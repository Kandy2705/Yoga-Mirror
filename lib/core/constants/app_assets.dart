class AppAssets {
  AppAssets._();

  static const String treePoseJson = 'assets/poses/tree_pose.json';

  /// Guide model — local Flutter asset only (no HTTPS / CDN).
  /// Prefer a single .vrm/.glb with meshes+textures embedded.
  static const String yogaAvatarVrm = 'assets/models/yoga_avatar.vrm';

  static const String vrmRendererHtml = 'assets/web/yoga_vrm_renderer.html';

  /// Offline esbuild bundle (three + three-vrm + kalidokit + renderer).
  /// Rebuild: `npm run build:renderer`
  static const String vrmRendererJs = 'assets/web/yoga_vrm_renderer.bundle.js';

  /// Source (not loaded at runtime). Edit this, then rebuild bundle.
  static const String vrmRendererJsSource = 'assets/web/yoga_vrm_renderer.js';

  /// Alias giữ tương thích code cũ.
  static const String defaultPoseJson = treePoseJson;

  static const String exerciseDisplayName = 'Tree Pose';

  /// Chunk size khi gửi VRM base64 sang WebView (ký tự).
  /// Larger = fewer bridge round-trips (main cost on iOS).
  static const int vrmBase64ChunkSize = 512000;
}