import 'dart:math' as math;
import 'dart:ui';

import 'package:rive/rive.dart' as rive;

import '../models/pose_models.dart';

class ProjectedPose {
  const ProjectedPose({
    required this.points,
    required this.avgVisibility,
    required this.timestampMs,
  });

  final Map<String, Offset> points;
  final double avgVisibility;
  final double timestampMs;
}

class PoseRigDriver {
  PoseRigDriver(this.artboard)
      : _components = {
          for (final name in _componentNames) name: artboard.component(name),
        };

  static const double artboardWidth = 720;
  static const double artboardHeight = 1280;
  static const double _targetPoseWidth = 610;
  static const double _targetPoseHeight = 1080;
  static const Offset _targetPoseCenter = Offset(360, 640);

  final rive.Artboard artboard;
  final Map<String, rive.Component?> _components;
  final Map<String, Offset> _smoothedPoints = <String, Offset>{};
  double? _lastTimestampMs;

  ProjectedPose apply(PoseSample sample) {
    final projected = _smooth(_project(sample));
    final p = projected.points;

    final leftShoulder = p['leftShoulder'];
    final rightShoulder = p['rightShoulder'];
    final leftHip = p['leftHip'];
    final rightHip = p['rightHip'];
    if (leftShoulder == null ||
        rightShoulder == null ||
        leftHip == null ||
        rightHip == null) {
      artboard.advance(0);
      return projected;
    }

    final shoulderMid = midpoint(leftShoulder, rightShoulder);
    final hipMid = midpoint(leftHip, rightHip);
    final shoulderWidth = (leftShoulder - rightShoulder).distance;
    final hipWidth = (leftHip - rightHip).distance;
    final torsoLength = math.max(1.0, (hipMid - shoulderMid).distance);

    final profileRatio = (shoulderWidth / torsoLength).clamp(0.0, 1.0).toDouble();
    final silhouetteBase = math.max(math.max(shoulderWidth, hipWidth), torsoLength * 0.42);
    final bodyThicknessScale = (silhouetteBase / 185).clamp(0.98, 1.55).toDouble();

    _setAxisPart(
      'torso',
      shoulderMid,
      hipMid,
      baseLength: 250,
      scaleX: (math.max(shoulderWidth, torsoLength * 0.44) / 176)
          .clamp(0.92, 1.75)
          .toDouble(),
      overlap: 36,
    );

    final pelvisWidth = math.max(hipWidth * 1.18, torsoLength * 0.36);
    _setPart(
      'pelvis',
      hipMid.translate(0, torsoLength * 0.04),
      rotation: _verticalRotation(shoulderMid, hipMid),
      scaleX: (pelvisWidth / 142).clamp(0.88, 1.65).toDouble(),
      scaleY: ((torsoLength * 0.31) / 86).clamp(0.7, 1.45).toDouble(),
    );

    _applyArm(
      side: 'left',
      shoulder: leftShoulder,
      elbow: p['leftElbow'],
      wrist: p['leftWrist'],
      handPoints: [p['leftIndex'], p['leftPinky'], p['leftThumb']],
      thicknessScale: bodyThicknessScale,
    );
    _applyArm(
      side: 'right',
      shoulder: rightShoulder,
      elbow: p['rightElbow'],
      wrist: p['rightWrist'],
      handPoints: [p['rightIndex'], p['rightPinky'], p['rightThumb']],
      thicknessScale: bodyThicknessScale,
    );

    _applyLeg(
      side: 'left',
      hip: leftHip,
      knee: p['leftKnee'],
      ankle: p['leftAnkle'],
      heel: p['leftHeel'],
      footIndex: p['leftFootIndex'],
      thicknessScale: bodyThicknessScale,
    );
    _applyLeg(
      side: 'right',
      hip: rightHip,
      knee: p['rightKnee'],
      ankle: p['rightAnkle'],
      heel: p['rightHeel'],
      footIndex: p['rightFootIndex'],
      thicknessScale: bodyThicknessScale,
    );

    _applyHeadNoNeck(
      points: p,
      shoulderMid: shoulderMid,
      hipMid: hipMid,
      shoulderWidth: shoulderWidth,
      torsoLength: torsoLength,
      profileRatio: profileRatio,
    );

    artboard.advance(0);
    return projected;
  }

  ProjectedPose _smooth(ProjectedPose raw) {
    final previousTimestamp = _lastTimestampMs;
    final mustReset = previousTimestamp == null ||
        raw.timestampMs < previousTimestamp ||
        (raw.timestampMs - previousTimestamp).abs() > 250;

    if (mustReset) {
      _smoothedPoints
        ..clear()
        ..addAll(raw.points);
      _lastTimestampMs = raw.timestampMs;
      return raw;
    }

    final elapsedMs = math.max(0.0, raw.timestampMs - previousTimestamp);
    final alpha = elapsedMs == 0
        ? 1.0
        : (1 - math.exp(-elapsedMs / 45)).clamp(0.12, 1.0).toDouble();

    for (final entry in raw.points.entries) {
      final previous = _smoothedPoints[entry.key];
      _smoothedPoints[entry.key] = previous == null
          ? entry.value
          : Offset.lerp(previous, entry.value, alpha)!;
    }
    _lastTimestampMs = raw.timestampMs;

    return ProjectedPose(
      points: Map<String, Offset>.unmodifiable(_smoothedPoints),
      avgVisibility: raw.avgVisibility,
      timestampMs: raw.timestampMs,
    );
  }

