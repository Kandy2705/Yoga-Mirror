import 'pose_landmark.dart';

class PoseFrame {
  const PoseFrame({
    required this.timestampMs,
    required this.frameWidth,
    required this.frameHeight,
    required this.personDetected,
    required this.landmarks,
    this.avgVisibility = 0,
    this.distanceProxy,
  });

  final int timestampMs;
  final double frameWidth;
  final double frameHeight;
  final bool personDetected;
  final double avgVisibility;
  final Map<String, dynamic>? distanceProxy;
  final List<PoseLandmark> landmarks;

  factory PoseFrame.fromJson(Map<String, dynamic> json) {
    final rawLandmarks = json['landmarks'] as List<dynamic>? ?? [];
    return PoseFrame(
      timestampMs: json['timestampMs'] as int,
      frameWidth: (json['frameWidth'] as num).toDouble(),
      frameHeight: (json['frameHeight'] as num).toDouble(),
      personDetected: json['personDetected'] as bool? ?? false,
      avgVisibility: (json['avgVisibility'] as num?)?.toDouble() ?? 0,
      distanceProxy: json['distanceProxy'] as Map<String, dynamic>?,
      landmarks: rawLandmarks
          .map((e) => PoseLandmark.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  PoseLandmark? landmarkByIndex(int index) {
    for (final landmark in landmarks) {
      if (landmark.index == index) {
        return landmark;
      }
    }
    return null;
  }

  PoseLandmark? landmarkByName(String name) {
    for (final landmark in landmarks) {
      if (landmark.name == name) {
        return landmark;
      }
    }
    return null;
  }
}