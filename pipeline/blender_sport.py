"""Équipements des terrains de sport, faits avec Blender (bpy) : buts de foot avec filets, poteaux de rugby, filet de
tennis, panier de basket, mât d'éclairage, panneau de grillage, banc de touche couvert.
Lancer avec le Python où bpy est installé :  <venv>/bin/python blender_sport.py
Repère (après export glTF) : x en largeur, y en haut, z en profondeur ; origine au sol.
Sorties : ../godot/assets/sport/<nom>.glb"""
import math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
import bmesh
from blender_commerces import reset, mat, box, cyl, plane, obj_from_bm, export, MATS
import blender_commerces

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "godot", "assets", "sport")
blender_commerces.OUT = OUT

WHITE = dict(col=(0.92, 0.92, 0.9), metal=0.3, rough=0.35)


def tube(name, a, b, r, m, n=10):
    """Tube de a à b (Blender : x, y profondeur, z haut)."""
    import mathutils
    a = mathutils.Vector(a); b = mathutils.Vector(b)
    o = cyl(name, (0, 0, 0), r, (b - a).length, m, n=n)
    o.location = (a + b) / 2
    o.rotation_mode = "QUATERNION"
    o.rotation_quaternion = mathutils.Vector((0, 0, 1)).rotation_difference(b - a)
    return o


def net_plane(name, verts, m):
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    vs = [bm.verts.new(v) for v in verts]
    f = bm.faces.new(vs)
    for lp, v in zip(f.loops, verts):
        lp[uv].uv = (v[0] + v[1], v[2])
    return obj_from_bm(bm, name, m)


def but_foot():
    """But de football 7,32 × 2,44 m, filet tendu vers l'arrière (+y Blender = derrière le but)."""
    reset()
    w = mat("blanc", **WHITE)
    n = mat("filet", (0.95, 0.95, 0.95), rough=0.8)
    W, H, D = 7.32, 2.44, 2.0
    tube("poteau_g", (-W / 2, 0, 0), (-W / 2, 0, H), 0.06, w)
    tube("poteau_d", (W / 2, 0, 0), (W / 2, 0, H), 0.06, w)
    tube("barre", (-W / 2, 0, H), (W / 2, 0, H), 0.06, w)
    for sx in (-1, 1):
        tube("hauban", (sx * W / 2, 0, H), (sx * W / 2, D * 0.5, H * 0.7), 0.025, w, n=6)
        tube("pied", (sx * W / 2, D * 0.5, H * 0.7), (sx * W / 2, D, 0), 0.025, w, n=6)
    tube("barre_sol", (-W / 2, D, 0.02), (W / 2, D, 0.02), 0.025, w, n=6)
    net_plane("filet_haut", [(-W / 2, 0, H), (W / 2, 0, H), (W / 2, D * 0.5, H * 0.7), (-W / 2, D * 0.5, H * 0.7)], n)
    net_plane("filet_fond", [(-W / 2, D * 0.5, H * 0.7), (W / 2, D * 0.5, H * 0.7), (W / 2, D, 0), (-W / 2, D, 0)], n)
    for sx in (-1, 1):
        net_plane("filet_cote", [(sx * W / 2, 0, 0), (sx * W / 2, 0, H), (sx * W / 2, D * 0.5, H * 0.7), (sx * W / 2, D, 0)], n)
    export("but_foot")


def poteaux_rugby():
    reset()
    w = mat("blanc", **WHITE)
    for sx in (-1, 1):
        tube("poteau", (sx * 2.8, 0, 0), (sx * 2.8, 0, 11.0), 0.08, w)
        box("protection", (sx * 2.8, 0, 1.0), (0.35, 0.35, 2.0), mat("protection", (0.1, 0.3, 0.7), rough=0.7), bevel=0.05)
    tube("barre", (-2.8, 0, 3.0), (2.8, 0, 3.0), 0.07, w)
    export("poteaux_rugby")


