import {readFileSync,existsSync} from 'node:fs';
import {resolve,basename} from 'node:path';
// Validate the delivery folder before assigning URLs in the catalog.
const root=process.argv[2];
if(!root) {console.error('Usage: node scripts/validate-assets.mjs /path/to/delivery');process.exit(1);}
const catalog=JSON.parse(readFileSync(new URL('../../backend/ta-api/src/main/resources/slay/catalog.json',import.meta.url),'utf8'));
let missing=0,invalid=0;
const rigs=new Map();
function inspect(path) {
 const bytes=readFileSync(path);
 if(bytes.byteLength>32*1024*1024) throw Error('exceeds the renderer asset limit');
 if(bytes.toString('ascii',0,4)!=='glTF'||bytes.readUInt32LE(4)!==2||bytes.readUInt32LE(8)!==bytes.length)throw Error('invalid GLB 2 header');
 if(bytes.toString('ascii',16,20)!=='JSON')throw Error('missing JSON chunk');
 const gltf=JSON.parse(bytes.toString('utf8',20,20+bytes.readUInt32LE(12)).trim());
 const bones=new Set((gltf.skins??[]).flatMap(s=>s.joints.map(j=>gltf.nodes[j]?.name)));
 return {gltf,bones};
}
for(const avatar of catalog.avatars) {
 const path=resolve(root,avatar.body+'.glb');
 if(!existsSync(path)){console.log('MISSING '+basename(path));missing++;continue;}
 try {const info=inspect(path);if(!info.bones.size)throw Error('base avatar must have a named skeleton');rigs.set(avatar.body,info.bones);
  const clips=new Set((info.gltf.animations??[]).map(a=>a.name));for(const pose of ['idle',...catalog.poses])if(!clips.has(pose))console.log('WARN '+avatar.body+' animation missing: '+pose);
  console.log('OK '+basename(path)+' · '+info.bones.size+' bones');
 }catch(e){console.log('INVALID '+basename(path)+' · '+e.message);invalid++;}
}
for(const item of catalog.items) {
 const path=resolve(root,item.id+'.glb');
 if(!existsSync(path)){console.log('MISSING '+basename(path));missing++;continue;}
 try {const {bones}=inspect(path);const targets=item.body==='unisex'?['male','female']:[item.body];
  for(const body of targets){const rig=rigs.get(body);if(rig)for(const bone of bones)if(!rig.has(bone))throw Error('unknown '+body+' bone: '+bone);if(item.attachmentBone&&rig&&!rig.has(item.attachmentBone))throw Error('attachment bone absent: '+item.attachmentBone);}
  console.log('OK '+basename(path));
 }catch(e){console.log('INVALID '+basename(path)+' · '+e.message);invalid++;}
 if(!existsSync(resolve(root,item.id+'.webp')))console.log('WARN thumbnail missing: '+item.id+'.webp');
}
console.log(`Delivery check: ${missing} missing models, ${invalid} invalid models. Warnings also need visual review.`);
process.exitCode=missing||invalid?1:0;
