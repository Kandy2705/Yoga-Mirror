import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../core/constants/app_assets.dart';
import '../controllers/yoga_mirror_controller.dart';
import '../services/pose_stream_processor.dart';
import 'camera_pose_view.dart';
import 'playback_controls.dart';
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
  final GlobalKey<VrmModelWebViewState> _vrmKey =
      GlobalKey<VrmModelWebViewState>();
  Ticker? _ticker;
  Duration? _lastTick;
  bool _debugOverlayEnabled = false;
  bool _mappingToolEnabled = false;
  /// Manual guide scale panel (mentor option 2.1).
  bool _scalePanelOpen = false;
  double _manualScale = 0.7;
  double _manualScaleY = 1.0;
  double _manualScaleX = 1.0;
  double _manualYOffset = 1.0;
  /// 0=off, 1=vrm (modal bones), 2=json, 3=all
  int _idLabelModeIndex = 0;
  static const _idLabelModes = ['off', 'vrm', 'json', 'all'];

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
          IconButton(
            onPressed: () =>
                setState(() => _mappingToolEnabled = !_mappingToolEnabled),
            icon: Icon(
              Icons.account_tree_outlined,
              color: _mappingToolEnabled
                  ? const Color(0xFFB388FF)
                  : Colors.white54,
            ),
            tooltip: 'Bone mapping tool',
          ),
          IconButton(
            onPressed: () => setState(() {
              _idLabelModeIndex =
                  (_idLabelModeIndex + 1) % _idLabelModes.length;
            }),
            icon: Icon(
              Icons.tag,
              color: switch (_idLabelModeIndex) {
                1 => const Color(0xFFB388FF), // VRM / modal
                2 => const Color(0xFF7FDBFF), // JSON
                3 => const Color(0xFFFFD54F), // all
                _ => Colors.white54,
              },
            ),
            tooltip: switch (_idLabelModeIndex) {
              1 => 'ID labels: VRM (tap → JSON)',
              2 => 'ID labels: JSON (tap → all)',
              3 => 'ID labels: all (tap → off)',
              _ => 'ID labels: off (tap → VRM)',
            },
          ),
          IconButton(
            onPressed: () => setState(() => _scalePanelOpen = !_scalePanelOpen),
            icon: Icon(
              Icons.open_with,
              color: _scalePanelOpen
                  ? const Color(0xFFB388FF)
                  : Colors.white54,
            ),
            tooltip: 'Căn chỉnh scale avatar',
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'YogaMirror',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: compact ? 18 : 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
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

    // Camera + VRM start immediately; pose JSON (~15MB) loads in background.
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
                  key: _vrmKey,
                  modelAssetPath: AppAssets.yogaAvatarVrm,
                  currentFrame: _controller.currentSampleFrame,
                  opacity: 0.65,
                  isPlaying: _controller.isPlaying,
                  debugOverlayEnabled: _debugOverlayEnabled,
                  mappingToolEnabled: _mappingToolEnabled,
                  idLabelMode: _idLabelModes[_idLabelModeIndex],
                ),
                if (_controller.isLoading)
                  const Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: _LoadChip(label: 'Đang tải mẫu động tác...'),
                    ),
                  ),
                if (_scalePanelOpen) _buildScalePanel(),
              ],
            ),
          );
        },
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
                      'Căn chỉnh avatar',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      _vrmKey.currentState?.resetSessionScale();
                      setState(() {
                        _manualScale = 0.7;
                        _manualScaleX = 1.0;
                        _manualScaleY = 1.0;
                        _manualYOffset = 1.0;
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
                label: 'Scale chung',
                value: _manualScale,
                min: 0.3,
                max: 1.5,
                onChanged: (v) {
                  setState(() => _manualScale = v);
                  _pushManualScale();
                },
              ),
              _scaleSlider(
                label: 'Chiều cao (Y)',
                value: _manualScaleY,
                min: 0.5,
                max: 1.8,
                onChanged: (v) {
                  setState(() => _manualScaleY = v);
                  _pushManualScale();
                },
              ),
              _scaleSlider(
                label: 'Bề ngang (X)',
                value: _manualScaleX,
                min: 0.5,
                max: 1.8,
                onChanged: (v) {
                  setState(() => _manualScaleX = v);
                  _pushManualScale();
                },
              ),
              _scaleSlider(
                label: 'Lên / xuống',
                value: _manualYOffset,
                min: -0.5,
                max: 2.0,
                onChanged: (v) {
                  setState(() => _manualYOffset = v);
                  _pushManualScale();
                },
              ),
              const SizedBox(height: 4),
              Text(
                'Tự scale theo body (1 lần khi bắt đầu) sẽ qua API '
                'applySessionBodyScale / fitGuideToUserFromFrame — '
                'không scale lại khi cam đang chạy.',
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
          width: 40,
          child: Text(
            value.toStringAsFixed(2),
            style: const TextStyle(color: Colors.white54, fontSize: 11),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }

  void _pushManualScale() {
    _vrmKey.currentState?.setGuideTransform(
      scale: _manualScale,
      scaleX: _manualScaleX,
      scaleY: _manualScaleY,
      yOffset: _manualYOffset,
      force: true,
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
