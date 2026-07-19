import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../controllers/yoga_mirror_controller.dart';
import '../mannequin/mannequin_visual_spec.dart';
import '../services/pose_stream_processor.dart';
import 'camera_pose_view.dart';
import 'mannequin_guide_overlay.dart';
import 'playback_controls.dart';

/// Demo screen — temporary main guide = mannequin (Rive or spec painter).
/// VRM WebView path is kept in repo but not mounted here on this branch.
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

  bool _scalePanelOpen = false;
  double _manualScale = 1.0;
  double _manualYOffset = 0.0;
  double _manualOpacity = MannequinVisualSpec.defaultOpacity;

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
    if (mounted) setState(() {});
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
            onPressed: () => setState(() => _scalePanelOpen = !_scalePanelOpen),
            icon: Icon(
              Icons.open_with,
              color: _scalePanelOpen
                  ? const Color(0xFFB388FF)
                  : Colors.white54,
            ),
            tooltip: 'Căn chỉnh mannequin',
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
                  'Mannequin guide · ${_controller.exerciseName}',
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CameraPoseView(
              controller: _controller,
              poseProcessor: widget.poseProcessor,
            ),
            MannequinGuideOverlay(
              frame: _controller.currentSampleFrame,
              opacity: _manualOpacity,
              scale: _manualScale,
              yOffset: _manualYOffset,
              isPlaying: _controller.isPlaying,
            ),
            if (_controller.isLoading)
              const Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: _LoadChip(label: 'Đang tải mẫu động tác...'),
                ),
              )
            else if (_controller.isBufferingChunks)
              Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _LoadChip(
                    label:
                        'Đang nạp thêm pose ${_controller.loadedChunkCount}/${_controller.totalChunkCount}…',
                  ),
                ),
              ),
            if (_scalePanelOpen) _buildScalePanel(),
          ],
        ),
      ),
    );
  }

  Widget _buildScalePanel() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Material(
        color: const Color(0xE61A1A24),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Căn chỉnh mannequin',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _manualScale = 1.0;
                        _manualYOffset = 0.0;
                        _manualOpacity = MannequinVisualSpec.defaultOpacity;
                      });
                    },
                    child: const Text('Reset'),
                  ),
                  IconButton(
                    onPressed: () => setState(() => _scalePanelOpen = false),
                    icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                  ),
                ],
              ),
              _scaleSlider(
                label: 'Scale',
                value: _manualScale,
                min: 0.4,
                max: 1.8,
                onChanged: (v) => setState(() => _manualScale = v),
              ),
              _scaleSlider(
                label: 'Lên / xuống',
                value: _manualYOffset,
                min: -120,
                max: 120,
                onChanged: (v) => setState(() => _manualYOffset = v),
              ),
              _scaleSlider(
                label: 'Độ mờ',
                value: _manualOpacity,
                min: 0.2,
                max: 1.0,
                onChanged: (v) => setState(() => _manualOpacity = v),
              ),
              Text(
                'Guide: mannequin vector 1 màu, từng bộ phận bind JSON landmarks '
                '(góc/vị trí khớp). Không vẽ skeleton/debug chấm.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _scaleSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            activeColor: const Color(0xFFB388FF),
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            value.toStringAsFixed(value.abs() >= 10 ? 0 : 2),
            style: const TextStyle(color: Colors.white54, fontSize: 11),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}

class _LoadChip extends StatelessWidget {
  const _LoadChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xCC1A1A24),
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFFB388FF),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
