import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/pose_capture.dart';
import '../models/pose_frame.dart';

class PoseJsonAssetLoader {
  Future<PoseCapture> load(String assetPath) async {
    final jsonString = await rootBundle.loadString(assetPath);
    final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
    final capture = PoseCapture.fromJson(decoded);

    final sortedFrames = List<PoseFrame>.from(capture.frames)
      ..sort((a, b) => a.timestampMs.compareTo(b.timestampMs));

    return PoseCapture(
      schemaVersion: capture.schemaVersion,
      capture: capture.capture,
      device: capture.device,
      captureParams: capture.captureParams,
      frames: sortedFrames,
    );
  }
}