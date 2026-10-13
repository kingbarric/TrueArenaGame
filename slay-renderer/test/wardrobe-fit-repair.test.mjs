import {test} from 'node:test';import assert from 'node:assert/strict';import {readFileSync} from 'node:fs';
import {AnimationMixer,Bone,Group,Raycaster,Vector3} from 'three';
import {loadGlb} from '../scripts/glb-node.mjs';import {coverBody} from '../src/coverage.ts';import {VariantFit} from '../src/variant-fit.ts';import {bindGarment} from '../src/rig.ts';import {applyPose} from '../src/poses.ts';import {catwalkClip} from '../src/showcase.ts';import {drapeBust,stabiliseTrouserSeam,concealsFootwear} from '../src/garment-drape.ts';
const assets=new URL('../../app/assets/slay_renderer/assets/',import.meta.url),load=id=>loadGlb(readFileSync(new URL(id+'.glb',assets)));
test('black dress hides covered thighs and bust during all poses and the entire catwalk on all women',async()=>{
 for(const id of ['female','avatar-ella','avatar-beverly','avatar-girl02']){
  const body=await load(id),dress=await load('female-s2-little-black-cocktail-dress'),root=new Group(),bones=new Map();root.add(body.scene,dress.scene);body.scene.traverse(o=>{if(o instanceof Bone)bones.set(o.name,o);});
  if(id!=='female')new VariantFit(JSON.parse(readFileSync(new URL(id+'-fit.json',assets)))).apply(dress.scene);drapeBust(dress.scene);bindGarment(dress.scene,bones);root.updateMatrixWorld(true);const mixer=new AnimationMixer(body.scene),walk=catwalkClip(body.scene);
  coverBody(body.scene,['female-s2-little-black-cocktail-dress']);const surfaces=[];root.traverse(o=>{if(o.isSkinnedMesh&&(o.name.startsWith('region_')||o.name.startsWith('female-s2-')))surfaces.push(o);});
  const check=label=>{root.updateMatrixWorld(true);surfaces.forEach(m=>{m.skeleton.update();m.geometry.computeBoundingSphere();});for(const x of [-.12,-.08,.08,.12])for(const y of [.72,.80,1.30]){const ray=new Raycaster(new Vector3(x,y,2),new Vector3(0,0,-1));const hit=ray.intersectObjects(surfaces,false)[0];assert.ok(hit&&!hit.object.name.startsWith('region_'),id+'/'+label+': skin through dress at '+x+','+y);}};
  for(const pose of ['idle','signature','confident','editorial','celebrate']){applyPose(mixer,body.animations,pose);check(pose);}
  mixer.stopAllAction();mixer.clipAction(walk).reset().play();for(let frame=0;frame<=48;frame++){mixer.update(walk.duration/48);check('gait-'+frame);}
 }
});
test('trouser centre seam uses the pelvis while outer legs preserve their authored weights',async()=>{
 const trousers=await load('male-trousers-classic');let centre=0,outer=0;
 trousers.scene.traverse(mesh=>{if(!mesh.isSkinnedMesh)return;const p=mesh.geometry.attributes.position,w=mesh.geometry.attributes.skinWeight;mesh.userData.before=Array.from(w.array);});stabiliseTrouserSeam(trousers.scene);
 trousers.scene.traverse(mesh=>{if(!mesh.isSkinnedMesh)return;const p=mesh.geometry.attributes.position,w=mesh.geometry.attributes.skinWeight,j=mesh.geometry.attributes.skinIndex;for(let i=0;i<p.count;i++){if(Math.abs(p.getX(i))<.006&&p.getY(i)>.84&&p.getY(i)<1.05){assert.equal(mesh.skeleton.bones[j.getX(i)].name,'Hips');assert.ok(w.getX(i)>.999);centre++;}if(Math.abs(p.getX(i))>.10){for(let k=0;k<4;k++)assert.equal(w.getComponent(i,k),mesh.userData.before[i*4+k]);outer++;}}});assert.ok(centre>0);assert.ok(outer>100);
});

test('floor-length trains conceal footwear while short dresses leave it visible',async()=>{
 assert.equal(concealsFootwear((await load('female-redcarpet')).scene),true);
 assert.equal(concealsFootwear((await load('female-s2-little-black-cocktail-dress')).scene),false);
 assert.equal(concealsFootwear((await load('female-date-cutout')).scene),false);
});
