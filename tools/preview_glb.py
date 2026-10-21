"""Render a quick preview of a GLB for visual QA (Cycles CPU, no denoise)."""
import os

import bpy
from mathutils import Vector

glb = os.environ["GLB"]
out = os.environ.get("OUT", "/tmp/opencode/preview.png")

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb)

mn = Vector((1e9, 1e9, 1e9))
mx = Vector((-1e9, -1e9, -1e9))
for obj in bpy.data.objects:
    if obj.type != "MESH":
        continue
    for corner in obj.bound_box:
        point = obj.matrix_world @ Vector(corner)
        mn = Vector((min(mn[i], point[i]) for i in range(3)))
        mx = Vector((max(mx[i], point[i]) for i in range(3)))
center = (mn + mx) * 0.5
size = mx - mn
radius = max(size)

scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 20
scene.cycles.use_denoising = False
scene.render.resolution_x = 800
scene.render.resolution_y = 520
scene.render.filepath = out

camera_data = bpy.data.cameras.new("Cam")
camera = bpy.data.objects.new("Cam", camera_data)
scene.collection.objects.link(camera)
camera.location = center + Vector((radius * 0.9, -radius * 1.15, radius * 0.55))
camera.rotation_euler = (center - camera.location).to_track_quat("-Z", "Y").to_euler()
scene.camera = camera

sun_data = bpy.data.lights.new("Sun", "SUN")
sun_data.energy = 4.0
sun = bpy.data.objects.new("Sun", sun_data)
sun.rotation_euler = (0.55, 0.15, 0.9)
scene.collection.objects.link(sun)
scene.world = bpy.data.worlds.new("World")
scene.world.use_nodes = True
scene.world.node_tree.nodes["Background"].inputs[0].default_value = (0.5, 0.62, 0.78, 1.0)
bpy.ops.render.render(write_still=True)
print(f"PREVIEW OK {out} bounds={tuple(round(v, 2) for v in size)}")
