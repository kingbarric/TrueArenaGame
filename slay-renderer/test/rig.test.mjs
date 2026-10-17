import {test} from 'node:test';import assert from 'node:assert/strict';
import {Bone,Skeleton,SkinnedMesh,BufferGeometry,MeshBasicMaterial} from 'three';
import {bindGarment} from '../src/rig.ts';
test('garments use the avatar skeleton, preserving their original inverse bind matrices',()=>{
 const old=new Bone();old.name='Head';const mesh=new SkinnedMesh(new BufferGeometry(),new MeshBasicMaterial());mesh.bind(new Skeleton([old]));const inverse=mesh.skeleton.boneInverses[0].clone();const shared=new Bone();shared.name='Head';
 bindGarment(mesh,new Map([['Head',shared]]));assert.equal(mesh.skeleton.bones[0],shared);assert.deepEqual(mesh.skeleton.boneInverses[0].elements,inverse.elements);
});
test('incompatible clothing fails explicitly instead of silently floating off the avatar',()=>{
 const bone=new Bone();bone.name='MissingBone';const mesh=new SkinnedMesh(new BufferGeometry(),new MeshBasicMaterial());mesh.bind(new Skeleton([bone]));assert.throws(()=>bindGarment(mesh,new Map()),/Rig mismatch: MissingBone/);
});
