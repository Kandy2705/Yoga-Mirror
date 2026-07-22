import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:rive/rive.dart' as rive;

import '../models/pose_models.dart';
import '../services/pose_rig_driver.dart';
import 'debug_pose_painter.dart';
import 'leg_guide_painter.dart';

class MannequinStage extends StatefulWidget {
  const MannequinStage({
    super.key,
    required this.sequence,
    required this.positionMs,
    required this.showJsonOverlay,
    required this.showLegGuides,
    required this.mirror,
    required this.widthScale,
    required this.heightScale,
  });

  final PoseSequence sequence;
  final double positionMs;
  final bool showJsonOverlay;
  final bool showLegGuides;
  final bool mirror;
  final double widthScale;
  final double heightScale;

  @override
  State<MannequinStage> createState() => _MannequinStageState();
}

class _MannequinStageState extends State<MannequinStage> {
  rive.File? _file;
  rive.Artboard? _artboard;
  rive.BasicArtboardPainter? _painter;
  PoseRigDriver? _driver;
  ProjectedPose? _projectedPose;
  PoseSample? _currentSample;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _loadRive();
  }

  @override
  void didUpdateWidget(covariant MannequinStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.positionMs != widget.positionMs ||
        oldWidget.sequence != widget.sequence) {
      _applyCurrentPose();
    }
  }

  Future<void> _loadRive() async {
    try {
      final file = await rive.File.asset(
        'assets/rive/yoga_mannequin.riv',
        riveFactory: rive.Factory.rive,
      );
      final artboard = file?.defaultArtboard();
      if (file == null || artboard == null) {
        throw StateError('Không đọc được artboard YogaMannequin.');
      }
      final painter = rive.BasicArtboardPainter(
        fit: rive.Fit.contain,
        alignment: Alignment.center,
      );
      if (!mounted) {
        artboard.dispose();
        file.dispose();
        painter.dispose();
        return;
      }
      setState(() {
        _file = file;
        _artboard = artboard;
        _painter = painter;
        _driver = PoseRigDriver(artboard);
      });
      _applyCurrentPose();
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  void _applyCurrentPose() {
    final driver = _driver;
    if (driver == null) return;

    final sample = widget.sequence.sampleAt(widget.positionMs);
    final projected = driver.apply(sample);
    _currentSample = sample;
    _projectedPose = projected;
    _painter?.scheduleRepaint();

    if (mounted && (widget.showJsonOverlay || widget.showLegGuides)) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _painter?.dispose();
    _artboard?.dispose();
    _file?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Không tải được Rive mannequin:\n$_error',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    final artboard = _artboard;
    final painter = _painter;
    if (artboard == null || painter == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final frontLeg = inferFrontLeg(_currentSample);
    final stage = SizedBox(
      width: PoseRigDriver.artboardWidth,
      height: PoseRigDriver.artboardHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(
            child: CustomPaint(
              painter: _MannequinShadowPainter(
                points: _projectedPose?.points ?? const {},
              ),
            ),
          ),
          rive.RiveArtboardWidget(artboard: artboard, painter: painter),
          if (widget.showLegGuides)
            IgnorePointer(
              child: CustomPaint(
                painter: LegGuidePainter(
                  points: _projectedPose?.points ?? const {},
                  frontLeg: frontLeg,
                  mirror: widget.mirror,
                ),
              ),
            ),
          if (widget.showLegGuides)
            IgnorePointer(
              child: CustomPaint(
                painter: _ArmGuidePainter(
                  points: _projectedPose?.points ?? const {},
                  mirror: widget.mirror,
                ),
              ),
            ),
          if (widget.showJsonOverlay)
            IgnorePointer(
              child: CustomPaint(
                painter: DebugPosePainter(
                  points: _projectedPose?.points ?? const {},
                ),
              ),
            ),
          if (widget.showJsonOverlay)
            Positioned(
              top: 18,
              right: 18,
              child: Transform.scale(
                scaleX: widget.mirror ? -1 : 1,
                child: _JsonFrameBadge(pose: _projectedPose),
              ),
            ),
          if (widget.showLegGuides)
            Positioned(
              top: 18,
              left: 18,
              child: Transform.scale(
                scaleX: widget.mirror ? -1 : 1,
                child: _LegGuideBadge(frontLeg: frontLeg),
              ),
            ),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, _) {
        return Center(
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.diagonal3Values(
              (widget.mirror ? -1 : 1) * widget.widthScale,
              widget.heightScale,
              1,
            ),
            child: FittedBox(
              fit: BoxFit.contain,
              child: stage,
            ),
          ),
        );
      },
    );
  }
}

