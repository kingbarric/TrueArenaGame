import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {AnimationMixer, Bone, Group, SkinnedMesh, Vector3} from 'three';
import {GLTFLoader} from 'three/addons/loaders/GLTFLoader.js';
import {Showcase, SHOWCASE_SECONDS} from '../src/showcase.ts';
import {bindGarment} from '../src/rig.ts';
import {selectBodyFit, applyPose} from '../src/poses.ts';

async function load(id) {
  const file = readFileSync(new URL(`../../app/assets/slay_renderer/assets/${id}.glb`, import.meta.url));
  const n = file.readUInt32LE(12), doc = JSON.parse(file.subarray(20, 20+n));
  doc.materials = doc.materials.map(() => ({pbrMetallicRoughness: {}}));
  delete doc.images; delete doc.textures;
  doc.buffers[0].uri = `data:application/octet-stream;base64,${file.subarray(28+n).toString('base64')}`;
  globalThis.ProgressEvent ??= class ProgressEvent {};
  return new GLTFLoader().parseAsync(JSON.stringify(doc), '');
}
for (const body of ['female', 'male']) test(`${body} runway moves rig and shoes, turns, finishes and cancels cleanly`, async () => {
  const avatar = await load(body), shoes = await load('shoe-1'), root = new Group();
  root.add(avatar.scene, shoes.scene); root.updateMatrixWorld(true);
  const bones = new Map(); avatar.scene.traverse(o => {if(o instanceof Bone) bones.set(o.name,o);});
  selectBodyFit(shoes.scene, body); bindGarment(shoes.scene,bones);
  const mixer = new AnimationMixer(avatar.scene), events = [];
  const show = new Showcase(root, avatar.scene, mixer, avatar.animations, (playing,phase)=>events.push({playing,phase}));
  applyPose(mixer,avatar.animations,'editorial');
  const complete = show.play('confident');
  assert.throws(()=>show.play(),/already playing/);
  const heights = [], positions = [];
  for(let frame=0;frame<=Math.ceil(SHOWCASE_SECONDS*60);frame++) {
    show.update(1/60); root.updateMatrixWorld(true);
    heights.push(bones.get('LeftFoot').getWorldPosition(new Vector3()).y);
    positions.push(bones.get('LeftFoot').getWorldPosition(new Vector3()).z);
    shoes.scene.traverse(mesh=>{
      if(!(mesh instanceof SkinnedMesh) || !mesh.visible) return;
      mesh.skeleton.update(); const vertices=mesh.geometry.getAttribute('position');
      for(let i=0;i<vertices.count;i+=29) {
        const p=mesh.applyBoneTransform(i,new Vector3().fromBufferAttribute(vertices,i)).applyMatrix4(mesh.matrixWorld);
        assert.ok(p.toArray().every(Number.isFinite));
        assert.ok(p.y>-.012,`${body}: shoe below floor at ${frame}: ${p.y}`);
      }
    });
    if(frame===180) assert.ok(root.rotation.y>0 && root.rotation.y<2*Math.PI);
  }
  assert.equal(await complete,'confident'); assert.equal(show.playing,false);
  assert.ok(Math.max(...heights)-Math.min(...heights)>.04,'feet lift for steps');
  assert.ok(Math.max(...positions)-Math.min(...positions)>.5,'walk approaches the stage');
  assert.equal(root.position.length(),0); assert.equal(root.rotation.y,0);
  assert.deepEqual(events.map(e=>e.phase),['Walking to the stage','Strike a pose','Show every angle','Own the spotlight','Finished']);
  const finalHip=bones.get('Hips').position.clone();
  const interrupted=show.play('editorial'); const rejected=assert.rejects(interrupted,/cancelled/);
  show.update(1); show.stop(); await rejected;
  assert.equal(root.position.length(),0); assert.equal(root.rotation.y,0);
  assert.ok(bones.get('Hips').position.distanceTo(finalHip)<.00001,'walk hip offset resets');
  const replay=show.play('confident'); show.update(SHOWCASE_SECONDS); await replay;
  assert.ok(bones.get('Hips').position.distanceTo(finalHip)<.00001);
});

for (const body of ['female', 'male']) test(`${body} all four finishes start with a catwalk and preserve the selected pose`, async () => {
  const avatar = await load(body), root = new Group(); root.add(avatar.scene);
  const mixer = new AnimationMixer(avatar.scene), bones = [];
  avatar.scene.traverse(o => {if(o instanceof Bone) bones.push(o);});
  const show = new Showcase(root, avatar.scene, mixer, avatar.animations);
  const finishes = [];
  for (const pose of ['signature','confident','editorial','celebrate']) {
    const complete = show.play(pose);
    assert.equal(show.playing,true);
    assert.ok(root.position.z<0,'every choice walks in from backstage');
    show.update(1); assert.ok(root.position.z<0 && root.position.z>-.65);
    show.update(1); assert.ok(Math.abs(root.position.z)<.00001,'walk reaches the stage within two seconds');
    show.update(2.9); assert.equal(show.playing,true,'hold the finishing stance before completion');
    show.update(.1); assert.equal(await complete,pose);
    finishes.push(bones.flatMap(bone=>bone.quaternion.toArray()));
  }
  for(let i=0;i<finishes.length;i++) for(let j=i+1;j<finishes.length;j++) {
    assert.ok(finishes[i].some((value,k)=>Math.abs(value-finishes[j][k])>.04),'each finish has a distinct articulated stance');
  }
});
