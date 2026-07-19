import 'package:flutter/material.dart';

import '../mannequin/mannequin_visual_spec.dart';
import '../models/pose_frame.dart';
import 'vector_mannequin_painter.dart';

/// Full-screen guide: in-project 2D vector mannequin driven by pose JSON.
///
/// No Rive/designer asset required. No skeleton/landmark debug drawing.
class MannequinGuideOverlay extends StatelessWidget {
  const MannequinGuideOverlay({
    super.key,
    this.frame,
    this.opacity = MannequinVisualSpec.defaultOpacity,
    this.scale = 1.0,
    this.yOffset = 0.0,
    this.isPlaying = false,
  });

  final PoseFrame? frame;
  final double opacity;
  final double scale;
  final double yOffset;

  /// Reserved for future blend / interp; layout already snaps per frame.
  final bool isPlaying;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Opacity(
        opacity: opacity.clamp(0.1, 1.0),
        child: Transform.translate(
          offset: Offset(0, yOffset),
          child: Transform.scale(
            scale: scale.clamp(0.2, 2.5),
            alignment: Alignment.center,
            child: CustomPaint(
              painter: VectorMannequinPainter(frame: frame),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
  }
}
