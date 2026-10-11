"""Animaux des prés faits avec Blender (bpy) : formes organiques en « metaballs » (corps, cou, tête, pattes)
converties en maillage lissé puis allégé. Vache (Montbéliarde, ~1,4 m au garrot), mouton, cheval.
Le pelage (taches, robes) et les mouvements (tête qui broute, queue) sont faits en jeu par le shader.
Lancer avec le Python où bpy est installé :  <venv>/bin/python blender_animaux.py
Repère (après export glTF) : avant vers +z, y en haut, origine au sol sous le milieu du corps.
Sorties : ../godot/assets/animaux/{vache,mouton,cheval,cloture}.glb"""
import math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
import mathutils
import blender_commerces
from blender_commerces import reset, mat, cyl, box, export

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "godot", "assets", "animaux")
blender_commerces.OUT = OUT


def meta(name, parts, res=0.04, decimate=0.12, m=None):
    """parts : (forme, centre (x, avant, haut) Blender, rayon, échelle xyz, rotation (degrés)) ; ellipsoïdes et
    capsules qui se chevauchent, fondus en une seule peau par remaillage en voxels, lissés puis allégés."""
    objs = []
    for t, c, r, sc, rot in parts:
        if t == "CAPSULE":
            # capsule le long de x local : longueur 2 × sc[0], rayon r
            bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=2 * sc[0], vertices=16)
            o = bpy.context.active_object
            o.rotation_euler = (0, math.radians(90), 0)
            bpy.ops.object.transform_apply(rotation=True)
            for sx in (-1, 1):
                bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=(sx * sc[0], 0, 0), segments=16, ring_count=8)
                objs.append(bpy.context.active_object)
            objs.append(o)
            grp = objs[-3:]
            bpy.ops.object.select_all(action="DESELECT")
            for g in grp:
                g.select_set(True)
            bpy.context.view_layer.objects.active = o
            bpy.ops.object.join()
            del objs[-3:]
            o = bpy.context.active_object
        else:
            bpy.ops.mesh.primitive_uv_sphere_add(radius=r, segments=24, ring_count=12)
            o = bpy.context.active_object
            o.scale = sc
        o.rotation_euler = mathutils.Euler([math.radians(v) for v in rot])
        o.location = c
        objs.append(o)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = name
    md = o.modifiers.new("peau", "REMESH"); md.mode = "VOXEL"; md.voxel_size = res
    sm = o.modifiers.new("lisse", "SMOOTH"); sm.factor = 0.8; sm.iterations = 6
    dc = o.modifiers.new("allege", "DECIMATE"); dc.ratio = decimate
    bpy.ops.object.convert(target="MESH")
    o.data.materials.clear()
    o.data.materials.append(m)
    return o


def vache():
    reset()
    m = mat("pelage", (0.8, 0.8, 0.8), rough=0.8)
    L = [
        ("ELLIPSOID", (0, 0, 1.0), 1.0, (0.36, 0.95, 0.42), (0, 0, 0)),          # corps
        ("ELLIPSOID", (0, -0.62, 1.08), 1.0, (0.34, 0.4, 0.42), (0, 0, 0)),      # épaules
        ("ELLIPSOID", (0, 0.62, 1.08), 1.0, (0.36, 0.38, 0.42), (0, 0, 0)),         # croupe
        ("CAPSULE", (0, -1.0, 1.12), 0.2, (0.28, 0.1, 0.1), (0, 25, 90)),          # cou
        ("ELLIPSOID", (0, -1.35, 1.0), 1.0, (0.17, 0.3, 0.2), (35, 0, 0)),        # tête
        ("ELLIPSOID", (0, -1.55, 0.86), 1.0, (0.15, 0.13, 0.12), (0, 0, 0)),          # mufle
        ("ELLIPSOID", (0, 0.42, 0.62), 1.0, (0.16, 0.14, 0.1), (0, 0, 0)),          # mamelle
    ]
    for x in (-0.28, 0.28):
        for y in (-0.7, 0.75):
            L.append(("CAPSULE", (x * 0.85, y, 0.45), 0.08, (0.4, 0.1, 0.1), (0, 90, 0)))   # pattes
    meta("vache", L, m=m)
    for x in (-0.12, 0.12):
        o = cyl("corne", (x * 1.5, -1.5, 1.32), 0.025, 0.14, mat("corne", (0.85, 0.82, 0.7), rough=0.5), n=6)
        o.rotation_euler = (0, math.radians(70 if x > 0 else -70), 0)
    o = cyl("queue", (0, 1.28, 0.85), 0.025, 0.7, m, n=6)
    o.rotation_euler = (math.radians(12), 0, 0)
    export("vache")


