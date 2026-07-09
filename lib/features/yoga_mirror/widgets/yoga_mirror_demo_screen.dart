import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../core/constants/app_assets.dart';
import '../controllers/yoga_mirror_controller.dart';
import '../services/pose_stream_processor.dart';
import 'camera_pose_view.dart';
import 'playback_controls.dart';
import 'pose_feedback_panel.dart';
import 'pose_score_card.dart';
import 'vrm_model_webview.dart';

class YogaMirrorDemoScreen extends StatefulWidget {
  const YogaMirrorDemoScreen({
    super.key,
    this.simulatorMode = false,
    this.poseProcessor,
  });

  final bool simulatorMode;
  final PoseStreamProcessor? poseProcessor;

  @override
  State<YogaMirrorDemoScreen> createState() => _YogaMirrorDemoScreenState();
}

class _YogaMirrorDemoScreenState extends State<YogaMirrorDemoScreen>
    with SingleTickerProviderStateMixin {
  late final YogaMirrorController _controller;
  Ticker? _ticker;
  Duration? _lastTick;
  bool _debugOverlayEnabled = false;

  @override
  void initState() {
    super.initState();
    _controller = YogaMirrorController(simulatorMode: widget.simulatorMode)
      ..addListener(_onControllerChanged);
    _controller.initialize();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onTick(Duration elapsed) {
    if (_lastTick == null) {
      _lastTick = elapsed;
      return;
    }

    final deltaMs = (elapsed - _lastTick!).inMilliseconds;
    _lastTick = elapsed;
    _controller.tick(deltaMs);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101018),
      body: SafeArea(
        child: OrientationBuilder(
          builder: (context, orientation) {
            final isLandscape = orientation == Orientation.landscape;
            return isLandscape ? _buildLandscape() : _buildPortrait();
          },
        ),
      ),
    );
  }

  Widget _buildPortrait() {
    return Column(
      children: [
        _buildHeader(),
        Expanded(child: _buildCameraStack()),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: PoseScoreCard(scoreLabel: _controller.scoreLabel),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: PoseFeedbackPanel(messages: _controller.feedback),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: PlaybackControls(
            isPlaying: _controller.isPlaying,
            progress: _controller.playbackProgress,
            onPlayPause: () => _controller.setPlaying(!_controller.isPlaying),
            onSeek: _controller.seekToProgress,
            onReset: _controller.resetPlayback,
          ),
        ),
      ],
    );
  }

  Widget _buildLandscape() {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Column(
            children: [
              _buildHeader(compact: true),
              Expanded(child: _buildCameraStack()),
            ],
          ),
        ),
        Expanded(
          flex: 2,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PoseScoreCard(scoreLabel: _controller.scoreLabel),
                const SizedBox(height: 12),
                Expanded(
                  child: SingleChildScrollView(
                    child: PoseFeedbackPanel(messages: _controller.feedback),
                  ),
                ),
                const SizedBox(height: 12),
                PlaybackControls(
                  isPlaying: _controller.isPlaying,
                  progress: _controller.playbackProgress,
                  onPlayPause: () =>
                      _controller.setPlaying(!_controller.isPlaying),
                  onSeek: _controller.seekToProgress,
                  onReset: _controller.resetPlayback,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader({bool compact = false}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(8, compact ? 4 : 8, 16, compact ? 4 : 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          ),
          IconButton(
            onPressed: () =>
                setState(() => _debugOverlayEnabled = !_debugOverlayEnabled),
            icon: Icon(
              Icons.bug_report,
              color: _debugOverlayEnabled
                  ? const Color(0xFFB388FF)
                  : Colors.white54,
            ),
            tooltip: 'Debug overlay',
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'YogaMirror',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 18 : 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  _controller.exerciseName,
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: compact ? 12 : 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraStack() {
    if (_controller.isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFFB388FF)),
            SizedBox(height: 12),
            Text(
              'Đang tải mẫu động tác...',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      );
    }

    if (_controller.loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _controller.loadError!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.redAccent),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              fit: StackFit.expand,
              children: [
                CameraPoseView(
                  controller: _controller,
                  poseProcessor: widget.poseProcessor,
                ),
                VrmModelWebView(
                  modelAssetPath: AppAssets.yogaAvatarVrm,
                  currentFrame: _controller.currentSampleFrame,
                  opacity: 0.65,
                  isPlaying: _controller.isPlaying,
                  debugOverlayEnabled: _debugOverlayEnabled,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
