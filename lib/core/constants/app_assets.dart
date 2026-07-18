class AppAssets {
  AppAssets._();

  /// Legacy monolith path (not bundled by default — use [defaultPoseMeta]).
  static const String treePoseJson = 'assets/poses/tree_pose.json';

  /// Chunked tree pose (optional).
  static const String treePoseMeta = 'assets/poses/tree_pose/meta.json';

  /// Default guide motion: part_3 video → MediaPipe Pose Landmarker (full).
  static const String defaultPoseMeta =
      'assets/poses/part_3_sapiens_pose/meta.json';

  /// Other chunked poses (optional switch).
  static const String mediaPipeVideo1Meta =
      'assets/poses/MediaPipe-video1/meta.json';
  static const String sapiens2PoseMeta =
      'assets/poses/sapiens2_to_mediapipe_video_3/meta.json';

  /// Guide model — local Flutter asset only (no HTTPS / CDN).
  static const String yogaAvatarVrm = 'assets/models/yoga_avatar.vrm';

  static const String vrmRendererHtml = 'assets/web/yoga_vrm_renderer.html';

  /// Offline esbuild bundle (three + three-vrm + kalidokit + renderer).
  /// Rebuild: `npm run build:renderer`
  static const String vrmRendererJs = 'assets/web/yoga_vrm_renderer.bundle.js';

  /// Source (not loaded at runtime). Edit this, then rebuild bundle.
  static const String vrmRendererJsSource = 'assets/web/yoga_vrm_renderer.js';

  /// Hidden WebView: Kalidokit Pose.solve only (no VRM render).
  static const String kalidokitSolverHtml = 'assets/web/kalidokit_solver.html';

  /// Offline Kalidokit UMD (inject vào solver HTML — không CDN).
  static const String kalidokitUmdJs = 'assets/web/kalidokit.umd.js';

  /// Alias — default runtime path is chunked meta.
  static const String defaultPoseJson = defaultPoseMeta;

  static const String exerciseDisplayName = 'Part 3 Sapiens Pose';

  /// Chunk size khi gửi VRM base64 sang WebView (ký tự).
  /// Larger = fewer bridge round-trips (main cost on iOS).
  static const int vrmBase64ChunkSize = 512000;
}
