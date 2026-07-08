import 'pose_frame.dart';

class PoseCapture {
  const PoseCapture({
    required this.schemaVersion,
    required this.frames,
    this.capture,
    this.device,
    this.captureParams,
  });

  final String? schemaVersion;
  final Map<String, dynamic>? capture;
  final Map<String, dynamic>? device;
  final Map<String, dynamic>? captureParams;
  final List<PoseFrame> frames;

  factory PoseCapture.fromJson(Map<String, dynamic> json) {
    final rawFrames = json['frames'] as List<dynamic>? ?? [];
    return PoseCapture(
      schemaVersion: json['schemaVersion'] as String?,
      capture: json['capture'] as Map<String, dynamic>?,
      device: json['device'] as Map<String, dynamic>?,
      captureParams: json['captureParams'] as Map<String, dynamic>?,
      frames: rawFrames
          .map((e) => PoseFrame.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  int get durationMs {
    if (frames.isEmpty) {
      return 0;
    }
    return frames.last.timestampMs - frames.first.timestampMs;
  }
}