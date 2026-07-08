# YogaMirror — TODO Next

## VRM 3D Guide (yêu cầu mới)

- [x] Verify VRM asset path (`assets/models/yoga_avatar.vrm`)
- [x] Load VRM từ Flutter asset bytes → WebView base64 (chunked)
- [x] Build Three.js/three-vrm scene (`assets/web/yoga_vrm_renderer.js`)
- [x] Apply JSON PoseFrame → VRM bones (Kalidokit + custom fallback)
- [x] Thay ghost 2D overlay bằng `VrmModelWebView`
- [x] Sync slider/play/pause/speed với JSON timeline
- [x] Web fallback message (không crash)
- [x] Cập nhật PROJECT_CONTEXT.md

## Cần test thủ công

- [ ] **iPhone thật**: `flutter run` — camera + VRM overlay + score
- [ ] Xác nhận VRM load xong (~20MB, có thể mất 10–30s)
- [ ] Xác nhận model chuyển động theo JSON khi Play
- [ ] Xác nhận Slider tua được pose model
- [ ] Xác nhận Speed 0.5x/1x/1.5x ảnh hưởng timeline
- [ ] Xác nhận WebView transparent chồng lên camera
- [ ] Test khi **không có internet** (CDN three.js/vrm/kalidokit)

## Cải tiến retarget

- [ ] Tune model scale/position/opacity trên nhiều device
- [ ] Improve Kalidokit/custom retarget accuracy (tay/chân/thân)
- [ ] Tune coordinate mapping wx/wy/wz vs xNorm/yNorm
- [ ] Fix bone rest pose alignment nếu model A-pose/T-pose khác
- [ ] Vendor local JS thay CDN nếu WebView block network:
  - `three.module.js`
  - `GLTFLoader.js`
  - `three-vrm.module.js`
  - `kalidokit` (optional)

## Dev tools (không show cho user)

- [ ] Debug mode: `showDebugSkeleton` trong JS (dev only)
- [ ] JavaScriptChannel log errors về Flutter console
- [ ] `file_picker` chọn JSON/VRM khác (dev tool)

## Performance

- [ ] Cache VRM đã parse trong WebView session
- [ ] Giảm kích thước VRM asset nếu load quá chậm
- [ ] Throttle `applyPoseFrame` nếu slider drag gây lag

## Giữ nguyên từ bản trước

- [x] ML Kit pose scoring iOS/Android
- [x] Feedback tiếng Việt
- [x] Portrait/landscape responsive
- [x] Không hiện skeleton/landmark người dùng