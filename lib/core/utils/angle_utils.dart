import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Góc tại điểm [b] (độ), từ vector ba→b và c→b.
double calculateAngle(Offset a, Offset b, Offset c) {
  final ba = Offset(a.dx - b.dx, a.dy - b.dy);
  final bc = Offset(c.dx - b.dx, c.dy - b.dy);

  final dot = ba.dx * bc.dx + ba.dy * bc.dy;
  final magBa = math.sqrt(ba.dx * ba.dx + ba.dy * ba.dy);
  final magBc = math.sqrt(bc.dx * bc.dx + bc.dy * bc.dy);

  if (magBa == 0 || magBc == 0) {
    return 0;
  }

  final cosAngle = (dot / (magBa * magBc)).clamp(-1.0, 1.0);
  return math.acos(cosAngle) * 180 / math.pi;
}