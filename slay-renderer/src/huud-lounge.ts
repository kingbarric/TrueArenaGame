import {seed,seatPose} from './huud-avatar';
import * as T from 'three';
import {OrbitControls} from 'three/addons/controls/OrbitControls.js';
import {clone} from 'three/addons/utils/SkeletonUtils.js';
import {Wardrobe} from './avatar';
import {presentBody} from './presentation';
import type {Catalog,Look} from './types';

type Person={id:string;name:string;host:boolean;here:boolean;speaking:boolean;me:boolean};
type Actor={person:Person;root:T.Group;bones:Map<string,T.Bone>;label:HTMLButtonElement;phase:number;head:T.Vector3};
const send=(type:string,payload:Record<string,unknown>={})=>{if(window.flutter_inappwebview)void window.flutter_inappwebview.callHandler('huud',{type,...payload});};
const renderer=new T.WebGLRenderer({antialias:true,alpha:false});
renderer.setPixelRatio(Math.min(devicePixelRatio,1.5));renderer.setSize(innerWidth,innerHeight);renderer.outputColorSpace=T.SRGBColorSpace;renderer.toneMapping=T.ACESFilmicToneMapping;renderer.toneMappingExposure=1.2;
renderer.shadowMap.enabled=true;renderer.shadowMap.type=T.PCFSoftShadowMap;
document.body.prepend(renderer.domElement);
const scene=new T.Scene();scene.background=new T.Color('#e8e3d5');
const camera=new T.PerspectiveCamera(39,innerWidth/innerHeight,.05,50);camera.position.set(5.5,4.3,6.7);
const controls=new OrbitControls(camera,renderer.domElement);controls.target.set(0,.65,0);controls.enableDamping=true;controls.minDistance=4;controls.maxDistance=12;controls.minPolarAngle=.55;controls.maxPolarAngle=1.3;controls.enablePan=false;controls.update();
scene.add(new T.HemisphereLight('#fffaf1','#7d9582',2.7));
const sun=new T.DirectionalLight('#fff1d8',3.2);sun.position.set(-3,7,5);sun.castShadow=true;sun.shadow.mapSize.set(1024,1024);sun.shadow.camera.left=-5;sun.shadow.camera.right=5;sun.shadow.camera.top=5;sun.shadow.camera.bottom=-5;sun.shadow.bias=-.001;scene.add(sun);
const fill=new T.DirectionalLight('#e4edff',1.5);fill.position.set(4,3,-2);scene.add(fill);
const material=(color:string,rough=.8)=>new T.MeshStandardMaterial({color,roughness:rough});
const wood=material('#b68a5a'),cream=material('#e5dec9'),sage=material('#a3b49b'),dark=material('#486753'),gold=material('#bba16b',.35),white=material('#eee9dc');
function mesh(g:T.BufferGeometry,m:T.Material,x:number,y:number,z:number){const a=new T.Mesh(g,m);a.position.set(x,y,z);a.castShadow=true;a.receiveShadow=true;scene.add(a);return a;}
const box=(w:number,h:number,d:number,m:T.Material,x:number,y:number,z:number)=>mesh(new T.BoxGeometry(w,h,d),m,x,y,z);
// An open, cutaway parlor with windows, a sofa, plants and warm flooring.
box(7,.12,6.4,material('#c7c7ae'),0,-.09,0);
box(7,2.65,.12,cream,0,1.25,-3.15);box(.12,2.65,6.4,sage,-3.45,1.25,0);
for(let i=-3;i<=3;i++)box(.012,.004,6.3,material('#b8bca5'),i,.0,0);
const glass=material('#bfdce1');for(const x of [-1.7,1.7]){box(1.6,1.35,.035,white,x,1.55,-3.06);box(1.44,1.2,.04,glass,x,1.55,-3.03);box(.035,1.23,.05,white,x,1.55,-3);box(1.5,.035,.05,white,x,1.55,-3);for(const s of [-1,1])box(.19,1.65,.11,material('#d6b39b'),x+s*.85,1.4,-2.97);}
box(2.05,.38,.75,dark,-2.7,.28,-1.7);box(2.05,.65,.18,sage,-2.7,.72,-2.02);for(const x of [-3.61,-1.79])box(.2,.55,.9,sage,x,.43,-1.7);for(const x of [-3.17,-2.23])box(.86,.13,.66,material('#bdc5a6'),x,.52,-1.63);
box(.07,.82,1.05,gold,-3.36,1.7,.55);box(.075,.69,.9,material('#d7b590'),-3.31,1.7,.55);
const rug=mesh(new T.CylinderGeometry(2.5,2.5,.012,64),material('#c9b28c'),0,.005,.2);rug.scale.z=.89;
function plant(x:number,z:number){mesh(new T.CylinderGeometry(.18,.13,.3,16),material('#b77c5c'),x,.16,z);for(let i=0;i<8;i++){const leaf=mesh(new T.SphereGeometry(.18,10,8),material(i%2?'#5d865f':'#829d6d'),x+Math.sin(i*2.4)*.19,.45+i*.065,z+Math.cos(i*2.4)*.15);leaf.scale.set(.45,1.5,.7);leaf.rotation.z=Math.sin(i)*.5;}}
plant(2.8,-2.5);plant(-2.8,2.4);
mesh(new T.CylinderGeometry(.15,.25,.76,24),wood,0,.38,0);mesh(new T.CylinderGeometry(1.16,1.2,.095,64),wood,0,.81,0);
mesh(new T.CylinderGeometry(.36,.36,.012,40),material('#d5c49c'),0,.865,0);
mesh(new T.CylinderGeometry(.075,.065,.12,12),white,0,.935,0);mesh(new T.SphereGeometry(.11,12,8),dark,0,1.06,0);
// Small mugs and an open book on the table.
for(const [x,z] of [[-.65,.25],[.4,-.5],[.6,.35]]){mesh(new T.CylinderGeometry(.065,.055,.11,16),white,x,.91,z);mesh(new T.TorusGeometry(.043,.01,8,16),white,x+.073,.91,z).rotation.y=Math.PI/2;}
box(.24,.012,.18,material('#ede6d3'),-.15,.88,.48);
const labels=document.querySelector('#names')!;
const actorGroup=new T.Group();scene.add(actorGroup);
const chairGroup=new T.Group();scene.add(chairGroup);
const prototypes=new Map<string,Promise<Wardrobe>>();let catalog:Catalog,actors:Actor[]=[],epoch=0,generation=0,paused=false,reducedMotion=false;

