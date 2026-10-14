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