class _LegGuideBadge extends StatelessWidget {
  const _LegGuideBadge({required this.frontLeg});

  final FrontLeg frontLeg;

  @override
  Widget build(BuildContext context) {
    final frontText = switch (frontLeg) {
      FrontLeg.left => 'Chân trước: TRÁI',
      FrontLeg.right => 'Chân trước: PHẢI',
      FrontLeg.unknown => 'Chân trước: chưa xác định',
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xCC080D18),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Text(
          'Xanh = trái • Hồng = phải\n$frontText',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Colors.white70,
                height: 1.35,
              ),
        ),
      ),
    );
  }
}

class _JsonFrameBadge extends StatelessWidget {
  const _JsonFrameBadge({required this.pose});

  final ProjectedPose? pose;

  @override
  Widget build(BuildContext context) {
    final current = pose;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xCC080D18),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Text(
          current == null
              ? 'JSON đang tải…'
              : 'JSON ${current.timestampMs.round()} ms\n'
                  '${current.points.length} điểm • '
                  'vis ${(current.avgVisibility * 100).round()}%',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Colors.white70,
                height: 1.35,
              ),
        ),
      ),
    );
  }
}


class _ArmGuidePainter extends CustomPainter {
  const _ArmGuidePainter({required this.points, required this.mirror});

  final Map<String, Offset> points;
  final bool mirror;

  static const _leftColor = Color(0xFF5DD2FF);
  static const _rightColor = Color(0xFFFF6FA3);

  @override
  void paint(Canvas canvas, Size size) {
    _drawArm(canvas, 'left', _leftColor, 'TRÁI');
    _drawArm(canvas, 'right', _rightColor, 'PHẢI');
  }

  void _drawArm(Canvas canvas, String side, Color color, String label) {
    final shoulder = points['${side}Shoulder'];
    final elbow = points['${side}Elbow'];
    final wrist = points['${side}Wrist'];
    if (shoulder == null || elbow == null || wrist == null) return;

    final handTip = _averageExisting([
      points['${side}Index'],
      points['${side}Pinky'],
      points['${side}Thumb'],
    ]) ?? wrist;

    final glow = Paint()
      ..color = color.withValues(alpha: 0.24)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4)
      ..isAntiAlias = true;

    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    void drawSeg(Offset a, Offset b) {
      canvas.drawLine(a, b, glow);
      canvas.drawLine(a, b, line);
    }

    drawSeg(shoulder, elbow);
    drawSeg(elbow, wrist);
    drawSeg(wrist, handTip);

    _dot(canvas, shoulder, color);
    _dot(canvas, elbow, color);
    _dot(canvas, wrist, color);

    final labelAnchor = Offset.lerp(wrist, handTip, 0.72)!;
    _drawChip(canvas, labelAnchor.translate(side == 'left' ? -10 : 10, -10), label, color);
  }

  void _dot(Canvas canvas, Offset c, Color color) {
    canvas.drawCircle(
      c,
      7,
      Paint()
        ..color = color.withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3)
        ..isAntiAlias = true,
    );
    canvas.drawCircle(
      c,
      4,
      Paint()
        ..color = color
        ..isAntiAlias = true,
    );
  }

  void _drawChip(Canvas canvas, Offset center, String text, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final paddingX = 9.0;
    final paddingY = 5.0;
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: center,
        width: tp.width + paddingX * 2,
        height: tp.height + paddingY * 2,
      ),
      const Radius.circular(999),
    );

    canvas.drawRRect(
      rect,
      Paint()..color = color.withValues(alpha: 0.88),
    );
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
  }

  Offset? _averageExisting(List<Offset?> values) {
    final existing = values.whereType<Offset>().toList();
    if (existing.isEmpty) return null;
    return Offset(
      existing.map((e) => e.dx).reduce((a, b) => a + b) / existing.length,
      existing.map((e) => e.dy).reduce((a, b) => a + b) / existing.length,
    );
  }

  @override
  bool shouldRepaint(covariant _ArmGuidePainter oldDelegate) {
    return oldDelegate.points != points || oldDelegate.mirror != mirror;
  }
}



