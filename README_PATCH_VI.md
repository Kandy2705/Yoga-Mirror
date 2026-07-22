# Bản cập nhật: đường phân biệt chân + JSON video3_fixed

## Có gì mới

- Đường xanh chạy theo chân trái.
- Đường hồng chạy theo chân phải.
- Chân được suy đoán ở phía trước: đường liền, dày và có nhãn `TRƯỚC`.
- Chân bị che/phía sau: đường đứt và mờ hơn.
- Nút hình người đi bộ trên thanh công cụ để bật/tắt đường chân.
- Đọc được cả JSON schema cũ và schema mới dạng:
  - `metadata.source_fps`
  - `frames[].timestamp_ms`
  - `frames[].poses[0].pose_landmarks[]`
  - landmark dùng `x`, `y`
- `video3_fixed.json` đã được đặt làm JSON mặc định trong `assets/data/sample_pose.json`.

## Cách áp dụng patch

Tại thư mục project:

```bash
cd ~/Downloads/yoga_mirror_rive_demo
unzip -o ~/Downloads/yoga_mirror_leg_guides_video3_patch.zip
flutter clean
flutter pub get
dart run rive_native:setup --clean --platform ios
flutter run
```

Không chạy lại `bootstrap.sh`.

## Cách nhận biết chân trước

File mới ghi `visibility = 0.15` cho điểm bị che. App lấy trung bình visibility của hông, gối, mắt cá, gót và mũi chân:

- bên có visibility cao hơn được đánh dấu `TRƯỚC`;
- nếu hai bên gần bằng nhau, app ghi `chưa xác định` vì JSON 2D không có trục z.
