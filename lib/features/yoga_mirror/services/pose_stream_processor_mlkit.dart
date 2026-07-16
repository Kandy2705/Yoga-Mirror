import 'package:camera/camera.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../../../core/utils/camera_input_image.dart';
import 'pose_matching_service.dart';
import 'pose_stream_processor.dart';

/// Device iOS/Android — pose detection thật bằng ML Kit.
class PoseStreamProcessorMlKit implements PoseStreamProcessor {
  PoseDetector? _detector;

  @override
  Future<void> initialize() async {
    _detector ??= PoseDetector(
      options: PoseDetectorOptions(
        model: PoseDetectionModel.base,
        mode: PoseDetectionMode.stream,
      ),
    );
  }

  @override
  Future<UserPoseResult?> process(
    CameraImage image,
    CameraController camera,
  ) async {
    final detector = _detector;
    if (detector == null) return null;

    final inputImage = cameraImageToInputImage(
      image: image,
      camera: camera.description,
      deviceOrientation: camera.value.deviceOrientation,
    );
    if (inputImage == null) return null;

    final poses = await detector.processImage(inputImage);
    if (poses.isEmpty) return null;

    final landmarks = <int, PoseMatchPoint>{};
    poses.first.landmarks.forEach((type, landmark) {
      landmarks[type.index] = PoseMatchPoint(
        x: landmark.x,
        y: landmark.y,
        visibility: landmark.likelihood,
      );
    });
    return UserPoseResult(landmarks: landmarks);
  }

  @override
  Future<void> dispose() async {
    await _detector?.close();
    _detector = null;
  }
}
