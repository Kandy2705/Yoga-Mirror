# Retarget MediaPipe Pose JSON → VRM Humanoid (YogaMirror)

## 0. Đã kiểm tra file `yoga_avatar.vrm` của bạn

Tôi parse trực tiếp glTF/JSON chunk của file. Kết quả quan trọng:

- **Đây là VRM 0.x** (không phải VRM 1.0). Bằng chứng: extension nằm ở `extensions.VRM` với các field kiểu cũ (`allowedUserName`, `commercialUssageName` — spelling "Ussage" là đặc trưng VRM0.x, VRM1.0 dùng `VRMC_vrm` với schema khác hẳn).
- Đây là model chuẩn **VRoid**, có đầy đủ `humanBones` bạn cần: `hips, spine, chest, upperChest, neck, head, leftUpperArm/leftLowerArm/leftHand, rightUpperArm/rightLowerArm/rightHand, leftUpperLeg/leftLowerLeg/leftFoot, rightUpperLeg/rightLowerLeg/rightFoot` + đầy đủ ngón tay, mắt.
- Không có custom bone lạ, không thiếu bone quan trọng nào cho yoga pose.

**Vì sao điều này quan trọng:** VRM 0.x quy ước model đứng quay mặt về **-Z** (ngược hoàn toàn với VRM 1.0, quay về **+Z**). Đây gần như chắc chắn là nguyên nhân gốc của lỗi "model chưa nhìn thẳng camera" mà bạn thấy — không phải do JSON retarget.

---

## 1. Fix "model không nhìn thẳng camera" (tách biệt hoàn toàn khỏi retarget)

`@pixiv/three-vrm` phiên bản mới (v1.x/v2.x trở lên hỗ trợ cả VRM0 và VRM1) sẽ **tự động xoay 180° quanh trục Y** khi load VRM 0.x, để `vrm.scene` và hệ xương "normalized" luôn thống nhất hướng +Z giống VRM1. Nhưng việc này phụ thuộc đúng version + đúng cách bạn set up loader:

```js
import { VRMLoaderPlugin } from '@pixiv/three-vrm';

loader.register((parser) => new VRMLoaderPlugin(parser));
// KHÔNG tự ý thêm loader.register(new VRM0LoaderPlugin) song song hay dùng bản three-vrm cũ (0.x)
// chỉ hỗ trợ VRM0 và có convention khác.
```

**Checklist debug hướng mặt (làm theo thứ tự, đừng đoán):**

1. Kiểm tra version `@pixiv/three-vrm` trong `package.json` của bundle bạn nhúng vào WebView — phải là bản mới (>=1.0, khuyến nghị 2.x hiện tại) để có convert VRM0→VRM1 tự động.
2. Sau khi `vrm.scene.add(...)`, **đừng tự thêm bất kỳ rotation.y thủ công nào** dựa vào đoán mò. Load model, để mặc định, chụp ảnh xem model quay hướng nào so với camera Three.js (camera đặt ở +Z nhìn về gốc là chuẩn phổ biến).
3. Nếu model quay lưng lại camera → set **một lần duy nhất** lúc load: `vrm.scene.rotation.y = Math.PI;`. Đừng set trong loop update — đây là orientation cố định của cả scene, không phải animation.
4. **Tuyệt đối không xoay `hips` bone dựa theo JSON để "tạo hướng nhìn camera"** — đây chính là bug thứ 2 bạn đang gặp (mục 3 bên dưới). Hướng nhìn camera là setup 1 lần của `vrm.scene`, còn `hips` bone chỉ nên phản ánh chuyển động thật (nghiêng người, xoay hông trong tư thế yoga) — nếu tính sai sẽ trông như "chỉ có hips xoay lung tung".

---

## 2. Trả lời thẳng câu hỏi #4/#5: `getNormalizedBoneNode` vs rest-pose offset

VRM humanoid có 2 hệ xương song song:

- **Raw skeleton** (`humanoid.getRawBoneNode`) — xương gốc từ file glTF, có rotation "rest pose" tùy ý theo cách nhà thiết kế rig (rest pose có thể lệch trục kỳ lạ).
- **Normalized skeleton** (`humanoid.getNormalizedBoneNode`) — three-vrm tạo ra 1 hệ xương ảo song song, đã "làm sạch": **rest pose = identity quaternion cho mọi bone**, và trục đã được chuẩn hoá (ví dụ leftUpperArm mặc định hướng theo trục X).

