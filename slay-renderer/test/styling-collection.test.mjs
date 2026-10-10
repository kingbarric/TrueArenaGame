import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {AnimationMixer, Bone, Group, SkinnedMesh, Vector3, Raycaster} from 'three';
import {GLTFLoader} from 'three/addons/loaders/GLTFLoader.js';
import {presentUnderwear, presentBody} from '../src/presentation.ts';
import {bindGarment} from '../src/rig.ts';
import {applyPose} from '../src/poses.ts';
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

for (const variant of [4,10]) test(`tube top ${variant} covers the chest and back through every pose`,async()=>{
  const avatar=await load('female'),garment=await load(`female-tops-collection-${variant}`),root=new Group();
  root.add(avatar.scene,garment.scene);root.updateMatrixWorld(true);
  const bones=new Map();avatar.scene.traverse(o=>{if(o instanceof Bone)bones.set(o.name,o);});
  bindGarment(garment.scene,bones);
  const torso=avatar.scene.getObjectByName('region_torso'),positions=torso.geometry.getAttribute('position');
  const original=Array.from(torso.geometry.index.array),id=`female-tops-collection-${variant}`;
  coverBody(avatar.scene,[id]);presentUnderwear(avatar.scene,new Set(['tops']));
  assert.ok(torso.geometry.index.count<original.length,'tube band must mask covered skin');
  assert.equal(avatar.scene.getObjectByName('starter_bra').visible,false);
  assert.equal(avatar.scene.getObjectByName('starter_briefs').visible,true,'changing from a dress retains briefs');
  const exposed=new Set(torso.geometry.index.array);
  assert.ok(original.some(i=>positions.getY(i)>1.1 && positions.getY(i)<1.19 && exposed.has(i)),'midriff remains visible');
  const samples=[];
  for(let i=0;i<positions.count;i++) {
    const p=new Vector3().fromBufferAttribute(positions,i);
    if(p.y>1.27 && p.y<1.38 && Math.abs(p.x)<.1 && (p.z>.11 || p.z<-.018))samples.push({index:i,side:p.z>0?1:-1});
  }
  assert.ok(samples.some(s=>s.side===1)&&samples.some(s=>s.side===-1));
  const mixer=new AnimationMixer(avatar.scene),ray=new Raycaster();
  for(const pose of catalog.poses) {
    applyPose(mixer,avatar.animations,pose);root.updateMatrixWorld(true);
    torso.skeleton.update();garment.scene.traverse(o=>{if(o instanceof SkinnedMesh)o.skeleton.update();});
    for(const sample of samples){
      const point=torso.applyBoneTransform(sample.index,new Vector3().fromBufferAttribute(positions,sample.index)).applyMatrix4(torso.matrixWorld);
      const outward=new Vector3(0,0,sample.side).transformDirection(bones.get('Chest').matrixWorld);
      ray.set(point.clone().addScaledVector(outward,.5),outward.clone().negate());
      const hit=ray.intersectObject(garment.scene,true)[0];
      assert.ok(hit && hit.distance<.5, `${id}/${pose}: fabric must cover ${sample.side===1?'chest':'back'} (${hit?.distance})`);
    }
  }
  coverBody(avatar.scene,[]);presentUnderwear(avatar.scene,new Set());
  assert.deepEqual(Array.from(torso.geometry.index.array),original);
  assert.equal(avatar.scene.getObjectByName('starter_bra').visible,true);
});
