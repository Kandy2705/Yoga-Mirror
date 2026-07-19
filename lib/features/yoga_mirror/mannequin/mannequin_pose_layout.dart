import 'dart:math' as math;
import 'dart:ui';

import '../models/pose_frame.dart';
import '../models/pose_landmark.dart';
import 'mannequin_visual_spec.dart';

/// One drawable segment in canvas space after fit.
class MannequinSegment {
  const MannequinSegment({
    required this.part,
    required this.from,
    required this.to,
    this.isCircle = false,
    this.radius = 0,
  });

  final MannequinPart part;
  final Offset from;
  final Offset to;

  /// Head / joint ball use circle at [from] with [radius].
  final bool isCircle;
  final double radius;
}

/// Builds mannequin part geometry from a pose JSON frame (landmarks only).
///
/// Uses joint positions + segment angles. No skeleton overlay data —
/// output is only opaque body segments for painting.
class MannequinPoseLayout {
  MannequinPoseLayout._();

  // MediaPipe indices
  static const int _nose = 0;
  static const int _lShoulder = 11;
  static const int _rShoulder = 12;
  static const int _lElbow = 13;
  static const int _rElbow = 14;
  static const int _lWrist = 15;
  static const int _rWrist = 16;
  static const int _lIndex = 19;
  static const int _rIndex = 20;
  static const int _lHip = 23;
  static const int _rHip = 24;
  static const int _lKnee = 25;
  static const int _rKnee = 26;
  static const int _lAnkle = 27;
  static const int _rAnkle = 28;
  static const int _lFoot = 31;
  static const int _rFoot = 32;

  /// Rest proportions (unit figure) for soft length clamp.
  static const Map<MannequinPart, double> _restLen = {
    MannequinPart.leftUpperArm: 0.15,
    MannequinPart.leftForearm: 0.14,
    MannequinPart.rightUpperArm: 0.15,
    MannequinPart.rightForearm: 0.14,
    MannequinPart.leftThigh: 0.22,
    MannequinPart.leftShin: 0.22,
    MannequinPart.rightThigh: 0.22,
    MannequinPart.rightShin: 0.22,
  };

