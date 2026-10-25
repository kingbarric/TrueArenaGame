import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync, existsSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {AnimationMixer, Bone, Group, Vector3} from 'three';
import {GLTFLoader} from 'three/addons/loaders/GLTFLoader.js';
import {bindGarment} from '../src/rig.ts';
import {applyPose} from '../src/poses.ts';
import {hairExpansion} from '../scripts/hair-expansion.mjs';

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

for (const body of ['female', 'male']) test(`${body} has twelve delivered hairstyles with different geometry, never colour-only copies`, () => {
  const choices = catalog.items.filter(i => i.body === body && i.category === 'hair' && i.assetUrl);
  assert.equal(choices.length, 12);
  const shapes = new Set();
  for (const item of choices) {
    assert.ok(existsSync(new URL(`../../app/assets/slay_renderer/${item.thumbnailUrl}`, import.meta.url)));
    const {doc, bin} = data(item.id), primitive = doc.meshes[0].primitives[0];
    const position = doc.bufferViews[doc.accessors[primitive.attributes.POSITION].bufferView];
    const digest = createHash('sha256').update(bin.subarray(position.byteOffset, position.byteOffset + position.byteLength)).digest('hex');
    assert.ok(!shapes.has(digest), item.id + ': repeated silhouette'); shapes.add(digest);
    assert.equal(doc.materials[0].alphaMode, 'MASK');
    assert.equal(item.isDefault, item.coinCost === 0);
  }
});

test('new hairstyles fit their body head origin and stay on its live rig throughout every pose', async () => {
  for (const body of ['female', 'male']) {
    const avatar = await load(body), root = new Group(); root.add(avatar.scene);
    const bones = new Map(); avatar.scene.traverse(o => {if (o instanceof Bone) bones.set(o.name, o);});
    const mixer = new AnimationMixer(avatar.scene), head = bones.get('Head');
    for (const item of hairExpansion.filter(i => i.body === body)) {
      const hair = await load(item.id); bindGarment(hair.scene, bones); root.add(hair.scene);
      const mesh = hair.scene.getObjectByName(item.id), p = mesh.geometry.getAttribute('position');
      mesh.geometry.computeBoundingBox(); const bounds = mesh.geometry.boundingBox;
      assert.ok(bounds.max.y > (body === 'male' ? 1.90 : 1.75) && bounds.max.y < 2.25, item.id + ': scalp origin');
      const weights = mesh.geometry.getAttribute('skinWeight'), joints = mesh.geometry.getAttribute('skinIndex');
      for (let i = 0; i < weights.count; i += 17) {
        assert.equal(weights.getX(i), 1); assert.equal(mesh.skeleton.bones[joints.getX(i)], head);
      }
      for (const pose of catalog.poses) {
        applyPose(mixer, avatar.animations, pose); root.updateMatrixWorld(true); mesh.skeleton.update();
        const toHead = head.matrixWorld.clone().invert();
        for (let i = 0; i < p.count; i += 73) {
          const vertex = mesh.localToWorld(mesh.getVertexPosition(i, new Vector3())).applyMatrix4(toHead);
          const expected = new Vector3().fromBufferAttribute(p, i).sub(new Vector3(0, body === 'male' ? 1.82 : 1.66, .025));
          assert.ok(vertex.distanceTo(expected) < .00001, item.id + '/' + pose + ': hairstyle slipped from head');
        }
      }
      mixer.stopAllAction(); root.remove(hair.scene);
    }
  }
});
