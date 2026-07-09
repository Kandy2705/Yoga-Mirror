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
- [ ] Xác nhận WebView transparent chồng lên camera
- [ ] Test khi **không có internet** (CDN three.js/vrm/kalidokit)

## Đã fix
- [x] Loading step tracking: asset load → base64 encode → gửi chunk → JS parse → ready
- [x] CDN error detection: `window.onerror` + `unhandledrejection` bắt lỗi import fail
- [x] JS error phân loại: CDN vs VRM parse vs network, gửi detail về Flutter
- [x] Flutter error UI: hiển thị icon + message + detail (nếu có)
- [x] Xoá speed buttons (0.5x, 1x, 1.5x) khỏi UI
- [x] Xoá file duplicate `assets/yoga_avatar.vrm` (root level)
- [x] JS `enableRetarget` flag, mặc định `false`, bật sau 500ms
- [x] `normalizeVrmModel()` — center model về gốc, scale đúng, camera lookAt
- [x] Camera fix: `position(0, 0.9, 3.0)`, `lookAt(0, 0.7, 0)`
- [x] `mirrorGuide` flag — swap left/right landmarks khi enabled
- [x] Retarget pipeline: torso → arms → legs (từng nhóm riêng)
- [x] `isValidFrame()` validation trước khi apply pose
- [x] Smoothing via slerp với `rotationSmoothing = 0.25`
- [x] `setGuideTransform()` — Flutter có thể gọi để chỉnh scale/offset/yaw
- [x] Score chỉ tính khi camera thấy full-body (vai, hông, gối, cổ chân)
- [x] Feedback cải thiện: phân biệt "no_torso" vs "partial" vs "full"
- [x] `PoseFeedbackService.bodyStatus` param

## Cải tiến retarget

- [ ] Test torso only retarget first
- [ ] Test arms only retarget second
- [ ] Test legs only retarget third
- [ ] Test mirrorGuide true/false
- [ ] Tune defaultDir per bone if arm/leg orientation looks wrong
- [ ] Model hiện tại có nhiều mesh phụ như tóc/váy nên dễ lỗi khi retarget; nên dùng mannequin/robot đơn giản cho demo mapping
- [ ] Improve custom retarget accuracy (tay/chân/thân)
- [ ] Fix bone rest pose alignment nếu model A-pose/T-pose khác
- [ ] Vendor local JS thay CDN nếu WebView block network

## Dev tools (không show cho user)

- [x] Debug mode: `showDebugSkeleton(enable)` trong JS (dev only)
- [x] `window.getDebugInfo()` — query retarget state từ Flutter
- [ ] JavaScriptChannel log errors về Flutter console
- [ ] `file_picker` chọn JSON/VRM khác (dev tool)

## Vừa fix

- [x] **mirror arm restDir bug**: khi `mirrorGuide=true`, arm `defaultDir` không được mirror → tay VRM xoay sai hướng. Fix: `if (mirrorGuide) restDir.x *= -1`

## Performance

- [ ] Cache VRM đã parse trong WebView session
- [ ] Giảm kích thước VRM asset nếu load quá chậm
- [ ] Throttle `applyPoseFrame` nếu slider drag gây lag

## Giữ nguyên từ bản trước

- [x] ML Kit pose scoring iOS/Android
- [x] Feedback tiếng Việt
- [x] Portrait/landscape responsive
- [x] Không hiện skeleton/landmark người dùng