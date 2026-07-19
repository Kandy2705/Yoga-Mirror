import './styles.css';
import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { VRMLoaderPlugin, VRMUtils } from '@pixiv/three-vrm';
import * as Kalidokit from 'kalidokit';

const APP_ASSET_PREFIX = '/assets';
const DEFAULT_VRM_PATH = `${APP_ASSET_PREFIX}/models/yoga_avatar.vrm`;
const DEFAULT_META_PATH = `${APP_ASSET_PREFIX}/poses/mediapipe_video_3/meta.json`;

const LANDMARK_NAMES = [
  'nose', 'leftEyeInner', 'leftEye', 'leftEyeOuter', 'rightEyeInner', 'rightEye', 'rightEyeOuter',
  'leftEar', 'rightEar', 'mouthLeft', 'mouthRight',
  'leftShoulder', 'rightShoulder', 'leftElbow', 'rightElbow', 'leftWrist', 'rightWrist',
  'leftPinky', 'rightPinky', 'leftIndex', 'rightIndex', 'leftThumb', 'rightThumb',
  'leftHip', 'rightHip', 'leftKnee', 'rightKnee', 'leftAnkle', 'rightAnkle',
  'leftHeel', 'rightHeel', 'leftFootIndex', 'rightFootIndex',
];
const LANDMARK = Object.fromEntries(LANDMARK_NAMES.map((name, index) => [name, index]));
const POSE_CONNECTIONS = [
  [11, 12], [11, 13], [13, 15], [15, 17], [15, 19], [15, 21], [17, 19],
  [12, 14], [14, 16], [16, 18], [16, 20], [16, 22], [18, 20],
  [11, 23], [12, 24], [23, 24], [23, 25], [25, 27], [27, 29], [29, 31], [27, 31],
  [24, 26], [26, 28], [28, 30], [30, 32], [28, 32],
  [0, 2], [2, 7], [0, 5], [5, 8],
];
const HUMANOID_BONES = [
  'hips', 'spine', 'chest', 'upperChest', 'neck', 'head',
  'leftShoulder', 'leftUpperArm', 'leftLowerArm', 'leftHand',
  'rightShoulder', 'rightUpperArm', 'rightLowerArm', 'rightHand',
  'leftUpperLeg', 'leftLowerLeg', 'leftFoot', 'leftToes',
  'rightUpperLeg', 'rightLowerLeg', 'rightFoot', 'rightToes',
  'leftThumbMetacarpal', 'leftThumbProximal', 'leftThumbDistal',
  'leftIndexProximal', 'leftIndexIntermediate', 'leftIndexDistal',
  'rightThumbMetacarpal', 'rightThumbProximal', 'rightThumbDistal',
  'rightIndexProximal', 'rightIndexIntermediate', 'rightIndexDistal',
];
// Camera-facing mirrored map verified in Mapping Studio for the current yoga data.
// Keep mirror checkbox = false: the explicit cross-side entries below are the actual mapping.
const DEFAULT_MAPPING = {
  head: 'nose',
  leftUpperArm: 'rightShoulder',
  leftLowerArm: 'rightElbow',
  leftHand: 'rightWrist',
  rightUpperArm: 'leftShoulder',
  rightLowerArm: 'leftElbow',
  rightHand: 'leftWrist',
  leftThumbProximal: 'rightThumb',
  leftIndexProximal: 'rightPinky',
  leftIndexDistal: 'rightIndex',
  rightThumbProximal: 'leftIndex',
  rightIndexProximal: 'leftPinky',
  rightIndexDistal: 'leftIndex',
  leftUpperLeg: 'rightHip',
  leftLowerLeg: 'rightKnee',
  leftFoot: 'rightAnkle',
  rightUpperLeg: 'leftHip',
  rightLowerLeg: 'leftKnee',
  rightFoot: 'leftAnkle',
  rightIndexIntermediate: 'leftIndex',
};

const $ = (id) => document.getElementById(id);
const tmpV = new THREE.Vector3();
const raycaster = new THREE.Raycaster();
const pointer = new THREE.Vector2();

let renderer, scene, camera, controls, vrm, mixerRoot;
let poseGroup = new THREE.Group(); // JSON skeleton offset (side panel style)
let poseOnVrmGroup = new THREE.Group(); // JSON landmarks painted ON the VRM body
let boneNodeGroup = new THREE.Group();
let boneLabelGroup = new THREE.Group();
let landmarkLabelGroup = new THREE.Group();
let boneHelper;
/** @type {{ name: string, mesh: THREE.Mesh, bone: THREE.Object3D }[]} */
let boneNodes = [];
/** @type {{ mesh: THREE.Mesh, landmark: object, index: number, name: string }[]} */
let landmarkNodes = [];
let frames = [];
let currentFrameIndex = 0;
let playing = false;
let speed = 1;
let lastT = 0;
let mapping = structuredClone(DEFAULT_MAPPING);
let selectedBone = null;
let mirror = false; // anatomical export by default (matches DEFAULT_MAPPING)
let displayMode = 'both';
let retargetMode = 'idle';
let solverMode = 'ik';
let showNameLabels = false;
let landmarksOnVrm = false; // chấm JSON thẳng lên người VRM
let showSideJson = true; // skeleton JSON bên cạnh (offset)
let fitMappedPoints = true; // scale/translate JSON by mapped bone pairs
let snapMappedLandmarks = false; // force mapped JSON dots to VRM bone positions for checking
let flipJsonDepth = false; // MediaPipe world Z front/back can be opposite of VRM
let autoBodyYaw = true; // rotate the whole VRM toward JSON facing before limb correction
let invertBodyYaw = false; // user override when MediaPipe handedness chooses the opposite facing normal
let bodyYaw = 0;
let hoverInfo = null;
const calibratedRestDirs = new Map();
const restPoseQuats = new Map();
const playbackRetargetAlpha = 0.5;
const debugRetargetAlpha = 1.0;

function currentRetargetAlpha(baseAlpha = playbackRetargetAlpha) {
  return playing ? baseAlpha : debugRetargetAlpha;
}

const _parentQ = new THREE.Quaternion();
const _dir = new THREE.Vector3();
const _rest = new THREE.Vector3();
const _desiredQ = new THREE.Quaternion();

const boneDotGeo = new THREE.SphereGeometry(0.022, 14, 14);
const boneDotMat = new THREE.MeshBasicMaterial({ color: 0x38bdf8, depthTest: true });
const boneDotHotMat = new THREE.MeshBasicMaterial({ color: 0xfde047, depthTest: true });
const boneDotSelMat = new THREE.MeshBasicMaterial({ color: 0x22c55e, depthTest: true });
const lmDotGeo = new THREE.SphereGeometry(0.02, 12, 12);
const lmOnVrmGeo = new THREE.SphereGeometry(0.028, 14, 14);
const lmOnVrmMat = new THREE.MeshBasicMaterial({
  color: 0xff4d6d,
  depthTest: false,
  transparent: true,
  opacity: 0.95,
});
const lmOnVrmSelMat = new THREE.MeshBasicMaterial({
  color: 0x4ade80,
  depthTest: false,
  transparent: true,
  opacity: 1,
});

