import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { RiveFile, hex } from '@stevysmith/rive-generator';

const here = dirname(fileURLToPath(import.meta.url));
const output = resolve(here, '../assets/rive/yoga_mannequin.riv');
mkdirSync(dirname(output), { recursive: true });

const riv = new RiveFile();
const artboard = riv.addArtboard({
  name: 'YogaMannequin',
  width: 720,
  height: 1280,
  originX: 0,
  originY: 0,
});

const bodyColor = hex('#F2E8E1');
const root = riv.addNode(artboard, { name: 'mannequin_root' });

function fillShape(shapeId) {
  const fill = riv.addFill(shapeId, { name: 'fill' });
  riv.addSolidColor(fill, bodyColor, 'body_color');
}

function roundedSegment(name, width, height = 100) {
  const node = riv.addNode(root, { name, x: 360, y: 640 });
  const shape = riv.addShape(node, { name: `${name}_shape` });
  riv.addRectangle(shape, {
    name: `${name}_path`,
    width,
    height,
    x: 0,
    y: 0,
    cornerRadius: width / 2,
  });
  fillShape(shape);
  return node;
}

function ellipsePart(name, width, height) {
  const node = riv.addNode(root, { name, x: 360, y: 640 });
  const shape = riv.addShape(node, { name: `${name}_shape` });
  riv.addEllipse(shape, { name: `${name}_path`, width, height, x: 0, y: 0 });
  fillShape(shape);
  return node;
}

function polygonPart(name, points) {
  const node = riv.addNode(root, { name, x: 360, y: 640 });
  const shape = riv.addShape(node, { name: `${name}_shape` });
  const path = riv.addPointsPath(shape, { name: `${name}_path`, closed: true });
  for (const [x, y] of points) {
    riv.addVertex(path, { x, y });
  }
  fillShape(shape);
  return node;
}

// Back layer: legs.
roundedSegment('left_thigh', 58);
roundedSegment('right_thigh', 58);
roundedSegment('left_calf', 48);
roundedSegment('right_calf', 48);
ellipsePart('left_foot', 78, 34);
ellipsePart('right_foot', 78, 34);

// Core silhouette.
polygonPart('torso', [
  [-58, -125], [-88, -92], [-78, -22], [-58, 75],
  [-42, 125], [42, 125], [58, 75], [78, -22], [88, -92], [58, -125],
]);
ellipsePart('pelvis', 142, 86);

// Arms are above the torso so a crossing yoga pose remains readable in 2D.
roundedSegment('left_upper_arm', 44);
roundedSegment('right_upper_arm', 44);
roundedSegment('left_forearm', 38);
roundedSegment('right_forearm', 38);
ellipsePart('left_hand', 48, 64);
ellipsePart('right_hand', 48, 64);

roundedSegment('neck', 38);
ellipsePart('head', 112, 142);

// Joint covers keep every body part visually connected while segments stretch.
for (const [name, size] of [
  ['left_shoulder_joint', 54], ['right_shoulder_joint', 54],
  ['left_elbow_joint', 42], ['right_elbow_joint', 42],
  ['left_wrist_joint', 34], ['right_wrist_joint', 34],
  ['left_hip_joint', 62], ['right_hip_joint', 62],
  ['left_knee_joint', 50], ['right_knee_joint', 50],
  ['left_ankle_joint', 38], ['right_ankle_joint', 38],
  ['neck_joint', 44],
]) {
  ellipsePart(name, size, size);
}

writeFileSync(output, riv.export());
console.log(`Generated ${output}`);
