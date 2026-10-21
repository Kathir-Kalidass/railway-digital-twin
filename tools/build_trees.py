"""Build leafy tree/bush models for the Godot twin.

The bundled Libre-TrainSim tree assets reference missing leaf textures, so we
generate self-contained low-poly foliage in Blender and export compact GLBs.

Run: blender -b -P tools/build_trees.py
Out: godot/assets/models/trees/{oak,pine,birch,bush}.glb
"""
import math
import os
import random

import bpy
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "godot", "assets", "models", "trees")


def reset(seed: int) -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.unit_settings.system = "METRIC"
    random.seed(seed)


def material(name, color, roughness=0.9, metallic=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    return mat


def _finish(obj, mat, smooth=True):
    obj.data.materials.append(mat)
    if smooth:
        bpy.ops.object.shade_smooth()


def cylinder(name, radius_top, radius_bottom, height, location, mat, rotation=(0, 0, 0), vertices=12):
    bpy.ops.mesh.primitive_cone_add(
        vertices=vertices,
        radius1=radius_bottom,
        radius2=radius_top,
        depth=height,
        location=location,
    )
    obj = bpy.context.object
    obj.name = name
    obj.rotation_euler = rotation
    _finish(obj, mat)
    return obj


def cone(name, radius, height, location, mat, vertices=14):
    bpy.ops.mesh.primitive_cone_add(vertices=vertices, radius1=radius, radius2=0.02, depth=height, location=location)
    obj = bpy.context.object
    obj.name = name
    _finish(obj, mat)
    return obj


def blob(name, radius, location, mat, squash=0.85):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=radius, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = (1.0, 1.0, squash)
    for vert in obj.data.vertices:
        vert.co += Vector(
            (
                random.uniform(-0.12, 0.12) * radius,
                random.uniform(-0.12, 0.12) * radius,
                random.uniform(-0.12, 0.12) * radius,
            )
        )
    _finish(obj, mat)
    return obj


def add_bush(name, location, scale, mat):
    root = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(root)
    root.location = location
    for i in range(5):
        angle = i * 1.257
        blob(
            f"{name}Blob{i}",
            0.45 * scale * random.uniform(0.8, 1.15),
            (math.cos(angle) * 0.35 * scale, math.sin(angle) * 0.35 * scale, 0.45 * scale),
            mat,
            squash=0.7,
        ).parent = root
    return root


def build_oak():
    bark = material("OakBark", (0.20, 0.12, 0.06), 0.95)
    leaf = material("OakLeaf", (0.035, 0.10, 0.02), 0.9)
    leaf_light = material("OakLeafLight", (0.06, 0.15, 0.035), 0.88)
    cylinder("Trunk", 0.18, 0.34, 3.6, (0.0, 0.0, 1.8), bark, vertices=14)
    for index in range(5):
        angle = index * math.tau / 5.0 + 0.4
        length = random.uniform(1.5, 2.4)
        branch = cylinder(
            f"Branch{index}",
            0.05,
            0.18,
            length,
            (math.cos(angle) * length * 0.3, math.sin(angle) * length * 0.3, 3.1 + index * 0.28),
            bark,
            rotation=(random.uniform(0.7, 1.2), 0.0, angle),
            vertices=8,
        )
        branch.rotation_mode = "XYZ"
    canopy_center = Vector((0.0, 0.0, 5.4))
    for index in range(16):
        angle = index * math.tau / 16.0 * 3.0
        radius = random.uniform(0.7, 1.9)
        offset = Vector(
            (
                math.cos(angle) * random.uniform(0.0, 2.0),
                math.sin(angle) * random.uniform(0.0, 2.0),
                random.uniform(-1.0, 1.5),
            )
        )
        blob(f"Leaf{index}", radius, canopy_center + offset, leaf if index % 3 else leaf_light)
    for index in range(6):
        angle = random.uniform(0, math.tau)
        blob(
            f"LowLeaf{index}",
            random.uniform(0.6, 1.1),
            (math.cos(angle) * random.uniform(1.5, 2.6), math.sin(angle) * random.uniform(1.5, 2.6), random.uniform(3.2, 4.3)),
            leaf,
        )


def build_pine():
    bark = material("PineBark", (0.24, 0.14, 0.07), 0.95)
    needle = material("PineNeedle", (0.02, 0.07, 0.03), 0.92)
    needle_light = material("PineNeedleLight", (0.03, 0.10, 0.04), 0.9)
    cylinder("Trunk", 0.10, 0.28, 7.6, (0.0, 0.0, 3.8), bark, vertices=12)
    for index in range(8):
        radius = 2.8 - index * 0.3
        cone(
            f"Needles{index}",
            radius,
            2.4,
            (0.0, 0.0, 1.8 + index * 0.85),
            needle if index % 2 else needle_light,
        )


def build_birch():
    bark = material("BirchBark", (0.82, 0.80, 0.72), 0.9)
    leaf = material("BirchLeaf", (0.06, 0.16, 0.035), 0.9)
    cylinder("Trunk", 0.10, 0.20, 5.2, (0.0, 0.0, 2.6), bark, vertices=12)
    for index in range(12):
        angle = index * math.tau / 12.0 * 2.0
        blob(
            f"Leaf{index}",
            random.uniform(0.7, 1.2),
            (
                math.cos(angle) * random.uniform(0.2, 1.7),
                math.sin(angle) * random.uniform(0.2, 1.7),
                random.uniform(3.6, 6.0),
            ),
            leaf,
        )


def join_all():
    meshes = [obj for obj in bpy.data.objects if obj.type == "MESH"]
    for obj in meshes:
        with bpy.context.temp_override(
            active_object=obj,
            selected_editable_objects=[obj],
            selected_objects=[obj],
            object=obj,
        ):
            bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    if len(meshes) > 1:
        with bpy.context.temp_override(
            active_object=meshes[0],
            selected_editable_objects=meshes,
            selected_objects=meshes,
        ):
            bpy.ops.object.join()


def export(name: str) -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, f"{name}.glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_apply=True, export_yup=True)
    print(f"TREE OK {path} {os.path.getsize(path)} bytes")


def main() -> None:
    for name, builder in (("oak", build_oak), ("pine", build_pine), ("birch", build_birch)):
        reset(hash(name) % 1000)
        builder()
        join_all()
        export(name)
    reset(7)
    bush = material("BushLeaf", (0.03, 0.09, 0.02), 0.92)
    add_bush("Bush", (0.0, 0.0, 0.0), 1.0, bush)
    join_all()
    export("bush")


if __name__ == "__main__":
    main()
