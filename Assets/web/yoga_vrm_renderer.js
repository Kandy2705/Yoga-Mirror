import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { VRMLoaderPlugin, VRMUtils } from '@pixiv/three-vrm';

let Kalidokit = null;
try {
  Kalidokit = await import('kalidokit');
} catch (e) {
  console.warn('[YogaVRM] Kalidokit unavailable, using custom solver.', e);
}

// ─── Config ─────────────────────────────────────────────────────────────────
let enableRetarget = false;
// Mirror is encoded in BONE_LANDMARK_MAP (VRM left ← JSON right). Do NOT also
// swap bone names in getBone — that would double-mirror.
let mirrorGuide = false;
let retargetParts = { torso: true, arms: true, legs: true };
const rotationSmoothing = 0.4;
let guideModelScale = 0.7;
let guideModelYOffset = 1.3;
let guideModelZOffset = 0.0;
let guideModelYaw = Math.PI;

// ─── Scene state ───────────────────────────────────────────────────────────
const canvas = document.getElementById('canvas');
const statusEl = document.getElementById('status');
const clock = new THREE.Clock();

let renderer, scene, camera, vrm = null;
let guideRoot = null;
let guideOpacity = 0.55;
let isPlaying = false;
let animationId = null;
let vrmBase64Chunks = [];
let lastFrame = null;
let debugSkeletonEnabled = false;
let showBoneSkeleton = false;
let boneHelper = null;
let debugRecenterOffset = new THREE.Vector3();
let debugScaleFactor = 1;
const debugGroup = new THREE.Group();
// ID label modes: 'off' | 'vrm' (mapping panel bones) | 'json' (MediaPipe) | 'all'
let idLabelMode = 'off';

// --- Bone mapping runtime state -------------------------------------------
let boneMapping = {};
let mappingMode = false;
let mappingOverlay = null;
let _mappingButton = null;

const LANDMARK = {
  nose: 0,
  leftShoulder: 11, rightShoulder: 12,
  leftElbow: 13, rightElbow: 14,
  leftWrist: 15, rightWrist: 16,
  leftHip: 23, rightHip: 24,
  leftKnee: 25, rightKnee: 26,
  leftAnkle: 27, rightAnkle: 28,
};

/**
 * Manual bone mapping from Bone Mapping Tool (user verified).
 * VRM bone name → JSON landmark name (proximal joint / end effector for that bone).
 * Pattern: model left driven by MediaPipe right (and vice versa) — face-camera mirror.
 */
const BONE_LANDMARK_MAP = {
  head: 'nose',
  // Arms (VRM left ← MP right, VRM right ← MP left)
  leftUpperArm: 'rightShoulder',
  leftLowerArm: 'rightElbow',
  leftHand: 'rightWrist',
  rightUpperArm: 'leftShoulder',
  rightLowerArm: 'leftElbow',
  rightHand: 'leftWrist',
  // Legs
  leftUpperLeg: 'rightHip',
  leftLowerLeg: 'rightKnee',
  leftFoot: 'rightAnkle',
  rightUpperLeg: 'leftHip',
  rightLowerLeg: 'leftKnee',
  rightFoot: 'leftAnkle',
};

function landmarkIndexForBone(boneName) {
  const lmName = BONE_LANDMARK_MAP[boneName];
  if (!lmName) return null;
  return Object.prototype.hasOwnProperty.call(LANDMARK, lmName) ? LANDMARK[lmName] : null;
}

function getMappedLandmarkPoint(frame, boneName) {
  const idx = landmarkIndexForBone(boneName);
  return idx != null ? getLandmarkPoint(frame, idx) : null;
}

// ─── Flutter bridge ─────────────────────────────────────────────────────────
function postToFlutter(payload) {
  if (window.YogaMirrorBridge && window.YogaMirrorBridge.postMessage) {
    window.YogaMirrorBridge.postMessage(JSON.stringify(payload));
  }
}

function setStatus(text) {
  if (!statusEl) return;
  statusEl.textContent = text || '';
  statusEl.style.display = text ? 'block' : 'none';
}

function reportStep(step) {
  postToFlutter({ type: 'loading_step', step: step });
}

function sendError(message, detail) {
  postToFlutter({ type: 'error', message: message, detail: detail || '' });
}

// ─── Scene init ───────────────────────────────────────────────────────────────
function initScene() {
  renderer = new THREE.WebGLRenderer({
    canvas, alpha: true, antialias: true, premultipliedAlpha: false,
  });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
  renderer.setClearColor(0x000000, 0);
  renderer.outputColorSpace = THREE.SRGBColorSpace;

  scene = new THREE.Scene();
  camera = new THREE.PerspectiveCamera(30, 1, 0.1, 20);
  camera.position.set(0, 0.9, 3.0);
  camera.lookAt(0, 0.7, 0);

  scene.add(new THREE.AmbientLight(0xffffff, 0.85));
  const key = new THREE.DirectionalLight(0xfff0ff, 1.1);
  key.position.set(1, 2, 2);
  scene.add(key);
  const fill = new THREE.DirectionalLight(0xc8d8ff, 0.45);
  fill.position.set(-1.5, 1, -1);
  scene.add(fill);

  window.addEventListener('resize', onResize);
  onResize();
  animate();
  // Create mapping overlay UI (lightweight) for manual bone mapping
  try { createMappingOverlay(); } catch (e) { console.warn('[YogaVRM] createMappingOverlay failed', e); }
}

function onResize() {
  const w = window.innerWidth;
  const h = window.innerHeight;
  if (!renderer || !camera) return;
  renderer.setSize(w, h, false);
  camera.aspect = w / h;
  camera.updateProjectionMatrix();
}

function animate() {
  animationId = requestAnimationFrame(animate);
  if (vrm) vrm.update(clock.getDelta());
  if (debugSkeletonEnabled || idLabelMode !== 'off') {
    updateDebugVisuals(lastFrame);
  }
  renderer.render(scene, camera);
}

// ─── Model normalization ──────────────────────────────────────────────────────
function normalizeVrmModel(vrmModel) {
  const box = new THREE.Box3().setFromObject(vrmModel.scene);
  const size = new THREE.Vector3();
  const center = new THREE.Vector3();
  box.getSize(size);
  box.getCenter(center);

  vrmModel.scene.position.sub(center);

  const targetHeight = 1.8;
  const scale = targetHeight / Math.max(size.y, 0.01);
  vrmModel.scene.scale.setScalar(scale * guideModelScale);

  debugRecenterOffset.copy(center);
  debugScaleFactor = scale * guideModelScale;

  if (guideRoot) {
    guideRoot.position.set(0, guideModelYOffset, guideModelZOffset);
    guideRoot.rotation.y = guideModelYaw;
    guideRoot.scale.setScalar(1);
  }

  camera.position.set(0, 0.9, 3.0);
  camera.lookAt(0, 0.7, 0);

  console.log('[YogaVRM] Model normalized:',
    'size', size.x.toFixed(3), size.y.toFixed(3), size.z.toFixed(3),
    'center', center.x.toFixed(3), center.y.toFixed(3), center.z.toFixed(3),
    'scale', scale.toFixed(3));
}

