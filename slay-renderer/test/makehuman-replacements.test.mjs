import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {AnimationMixer,Bone,Group,Raycaster,Vector3} from 'three';
import {loadGlb} from '../scripts/glb-node.mjs';
import {VariantFit} from '../src/variant-fit.ts';
import {bindGarment} from '../src/rig.ts';
import {applyPose} from '../src/poses.ts';
import {coverBody} from '../src/coverage.ts';
import {presentFace,presentEyes,presentUnderwear} from '../src/presentation.ts';
const root=new URL('../../app/assets/slay_renderer/assets/',import.meta.url);
const catalog=JSON.parse(readFileSync(new URL('../../backend/ta-api/src/main/resources/slay/catalog.json',import.meta.url)));
const load=id=>loadGlb(readFileSync(new URL(id+'.glb',root)));

test('curvy and slim MakeHuman replacements preserve the named rig, body topology and customisation',async()=>{
 for(const [id,name,body] of [['ella','Ella','female'],['beverly','Elisabeth','female']]){
  const entry=catalog.avatars.find(a=>a.id===id);assert.equal(entry?.name,name);assert.equal(entry.body,body);
  const avatar=await load('avatar-'+id),base=await load(body),bones=new Map(),expected=new Set();
  avatar.scene.traverse(o=>{if(o instanceof Bone){assert.ok(!bones.has(o.name));bones.set(o.name,o);}});base.scene.traverse(o=>{if(o instanceof Bone)expected.add(o.name);});
  assert.deepEqual(new Set(bones.keys()),expected);assert.equal(bones.size,18);
  assert.deepEqual(new Set(avatar.animations.map(a=>a.name)),new Set(['idle',...catalog.poses]));
  const fit=new VariantFit(JSON.parse(readFileSync(new URL(entry.fitUrl.split('/').pop(),root)))),scene=new Group();scene.add(avatar.scene);
  const ids=body==='female'?['female-s2-little-black-cocktail-dress','female-top-camisole','female-trousers-tailored','female-hair-long','female-eyes-blue','female-shoe-maryjane']:['male-essential','male-tee-polo','male-trousers-classic','male-hair-0','male-eyes-blue','shoe-1'];
  for(const garmentId of ids){const garment=await load(garmentId);fit.apply(garment.scene);bindGarment(garment.scene,bones);scene.add(garment.scene);}
  const meshes=[];avatar.scene.traverse(o=>{if(o.isSkinnedMesh&&o.name.startsWith('region_'))meshes.push(o);});assert.ok(meshes.length>=6);
  presentFace(avatar.scene,'classic','signature');scene.updateMatrixWorld(true);
  const originals=new Map(meshes.map(m=>[m,Array.from(m.geometry.index.array)]));
  let masks=0;
  for(const mesh of meshes){
   const original=base.scene.getObjectByName(mesh.name);assert.ok(original);assert.deepEqual(Array.from(mesh.geometry.index.array),Array.from(original.geometry.index.array));assert.deepEqual(mesh.userData.slayCoverage,original.userData.slayCoverage);
   for(const triangles of Object.values(mesh.userData.slayCoverage)){assert.ok(triangles.every(i=>Number.isInteger(i)&&i>=0&&i*3<mesh.geometry.index.count));masks+=triangles.length;}
   mesh.skeleton.update();for(let i=0;i<mesh.geometry.index.count;i+=127){const vertex=mesh.geometry.index.getX(i),rest=new Vector3().fromBufferAttribute(mesh.geometry.attributes.position,vertex),posed=mesh.getVertexPosition(vertex,new Vector3());assert.ok(rest.distanceTo(posed)<.00001,id+': neutral bind must not deform the source');}
  }assert.ok(masks>500,id+': wardrobe masks');
  const clothes=body==='female'?['female-s2-little-black-cocktail-dress']:['male-essential'];coverBody(avatar.scene,clothes);
  assert.ok(meshes.some(m=>m.geometry.index.count<originals.get(m).length));
  for(const face of catalog.facePresets){presentFace(scene,face,'confident');let controls=0;avatar.scene.traverse(o=>{const index=o.morphTargetDictionary?.['face_'+face];if(index!==undefined){assert.equal(o.morphTargetInfluences[index],1);controls++;}});assert.ok(controls>0);}
  presentEyes(avatar.scene,true);assert.equal(avatar.scene.getObjectByName('face_eyes').visible,false);presentEyes(avatar.scene,false);
  presentUnderwear(avatar.scene,new Set(['outfit']));let underwear=0;avatar.scene.traverse(o=>{if(o.userData.slayUnderwear||['starter_bra','starter_briefs'].includes(o.name)){assert.equal(o.visible,false);underwear++;}});assert.ok(underwear>0);
  presentUnderwear(avatar.scene,new Set());avatar.scene.traverse(o=>{if(o.userData.slayUnderwear)assert.equal(o.visible,true);});
  const mixer=new AnimationMixer(avatar.scene);
  for(const pose of ['idle',...catalog.poses]){
   applyPose(mixer,avatar.animations,pose);mixer.update(.2);scene.updateMatrixWorld(true);
   scene.traverse(o=>{if(!o.isSkinnedMesh)return;o.skeleton.update();for(let i=0;i<o.geometry.index.count;i+=157){const p=o.getVertexPosition(o.geometry.index.getX(i),new Vector3());assert.ok(p.toArray().every(Number.isFinite));assert.ok(p.length()<3.1,id+'/'+pose+': bounded body and wardrobe');}});
  }
  coverBody(avatar.scene,[]);for(const mesh of meshes)assert.deepEqual(Array.from(mesh.geometry.index.array),originals.get(mesh));
 }
});

