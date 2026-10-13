// Fit modest preview underwear to each finished MakeHuman body, including
// interpolated skin weights at its boundaries. The body/masks stay unchanged.
import {readFileSync,writeFileSync} from 'node:fs';
import {NodeIO} from '@gltf-transform/core';
import {prune} from '@gltf-transform/functions';
const io=new NodeIO(),assets=new URL('../../app/assets/slay_renderer/assets/',import.meta.url);
const mix=(a,b,t)=>{
 const influences=new Map();
 for(const [joint,weight] of a.influences)influences.set(joint,weight*(1-t));
 for(const [joint,weight] of b.influences)influences.set(joint,(influences.get(joint)??0)+weight*t);
 return {p:a.p.map((v,i)=>v+(b.p[i]-v)*t),n:a.n.map((v,i)=>v+(b.n[i]-v)*t),influences};
};
const clip=(polygon,plane)=>{
 const result=[];
 for(let i=0;i<polygon.length;i++){
  const a=polygon[i],b=polygon[(i+1)%polygon.length],da=plane(a),db=plane(b);
  if(da>=0)result.push(a);
  if((da>=0)!==(db>=0))result.push(mix(a,b,da/(da-db)));
 }
 return result;
};
for(const id of process.argv.slice(2)){
 const path=new URL('avatar-'+id+'.glb',assets),document=await io.readBinary(new Uint8Array(readFileSync(path)));
 const buffer=document.getRoot().listBuffers()[0],surfaces=document.getRoot().listNodes().filter(node=>['region_torso','region_upper_legs'].includes(node.getName()));
 for(const [name,low,high] of [['starter_bra',1.21,1.415],['starter_briefs',.80,1.02]]){
  const node=document.getRoot().listNodes().find(node=>node.getName()===name),material=node.getMesh().listPrimitives()[0].getMaterial();
  const armJoints=new Set(node.getSkin().listJoints().map((joint,index)=>/Arm|Hand/.test(joint.getName())?index:-1).filter(index=>index>=0));
  const arrays={POSITION:[],NORMAL:[],JOINTS_0:[],WEIGHTS_0:[]},indices=[];
  for(const surface of surfaces)for(const primitive of surface.getMesh().listPrimitives()){
   const position=primitive.getAttribute('POSITION'),normal=primitive.getAttribute('NORMAL'),joints=primitive.getAttribute('JOINTS_0'),weights=primitive.getAttribute('WEIGHTS_0'),index=primitive.getIndices();
   for(let i=0;i<index.getCount();i+=3){
    const original=[0,1,2].map(j=>{
     const vertex=index.getScalar(i+j),joint=joints.getElement(vertex,[]),weight=weights.getElement(vertex,[]),influences=new Map();
     joint.forEach((bone,k)=>{if(weight[k]>0)influences.set(bone,(influences.get(bone)??0)+weight[k]);});
     return {p:position.getElement(vertex,[]),n:normal.getElement(vertex,[]),influences};
    });
    const ellaBra=id==='ella'&&name==='starter_bra';
    for(const piece of ellaBra?['cups']:['band']){
    let polygon=original;
    if(ellaBra&&piece==='cups'){
     // Rounded front cups and a narrower support band behind the torso.
     const top=v=>v.p[2]>.035?1.35+.07*Math.max(0,1-((Math.abs(v.p[0])-.105)/.09)**2):1.335;
     polygon=clip(clip(polygon,v=>v.p[1]-1.22),v=>top(v)-v.p[1]);
    }else polygon=clip(clip(polygon,vertex=>vertex.p[1]-low),vertex=>high-vertex.p[1]);
    if(name==='starter_bra')polygon=clip(polygon,vertex=>.03-[...vertex.influences].reduce((sum,[joint,weight])=>sum+(armJoints.has(joint)?weight:0),0));
    for(let j=1;j<polygon.length-1;j++)for(const vertex of [polygon[0],polygon[j],polygon[j+1]]){
     const length=Math.hypot(...vertex.n)||1,n=vertex.n.map(v=>v/length),influences=[...vertex.influences].sort((a,b)=>b[1]-a[1]).slice(0,4),total=influences.reduce((sum,pair)=>sum+pair[1],0);
     arrays.POSITION.push(...vertex.p.map((v,k)=>v+n[k]*.006));arrays.NORMAL.push(...n);
     for(let k=0;k<4;k++){arrays.JOINTS_0.push(influences[k]?.[0]??0);arrays.WEIGHTS_0.push((influences[k]?.[1]??0)/total);}
     indices.push(indices.length);
    }
    }
   }
  }
  const primitive=document.createPrimitive().setMaterial(material),mesh=document.createMesh(name).addPrimitive(primitive);
  for(const [attribute,array] of Object.entries(arrays))primitive.setAttribute(attribute,document.createAccessor().setType(attribute==='POSITION'||attribute==='NORMAL'?'VEC3':'VEC4').setArray(attribute==='JOINTS_0'?new Uint16Array(array):new Float32Array(array)).setBuffer(buffer));
  primitive.setIndices(document.createAccessor().setType('SCALAR').setArray(new Uint32Array(indices)).setBuffer(buffer));
  node.setMesh(mesh).setExtras({...node.getExtras(),slayUnderwear:name==='starter_bra'?'bra':'briefs'});
 }
 await document.transform(prune({keepAttributes:true,keepIndices:true,keepLeaves:true,keepSolidTextures:true}));
 writeFileSync(path,await io.writeBinary(document));console.log(id,'fitted underwear');
}
