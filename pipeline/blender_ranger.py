"""Voiture du joueur : Ford Ranger Raptor 2019 (David_Holiday, CC BY 4.0, fetch_ranger.py) noir, avec un couvercle de
benne blanc (plateau rigide posé sur les ridelles, ajouté ici). Conversion au format de la voiture du jeu :
  - échelle réelle, origine au sol au milieu de l'empattement, avant vers -Z (glTF), droite +X ;
  - matériaux renommés d'après car.gd (paint, plastic, rubber, glass, chrome, lamp, tail, cover) ;
  - roues retirées de la caisse : la roue avant droite devient wheel.glb (centrée, face extérieure vers +X) ;
  - maillage allégé pour le téléphone (Decimate sur les grosses pièces).
Lancer avec le Python où bpy est installé :  <venv>/bin/python blender_ranger.py
Sorties : ../godot/assets/car/{body,wheel}.glb + meta.json"""
import json, math, os
import bpy, bmesh
import mathutils

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "godot", "import", "ranger", "scene.gltf")
OUT = os.path.join(HERE, "..", "godot", "assets", "car")
S = 0.30                               # unités du modèle -> mètres (longueur 5,4 m, largeur 2,2 m, hauteur 1,72 m)
GROUND = 0.56                          # bas des pneus (unités du modèle)
AXLE_Y = 5.6                           # essieux à ±5,6 (unités du modèle, +Y = avant dans Blender)
WHEEL_Z = 1.44                         # centre des roues
MATS = {"material": "paint", "preto__spec": "plastic", "Matte__FFFFF": "plastic", "Color_I11": "plastic",
        "FrontColor": "plastic", "preto_fosco": "plastic", "Color_008": "rubber", "black__spec": "chrome",
        "vidrogeral": "glass", "vidffron__sp": "glass", "lanterna__sp": "tail", "material_11": "lamp"}
TARGET_FACES = 45000                   # caisse ; roue : 2 500


def bbox(o):
    pts = [o.matrix_world @ mathutils.Vector(c) for c in o.bound_box]
    return ([min(p[i] for p in pts) for i in range(3)], [max(p[i] for p in pts) for i in range(3)])


def is_wheel(o):
    mn, mx = bbox(o)
    c = [(a + b) / 2 for a, b in zip(mn, mx)]
    side = mn[0] > 1.7 or mx[0] < -1.7
    return side and abs(abs(c[1]) - AXLE_Y) < 0.6 and abs(c[2] - WHEEL_Z) < 0.5 \
        and mx[1] - mn[1] < 2.6 and mx[2] - mn[2] < 2.6


def mat(name, col, metal=0.0, rough=0.5, alpha=1.0):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*col, 1.0)
    b.inputs["Metallic"].default_value = metal
    b.inputs["Roughness"].default_value = rough
    b.inputs["Alpha"].default_value = alpha
    return m


