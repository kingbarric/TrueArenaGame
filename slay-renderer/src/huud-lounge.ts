import hostBadgeUrl from '../../app/assets/images/huud_ui/crown.png?inline';
import {cloneItemMaterial} from './item-colours';
import {seed,seatPose,roomPlace,animateBody,walkPosition,doorRoute,exitRoute,WALK_RATE,TRANSIT_SPEED} from './huud-avatar';
import * as T from 'three';
import {OrbitControls} from 'three/addons/controls/OrbitControls.js';
import {clone} from 'three/addons/utils/SkeletonUtils.js';
import {Wardrobe} from './avatar';
import {presentBody} from './presentation';
import type {Catalog,Look} from './types';

type Person={id:string;name:string;host:boolean;here:boolean;speaking:boolean;me:boolean;mode?:string;look?:Look};
type Actor={person:Person;root:T.Group;bones:Map<string,T.Bone>;label:HTMLButtonElement;phase:number;body:string;model:T.Group;place:ReturnType<typeof roomPlace>;seated:number;angle:number;slot:number;route:T.Vector3[];transit:'enter'|'exit'|null};
const send=(type:string,payload:Record<string,unknown>={})=>{if(window.flutter_inappwebview)void window.flutter_inappwebview.callHandler('huud',{type,...payload});};
const renderer=new T.WebGLRenderer({antialias:true,alpha:false});
renderer.setPixelRatio(Math.min(devicePixelRatio,1.5));renderer.setSize(innerWidth,innerHeight);renderer.outputColorSpace=T.SRGBColorSpace;renderer.toneMapping=T.ACESFilmicToneMapping;renderer.toneMappingExposure=1.0;
renderer.shadowMap.enabled=true;renderer.shadowMap.type=T.PCFSoftShadowMap;
document.body.prepend(renderer.domElement);
const scene=new T.Scene();scene.background=new T.Color('#fff0df');
const camera=new T.PerspectiveCamera(42,innerWidth/innerHeight,.05,50);camera.position.set(6.3,4.8,7.6);
const controls=new OrbitControls(camera,renderer.domElement);controls.target.set(0,.65,0);controls.enableDamping=true;controls.minDistance=4;controls.maxDistance=12;controls.minPolarAngle=.55;controls.maxPolarAngle=1.3;controls.enablePan=false;controls.update();
scene.add(new T.HemisphereLight('#fffaf1','#b87945',2.7));
const sun=new T.DirectionalLight('#fff1d8',3.2);sun.position.set(-3,7,5);sun.castShadow=true;sun.shadow.mapSize.set(1024,1024);sun.shadow.camera.left=-5;sun.shadow.camera.right=5;sun.shadow.camera.top=5;sun.shadow.camera.bottom=-5;sun.shadow.bias=-.001;scene.add(sun);
const fill=new T.DirectionalLight('#fff0dd',1.5);fill.position.set(4,3,-2);scene.add(fill);
const material=(color:string,rough=.8)=>new T.MeshStandardMaterial({color,roughness:rough});
const wood=material('#b68a5a'),cream=material('#fff0da'),sage=material('#f36d13'),dark=material('#a74412'),gold=material('#bba16b',.35),white=material('#eee9dc');
function mesh(g:T.BufferGeometry,m:T.Material,x:number,y:number,z:number){const a=new T.Mesh(g,m);a.position.set(x,y,z);a.castShadow=true;a.receiveShadow=true;scene.add(a);return a;}
const box=(w:number,h:number,d:number,m:T.Material,x:number,y:number,z:number)=>mesh(new T.BoxGeometry(w,h,d),m,x,y,z);
// An open, cutaway parlor with windows, a sofa, plants and warm flooring.
box(7,.12,6.4,material('#edd4b5'),0,-.09,0);
box(7,2.65,.12,cream,0,1.25,-3.15);box(.12,2.65,6.4,sage,-3.45,1.25,0);
for(let i=-3;i<=3;i++)box(.012,.004,6.3,material('#dfbc97'),i,.0,0);
const glass=material('#bfdce1');for(const x of [-1.7,1.7]){box(1.6,1.35,.035,white,x,1.55,-3.06);box(1.44,1.2,.04,glass,x,1.55,-3.03);box(.035,1.23,.05,white,x,1.55,-3);box(1.5,.035,.05,white,x,1.55,-3);for(const s of [-1,1])box(.19,1.65,.11,material('#ffc67b'),x+s*.85,1.4,-2.97);}
function couch(x:number,z:number,yaw:number,width:number){
 const group=new T.Group();group.position.set(x,0,z);group.rotation.y=yaw;scene.add(group);
 const piece=(w:number,h:number,d:number,m:T.Material,px:number,py:number,pz:number)=>{const item=new T.Mesh(new T.BoxGeometry(w,h,d),m);item.position.set(px,py,pz);item.castShadow=true;item.receiveShadow=true;group.add(item);};
 piece(width,.2,.8,dark,0,.19,0);piece(width,.62,.17,sage,0,.68,-.39);
 const count=Math.round(width/.78);for(let i=0;i<count;i++)piece(width/count-.035,.12,.68,material('#ff8a1f'),-width/2+(i+.5)*width/count,.31,.04);
 for(const sign of [-1,1]){piece(.18,.44,.85,sage,sign*(width/2+.03),.4,0);piece(.28,.3,.12,material('#ffe0b6'),sign*(width/2-.27),.66,-.27);}
 for(const px of [-width/2+.12,width/2-.12])for(const pz of [-.3,.3])piece(.07,.13,.07,wood,px,.055,pz);
}
couch(0,-1.95,0,2.45);couch(-2.3,.08,Math.PI/2,2.45);couch(2.3,0,-Math.PI/2,1.67);

