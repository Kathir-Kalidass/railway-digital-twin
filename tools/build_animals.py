"""Build detailed, game-ready deer and elephant models for the Godot twin.

Run with:  blender -b -P tools/build_animals.py
Outputs:   godot/assets/models/animals/deer.glb
           godot/assets/models/animals/elephant.glb

Every limb is a separate object whose origin sits at the joint, so the Godot
side can swing legs/trunk by rotating child nodes. No image textures are used,
keeping each GLB a few hundred kilobytes.
"""
import math
import os

import bpy
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "godot", "assets", "models", "animals")


def reset() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.unit_settings.system = "METRIC"


def material(name: str, color, roughness=0.8, metallic=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    return mat


def _finish(obj, mat) -> None:
    obj.data.materials.append(mat)
    bpy.ops.object.shade_smooth()


def ellipsoid(name, scale, location, mat, rotation=(0.0, 0.0, 0.0)):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=20, radius=1.0, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    obj.rotation_euler = rotation
    _finish(obj, mat)
    return obj


def limb(name, radius, length, location, mat, rotation=(0.0, 0.0, 0.0), taper=0.7):
    """Cylinder whose origin is the top joint; extends along -Z."""
    bpy.ops.mesh.primitive_cone_add(
        vertices=20,
        radius1=radius,
        radius2=radius * taper,
        depth=length,
        location=(0.0, 0.0, 0.0),
    )
    obj = bpy.context.object
    obj.name = name
    obj.data.transform(
        __import__("mathutils").Matrix.Translation(Vector((0.0, 0.0, -length * 0.5)))
    )
    obj.location = location
    obj.rotation_euler = rotation
    _finish(obj, mat)
    return obj


def horn(name, radius, length, location, mat, rotation=(0.0, 0.0, 0.0)):
    return limb(name, radius, length, location, mat, rotation=rotation, taper=0.15)


def join_meshes(objects, name, parent=None):
    """Join static parts into a single multi-material mesh (fewer draw calls)."""
    objects = [obj for obj in objects if obj and obj.type == "MESH"]
    if not objects:
        return None
    for obj in objects:
        with bpy.context.temp_override(
            active_object=obj,
            selected_editable_objects=[obj],
            selected_objects=[obj],
            object=obj,
        ):
            bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    if len(objects) > 1:
        with bpy.context.temp_override(
            active_object=objects[0],
            selected_editable_objects=objects,
            selected_objects=objects,
        ):
            bpy.ops.object.join()
    joined = objects[0]
    joined.name = name
    if joined.parent != parent:
        joined.parent = parent
        if parent:
            joined.matrix_parent_inverse = parent.matrix_world.inverted()
    return joined


def build_deer():
    fur = material("DeerFur", (0.30, 0.18, 0.09), 0.85)
    belly = material("DeerBelly", (0.78, 0.70, 0.56), 0.85)
    antler = material("DeerAntler", (0.72, 0.64, 0.47), 0.6)
    dark = material("DeerDark", (0.06, 0.04, 0.03), 0.4)

    ellipsoid("Body", (0.82, 0.40, 0.48), (0.0, 0.0, 0.98), fur)
    ellipsoid("Rump", (0.38, 0.36, 0.40), (-0.62, 0.0, 1.0), fur)
    ellipsoid("Belly", (0.55, 0.30, 0.26), (0.05, 0.0, 0.78), belly)
    ellipsoid("Neck", (0.30, 0.22, 0.46), (0.62, 0.0, 1.35), fur, rotation=(0.0, -0.45, 0.0))
    ellipsoid("Head", (0.30, 0.19, 0.22), (0.98, 0.0, 1.66), fur)
    ellipsoid("Muzzle", (0.17, 0.12, 0.12), (1.24, 0.0, 1.56), belly)
    ellipsoid("EarL", (0.11, 0.035, 0.13), (0.82, 0.20, 1.83), fur, rotation=(0.35, 0.0, 0.55))
    ellipsoid("EarR", (0.11, 0.035, 0.13), (0.82, -0.20, 1.83), fur, rotation=(-0.35, 0.0, -0.55))
    ellipsoid("EyeL", (0.035, 0.03, 0.035), (1.08, 0.13, 1.72), dark)
    ellipsoid("EyeR", (0.035, 0.03, 0.035), (1.08, -0.13, 1.72), dark)
    ellipsoid("Nose", (0.055, 0.05, 0.04), (1.37, 0.0, 1.53), dark)

    for side, suffix in ((0.11, "L"), (-0.11, "R")):
        horn(f"Antler{suffix}", 0.032, 0.58, (0.92, side, 1.82), antler, rotation=(0.0, -0.30, 0.0))
        horn(f"Antler{suffix}2", 0.026, 0.40, (0.91, side, 2.02), antler, rotation=(0.35, -0.55, 0.15))
        horn(f"Antler{suffix}3", 0.026, 0.38, (0.91, side, 2.02), antler, rotation=(-0.35, -0.55, -0.15))
        horn(f"Antler{suffix}4", 0.02, 0.30, (1.06, side, 2.30), antler, rotation=(0.25, -0.85, 0.3))
        horn(f"Antler{suffix}5", 0.02, 0.28, (0.94, side, 2.28), antler, rotation=(-0.4, -0.75, -0.2))

    limb("LegFL", 0.068, 0.94, (0.58, 0.24, 0.95), fur)
    limb("LegFR", 0.068, 0.94, (0.58, -0.24, 0.95), fur)
    limb("LegBL", 0.075, 0.98, (-0.62, 0.24, 1.00), fur)
    limb("LegBR", 0.075, 0.98, (-0.62, -0.24, 1.00), fur)
    horn("Tail", 0.045, 0.30, (-0.92, 0.0, 1.18), fur, rotation=(0.0, 0.55, 0.0))
    static = [o for o in bpy.data.objects if o.type == "MESH" and not o.name.startswith("Leg")]
    join_meshes(static, "DeerBody")


def build_elephant():
    skin = material("ElephantSkin", (0.42, 0.42, 0.44), 0.95)
    wrinkles = material("ElephantWrinkles", (0.36, 0.36, 0.38), 0.95)
    tusk = material("ElephantTusk", (0.90, 0.87, 0.76), 0.35)
    dark = material("ElephantEye", (0.05, 0.04, 0.04), 0.3)

    ellipsoid("Body", (1.45, 0.82, 0.92), (0.0, 0.0, 1.55), skin)
    ellipsoid("Shoulders", (0.62, 0.78, 0.85), (0.78, 0.0, 1.62), skin)
    ellipsoid("Hips", (0.60, 0.74, 0.80), (-0.92, 0.0, 1.58), skin)
    ellipsoid("Head", (0.68, 0.58, 0.66), (1.38, 0.0, 1.86), skin)
    ellipsoid("Forehead", (0.40, 0.52, 0.46), (1.30, 0.0, 2.18), wrinkles)
    ellipsoid("EarL", (0.07, 0.55, 0.72), (1.10, 0.62, 2.02), wrinkles, rotation=(0.25, 0.0, 0.35))
    ellipsoid("EarR", (0.07, 0.55, 0.72), (1.10, -0.62, 2.02), wrinkles, rotation=(-0.25, 0.0, -0.35))
    ellipsoid("EyeL", (0.05, 0.05, 0.05), (1.78, 0.42, 2.0), dark)
    ellipsoid("EyeR", (0.05, 0.05, 0.05), (1.78, -0.42, 2.0), dark)

    trunk = bpy.data.objects.new("Trunk", None)
    bpy.context.scene.collection.objects.link(trunk)
    trunk.location = (1.84, 0.0, 1.72)
    for index in range(10):
        t = index / 9.0
        radius = 0.30 * (1.0 - t) + 0.09
        x = 1.84 + 0.50 * math.sin(t * 1.4)
        z = 1.72 - 1.62 * t
        part = ellipsoid(f"Trunk{index + 1:02d}", (radius, radius, radius * 0.92), (x, 0.0, z), skin if index % 2 == 0 else wrinkles)
        part.parent = trunk
        part.matrix_parent_inverse = trunk.matrix_world.inverted()
    for side in (1.0, -1.0):
        horn(f"Tusk{'L' if side > 0 else 'R'}", 0.10, 0.85, (1.88, 0.30 * side, 1.62), tusk, rotation=(0.0, 1.25, 0.0))

    limb("LegFL", 0.225, 1.55, (0.92, 0.50, 1.55), skin, taper=0.8)
    limb("LegFR", 0.225, 1.55, (0.92, -0.50, 1.55), skin, taper=0.8)
    limb("LegBL", 0.235, 1.55, (-0.88, 0.50, 1.55), wrinkles, taper=0.8)
    limb("LegBR", 0.235, 1.55, (-0.88, -0.50, 1.55), wrinkles, taper=0.8)
    horn("Tail", 0.06, 0.85, (-1.42, 0.0, 1.7), skin, rotation=(0.0, 0.5, 0.0))
    trunk_parts = [o for o in bpy.data.objects if o.type == "MESH" and o.name.startswith("Trunk")]
    join_meshes(trunk_parts, "TrunkMesh", parent=trunk)
    static = [
        o for o in bpy.data.objects
        if o.type == "MESH" and not o.name.startswith("Leg") and not o.name.startswith("Trunk")
    ]
    join_meshes(static, "ElephantBody")


def export(name: str) -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, f"{name}.glb")
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        export_apply=True,
        export_yup=True,
        export_materials="EXPORT",
    )
    mn = Vector((1e9, 1e9, 1e9))
    mx = Vector((-1e9, -1e9, -1e9))
    for obj in bpy.data.objects:
        if obj.type != "MESH":
            continue
        for corner in obj.bound_box:
            point = obj.matrix_world @ Vector(corner)
            mn = Vector((min(mn[i], point[i]) for i in range(3)))
            mx = Vector((max(mx[i], point[i]) for i in range(3)))
    print(f"ANIMAL OK {path} size={os.path.getsize(path)} bounds={tuple(round(v, 2) for v in mx - mn)}")


