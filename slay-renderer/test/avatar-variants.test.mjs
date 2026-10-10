import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {AnimationMixer,Bone,Group,Mesh,PerspectiveCamera,Raycaster,Vector3} from 'three';
import {GLTFLoader} from 'three/addons/loaders/GLTFLoader.js';
import {VariantFit} from '../src/variant-fit.ts';
import {StudioBackdrop} from '../src/studio.ts';
import {bindGarment} from '../src/rig.ts';
import {applyPose} from '../src/poses.ts';
import {presentEyes} from '../src/presentation.ts';
const assets=new URL('../../app/assets/slay_renderer/assets/',import.meta.url);
const catalog=JSON.parse(readFileSync(new URL('../../backend/ta-api/src/main/resources/slay/catalog.json',import.meta.url)));
async function load(id){
 const bytes=readFileSync(new URL(id+'.glb',assets)),n=bytes.readUInt32LE(12),doc=JSON.parse(bytes.subarray(20,20+n)),bin=bytes.subarray(28+n);
 doc.materials=doc.materials.map(()=>({pbrMetallicRoughness:{}}));delete doc.images;delete doc.textures;doc.buffers[0].uri='data:application/octet-stream;base64,'+bin.toString('base64');globalThis.ProgressEvent??=class ProgressEvent{};
 return new GLTFLoader().parseAsync(JSON.stringify(doc),'');
}
test('new characters change body shape, preserve masks and accept the wardrobe through every finish',async()=>{
 for(const avatar of catalog.avatars.filter(a=>a.fitUrl)){
  const base=await load(avatar.body),variant=await load('avatar-'+avatar.id),fit=new VariantFit(JSON.parse(readFileSync(new URL(avatar.fitUrl.split('/').pop(),assets))));let changed=0;
  variant.scene.traverse(o=>{if(o instanceof Mesh && o.name.startsWith('region_')){const ref=base.scene.getObjectByName(o.name),p=o.geometry.attributes.position,q=ref.geometry.attributes.position;assert.equal(p.count,q.count);assert.deepEqual(o.userData.slayCoverage,ref.userData.slayCoverage);for(let i=0;i<p.count;i+=19){const a=new Vector3().fromBufferAttribute(p,i),b=new Vector3().fromBufferAttribute(q,i);assert.ok(Number.isFinite(a.length()));if(a.distanceTo(b)>.002)changed++;}}});assert.ok(changed>25,avatar.id+': distinct shape');
  const bones=new Map();variant.scene.traverse(o=>{if(o instanceof Bone)bones.set(o.name,o);});const root=new Group();root.add(variant.scene);
  for(const id of [avatar.body+'-essential',avatar.body+'-hair-0',avatar.body+'-eyes-blue']){const item=await load(id);fit.apply(item.scene);bindGarment(item.scene,bones);root.add(item.scene);}
  const mixer=new AnimationMixer(variant.scene);for(const pose of catalog.poses){applyPose(mixer,variant.animations,pose);root.updateMatrixWorld(true);root.traverse(o=>{if(!o.isSkinnedMesh)return;o.skeleton.update();assert.ok(o.skeleton.bones.every(b=>bones.get(b.name)===b));for(let i=0;i<o.geometry.attributes.position.count;i+=137)assert.ok(Number.isFinite(o.getVertexPosition(i,new Vector3()).length()),avatar.id+'/'+pose);});}
 }
});
test('male colour choices expose eye geometry in front of the sockets and replace the base eyes',async()=>{
 const body=await load('male');presentEyes(body.scene,true);
 for(const colour of ['hazel','green','blue']){const eye=await load('male-eyes-'+colour),root=new Group();root.add(body.scene,eye.scene);root.updateMatrixWorld(true);const meshes=[];root.traverse(o=>{if(o.isSkinnedMesh){o.skeleton.update();if(o.visible&&(o.name==='region_head'||o.name==='male-eyes-'+colour))meshes.push(o);}});const ray=new Raycaster();let visible=0;
  for(let x=.023;x<.060;x+=.003)for(let y=1.824;y<1.855;y+=.003){ray.set(new Vector3(x,y,1),new Vector3(0,0,-1));if(ray.intersectObjects(meshes,false)[0]?.object.name==='male-eyes-'+colour)visible++;}assert.ok(visible>5,colour+': hidden by head');root.remove(eye.scene);
 }presentEyes(body.scene,false);assert.equal(body.scene.getObjectByName('face_eyes').visible,true);
});
test('studio props stay behind the model through a full rotation, with a modest mesh budget',()=>{
 const studio=new StudioBackdrop(),camera=new PerspectiveCamera();let triangles=0;studio.root.traverse(o=>{if(o instanceof Mesh)triangles+=(o.geometry.index?.count??o.geometry.attributes.position.count)/3;});assert.ok(triangles<6000);
 for(let angle=0;angle<Math.PI*2;angle+=Math.PI/4){camera.position.set(Math.sin(angle)*3.5,1,Math.cos(angle)*3.5);studio.update(camera,'studio');studio.root.updateMatrixWorld(true);const view=new Vector3(Math.sin(angle),0,Math.cos(angle));studio.root.traverse(o=>{if(!(o instanceof Mesh))return;const p=o.geometry.attributes.position;for(let i=0;i<p.count;i+=7){const world=o.localToWorld(new Vector3().fromBufferAttribute(p,i));assert.ok(world.dot(view)<-3,'prop in styling area');}});}
 studio.update(camera,'runway');assert.equal(studio.root.visible,false);studio.dispose();
});
test('fingertips follow arms in hip and cover poses rather than stretching towards the legs',async()=>{
 for(const body of ['female','male','avatar-girl02','avatar-indian-male']){const avatar=await load(body),mixer=new AnimationMixer(avatar.scene);let samples=0;
  avatar.scene.traverse(o=>{if(!o.isSkinnedMesh||!o.name.startsWith('region_'))return;const p=o.geometry.attributes.position,j=o.geometry.attributes.skinIndex,w=o.geometry.attributes.skinWeight;
   for(let i=0;i<p.count;i++){if(Math.abs(p.getX(i))<.50||p.getY(i)<.70||p.getY(i)>1.25)continue;for(let k=0;k<4;k++)if(w.getComponent(i,k)>.001)assert.ok(!/Leg|Foot/.test(o.skeleton.bones[j.getComponent(i,k)].name),body+': fingertip bound to leg');samples++;}
  });assert.ok(samples>20);
  for(const pose of ['confident','editorial']){applyPose(mixer,avatar.animations,pose);avatar.scene.updateMatrixWorld(true);avatar.scene.traverse(o=>{if(!o.isSkinnedMesh)return;o.skeleton.update();
    const p=o.geometry.attributes.position,indices=o.geometry.index;
    if(!o.name.startsWith('region_')||!indices)return;
    for(let i=0;i<indices.count;i+=3){const ids=[0,1,2].map(j=>indices.getX(i+j));
     if(!ids.every(j=>Math.abs(p.getX(j))>.49 && p.getY(j)>.70 && p.getY(j)<1.25))continue;
     const rest=ids.map(j=>new Vector3().fromBufferAttribute(p,j)),posed=ids.map(j=>o.getVertexPosition(j,new Vector3()));
     for(let j=0;j<3;j++){const a=rest[j].distanceTo(rest[(j+1)%3]),b=posed[j].distanceTo(posed[(j+1)%3]);
      if(a>.001)assert.ok(Math.abs(b/a-1)<.002,body+'/'+pose+': palm/finger edge stretched '+(b/a));}
    }
   });}
 }
});
