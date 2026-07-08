class AppAssets {
  AppAssets._();

  static const String treePoseJson = 'assets/poses/tree_pose.json';
  static const String yogaAvatarVrm = 'assets/models/yoga_avatar.vrm';
  static const String vrmRendererHtml = 'assets/web/yoga_vrm_renderer.html';
  static const String vrmRendererJs = 'assets/web/yoga_vrm_renderer.js';

  /// Alias giữ tương thích code cũ.
  static const String defaultPoseJson = treePoseJson;

  static const String exerciseDisplayName = 'Tree Pose';

  /// Chunk size khi gửi VRM base64 sang WebView (ký tự).
  static const int vrmBase64ChunkSize = 256000;
}