import './styles.css';
import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { VRMLoaderPlugin, VRMUtils } from '@pixiv/three-vrm';
import * as Kalidokit from 'kalidokit';

const APP_ASSET_PREFIX = '/Assets';
const DEFAULT_VRM_PATH = `${APP_ASSET_PREFIX}/models/yoga_avatar.vrm`;
const DEFAULT_META_PATH = `${APP_ASSET_PREFIX}/poses/sapiens2_to_mediapipe_video_3_with_z/meta.json`;

const LANDMARK_NAMES = ['nose','leftEyeInner','leftEye','leftEyeOuter','rightEyeInner','rightEye','rightEyeOuter','leftEar','rightEar','mouthLeft','mouthRight','leftShoulder','rightShoulder','leftElbow','rightElbow','leftWrist','rightWrist','leftPinky','rightPinky','leftIndex','rightIndex','leftThumb','rightThumb','leftHip','rightHip','leftKnee','rightKnee','leftAnkle','rightAnkle','leftHeel','rightHeel','leftFootIndex','rightFootIndex'];
const LANDMARK = Object.fromEntries(LANDMARK_NAMES.map((name, index) => [name, index]));
const POSE_CONNECTIONS = [[11,12],[11,13],[13,15],[15,17],[15,19],[15,21],[17,19],[12,14],[14,16],[16,18],[16,20],[16,22],[18,20],[11,23],[12,24],[23,24],[23,25],[25,27],[27,29],[29,31],[27,31],[24,26],[26,28],[28,30],[30,32],[28,32],[0,2],[2,7],[0,5],[5,8]];
const HUMANOID_BONES = ['hips','spine','chest','upperChest','neck','head','leftShoulder','leftUpperArm','leftLowerArm','leftHand','rightShoulder','rightUpperArm','rightLowerArm','rightHand','leftUpperLeg','leftLowerLeg','leftFoot','leftToes','rightUpperLeg','rightLowerLeg','rightFoot','rightToes','leftThumbMetacarpal','leftThumbProximal','leftThumbDistal','leftIndexProximal','leftIndexIntermediate','leftIndexDistal','rightThumbMetacarpal','rightThumbProximal','rightThumbDistal','rightIndexProximal','rightIndexIntermediate','rightIndexDistal'];
const DEFAULT_MAPPING = { head:'nose', leftUpperArm:'rightShoulder', leftLowerArm:'rightElbow', leftHand:'rightWrist', rightUpperArm:'leftShoulder', rightLowerArm:'leftElbow', rightHand:'leftWrist', leftUpperLeg:'rightHip', leftLowerLeg:'rightKnee', leftFoot:'rightAnkle', rightUpperLeg:'leftHip', rightLowerLeg:'leftKnee', rightFoot:'leftAnkle' };

let renderer, scene, camera, controls, vrm, mixerRoot;
let poseGroup = new THREE.Group();
let boneLabelGroup = new THREE.Group();
let landmarkLabelGroup = new THREE.Group();
let boneHelper;
let frames = [], currentFrameIndex = 0, playing = false, speed = 1, lastT = 0;
let mapping = structuredClone(DEFAULT_MAPPING);
let selectedBone = null;
let mirror = true;
let displayMode = 'both';
let retargetMode = 'idle';

const $ = (id) => document.getElementById(id);

