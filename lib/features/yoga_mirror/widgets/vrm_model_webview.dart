import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../../../core/constants/app_assets.dart';
import '../models/pose_frame.dart';
import '../utils/pose_frame_serializer.dart';

enum _LoadStep {
  initializing,
  loadingAsset,
  sendingToRenderer,
  parsingVrm,
  ready,
  error,
}

class VrmModelWebView extends StatefulWidget {
  const VrmModelWebView({
    super.key,
    required this.modelAssetPath,
    required this.currentFrame,
    this.opacity = 0.65,
    this.isPlaying = false,
    this.debugOverlayEnabled = false,
  });

  final String modelAssetPath;
  final PoseFrame? currentFrame;
  final double opacity;
  final bool isPlaying;
  final bool debugOverlayEnabled;

  @override
  State<VrmModelWebView> createState() => _VrmModelWebViewState();
}

class _VrmModelWebViewState extends State<VrmModelWebView> {
  WebViewController? _controller;
  bool _webViewReady = false;
  bool _vrmLoaded = false;
  _LoadStep _loadStep = _LoadStep.initializing;
  String? _errorMessage;
  String? _errorDetail;
  int _vrmBytes = 0;
  PoseFrame? _pendingFrame;
  bool _isLoadingVrm = false;

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
    if (widget.debugOverlayEnabled != oldWidget.debugOverlayEnabled) {
      _setDebugOverlay(widget.debugOverlayEnabled);
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
              debugPrint(
                '[VrmModelWebView] Web resource error: ${error.description}',
              );
            },
          ),
        );

      if (controller.platform is WebKitWebViewController) {
        final webKit = controller.platform as WebKitWebViewController;
        await webKit.setAllowsBackForwardNavigationGestures(false);
        await webKit.setBackgroundColor(Colors.transparent);
      }

      final html = await _buildHtmlDocument();
      await controller.loadHtmlString(html);

      if (!mounted) return;
      setState(() => _controller = controller);
    } catch (error) {
      debugPrint('[VrmModelWebView] init error: $error');
      setState(() {
        _loadStep = _LoadStep.error;
        _errorMessage = 'Không tải được WebView renderer.';
        _errorDetail = error.toString();
      });
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
          debugPrint('[VrmModelWebView] JS renderer ready');
          if (!_webViewReady) {
            _webViewReady = true;
            _loadVrmModel();
          }
        case 'ready':
          debugPrint('[VrmModelWebView] VRM loaded successfully');
          if (mounted) {
            setState(() {
              _vrmLoaded = true;
              _loadStep = _LoadStep.ready;
              _errorMessage = null;
              _errorDetail = null;
            });
          }
          _setOpacity(widget.opacity);
          _setPlaybackState(widget.isPlaying);
          _setRetargetEnabled(true);
          _setRetargetParts(const {'torso': true, 'arms': true, 'legs': true});
          if (widget.debugOverlayEnabled) _setDebugOverlay(true);
          _flushPendingFrame();
        case 'error':
          final msg = data['message'] as String? ?? 'Không tải được VRM model.';
          debugPrint('[VrmModelWebView] JS error: $msg');
          if (mounted) {
            setState(() {
              _loadStep = _LoadStep.error;
              _errorMessage = msg;
              _errorDetail = data['detail'] as String?;
            });
          }
        case 'loading_step':
          debugPrint('[VrmModelWebView] JS step: ${data['step']}');
      }
    } catch (error) {
      debugPrint('[VrmModelWebView] bridge parse error: $error');
    }
  }

  Future<void> _onPageFinished() async {
    if (!_webViewReady) {
      _webViewReady = true;
    }
    if (!_isLoadingVrm && !_vrmLoaded && mounted) {
      await Future.delayed(const Duration(milliseconds: 700));
      if (mounted) {
        await _loadVrmModel();
      }
    }
  }

  Future<void> _loadVrmModel() async {
    final controller = _controller;
    if (controller == null || _isLoadingVrm || _vrmLoaded) return;

    _isLoadingVrm = true;
    setState(() {
      _loadStep = _LoadStep.loadingAsset;
      _errorMessage = null;
      _errorDetail = null;
    });

    try {
      debugPrint(
        '[VrmModelWebView] Loading VRM asset: ${widget.modelAssetPath}',
      );
      final data = await rootBundle.load(widget.modelAssetPath);
      final bytes = data.buffer.asUint8List();
      _vrmBytes = bytes.length;
      debugPrint('[VrmModelWebView] VRM bytes: $_vrmBytes');

      if (_vrmBytes == 0) {
        throw Exception('File VRM rỗng hoặc không đọc được.');
      }
      if (!mounted) return;

      setState(() => _loadStep = _LoadStep.sendingToRenderer);
      debugPrint('[VrmModelWebView] Sending VRM to renderer...');
      final base64 = base64Encode(bytes);

      for (var attempt = 0; attempt < 5; attempt++) {
        try {
          await controller.runJavaScript(
            "typeof window.beginVrmBase64Load === 'function' ? window.beginVrmBase64Load() : (()=>{ throw new Error('renderer_not_ready'); })()",
          );
          break;
        } catch (error) {
          if (attempt == 4) rethrow;
          debugPrint(
            '[VrmModelWebView] Renderer not ready yet, retrying... ($attempt)',
          );
          await Future.delayed(const Duration(milliseconds: 400));
        }
      }

      const chunkSize = AppAssets.vrmBase64ChunkSize;
      for (var i = 0; i < base64.length; i += chunkSize) {
        final end = (i + chunkSize < base64.length)
            ? i + chunkSize
            : base64.length;
        final chunk = base64.substring(i, end);
        await controller.runJavaScript(
          'window.appendVrmBase64Chunk(${jsonEncode(chunk)})',
        );
      }
      await controller.runJavaScript('window.finishVrmBase64Load()');

      if (mounted) setState(() => _loadStep = _LoadStep.parsingVrm);
    } catch (error) {
      debugPrint('[VrmModelWebView] VRM load error: $error');
      if (mounted) {
        setState(() {
          _loadStep = _LoadStep.error;
          _errorMessage = 'Không tải được VRM model.';
          _errorDetail = error.toString();
        });
      }
    } finally {
      _isLoadingVrm = false;
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

  Future<void> _setRetargetEnabled(bool enabled) async {
    if (_controller == null || !_vrmLoaded) return;
    try {
      await _controller!.runJavaScript(
        'window.setRetargetEnabled(${enabled ? 'true' : 'false'})',
      );
    } catch (error) {
      debugPrint('[VrmModelWebView] setRetargetEnabled error: $error');
    }
  }

  Future<void> _setRetargetParts(Map<String, dynamic> parts) async {
    if (_controller == null || !_vrmLoaded) return;
    try {
      final payload = jsonEncode(parts);
      await _controller!.runJavaScript('window.setRetargetParts($payload)');
    } catch (error) {
      debugPrint('[VrmModelWebView] setRetargetParts error: $error');
    }
  }

  Future<void> _setDebugOverlay(bool enabled) async {
    if (_controller == null || !_vrmLoaded) return;
    try {
      await _controller!.runJavaScript(
        'window.setDebugOverlay(${enabled ? 'true' : 'false'})',
      );
    } catch (error) {
      debugPrint('[VrmModelWebView] setDebugOverlay error: $error');
    }
  }

  String _loadStepText() {
    switch (_loadStep) {
      case _LoadStep.initializing:
        return 'Đang khởi tạo WebView...';
      case _LoadStep.loadingAsset:
        return 'Đang đọc VRM asset...';
      case _LoadStep.sendingToRenderer:
        final mb = (_vrmBytes / (1024 * 1024)).toStringAsFixed(1);
        return 'Đang gửi VRM ($mb MB) sang renderer...';
      case _LoadStep.parsingVrm:
        return 'Đang parse VRM...';
      case _LoadStep.ready:
      case _LoadStep.error:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Container(
        alignment: Alignment.center,
        color: Colors.black.withValues(alpha: 0.15),
        padding: const EdgeInsets.all(16),
        child: const Text(
          '3D VRM renderer chạy tốt nhất trên iOS/Android.\nWeb hiện chỉ dùng để test layout.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
      );
    }

    if (_loadStep == _LoadStep.error) {
      return _errorWidget();
    }

    if (_loadStep == _LoadStep.ready && _controller != null) {
      return Opacity(
        opacity: widget.opacity,
        child: IgnorePointer(child: WebViewWidget(controller: _controller!)),
      );
    }

    if (_controller != null && _loadStep != _LoadStep.initializing) {
      return _loadingWidget();
    }

    return _loadingWidget();
  }

  Widget _loadingWidget() {
    final stepText = _loadStepText();
    return Container(
      alignment: Alignment.center,
      color: Colors.black.withValues(alpha: 0.15),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: Color(0xFFB388FF),
            ),
          ),
          if (stepText.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              stepText,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }

  Widget _errorWidget() {
    final detail = _errorDetail;
    return Container(
      alignment: Alignment.center,
      color: Colors.black.withValues(alpha: 0.15),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 32),
          const SizedBox(height: 8),
          Text(
            _errorMessage ?? 'Không tải được VRM model.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          if (detail != null && detail.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white38, fontSize: 11),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}