// ─── VRM load ─────────────────────────────────────────────────────────────────
async function loadVrmFromBase64Internal(base64) {
  try {
    reportStep('decoding_base64');
    setStatus('Đang parse VRM...');
    const binary = atob(base64);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    const blob = new Blob([bytes], { type: 'application/octet-stream' });
    const url = URL.createObjectURL(blob);

    reportStep('loading_vrm_gltf');
    const loader = new GLTFLoader();
    loader.register((parser) => new VRMLoaderPlugin(parser));
    const gltf = await loader.loadAsync(url);
    URL.revokeObjectURL(url);

    if (vrm) {
      VRMUtils.deepDispose(vrm.scene);
      if (guideRoot) scene.remove(guideRoot);
    }

    vrm = gltf.userData.vrm;
    if (!vrm) throw new Error('File is not a valid VRM');
    reportStep('vrm_parsed');
    console.log('[YogaVRM] VRM loaded');

    // three-vrm v2.x auto-converts VRM0→VRM1 orientation.
    // Do NOT call VRMUtils.rotateVRM0 — guideRoot rotation.y handles facing.

    guideRoot = new THREE.Group();
    guideRoot.add(vrm.scene);
    scene.add(guideRoot);

    normalizeVrmModel(vrm);
    setGuideOpacity(guideOpacity);

    console.log('[YogaVRM] VRM normalized and added to scene');

    if (showBoneSkeleton) addBoneHelper();

    // Enable retarget after short delay so display is stable first
    setTimeout(() => {
      enableRetarget = true;
      console.log('[YogaVRM] Retarget enabled');
    }, 500);

    postToFlutter({ type: 'ready' });
    setStatus('');
  } catch (err) {
    console.error('[YogaVRM] loadVrm error', err);
    var errorMsg = String(err);
    if (errorMsg.includes('three') || errorMsg.includes('Three') || errorMsg.includes('THREE')) {
      sendError('Failed to load Three.js dependency.', errorMsg);
    } else if (errorMsg.includes('vrm') || errorMsg.includes('VRM') || errorMsg.includes('gltf') || errorMsg.includes('GLTF')) {
      sendError('Không tải được VRM model.', errorMsg);
    } else if (errorMsg.includes('NetworkError') || errorMsg.includes('net::ERR_') || errorMsg.includes('Failed to fetch')) {
      sendError('Network error. Check internet connection.', errorMsg);
    } else {
      sendError('Không tải được VRM model.', errorMsg);
    }
    setStatus('Không tải được VRM model.');
  }
}

window.beginVrmBase64Load = function () { vrmBase64Chunks = []; };
window.appendVrmBase64Chunk = function (chunk) { vrmBase64Chunks.push(chunk); };
window.finishVrmBase64Load = async function () {
  const base64 = vrmBase64Chunks.join('');
  vrmBase64Chunks = [];
  await loadVrmFromBase64Internal(base64);
};
window.loadVrmFromBase64 = async function (base64) {
  await loadVrmFromBase64Internal(base64);
};

// ─── Guide transform (Flutter can call to adjust) ────────────────────────────
window.setGuideTransform = function (config) {
  if (config.scale !== undefined || config.yOffset !== undefined ||
      config.zOffset !== undefined || config.yaw !== undefined) {
    guideModelScale = config.scale ?? guideModelScale;
    guideModelYOffset = config.yOffset ?? guideModelYOffset;
    guideModelZOffset = config.zOffset ?? guideModelZOffset;
    guideModelYaw = config.yaw ?? guideModelYaw;
    if (guideRoot) {
      guideRoot.position.set(0, guideModelYOffset, guideModelZOffset);
      guideRoot.rotation.y = guideModelYaw;
      guideRoot.scale.setScalar(1);
    }
  }
};

window.setGuideYaw = function (yaw) {
  guideModelYaw = yaw;
  if (guideRoot) guideRoot.rotation.y = yaw;
};

// ─── Landmark helpers ─────────────────────────────────────────────────────────
function isVisible(lm) {
  return lm && (lm.visibility ?? 1) > 0.5 && (lm.presence ?? 1) > 0.5;
}

function getLandmark(frame, index) {
  if (!frame || !frame.landmarks) return null;
  const lm = frame.landmarks.find((l) => l.index === index);
  if (!lm || !isVisible(lm)) return null;
  return lm;
}

// MediaPipe world landmarks: Y-down → Three.js Y-up = negate Y.
// MediaPipe Z is negative toward the camera, so invert Z for Three.js if camera is in +Z.
// Always use wx/wy/wz for all 33 landmarks — do NOT mix with xNorm/yNorm.
function toWorldPoint(lm) {
  if (!lm) return null;
  if (lm.wx != null) {
    return new THREE.Vector3(lm.wx, -lm.wy, -lm.wz);
  }
  if (lm.xNorm != null && lm.yNorm != null) {
    const x = (lm.xNorm - 0.5) * 1.5;
    const y = -(lm.yNorm - 0.5) * 1.5;
    const z = (lm.z ?? 0) * 0.01;
    return new THREE.Vector3(x, y, z);
  }
  return null;
}

/**
 * Align MediaPipe world skeleton onto current VRM body:
 *  - translate so MP hip-center → VRM hips bone
 *  - uniform scale so MP shoulder–hip length ≈ VRM shoulder–hip length
 * Result is in debugGroup local space (same parent as mesh under guideRoot).
 */
function computeJsonDebugAlign(frame) {
  if (!frame?.landmarks?.length || !vrm?.humanoid || !guideRoot) return null;

  const findLm = (index) => frame.landmarks.find((l) => l.index === index) || null;
  const mpHipL = toWorldPoint(findLm(LANDMARK.leftHip));
  const mpHipR = toWorldPoint(findLm(LANDMARK.rightHip));
  const mpShL = toWorldPoint(findLm(LANDMARK.leftShoulder));
  const mpShR = toWorldPoint(findLm(LANDMARK.rightShoulder));
  const mpHip = midpoint(mpHipL, mpHipR);
  const mpShoulder = midpoint(mpShL, mpShR);
  if (!mpHip || !mpShoulder) return null;

  const mpLen = mpShoulder.distanceTo(mpHip);
  if (mpLen < 1e-5) return null;

  guideRoot.updateMatrixWorld(true);
  debugGroup.updateMatrixWorld(true);

  const world = new THREE.Vector3();
  const hipsBone = vrm.humanoid.getNormalizedBoneNode('hips');
  if (!hipsBone) return null;
  hipsBone.getWorldPosition(world);
  const vrmHip = debugGroup.worldToLocal(world.clone());

  const lsBone = vrm.humanoid.getNormalizedBoneNode('leftShoulder')
    || vrm.humanoid.getNormalizedBoneNode('leftUpperArm');
  const rsBone = vrm.humanoid.getNormalizedBoneNode('rightShoulder')
    || vrm.humanoid.getNormalizedBoneNode('rightUpperArm');
  if (!lsBone || !rsBone) return null;
  lsBone.getWorldPosition(world);
  const vrmLs = debugGroup.worldToLocal(world.clone());
  rsBone.getWorldPosition(world);
  const vrmRs = debugGroup.worldToLocal(world.clone());
  const vrmShoulder = midpoint(vrmLs, vrmRs);
  if (!vrmShoulder) return null;

  const vrmLen = vrmShoulder.distanceTo(vrmHip);
  if (vrmLen < 1e-5) return null;

  return {
    mpHip: mpHip.clone(),
    vrmHip: vrmHip.clone(),
    scale: vrmLen / mpLen,
  };
}