document.querySelector('#app').innerHTML = `
<header><strong>YogaMirror Mapping Studio</strong><span id="status">Booting…</span></header>
<main><section id="viewport"><canvas id="three"></canvas><div id="hint">Click a VRM bone label, then a landmark label to map.</div></section>
<aside>
  <section class="card"><h2>Files</h2><button id="loadDefault">Load default assets</button><label>VRM <input id="vrmFile" type="file" accept=".vrm"></label><label>Pose JSON/meta/chunk <input id="poseFile" type="file" accept=".json" multiple></label><input id="assetPath" value="Assets/poses/sapiens2_to_mediapipe_video_3_with_z/meta.json"><button id="loadPath">Load asset path</button></section>
  <section class="card"><h2>View</h2><select id="mode"><option value="both">Both overlay</option><option value="vrm">VRM only</option><option value="json">JSON skeleton only</option></select><label><input id="mirror" type="checkbox" checked> Mirror L/R in export</label><label><input id="face" type="checkbox"> Show face landmarks</label></section>
  <section class="card"><h2>Playback</h2><button id="play">Play</button><input id="scrub" type="range" min="0" max="0" value="0"><label>Speed <input id="speed" type="number" min="0.1" max="4" step="0.1" value="1"></label><div id="time"></div></section>
  <section class="card mapping"><h2>Mapping</h2><div class="columns"><div><h3>VRM bones</h3><div id="bones"></div></div><div><h3>MediaPipe landmarks</h3><div id="landmarks"></div></div></div></section>
  <section class="card"><h2>Debug</h2><pre id="debug"></pre></section>
  <section class="card"><h2>Export</h2><button id="downloadMapping">Download mapping JSON</button><button id="copySnippet">Copy BONE_LANDMARK_MAP</button><textarea id="exportText" spellcheck="false"></textarea></section>
</aside></main>`;

initScene(); initUi(); renderMappingLists(); loadDefaults(); animate(0);