box(.07,.82,1.05,gold,-3.36,1.7,.55);box(.075,.69,.9,material('#d7b590'),-3.31,1.7,.55);
const rug=mesh(new T.CylinderGeometry(2.5,2.5,.012,64),material('#f8ba74'),0,.005,.2);rug.scale.z=.89;
function plant(x:number,z:number){mesh(new T.CylinderGeometry(.18,.13,.3,16),material('#b77c5c'),x,.16,z);for(let i=0;i<8;i++){const leaf=mesh(new T.SphereGeometry(.18,10,8),material(i%2?'#5d865f':'#829d6d'),x+Math.sin(i*2.4)*.19,.45+i*.065,z+Math.cos(i*2.4)*.15);leaf.scale.set(.45,1.5,.7);leaf.rotation.z=Math.sin(i)*.5;}}
plant(2.8,-2.5);plant(-2.8,2.4);
// The open front doorway is the entry/exit point, away from the couches.
box(.12,2.25,.16,dark,-.63,1.12,3.08);box(.12,2.25,.16,dark,.63,1.12,3.08);
box(1.38,.13,.16,sage,0,2.28,3.08);box(1.2,.035,.6,material('#ff8a1f'),0,.015,3.08);
// A large, readable game button is anchored to the coffee table.
box(1.4,.08,.85,wood,0,.44,.4);for(const x of [-.54,.54])for(const z of [.08,.72])box(.065,.38,.065,wood,x,.2,z);
const gameButton=document.createElement('button');gameButton.id='start-game';gameButton.textContent='Start a game';gameButton.onclick=()=>send('game');document.body.append(gameButton);
const gamePoint=new T.Vector3();
const labels=document.querySelector('#names')!;
const actorGroup=new T.Group();scene.add(actorGroup);
const chairGroup=new T.Group();scene.add(chairGroup);
const prototypes=new Map<string,Promise<Wardrobe>>();let roomKey:unknown=null;let initialized=false,catalog:Catalog,actors:Actor[]=[],epoch=0,generation=0,paused=false,reducedMotion=false,selfMode:'sit'|'stand'|'walk'='sit';