/** Map one MP landmark into debugGroup space, aligned to VRM when possible. */
function toDebugPoint(lm, align) {
  const raw = toWorldPoint(lm);
  if (!raw) return null;
  if (align) {
    // (p - mpHip) * scale + vrmHip
    return raw.sub(align.mpHip).multiplyScalar(align.scale).add(align.vrmHip);
  }
  // Fallback (no hips/shoulders in frame): old bbox heuristic
  return raw.sub(debugRecenterOffset).multiplyScalar(debugScaleFactor);
}

/** Core landmarks for cleaner debug (nose + arms + hips/legs). */
const JSON_DEBUG_CORE_INDICES = new Set([
  0, // nose
  11, 12, 13, 14, 15, 16, // shoulders, elbows, wrists
  23, 24, 25, 26, 27, 28, // hips, knees, ankles
]);

function isCoreJsonLandmark(lm) {
  const idx = lm.index != null
    ? lm.index
    : (Object.prototype.hasOwnProperty.call(LANDMARK, lm.name) ? LANDMARK[lm.name] : null);
  return idx != null && JSON_DEBUG_CORE_INDICES.has(idx);
}

function midpoint(a, b) {
  if (!a || !b) return null;
  return new THREE.Vector3().addVectors(a, b).multiplyScalar(0.5);
}

function isValidFrame(frame) {
  if (!frame || !Array.isArray(frame.landmarks) || frame.landmarks.length < 5) {
    console.warn('[YogaVRM] Invalid frame: missing landmarks');
    return false;
  }
  return true;
}

function getLandmarkPoint(frame, index) {
  const lm = getLandmark(frame, index);
  return lm ? toWorldPoint(lm) : null;
}

function getBone(name) {
  if (!vrm?.humanoid) return null;
  // Bone names are already the real VRM humanoid bones. L/R mirror lives in
  // BONE_LANDMARK_MAP only (see applyArm / applyLeg). Optional legacy swap:
  if (mirrorGuide) {
    const swapMap = {
      'leftUpperArm': 'rightUpperArm', 'rightUpperArm': 'leftUpperArm',
      'leftLowerArm': 'rightLowerArm', 'rightLowerArm': 'leftLowerArm',
      'leftHand': 'rightHand', 'rightHand': 'leftHand',
      'leftUpperLeg': 'rightUpperLeg', 'rightUpperLeg': 'leftUpperLeg',
      'leftLowerLeg': 'rightLowerLeg', 'rightLowerLeg': 'leftLowerLeg',
      'leftFoot': 'rightFoot', 'rightFoot': 'leftFoot',
    };
    name = swapMap[name] || name;
  }
  return vrm.humanoid.getNormalizedBoneNode(name);
}

window.debugListBones = function () {
  const names = [
    'hips', 'spine', 'chest', 'neck', 'head',
    'leftUpperArm', 'leftLowerArm', 'leftHand',
    'rightUpperArm', 'rightLowerArm', 'rightHand',
    'leftUpperLeg', 'leftLowerLeg', 'leftFoot',
    'rightUpperLeg', 'rightLowerLeg', 'rightFoot',
  ];
  for (const name of names) {
    console.log('[Bone]', name, getBone(name) ? 'FOUND' : 'MISSING');
  }
};

window.runBoneSanityTest = function () {
  const leftUpperArm = getBone('leftUpperArm');
  const rightUpperArm = getBone('rightUpperArm');
  if (leftUpperArm) leftUpperArm.rotation.z = 0.8;
  if (rightUpperArm) rightUpperArm.rotation.z = -0.8;
};

// ─── Bone chain: world→local conversion (top-down, parent→child) ────────────
const _parentWorldQuat = new THREE.Quaternion();
const _desiredWorldQuat = new THREE.Quaternion();

function applyBoneDirectionChain(bone, fromWorld, toWorld, defaultDir, alpha) {
  if (!bone || !bone.parent) return;

  const direction = new THREE.Vector3().subVectors(toWorld, fromWorld);
  if (direction.lengthSq() < 1e-6) return;
  direction.normalize();

  _desiredWorldQuat.setFromUnitVectors(defaultDir.clone().normalize(), direction);

  bone.parent.getWorldQuaternion(_parentWorldQuat);
  const localQuat = _parentWorldQuat.clone().invert().multiply(_desiredWorldQuat);

  bone.quaternion.slerp(localQuat, alpha ?? rotationSmoothing);
  bone.updateMatrixWorld(true);
}

function applyBoneDirectionChainByName(boneName, from, to, defaultDir, alpha) {
  const bone = getBone(boneName);
  if (!bone) return;
  applyBoneDirectionChain(bone, from, to, defaultDir, alpha);
}

// ─── Torso (chain: hips → spine → chest → neck → head) ───────────────────────
function applyTorso(frame) {
  // Shoulders/hips still use both sides (midpoints); head uses map head → nose.
  const ls = getLandmarkPoint(frame, LANDMARK.leftShoulder);
  const rs = getLandmarkPoint(frame, LANDMARK.rightShoulder);
  const hipL = getLandmarkPoint(frame, LANDMARK.leftHip);
  const hipR = getLandmarkPoint(frame, LANDMARK.rightHip);
  const nose = getMappedLandmarkPoint(frame, 'head')
    || getLandmarkPoint(frame, LANDMARK.nose);
  const up = new THREE.Vector3(0, 1, 0);

  const hipCenter = midpoint(hipL, hipR);
  const shoulderCenter = midpoint(ls, rs);

  if (hipCenter && shoulderCenter) {
    applyBoneDirectionChainByName('hips', hipCenter, shoulderCenter, up, 0.5);
    vrm.scene.updateMatrixWorld(true);
    applyBoneDirectionChainByName('spine', hipCenter, shoulderCenter, up, 0.7);
    vrm.scene.updateMatrixWorld(true);
    applyBoneDirectionChainByName('chest', hipCenter, shoulderCenter, up, 0.8);
    vrm.scene.updateMatrixWorld(true);
  }
  if (shoulderCenter && nose) {
    applyBoneDirectionChainByName('neck', shoulderCenter, nose, up, 0.6);
    vrm.scene.updateMatrixWorld(true);
    applyBoneDirectionChainByName('head', shoulderCenter, nose, up, 0.75);
    vrm.scene.updateMatrixWorld(true);
  }
}

// ─── Arm (single side, chain: upperArm → lowerArm → hand) ─────────────────────
// Landmarks from BONE_LANDMARK_MAP (user tool): VRM left ← MP right, etc.
function applyArm(frame, side) {
  const isLeft = side === 'left';
  const prefix = isLeft ? 'left' : 'right';
  const upper = prefix + 'UpperArm';
  const lower = prefix + 'LowerArm';
  const hand = prefix + 'Hand';

  // Rest dir follows the *VRM bone side* (not the MP side).
  const restDir = isLeft ? new THREE.Vector3(-1, 0, 0) : new THREE.Vector3(1, 0, 0);

  const s = getMappedLandmarkPoint(frame, upper);
  const e = getMappedLandmarkPoint(frame, lower);
  const w = getMappedLandmarkPoint(frame, hand);

  if (s && e) {
    applyBoneDirectionChainByName(upper, s, e, restDir);
    vrm.scene.updateMatrixWorld(true);
  }
  if (e && w) {
    applyBoneDirectionChainByName(lower, e, w, restDir);
    vrm.scene.updateMatrixWorld(true);
  }
  if (w && e) {
    applyBoneDirectionChainByName(hand, e, w, restDir, 0.5);
    vrm.scene.updateMatrixWorld(true);
  }
}

