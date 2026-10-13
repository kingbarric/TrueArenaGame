import { Object3D,SkinnedMesh,Skeleton,Bone,BufferAttribute,Float32BufferAttribute,Matrix3,Matrix4,Vector3 } from 'three';

/** Meshopt quantization stores the decode transform in inverse bind matrices.
 * Restore metre-space vertices before spatial fitting/draping edits them. */
export function restoreBindSpace(root:Object3D){
 root.updateMatrixWorld(true);
 root.traverse(object=>{if(!(object instanceof SkinnedMesh)||!object.skeleton.bones.length)return;
  const decode=object.skeleton.bones[0].matrixWorld.clone().multiply(object.skeleton.boneInverses[0]);
  if(decode.elements.every((v,i)=>Math.abs(v-new Matrix4().elements[i])<1e-6))return;
  // This conversion applies only to a common decode transform, not an authored pose.
  if(!object.skeleton.bones.every((b,i)=>b.matrixWorld.clone().multiply(object.skeleton.boneInverses[i]).elements.every((v,k)=>Math.abs(v-decode.elements[k])<1e-5)))throw Error('Inconsistent garment bind space');
  const geometry=object.geometry,normalMatrix=new Matrix3().getNormalMatrix(decode),linear=new Matrix3().setFromMatrix4(decode);
  for(const name of ['position','normal']){const a=geometry.getAttribute(name);if(!a)continue;const values=[];for(let i=0;i<a.count;i++){const p=new Vector3().fromBufferAttribute(a,i);if(name==='position')p.applyMatrix4(decode);else p.applyMatrix3(normalMatrix).normalize();values.push(...p.toArray());}geometry.setAttribute(name,new Float32BufferAttribute(values,3));}
  for(const name of ['position','normal']){const list=geometry.morphAttributes[name];if(!list)continue;geometry.morphAttributes[name]=list.map((a:BufferAttribute)=>{const values=[];for(let i=0;i<a.count;i++){const p=new Vector3().fromBufferAttribute(a,i);if(name==='position'){if(geometry.morphTargetsRelative)p.applyMatrix3(linear);else p.applyMatrix4(decode);}else p.applyMatrix3(normalMatrix);values.push(...p.toArray());}return new Float32BufferAttribute(values,3);});}
  const inverse=decode.clone().invert();object.skeleton.boneInverses=object.skeleton.boneInverses.map(m=>m.clone().multiply(inverse));object.skeleton.update();
  geometry.computeBoundingBox();geometry.computeBoundingSphere();
 });
}
export function bindGarment(garment:Object3D,bones:Map<string,Bone>){
 garment.traverse(object=>{if(object instanceof SkinnedMesh){
  const shared=object.skeleton.bones.map(b=>{const match=bones.get(b.name);if(!match)throw Error('Rig mismatch: '+b.name);return match;});
  object.bind(new Skeleton(shared,object.skeleton.boneInverses.map(m=>m.clone())),object.bindMatrix);
 }});
}