  static List<MannequinSegment> build(Size canvas, PoseFrame? frame) {
    if (frame == null || !frame.personDetected || frame.landmarks.isEmpty) {
      return _idleStand(canvas);
    }

    final raw = <int, Offset>{};
    for (final lm in frame.landmarks) {
      final p = _normPoint(lm);
      if (p != null) raw[lm.index] = p;
    }

    // Need core torso at minimum
    if (!_has(raw, _lShoulder) ||
        !_has(raw, _rShoulder) ||
        !_has(raw, _lHip) ||
        !_has(raw, _rHip)) {
      return _idleStand(canvas);
    }

    final fitted = _fitToCanvas(canvas, raw);
    if (fitted.isEmpty) return _idleStand(canvas);

    final figH = canvas.shortestSide * MannequinVisualSpec.figureFill;
    final headR = figH * MannequinVisualSpec.headRadiusRatio;

    Offset j(int i) => fitted[i]!;
    Offset? jOpt(int i) => fitted[i];

    final lSh = j(_lShoulder);
    final rSh = j(_rShoulder);
    final lHip = j(_lHip);
    final rHip = j(_rHip);
    final midSh = Offset((lSh.dx + rSh.dx) * 0.5, (lSh.dy + rSh.dy) * 0.5);
    final midHip = Offset((lHip.dx + rHip.dx) * 0.5, (lHip.dy + rHip.dy) * 0.5);

    final segments = <MannequinSegment>[];

    // Torso first (behind limbs in painter order — we sort later)
    segments.add(MannequinSegment(
      part: MannequinPart.torso,
      from: midSh,
      to: midHip,
    ));

    // Head: above mid-shoulder toward nose, or straight up
    final nose = jOpt(_nose);
    final headCenter = nose != null
        ? Offset(
            midSh.dx * 0.35 + nose.dx * 0.65,
            midSh.dy - headR * 1.15,
          )
        : Offset(midSh.dx, midSh.dy - headR * 1.35);
    // Soft pull head toward nose X if present
    final headPos = nose != null
        ? Offset(
            nose.dx * 0.55 + midSh.dx * 0.45,
            nose.dy * 0.7 + (midSh.dy - headR) * 0.3,
          )
        : headCenter;
    segments.add(MannequinSegment(
      part: MannequinPart.head,
      from: headPos,
      to: headPos,
      isCircle: true,
      radius: headR,
    ));

    void limb(
      MannequinPart upper,
      MannequinPart lower,
      MannequinPart? endPart,
      int a,
      int b,
      int c,
      int? d,
    ) {
      final pa = jOpt(a);
      final pb = jOpt(b);
      final pc = jOpt(c);
      if (pa == null || pb == null) return;

      final u = _softSegment(upper, pa, pb, figH);
      segments.add(u);

      if (pc != null) {
        segments.add(_softSegment(lower, u.to, pc, figH));
        final end = d != null ? jOpt(d) : null;
        if (endPart != null) {
          if (end != null) {
            segments.add(MannequinSegment(
              part: endPart,
              from: pc,
              to: end,
            ));
          } else {
            // Hand ball at wrist
            segments.add(MannequinSegment(
              part: endPart,
              from: pc,
              to: pc,
              isCircle: true,
              radius: figH * MannequinVisualSpec.handRadiusRatio,
            ));
          }
        }
      }
    }

    // Arms
    limb(
      MannequinPart.leftUpperArm,
      MannequinPart.leftForearm,
      MannequinPart.leftHand,
      _lShoulder,
      _lElbow,
      _lWrist,
      _lIndex,
    );
    limb(
      MannequinPart.rightUpperArm,
      MannequinPart.rightForearm,
      MannequinPart.rightHand,
      _rShoulder,
      _rElbow,
      _rWrist,
      _rIndex,
    );

    // Legs
    limb(
      MannequinPart.leftThigh,
      MannequinPart.leftShin,
      MannequinPart.leftFoot,
      _lHip,
      _lKnee,
      _lAnkle,
      _lFoot,
    );
    limb(
      MannequinPart.rightThigh,
      MannequinPart.rightShin,
      MannequinPart.rightFoot,
      _rHip,
      _rKnee,
      _rAnkle,
      _rFoot,
    );

    return segments;
  }

  static Offset? _normPoint(PoseLandmark lm) {
    final nx = lm.xNorm;
    final ny = lm.yNorm;
    if (nx == null || ny == null) return null;
    if (!nx.isFinite || !ny.isFinite) return null;
    return Offset(nx, ny);
  }

  static bool _has(Map<int, Offset> m, int i) => m.containsKey(i);

  /// Fit normalized landmarks into canvas, upright, centered, fill figureFill.
  static Map<int, Offset> _fitToCanvas(Size canvas, Map<int, Offset> raw) {
    double minX = 1e9, minY = 1e9, maxX = -1e9, maxY = -1e9;
    for (final p in raw.values) {
      minX = math.min(minX, p.dx);
      minY = math.min(minY, p.dy);
      maxX = math.max(maxX, p.dx);
      maxY = math.max(maxY, p.dy);
    }
    final bw = math.max(maxX - minX, 1e-4);
    final bh = math.max(maxY - minY, 1e-4);

    final targetH = canvas.shortestSide * MannequinVisualSpec.figureFill;
    final targetW = targetH * (bw / bh);
    final scale = math.min(targetH / bh, targetW / bw);

    final cx = canvas.width * 0.5;
    final cy = canvas.height * 0.5;
    final midX = (minX + maxX) * 0.5;
    final midY = (minY + maxY) * 0.5;

    final out = <int, Offset>{};
    for (final e in raw.entries) {
      final lx = (e.value.dx - midX) * scale + cx;
      final ly = (e.value.dy - midY) * scale + cy;
      out[e.key] = Offset(lx, ly);
    }
    return out;
  }

