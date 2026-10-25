import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {Bone,Group,Vector3} from 'three';
import {clone} from 'three/addons/utils/SkeletonUtils.js';
import {loadGlb} from '../scripts/glb-node.mjs';
import {restoreBindSpace,bindGarment} from '../src/rig.ts';
import {VariantFit} from '../src/variant-fit.ts';
import {drapeBust,stabiliseTrouserSeam} from '../src/garment-drape.ts';
import {fitMaleSeparates,fitFemaleSeparates} from '../src/male-separates.ts';
import {seatPose,animateBody} from '../src/huud-avatar.ts';
const root=new URL('../../',import.meta.url),catalog=JSON.parse(readFileSync(new URL('app/assets/slay_renderer/catalog.json',root))),options=JSON.parse(readFileSync(new URL('backend/ta-api/src/main/resources/slay/huud-avatars.json',root)));
const cache=new Map();
async function model(path){let promise=cache.get(path);if(!promise){promise=loadGlb(readFileSync(new URL('website/slay-assets/'+catalog.assets.files[path].name,root))).then(g=>{restoreBindSpace(g.scene);return g.scene;});cache.set(path,promise);}const scene=clone(await promise);scene.traverse(o=>{if(o.isMesh)o.geometry=o.geometry.clone();});return scene;}
test('all 50 profile outfits bind and remain finite when sitting, standing and walking',async()=>{
 for(const avatar of options.avatars){
  const source=catalog.avatars.find(a=>a.id===avatar.id),fit=source.fitUrl?new VariantFit(JSON.parse(readFileSync(new URL('app/assets/slay_renderer/'+source.fitUrl,root)))):null;
  for(const outfit of options.outfits){
   const slots=avatar.body==='female'?outfit.female:outfit.male;
   const [body,top,pants]=await Promise.all([model(source.assetUrl),model(catalog.items.find(i=>i.id===(slots.tops??slots.shirts)).assetUrl),model(catalog.items.find(i=>i.id===slots.trousers).assetUrl)]);
   if(fit){fit.apply(top);fit.apply(pants);}drapeBust(top);stabiliseTrouserSeam(pants);if(avatar.body==='female')fitFemaleSeparates(top,pants);else fitMaleSeparates(top,pants,slots.shirts.includes('tucked'));
   const group=new Group(),bones=new Map();group.add(body,top,pants);body.traverse(o=>{if(o instanceof Bone)bones.set(o.name,o);});bindGarment(top,bones);bindGarment(pants,bones);const seatedBones=seatPose(group,avatar.body);
   const check=(seated,walking,time)=>{animateBody(group,seatedBones,avatar.body,seated,walking,time);group.updateMatrixWorld(true);let checked=0;group.traverse(o=>{if(!o.isSkinnedMesh||!o.visible)return;o.skeleton.update();const p=o.geometry.attributes.position;for(let i=0;i<p.count;i+=193){const v=new Vector3().fromBufferAttribute(p,i);o.applyBoneTransform(i,v);assert.ok([v.x,v.y,v.z].every(Number.isFinite),avatar.id+'/'+outfit.id);assert.ok(v.length()<3,avatar.id+'/'+outfit.id+' binding must stay in metres');checked++;}});assert.ok(checked>10);};
   check(1,false,0);check(0,false,0);for(const time of [.2,.6,1])check(0,true,time);
   group.traverse(o=>{if(o.isMesh)o.geometry.dispose();if(o.isSkinnedMesh)o.skeleton.dispose();});
  }
 }
});
