import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

class MannequinOutlinePainter extends CustomPainter {
  const MannequinOutlinePainter({
    required this.points,
    this.outlineWidth = 7,
  });

  final Map<String, Offset> points;
  final double outlineWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final leftShoulder = points['leftShoulder'];
    final rightShoulder = points['rightShoulder'];
    final leftHip = points['leftHip'];
    final rightHip = points['rightHip'];

    if (leftShoulder == null ||
        rightShoulder == null ||
        leftHip == null ||
        rightHip == null) {
      return;
    }

    final shoulderMid = _midpoint(leftShoulder, rightShoulder);
    final hipMid = _midpoint(leftHip, rightHip);
    final shoulderWidth = (leftShoulder - rightShoulder).distance;
    final hipWidth = (leftHip - rightHip).distance;
    final torsoLength = math.max(1.0, (hipMid - shoulderMid).distance);
    final profileRatio =
        (shoulderWidth / torsoLength).clamp(0.0, 1.0).toDouble();
    final silhouetteBase =
        math.max(math.max(shoulderWidth, hipWidth), torsoLength * 0.42);
    final bodyScale = (silhouetteBase / 185).clamp(0.98, 1.55).toDouble();

    final paint = Paint()
      ..color = const Color(0xF5000000)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    // Tay và chân vẽ trước để toàn bộ lớp đen phía sau hợp thành một silhouette.
    _drawArm(canvas, paint, 'left', bodyScale);
    _drawArm(canvas, paint, 'right', bodyScale);
    _drawLeg(canvas, paint, 'left', bodyScale);
    _drawLeg(canvas, paint, 'right', bodyScale);

    final torsoVisualWidth = math.max(shoulderWidth, torsoLength * 0.44);
    _drawSegment(
      canvas,
      paint,
      shoulderMid,
      hipMid,
      torsoVisualWidth + outlineWidth * 2,
    );

    final pelvisWidth = math.max(hipWidth * 1.18, torsoLength * 0.36);
    final pelvisHeight = torsoLength * 0.31;
    final pelvisCenter = hipMid.translate(0, torsoLength * 0.04);
    canvas.drawOval(
      Rect.fromCenter(
        center: pelvisCenter,
        width: pelvisWidth + outlineWidth * 2,
        height: pelvisHeight + outlineWidth * 2,
      ),
      Paint()
        ..color = const Color(0xF5000000)
        ..style = PaintingStyle.fill
        ..isAntiAlias = true,
    );

    _drawHead(
      canvas,
      shoulderMid: shoulderMid,
      hipMid: hipMid,
      shoulderWidth: shoulderWidth,
      torsoLength: torsoLength,
      profileRatio: profileRatio,
    );
  }

  void _drawArm(Canvas canvas, Paint paint, String side, double bodyScale) {
    final shoulder = points['${side}Shoulder'];
    final elbow = points['${side}Elbow'];
    final wrist = points['${side}Wrist'];
    if (shoulder == null || elbow == null || wrist == null) return;

    _drawSegment(
      canvas,
      paint,
      shoulder,
      elbow,
      39 * bodyScale + outlineWidth * 2,
    );
    _drawSegment(
      canvas,
      paint,
      elbow,
      wrist,
      34 * bodyScale + outlineWidth * 2,
    );

    final handCandidates = <Offset>[];
    final index = points['${side}Index'];
    final pinky = points['${side}Pinky'];
    final thumb = points['${side}Thumb'];
    if (index != null) handCandidates.add(index);
    if (pinky != null) handCandidates.add(pinky);
    if (thumb != null) handCandidates.add(thumb);
    final handTip = handCandidates.isEmpty
        ? wrist.translate(0, 42)
        : Offset(
            handCandidates.map((point) => point.dx).reduce((a, b) => a + b) /
                handCandidates.length,
            handCandidates.map((point) => point.dy).reduce((a, b) => a + b) /
                handCandidates.length,
          );

    _drawSegment(
      canvas,
      paint,
      wrist,
      handTip,
      32 * bodyScale + outlineWidth * 2,
    );
  }

  void _drawLeg(Canvas canvas, Paint paint, String side, double bodyScale) {
    final hip = points['${side}Hip'];
    final knee = points['${side}Knee'];
    final ankle = points['${side}Ankle'];
    if (hip == null || knee == null || ankle == null) return;

    _drawSegment(
      canvas,
      paint,
      hip,
      knee,
      51 * bodyScale + outlineWidth * 2,
    );
    _drawSegment(
      canvas,
      paint,
      knee,
      ankle,
      43 * bodyScale + outlineWidth * 2,
    );

    final footEnd =
        points['${side}FootIndex'] ?? points['${side}Heel'] ?? ankle.translate(42, 0);
    _drawSegment(
      canvas,
      paint,
      ankle,
      footEnd,
      30 * bodyScale + outlineWidth * 2,
    );
  }

  void _drawHead(
    Canvas canvas, {
    required Offset shoulderMid,
    required Offset hipMid,
    required double shoulderWidth,
    required double torsoLength,
    required double profileRatio,
  }) {
    final torsoUp = shoulderMid - hipMid;
    final torsoUpLength = math.max(1.0, torsoUp.distance);
    final up = Offset(torsoUp.dx / torsoUpLength, torsoUp.dy / torsoUpLength);
    final right = Offset(up.dy, -up.dx);

    final profileHeadBoost = 1 + (1 - profileRatio) * 0.18;
    final headDiameter =
        (math.max(shoulderWidth * 0.64, torsoLength * 0.285) *
                profileHeadBoost)
            .clamp(92.0, 170.0)
            .toDouble();

    final facePoints = <Offset>[];
    for (final name in const [
      'nose',
      'leftEye',
      'rightEye',
      'leftEar',
      'rightEar',
    ]) {
      final point = points[name];
      if (point != null) facePoints.add(point);
    }

    double sidewaysShift = 0;
    if (facePoints.isNotEmpty) {
      final faceCenter = Offset(
        facePoints.map((point) => point.dx).reduce((a, b) => a + b) /
            facePoints.length,
        facePoints.map((point) => point.dy).reduce((a, b) => a + b) /
            facePoints.length,
      );
      final rawShift = (faceCenter - shoulderMid).dx;
      sidewaysShift =
          rawShift.clamp(-headDiameter * 0.12, headDiameter * 0.12) * 0.35;
    }

    final headCenter = shoulderMid +
        up * (headDiameter * (0.60 + (1 - profileRatio) * 0.03)) +
        right * sidewaysShift;

    canvas.drawCircle(
      headCenter,
      headDiameter / 2 + outlineWidth,
      Paint()
        ..color = const Color(0xF5000000)
        ..style = PaintingStyle.fill
        ..isAntiAlias = true,
    );
  }

  void _drawSegment(
    Canvas canvas,
    Paint paint,
    Offset start,
    Offset end,
    double width,
  ) {
    paint.strokeWidth = width;
    canvas.drawLine(start, end, paint);
  }

  Offset _midpoint(Offset a, Offset b) {
    return Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
  }

  @override
  bool shouldRepaint(covariant MannequinOutlinePainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.outlineWidth != outlineWidth;
  }
}
