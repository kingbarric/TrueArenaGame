"""Run with Blender --background --factory-startup --python this-file.py."""
from pathlib import Path
import bpy
from mathutils import Vector

assets = Path(__file__).resolve().parents[2] / "app/assets/slay_renderer/assets"
for item in ["shoe-0", "shoe-1"]:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    bpy.ops.import_scene.gltf(filepath=str(assets / f"{item}.glb"))
    for obj in bpy.context.scene.objects:
        if obj.get("slayBody") == "male":
            obj.hide_render = True
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 24
    scene.render.resolution_x = scene.render.resolution_y = 192
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.view_settings.view_transform = "Standard"
    scene.world.color = (.3, .3, .3)
    bpy.ops.object.camera_add(location=(.65, -1.0, .65))
    camera = bpy.context.object
    camera.rotation_euler = (Vector((0, -.07, .06)) - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = .67
    scene.camera = camera
    for location, energy, size in [((1, -2, 3), 180, 3), ((-2, 0, 2), 100, 2)]:
        bpy.ops.object.light_add(type="AREA", location=location)
        light = bpy.context.object
        light.data.energy, light.data.shape, light.data.size = energy, "DISK", size
        light.rotation_euler = (Vector((0, 0, .08)) - light.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = str(assets / f"{item}.png")
    bpy.ops.render.render(write_still=True)
