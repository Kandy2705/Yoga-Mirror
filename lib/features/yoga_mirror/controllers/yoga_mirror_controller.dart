import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/constants/app_assets.dart';
import '../data/pose_json_asset_loader.dart';
import '../models/pose_capture.dart';
import '../models/pose_chunk_meta.dart';
import '../models/pose_frame.dart';
import '../services/pose_feedback_service.dart';
import '../services/pose_matching_service.dart';

class YogaMirrorController extends ChangeNotifier {
  YogaMirrorController({
    PoseJsonAssetLoader? loader,
    PoseMatchingService? matchingService,
    PoseFeedbackService? feedbackService,
    this.simulatorMode = false,
  }) : _loader = loader ?? PoseJsonAssetLoader(),
       _matchingService = matchingService ?? PoseMatchingService(),
       _feedbackService = feedbackService ?? PoseFeedbackService(),
       poseDetectionSupported = !kIsWeb && !simulatorMode,
       scoreLabel = _initialScoreLabel(simulatorMode);

  final PoseJsonAssetLoader _loader;
  final PoseMatchingService _matchingService;
  final PoseFeedbackService _feedbackService;
  final bool simulatorMode;

  PoseCapture? capture;

  /// All **loaded** frames so far (sorted by timestamp). Grows as chunks arrive.
  List<PoseFrame> frames = [];
  int durationMs = 0;
  int startTimestampMs = 0;
  int endTimestampMs = 0;
  int currentTimeMs = 0;
  PoseFrame? currentSampleFrame;
  double playbackSpeed = 1.0;
  bool isPlaying = false;
  double? smoothedScore;
  List<String> feedback = ['Đang tải mẫu động tác...'];
  bool isLoading = true;

  /// True while more pose chunks still loading in background.
  bool isBufferingChunks = false;
  String? loadError;
  bool userDetected = false;
  final bool poseDetectionSupported;

  String exerciseName = AppAssets.exerciseDisplayName;
  String scoreLabel;

  PoseChunkMeta? _meta;
  final Set<int> _loadedChunkIndices = {};
  final Map<int, Future<void>> _chunkLoads = {};
  bool _disposed = false;

  static String _initialScoreLabel(bool simulatorMode) {
    if (kIsWeb) return 'Chỉ hỗ trợ chấm điểm trên iOS/Android';
    if (simulatorMode) return 'Simulator: cần iPhone thật';
    return '--';
  }

  /// Default: chunked meta (fast first paint). Falls back to monolith JSON path.
  Future<void> initialize({
    String assetPath = AppAssets.defaultPoseMeta,
  }) async {
    isLoading = true;
    loadError = null;
    isBufferingChunks = false;
    _meta = null;
    _loadedChunkIndices.clear();
    _chunkLoads.clear();
    frames = [];
    notifyListeners();

    try {
      if (_loader.isChunkedMetaPath(assetPath)) {
        await _initializeChunked(assetPath);
      } else {
        await _initializeMonolith(assetPath);
      }
      feedback = _initialFeedback();
      isLoading = false;
    } catch (error) {
      loadError = 'Không load được JSON: $error';
      isLoading = false;
      feedback = [loadError!];
    }

    if (!_disposed) notifyListeners();
  }

  Future<void> _initializeMonolith(String assetPath) async {
    capture = await _loader.load(assetPath);
    frames = capture!.frames;
    durationMs = capture!.durationMs;
    if (frames.isNotEmpty) {
      startTimestampMs = frames.first.timestampMs;
      endTimestampMs = frames.last.timestampMs;
      currentSampleFrame = frames.first;
      currentTimeMs = startTimestampMs;
    }
  }

  Future<void> _initializeChunked(String metaPath) async {
    final meta = await _loader.loadMeta(metaPath);
    if (meta.chunks.isEmpty) {
      throw StateError('Pose meta has no chunks: $metaPath');
    }
    _meta = meta;
    durationMs = meta.durationMs;
    startTimestampMs = meta.startTimestampMs;
    endTimestampMs = meta.endTimestampMs;

    capture = PoseCapture(
      schemaVersion: meta.schemaVersion,
      capture: meta.capture,
      device: meta.device,
      captureParams: meta.captureParams,
      frames: const [], // filled lazily into [frames]
    );

    // First chunk only — unblocks UI (~300–400KB parse).
    await _loadChunkIndex(0);
    if (frames.isNotEmpty) {
      currentSampleFrame = frames.first;
      currentTimeMs = frames.first.timestampMs;
    } else {
      currentTimeMs = startTimestampMs;
    }

    // Rest of timeline in background (does not block isLoading).
    isBufferingChunks = meta.chunks.length > 1;
    unawaited(_preloadRemainingChunks());
  }

