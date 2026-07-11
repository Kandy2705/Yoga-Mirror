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

/// Top-level for [compute] — base64-encode VRM bytes off the UI isolate.
String _encodeBase64(Uint8List bytes) => base64Encode(bytes);

class VrmModelWebView extends StatefulWidget {
  const VrmModelWebView({
    super.key,
    required this.modelAssetPath,
    required this.currentFrame,
    this.opacity = 0.65,
    this.isPlaying = false,
    this.debugOverlayEnabled = false,
    this.mappingToolEnabled = false,
    this.idLabelMode = 'off',
    this.onWebViewCreated,
  });

  final String modelAssetPath;
  final PoseFrame? currentFrame;
  final double opacity;
  final bool isPlaying;
  final bool debugOverlayEnabled;
  /// Dev tool: show JS panel to pair VRM bones ↔ JSON landmarks by name.
  final bool mappingToolEnabled;
  /// On-screen id labels: `off` | `vrm` | `json` | `all`.
  final String idLabelMode;
  final void Function(WebViewController controller)? onWebViewCreated;

  @override
  State<VrmModelWebView> createState() => VrmModelWebViewState();
}

/// Public so parent can call scale/fit APIs via [GlobalKey].
class VrmModelWebViewState extends State<VrmModelWebView> {
  WebViewController? _controller;
  bool _webViewReady = false;
  bool _vrmLoaded = false;
  _LoadStep _loadStep = _LoadStep.initializing;
  String? _errorMessage;
  String? _errorDetail;
  int _vrmBytes = 0;
  PoseFrame? _pendingFrame;
  bool _isLoadingVrm = false;
  /// Preloaded while WebView boots — avoids serial read after page ready.
  Future<String>? _vrmBase64Future;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _vrmBase64Future = _preloadVrmBase64();
      _initWebView();
    }
  }

  Future<String> _preloadVrmBase64() async {
    final data = await rootBundle.load(widget.modelAssetPath);
    final bytes = data.buffer.asUint8List();
    _vrmBytes = bytes.length;
    if (_vrmBytes == 0) {
      throw Exception('File VRM rỗng hoặc không đọc được.');
    }
    if (mounted) {
      setState(() => _loadStep = _LoadStep.loadingAsset);
    }
    debugPrint('[VrmModelWebView] Preloaded VRM bytes: $_vrmBytes');
    // base64Encode is CPU-heavy on ~10MB — run off UI isolate.
    final b64 = await compute(_encodeBase64, bytes);
    return b64;
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
    if (widget.mappingToolEnabled != oldWidget.mappingToolEnabled) {
      _setMappingToolEnabled(widget.mappingToolEnabled);
    }
    if (widget.idLabelMode != oldWidget.idLabelMode) {
      _setIdLabelMode(widget.idLabelMode);
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
        // iOS 16.4+: without this, Safari → Phát triển → Kandy shows
        // "Không có ứng dụng có thể kiểm tra web" (no YogaMirror entry).
        await webKit.setInspectable(true);
        debugPrint('[VrmModelWebView] setInspectable(true) OK');
      }

      final html = await _buildHtmlDocument();
      await controller.loadHtmlString(html);

      // expose controller to parent if requested
      widget.onWebViewCreated?.call(controller);

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
    // Offline IIFE bundle (no type=module, no CDN importmap).
    final js = await rootBundle.loadString(AppAssets.vrmRendererJs);
    return html.replaceFirst(
      '<!-- YOGA_VRM_SCRIPT -->',
      '<script>\n$js\n</script>',
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
          // Yaw/pitch live in JS (guideModelYaw / guideModelPitch) — no UI slider.
          if (widget.debugOverlayEnabled) _setDebugOverlay(true);
          if (widget.mappingToolEnabled) _setMappingToolEnabled(true);
          if (widget.idLabelMode != 'off') _setIdLabelMode(widget.idLabelMode);
          _flushPendingFrame();
        case 'error':
          final msg = data['message'] as String? ?? 'Không tải được VRM model.';
          final detail = data['detail'] as String?;
          debugPrint('[VrmModelWebView] JS error: $msg');
          if (detail != null && detail.isNotEmpty) {
            debugPrint('[VrmModelWebView] JS error detail: $detail');
          }
          if (mounted) {
            setState(() {
              _loadStep = _LoadStep.error;
              _errorMessage = msg;
              _errorDetail = detail;
            });
          }
        case 'loading_step':
          debugPrint('[VrmModelWebView] JS step: ${data['step']}');
        case 'bone_mapping_result':
          final mapping = data['mapping'] as Map<String, dynamic>? ?? {};
          final mappingWithIds =
              data['mappingWithIds'] as Map<String, dynamic>? ?? {};
          debugPrint('[BoneMapping] Kết quả mapping thủ công (names):');
          debugPrint(const JsonEncoder.withIndent('  ').convert(mapping));
          if (mappingWithIds.isNotEmpty) {
            debugPrint('[BoneMapping] Kết quả mapping (with ids):');
            debugPrint(
              const JsonEncoder.withIndent('  ').convert(mappingWithIds),
            );
          }
      }
    } catch (error) {
      debugPrint('[VrmModelWebView] bridge parse error: $error');
    }
  }

  Future<void> _onPageFinished() async {
    if (!_webViewReady) {
      _webViewReady = true;
    }
    // No artificial delay — start transfer as soon as page/JS is up.
    if (!_isLoadingVrm && !_vrmLoaded && mounted) {
      await _loadVrmModel();
    }
  }

  Future<void> _loadVrmModel() async {
    final controller = _controller;
    if (controller == null || _isLoadingVrm || _vrmLoaded) return;

    _isLoadingVrm = true;
    if (mounted) {
      setState(() {
        _errorMessage = null;
        _errorDetail = null;
      });
    }

    try {
      debugPrint('[VrmModelWebView] Waiting preloaded VRM base64...');
      final base64 =
          await (_vrmBase64Future ??= _preloadVrmBase64());
      if (!mounted) return;

      setState(() => _loadStep = _LoadStep.sendingToRenderer);
      debugPrint(
        '[VrmModelWebView] Sending VRM to renderer ($_vrmBytes bytes)...',
      );

      for (var attempt = 0; attempt < 8; attempt++) {
        try {
          await controller.runJavaScript(
            "typeof window.beginVrmBase64Load === 'function' ? window.beginVrmBase64Load() : (()=>{ throw new Error('renderer_not_ready'); })()",
          );
          break;
        } catch (error) {
          if (attempt == 7) rethrow;
          debugPrint(
            '[VrmModelWebView] Renderer not ready yet, retrying... ($attempt)',
          );
          await Future.delayed(const Duration(milliseconds: 120));
        }
      }

      // Larger chunks = fewer JS bridge round-trips (main transfer cost).
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

  Future<void> _setMappingToolEnabled(bool enabled) async {
    if (_controller == null || !_vrmLoaded) return;
    try {
      await _controller!.runJavaScript(
        'window.setMappingToolEnabled(${enabled ? 'true' : 'false'})',
      );
    } catch (error) {
      debugPrint('[VrmModelWebView] setMappingToolEnabled error: $error');
    }
  }

  Future<void> _setIdLabelMode(String mode) async {
    if (_controller == null || !_vrmLoaded) return;
    try {
      await _controller!.runJavaScript(
        'window.setIdLabelMode(${jsonEncode(mode)})',
      );
    } catch (error) {
      debugPrint('[VrmModelWebView] setIdLabelMode error: $error');
    }
  }

  /// Manual scale/offset (mentor 2.1). Always `force: true` so user can tweak
  /// even after a session-start auto scale.
  Future<void> setGuideTransform({
    double? scale,
    double? scaleX,
    double? scaleY,
    double? yOffset,
    double? zOffset,
    double? yaw,
    double? pitch,
    bool force = true,
  }) async {
    if (_controller == null || !_vrmLoaded) return;
    final config = <String, dynamic>{'force': force};
    if (scale != null) config['scale'] = scale;
    if (scaleX != null) config['scaleX'] = scaleX;
    if (scaleY != null) config['scaleY'] = scaleY;
    if (yOffset != null) config['yOffset'] = yOffset;
    if (zOffset != null) config['zOffset'] = zOffset;
    if (yaw != null) config['yaw'] = yaw;
    if (pitch != null) config['pitch'] = pitch;
    try {
      await _controller!.runJavaScript(
        'window.setGuideTransform(${jsonEncode(config)})',
      );
    } catch (error) {
      debugPrint('[VrmModelWebView] setGuideTransform error: $error');
    }
  }

  /// Mentor 2.2 — apply height/width once at session start, then lock.
  Future<void> applySessionBodyScale({
    double? scale,
    double? heightScale,
    double? widthScale,
    double? yOffset,
    double? zOffset,
    bool lock = true,
    bool force = false,
  }) async {
    if (_controller == null || !_vrmLoaded) return;
    final params = <String, dynamic>{
      'lock': lock,
      'force': force,
    };
    if (scale != null) params['scale'] = scale;
    if (heightScale != null) params['heightScale'] = heightScale;
    if (widthScale != null) params['widthScale'] = widthScale;
    if (yOffset != null) params['yOffset'] = yOffset;
    if (zOffset != null) params['zOffset'] = zOffset;
    try {
      await _controller!.runJavaScript(
        'window.applySessionBodyScale(${jsonEncode(params)})',
      );
    } catch (error) {
      debugPrint('[VrmModelWebView] applySessionBodyScale error: $error');
    }
  }

  /// Fit avatar to a user pose frame (landmarks) once; locks by default.
  Future<void> fitGuideToUserFromFrame(
    PoseFrame frame, {
    bool lock = true,
    bool force = false,
  }) async {
    if (_controller == null || !_vrmLoaded) return;
    try {
      final json = PoseFrameSerializer.toJsonString(frame);
      await _controller!.runJavaScript(
        'window.fitGuideToUserFromFrame($json, ${jsonEncode({
              'lock': lock,
              'force': force,
            })})',
      );
    } catch (error) {
      debugPrint('[VrmModelWebView] fitGuideToUserFromFrame error: $error');
    }
  }

  Future<void> resetSessionScale() async {
    if (_controller == null || !_vrmLoaded) return;
    try {
      await _controller!.runJavaScript('window.resetSessionScale()');
    } catch (error) {
      debugPrint('[VrmModelWebView] resetSessionScale error: $error');
    }
  }

  Future<void> setSessionScaleLocked(bool locked) async {
    if (_controller == null || !_vrmLoaded) return;
    try {
      await _controller!.runJavaScript(
        'window.setSessionScaleLocked(${locked ? 'true' : 'false'})',
      );
    } catch (error) {
      debugPrint('[VrmModelWebView] setSessionScaleLocked error: $error');
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
      // Allow pointer only when mapping tool is open so the panel receives taps.
      // Otherwise keep IgnorePointer so camera/pose gestures pass through.
      return Opacity(
        opacity: widget.opacity,
        child: IgnorePointer(
          ignoring: !widget.mappingToolEnabled,
          child: WebViewWidget(controller: _controller!),
        ),
      );
    }

    if (_controller != null && _loadStep != _LoadStep.initializing) {
      return _loadingWidget();
    }

    return _loadingWidget();
  }

  Widget _loadingWidget() {
    final stepText = _loadStepText();
    // Compact chip — camera stays visible underneath (feels faster).
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Material(
          color: const Color(0xCC1A1A24),
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFFB388FF),
                  ),
                ),
                if (stepText.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      stepText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
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
