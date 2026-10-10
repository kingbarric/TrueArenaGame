import * as T from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { Wardrobe } from './avatar';
import type { Catalog,Look,Message } from './types';
import { LookState } from './look-state';
import { StudioBackdrop } from './studio';

let catalog:Catalog,look:Look,paused=false,disposed=false;
const lookState=new LookState();
let renderer:T.WebGLRenderer;
function send(type:string,payload:unknown={},id?:string){const message={v:1,type,payload,...(id?{id}:{})};if(window.flutter_inappwebview)void window.flutter_inappwebview.callHandler('slay',message);else window.SlayBridge?.postMessage(JSON.stringify(message));}
try{renderer=new T.WebGLRenderer({antialias:true,alpha:false,preserveDrawingBuffer:true});}catch(error){send('error',{code:'WEBGL_UNAVAILABLE',message:String(error)});throw error;}
renderer.setPixelRatio(Math.min(window.devicePixelRatio,2));renderer.setSize(innerWidth,innerHeight);renderer.outputColorSpace=T.SRGBColorSpace;renderer.toneMapping=T.ACESFilmicToneMapping;renderer.toneMappingExposure=1.25;
document.body.prepend(renderer.domElement);
const scene=new T.Scene();scene.background=new T.Color('#eee9e2');
const camera=new T.PerspectiveCamera(33,innerWidth/innerHeight,.05,40);camera.position.set(0,1.1,3.5);
const controls=new OrbitControls(camera,renderer.domElement);controls.target.set(0,.95,0);controls.enableDamping=true;controls.enablePan=false;controls.minDistance=1.25;controls.maxDistance=5;controls.minPolarAngle=Math.PI*.2;controls.maxPolarAngle=Math.PI*.67;
scene.add(new T.HemisphereLight('#ffffff','#b4a99b',2.2));const key=new T.DirectionalLight('#fff4df',3.5);key.position.set(2,4,3);scene.add(key);
const rim=new T.DirectionalLight('#d5dfff',1.5);rim.position.set(-2,2,-2);scene.add(rim);
const platform=new T.Mesh(new T.CylinderGeometry(.49,.52,.065,64),new T.MeshStandardMaterial({color:'#d4cabe',roughness:.65}));platform.position.y=-.025;scene.add(platform);
const wardrobe=new Wardrobe(renderer);scene.add(wardrobe.root);
const studio=new StudioBackdrop();scene.add(studio.root);
const runway=new T.Mesh(new T.BoxGeometry(1.05,.065,1.75),new T.MeshStandardMaterial({color:'#d4cabe',roughness:.65}));runway.position.set(0,-.025,-.45);runway.visible=false;scene.add(runway);
wardrobe.onShowcaseState=(playing,phase)=>{runway.visible=playing;platform.visible=!playing;send('showcaseState',{playing,phase});};
function setCamera(preset:string){
 const male=look?.body==='male',height=male?1.05:.95,distance=male?3.95:3.5,face=male?1.82:1.68;
 camera.position.set(preset==='back'?-.01:0,preset==='face'?face:preset==='feet'?.25:height+.15,preset==='back'?-distance:preset==='face'?1.1:preset==='feet'?1.8:distance);
 controls.target.set(0,preset==='face'?face:preset==='feet'?.2:height,0);controls.update();
}
let previous=performance.now(),frames=0,sampleAt=previous,slowSamples=0,tier='high';
renderer.setAnimationLoop(()=>{if(paused||disposed||document.hidden)return;const now=performance.now();const seconds=Math.max(0,(now-previous)/1000);wardrobe.update(wardrobe.showingOff?seconds:Math.min(seconds,.05));previous=now;controls.update();studio.update(camera,look?.background??'studio');renderer.render(scene,camera);frames++;if(now-sampleAt>5000){const fps=Math.round(frames*1000/(now-sampleAt));if(fps<24){if(++slowSamples>=2&&tier!=='low'){tier=tier==='high'?'standard':'low';renderer.setPixelRatio(tier==='low'?1:1.5);slowSamples=0;}}else slowSamples=0;send('perf',{fps,tier});frames=0;sampleAt=now;}});
window.addEventListener('resize',()=>{if(disposed)return;camera.aspect=innerWidth/innerHeight;camera.updateProjectionMatrix();renderer.setSize(innerWidth,innerHeight);});
renderer.domElement.addEventListener('webglcontextlost',event=>{event.preventDefault();paused=true;send('contextLost');});
renderer.domElement.addEventListener('webglcontextrestored',()=>{paused=false;send('ready',{rendererVersion:1,webgl2:true});});
document.addEventListener('visibilitychange',()=>{previous=sampleAt=performance.now();frames=slowSamples=0;});
let chain:Promise<void>=Promise.resolve();
window.slayReceive=async(message:Message)=>{
 chain=chain.catch(()=>{}).then(async()=>{
 try{
  if(message.v!==1)throw Error('Unsupported bridge version');const p=message.payload;
  switch(message.type){
   case 'init':catalog=p.catalog as Catalog;tier=String(p.tier??'high');renderer.setPixelRatio(p.tier==='low'?1:p.tier==='standard'?1.5:Math.min(devicePixelRatio,2));break;
   case 'applyLook':{if(!catalog)throw Error('Initialise the catalog first');const oldBody=look?.body;await lookState.apply(p.look as Look,async()=>{await wardrobe.apply(p.look as Look,catalog);});look=p.look as Look;if(oldBody!==look.body)setCamera('full');scene.background=new T.Color(({studio:'#eee9e2',runway:'#d8d4e0',lagos:'#ddcfb6',sunset:'#e7bb9e',royal:'#d3c5d3'} as Record<string,string>)[look.background]??'#eee9e2');break;}
   case 'showcase':{
     lookState.requireRendered();setCamera('full');previous=performance.now();
     // Return from the command queue immediately: Stop, Pause and outfit
     // changes must still be handled while Flutter awaits the performance.
     void wardrobe.showOff().then(async pose=>{look={...look,pose};await lookState.apply(look,async()=>{});send('ack',{pose},message.id);})
       .catch(error=>send('error',{code:'SHOWCASE_INTERRUPTED',message:String(error)},message.id));return;
   }
   case 'stopShowcase':wardrobe.stopShowcase();break;
   case 'setCamera':setCamera(String(p.preset));break;
   case 'rotateCamera':{const angle=Number(p.radians);if(!Number.isFinite(angle)||Math.abs(angle)>Math.PI)throw Error('Invalid camera rotation');camera.position.sub(controls.target).applyAxisAngle(new T.Vector3(0,1,0),angle).add(controls.target);controls.update();break;}
   case 'setPose':wardrobe.pose(String(p.poseId));if(look)look={...look,pose:String(p.poseId)};break;
   case 'snapshot':{
      lookState.requireRendered();if(wardrobe.showingOff)throw Error('Finish your show off before saving');const width=Math.max(256,Math.min(1024,Number(p.width)||600)),height=Math.max(256,Math.min(1536,Number(p.height)||900));
      const position=camera.position.clone(),target=controls.target.clone(),size=renderer.getSize(new T.Vector2()),ratio=renderer.getPixelRatio(),aspect=camera.aspect;
      try{renderer.setPixelRatio(1);renderer.setSize(width,height,false);camera.aspect=width/height;camera.updateProjectionMatrix();setCamera('full');studio.update(camera,look.background);renderer.render(scene,camera);
       send('snapshotResult',{pngBase64:renderer.domElement.toDataURL('image/png').split(',')[1]},message.id);
      }finally{renderer.setPixelRatio(ratio);renderer.setSize(size.x,size.y,false);camera.aspect=aspect;camera.position.copy(position);controls.target.copy(target);camera.updateProjectionMatrix();controls.update();}return;
   }
   case 'pause':paused=Boolean(p.paused);if(paused)wardrobe.stopShowcase('Show off cancelled: studio paused');previous=sampleAt=performance.now();frames=slowSamples=0;break;
   case 'dispose':disposed=true;renderer.setAnimationLoop(null);controls.dispose();wardrobe.destroy();studio.dispose();renderer.dispose();break;
   default:throw Error('Unknown bridge command');
  }
  send('ack',{},message.id);
 }catch(error){send('error',{code:'RENDERER_ERROR',message:String(error)},message.id);}
 });return chain;
};
const ready=()=>send('ready',{rendererVersion:1,webgl2:true,maxTextureSize:renderer.capabilities.maxTextureSize});
window.addEventListener('flutterInAppWebViewPlatformReady',ready);ready();
// Standalone browser preview uses the same starter wardrobe as the app.
if(import.meta.env?.DEV){fetch('/catalog.json').then(r=>r.json()).then(async c=>{await window.slayReceive({v:1,id:'init',type:'init',payload:{catalog:c,tier:'high'}});await window.slayReceive({v:1,id:'look',type:'applyLook',payload:{look:{body:'female',skinTone:'#623a27',facePreset:'classic',items:{outfit:'female-essential',hair:'female-hair-0',shoes:'shoe-1'},pose:'signature',background:'studio'}}});});}
