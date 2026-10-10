import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync, existsSync} from 'node:fs';
import {AnimationMixer, Bone, Group, Vector3} from 'three';
import {GLTFLoader} from 'three/addons/loaders/GLTFLoader.js';
import {bindGarment} from '../src/rig.ts';
import {applyPose} from '../src/poses.ts';
import {presentFace} from '../src/presentation.ts';
import {femaleBeauty} from '../scripts/female-beauty.mjs';

const catalog = JSON.parse(readFileSync(new URL('../../backend/ta-api/src/main/resources/slay/catalog.json', import.meta.url)));
function data(id) {
  const bytes = readFileSync(new URL(`../../app/assets/slay_renderer/assets/${id}.glb`, import.meta.url));
  const length = bytes.readUInt32LE(12);
  return {doc: JSON.parse(bytes.subarray(20, 20 + length)), bin: bytes.subarray(28 + length)};
}
async function load(id) {
  const {doc, bin} = data(id);
  doc.materials = doc.materials.map(() => ({pbrMetallicRoughness: {}})); delete doc.images; delete doc.textures;
  doc.buffers[0].uri = `data:application/octet-stream;base64,${bin.toString('base64')}`;
  globalThis.ProgressEvent ??= class ProgressEvent {};
  return new GLTFLoader().parseAsync(JSON.stringify(doc), '');
}

test('beauty additions deliver three distinct haircuts with two coin locks, eight lip shades and one nose hoop', () => {
  const hair = femaleBeauty.filter(i => i.category === 'hair');
  assert.equal(hair.length, 3);
  assert.deepEqual(hair.map(i => i.cost), [0, 80, 120]);
  assert.equal(new Set(hair.map(i => i.asset[1])).size, 3);
  assert.equal(catalog.items.filter(i => i.id.startsWith('female-lipstick-')).length, 8);
  for (const choice of femaleBeauty) {
    const item = catalog.items.find(i => i.id === choice.id);
    assert.equal(item.body, 'female');
    assert.equal(item.coinCost, choice.cost);
    assert.equal(item.isDefault, choice.cost === 0);
    assert.equal(item.category, choice.category);
    assert.ok(existsSync(new URL(`../../app/assets/slay_renderer/${item.thumbnailUrl}`, import.meta.url)));
    assert.ok(data(item.id).doc.meshes.length);
  }
  const hoop = catalog.items.find(i => i.id === 'female-nose-ring-gold');
  assert.equal(hoop.category, 'accessories', 'wearable alongside earrings');
  assert.deepEqual(hoop.hidesRegions, []);
});

test('new hair binds to the live head and stays fitted through each runway finish', async () => {
  const avatar = await load('female'), root = new Group(); root.add(avatar.scene);
  const bones = new Map(); avatar.scene.traverse(o => {if (o instanceof Bone) bones.set(o.name, o);});
  for (const item of femaleBeauty.filter(i => i.category === 'hair')) {
    const hair = await load(item.id); bindGarment(hair.scene, bones); root.add(hair.scene);
    const mesh = hair.scene.getObjectByName(item.id);
    mesh.geometry.computeBoundingBox();
    assert.ok(mesh.geometry.boundingBox.max.y > 1.75 && mesh.geometry.boundingBox.min.y > .95);
    assert.equal(data(item.id).doc.materials[0].alphaMode, 'MASK');
    assert.ok(mesh.skeleton.bones.every(b => bones.get(b.name) === b));
    const weights = mesh.geometry.getAttribute('skinWeight'), joints = mesh.geometry.getAttribute('skinIndex');
    for (let i = 0; i < weights.count; i++) {
      assert.equal(weights.getX(i), 1);
      assert.equal(mesh.skeleton.bones[joints.getX(i)].name, 'Head');
    }
    const mixer = new AnimationMixer(avatar.scene);
    for (const pose of catalog.poses) {
      applyPose(mixer, avatar.animations, pose); root.updateMatrixWorld(true); mesh.skeleton.update();
      assert.ok(mesh.getVertexPosition(0, new Vector3()).toArray().every(Number.isFinite));
    }
    mixer.stopAllAction(); root.remove(hair.scene);
  }
});

test('nose hoop remains at the nostril through facial presets and poses without hiding skin', async () => {
  const avatar = await load('female'), ring = await load('female-nose-ring-gold'), root = new Group(); root.add(avatar.scene);
  const bones = new Map(); avatar.scene.traverse(o => {if (o instanceof Bone) bones.set(o.name, o);});
  bindGarment(ring.scene, bones); root.add(ring.scene);
  const head = avatar.scene.getObjectByName('region_head'), hoop = ring.scene.getObjectByName('female-nose-ring-gold');
  const mixer = new AnimationMixer(avatar.scene);
  for (const face of catalog.facePresets) for (const pose of catalog.poses) {
    applyPose(mixer, avatar.animations, pose); presentFace(root, face, pose); root.updateMatrixWorld(true);
    head.skeleton.update(); hoop.skeleton.update();
    const surface = [];
    const p = head.geometry.getAttribute('position');
    for (let i = 0; i < p.count; i++) if (p.getX(i) > 0 && p.getX(i) < .04 && p.getY(i) > 1.62 && p.getY(i) < 1.67 && p.getZ(i) > .14)
      surface.push(head.localToWorld(head.getVertexPosition(i, new Vector3())));
    for (let i = 0; i < hoop.geometry.getAttribute('position').count; i++) {
      const vertex = hoop.localToWorld(hoop.getVertexPosition(i, new Vector3()));
      assert.ok(Math.min(...surface.map(v => v.distanceTo(vertex))) < .012, `${face}/${pose}: hoop detached from nostril`);
    }
    assert.equal(hoop.morphTargetInfluences[hoop.morphTargetDictionary['face_' + face]], 1);
  }
  assert.equal(data('female-nose-ring-gold').doc.materials[0].pbrMetallicRoughness.metallicFactor, .85);
});
