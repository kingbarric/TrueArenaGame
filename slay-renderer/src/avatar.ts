import * as T from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { KTX2Loader } from 'three/addons/loaders/KTX2Loader.js';
import { MeshoptDecoder } from 'three/addons/libs/meshopt_decoder.module.js';
import type { Look,Item,Catalog } from './types';
import { bindGarment } from './rig';
import { assetBytes } from './cache';
import { presentBody, presentFace, presentEyes } from './presentation';
import { applyPose, selectBodyFit } from './poses';
import { coverBody } from './coverage';
import { Showcase } from './showcase';

const palette:Record<string,string>={gold:'#c39b55',navy:'#283d54',pink:'#c98491',red:'#a53541',purple:'#674269',green:'#397c65',black:'#28262a',white:'#eee5d6',blue:'#48879a',grey:'#8e8c87',orange:'#c5773d',yellow:'#ddba55'};
function material(colour:string){return new T.MeshStandardMaterial({color:colour,roughness:.72,metalness:.05});}
function mesh(geometry:T.BufferGeometry,mat:T.Material,x:number,y:number,z:number){const object=new T.Mesh(geometry,mat);object.position.set(x,y,z);object.castShadow=true;object.receiveShadow=true;return object;}
function mannequin(look:Look){
  const group=new T.Group(),skin=material(look.skinTone);group.name='development-mannequin';
  const torso=mesh(new T.CapsuleGeometry(.18,.40,8,16),skin,0,1.16,0);torso.name='region_torso';group.add(torso);
  const head=mesh(new T.SphereGeometry(.135,24,24),skin,0,1.72,0);head.scale.set(.83,1.18,.88);head.name='region_head';group.add(head);
  group.add(mesh(new T.CylinderGeometry(.05,.065,.12,16),skin,0,1.53,0));
  for(const sign of [-1,1]){
    const arm=mesh(new T.CapsuleGeometry(.048,.51,6,12),skin,sign*.265,1.13,0);arm.rotation.z=sign*.09;arm.name='region_arms';group.add(arm);
    const leg=mesh(new T.CapsuleGeometry(.065,.67,6,12),skin,sign*.09,.46,0);leg.name='region_legs';group.add(leg);
    group.add(mesh(new T.SphereGeometry(.052,12,12),skin,sign*.29,.80,0));
  }
  return group;
}
function placeholder(item:Item,body:string){
  const g=new T.Group(),mat=material(palette[item.colourTags[0]]??'#bda278');
  if(['outfit','dress','tops','shirts','traditional_outfits'].includes(item.category)){
    const jacket=mesh(new T.CylinderGeometry(.195,.19,.48,24),mat,0,1.17,0);jacket.scale.z=.63;g.add(jacket);
    if(item.category==='dress'||body==='female'){
      const skirt=mesh(new T.CylinderGeometry(.185,.33,.66,32),mat,0,.61,0);skirt.scale.z=.67;g.add(skirt);
      const belt=mesh(new T.TorusGeometry(.191,.012,8,32),material('#c7a461'),0,.92,0);belt.rotation.x=Math.PI/2;belt.scale.z=.65;g.add(belt);
    }else for(const s of [-1,1])g.add(mesh(new T.CylinderGeometry(.088,.069,.80,18),mat,s*.09,.49,0));
    if(item.id.includes('owambe')||item.id.includes('royal')||item.id.includes('ankara')){
      for(const y of [1.05,1.12,1.19,1.26]){const trim=mesh(new T.TorusGeometry(.198,.007,6,32),material('#e6c881'),0,y,0);trim.rotation.x=Math.PI/2;trim.scale.z=.64;g.add(trim);}
    }
  } else if(item.category==='shoes') for(const s of [-1,1]){const shoe=mesh(new T.SphereGeometry(.075,16,12),mat,s*.09,.065,.037);shoe.scale.set(.8,.7,1.55);g.add(shoe);}
  else if(item.category==='hair'){const hair=mesh(new T.SphereGeometry(.14,24,20),material('#1d1716'),0,1.80,-.018);hair.scale.set(.84,.7,.87);g.add(hair);if(item.id.endsWith('2')||item.id.endsWith('4'))for(const s of [-1,1])g.add(mesh(new T.CapsuleGeometry(.052,.19,6,12),material('#211916'),s*.12,1.66,-.06));}
  else if(item.category==='headwear'){const wrap=mesh(new T.SphereGeometry(.18,24,20),mat,0,1.87,-.035);wrap.scale.set(1.18,.7,.85);g.add(wrap);}
  else if(item.category==='jewellery')for(const s of [-1,1])g.add(mesh(new T.TorusGeometry(.025,.006,8,20),material('#e2bf73'),s*.123,1.65,.017));
  else if(item.category==='glasses')for(const s of [-1,1])g.add(mesh(new T.TorusGeometry(.035,.006,8,20),mat,s*.047,1.745,.106));
  else if(item.category==='bags'){const bag=mesh(new T.BoxGeometry(.17,.14,.07),mat,.31,.8,.055);bag.rotation.z=-.12;g.add(bag);}
  else if(item.category==='watches'||item.category==='accessories'){const ring=mesh(new T.TorusGeometry(.052,.012,8,24),mat,.285,.89,0);ring.rotation.x=Math.PI/2;g.add(ring);}
  return g;
}
export function dispose(root:T.Object3D){
  root.traverse(object=>{if(object instanceof T.Mesh){if(object instanceof T.SkinnedMesh)object.skeleton.dispose();object.geometry.dispose();const mats=Array.isArray(object.material)?object.material:[object.material];for(const mat of mats){for(const value of Object.values(mat))if(value instanceof T.Texture)value.dispose();mat.dispose();}}});
}
export class Wardrobe {
  root=new T.Group();private body?:T.Group;private bodyKey='';private equipped=new Map<string,{id:string,root:T.Group}>();
  private revision=0;private loader:GLTFLoader;private ktx:KTX2Loader;private mixer?:T.AnimationMixer;private clips:T.AnimationClip[]=[];
  private bones=new Map<string,T.Bone>();
  private assetVersion=0;private performance?:Showcase;private currentPose='signature';
  onShowcaseState:(playing:boolean,phase:string)=>void=()=>{};
  constructor(renderer:T.WebGLRenderer){this.ktx=new KTX2Loader().setTranscoderPath('basis/').detectSupport(renderer);this.loader=new GLTFLoader().setKTX2Loader(this.ktx).setMeshoptDecoder(MeshoptDecoder);}
  private async load(url:string){const address=new URL(url,location.href);if(address.protocol!=='https:' && address.origin!==location.origin)throw Error('Asset URL must be HTTPS or bundled');address.searchParams.set('catalogVersion',String(this.assetVersion));const bytes=await assetBytes(address.href);return this.loader.parseAsync(bytes,new URL('.',address).href);}
  async apply(look:Look,catalog:Catalog){
    this.stopShowcase('Show off cancelled: look changed');
    const version=++this.revision;
    this.assetVersion=catalog.version;
    const avatar=catalog.avatars.find(a=>a.body===look.body);if(!avatar)throw Error('Unknown avatar');
    if(this.bodyKey!==look.body+':'+avatar.assetUrl+':'+catalog.version){
      if(!avatar.assetUrl&&!catalog.developmentAssets)throw Error('Missing production avatar asset');
      const gltf=avatar.assetUrl?await this.load(avatar.assetUrl):null;
      const body=gltf?.scene??mannequin(look);if(version!==this.revision){dispose(body);return;}
      presentBody(body,look.skinTone,new Set());
      this.clear();this.body=body;this.bodyKey=look.body+':'+avatar.assetUrl+':'+catalog.version;this.root.add(body);
      this.clips=gltf?.animations??[];this.mixer=new T.AnimationMixer(body);this.bones.clear();
      body.traverse(o=>{if(o instanceof T.Bone)this.bones.set(o.name,o);});
    }
    const body=this.body!;
    const staged=new Map<string,{id:string,root:T.Group}>();
    try {
      for(const [slot,id] of Object.entries(look.items)){
        const item=catalog.items.find(i=>i.id===id);if(!item)throw Error('Unknown wardrobe item');
        if(this.equipped.get(slot)?.id===id)continue;
        if(!item.assetUrl&&!catalog.developmentAssets)throw Error('Missing production wardrobe asset: '+id);
        const garment=item.assetUrl?(await this.load(item.assetUrl)).scene:placeholder(item,look.body);
        if(version!==this.revision){dispose(garment);for(const e of staged.values())dispose(e.root);return;}
        staged.set(slot,{id,root:garment});
        if(item.assetUrl){
          selectBodyFit(garment,look.body);
          bindGarment(garment,this.bones);
          if(item.attachmentBone){const bone=this.bones.get(item.attachmentBone);if(!bone)throw Error('Missing attachment bone: '+item.attachmentBone);}
        }
      }
    }catch(error){for(const e of staged.values())dispose(e.root);throw error;}
    if(version!==this.revision){for(const e of staged.values())dispose(e.root);return;}
    for(const [slot,e] of this.equipped){if(look.items[slot]!==e.id){e.root.removeFromParent();dispose(e.root);this.equipped.delete(slot);}}
    for(const [slot,e] of staged){const item=catalog.items.find(i=>i.id===e.id)!;const parent=item.attachmentBone?this.bones.get(item.attachmentBone):this.root;(parent??this.root).add(e.root);this.equipped.set(slot,e);}
    const hidden=new Set(Object.values(look.items).flatMap(id=>catalog.items.find(i=>i.id===id)!.hidesRegions));
    coverBody(body,Object.values(look.items));
    presentBody(body,look.skinTone,hidden);
    // Eye choices replace the baked brown-eye mesh; do not stack two sets.
    presentEyes(body,!!look.items.eyes);
    presentFace(this.root,look.facePreset,look.pose);
    this.pose(look.pose);
  }
  showOff(){
    if(!this.body||!this.mixer)throw Error('Wait for your avatar to load');
    this.performance??=new Showcase(this.root,this.body,this.mixer,this.clips,(playing,phase)=>this.onShowcaseState(playing,phase));
    return this.performance.play(this.currentPose==='signature'?'confident':this.currentPose).then(pose=>{this.pose(pose);return pose;});
  }
  get showingOff(){return this.performance?.playing??false;}
  stopShowcase(reason?:string){this.performance?.stop(reason);}
  pose(id:string){
    this.stopShowcase();this.currentPose=id;
    this.root.traverse(o=>{if(o instanceof T.Mesh&&o.morphTargetDictionary&&o.morphTargetInfluences){for(const [name,index] of Object.entries(o.morphTargetDictionary))if(name.startsWith('expression_'))o.morphTargetInfluences[index]=name==='expression_smile'&&['confident','celebrate'].includes(id)?1:0;}});
    if(this.mixer && this.clips.length) applyPose(this.mixer,this.clips,id);
    this.root.updateMatrixWorld(true);
  }
  update(seconds:number){if(this.performance?.playing)this.performance.update(seconds);else this.mixer?.update(seconds);}
  clear(){this.stopShowcase('Show off cancelled: stage closed');this.performance=undefined;this.mixer?.stopAllAction();if(this.body)this.mixer?.uncacheRoot(this.body);this.body?.removeFromParent();if(this.body)dispose(this.body);for(const item of this.equipped.values()){item.root.removeFromParent();dispose(item.root);}this.equipped.clear();this.bodyKey='';}
  destroy(){this.revision++;this.clear();this.ktx.dispose();}
}