def preview(name: str) -> None:
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 24
    scene.cycles.use_denoising = False
    scene.render.resolution_x = 640
    scene.render.resolution_y = 480
    scene.render.filepath = f"/tmp/opencode/{name}_preview.png"
    camera_data = bpy.data.cameras.new("PreviewCam")
    camera = bpy.data.objects.new("PreviewCam", camera_data)
    scene.collection.objects.link(camera)
    camera.location = (4.2, -5.4, 2.6)
    direction = Vector((0.4, 0.0, 1.2)) - camera.location
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    scene.camera = camera
    sun_data = bpy.data.lights.new("PreviewSun", "SUN")
    sun_data.energy = 4.0
    sun = bpy.data.objects.new("PreviewSun", sun_data)
    sun.rotation_euler = (0.6, 0.2, 0.8)
    scene.collection.objects.link(sun)
    scene.world = bpy.data.worlds.new("PreviewWorld")
    scene.world.use_nodes = True
    scene.world.node_tree.nodes["Background"].inputs[0].default_value = (0.55, 0.65, 0.8, 1.0)
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(camera, do_unlink=True)
    bpy.data.objects.remove(sun, do_unlink=True)
    print(f"ANIMAL PREVIEW {scene.render.filepath}")


def main() -> None:
    reset()
    build_deer()
    export("deer")
    if os.environ.get("PREVIEW"):
        preview("deer")
    reset()
    build_elephant()
    export("elephant")
    if os.environ.get("PREVIEW"):
        preview("elephant")


if __name__ == "__main__":
    main()
