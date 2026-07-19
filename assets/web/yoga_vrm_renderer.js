import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { VRMLoaderPlugin, VRMUtils } from '@pixiv/three-vrm';

import * as Kalidokit from 'kalidokit';


let enableRetarget = false;


let mirrorGuide = false;
let retargetParts = { torso: true, arms: true, legs: true };
// Guide JSON is keyframed truth: every apply resets to rest then sets bones.
// If playback alpha < 1, play never reaches the pose that scrub (alpha=1) shows.
// Soft slerp is for live jitter — not for pre-authored guide playback.
const playbackRetargetAlpha = 1.0;
const debugRetargetAlpha = 1.0;

function currentRetargetAlpha(baseAlpha = playbackRetargetAlpha) {
  // Play and scrub both snap fully so motion matches frame-by-frame review.
  return isPlaying ? playbackRetargetAlpha : debugRetargetAlpha;
}


let guideModelScale = 0.7;

let guideModelScaleY = 1.0;
let guideModelScaleX = 1.0;
let guideModelYOffset = 1;  
let guideModelZOffset = 0.0;   

let guideModelYaw = Math.PI;   

let poseBodyYaw = 0;
let poseBodyYawTarget = 0; // filtered facing target (outlier-safe)
let poseBodyYawInitialized = false;
/** Rotate whole VRM root toward JSON facing (shoulder/hip normal). */
let autoBodyYaw = true;
let lastRetargetMode = 'idle';


let guideModelPitch = 0;    

let baseNormalizeScale = 1;

let sessionScaleLocked = false;



const CAMERA_FOV = 35;
const CAMERA_POS = { x: 0, y: 0.95, z: 2.7 };   
const CAMERA_LOOK = { x: 0, y: 0.95, z: 0 };    

function applyModelScale() {
  if (!vrm?.scene) return;
  const u = baseNormalizeScale * guideModelScale;
  const sx = u * guideModelScaleX;
  const sy = u * guideModelScaleY;
  
  const sz = u * ((guideModelScaleX + guideModelScaleY) * 0.5);
  vrm.scene.scale.set(sx, sy, sz);
  debugScaleFactor = sy;
}

function applyGuideRootTransform() {
  if (!guideRoot) return;
  guideRoot.position.set(0, guideModelYOffset, guideModelZOffset);
  
  guideRoot.rotation.order = 'YXZ';
  guideRoot.rotation.set(guideModelPitch, guideModelYaw + poseBodyYaw, 0);
  
  
  guideRoot.scale.setScalar(1);
  applyModelScale();
}


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
const restPoseQuats = new Map();

let idLabelMode = 'off';


let boneMapping = {};
let mappingMode = false;
let mappingOverlay = null;
let _mappingButton = null;

const LANDMARK = {
  nose: 0,
  leftShoulder: 11, rightShoulder: 12,
  leftElbow: 13, rightElbow: 14,
  leftWrist: 15, rightWrist: 16,
  leftPinky: 17, rightPinky: 18,
  leftIndex: 19, rightIndex: 20,
  leftThumb: 21, rightThumb: 22,
  leftHip: 23, rightHip: 24,
  leftKnee: 25, rightKnee: 26,
  leftAnkle: 27, rightAnkle: 28,
  leftHeel: 29, rightHeel: 30,
  leftFootIndex: 31, rightFootIndex: 32,
};