/// Đổ bóng mềm phía sau đầu, thân, tay và chân để các bộ phận tách khỏi nhau
/// rõ hơn khi cùng một màu, nhưng không tạo viền outline cứng.
class _MannequinShadowPainter extends CustomPainter {
  const _MannequinShadowPainter({required this.points});

  final Map<String, Offset> points;

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
    final torsoLength = math.max(1.0, (hipMid - shoulderMid).distance);
    final shoulderWidth = (leftShoulder - rightShoulder).distance;
    final hipWidth = (leftHip - rightHip).distance;
    final silhouetteBase =
        math.max(math.max(shoulderWidth, hipWidth), torsoLength * 0.42);
    final bodyScale = (silhouetteBase / 185).clamp(0.98, 1.55).toDouble();

    final shadowPaint = Paint()
      ..color = const Color(0x33000000)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8)
      ..isAntiAlias = true;

    final fillShadowPaint = Paint()
      ..color = const Color(0x18000000)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10)
      ..isAntiAlias = true;

    // Head / torso soft shadow
    _drawHeadShadow(canvas, shoulderMid, hipMid, shoulderWidth, torsoLength,
        fillShadowPaint, bodyScale);
    _drawTorsoShadow(canvas, leftShoulder, rightShoulder, leftHip, rightHip,
        fillShadowPaint, bodyScale);

    // Limbs
    _drawArm(canvas, 'left', bodyScale, shadowPaint);
    _drawArm(canvas, 'right', bodyScale, shadowPaint);
    _drawLeg(canvas, 'left', bodyScale, shadowPaint);
    _drawLeg(canvas, 'right', bodyScale, shadowPaint);
  }

  void _drawHeadShadow(
    Canvas canvas,
    Offset shoulderMid,
    Offset hipMid,
    double shoulderWidth,
    double torsoLength,
    Paint paint,
    double scale,
  ) {
    final torsoUp = shoulderMid - hipMid;
    final upLen = math.max(1.0, torsoUp.distance);
    final up = Offset(torsoUp.dx / upLen, torsoUp.dy / upLen);
    final headDiameter = math.max(shoulderWidth * 0.64, torsoLength * 0.285)
        .clamp(92.0, 170.0)
        .toDouble();
    final center = shoulderMid + up * (headDiameter * 0.60);
    final rect = Rect.fromCenter(
      center: center.translate(0, 8),
      width: headDiameter * 0.95,
      height: headDiameter * 1.02,
    );
    canvas.drawOval(rect, paint);
  }

  void _drawTorsoShadow(
    Canvas canvas,
    Offset leftShoulder,
    Offset rightShoulder,
    Offset leftHip,
    Offset rightHip,
    Paint paint,
    double scale,
  ) {
    final shoulderMid = _midpoint(leftShoulder, rightShoulder);
    final hipMid = _midpoint(leftHip, rightHip);
    final shoulderWidth = (leftShoulder - rightShoulder).distance;
    final hipWidth = (leftHip - rightHip).distance;
    final torsoLength = (hipMid - shoulderMid).distance;

    final path = Path();
    final topLeft = leftShoulder.translate(10 * scale, 8 * scale);
    final topRight = rightShoulder.translate(-10 * scale, 8 * scale);
    final bottomRight = rightHip.translate(-6 * scale, -6 * scale);
    final bottomLeft = leftHip.translate(6 * scale, -6 * scale);
    final topMid = _midpoint(topLeft, topRight).translate(0, -8 * scale);
    final bottomMid = _midpoint(bottomLeft, bottomRight).translate(0, 10 * scale);

    path.moveTo(topLeft.dx, topLeft.dy);
    path.quadraticBezierTo(topMid.dx, topMid.dy, topRight.dx, topRight.dy);
    path.quadraticBezierTo(
      shoulderMid.dx + shoulderWidth * 0.34,
      shoulderMid.dy + torsoLength * 0.52,
      bottomRight.dx,
      bottomRight.dy,
    );
    path.quadraticBezierTo(
      bottomMid.dx,
      bottomMid.dy,
      bottomLeft.dx,
      bottomLeft.dy,
    );
    path.quadraticBezierTo(
      shoulderMid.dx - shoulderWidth * 0.34,
      shoulderMid.dy + torsoLength * 0.52,
      topLeft.dx,
      topLeft.dy,
    );
    path.close();

    canvas.drawPath(path.shift(const Offset(0, 10)), paint);

    final pelvisRect = Rect.fromCenter(
      center: _midpoint(leftHip, rightHip).translate(0, 12),
      width: hipWidth * 1.12,
      height: torsoLength * 0.22,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(pelvisRect, Radius.circular(34 * scale)),
      paint,
    );
  }

  void _drawArm(Canvas canvas, String side, double scale, Paint paint) {
    final shoulder = points['${side}Shoulder'];
    final elbow = points['${side}Elbow'];
    final wrist = points['${side}Wrist'];
    if (shoulder == null || elbow == null || wrist == null) return;

    _drawShadowSegment(canvas, shoulder, elbow,
        thickness: 36 * scale, paint: paint);
    _drawShadowSegment(canvas, elbow, wrist,
        thickness: 29 * scale, paint: paint);

    final handTip = _averageExisting([
      points['${side}Index'],
      points['${side}Pinky'],
      points['${side}Thumb'],
    ]);
    if (handTip != null) {
      _drawFootOrHandShadow(
        canvas,
        anchor: wrist,
        tip: handTip,
        crossRadius: 18 * scale,
        paint: paint,
      );
    }
  }

  void _drawLeg(Canvas canvas, String side, double scale, Paint paint) {
    final hip = points['${side}Hip'];
    final knee = points['${side}Knee'];
    final ankle = points['${side}Ankle'];
    if (hip == null || knee == null || ankle == null) return;

    _drawShadowSegment(canvas, hip, knee,
        thickness: 44 * scale, paint: paint);
    _drawShadowSegment(canvas, knee, ankle,
        thickness: 35 * scale, paint: paint);

    final heel = points['${side}Heel'];
    final toe = points['${side}FootIndex'];
    if (heel != null || toe != null) {
      _drawFootOrHandShadow(
        canvas,
        anchor: ankle,
        tip: toe ?? heel!,
        back: heel,
        crossRadius: 20 * scale,
        paint: paint,
      );
    }
  }

  void _drawShadowSegment(
    Canvas canvas,
    Offset start,
    Offset end, {
    required double thickness,
    required Paint paint,
  }) {
    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..lineTo(end.dx, end.dy);
    final shadowPaint = Paint.from(paint)..strokeWidth = thickness;
    canvas.drawPath(path.shift(const Offset(2, 5)), shadowPaint);
  }

  void _drawFootOrHandShadow(
    Canvas canvas, {
    required Offset anchor,
    required Offset tip,
    Offset? back,
    required double crossRadius,
    required Paint paint,
  }) {
    final backPoint = back ?? anchor;
    final start = Offset.lerp(backPoint, anchor, 0.35)!;
    final axis = tip - start;
    final length = math.max(axis.distance, 1.0);
    final tangent = Offset(axis.dx / length, axis.dy / length);
    final normal = Offset(-tangent.dy, tangent.dx);

    final rearTop = start + normal * (crossRadius * 0.95);
    final rearBottom = start - normal * (crossRadius * 0.82);
    final midTop = anchor + normal * (crossRadius * 0.72);
    final midBottom = anchor - normal * (crossRadius * 0.64);
    final frontTop = tip + normal * (crossRadius * 0.55);
    final frontBottom = tip - normal * (crossRadius * 0.48);

    final path = Path()
      ..moveTo(rearTop.dx, rearTop.dy)
      ..quadraticBezierTo(midTop.dx, midTop.dy, frontTop.dx, frontTop.dy)
      ..quadraticBezierTo(
        tip.dx + tangent.dx * (crossRadius * 0.55),
        tip.dy + tangent.dy * (crossRadius * 0.10),
        frontBottom.dx,
        frontBottom.dy,
      )
      ..quadraticBezierTo(midBottom.dx, midBottom.dy, rearBottom.dx, rearBottom.dy)
      ..close();

    canvas.drawPath(path.shift(const Offset(2, 5)), paint);
  }

  Offset _midpoint(Offset a, Offset b) =>
      Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);

  Offset? _averageExisting(List<Offset?> values) {
    final existing = values.whereType<Offset>().toList();
    if (existing.isEmpty) return null;
    return Offset(
      existing.map((e) => e.dx).reduce((a, b) => a + b) / existing.length,
      existing.map((e) => e.dy).reduce((a, b) => a + b) / existing.length,
    );
  }

  @override
  bool shouldRepaint(covariant _MannequinShadowPainter oldDelegate) {
    return oldDelegate.points != points;
  }
}
