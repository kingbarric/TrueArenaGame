"""Render 256px character-picker portraits. Run with Blender in background mode."""
import bpy,json
from pathlib import Path
from mathutils import Vector
from mathutils.kdtree import KDTree
root=Path(__file__).resolve().parents[2];assets=root/'app/assets/slay_renderer/assets'
for ident in ['ella','beverly','girl02']:
 bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(assets/f'avatar-{ident}.glb'))
 old=set(bpy.data.objects);hair='male-hair-0' if ident=='michael' else 'female-hair-long';bpy.ops.import_scene.gltf(filepath=str(assets/f'{hair}.glb'))
 field=json.loads((assets/f'avatar-{ident}-fit.json').read_text());samples=[Vector((p[0],-p[2],p[1])) for p in field['samples']];deltas=[Vector((p[0],-p[2],p[1])) for p in field['deltas']];kd=KDTree(len(samples))
 for i,p in enumerate(samples):kd.insert(p,i)
 kd.balance()
 for obj in bpy.data.objects:
  if obj in old or obj.type!='MESH':continue
  inverse=obj.matrix_world.inverted()
  for v in obj.data.vertices:
   point=obj.matrix_world@v.co;near=kd.find_n(point,4);weights=[1/max(n[2],.001)**2 for n in near];offset=sum((deltas[n[1]]*w for n,w in zip(near,weights)),Vector())/sum(weights);v.co=inverse@(point+offset)
 scene=bpy.context.scene;scene.render.engine='BLENDER_EEVEE';scene.render.resolution_x=256;scene.render.resolution_y=256;scene.render.resolution_percentage=100;scene.world=bpy.data.worlds.new('World');scene.world.color=(.12,.12,.12)
 height=1.79 if ident=='michael' else 1.64;target=Vector((0,-.02,height));bpy.ops.object.camera_add(location=(0,-1.6,height+.03));camera=bpy.context.object;camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.type='ORTHO';camera.data.ortho_scale=.46;scene.camera=camera
 for loc,power in [((1,-2,3),180),((-1,-1,2),90)]:
  bpy.ops.object.light_add(type='AREA',location=loc);o=bpy.context.object;o.data.energy=power;o.data.shape='DISK';o.data.size=3;o.rotation_euler=(target-o.location).to_track_quat('-Z','Y').to_euler()
 scene.render.image_settings.file_format='PNG';scene.render.filepath=str(assets/f'avatar-{ident}.png');bpy.ops.render.render(write_still=True)
