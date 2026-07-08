import 'dart:convert';

import '../models/pose_frame.dart';

class PoseFrameSerializer {
  PoseFrameSerializer._();

  static String toJsonString(PoseFrame frame) {
    return jsonEncode(toMap(frame));
  }

  static Map<String, dynamic> toMap(PoseFrame frame) {
    return {
      'timestampMs': frame.timestampMs,
      'frameWidth': frame.frameWidth,
      'frameHeight': frame.frameHeight,
      'personDetected': frame.personDetected,
      'avgVisibility': frame.avgVisibility,
      'landmarks': frame.landmarks.map((lm) => lm.toJson()).toList(),
    };
  }
}