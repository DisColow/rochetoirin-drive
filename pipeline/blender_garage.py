"""Pièces du garage (fetch_garage.py, issue #43) -> ../godot/assets/garage/<rubrique>_<n>.glb, calées dans le repère
de la voiture du joueur (Blender : x à gauche, y vers l'arrière, z en haut ; glTF/Godot : x, z, -y) :
  - ailerons S1-S5 : envergure 1,70 m, posés au bout de la benne (bas à 1,27 m, 2,60 m derrière le centre) ;
  - échappements E1-E4 : sortie de 0,30 m, deux exemplaires sous le pare-chocs arrière ;
  - jantes J1-J5 : roue complète, axe x, diamètre 1 m, centrée (tuning.gd la met à la taille de la roue) ; la J4 n'a
    pas de pneu : jante ramenée à 0,68 m et pneu ajouté.
Textures ramenées à 512 px.   <venv>/bin/python blender_garage.py"""
import math, os
import bpy
import mathutils

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "godot", "import", "garage")
OUT = os.path.join(HERE, "..", "godot", "assets", "garage")
# code : (sortie, garder(nom d'objet, centre) -> bool, matériaux retirés, axe de la longueur ou de la roue)
PIECES = {
    "S1": ("aileron_1", None, [], "x"), "S2": ("aileron_2", None, [], "x"),
    "S3": ("aileron_3", lambda n, c: n.startswith("Cube.018"), [], "x"),
    "S4": ("aileron_4", None, [], "x"), "S5": ("aileron_5", None, [], "x"),
    "E1": ("echappement_1", None, [], "y"), "E2": ("echappement_2", lambda n, c: c.x > -300, [], "y"),
    "E3": ("echappement_3", None, [], "x"), "E4": ("echappement_4", None, [], "x"),
    "J1": ("jantes_1", lambda n, c: n not in ("Object_3", "Object_6"), [], "x"),
    "J2": ("jantes_2", lambda n, c: "Stand" not in n, [], "y"),
    "J3": ("jantes_3", None, [], "x"),
    "J4": ("jantes_4", lambda n, c: n.startswith("Cube.001") or n.startswith("Cylinder"), [], "y"),
    "J5": ("jantes_5", lambda n, c: n != "Object_5", [], "y"),
}

def bornes(objs):
    V = [o.matrix_world @ v.co for o in objs for v in o.data.vertices]
    return (mathutils.Vector([min(v[i] for v in V) for i in range(3)]),
            mathutils.Vector([max(v[i] for v in V) for i in range(3)]))

def joindre(objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    return bpy.context.view_layer.objects.active

def transformer(o, m):
    o.matrix_world = m @ o.matrix_world
    bpy.ops.object.select_all(action="DESELECT"); o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

def mat(nom, c, rug, metal=0.0):
    m = bpy.data.materials.new(nom); m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*c, 1); b.inputs["Roughness"].default_value = rug
    b.inputs["Metallic"].default_value = metal
    return m

os.makedirs(OUT, exist_ok=True)
for code, (sortie, garder, _, axe) in PIECES.items():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, code, "scene.gltf"))
    for o in list(bpy.data.objects):
        if o.type == "MESH":
            mw = o.matrix_world.copy(); o.parent = None; o.matrix_world = mw
    for o in list(bpy.data.objects):
        if o.type != "MESH" or len(o.data.polygons) == 0:
            bpy.data.objects.remove(o, do_unlink=True)
            continue
        if garder:
            mn, mx = bornes([o])
            if not garder(o.name, (mn + mx) / 2):
                bpy.data.objects.remove(o, do_unlink=True)
    o = joindre(list(bpy.data.objects))
    # axe principal ramené sur x (envergure, longueur de la sortie, axe de la roue)
    if axe == "y":
        transformer(o, mathutils.Matrix.Rotation(math.pi / 2, 4, "Z"))
    mn, mx = bornes([o]); c = (mn + mx) / 2
    transformer(o, mathutils.Matrix.Translation(-c))
    mn, mx = bornes([o]); d = mx - mn
    if code.startswith("S"):
        s = 1.70 / d.x
        transformer(o, mathutils.Matrix.Scale(s, 4))
        mn, mx = bornes([o])
        transformer(o, mathutils.Matrix.Translation((0, 2.60, 1.27 - mn.z)))
    elif code.startswith("E"):
        s = 0.30 / d.x
        transformer(o, mathutils.Matrix.Scale(s, 4))
        # longueur vers l'arrière de la voiture (+y Blender), deux sorties
        transformer(o, mathutils.Matrix.Rotation(math.pi / 2, 4, "Z"))
        o2 = o.copy(); o2.data = o.data.copy(); bpy.context.collection.objects.link(o2)
        transformer(o, mathutils.Matrix.Translation((0.55, 2.78, 0.22)))
        transformer(o2, mathutils.Matrix.Translation((-0.55, 2.78, 0.22)))
        o = joindre([o, o2])
    else:
        dia = max(d.y, d.z)
        if code == "J4":
            transformer(o, mathutils.Matrix.Scale(0.68 / dia, 4))
            bpy.ops.mesh.primitive_torus_add(major_radius=0.42, minor_radius=0.085, major_segments=40, minor_segments=10,
                                             rotation=(0, math.pi / 2, 0))
            pneu = bpy.context.view_layer.objects.active
            transformer(pneu, mathutils.Matrix.Scale(1.0, 4) @ mathutils.Matrix.Diagonal((2.1, 1, 1, 1)))
            pneu.data.materials.append(mat("pneu", (0.03, 0.03, 0.035), 0.9))
            o = joindre([o, pneu])
        else:
            transformer(o, mathutils.Matrix.Scale(1.0 / dia, 4))
    mn, mx = bornes([o])
    print(code, sortie, "taille", [round(v, 2) for v in (mx - mn)], "centre", [round(v, 2) for v in (mn + mx) / 2], "faces", len(o.data.polygons))
    for im in bpy.data.images:
        if im.size[0] > 512:
            im.scale(512, max(1, 512 * im.size[1] // im.size[0]))
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, sortie + ".glb"), export_format="GLB",
                              export_image_format="JPEG", export_apply=True)
