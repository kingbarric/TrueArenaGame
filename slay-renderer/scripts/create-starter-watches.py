"""Author three original rigid watch GLBs, local to LeftHand (Blender Z-up)."""
from pathlib import Path
import math
import bpy
from mathutils import Vector

assets = Path(__file__).resolve().parents[2] / 'app/assets/slay_renderer/assets'

def material(name, colour, metal=0, rough=.35):
    m = bpy.data.materials.new(name); m.diffuse_color = (*colour, 1); m.use_nodes = True
    bsdf = m.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = (*colour, 1)
    bsdf.inputs['Metallic'].default_value = metal; bsdf.inputs['Roughness'].default_value = rough
    return m

def cylinder(name, radius, depth, location, mat):
    bpy.ops.mesh.primitive_cylinder_add(vertices=40, radius=radius, depth=depth, location=location)
    o = bpy.context.object; o.name = name
    o.rotation_euler[0] = math.pi / 2; o.data.materials.append(mat)
    bevel = o.modifiers.new('Rounded edge', 'BEVEL'); bevel.width = .001; bevel.segments = 2
    return o

def box(name, size, location, mat):
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    o = bpy.context.object; o.name = name; o.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o.data.materials.append(mat)
    bevel = o.modifiers.new('Soft edge', 'BEVEL'); bevel.width = .002; bevel.segments = 3
    return o

for style in ['gold', 'silver', 'smart']:
    bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
    metal = material('Gold' if style == 'gold' else 'Steel', (.7,.43,.13) if style == 'gold' else (.6,.65,.7), .85)
    dark = material('Leather' if style == 'silver' else 'Silicone', (.055,.029,.018) if style == 'silver' else (.018,.022,.028), 0, .7)
    dial = material('Dial', (.86,.8,.65) if style == 'gold' else (.028,.04,.06), .1)
    hands = material('Hands', (.02,.025,.035) if style == 'gold' else (.9,.88,.8), .4)
    centre = Vector((-.025, 0, .043))
    # A real wrist band, with the hole aligned to the forearm direction.
    bpy.ops.mesh.primitive_torus_add(major_radius=.048, minor_radius=.0045, major_segments=40, minor_segments=8, location=centre)
    band = bpy.context.object; band.name = 'Wrist band'
    band.rotation_euler = Vector((.30,-.55,-.75)).to_track_quat('Z','Y').to_euler()
    band.data.materials.append(metal if style == 'gold' else dark)
    if style == 'smart':
        box('Smart case', (.057,.010,.064), (-.025,-.035,.043), metal)
        box('Smart display', (.048,.002,.055), (-.025,-.041,.043), dial)
        for n, width in enumerate([.024,.033,.018]):
            box('Display bar', (width,.001,.003), (-.025,-.043,.03+n*.009), hands)
    else:
        cylinder('Case', .031, .01, (-.025,-.034,.043), metal)
        cylinder('Dial', .026, .002, (-.025,-.040,.043), dial)
        for hour in range(12):
            a = hour * math.pi/6
            marker = box('Hour marker', (.002,.001,.004), (-.025+math.sin(a)*.021,-.042,.043+math.cos(a)*.021), hands)
            marker.rotation_euler[1] = -a
        box('Minute hand', (.002,.001,.021), (-.025,-.043,.052), hands)
        box('Hour hand', (.015,.001,.002), (-.019,-.043,.043), hands)
        if style == 'gold':
            for x,z in [(-.035,.038),(-.015,.038),(-.025,.027)]: cylinder('Chronograph', .005,.001,(x,-.043,z),metal)
        cylinder('Crown', .004, .007, (.009,-.034,.043), metal)
    # Both source bodies extend their hands forward of the rig plane.
    # Keep reviewed fit groups so each band actually surrounds its wrist.
    originals = [obj for obj in bpy.context.scene.objects if obj.type == 'MESH']
    for obj in originals:
        if obj.name != 'Wrist band': obj.location.y *= 1.5
    for body, target in [('female', Vector((-.030,-.185,.095))), ('male', Vector((-.070,-.200,.090)))]:
        group = bpy.data.objects.new(f'{body} watch fit', None)
        bpy.context.collection.objects.link(group); group['slayBody'] = body
        group.location = target - centre
        for original in originals:
            obj = original if body == 'female' else original.copy()
            if body == 'male': bpy.context.collection.objects.link(obj)
            obj.parent = group
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.export_scene.gltf(filepath=str(assets / f'watch-{style}.glb'), export_format='GLB', use_selection=True, export_yup=True, export_extras=True)