def join(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = name
    return o


def decimate(o, faces):
    n = len(o.data.polygons)
    if n > faces:
        md = o.modifiers.new("dec", "DECIMATE")
        md.ratio = faces / n
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.modifier_apply(modifier="dec")


def export(objs, path):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                              export_apply=True)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=SRC)
    new = {"paint": mat("paint", (0.012, 0.012, 0.014), 0.0, 0.3), "plastic": mat("plastic", (0.03, 0.03, 0.034)),
           "rubber": mat("rubber", (0.03, 0.03, 0.035), 0.0, 0.9), "chrome": mat("chrome", (0.8, 0.8, 0.82), 1.0, 0.15),
           "glass": mat("glass", (0.04, 0.05, 0.06), 0.2, 0.05, 0.55), "tail": mat("tail", (0.7, 0.03, 0.03), 0.0, 0.2),
           "lamp": mat("lamp", (0.85, 0.88, 0.9), 0.5, 0.1), "cover": mat("cover", (0.85, 0.86, 0.86), 0.0, 0.35)}
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    for o in meshes:
        for s in o.material_slots:
            if s.material:
                s.material = new[MATS.get(s.material.name.split(".")[0], "plastic")]
    # ridelles de la benne (peinture à l'arrière de la cabine) : couvercle blanc posé dessus
    bed = [o.matrix_world @ v.co for o in meshes if not is_wheel(o) and o.material_slots and o.material_slots[0].material == new["paint"]
           for v in o.data.vertices]
    bed = [p for p in bed if -8.6 < p.y < -4.2]
    top = max(p.z for p in bed)
    xin = max(abs(p.x) for p in bed if p.z > top - 0.4) * 0.93
    ys = [p.y for p in bed if p.z > top - 0.4]
    y0, y1 = min(ys) + 0.15, max(ys) - 0.05
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = mathutils.Vector((v.co.x * 2 * xin, (y0 + y1) / 2 + v.co.y * (y1 - y0), top + 0.06 + v.co.z * 0.12))
    cm = bpy.data.meshes.new("couvercle"); bm.to_mesh(cm); bm.free()
    cover = bpy.data.objects.new("couvercle", cm); cm.materials.append(new["cover"])
    bpy.context.scene.collection.objects.link(cover)
    print("couvercle : y %.2f..%.2f, x ±%.2f, z %.2f (unités du modèle)" % (y0, y1, xin, top))
    # roues : avant droite -> wheel.glb, les autres supprimées
    wheels = [o for o in meshes if is_wheel(o)]
    fr = [o for o in wheels if bbox(o)[0][0] > 0 and bbox(o)[0][1] > 0]
    wc = mathutils.Vector((sum((bbox(o)[0][0] + bbox(o)[1][0]) / 2 for o in fr) / len(fr), AXLE_Y, WHEEL_Z))
    wmn = [min(bbox(o)[0][i] for o in fr) for i in range(3)]; wmx = [max(bbox(o)[1][i] for o in fr) for i in range(3)]
    wc = mathutils.Vector(((wmn[0] + wmx[0]) / 2, (wmn[1] + wmx[1]) / 2, (wmn[2] + wmx[2]) / 2))
    radius = (wmx[2] - wmn[2]) / 2 * S
    for o in wheels:
        if o not in fr:
            bpy.data.objects.remove(o)
    body = [o for o in meshes if o not in wheels] + [cover]
    # caisse : mise à l'échelle, origine au sol au milieu de l'empattement
    for o in body + fr:
        o.select_set(False)
    for o in body + fr:
        if o.parent:
            mw = o.matrix_world.copy(); o.parent = None; o.matrix_world = mw
    b = join(body, "caisse")
    b.data.transform(b.matrix_world); b.matrix_world = mathutils.Matrix()
    b.data.transform(mathutils.Matrix.Translation((0, 0, -GROUND)))
    b.data.transform(mathutils.Matrix.Scale(S, 4))
    decimate(b, TARGET_FACES)
    w = join(fr, "roue")
    w.data.transform(w.matrix_world); w.matrix_world = mathutils.Matrix()
    w.data.transform(mathutils.Matrix.Translation(-wc))
    w.data.transform(mathutils.Matrix.Scale(S, 4))
    decimate(w, 2500)
    for o in list(bpy.context.scene.objects):
        if o not in (b, w):
            bpy.data.objects.remove(o)
    os.makedirs(OUT, exist_ok=True)
    export([w], os.path.join(OUT, "wheel.glb"))
    export([b], os.path.join(OUT, "body.glb"))
    track = 2 * wc.x * S
    # repère du jeu (meta) : x à droite, avant vers -Z ; steer/eye en x « conducteur à gauche » (car.gd inverse x)
    meta = {"steer": [-0.40, 1.22, -0.55], "eye": [-0.40, 1.52, -0.05], "wheelbase": round(2 * AXLE_Y * S, 3),
            "track": round(track, 3), "radius": round(radius, 3), "wheel_center": [0.0, 0.0, 0.0],
            "box": [1.9, 1.25, 5.2], "box_y": 1.0, "beams": [0.72, 0.95, 2.62],
            "model": "Ford Ranger Raptor 2019 (David_Holiday, CC BY 4.0), noir, couvercle de benne blanc"}
    json.dump(meta, open(os.path.join(OUT, "meta.json"), "w"))
    print("caisse", len(b.data.polygons), "faces ; roue", len(w.data.polygons), "faces ;", meta)


main()
