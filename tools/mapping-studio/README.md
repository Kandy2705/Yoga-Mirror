# YogaMirror Mapping Studio

Developer-only Vite tool for calibrating VRM humanoid bones against YogaMirror MediaPipe pose JSON.

## Run

From the repository root:

```bash
cd tools/mapping-studio
npm install
npm run dev
```

Open the Vite URL. The tool loads the local YogaMirror avatar from `/Assets/models/yoga_avatar.vrm` and the default chunked pose manifest from `/Assets/poses/sapiens2_to_mediapipe_video_3_with_z/meta.json`.

## Features

- VRM preview using Three.js r160 and `@pixiv/three-vrm` 2.x.
- Clear humanoid bone labels driven by `vrm.humanoid.getNormalizedBoneNode(...)`.
- MediaPipe JSON skeleton preview with 33 landmarks and pose connections.
- View modes: VRM only, JSON skeleton only, and both overlay.
- Click a VRM bone label or list item, then click a MediaPipe landmark label or list item to map it.
- Playback controls: play/pause, timeline scrubber by frame timestamp, and speed.
- Retarget preview applies rotations only. It tries `Kalidokit.Pose.solve` when `wx/wy/wz` world landmarks are present and falls back to planar direction chains when world coordinates are unavailable.
- Debug panel shows world/debug values for shoulders, hips, ankles, shoulder delta, guide yaw, and retarget mode.
- Export panel downloads mapping JSON and copies a paste-ready `BONE_LANDMARK_MAP` snippet for `Assets/web/yoga_vrm_renderer.js`.

## Loading pose JSON

Supported inputs:

1. Monolith schema 2.0 JSON containing `frames[]`.
2. Chunk files containing `frames[]` selected together via the file picker or drag/drop.
3. Repo asset manifest paths, e.g. `Assets/poses/sapiens2_to_mediapipe_video_3_with_z/meta.json`, loaded by the path field.

The app intentionally lives under `tools/mapping-studio/` and does not alter the Flutter runtime.
