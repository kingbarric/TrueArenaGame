import {NodeIO} from '@gltf-transform/core';
import {prune,weld} from '@gltf-transform/functions';
const io=new NodeIO(),root=new URL('../../app/assets/slay_renderer/assets/',import.meta.url),hem=.73;
const path=new URL('female-s0-hoodie-dress.glb',root).pathname,doc=await io.read(path);
for(const mesh of doc.getRoot().listMeshes())for(const primitive of mesh.listPrimitives()){
 const attrs=Object.fromEntries(primitive.listSemantics().map(s=>[s,primitive.getAttribute(s)])),index=primitive.getIndices(),arrays=Object.fromEntries(Object.keys(attrs).map(s=>[s,[]]));
 const vertex=i=>Object.fromEntries(Object.entries(attrs).map(([s,a])=>[s,a.getElement(i,[])]));
 const interpolate=(a,b,t)=>{const v=Object.fromEntries(Object.keys(attrs).map(s=>[s,a[s].map((x,k)=>x+(b[s][k]-x)*t)]));if(a.JOINTS_0){const weights=new Map();for(const [x,f] of [[a,1-t],[b,t]])x.JOINTS_0.forEach((j,k)=>weights.set(j,(weights.get(j)??0)+x.WEIGHTS_0[k]*f));const list=[...weights].sort((a,b)=>b[1]-a[1]).slice(0,4),total=list.reduce((n,e)=>n+e[1],0);v.JOINTS_0=[0,1,2,3].map(k=>list[k]?.[0]??0);v.WEIGHTS_0=[0,1,2,3].map(k=>(list[k]?.[1]??0)/total);}return v;};
 for(let i=0;i<index.getCount();i+=3){const input=[0,1,2].map(k=>vertex(index.getScalar(i+k))),polygon=[];for(let k=0;k<3;k++){const a=input[k],b=input[(k+1)%3],da=a.POSITION[1]-hem,db=b.POSITION[1]-hem;if(da>=0)polygon.push(a);if((da>=0)!==(db>=0))polygon.push(interpolate(a,b,da/(da-db)));}for(let k=1;k<polygon.length-1;k++)for(const v of [polygon[0],polygon[k],polygon[k+1]])for(const s of Object.keys(attrs))arrays[s].push(...v[s]);}
 for(const [s,a] of Object.entries(attrs))primitive.setAttribute(s,doc.createAccessor().setType(a.getType()).setArray(new (a.getArray().constructor)(arrays[s])).setBuffer(a.getBuffer()));
 primitive.setIndices(doc.createAccessor().setType('SCALAR').setArray(new Uint32Array(Array.from({length:arrays.POSITION.length/3},(_,i)=>i))).setBuffer(doc.getRoot().listBuffers()[0]));
}
await doc.transform(weld(),prune({keepAttributes:true,keepIndices:true,keepLeaves:true,keepSolidTextures:true}));
await io.write(path,doc);
for(const file of ['female','avatar-girl02','avatar-ella','avatar-beverly']){const path=new URL(file+'.glb',root).pathname,d=await io.read(path);for(const n of d.getRoot().listNodes()){const masks=n.getExtras().slayCoverage;if(!masks)continue;const p=n.getMesh().listPrimitives()[0],position=p.getAttribute('POSITION'),indices=p.getIndices();for(const key of Object.keys(masks))if(key.includes('hoodie-dress'))masks[key]=masks[key].filter(t=>[0,1,2].every(k=>position.getElement(indices.getScalar(t*3+k),[])[1]>=hem-.002));n.setExtras({...n.getExtras(),slayCoverage:masks});}await io.write(path,d);}
// The variants share the base body's indexed mask topology.
const base=await io.read(new URL('female.glb',root).pathname),masks=new Map(base.getRoot().listNodes().map(n=>[n.getName(),n.getExtras().slayCoverage]));
for(const file of ['avatar-girl02','avatar-ella','avatar-beverly']){const path=new URL(file+'.glb',root).pathname,d=await io.read(path);for(const n of d.getRoot().listNodes()){const own=n.getExtras().slayCoverage,source=masks.get(n.getName());if(!own||!source)continue;for(const key of Object.keys(source))if(key.includes('hoodie-dress'))own[key]=source[key];n.setExtras({...n.getExtras(),slayCoverage:own});}await io.write(path,d);}
