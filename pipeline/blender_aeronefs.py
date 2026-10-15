"""Aéronefs du ciel (fetch_aeronefs.py, issue #46) : import glTF, taille réelle, nez vers -Y de Blender (+Z dans Godot),
centrés. Les pièces qui tournent restent des objets à part, l'origine en leur centre : « rotor » (rotor principal de
l'hélicoptère, axe vertical) et « helice » (hélice de l'avion, rotor de queue : axe donné par AXES). Le reste est
fusionné en « corps ». Textures ramenées à 512 px. Sortie : ../godot/assets/aeronefs/<nom>.glb.
<venv>/bin/python blender_aeronefs.py"""
import math, os
import bpy
import mathutils

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "godot", "import", "aeronefs")
OUT = os.path.join(HERE, "..", "godot", "assets", "aeronefs")
# nom : (longueur réelle en m, rotation autour de Z pour mettre le nez vers -Y, {morceau du nom d'objet : rôle})
MODELES = {
    "tourisme": (8.3, 0.0, {"fan grey": "helice", "pointy head": "helice"}),
    "ligne": (36.0, 0.0, {}),
    "helico": (12.8, math.pi / 2, {"Propeller_2": "rotor", "Propeller_Palette": "helice_q"}),
    "planeur": (6.6, 0.0, {}),
}

def bornes(objs):
    V = [o.matrix_world @ v.co for o in objs for v in o.data.vertices]
    mn = mathutils.Vector([min(v[i] for v in V) for i in range(3)])
    mx = mathutils.Vector([max(v[i] for v in V) for i in range(3)])
    return mn, mx

def joindre(objs, nom):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    o.name = nom
    return o

os.makedirs(OUT, exist_ok=True)
for nom, (longueur, rz, roles) in MODELES.items():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, nom, "scene.gltf"))
    for o in list(bpy.data.objects):
        if o.type == "MESH":
            mw = o.matrix_world.copy(); o.parent = None; o.matrix_world = mw
    for o in list(bpy.data.objects):
        if o.type != "MESH":
            bpy.data.objects.remove(o, do_unlink=True)
    objs = [o for o in bpy.data.objects]
    # orientation et échelle (longueur = étendue le long de Y une fois le nez vers -Y)
    for o in objs:
        o.matrix_world = mathutils.Matrix.Rotation(rz, 4, "Z") @ o.matrix_world
    mn, mx = bornes(objs)
    s = longueur / (mx.y - mn.y)
    c = (mn + mx) / 2
    for o in objs:
        o.matrix_world = mathutils.Matrix.Scale(s, 4) @ mathutils.Matrix.Translation(-c) @ o.matrix_world
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    groupes = {}
    for o in objs:
        r = next((v for k, v in roles.items() if k in o.name), "corps")
        groupes.setdefault(r, []).append(o)
    for r, lst in groupes.items():
        o = joindre(lst, r)
        if r != "corps":
            bpy.ops.object.origin_set(type="ORIGIN_GEOMETRY", center="BOUNDS")
    mn, mx = bornes([o for o in bpy.data.objects])
    print(nom, "taille", [round(v, 1) for v in (mx - mn)], {o.name: (len(o.data.polygons), [round(v, 2) for v in o.location]) for o in bpy.data.objects})
    for im in bpy.data.images:
        if im.size[0] > 512:
            im.scale(512, max(1, 512 * im.size[1] // im.size[0]))
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, nom + ".glb"), export_format="GLB",
                              export_image_format="JPEG", export_apply=True)
