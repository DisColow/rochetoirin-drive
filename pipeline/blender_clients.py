"""Clients du taxi : pack « Low Poly Characters (PACK) » de micaelsampaio (Sketchfab, CC BY 4.0), téléchargé dans
../godot/import/clients/ (fetch_clients.py). Les 4 personnages (un objet chacun) sont séparés,
mis à 1,70 m, centrés, pieds à y = 0, de face vers −Y Blender (+Z en jeu).
Sorties : ../godot/assets/clients/client<k>.glb.   <venv>/bin/python blender_clients.py"""
import os
import bpy
import mathutils

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "godot", "import", "clients", "scene.gltf")
OUT = os.path.join(HERE, "..", "godot", "assets", "clients")
H = 1.70


def bbox(objs):
    V = [o.matrix_world @ v.co for o in objs for v in o.data.vertices]
    return (mathutils.Vector([min(v[i] for v in V) for i in range(3)]),
            mathutils.Vector([max(v[i] for v in V) for i in range(3)]))


def main():
    os.makedirs(OUT, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=SRC)
    for o in list(bpy.data.objects):
        if o.type == "MESH":
            mw = o.matrix_world.copy(); o.parent = None; o.matrix_world = mw
    for o in list(bpy.data.objects):
        if o.type != "MESH":
            bpy.data.objects.remove(o, do_unlink=True)
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    for o in meshes:
        o.modifiers.clear()
    # un objet par personnage, rangés de gauche à droite
    meshes.sort(key=lambda o: o.matrix_world.translation.x + sum((o.matrix_world @ v.co).x for v in o.data.vertices[:50]))
    groups = [[o] for o in meshes]
    for k, g in enumerate(groups):
        o = g[0]
        bpy.ops.object.select_all(action="DESELECT")
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        a, b = bbox([o])
        s = H / (b.z - a.z)
        o.data.transform(mathutils.Matrix.Scale(s, 4))
        a, b = bbox([o])
        o.data.transform(mathutils.Matrix.Translation((-(a.x + b.x) / 2, -(a.y + b.y) / 2, -a.z)))
        o.location = (0, 0, 0)
        for other in bpy.data.objects:
            other.hide_set(other != o)
        bpy.ops.object.select_all(action="DESELECT"); o.select_set(True)
        bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "client%d.glb" % k), export_format="GLB",
                                  use_selection=True, export_apply=True)
        print("client", k, len(o.data.polygons), "faces")


if __name__ == "__main__":
    main()
