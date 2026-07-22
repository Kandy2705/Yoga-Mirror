import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:rive/rive.dart' as rive;

import 'models/pose_models.dart';
import 'network/backend_api.dart';
import 'network/pose_websocket_client.dart';
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
        sliderTheme: const SliderThemeData(
          showValueIndicator: ShowValueIndicator.always,
        ),
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

  final BackendApi _api = BackendApi();
  PoseWebSocketClient? _wsClient;
  StreamSubscription<Map<String, dynamic>>? _wsSubscription;

  PoseSequence? _sequence;
  Object? _loadError;
  double _positionMs = 0;
  bool _playing = false;
  bool _loop = true;
  bool _showJsonOverlay = false;
  bool _showLegGuides = true;
  bool _mirror = false;
  double _speed = 1;
  double _widthScale = 1;
  double _heightScale = 1;

  bool _isLoggedIn = false;
  bool _loggingIn = false;
  String? _loginError;
  List<Map<String, dynamic>> _assignedExercises = [];
  bool _loadingExercises = false;
  String? _selectedExerciseId;

  bool _wsConnected = false;
  String? _wsError;
  bool _downloadingJson = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  // ── Auth ──

  Future<void> _login() async {
    if (_loggingIn) return;
    setState(() {
      _loggingIn = true;
      _loginError = null;
    });

    try {
      await _api.login(
        email: 'patient.test@example.com',
        password: 'MySecretPassword123',
      );
      if (mounted) {
        setState(() {
          _isLoggedIn = true;
          _loggingIn = false;
        });
        await _loadAssignedExercises();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loginError = e.toString();
          _loggingIn = false;
        });
      }
    }
  }

  void _logout() {
    _pause();
    _disconnectWebSocket();
    setState(() {
      _isLoggedIn = false;
      _assignedExercises = [];
      _selectedExerciseId = null;
      _sequence = null;
      _positionMs = 0;
    });
  }

  // ── Exercises ──

  Future<void> _loadAssignedExercises() async {
    if (!_isLoggedIn) return;
    setState(() => _loadingExercises = true);

    try {
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final exercises = await _api.getAssignedExercises(today);
      if (mounted) {
        setState(() {
          _assignedExercises = exercises;
          _loadingExercises = false;
        });
      }
    } catch (e) {
      debugPrint('Load exercises error: $e');
      if (mounted) {
        setState(() => _loadingExercises = false);
      }
    }
  }

  Future<void> _selectExercise(Map<String, dynamic> exercise) async {
    final userExerciseId = exercise['id']?.toString() ?? '';
    final media = exercise['data_exercise']?['media'];
    final refJsonUrl = (media is List && media.isNotEmpty)
        ? media[0]['reference_json_url']?.toString()
        : null;

    if (refJsonUrl == null || refJsonUrl.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bai tap nay khong co JSON reference.')),
        );
      }
      return;
    }

    _pause();
    setState(() {
      _downloadingJson = true;
      _loadError = null;
      _selectedExerciseId = userExerciseId;
      _positionMs = 0;
    });

    try {
      final jsonData = await _api.downloadJson(refJsonUrl);
      final sequence = PoseSequence.fromJson(jsonData);

      if (mounted) {
        setState(() {
          _sequence = sequence;
          _downloadingJson = false;
        });
        await _connectWebSocket(userExerciseId);
      }
    } catch (e) {
      debugPrint('Download JSON error: $e');
      if (mounted) {
        setState(() {
          _loadError = e;
          _downloadingJson = false;
        });
      }
    }
  }

  // ── WebSocket ──

  Future<void> _connectWebSocket(String userExerciseId) async {
    if (_api.accessToken == null) return;
    await _disconnectWebSocket();

    final client = PoseWebSocketClient();
    _wsSubscription = client.messages.listen((msg) {
      final event = msg['event'] ?? msg['type'];
      debugPrint('WS event: $event');
      if (event == 'connected') {
        if (mounted) setState(() => _wsConnected = true);
      } else if (event == 'error') {
        if (mounted) {
          setState(() => _wsError = msg['error']?['reason']?.toString());
        }
      } else if (event == 'done') {
        debugPrint('WS done: $msg');
      }
    });

    try {
      await client.connect(
        userExerciseId: userExerciseId,
        token: _api.accessToken!,
      );
      _wsClient = client;
      if (mounted) setState(() => _wsConnected = true);
    } catch (e) {
      debugPrint('WS connect error: $e');
      if (mounted) {
        setState(() {
          _wsError = e.toString();
          _wsConnected = false;
        });
      }
      await client.dispose();
    }
  }

  Future<void> _disconnectWebSocket() async {
    await _wsSubscription?.cancel();
    _wsSubscription = null;
    await _wsClient?.dispose();
    _wsClient = null;
    if (mounted) {
      setState(() {
        _wsConnected = false;
        _wsError = null;
      });
    }
  }

  // ── Playback ──

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
    if (sequence == null) return;
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
    _wsSubscription?.cancel();
    _wsClient?.dispose();
    _api.close();
    super.dispose();
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final sequence = _sequence;
    return Scaffold(
      appBar: AppBar(
        title: const Text('YogaMirror 2D'),
        actions: [
          if (_isLoggedIn) ...[
            IconButton(
              tooltip: 'Tai lai danh sach',
              onPressed: _loadingExercises ? null : _loadAssignedExercises,
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: 'Dang xuat',
              onPressed: _logout,
              icon: const Icon(Icons.logout),
            ),
          ] else
            IconButton(
              tooltip: 'Dang nhap',
              onPressed: _loggingIn ? null : _login,
              icon: _loggingIn
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.login),
            ),
          IconButton(
            tooltip: 'Can chieu cao / chieu rong',
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
              if (_loginError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Login error: $_loginError',
                    style:
                        const TextStyle(color: Colors.redAccent, fontSize: 12),
                  ),
                ),
              if (_isLoggedIn) _buildExercisePanel(),
              if (_wsConnected)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.link,
                          size: 16, color: Colors.greenAccent),
                      const SizedBox(width: 4),
                      const Text('WS connected',
                          style: TextStyle(
                              color: Colors.greenAccent, fontSize: 12)),
                      const Spacer(),
                      if (_wsError != null)
                        Text('Error: $_wsError',
                            style: const TextStyle(
                                color: Colors.orangeAccent, fontSize: 11)),
                    ],
                  ),
                ),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFF111A2D),
                    borderRadius: BorderRadius.circular(28),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: _buildStage(sequence),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (sequence != null) ...[
                _buildExerciseInfo(),
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

  Widget _buildExercisePanel() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2236),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.cloud, size: 16, color: Color(0xFF7C6DFF)),
              const SizedBox(width: 6),
              Text(
                _loadingExercises
                    ? 'Dang tai...'
                    : 'Bai tap da gan (${_assignedExercises.length})',
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ],
          ),
          if (_assignedExercises.isNotEmpty) ...[
            const SizedBox(height: 8),
            ..._assignedExercises.map((ex) {
              final title = ex['data_exercise']?['title'] ?? 'Bai tap';
              final userExerciseId = ex['id']?.toString() ?? '';
              final isSelected = userExerciseId == _selectedExerciseId;
              return Card(
                margin: const EdgeInsets.only(bottom: 6),
                color: isSelected
                    ? const Color(0xFF2A3456)
                    : const Color(0xFF151E30),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: isSelected
                        ? const Color(0xFF7C6DFF)
                        : Colors.white.withValues(alpha: 0.06),
                  ),
                ),
                child: ListTile(
                  dense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  leading: Icon(
                    Icons.fitness_center,
                    size: 20,
                    color:
                        isSelected ? const Color(0xFF7C6DFF) : Colors.white54,
                  ),
                  title: Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13)),
                  trailing: _downloadingJson && isSelected
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          isSelected
                              ? Icons.check_circle
                              : Icons.play_circle_outline,
                          color: isSelected
                              ? const Color(0xFF52D6FF)
                              : Colors.white38,
                        ),
                  onTap: _downloadingJson ? null : () => _selectExercise(ex),
                ),
              );
            }),
          ],
          if (_assignedExercises.isEmpty && !_loadingExercises)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Khong co bai tap nao cho hom nay.',
                style: TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStage(PoseSequence? sequence) {
    if (_downloadingJson) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Dang tai JSON tu server...',
                style: TextStyle(color: Colors.white60)),
          ],
        ),
      );
    }
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 12),
              Text('Loi: $_loadError', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _loadAssignedExercises,
                child: const Text('Thu lai'),
              ),
            ],
          ),
        ),
      );
    }
    if (sequence == null) {
      return Center(
        child: _isLoggedIn
            ? const Text('Chon bai tap de bat dau',
                style: TextStyle(color: Colors.white38))
            : const Text('Dang nhap de xem bai tap',
                style: TextStyle(color: Colors.white38)),
      );
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

  Widget _buildExerciseInfo() {
    final sequence = _sequence;
    if (sequence == null) return const SizedBox.shrink();
    return Row(
      children: [
        const Icon(Icons.fitness_center, size: 16, color: Colors.white54),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '${sequence.sourceName} - ${sequence.frames.length} frames - ${sequence.sampleFps.toStringAsFixed(0)} FPS',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.white60),
          ),
        ),
      ],
    );
  }

  Widget _buildToolRow(PoseSequence sequence) {
    return Row(
      children: [
        FilterChip(
          selected: _showJsonOverlay,
          onSelected: (value) => setState(() => _showJsonOverlay = value),
          avatar: const Icon(Icons.data_object, size: 18),
          label: const Text('So sanh JSON'),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: 'Bat/tat duong phan biet chan',
          onPressed: () => setState(() => _showLegGuides = !_showLegGuides),
          icon: Icon(
            Icons.directions_walk,
            color: _showLegGuides ? const Color(0xFF52D6FF) : null,
          ),
        ),
        const SizedBox(width: 6),
        IconButton.filledTonal(
          tooltip: 'Lat trai / phai',
          onPressed: () => setState(() => _mirror = !_mirror),
          icon: Icon(_mirror ? Icons.flip_to_front : Icons.flip),
        ),
      ],
    );
  }

  Widget _buildTimeline(PoseSequence sequence) {
    final maxMs =
        sequence.durationMs <= 0 ? 1.0 : sequence.durationMs.toDouble();
    return Row(
      children: [
        SizedBox(width: 45, child: Text(_formatMs(_positionMs))),
        Expanded(
          child: Slider(
            value: _positionMs.clamp(0.0, maxMs).toDouble(),
            max: maxMs,
            onChangeStart: (_) => _pause(),
            onChanged: (value) => setState(() => _positionMs = value),
          ),
        ),
        SizedBox(
          width: 45,
          child: Text(_formatMs(sequence.durationMs.toDouble()),
              textAlign: TextAlign.end),
        ),
      ],
    );
  }

  Widget _buildPlaybackRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: 'Ve dau',
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
          label: Text(_playing ? 'Tam dung' : 'Phat'),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Lap lai',
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

String _formatMs(double value) {
  final totalSeconds = (value / 1000).floor();
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}
