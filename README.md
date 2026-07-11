# YogaMirror

Demo Flutter: **camera live** + **avatar 3D VRM** hướng dẫn tư thế yoga, motion lấy từ **MediaPipe JSON**, đồng thời **chấm điểm** khớp tư thế (ML Kit) trên iOS/Android.

| Thành phần | Mô tả |
|---|---|
| Camera | Preview live + pose detection (ML Kit) |
| Guide 3D | Model VRM render qua WebView (Three.js + three-vrm) |
| Motion | `assets/poses/tree_pose.json` — nguồn chuyển động duy nhất |
| Score | So khớp góc khớp camera vs frame JSON |

> **Target chính:** iPhone/Android **thiết bị thật**. Simulator / Flutter Web có hạn chế (xem bảng bên dưới).

---

## Yêu cầu

- [Flutter](https://docs.flutter.dev/get-started/install) (SDK ^3.12)
- Xcode (iOS) / Android Studio (Android)
- **Không cần internet lúc chạy** — Three.js / three-vrm / Kalidokit đã bundle offline
- (Dev) Node.js + npm nếu sửa `assets/web/yoga_vrm_renderer.js` → `npm run build:renderer`
- Camera + quyền camera
- Đủ chỗ trống: VRM ~6–7MB (đã nén texture), pose JSON ~8MB (minified), renderer bundle ~1.3MB

Kiểm tra môi trường:

```bash
flutter doctor
flutter devices
```

---

## Cài đặt

```bash
# Clone / mở project
cd YogaMirror

# Cài dependency
flutter pub get

# (Tuỳ chọn) rebuild WebView renderer offline bundle sau khi sửa JS
npm install          # cài three/three-vrm/kalidokit + esbuild
npm run build:renderer

# iOS: cài CocoaPods
cd ios && pod install && cd ..
```

Đảm bảo assets có sẵn (đã khai báo trong `pubspec.yaml`):

```text
assets/
├── poses/tree_pose/
│   ├── meta.json                        # manifest (nhỏ)
│   └── chunk_XXX.json                   # lazy pose chunks (~340KB mỗi file)
├── models/yoga_avatar.vrm               # guide model (local)
└── web/
    ├── yoga_vrm_renderer.html
    ├── yoga_vrm_renderer.js             # source
    └── yoga_vrm_renderer.bundle.js      # offline IIFE — runtime

# Tooling (không bundle vào app):
# tools/tree_pose.source.json  →  npm run split:pose
```

Đường dẫn asset cấu hình tại `lib/core/constants/app_assets.dart`.

### Offline checklist (G1 pattern)

| Mục | YogaMirror |
|-----|------------|
| Model trong project | `assets/models/yoga_avatar.vrm` (base64 → WebView, không HTTPS) |
| Lib 3D npm bundle | `npm run build:renderer` → `yoga_vrm_renderer.bundle.js` |
| Pose / animation | `assets/poses/*.json` local |
| Texture / HDR ngoài | Không dùng |
| Verify | Airplane mode → avatar + retarget vẫn load |

---

## Cách chạy

### 1) iOS — thiết bị thật (khuyến nghị)

Full feature: camera + VRM + score ML Kit.

```bash
# Cắm iPhone, trust máy, chọn device
flutter devices

flutter run -d <device_id>
# hoặc
flutter run
```

Entry point mặc định: `lib/main.dart`.

### 2) Android — thiết bị thật

```bash
flutter run -d <android_device_id>
```

Cần bật USB debugging / wireless debugging.

### 3) iOS Simulator (không có ML Kit)

Simulator không chạy ML Kit pose detection. Dùng entry riêng:

```bash
# Cách 1: script (tự tạm bỏ google_mlkit, chạy, rồi restore pubspec)
bash tool/run_simulator.sh

# Cách 2: thủ công
flutter run -d "iPhone 17 Pro" -t lib/main_simulator.dart
```

> Script `tool/run_simulator.sh` sẽ backup/restore `pubspec.yaml` và chạy `pod install`. Nếu script bị dừng giữa chừng, kiểm tra lại `pubspec.yaml` có còn dependency ML Kit không.

### 4) Flutter Web

```bash
flutter run -d chrome
```

**Hạn chế:** VRM overlay và score không full như mobile — chủ yếu fallback / UI.

### Build release (tuỳ chọn)

```bash
# Android APK
flutter build apk --release

# iOS (cần signing trên Xcode)
flutter build ios --release
```

---

## Cách dùng app

1. **Mở app** → cho phép **Camera**.
2. Đặt điện thoại cách người khoảng **2–3m**, khung hình thấy **từ đầu tới chân**.
3. Chờ **VRM load** (file lớn, có thể 10–30s lần đầu; cần mạng cho CDN).
4. Dùng control phía dưới:
   - **Play / Pause** — chạy / dừng timeline pose JSON
   - **Slider** — tua frame hướng dẫn
   - **Reset** — về đầu bài
5. **Score** cập nhật khi camera thấy đủ full-body (vai, hông, gối, cổ chân).
6. Làm theo tư thế avatar 3D trên camera (lớp guide bán trong suốt).

Hỗ trợ **portrait** và **landscape**.

---

## Nền tảng hỗ trợ

| Platform | Camera | VRM 3D overlay | Pose scoring |
|----------|:------:|:--------------:|:------------:|
| iOS device | ✅ | ✅ | ✅ ML Kit |
| Android device | ✅ | ✅ | ✅ ML Kit |
| iOS Simulator | ⚠️ / mock | ✅ offline bundle | ❌ (`main_simulator`) |
| Flutter Web | ⚠️ | ❌ fallback | ❌ |

---

## Lưu ý quan trọng

### Score `--` hoặc 0%
- Camera **chưa thấy toàn thân** → app không tính điểm.
- Di chuyển máy xa hơn, đủ sáng, tránh che khuất khớp.

### VRM không hiện / lỗi load
1. Thiếu `assets/web/yoga_vrm_renderer.bundle.js` → chạy `npm run build:renderer`.
2. Asset path sai hoặc thiếu trong `pubspec.yaml` (`assets/models/`, `assets/web/`).
3. File `.vrm` hỏng / không đúng format.
4. Lần đầu load chậm — chờ base64 chunk gửi xong rồi JS parse.

### Internet / offline
- **Runtime không cần mạng**: model + pose + three/three-vrm/kalidokit đều local.
- `INTERNET` permission Android vẫn có (debug tooling); app demo không fetch CDN/API.

### Scale avatar theo người (mentor)
- **2.1 Manual:** icon *open_with* trên header → slider scale / cao / ngang / Y offset.
- **2.2 Session-start:** `applySessionBodyScale` hoặc `fitGuideToUserFromFrame` (lock sau lần đầu, cam live không re-scale).

### Simulator
- Không test score / ML Kit trên Simulator.
- Dùng `lib/main_simulator.dart` hoặc `tool/run_simulator.sh`.

### Performance
- VRM lớn → load lâu, tốn RAM.
- Pose JSON lớn → parse lần đầu có thể chậm.
- Nên test trên **máy thật** để đánh giá mượt / score.

### Quyền & privacy
- iOS: `NSCameraUsageDescription` trong `Info.plist`.
- Android: `CAMERA` + `INTERNET` trong `AndroidManifest.xml`.
- App chỉ dùng camera local để detect pose; không stream video lên server trong flow demo này.

---

## Cấu trúc code (tóm tắt)

```text
lib/
├── main.dart                 # entry device (ML Kit)
├── main_simulator.dart       # entry simulator (không ML Kit)
├── app/yoga_mirror_app.dart
├── core/constants/app_assets.dart
└── features/yoga_mirror/
    ├── widgets/              # UI: demo screen, camera, VRM webview, controls
    ├── controllers/          # playback + score state
    ├── services/             # matching, feedback, pose stream
    └── data/                 # load pose JSON
assets/
├── poses/                    # MediaPipe motion JSON
├── models/                   # VRM avatar
└── web/                      # Three.js renderer (HTML/JS)
```

---

## Troubleshooting nhanh

| Triệu chứng | Việc nên thử |
|---|---|
| `flutter pub get` lỗi | Kiểm tra Flutter SDK version (`sdk: ^3.12`) |
| iOS build fail pods | `cd ios && pod install --repo-update` |
| Camera đen / denied | Vào Settings → cấp quyền Camera cho app |
| VRM trắng / lỗi CDN | Bật Wi‑Fi, reload app |
| Score không đổi | Đứng full-body trong khung, đủ sáng |
| Script simulator dở | Restore `pubspec.yaml` từ backup `.device.bak` nếu còn |

---

## License / ghi chú demo

Project demo nội bộ — chưa public package (`publish_to: 'none'`).

Avatar VRM, pose JSON và video nguồn thuộc tài sản demo của project; không redistribute nếu chưa được phép.
