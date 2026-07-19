import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/pose_capture.dart';
import '../models/pose_chunk_meta.dart';
import '../models/pose_frame.dart';

class PoseJsonAssetLoader {
  
  Future<PoseCapture> load(String assetPath) async {
    final jsonString = await rootBundle.loadString(assetPath);
    return compute(_parsePoseCapture, jsonString);
  }

  
  Future<PoseChunkMeta> loadMeta(String metaAssetPath) async {
    final jsonString = await rootBundle.loadString(metaAssetPath);
    final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
    return PoseChunkMeta.fromJson(decoded);
  }

  
  Future<List<PoseFrame>> loadChunk(String chunkAssetPath) async {
    final jsonString = await rootBundle.loadString(chunkAssetPath);
    return compute(_parseChunkFrames, jsonString);
  }

  
  bool isChunkedMetaPath(String assetPath) {
    return assetPath.endsWith('meta.json') ||
        assetPath.contains('/meta.json');
  }
}


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


List<PoseFrame> _parseChunkFrames(String jsonString) {
  final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
  final raw = decoded['frames'] as List<dynamic>? ?? [];
  final frames = raw
      .map((e) => PoseFrame.fromJson(e as Map<String, dynamic>))
      .toList()
    ..sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
  return frames;
}