document.querySelector('#app').innerHTML = `
<header>
  <strong>YogaMirror Mapping Studio</strong>
  <span id="status">Booting…</span>
</header>
<main>
  <section id="viewport">
    <canvas id="three"></canvas>
    <div id="labelLayer"></div>
    <div id="hoverTip"></div>
    <div id="hint">Hồng = JSON lên VRM (giữ shape + chạm đất) · Xanh = bone VRM · Cam = JSON gốc bên cạnh · Flip 180° chỉ quay Y không bẻ xương</div>
  </section>
  <aside>
    <section class="card">
      <h2>Files</h2>
      <button id="loadDefault">Load default assets</button>
      <label>VRM <input id="vrmFile" type="file" accept=".vrm"></label>
      <label>Pose JSON/meta/chunk <input id="poseFile" type="file" accept=".json" multiple></label>
      <input id="assetPath" value="assets/poses/mediapipe_video_3/meta.json">
      <button id="loadPath">Load asset path</button>
    </section>
    <section class="card">
      <h2>View</h2>
      <select id="mode">
        <option value="both">Both overlay</option>
        <option value="vrm">VRM only</option>
        <option value="json">JSON skeleton only</option>
      </select>
      <label><input id="mirror" type="checkbox"> Mirror L/R in export (off = anatomical)</label>
      <label><input id="face" type="checkbox" checked> Show face landmarks</label>
      <label><input id="nameLabels" type="checkbox"> Show name labels (can clutter)</label>
      <label><input id="lmOnVrm" type="checkbox"> Chấm mốc JSON lên người VRM</label>
      <label><input id="sideJson" type="checkbox" checked> JSON skeleton bên cạnh (offset)</label>
      <label><input id="flipJsonDepth" type="checkbox"> Đảo chiều sâu JSON Z (sửa trước/sau)</label>
      <label><input id="fitMappedPoints" type="checkbox" checked> Fit JSON bằng mapped bone points</label>
      <label><input id="snapMapped" type="checkbox"> Ép mapped JSON trùng bone VRM</label>
      <label><input id="autoBodyYaw" type="checkbox" checked> Xoay nguyên thân VRM theo hướng JSON</label>
      <label><input id="invertBodyYaw" type="checkbox"> Đảo hướng xoay thân VRM</label>
      <label><input id="flipJsonFacing" type="checkbox"> Xoay JSON 180° quanh Y (giữ shape)</label>
      <label>Retarget solver <select id="solverMode"><option value="ik" selected>IK solver (no Kalidokit)</option><option value="hybrid">Kalidokit + correction</option></select></label>
      <label><input id="yawMatchShoulders" type="checkbox"> Khớp hướng vai JSON↔VRM (chỉ yaw Y)</label>
    </section>
    <section class="card">
      <h2>Playback</h2>
      <button id="play">Play</button>
      <input id="scrub" type="range" min="0" max="0" value="0">
      <label>Speed <input id="speed" type="number" min="0.1" max="4" step="0.1" value="1"></label>
      <div id="time"></div>
    </section>
    <section class="card mapping">
      <h2>Mapping</h2>
      <div class="columns">
        <div><h3>VRM bones</h3><div id="bones"></div></div>
        <div><h3>MediaPipe landmarks</h3><div id="landmarks"></div></div>
      </div>
    </section>
    <section class="card"><h2>Debug</h2><pre id="debug"></pre></section>
    <section class="card">
      <h2>Export</h2>
      <button id="downloadMapping">Download mapping JSON</button>
      <button id="copySnippet">Copy BONE_LANDMARK_MAP</button>
      <textarea id="exportText" spellcheck="false"></textarea>
    </section>
  </aside>
</main>`;

initScene();
initUi();
renderMappingLists();
loadDefaults();
animate(0);

function setStatus(s) {
  $('status').textContent = s;
}

function initScene() {
  renderer = new THREE.WebGLRenderer({ canvas: $('three'), antialias: true, alpha: false });
  renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  scene = new THREE.Scene();
  scene.background = new THREE.Color(0x111827);
  camera = new THREE.PerspectiveCamera(35, 1, 0.05, 50);
  camera.position.set(0, 1.15, 3.6);
  controls = new OrbitControls(camera, renderer.domElement);
  controls.target.set(0, 0.95, 0);
  controls.update();
  scene.add(new THREE.GridHelper(4, 20, 0x334155, 0x1f2937));
  scene.add(new THREE.HemisphereLight(0xffffff, 0x334155, 1.2));
  const d = new THREE.DirectionalLight(0xffffff, 1);
  d.position.set(2, 4, 3);
  scene.add(d);
  mixerRoot = new THREE.Group();
  scene.add(mixerRoot);
  scene.add(poseGroup);
  scene.add(poseOnVrmGroup);
  scene.add(boneNodeGroup);
  scene.add(boneLabelGroup);
  scene.add(landmarkLabelGroup);
  addDropZone();
  addEventListener('resize', resize);
  const canvas = $('three');
  canvas.addEventListener('pointermove', onPointerMove);
  canvas.addEventListener('pointerleave', () => hideHoverTip());
  canvas.addEventListener('click', onPointerClick);
  resize();
}

function initUi() {
  $('loadDefault').onclick = loadDefaults;
  $('loadPath').onclick = () => loadPoseFromPath($('assetPath').value);
  $('vrmFile').onchange = (e) => loadVrmFile(e.target.files[0]);
  $('poseFile').onchange = (e) => loadPoseFiles([...e.target.files]);
  $('play').onclick = () => {
    playing = !playing;
    $('play').textContent = playing ? 'Pause' : 'Play';
  };
  $('scrub').oninput = (e) => setFrame(+e.target.value);
  $('speed').oninput = (e) => { speed = +e.target.value || 1; };
  $('mode').onchange = (e) => {
    displayMode = e.target.value;
    updateVisibility();
  };
  $('mirror').onchange = (e) => {
    mirror = e.target.checked;
    updateExport();
  };
  $('face').onchange = () => {
    renderLandmarkList();
    if (frames[currentFrameIndex]) drawPose(frames[currentFrameIndex]);
  };
  $('nameLabels').onchange = (e) => {
    showNameLabels = e.target.checked;
    refreshLabelVisibility();
  };
  $('lmOnVrm').onchange = (e) => {
    landmarksOnVrm = e.target.checked;
    if (frames[currentFrameIndex]) setFrame(currentFrameIndex);
    updateVisibility();
  };
  $('sideJson').onchange = (e) => {
    showSideJson = e.target.checked;
    if (frames[currentFrameIndex]) setFrame(currentFrameIndex);
    updateVisibility();
  };
  $('flipJsonDepth').onchange = (e) => {
    flipJsonDepth = e.target.checked;
    if (frames[currentFrameIndex]) setFrame(currentFrameIndex);
  };
  $('fitMappedPoints').onchange = (e) => {
    fitMappedPoints = e.target.checked;
    if (frames[currentFrameIndex]) setFrame(currentFrameIndex);
  };
  $('snapMapped').onchange = (e) => {
    snapMappedLandmarks = e.target.checked;
    if (frames[currentFrameIndex]) setFrame(currentFrameIndex);
  };
  $('autoBodyYaw').onchange = (e) => {
    autoBodyYaw = e.target.checked;
    if (!autoBodyYaw) {
      bodyYaw = 0;
      if (mixerRoot) mixerRoot.rotation.y = 0;
    }
    if (frames[currentFrameIndex]) setFrame(currentFrameIndex);
  };
  $('invertBodyYaw').onchange = (e) => {
    invertBodyYaw = e.target.checked;
    bodyYaw = 0;
    if (frames[currentFrameIndex]) setFrame(currentFrameIndex);
  };
  $('flipJsonFacing').onchange = () => {
    if (frames[currentFrameIndex]) setFrame(currentFrameIndex);
  };
  $('solverMode').onchange = (e) => {
    solverMode = e.target.value;
    bodyYaw = 0;
    if (frames[currentFrameIndex]) setFrame(currentFrameIndex);
  };
  $('yawMatchShoulders').onchange = () => {
    if (frames[currentFrameIndex]) setFrame(currentFrameIndex);
  };
  $('downloadMapping').onclick = downloadMapping;
  $('copySnippet').onclick = () => navigator.clipboard.writeText(makeSnippet());
}

async function loadDefaults() {
  await loadVrmPath(DEFAULT_VRM_PATH);
  await loadPoseFromPath(DEFAULT_META_PATH);
}

async function loadVrmPath(path) {
  setStatus(`Loading VRM ${path}`);
  const loader = new GLTFLoader();
  loader.register((p) => new VRMLoaderPlugin(p));
  const gltf = await loader.loadAsync(path);
  if (vrm) mixerRoot.remove(vrm.scene);
  vrm = gltf.userData.vrm;
  VRMUtils.removeUnnecessaryVertices(gltf.scene);
  VRMUtils.removeUnnecessaryJoints(gltf.scene);
  vrm.scene.rotation.y = Math.PI;
  normalize(vrm.scene);
  mixerRoot.add(vrm.scene);
  if (boneHelper?.parent) boneHelper.parent.remove(boneHelper);
  boneHelper = new THREE.SkeletonHelper(vrm.scene);
  boneHelper.material.color.set(0x38bdf8);
  scene.add(boneHelper);
  captureRestPose();
  calibrateRestDirections();
  createBoneNodesAndLabels();
  setStatus('VRM loaded');
  updateVisibility();
  if (frames[currentFrameIndex]) setFrame(currentFrameIndex);
}

async function loadVrmFile(file) {
  if (!file) return;
  await loadVrmPath(URL.createObjectURL(file));
}

