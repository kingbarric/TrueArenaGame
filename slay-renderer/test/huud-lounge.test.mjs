import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {Group,SkinnedMesh,Vector3} from 'three';
import {clone} from 'three/addons/utils/SkeletonUtils.js';
import {seed,seatPose} from '../src/huud-avatar.ts';
import {loadGlb} from '../scripts/glb-node.mjs';
test('lounge seats share geometry but move independent skeletons on both body types',async()=>{
 for(const body of ['male','female']){
  const model=await loadGlb(readFileSync(new URL('../../app/assets/slay_renderer/assets/'+body+'.glb',import.meta.url)));
  const first=clone(model.scene),second=clone(model.scene),room=new Group();room.add(first,second);
  const a=seatPose(first,body),b=seatPose(second,body);room.updateMatrixWorld(true);
  for(const side of ['Left','Right']){
   const hip=a.get(side+'UpperLeg').getWorldPosition(new Vector3()),knee=a.get(side+'LowerLeg').getWorldPosition(new Vector3()),ankle=a.get(side+'Foot').getWorldPosition(new Vector3());
   assert.ok(Math.abs(knee.y-hip.y)<.13,body+': thigh stays nearly horizontal');
   assert.ok(ankle.y<knee.y-.25,body+': shins point down');
  }
  a.get('Head').rotation.y=.2;assert.equal(b.get('Head').rotation.y,0);
  let meshes=0;first.traverse(o=>{if(o instanceof SkinnedMesh){const other=second.getObjectByName(o.name);assert.equal(o.geometry,other.geometry);assert.notEqual(o.skeleton,other.skeleton);meshes++;}});assert.ok(meshes>0);
 }
});
test('identity variations are stable and include both body types',()=>{
 const ids=['me','person1','person2','person3','person4','person5'];
 assert.equal(new Set(ids.map(id=>seed(id)%2)).size,2);
 assert.equal(seed('same-user'),seed('same-user'));
});
test('couch overflow stands apart and the walking path clears furniture',async()=>{
 const {roomPlace,walkPosition,animateBody}=await import('../src/huud-avatar.ts');
 const places=Array.from({length:12},(_,i)=>roomPlace(i));
 assert.equal(places.filter(p=>p.seated).length,8);
 assert.equal(new Set(places.map(p=>`${p.x}/${p.z}`)).size,12);
 for(let i=0;i<100;i++){
  const p=walkPosition(i*Math.PI*2/100);
  assert.ok(Math.abs(p.x)<=1.41&&p.z>=-1.01&&p.z<=1.81);
  assert.ok(Math.abs(p.x)>.75||Math.abs(p.z-.4)>.6,'walk clears coffee table');
 }
 for(const body of ['male','female']){
  const model=await loadGlb(readFileSync(new URL('../../app/assets/slay_renderer/assets/'+body+'.glb',import.meta.url))),root=clone(model.scene),bones=seatPose(root,body);
  animateBody(root,bones,body,0,false,0);assert.equal(Math.abs(root.position.y),0);
  assert.equal(Math.abs(bones.get('LeftUpperLeg').rotation.x),0);
  animateBody(root,bones,body,0,true,.2);
  assert.ok(bones.get('LeftUpperLeg').rotation.x*bones.get('RightUpperLeg').rotation.x<0,'walking legs alternate');
 }
});
test('each avatar clone keeps its own outfit dye uniforms',async()=>{
 const {Mesh,BoxGeometry,MeshStandardMaterial}=await import('three');
 const {applyDye,cloneItemMaterial}=await import('../src/item-colours.ts');
 const source=new Mesh(new BoxGeometry(),new MeshStandardMaterial());
 applyDye(source,'#28262a');
 const material=cloneItemMaterial(source.material);
 assert.notEqual(material.userData.slayDye,source.material.userData.slayDye);
 source.material.userData.slayDye.tint.value.set('#48879a');
 const shader={uniforms:{},fragmentShader:'#include <map_fragment>'};
 material.onBeforeCompile(shader,{});
 assert.equal(shader.uniforms.slayDyeTint.value.getHexString(),'28262a');
 assert.equal(shader.uniforms.slayDyeEnabled.value,1);
});
test('seated hips clear cushions and shins sit beyond the sofa front',async()=>{
 const {roomPlace,CUSHION_TOP}=await import('../src/huud-avatar.ts');
 for(const body of ['male','female']){
  const model=await loadGlb(readFileSync(new URL('../../app/assets/slay_renderer/assets/'+body+'.glb',import.meta.url)));
  const root=clone(model.scene),bones=seatPose(root,body);root.updateMatrixWorld(true);
  for(const side of ['Left','Right']){
   const hip=bones.get(side+'UpperLeg').getWorldPosition(new Vector3()),knee=bones.get(side+'LowerLeg').getWorldPosition(new Vector3()),foot=bones.get(side+'Foot').getWorldPosition(new Vector3());
   assert.ok(hip.y-CUSHION_TOP>=.085,'thigh centre clears cushion by its thickness');
   assert.ok(Math.abs(foot.y)<.04,'feet stay at floor level');
   for(let i=0;i<8;i++){
    const p=roomPlace(i),worldKnee=knee.clone().applyAxisAngle(new Vector3(0,1,0),p.yaw).add(new Vector3(p.x,0,p.z));
    const front=new Vector3(Math.sin(p.yaw),0,Math.cos(p.yaw));
    const sofaCentre=i<3?new Vector3(0,0,-1.95):i<6?new Vector3(-2.3,0,.08):new Vector3(2.3,0,0);
    assert.ok(worldKnee.sub(sofaCentre).dot(front)>.6,'shins are in front of cushion and base');
   }
  }
 }
});
test('entrance and exit use the doorway and keep a clear route around the table',async()=>{
 const {roomPlace,doorRoute,exitRoute,DOOR,WALK_RATE,TRANSIT_SPEED}=await import('../src/huud-avatar.ts');
 assert.ok(WALK_RATE>.8&&TRANSIT_SPEED>2,'walk and doorway transitions are faster');
 for(let i=0;i<12;i++){
  const place=roomPlace(i),path=doorRoute(place);
  assert.deepEqual(path[0].toArray(),DOOR.toArray());
  assert.deepEqual(path.at(-1).toArray(),[place.x,0,place.z]);
  const leaving=exitRoute(path.at(-1),place);
  assert.deepEqual(leaving.at(-1).toArray(),DOOR.toArray());
  for(let j=1;j<path.length;j++)for(let t=0;t<=1;t+=.05){
   const p=path[j-1].clone().lerp(path[j],t);
   assert.ok(Math.abs(p.x)>.8||Math.abs(p.z-.4)>.6,'route clears tabletop plus body width');
  }
 }
});
