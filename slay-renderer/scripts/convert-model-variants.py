"""Offline conversion of CC0 MHM character definitions for the shared fashion rig.
Usage: blender -b --python this.py -- MAKEHUMAN_ROOT OUTPUT_DIRECTORY.
The input GLBs are opened read-only. Only new avatar-* files are written.
MakeHuman authoring dependencies are not shipped in the game.
"""
import json, os, sys, struct, math
from pathlib import Path
import numpy as np
from mathutils import Vector
from mathutils.kdtree import KDTree
root=Path(__file__).resolve().parents[2]
assets=root/'app/assets/slay_renderer/assets'
source=root/'slay-renderer/source_assets/makehuman/starter'
args=sys.argv[sys.argv.index('--')+1:];mh=Path(args[0]).resolve();out=Path(args[1]).resolve();out.mkdir(parents=True,exist_ok=True)
os.chdir(mh);sys.path.insert(0,str(mh/'lib'));import targets
library=targets.getTargets()
def vertices(p):return np.array([list(map(float,l.split()[1:4])) for l in p.read_text().splitlines() if l.startswith('v ')])
base=vertices(mh/'data/3dobjs/base.obj')
def factors(mods,body):
 v={k.split('/')[-1]:x for k,x in mods.items() if k.startswith('macrodetails') or k in ['breast/BreastSize','breast/BreastFirmness']};g=v.get('Gender',0 if body=='female' else 1);a=v.get('Age',.5);f={'male':g,'female':1-g}
 if a<.5:f.update(old=0,baby=max(0,1-a*5.333),young=max(0,(a-.1875)*3.2));f['child']=max(0,min(1,5.333*a)-f['young'])
 else:f.update(child=0,baby=0,old=2*a-1,young=2-2*a)
 for key,labels in [('Muscle',['minmuscle','averagemuscle','maxmuscle']),('Weight',['minweight','averageweight','maxweight']),('Height',['minheight','averageheight','maxheight']),('BreastSize',['mincup','averagecup','maxcup']),('BreastFirmness',['minfirmness','averagefirmness','maxfirmness']),('BodyProportions',['uncommonproportions','regularproportions','idealproportions'])]:
  x=v.get(key,.5);lo=max(0,1-2*x);hi=max(0,2*x-1);f.update(zip(labels,[lo,1-lo-hi,hi]))
 for race in ['African','Asian','Caucasian']:f[race.lower()]=v.get(race,1/3)
 return f

def shape(mods,body):
 f=factors(mods,body);weights={};missing=[]
 for name,value in mods.items():
  if name.startswith('macrodetails') or name in ['breast/BreastSize','breast/BreastFirmness']:continue
  group,modifier=name.split('/',1)
  if '|' in modifier:
   ends=modifier.split('|');stem=ends[0].rsplit('-',1)[0];suffix=ends[0].rsplit('-',1)[1] if value<0 else ends[-1];key=tuple((group+'-'+stem+'-'+suffix).split('-'));amount=abs(value)
  else:key=tuple((group+'-'+modifier).split('-'));amount=max(0,value)
  matches=library.groups.get(key,[])
  if not matches and amount:missing.append(name)
  for c in matches:weights[c.path]=amount*math.prod(f[x] for x in c.getVariables())
 for key,components in library.groups.items():
  if key[0]=='macrodetails' or key==('breast',):
   for c in components:weights[c.path]=math.prod(f[x] for x in c.getVariables())
 result=base.copy()
 for path,weight in weights.items():
  if weight<1e-8:continue
  data=np.loadtxt(mh/path,comments='#',ndmin=2)
  if data.size:result[data[:,0].astype(int)]+=data[:,1:4]*weight
 if missing:raise ValueError('Unmapped MHM modifiers: '+str(missing))
 return result

def proxy(coords):
 scales={};rows=[];active=False
 for l in (source/'proxymeshes/female1605/female1605.proxy').read_text().splitlines():
  p=l.split()
  if not p:continue
  if p[0] in ['x_scale','y_scale','z_scale']:
   a,b=int(p[1]),int(p[2]);axis='xyz'.index(p[0][0]);scales[axis]=abs(coords[a,axis]-coords[b,axis])/float(p[3])
  elif p[0]=='verts':active=True
  elif active and p[0].isdigit() and len(p)==1:rows.append(coords[int(p[0])])
  elif active and p[0].isdigit() and len(p)>=9:rows.append(sum(coords[int(p[i])]*float(p[i+3]) for i in range(3))+np.array([float(p[i+6])*scales.get(i,1) for i in range(3)]))
  elif active and not p[0].startswith('#'):break
 return np.array(rows)

