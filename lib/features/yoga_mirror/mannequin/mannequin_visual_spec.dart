import 'package:flutter/material.dart';

/// Locked visual contract for the 2D vector mannequin guide.
///
/// Single-color smooth mannequin, no face features, no multi-color, no photo.
class MannequinVisualSpec {
  MannequinVisualSpec._();

  /// One solid body color for every part.
  static const Color bodyColor = Color(0xFFB8B0C8);

  static const double defaultOpacity = 0.78;

  /// No eyes / nose / mouth / hair.
  static const bool hasFaceFeatures = false;

  /// Soft limb length vs rest (avoid stretch/break look).
  static const double minLengthScale = 0.88;
  static const double maxLengthScale = 1.12;

  /// Figure height as fraction of short canvas side when fitted.
  static const double figureFill = 0.82;

  /// Thickness ratios relative to figure height.
  static const double headRadiusRatio = 0.065;
  static const double neckThicknessRatio = 0.028;
  static const double torsoWidthRatio = 0.14;
  static const double limbThicknessRatio = 0.038;
  static const double handRadiusRatio = 0.028;
  static const double footLengthRatio = 0.055;
  static const double footThicknessRatio = 0.028;
}

/// Controllable body segments (separate transforms).
enum MannequinPart {
  head,
  torso,
  leftUpperArm,
  leftForearm,
  leftHand,
  rightUpperArm,
  rightForearm,
  rightHand,
  leftThigh,
  leftShin,
  leftFoot,
  rightThigh,
  rightShin,
  rightFoot,
}
