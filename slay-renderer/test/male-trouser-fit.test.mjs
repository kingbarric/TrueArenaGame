import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {AnimationMixer, Bone, Group, Raycaster, Vector3} from 'three';
import {GLTFLoader} from 'three/addons/loaders/GLTFLoader.js';
import {VariantFit} from '../src/variant-fit.ts';
import {bindGarment} from '../src/rig.ts';
import {applyPose} from '../src/poses.ts';
import {coverBody} from '../src/coverage.ts';
const assets = new URL('../../app/assets/slay_renderer/assets/', import.meta.url);
async function load(id) {
  const bytes = readFileSync(new URL(id + '.glb', assets)), n = bytes.readUInt32LE(12);
  const doc = JSON.parse(bytes.subarray(20, 20 + n));
  doc.materials = doc.materials.map(() => ({pbrMetallicRoughness: {}, doubleSided: true}));
  delete doc.images; delete doc.textures;
  doc.buffers[0].uri = 'data:application/octet-stream;base64,' + bytes.subarray(28 + n).toString('base64');
  globalThis.ProgressEvent ??= class ProgressEvent {};
  return new GLTFLoader().parseAsync(JSON.stringify(doc), '');
}
test('all male bottoms cover the waist around both male characters in every finish', async () => {
  for (const id of ['male', 'avatar-indian-male']) {
    const avatar = await load(id), root = new Group(); root.add(avatar.scene);
    const bones = new Map(); avatar.scene.traverse(o => {if (o instanceof Bone) bones.set(o.name, o);});
    const fit = id === 'male' ? null : new VariantFit(JSON.parse(readFileSync(new URL(id + '-fit.json', assets))));
    const torso = avatar.scene.getObjectByName('region_torso'), p = torso.geometry.attributes.position;
    const samples = [];
    for (let i = 0; i < p.count; i++) if (p.getY(i) > 1.02 && p.getY(i) < 1.10 && Math.abs(p.getX(i)) < .25) samples.push(i);
    assert.ok(samples.length > 15, 'waist samples include front, sides and back');
    const mixer = new AnimationMixer(avatar.scene), ray = new Raycaster();
    for (const style of ['classic', 'cargo', 'harem', 'denim-shorts']) {
      const garment = await load('male-trousers-' + style); fit?.apply(garment.scene); bindGarment(garment.scene, bones); root.add(garment.scene);
      for (const pose of ['signature', 'confident', 'editorial', 'celebrate']) {
        applyPose(mixer, avatar.animations, pose); root.updateMatrixWorld(true); torso.skeleton.update();
        garment.scene.traverse(o => {if (o.isSkinnedMesh) o.skeleton.update();});
        for (const i of samples) {
          const rest = new Vector3().fromBufferAttribute(p, i), outward = new Vector3(rest.x, 0, rest.z - .025).normalize();
          const point = torso.applyBoneTransform(i, rest.clone()).applyMatrix4(torso.matrixWorld);
          const origin = torso.applyBoneTransform(i, rest.clone().addScaledVector(outward, .4)).applyMatrix4(torso.matrixWorld);
          ray.set(origin, point.clone().sub(origin).normalize());
          const hit = ray.intersectObject(garment.scene, true)[0];
          assert.ok(hit && hit.distance < origin.distanceTo(point), `${id}/${style}/${pose}: waist skin exposed at ${rest.toArray()} (${hit?.distance})`);
        }
      }
      root.remove(garment.scene);
    }
  }
});
test('male trouser masks retain the abdomen above the dipped waistband and restore on removal', async () => {
  for (const id of ['male', 'avatar-indian-male']) {
    const avatar = await load(id), torso = avatar.scene.getObjectByName('region_torso');
    const original = Array.from(torso.geometry.index.array), p = torso.geometry.attributes.position;
    for (const style of ['classic', 'cargo', 'harem', 'denim-shorts']) {
      coverBody(avatar.scene, ['male-trousers-' + style]);
      const visible = new Set(torso.geometry.index.array);
      for (let i = 0; i < original.length; i += 3) {
        const triangle = original.slice(i, i + 3);
        if (triangle.some(j => p.getY(j) > 1.14)) assert.ok(triangle.every(j => visible.has(j)), id + '/' + style + ': exposed abdomen erased');
      }
      assert.ok(torso.geometry.index.count < original.length, 'covered lower waist is still masked');
      coverBody(avatar.scene, []); assert.deepEqual(Array.from(torso.geometry.index.array), original);
    }
  }
});