const appearanceKey=(body:string,look?:Look)=>look?JSON.stringify(look):body;
const bodyAttributes=new Map<string,Record<string,T.BufferAttribute|T.InterleavedBufferAttribute>>();
async function prototype(body:'male'|'female',custom?:Look){
 const key=appearanceKey(body,custom);
 let pending=prototypes.get(key);
 if(!pending){pending=(async()=>{
  const w=new Wardrobe(renderer);
  const look:Look=custom??{body,avatarId:body,skinTone:body==='female'?'#c79782':'#996244',facePreset:'classic',pose:'idle',background:'studio',items:body==='female'?{tops:'female-top-tee',trousers:'female-trousers-tailored',hair:'female-hair-long',shoes:'shoe-1'}:{shirts:'male-tee-polo',trousers:'male-trousers-classic',hair:'male-hair-1',shoes:'shoe-1'}};
  await w.apply(look,catalog);
  w.root.traverse(o=>{
   delete o.userData.slayCoverage;
   if(o instanceof T.Mesh&&o.name.startsWith('region_')){
    const bodyKey=(look.avatarId??body)+':'+o.name,shared=bodyAttributes.get(bodyKey);
    if(shared)for(const [name,attribute] of Object.entries(shared))o.geometry.setAttribute(name,attribute);
    else bodyAttributes.set(bodyKey,{...o.geometry.attributes});
   }
  });
  return w;
 })();prototypes.set(key,pending);pending.catch(()=>{if(prototypes.get(key)===pending)prototypes.delete(key);});}
 return pending;
}
const copyMaterial=cloneItemMaterial;