// ─── Leg (single side, chain: upperLeg → lowerLeg → foot) ─────────────────────
function applyLeg(frame, side) {
  const isLeft = side === 'left';
  const prefix = isLeft ? 'left' : 'right';
  const upper = prefix + 'UpperLeg';
  const lower = prefix + 'LowerLeg';
  const foot = prefix + 'Foot';
  const down = new THREE.Vector3(0, -1, 0);

  const h = getMappedLandmarkPoint(frame, upper);
  const k = getMappedLandmarkPoint(frame, lower);
  const a = getMappedLandmarkPoint(frame, foot);

  if (h && k) {
    applyBoneDirectionChainByName(upper, h, k, down);
    vrm.scene.updateMatrixWorld(true);
  }
  if (k && a) {
    applyBoneDirectionChainByName(lower, k, a, down);
    vrm.scene.updateMatrixWorld(true);
  }
  if (a) {
    applyBoneDirectionChainByName(foot, k || h, a, down, 0.5);
    vrm.scene.updateMatrixWorld(true);
  }
}

// ─── Custom solver ────────────────────────────────────────────────────────────
function applyCustomPose(frame) {
  if (!vrm) return;
  if (frame.personDetected === false) return;
  if (retargetParts.torso) applyTorso(frame);
  if (retargetParts.arms) { applyArm(frame, 'left'); applyArm(frame, 'right'); }
  if (retargetParts.legs) { applyLeg(frame, 'left'); applyLeg(frame, 'right'); }
}

// ─── Kalidokit ────────────────────────────────────────────────────────────────
// Build by index (0-32) — data thật có đủ 33 landmark theo index, không thiếu.
// poseLandmarkArray: screen-space normalized, dùng cho ước lượng visibility/scale
// poseWorld3DArray: world-space (mét), dùng để tính rotation — giữ raw wx/wy/wz
function frameToKalidoKitInputs(frame) {
  const byIndex = new Array(33).fill(null);
  frame.landmarks.forEach(lm => { byIndex[lm.index] = lm; });

  const poseLandmarkArray = byIndex.map(lm =>
    lm
      ? { x: lm.xNorm, y: lm.yNorm, z: lm.z ?? 0, visibility: lm.visibility ?? 0 }
      : { x: 0.5, y: 0.5, z: 0, visibility: 0 }
  );

  const poseWorld3DArray = byIndex.map(lm =>
    lm
      ? { x: lm.wx ?? 0, y: -(lm.wy ?? 0), z: -(lm.wz ?? 0), visibility: lm.visibility ?? 0 }
      : { x: 0, y: 0, z: 0, visibility: 0 }
  );

  return { poseLandmarkArray, poseWorld3DArray };
}

// Matches BONE_LANDMARK_MAP: person right arm → VRM left arm (face-camera mirror).
// Kalido Left* is anatomical left of the tracked body → drive VRM right* bones.
const KALIDOKIT_MIRROR_MAP = {
  Hips: 'hips', Spine: 'spine', Chest: 'chest', Neck: 'neck', Head: 'head',
  LeftUpperArm: 'rightUpperArm', RightUpperArm: 'leftUpperArm',
  LeftLowerArm: 'rightLowerArm', RightLowerArm: 'leftLowerArm',
  LeftHand: 'rightHand', RightHand: 'leftHand',
  LeftUpperLeg: 'rightUpperLeg', RightUpperLeg: 'leftUpperLeg',
  LeftLowerLeg: 'rightLowerLeg', RightLowerLeg: 'leftLowerLeg',
};
const KALIDOKIT_DIRECT_MAP = {
  Hips: 'hips', Spine: 'spine', Chest: 'chest', Neck: 'neck', Head: 'head',
  LeftUpperArm: 'leftUpperArm', RightUpperArm: 'rightUpperArm',
  LeftLowerArm: 'leftLowerArm', RightLowerArm: 'rightLowerArm',
  LeftHand: 'leftHand', RightHand: 'rightHand',
  LeftUpperLeg: 'leftUpperLeg', RightUpperLeg: 'rightUpperLeg',
  LeftLowerLeg: 'leftLowerLeg', RightLowerLeg: 'rightLowerLeg',
};

function applyKalidoPoseToVrm(riggedPose) {
  if (!vrm || !riggedPose) return false;
  // Always use mirror map so Kalidokit matches manual BONE_LANDMARK_MAP L/R cross.
  // (mirrorGuide only toggles legacy getBone name-swap; keep it false.)
  const boneMap = KALIDOKIT_MIRROR_MAP;

  for (const [kalidoKey, vrmBone] of Object.entries(boneMap)) {
    const src = riggedPose[kalidoKey];
    if (!src) continue;
    const bone = vrm.humanoid.getNormalizedBoneNode(vrmBone);
    if (!bone) continue;
    const rotationData = src.rotation ?? src;
    if (rotationData.x == null || rotationData.y == null || rotationData.z == null) continue;

    let q;
    if (rotationData.w != null) {
      q = new THREE.Quaternion(
        rotationData.x,
        rotationData.y,
        rotationData.z,
        rotationData.w,
      ).normalize();
    } else {
      const euler = new THREE.Euler(rotationData.x, rotationData.y, rotationData.z, 'XYZ');
      q = new THREE.Quaternion().setFromEuler(euler);
    }

    bone.quaternion.slerp(q, rotationSmoothing);
    bone.updateMatrixWorld(true);
  }

  vrm.humanoid.update(0);
  return true;
}

// ─── Main retarget pipeline ───────────────────────────────────────────────────
// Force custom solver so BONE_LANDMARK_MAP (manual tool) always drives the mesh.
// Kalidokit path kept in file for optional re-enable later.
const USE_CUSTOM_SOLVER_ONLY = true;

function applyPoseToVrm(frame) {
  if (!vrm || !enableRetarget) return;
  if (!isValidFrame(frame)) return;

  if (!USE_CUSTOM_SOLVER_ONLY) {
    const allPartsEnabled = retargetParts.torso && retargetParts.arms && retargetParts.legs;
    if (Kalidokit && allPartsEnabled) {
      const { poseLandmarkArray, poseWorld3DArray } = frameToKalidoKitInputs(frame);
      const riggedPose = Kalidokit.Pose.solve(poseWorld3DArray, poseLandmarkArray, {
        runtime: 'mediapipe',
        video: null,
        enableLegs: true,
      });
      if (riggedPose?.Hips) { applyKalidoPoseToVrm(riggedPose); return; }
    }
  }

  applyCustomPose(frame);
}

// ─── Global API (Flutter gọi qua runJavaScript) ───────────────────────────────
window.applyPoseFrame = function (frameJson) {
  try {
    const frame = typeof frameJson === 'string' ? JSON.parse(frameJson) : frameJson;
    lastFrame = frame;
    console.log('[YogaVRM] Frame received:', frame.timestampMs,
      'landmarks:', frame.landmarks?.length,
      'retarget:', enableRetarget);
    applyPoseToVrm(frame);
  } catch (e) {
    console.error('[YogaVRM] applyPoseFrame error', e);
    postToFlutter({ type: 'error', message: String(e) });
  }
};