  Future<void> _preloadRemainingChunks() async {
    final meta = _meta;
    if (meta == null) return;
    for (var i = 1; i < meta.chunks.length; i++) {
      if (_disposed) return;
      try {
        await _loadChunkIndex(i);
      } catch (e) {
        debugPrint('[YogaMirror] background chunk $i failed: $e');
      }
    }
    if (_disposed) return;
    isBufferingChunks = false;
    notifyListeners();
  }

  Future<void> _loadChunkIndex(int index) async {
    final meta = _meta;
    if (meta == null) return;
    if (index < 0 || index >= meta.chunks.length) return;
    if (_loadedChunkIndices.contains(index)) return;

    final existing = _chunkLoads[index];
    if (existing != null) {
      await existing;
      return;
    }

    final future = _doLoadChunk(index);
    _chunkLoads[index] = future;
    try {
      await future;
    } finally {
      _chunkLoads.remove(index);
    }
  }

  Future<void> _doLoadChunk(int index) async {
    final meta = _meta!;
    if (_loadedChunkIndices.contains(index)) return;

    final info = meta.chunks[index];
    final chunkFrames = await _loader.loadChunk(info.asset);
    if (_disposed) return;

    _loadedChunkIndices.add(index);
    if (chunkFrames.isEmpty) return;

    // Merge into sorted timeline (append-fast path when loading in order).
    if (frames.isEmpty) {
      frames = List<PoseFrame>.from(chunkFrames);
    } else if (chunkFrames.first.timestampMs >= frames.last.timestampMs) {
      frames = [...frames, ...chunkFrames];
    } else if (chunkFrames.last.timestampMs <= frames.first.timestampMs) {
      frames = [...chunkFrames, ...frames];
    } else {
      frames = [...frames, ...chunkFrames]
        ..sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
    }

    // Refresh capture shell for any code reading capture.frames (optional).
    if (capture != null) {
      capture = PoseCapture(
        schemaVersion: capture!.schemaVersion,
        capture: capture!.capture,
        device: capture!.device,
        captureParams: capture!.captureParams,
        frames: frames,
      );
    }

    if (!_disposed) notifyListeners();
  }

  /// Ensure pose data around [timeMs] is loaded (seek / play head).
  Future<void> ensureTimeLoaded(int timeMs) async {
    final meta = _meta;
    if (meta == null) return;
    final idx = meta.chunkIndexForTime(timeMs);
    await _loadChunkIndex(idx);
    // Look-ahead ~1 chunk for smooth playback.
    if (idx + 1 < meta.chunks.length) {
      unawaited(_loadChunkIndex(idx + 1));
    }
  }

  void setPlaying(bool value) {
    isPlaying = value;
    if (value) {
      unawaited(ensureTimeLoaded(currentTimeMs));
    }
    notifyListeners();
  }

  void setPlaybackSpeed(double speed) {
    playbackSpeed = speed;
    notifyListeners();
  }

  void seekToProgress(double progress) {
    if (durationMs <= 0) return;

    currentTimeMs =
        startTimestampMs + (durationMs * progress.clamp(0, 1)).round();
    unawaited(_seekToTime(currentTimeMs));
  }

  Future<void> _seekToTime(int timeMs) async {
    await ensureTimeLoaded(timeMs);
    if (_disposed) return;
    currentTimeMs = timeMs;
    if (frames.isNotEmpty) {
      currentSampleFrame = _frameAtTime(timeMs);
    }
    notifyListeners();
  }

  void resetPlayback() {
    currentTimeMs = startTimestampMs;
    if (frames.isNotEmpty) {
      currentSampleFrame = frames.first;
    }
    isPlaying = false;
    smoothedScore = null;
    scoreLabel = poseDetectionSupported ? '--' : scoreLabel;
    unawaited(ensureTimeLoaded(currentTimeMs));
    notifyListeners();
  }

