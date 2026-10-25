// Preserve the preset's skin detail while retaining the game's colour picker.
import {readFileSync,writeFileSync} from 'node:fs';
import {NodeIO} from '@gltf-transform/core';
import sharp from 'sharp';
import {prune} from '@gltf-transform/functions';

const root=new URL('../../',import.meta.url),io=new NodeIO();
const cataloguePath=new URL('backend/ta-api/src/main/resources/slay/catalog.json',root);
const catalogue=JSON.parse(readFileSync(cataloguePath));
const sources={
 ella:'slay-renderer/source_assets/makehuman/indian_skin3e.png',
 beverly:'slay-renderer/source_assets/makehuman/starter/skins/young_caucasian_female2/young_lightskinned_female_diffuse2.png',
 girl02:'slay-renderer/source_assets/makehuman/starter/skins/young_caucasian_female/young_lightskinned_female_diffuse.png',
};
for(const [id,source] of Object.entries(sources)){
 const path=new URL('app/assets/slay_renderer/assets/avatar-'+id+'.glb',root);
 const document=await io.readBinary(new Uint8Array(readFileSync(path)));
 const png=await sharp(readFileSync(new URL(source,root))).resize({width:1024,height:1024,fit:'inside',withoutEnlargement:true}).png().toBuffer();
 const {data,info}=await sharp(png).removeAlpha().raw().toBuffer({resolveWithObject:true});
 const channels=[[],[],[]],materials=new Set();
 for(const node of document.getRoot().listNodes()){
  if(!node.getName().startsWith('region_'))continue;
  for(const primitive of node.getMesh().listPrimitives()){
   materials.add(primitive.getMaterial());
   if(node.getName()!=='region_torso')continue;
   const uv=primitive.getAttribute('TEXCOORD_0');
   for(let i=0;i<uv.getCount();i++){
    const [u,v]=uv.getElement(i,[]),x=Math.max(0,Math.min(info.width-1,Math.round(u*(info.width-1)))),y=Math.max(0,Math.min(info.height-1,Math.round(v*(info.height-1))));
    const offset=(y*info.width+x)*info.channels;
    if(data[offset]<30)continue;
    for(let channel=0;channel<3;channel++)channels[channel].push(data[offset+channel]);
   }
  }
 }
 const reference='#'+channels.map(values=>{if(!values.length)throw Error('Missing skin samples');values.sort((a,b)=>a-b);return values[values.length>>1].toString(16).padStart(2,'0');}).join('');
 const texture=document.createTexture(id+'-preset-skin').setMimeType('image/png').setImage(png);
 for(const material of materials)material.setBaseColorTexture(texture).setExtras({...material.getExtras(),slaySkinBase:reference});
 const entry=catalogue.avatars.find(avatar=>avatar.id===id);entry.naturalSkinTone=reference;
 if(!catalogue.skinTones.includes(reference))catalogue.skinTones.push(reference);
 await document.transform(prune({keepAttributes:true,keepIndices:true,keepLeaves:true,keepSolidTextures:true}));
 writeFileSync(path,await io.writeBinary(document));
 console.log(id,reference);
}
writeFileSync(cataloguePath,JSON.stringify(catalogue,null,2)+'\n');