window.setRetargetEnabled = function (value) {
  enableRetarget = !!value;
  console.log('[Retarget] enableRetarget =', enableRetarget);
};

window.setMirrorGuide = function (value) {
  mirrorGuide = !!value;
  console.log('[Retarget] mirrorGuide =', mirrorGuide);
};

window.setRetargetParts = function (parts) {
  retargetParts = { ...retargetParts, ...parts };
  console.log('[Retarget] parts =', retargetParts);
};

window.setGuideOpacity = function (opacity) {
  guideOpacity = Math.max(0.1, Math.min(1, opacity));
  if (renderer?.domElement) {
    renderer.domElement.style.opacity = guideOpacity.toString();
    renderer.domElement.style.transition = 'opacity 120ms ease-out';
  }
};

window.setPlaybackState = function (playing) {
  isPlaying = !!playing;
};

// ─── Debug skeleton ────────────────────────────────────────────────────────────
function addBoneHelper() {
  if (boneHelper) {
    scene.remove(boneHelper);
    boneHelper.dispose();
    boneHelper = null;
  }
  if (!showBoneSkeleton || !vrm) return;
  boneHelper = new THREE.SkeletonHelper(vrm.scene);
  boneHelper.visible = true;
  scene.add(boneHelper);
}

window.setDebugOverlay = function (enable) {
  debugSkeletonEnabled = !!enable;
  showBoneSkeleton = !!enable;
  if (debugSkeletonEnabled || idLabelMode !== 'off') {
    ensureDebugGroupParented();
  } else {
    if (debugGroup.parent) debugGroup.parent.remove(debugGroup);
    clearDebugGroup();
  }
  if (showBoneSkeleton) {
    addBoneHelper();
  } else if (boneHelper) {
    scene.remove(boneHelper);
    boneHelper.dispose();
    boneHelper = null;
  }
};

window.showDebugSkeleton = function (enable) {
  debugSkeletonEnabled = !!enable;
  if (debugSkeletonEnabled || idLabelMode !== 'off') {
    ensureDebugGroupParented();
  } else {
    if (debugGroup.parent) debugGroup.parent.remove(debugGroup);
    clearDebugGroup();
  }
};

const DEBUG_CONNECTIONS = [
  ['leftShoulder', 'rightShoulder'],
  ['leftShoulder', 'leftElbow'], ['leftElbow', 'leftWrist'],
  ['rightShoulder', 'rightElbow'], ['rightElbow', 'rightWrist'],
  ['leftHip', 'rightHip'],
  ['leftHip', 'leftKnee'], ['leftKnee', 'leftAnkle'],
  ['rightHip', 'rightKnee'], ['rightKnee', 'rightAnkle'],
  ['leftShoulder', 'leftHip'],
  ['rightShoulder', 'rightHip'],
  ['nose'],
];

const DEBUG_LANDMARK_COLORS = {
  nose: 0xff4444,
  leftShoulder: 0xffaa00, rightShoulder: 0xffaa00,
  leftElbow: 0xff8800, rightElbow: 0xff8800,
  leftWrist: 0xff00ff, rightWrist: 0xff00ff,
  leftHip: 0x00ffcc, rightHip: 0x00ffcc,
  leftKnee: 0x00aaff, rightKnee: 0x00aaff,
  leftAnkle: 0x0066ff, rightAnkle: 0x0066ff,
};

// Cache canvas textures for id labels (reused across frames).
// key = `${colorHex}|${text}`
const _debugLabelTexCache = new Map();

function disposeDebugObject(obj) {
  if (obj.geometry) obj.geometry.dispose();
  if (obj.material) {
    // Don't dispose cached label textures — they live in _debugLabelTexCache.
    if (obj.userData && obj.userData.isDebugLabel) {
      obj.material.dispose();
    } else {
      if (obj.material.map) obj.material.map.dispose();
      obj.material.dispose();
    }
  }
}

function clearDebugGroup() {
  while (debugGroup.children.length) {
    const c = debugGroup.children[0];
    disposeDebugObject(c);
    debugGroup.remove(c);
  }
}

function ensureDebugGroupParented() {
  if (guideRoot && debugGroup.parent !== guideRoot) {
    guideRoot.add(debugGroup);
  }
}

/**
 * Sprite label next to a point.
 * @param {string|number} idText
 * @param {string} colorCss e.g. '#7FDBFF' (JSON) or '#B388FF' (VRM/modal)
 */
function makeDebugIdLabel(idText, colorCss = '#7FDBFF') {
  const text = String(idText);
  const cacheKey = colorCss + '|' + text;
  let tex = _debugLabelTexCache.get(cacheKey);
  if (!tex) {
    const canvas = document.createElement('canvas');
    canvas.width = 128;
    canvas.height = 64;
    const ctx = canvas.getContext('2d');
    ctx.clearRect(0, 0, 128, 64);
    ctx.fillStyle = 'rgba(0,0,0,0.72)';
    const r = 12;
    const x = 8, y = 8, w = 112, h = 48;
    ctx.beginPath();
    ctx.moveTo(x + r, y);
    ctx.arcTo(x + w, y, x + w, y + h, r);
    ctx.arcTo(x + w, y + h, x, y + h, r);
    ctx.arcTo(x, y + h, x, y, r);
    ctx.arcTo(x, y, x + w, y, r);
    ctx.closePath();
    ctx.fill();
    ctx.fillStyle = colorCss;
    ctx.font = 'bold 32px -apple-system,sans-serif';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(text, 64, 34);
    tex = new THREE.CanvasTexture(canvas);
    tex.needsUpdate = true;
    _debugLabelTexCache.set(cacheKey, tex);
  }
  const mat = new THREE.SpriteMaterial({
    map: tex,
    transparent: true,
    depthTest: false,
    depthWrite: false,
  });
  const sprite = new THREE.Sprite(mat);
  sprite.scale.set(0.16, 0.08, 1);
  sprite.userData.isDebugLabel = true;
  sprite.renderOrder = 999;
  return sprite;
}

function showJsonIds() {
  return idLabelMode === 'json' || idLabelMode === 'all';
}

function showVrmIds() {
  return idLabelMode === 'vrm' || idLabelMode === 'all';
}