  ProjectedPose _project(PoseSample sample) {
    final landmarks = sample.landmarks.values
        .where((value) => value.visibility >= 0.12)
        .toList(growable: false);
    if (landmarks.isEmpty) {
      return ProjectedPose(
        points: const {},
        avgVisibility: sample.avgVisibility,
        timestampMs: sample.timestampMs,
      );
    }

    final sourcePoints = <String, Offset>{};
    for (final landmark in landmarks) {
      sourcePoints[landmark.name] = Offset(
        landmark.xNorm * sample.frameWidth,
        landmark.yNorm * sample.frameHeight,
      );
    }

    final xs = sourcePoints.values.map((point) => point.dx);
    final ys = sourcePoints.values.map((point) => point.dy);
    final minX = xs.reduce(math.min);
    final maxX = xs.reduce(math.max);
    final minY = ys.reduce(math.min);
    final maxY = ys.reduce(math.max);
    final sourceWidth = math.max(1.0, maxX - minX);
    final measuredHeight = math.max(1.0, maxY - minY);
    final proxyHeight = sample.bboxHeightNorm == null
        ? measuredHeight
        : sample.bboxHeightNorm! * sample.frameHeight;
    final sourceHeight = math.max(measuredHeight, proxyHeight);
    final pixelScale = math.min(
      _targetPoseWidth / sourceWidth,
      _targetPoseHeight / sourceHeight,
    );
    final sourceCenter = Offset((minX + maxX) / 2, (minY + maxY) / 2);

    final points = <String, Offset>{};
    for (final entry in sourcePoints.entries) {
      points[entry.key] = _targetPoseCenter + (entry.value - sourceCenter) * pixelScale;
    }

    return ProjectedPose(
      points: points,
      avgVisibility: sample.avgVisibility,
      timestampMs: sample.timestampMs,
    );
  }

  void _applyArm({
    required String side,
    required Offset shoulder,
    required Offset? elbow,
    required Offset? wrist,
    required List<Offset?> handPoints,
    required double thicknessScale,
  }) {
    if (elbow == null || wrist == null) return;

    _setAxisPart(
      '${side}_upper_arm',
      shoulder,
      elbow,
      baseLength: 100,
      scaleX: (thicknessScale * 0.98).clamp(0.98, 1.6).toDouble(),
      overlap: 20,
    );
    _setAxisPart(
      '${side}_forearm',
      elbow,
      wrist,
      baseLength: 100,
      scaleX: (thicknessScale * 0.92).clamp(0.94, 1.55).toDouble(),
      overlap: 18,
    );
    _setJoint('${side}_shoulder_joint', shoulder, thicknessScale * 1.06);
    _setJoint('${side}_elbow_joint', elbow, thicknessScale);
    _setJoint('${side}_wrist_joint', wrist, thicknessScale * 0.92);

    final validHandPoints = handPoints.whereType<Offset>().toList();
    final handTip = validHandPoints.isEmpty
        ? wrist.translate(0, 42)
        : Offset(
            validHandPoints.map((point) => point.dx).reduce((a, b) => a + b) /
                validHandPoints.length,
            validHandPoints.map((point) => point.dy).reduce((a, b) => a + b) /
                validHandPoints.length,
          );
    final length = math.max(54.0, (handTip - wrist).distance * 1.35);
    final center = midpoint(wrist, handTip);
    _setPart(
      '${side}_hand',
      center,
      rotation: _verticalRotation(wrist, handTip),
      scaleX: (thicknessScale * 0.95).clamp(0.88, 1.45).toDouble(),
      scaleY: (length / 64).clamp(0.82, 1.95).toDouble(),
    );
  }

  void _applyLeg({
    required String side,
    required Offset hip,
    required Offset? knee,
    required Offset? ankle,
    required Offset? heel,
    required Offset? footIndex,
    required double thicknessScale,
  }) {
    if (knee == null || ankle == null) return;

    _setAxisPart(
      '${side}_thigh',
      hip,
      knee,
      baseLength: 100,
      scaleX: (thicknessScale * 1.08).clamp(1.0, 1.75).toDouble(),
      overlap: 24,
    );
    _setAxisPart(
      '${side}_calf',
      knee,
      ankle,
      baseLength: 100,
      scaleX: (thicknessScale * 0.98).clamp(0.96, 1.65).toDouble(),
      overlap: 22,
    );
    _setJoint('${side}_hip_joint', hip, thicknessScale * 1.08);
    _setJoint('${side}_knee_joint', knee, thicknessScale);
    _setJoint('${side}_ankle_joint', ankle, thicknessScale * 0.9);

    final footStart = ankle;
    final footEnd = footIndex ?? heel ?? ankle.translate(42, 0);
    final vector = footEnd - footStart;
    final center = midpoint(footStart, footEnd).translate(0, 5);
    _setPart(
      '${side}_foot',
      center,
      rotation: math.atan2(vector.dy, vector.dx),
      scaleX: ((vector.distance + 32) / 78).clamp(0.95, 1.95).toDouble(),
      scaleY: (thicknessScale * 0.9).clamp(0.82, 1.4).toDouble(),
    );
  }

