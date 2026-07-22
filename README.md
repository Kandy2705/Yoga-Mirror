# YogaMirror 2D

Demo Flutter hiển thị **người nộm 2D bằng Rive**, chuyển động theo các frame **pose JSON**. Ứng dụng có bộ chọn nhiều bài JSON có sẵn, phát/tua animation, lật trái–phải, chỉnh kích thước người nộm, hiển thị landmark để debug, vẽ đường phân biệt chân trái/phải và viền đen bao quanh toàn bộ cơ thể.

| Thành phần | Mô tả |
|---|---|
| Guide 2D | Người nộm faceless render bằng `assets/rive/yoga_mannequin.riv` |
| Motion | Pose 2D lấy từ các file JSON trong `assets/data/` |
| Chọn bài | Tự quét toàn bộ file `.json` đã bundle và hiển thị trong modal chọn bài |
| Playback | Play / Pause, tua timeline, về đầu, lặp lại, tốc độ `0.5x–2x` |
| Leg guide | Xanh = chân trái, hồng = chân phải; chân trước được tô đậm và gắn nhãn |
| Outline | Viền đen bao quanh toàn bộ silhouette người nộm |
| Debug | Overlay landmark và thông tin frame JSON |
| Import | Có thể chọn thêm file JSON trực tiếp từ điện thoại |

> **Target chính:** iPhone và Android thiết bị thật. App hiện là demo **pose playback 2D**, chưa tích hợp camera live hoặc chấm điểm tư thế.

---

## Yêu cầu

- Flutter SDK tương thích Dart `>=3.6.0 <4.0.0`
- Xcode cho iOS hoặc Android Studio cho Android
- iPhone/Android đã bật chế độ developer khi chạy trên thiết bị thật
- Internet ở lần cài/build đầu để tải package và Rive Native binary
- Không cần internet khi app đã build xong vì Rive và JSON đều nằm local trong project

Kiểm tra môi trường:

```bash
flutter doctor -v
flutter devices
```

---

## Cài đặt

```bash
cd yoga_mirror_rive_demo
flutter pub get
```

Nếu đường dẫn project có khoảng trắng, cần đặt đường dẫn trong dấu ngoặc kép:

```bash
cd "/Users/<username>/Documents/Du an ngoai/yoga_mirror_rive_demo"
```

### iOS: tải Rive Native XCFramework

Project dùng `rive: ^0.14.9`, vì vậy trước lần build iOS đầu tiên nên chạy:

```bash
dart run rive_native:setup \
  --clean \
  --platform ios
```

Nếu thư mục `ios/` hoặc `android/` chưa tồn tại, chỉ chạy script bootstrap **một lần**:

```bash
chmod +x bootstrap.sh
./bootstrap.sh
```

Sau khi platform đã được tạo, không cần chạy lại `bootstrap.sh` mỗi lần build.

---

## Assets

Các asset được khai báo trong `pubspec.yaml`:

```yaml
flutter:
  uses-material-design: true
  assets:
    - assets/data/
    - assets/rive/yoga_mannequin.riv
```

Cấu trúc đề xuất:

```text
assets/
├── data/
│   ├── sample_pose.json
│   ├── bai_02.json
│   └── video3_fixed.json
└── rive/
    └── yoga_mannequin.riv
```

Tên file JSON có thể đặt tùy ý. Ứng dụng tự quét toàn bộ file có đuôi `.json` trong `assets/data/` và đưa vào modal **Chọn bài tập JSON**.

Sau khi thêm, xóa hoặc đổi tên JSON, cần build lại để Flutter cập nhật AssetManifest:

```bash
flutter clean
flutter pub get
flutter run
```

Hot reload không luôn cập nhật danh sách asset mới.

---

## Cách chạy

### 1) iOS — thiết bị thật

```bash
flutter devices

dart run rive_native:setup \
  --clean \
  --platform ios

flutter run -d <device_id>
```

Hoặc khi chỉ có một thiết bị được kết nối:

```bash
flutter run
```

Giữ iPhone mở khóa trong lúc cài và launch app.

### 2) Android — thiết bị thật

```bash
flutter devices
flutter run -d <android_device_id>
```

Cần bật USB debugging hoặc wireless debugging.

### 3) iOS Simulator

Có thể dùng để kiểm tra UI và playback JSON, nhưng target kiểm thử chính vẫn là thiết bị thật:

```bash
flutter run -d "iPhone Simulator"
```

### 4) Flutter Web

Flutter Web chưa phải target chính của project này. Cần kiểm tra lại khả năng tương thích của Rive Native và file picker trước khi dùng cho production.

### Build release

```bash
# Android APK
flutter build apk --release

# iOS — cần signing hợp lệ trong Xcode
flutter build ios --release
```

---

## Cách dùng app

1. Mở app và đợi người nộm cùng JSON mặc định được load.
2. Bấm nút **Bài X • tên_file.json** để mở modal chọn giữa các bài JSON có sẵn.
3. Dùng các control phía dưới:
   - **Phát / Tạm dừng** — chạy hoặc dừng animation.
   - **Slider** — tua tới thời điểm bất kỳ.
   - **Về đầu** — đưa timeline về `0:00`.
   - **Lặp lại** — bật/tắt loop.
   - **0.5x / 1x / 1.5x / 2x** — đổi tốc độ phát.