def mouton():
    reset()
    m = mat("pelage", (0.8, 0.8, 0.8), rough=0.9)
    L = [
        ("ELLIPSOID", (0, 0, 0.62), 1.0, (0.3, 0.48, 0.3), (0, 0, 0)),
        ("ELLIPSOID", (0, -0.36, 0.66), 1.0, (0.26, 0.24, 0.27), (0, 0, 0)),
        ("ELLIPSOID", (0, -0.6, 0.72), 1.0, (0.09, 0.17, 0.1), (30, 0, 0)),
    ]
    for x in (-0.15, 0.15):
        for y in (-0.33, 0.33):
            L.append(("CAPSULE", (x, y, 0.25), 0.04, (0.22, 0.1, 0.1), (0, 90, 0)))
    meta("mouton", L, res=0.03, m=m)
    export("mouton")


def cheval():
    reset()
    m = mat("pelage", (0.8, 0.8, 0.8), rough=0.6)
    L = [
        ("ELLIPSOID", (0, 0, 1.25), 1.0, (0.3, 0.85, 0.36), (0, 0, 0)),
        ("ELLIPSOID", (0, -0.55, 1.3), 1.0, (0.29, 0.38, 0.38), (0, 0, 0)),
        ("ELLIPSOID", (0, 0.58, 1.3), 1.0, (0.31, 0.36, 0.38), (0, 0, 0)),
        ("CAPSULE", (0, -0.85, 1.6), 0.16, (0.38, 0.1, 0.1), (0, 50, 90)),
        ("ELLIPSOID", (0, -1.2, 1.88), 1.0, (0.12, 0.32, 0.14), (50, 0, 0)),
    ]
    for x in (-0.22, 0.22):
        for y in (-0.62, 0.68):
            L.append(("CAPSULE", (x * 0.8, y, 0.55), 0.06, (0.5, 0.1, 0.1), (0, 90, 0)))
    meta("cheval", L, res=0.04, m=m)
    o = cyl("queue", (0, 1.15, 1.0), 0.05, 0.75, mat("crins", (0.1, 0.07, 0.05), rough=0.9), n=6)
    o.rotation_euler = (math.radians(15), 0, 0)
    export("cheval")


def cloture():
    """Travée de clôture de pâture de 1 m (étirée en jeu à la longueur de la travée) : 3 fils barbelés vers +x, en
    deux brins torsadés assez épais pour rester visibles à l'écran, pointes tous les 25 cm. Le piquet est un modèle à
    part (piquet), pour ne pas être élargi avec la travée."""
    reset()
    fm = mat("fil", (0.5, 0.5, 0.52), 0.45, 0.6)
    for z in (0.45, 0.8, 1.12):
        for dy in (-0.006, 0.006):
            box("fil", (0.5, dy, z + dy * 0.5), (1.0, 0.013, 0.013), fm)
        for k in range(4):
            x = 0.125 + 0.25 * k
            box("fil", (x, 0, z), (0.012, 0.05, 0.012), fm)
            box("fil", (x, 0, z), (0.012, 0.012, 0.05), fm)
    export("cloture")


def piquet():
    """Piquet de clôture en bois (Ø 10 cm, 1,3 m), posé au début de chaque travée."""
    reset()
    cyl("piquet", (0, 0, 0.62), 0.05, 1.3, mat("piquet", (0.38, 0.28, 0.18), rough=0.9), n=7)
    export("piquet")


def main():
    os.makedirs(OUT, exist_ok=True)
    for f in (vache, mouton, cheval, cloture, piquet):
        f()


if __name__ == "__main__":
    main()
