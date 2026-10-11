"""Soucoupe volante du gardien (fetch_ufo.py) : import glTF, mise à 12 m de diamètre, centrée, dessous à y = 0,
textures ramenées à 1024 px (couleur, métal/rugosité, émission des feux, normales).
Sortie : ../godot/assets/ufo/ufo.glb.   <venv>/bin/python blender_ufo.py"""
import os
import bpy
import mathutils

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "godot", "import", "ufo", "scene.gltf")
OUT = os.path.join(HERE, "..", "godot", "assets", "ufo")
DIAM = 12.0

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
meshes = sorted([o for o in bpy.data.objects if o.type == "MESH"], key=lambda o: -len(o.data.polygons))
for o in list(bpy.data.objects):
    if o.type == "MESH":
        mw = o.matrix_world.copy(); o.parent = None; o.matrix_world = mw
for o in list(bpy.data.objects):
    if o.type != "MESH":
        bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.object.select_all(action="DESELECT")
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
if len(meshes) > 1:
    bpy.ops.object.join()
o = bpy.context.view_layer.objects.active
V = [o.matrix_world @ v.co for v in o.data.vertices]
mn = mathutils.Vector([min(v[i] for v in V) for i in range(3)]); mx = mathutils.Vector([max(v[i] for v in V) for i in range(3)])
s = DIAM / max(mx.x - mn.x, mx.y - mn.y)
o.scale = (s, s, s); bpy.ops.object.transform_apply(scale=True)
V = [o.matrix_world @ v.co for v in o.data.vertices]
mn = mathutils.Vector([min(v[i] for v in V) for i in range(3)]); mx = mathutils.Vector([max(v[i] for v in V) for i in range(3)])
o.location = (-(mn.x + mx.x) / 2, -(mn.y + mx.y) / 2, -mn.z); bpy.ops.object.transform_apply(location=True)
print("soucoupe", [round(v, 2) for v in (mx - mn)], "faces", len(o.data.polygons))
for im in bpy.data.images:
    if im.size[0] > 1024:
        im.scale(1024, max(1, 1024 * im.size[1] // im.size[0]))
os.makedirs(OUT, exist_ok=True)
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "ufo.glb"), export_format="GLB", export_image_format="JPEG",
                          export_apply=True)
