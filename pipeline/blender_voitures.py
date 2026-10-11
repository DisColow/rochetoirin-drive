"""Voitures garées (fetch_voitures.py, modèles Sketchfab CC BY) : import glTF, maillages fusionnés, longueur ramenée à
la taille réelle, avant vers +Y Blender (−Z en jeu, comme les anciens modèles procéduraux), centrées, roues à y = 0,
textures ramenées à 512 px. Matériaux renommés pour le jeu (props.gd) : carrosserie unie -> « paint » (teinte par
voiture), vitres -> « glass », pneus -> « rubber » ; les carrosseries texturées gardent leur texture.
Sorties : ../godot/assets/props/car<n>.glb, data/voitures_dims.json (longueur, largeur, hauteur).
<venv>/bin/python blender_voitures.py [--apercu]"""
import json, math, os, sys
import bpy
import mathutils

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "godot", "import", "voitures")
OUT = os.path.join(HERE, "..", "godot", "assets", "props")
# type (props.gd) : (dossier, longueur réelle, demi-tour pour mettre l'avant vers +Y, renommage des matériaux,
# largeur et hauteur réelles pour les modèles stylisés trop hauts, ou None)
CARS = {
    1: ("citadine", 3.75, True, {"Chassis": "paint", "Windows": "glass", "Tire": "rubber"}, (1.72, 1.48)),
    2: ("berline80", 4.05, True, {}, None),
    3: ("berline", 4.45, True, {"Chassis": "paint", "Windows": "glass", "Tire": "rubber"}, (1.78, 1.45)),
    4: ("compacte", 4.15, True, {"MAT_Windows": "glass"}, None),
}
FLIP = json.load(open(os.path.join(HERE, "data", "voitures_flip.json"))) if os.path.exists(os.path.join(HERE, "data", "voitures_flip.json")) else {}


def bbox(o):
    V = [o.matrix_world @ v.co for v in o.data.vertices]
    mn = mathutils.Vector([min(v[i] for v in V) for i in range(3)])
    mx = mathutils.Vector([max(v[i] for v in V) for i in range(3)])
    return mn, mx


def convert(t, folder, length, flip, ren, wh):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, folder, "scene.gltf"))
    for o in list(bpy.data.objects):
        if o.type == "MESH":
            mw = o.matrix_world.copy(); o.parent = None; o.matrix_world = mw
    for o in list(bpy.data.objects):
        if o.type != "MESH":
            bpy.data.objects.remove(o, do_unlink=True)
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    if len(meshes) > 1:
        bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    mn, mx = bbox(o)
    d = mx - mn
    # l'import glTF met déjà le haut selon Z ; longueur = plus grand des deux axes horizontaux, mise selon Y
    if d.x > d.y:
        o.data.transform(mathutils.Matrix.Rotation(math.pi / 2, 4, "Z"))
    if flip or FLIP.get(folder):
        o.data.transform(mathutils.Matrix.Rotation(math.pi, 4, "Z"))
    mn, mx = bbox(o); d = mx - mn
    s = length / d.y
    o.data.transform(mathutils.Matrix.Scale(s, 4))
    if wh:
        mn, mx = bbox(o); d = mx - mn
        o.data.transform(mathutils.Matrix.Diagonal((wh[0] / d.x, 1.0, wh[1] / d.z, 1.0)))
    mn, mx = bbox(o)
    o.data.transform(mathutils.Matrix.Translation((-(mn.x + mx.x) / 2, -(mn.y + mx.y) / 2, -mn.z)))
    mn, mx = bbox(o); d = mx - mn
    for m in o.data.materials:
        if m and m.name in ren:
            m.name = ren[m.name]
    for im in bpy.data.images:
        if im.size[0] > 512:
            im.scale(512, max(1, 512 * im.size[1] // im.size[0]))
    print("voiture", t, folder, [round(v, 2) for v in d], "faces", len(o.data.polygons),
          "matériaux", [m.name for m in o.data.materials if m])
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "car%d.glb" % t), export_format="GLB",
                              export_image_format="JPEG", export_apply=True)
    return dict(L=round(d.y, 2), W=round(d.x, 2), H=round(d.z, 2))


def main():
    os.makedirs(OUT, exist_ok=True)
    dims = {}
    for t, (folder, length, flip, ren, wh) in CARS.items():
        dims[t] = convert(t, folder, length, flip, ren, wh)
    json.dump(dims, open(os.path.join(HERE, "data", "voitures_dims.json"), "w"), indent=1)


if __name__ == "__main__":
    main()
