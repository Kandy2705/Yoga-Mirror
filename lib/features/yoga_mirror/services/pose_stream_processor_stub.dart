import 'package:camera/camera.dart';

import 'pose_stream_processor.dart';

/// Simulator / Web — không có ML Kit.
class PoseStreamProcessorStub implements PoseStreamProcessor {
  @override
  Future<void> initialize() async {}

  @override
  Future<UserPoseResult?> process(
    CameraImage image,
    CameraController camera,
  ) async =>
      null;

  @override
  Future<void> dispose() async {}
}