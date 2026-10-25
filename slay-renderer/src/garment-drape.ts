import {BufferAttribute,Mesh,Object3D} from 'three';

/** Bridge the underside of a full bust with fabric instead of copying each
 * body indentation. Operates once in bind space; openings and back stay intact. */
export function drapeBust(root:Object3D){
 root.traverse(object=>{
  if(!(object instanceof Mesh))return;
  const p=object.geometry.attributes.position as BufferAttribute;
  let peakY=1.33,peakZ=-Infinity,waistZ=-Infinity;
  for(let i=0;i<p.count;i++){
   const x=Math.abs(p.getX(i)),y=p.getY(i),z=p.getZ(i);if(x>.17||z<.04)continue;
   if(y>1.29&&y<1.38&&z>peakZ){peakZ=z;peakY=y;}
   if(y>1.12&&y<1.19)waistZ=Math.max(waistZ,z);
  }
  if(!Number.isFinite(peakZ+waistZ))return;
  for(let i=0;i<p.count;i++){
   const x=Math.abs(p.getX(i)),y=p.getY(i),z=p.getZ(i);
   if(z<.04||x>.22||y<1.16||y>=peakY)continue;
   const t=(y-1.16)/(peakY-1.16),bridge=waistZ*(1-t)+peakZ*t;
   // A continuous transverse profile avoids bands at sample-column boundaries.
   const target=bridge-.07*(x/.22)**2;
   p.setZ(i,Math.max(z,Math.min(z+.008,target)));
  }
  p.needsUpdate=true;object.geometry.computeVertexNormals();object.geometry.computeBoundingBox();object.geometry.computeBoundingSphere();
 });
}

/** Weld the centre crotch to the pelvis instead of letting coincident seam
 * vertices follow opposite thighs during a stride. Fade back to leg weights. */
export function stabiliseTrouserSeam(root:Object3D){
 root.traverse(object=>{
  if(!(object instanceof Mesh)||!('skeleton' in object))return;
  const mesh=object as import('three').SkinnedMesh,hips=mesh.skeleton.bones.findIndex(b=>b.name==='Hips');
  if(hips<0)return;
  const p=mesh.geometry.attributes.position as BufferAttribute,j=mesh.geometry.attributes.skinIndex as BufferAttribute,w=mesh.geometry.attributes.skinWeight as BufferAttribute;
  for(let i=0;i<p.count;i++){
   const x=Math.abs(p.getX(i)),y=p.getY(i);if(x>=.035||y<.78||y>1.05)continue;
   const amount=Math.max(0,Math.min(1,(.035-x)/.029))*Math.min(1,(y-.78)/.05),weights=new Map<number,number>();
   for(let k=0;k<4;k++)weights.set(j.getComponent(i,k),(weights.get(j.getComponent(i,k))??0)+w.getComponent(i,k)*(1-amount));
   weights.set(hips,(weights.get(hips)??0)+amount);
   const entries=[...weights].sort((a,b)=>b[1]-a[1]).slice(0,4),total=entries.reduce((sum,e)=>sum+e[1],0);
   for(let k=0;k<4;k++){j.setComponent(i,k,entries[k]?.[0]??0);w.setComponent(i,k,(entries[k]?.[1]??0)/total);}
  }
  j.needsUpdate=true;w.needsUpdate=true;
 });
}

/** A floor-length skirt/train surrounds the shoes. Rendering them through
 * its cloth exposes the lack of cloth collision; keep the equipped shoes
 * concealed while the enclosing garment is worn. */
export function concealsFootwear(root:Object3D){
 let left=Infinity,right=-Infinity;
 root.traverse(object=>{
  if(!(object instanceof Mesh))return;
  const p=object.geometry.attributes.position as BufferAttribute;
  for(let i=0;i<p.count;i++)if(p.getY(i)<.06){left=Math.min(left,p.getX(i));right=Math.max(right,p.getX(i));}
 });
 return right-left>.55;
}
