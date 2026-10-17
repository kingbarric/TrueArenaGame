// Supplement incomplete author masks with faces enclosed by the real garment.
import {readFileSync} from 'node:fs';
import {NodeIO} from '@gltf-transform/core';
import {Ray,Vector3} from 'three';
import {loadGlb} from './glb-node.mjs';
const assets=new URL('../../app/assets/slay_renderer/assets/',import.meta.url),io=new NodeIO();
const catalog=JSON.parse(readFileSync(new URL('../../backend/ta-api/src/main/resources/slay/catalog.json',import.meta.url)));
const categories=new Set(['dress','outfit','tops','shirts','trousers','skirts']);
for(const body of ['female','male']){
 const base=await io.read(new URL(body+'.glb',assets).pathname),regions=base.getRoot().listNodes().filter(n=>n.getName().startsWith('region_'));
 const masks=new Map(regions.map(n=>[n.getName(),{...n.getExtras().slayCoverage}])),grouped=new Map();
 for(const item of catalog.items.filter(i=>i.body===body&&i.assetUrl&&categories.has(i.category))){if(!grouped.has(item.assetUrl))grouped.set(item.assetUrl,[]);grouped.get(item.assetUrl).push(item);}
 for(const [url,items] of grouped){
  const garment=await loadGlb(readFileSync(new URL(url.split('/').pop(),assets))),bins=new Map();
  garment.scene.updateMatrixWorld(true);let bottom=Infinity,top=-Infinity;
  garment.scene.traverse(mesh=>{if(!mesh.isMesh)return;const p=mesh.geometry.attributes.position,index=mesh.geometry.index;
   for(let i=0;i<index.count;i+=3){const tri=[0,1,2].map(k=>new Vector3().fromBufferAttribute(p,index.getX(i+k)).applyMatrix4(mesh.matrixWorld));const low=Math.min(...tri.map(v=>v.y)),high=Math.max(...tri.map(v=>v.y));bottom=Math.min(bottom,low);top=Math.max(top,high);
    for(let bin=Math.floor(low*200);bin<=Math.floor(high*200);bin++){if(!bins.has(bin))bins.set(bin,[]);bins.get(bin).push(tri);}
   }
  });
  const ray=new Ray(),hit=new Vector3(),direction=new Vector3();
  const enclosed=p=>{
   const candidates=bins.get(Math.floor(p.y*200));if(!candidates)return false;
   const axis=p.y<1.02?(p.x<0?-.09:.09):0,origin=new Vector3(axis,p.y,.015);direction.copy(p).sub(origin);direction.y=0;const radius=direction.length();if(radius<.005)return false;direction.normalize();ray.set(origin,direction);
   return candidates.some(tri=>{if(!ray.intersectTriangle(...tri,false,hit))return false;const distance=hit.distanceTo(origin);return distance>=radius-.012&&distance<radius+.30;});
  };
  let added=0;
  for(const node of regions){
   if(['region_head','region_feet'].includes(node.getName()))continue;
   const primitive=node.getMesh().listPrimitives()[0],p=primitive.getAttribute('POSITION'),index=primitive.getIndices(),extra=[];
   for(let i=0;i<index.getCount();i+=3){const points=[0,1,2].map(k=>new Vector3().fromArray(p.getElement(index.getScalar(i+k),[])));if(points.some(v=>v.y<bottom+.008||v.y>top-.008))continue;if(items.every(i=>['trousers','skirts'].includes(i.category))&&points.some(v=>v.y>(body==='male'?1.10:1.02)))continue;if(points.every(enclosed))extra.push(i/3);}
   for(const item of items){const key=catalog.wardrobePresentation?.[item.id]?.maskOf??item.id,before=masks.get(node.getName())[key]??[],merged=[...new Set([...before,...extra])].sort((a,b)=>a-b);added+=merged.length-before.length;masks.get(node.getName())[key]=merged;}
  }
  console.log(body,items[0].id,'additional covered triangles',added);
 }
 for(const avatar of catalog.avatars.filter(a=>a.body===body)){
  const path=new URL((avatar.assetUrl??'assets/'+body+'.glb').split('/').pop(),assets).pathname,doc=await io.read(path);
  for(const node of doc.getRoot().listNodes())if(masks.has(node.getName()))node.setExtras({...node.getExtras(),slayCoverage:masks.get(node.getName())});await io.write(path,doc);
 }
}
