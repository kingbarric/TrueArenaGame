// Check every delivered model on each compatible avatar and every separates pair.
// These geometry/rig/mask checks complement visual review, not replace it.
import {readFileSync,writeFileSync} from 'node:fs';
import {AnimationMixer,Bone,Group,Vector3} from 'three';
import {loadGlb} from './glb-node.mjs';
import {VariantFit} from '../src/variant-fit.ts';
import {drapeBust,stabiliseTrouserSeam} from '../src/garment-drape.ts';
import {bindGarment} from '../src/rig.ts';
import {selectBodyFit,applyPose} from '../src/poses.ts';
import {coverBody} from '../src/coverage.ts';
import {catwalkClip} from '../src/showcase.ts';
import {fitMaleSeparates} from '../src/male-separates.ts';
const assets=new URL('../../app/assets/slay_renderer/assets/',import.meta.url),catalog=JSON.parse(readFileSync(new URL('../../backend/ta-api/src/main/resources/slay/catalog.json',import.meta.url)));
const report={avatars:[],failures:[],modelFits:0,clothingPairs:0,seamFits:0};
const load=async url=>loadGlb(readFileSync(new URL(url.split('/').pop(),assets)));
const seamsOnly=process.argv.includes('--seams-only');
for(const entry of catalog.avatars.filter(a=>!seamsOnly||a.body==='male')){
 const avatar=await load(entry.assetUrl??entry.body+'.glb'),root=new Group(),bones=new Map();root.add(avatar.scene);root.updateMatrixWorld(true);avatar.scene.traverse(o=>{if(o instanceof Bone)bones.set(o.name,o);});
 const mixer=new AnimationMixer(avatar.scene),walk=catwalkClip(avatar.scene),fit=entry.fitUrl?new VariantFit(JSON.parse(readFileSync(new URL(entry.fitUrl.split('/').pop(),assets)))):undefined;
 const available=catalog.items.filter(i=>i.assetUrl&&(i.body===entry.body||i.body==='unisex')),unique=[...new Map(available.filter(i=>!seamsOnly||['shirts','trousers'].includes(i.category)).map(i=>[i.assetUrl,i])).values()],garments=new Map(),stats={id:entry.id,models:0,pairs:0};
 for(const item of unique){
  const garment=await load(item.assetUrl);selectBodyFit(garment.scene,entry.body);fit?.apply(garment.scene);if(entry.body==='female'&&['dress','outfit','tops'].includes(item.category))drapeBust(garment.scene);if(item.category==='trousers')stabiliseTrouserSeam(garment.scene);bindGarment(garment.scene,bones);root.add(garment.scene);garments.set(item.assetUrl,garment.scene);
  const validate=label=>{root.updateMatrixWorld(true);garment.scene.traverse(mesh=>{if(!mesh.isSkinnedMesh||!mesh.visible)return;mesh.skeleton.update();const p=mesh.geometry.attributes.position,index=mesh.geometry.index;for(let i=0;i<(index?.count??p.count);i+=Math.max(1,Math.floor((index?.count??p.count)/120))){const v=index?index.getX(i):i,point=mesh.getVertexPosition(v,new Vector3());if(!point.toArray().every(Number.isFinite)||point.length()>3.2)throw Error(entry.id+'/'+item.id+'/'+label+': invalid geometry');}});};
  try{if(!seamsOnly){for(const pose of ['idle',...catalog.poses]){applyPose(mixer,avatar.animations,pose);mixer.update(.1);validate(pose);}mixer.stopAllAction();const action=mixer.clipAction(walk).reset().play();for(let f=0;f<=24;f++){mixer.update(walk.duration/24);validate('gait-'+f);}action.stop();}}catch(e){report.failures.push(e.message);}
  root.remove(garment.scene);stats.models++;report.modelFits++;if(stats.models%40===0)console.log(entry.id,stats.models+'/'+unique.length,'models checked');
 }
 const regions=[];avatar.scene.traverse(mesh=>{if(mesh.isMesh&&mesh.name.startsWith('region_'))regions.push(mesh);});const originalIndices=new Map(regions.map(mesh=>[mesh,Array.from(mesh.geometry.index.array)]));
 const tops=available.filter(i=>['tops','shirts'].includes(i.category)),bottoms=available.filter(i=>['skirts','trousers'].includes(i.category));
 if(!seamsOnly)for(const top of tops)for(const bottom of bottoms){coverBody(avatar.scene,[top,bottom].map(i=>catalog.wardrobePresentation?.[i.id]?.maskOf??i.id));for(const mesh of regions){const expected=new Set([top,bottom].flatMap(i=>mesh.userData.slayCoverage?.[catalog.wardrobePresentation?.[i.id]?.maskOf??i.id]??[]));if(mesh.geometry.index.count!==originalIndices.get(mesh).length-expected.size*3)throw Error(entry.id+'/'+top.id+'/'+bottom.id+': incorrect mask union');}stats.pairs++;report.clothingPairs++;}coverBody(avatar.scene,[]);for(const mesh of regions)if(mesh.geometry.index.count!==originalIndices.get(mesh).length)throw Error(entry.id+': skin failed to restore');
 if(entry.body==='male')for(const shirt of unique.filter(i=>i.category==='shirts'))for(const trousers of unique.filter(i=>i.category==='trousers')){try{fitMaleSeparates(garments.get(shirt.assetUrl),garments.get(trousers.assetUrl),shirt.id!=='male-tee-relaxed');report.seamFits++;}catch(e){report.failures.push(entry.id+'/'+shirt.id+'/'+trousers.id+': '+e.message);}}
 report.avatars.push(stats);console.log(entry.id,stats.models,'models;',stats.pairs,'clothing pairs');
}
writeFileSync(process.argv.slice(2).find(a=>!a.startsWith('--'))??(seamsOnly?'/tmp/slay-seam-fit-audit.json':'/tmp/slay-wardrobe-fit-audit.json'),JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify(report));if(report.failures.length)process.exitCode=1;
