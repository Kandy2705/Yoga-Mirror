import 'package:flutter/material.dart';

import '../../../core/utils/angle_utils.dart';
import '../models/pose_frame.dart';

/// Điểm pose dùng nội bộ cho so khớp góc khớp.
class PoseMatchPoint {
  const PoseMatchPoint({required this.x, required this.y, this.visibility = 1});

  final double x;
  final double y;
  final double visibility;
}

class AngleMatchResult {
  const AngleMatchResult({
    required this.score,
    required this.angleDiffs,
  });

  final double score;
  final Map<String, double> angleDiffs;
}

class PoseMatchingService {
  static const double toleranceDegrees = 35;
  static const double minVisibility = 0.3;

  static const Map<String, List<int>> _angleJoints = {
    'leftElbow': [11, 13, 15],
    'rightElbow': [12, 14, 16],
    'leftShoulder': [13, 11, 23],
    'rightShoulder': [14, 12, 24],
    'leftHip': [11, 23, 25],
    'rightHip': [12, 24, 26],
    'leftKnee': [23, 25, 27],
    'rightKnee': [24, 26, 28],
  };

  AngleMatchResult compare({
    required PoseFrame sampleFrame,
    required Map<int, PoseMatchPoint> userLandmarks,
  }) {
    final samplePoints = _extractSamplePoints(sampleFrame);
    final diffs = <String, double>{};
    final scores = <double>[];

    _angleJoints.forEach((name, indices) {
      final sampleAngle = _angleFromIndices(samplePoints, indices);
      final userAngle = _angleFromIndices(userLandmarks, indices);

      if (sampleAngle == null || userAngle == null) {
        return;
      }

      final diff = (sampleAngle - userAngle).abs();
      diffs[name] = diff;
      final angleScore = (1 - diff / toleranceDegrees).clamp(0.0, 1.0);
      scores.add(angleScore);
    });

    if (scores.isEmpty) {
      return const AngleMatchResult(score: 0, angleDiffs: {});
    }

    final total = scores.reduce((a, b) => a + b) / scores.length;
    return AngleMatchResult(
      score: (total * 100).clamp(0, 100),
      angleDiffs: diffs,
    );
  }

  Map<int, PoseMatchPoint> _extractSamplePoints(PoseFrame frame) {
    final result = <int, PoseMatchPoint>{};
    for (final landmark in frame.landmarks) {
      result[landmark.index] = PoseMatchPoint(
        x: landmark.normalizedX(frame.frameWidth),
        y: landmark.normalizedY(frame.frameHeight),
        visibility: landmark.visibility,
      );
    }
    return result;
  }

  double? _angleFromIndices(Map<int, PoseMatchPoint> points, List<int> indices) {
    if (indices.length != 3) {
      return null;
    }

    final a = points[indices[0]];
    final b = points[indices[1]];
    final c = points[indices[2]];

    if (a == null || b == null || c == null) {
      return null;
    }

    if (a.visibility < minVisibility ||
        b.visibility < minVisibility ||
        c.visibility < minVisibility) {
      return null;
    }

    return calculateAngle(
      Offset(a.x, a.y),
      Offset(b.x, b.y),
      Offset(c.x, c.y),
    );
  }
}