  static MannequinSegment _softSegment(
    MannequinPart part,
    Offset from,
    Offset to,
    double figH,
  ) {
    final rest = _restLen[part];
    if (rest == null) {
      return MannequinSegment(part: part, from: from, to: to);
    }
    final restPx = rest * figH;
    final delta = to - from;
    final dist = delta.distance;
    if (dist < 1e-4) {
      return MannequinSegment(part: part, from: from, to: to);
    }
    final minL = restPx * MannequinVisualSpec.minLengthScale;
    final maxL = restPx * MannequinVisualSpec.maxLengthScale;
    final clamped = dist.clamp(minL, maxL);
    final dir = delta / dist;
    return MannequinSegment(
      part: part,
      from: from,
      to: from + dir * clamped,
    );
  }

  /// Front-facing idle mannequin when no pose frame.
  static List<MannequinSegment> _idleStand(Size canvas) {
    final figH = canvas.shortestSide * MannequinVisualSpec.figureFill;
    final cx = canvas.width * 0.5;
    final top = (canvas.height - figH) * 0.5;

    final headR = figH * MannequinVisualSpec.headRadiusRatio;
    final headC = Offset(cx, top + headR);
    final midSh = Offset(cx, top + figH * 0.18);
    final midHip = Offset(cx, top + figH * 0.48);
    final shW = figH * 0.11;
    final hipW = figH * 0.07;

    final lSh = Offset(midSh.dx - shW, midSh.dy);
    final rSh = Offset(midSh.dx + shW, midSh.dy);
    final lHip = Offset(midHip.dx - hipW, midHip.dy);
    final rHip = Offset(midHip.dx + hipW, midHip.dy);

    final lElbow = Offset(lSh.dx - figH * 0.02, lSh.dy + figH * 0.14);
    final rElbow = Offset(rSh.dx + figH * 0.02, rSh.dy + figH * 0.14);
    final lWrist = Offset(lElbow.dx - figH * 0.01, lElbow.dy + figH * 0.13);
    final rWrist = Offset(rElbow.dx + figH * 0.01, rElbow.dy + figH * 0.13);
    final lKnee = Offset(lHip.dx, lHip.dy + figH * 0.2);
    final rKnee = Offset(rHip.dx, rHip.dy + figH * 0.2);
    final lAnkle = Offset(lKnee.dx, lKnee.dy + figH * 0.2);
    final rAnkle = Offset(rKnee.dx, rKnee.dy + figH * 0.2);
    final lFoot = Offset(lAnkle.dx - figH * 0.01, lAnkle.dy + figH * 0.02);
    final rFoot = Offset(rAnkle.dx + figH * 0.01, rAnkle.dy + figH * 0.02);

    return [
      MannequinSegment(
        part: MannequinPart.head,
        from: headC,
        to: headC,
        isCircle: true,
        radius: headR,
      ),
      MannequinSegment(part: MannequinPart.torso, from: midSh, to: midHip),
      MannequinSegment(
          part: MannequinPart.leftUpperArm, from: lSh, to: lElbow),
      MannequinSegment(
          part: MannequinPart.leftForearm, from: lElbow, to: lWrist),
      MannequinSegment(
        part: MannequinPart.leftHand,
        from: lWrist,
        to: lWrist,
        isCircle: true,
        radius: figH * MannequinVisualSpec.handRadiusRatio,
      ),
      MannequinSegment(
          part: MannequinPart.rightUpperArm, from: rSh, to: rElbow),
      MannequinSegment(
          part: MannequinPart.rightForearm, from: rElbow, to: rWrist),
      MannequinSegment(
        part: MannequinPart.rightHand,
        from: rWrist,
        to: rWrist,
        isCircle: true,
        radius: figH * MannequinVisualSpec.handRadiusRatio,
      ),
      MannequinSegment(part: MannequinPart.leftThigh, from: lHip, to: lKnee),
      MannequinSegment(part: MannequinPart.leftShin, from: lKnee, to: lAnkle),
      MannequinSegment(part: MannequinPart.leftFoot, from: lAnkle, to: lFoot),
      MannequinSegment(part: MannequinPart.rightThigh, from: rHip, to: rKnee),
      MannequinSegment(part: MannequinPart.rightShin, from: rKnee, to: rAnkle),
      MannequinSegment(part: MannequinPart.rightFoot, from: rAnkle, to: rFoot),
    ];
  }
}