  void tick(int elapsedMs) {
    if (!isPlaying || durationMs <= 0) {
      return;
    }

    final end = endTimestampMs > 0
        ? endTimestampMs
        : startTimestampMs + durationMs;
    final next = currentTimeMs + (elapsedMs * playbackSpeed).round();

    if (next >= end) {
      currentTimeMs = end;
      if (frames.isNotEmpty) {
        currentSampleFrame = frames.last;
      }
      isPlaying = false;
    } else {
      currentTimeMs = next;
      if (frames.isNotEmpty) {
        currentSampleFrame = _frameAtTime(currentTimeMs);
      }
      // Prefetch while playing.
      unawaited(ensureTimeLoaded(currentTimeMs + 1500));
    }

    notifyListeners();
  }

  List<String> _initialFeedback() {
    if (simulatorMode) {
      return [
        'Simulator: xem VRM + JSON animation. Chấm điểm cần iPhone thật.',
      ];
    }
    if (!poseDetectionSupported) {
      return ['Chỉ hỗ trợ chấm điểm trên iOS/Android'];
    }
    return [];
  }

  /// Landmark indices for full-body detection validation
  static const _fullBodyIndices = {11, 12, 23, 24, 25, 26, 27, 28};
  static const _torsoIndices = {11, 12, 23, 24};

  bool _hasFullBody(Map<int, PoseMatchPoint> landmarks) {
    return _fullBodyIndices.every(
      (i) => landmarks.containsKey(i) && landmarks[i]!.visibility >= 0.3,
    );
  }

  bool _hasTorso(Map<int, PoseMatchPoint> landmarks) {
    return _torsoIndices.every(
      (i) => landmarks.containsKey(i) && landmarks[i]!.visibility >= 0.3,
    );
  }

  void onUserLandmarks(Map<int, PoseMatchPoint>? landmarks) {
    if (!poseDetectionSupported) {
      return;
    }

    if (landmarks == null || landmarks.isEmpty || currentSampleFrame == null) {
      userDetected = false;
      scoreLabel = '--';
      feedback = _feedbackService.buildFeedback(
        score: 0,
        userDetected: false,
        poseDetectionSupported: true,
        angleDiffs: const {},
        bodyStatus: 'none',
      );
      notifyListeners();
      return;
    }

    userDetected = true;

    if (!_hasFullBody(landmarks)) {
      String bodyStatus;
      if (!_hasTorso(landmarks)) {
        bodyStatus = 'no_torso';
      } else {
        bodyStatus = 'partial';
      }
      scoreLabel = '--';
      feedback = _feedbackService.buildFeedback(
        score: 0,
        userDetected: true,
        poseDetectionSupported: true,
        angleDiffs: const {},
        bodyStatus: bodyStatus,
      );
      notifyListeners();
      return;
    }

    final result = _matchingService.compare(
      sampleFrame: currentSampleFrame!,
      userLandmarks: landmarks,
    );

    final previous = smoothedScore ?? result.score;
    smoothedScore = previous * 0.8 + result.score * 0.2;
    scoreLabel = '${smoothedScore!.round()}%';

    feedback = _feedbackService.buildFeedback(
      score: smoothedScore!,
      userDetected: true,
      poseDetectionSupported: true,
      angleDiffs: result.angleDiffs,
      bodyStatus: 'full',
    );

    notifyListeners();
  }

  double get playbackProgress {
    if (durationMs <= 0) {
      return 0;
    }
    return ((currentTimeMs - startTimestampMs) / durationMs).clamp(0, 1);
  }

  /// How many pose chunks are ready (debug / UI).
  int get loadedChunkCount => _loadedChunkIndices.length;

  int get totalChunkCount => _meta?.chunks.length ?? (frames.isEmpty ? 0 : 1);

  PoseFrame _frameAtTime(int timeMs) {
    if (frames.isEmpty) {
      throw StateError('No pose frames loaded');
    }

    // Binary search nearest timestamp.
    var lo = 0;
    var hi = frames.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (frames[mid].timestampMs < timeMs) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    // lo is first >= timeMs (or last).
    if (lo == 0) return frames.first;
    if (lo >= frames.length) return frames.last;
    final a = frames[lo - 1];
    final b = frames[lo];
    final da = (timeMs - a.timestampMs).abs();
    final db = (timeMs - b.timestampMs).abs();
    return da <= db ? a : b;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