function releaseActor(a:Actor){a.root.traverse(o=>{if(o instanceof T.Mesh){for(const m of Array.isArray(o.material)?o.material:[o.material])m.dispose();if(o instanceof T.SkinnedMesh)o.skeleton.dispose();}});a.label.remove();actorGroup.remove(a.root);}
function releaseActors(){for(const a of actors)releaseActor(a);actors=[];actorGroup.clear();}
async function populate(raw:Person[],animate=true){
 const people=raw.filter(p=>p.here),current=++epoch;
 const prepared:{p:Person;body:'male'|'female';source:Wardrobe}[]=new Array(people.length);
 let next=0;const worker=async()=>{while(next<people.length){const i=next++,p=people[i],body=p.look?.body??(seed(p.id)%2?'female':'male');prepared[i]={p,body,source:await prototype(body,p.look)};}};await Promise.all([worker(),worker()]);
 if(current!==epoch)return;
 const incoming=new Set(people.map(p=>p.id));
 for(const a of [...actors])if(!incoming.has(a.person.id)&&a.transit!=='exit'){
  if(reducedMotion||!animate){releaseActor(a);actors=actors.filter(v=>v!==a);}
  else{a.person={...a.person,here:false,speaking:false};a.transit='exit';a.route=exitRoute(a.root.position,a.place);decorate(a);}
 }
 for(const {p,body,source} of prepared){
  let existing=actors.find(a=>a.person.id===p.id);
  if(existing&&JSON.stringify(existing.person.look??null)===JSON.stringify(p.look??null)){
   if(existing.transit==='exit'){existing.route=[...existing.route,...doorRoute(existing.place).slice(1)];existing.transit='enter';}
   existing.person=p;decorate(existing);continue;
  }
  const used=new Set(actors.filter(a=>a.transit!=='exit'&&a!==existing).map(a=>a.slot));let slot=0;while(used.has(slot))slot++;
  const place=existing?.place??roomPlace(slot),position=existing?.root.position.clone(),seated=existing?.seated;
  if(existing){slot=existing.slot;releaseActor(existing);actors=actors.filter(a=>a!==existing);}
  const root=clone(source.root) as T.Group;root.traverse(o=>{if(o instanceof T.Mesh){o.material=Array.isArray(o.material)?o.material.map(copyMaterial):copyMaterial(o.material);o.castShadow=true;}});
  const actor=new T.Group();actor.add(root);actor.rotation.y=place.yaw;actorGroup.add(actor);
  const bones=seatPose(root,body),tones=['#c79782','#956443','#d5aa8b','#754e37'];if(!p.look)presentBody(root,tones[seed(p.id)%tones.length],new Set());
  const label=document.createElement('button');label.type='button';label.className='name';label.onclick=()=>send('person',{id:p.id});labels.append(label);
  const entering=initialized&&animate&&!reducedMotion&&!existing,route=entering?doorRoute(place):[];
  actor.position.copy(position??route[0]??new T.Vector3(place.x,0,place.z));
  const a:Actor={person:p,root:actor,bones,label,phase:(seed(p.id)%99)/10,body,model:root,place,seated:seated??(entering?0:place.seated?1:0),angle:Math.atan2(place.x,place.z-.4),slot,route,transit:entering?'enter':null};actors.push(a);decorate(a);
 }
 const first=!initialized;initialized=true;
 if(first)send('loaded',{generation,canSit:actors.some(a=>a.person.me&&a.place.seated)});
 // Retain prototypes while exiting avatars still use their shared geometry.
 const needed=new Set(actors.map(a=>appearanceKey(a.body,a.person.look)));
 for(const [key,value] of prototypes)if(!needed.has(key)){prototypes.delete(key);void value.then(w=>w.destroy());}
}
function decorate(a:Actor){a.label.replaceChildren();if(a.person.host){const badge=document.createElement('img');badge.src=hostBadgeUrl;badge.className='host-badge';badge.alt='';badge.setAttribute('aria-hidden','true');a.label.append(badge);}a.label.append(document.createTextNode(a.person.me?'You':a.person.name));a.label.classList.toggle('talking',a.person.speaking);a.label.classList.toggle('away',!a.person.here);a.label.setAttribute('aria-label',`${a.person.name}${a.person.speaking?', talking':''}${a.person.host?', host':''}`);a.label.title=a.person.speaking?'Talking now':a.person.here?'Here now':'Away';}
const point=new T.Vector3();let time=0,previous=performance.now();
renderer.setAnimationLoop(()=>{if(paused||document.hidden)return;const now=performance.now(),dt=Math.min((now-previous)/1000,.05);time+=dt;previous=now;controls.update();
 const plates:{x:number;y:number;w:number}[]=[];
 for(const a of [...actors]){
  const own=a.person.me,mode=own?selfMode:(a.person.mode??'sit'),walking=(a.transit!==null||mode==='walk')&&!reducedMotion;
  const seated=!a.transit&&a.place.seated&&mode==='sit';
  a.seated=T.MathUtils.damp(a.seated,seated?1:0,6,dt);
  let target=new T.Vector3(a.place.x,0,a.place.z),yaw=a.place.yaw;
  if(!seated&&(a.place.seated||walking)){if(walking&&!a.transit)a.angle+=dt*WALK_RATE;target=walkPosition(a.angle);yaw=walking?a.angle+Math.PI/2:Math.atan2(-target.x,.4-target.z);}
  if(a.transit){
   if(reducedMotion){a.root.position.copy(a.route.at(-1)!);a.route=[];}
   let distance=TRANSIT_SPEED*dt;
   while(a.route.length&&distance>0){const next=a.route[0],delta=next.clone().sub(a.root.position),length=delta.length();if(length>.005)yaw=Math.atan2(delta.x,delta.z);if(length<=distance){a.root.position.copy(next);a.route.shift();distance-=length;}else{a.root.position.addScaledVector(delta,distance/length);distance=0;}}
   if(!a.route.length){if(a.transit==='exit'){releaseActor(a);actors=actors.filter(v=>v!==a);continue;}a.transit=null;}
  }else if(reducedMotion){a.root.position.copy(target);a.seated=seated?1:0;}else a.root.position.lerp(target,1-Math.exp(-6*dt));
  a.root.rotation.y=yaw;animateBody(a.model,a.bones,a.body,a.seated,walking&&a.seated<.1,time);
  const move=reducedMotion||!a.person.here?0:Math.sin(time*.9+a.phase),spine=a.bones.get('Spine'),head=a.bones.get('Head');
  if(spine){spine.rotation.x=move*.018;spine.rotation.z=move*.013;}
  if(head){head.rotation.y=reducedMotion?0:Math.sin(time*.55+a.phase)*.055;head.rotation.x=a.person.speaking&&!reducedMotion?Math.sin(time*3+a.phase)*.025:0;}
  a.root.updateMatrixWorld(true);head?.getWorldPosition(point);point.y+=.24;point.project(camera);
  const width=a.label.offsetWidth,anchorX=(point.x*.5+.5)*innerWidth,anchor=(-point.y*.5+.5)*innerHeight;
  let x=T.MathUtils.clamp(anchorX,width/2+5,innerWidth-width/2-5),y=Math.max(30,anchor);
  placement:for(const dy of [0,19,38,57])for(const dx of [0,-20,20,-40,40]){
    const nextX=T.MathUtils.clamp(anchorX+dx,width/2+5,innerWidth-width/2-5),nextY=Math.max(30,anchor-dy);
    if(!plates.some(p=>Math.abs(p.x-nextX)<(p.w+width)/2+3&&Math.abs(p.y-nextY)<19)){x=nextX;y=nextY;break placement;}
  }
  plates.push({x,y,w:width});
  a.label.style.zIndex=a.person.speaking?'100':a.person.host?'50':'1';
  a.label.style.setProperty('--head',anchorX-x+'px');
  a.label.style.setProperty('--stem',Math.max(4,anchor-y+4)+'px');
  a.label.style.transform=`translate(-50%,-100%) translate(${x}px,${y}px)`;a.label.style.visibility=point.z<1&&point.z>-1?'visible':'hidden';

 }
 gamePoint.set(0,.58,.4).project(camera);gameButton.style.left=`${(gamePoint.x*.5+.5)*innerWidth}px`;gameButton.style.top=`${(-gamePoint.y*.5+.5)*innerHeight}px`;gameButton.style.visibility=gamePoint.z>-1&&gamePoint.z<1?'visible':'hidden';
 renderer.render(scene,camera);
});
window.addEventListener('resize',()=>{camera.aspect=innerWidth/innerHeight;camera.updateProjectionMatrix();renderer.setSize(innerWidth,innerHeight);});
renderer.domElement.addEventListener('webglcontextlost',e=>{e.preventDefault();paused=true;send('lost');});
(window as unknown as {huudReceive:(p:any)=>void}).huudReceive=(p)=>{if(p.type==='init'){paused=false;previous=performance.now();catalog=p.catalog;generation=p.generation;reducedMotion=!!p.reducedMotion;gameButton.hidden=p.canPlay===false;if(roomKey!==p.roomKey){releaseActors();initialized=false;roomKey=p.roomKey;}void populate(p.people,false).catch(e=>send('error',{message:String(e),generation}));}else if(p.type==='people'){void populate(p.people,p.animate!==false).catch(e=>send('error',{message:String(e),generation}));}else if(p.type==='selfAction'){selfMode=p.mode==='walk'?'walk':p.mode==='stand'?'stand':'sit';}else if(p.type==='pause'){paused=!!p.paused;previous=performance.now();}else if(p.type==='resetCamera'){camera.position.set(6.3,4.8,7.6);controls.target.set(0,.65,0);}else if(p.type==='dispose'){paused=true;++epoch;renderer.setAnimationLoop(null);releaseActors();controls.dispose();for(const w of prototypes.values())void w.then(w=>w.destroy());scene.traverse(o=>{if(o instanceof T.Mesh){o.geometry.dispose();for(const m of Array.isArray(o.material)?o.material:[o.material])m.dispose();}});renderer.dispose();}};
window.addEventListener('error',e=>send('error',{message:e.message,generation}));
const ready=()=>send('ready');window.addEventListener('flutterInAppWebViewPlatformReady',ready);ready();
