import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {Vector3, SkinnedMesh} from 'three';
import {GLTFLoader} from 'three/addons/loaders/GLTFLoader.js';

const asset = id => {
  const file = readFileSync(new URL(`../../app/assets/slay_renderer/assets/${id}.glb`, import.meta.url));
  const jsonLength = file.readUInt32LE(12);
  return {doc: JSON.parse(file.subarray(20, 20 + jsonLength).toString()), bin: file.subarray(28 + jsonLength)};
};

test('starter GLBs contain actual PNG textures, unique scene roots and bounded geometry', () => {
  for (const id of ['female', 'male', 'female-essential', 'male-essential', 'female-hair-0', 'shoe-0']) {
    const {doc, bin} = asset(id);
    const view = doc.bufferViews[doc.images[0].bufferView];
    assert.equal(bin.subarray(view.byteOffset, view.byteOffset + 8).toString('hex'), '89504e470d0a1a0a', id);
    const roots = doc.scenes[0].nodes;
    const children = new Set(doc.nodes.flatMap(node => node.children ?? []));
    assert.equal(new Set(roots).size, roots.length, `${id}: duplicate roots`);
    assert.ok(roots.every(root => !children.has(root)), `${id}: bone cannot be both a root and a child`);
    for (const mesh of doc.meshes) {
      const position = doc.accessors[mesh.primitives[0].attributes.POSITION];
      assert.ok(position.min && position.max, `${id}: missing bounds`);
    }
  }
});

test('starter skinning leaves both bodies upright and in their bind pose', async () => {
  for (const id of ['female', 'male']) {
    const {doc, bin} = asset(id);
    // Textures are validated above. Parse geometry without requiring a DOM.
    doc.materials = doc.materials.map(() => ({pbrMetallicRoughness: {}})); delete doc.images; delete doc.textures;
    doc.buffers[0].uri = `data:application/octet-stream;base64,${bin.toString('base64')}`;
    globalThis.ProgressEvent ??= class ProgressEvent {};
    const gltf = await new GLTFLoader().parseAsync(JSON.stringify(doc), '');
    gltf.scene.updateMatrixWorld(true);
    let checked = 0;
    gltf.scene.traverse(mesh => {
      if (!(mesh instanceof SkinnedMesh)) return;
      mesh.skeleton.update();
      const position = mesh.geometry.getAttribute('position');
      for (let i = 0; i < position.count; i += 37) {
        const original = new Vector3().fromBufferAttribute(position, i);
        const posed = mesh.applyBoneTransform(i, original.clone());
        assert.ok(posed.distanceTo(original) < .00001, `${id}: skinning moved a bind-pose vertex`);
        checked++;
      }
    });
    assert.ok(checked > 10);
  }
});

test('hair remains at head height and only the starter pack is in the Flutter bundle', () => {
  const {doc} = asset('female-hair-0');
  const accessor = doc.accessors[doc.meshes[0].primitives[0].attributes.POSITION];
  assert.ok(accessor.min[1] > 1.6);
  const pubspec = readFileSync(new URL('../../app/pubspec.yaml', import.meta.url), 'utf8');
  assert.match(pubspec, /- assets\/slay_renderer\/starter\//);
  assert.doesNotMatch(pubspec, /- assets\/slay_renderer\/assets\//);
});

test('starter eyes sit at face height rather than above the scalp', () => {
  for (const [id, low, high] of [['female', 1.65, 1.70], ['male', 1.80, 1.85]]) {
    const {doc} = asset(id);
    const eyes = doc.meshes.find(mesh => mesh.name === 'face_eyes');
    const bounds = doc.accessors[eyes.primitives[0].attributes.POSITION];
    assert.ok(bounds.min[1] > low && bounds.max[1] < high, `${id}: misplaced eyes`);
  }
});
