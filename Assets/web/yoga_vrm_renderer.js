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
let mirrorGuide = true;
let retargetParts = { torso: true, arms: true, legs: true };
const rotationSmoothing = 0.4;
let guideModelScale = 1.0;
let guideModelYOffset = 0.0;
let guideModelZOffset = 0.0;
let guideModelYaw = 0;

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
const debugGroup = new THREE.Group();

const LANDMARK = {
  nose: 0,
  leftShoulder: 11, rightShoulder: 12,
  leftElbow: 13, rightElbow: 14,
  leftWrist: 15, rightWrist: 16,
  leftHip: 23, rightHip: 24,
  leftKnee: 25, rightKnee: 26,
  leftAnkle: 27, rightAnkle: 28,
};

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
  if (debugSkeletonEnabled && lastFrame) {
    updateDebugSkeleton(lastFrame);
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
  const swapMap = {
    'leftUpperArm': 'rightUpperArm', 'rightUpperArm': 'leftUpperArm',
    'leftLowerArm': 'rightLowerArm', 'rightLowerArm': 'leftLowerArm',
    'leftHand': 'rightHand', 'rightHand': 'leftHand',
    'leftUpperLeg': 'rightUpperLeg', 'rightUpperLeg': 'leftUpperLeg',
    'leftLowerLeg': 'rightLowerLeg', 'rightLowerLeg': 'leftLowerLeg',
    'leftFoot': 'rightFoot', 'rightFoot': 'leftFoot',
  };
  const resolved = mirrorGuide ? (swapMap[name] || name) : name;
  return vrm.humanoid.getNormalizedBoneNode(resolved);
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
  const ls = getLandmarkPoint(frame, LANDMARK.leftShoulder);
  const rs = getLandmarkPoint(frame, LANDMARK.rightShoulder);
  const hipL = getLandmarkPoint(frame, LANDMARK.leftHip);
  const hipR = getLandmarkPoint(frame, LANDMARK.rightHip);
  const nose = getLandmarkPoint(frame, LANDMARK.nose);
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
function applyArm(frame, side) {
  const isLeft = side === 'left';
  const shoulder = isLeft ? LANDMARK.leftShoulder : LANDMARK.rightShoulder;
  const elbow = isLeft ? LANDMARK.leftElbow : LANDMARK.rightElbow;
  const wrist = isLeft ? LANDMARK.leftWrist : LANDMARK.rightWrist;
  const prefix = isLeft ? 'left' : 'right';
  let restDir = isLeft ? new THREE.Vector3(-1, 0, 0) : new THREE.Vector3(1, 0, 0);
  if (mirrorGuide) restDir.x *= -1;

  const s = getLandmarkPoint(frame, shoulder);
  const e = getLandmarkPoint(frame, elbow);
  const w = getLandmarkPoint(frame, wrist);

  if (s && e) {
    applyBoneDirectionChainByName(prefix + 'UpperArm', s, e, restDir);
    vrm.scene.updateMatrixWorld(true);
  }
  if (e && w) {
    applyBoneDirectionChainByName(prefix + 'LowerArm', e, w, restDir);
    vrm.scene.updateMatrixWorld(true);
  }
  if (w && e) {
    applyBoneDirectionChainByName(prefix + 'Hand', e, w, restDir, 0.5);
    vrm.scene.updateMatrixWorld(true);
  }
}

// ─── Leg (single side, chain: upperLeg → lowerLeg → foot) ─────────────────────
function applyLeg(frame, side) {
  const isLeft = side === 'left';
  const hip = isLeft ? LANDMARK.leftHip : LANDMARK.rightHip;
  const knee = isLeft ? LANDMARK.leftKnee : LANDMARK.rightKnee;
  const ankle = isLeft ? LANDMARK.leftAnkle : LANDMARK.rightAnkle;
  const prefix = isLeft ? 'left' : 'right';
  const down = new THREE.Vector3(0, -1, 0);

  const h = getLandmarkPoint(frame, hip);
  const k = getLandmarkPoint(frame, knee);
  const a = getLandmarkPoint(frame, ankle);

  if (h && k) {
    applyBoneDirectionChainByName(prefix + 'UpperLeg', h, k, down);
    vrm.scene.updateMatrixWorld(true);
  }
  if (k && a) {
    applyBoneDirectionChainByName(prefix + 'LowerLeg', k, a, down);
    vrm.scene.updateMatrixWorld(true);
  }
  if (a) {
    applyBoneDirectionChainByName(prefix + 'Foot', k || h, a, down, 0.5);
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

// Mirror map: MediaPipe left (anatomical) → VRM right (mirror UX).
// When mirrorGuide=false, use direct map (MediaPipe left → VRM left).
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
  const boneMap = mirrorGuide ? KALIDOKIT_MIRROR_MAP : KALIDOKIT_DIRECT_MAP;

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
function applyPoseToVrm(frame) {
  if (!vrm || !enableRetarget) return;
  if (!isValidFrame(frame)) return;

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
  if (debugSkeletonEnabled) {
    if (debugGroup.parent !== scene) scene.add(debugGroup);
  } else {
    scene.remove(debugGroup);
    while (debugGroup.children.length) {
      const c = debugGroup.children[0];
      if (c.geometry) c.geometry.dispose();
      if (c.material) c.material.dispose();
      debugGroup.remove(c);
    }
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
  if (debugSkeletonEnabled) {
    if (debugGroup.parent !== scene) scene.add(debugGroup);
  } else {
    scene.remove(debugGroup);
    while (debugGroup.children.length) {
      const c = debugGroup.children[0];
      if (c.geometry) c.geometry.dispose();
      if (c.material) c.material.dispose();
      debugGroup.remove(c);
    }
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

function updateDebugSkeleton(frame) {
  while (debugGroup.children.length) {
    const c = debugGroup.children[0];
    if (c.geometry) c.geometry.dispose();
    if (c.material) c.material.dispose();
    debugGroup.remove(c);
  }

  const byName = {};
  frame.landmarks.forEach(lm => { byName[lm.name] = toWorldPoint(lm); });

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
    const mat = new THREE.LineBasicMaterial({ color: 0x00ff88, opacity: 0.5, transparent: true });
    debugGroup.add(new THREE.LineSegments(geo, mat));
  }

  const sphereGeo = new THREE.SphereGeometry(0.025, 8, 8);
  for (const lm of frame.landmarks) {
    const pt = toWorldPoint(lm);
    if (!pt) continue;
    const color = DEBUG_LANDMARK_COLORS[lm.name] || 0x666688;
    const mat = new THREE.MeshBasicMaterial({ color });
    const mesh = new THREE.Mesh(sphereGeo, mat);
    mesh.position.copy(pt);
    debugGroup.add(mesh);
  }
}

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

// ─── Boot ─────────────────────────────────────────────────────────────────────
initScene();
postToFlutter({ type: 'webview_ready' });