→ **Bạn đang làm đúng khi dùng `getNormalizedBoneNode`.** Ưu điểm chính xác là: bạn KHÔNG cần cộng thêm rest-pose offset thủ công. `defaultDir` bạn định nghĩa (`(-1,0,0)` cho tay trái, `(0,-1,0)` cho chân...) chính là hướng của bone đó tại rest pose trong hệ normalized — điều này đúng.

three-vrm tự động sync ngược từ normalized skeleton sang raw skeleton mỗi khi bạn gọi `vrm.update(delta)` (hoặc `humanoid.update()`), nên bạn không cần đụng vào raw bone bao giờ.

→ Vậy **rest-pose offset không phải là vấn đề của bạn**. Vấn đề thật sự nằm ở mục 3.

---

## 3. Nguyên nhân chính: "chỉ hips xoay, tay chân không theo JSON"

Đây là lỗi kinh điển khi retarget theo chuỗi (kinematic chain) bằng world-space vector.

Code hiện tại của bạn:

```js
const direction = new THREE.Vector3().subVectors(to, from).normalize(); // world-space direction
const targetQuat = new THREE.Quaternion().setFromUnitVectors(defaultDir, direction);
bone.quaternion.slerp(targetQuat, 0.25); // gán thẳng vào LOCAL quaternion
```

Vấn đề: `bone.quaternion` là **rotation cục bộ (local)**, tính so với **parent hiện tại** của nó. Nhưng `direction` bạn tính là vector **world-space** (từ toạ độ landmark thế giới). Bạn đang gán 1 giá trị world-space thẳng vào 1 slot local-space.

Với `hips` — bone gốc (không có parent xoay), local ≈ world, nên nó "nhìn có vẻ đúng" (hoặc ít nhất là xoay được).

Với `leftUpperArm` — parent của nó là `leftShoulder`/`chest`, đã có rotation riêng. Local quaternion đúng phải là:

```
localQuat_upperArm = inverse(parentWorldQuat) × desiredWorldQuat
```

Nếu bạn bỏ qua bước này, `leftUpperArm` sẽ set sai hướng (rotation "cộng dồn" lệch theo rotation của parent). Với `leftLowerArm` (parent là `leftUpperArm`, mà bản thân `leftUpperArm` cũng bị set sai) → sai chồng sai → nhìn như "không cử động theo JSON", đúng như triệu chứng bạn mô tả.

### Cách fix — xử lý bone theo thứ tự cha→con, mỗi bước lấy world quaternion mới nhất của parent:

```js
const tmpParentWorldQuat = new THREE.Quaternion();
const tmpDesiredWorldQuat = new THREE.Quaternion();

function applyBoneDirectionChain(bone, fromWorld, toWorld, defaultDir, alpha = 0.4) {
  if (!bone || !bone.parent) return;

  // 1. Hướng mong muốn trong world space
  const direction = new THREE.Vector3().subVectors(toWorld, fromWorld).normalize();
  tmpDesiredWorldQuat.setFromUnitVectors(defaultDir.clone().normalize(), direction);

  // 2. Lấy world quaternion HIỆN TẠI của parent (phải update trước đó)
  bone.parent.getWorldQuaternion(tmpParentWorldQuat);

  // 3. Convert world -> local: local = inverse(parentWorld) * desiredWorld
  const localQuat = tmpParentWorldQuat.clone().invert().multiply(tmpDesiredWorldQuat);

  bone.quaternion.slerp(localQuat, alpha);

  // 4. Bắt buộc update matrixWorld của bone này trước khi xử lý bone con của nó
  bone.updateMatrixWorld(true);
}
```

**Thứ tự gọi bắt buộc phải là top-down theo chain**, không được xử lý song song / không theo thứ tự:

```
hips → spine → chest → (leftShoulder →) leftUpperArm → leftLowerArm → leftHand
hips → spine → chest → (rightShoulder →) rightUpperArm → rightLowerArm → rightHand
hips → leftUpperLeg → leftLowerLeg → leftFoot
hips → rightUpperLeg → rightLowerLeg → rightFoot
hips → spine → chest → neck → head
```

Sau khi set `hips`, gọi `vrm.scene.updateMatrixWorld(true)` (hoặc ít nhất `hipsBone.updateMatrixWorld(true)`) trước khi tính `spine`, rồi lại update trước khi tính `chest`, v.v. — vì bước 2 ở trên cần `parent.getWorldQuaternion()` phản ánh đúng giá trị **vừa mới set**, không phải giá trị của frame trước.

