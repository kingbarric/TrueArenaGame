import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {AnimationMixer, Bone, Group, Raycaster, Vector3} from 'three';
import {GLTFLoader} from 'three/addons/loaders/GLTFLoader.js';
import {fitMaleSeparates} from '../src/male-separates.ts';
import {VariantFit} from '../src/variant-fit.ts';
import {bindGarment} from '../src/rig.ts';
import {applyPose} from '../src/poses.ts';
import {Showcase} from '../src/showcase.ts';
import {coverBody} from '../src/coverage.ts';
import {presentUnderwear} from '../src/presentation.ts';
const assets = new URL('../../app/assets/slay_renderer/assets/', import.meta.url);
async function load(id) {
  const bytes=readFileSync(new URL(id+'.glb',assets)),n=bytes.readUInt32LE(12),doc=JSON.parse(bytes.subarray(20,20+n));
  doc.materials=doc.materials.map(()=>({pbrMetallicRoughness:{},doubleSided:true}));delete doc.images;delete doc.textures;
  doc.buffers[0].uri='data:application/octet-stream;base64,'+bytes.subarray(28+n).toString('base64');globalThis.ProgressEvent??=class ProgressEvent{};
  return new GLTFLoader().parseAsync(JSON.stringify(doc),'');
}
test('polo and tucked tee meet the waistband without long tails or a cropped abdomen',async()=>{
  for(const style of ['polo','tucked']) {
    const shirt=await load('male-tee-'+style),p=shirt.scene.children.find(o=>o.isSkinnedMesh).geometry.attributes.position;
    const heights=Array.from(p.array).filter((_,i)=>i%3===1);
    assert.ok(Math.abs(Math.min(...heights)-1.105)<.0001,style+': hem must reach the waist without extending through the trousers');
  }
});
test('male shirt coverage leaves exposed midriff and briefs when no trousers are selected',async()=>{
  for(const id of ['male','avatar-indian-male']) {
    const avatar=await load(id),torso=avatar.scene.getObjectByName('region_torso'),p=torso.geometry.attributes.position,original=Array.from(torso.geometry.index.array);
    for(const style of ['polo','tucked','relaxed']) {
      coverBody(avatar.scene,['male-tee-'+style]);presentUnderwear(avatar.scene,new Set(['shirts']));
      assert.equal(avatar.scene.getObjectByName('starter_briefs').visible,true);
      assert.ok(torso.geometry.index.count<original.length,'covered chest is masked');
      const visible=new Set(torso.geometry.index.array);
      assert.ok(original.some(i=>p.getY(i)<1.06 && visible.has(i)),'abdomen below hem is retained');
      coverBody(avatar.scene,[]);assert.deepEqual(Array.from(torso.geometry.index.array),original);
    }
  }
});
test('all male shirt/trouser combinations retain their layer order through every pose and reset cleanly',async()=>{
  for(const id of ['male','avatar-indian-male']) {
    const avatar=await load(id),bones=new Map();avatar.scene.traverse(o=>{if(o instanceof Bone)bones.set(o.name,o);});
    const fit=id==='male'?null:new VariantFit(JSON.parse(readFileSync(new URL(id+'-fit.json',assets))));
    const root=new Group();root.add(avatar.scene);const mixer=new AnimationMixer(avatar.scene),ray=new Raycaster();
    for(const style of ['polo','tucked','relaxed']) {
      const shirt=await load('male-tee-'+style),sourcePositions=Array.from(shirt.scene.children.find(o=>o.isSkinnedMesh).geometry.attributes.position.array);fit?.apply(shirt.scene);bindGarment(shirt.scene,bones);root.add(shirt.scene);
      const mesh=shirt.scene.children.find(o=>o.isSkinnedMesh),p=mesh.geometry.attributes.position,baseline=Array.from(p.array),tucked=style!=='relaxed';
      for(const bottom of ['classic','cargo','harem','denim-shorts']) {
        const pants=await load('male-trousers-'+bottom);fit?.apply(pants.scene);bindGarment(pants.scene,bones);root.add(pants.scene);
        fitMaleSeparates(shirt.scene,pants.scene,tucked);
        const fitted=Array.from(p.array);fitMaleSeparates(shirt.scene,pants.scene,tucked);assert.deepEqual(Array.from(p.array),fitted,'recolour/reapply must not accumulate fit');
        const candidates=[],indices=mesh.geometry.index.array;
        for(let f=0;f<indices.length;f+=3){
          const ids=Array.from(indices.slice(f,f+3));
          const y=ids.reduce((n,i)=>n+sourcePositions[i*3+1],0)/3;
          if(y>1.075 && y<(tucked?1.116:1.135) && ids.every(i=>Math.abs(sourcePositions[i*3])<.25))candidates.push(ids);
        }
        const samples=candidates.filter((_,i)=>i%Math.max(1,Math.floor(candidates.length/24))===0);
        assert.ok(samples.length>10,style+': hem samples');
        const check=(phase)=>{
          root.updateMatrixWorld(true);root.traverse(o=>{if(o.isSkinnedMesh)o.skeleton.update();});
          for(const ids of samples) {
            const rest=new Vector3(),point=new Vector3(),origin=new Vector3();
            for(const i of ids){
              const vertex=new Vector3().fromBufferAttribute(p,i),outward=new Vector3(vertex.x,0,vertex.z-.025).normalize();
              rest.addScaledVector(vertex,1/3);
              point.addScaledVector(mesh.applyBoneTransform(i,vertex.clone()).applyMatrix4(mesh.matrixWorld),1/3);
              origin.addScaledVector(mesh.applyBoneTransform(i,vertex.clone().addScaledVector(outward,.4)).applyMatrix4(mesh.matrixWorld),1/3);
            }
            ray.set(origin,point.clone().sub(origin).normalize());
            const hit=ray.intersectObject(pants.scene,true)[0];
            assert.ok(hit,`${id}/${style}/${bottom}/${phase}: missing waistband`);
            const shirtDistance=point.distanceTo(origin);
            assert.ok(tucked?hit.distance<shirtDistance-.002:hit.distance>shirtDistance+.002,`${id}/${style}/${bottom}/${phase}: garments intersect at ${rest.toArray()} (clearance ${hit.distance-shirtDistance})`);
          }
        };
        for(const pose of ['signature','confident','editorial','celebrate']) {
          applyPose(mixer,avatar.animations,pose);check(pose);
        }
        const runway=new Showcase(root,avatar.scene,mixer,avatar.animations),finished=runway.play('confident');
        for(const delta of [.3,.5,.5,.7,1.1,1.1,.8]){runway.update(delta);check('catwalk/turn');}
        assert.equal(await finished,'confident');
        root.remove(pants.scene);
      }
      fitMaleSeparates(shirt.scene,undefined,tucked);assert.deepEqual(Array.from(p.array),baseline,'removing trousers restores original fit');root.remove(shirt.scene);
    }
  }
});