const BONE_LANDMARK_MAP = {
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

function landmarkIndexForBone(boneName) {
  const lmName = BONE_LANDMARK_MAP[boneName];
  if (!lmName) return null;
  return Object.prototype.hasOwnProperty.call(LANDMARK, lmName) ? LANDMARK[lmName] : null;
}

function getMappedLandmarkPoint(frame, boneName) {
  const idx = landmarkIndexForBone(boneName);
  return idx != null ? getLandmarkPoint(frame, idx) : null;
}


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


function initScene() {
  renderer = new THREE.WebGLRenderer({
    canvas, alpha: true, antialias: true, premultipliedAlpha: false,
  });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
  renderer.setClearColor(0x000000, 0);
  renderer.outputColorSpace = THREE.SRGBColorSpace;

  scene = new THREE.Scene();
  camera = new THREE.PerspectiveCamera(CAMERA_FOV, 1, 0.1, 20);
  camera.position.set(CAMERA_POS.x, CAMERA_POS.y, CAMERA_POS.z);
  camera.lookAt(CAMERA_LOOK.x, CAMERA_LOOK.y, CAMERA_LOOK.z);

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
  applyGuideRootTransform();
  if (debugSkeletonEnabled || idLabelMode !== 'off') {
    updateDebugVisuals(lastFrame);
  }
  renderer.render(scene, camera);
}


function normalizeVrmModel(vrmModel) {
  if (!vrmModel?.scene) throw new Error('normalizeVrmModel: vrm.scene missing');

  
  vrmModel.scene.updateMatrixWorld(true);

  const box = new THREE.Box3().setFromObject(vrmModel.scene);
  if (box.isEmpty()) {
    console.warn('[YogaVRM] Empty bbox — skip center/scale');
    applyGuideRootTransform();
    return;
  }

  const size = new THREE.Vector3();
  const center = new THREE.Vector3();
  box.getSize(size);
  box.getCenter(center);

  vrmModel.scene.position.sub(center);

  const targetHeight = 1.8;
  baseNormalizeScale = targetHeight / Math.max(size.y, 0.01);
  debugRecenterOffset.copy(center);

  applyGuideRootTransform();

  if (camera) {
    camera.position.set(CAMERA_POS.x, CAMERA_POS.y, CAMERA_POS.z);
    camera.lookAt(CAMERA_LOOK.x, CAMERA_LOOK.y, CAMERA_LOOK.z);
  }

  console.log('[YogaVRM] Model normalized:',
    'size', size.x.toFixed(3), size.y.toFixed(3), size.z.toFixed(3),
    'center', center.x.toFixed(3), center.y.toFixed(3), center.z.toFixed(3),
    'baseScale', baseNormalizeScale.toFixed(3),
    'guideScale', guideModelScale.toFixed(3));
}


function ensureRendererAlive() {
  
  let gl = null;
  try {
    gl = renderer ? renderer.getContext() : null;
  } catch (_) {
    gl = null;
  }
  const lost = !renderer || !gl || (typeof gl.isContextLost === 'function' && gl.isContextLost());
  if (!lost) return;

  console.warn('[YogaVRM] WebGL context lost — recreating renderer');
  try {
    if (renderer) renderer.dispose();
  } catch (_) {  }

  if (!canvas) throw new Error('canvas element missing');
  renderer = new THREE.WebGLRenderer({
    canvas, alpha: true, antialias: true, premultipliedAlpha: false,
  });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
  renderer.setClearColor(0x000000, 0);
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  onResize();

  if (!scene) {
    scene = new THREE.Scene();
    scene.add(new THREE.AmbientLight(0xffffff, 0.85));
    const key = new THREE.DirectionalLight(0xfff0ff, 1.1);
    key.position.set(1, 2, 2);
    scene.add(key);
  }
  if (!camera) {
    camera = new THREE.PerspectiveCamera(CAMERA_FOV, 1, 0.1, 20);
    camera.position.set(CAMERA_POS.x, CAMERA_POS.y, CAMERA_POS.z);
    camera.lookAt(CAMERA_LOOK.x, CAMERA_LOOK.y, CAMERA_LOOK.z);
  }
}

async function loadVrmFromBase64Internal(base64) {
  let step = 'start';
  try {
    step = 'decoding_base64';
    reportStep(step);
    setStatus('Đang parse VRM...');
    const binary = atob(base64);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    const blob = new Blob([bytes], { type: 'application/octet-stream' });
    const url = URL.createObjectURL(blob);

    step = 'loading_vrm_gltf';
    reportStep(step);
    const loader = new GLTFLoader();
    loader.register((parser) => new VRMLoaderPlugin(parser));
    const gltf = await loader.loadAsync(url);
    URL.revokeObjectURL(url);

    if (vrm) {
      try { VRMUtils.deepDispose(vrm.scene); } catch (_) {  }
      if (guideRoot && scene) scene.remove(guideRoot);
    }

    vrm = gltf.userData.vrm;
    if (!vrm) throw new Error('File is not a valid VRM (userData.vrm missing)');
    poseBodyYaw = 0;
    poseBodyYawTarget = 0;
    poseBodyYawInitialized = false;
    step = 'vrm_parsed';
    reportStep(step);
    console.log('[YogaVRM] VRM loaded');

    step = 'ensure_renderer';
    ensureRendererAlive();
    if (!scene || !renderer) throw new Error('Three.js scene/renderer not ready after WebGL re-init');

    step = 'add_to_scene';
    guideRoot = new THREE.Group();
    guideRoot.add(vrm.scene);
    scene.add(guideRoot);

    step = 'normalize';
    normalizeVrmModel(vrm);

    captureRestPose();
    calibrateRestDirections();

    step = 'opacity';
    if (typeof window.setGuideOpacity === 'function') {
      window.setGuideOpacity(guideOpacity);
    }

    console.log('[YogaVRM] VRM normalized and added to scene');

    if (showBoneSkeleton) addBoneHelper();

    setTimeout(() => {
      enableRetarget = true;
      console.log('[YogaVRM] Retarget enabled (IK = Mapping Studio)');
      if (lastFrame) applyPoseToVrm(lastFrame);
    }, 500);

    postToFlutter({ type: 'ready' });
    setStatus('');
  } catch (err) {
    console.error('[YogaVRM] loadVrm error at step=', step, err);
    const errorMsg = (err && err.message) ? err.message : String(err);
    const stack = (err && err.stack) ? String(err.stack) : '';
    const detail = `[${step}] ${errorMsg}${stack ? '\n' + stack : ''}`;
    sendError('Không tải được VRM model.', detail);
    setStatus('Không tải được VRM model: ' + errorMsg);
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



window.setGuideTransform = function (config) {
  if (!config) return;
  if (sessionScaleLocked && !config.force) {
    console.log('[YogaVRM] setGuideTransform ignored (sessionScaleLocked)');
    return false;
  }
  if (config.scale !== undefined) guideModelScale = Number(config.scale);
  if (config.scaleX !== undefined) guideModelScaleX = Number(config.scaleX);
  if (config.scaleY !== undefined) guideModelScaleY = Number(config.scaleY);
  if (config.yOffset !== undefined) guideModelYOffset = Number(config.yOffset);
  if (config.zOffset !== undefined) guideModelZOffset = Number(config.zOffset);
  if (config.yaw !== undefined) guideModelYaw = Number(config.yaw);
  if (config.pitch !== undefined) guideModelPitch = Number(config.pitch);
  if (Number.isNaN(guideModelScale)) guideModelScale = 0.7;
  if (Number.isNaN(guideModelScaleX)) guideModelScaleX = 1;
  if (Number.isNaN(guideModelScaleY)) guideModelScaleY = 1;
  applyGuideRootTransform();
  console.log('[YogaVRM] setGuideTransform', {
    scale: guideModelScale, scaleX: guideModelScaleX, scaleY: guideModelScaleY,
    yOffset: guideModelYOffset, zOffset: guideModelZOffset,
  });
  return true;
};


window.applySessionBodyScale = function (params) {
  if (!params) return false;
  if (sessionScaleLocked && !params.force) {
    console.log('[YogaVRM] applySessionBodyScale skipped (already locked)');
    return false;
  }
  if (params.scale !== undefined) guideModelScale = Number(params.scale);
  if (params.heightScale !== undefined) guideModelScaleY = Number(params.heightScale);
  if (params.widthScale !== undefined) guideModelScaleX = Number(params.widthScale);
  
  if (params.scaleY !== undefined) guideModelScaleY = Number(params.scaleY);
  if (params.scaleX !== undefined) guideModelScaleX = Number(params.scaleX);
  if (params.yOffset !== undefined) guideModelYOffset = Number(params.yOffset);
  if (params.zOffset !== undefined) guideModelZOffset = Number(params.zOffset);
  applyGuideRootTransform();
  const shouldLock = params.lock !== false;
  if (shouldLock) sessionScaleLocked = true;
  console.log('[YogaVRM] applySessionBodyScale', {
    scale: guideModelScale, scaleX: guideModelScaleX, scaleY: guideModelScaleY,
    locked: sessionScaleLocked,
  });
  postToFlutter({
    type: 'session_scale_applied',
    scale: guideModelScale,
    scaleX: guideModelScaleX,
    scaleY: guideModelScaleY,
    locked: sessionScaleLocked,
  });
  return true;
};


window.fitGuideToUserFromFrame = function (frameJson, opts) {
  opts = opts || {};
  if (sessionScaleLocked && !opts.force) {
    console.log('[YogaVRM] fitGuideToUserFromFrame skipped (locked)');
    return false;
  }
  if (!vrm?.scene) return false;
  const frame = typeof frameJson === 'string' ? JSON.parse(frameJson) : frameJson;
  if (!frame?.landmarks?.length) return false;

  const find = (index) => frame.landmarks.find((l) => l.index === index) || null;
  const nose = find(LANDMARK.nose);
  const lAnkle = find(LANDMARK.leftAnkle);
  const rAnkle = find(LANDMARK.rightAnkle);
  const lSh = find(LANDMARK.leftShoulder);
  const rSh = find(LANDMARK.rightShoulder);
  if (!nose || !lAnkle || !rAnkle || !lSh || !rSh) {
    console.warn('[YogaVRM] fitGuideToUser: missing landmarks');
    return false;
  }

  const pNose = toWorldPoint(nose);
  const pLA = toWorldPoint(lAnkle);
  const pRA = toWorldPoint(rAnkle);
  const pLS = toWorldPoint(lSh);
  const pRS = toWorldPoint(rSh);
  if (!pNose || !pLA || !pRA || !pLS || !pRS) return false;

  const ankleMid = midpoint(pLA, pRA);
  const userHeight = Math.abs(pNose.y - ankleMid.y);
  const userWidth = pLS.distanceTo(pRS);
  if (userHeight < 1e-4 || userWidth < 1e-4) return false;

  
  vrm.scene.updateMatrixWorld(true);
  
  const prevX = guideModelScaleX;
  const prevY = guideModelScaleY;
  const prevU = guideModelScale;
  guideModelScaleX = 1;
  guideModelScaleY = 1;
  
  applyModelScale();
  vrm.scene.updateMatrixWorld(true);
  const box = new THREE.Box3().setFromObject(vrm.scene);
  const size = new THREE.Vector3();
  box.getSize(size);
  guideModelScaleX = prevX;
  guideModelScaleY = prevY;
  guideModelScale = prevU;

  const modelH = Math.max(size.y, 1e-3);
  const modelW = Math.max(size.x, 1e-3);
  
  let heightScale = userHeight / modelH;
  let widthScale = userWidth / modelW;
  
  heightScale = Math.min(2.5, Math.max(0.35, heightScale));
  widthScale = Math.min(2.5, Math.max(0.35, widthScale));

  return window.applySessionBodyScale({
    heightScale,
    widthScale,
    lock: opts.lock !== false,
    force: !!opts.force,
  });
};

window.setSessionScaleLocked = function (locked) {
  sessionScaleLocked = !!locked;
  console.log('[YogaVRM] sessionScaleLocked =', sessionScaleLocked);
};

window.resetSessionScale = function () {
  sessionScaleLocked = false;
  guideModelScale = 0.7;
  guideModelScaleX = 1;
  guideModelScaleY = 1;
  applyGuideRootTransform();
  console.log('[YogaVRM] session scale reset');
};

window.getGuideScaleState = function () {
  return JSON.stringify({
    scale: guideModelScale,
    scaleX: guideModelScaleX,
    scaleY: guideModelScaleY,
    yOffset: guideModelYOffset,
    zOffset: guideModelZOffset,
    yaw: guideModelYaw,
    pitch: guideModelPitch,
    baseNormalizeScale,
    sessionScaleLocked,
  });
};

window.setGuideYaw = function (yaw) {
  guideModelYaw = Number(yaw);
  if (Number.isNaN(guideModelYaw)) guideModelYaw = 0;
  applyGuideRootTransform();
};

window.setGuidePitch = function (pitch) {
  guideModelPitch = Number(pitch);
  if (Number.isNaN(guideModelPitch)) guideModelPitch = 0;
  applyGuideRootTransform();
  console.log('[YogaVRM] setGuidePitch', guideModelPitch);
};


function isVisible(lm) {
  return lm && (lm.visibility ?? 1) > 0.5 && (lm.presence ?? 1) > 0.5;
}

function getLandmark(frame, index, { requireVisible = false } = {}) {
  if (!frame || !frame.landmarks) return null;
  const lm = frame.landmarks.find((l) => l.index === index);
  if (!lm) return null;
  // Guide JSON is authoring data — do not drop joints on soft visibility dips
  // (Mapping Studio also uses raw landmarks for retarget).
  if (requireVisible && !isVisible(lm)) return null;
  return lm;
}



function hasFiniteNumber(value) {
  return typeof value === 'number' && Number.isFinite(value);
}

function landmarkHasWorld(lm) {
  return !!lm && hasFiniteNumber(lm.wx) && hasFiniteNumber(lm.wy) && hasFiniteNumber(lm.wz);
}

function frameWorldLandmarkCount(frame) {
  if (!frame?.landmarks) return 0;
  return frame.landmarks.reduce((count, lm) => count + (landmarkHasWorld(lm) ? 1 : 0), 0);
}

function frameHasWorldLandmarks(frame) {
  return frameWorldLandmarkCount(frame) >= 10;
}



function toWorldPoint(lm) {
  if (!lm) return null;
  if (landmarkHasWorld(lm)) {
    return new THREE.Vector3(lm.wx, -lm.wy, lm.wz);
  }
  if (lm.xNorm != null && lm.yNorm != null) {
    const x = (lm.xNorm - 0.5) * 1.5;
    const y = -(lm.yNorm - 0.5) * 1.5;
    return new THREE.Vector3(x, y, 0);
  }
  return null;
}


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


function toDebugPoint(lm, align) {
  const raw = toWorldPoint(lm);
  if (!raw) return null;
  if (align) {
    
    return raw.sub(align.mpHip).multiplyScalar(align.scale).add(align.vrmHip);
  }
  
  return raw.sub(debugRecenterOffset).multiplyScalar(debugScaleFactor);
}


const JSON_DEBUG_CORE_INDICES = new Set([
  0, 
  11, 12, 13, 14, 15, 16, 
  23, 24, 25, 26, 27, 28, 
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


const _parentWorldQuat = new THREE.Quaternion();
const _desiredLocalQuat = new THREE.Quaternion();
const _dir = new THREE.Vector3();
const _rest = new THREE.Vector3();

// Fallback rest directions (normalized VRM). Prefer calibratedRestDirs when available.
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

/** @type {Map<string, THREE.Vector3>} parent-local rest direction per bone */
const calibratedRestDirs = new Map();

/**
 * Measure each bone's rest direction in parent-local space from the actual VRM.
 * Mapping Studio uses this so setFromUnitVectors targets the real skeleton, not
 * generic axis assumptions.
 */
function calibrateRestDirections() {
  calibratedRestDirs.clear();
  if (!vrm?.humanoid) return;
  vrm.scene.updateMatrixWorld(true);
  if (guideRoot) guideRoot.updateMatrixWorld(true);
  for (const [boneName, childName] of Object.entries(REST_CHILD_BONE)) {
    const bone = vrm.humanoid.getNormalizedBoneNode(boneName);
    const child = vrm.humanoid.getNormalizedBoneNode(childName);
    if (!bone?.parent || !child) continue;
    const from = bone.getWorldPosition(new THREE.Vector3());
    const to = child.getWorldPosition(new THREE.Vector3());
    const dir = to.sub(from);
    if (dir.lengthSq() < 1e-8) continue;
    bone.parent.getWorldQuaternion(_parentWorldQuat);
    dir.applyQuaternion(_parentWorldQuat.clone().invert()).normalize();
    calibratedRestDirs.set(boneName, dir.clone());
  }
  console.log('[YogaVRM] calibrated rest dirs:', calibratedRestDirs.size);
}

function restDirForBone(boneName, planar = false) {
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

/**
 * Studio-aligned IK: convert world segment → parent-local direction, then
 * set local quaternion from restDir → targetDir. No world-quat strip hacks.
 */
function applyBoneWorldFromTo(boneName, from, to, planar = false, correctionScale = 1) {
  const bone = getBone(boneName);
  if (!bone?.parent || !from || !to) return;

  _dir.subVectors(to, from);
  if (planar) _dir.z = 0;
  if (_dir.lengthSq() < 1e-8) return;
  _dir.normalize();

  bone.parent.getWorldQuaternion(_parentWorldQuat);
  _dir.applyQuaternion(_parentWorldQuat.clone().invert());
  if (_dir.lengthSq() < 1e-8) return;
  _dir.normalize();

  _rest.copy(restDirForBone(boneName, planar));

  const dot = THREE.MathUtils.clamp(_rest.dot(_dir), -1, 1);
  if (dot > 0.9995) return;
  if (dot < -0.9995) {
    _desiredLocalQuat.setFromAxisAngle(new THREE.Vector3(0, 0, 1), Math.PI);
  } else {
    _desiredLocalQuat.setFromUnitVectors(_rest, _dir);
  }
  // Full snap in both play & scrub (correctionScale kept for API compat only).
  // Partial slerp after reset-to-rest was why play lagged behind scrub.
  void correctionScale;
  bone.quaternion.slerp(_desiredLocalQuat, currentRetargetAlpha());
  bone.updateMatrixWorld(true);
}

/** Legacy Kalidokit planar overrides — maps old signature onto studio IK. */
function applyBoneDirectionChainByName(boneName, from, to, _defaultDir, alpha) {
  const a = typeof alpha === 'number' ? alpha : 1;
  applyBoneWorldFromTo(boneName, from, to, true, Math.max(0.1, a));
}

function captureRestPose() {
  restPoseQuats.clear();
  if (!vrm?.humanoid) return;
  const names = [
    'hips', 'spine', 'chest', 'upperChest', 'neck', 'head',
    'leftUpperArm', 'leftLowerArm', 'leftHand',
    'rightUpperArm', 'rightLowerArm', 'rightHand',
    'leftUpperLeg', 'leftLowerLeg', 'leftFoot', 'leftToes',
    'rightUpperLeg', 'rightLowerLeg', 'rightFoot', 'rightToes',
    'leftThumbProximal', 'leftIndexProximal', 'leftIndexIntermediate', 'leftIndexDistal',
    'rightThumbProximal', 'rightIndexProximal', 'rightIndexIntermediate', 'rightIndexDistal',
  ];
  for (const name of names) {
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
  if (guideRoot) guideRoot.updateMatrixWorld(true);
}

function getLandmarkPointByName(frame, landmarkName) {
  const idx = Object.prototype.hasOwnProperty.call(LANDMARK, landmarkName) ? LANDMARK[landmarkName] : null;
  return idx != null ? getLandmarkPoint(frame, idx) : null;
}

function footGuideLandmarksForBone(footBoneName) {
  const ankleName = BONE_LANDMARK_MAP[footBoneName];
  if (ankleName?.startsWith('right')) return { heel: 'rightHeel', toe: 'rightFootIndex' };
  if (ankleName?.startsWith('left')) return { heel: 'leftHeel', toe: 'leftFootIndex' };
  return footBoneName.startsWith('right')
    ? { heel: 'rightHeel', toe: 'rightFootIndex' }
    : { heel: 'leftHeel', toe: 'leftFootIndex' };
}

function shortestAngleDelta(from, to) {
  return Math.atan2(Math.sin(to - from), Math.cos(to - from));
}

function computeJsonBodyYaw(frame) {
  const lHip = getLandmarkPoint(frame, LANDMARK.leftHip);
  const rHip = getLandmarkPoint(frame, LANDMARK.rightHip);
  const lSh = getLandmarkPoint(frame, LANDMARK.leftShoulder);
  const rSh = getLandmarkPoint(frame, LANDMARK.rightShoulder);
  const hipMid = midpoint(lHip, rHip);
  const shMid = midpoint(lSh, rSh);
  if (!hipMid || !shMid) return null;

  const right = new THREE.Vector3();
  let rightCount = 0;
  if (lHip && rHip) { right.add(new THREE.Vector3().subVectors(rHip, lHip)); rightCount++; }
  if (lSh && rSh) { right.add(new THREE.Vector3().subVectors(rSh, lSh)); rightCount++; }
  if (!rightCount) return null;
  right.multiplyScalar(1 / rightCount);

  const up = new THREE.Vector3().subVectors(shMid, hipMid);
  if (right.lengthSq() < 1e-8 || up.lengthSq() < 1e-8) return null;

  const forward = new THREE.Vector3().crossVectors(right, up);
  forward.y = 0;

  const lHeel = getLandmarkPoint(frame, LANDMARK.leftHeel);
  const lToe = getLandmarkPoint(frame, LANDMARK.leftFootIndex);
  const rHeel = getLandmarkPoint(frame, LANDMARK.rightHeel);
  const rToe = getLandmarkPoint(frame, LANDMARK.rightFootIndex);
  const footForward = new THREE.Vector3();
  let footCount = 0;
  if (lHeel && lToe) { footForward.add(new THREE.Vector3().subVectors(lToe, lHeel)); footCount++; }
  if (rHeel && rToe) { footForward.add(new THREE.Vector3().subVectors(rToe, rHeel)); footCount++; }
  footForward.y = 0;
  if (footCount && footForward.lengthSq() > 1e-8) {
    footForward.normalize();
    if (forward.lengthSq() < 1e-8 || Math.abs(forward.clone().normalize().dot(footForward)) < 0.35) {
      forward.copy(footForward);
    }
  }

  if (forward.lengthSq() < 1e-8) return null;
  forward.normalize();
  return Math.atan2(forward.x, forward.z);
}

function applyJsonBodyYaw(frame) {
  // Two-stage smooth facing:
  // 1) filter raw JSON yaw (reject ~180° flips, light EMA on target)
  // 2) ease poseBodyYaw toward filtered target (play = mượt, scrub = snap)
  if (!autoBodyYaw) {
    poseBodyYaw = 0;
    poseBodyYawTarget = 0;
    poseBodyYawInitialized = false;
    return;
  }

  const rawYaw = computeJsonBodyYaw(frame);
  if (rawYaw == null) return;

  if (!poseBodyYawInitialized) {
    poseBodyYaw = rawYaw;
    poseBodyYawTarget = rawYaw;
    poseBodyYawInitialized = true;
    return;
  }

  // Stage 1: update filtered target — ignore single-frame opposite facing
  const dTarget = shortestAngleDelta(poseBodyYawTarget, rawYaw);
  if (Math.abs(dTarget) <= Math.PI * 0.55) {
    // Play: soft absorb noise; scrub: take exact frame facing
    const targetBlend = isPlaying ? 0.38 : 1.0;
    poseBodyYawTarget += dTarget * targetBlend;
    // keep in [-π, π] for stability
    if (poseBodyYawTarget > Math.PI) poseBodyYawTarget -= Math.PI * 2;
    if (poseBodyYawTarget < -Math.PI) poseBodyYawTarget += Math.PI * 2;
  }

  // Stage 2: ease displayed yaw toward filtered target
  const delta = shortestAngleDelta(poseBodyYaw, poseBodyYawTarget);
  if (!isPlaying) {
    poseBodyYaw = poseBodyYawTarget;
    return;
  }
  // ~smooth follow: not laggy (old 0.08), not jerky (near-snap 0.92)
  const blend = 0.48;
  const maxStep = 0.20; // ~11.5° per frame update
  poseBodyYaw += THREE.MathUtils.clamp(delta * blend, -maxStep, maxStep);
}

window.setAutoBodyYaw = function (enabled) {
  autoBodyYaw = !!enabled;
  if (!autoBodyYaw) {
    poseBodyYaw = 0;
    poseBodyYawTarget = 0;
    poseBodyYawInitialized = false;
    applyGuideRootTransform();
  }
  console.log('[YogaVRM] autoBodyYaw =', autoBodyYaw);
};



function applyTorso(frame) {
  // Match Mapping Studio applyIkTorso
  const ls = getLandmarkPoint(frame, LANDMARK.leftShoulder);
  const rs = getLandmarkPoint(frame, LANDMARK.rightShoulder);
  const hipL = getLandmarkPoint(frame, LANDMARK.leftHip);
  const hipR = getLandmarkPoint(frame, LANDMARK.rightHip);
  const nose = getMappedLandmarkPoint(frame, 'head')
    || getLandmarkPoint(frame, LANDMARK.nose);

  const hipCenter = midpoint(hipL, hipR);
  const shoulderCenter = midpoint(ls, rs);

  if (hipCenter && shoulderCenter) {
    applyBoneWorldFromTo('hips', hipCenter, shoulderCenter, false, 0.7);
    applyBoneWorldFromTo('spine', hipCenter, shoulderCenter, false, 0.85);
    applyBoneWorldFromTo('chest', hipCenter, shoulderCenter, false, 1);
    applyBoneWorldFromTo('upperChest', hipCenter, shoulderCenter, false, 0.8);
  }
  if (shoulderCenter && nose) {
    applyBoneWorldFromTo('neck', shoulderCenter, nose, false, 0.65);
    applyBoneWorldFromTo('head', shoulderCenter, nose, false, 0.55);
  }
}

function applyArm(frame, side) {
  const isLeft = side === 'left';
  const prefix = isLeft ? 'left' : 'right';
  const upper = prefix + 'UpperArm';
  const lower = prefix + 'LowerArm';
  const hand = prefix + 'Hand';

  // Mapping-driven landmarks (cross-side map already encodes camera mirror)
  const s = getMappedLandmarkPoint(frame, upper);
  const e = getMappedLandmarkPoint(frame, lower);
  const w = getMappedLandmarkPoint(frame, hand);
  const finger =
    getMappedLandmarkPoint(frame, prefix + 'IndexProximal') ||
    getMappedLandmarkPoint(frame, prefix + 'ThumbProximal');

  if (s && e) applyBoneWorldFromTo(upper, s, e, false, 1);
  if (e && w) applyBoneWorldFromTo(lower, e, w, false, 1);
  if (w && (finger || e)) applyBoneWorldFromTo(hand, w, finger || e, false, 0.9);
}

function applyLeg(frame, side) {
  const isLeft = side === 'left';
  const prefix = isLeft ? 'left' : 'right';
  const upper = prefix + 'UpperLeg';
  const lower = prefix + 'LowerLeg';
  const foot = prefix + 'Foot';
  const toes = prefix + 'Toes';

  const h = getMappedLandmarkPoint(frame, upper);
  const k = getMappedLandmarkPoint(frame, lower);
  const a = getMappedLandmarkPoint(frame, foot);
  const t = getMappedLandmarkPoint(frame, toes);
  const footGuide = footGuideLandmarksForBone(foot);
  const heel = getLandmarkPointByName(frame, footGuide.heel);
  const toe = getLandmarkPointByName(frame, footGuide.toe);

  if (h && k) applyBoneWorldFromTo(upper, h, k, false, 1);
  if (k && a) applyBoneWorldFromTo(lower, k, a, false, 1);
  // Studio: foot from heel → toe (or mapped toes), not ankle alone
  if (heel && toe) {
    applyBoneWorldFromTo(foot, heel, toe, false, 1);
  } else if (a && (k || h)) {
    applyBoneWorldFromTo(foot, k || h, a, false, 0.85);
  }
  // Only rotate toes when mapped (studio skips unmapped toes to avoid collapse)
  if (a && t && BONE_LANDMARK_MAP[toes]) {
    applyBoneWorldFromTo(toes, a, t, false, 0.8);
  }
}


function computePlanarBodyYaw(frame) {
  const ls = getLandmark(frame, LANDMARK.leftShoulder);
  const rs = getLandmark(frame, LANDMARK.rightShoulder);
  const lh = getLandmark(frame, LANDMARK.leftHip);
  const rh = getLandmark(frame, LANDMARK.rightHip);
  if (!ls || !rs || !lh || !rh) return 0;

  const shoulderWidth = Math.abs((ls.xNorm ?? 0.5) - (rs.xNorm ?? 0.5));
  const hipWidth = Math.abs((lh.xNorm ?? 0.5) - (rh.xNorm ?? 0.5));
  const bodyWidth = Math.max(shoulderWidth, hipWidth);
  const normalWidth = 0.23;
  const collapse = Math.max(0, Math.min(1, 1 - bodyWidth / normalWidth));
  if (collapse < 0.12) return 0;

  
  
  
  let yawSign = 0;
  const leftDepth = [ls.z, lh.z].filter(hasFiniteNumber);
  const rightDepth = [rs.z, rh.z].filter(hasFiniteNumber);
  if (leftDepth.length && rightDepth.length) {
    const avg = (arr) => arr.reduce((sum, value) => sum + value, 0) / arr.length;
    const dz = avg(leftDepth) - avg(rightDepth);
    if (Math.abs(dz) > 0.015) {
      
      yawSign = dz < 0 ? -1 : 1;
    }
  }
  if (yawSign === 0) {
    yawSign = ((ls.xNorm ?? 0) + (lh.xNorm ?? 0)) > ((rs.xNorm ?? 0) + (rh.xNorm ?? 0)) ? 1 : -1;
  }

  return yawSign * collapse * (Math.PI * 0.48);
}

function applyCustomPose(frame) {
  if (!vrm) return;
  if (frame.personDetected === false) return;
  // Same path as Mapping Studio default: IK solver (no Kalidokit)
  lastRetargetMode = 'ik-solver';
  resetVrmPoseToRest();
  applyJsonBodyYaw(frame);
  applyGuideRootTransform();
  if (guideRoot) guideRoot.updateMatrixWorld(true);
  if (retargetParts.torso) applyTorso(frame);
  if (retargetParts.arms) { applyArm(frame, 'left'); applyArm(frame, 'right'); }
  if (retargetParts.legs) { applyLeg(frame, 'left'); applyLeg(frame, 'right'); }
  if (vrm.humanoid) vrm.humanoid.update(0);
}





function frameToKalidoKitInputs(frame) {
  const byIndex = new Array(33).fill(null);
  frame.landmarks.forEach(lm => { byIndex[lm.index] = lm; });

  const poseLandmarkArray = byIndex.map(lm =>
    lm
      ? { x: lm.xNorm, y: lm.yNorm, z: lm.z ?? 0, visibility: lm.visibility ?? 0 }
      : { x: 0.5, y: 0.5, z: 0, visibility: 0 }
  );

  const poseWorld3DArray = byIndex.map(lm =>
    lm && landmarkHasWorld(lm)
      ? { x: lm.wx, y: lm.wy, z: lm.wz, visibility: lm.visibility ?? 0 }
      : { x: 0, y: 0, z: 0, visibility: 0 }
  );

  return { poseLandmarkArray, poseWorld3DArray };
}



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

function landmarkToPlanarPoint(lm) {
  if (!lm || lm.xNorm == null || lm.yNorm == null) return null;
  return new THREE.Vector3(
    ((lm.xNorm ?? 0.5) - 0.5) * 1.5,
    -((lm.yNorm ?? 0.5) - 0.5) * 1.5,
    0,
  );
}

function midpointPlanar(a, b) {
  const pa = landmarkToPlanarPoint(a);
  const pb = landmarkToPlanarPoint(b);
  return midpoint(pa, pb);
}

function applyKalidoTorsoLeanOverride(frame) {
  if (!vrm || !retargetParts.torso) return;

  
  
  
  
  const ls = getLandmark(frame, LANDMARK.leftShoulder);
  const rs = getLandmark(frame, LANDMARK.rightShoulder);
  const lh = getLandmark(frame, LANDMARK.leftHip);
  const rh = getLandmark(frame, LANDMARK.rightHip);
  const noseLm = getLandmark(frame, LANDMARK.nose);
  if (!ls || !rs || !lh || !rh) return;

  const shoulderCenter2d = midpointPlanar(ls, rs);
  const hipCenter2d = midpointPlanar(lh, rh);
  if (!shoulderCenter2d || !hipCenter2d) return;
  const torsoDir = shoulderCenter2d.clone().sub(hipCenter2d);
  if (torsoDir.lengthSq() < 1e-5) return;
  torsoDir.normalize();

  const leanAngle = Math.acos(THREE.MathUtils.clamp(torsoDir.dot(new THREE.Vector3(0, 1, 0)), -1, 1));
  if (leanAngle < THREE.MathUtils.degToRad(10)) return;

  const torsoAlpha = THREE.MathUtils.clamp((leanAngle - THREE.MathUtils.degToRad(8)) / THREE.MathUtils.degToRad(45), 0.15, 0.65);
  applyBoneDirectionChainByName('hips', hipCenter2d, shoulderCenter2d, new THREE.Vector3(0, 1, 0), torsoAlpha * 0.45);
  vrm.scene.updateMatrixWorld(true);
  applyBoneDirectionChainByName('spine', hipCenter2d, shoulderCenter2d, new THREE.Vector3(0, 1, 0), torsoAlpha * 0.75);
  vrm.scene.updateMatrixWorld(true);
  applyBoneDirectionChainByName('chest', hipCenter2d, shoulderCenter2d, new THREE.Vector3(0, 1, 0), torsoAlpha);
  vrm.scene.updateMatrixWorld(true);

  if (noseLm) {
    const nose2d = landmarkToPlanarPoint(noseLm);
    if (!nose2d) return;
    applyBoneDirectionChainByName('neck', shoulderCenter2d, nose2d, new THREE.Vector3(0, 1, 0), torsoAlpha * 0.55);
    vrm.scene.updateMatrixWorld(true);
    applyBoneDirectionChainByName('head', shoulderCenter2d, nose2d, new THREE.Vector3(0, 1, 0), torsoAlpha * 0.45);
    vrm.scene.updateMatrixWorld(true);
  }
}

function applyKalidoPlanarLegOverride(frame) {
  if (!vrm || !retargetParts.legs) return;

  
  
  
  
  
  const applySide = (side, hipIndex, kneeIndex, ankleIndex) => {
    const hip = landmarkToPlanarPoint(getLandmark(frame, hipIndex));
    const knee = landmarkToPlanarPoint(getLandmark(frame, kneeIndex));
    const ankle = landmarkToPlanarPoint(getLandmark(frame, ankleIndex));
    if (!hip || !knee || !ankle) return;

    const prefix = side === 'left' ? 'left' : 'right';
    const hipToKnee = knee.clone().sub(hip);
    const kneeToAnkle = ankle.clone().sub(knee);
    if (hipToKnee.lengthSq() < 1e-5 || kneeToAnkle.lengthSq() < 1e-5) return;

    
    
    const upperAlpha = 0.85;
    const lowerAlpha = 0.9;
    const down = new THREE.Vector3(0, -1, 0);
    applyBoneDirectionChainByName(prefix + 'UpperLeg', hip, knee, down, upperAlpha);
    vrm.scene.updateMatrixWorld(true);
    applyBoneDirectionChainByName(prefix + 'LowerLeg', knee, ankle, down, lowerAlpha);
    vrm.scene.updateMatrixWorld(true);
    applyBoneDirectionChainByName(prefix + 'Foot', knee, ankle, down, 0.45);
    vrm.scene.updateMatrixWorld(true);
  };

  applySide('left', LANDMARK.leftHip, LANDMARK.leftKnee, LANDMARK.leftAnkle);
  applySide('right', LANDMARK.rightHip, LANDMARK.rightKnee, LANDMARK.rightAnkle);
}

function applyKalidoPlanarArmOverride(frame) {
  if (!vrm || !retargetParts.arms) return;

  const applySide = (side, shoulderIndex, elbowIndex, wristIndex, indexIndex, thumbIndex) => {
    const shoulder = landmarkToPlanarPoint(getLandmark(frame, shoulderIndex));
    const elbow = landmarkToPlanarPoint(getLandmark(frame, elbowIndex));
    const wrist = landmarkToPlanarPoint(getLandmark(frame, wristIndex));
    const finger = landmarkToPlanarPoint(getLandmark(frame, indexIndex))
      || landmarkToPlanarPoint(getLandmark(frame, thumbIndex));
    if (!shoulder || !elbow || !wrist) return;

    const prefix = side === 'left' ? 'left' : 'right';
    const restDir = side === 'left'
      ? new THREE.Vector3(-1, 0, 0)
      : new THREE.Vector3(1, 0, 0);
    const upperSegment = elbow.clone().sub(shoulder);
    const lowerSegment = wrist.clone().sub(elbow);
    if (upperSegment.lengthSq() < 1e-5 || lowerSegment.lengthSq() < 1e-5) return;

    applyBoneDirectionChainByName(prefix + 'UpperArm', shoulder, elbow, restDir, 0.75);
    vrm.scene.updateMatrixWorld(true);
    applyBoneDirectionChainByName(prefix + 'LowerArm', elbow, wrist, restDir, 0.85);
    vrm.scene.updateMatrixWorld(true);
    if (finger) {
      applyBoneDirectionChainByName(prefix + 'Hand', wrist, finger, restDir, 0.45);
      vrm.scene.updateMatrixWorld(true);
    }
  };

  applySide('left', LANDMARK.leftShoulder, LANDMARK.leftElbow, LANDMARK.leftWrist, LANDMARK.leftIndex, LANDMARK.leftThumb);
  applySide('right', LANDMARK.rightShoulder, LANDMARK.rightElbow, LANDMARK.rightWrist, LANDMARK.rightIndex, LANDMARK.rightThumb);
}

function applyKalidoPoseToVrm(riggedPose) {
  if (!vrm || !riggedPose) return false;
  
  
  const boneMap = KALIDOKIT_DIRECT_MAP;

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

    if (kalidoKey === 'Spine' || kalidoKey === 'Chest') {
      q.slerp(new THREE.Quaternion(), 0.35);
    }
    bone.quaternion.slerp(q, currentRetargetAlpha());
    bone.updateMatrixWorld(true);
  }

  vrm.humanoid.update(0);
  return true;
}


function applyPoseToVrm(frame) {
  if (!vrm || !enableRetarget) return;
  if (!isValidFrame(frame)) return;

  // Keep mobile/WebView behavior aligned with Mapping Studio's default IK solver.
  // Kalidokit remains in the bundle for diagnostics, but the guide model now uses
  // the same mapping-driven IK-style path users validate in the web studio.
  applyCustomPose(frame);
  updateDepthHud(frame);
}


function updateDepthHud(frame) {
  if (!statusEl || !frame?.landmarks?.length) return;
  const nose = frame.landmarks.find((l) => l.index === LANDMARK.nose);
  const ls = frame.landmarks.find((l) => l.index === LANDMARK.leftShoulder);
  const rs = frame.landmarks.find((l) => l.index === LANDMARK.rightShoulder);
  const fmt = (v) => hasFiniteNumber(v) ? v.toFixed(3) : '--';
  const shDx = (ls && rs && hasFiniteNumber(ls.xNorm) && hasFiniteNumber(rs.xNorm))
    ? Math.abs(ls.xNorm - rs.xNorm)
    : null;
  statusEl.textContent = `mode=${lastRetargetMode} world=${frameWorldLandmarkCount(frame)} `
    + `nose z=${fmt(nose?.z)} wx=${fmt(nose?.wx)} wy=${fmt(nose?.wy)} wz=${fmt(nose?.wz)} `
    + `shΔx=${fmt(shDx)} yaw=${poseBodyYaw.toFixed(2)}`;
  statusEl.style.display = 'block';
}


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



const _debugLabelTexCache = new Map();

function disposeDebugObject(obj) {
  if (obj.geometry) obj.geometry.dispose();
  if (obj.material) {
    
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


function addJsonLandmarkVisuals(frame) {
  if (!frame || !frame.landmarks) return;

  const align = computeJsonDebugAlign(frame);
  
  const useCoreOnly = showJsonIds() || idLabelMode === 'all' || debugSkeletonEnabled;
  const landmarks = useCoreOnly
    ? frame.landmarks.filter(isCoreJsonLandmark)
    : frame.landmarks;

  const byName = {};
  landmarks.forEach(lm => {
    if (lm.name) byName[lm.name] = toDebugPoint(lm, align);
  });

  
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
        
        const text = idLabelMode === 'all' ? ('J' + mpId) : String(mpId);
        const label = makeDebugIdLabel(text, '#7FDBFF');
        label.position.set(pt.x + 0.06, pt.y + 0.05, pt.z);
        debugGroup.add(label);
      }
    }
  }
}


function addVrmBoneIdVisuals() {
  if (!showVrmIds() || !vrm || !vrm.humanoid || !guideRoot) return;

  
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
    
    const bone = vrm.humanoid.getNormalizedBoneNode(name);
    if (!bone) continue;

    bone.getWorldPosition(worldPos);
    
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
  
  if (guideRoot) guideRoot.updateMatrixWorld(true);
  clearDebugGroup();

  if (debugSkeletonEnabled || showJsonIds()) {
    addJsonLandmarkVisuals(frame);
  }
  addVrmBoneIdVisuals();
}


function updateDebugSkeleton(frame) {
  updateDebugVisuals(frame);
}


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

  
  const exportBtn = document.createElement('button');
  exportBtn.textContent = 'Export';
  exportBtn.title = 'Export mapping to console';
  exportBtn.style.marginRight = '8px';
  exportBtn.style.cursor = 'pointer';
  exportBtn.style.padding = '6px 10px';
  exportBtn.style.borderRadius = '8px';
  exportBtn.onclick = () => { console.log('YogaMirror boneMapping:', JSON.stringify(boneMapping)); };
  mappingOverlay.appendChild(exportBtn);

  
  const clearBtn = document.createElement('button');
  clearBtn.textContent = 'Clear';
  clearBtn.style.cursor = 'pointer';
  clearBtn.style.padding = '6px 10px';
  clearBtn.style.borderRadius = '8px';
  clearBtn.onclick = () => { boneMapping = {}; _saveMapping(); updateMappingList(); };
  mappingOverlay.appendChild(clearBtn);

  
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
  
  exportBtn.addEventListener('click', () => { mappingOverlay.style.display = 'none'; if (hideTimer) { clearTimeout(hideTimer); hideTimer = null; } });
  clearBtn.addEventListener('click', () => { mappingOverlay.style.display = 'none'; if (hideTimer) { clearTimeout(hideTimer); hideTimer = null; } });

  
  const existingHeader = document.querySelector('header');
  if (existingHeader) {
    toggle.style.position = 'relative';
    toggle.style.margin = '8px';
    toggle.style.right = 'auto';
    toggle.style.top = 'auto';
    toggle.style.zIndex = 10002;
    existingHeader.appendChild(toggle);
  } else {
    
    toggle.style.position = 'fixed';
    toggle.style.right = '12px';
    toggle.style.bottom = '48px';
    toggle.style.zIndex = 10002;
    document.body.appendChild(toggle);
  }

  
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
    guideModelScaleX,
    guideModelScaleY,
    guideModelYOffset,
    guideModelZOffset,
    baseNormalizeScale,
    sessionScaleLocked,
    vrmLoaded: !!vrm,
    guideRootPresent: !!guideRoot,
    lastFrameTimestamp: lastFrame?.timestampMs ?? null,
    lastFrameLandmarks: lastFrame?.landmarks?.length ?? 0,
    offlineBundle: true,
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


function vrmBoneId(name) {
  const i = VRM_BONE_NAMES.indexOf(name);
  return i >= 0 ? i : null;
}


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

let manualMapping = {}; 
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


initScene();
postToFlutter({ type: 'webview_ready' });
