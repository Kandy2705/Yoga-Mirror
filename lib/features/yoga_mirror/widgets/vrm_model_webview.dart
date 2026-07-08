import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../../../core/constants/app_assets.dart';
import '../models/pose_frame.dart';
import '../utils/pose_frame_serializer.dart';

/// WebView overlay render VRM 3D guide bằng Three.js/three-vrm.
/// JSON PoseFrame là nguồn motion duy nhất — không dùng animation có sẵn.
class VrmModelWebView extends StatefulWidget {
  const VrmModelWebView({
    super.key,
    required this.modelAssetPath,
    required this.currentFrame,
    this.opacity = 0.55,
    this.isPlaying = false,
  });

  final String modelAssetPath;
  final PoseFrame? currentFrame;
  final double opacity;
  final bool isPlaying;

  @override
  State<VrmModelWebView> createState() => _VrmModelWebViewState();
}

class _VrmModelWebViewState extends State<VrmModelWebView> {
  WebViewController? _controller;
  bool _webViewReady = false;
  bool _vrmLoaded = false;
  bool _isLoadingVrm = false;
  bool _vrmLoadStarted = false;
  String? _errorMessage;
  PoseFrame? _pendingFrame;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _initWebView();
    }
  }

  @override
  void didUpdateWidget(covariant VrmModelWebView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.currentFrame != oldWidget.currentFrame) {
      _applyPoseFrame(widget.currentFrame);
    }
    if (widget.opacity != oldWidget.opacity) {
      _setOpacity(widget.opacity);
    }
    if (widget.isPlaying != oldWidget.isPlaying) {
      _setPlaybackState(widget.isPlaying);
    }
  }

  Future<void> _initWebView() async {
    try {
      late final PlatformWebViewControllerCreationParams params;
      if (WebViewPlatform.instance is WebKitWebViewPlatform) {
        params = WebKitWebViewControllerCreationParams(
          allowsInlineMediaPlayback: true,
          mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
        );
      } else {
        params = const PlatformWebViewControllerCreationParams();
      }

      final controller = WebViewController.fromPlatformCreationParams(params)
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.transparent)
        ..addJavaScriptChannel(
          'YogaMirrorBridge',
          onMessageReceived: _onJsMessage,
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageFinished: (_) => _onPageFinished(),
            onWebResourceError: (error) {
              debugPrint('[VrmModelWebView] Web resource error: ${error.description}');
            },
          ),
        );

      if (controller.platform is WebKitWebViewController) {
        final webKit = controller.platform as WebKitWebViewController;
        await webKit.setAllowsBackForwardNavigationGestures(false);
        // Nền trong suốt để chồng lên camera.
        await webKit.setBackgroundColor(Colors.transparent);
      }

      final html = await _buildHtmlDocument();
      await controller.loadHtmlString(html);

      if (!mounted) return;
      setState(() => _controller = controller);
    } catch (error) {
      debugPrint('[VrmModelWebView] init error: $error');
      setState(() => _errorMessage = 'Không tải được VRM model.');
    }
  }

  Future<String> _buildHtmlDocument() async {
    final html = await rootBundle.loadString(AppAssets.vrmRendererHtml);
    final js = await rootBundle.loadString(AppAssets.vrmRendererJs);
    return html.replaceFirst(
      '<!-- YOGA_VRM_SCRIPT -->',
      '<script type="module">\n$js\n</script>',
    );
  }

  void _onJsMessage(JavaScriptMessage message) {
    try {
      final data = jsonDecode(message.message) as Map<String, dynamic>;
      final type = data['type'] as String?;

      switch (type) {
        case 'webview_ready':
          if (!_webViewReady) {
            _webViewReady = true;
            _loadVrmModel();
          }
        case 'ready':
          if (mounted) {
            setState(() {
              _vrmLoaded = true;
              _isLoadingVrm = false;
              _errorMessage = null;
            });
          }
          _setOpacity(widget.opacity);
          _setPlaybackState(widget.isPlaying);
          _flushPendingFrame();
        case 'error':
          if (mounted) {
            setState(() {
              _errorMessage = data['message'] as String? ??
                  'Không tải được VRM model.';
              _isLoadingVrm = false;
            });
          }
      }
    } catch (error) {
      debugPrint('[VrmModelWebView] bridge parse error: $error');
    }
  }

  Future<void> _onPageFinished() async {
    if (!_webViewReady) {
      _webViewReady = true;
      await _loadVrmModel();
    }
  }

  Future<void> _loadVrmModel() async {
    final controller = _controller;
    if (controller == null || _vrmLoadStarted || _vrmLoaded) return;
    _vrmLoadStarted = true;

    setState(() {
      _isLoadingVrm = true;
      _errorMessage = null;
    });

    try {
      final data = await rootBundle.load(widget.modelAssetPath);
      final bytes = data.buffer.asUint8List();
      final base64 = base64Encode(bytes);

      // VRM ~20MB — gửi theo chunk để tránh giới hạn JS bridge.
      await controller.runJavaScript('window.beginVrmBase64Load()');

      const chunkSize = AppAssets.vrmBase64ChunkSize;
      for (var i = 0; i < base64.length; i += chunkSize) {
        final end = (i + chunkSize < base64.length) ? i + chunkSize : base64.length;
        final chunk = base64.substring(i, end);
        await controller.runJavaScript(
          'window.appendVrmBase64Chunk(${jsonEncode(chunk)})',
        );
      }

      await controller.runJavaScript('window.finishVrmBase64Load()');
    } catch (error) {
      debugPrint('[VrmModelWebView] VRM load error: $error');
      if (mounted) {
        setState(() {
          _errorMessage = 'Không tải được VRM model.';
          _isLoadingVrm = false;
        });
      }
    }
  }

  Future<void> _applyPoseFrame(PoseFrame? frame) async {
    if (frame == null) return;

    if (!_webViewReady || !_vrmLoaded || _controller == null) {
      _pendingFrame = frame;
      return;
    }

    try {
      final json = PoseFrameSerializer.toJsonString(frame);
      await _controller!.runJavaScript('window.applyPoseFrame($json)');
    } catch (error) {
      debugPrint('[VrmModelWebView] applyPoseFrame error: $error');
    }
  }

  void _flushPendingFrame() {
    final pending = _pendingFrame;
    if (pending != null) {
      _pendingFrame = null;
      _applyPoseFrame(pending);
    } else if (widget.currentFrame != null) {
      _applyPoseFrame(widget.currentFrame);
    }
  }

  Future<void> _setOpacity(double opacity) async {
    if (_controller == null || !_vrmLoaded) return;
    try {
      await _controller!.runJavaScript('window.setGuideOpacity($opacity)');
    } catch (error) {
      debugPrint('[VrmModelWebView] setOpacity error: $error');
    }
  }

  Future<void> _setPlaybackState(bool isPlaying) async {
    if (_controller == null || !_vrmLoaded) return;
    try {
      await _controller!.runJavaScript(
        'window.setPlaybackState(${isPlaying ? 'true' : 'false'})',
      );
    } catch (error) {
      debugPrint('[VrmModelWebView] setPlaybackState error: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return _overlayMessage(
        '3D VRM renderer chạy tốt nhất trên iOS/Android.\nWeb hiện chỉ dùng để test layout.',
      );
    }

    if (_errorMessage != null) {
      return _overlayMessage(_errorMessage!);
    }

    if (_controller == null || _isLoadingVrm) {
      return _overlayMessage('Đang tải model 3D...', showSpinner: true);
    }

    return IgnorePointer(
      child: WebViewWidget(controller: _controller!),
    );
  }

  Widget _overlayMessage(String message, {bool showSpinner = false}) {
    return Container(
      alignment: Alignment.center,
      color: Colors.black.withValues(alpha: 0.15),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showSpinner) ...[
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Color(0xFFB388FF),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}