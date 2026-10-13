import {test} from 'node:test';import assert from 'node:assert/strict';import {readFileSync} from 'node:fs';
import {Bone,Group,Vector3,Raycaster,AnimationMixer} from 'three';import {loadGlb} from '../scripts/glb-node.mjs';import {restoreBindSpace,bindGarment} from '../src/rig.ts';import {VariantFit} from '../src/variant-fit.ts';import {coverBody} from '../src/coverage.ts';import {drapeBust} from '../src/garment-drape.ts';
import {fitFemaleSeparates} from '../src/male-separates.ts';import {applyPose} from '../src/poses.ts';import {catwalkClip} from '../src/showcase.ts';
const root=new URL('../../',import.meta.url),c=JSON.parse(readFileSync(new URL('app/assets/slay_renderer/catalog.json',root)));
const source=id=>loadGlb(readFileSync(new URL('app/assets/slay_renderer/assets/'+id+'.glb',root)));
const delivered=id=>loadGlb(readFileSync(new URL('website/slay-assets/'+c.assets.files['assets/'+id+'.glb'].name,root)));
test('compressed garments fit and bind like the uncompressed preview',async()=>{
 for(const id of ['female-s0-hoodie-dress','female-s2-little-black-cocktail-dress']){
  const [a,b,body]=await Promise.all([source(id),delivered(id),source('avatar-ella')]);restoreBindSpace(b.scene);
  const meshes=g=>{const m=[];g.scene.traverse(o=>{if(o.isSkinnedMesh)m.push(o);});return m;};const aa=meshes(a),bb=meshes(b);
  const fit=new VariantFit(JSON.parse(readFileSync(new URL('app/assets/slay_renderer/assets/avatar-ella-fit.json',root))));
  for(const g of [a,b]){fit.apply(g.scene);drapeBust(g.scene);}
  const bones=new Map();body.scene.traverse(o=>{if(o instanceof Bone)bones.set(o.name,o);});const r=new Group();r.add(body.scene,a.scene,b.scene);for(const g of [a,b])bindGarment(g.scene,bones);r.updateMatrixWorld(true);
  for(let j=0;j<aa.length;j++){const p=aa[j].geometry.attributes.position,q=bb[j].geometry.attributes.position;for(let i=0;i<p.count;i++){const x=new Vector3().fromBufferAttribute(p,i),y=new Vector3().fromBufferAttribute(q,i);aa[j].applyBoneTransform(i,x);bb[j].applyBoneTransform(i,y);assert.ok(x.distanceTo(y)<.01,id+' fitted delivery matches preview');}}
 }
});
test('delivered short and casual dresses preserve exposed lower legs on all women',async()=>{
 for(const id of ['female','avatar-ella','avatar-beverly','avatar-girl02']){const body=await delivered(id);restoreBindSpace(body.scene);const legs=body.scene.getObjectByName('region_legs'),p=legs.geometry.attributes.position;
  for(const item of c.items.filter(i=>i.category==='dress'&&!i.id.includes('-s3-')&&!i.id.includes('-s4-'))){coverBody(body.scene,[c.wardrobePresentation[item.id]?.maskOf??item.id]);const ix=legs.geometry.index;let visible=0;for(let i=0;i<ix.count;i++)if(p.getY(ix.getX(i))<.25)visible++;assert.ok(visible>0,id+'/'+item.id+' lower legs must remain');}
 }
});

test('tees stay inside the back waistband of Ribbon Shorts on all female characters',async()=>{
 for(const id of ['female','avatar-ella','avatar-beverly','avatar-girl02']){
  const [body,tee,pants]=await Promise.all([delivered(id),delivered('female-top-tee'),delivered('female-s0-ribbon-shorts')]);for(const g of [body,tee,pants])restoreBindSpace(g.scene);
  if(id!=='female'){const fit=new VariantFit(JSON.parse(readFileSync(new URL('app/assets/slay_renderer/assets/'+id+'-fit.json',root))));fit.apply(tee.scene);fit.apply(pants.scene);}drapeBust(tee.scene);fitFemaleSeparates(tee.scene,pants.scene);
  const r=new Group(),bones=new Map();r.add(body.scene,tee.scene,pants.scene);body.scene.traverse(o=>{if(o instanceof Bone)bones.set(o.name,o);});for(const g of [tee,pants])bindGarment(g.scene,bones);const surfaces=[];for(const g of [tee,pants])g.scene.traverse(o=>{if(o.isSkinnedMesh)surfaces.push(o);});
  const check=()=>{r.updateMatrixWorld(true);surfaces.forEach(m=>{m.skeleton.update();m.geometry.computeBoundingSphere();});for(const y of [.98,1.0,1.02])for(const x of [-.12,-.06,0,.06,.12]){const hits=new Raycaster(new Vector3(x,y,-2),new Vector3(0,0,1)).intersectObjects(surfaces,false);if(hits.some(h=>h.object.name==='female-s0-ribbon-shorts'))assert.equal(hits[0].object.name,'female-s0-ribbon-shorts',id+': back waistband');}};
  const mixer=new AnimationMixer(body.scene);for(const pose of ['signature','idle','confident','editorial','celebrate']){applyPose(mixer,body.animations,pose);check();}mixer.stopAllAction();const walk=catwalkClip(body.scene);mixer.clipAction(walk).reset().play();for(let frame=0;frame<=24;frame++){mixer.update(walk.duration/24);check();}
 }
});
