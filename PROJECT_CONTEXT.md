# YogaMirror — Project Context

## Tên dự án
- **Display name:** YogaMirror
- **Flutter package:** `yoga_mirror`
- **Màn hình chính:** `YogaMirrorDemoScreen`

## Mục tiêu demo
Một màn hình demo cho khách hàng: camera live + **3D VRM model** làm lớp hướng dẫn, chuyển động theo MediaPipe JSON, có tính điểm khớp tư thế thật trên iOS/Android.

## Yêu cầu khách hàng (đã chốt)
- **Guide layer = 3D VRM model** (`assets/models/yoga_avatar.vrm`)
- **MediaPipe JSON** (`assets/poses/tree_pose.json`) là **nguồn motion duy nhất**
- **Không** dùng skeleton 2D / ghost line overlay
- **Không** dùng animation có sẵn trong VRM để thay JSON
- **Không** hiện landmark/chấm xương/skeleton cho người dùng

## Kiến trúc render VRM
Flutter giữ UI chính (camera, score, feedback, controls).

**VRM render qua WebView** (Three.js + @pixiv/three-vrm), không dùng `flutter_3d_controller`:
```
Flutter                          WebView (Three.js)
────────                         ──────────────────
PoseJsonAssetLoader              yoga_vrm_renderer.html/js
YogaMirrorController  ──JS──►   loadVrmFromBase64 (chunked)
current PoseFrame     ──JS──►   applyPoseFrame(frameJson)
                                 Kalidokit (optional) + custom bone solver
```

### Load VRM an toàn trên iOS WebView
Flutter `rootBundle.load()` → base64 → gửi theo **chunk** (~256KB) sang JS:
- `window.beginVrmBase64Load()`
- `window.appendVrmBase64Chunk(chunk)`
- `window.finishVrmBase64Load()`

Tránh fetch trực tiếp `assets/models/...` trong WebView (path/CORS issues).

## Package chính
```yaml
camera: ^0.11.0
google_mlkit_pose_detection: ^0.14.0
permission_handler: ^11.3.1
webview_flutter: ^4.10.0
```

## Assets
```txt
assets/
├── poses/tree_pose.json      # MediaPipe motion (~1444 frames)
├── models/yoga_avatar.vrm    # VRM guide model (~20MB)
└── web/
    ├── yoga_vrm_renderer.html
    └── yoga_vrm_renderer.js
```

Đổi đường dẫn tại `lib/core/constants/app_assets.dart`.

## Web vs iOS/Android
| Platform | Camera | VRM 3D overlay | Pose scoring |
|----------|--------|----------------|--------------|
| iOS/Android | ✅ | ✅ WebView + Three.js | ✅ ML Kit |
| Flutter Web | ✅ | ❌ fallback message | ❌ |

Target chính: **iOS real device** (camera + VRM + score).

## Cấu trúc thư mục chính
```txt
lib/features/yoga_mirror/
├── widgets/
│   ├── yoga_mirror_demo_screen.dart
│   ├── camera_pose_view.dart
│   └── vrm_model_webview.dart      # NEW — WebView VRM overlay
├── controllers/yoga_mirror_controller.dart
├── services/pose_matching_service.dart, pose_feedback_service.dart
├── utils/pose_frame_serializer.dart
└── painters/ghost_pose_painter.dart  # deprecated, không dùng trong UI
```

## Retarget (prototype)
JS nhận `PoseFrame` JSON, map landmarks → VRM humanoid bones:
- Ưu tiên `wx/wy/wz` (world coord), fallback `xNorm/yNorm`
- Chỉ dùng **custom solver** cho phase đầu, không động vào render/opacity/camera nữa
- Bones: hips, spine, chest, neck, head, arms, legs
- Retarget theo từng phase: torso → arms → legs
- **Render VRM neutral đã đúng**; phần này chỉ tập trung vào mapping/rotation, không sửa UI/render nữa

## Quyết định kỹ thuật
1. JSON `timestampMs` điều khiển timeline — play/pause/speed/slider ở Flutter
2. Mỗi frame change → `applyPoseFrame()` sang WebView
3. VRM opacity ~0.45–0.65, renderer alpha transparent
4. Score vẫn tính bằng góc khớp ML Kit vs JSON (không đổi)
5. CDN: three.js, @pixiv/three-vrm, kalidokit — cần internet lần đầu
6. WebView: HTML/JS inject inline qua `rootBundle`, không fetch Flutter asset path trực tiếp
7. Error handling: JS bắt lỗi CDN (error/unhandledrejection) + lỗi parse VRM, gửi về Flutter qua `YogaMirrorBridge`

## Lỗi thường gặp — VRM không load được
1. **CDN không có mạng**: Three.js/three-vrm/kalidokit import fail → báo "Failed to load CDN dependency"
2. **Asset path sai**: `pubspec.yaml` thiếu `assets/models/` hoặc tên file không khớp `AppAssets`
3. **File VRM lỗi/không đúng format**: Three.js GLTFLoader báo lỗi parse
4. **WebView resource bị chặn**: iOS WKWebView policy, cần dùng `loadHtmlString`

## Trạng thái hiện tại
- ✅ VRM đã load được qua rootBundle + base64 chunked
- 🔄 Model display: đã normalize center/scale/camera, đang tuning
- 🔄 Retarget JSON → VRM bones: đã chia pipeline torso → arms → legs
- 🔄 Score: thêm full-body detection validation, chỉ tính điểm khi đủ landmarks

## Các phase sửa lỗi
1. **Phase 1 (done)**: Normalize VRM display — center model, scale, camera, neutral pose
2. **Phase 2 (in progress)**: Retarget JSON → bones — mirror toggle, smoothing, grouped body parts
3. **Phase 3**: Score validation — full-body check, feedback cải thiện
4. **Phase 4**: Tuning — bone mapping, coordinate system, scale/position calibration

## Lưu ý
- Score `--` hoặc 0% có thể do camera chưa thấy toàn thân.
- Cần đặt điện thoại xa 2-3m, thấy từ đầu tới chân để score hoạt động.
- `enableRetarget = true` sau khi VRM load xong 500ms, tránh retarget lúc model chưa ổn định.

## Việc tiếp theo
- Tune bone mapping / coordinate system cho retarget chính xác hơn
- Vendor local JS nếu CDN không ổn trên WebView
- Giảm VRM size hoặc cache sau lần load đầu
- Debug mode dev-only (không show skeleton cho user)