test('the green flapper dress no longer appears and saved item IDs resolve to the black cocktail dress',()=>{
 for(const id of ['female-essential','female-dress-collection-9']){
  const item=catalog.items.find(i=>i.id===id);assert.equal(item.name,'Little Black Dress');assert.equal(item.assetUrl,'assets/female-s2-little-black-cocktail-dress.glb');
  assert.equal(catalog.wardrobePresentation[id].maskOf,'female-s2-little-black-cocktail-dress');
 }
 assert.ok(catalog.avatars.every(a=>!['Amara','Kofi','Zuri','Tayo','Femi','Tolu'].includes(a.name)));
});

test('distorted Michael is removed while Alexander and Ethan remain available',()=>{assert.ok(!catalog.avatars.some(a=>a.id==='michael'));for(const id of ['male','indian-male'])assert.ok(catalog.avatars.some(a=>a.id===id));});


test('female replacements and Chloe share smooth normals at duplicated body seams',async()=>{
 for(const id of ['ella','beverly','girl02']){
  const avatar=await load('avatar-'+id),seen=new Map();let seams=0;
  avatar.scene.traverse(mesh=>{
   if(!mesh.isSkinnedMesh||!mesh.name.startsWith('region_'))return;
   const positions=mesh.geometry.attributes.position,normals=mesh.geometry.attributes.normal;
   for(let i=0;i<positions.count;i++){
    const key=[positions.getX(i),positions.getY(i),positions.getZ(i)].map(v=>v.toFixed(6)).join(','),normal=new Vector3().fromBufferAttribute(normals,i);
    if(seen.has(key)){assert.ok(normal.distanceTo(seen.get(key))<.00001,id+': visible normal seam');seams++;}else seen.set(key,normal);
   }
  });assert.ok(seams>50,id+': exercises duplicated seam vertices');
 }
});


test('preview bras and briefs cover the body from front and back through each pose',async()=>{
 for(const id of ['ella','beverly','girl02']){
  const avatar=await load('avatar-'+id),mixer=new AnimationMixer(avatar.scene),surfaces=[];
  avatar.scene.traverse(mesh=>{if(mesh.isSkinnedMesh&&(['region_torso','region_upper_legs','starter_bra','starter_briefs'].includes(mesh.name)))surfaces.push(mesh);});
  for(const pose of ['idle',...catalog.poses]){
   applyPose(mixer,avatar.animations,pose);mixer.update(.1);avatar.scene.updateMatrixWorld(true);surfaces.forEach(mesh=>mesh.skeleton.update());
   for(const side of [1,-1])for(const x of [-.10,-.04,.04,.10])for(const [y,name] of [[1.30,'starter_bra'],[.90,'starter_briefs']]){
    const ray=new Raycaster(new Vector3(x,y,side*2),new Vector3(0,0,-side));
    const first=ray.intersectObjects(surfaces,false)[0];assert.equal(first?.object.name,name,id+'/'+pose+'/'+side+': underwear must sit over the covered skin');
   }
  }
 }
});
