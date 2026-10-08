import { Object3D,SkinnedMesh,Skeleton,Bone } from 'three';
export function bindGarment(garment:Object3D,bones:Map<string,Bone>){
 garment.traverse(object=>{if(object instanceof SkinnedMesh){
  const shared=object.skeleton.bones.map(b=>{const match=bones.get(b.name);if(!match)throw Error('Rig mismatch: '+b.name);return match;});
  object.bind(new Skeleton(shared,object.skeleton.boneInverses.map(m=>m.clone())),object.bindMatrix);
 }});
}
