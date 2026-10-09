import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {AnimationMixer, SkinnedMesh, Vector3} from 'three';
import {GLTFLoader} from 'three/addons/loaders/GLTFLoader.js';
import {coverBody} from '../src/coverage.ts';
import {applyPose} from '../src/poses.ts';
import {deletedVertices, proxyCoverage, coveredTriangles} from '../scripts/makehuman-coverage.mjs';

test('MakeHuman coverage transfers authored ranges through the proxy without deleting exposed boundary faces', () => {
  const deleted = deletedVertices('name Dress\ndelete_verts\n1 - 3 7\n# comment\n9\nmaterial next');
  assert.deepEqual([...deleted], [1, 2, 3, 7, 9]);
  const weights = proxyCoverage('verts 0\n1 2 8 .3 .3 .4 0 0 0\n4 5 6 .2 .3 .5 0 0 0\n7\n9\n', deleted);
  assert.deepEqual(weights, [.6, 0, 1, 1]);
  assert.deepEqual(coveredTriangles([0, 2, 3, 0, 1, 2], weights), [0]);
});

async function avatar() {
  const file = readFileSync(new URL('../../app/assets/slay_renderer/assets/female.glb', import.meta.url));
  const length = file.readUInt32LE(12), doc = JSON.parse(file.subarray(20, 20 + length));
  doc.materials = doc.materials.map(() => ({pbrMetallicRoughness: {}}));
  delete doc.images; delete doc.textures;
  doc.buffers[0].uri = `data:application/octet-stream;base64,${file.subarray(28 + length).toString('base64')}`;
  globalThis.ProgressEvent ??= class ProgressEvent {};
  return new GLTFLoader().parseAsync(JSON.stringify(doc), '');
}

test('all seven female outfits remove only their covered triangles and restore skin when switched or removed', async () => {
  const {scene} = await avatar();
  const meshes = []; scene.traverse(mesh => {if (mesh instanceof SkinnedMesh && mesh.name.startsWith('region_')) meshes.push(mesh);});
  const originals = new Map(meshes.map(mesh => [mesh, Array.from(mesh.geometry.index.array)]));
  for (const outfit of ['female-essential', 'female-executive', 'female-redcarpet', 'female-romantic', 'female-night', 'female-business', 'female-dinner']) {
    coverBody(scene, [outfit]);
    let removed = 0;
    for (const mesh of meshes) {
      const indices = originals.get(mesh), hidden = new Set(mesh.userData.slayCoverage[outfit]);
      assert.ok([...hidden].every(index => index >= 0 && index * 3 < indices.length));
      const expected = indices.filter((_, i) => !hidden.has(Math.floor(i / 3)));
      assert.deepEqual(Array.from(mesh.geometry.index.array), expected, `${outfit}/${mesh.name}`);
      removed += hidden.size;
    }
    assert.ok(removed > 100, `${outfit}: must mask substantial covered skin`);
    const head = scene.getObjectByName('region_head'), headPosition = head.geometry.getAttribute('position');
    const visibleHead = new Set(head.geometry.index.array);
    for (const index of originals.get(head)) if (headPosition.getY(index) > 1.55) {
      assert.ok(visibleHead.has(index), 'face remains intact; a high collar can cover the lower neck');
    }
    const stable = meshes[0].geometry.index;
    coverBody(scene, [outfit]); assert.equal(meshes[0].geometry.index, stable, 'unchanged look does not allocate new indices');
  }
  // Short dresses restore the shins covered by a previous floor-length dress.
  coverBody(scene, ['female-romantic']);
  const legs = scene.getObjectByName('region_legs');
  assert.deepEqual(Array.from(legs.geometry.index.array), originals.get(legs));
  const torso = scene.getObjectByName('region_torso');
  const position = torso.geometry.getAttribute('position');
  const remaining = new Set(torso.geometry.index.array);
  assert.ok([...remaining].some(i => position.getY(i) > 1.28 && position.getZ(i) < -.05), 'halter open back remains visible');
  coverBody(scene, []);
  for (const mesh of meshes) assert.deepEqual(Array.from(mesh.geometry.index.array), originals.get(mesh), 'unequip restores every original face');
});

test('garment coverage stays applied through every animated fashion pose', async () => {
  const {scene, animations} = await avatar();
  const mixer = new AnimationMixer(scene);
  for (const outfit of ['female-redcarpet', 'female-romantic', 'female-night']) {
    coverBody(scene, [outfit]);
    const torso = scene.getObjectByName('region_torso'), originalMask = Array.from(torso.geometry.index.array);
    for (const pose of ['signature', 'confident', 'editorial', 'celebrate']) {
      applyPose(mixer, animations, pose); mixer.update(1.5); scene.updateMatrixWorld(true);
      assert.deepEqual(Array.from(torso.geometry.index.array), originalMask, 'pose must not bring hidden skin back');
      scene.traverse(mesh => {
        if (!(mesh instanceof SkinnedMesh)) return;
        mesh.skeleton.update();
        const position = mesh.geometry.getAttribute('position');
        for (let i = 0; i < mesh.geometry.index.count; i += 53) {
          const vertex = mesh.geometry.index.getX(i);
          assert.ok(mesh.applyBoneTransform(vertex, new Vector3().fromBufferAttribute(position, vertex)).toArray().every(Number.isFinite));
        }
      });
    }
  }
});
