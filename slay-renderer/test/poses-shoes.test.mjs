import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {AnimationMixer, Bone, Group, SkinnedMesh, Vector3} from 'three';
import {GLTFLoader} from 'three/addons/loaders/GLTFLoader.js';
import {applyPose, selectBodyFit} from '../src/poses.ts';
import {bindGarment} from '../src/rig.ts';
import {presentBody} from '../src/presentation.ts';

async function load(id) {
  const file = readFileSync(new URL(`../../app/assets/slay_renderer/assets/${id}.glb`, import.meta.url));
  const jsonLength = file.readUInt32LE(12), doc = JSON.parse(file.subarray(20, 20 + jsonLength));
  doc.materials = doc.materials.map(() => ({pbrMetallicRoughness: {}}));
  delete doc.images; delete doc.textures;
  doc.buffers[0].uri = `data:application/octet-stream;base64,${file.subarray(28 + jsonLength).toString('base64')}`;
  globalThis.ProgressEvent ??= class ProgressEvent {};
  return new GLTFLoader().parseAsync(JSON.stringify(doc), '');
}

test('all fashion poses move limbs on both avatars and reset when changed', async () => {
  for (const body of ['female', 'male']) {
    const avatar = await load(body), root = new Group(); root.add(avatar.scene);
    const mixer = new AnimationMixer(avatar.scene), bones = new Map();
    avatar.scene.traverse(o => {if (o instanceof Bone) bones.set(o.name, o);});
    const positions = [];
    for (const pose of ['signature', 'confident', 'editorial', 'celebrate']) {
      applyPose(mixer, avatar.animations, pose); root.updateMatrixWorld(true);
      positions.push(['LeftHand', 'RightHand', 'Head'].flatMap(name => bones.get(name).getWorldPosition(new Vector3()).toArray()));
      avatar.scene.traverse(mesh => {
        if (!(mesh instanceof SkinnedMesh)) return;
        mesh.skeleton.update();
        const vertices = mesh.geometry.getAttribute('position');
        for (let i = 0; i < vertices.count; i += 67) {
          const p = mesh.applyBoneTransform(i, new Vector3().fromBufferAttribute(vertices, i));
          assert.ok(p.toArray().every(Number.isFinite), `${body}/${pose}: invalid deformation`);
        }
      });
    }
    for (let i = 0; i < positions.length; i++) for (let j = i + 1; j < positions.length; j++) {
      assert.ok(Math.hypot(...positions[i].map((v, k) => v - positions[j][k])) > .04, `${body}: poses must visibly differ`);
    }
    applyPose(mixer, avatar.animations, 'signature'); root.updateMatrixWorld(true);
    const reset = ['LeftHand', 'RightHand', 'Head'].flatMap(name => bones.get(name).getWorldPosition(new Vector3()).toArray());
    assert.ok(reset.every((v, i) => Math.abs(v - positions[0][i]) < .00001), 'previous pose must not leak into the new stance');
    assert.throws(() => applyPose(mixer, avatar.animations, 'missing'), /unavailable/);
  }
});

test('both shoe styles have sock-free body fits and follow the avatar bones', async () => {
  for (const shoe of ['shoe-0', 'shoe-1']) for (const body of ['female', 'male']) {
    const avatar = await load(body), garment = await load(shoe), root = new Group();
    root.add(avatar.scene, garment.scene); root.updateMatrixWorld(true);
    const bones = new Map(); avatar.scene.traverse(o => {if (o instanceof Bone) bones.set(o.name, o);});
    selectBodyFit(garment.scene, body); bindGarment(garment.scene, bones);
    const fits = []; garment.scene.traverse(o => {if (o instanceof SkinnedMesh) fits.push(o);});
    assert.equal(fits.length, 2);
    assert.equal(fits.filter(mesh => mesh.visible).length, 1);
    const fit = fits.find(mesh => mesh.visible), vertices = fit.geometry.getAttribute('position');
    let maxHeight = 0;
    for (let i = 0; i < vertices.count; i++) maxHeight = Math.max(maxHeight, vertices.getY(i));
    assert.ok(maxHeight < .145, 'sock shaft must be removed without cutting off the shoe collar');
    assert.ok(fit.skeleton.bones.every(bone => bones.get(bone.name) === bone), 'shoe must share the live avatar skeleton');
    presentBody(avatar.scene, '#623a27', new Set(['feet']));
    assert.equal(avatar.scene.getObjectByName('region_feet').visible, false);
    assert.equal(avatar.scene.getObjectByName('region_legs').visible, true, 'mask the covered foot, not the exposed leg');
    applyPose(new AnimationMixer(avatar.scene), avatar.animations, 'editorial');
    root.updateMatrixWorld(true); fit.skeleton.update();
    for (let i = 0; i < vertices.count; i += 29) {
      const p = fit.applyBoneTransform(i, new Vector3().fromBufferAttribute(vertices, i));
      assert.ok(p.toArray().every(Number.isFinite));
      assert.ok(p.y > -.005 && p.y < .15, 'changing pose must leave shoes grounded');
    }
  }
});
