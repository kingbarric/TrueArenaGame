"""Render actual converted geometry, not placeholders or unrelated previews."""
from pathlib import Path
import json
import bpy
from mathutils import Vector

root = Path(__file__).resolve().parents[2]
assets = root / 'app/assets/slay_renderer/assets'
catalog = json.loads((root / 'backend/ta-api/src/main/resources/slay/catalog.json').read_text())
for item in catalog['items']:
    if not item['assetUrl'] or not (item['id'].startswith(('female-date-', 'male-tee-', 'male-trousers-', 'male-dinner-', 'male-bowtie-', 'male-tailored-', 'female-earrings-', 'female-bag-', 'female-lipstick-', 'watch-'))): continue
    bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
    bpy.ops.import_scene.gltf(filepath=str(assets / (item['id']+'.glb')))
    for obj in bpy.context.scene.objects:
        ancestor = obj
        while ancestor is not None:
            if ancestor.get('slayBody') == 'male': obj.hide_render = True
            ancestor = ancestor.parent
    points = [obj.matrix_world @ Vector(corner) for obj in bpy.context.scene.objects if obj.type == 'MESH' and not obj.hide_render for corner in obj.bound_box]
    low = Vector([min(p[a] for p in points) for a in range(3)])
    high = Vector([max(p[a] for p in points) for a in range(3)])
    target = (low+high)/2; height = max(high.z-low.z, (high.x-low.x)*1.15, .04)
    scene = bpy.context.scene; scene.render.engine = 'CYCLES'; scene.cycles.samples = 16
    scene.render.resolution_x = scene.render.resolution_y = 192; scene.render.resolution_percentage = 100
    scene.render.film_transparent = True; scene.render.image_settings.file_format = 'PNG'; scene.view_settings.view_transform = 'Standard'; scene.world.color = (.3,.3,.3)
    bpy.ops.object.camera_add(location=target+Vector((height*.18,-height*2,height*.10)))
    camera=bpy.context.object; camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler(); camera.data.type='ORTHO';camera.data.ortho_scale=height*1.18;scene.camera=camera
    for delta,energy in [((1,-2,3),180),((-2,-1,2),110)]:
        bpy.ops.object.light_add(type='AREA',location=target+Vector(delta));light=bpy.context.object;light.data.energy=energy;light.data.shape='DISK';light.data.size=3;light.rotation_euler=(target-light.location).to_track_quat('-Z','Y').to_euler()
    scene.render.filepath=str(assets/(item['id']+'.png'));bpy.ops.render.render(write_still=True)