/** Draw JSON MediaPipe landmark dots + optional id labels (aligned to VRM). */
function addJsonLandmarkVisuals(frame) {
  if (!frame || !frame.landmarks) return;

  const align = computeJsonDebugAlign(frame);
  // Core-only when showing id labels or always for cleaner overlay
  const useCoreOnly = showJsonIds() || idLabelMode === 'all' || debugSkeletonEnabled;
  const landmarks = useCoreOnly
    ? frame.landmarks.filter(isCoreJsonLandmark)
    : frame.landmarks;

  const byName = {};
  landmarks.forEach(lm => {
    if (lm.name) byName[lm.name] = toDebugPoint(lm, align);
  });

  // Lines only when full debug skeleton is on
  if (debugSkeletonEnabled) {
    const linePts = [];
    for (const conn of DEBUG_CONNECTIONS) {
      if (conn.length === 2) {
        const a = byName[conn[0]];
        const b = byName[conn[1]];
        if (a && b) linePts.push(a.clone(), b.clone());
      }
    }
    if (linePts.length > 0) {
      const geo = new THREE.BufferGeometry().setFromPoints(linePts);
      const mat = new THREE.LineBasicMaterial({
        color: 0xff66ff,
        opacity: 0.9,
        transparent: true,
        linewidth: 4,
        depthTest: false,
      });
      debugGroup.add(new THREE.LineSegments(geo, mat));
    }
  }

  const needDots = debugSkeletonEnabled || showJsonIds();
  if (!needDots) return;

  const sphereGeo = new THREE.SphereGeometry(0.04, 12, 12);
  for (const lm of landmarks) {
    const pt = toDebugPoint(lm, align);
    if (!pt) continue;
    const color = DEBUG_LANDMARK_COLORS[lm.name] || 0xffffff;
    const mat = new THREE.MeshBasicMaterial({ color, opacity: 0.95, transparent: true });
    const mesh = new THREE.Mesh(sphereGeo, mat);
    mesh.position.copy(pt);
    debugGroup.add(mesh);

    if (showJsonIds()) {
      const mpId = (lm.index != null)
        ? lm.index
        : (Object.prototype.hasOwnProperty.call(LANDMARK, lm.name) ? LANDMARK[lm.name] : null);
      if (mpId != null) {
        // Prefix J when "all" so không nhầm với id bone VRM
        const text = idLabelMode === 'all' ? ('J' + mpId) : String(mpId);
        const label = makeDebugIdLabel(text, '#7FDBFF');
        label.position.set(pt.x + 0.06, pt.y + 0.05, pt.z);
        debugGroup.add(label);
      }
    }
  }
}

/** Draw VRM humanoid bone dots + id labels (same ids as mapping panel list). */
function addVrmBoneIdVisuals() {
  if (!showVrmIds() || !vrm || !vrm.humanoid || !guideRoot) return;

  // VRM_BONE_NAMES defined later in this module; available at runtime.
  const names = (typeof VRM_BONE_NAMES !== 'undefined' && VRM_BONE_NAMES)
    ? VRM_BONE_NAMES
    : [
      'hips', 'spine', 'chest', 'upperChest', 'neck', 'head',
      'leftShoulder', 'rightShoulder',
      'leftUpperArm', 'leftLowerArm', 'leftHand',
      'rightUpperArm', 'rightLowerArm', 'rightHand',
      'leftUpperLeg', 'leftLowerLeg', 'leftFoot',
      'rightUpperLeg', 'rightLowerLeg', 'rightFoot',
    ];

  const sphereGeo = new THREE.SphereGeometry(0.035, 10, 10);
  const worldPos = new THREE.Vector3();

  for (let i = 0; i < names.length; i++) {
    const name = names[i];
    // Use raw bone node (no mirror swap) — label the actual mesh bone
    const bone = vrm.humanoid.getNormalizedBoneNode(name);
    if (!bone) continue;

    bone.getWorldPosition(worldPos);
    // Convert into debugGroup local space (debugGroup under guideRoot)
    debugGroup.worldToLocal(worldPos);

    const mat = new THREE.MeshBasicMaterial({
      color: 0xb388ff,
      opacity: 0.95,
      transparent: true,
      depthTest: false,
    });
    const mesh = new THREE.Mesh(sphereGeo, mat);
    mesh.position.copy(worldPos);
    mesh.renderOrder = 998;
    debugGroup.add(mesh);

    // Prefix B when "all" so không nhầm với MediaPipe index
    const text = idLabelMode === 'all' ? ('B' + i) : String(i);
    const label = makeDebugIdLabel(text, '#B388FF');
    label.position.set(worldPos.x + 0.06, worldPos.y + 0.05, worldPos.z);
    debugGroup.add(label);
  }
}

function updateDebugVisuals(frame) {
  if (!debugSkeletonEnabled && idLabelMode === 'off') {
    clearDebugGroup();
    if (debugGroup.parent) debugGroup.parent.remove(debugGroup);
    return;
  }

  ensureDebugGroupParented();
  // Need up-to-date matrices before worldToLocal for VRM labels
  if (guideRoot) guideRoot.updateMatrixWorld(true);
  clearDebugGroup();

  if (debugSkeletonEnabled || showJsonIds()) {
    addJsonLandmarkVisuals(frame);
  }
  addVrmBoneIdVisuals();
}

// Back-compat alias
function updateDebugSkeleton(frame) {
  updateDebugVisuals(frame);
}

/** Cycle / set id label mode. mode: 'off'|'vrm'|'json'|'all' */
window.setIdLabelMode = function (mode) {
  const allowed = ['off', 'vrm', 'json', 'all'];
  idLabelMode = allowed.includes(mode) ? mode : 'off';
  if (idLabelMode === 'off' && !debugSkeletonEnabled) {
    clearDebugGroup();
    if (debugGroup.parent) debugGroup.parent.remove(debugGroup);
  } else {
    ensureDebugGroupParented();
    updateDebugVisuals(lastFrame);
  }
  console.log('[YogaVRM] idLabelMode =', idLabelMode);
  return idLabelMode;
};

window.cycleIdLabelMode = function () {
  const order = ['off', 'vrm', 'json', 'all'];
  const idx = order.indexOf(idLabelMode);
  return window.setIdLabelMode(order[(idx + 1) % order.length]);
};

window.getIdLabelMode = function () {
  return idLabelMode;
};
// -------------------- Mapping UI & helpers ---------------------------------
function _saveMapping() {
  try { localStorage.setItem('yogamirror_bone_mapping', JSON.stringify(boneMapping)); } catch (e) { }
}

function _loadMapping() {
  try {
    const raw = localStorage.getItem('yogamirror_bone_mapping');
    if (raw) boneMapping = JSON.parse(raw) || {};
  } catch (e) { boneMapping = {}; }
}

function updateMappingList() {
  if (!mappingOverlay) return;
  const list = mappingOverlay.querySelector('.mapping-list');
  list.innerHTML = '';
  for (const k of Object.keys(boneMapping)) {
    const row = document.createElement('div');
    row.style.marginBottom = '4px';
    row.textContent = k + ' → ' + boneMapping[k];
    list.appendChild(row);
  }
}

