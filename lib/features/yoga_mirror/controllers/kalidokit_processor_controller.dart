import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../../../core/constants/app_assets.dart';
import '../models/pose_frame.dart';
import '../utils/pose_frame_serializer.dart';

/// RAW Kalidokit poseRig — góc Euler (radians) cho từng bone.
///
/// Keys (convention Kalidokit, **không** swap ở đây):
///   RightUpperArm / LeftUpperArm / RightLowerArm / LeftLowerArm
///   RightHand / LeftHand
///   RightUpperLeg / LeftUpperLeg / RightLowerLeg / LeftLowerLeg
///   Hips: { position, rotation, worldPosition }
///   Spine: {x,y,z}
///
/// Dart **không** chứa vector/quaternion. Bạn tự gán poseRig → xương VRM.
class KalidokitRawResult {
  final int timestampMs;
  final Map<String, dynamic> poseRig;

  /// `mediapipe_world` | `screen_pseudo_world`
  final String coordMode;
  final List<String> coordNotes;

  KalidokitRawResult({
    required this.timestampMs,
    required this.poseRig,
    this.coordMode = '',
    this.coordNotes = const [],
  });

  factory KalidokitRawResult.fromJson(Map<String, dynamic> json) {
    final notes = json['coordNotes'];
    return KalidokitRawResult(
      timestampMs: (json['timestampMs'] as num?)?.toInt() ?? 0,
      poseRig: (json['poseRig'] as Map<String, dynamic>?) ?? {},
      coordMode: json['coordMode'] as String? ?? '',
      coordNotes: notes is List
          ? notes.map((e) => e.toString()).toList()
          : const [],
    );
  }

  /// Helper: lấy Euler {x,y,z} của 1 bone key (null nếu thiếu).
  Map<String, double>? eulerOf(String key) {
    final raw = poseRig[key];
    if (raw is! Map) return null;
    return {
      'x': (raw['x'] as num?)?.toDouble() ?? 0,
      'y': (raw['y'] as num?)?.toDouble() ?? 0,
      'z': (raw['z'] as num?)?.toDouble() ?? 0,
    };
  }
}

/// Hidden WebView chạy Kalidokit solver (JS-only kinematics).
///
/// ## Dart chỉ làm 3 việc:
/// 1. Load `kalidokit_solver.html` + inject `kalidokit.umd.js` (offline)
/// 2. Gửi frame JSON: `processPose(...)`
/// 3. Nhận RAW poseRig qua JavaScriptChannel `PoseChannel`
///
/// ## Không làm:
/// - Tính vector / quaternion / world→local
/// - Map tên xương VRM / swap L-R
class KalidokitProcessorController {
  KalidokitProcessorController({this.onReady, this.onPoseSolved, this.onError});

  final VoidCallback? onReady;
  final void Function(KalidokitRawResult result)? onPoseSolved;
  final void Function(String error)? onError;

  WebViewController? _controller;
  bool _isReady = false;
  bool _isProcessing = false;
  Timer? _timer;
  int _frameIndex = 0;

  bool get isReady => _isReady;
  bool get isProcessing => _isProcessing;

  // ─── Bước 1: Load solver HTML (offline) ────────────────────────────

  Future<void> initialize() async {
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
        ..setBackgroundColor(const Color(0x00000000))
        ..addJavaScriptChannel('PoseChannel', onMessageReceived: _onMessage);

      if (controller.platform is WebKitWebViewController) {
        final webKit = controller.platform as WebKitWebViewController;
        await webKit.setAllowsBackForwardNavigationGestures(false);
        await webKit.setBackgroundColor(const Color(0x00000000));
        await webKit.setInspectable(true);
      }

      final html = await _buildSolverHtml();
      await controller.loadHtmlString(html);
      _controller = controller;
    } catch (e) {
      onError?.call('KalidokitProcessor init: $e');
    }
  }

  /// Inject kalidokit UMD vào placeholder — giống pattern VRM renderer offline.
  Future<String> _buildSolverHtml() async {
    final html = await rootBundle.loadString(AppAssets.kalidokitSolverHtml);
    final umd = await rootBundle.loadString(AppAssets.kalidokitUmdJs);
    return html.replaceFirst(
      '<!-- KALIDOKIT_SCRIPT -->',
      '<script>\n$umd\n</script>',
    );
  }

  // ─── Bước 3: Nhận kết quả ─────────────────────────────────────────

  void _onMessage(JavaScriptMessage msg) {
    try {
      final data = jsonDecode(msg.message) as Map<String, dynamic>;
      switch (data['type'] as String?) {
        case 'ready':
          _isReady = true;
          debugPrint(
            '[KalidokitProcessor] ready: ${data['message']} '
            'convention=${data['convention']}',
          );
          onReady?.call();
        case 'pose_solved':
          final result = KalidokitRawResult.fromJson(data);
          if (result.coordMode == 'screen_pseudo_world') {
            // Log 1 lần kiểu — tránh spam; dùng debugPrint thưa.
            debugPrint(
              '[KalidokitProcessor] frame ${result.timestampMs}ms '
              'coordMode=screen_pseudo_world (no wx/wy/wz — depth flat)',
            );
          }
          onPoseSolved?.call(result);
        case 'error':
          onError?.call(data['message'] as String? ?? 'Unknown');
      }
    } catch (e) {
      debugPrint('[KalidokitProcessor] parse error: $e');
    }
  }

  // ─── Bước 2: Gửi frame ────────────────────────────────────────────

  Future<void> sendFrame(PoseFrame frame) async {
    if (!_isReady || _controller == null) return;
    try {
      final json = PoseFrameSerializer.toJsonString(frame);
      await _controller!.runJavaScript('processPose($json)');
    } catch (e) {
      debugPrint('[KalidokitProcessor] sendFrame error: $e');
    }
  }

  /// Gửi raw JSON string (khi đã có string frame sẵn).
  Future<void> sendFrameJson(String frameJson) async {
    if (!_isReady || _controller == null) return;
    try {
      await _controller!.runJavaScript('processPose($frameJson)');
    } catch (e) {
      debugPrint('[KalidokitProcessor] sendFrameJson error: $e');
    }
  }

  /// Play list frames với timer
  void playFrames(
    List<PoseFrame> frames, {
    double speed = 1.0,
    bool loop = false,
  }) {
    if (!_isReady || frames.isEmpty) return;
    stop();
    _frameIndex = 0;
    _isProcessing = true;

    final avgMs = _avgInterval(frames);
    _timer = Timer.periodic(
      Duration(milliseconds: (avgMs / speed).round().clamp(16, 500)),
      (_) {
        if (_frameIndex >= frames.length) {
          if (loop) {
            _frameIndex = 0;
          } else {
            stop();
            return;
          }
        }
        sendFrame(frames[_frameIndex]);
        _frameIndex++;
      },
    );
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _isProcessing = false;
  }

  int _avgInterval(List<PoseFrame> frames) {
    if (frames.length < 2) return 100;
    var total = 0;
    for (var i = 1; i < frames.length; i++) {
      total += frames[i].timestampMs - frames[i - 1].timestampMs;
    }
    return (total / (frames.length - 1)).round().clamp(16, 500);
  }

  /// Widget 1×1 (invisible) — phải gắn vào tree để WebView chạy.
  WebViewWidget? get widget {
    if (_controller == null) return null;
    return WebViewWidget(controller: _controller!);
  }

  void dispose() {
    stop();
    _isReady = false;
  }
}
