import 'package:camera/camera.dart';

import 'pose_matching_service.dart';

/// Kết quả pose người dùng detect — dùng nội bộ, không vẽ lên UI.
class UserPoseResult {
  const UserPoseResult({required this.landmarks});

  final Map<int, PoseMatchPoint> landmarks;
}

/// Xử lý frame camera → pose landmarks (ML Kit trên device, stub trên simulator).
abstract class PoseStreamProcessor {
  Future<void> initialize();
  Future<UserPoseResult?> process(CameraImage image, CameraController camera);
  Future<void> dispose();
}