function createMappingOverlay() {
  if (mappingOverlay) return;
  _loadMapping();
  // small toggle button (minimized) to avoid blocking UI; draggable
  const toggle = document.createElement('div');
  toggle.style.position = 'fixed';
  toggle.style.right = '12px';
  toggle.style.top = '12px';
  toggle.style.zIndex = 9999;
  toggle.style.width = '44px';
  toggle.style.height = '44px';
  toggle.style.borderRadius = '22px';
  toggle.style.background = 'linear-gradient(135deg,#b388ff,#ff66ff)';
  toggle.style.boxShadow = '0 4px 12px rgba(0,0,0,0.5)';
  toggle.style.display = 'flex';
  toggle.style.alignItems = 'center';
  toggle.style.justifyContent = 'center';
  toggle.style.color = '#111';
  toggle.style.cursor = 'pointer';
  toggle.title = 'Bone mapping';
    // Do not append the JS 'M' toggle button (UI is controlled from Flutter)
    // const toggle = document.createElement('div');
    // toggle.style.position = 'fixed';
    // toggle.style.right = '12px';
    // toggle.style.top = '12px';
    // toggle.style.zIndex = 9999;
    // toggle.style.width = '44px';
    // toggle.style.height = '44px';
    // toggle.style.borderRadius = '22px';
    // toggle.style.background = 'linear-gradient(135deg,#b388ff,#ff66ff)';
    // toggle.style.boxShadow = '0 4px 12px rgba(0,0,0,0.5)';
    // toggle.style.display = 'flex';
    // toggle.style.alignItems = 'center';
    // toggle.style.justifyContent = 'center';
    // toggle.style.color = '#111';
    // toggle.style.cursor = 'pointer';
    // toggle.title = 'Bone mapping';
    // toggle.textContent = 'M';

  // Enter/Exit mapping button
  const btn = document.createElement('button');
  btn.textContent = mappingMode ? 'Exit mapping' : 'Map';
  btn.style.marginRight = '8px';
  btn.style.cursor = 'pointer';
  btn.style.padding = '6px 10px';
  btn.style.borderRadius = '8px';
  btn.onclick = () => {
    mappingMode = !mappingMode;
    btn.textContent = mappingMode ? 'Exit mapping' : 'Map';
  };
  _mappingButton = btn;
  mappingOverlay.appendChild(btn);

  // Export button
  const exportBtn = document.createElement('button');
  exportBtn.textContent = 'Export';
  exportBtn.title = 'Export mapping to console';
  exportBtn.style.marginRight = '8px';
  exportBtn.style.cursor = 'pointer';
  exportBtn.style.padding = '6px 10px';
  exportBtn.style.borderRadius = '8px';
  exportBtn.onclick = () => { console.log('YogaMirror boneMapping:', JSON.stringify(boneMapping)); };
  mappingOverlay.appendChild(exportBtn);

  // Clear button
  const clearBtn = document.createElement('button');
  clearBtn.textContent = 'Clear';
  clearBtn.style.cursor = 'pointer';
  clearBtn.style.padding = '6px 10px';
  clearBtn.style.borderRadius = '8px';
  clearBtn.onclick = () => { boneMapping = {}; _saveMapping(); updateMappingList(); };
  mappingOverlay.appendChild(clearBtn);

  // (optional) small mapping summary icon
  const list = document.createElement('div');
  list.className = 'mapping-list';
  list.style.display = 'none';
  list.style.marginTop = '6px';
  list.style.maxHeight = '160px';
  list.style.overflow = 'auto';
  mappingOverlay.appendChild(list);

  document.body.appendChild(toggle);
  document.body.appendChild(mappingOverlay);
  updateMappingList();
  let hideTimer = null;
  // hide panel after export/clear to avoid staying on-screen
  exportBtn.addEventListener('click', () => { mappingOverlay.style.display = 'none'; if (hideTimer) { clearTimeout(hideTimer); hideTimer = null; } });
  clearBtn.addEventListener('click', () => { mappingOverlay.style.display = 'none'; if (hideTimer) { clearTimeout(hideTimer); hideTimer = null; } });

  // Place toggle in header if page has one; otherwise attach to bottom-right near controls.
  const existingHeader = document.querySelector('header');
  if (existingHeader) {
    toggle.style.position = 'relative';
    toggle.style.margin = '8px';
    toggle.style.right = 'auto';
    toggle.style.top = 'auto';
    toggle.style.zIndex = 10002;
    existingHeader.appendChild(toggle);
  } else {
    // attach toggle next to bottom-right (above mappingOverlay)
    toggle.style.position = 'fixed';
    toggle.style.right = '12px';
    toggle.style.bottom = '48px';
    toggle.style.zIndex = 10002;
    document.body.appendChild(toggle);
  }

  // Simple click briefly shows the mapping panel then auto-hides so it doesn't block camera
  toggle.addEventListener('click', (ev) => {
    const visible = mappingOverlay.style.display !== 'none' && mappingOverlay.style.display !== '';
    if (!visible) {
      mappingOverlay.style.display = 'block';
      if (hideTimer) { clearTimeout(hideTimer); hideTimer = null; }
      hideTimer = setTimeout(() => { mappingOverlay.style.display = 'none'; hideTimer = null; }, 1700);
    } else {
      mappingOverlay.style.display = 'none';
      if (hideTimer) { clearTimeout(hideTimer); hideTimer = null; }
    }
  });

  // canvas click mapping handler
  canvas.addEventListener('click', (ev) => {
    if (!mappingMode) return;
    if (!lastFrame) return;
    const rect = renderer.domElement.getBoundingClientRect();
    const mx = ev.clientX - rect.left;
    const my = ev.clientY - rect.top;
    let best = null;
    let bestDist = Infinity;
    const tmp = new THREE.Vector3();
    for (const lm of lastFrame.landmarks) {
      const wp = toDebugPoint(lm);
      if (!wp) continue;
      tmp.copy(wp).project(camera);
      const sx = (tmp.x * 0.5 + 0.5) * rect.width;
      const sy = (-tmp.y * 0.5 + 0.5) * rect.height;
      const dx = sx - mx;
      const dy = sy - my;
      const d = Math.sqrt(dx*dx + dy*dy);
      if (d < bestDist) { bestDist = d; best = lm; }
    }
    if (best && bestDist < 48) {
      const boneName = prompt('Map landmark "' + (best.name || best.index) + '" to VRM bone (e.g. leftUpperArm):');
      if (boneName && boneName.trim()) {
        const key = best.name || String(best.index);
        boneMapping[key] = boneName.trim();
        _saveMapping();
        updateMappingList();
        console.log('[YogaVRM] mapped', key, '→', boneMapping[key]);
      }
    }
  });
}

// Expose simple API for Flutter/console
window.getBoneMapping = function () { return boneMapping; };
window.setBoneMapping = function (obj) { boneMapping = obj || {}; _saveMapping(); updateMappingList(); };
window.enterMappingMode = function () { mappingMode = true; if (_mappingButton) _mappingButton.textContent = 'Exit mapping'; };
window.exitMappingMode = function () { mappingMode = false; if (_mappingButton) _mappingButton.textContent = 'Map'; };
window.logCurrentMapping = function () { console.log('YogaMirror boneMapping:', JSON.stringify(boneMapping)); };
window.toggleMappingPanel = function () {
  if (!mappingOverlay) return;
  mappingOverlay.style.display = mappingOverlay.style.display === 'none' ? 'block' : 'none';
};


window.getDebugInfo = function () {
  const info = {
    enableRetarget,
    mirrorGuide,
    guideModelYaw,
    guideModelScale,
    guideModelYOffset,
    guideModelZOffset,
    vrmLoaded: !!vrm,
    guideRootPresent: !!guideRoot,
    lastFrameTimestamp: lastFrame?.timestampMs ?? null,
    lastFrameLandmarks: lastFrame?.landmarks?.length ?? 0,
  };
  if (vrm?.humanoid) {
    const boneNames = [
      'hips', 'spine', 'chest', 'neck', 'head',
      'leftUpperArm', 'rightUpperArm',
      'leftLowerArm', 'rightLowerArm',
      'leftUpperLeg', 'rightUpperLeg',
      'leftLowerLeg', 'rightLowerLeg',
    ];
    for (const name of boneNames) {
      info['bone_' + name] = !!vrm.humanoid.getNormalizedBoneNode(name);
    }
  }
  console.log('[YogaVRM] Debug info:', info);
  return JSON.stringify(info);
};

