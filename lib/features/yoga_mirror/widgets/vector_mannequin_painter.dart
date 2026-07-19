import 'package:flutter/material.dart';

import '../mannequin/mannequin_pose_layout.dart';
import '../mannequin/mannequin_visual_spec.dart';
import '../models/pose_frame.dart';

/// Paints a single-color vector mannequin from [MannequinPoseLayout] segments.
/// No skeleton lines, no landmark dots — body parts only.
class VectorMannequinPainter extends CustomPainter {
  VectorMannequinPainter({this.frame});

  final PoseFrame? frame;

  @override
  void paint(Canvas canvas, Size size) {
    final segments = MannequinPoseLayout.build(size, frame);
    final figH = size.shortestSide * MannequinVisualSpec.figureFill;
    final limbT = figH * MannequinVisualSpec.limbThicknessRatio;
    final torsoW = figH * MannequinVisualSpec.torsoWidthRatio;

    final paint = Paint()
      ..color = MannequinVisualSpec.bodyColor
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // Draw order: torso → legs → arms → head (head on top)
    final order = [
      MannequinPart.torso,
      MannequinPart.leftThigh,
      MannequinPart.rightThigh,
      MannequinPart.leftShin,
      MannequinPart.rightShin,
      MannequinPart.leftFoot,
      MannequinPart.rightFoot,
      MannequinPart.leftUpperArm,
      MannequinPart.rightUpperArm,
      MannequinPart.leftForearm,
      MannequinPart.rightForearm,
      MannequinPart.leftHand,
      MannequinPart.rightHand,
      MannequinPart.head,
    ];

    final byPart = <MannequinPart, MannequinSegment>{};
    for (final s in segments) {
      byPart[s.part] = s;
    }

    for (final part in order) {
      final s = byPart[part];
      if (s == null) continue;

      if (s.isCircle || part == MannequinPart.head) {
        final r = s.radius > 0
            ? s.radius
            : figH * MannequinVisualSpec.headRadiusRatio;
        canvas.drawCircle(s.from, r, paint);
        continue;
      }

      if (part == MannequinPart.torso) {
        _drawTorso(canvas, paint, s.from, s.to, torsoW);
        continue;
      }

      if (part == MannequinPart.leftFoot || part == MannequinPart.rightFoot) {
        _drawFoot(canvas, paint, s.from, s.to, figH);
        continue;
      }

      if (part == MannequinPart.leftHand || part == MannequinPart.rightHand) {
        final r = figH * MannequinVisualSpec.handRadiusRatio;
        canvas.drawCircle(s.to, r, paint);
        // Still draw a short forearm tip if segment has length
        if ((s.to - s.from).distance > r * 0.5) {
          _drawCapsule(canvas, paint, s.from, s.to, limbT * 0.75);
        }
        continue;
      }

      final thickness = switch (part) {
        MannequinPart.leftUpperArm ||
        MannequinPart.rightUpperArm ||
        MannequinPart.leftThigh ||
        MannequinPart.rightThigh =>
          limbT * 1.05,
        MannequinPart.leftForearm ||
        MannequinPart.rightForearm ||
        MannequinPart.leftShin ||
        MannequinPart.rightShin =>
          limbT * 0.9,
        _ => limbT,
      };
      _drawCapsule(canvas, paint, s.from, s.to, thickness);
      // Joint ball for smooth mannequin look (same color — not a landmark)
      canvas.drawCircle(s.from, thickness * 0.55, paint);
      canvas.drawCircle(s.to, thickness * 0.5, paint);
    }
  }

  void _drawTorso(
    Canvas canvas,
    Paint paint,
    Offset shoulderMid,
    Offset hipMid,
    double width,
  ) {
    final delta = hipMid - shoulderMid;
    final len = delta.distance;
    if (len < 1e-3) return;
    final dir = delta / len;
    final n = Offset(-dir.dy, dir.dx);
    final topW = width * 1.05;
    final botW = width * 0.92;
    final path = Path()
      ..moveTo(
        shoulderMid.dx + n.dx * topW * 0.5,
        shoulderMid.dy + n.dy * topW * 0.5,
      )
      ..lineTo(
        hipMid.dx + n.dx * botW * 0.5,
        hipMid.dy + n.dy * botW * 0.5,
      )
      ..lineTo(
        hipMid.dx - n.dx * botW * 0.5,
        hipMid.dy - n.dy * botW * 0.5,
      )
      ..lineTo(
        shoulderMid.dx - n.dx * topW * 0.5,
        shoulderMid.dy - n.dy * topW * 0.5,
      )
      ..close();
    canvas.drawPath(path, paint);
    // Soft shoulder / hip caps
    canvas.drawCircle(shoulderMid, topW * 0.42, paint);
    canvas.drawCircle(hipMid, botW * 0.4, paint);
  }

  void _drawFoot(
    Canvas canvas,
    Paint paint,
    Offset ankle,
    Offset toe,
    double figH,
  ) {
    final len = figH * MannequinVisualSpec.footLengthRatio;
    final thick = figH * MannequinVisualSpec.footThicknessRatio;
    final delta = toe - ankle;
    final dist = delta.distance;
    final dir = dist > 1e-3 ? delta / dist : const Offset(0, 1);
    final tip = ankle + dir * len;
    _drawCapsule(canvas, paint, ankle, tip, thick);
    canvas.drawCircle(ankle, thick * 0.55, paint);
  }

  void _drawCapsule(
    Canvas canvas,
    Paint paint,
    Offset a,
    Offset b,
    double thickness,
  ) {
    final d = b - a;
    final len = d.distance;
    if (len < 1e-3) {
      canvas.drawCircle(a, thickness * 0.5, paint);
      return;
    }
    final dir = d / len;
    final n = Offset(-dir.dy, dir.dx) * (thickness * 0.5);
    final path = Path()
      ..moveTo(a.dx + n.dx, a.dy + n.dy)
      ..lineTo(b.dx + n.dx, b.dy + n.dy)
      ..lineTo(b.dx - n.dx, b.dy - n.dy)
      ..lineTo(a.dx - n.dx, a.dy - n.dy)
      ..close();
    canvas.drawPath(path, paint);
    canvas.drawCircle(a, thickness * 0.5, paint);
    canvas.drawCircle(b, thickness * 0.5, paint);
  }

  @override
  bool shouldRepaint(covariant VectorMannequinPainter oldDelegate) {
    final a = oldDelegate.frame;
    final b = frame;
    if (identical(a, b)) return false;
    if (a == null || b == null) return a != b;
    return a.timestampMs != b.timestampMs;
  }
}