def filet_tennis():
    reset()
    m = mat("metal", (0.15, 0.3, 0.2), 0.6, 0.4)
    for sx in (-1, 1):
        tube("poteau", (sx * 6.4, 0, 0), (sx * 6.4, 0, 1.07), 0.04, m)
    net_plane("filet", [(-6.4, 0, 0.05), (6.4, 0, 0.05), (6.4, 0, 1.07), (-6.4, 0, 0.914)], mat("filet_noir", (0.05, 0.05, 0.05), rough=0.8))
    box("bande", (0, 0, 0.99), (12.8, 0.03, 0.07), mat("blanc", **WHITE))
    export("filet_tennis")


def panier_basket():
    reset()
    m = mat("metal", (0.2, 0.22, 0.25), 0.7, 0.4)
    tube("mat", (0, 1.2, 0), (0, 1.2, 3.2), 0.08, m)
    tube("bras", (0, 1.2, 3.2), (0, 0.15, 3.35), 0.06, m)
    box("planche", (0, 0.1, 3.4), (1.8, 0.05, 1.05), mat("blanc", **WHITE), bevel=0.02)
    box("carre", (0, 0.07, 3.3), (0.59, 0.02, 0.45), mat("rouge", (0.8, 0.1, 0.05)))
    bm = bmesh.new()
    bmesh.ops.create_circle(bm, cap_ends=False, radius=0.23, segments=16)
    for v in bm.verts:
        v.co.y -= 0.18; v.co.z += 3.05
    o = obj_from_bm(bm, "cercle", mat("orange", (0.95, 0.4, 0.05), 0.5, 0.4))
    md = o.modifiers.new("ep", "SKIN")
    export("panier_basket")


def mat_eclairage():
    reset()
    m = mat("metal", (0.55, 0.57, 0.6), 0.8, 0.35)
    tube("mat", (0, 0, 0), (0, 0, 18.0), 0.18, m, n=12)
    box("tete", (0, -0.2, 18.4), (2.6, 0.4, 1.4), m, bevel=0.04)
    for i in range(3):
        for j in range(2):
            plane("projecteur", (-0.85 + i * 0.85, -0.42, 17.95 + j * 0.8), 0.7, 0.6, mat("projecteur", (1, 1, 0.95)))
    export("mat_eclairage")


def grillage():
    """Panneau de grillage de 3 m × 3 m (courts de tennis) : poteaux, lisses, grillage vert (motif en jeu)."""
    reset()
    m = mat("metal", (0.15, 0.3, 0.2), 0.6, 0.4)
    tube("poteau", (-1.5, 0, 0), (-1.5, 0, 3.0), 0.035, m, n=8)
    tube("lisse_h", (-1.5, 0, 2.98), (1.5, 0, 2.98), 0.025, m, n=6)
    tube("lisse_b", (-1.5, 0, 0.05), (1.5, 0, 0.05), 0.025, m, n=6)
    net_plane("grillage", [(-1.5, 0, 0.05), (1.5, 0, 0.05), (1.5, 0, 2.98), (-1.5, 0, 2.98)], mat("grillage", (0.1, 0.3, 0.15), rough=0.6))
    export("grillage")


def banc_touche():
    reset()
    m = mat("metal", (0.6, 0.62, 0.64), 0.8, 0.35)
    box("abri", (0, 0.4, 1.1), (4.0, 0.06, 2.2), mat("plexi", (0.2, 0.35, 0.5), 0.2, 0.1), bevel=0.02)
    box("toit", (0, -0.2, 2.2), (4.1, 1.3, 0.06), mat("plexi", (0.2, 0.35, 0.5), 0.2, 0.1), bevel=0.02)
    box("banc", (0, 0.15, 0.45), (3.8, 0.4, 0.08), mat("rouge", (0.7, 0.1, 0.08)), bevel=0.02)
    for sx in (-1.95, 1.95):
        box("cote", (sx, -0.2, 1.1), (0.06, 1.3, 2.2), mat("plexi", (0.2, 0.35, 0.5), 0.2, 0.1))
    export("banc_touche")


def main():
    os.makedirs(OUT, exist_ok=True)
    for f in (but_foot, poteaux_rugby, filet_tennis, panier_basket, mat_eclairage, grillage, banc_touche):
        f()


if __name__ == "__main__":
    main()