// ─── Manual Bone Mapping Tool ────────────────────────────────────────────────
// Pair VRM bones ↔ JSON landmarks via two text lists (no 3D hit-test).
// IDs shown on UI:
//   - VRM bone: list index (stable in this tool)
//   - JSON landmark: MediaPipe Pose landmark index (LANDMARK map)
const VRM_BONE_NAMES = [
  'hips', 'spine', 'chest', 'upperChest', 'neck', 'head',
  'leftShoulder', 'rightShoulder',
  'leftUpperArm', 'leftLowerArm', 'leftHand',
  'rightUpperArm', 'rightLowerArm', 'rightHand',
  'leftUpperLeg', 'leftLowerLeg', 'leftFoot',
  'rightUpperLeg', 'rightLowerLeg', 'rightFoot',
];

const JSON_LANDMARK_NAMES = [
  'nose',
  'leftShoulder', 'rightShoulder',
  'leftElbow', 'rightElbow',
  'leftWrist', 'rightWrist',
  'leftHip', 'rightHip',
  'leftKnee', 'rightKnee',
  'leftAnkle', 'rightAnkle',
];

/** VRM bone name → stable tool id (index in VRM_BONE_NAMES). */
function vrmBoneId(name) {
  const i = VRM_BONE_NAMES.indexOf(name);
  return i >= 0 ? i : null;
}

/** JSON landmark name → MediaPipe index from LANDMARK. */
function jsonLandmarkId(name) {
  return Object.prototype.hasOwnProperty.call(LANDMARK, name) ? LANDMARK[name] : null;
}

function formatVrmBoneLabel(name) {
  const id = vrmBoneId(name);
  return id !== null ? `[${id}] ${name}` : name;
}

function formatJsonLandmarkLabel(name) {
  const id = jsonLandmarkId(name);
  return id !== null ? `[${id}] ${name}` : name;
}

let manualMapping = {}; // { vrmBoneName: jsonLandmarkName }
let mappingToolEl = null;
let selectedBoneName = null;

function mappingButtonStyle() {
  return 'display:block; width:100%; text-align:left; margin-bottom:4px; padding:6px 8px;' +
    'background:#242433; color:#fff; border:1px solid #3a3a4a; border-radius:6px;' +
    'font-size:11px; cursor:pointer; font-family:ui-monospace,Menlo,monospace;';
}

function buildMappingToolUI() {
  if (mappingToolEl) return;

  mappingToolEl = document.createElement('div');
  mappingToolEl.id = 'bone-mapping-tool';
  mappingToolEl.style.cssText =
    'position:fixed; top:0; right:0; width:260px; height:100%;' +
    'background:rgba(16,16,24,0.94); color:#fff; font-family:-apple-system,sans-serif;' +
    'font-size:12px; z-index:9999; overflow-y:auto; padding:10px; box-sizing:border-box; display:none;';

  const title = document.createElement('div');
  title.textContent = 'Bone Mapping Tool';
  title.style.cssText = 'font-weight:700; font-size:14px; margin-bottom:6px;';
  mappingToolEl.appendChild(title);

  const hint = document.createElement('div');
  hint.innerHTML =
    'Chọn 1 VRM bone, rồi 1 landmark.<br>' +
    '<span style="color:#B388FF">[id]</span> bone = index list · ' +
    '<span style="color:#7FDBFF">[id]</span> landmark = MediaPipe index';
  hint.style.cssText = 'color:#aaa; margin-bottom:10px; line-height:1.35;';
  mappingToolEl.appendChild(hint);

  const boneTitle = document.createElement('div');
  boneTitle.textContent = 'VRM Bones  [id] name';
  boneTitle.style.cssText = 'font-weight:600; margin:8px 0 4px; color:#B388FF;';
  mappingToolEl.appendChild(boneTitle);

  VRM_BONE_NAMES.forEach(name => {
    const btn = document.createElement('button');
    btn.dataset.bone = name;
    btn.dataset.boneId = String(vrmBoneId(name));
    btn.style.cssText = mappingButtonStyle();
    btn.onclick = () => { selectedBoneName = name; renderMappingUI(); };
    mappingToolEl.appendChild(btn);
  });

  const lmTitle = document.createElement('div');
  lmTitle.textContent = 'JSON Landmarks  [mp] name';
  lmTitle.style.cssText = 'font-weight:600; margin:14px 0 4px; color:#7FDBFF;';
  mappingToolEl.appendChild(lmTitle);

  JSON_LANDMARK_NAMES.forEach(name => {
    const btn = document.createElement('button');
    btn.dataset.landmark = name;
    const mpId = jsonLandmarkId(name);
    if (mpId !== null) btn.dataset.landmarkId = String(mpId);
    btn.style.cssText = mappingButtonStyle();
    btn.onclick = () => {
      if (!selectedBoneName) { alert('Chọn 1 VRM bone trước đã.'); return; }
      manualMapping[selectedBoneName] = name;
      selectedBoneName = null;
      renderMappingUI();
    };
    mappingToolEl.appendChild(btn);
  });

  const actions = document.createElement('div');
  actions.style.cssText = 'margin-top:14px; display:flex; gap:8px;';

  const clearBtn = document.createElement('button');
  clearBtn.textContent = 'Clear';
  clearBtn.style.cssText = mappingButtonStyle();
  clearBtn.onclick = () => { manualMapping = {}; selectedBoneName = null; renderMappingUI(); };
  actions.appendChild(clearBtn);

  const saveBtn = document.createElement('button');
  saveBtn.textContent = 'Save (log console)';
  saveBtn.style.cssText = mappingButtonStyle() + 'background:#B388FF;color:#000;font-weight:700;';
  saveBtn.onclick = () => {
    // Rich export: names + ids so you can map by eye / paste into notes
    const detailed = {};
    for (const [bone, landmark] of Object.entries(manualMapping)) {
      detailed[bone] = {
        boneId: vrmBoneId(bone),
        landmark,
        landmarkId: jsonLandmarkId(landmark),
      };
    }
    console.log('[BoneMapping] Manual mapping result (names):', JSON.stringify(manualMapping, null, 2));
    console.log('[BoneMapping] Manual mapping result (with ids):', JSON.stringify(detailed, null, 2));
    postToFlutter({
      type: 'bone_mapping_result',
      mapping: manualMapping,
      mappingWithIds: detailed,
    });
  };
  actions.appendChild(saveBtn);

  mappingToolEl.appendChild(actions);
  document.body.appendChild(mappingToolEl);
  renderMappingUI();
}

function renderMappingUI() {
  if (!mappingToolEl) return;

  mappingToolEl.querySelectorAll('button[data-bone]').forEach(btn => {
    const name = btn.dataset.bone;
    const base = formatVrmBoneLabel(name);
    if (manualMapping[name]) {
      btn.textContent = base + ' → ' + formatJsonLandmarkLabel(manualMapping[name]);
    } else {
      btn.textContent = base;
    }
    btn.style.outline = name === selectedBoneName ? '2px solid #B388FF' : 'none';
  });

  mappingToolEl.querySelectorAll('button[data-landmark]').forEach(btn => {
    const name = btn.dataset.landmark;
    btn.textContent = formatJsonLandmarkLabel(name);
  });
}

window.setMappingToolEnabled = function (enable) {
  buildMappingToolUI();
  mappingToolEl.style.display = enable ? 'block' : 'none';
};

// ─── Boot ─────────────────────────────────────────────────────────────────────
initScene();
postToFlutter({ type: 'webview_ready' });
