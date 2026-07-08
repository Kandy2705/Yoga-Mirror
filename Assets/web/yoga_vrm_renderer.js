import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { VRMLoaderPlugin, VRMUtils } from '@pixiv/three-vrm';

// Kalidokit optional — nếu import fail sẽ dùng custom solver.
let Kalidokit = null;
try {
  Kalidokit = await import('kalidokit');
} catch (e) {
  console.warn('[YogaVRM] Kalidokit unavailable, using custom solver.', e);
}

// ─── Scene state ───────────────────────────────────────────────────────────
const canvas = document.getElementById('canvas');
const statusEl = document.getElementById('status');

let renderer, scene, camera, vrm = null;
let guideOpacity = 0.55;
let isPlaying = false;
let animationId = null;
const restRotations = {};
let vrmBase64Chunks = [];

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

// ─── Scene init ───────────────────────────────────────────────────────────────
function initScene() {
  renderer = new THREE.WebGLRenderer({
    canvas,
    alpha: true,
    antialias: true,
    premultipliedAlpha: false,
  });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
  renderer.setClearColor(0x000000, 0);
  renderer.outputColorSpace = THREE.SRGBColorSpace;

  scene = new THREE.Scene();
  camera = new THREE.PerspectiveCamera(30, 1, 0.1, 20);
  camera.position.set(0, 1.35, 2.8);
  camera.lookAt(0, 1.0, 0);

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
  if (vrm) {
    vrm.update(1 / 60);
  }
  renderer.render(scene, camera);
}

// ─── VRM load (chunked base64 from Flutter) ───────────────────────────────────
async function loadVrmFromBase64Internal(base64) {
  try {
    setStatus('Đang parse VRM...');
    const binary = atob(base64);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) {
      bytes[i] = binary.charCodeAt(i);
    }
    const blob = new Blob([bytes], { type: 'application/octet-stream' });
    const url = URL.createObjectURL(blob);

    const loader = new GLTFLoader();
    loader.register((parser) => new VRMLoaderPlugin(parser));

    const gltf = await loader.loadAsync(url);
    URL.revokeObjectURL(url);

    if (vrm) {
      VRMUtils.deepDispose(vrm.scene);
      scene.remove(vrm.scene);
    }

    vrm = gltf.userData.vrm;
    if (!vrm) throw new Error('File is not a valid VRM');

    // Không auto-play animation có sẵn trong model.
    VRMUtils.rotateVRM0(vrm);
    vrm.scene.rotation.y = Math.PI; // quay mặt về camera

    // Scale & center model trong khung.
    const box = new THREE.Box3().setFromObject(vrm.scene);
    const size = box.getSize(new THREE.Vector3());
    const center = box.getCenter(new THREE.Vector3());
    const targetHeight = 1.65;
    const scale = targetHeight / Math.max(size.y, 0.01);
    vrm.scene.scale.setScalar(scale);
    vrm.scene.position.sub(center.multiplyScalar(scale));
    vrm.scene.position.y += 0.05;

    scene.add(vrm.scene);
    saveRestRotations();
    setGuideOpacity(guideOpacity);

    postToFlutter({ type: 'ready' });
    setStatus('');
  } catch (err) {
    console.error('[YogaVRM] loadVrm error', err);
    postToFlutter({ type: 'error', message: String(err) });
    setStatus('Không tải được VRM model.');
  }
}

window.beginVrmBase64Load = function () {
  vrmBase64Chunks = [];
};

window.appendVrmBase64Chunk = function (chunk) {
  vrmBase64Chunks.push(chunk);
};

window.finishVrmBase64Load = async function () {
  const base64 = vrmBase64Chunks.join('');
  vrmBase64Chunks = [];
  await loadVrmFromBase64Internal(base64);
};

window.loadVrmFromBase64 = async function (base64) {
  await loadVrmFromBase64Internal(base64);
};

// ─── Landmark helpers ─────────────────────────────────────────────────────────
function getLandmark(frame, index) {
  if (!frame || !frame.landmarks) return null;
  const lm = frame.landmarks.find((l) => l.index === index);
  if (!lm) return null;
  if (lm.visibility != null && lm.visibility < 0.3) return null;

  // Ưu tiên world coordinate từ MediaPipe.
  if (lm.wx != null && lm.wy != null && lm.wz != null) {
    return new THREE.Vector3(lm.wx, lm.wy, lm.wz);
  }

  const xNorm = lm.xNorm != null ? lm.xNorm : lm.x / frame.frameWidth;
  const yNorm = lm.yNorm != null ? lm.yNorm : lm.y / frame.frameHeight;
  return new THREE.Vector3(xNorm - 0.5, 0.5 - yNorm, lm.z || 0);
}