> Nếu ngại tự quản lý matrixWorld thủ công, cách đơn giản hơn: gọi `vrm.scene.updateMatrixWorld(true)` **sau mỗi bone** thay vì optimize — với ~16 bone chính, chi phí không đáng kể so với lợi ích debug được đúng.

---

## 4. Convert toạ độ MediaPipe → Three.js: có 1 bug trong code hiện tại

```js
function toPosePoint(lm) {
  return new THREE.Vector3(
    lm.wx ?? ((lm.xNorm ?? 0.5) - 0.5),
    lm.wy ?? (0.5 - (lm.yNorm ?? 0.5)),   // <-- nhánh fallback có đảo dấu, nhánh wy KHÔNG đảo dấu
    lm.wz ?? (lm.z ?? 0)
  );
}
```

MediaPipe world landmarks (`wx, wy, wz` — bạn đã record sẵn, rất tốt vì đây chính là dữ liệu nên dùng, đừng dùng `xNorm/yNorm` cho việc này) có quy ước: gốc toạ độ ở giữa hông, **Y dương hướng xuống** (giống hệ toạ độ ảnh). Three.js là hệ **Y dương hướng lên**. 

→ Nhánh `lm.wy` của bạn **thiếu dấu trừ**. Trong khi nhánh fallback (`0.5 - yNorm`) lại có đảo dấu đúng. Vì JSON của bạn luôn có `wx/wy/wz` (không bao giờ rơi vào fallback), toàn bộ pipeline hiện tại đang dùng **Y sai chiều** — đây rất có thể là lý do chính khiến limb "không cử động rõ theo JSON" (tay/chân bị tính lệch trục, kết quả rotation nhỏ/vô nghĩa sau khi normalize).

**Fix:**

```js
function toPosePoint(lm) {
  return new THREE.Vector3(
    lm.wx,
    -lm.wy,   // đảo dấu bắt buộc: MediaPipe Y-down -> Three.js Y-up
    -lm.wz    // xem mục mirror bên dưới để quyết định dấu Z
  );
}
```

Về `wz`: MediaPipe world Z dùng cùng scale với X/Y, quy ước gần đúng là "âm = gần camera hơn hông". Vì `vrm.scene` (sau fix mục 1) nhìn về phía **+Z** của Three.js, và camera thường đặt ở phía +Z nhìn vào gốc, bạn cần Z dương ở phía model = phía khán giả/camera. Nên thường phải đảo dấu Z tương tự Y. **Cách kiểm chứng nhanh** (xem mục 5): test tay đưa thẳng về phía camera (namaste ra trước ngực rồi đẩy tay ra) — nếu tay "thụt vào trong ngực" thay vì đưa ra trước, đảo dấu Z lại.

**Không trộn `wx/wy/wz` với `xNorm/yNorm` trong cùng 1 frame** — 2 hệ quy chiếu scale khác nhau (world landmarks tính bằng mét thực, dựa trên ước lượng tỉ lệ cơ thể; norm landmarks tính theo tỉ lệ khung hình ảnh). Vì bạn đã record đủ `wx/wy/wz` cho mọi landmark, hãy dùng world landmarks cho **toàn bộ** 33 điểm, bỏ hẳn nhánh fallback.

---

## 5. Có nên chuyển qua KalidoKit không? → **Có, khuyến nghị mạnh**

`KalidoKit.Pose.solve()` được viết chính xác cho use-case này (MediaPipe/Mediapipe-style landmarks → VRM humanoid rotation), và đã tự xử lý đúng bài toán world→local theo chain ở mục 3 — bạn sẽ tiết kiệm rất nhiều thời gian debug thủ công.

### Input format cần convert sang:

```js
// poseLandmarkArray: 33 điểm, screen-space normalized (0..1), dùng cho ước lượng visibility/scale
// poseWorld3DArray: 33 điểm, world-space (mét), dùng để tính rotation chính xác
//
// Build theo `index` (0-32) trực tiếp từ JSON, KHÔNG build theo `name` — đã kiểm tra
// trên data thật và xác nhận field "name" của app bạn dùng "leftMouth"/"rightMouth"
// (không phải "mouthLeft"/"mouthRight" như naming convention gốc của MediaPipe docs).
// Build theo index tránh hoàn toàn rủi ro lệch naming này, kể cả nếu sau này có
// landmark nào khác đặt tên khác chuẩn.

function frameToKalidoKitInputs(frame) {
  const byIndex = new Array(33).fill(null);
  frame.landmarks.forEach(lm => { byIndex[lm.index] = lm; });

  const poseLandmarkArray = byIndex.map(lm =>
    lm
      ? { x: lm.xNorm, y: lm.yNorm, z: lm.z ?? 0, visibility: lm.visibility ?? 0 }
      : { x: 0.5, y: 0.5, z: 0, visibility: 0 } // landmark không record -> visibility 0
  );

  const poseWorld3DArray = byIndex.map(lm =>
    lm
      ? { x: lm.wx, y: lm.wy, z: lm.wz, visibility: lm.visibility ?? 0 }
      : { x: 0, y: 0, z: 0, visibility: 0 }
  );

  return { poseLandmarkArray, poseWorld3DArray };
}
```