function normalize(obj) {
  const box = new THREE.Box3().setFromObject(obj);
  const size = new THREE.Vector3();
  const center = new THREE.Vector3();
  box.getSize(size);
  box.getCenter(center);
  obj.position.sub(center);
  obj.scale.setScalar(1.8 / Math.max(size.y, 0.01));
  obj.position.y += 0.9;
}

async function loadPoseFromPath(path) {
  const clean = '/' + path.replace(/^\//, '').replace(/^Assets\//, 'assets/');
  const data = await (await fetch(clean)).json();
  if (data.chunks) {
    const loaded = [];
    for (const c of data.chunks) {
      const chunkPath = '/' + String(c.asset).replace(/^\//, '').replace(/^Assets\//i, 'assets/');
      const chunk = await (await fetch(chunkPath)).json();
      loaded.push(...(chunk.frames || []));
    }
    frames = loaded;
  } else {
    frames = data.frames || [];
  }
  afterPoseLoad();
}

async function loadPoseFiles(files) {
  const jsons = await Promise.all(
    files.map((f) => f.text().then((t) => ({ name: f.name, data: JSON.parse(t) }))),
  );
  frames = jsons
    .flatMap((x) => x.data.frames || [])
    .sort((a, b) => (a.timestampMs || 0) - (b.timestampMs || 0));
  const meta = jsons.find((x) => x.data.chunks);
  if (meta && !frames.length) {
    alert('Meta selected without chunk files. Use asset path or select chunk JSON files too.');
  }
  afterPoseLoad();
}

function afterPoseLoad() {
  currentFrameIndex = 0;
  $('scrub').max = Math.max(0, frames.length - 1);
  setFrame(0);
  setStatus(`Đã tải ${frames.length} khung hình`);
}

function addDropZone() {
  document.body.ondragover = (e) => e.preventDefault();
  document.body.ondrop = (e) => {
    e.preventDefault();
    loadPoseFiles([...e.dataTransfer.files].filter((f) => f.name.endsWith('.json')));
  };
}

function setFrame(i) {
  if (!frames.length) return;
  currentFrameIndex = Math.max(0, Math.min(frames.length - 1, i));
  $('scrub').value = currentFrameIndex;
  // Retarget first so hip/scale align uses posed VRM bones, then paint landmarks on body
  applyRetarget(frames[currentFrameIndex]);
  updateBoneNodePositions();
  drawPose(frames[currentFrameIndex]);
  updateDebug(frames[currentFrameIndex]);
}

function animate(t) {
  requestAnimationFrame(animate);
  const dt = t - lastT || 0;
  lastT = t;
  if (playing && frames.length) {
    const step = Math.max(1, Math.round((dt / 100) * speed));
    setFrame((currentFrameIndex + step) % frames.length);
  } else {
    updateBoneNodePositions();
    projectLabels(boneLabelGroup);
    projectLabels(landmarkLabelGroup);
  }
  if (vrm) vrm.update(Math.min(0.05, dt / 1000));
  controls.update();
  renderer.render(scene, camera);
  projectLabels(boneLabelGroup);
  projectLabels(landmarkLabelGroup);
}

function resize() {
  const r = $('viewport').getBoundingClientRect();
  renderer.setSize(r.width, r.height, false);
  camera.aspect = r.width / Math.max(r.height, 1);
  camera.updateProjectionMatrix();
}

function lm(frame, i) {
  return frame?.landmarks?.find((l) => l.index === i);
}
function hasWorld(l) {
  return Number.isFinite(l?.wx) && Number.isFinite(l?.wy) && Number.isFinite(l?.wz);
}
function toWorldPoint(l) {
  if (!l) return null;
  if (hasWorld(l)) return new THREE.Vector3(l.wx, -l.wy, flipJsonDepth ? -l.wz : l.wz);
  return new THREE.Vector3((l.xNorm - 0.5) * 2, -(l.yNorm - 0.5) * 2, 0);
}

/**
 * Align JSON onto VRM WITHOUT warping the true JSON bone structure.
 *
 * Previous full 3D basis match (R = VrmBasis * inv(MpBasis)) twisted the
 * landmark graph when VRM pose ≠ JSON pose. We only allow:
 *   - uniform scale
 *   - optional yaw around Y (facing flip 0/180 or shoulder-line yaw)
 *   - translate so hip matches + feet sit on VRM ground (min ankle Y)
 *
 * Shape of JSON (relative joints) is preserved = rigid similarity transform.
 */
function computeJsonToVrmAlign(frame) {
  if (!vrm?.humanoid || !frame?.landmarks?.length) return null;

  const mpLHip = toWorldPoint(lm(frame, 23));
  const mpRHip = toWorldPoint(lm(frame, 24));
  const mpLSh = toWorldPoint(lm(frame, 11));
  const mpRSh = toWorldPoint(lm(frame, 12));
  const mpNose = toWorldPoint(lm(frame, 0));
  const mpLAn = toWorldPoint(lm(frame, 27));
  const mpRAn = toWorldPoint(lm(frame, 28));
  const mpHip = mid3(mpLHip, mpRHip);
  if (!mpHip) return null;

  const mpSh = mid3(mpLSh, mpRSh);
  const mpAn = mid3(mpLAn, mpRAn);
  let mpLen = 0;
  if (mpNose && mpAn) mpLen = mpNose.distanceTo(mpAn);
  if (!(mpLen > 1e-5) && mpSh) mpLen = mpSh.distanceTo(mpHip);
  if (!(mpLen > 1e-5)) return null;

  const hipsBone = vrm.humanoid.getNormalizedBoneNode('hips');
  if (!hipsBone) return null;
  const vrmHip = hipsBone.getWorldPosition(new THREE.Vector3());

  const headBone =
    vrm.humanoid.getNormalizedBoneNode('head') ||
    vrm.humanoid.getNormalizedBoneNode('neck');
  const footL =
    vrm.humanoid.getNormalizedBoneNode('leftFoot') ||
    vrm.humanoid.getNormalizedBoneNode('leftLowerLeg');
  const footR =
    vrm.humanoid.getNormalizedBoneNode('rightFoot') ||
    vrm.humanoid.getNormalizedBoneNode('rightLowerLeg');

  let vrmLen = 0;
  let groundY = 0;
  if (headBone && footL && footR) {
    const vh = headBone.getWorldPosition(new THREE.Vector3());
    const fl = footL.getWorldPosition(new THREE.Vector3());
    const fr = footR.getWorldPosition(new THREE.Vector3());
    const fm = mid3(fl, fr);
    if (fm) vrmLen = vh.distanceTo(fm);
    groundY = Math.min(fl.y, fr.y);
  }
  if (!(vrmLen > 1e-5)) {
    const ls = vrm.humanoid.getNormalizedBoneNode('leftUpperArm');
    const rs = vrm.humanoid.getNormalizedBoneNode('rightUpperArm');
    if (ls && rs) {
      vrmLen = ls.getWorldPosition(new THREE.Vector3())
        .distanceTo(rs.getWorldPosition(new THREE.Vector3())) * 2.2;
    }
  }
  if (!(vrmLen > 1e-5)) return null;

  const scale = vrmLen / mpLen;

  // Yaw only (around Y): keep JSON upright structure, optional face flip
  let yaw = 0;
  if ($('flipJsonFacing')?.checked) yaw = Math.PI;

  // Optional: align shoulder/hip line in XZ only (still pure yaw → rigid)
  if ($('yawMatchShoulders')?.checked) {
    const mpRight = (mpRHip && mpLHip)
      ? new THREE.Vector3().subVectors(mpRHip, mpLHip)
      : (mpRSh && mpLSh)
        ? new THREE.Vector3().subVectors(mpRSh, mpLSh)
        : null;
    const legL = vrm.humanoid.getNormalizedBoneNode('leftUpperLeg');
    const legR = vrm.humanoid.getNormalizedBoneNode('rightUpperLeg');
    const armL = vrm.humanoid.getNormalizedBoneNode('leftUpperArm');
    const armR = vrm.humanoid.getNormalizedBoneNode('rightUpperArm');
    let vrmRight = null;
    if (legL && legR) {
      vrmRight = new THREE.Vector3().subVectors(
        legR.getWorldPosition(new THREE.Vector3()),
        legL.getWorldPosition(new THREE.Vector3()),
      );
    } else if (armL && armR) {
      vrmRight = new THREE.Vector3().subVectors(
        armR.getWorldPosition(new THREE.Vector3()),
        armL.getWorldPosition(new THREE.Vector3()),
      );
    }
    if (mpRight && vrmRight) {
      mpRight.y = 0;
      vrmRight.y = 0;
      if (mpRight.lengthSq() > 1e-8 && vrmRight.lengthSq() > 1e-8) {
        const a = Math.atan2(mpRight.z, mpRight.x);
        const b = Math.atan2(vrmRight.z, vrmRight.x);
        yaw += b - a;
      }
    }
  }

  const rotation = new THREE.Quaternion().setFromAxisAngle(
    new THREE.Vector3(0, 1, 0),
    yaw,
  );

  // Ground: after scale+yaw, put lowest ankle/heel on VRM foot Y
  let yOffset = 0;
  const footIdx = [27, 28, 29, 30, 31, 32];
  let minLocalY = Infinity;
  for (const idx of footIdx) {
    const p = toWorldPoint(lm(frame, idx));
    if (!p) continue;
    const local = p.clone().sub(mpHip).multiplyScalar(scale);
    local.applyQuaternion(rotation);
    if (local.y < minLocalY) minLocalY = local.y;
  }
  if (Number.isFinite(minLocalY) && Number.isFinite(groundY)) {
    // worldY = local.y + vrmHip.y + yOffset  → want min = groundY
    yOffset = groundY - (minLocalY + vrmHip.y);
  }

  const align = {
    mpHip: mpHip.clone(),
    vrmHip: vrmHip.clone(),
    scale,
    rotation,
    yOffset,
    extraOffset: new THREE.Vector3(),
  };
  applyMappedPointFit(frame, align);
  return align;
}

function mid3(a, b) {
  if (!a || !b) return null;
  return new THREE.Vector3().addVectors(a, b).multiplyScalar(0.5);
}

function applyMappedPointFit(frame, align) {
  if (!fitMappedPoints || !vrm?.humanoid || !frame?.landmarks?.length || !align) return;
  const pairs = [];
  const usedLandmarks = new Set();
  for (const [boneName, lmName] of Object.entries(mapping)) {
    if (!lmName || usedLandmarks.has(lmName)) continue;
    const idx = LANDMARK[lmName];
    const bone = vrm.humanoid.getNormalizedBoneNode(boneName);
    const raw = idx != null ? toWorldPoint(lm(frame, idx)) : null;
    if (!bone || !raw) continue;
    usedLandmarks.add(lmName);
    const source = raw.clone().sub(align.mpHip);
    if (align.rotation) source.applyQuaternion(align.rotation);
    const target = bone.getWorldPosition(new THREE.Vector3()).sub(align.vrmHip);
    pairs.push({ source, target });
  }
  if (pairs.length < 3) return;

  const sourceCenter = new THREE.Vector3();
  const targetCenter = new THREE.Vector3();
  for (const pair of pairs) {
    sourceCenter.add(pair.source);
    targetCenter.add(pair.target);
  }
  sourceCenter.multiplyScalar(1 / pairs.length);
  targetCenter.multiplyScalar(1 / pairs.length);

  let sourceRms = 0;
  let targetRms = 0;
  for (const pair of pairs) {
    sourceRms += pair.source.distanceToSquared(sourceCenter);
    targetRms += pair.target.distanceToSquared(targetCenter);
  }
  sourceRms = Math.sqrt(sourceRms / pairs.length);
  targetRms = Math.sqrt(targetRms / pairs.length);
  if (sourceRms > 1e-5 && targetRms > 1e-5) {
    const mappedScale = THREE.MathUtils.clamp(targetRms / (sourceRms * align.scale), 0.35, 2.5);
    align.scale *= mappedScale;
  }

  const residual = new THREE.Vector3();
  for (const pair of pairs) {
    const fitted = pair.source.clone().multiplyScalar(align.scale);
    fitted.y += align.yOffset || 0;
    residual.add(pair.target.clone().sub(fitted));
  }
  align.extraOffset.copy(residual.multiplyScalar(1 / pairs.length));
}

function mappedBoneTargets() {
  const targets = new Map();
  if (!snapMappedLandmarks || !vrm?.humanoid) return targets;
  for (const [boneName, lmName] of Object.entries(mapping)) {
    if (!lmName || targets.has(lmName)) continue;
    const bone = vrm.humanoid.getNormalizedBoneNode(boneName);
    if (!bone) continue;
    targets.set(lmName, bone.getWorldPosition(new THREE.Vector3()));
  }
  return targets;
}

/** Map one landmark into VRM-aligned world space (preserves JSON shape). */
function toVrmBodyPoint(l, align) {
  const raw = toWorldPoint(l);
  if (!raw || !align) return null;
  const local = raw.clone().sub(align.mpHip).multiplyScalar(align.scale);
  if (align.rotation) local.applyQuaternion(align.rotation);
  local.y += align.yOffset || 0;
  if (align.extraOffset) local.add(align.extraOffset);
  return local.add(align.vrmHip);
}

function clearLabelGroup(group) {
  for (const child of [...group.children]) {
    child.element?.remove();
    group.remove(child);
  }
}

function clearBoneNodes() {
  while (boneNodeGroup.children.length) {
    const m = boneNodeGroup.children.pop();
    m.geometry?.dispose?.();
  }
  boneNodes = [];
}

function createBoneNodesAndLabels() {
  clearLabelGroup(boneLabelGroup);
  clearBoneNodes();
  if (!vrm?.humanoid) return;

  for (const name of HUMANOID_BONES) {
    const bone = vrm.humanoid.getNormalizedBoneNode(name);
    if (!bone) continue;
    const mesh = new THREE.Mesh(boneDotGeo, boneDotMat.clone());
    mesh.userData = { kind: 'vrm-bone', name };
    boneNodeGroup.add(mesh);
    boneNodes.push({ name, mesh, bone });

    const world = bone.getWorldPosition(new THREE.Vector3());
    addLabel(boneLabelGroup, name, world, 'bone', name, {
      kind: 'vrm-bone',
      name,
    });
  }
  refreshLabelVisibility();
}

function updateBoneNodePositions() {
  for (const n of boneNodes) {
    n.bone.getWorldPosition(tmpV);
    n.mesh.position.copy(tmpV);
    // keep label object at bone
    const lab = boneLabelGroup.children.find((c) => c.userData?.name === n.name);
    if (lab) lab.position.copy(tmpV);
  }
}

const REST_CHILD_BONE = {
  leftUpperArm: 'leftLowerArm',
  leftLowerArm: 'leftHand',
  rightUpperArm: 'rightLowerArm',
  rightLowerArm: 'rightHand',
  leftUpperLeg: 'leftLowerLeg',
  leftLowerLeg: 'leftFoot',
  rightUpperLeg: 'rightLowerLeg',
  rightLowerLeg: 'rightFoot',
  leftFoot: 'leftToes',
  rightFoot: 'rightToes',
};

function calibrateRestDirections() {
  calibratedRestDirs.clear();
  if (!vrm?.humanoid) return;
  vrm.scene.updateMatrixWorld(true);
  for (const [boneName, childName] of Object.entries(REST_CHILD_BONE)) {
    const bone = vrm.humanoid.getNormalizedBoneNode(boneName);
    const child = vrm.humanoid.getNormalizedBoneNode(childName);
    if (!bone?.parent || !child) continue;
    const from = bone.getWorldPosition(new THREE.Vector3());
    const to = child.getWorldPosition(new THREE.Vector3());
    const dir = to.sub(from);
    if (dir.lengthSq() < 1e-8) continue;
    bone.parent.getWorldQuaternion(_parentQ);
    dir.applyQuaternion(_parentQ.clone().invert()).normalize();
    calibratedRestDirs.set(boneName, dir.clone());
  }
}

function captureRestPose() {
  restPoseQuats.clear();
  if (!vrm?.humanoid) return;
  for (const name of HUMANOID_BONES) {
    const bone = vrm.humanoid.getNormalizedBoneNode(name);
    if (bone) restPoseQuats.set(name, bone.quaternion.clone());
  }
}

function resetVrmPoseToRest() {
  if (!vrm?.humanoid) return;
  for (const [name, quat] of restPoseQuats.entries()) {
    const bone = vrm.humanoid.getNormalizedBoneNode(name);
    if (bone) bone.quaternion.copy(quat);
  }
  vrm.scene.updateMatrixWorld(true);
  if (mixerRoot) mixerRoot.updateMatrixWorld(true);
}

function restDirForBone(boneName, planar) {
  const calibrated = calibratedRestDirs.get(boneName);
  const fallback = BONE_REST_DIR[boneName] || new THREE.Vector3(0, -1, 0);
  const rest = (calibrated || fallback).clone().normalize();
  if (planar) {
    rest.z = 0;
    if (rest.lengthSq() < 1e-8) rest.copy(fallback).normalize();
    else rest.normalize();
  }
  return rest;
}

function clearGroupMeshes(group) {
  while (group.children.length) {
    const c = group.children.pop();
    c.geometry?.dispose?.();
    if (c.material && !Array.isArray(c.material) && c.material !== lmOnVrmMat && c.material !== lmOnVrmSelMat) {
      c.material.dispose?.();
    }
  }
}

function drawPose(frame) {
  clearGroupMeshes(poseGroup);
  clearGroupMeshes(poseOnVrmGroup);
  clearLabelGroup(landmarkLabelGroup);
  landmarkNodes = [];
  if (!frame) return;

  const showFace = $('face')?.checked;
  const align = landmarksOnVrm ? computeJsonToVrmAlign(frame) : null;

  // ── A) Landmarks ON VRM body (pink dots + yellow stick figure) ──
  if (landmarksOnVrm && align) {
    const ptsOn = new Map();
    const snapTargets = mappedBoneTargets();
    const lineMat = new THREE.LineBasicMaterial({
      color: 0xff6b8a,
      transparent: true,
      opacity: 0.85,
      depthTest: false,
    });
    for (const l of frame.landmarks || []) {
      if (l.index < 11 && !showFace) continue;
      const p = snapTargets.get(l.name)?.clone() || toVrmBodyPoint(l, align);
      if (!p) continue;
      ptsOn.set(l.index, p.clone());

      const isMappedTarget =
        selectedBone && mapping[selectedBone] === l.name;
      const mesh = new THREE.Mesh(
        lmOnVrmGeo,
        isMappedTarget ? lmOnVrmSelMat : lmOnVrmMat,
      );
      mesh.position.copy(p);
      mesh.renderOrder = 10;
      mesh.userData = {
        kind: 'landmark',
        name: l.name,
        index: l.index,
        landmark: l,
        onVrm: true,
      };
      poseOnVrmGroup.add(mesh);
      landmarkNodes.push({ mesh, landmark: l, index: l.index, name: l.name });

      // short labels only on VRM body when name labels on, else small hit targets via mesh only
      if (showNameLabels) {
        addLabel(landmarkLabelGroup, `${l.index}`, p, 'landmark', l.name, {
          kind: 'landmark',
          name: l.name,
          index: l.index,
          landmark: l,
          onVrm: true,
        });
      }
    }
    for (const [a, b] of POSE_CONNECTIONS) {
      if (ptsOn.has(a) && ptsOn.has(b)) {
        const line = new THREE.Line(
          new THREE.BufferGeometry().setFromPoints([ptsOn.get(a), ptsOn.get(b)]),
          lineMat,
        );
        line.renderOrder = 9;
        poseOnVrmGroup.add(line);
      }
    }

    // Lines: mapped VRM bone (cyan) → aligned JSON landmark (pink) for selected / all mapped
    const linkMat = new THREE.LineBasicMaterial({
      color: 0xa78bfa,
      transparent: true,
      opacity: 0.65,
      depthTest: false,
    });
    for (const [boneName, lmName] of Object.entries(mapping)) {
      if (!lmName) continue;
      const bone = vrm?.humanoid?.getNormalizedBoneNode(boneName);
      const idx = LANDMARK[lmName];
      const lp = idx != null ? ptsOn.get(idx) : null;
      if (!bone || !lp) continue;
      const bp = bone.getWorldPosition(new THREE.Vector3());
      const line = new THREE.Line(
        new THREE.BufferGeometry().setFromPoints([bp, lp]),
        linkMat,
      );
      line.renderOrder = 11;
      poseOnVrmGroup.add(line);
    }
  }

  // ── B) Side JSON skeleton (orange, offset right) ──
  if (showSideJson) {
    const pts = new Map();
    const mat = new THREE.LineBasicMaterial({ color: 0xfacc15 });
    for (const l of frame.landmarks || []) {
      if (l.index < 11 && !showFace) continue;
      const p = toWorldPoint(l);
      if (!p) continue;
      p.multiplyScalar(1.8).add(new THREE.Vector3(1.35, 1, 0));
      pts.set(l.index, p.clone());

      const mapped = selectedBone && mapping[selectedBone] === l.name;
      const mesh = new THREE.Mesh(
        lmDotGeo,
        new THREE.MeshBasicMaterial({ color: mapped ? 0x22c55e : 0xf97316 }),
      );
      mesh.position.copy(p);
      mesh.userData = { kind: 'landmark', name: l.name, index: l.index, landmark: l };
      poseGroup.add(mesh);
      // Avoid double-counting for raycast if already on VRM list
      if (!landmarksOnVrm || !align) {
        landmarkNodes.push({ mesh, landmark: l, index: l.index, name: l.name });
      }

      addLabel(landmarkLabelGroup, `${l.index} ${l.name}`, p, 'landmark', l.name, {
        kind: 'landmark',
        name: l.name,
        index: l.index,
        landmark: l,
      });
    }
    for (const [a, b] of POSE_CONNECTIONS) {
      if (pts.has(a) && pts.has(b)) {
        const line = new THREE.Line(
          new THREE.BufferGeometry().setFromPoints([pts.get(a), pts.get(b)]),
          mat,
        );
        poseGroup.add(line);
      }
    }
  }

  refreshLabelVisibility();
  updateVisibility();
}

function addLabel(group, text, pos, kind, value, userData = {}) {
  const el = document.createElement('button');
  el.type = 'button';
  el.className = `label ${kind}`;
  el.textContent = text;
  el.onclick = (e) => {
    e.stopPropagation();
    if (kind === 'bone') selectBone(value);
    else mapSelected(value);
  };
  el.onpointerenter = () => showHoverFromUserData(userData, el);
  el.onpointerleave = () => hideHoverTip();
  const label = new CSS2DLike(el, pos);
  label.userData = { ...userData, name: value, kind };
  group.add(label);
}

class CSS2DLike extends THREE.Object3D {
  constructor(el, pos) {
    super();
    this.element = el;
    this.position.copy(pos);
    $('labelLayer').appendChild(el);
  }
  removeFromParent() {
    this.element?.remove();
    return super.removeFromParent();
  }
}

function projectLabels(group) {
  const r = $('viewport').getBoundingClientRect();
  const pad = 8;
  group.children.forEach((o) => {
    if (!o.element) return;
    const v = o.getWorldPosition(tmpV).project(camera);
    // behind camera
    if (v.z > 1 || v.z < -1) {
      o.element.style.display = 'none';
      return;
    }
    let x = (v.x * 0.5 + 0.5) * r.width;
    let y = (-v.y * 0.5 + 0.5) * r.height;
    // clamp inside viewport so never covers app header
    x = Math.min(r.width - pad, Math.max(pad, x));
    y = Math.min(r.height - pad, Math.max(pad, y));
    o.element.style.display = 'block';
    o.element.style.transform = `translate(${x}px, ${y}px) translate(-50%, -50%)`;
  });
}

function refreshLabelVisibility() {
  for (const o of boneLabelGroup.children) {
    o.element?.classList.toggle('hidden-text', !showNameLabels);
    if (!showNameLabels && o.element) o.element.textContent = '';
    if (showNameLabels && o.element) o.element.textContent = o.userData?.name || '';
  }
  for (const o of landmarkLabelGroup.children) {
    o.element?.classList.toggle('hidden-text', !showNameLabels);
    if (!showNameLabels && o.element) o.element.textContent = '';
    if (showNameLabels && o.element) {
      const n = o.userData?.name;
      const i = o.userData?.index;
      o.element.textContent = i != null ? `${i} ${n}` : n || '';
    }
  }
}

function renderMappingLists() {
  const b = $('bones');
  b.innerHTML = '';
  for (const name of HUMANOID_BONES) {
    const row = document.createElement('button');
    row.type = 'button';
    const target = mapping[name];
    row.textContent = `${name} → ${target || 'none'}`;
    if (!target) row.style.opacity = '0.75';
    row.onclick = () => selectBone(name);
    row.id = `bone-${name}`;
    // Double-click bone list = unmap
    row.ondblclick = (e) => {
      e.preventDefault();
      selectBone(name);
      mapSelected(null);
    };
    if (selectedBone === name) row.classList.add('selected');
    b.append(row);
  }
  renderLandmarkList();
  updateExport();
}

function renderLandmarkList() {
  const l = $('landmarks');
  l.innerHTML = '';

  // Unmap: gán bone đang chọn về none (xóa mapping sai)
  const noneBtn = document.createElement('button');
  noneBtn.type = 'button';
  noneBtn.id = 'lm-none';
  noneBtn.textContent = '∅ none (bỏ gán / unmap)';
  noneBtn.style.borderColor = '#f87171';
  noneBtn.style.color = '#fecaca';
  noneBtn.onclick = () => mapSelected(null);
  l.append(noneBtn);

  LANDMARK_NAMES.forEach((name, i) => {
    if (i < 11 && !$('face')?.checked) return;
    const row = document.createElement('button');
    row.type = 'button';
    row.textContent = `${i} ${name}`;
    row.onclick = () => mapSelected(name);
    l.append(row);
  });
}

function selectBone(name) {
  selectedBone = name;
  document.querySelectorAll('#bones button').forEach((x) => {
    x.classList.toggle('selected', x.id === `bone-${name}`);
  });
  for (const n of boneNodes) {
    n.mesh.material = n.name === name ? boneDotSelMat : boneDotMat;
  }
  if (frames[currentFrameIndex]) drawPose(frames[currentFrameIndex]);
}

/** @param {string|null} lmName - landmark name, or null to clear mapping */
function mapSelected(lmName) {
  if (!selectedBone) {
    setStatus('Chọn VRM bone trước, rồi chọn landmark (hoặc none)');
    return;
  }
  if (lmName == null || lmName === '' || lmName === 'none') {
    delete mapping[selectedBone];
    renderMappingLists();
    setFrame(currentFrameIndex);
    setStatus(`Unmapped ${selectedBone} → none`);
    return;
  }
  mapping[selectedBone] = lmName;
  renderMappingLists();
  setFrame(currentFrameIndex);
  setStatus(`Mapped ${selectedBone} → ${lmName}`);
}

function updateExport() {
  $('exportText').value =
    JSON.stringify({ schemaVersion: 'yoga-mirror-bone-landmark-map/1.0', mirror, mapping }, null, 2) +
    '\n\n' +
    makeSnippet();
}
function makeSnippet() {
  return `const BONE_LANDMARK_MAP = ${JSON.stringify(mapping, null, 2)};`;
}
function downloadMapping() {
  const a = document.createElement('a');
  a.href = URL.createObjectURL(new Blob([$('exportText').value], { type: 'application/json' }));
  a.download = 'yoga_mirror_bone_landmark_map.json';
  a.click();
}

function updateVisibility() {
  if (vrm?.scene) vrm.scene.visible = displayMode !== 'json';
  if (boneHelper) boneHelper.visible = displayMode !== 'json';
  boneNodeGroup.visible = displayMode !== 'json';
  boneLabelGroup.visible = displayMode !== 'json';
  // Side JSON (orange): only when not VRM-only
  poseGroup.visible = showSideJson && displayMode !== 'vrm';
  // Landmarks on VRM (pink): need VRM visible
  poseOnVrmGroup.visible = landmarksOnVrm && displayMode !== 'json';
  landmarkLabelGroup.visible =
    (showSideJson && displayMode !== 'vrm') ||
    (landmarksOnVrm && displayMode !== 'json' && showNameLabels);
}

/**
 * Hybrid retarget path per frame.
 * - world landmarks → Kalidokit base + mapping-driven direction correction
 * - else → planar direction chains only (mapping-driven)
 */
function applyRetarget(frame) {
  if (!vrm || !frame) return;
  resetVrmPoseToRest();
  if (solverMode === 'ik') {
    retargetMode = 'ik-solver';
    applyIkSolver(frame);
  } else {
    const worldCount = frame.landmarks?.filter(hasWorld).length || 0;
    const useWorld = worldCount >= 10;
    if (useWorld) {
      const ok = applyKalidokit(frame);
      retargetMode = ok ? 'kalidokit+direction-correction' : 'kalidokit-fail→planar';
      if (ok) {
        applyJsonBodyYaw(frame);
        applyDirectionChains(frame, false, 0.45);
      } else applyDirectionChains(frame, true);
    } else {
      retargetMode = 'planar-chain-only';
      applyJsonBodyYaw(frame);
      applyDirectionChains(frame, true);
    }
  }
  if (vrm.humanoid) vrm.humanoid.update(0);
}

function applyIkSolver(frame) {
  applyJsonBodyYaw(frame);
  applyIkTorso(frame);
  applyDirectionChains(frame, false, 1);
}

function applyIkTorso(frame) {
  const lHip = toWorldPoint(lm(frame, LANDMARK.leftHip));
  const rHip = toWorldPoint(lm(frame, LANDMARK.rightHip));
  const lSh = toWorldPoint(lm(frame, LANDMARK.leftShoulder));
  const rSh = toWorldPoint(lm(frame, LANDMARK.rightShoulder));
  const nose = toWorldPoint(lm(frame, LANDMARK.nose));
  const hipMid = mid3(lHip, rHip);
  const shMid = mid3(lSh, rSh);
  if (hipMid && shMid) {
    applyBoneWorldFromTo('hips', hipMid, shMid, false, 0.7);
    applyBoneWorldFromTo('spine', hipMid, shMid, false, 0.85);
    applyBoneWorldFromTo('chest', hipMid, shMid, false, 1);
    applyBoneWorldFromTo('upperChest', hipMid, shMid, false, 0.8);
  }
  if (shMid && nose) {
    applyBoneWorldFromTo('neck', shMid, nose, false, 0.65);
    applyBoneWorldFromTo('head', shMid, nose, false, 0.55);
  }
}

function shortestAngleDelta(from, to) {
  return Math.atan2(Math.sin(to - from), Math.cos(to - from));
}

function computeJsonBodyYaw(frame) {
  const lHip = toWorldPoint(lm(frame, LANDMARK.leftHip));
  const rHip = toWorldPoint(lm(frame, LANDMARK.rightHip));
  const lSh = toWorldPoint(lm(frame, LANDMARK.leftShoulder));
  const rSh = toWorldPoint(lm(frame, LANDMARK.rightShoulder));
  const hipMid = mid3(lHip, rHip);
  const shMid = mid3(lSh, rSh);
  if (!hipMid || !shMid) return null;

  const right = new THREE.Vector3();
  let rightCount = 0;
  if (lHip && rHip) { right.add(new THREE.Vector3().subVectors(rHip, lHip)); rightCount++; }
  if (lSh && rSh) { right.add(new THREE.Vector3().subVectors(rSh, lSh)); rightCount++; }
  if (!rightCount) return null;
  right.multiplyScalar(1 / rightCount);

  const up = new THREE.Vector3().subVectors(shMid, hipMid);
  if (right.lengthSq() < 1e-8 || up.lengthSq() < 1e-8) return null;

  let forward = new THREE.Vector3().crossVectors(right, up);
  forward.y = 0;

  // Feet give a stronger front/back hint when the torso normal is ambiguous.
  const lHeel = toWorldPoint(lm(frame, LANDMARK.leftHeel));
  const lToe = toWorldPoint(lm(frame, LANDMARK.leftFootIndex));
  const rHeel = toWorldPoint(lm(frame, LANDMARK.rightHeel));
  const rToe = toWorldPoint(lm(frame, LANDMARK.rightFootIndex));
  const footForward = new THREE.Vector3();
  let footCount = 0;
  if (lHeel && lToe) { footForward.add(new THREE.Vector3().subVectors(lToe, lHeel)); footCount++; }
  if (rHeel && rToe) { footForward.add(new THREE.Vector3().subVectors(rToe, rHeel)); footCount++; }
  footForward.y = 0;
  if (footCount && footForward.lengthSq() > 1e-8) {
    footForward.normalize();
    if (forward.lengthSq() < 1e-8 || Math.abs(forward.normalize().dot(footForward)) < 0.35) {
      forward.copy(footForward);
    }
  }

  if (forward.lengthSq() < 1e-8) return null;
  forward.normalize();
  let yaw = Math.atan2(forward.x, forward.z);
  if (invertBodyYaw) yaw = -yaw;
  return yaw;
}

function applyJsonBodyYaw(frame) {
  if (!mixerRoot) return;
  if (!autoBodyYaw) {
    mixerRoot.rotation.y = 0;
    return;
  }
  const targetYaw = computeJsonBodyYaw(frame);
  if (targetYaw == null) return;
  bodyYaw += shortestAngleDelta(bodyYaw, targetYaw) * currentRetargetAlpha(0.35);
  mixerRoot.rotation.y = bodyYaw;
  mixerRoot.updateMatrixWorld(true);
}

function arr(frame, world) {
  const out = [];
  for (let i = 0; i < 33; i++) {
    const l = lm(frame, i) || {};
    out[i] = world
      ? { x: l.wx || 0, y: l.wy || 0, z: l.wz || 0, visibility: l.visibility ?? 1 }
      : { x: l.xNorm || 0, y: l.yNorm || 0, z: l.z || 0, visibility: l.visibility ?? 1 };
  }
  return out;
}

/** @returns {boolean} success */
function applyKalidokit(frame) {
  try {
    // MediaPipe world AS-IS (no axis flip) — same as kalidokit_solver / app notes
    const rig = Kalidokit.Pose.solve(arr(frame, true), arr(frame, false), {
      runtime: 'mediapipe',
      video: null,
      enableLegs: true,
    });
    if (!rig || (!rig.Hips && !rig.RightUpperArm)) return false;

    // Official DIRECT map (anatomical). If mirror export is on, swap limb sides.
    const direct = {
      Hips: 'hips', Spine: 'spine', Chest: 'chest', Neck: 'neck', Head: 'head',
      LeftUpperArm: 'leftUpperArm', LeftLowerArm: 'leftLowerArm', LeftHand: 'leftHand',
      RightUpperArm: 'rightUpperArm', RightLowerArm: 'rightLowerArm', RightHand: 'rightHand',
      LeftUpperLeg: 'leftUpperLeg', LeftLowerLeg: 'leftLowerLeg',
      RightUpperLeg: 'rightUpperLeg', RightLowerLeg: 'rightLowerLeg',
    };
    const mirrorMap = {
      Hips: 'hips', Spine: 'spine', Chest: 'chest', Neck: 'neck', Head: 'head',
      LeftUpperArm: 'rightUpperArm', LeftLowerArm: 'rightLowerArm', LeftHand: 'rightHand',
      RightUpperArm: 'leftUpperArm', RightLowerArm: 'leftLowerArm', RightHand: 'leftHand',
      LeftUpperLeg: 'rightUpperLeg', LeftLowerLeg: 'rightLowerLeg',
      RightUpperLeg: 'leftUpperLeg', RightLowerLeg: 'leftLowerLeg',
    };
    const map = mirror ? mirrorMap : direct;

    // Hips first (body yaw lives here)
    const hipsRot = rig.Hips && (rig.Hips.rotation || rig.Hips);
    if (hipsRot?.x != null) {
      const bone = vrm.humanoid.getNormalizedBoneNode('hips');
      if (bone) {
        const e = new THREE.Euler(hipsRot.x, hipsRot.y, hipsRot.z, 'XYZ');
        bone.quaternion.slerp(new THREE.Quaternion().setFromEuler(e), currentRetargetAlpha(0.55));
        bone.updateMatrixWorld(true);
      }
    }
    if (rig.Spine) {
      const bone = vrm.humanoid.getNormalizedBoneNode('spine');
      if (bone) {
        const s = rig.Spine;
        const e = new THREE.Euler(s.x * 0.85, (s.y || 0) * 0.4, (s.z || 0) * 0.85, 'XYZ');
        bone.quaternion.slerp(new THREE.Quaternion().setFromEuler(e), currentRetargetAlpha());
        bone.updateMatrixWorld(true);
      }
      const chest = vrm.humanoid.getNormalizedBoneNode('chest');
      if (chest) {
        const s = rig.Spine;
        const e = new THREE.Euler(s.x * 0.45, (s.y || 0) * 0.2, (s.z || 0) * 0.45, 'XYZ');
        chest.quaternion.slerp(new THREE.Quaternion().setFromEuler(e), currentRetargetAlpha());
        chest.updateMatrixWorld(true);
      }
    }

    for (const [k, bn] of Object.entries(map)) {
      if (k === 'Hips' || k === 'Spine' || k === 'Chest') continue;
      const r = rig[k];
      const b = vrm.humanoid.getNormalizedBoneNode(bn);
      if (!r || !b || r.x == null) continue;
      const e = new THREE.Euler(r.x || 0, r.y || 0, r.z || 0, 'XYZ');
      b.quaternion.slerp(new THREE.Quaternion().setFromEuler(e), currentRetargetAlpha());
      b.updateMatrixWorld(true);
    }
    return true;
  } catch (e) {
    console.warn('[mapping-studio] Kalidokit failed', e);
    return false;
  }
}

/** Rest directions for normalized VRM bones */
const BONE_REST_DIR = {
  hips: new THREE.Vector3(0, 1, 0),
  spine: new THREE.Vector3(0, 1, 0),
  chest: new THREE.Vector3(0, 1, 0),
  upperChest: new THREE.Vector3(0, 1, 0),
  neck: new THREE.Vector3(0, 1, 0),
  head: new THREE.Vector3(0, 1, 0),
  leftUpperArm: new THREE.Vector3(-1, 0, 0),
  leftLowerArm: new THREE.Vector3(-1, 0, 0),
  leftHand: new THREE.Vector3(-1, 0, 0),
  rightUpperArm: new THREE.Vector3(1, 0, 0),
  rightLowerArm: new THREE.Vector3(1, 0, 0),
  rightHand: new THREE.Vector3(1, 0, 0),
  leftUpperLeg: new THREE.Vector3(0, -1, 0),
  leftLowerLeg: new THREE.Vector3(0, -1, 0),
  leftFoot: new THREE.Vector3(0, -1, 0),
  leftToes: new THREE.Vector3(0, 0, -1),
  rightUpperLeg: new THREE.Vector3(0, -1, 0),
  rightLowerLeg: new THREE.Vector3(0, -1, 0),
  rightFoot: new THREE.Vector3(0, -1, 0),
  rightToes: new THREE.Vector3(0, 0, -1),
};

/**
 * Direction chain from mapping: bone maps to proximal joint;
 * segment = mapping[bone] → mapping[nextBone] (or toes).
 * planar=true forces z=0 (anti-twist without world).
 */
function footGuideLandmarksForBone(footBoneName) {
  const ankleName = mapping[footBoneName];
  if (ankleName?.startsWith('right')) return { heel: 'rightHeel', toe: 'rightFootIndex' };
  if (ankleName?.startsWith('left')) return { heel: 'leftHeel', toe: 'leftFootIndex' };
  return footBoneName.startsWith('right')
    ? { heel: 'rightHeel', toe: 'rightFootIndex' }
    : { heel: 'leftHeel', toe: 'leftFootIndex' };
}

function pushMappedToesSegment(segs, toesBoneName, footBoneName) {
  const toeTarget = mapping[toesBoneName];
  // If toes are intentionally left unmapped, do not rotate the toe bone: on this
  // VRM the toes can collapse the foot chain. The parent foot still receives a
  // heel→footIndex guide so lifted-foot poses point the toe in the right direction.
  if (toeTarget) segs.push([toesBoneName, mapping[footBoneName], toeTarget]);
}

function applyDirectionChains(frame, planar, correctionScale = 1) {
  const leftFootGuide = footGuideLandmarksForBone('leftFoot');
  const rightFootGuide = footGuideLandmarksForBone('rightFoot');
  // [bone, fromLmKey, toLmKey] using mapping table for lm names
  const segs = [
    ['leftUpperArm', mapping.leftUpperArm, mapping.leftLowerArm],
    ['leftLowerArm', mapping.leftLowerArm, mapping.leftHand],
    ['leftHand', mapping.leftHand, mapping.leftIndexProximal || mapping.leftThumbProximal],
    ['rightUpperArm', mapping.rightUpperArm, mapping.rightLowerArm],
    ['rightLowerArm', mapping.rightLowerArm, mapping.rightHand],
    ['rightHand', mapping.rightHand, mapping.rightIndexProximal || mapping.rightThumbProximal],
    ['leftUpperLeg', mapping.leftUpperLeg, mapping.leftLowerLeg],
    ['leftLowerLeg', mapping.leftLowerLeg, mapping.leftFoot],
    ['leftFoot', leftFootGuide.heel, mapping.leftToes || leftFootGuide.toe],
    ['rightUpperLeg', mapping.rightUpperLeg, mapping.rightLowerLeg],
    ['rightLowerLeg', mapping.rightLowerLeg, mapping.rightFoot],
    ['rightFoot', rightFootGuide.heel, mapping.rightToes || rightFootGuide.toe],
  ];
  pushMappedToesSegment(segs, 'leftToes', 'leftFoot');
  pushMappedToesSegment(segs, 'rightToes', 'rightFoot');

  for (const [boneName, fromName, toName] of segs) {
    if (!fromName || !toName || fromName === toName) continue;
    applyBoneFromTo(boneName, fromName, toName, frame, planar, correctionScale);
  }
}

function applyBoneFromTo(boneName, fromLmName, toLmName, frame, planar, correctionScale = 1) {
  const fromL = lm(frame, LANDMARK[fromLmName]);
  const toL = lm(frame, LANDMARK[toLmName]);
  const from = toWorldPoint(fromL);
  const to = toWorldPoint(toL);
  applyBoneWorldFromTo(boneName, from, to, planar, correctionScale);
}

function applyBoneWorldFromTo(boneName, from, to, planar, correctionScale = 1) {
  const bone = vrm.humanoid.getNormalizedBoneNode(boneName);
  if (!bone?.parent || !from || !to) return;

  _dir.subVectors(to, from);
  if (planar) _dir.z = 0;
  if (_dir.lengthSq() < 1e-8) return;
  _dir.normalize();

  // world dir → parent-local
  bone.parent.getWorldQuaternion(_parentQ);
  _dir.applyQuaternion(_parentQ.clone().invert());
  if (_dir.lengthSq() < 1e-8) return;
  _dir.normalize();

  _rest.copy(restDirForBone(boneName, planar));

  const dot = THREE.MathUtils.clamp(_rest.dot(_dir), -1, 1);
  if (dot > 0.9995) return;
  if (dot < -0.9995) {
    _desiredQ.setFromAxisAngle(new THREE.Vector3(0, 0, 1), Math.PI);
  } else {
    _desiredQ.setFromUnitVectors(_rest, _dir);
  }
  bone.quaternion.slerp(_desiredQ, currentRetargetAlpha(0.5 * correctionScale));
  bone.updateMatrixWorld(true);
}

function updateDebug(frame) {
  const val = (i) => {
    const l = lm(frame, i);
    if (!l) return 'missing';
    return `z:${fmt(l.z)} wx:${fmt(l.wx)} wy:${fmt(l.wy)} wz:${fmt(l.wz)}`;
  };
  const fmt = (v) => (v == null || !Number.isFinite(+v) ? 'null' : (+v).toFixed(3));
  const ls = toWorldPoint(lm(frame, 11));
  const rs = toWorldPoint(lm(frame, 12));
  $('time').textContent = frame
    ? `${currentFrameIndex + 1}/${frames.length} @ ${frame.timestampMs ?? 0}ms`
    : '';
  $('debug').textContent =
    `mode: ${retargetMode} yaw:${bodyYaw.toFixed(2)}\n` +
    `VRM bone nodes: ${boneNodes.length}\n` +
    `L shoulder ${val(11)}\nR shoulder ${val(12)}\n` +
    `L hip ${val(23)}\nR hip ${val(24)}\n` +
    `L ankle ${val(27)}\nR ankle ${val(28)}\n` +
    `shΔxy: ${ls && rs ? `${(ls.x - rs.x).toFixed(3)}, ${(ls.y - rs.y).toFixed(3)}` : 'n/a'}`;
}

// ─── Hover / raycast ─────────────────────────────────────────────────────────
function setPointerFromEvent(e) {
  const r = $('three').getBoundingClientRect();
  pointer.x = ((e.clientX - r.left) / r.width) * 2 - 1;
  pointer.y = -((e.clientY - r.top) / r.height) * 2 + 1;
}

function onPointerMove(e) {
  setPointerFromEvent(e);
  raycaster.setFromCamera(pointer, camera);
  const targets = [];
  if (displayMode !== 'json') targets.push(...boneNodes.map((n) => n.mesh));
  if (displayMode !== 'vrm') targets.push(...landmarkNodes.map((n) => n.mesh));
  const hits = raycaster.intersectObjects(targets, false);
  // reset colors
  for (const n of boneNodes) {
    n.mesh.material = n.name === selectedBone ? boneDotSelMat : boneDotMat;
  }
  if (!hits.length) {
    hideHoverTip();
    return;
  }
  const hit = hits[0].object;
  const ud = hit.userData;
  if (ud.kind === 'vrm-bone') {
    hit.material = boneDotHotMat;
    showHoverTip(formatBoneTip(ud.name), e);
  } else if (ud.kind === 'landmark') {
    showHoverTip(formatLandmarkTip(ud.landmark || ud), e);
  }
}

function onPointerClick(e) {
  setPointerFromEvent(e);
  raycaster.setFromCamera(pointer, camera);
  const targets = [];
  if (displayMode !== 'json') targets.push(...boneNodes.map((n) => n.mesh));
  if (displayMode !== 'vrm') targets.push(...landmarkNodes.map((n) => n.mesh));
  const hits = raycaster.intersectObjects(targets, false);
  if (!hits.length) return;
  const ud = hits[0].object.userData;
  if (ud.kind === 'vrm-bone') selectBone(ud.name);
  else if (ud.kind === 'landmark') mapSelected(ud.name);
}

function formatBoneTip(name) {
  const bone = vrm?.humanoid?.getNormalizedBoneNode(name);
  if (!bone) return `VRM bone: ${name}\n(missing)`;
  bone.getWorldPosition(tmpV);
  const e = bone.rotation;
  const q = bone.quaternion;
  const mapped = mapping[name] || '—';
  return [
    `VRM bone: ${name}`,
    `mapped → ${mapped}`,
    `world pos: ${tmpV.x.toFixed(3)}, ${tmpV.y.toFixed(3)}, ${tmpV.z.toFixed(3)}`,
    `local euler XYZ: ${e.x.toFixed(3)}, ${e.y.toFixed(3)}, ${e.z.toFixed(3)}`,
    `local quat: ${q.x.toFixed(3)}, ${q.y.toFixed(3)}, ${q.z.toFixed(3)}, ${q.w.toFixed(3)}`,
  ].join('\n');
}

function formatLandmarkTip(l) {
  if (!l) return 'landmark missing';
  const idx = l.index ?? LANDMARK[l.name];
  const name = l.name || LANDMARK_NAMES[idx] || '?';
  return [
    `JSON landmark: [${idx}] ${name}`,
    `xNorm,yNorm: ${fmt(l.xNorm)}, ${fmt(l.yNorm)}`,
    `z (image): ${fmt(l.z)}`,
    `wx,wy,wz: ${fmt(l.wx)}, ${fmt(l.wy)}, ${fmt(l.wz)}`,
    `visibility: ${fmt(l.visibility)}  presence: ${fmt(l.presence)}`,
  ].join('\n');
}

function fmt(v) {
  if (v == null || !Number.isFinite(+v)) return 'null';
  return (+v).toFixed(3);
}

function showHoverFromUserData(ud, el) {
  if (ud.kind === 'vrm-bone') showHoverTip(formatBoneTip(ud.name), el);
  else if (ud.kind === 'landmark') showHoverTip(formatLandmarkTip(ud.landmark || ud), el);
}

function showHoverTip(text, anchor) {
  const tip = $('hoverTip');
  tip.textContent = text;
  tip.style.display = 'block';
  const vr = $('viewport').getBoundingClientRect();
  let x = 12;
  let y = 12;
  if (anchor?.clientX != null) {
    x = anchor.clientX - vr.left + 14;
    y = anchor.clientY - vr.top + 14;
  } else if (anchor?.getBoundingClientRect) {
    const r = anchor.getBoundingClientRect();
    x = r.right - vr.left + 8;
    y = r.top - vr.top;
  }
  const maxX = vr.width - 12;
  const maxY = vr.height - 12;
  tip.style.left = `${Math.min(maxX - 40, Math.max(8, x))}px`;
  tip.style.top = `${Math.min(maxY - 40, Math.max(8, y))}px`;
  hoverInfo = text;
}

function hideHoverTip() {
  const tip = $('hoverTip');
  if (tip) tip.style.display = 'none';
  hoverInfo = null;
}