async function prototype(body:'male'|'female'){
 let pending=prototypes.get(body);if(!pending){pending=(async()=>{const w=new Wardrobe(renderer);const look:Look={body,avatarId:body,skinTone:body==='female'?'#c79782':'#996244',facePreset:'classic',pose:'idle',background:'studio',items:body==='female'?{tops:'female-top-tee',trousers:'female-trousers-tailored',hair:'female-hair-long',shoes:'shoe-1'}:{shirts:'male-tee-polo',trousers:'male-trousers-classic',hair:'male-hair-1',shoes:'shoe-1'}};await w.apply(look,catalog);w.root.traverse(o=>{delete o.userData.slayCoverage;});return w;})();prototypes.set(body,pending);pending.catch(()=>prototypes.delete(body));}return pending;
}

function releaseActors(){for(const a of actors){a.root.traverse(o=>{if(o instanceof T.Mesh){for(const m of Array.isArray(o.material)?o.material:[o.material])m.dispose();if(o instanceof T.SkinnedMesh)o.skeleton.dispose();}});a.label.remove();}actors=[];actorGroup.clear();chairGroup.traverse(o=>{if(o instanceof T.Mesh)o.geometry.dispose();});chairGroup.clear();}
async function populate(people:Person[]){
 const current=++epoch,ids=people.map(p=>p.id).join('|');
 if(ids===actors.map(a=>a.person.id).join('|')){actors.forEach((a,i)=>{a.person=people[i];decorate(a);});return;}
 const bodies=people.map(p=>seed(p.id)%2?'female':'male');await Promise.all([...new Set(bodies)].map(b=>prototype(b as 'male'|'female')));if(current!==epoch)return;
 releaseActors();
 for(let i=0;i<people.length;i++){const p=people[i],body=bodies[i],source=await prototype(body as 'male'|'female');if(current!==epoch)return;
  const root=clone(source.root) as T.Group;root.traverse(o=>{if(o instanceof T.Mesh){o.material=Array.isArray(o.material)?o.material.map(m=>m.clone()):o.material.clone();o.castShadow=true;}});
  const actor=new T.Group();actor.add(root);const angle=Math.PI*.8+i*2*Math.PI/Math.max(people.length,3),radius=1.8;actor.position.set(Math.sin(angle)*radius,0,Math.cos(angle)*radius);actor.rotation.y=Math.atan2(-actor.position.x,-actor.position.z);actorGroup.add(actor);
  const bones=seatPose(root,body),tones=['#c79782','#956443','#d5aa8b','#754e37'];presentBody(root,tones[seed(p.id)%tones.length],new Set());
  const colors=['#78966c','#6c859a','#b58e73','#9b7d91','#607f78'];root.traverse(o=>{if(o instanceof T.Mesh&&(/tee|polo/.test(o.name))){for(const m of Array.isArray(o.material)?o.material:[o.material])if(m instanceof T.MeshStandardMaterial)m.color.set(colors[seed(p.id)%colors.length]);}});
  const chair=new T.Group();chair.position.copy(actor.position);chair.rotation.y=actor.rotation.y;chairGroup.add(chair);for(const [x,z] of [[-.24,-.18],[.24,-.18],[-.24,.2],[.24,.2]]){const leg=new T.Mesh(new T.CylinderGeometry(.025,.02,.45,8),wood);leg.position.set(x,.23,z);chair.add(leg);}const cushion=new T.Mesh(new T.BoxGeometry(.58,.12,.57),sage);cushion.position.y=.49;chair.add(cushion);const back=new T.Mesh(new T.BoxGeometry(.58,.53,.12),dark);back.position.set(0,.81,-.28);chair.add(back);
  const label=document.createElement('button');label.type='button';label.className='name';label.onclick=()=>send('person',{id:p.id});labels.append(label);const a:Actor={person:p,root:actor,bones,label,phase:(seed(p.id)%99)/10,head:new T.Vector3()};actors.push(a);decorate(a);
 }
 send('loaded',{generation});
}
function decorate(a:Actor){a.label.textContent=(a.person.host?'♛ ':'')+(a.person.me?'You':a.person.name);a.label.classList.toggle('talking',a.person.speaking);a.label.classList.toggle('away',!a.person.here);a.label.setAttribute('aria-label',`${a.person.name}${a.person.speaking?', talking':''}${a.person.host?', host':''}`);a.label.title=a.person.speaking?'Talking now':a.person.here?'Here now':'Away';}
const point=new T.Vector3();let time=0,previous=performance.now();
renderer.setAnimationLoop(()=>{if(paused||document.hidden)return;const now=performance.now();time+=Math.min((now-previous)/1000,.05);previous=now;controls.update();
 for(const a of actors){const move=reducedMotion||!a.person.here?0:Math.sin(time*.9+a.phase);const spine=a.bones.get('Spine'),head=a.bones.get('Head');if(spine){spine.rotation.x=move*.018;spine.rotation.z=move*.013;}if(head)head.rotation.y=reducedMotion?0:Math.sin(time*.55+a.phase)*.055;if(a.person.speaking&&head&&!reducedMotion)head.rotation.x=Math.sin(time*3+a.phase)*.025;
  a.root.updateMatrixWorld(true);head?.getWorldPosition(point);point.y+=.24;point.project(camera);a.label.style.transform=`translate(-50%,-100%) translate(${(point.x*.5+.5)*innerWidth}px,${(-point.y*.5+.5)*innerHeight}px)`;a.label.style.visibility=point.z<1&&point.z>-1?'visible':'hidden';
 }
 renderer.render(scene,camera);
});
window.addEventListener('resize',()=>{camera.aspect=innerWidth/innerHeight;camera.updateProjectionMatrix();renderer.setSize(innerWidth,innerHeight);});
renderer.domElement.addEventListener('webglcontextlost',e=>{e.preventDefault();paused=true;send('lost');});
(window as unknown as {huudReceive:(p:any)=>void}).huudReceive=(p)=>{if(p.type==='init'){catalog=p.catalog;generation=p.generation;reducedMotion=!!p.reducedMotion;void populate(p.people).catch(e=>send('error',{message:String(e),generation}));}else if(p.type==='people'){void populate(p.people).catch(e=>send('error',{message:String(e),generation}));}else if(p.type==='pause'){paused=!!p.paused;previous=performance.now();}else if(p.type==='resetCamera'){camera.position.set(5.5,4.3,6.7);controls.target.set(0,.65,0);}else if(p.type==='dispose'){paused=true;++epoch;renderer.setAnimationLoop(null);releaseActors();controls.dispose();for(const w of prototypes.values())void w.then(w=>w.destroy());renderer.dispose();}};
const ready=()=>send('ready');window.addEventListener('flutterInAppWebViewPlatformReady',ready);ready();