  void _applyHeadNoNeck({
    required Map<String, Offset> points,
    required Offset shoulderMid,
    required Offset hipMid,
    required double shoulderWidth,
    required double torsoLength,
    required double profileRatio,
  }) {
    final leftEar = points['leftEar'];
    final rightEar = points['rightEar'];
    final leftEye = points['leftEye'];
    final rightEye = points['rightEye'];
    final nose = points['nose'];

    final torsoUp = shoulderMid - hipMid;
    final torsoUpLength = math.max(1.0, torsoUp.distance);
    final up = Offset(torsoUp.dx / torsoUpLength, torsoUp.dy / torsoUpLength);
    final right = Offset(up.dy, -up.dx);

    final profileHeadBoost = 1 + (1 - profileRatio) * 0.18;
    final headDiameter = (math.max(shoulderWidth * 0.64, torsoLength * 0.285) * profileHeadBoost)
        .clamp(92.0, 170.0)
        .toDouble();

    final facePoints = <Offset>[
      if (nose != null) nose,
      if (leftEye != null) leftEye,
      if (rightEye != null) rightEye,
      if (leftEar != null) leftEar,
      if (rightEar != null) rightEar,
    ];

    double sidewaysShift = 0;
    if (facePoints.isNotEmpty) {
      final faceCenter = Offset(
        facePoints.map((point) => point.dx).reduce((a, b) => a + b) / facePoints.length,
        facePoints.map((point) => point.dy).reduce((a, b) => a + b) / facePoints.length,
      );
      final rawShift = (faceCenter - shoulderMid).dx;
      sidewaysShift = rawShift.clamp(-headDiameter * 0.12, headDiameter * 0.12) * 0.35;
    }

    final headCenter = shoulderMid +
        up * (headDiameter * (0.60 + (1 - profileRatio) * 0.03)) +
        right * sidewaysShift;

    _setPart(
      'head',
      headCenter,
      rotation: 0,
      scaleX: (headDiameter / 118).clamp(0.8, 1.5).toDouble(),
      scaleY: (headDiameter / 118).clamp(0.8, 1.5).toDouble(),
    );

    // Hide the neck so the head visually merges into the torso.
    _setPart(
      'neck',
      shoulderMid,
      rotation: 0,
      scaleX: 0.001,
      scaleY: 0.001,
    );
    _setPart(
      'neck_joint',
      shoulderMid,
      rotation: 0,
      scaleX: 0.001,
      scaleY: 0.001,
    );
  }

  void _setAxisPart(
    String name,
    Offset start,
    Offset end, {
    required double baseLength,
    required double scaleX,
    required double overlap,
  }) {
    final vector = end - start;
    _setPart(
      name,
      midpoint(start, end),
      rotation: _verticalRotation(start, end),
      scaleX: scaleX,
      scaleY: ((vector.distance + overlap) / baseLength).clamp(0.05, 4.0).toDouble(),
    );
  }

  void _setJoint(String name, Offset position, double scale) {
    _setPart(
      name,
      position,
      rotation: 0,
      scaleX: scale.clamp(0.72, 1.5).toDouble(),
      scaleY: scale.clamp(0.72, 1.5).toDouble(),
    );
  }

  void _setPart(
    String name,
    Offset position, {
    required double rotation,
    required double scaleX,
    required double scaleY,
  }) {
    final component = _components[name];
    if (component == null) return;
    component
      ..x = position.dx
      ..y = position.dy
      ..rotation = rotation
      ..scaleX = scaleX
      ..scaleY = scaleY;
  }

  double _verticalRotation(Offset start, Offset end) {
    final vector = end - start;
    return math.atan2(vector.dy, vector.dx) - math.pi / 2;
  }

  static Offset midpoint(Offset a, Offset b) => Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);

  static const _componentNames = <String>[
    'left_thigh',
    'right_thigh',
    'left_calf',
    'right_calf',
    'left_foot',
    'right_foot',
    'left_upper_arm',
    'right_upper_arm',
    'left_forearm',
    'right_forearm',
    'left_hand',
    'right_hand',
    'torso',
    'pelvis',
    'neck',
    'head',
    'left_shoulder_joint',
    'right_shoulder_joint',
    'left_elbow_joint',
    'right_elbow_joint',
    'left_wrist_joint',
    'right_wrist_joint',
    'left_hip_joint',
    'right_hip_joint',
    'left_knee_joint',
    'right_knee_joint',
    'left_ankle_joint',
    'right_ankle_joint',
    'neck_joint',
  ];
}
