class AppAssets {
  AppAssets._();

  /// Legacy monolith path (not bundled by default — use [treePoseMeta]).
  static const String treePoseJson = 'assets/poses/tree_pose.json';

  /// Chunked pose manifest — load first chunk only at startup (fast).
  /// Rebuild: `npm run split:pose` (source: tools/tree_pose.source.json)
  static const String treePoseMeta = 'assets/poses/tree_pose/meta.json';

  /// Guide model — local Flutter asset only (no HTTPS / CDN).
  /// Prefer a single .vrm/.glb with meshes+textures embedded.
  static const String yogaAvatarVrm = 'assets/models/yoga_avatar.vrm';

  static const String vrmRendererHtml = 'assets/web/yoga_vrm_renderer.html';

  /// Offline esbuild bundle (three + three-vrm + kalidokit + renderer).
  /// Rebuild: `npm run build:renderer`
  static const String vrmRendererJs = 'assets/web/yoga_vrm_renderer.bundle.js';

  /// Source (not loaded at runtime). Edit this, then rebuild bundle.
  static const String vrmRendererJsSource = 'assets/web/yoga_vrm_renderer.js';

  /// Alias — default runtime path is chunked meta.
  static const String defaultPoseJson = treePoseMeta;

  static const String exerciseDisplayName = 'Tree Pose';

  /// Chunk size khi gửi VRM base64 sang WebView (ký tự).
  /// Larger = fewer bridge round-trips (main cost on iOS).
  static const int vrmBase64ChunkSize = 512000;
}