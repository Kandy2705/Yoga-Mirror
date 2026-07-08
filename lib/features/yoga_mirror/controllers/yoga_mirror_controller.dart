import 'package:flutter/foundation.dart';

import '../../../core/constants/app_assets.dart';
import '../data/pose_json_asset_loader.dart';
import '../models/pose_capture.dart';
import '../models/pose_frame.dart';
import '../services/pose_feedback_service.dart';
import '../services/pose_matching_service.dart';

class YogaMirrorController extends ChangeNotifier {
  YogaMirrorController({
    PoseJsonAssetLoader? loader,
    PoseMatchingService? matchingService,
    PoseFeedbackService? feedbackService,
    this.simulatorMode = false,
  })  : _loader = loader ?? PoseJsonAssetLoader(),
        _matchingService = matchingService ?? PoseMatchingService(),
        _feedbackService = feedbackService ?? PoseFeedbackService(),
        poseDetectionSupported = !kIsWeb && !simulatorMode,
        scoreLabel = _initialScoreLabel(simulatorMode);

  final PoseJsonAssetLoader _loader;
  final PoseMatchingService _matchingService;
  final PoseFeedbackService _feedbackService;
  final bool simulatorMode;

  PoseCapture? capture;
  List<PoseFrame> frames = [];
  int durationMs = 0;
  int currentTimeMs = 0;
  PoseFrame? currentSampleFrame;
  double playbackSpeed = 1.0;
  bool isPlaying = false;
  double? smoothedScore;
  List<String> feedback = ['Đang tải mẫu động tác...'];
  bool isLoading = true;
  String? loadError;
  bool userDetected = false;
  final bool poseDetectionSupported;

  String exerciseName = AppAssets.exerciseDisplayName;
  String scoreLabel;

  static String _initialScoreLabel(bool simulatorMode) {
    if (kIsWeb) return 'Chỉ hỗ trợ chấm điểm trên iOS/Android';
    if (simulatorMode) return 'Simulator: cần iPhone thật';
    return '--';
  }

  Future<void> initialize({String assetPath = AppAssets.treePoseJson}) async {
    isLoading = true;
    loadError = null;
    notifyListeners();

    try {
      capture = await _loader.load(assetPath);
      frames = capture!.frames;
      durationMs = capture!.durationMs;
      if (frames.isNotEmpty) {
        currentSampleFrame = frames.first;
        currentTimeMs = frames.first.timestampMs;
      }
      feedback = _initialFeedback();
      isLoading = false;
    } catch (error) {
      loadError = 'Không load được JSON: $error';
      isLoading = false;
      feedback = [loadError!];
    }

    notifyListeners();
  }

  void setPlaying(bool value) {
    isPlaying = value;
    notifyListeners();
  }

  void setPlaybackSpeed(double speed) {
    playbackSpeed = speed;
    notifyListeners();
  }

  void seekToProgress(double progress) {
    if (frames.isEmpty || durationMs <= 0) {
      return;
    }

    final base = frames.first.timestampMs;
    currentTimeMs = base + (durationMs * progress.clamp(0, 1)).round();
    currentSampleFrame = _frameAtTime(currentTimeMs);
    notifyListeners();
  }

  void resetPlayback() {
    if (frames.isEmpty) {
      return;
    }
    currentTimeMs = frames.first.timestampMs;
    currentSampleFrame = frames.first;
    isPlaying = false;
    smoothedScore = null;
    scoreLabel = poseDetectionSupported ? '--' : scoreLabel;
    notifyListeners();
  }

  void tick(int elapsedMs) {
    if (!isPlaying || frames.isEmpty || durationMs <= 0) {
      return;
    }

    final end = frames.last.timestampMs;
    final next = currentTimeMs + (elapsedMs * playbackSpeed).round();

    if (next >= end) {
      currentTimeMs = end;
      currentSampleFrame = frames.last;
      isPlaying = false;
    } else {
      currentTimeMs = next;
      currentSampleFrame = _frameAtTime(currentTimeMs);
    }

    notifyListeners();
  }

  List<String> _initialFeedback() {
    if (simulatorMode) {
      return ['Simulator: xem VRM + JSON animation. Chấm điểm cần iPhone thật.'];
    }
    if (!poseDetectionSupported) {
      return ['Chỉ hỗ trợ chấm điểm trên iOS/Android'];
    }
    return ['Đứng vào khung hình để bắt đầu kiểm tra'];
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
      );
      notifyListeners();
      return;
    }

    userDetected = true;
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
    );

    notifyListeners();
  }

  double get playbackProgress {
    if (frames.isEmpty || durationMs <= 0) {
      return 0;
    }
    return ((currentTimeMs - frames.first.timestampMs) / durationMs).clamp(0, 1);
  }

  PoseFrame _frameAtTime(int timeMs) {
    PoseFrame nearest = frames.first;
    var minDiff = (timeMs - nearest.timestampMs).abs();

    for (final frame in frames) {
      final diff = (timeMs - frame.timestampMs).abs();
      if (diff < minDiff) {
        minDiff = diff;
        nearest = frame;
      }
    }

    return nearest;
  }
}