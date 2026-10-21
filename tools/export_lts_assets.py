"""Export a Libre-TrainSim .blend to a compact GLB for the Godot twin.

Run with:  LTS_OUT=out.glb blender -b asset.blend -P tools/export_lts_assets.py
Optional env vars:
  LTS_SELECT  comma separated object names to export (default: whole file)
  LTS_MAXTEX  longest texture edge, default 512
"""
import os
import sys

import bpy

OUT = os.environ["LTS_OUT"]
SELECT = [n for n in os.environ.get("LTS_SELECT", "").split(",") if n]
MAXTEX = int(os.environ.get("LTS_MAXTEX", "512"))
TINTS = {}
for entry in os.environ.get("LTS_TINTS", "").split(";"):
    if "=" not in entry:
        continue
    name, values = entry.split("=", 1)
    try:
        TINTS[name.strip()] = [float(v) for v in values.split(",")[:3]]
    except ValueError:
        pass


def _strip_non_mesh_helpers() -> None:
    for obj in list(bpy.data.objects):
        if obj.type in {"CAMERA", "LIGHT", "SPEAKER"}:
            bpy.data.objects.remove(obj, do_unlink=True)


def _downscale_images() -> None:
    for image in bpy.data.images:
        try:
            width, height = image.size
        except (AttributeError, TypeError):
            continue
        if width <= 0 or height <= 0 or max(width, height) <= MAXTEX:
            continue
        factor = float(MAXTEX) / max(width, height)
        image.scale(max(1, int(width * factor)), max(1, int(height * factor)))


def _apply_tints() -> None:
    for mat in bpy.data.materials:
        rgb = TINTS.get(mat.name)
        if rgb is None:
            continue
        mat.diffuse_color = (*rgb, 1.0)
        if not mat.use_nodes:
            mat.use_nodes = True
        for node in mat.node_tree.nodes:
            if node.type == "BSDF_PRINCIPLED":
                socket = node.inputs["Base Color"]
                for link in list(socket.links):
                    mat.node_tree.links.remove(link)
                socket.default_value = (*rgb, 1.0)
                break


def main() -> None:
    _strip_non_mesh_helpers()
    _apply_tints()
    if not SELECT:
        for obj in list(bpy.data.objects):
            if obj.hide_get() or obj.hide_render:
                bpy.data.objects.remove(obj, do_unlink=True)
    _downscale_images()
    if SELECT:
        for obj in bpy.data.objects:
            obj.select_set(False)
        for name in SELECT:
            obj = bpy.data.objects.get(name)
            if obj is None:
                print(f"LTS EXPORT WARNING: missing object {name!r}")
                continue
            obj.hide_set(False)
            obj.hide_viewport = False
            obj.hide_render = False
            obj.select_set(True)
            bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(
        filepath=OUT,
        export_format="GLB",
        export_apply=True,
        use_selection=bool(SELECT),
        export_yup=True,
        export_materials="EXPORT",
        export_image_format="AUTO",
    )
    print(f"LTS EXPORT OK {OUT} {os.path.getsize(OUT)} bytes")


if __name__ == "__main__":
    sys.exit(main())