function vectorBetween(a, b) {
  return new THREE.Vector3().subVectors(b, a);
}

function midpoint(a, b) {
  return new THREE.Vector3().addVectors(a, b).multiplyScalar(0.5);
}

// ─── Bone retarget ────────────────────────────────────────────────────────────
function saveRestRotations() {
  if (!vrm) return;
  const boneNames = [
    'hips', 'spine', 'chest', 'neck', 'head',
    'leftUpperArm', 'leftLowerArm', 'leftHand',
    'rightUpperArm', 'rightLowerArm', 'rightHand',
    'leftUpperLeg', 'leftLowerLeg', 'leftFoot',
    'rightUpperLeg', 'rightLowerLeg', 'rightFoot',
  ];
  for (const name of boneNames) {
    const node = vrm.humanoid.getNormalizedBoneNode(name);
    if (node) {
      restRotations[name] = node.quaternion.clone();
    }
  }
}

/**
 * Apply hướng vector (from→to) lên bone VRM.
 * restDir: hướng mặc định của bone trong T/A-pose.
 */
function applyBoneDirection(boneName, from, to, restDir, blend = 0.85) {
  if (!vrm || !from || !to) return;
  const bone = vrm.humanoid.getNormalizedBoneNode(boneName);
  if (!bone) return;

  const dir = vectorBetween(from, to);
  if (dir.lengthSq() < 1e-6) return;
  dir.normalize();

  const rest = restDir.clone().normalize();
  const targetQuat = new THREE.Quaternion().setFromUnitVectors(rest, dir);
  const restQuat = restRotations[boneName] || bone.quaternion.clone();
  bone.quaternion.copy(restQuat).slerp(targetQuat, blend);
}

function applyCustomPose(frame) {
  if (!vrm || !frame.personDetected) return;

  const ls = getLandmark(frame, LANDMARK.leftShoulder);
  const rs = getLandmark(frame, LANDMARK.rightShoulder);
  const le = getLandmark(frame, LANDMARK.leftElbow);
  const re = getLandmark(frame, LANDMARK.rightElbow);
  const lw = getLandmark(frame, LANDMARK.leftWrist);
  const rw = getLandmark(frame, LANDMARK.rightWrist);
  const lh = getLandmark(frame, LANDMARK.leftHip);
  const rh = getLandmark(frame, LANDMARK.rightHip);
  const lk = getLandmark(frame, LANDMARK.leftKnee);
  const rk = getLandmark(frame, LANDMARK.rightKnee);
  const la = getLandmark(frame, LANDMARK.leftAnkle);
  const ra = getLandmark(frame, LANDMARK.rightAnkle);
  const nose = getLandmark(frame, LANDMARK.nose);

  const hipCenter = lh && rh ? midpoint(lh, rh) : null;
  const shoulderCenter = ls && rs ? midpoint(ls, rs) : null;

  // Torso: hips → shoulders
  if (hipCenter && shoulderCenter) {
    applyBoneDirection('hips', hipCenter, shoulderCenter, new THREE.Vector3(0, 1, 0), 0.5);
    applyBoneDirection('spine', hipCenter, shoulderCenter, new THREE.Vector3(0, 1, 0), 0.7);
    applyBoneDirection('chest', hipCenter, shoulderCenter, new THREE.Vector3(0, 1, 0), 0.8);
  }

  // Head: shoulders → nose
  if (shoulderCenter && nose) {
    applyBoneDirection('neck', shoulderCenter, nose, new THREE.Vector3(0, 1, 0), 0.6);
    applyBoneDirection('head', shoulderCenter, nose, new THREE.Vector3(0, 1, 0), 0.75);
  }

  // Arms — restDir theo hướng tay duỗi ngang (A-pose)
  if (ls && le) applyBoneDirection('leftUpperArm', ls, le, new THREE.Vector3(-1, 0, 0));
  if (le && lw) applyBoneDirection('leftLowerArm', le, lw, new THREE.Vector3(-1, 0, 0));
  if (rs && re) applyBoneDirection('rightUpperArm', rs, re, new THREE.Vector3(1, 0, 0));
  if (re && rw) applyBoneDirection('rightLowerArm', re, rw, new THREE.Vector3(1, 0, 0));
  if (lw) {
    const hand = vrm.humanoid.getNormalizedBoneNode('leftHand');
    if (hand && le) applyBoneDirection('leftHand', le, lw, new THREE.Vector3(-1, 0, 0), 0.5);
  }
  if (rw) {
    const hand = vrm.humanoid.getNormalizedBoneNode('rightHand');
    if (hand && re) applyBoneDirection('rightHand', re, rw, new THREE.Vector3(1, 0, 0), 0.5);
  }

  // Legs — restDir hướng xuống
  if (lh && lk) applyBoneDirection('leftUpperLeg', lh, lk, new THREE.Vector3(0, -1, 0));
  if (lk && la) applyBoneDirection('leftLowerLeg', lk, la, new THREE.Vector3(0, -1, 0));
  if (la) applyBoneDirection('leftFoot', lk || lh, la, new THREE.Vector3(0, -1, 0), 0.5);
  if (rh && rk) applyBoneDirection('rightUpperLeg', rh, rk, new THREE.Vector3(0, -1, 0));
  if (rk && ra) applyBoneDirection('rightLowerLeg', rk, ra, new THREE.Vector3(0, -1, 0));
  if (ra) applyBoneDirection('rightFoot', rk || rh, ra, new THREE.Vector3(0, -1, 0), 0.5);
}

