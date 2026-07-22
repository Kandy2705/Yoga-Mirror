import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:rive/rive.dart' as rive;

import 'models/pose_models.dart';
import 'services/pose_loader.dart';
import 'widgets/mannequin_stage.dart';
import 'widgets/size_adjustment_sheet.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  await rive.RiveNative.init();
  runApp(const YogaMirrorApp());
}

class YogaMirrorApp extends StatelessWidget {
  const YogaMirrorApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF7C6DFF),
      brightness: Brightness.dark,
    );
    return MaterialApp(
      title: 'YogaMirror Rive 2D',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF080D18),
        sliderTheme: const SliderThemeData(showValueIndicator: ShowValueIndicator.always),
      ),
      home: const YogaMirrorScreen(),
    );
  }
}

class YogaMirrorScreen extends StatefulWidget {
  const YogaMirrorScreen({super.key});

  @override
  State<YogaMirrorScreen> createState() => _YogaMirrorScreenState();
}

class _YogaMirrorScreenState extends State<YogaMirrorScreen>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  PoseSequence? _sequence;
  Object? _loadError;
  double _positionMs = 0;
  bool _playing = false;
  bool _loop = true;
  bool _showJsonOverlay = false;
  bool _showLegGuides = true;
  bool _mirror = false;
  bool _openingFile = false;
  bool _loadingBundledExercise = false;
  List<String> _bundledJsonAssets = const [];
  String? _selectedBundledAsset;
  double _speed = 1;
  double _widthScale = 1;
  double _heightScale = 1;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _discoverAndLoadBundledExercises();
  }

  Future<void> _discoverAndLoadBundledExercises() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final assets = manifest
          .listAssets()
          .where(
            (path) => path.startsWith('assets/data/') &&
                path.toLowerCase().endsWith('.json'),
          )
          .toList()
        ..sort();

      if (assets.isEmpty) {
        throw const FormatException(
          'Không tìm thấy bài JSON nào trong assets/data/.',
        );
      }

      final preferred = assets.firstWhere(
        (path) => path.endsWith('/sample_pose.json'),
        orElse: () => assets.first,
      );

      if (mounted) {
        setState(() => _bundledJsonAssets = assets);
      }
      await _loadBundledJson(preferred);
    } catch (error) {
      if (mounted) {
        setState(() => _loadError = error);
      }
    }
  }

  Future<void> _loadBundledJson(String assetPath) async {
    if (_loadingBundledExercise) return;

    _pause();
    setState(() {
      _loadingBundledExercise = true;
      _loadError = null;
    });

    try {
      final sequence = await PoseLoader.fromAsset(assetPath);
      if (mounted) {
        setState(() {
          _sequence = sequence;
          _selectedBundledAsset = assetPath;
          _positionMs = 0;
          _loadError = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _loadError = error);
      }
    } finally {
      if (mounted) {
        setState(() => _loadingBundledExercise = false);
      }
    }
  }

  Future<void> _showBundledExercisePicker() async {
    if (_bundledJsonAssets.isEmpty || _loadingBundledExercise) return;

    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Chọn bài tập JSON',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(
                'Các file JSON có sẵn trong assets/data/',
                style: Theme.of(sheetContext)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.white60),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.55,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _bundledJsonAssets.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final path = _bundledJsonAssets[index];
                    final isSelected = path == _selectedBundledAsset;
                    return ListTile(
                      leading: CircleAvatar(
                        child: Text('${index + 1}'),
                      ),
                      title: Text('Bài ${index + 1}'),
                      subtitle: Text(
                        _assetFileName(path),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: isSelected
                          ? const Icon(Icons.check_circle)
                          : const Icon(Icons.chevron_right),
                      selected: isSelected,
                      onTap: () => Navigator.of(sheetContext).pop(path),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );

    if (selected != null && selected != _selectedBundledAsset) {
      await _loadBundledJson(selected);
    }
  }

  Future<void> _openJson() async {
    if (_openingFile) {
      return;
    }
    setState(() => _openingFile = true);
    try {
      _pause();
      final sequence = await PoseLoader.pickFromPhone();
      if (sequence != null && mounted) {
        setState(() {
          _sequence = sequence;
          _selectedBundledAsset = null;
          _positionMs = 0;
          _loadError = null;
          _showJsonOverlay = true;
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không mở được JSON: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _openingFile = false);
      }
    }
  }

  void _onTick(Duration elapsed) {
    final sequence = _sequence;
    if (!_playing || sequence == null) {
      _lastTick = elapsed;
      return;
    }
    if (sequence.durationMs <= 0) {
      _pause();
      return;
    }
    final delta = elapsed - _lastTick;
    _lastTick = elapsed;
    var next = _positionMs + delta.inMicroseconds / 1000 * _speed;
    if (next >= sequence.durationMs) {
      if (_loop) {
        next %= sequence.durationMs;
      } else {
        next = sequence.durationMs.toDouble();
        _pause();
      }
    }
    if (mounted) {
      setState(() => _positionMs = next);
    }
  }

  void _togglePlayback() {
    if (_playing) {
      _pause();
    } else {
      _play();
    }
  }

  void _play() {
    final sequence = _sequence;
    if (sequence == null) {
      return;
    }
    if (_positionMs >= sequence.durationMs) {
      _positionMs = 0;
    }
    _lastTick = Duration.zero;
    setState(() => _playing = true);
    _ticker.start();
  }

  void _pause() {
    _ticker.stop();
    _lastTick = Duration.zero;
    if (mounted) {
      setState(() => _playing = false);
    }
  }

  void _cycleSpeed() {
    const speeds = [0.5, 1.0, 1.5, 2.0];
    final current = speeds.indexOf(_speed);
    setState(() => _speed = speeds[(current + 1) % speeds.length]);
  }

  Future<void> _openSizePanel() {
    return showMannequinSizeSheet(
      context: context,
      initialWidth: _widthScale,
      initialHeight: _heightScale,
      onWidthChanged: (value) => setState(() => _widthScale = value),
      onHeightChanged: (value) => setState(() => _heightScale = value),
      onReset: () => setState(() {
        _widthScale = 1;
        _heightScale = 1;
      }),
    );
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sequence = _sequence;
    return Scaffold(
      appBar: AppBar(
        title: const Text('YogaMirror 2D'),
        actions: [
          IconButton(
            tooltip: 'Mở JSON từ điện thoại',
            onPressed: _openingFile ? null : _openJson,
            icon: _openingFile
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.folder_open),
          ),
          IconButton(
            tooltip: 'Căn chiều cao / chiều rộng',
            onPressed: _openSizePanel,
            icon: const Icon(Icons.tune),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          child: Column(
            children: [
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFF111A2D),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: _buildStage(sequence),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (sequence != null) ...[
                _buildExerciseSelector(),
                const SizedBox(height: 8),
                _buildToolRow(sequence),
                _buildTimeline(sequence),
                _buildPlaybackRow(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStage(PoseSequence? sequence) {
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 12),
              Text('Không đọc được JSON:\n$_loadError', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () {
                  final selected = _selectedBundledAsset;
                  if (selected != null) {
                    _loadBundledJson(selected);
                  } else {
                    _discoverAndLoadBundledExercises();
                  }
                },
                child: const Text('Thử lại'),
              ),
            ],
          ),
        ),
      );
    }
    if (sequence == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return MannequinStage(
      sequence: sequence,
      positionMs: _positionMs,
      showJsonOverlay: _showJsonOverlay,
      showLegGuides: _showLegGuides,
      mirror: _mirror,
      widthScale: _widthScale,
      heightScale: _heightScale,
    );
  }

  Widget _buildExerciseSelector() {
    final selected = _selectedBundledAsset;
    final index = selected == null ? -1 : _bundledJsonAssets.indexOf(selected);
    final title = selected == null
        ? 'JSON từ điện thoại'
        : index >= 0
            ? 'Bài ${index + 1}'
            : 'Bài JSON';
    final subtitle = selected == null ? null : _assetFileName(selected);

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _bundledJsonAssets.isEmpty || _loadingBundledExercise
            ? null
            : _showBundledExercisePicker,
        icon: _loadingBundledExercise
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.menu_book_outlined),
        label: Text(
          subtitle == null ? title : '$title • $subtitle',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _buildToolRow(PoseSequence sequence) {
    return Row(
      children: [
        FilterChip(
          selected: _showJsonOverlay,
          onSelected: (value) => setState(() => _showJsonOverlay = value),
          avatar: const Icon(Icons.data_object, size: 18),
          label: const Text('So sánh JSON'),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: 'Bật/tắt đường phân biệt chân',
          onPressed: () => setState(() => _showLegGuides = !_showLegGuides),
          icon: Icon(
            Icons.directions_walk,
            color: _showLegGuides ? const Color(0xFF52D6FF) : null,
          ),
        ),
        const SizedBox(width: 6),
        IconButton.filledTonal(
          tooltip: 'Lật trái / phải',
          onPressed: () => setState(() => _mirror = !_mirror),
          icon: Icon(_mirror ? Icons.flip_to_front : Icons.flip),
        ),
        const Spacer(),
        Flexible(
          child: Text(
            '${sequence.sourceName} • ${sequence.frames.length} frames • ${sequence.sampleFps.toStringAsFixed(0)} FPS',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white60),
          ),
        ),
      ],
    );
  }

  Widget _buildTimeline(PoseSequence sequence) {
    final maxPositionMs = sequence.durationMs <= 0
        ? 1.0
        : sequence.durationMs.toDouble();
    return Row(
      children: [
        SizedBox(width: 45, child: Text(_formatMs(_positionMs))),
        Expanded(
          child: Slider(
            value: _positionMs.clamp(0.0, maxPositionMs).toDouble(),
            max: maxPositionMs,
            onChangeStart: (_) => _pause(),
            onChanged: (value) => setState(() => _positionMs = value),
          ),
        ),
        SizedBox(
          width: 45,
          child: Text(_formatMs(sequence.durationMs.toDouble()), textAlign: TextAlign.end),
        ),
      ],
    );
  }

  Widget _buildPlaybackRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: 'Về đầu',
          onPressed: () {
            _pause();
            setState(() => _positionMs = 0);
          },
          icon: const Icon(Icons.skip_previous),
        ),
        const SizedBox(width: 8),
        FilledButton.tonalIcon(
          onPressed: _togglePlayback,
          icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
          label: Text(_playing ? 'Tạm dừng' : 'Phát'),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Lặp lại',
          onPressed: () => setState(() => _loop = !_loop),
          icon: Icon(_loop ? Icons.repeat_on : Icons.repeat),
        ),
        TextButton(
          onPressed: _cycleSpeed,
          child: Text(
            _speed == _speed.roundToDouble()
                ? '${_speed.toInt()}x'
                : '${_speed}x',
          ),
        ),
      ],
    );
  }
}

String _assetFileName(String assetPath) {
  final slash = assetPath.lastIndexOf('/');
  return slash < 0 ? assetPath : assetPath.substring(slash + 1);
}

String _formatMs(double value) {
  final totalSeconds = (value / 1000).floor();
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}
