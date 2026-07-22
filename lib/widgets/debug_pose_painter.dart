import 'package:flutter/material.dart';

class DebugPosePainter extends CustomPainter {
  DebugPosePainter({
    required this.points,
    this.keypointColors = const {},
  });

  final Map<String, Offset> points;
  final Map<String, Color> keypointColors;

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

  static Color colorFromHex(String source) {
    var value = source.trim().replaceFirst('#', '');
    if (value.length == 6) {
      value = 'FF$value';
    }
    if (value.length != 8) {
      throw FormatException('Ma mau khong hop le: $source');
    }
    return Color(int.parse(value, radix: 16));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = const Color(0xFF56D8FF).withValues(alpha: 0.85)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final defaultPointPaint = Paint()
      ..color = const Color(0xFFFF5D8F)
      ..style = PaintingStyle.fill;

    for (final (fromName, toName) in _connections) {
      final from = points[fromName];
      final to = points[toName];
      if (from != null && to != null) {
        canvas.drawLine(from, to, linePaint);
      }
    }

    for (final entry in points.entries) {
      final color = keypointColors[entry.key];
      if (color != null) {
        final paint = Paint()
          ..color = color
          ..style = PaintingStyle.fill;
        canvas.drawCircle(entry.value, 6, paint);
      } else {
        canvas.drawCircle(entry.value, 5, defaultPointPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant DebugPosePainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.keypointColors != keypointColors;
}
