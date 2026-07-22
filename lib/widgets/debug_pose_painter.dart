import 'package:flutter/material.dart';

class DebugPosePainter extends CustomPainter {
  DebugPosePainter({required this.points});

  final Map<String, Offset> points;

  static const _connections = <(String, String)>[
    ('leftEar', 'rightEar'),
    ('leftShoulder', 'rightShoulder'),
    ('leftShoulder', 'leftElbow'),
    ('leftElbow', 'leftWrist'),
    ('rightShoulder', 'rightElbow'),
    ('rightElbow', 'rightWrist'),
    ('leftShoulder', 'leftHip'),
    ('rightShoulder', 'rightHip'),
    ('leftHip', 'rightHip'),
    ('leftHip', 'leftKnee'),
    ('leftKnee', 'leftAnkle'),
    ('rightHip', 'rightKnee'),
    ('rightKnee', 'rightAnkle'),
    ('leftAnkle', 'leftHeel'),
    ('leftHeel', 'leftFootIndex'),
    ('rightAnkle', 'rightHeel'),
    ('rightHeel', 'rightFootIndex'),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = const Color(0xFF56D8FF).withValues(alpha: 0.85)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final pointPaint = Paint()
      ..color = const Color(0xFFFF5D8F)
      ..style = PaintingStyle.fill;

    for (final (fromName, toName) in _connections) {
      final from = points[fromName];
      final to = points[toName];
      if (from != null && to != null) {
        canvas.drawLine(from, to, linePaint);
      }
    }
    for (final point in points.values) {
      canvas.drawCircle(point, 5, pointPaint);
    }
  }

  @override
  bool shouldRepaint(covariant DebugPosePainter oldDelegate) =>
      oldDelegate.points != points;
}