function frameToKalidokitLandmarks(frame) {
  const result = [];
  for (let i = 0; i < 33; i++) {
    result.push({ x: 0, y: 0, z: 0, visibility: 0 });
  }
  for (const lm of frame.landmarks || []) {
    const xNorm = lm.xNorm != null ? lm.xNorm : lm.x / frame.frameWidth;
    const yNorm = lm.yNorm != null ? lm.yNorm : lm.y / frame.frameHeight;
    result[lm.index] = {
      x: lm.wx != null ? lm.wx : xNorm,
      y: lm.wy != null ? lm.wy : yNorm,
      z: lm.wz != null ? lm.wz : (lm.z || 0),
      visibility: lm.visibility ?? 1,
    };
  }
  return result;
}

function applyKalidokitPose(frame) {
  if (!Kalidokit || !vrm) return false;
  try {
    const landmarks = frameToKalidokitLandmarks(frame);
    const solved = Kalidokit.Pose.solve(landmarks, { runtime: 'mediapipe', enableLegs: true });
    if (!solved) return false;

    const map = {
      Hips: 'hips', Spine: 'spine', Chest: 'chest',
      Neck: 'neck', Head: 'head',
      LeftUpperArm: 'leftUpperArm', LeftLowerArm: 'leftLowerArm',
      RightUpperArm: 'rightUpperArm', RightLowerArm: 'rightLowerArm',
      LeftUpperLeg: 'leftUpperLeg', LeftLowerLeg: 'leftLowerLeg',
      RightUpperLeg: 'rightUpperLeg', RightLowerLeg: 'rightLowerLeg',
    };

    for (const [kalidoKey, vrmBone] of Object.entries(map)) {
      const part = solved[kalidoKey];
      const bone = vrm.humanoid.getNormalizedBoneNode(vrmBone);
      if (!bone || !part?.rotation) continue;
      bone.rotation.set(part.rotation.x, part.rotation.y, part.rotation.z);
    }
    return true;
  } catch (e) {
    console.warn('[YogaVRM] Kalidokit solve failed', e);
    return false;
  }
}

function applyPoseToVrm(frame) {
  if (!vrm) return;
  // JSON là motion source duy nhất — không play animation có sẵn.
  const usedKalidokit = applyKalidokitPose(frame);
  if (!usedKalidokit) {
    applyCustomPose(frame);
  }
}

// ─── Global API (Flutter gọi qua runJavaScript) ───────────────────────────────
window.applyPoseFrame = function (frameJson) {
  try {
    const frame = typeof frameJson === 'string' ? JSON.parse(frameJson) : frameJson;
    applyPoseToVrm(frame);
  } catch (e) {
    console.error('[YogaVRM] applyPoseFrame error', e);
    postToFlutter({ type: 'error', message: String(e) });
  }
};

window.setGuideOpacity = function (opacity) {
  guideOpacity = Math.max(0.1, Math.min(1, opacity));
  if (!vrm) return;
  vrm.scene.traverse((obj) => {
    if (obj.isMesh && obj.material) {
      const mats = Array.isArray(obj.material) ? obj.material : [obj.material];
      for (const mat of mats) {
        mat.transparent = true;
        mat.opacity = guideOpacity;
        mat.depthWrite = false;
        mat.needsUpdate = true;
      }
    }
  });
};

window.setPlaybackState = function (playing) {
  isPlaying = !!playing;
};

// ─── Boot ─────────────────────────────────────────────────────────────────────
initScene();
postToFlutter({ type: 'webview_ready' });