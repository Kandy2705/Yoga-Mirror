import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/pose_capture.dart';
import '../models/pose_frame.dart';

class PoseJsonAssetLoader {
  /// Load pose JSON from Flutter assets.
  /// Parse runs in a background isolate so the UI/camera can start sooner.
  Future<PoseCapture> load(String assetPath) async {
    final jsonString = await rootBundle.loadString(assetPath);
    // 15MB+ JSON: isolate keeps main isolate responsive (camera/WebView).
    return compute(_parsePoseCapture, jsonString);
  }
}

/// Top-level for [compute].
PoseCapture _parsePoseCapture(String jsonString) {
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
