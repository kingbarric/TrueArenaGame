import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {AnimationMixer, Bone, Group, SkinnedMesh, Vector3} from 'three';
import {GLTFLoader} from 'three/addons/loaders/GLTFLoader.js';
import {presentUnderwear, presentBody} from '../src/presentation.ts';
import {bindGarment} from '../src/rig.ts';
import {Showcase, SHOWCASE_SECONDS} from '../src/showcase.ts';
import {coverBody} from '../src/coverage.ts';
import {clipMesh} from '../scripts/clip-mesh.mjs';

const catalog = JSON.parse(readFileSync(new URL('../../backend/ta-api/src/main/resources/slay/catalog.json', import.meta.url)));
const path = id => new URL(`../../app/assets/slay_renderer/assets/${id}.glb`, import.meta.url);
async function load(id) {
  const file = readFileSync(path(id)), size = file.readUInt32LE(12), doc = JSON.parse(file.subarray(20, 20 + size));
  // Inspect textures separately; GLTFLoader here exercises the actual skinning.
  doc.materials = doc.materials.map(() => ({pbrMetallicRoughness: {}})); delete doc.images; delete doc.textures;
  doc.buffers[0].uri = `data:application/octet-stream;base64,${file.subarray(28 + size).toString('base64')}`;
  globalThis.ProgressEvent ??= class ProgressEvent {};
  return new GLTFLoader().parseAsync(JSON.stringify(doc), '');
}

test('garment clipping cuts through boundary triangles and preserves UVs instead of leaving jagged hems', () => {
  const mesh = {position: new Float32Array([-1,-1,0, 1,-1,0, 0,1,0]), normal: new Float32Array([0,0,1, 0,0,1, 0,0,1]), uv: new Float32Array([0,0, 1,0, .5,1]), sourceVertices: [0,1,2]};
  const cut = clipMesh(mesh, [p => p[1]]);
  assert.equal(cut.position.length, 9);
  assert.ok(Array.from(cut.position).filter((_,i) => i % 3 === 1).every(y => y >= 0));
  assert.ok(Array.from(cut.uv).includes(.25) && Array.from(cut.uv).includes(.75));
  assert.equal(clipMesh(mesh, [p => p[1] - 2]).position.length, 0);
});

test('both bodies have fitted starter underwear that restores after removing clothes', async () => {
  for (const gender of ['female', 'male']) {
    const {scene} = await load(gender), briefs = scene.getObjectByName('starter_briefs'), bra = scene.getObjectByName('starter_bra');
    assert.ok(briefs instanceof SkinnedMesh && briefs.geometry.index.count > 100);
    assert.equal(!!bra, gender === 'female');
    const material = briefs.material;
    presentBody(scene, '#ffccaa', new Set()); assert.equal(briefs.material, material);
    for (const [slots, visibleBriefs, visibleBra] of [
      [[], true, true], [['tops'], true, false], [['trousers'], false, true],
      [['tops','skirts'], false, false], [['dress'], false, false], [[], true, true],
    ]) {
      presentUnderwear(scene, new Set(slots));
      assert.equal(briefs.visible, visibleBriefs);
      if (bra) assert.equal(bra.visible, visibleBra);
    }
  }
});

test('all forty added female choices have real models, usable thumbnails and earned coin prices', () => {
  const choices = catalog.items.filter(item => item.id.includes('-collection-'));
  assert.equal(choices.length, 40);
  for (const category of ['dress', 'skirts', 'tops', 'trousers']) {
    const set = choices.filter(item => item.category === category);
    assert.equal(set.length, 10); assert.equal(set.filter(item => item.isDefault).length, 4);
    for (const item of set) {
      assert.equal(item.body, 'female');
      const glb = readFileSync(path(item.id)); assert.equal(glb.subarray(0,4).toString(), 'glTF');
      const thumb = readFileSync(new URL(`../../app/assets/slay_renderer/${item.thumbnailUrl}`, import.meta.url));
      assert.equal(thumb.subarray(0,8).toString('hex'), '89504e470d0a1a0a');
      assert.equal(thumb.readUInt32BE(16), 192);
      assert.ok(item.isDefault ? item.coinCost === 0 : item.coinCost >= 40 && item.coinCost <= 150);
    }
  }
});

test('new skirts, cropped tops and trousers follow the live walking rig with bounded vertices', async () => {
  const avatar = await load('female'), root = new Group(); root.add(avatar.scene);
  const bones = new Map(); avatar.scene.traverse(o => {if (o instanceof Bone) bones.set(o.name, o);});
  const mixer = new AnimationMixer(avatar.scene);
  for (const id of ['female-skirts-collection-1','female-skirts-collection-3','female-skirts-collection-6',
    'female-tops-collection-1','female-tops-collection-5','female-trousers-collection-1','female-trousers-collection-3']) {
    const garment = await load(id); bindGarment(garment.scene, bones); root.add(garment.scene);
    const show = new Showcase(root, avatar.scene, mixer, avatar.animations, () => {});
    const done = show.play('confident');
    for (let frame = 0; frame < 30; frame++) {
      show.update(SHOWCASE_SECONDS / 30); root.updateMatrixWorld(true);
      garment.scene.traverse(mesh => {
        if (!(mesh instanceof SkinnedMesh)) return;
        assert.ok(mesh.skeleton.bones.every(b => bones.get(b.name) === b)); mesh.skeleton.update();
        const p = mesh.geometry.getAttribute('position');
        for (let i = 0; i < p.count; i += 29) {
          const v = mesh.applyBoneTransform(i, new Vector3().fromBufferAttribute(p, i));
          assert.ok(v.toArray().every(Number.isFinite) && v.length() < 2.5, id);
        }
      });
    }
    show.update(.01); await done; root.remove(garment.scene);
  }
});

test('shorts and cropped tops mask covered skin while preserving exposed legs and abdomen', async () => {
  const {scene} = await load('female');
  const shins = scene.getObjectByName('region_legs'), torso = scene.getObjectByName('region_torso');
  const originalShins = Array.from(shins.geometry.index.array), originalTorso = Array.from(torso.geometry.index.array);
  coverBody(scene, ['female-trousers-collection-3','female-tops-collection-1']);
  assert.deepEqual(Array.from(shins.geometry.index.array), originalShins);
  const p = torso.geometry.getAttribute('position'), remaining = new Set(torso.geometry.index.array);
  assert.ok(originalTorso.some(i => p.getY(i) > 1.07 && p.getY(i) < 1.17 && remaining.has(i)), 'bare midriff remains visible');
  assert.ok(torso.geometry.index.count < originalTorso.length, 'top has a real coverage mask');
  coverBody(scene, []); assert.deepEqual(Array.from(torso.geometry.index.array), originalTorso);
});