Đã xác nhận trên file `tree_pose.json` thật: mọi frame đều có đủ 33 landmark theo `index`, không thiếu, không NaN — nên nhánh fallback ở trên chỉ là an toàn phòng hờ, thực tế sẽ luôn rơi vào nhánh có data.

### Áp kết quả vào VRM:

```js
import * as Kalidokit from 'kalidokit';

function applyKalidoPoseToVrm(vrm, riggedPose) {
  const rotationMap = {
    Hips: 'hips', Spine: 'spine', Chest: 'chest', Neck: 'neck', Head: 'head',
    // MediaPipe "Left/Right" đứng từ góc nhìn của NGƯỜI (anatomical), không phải từ góc nhìn camera.
    // Nếu app của bạn là "gương" (mirror UX), swap Left<->Right ở đây (xem mục 6).
    LeftUpperArm: 'rightUpperArm', RightUpperArm: 'leftUpperArm',
    LeftLowerArm: 'rightLowerArm', RightLowerArm: 'leftLowerArm',
    LeftHand: 'rightHand', RightHand: 'leftHand',
    LeftUpperLeg: 'rightUpperLeg', RightUpperLeg: 'leftUpperLeg',
    LeftLowerLeg: 'rightLowerLeg', RightLowerLeg: 'leftLowerLeg',
  };

  const applyRot = (kalidoKey, vrmBoneName, alpha = 0.4) => {
    const src = riggedPose[kalidoKey];
    if (!src) return;
    const bone = vrm.humanoid.getNormalizedBoneNode(vrmBoneName);
    if (!bone) return;
    const euler = new THREE.Euler(src.x, src.y, src.z);
    const q = new THREE.Quaternion().setFromEuler(euler);
    bone.quaternion.slerp(q, alpha);
  };

  applyRot('Hips', 'hips');
  applyRot('Spine', 'spine');
  applyRot('LeftUpperArm', rotationMap.LeftUpperArm);
  applyRot('RightUpperArm', rotationMap.RightUpperArm);
  applyRot('LeftLowerArm', rotationMap.LeftLowerArm);
  applyRot('RightLowerArm', rotationMap.RightLowerArm);
  applyRot('LeftUpperLeg', rotationMap.LeftUpperLeg);
  applyRot('RightUpperLeg', rotationMap.RightUpperLeg);
  applyRot('LeftLowerLeg', rotationMap.LeftLowerLeg);
  applyRot('RightLowerLeg', rotationMap.RightLowerLeg);

  vrm.humanoid.update(0); // sync normalized -> raw skeleton
}

// Gọi mỗi frame:
const { poseLandmarkArray, poseWorld3DArray } = frameToKalidoKitInputs(currentFrame);
const riggedPose = Kalidokit.Pose.solve(poseWorld3DArray, poseLandmarkArray, {
  runtime: 'mediapipe',
  video: null,
});
applyKalidoPoseToVrm(currentVrm, riggedPose.Hips ? riggedPose : riggedPose);
```

> KalidoKit tự xử lý chain world→local đúng, tự xử lý hips position + rotation, và có sẵn xử lý riêng cho vai/chân — đây là lý do tôi khuyến nghị bạn chuyển hẳn sang nó thay vì tiếp tục vá code thủ công, trừ khi bạn cần độ chính xác/kiểm soát cao hơn cho riêng bài toán yoga (ví dụ: muốn giữ nguyên hips position, không muốn model "đi lệch" theo world position — khi đó set `riggedPose.Hips.position` = bỏ qua, chỉ lấy `rotation`).

---

## 6. Xử lý mirror trái/phải

`leftShoulder` (index 11) trong MediaPipe **luôn là vai trái thật của người** (theo giải phẫu), bất kể camera có mirror hình ảnh hiển thị hay không — MediaPipe tính trên frame ảnh thô trước khi bạn mirror để hiển thị.