4. Bấm icon **thư mục** trên AppBar để chọn JSON từ Files trên điện thoại.
5. Bấm icon **tune** để chỉnh chiều cao và chiều rộng người nộm.
6. Bấm **So sánh JSON** để hiện landmark và thông tin frame.
7. Bấm icon **người đi bộ** để bật/tắt đường phân biệt chân.
8. Bấm icon **flip** để lật trái/phải toàn bộ pose.

App hiện khóa giao diện ở chế độ portrait.

---

## Đường phân biệt chân

Khi bật leg guide:

| Hiển thị | Ý nghĩa |
|---|---|
| Đường xanh | Chân trái |
| Đường hồng | Chân phải |
| Đường liền, dày | Chân được suy đoán nằm phía trước |
| Đường đứt, mờ | Chân được suy đoán nằm phía sau |
| Nhãn `TRƯỚC` | Chân có visibility cao hơn rõ rệt |

Việc xác định chân trước dựa trên giá trị `visibility` trung bình của hông, gối, cổ chân, gót chân và mũi chân.

> JSON hiện chỉ có dữ liệu 2D và thường không có `z`, vì vậy khi hai chân có visibility gần bằng nhau, app sẽ hiện **“Chân trước: chưa xác định”**. Đây là giới hạn của dữ liệu đầu vào, không phải lỗi render.

---

## Viền đen toàn thân

`MannequinOutlinePainter` vẽ silhouette đen phía sau Rive mannequin, giúp phân biệt rõ đầu, thân, tay và chân với nền.

Độ dày mặc định nằm trong:

```text
lib/widgets/mannequin_stage.dart
```

Tìm:

```dart
outlineWidth: 7,
```

Ví dụ:

```dart
outlineWidth: 4,  // viền mảnh hơn
outlineWidth: 10, // viền dày hơn
```

Sau khi sửa code Dart, hot reload thường là đủ.

---

## Định dạng JSON hỗ trợ

Project không đọc mọi JSON bất kỳ. File cần chứa danh sách frame pose và landmark theo một trong hai dạng tương thích dưới đây.

### Dạng A — pose JSON nội bộ

```json
{
  "schemaVersion": "2.0",
  "captureParams": {
    "sampleFps": 10
  },
  "frames": [
    {
      "timestampMs": 0,
      "frameWidth": 1280,
      "frameHeight": 720,
      "landmarks": [
        {
          "name": "leftShoulder",
          "xNorm": 0.54,
          "yNorm": 0.26,
          "visibility": 1.0
        }
      ]
    }
  ]
}
```

### Dạng B — MediaPipe/manual-correction

```json
{
  "metadata": {
    "source_fps": 10,
    "image_width": 1280,
    "image_height": 720
  },
  "frames": [
    {
      "frame_index": 0,
      "timestamp_ms": 0,
      "poses": [
        {
          "pose_landmarks": [
            {
              "index": 11,
              "name": "leftShoulder",
              "x": 0.54,
              "y": 0.26,
              "visibility": 1.0
            }
          ]
        }
      ]
    }
  ]
}
```

Parser hiện hỗ trợ:

- `timestampMs` hoặc `timestamp_ms`
- `xNorm` / `yNorm` hoặc `x` / `y`
- `visibility` hoặc `score`
- Landmark xác định bằng `name` hoặc MediaPipe `index`
- Tên camelCase như `leftShoulder`
- Một số alias snake_case như `left_shoulder`
- FPS từ `captureParams.sampleFps` hoặc `metadata.source_fps`
- Kích thước ảnh từ mỗi frame hoặc `metadata.image_width/image_height`

`z`, `presence`, `pixel_x` và `pixel_y` không bắt buộc cho animation 2D.

### Landmark cơ thể chính

Để render ổn định nên có tối thiểu:

```text
leftShoulder, rightShoulder
leftElbow, rightElbow
leftWrist, rightWrist
leftHip, rightHip
leftKnee, rightKnee
leftAnkle, rightAnkle
```

Các điểm sau giúp đầu, bàn tay và bàn chân chính xác hơn:

```text
nose
leftEye, rightEye
leftEar, rightEar
leftThumb, rightThumb
leftIndex, rightIndex
leftPinky, rightPinky
leftHeel, rightHeel
leftFootIndex, rightFootIndex
```

---

## Thêm một bài JSON mới

Chép file vào:

```text
assets/data/
```

Ví dụ:

```bash
cp ~/Downloads/new_pose.json \
  assets/data/new_pose.json
```

Sau đó chạy lại:

```bash
flutter clean
flutter pub get
flutter run
```

Bài mới sẽ tự xuất hiện trong modal chọn bài. Không cần sửa danh sách tên file trong `main.dart`.

---

## Thay người nộm Rive

Asset người nộm được load từ:

```text
assets/rive/yoga_mannequin.riv
```

Có thể thay file `.riv`, nhưng để code rig hiện tại tiếp tục hoạt động, artboard mới cần giữ đúng tên component:

```text
head
neck
neck_joint
torso
pelvis

left_upper_arm
right_upper_arm
left_forearm
right_forearm
left_hand
right_hand

left_thigh
right_thigh
left_calf
right_calf
left_foot
right_foot

left_shoulder_joint
right_shoulder_joint
left_elbow_joint
right_elbow_joint
left_wrist_joint
right_wrist_joint
left_hip_joint
right_hip_joint
left_knee_joint
right_knee_joint
left_ankle_joint
right_ankle_joint
```

Nếu đổi tên component trong Rive mà không cập nhật `PoseRigDriver`, phần tương ứng sẽ không di chuyển.

---

## Căn kích thước người nộm

Icon **tune** mở bottom sheet gồm:

- Chiều cao: `65%–145%`
- Chiều rộng: `65%–145%`
- Nút đặt lại về `100%`

Các giá trị này chỉ scale phần hiển thị của mannequin, không thay đổi dữ liệu gốc trong JSON.

---

## Nền tảng hỗ trợ

| Platform | Pose JSON | Rive mannequin | Chọn file JSON | Leg guide / outline |
|---|:---:|:---:|:---:|:---:|
| iOS device | ✅ | ✅ | ✅ | ✅ |
| Android device | ✅ | ✅ | ✅ | ✅ |
| iOS Simulator | ✅ | ⚠️ cần test theo máy | ⚠️ | ✅ |
| Flutter Web | ⚠️ chưa target | ⚠️ chưa target | ⚠️ | ⚠️ |

---

## Cấu trúc code

```text
lib/
├── main.dart
├── models/
│   └── pose_models.dart              # parse 2 format JSON + nội suy frame
├── services/
│   ├── pose_loader.dart              # load asset / chọn JSON từ điện thoại
│   └── pose_rig_driver.dart          # chiếu landmark lên Rive mannequin
└── widgets/
    ├── mannequin_stage.dart          # ghép Rive + outline + overlay
    ├── mannequin_outline_painter.dart
    ├── leg_guide_painter.dart
    ├── debug_pose_painter.dart
    └── size_adjustment_sheet.dart

assets/
├── data/                              # các bài pose JSON
└── rive/
    └── yoga_mannequin.riv

tool/
└── generate_mannequin_rive.mjs       # tooling tạo asset mannequin

bootstrap.sh                           # tạo platform lần đầu
pubspec.yaml
```

---

## Troubleshooting nhanh

| Triệu chứng | Việc nên thử |
|---|---|
| `No XCFramework found ... RiveNative_ios.xcframework` | Chạy lại `dart run rive_native:setup --clean --platform ios` |
| Xcode vẫn dùng artifact Rive cũ | Xóa `build`, `ios/.swiftpm`, DerivedData rồi setup lại Rive Native |
| `CoreDeviceError` / `Mercury error 1001` | Mở khóa iPhone, cắm lại cáp, kiểm tra Trust và Developer Mode rồi chạy lại |
| `No such file or directory` khi `cd` | Kiểm tra đúng vị trí project và đặt đường dẫn có khoảng trắng trong dấu `"..."` |
| Thiếu `pose_loader.dart` hoặc widget Dart | Đang chạy nhầm project hoặc patch chưa được giải nén đúng thư mục |
| App không thấy JSON mới | Đảm bảo file nằm trong `assets/data/`, sau đó `flutter clean` và build lại |
| JSON báo không có frame hợp lệ | Kiểm tra `frames`, timestamp, landmark name/index và tọa độ x/y |
| Người nộm không hiện | Kiểm tra `assets/rive/yoga_mannequin.riv` và khai báo asset trong `pubspec.yaml` |
| Một phần cơ thể không di chuyển | Tên component trong `.riv` không khớp `PoseRigDriver` |
| Không xác định được chân trước | Hai chân có visibility gần bằng nhau hoặc JSON không có thông tin che khuất |
| `6 packages have newer versions...` | Đây chỉ là cảnh báo version, không phải lỗi build |

### Reset iOS build/Rive cache

```bash
flutter clean
rm -rf build
rm -rf ios/.swiftpm
find ~/Library/Developer/Xcode/DerivedData \
  -maxdepth 1 \
  -name 'Runner-*' \
  -exec rm -rf {} +

flutter pub get

dart run rive_native:setup \
  --clean \
  --platform ios

flutter run
```

---

## Giới hạn hiện tại

- Chưa có camera live.
- Chưa có pose detection realtime trên người dùng.
- Chưa có chấm điểm tư thế.
- Dữ liệu đang là 2D, vì vậy không thể xác định chính xác chiều sâu trong mọi frame.
- Chân trước/phía sau chỉ là suy đoán từ visibility.
- Người nộm là Rive 2D, không phải model VRM/3D.
- Thứ tự chồng lớp tay/chân có thể chưa hoàn hảo khi pose quay ngang hoàn toàn.

---

## License / ghi chú demo

Project demo nội bộ — chưa public package:

```yaml
publish_to: none
```

Các file Rive, JSON pose và dữ liệu nguồn thuộc tài sản demo của project. Không redistribute khi chưa được phép.