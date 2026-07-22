import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/pose_models.dart';

enum FrontLeg { left, right, unknown }

FrontLeg inferFrontLeg(PoseSample? sample) {
  if (sample == null) return FrontLeg.unknown;

  final left = _legVisibility(sample, 'left');
  final right = _legVisibility(sample, 'right');
  if (left == null || right == null) return FrontLeg.unknown;

  // The corrected JSON uses visibility 0.15 for an occluded point.
  // A meaningful gap therefore tells us which leg is more likely in front.
  const minimumGap = 0.12;
  if ((left - right).abs() < minimumGap) return FrontLeg.unknown;
  return left > right ? FrontLeg.left : FrontLeg.right;
}

double? _legVisibility(PoseSample sample, String side) {
  final names = <String>[
    '${side}Hip',
    '${side}Knee',
    '${side}Ankle',
    '${side}Heel',
    '${side}FootIndex',
  ];
  final values = <double>[];
  for (final name in names) {
    final value = sample.landmarks[name];
    if (value != null) values.add(value.visibility);
  }
  if (values.isEmpty) return null;
  return values.reduce((a, b) => a + b) / values.length;
}

class LegGuidePainter extends CustomPainter {
  LegGuidePainter({
    required this.points,
    required this.frontLeg,
    required this.mirror,
  });

  final Map<String, Offset> points;
  final FrontLeg frontLeg;
  final bool mirror;

  static const _leftColor = Color(0xFF52D6FF);
  static const _rightColor = Color(0xFFFF6F9F);

  @override
  void paint(Canvas canvas, Size size) {
    _drawLeg(
      canvas,
      side: 'left',
      label: 'TRÁI',
      color: _leftColor,
      isFront: frontLeg == FrontLeg.left,
      isBack: frontLeg == FrontLeg.right,
    );
    _drawLeg(
      canvas,
      side: 'right',
      label: 'PHẢI',
      color: _rightColor,
      isFront: frontLeg == FrontLeg.right,
      isBack: frontLeg == FrontLeg.left,
    );
  }

  void _drawLeg(
    Canvas canvas, {
    required String side,
    required String label,
    required Color color,
    required bool isFront,
    required bool isBack,
  }) {
    final hip = points['${side}Hip'];
    final knee = points['${side}Knee'];
    final ankle = points['${side}Ankle'];
    final foot = points['${side}FootIndex'] ?? points['${side}Heel'];
    if (hip == null || knee == null || ankle == null) return;

    final pathPoints = <Offset>[hip, knee, ankle, if (foot != null) foot];
    final alpha = isBack ? 0.42 : 0.95;
    final width = isFront ? 8.0 : (isBack ? 4.0 : 5.5);

    if (isFront) {
      final halo = Paint()
        ..color = Colors.black.withValues(alpha: 0.34)
        ..strokeWidth = width + 5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      _drawPolyline(canvas, pathPoints, halo, dashed: false);
    }

    final paint = Paint()
      ..color = color.withValues(alpha: alpha)
      ..strokeWidth = width
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    _drawPolyline(canvas, pathPoints, paint, dashed: isBack);

    _drawLabel(canvas, ankle, label, color, isFront: isFront);
    if (isFront) {
      _drawFrontBadge(canvas, Offset.lerp(hip, knee, 0.52)!, color);
    }
  }

  void _drawPolyline(
    Canvas canvas,
    List<Offset> points,
    Paint paint, {
    required bool dashed,
  }) {
    for (var i = 0; i < points.length - 1; i++) {
      if (dashed) {
        _drawDashedLine(canvas, points[i], points[i + 1], paint);
      } else {
        canvas.drawLine(points[i], points[i + 1], paint);
      }
    }
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    final vector = end - start;
    final length = vector.distance;
    if (length <= 0.001) return;
    final direction = vector / length;
    const dash = 12.0;
    const gap = 8.0;
    var travelled = 0.0;
    while (travelled < length) {
      final dashEnd = math.min(travelled + dash, length);
      canvas.drawLine(
        start + direction * travelled,
        start + direction * dashEnd,
        paint,
      );
      travelled += dash + gap;
    }
  }

  void _drawLabel(
    Canvas canvas,
    Offset anchor,
    String text,
    Color color, {
    required bool isFront,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: isFront ? FontWeight.w900 : FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final paddingX = 8.0;
    final paddingY = 5.0;
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: anchor.translate(0, 25),
        width: painter.width + paddingX * 2,
        height: painter.height + paddingY * 2,
      ),
      const Radius.circular(10),
    );
    canvas.drawRRect(
      rect,
      Paint()..color = color.withValues(alpha: isFront ? 0.96 : 0.72),
    );

    _paintReadableText(
      canvas,
      painter,
      Offset(rect.left + paddingX, rect.top + paddingY),
      anchorX: rect.center.dx,
    );
  }

  void _drawFrontBadge(Canvas canvas, Offset anchor, Color color) {
    final painter = TextPainter(
      text: const TextSpan(
        text: 'TRƯỚC',
        style: TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final center = anchor.translate(34, 0);
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: center,
        width: painter.width + 18,
        height: painter.height + 10,
      ),
      const Radius.circular(10),
    );
    canvas.drawRRect(
      rect,
      Paint()..color = color.withValues(alpha: 0.98),
    );
    _paintReadableText(
      canvas,
      painter,
      Offset(rect.left + 9, rect.top + 5),
      anchorX: rect.center.dx,
    );
  }

  void _paintReadableText(
    Canvas canvas,
    TextPainter painter,
    Offset offset, {
    required double anchorX,
  }) {
    if (!mirror) {
      painter.paint(canvas, offset);
      return;
    }

    // The whole mannequin is mirrored outside this painter. Mirror the label
    // one more time around its own center so the letters remain readable.
    canvas.save();
    canvas.translate(anchorX, 0);
    canvas.scale(-1, 1);
    canvas.translate(-anchorX, 0);
    painter.paint(canvas, offset);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant LegGuidePainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.frontLeg != frontLeg ||
        oldDelegate.mirror != mirror;
  }
}