def encode(doc,binary):
 j=json.dumps(doc,separators=(',',':')).encode();j+=b' '*((-len(j))%4);binary+=b'\0'*((-len(binary))%4)
 return struct.pack('<5I',0x46546c67,2,28+len(j)+len(binary),len(j),0x4e4f534a)+j+struct.pack('<2I',len(binary),0x004e4942)+binary

for body,ident,file in [('female','girl02','girl02.mhm'),('male','indian-male','indian-male.mhm')]:
 mods={p[1]:float(p[2]) for l in (Path(__file__).parent/'models'/file).read_text().splitlines() if (p:=l.split()) and p[0]=='modifier'}
 original=proxy(shape({},body));custom=proxy(shape(mods,body))
 # Standardise stature to this game's existing rig, preserving shape changes.
 def normalise(points):
  points=points.copy();points[:,1]-=points[:,1].min();points*=(1.8 if body=='female' else 1.95)/points[:,1].max();return points
 original=normalise(original);custom=normalise(custom)
 if body=='female':
  samples=vertices(source/'proxymeshes/female1605/female1605.obj');samples[:,1]+=8.184;samples*=1.8/16.044
 else:samples=original
 delta=custom-original;delta[:,1]=np.clip(delta[:,1],-.045,.045)
 # Preserve the shared footwear fit with a smooth blend at the ankle.
 delta*=np.clip((samples[:,1]-.13)/.12,0,1)[:,None]
 tree=KDTree(len(samples))
 for i,p in enumerate(samples):tree.insert(Vector(p),i)
 tree.balance()
 def warp(p):
  near=tree.find_n(Vector(p),4)
  if near[0][2]<1e-6:return delta[near[0][1]]
  w=np.array([1/max(n[2],.001)**2 for n in near]);return np.sum(delta[[n[1] for n in near]]*w[:,None],axis=0)/w.sum()
 b=(assets/(body+'.glb')).read_bytes();n=struct.unpack_from('<I',b,12)[0];doc=json.loads(b[20:20+n]);binary=bytearray(b[28+n:])
 for mesh in doc['meshes']:
  for prim in mesh['primitives']:
   a=doc['accessors'][prim['attributes']['POSITION']];v=doc['bufferViews'][a['bufferView']];offset=v.get('byteOffset',0)+a.get('byteOffset',0);positions=np.frombuffer(binary,dtype='<f4',count=a['count']*3,offset=offset).reshape(-1,3)
   positions+=np.array([warp(p) for p in positions]);a['min']=positions.min(axis=0).tolist();a['max']=positions.max(axis=0).tolist()
   ai=doc['accessors'][prim['indices']];vi=doc['bufferViews'][ai['bufferView']];indices=np.frombuffer(binary,dtype='<u4',count=ai['count'],offset=vi.get('byteOffset',0)).reshape(-1,3)
   normals=np.zeros_like(positions);tri=positions[indices];face=np.cross(tri[:,1]-tri[:,0],tri[:,2]-tri[:,0])
   for i in range(3):np.add.at(normals,indices[:,i],face)
   normals/=np.maximum(np.linalg.norm(normals,axis=1)[:,None],1e-8)
   an=doc['accessors'][prim['attributes']['NORMAL']];vn=doc['bufferViews'][an['bufferView']];np.frombuffer(binary,dtype='<f4',count=an['count']*3,offset=vn.get('byteOffset',0)).reshape(-1,3)[:]=normals
 doc['asset']['generator']='SlayHuud shared-rig adaptation of MakeHuman '+ident
 output=out/('avatar-'+ident+'.glb');assert output.name not in ['female.glb','male.glb'];output.write_bytes(encode(doc,bytes(binary)))
 field={'version':1,'avatarId':ident,'body':body,'samples':np.round(samples,6).tolist(),'deltas':np.round(delta,6).tolist()};(out/('avatar-'+ident+'-fit.json')).write_text(json.dumps(field,separators=(',',':'))+'\n')
 print(ident,'samples',len(samples),'largest offset',np.linalg.norm(delta,axis=1).max())