Với app "YogaMirror" — trải nghiệm mong muốn thường là: **người dùng giơ tay phải → avatar cũng giơ tay ở phía bên phải màn hình** (như soi gương thật), tức là về mặt giải phẫu avatar phải giơ tay **trái**. Do đó:

- Map `leftShoulder/leftElbow/leftWrist...` (MediaPipe) → **`rightUpperArm/rightLowerArm/rightHand`** (VRM bone)
- Map `right...` (MediaPipe) → **`left...`** (VRM bone)
- **Không** đảo dấu tọa độ X để "mirror" — chỉ swap tên bone. Nếu bạn vừa đảo dấu X vừa swap tên, sẽ bị đảo ngược 2 lần = quay lại sai như cũ. Chọn 1 trong 2 cách, khuyến nghị chỉ swap tên bone (giữ nguyên toạ độ thế giới thật).

**Cách test nhanh để chốt đúng chiều:** yêu cầu người dùng chỉ giơ 1 tay (ví dụ tay phải) trước camera, chạy pipeline, xem avatar giơ tay bên nào trên màn hình. Nếu sai bên → đảo swap map ở trên.

---

## 7. Quy trình debug từng bước (bắt buộc làm tuần tự, đừng test full-body ngay)

1. **Bone sanity test (không cần JSON):** Trong console/devtool, set thẳng cứng:
   ```js
   vrm.humanoid.getNormalizedBoneNode('leftUpperArm').rotation.set(0, 0, Math.PI / 2);
   vrm.humanoid.update(0);
   ```
   Xác nhận: đúng tay trái (từ góc nhìn của model, tức bên phải màn hình nếu model nhìn ra bạn) di chuyển, di chuyển đúng hướng mong đợi (Euler Z dương → tay đưa lên/xuống/ra trước theo trục nào, ghi lại). Lặp lại cho từng bone 1 lần, note lại "trục nào ứng với hành động gì" — đây chính là `defaultDir` bạn cần, xác nhận bằng mắt thay vì đoán.

2. **Torso only:** Chỉ áp dụng `hips`, `spine`, `chest` từ 1 frame JSON tĩnh (không phải theo thời gian thực, dùng breakpoint 1 frame cố định), tay chân giữ nguyên T-pose. Xác nhận thân người nghiêng đúng theo tư thế yoga trong JSON.

3. **+ Arms:** Thêm `leftUpperArm/leftLowerArm/rightUpperArm/rightLowerArm` với chain fix ở mục 3. Test với 1 frame có tư thế tay rõ ràng (ví dụ tay giơ thẳng lên, hoặc dang ngang).

4. **+ Legs:** Thêm chân, test với 1 frame có chân rõ ràng (tree pose gập gối 1 bên là lựa chọn tốt vì bạn đã có sẵn file `tree_pose.json`).

5. **Full body theo thời gian thực:** Chỉ chuyển sang chạy full sequence sau khi bước 1-4 đều đúng ở static frame. Nếu full-body lỗi mà từng phần đều đúng → khả năng cao là do `alpha` slerp quá thấp/cao hoặc frame rate mismatch giữa `sampleFps` (10fps trong JSON) và tốc độ Flutter bắn `applyPoseFrame` qua JS bridge (nên interpolate giữa 2 frame JSON thay vì snap cứng, để tránh giật khi 10fps → hiển thị ở 60fps).

6. Dùng `THREE.SkeletonHelper(vrm.scene)` add vào scene để nhìn trực tiếp trục xương thay vì chỉ nhìn mesh — rất hữu ích khi nghi ngờ rotation bị sai trục mà mesh (đặc biệt mesh VRoid nhiều lớp quần áo) che mất chi tiết.

---

## Tóm tắt ưu tiên sửa (theo thứ tự tác động):

1. **Fix bug thiếu dấu trừ ở `wy`** (mục 4) — sửa nhanh nhất, khả năng cao giải quyết luôn phần lớn hiện tượng "tay chân không cử động".
2. **Fix world→local khi set quaternion theo chain** (mục 3) — đây là root cause thật sự của "chỉ hips xoay".
3. **Set `vrm.scene.rotation.y` một lần cố định**, tách biệt khỏi mọi rotation từ JSON (mục 1) — fix "không nhìn thẳng camera".
4. Sau khi 3 điều trên chạy ổn với 1 frame tĩnh → cân nhắc chuyển sang KalidoKit (mục 5) để giảm nợ kỹ thuật về lâu dài, đặc biệt nếu bạn sẽ mở rộng nhiều bài yoga pose khác nhau.
5. Chốt chiều mirror trái/phải bằng test thực tế (mục 6), đừng đoán.
