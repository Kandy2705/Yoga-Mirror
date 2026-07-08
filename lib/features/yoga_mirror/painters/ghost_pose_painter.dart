import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/pose_frame.dart';
import '../models/pose_landmark.dart';

class GhostPosePainter extends CustomPainter {
  GhostPosePainter({
    required this.sampleFrame,
    this.opacity = 0.3,
    this.showDebugSkeleton = false,
  });

  final PoseFrame? sampleFrame;
  final double opacity;
  final bool showDebugSkeleton;

  static const Set<int> _usedIndices = {
    0, 7, 8, 11, 12, 13, 14, 15, 16, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32,
  };

  @override
  void paint(Canvas canvas, Size size) {
    final frame = sampleFrame;
    if (frame == null || !frame.personDetected) {
      return;
    }

    final transform = _computeTransform(frame, size);
    final paint = Paint()
      ..color = const Color(0xFFE8D5FF).withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * 0.035
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 2);

    final fillPaint = Paint()
      ..color = Colors.white.withValues(alpha: opacity * 0.85)
      ..style = PaintingStyle.fill
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 3);

    Offset mapPoint(PoseLandmark? landmark) {
      if (landmark == null) {
        return Offset.zero;
      }
      final nx = landmark.normalizedX(frame.frameWidth);
      final ny = landmark.normalizedY(frame.frameHeight);
      return transform.map(nx, ny);
    }

    final nose = mapPoint(frame.landmarkByIndex(0));
    final leftEar = mapPoint(frame.landmarkByIndex(7));
    final rightEar = mapPoint(frame.landmarkByIndex(8));
    final leftShoulder = mapPoint(frame.landmarkByIndex(11));
    final rightShoulder = mapPoint(frame.landmarkByIndex(12));
    final leftElbow = mapPoint(frame.landmarkByIndex(13));
    final rightElbow = mapPoint(frame.landmarkByIndex(14));
    final leftWrist = mapPoint(frame.landmarkByIndex(15));
    final rightWrist = mapPoint(frame.landmarkByIndex(16));
    final leftHip = mapPoint(frame.landmarkByIndex(23));
    final rightHip = mapPoint(frame.landmarkByIndex(24));
    final leftKnee = mapPoint(frame.landmarkByIndex(25));
    final rightKnee = mapPoint(frame.landmarkByIndex(26));
    final leftAnkle = mapPoint(frame.landmarkByIndex(27));
    final rightAnkle = mapPoint(frame.landmarkByIndex(28));

    _drawHead(canvas, fillPaint, nose, leftEar, rightEar, size);
    _drawTorso(canvas, fillPaint, leftShoulder, rightShoulder, leftHip, rightHip);
    _drawLimb(canvas, paint, [leftShoulder, leftElbow, leftWrist]);
    _drawLimb(canvas, paint, [rightShoulder, rightElbow, rightWrist]);
    _drawLimb(canvas, paint, [leftHip, leftKnee, leftAnkle]);
    _drawLimb(canvas, paint, [rightHip, rightKnee, rightAnkle]);

    if (showDebugSkeleton) {
      _drawDebug(canvas, frame, transform);
    }
  }

  void _drawHead(
    Canvas canvas,
    Paint fillPaint,
    Offset nose,
    Offset leftEar,
    Offset rightEar,
    Size size,
  ) {
    final earDistance = (leftEar - rightEar).distance;
    final radius = earDistance > 4
        ? earDistance * 0.55
        : size.shortestSide * 0.04;
    final center = nose == Offset.zero
        ? Offset((leftEar.dx + rightEar.dx) / 2, (leftEar.dy + rightEar.dy) / 2)
        : nose;

    canvas.drawCircle(center, radius, fillPaint);
  }

  void _drawTorso(
    Canvas canvas,
    Paint fillPaint,
    Offset leftShoulder,
    Offset rightShoulder,
    Offset leftHip,
    Offset rightHip,
  ) {
    final shoulderCenter = Offset(
      (leftShoulder.dx + rightShoulder.dx) / 2,
      (leftShoulder.dy + rightShoulder.dy) / 2,
    );
    final hipCenter = Offset(
      (leftHip.dx + rightHip.dx) / 2,
      (leftHip.dy + rightHip.dy) / 2,
    );

    final shoulderWidth = (leftShoulder - rightShoulder).distance;
    final hipWidth = (leftHip - rightHip).distance;
    final topWidth = shoulderWidth * 0.9;
    final bottomWidth = hipWidth * 0.85;

    final path = Path()
      ..moveTo(shoulderCenter.dx - topWidth / 2, shoulderCenter.dy)
      ..lineTo(shoulderCenter.dx + topWidth / 2, shoulderCenter.dy)
      ..lineTo(hipCenter.dx + bottomWidth / 2, hipCenter.dy)
      ..lineTo(hipCenter.dx - bottomWidth / 2, hipCenter.dy)
      ..close();

    canvas.drawPath(path, fillPaint);
  }

  void _drawLimb(Canvas canvas, Paint paint, List<Offset> points) {
    if (points.any((p) => p == Offset.zero)) {
      return;
    }
    for (var i = 0; i < points.length - 1; i++) {
      canvas.drawLine(points[i], points[i + 1], paint);
    }
  }

  void _drawDebug(Canvas canvas, PoseFrame frame, _PoseTransform transform) {
    final debugPaint = Paint()
      ..color = Colors.red.withValues(alpha: 0.8)
      ..style = PaintingStyle.fill;

    for (final landmark in frame.landmarks) {
      if (!_usedIndices.contains(landmark.index)) {
        continue;
      }
      final point = transform.map(
        landmark.normalizedX(frame.frameWidth),
        landmark.normalizedY(frame.frameHeight),
      );
      canvas.drawCircle(point, 4, debugPaint);
    }
  }

  _PoseTransform _computeTransform(PoseFrame frame, Size size) {
    double minX = 1, maxX = 0, minY = 1, maxY = 0;
    var hasPoint = false;

    for (final landmark in frame.landmarks) {
      if (!_usedIndices.contains(landmark.index)) {
        continue;
      }
      final nx = landmark.normalizedX(frame.frameWidth);
      final ny = landmark.normalizedY(frame.frameHeight);
      minX = nx < minX ? nx : minX;
      maxX = nx > maxX ? nx : maxX;
      minY = ny < minY ? ny : minY;
      maxY = ny > maxY ? ny : maxY;
      hasPoint = true;
    }

    if (!hasPoint) {
      return _PoseTransform(scale: 1, offsetX: 0, offsetY: 0);
    }

    final bboxWidth = (maxX - minX).clamp(0.01, 1.0);
    final bboxHeight = (maxY - minY).clamp(0.01, 1.0);
    final targetHeight = size.height * 0.78;
    final targetWidth = size.width * 0.55;
    final scaleY = targetHeight / (bboxHeight * size.height);
    final scaleX = targetWidth / (bboxWidth * size.width);
    final scale = scaleY < scaleX ? scaleY : scaleX;

    final centerX = (minX + maxX) / 2;
    final centerY = (minY + maxY) / 2;

    return _PoseTransform(
      scale: scale,
      offsetX: size.width / 2 - centerX * scale * size.width,
      offsetY: size.height / 2 - centerY * scale * size.height,
      canvasWidth: size.width,
      canvasHeight: size.height,
    );
  }

  @override
  bool shouldRepaint(covariant GhostPosePainter oldDelegate) {
    return oldDelegate.sampleFrame != sampleFrame ||
        oldDelegate.opacity != opacity ||
        oldDelegate.showDebugSkeleton != showDebugSkeleton;
  }
}

class _PoseTransform {
  const _PoseTransform({
    required this.scale,
    required this.offsetX,
    required this.offsetY,
    this.canvasWidth = 1,
    this.canvasHeight = 1,
  });

  final double scale;
  final double offsetX;
  final double offsetY;
  final double canvasWidth;
  final double canvasHeight;

  Offset map(double nx, double ny) {
    return Offset(
      offsetX + nx * scale * canvasWidth,
      offsetY + ny * scale * canvasHeight,
    );
  }
}