function setStatus(s){ $('status').textContent = s; }
function initScene(){
  renderer = new THREE.WebGLRenderer({ canvas: $('three'), antialias:true, alpha:false }); renderer.setPixelRatio(Math.min(devicePixelRatio,2)); renderer.outputColorSpace = THREE.SRGBColorSpace;
  scene = new THREE.Scene(); scene.background = new THREE.Color(0x111827); camera = new THREE.PerspectiveCamera(35,1,.05,50); camera.position.set(0,1.2,4);
  controls = new OrbitControls(camera, renderer.domElement); controls.target.set(0,1,0); controls.update();
  scene.add(new THREE.GridHelper(4,20,0x334155,0x1f2937)); scene.add(new THREE.HemisphereLight(0xffffff,0x334155,1.2)); const d=new THREE.DirectionalLight(0xffffff,1); d.position.set(2,4,3); scene.add(d);
  mixerRoot = new THREE.Group(); scene.add(mixerRoot); scene.add(poseGroup); scene.add(boneLabelGroup); scene.add(landmarkLabelGroup); addDropZone(); addEventListener('resize', resize); resize();
}
function initUi(){
  $('loadDefault').onclick=loadDefaults; $('loadPath').onclick=()=>loadPoseFromPath($('assetPath').value); $('vrmFile').onchange=e=>loadVrmFile(e.target.files[0]); $('poseFile').onchange=e=>loadPoseFiles([...e.target.files]);
  $('play').onclick=()=>{playing=!playing; $('play').textContent=playing?'Pause':'Play'}; $('scrub').oninput=e=>setFrame(+e.target.value); $('speed').oninput=e=>speed=+e.target.value||1; $('mode').onchange=e=>{displayMode=e.target.value; updateVisibility()}; $('mirror').onchange=e=>{mirror=e.target.checked; updateExport()}; $('face').onchange=()=>renderLandmarkList();
  $('downloadMapping').onclick=downloadMapping; $('copySnippet').onclick=()=>navigator.clipboard.writeText(makeSnippet());
}
async function loadDefaults(){ await loadVrmPath(DEFAULT_VRM_PATH); await loadPoseFromPath(DEFAULT_META_PATH); }
async function loadVrmPath(path){ setStatus(`Loading VRM ${path}`); const loader=new GLTFLoader(); loader.register(p=>new VRMLoaderPlugin(p)); const gltf=await loader.loadAsync(path); if(vrm) mixerRoot.remove(vrm.scene); vrm=gltf.userData.vrm; VRMUtils.removeUnnecessaryVertices(gltf.scene); VRMUtils.removeUnnecessaryJoints(gltf.scene); vrm.scene.rotation.y=Math.PI; normalize(vrm.scene); mixerRoot.add(vrm.scene); boneHelper?.parent?.remove(boneHelper); boneHelper=new THREE.SkeletonHelper(vrm.scene); boneHelper.material.color.set(0x38bdf8); scene.add(boneHelper); createBoneLabels(); setStatus('VRM loaded'); updateVisibility(); }
async function loadVrmFile(file){ if(!file)return; await loadVrmPath(URL.createObjectURL(file)); }
function normalize(obj){ const box=new THREE.Box3().setFromObject(obj), size=new THREE.Vector3(), center=new THREE.Vector3(); box.getSize(size); box.getCenter(center); obj.position.sub(center); obj.scale.setScalar(1.8/Math.max(size.y,.01)); obj.position.y+=.9; }
async function loadPoseFromPath(path){ const clean='/' + path.replace(/^\//,''); const data=await (await fetch(clean)).json(); if(data.chunks) { const loaded=[]; for(const c of data.chunks){ const chunkPath='/' + c.asset.replace(/^assets/i,'Assets').replace(/^\//,''); const chunk=await (await fetch(chunkPath)).json(); loaded.push(...(chunk.frames||[])); } frames=loaded; } else frames=data.frames||[]; afterPoseLoad(); }
async function loadPoseFiles(files){ const jsons=await Promise.all(files.map(f=>f.text().then(t=>({name:f.name,data:JSON.parse(t)})))); const meta=jsons.find(x=>x.data.chunks); frames=jsons.flatMap(x=>x.data.frames||[]).sort((a,b)=>(a.timestampMs||0)-(b.timestampMs||0)); if(meta && !frames.length) alert('Meta selected without chunk files. Use asset path for repo chunks, or select chunk JSON files too.'); afterPoseLoad(); }
function afterPoseLoad(){ currentFrameIndex=0; $('scrub').max=Math.max(0,frames.length-1); setFrame(0); setStatus(`Loaded ${frames.length} frames`); }
function addDropZone(){ document.body.ondragover=e=>{e.preventDefault();}; document.body.ondrop=e=>{e.preventDefault(); loadPoseFiles([...e.dataTransfer.files].filter(f=>f.name.endsWith('.json')));}; }
function setFrame(i){ if(!frames.length)return; currentFrameIndex=Math.max(0,Math.min(frames.length-1,i)); $('scrub').value=currentFrameIndex; drawPose(frames[currentFrameIndex]); applyRetarget(frames[currentFrameIndex]); updateDebug(frames[currentFrameIndex]); }
function animate(t){ requestAnimationFrame(animate); const dt=(t-lastT)||0; lastT=t; if(playing&&frames.length){ setFrame((currentFrameIndex + Math.max(1, Math.round(dt/100*speed)))%frames.length); } controls.update(); renderer.render(scene,camera); }
function resize(){ const r=$('viewport').getBoundingClientRect(); renderer.setSize(r.width,r.height,false); camera.aspect=r.width/r.height; camera.updateProjectionMatrix(); }
function lm(frame,i){ return frame?.landmarks?.find(l=>l.index===i); } function hasWorld(l){return Number.isFinite(l?.wx)&&Number.isFinite(l?.wy)&&Number.isFinite(l?.wz)}
function toWorldPoint(l){ if(!l)return null; if(hasWorld(l)) return new THREE.Vector3(l.wx,-l.wy,l.wz); return new THREE.Vector3((l.xNorm-.5)*2, -(l.yNorm-.5)*2, 0); }
function clearLabelGroup(group){ for (const child of [...group.children]) { child.element?.remove(); group.remove(child); } }
function drawPose(frame){ poseGroup.clear(); clearLabelGroup(landmarkLabelGroup); if(!frame)return; const pts=new Map(); const mat=new THREE.LineBasicMaterial({color:0xfacc15}); const dotGeo=new THREE.SphereGeometry(.018,12,12); for(const l of frame.landmarks||[]){ if(l.index<11 && !$('face').checked) continue; const p=toWorldPoint(l); if(!p)continue; p.multiplyScalar(1.8).add(new THREE.Vector3(1.25,1,0)); pts.set(l.index,p); const dot=new THREE.Mesh(dotGeo,new THREE.MeshBasicMaterial({color: selectedBone && mapping[selectedBone]===l.name ? 0x22c55e:0xf97316})); dot.position.copy(p); poseGroup.add(dot); addLabel(landmarkLabelGroup, `${l.index} ${l.name}`, p, 'landmark', l.name); } for(const [a,b] of POSE_CONNECTIONS){ if(pts.has(a)&&pts.has(b)){ const line=new THREE.Line(new THREE.BufferGeometry().setFromPoints([pts.get(a),pts.get(b)]),mat); poseGroup.add(line); } } updateVisibility(); }
function addLabel(group,text,pos,kind,value){ const el=document.createElement('button'); el.className=`label ${kind}`; el.textContent=text; el.onclick=()=> kind==='bone' ? selectBone(value) : mapSelected(value); const label=new CSS2DLike(el,pos); group.add(label); }
class CSS2DLike extends THREE.Object3D{ constructor(el,pos){ super(); this.element=el; this.position.copy(pos); $('viewport').appendChild(el);} removeFromParent(){ this.element.remove(); super.removeFromParent(); }}
function projectLabels(group){ group.children.forEach(o=>{ const v=o.getWorldPosition(new THREE.Vector3()).project(camera), r=$('viewport').getBoundingClientRect(); o.element.style.transform=`translate(${(v.x*.5+.5)*r.width}px,${(-v.y*.5+.5)*r.height}px)`; o.element.style.display=v.z<1?'block':'none'; }); }
const oldRender=THREE.WebGLRenderer.prototype.render; THREE.WebGLRenderer.prototype.render=function(s,c){ projectLabels(boneLabelGroup); projectLabels(landmarkLabelGroup); oldRender.call(this,s,c); };
function createBoneLabels(){ clearLabelGroup(boneLabelGroup); for(const name of HUMANOID_BONES){ const b=vrm?.humanoid?.getNormalizedBoneNode(name); if(!b)continue; addLabel(boneLabelGroup, name, b.getWorldPosition(new THREE.Vector3()), 'bone', name); } }
function renderMappingLists(){ const b=$('bones'); b.innerHTML=''; for(const name of HUMANOID_BONES){ const row=document.createElement('button'); row.textContent=`${name} → ${mapping[name]||'—'}`; row.onclick=()=>selectBone(name); row.id=`bone-${name}`; b.append(row); } renderLandmarkList(); updateExport(); }
function renderLandmarkList(){ const l=$('landmarks'); l.innerHTML=''; LANDMARK_NAMES.forEach((name,i)=>{ if(i<11&&!$('face')?.checked)return; const row=document.createElement('button'); row.textContent=`${i} ${name}`; row.onclick=()=>mapSelected(name); l.append(row); }); }
function selectBone(name){ selectedBone=name; document.querySelectorAll('#bones button').forEach(x=>x.classList.toggle('selected',x.id===`bone-${name}`)); }
function mapSelected(lmName){ if(!selectedBone)return; mapping[selectedBone]=lmName; renderMappingLists(); setFrame(currentFrameIndex); }
function updateExport(){ $('exportText').value = JSON.stringify({schemaVersion:'yoga-mirror-bone-landmark-map/1.0', mirror, mapping}, null, 2) + '\n\n' + makeSnippet(); }
function makeSnippet(){ return `const BONE_LANDMARK_MAP = ${JSON.stringify(mapping,null,2)};`; }
function downloadMapping(){ const a=document.createElement('a'); a.href=URL.createObjectURL(new Blob([$('exportText').value],{type:'application/json'})); a.download='yoga_mirror_bone_landmark_map.json'; a.click(); }
function updateVisibility(){ if(vrm?.scene) vrm.scene.visible=displayMode!=='json'; if(boneHelper) boneHelper.visible=displayMode!=='json'; boneLabelGroup.visible=displayMode!=='json'; poseGroup.visible=displayMode!=='vrm'; landmarkLabelGroup.visible=displayMode!=='vrm'; }
function applyRetarget(frame){ if(!vrm||!frame)return; const world=frame.landmarks?.filter(hasWorld).length>=10; retargetMode=world?'kalidokit-world-as-is':'planar-direction'; if(world) applyKalidokit(frame); applyChains(frame); }
function arr(frame,world){ const out=[]; for(let i=0;i<33;i++){ const l=lm(frame,i)||{}; out[i]=world?{x:l.wx||0,y:l.wy||0,z:l.wz||0,visibility:l.visibility??1}:{x:l.xNorm||0,y:l.yNorm||0,z:l.z||0,visibility:l.visibility??1}; } return out; }
function applyKalidokit(frame){ try{ const rig=Kalidokit.Pose.solve(arr(frame,true), arr(frame,false), {runtime:'mediapipe', video:null, enableLegs:true}); const map={Hips:'hips',Spine:'spine',Chest:'chest',Neck:'neck',Head:'head',LeftUpperArm:'leftUpperArm',LeftLowerArm:'leftLowerArm',LeftHand:'leftHand',RightUpperArm:'rightUpperArm',RightLowerArm:'rightLowerArm',RightHand:'rightHand',LeftUpperLeg:'leftUpperLeg',LeftLowerLeg:'leftLowerLeg',RightUpperLeg:'rightUpperLeg',RightLowerLeg:'rightLowerLeg'}; Object.entries(map).forEach(([k,bn])=>{ const r=rig?.[k]; const b=vrm.humanoid.getNormalizedBoneNode(bn); if(r&&b) b.rotation.set(r.x||0,r.y||0,r.z||0); }); }catch(e){ retargetMode='kalidokit-error-planar'; }}
function applyChains(frame){ const chains=[['leftUpperArm','leftLowerArm','leftHand'],['rightUpperArm','rightLowerArm','rightHand'],['leftUpperLeg','leftLowerLeg','leftFoot'],['rightUpperLeg','rightLowerLeg','rightFoot']]; for(const chain of chains){ for(let i=0;i<chain.length-1;i++){ const a=mapping[chain[i]], b=mapping[chain[i+1]]; const pa=toWorldPoint(lm(frame,LANDMARK[a])), pb=toWorldPoint(lm(frame,LANDMARK[b])); const bone=vrm.humanoid.getNormalizedBoneNode(chain[i]); if(!pa||!pb||!bone)continue; const dir=pb.sub(pa).normalize(); const q=new THREE.Quaternion().setFromUnitVectors(new THREE.Vector3(0,-1,0), dir); bone.quaternion.slerp(q,.55); } } }
function updateDebug(frame){ const val=i=>{const p=toWorldPoint(lm(frame,i));return p?`z:${lm(frame,i)?.z?.toFixed(3)} wx:${p.x.toFixed(3)} wy:${p.y.toFixed(3)} wz:${p.z.toFixed(3)}`:'missing'}; const ls=toWorldPoint(lm(frame,11)), rs=toWorldPoint(lm(frame,12)); $('time').textContent = frame ? `${currentFrameIndex+1}/${frames.length} @ ${frame.timestampMs??0}ms` : ''; $('debug').textContent=`mode: ${retargetMode}\nguideRoot yaw display: ${(mixerRoot.rotation.y||0).toFixed(3)}\nL shoulder ${val(11)}\nR shoulder ${val(12)}\nL hip ${val(23)}\nR hip ${val(24)}\nL ankle ${val(27)}\nR ankle ${val(28)}\nshΔxy: ${ls&&rs ? `${(ls.x-rs.x).toFixed(3)}, ${(ls.y-rs.y).toFixed(3)}`:'n/a'}`; }
