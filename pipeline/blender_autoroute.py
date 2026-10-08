"""Équipements d'autoroute faits avec Blender (bpy) : glissière de sécurité (travée de 4 m), borne d'appel d'urgence
orange, panneau bleu sur deux poteaux (face = case de l'atlas des panneaux), panneau « sortie » à chevrons, auvent de
gare de péage (au-dessus de la chaussée, sans rien sur les voies), cabine de péage.
Lancer avec le Python où bpy est installé :  <venv>/bin/python blender_autoroute.py
Repère (après export glTF) : x le long de la route (travées) ou en largeur (panneaux), y en haut, +z vers la route.
Sorties : ../godot/assets/autoroute/<nom>.glb"""
import math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
import bmesh
import blender_commerces
from blender_commerces import reset, mat, box, cyl, plane, export, obj_from_bm

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "godot", "assets", "autoroute")
blender_commerces.OUT = OUT
GALVA = dict(col=(0.7, 0.72, 0.73), metal=0.5, rough=0.45)


def glissiere():
    """Travée de 4 m (légèrement mise à l'échelle en jeu) : lisse en W galvanisée à 0,6 m, poteaux en C tous les 2 m,
    écarteurs, catadioptre sur le premier poteau. +z (glTF) vers la chaussée."""
    reset()
    m = mat("galva", **GALVA)
    for x in (0.0, 2.0):
        box("poteau", (x, 0.16, 0.37), (0.1, 0.05, 0.74), m, bevel=0.004)
        box("ecarteur", (x, 0.09, 0.6), (0.07, 0.1, 0.22), m, bevel=0.004)
    bm = bmesh.new()
    prof = [(0.0, 0.445), (-0.025, 0.47), (-0.05, 0.51), (-0.05, 0.53), (-0.02, 0.57), (0.0, 0.6), (-0.02, 0.63),
            (-0.05, 0.67), (-0.05, 0.69), (-0.025, 0.73), (0.0, 0.755)]
    rows = []
    for x in (0.0, 4.0):
        rows.append([bm.verts.new((x, y + 0.04, z)) for y, z in prof])
    for j in range(len(prof) - 1):
        bm.faces.new([rows[0][j], rows[1][j], rows[1][j + 1], rows[0][j + 1]])
    bm.normal_update()
    o = obj_from_bm(bm, "lisse", m)
    md = o.modifiers.new("ep", "SOLIDIFY"); md.thickness = 0.004
    box("catadioptre", (0.05, -0.012, 0.6), (0.07, 0.01, 0.05), mat("catadioptre", (0.95, 0.55, 0.1), rough=0.3))
    export("glissiere")


def gba():
    """Glissière en béton adhérent (profil « New Jersey »), travée de 4 m, symétrique, 0,8 m de haut."""
    reset()
    m = mat("gba", (0.8, 0.79, 0.76), rough=0.9)
    prof = [(-0.3, 0.0), (-0.27, 0.075), (-0.14, 0.33), (-0.09, 0.8), (0.09, 0.8), (0.14, 0.33), (0.27, 0.075), (0.3, 0.0)]
    bm = bmesh.new()
    rows = [[bm.verts.new((x, y, z)) for y, z in prof] for x in (0.0, 4.0)]
    for j in range(len(prof) - 1):
        bm.faces.new([rows[0][j], rows[0][j + 1], rows[1][j + 1], rows[1][j]])
    bm.faces.new(rows[0][::-1]); bm.faces.new(rows[1])
    bm.normal_update()
    obj_from_bm(bm, "gba", m)
    export("gba")


def potence():
    """Potence de signalisation : mât à l'origine (bord droit), bras en treillis de 9 m vers -x (au-dessus des voies)."""
    reset()
    m = mat("galva", **GALVA)
    cyl("mat", (0, 0, 3.8), 0.22, 7.6, m, n=16)
    box("platine", (0, 0, 0.05), (0.8, 0.8, 0.1), mat("beton", (0.6, 0.6, 0.58), rough=0.85))
    for z in (6.2, 7.3):
        cyl("membrure", (-4.6, 0, z), 0.09, 9.4, m, n=10, axis="X")
    for k in range(9):
        x0 = -0.3 - k * 1.0
        cyl("montant", (x0, 0, 6.75), 0.04, 1.1, m, n=6)
        bm = bmesh.new()
        import mathutils
        bmesh.ops.create_cone(bm, cap_ends=True, segments=6, radius1=0.035, radius2=0.035, depth=1.48)
        bmesh.ops.rotate(bm, verts=bm.verts, matrix=mathutils.Matrix.Rotation(math.atan2(1.0, 1.1), 3, "Y"))
        for v in bm.verts:
            v.co.x += x0 - 0.5; v.co.z += 6.75
        obj_from_bm(bm, "diag", m)
    export("potence")


def panneau_haut():
    """Panneau 1 × 1 sans poteaux (potences, portiques) : caisson, face = case de l'atlas, haut à l'origine."""
    reset()
    box("caisson", (0, 0.05, -0.5), (1.0, 0.08, 1.0), mat("dos", (0.55, 0.57, 0.6), 0.6, 0.4), bevel=0.01)
    plane("face", (0, 0.008, -0.5), 1.0, 1.0, mat("panneau", (1, 1, 1), rough=0.35))
    for x in (-0.3, 0.3):
        box("attache", (x, 0.12, 0.05), (0.05, 0.05, 0.25), mat("galva", **GALVA))
    export("panneau_haut")


def rond():
    """Panneau rond (limitation de vitesse) Ø 0,9 m sur poteau : face = moitié gauche (carrée) de la case d'atlas."""
    reset()
    box("poteau", (0, 0.06, 1.15), (0.07, 0.07, 2.3), mat("galva", **GALVA))
    for name, y, mm, flip in (("face", -0.0, mat("panneau", (1, 1, 1), rough=0.35), False),
                              ("dos", 0.02, mat("dos", (0.55, 0.57, 0.6), 0.6, 0.4), True)):
        bm = bmesh.new()
        uv = bm.loops.layers.uv.new("UVMap")
        c = bm.verts.new((0, y, 2.3))
        ring = [bm.verts.new((0.45 * math.cos(a), y, 2.3 + 0.45 * math.sin(a)))
                for a in [2 * math.pi * k / 32 for k in range(32)]]
        for k in range(32):
            vs = [c, ring[(k + 1) % 32], ring[k]]
            if not flip:
                vs = [c, ring[k], ring[(k + 1) % 32]]
            f = bm.faces.new(vs)
            for lp in f.loops:
                x, z = lp.vert.co.x, lp.vert.co.z - 2.3
                lp[uv].uv = (0.5 + x / 0.9, 0.5 - z / 0.9)
        bm.normal_update()
        obj_from_bm(bm, name, mm)
    export("rond")


def grillage():
    """Clôture d'emprise : travée de 4 m, poteau vert à l'origine, grillage à mailles (trous découpés) de 1,8 m."""
    reset()
    v = mat("vert", (0.16, 0.3, 0.18), rough=0.6)
    cyl("poteau", (0, 0.03, 0.95), 0.03, 1.9, v, n=8)
    plane("treillis", (2.0, 0.0, 0.95), 4.0, 1.8, mat("treillis", (0.35, 0.42, 0.36), rough=0.6))
    export("grillage")


def absorbeur():
    """Absorbeur de choc au musoir : caisson jaune de 3 m, face avant à chevrons ; avant à l'origine, vers -x."""
    reset()
    box("corps", (-1.5, 0, 0.45), (3.0, 0.7, 0.9), mat("ilot", (0.95, 0.75, 0.1), rough=0.6), bevel=0.04)
    p = plane("face", (0.0, 0.0, 0.45), 0.7, 0.8, mat("chevrons", (1, 1, 1)))
    import mathutils
    p.rotation_euler = (0, 0, math.pi / 2)
    p.location = (0.01, 0, 0)
    export("absorbeur")


def borne_sos():
    reset()
    o = mat("orange", (0.95, 0.42, 0.04), rough=0.4)
    box("socle", (0, 0, 0.1), (0.5, 0.4, 0.2), mat("beton", (0.6, 0.6, 0.58), rough=0.85), bevel=0.02)
    box("corps", (0, 0, 0.75), (0.32, 0.26, 1.1), o, bevel=0.04)
    box("tete", (0, 0, 1.38), (0.42, 0.34, 0.16), o, bevel=0.04)
    plane("face", (0, -0.131, 0.95), 0.24, 0.3, mat("sos", (0.95, 0.95, 0.95)))
    box("combine", (0, -0.14, 0.7), (0.12, 0.04, 0.2), mat("noir", (0.05, 0.05, 0.05), rough=0.5), bevel=0.01)
    box("poteau", (0, 0.05, 1.9), (0.08, 0.08, 1.0), mat("galva", **GALVA))
    box("plaque", (0, -0.0, 2.35), (0.6, 0.04, 0.4), o, bevel=0.01)
    plane("plaque_face", (0, -0.022, 2.35), 0.56, 0.36, mat("sos", (0.95, 0.95, 0.95)))
    export("borne_sos")


def panneau_bleu():
    """Panneau de 1 × 1 (mis à l'échelle en jeu) : caisson bleu à bord blanc, face avant = case de l'atlas, deux
    poteaux galvanisés (hauteur sous panneau 2,2 m, mise à l'échelle avec le panneau)."""
    reset()
    m = mat("galva", **GALVA)
    box("caisson", (0, 0.04, 0.5), (1.0, 0.06, 1.0), mat("dos", (0.55, 0.57, 0.6), 0.6, 0.4), bevel=0.01)
    plane("face", (0, 0.008, 0.5), 1.0, 1.0, mat("panneau", (1, 1, 1), rough=0.35))
    for x in (-0.33, 0.33):
        box("poteau", (x, 0.1, -0.3), (0.06, 0.06, 1.6), m)
    export("panneau_bleu")


def peage():
    """Auvent de gare de péage (1 m de large, mis à l'échelle de la chaussée) à 5,5 m de haut sur deux piles hors des
    voies ; bandeau bleu et « PÉAGE »."""
    reset()
    w = mat("blanc", (0.9, 0.9, 0.88), 0.2, 0.45)
    box("toit", (0, 0, 6.2), (1.0, 9.0, 0.8), w, bevel=0.03)
    box("bande", (0, 0, 6.0), (1.02, 9.02, 0.3), mat("bande", (0.1, 0.25, 0.6), rough=0.4))
    for sx in (-0.5, 0.5):
        pass
    export("peage")


def pile_peage():
    reset()
    w = mat("blanc", (0.9, 0.9, 0.88), 0.2, 0.45)
    box("pile", (0, 0, 2.9), (0.8, 1.6, 5.8), w, bevel=0.06)
    box("cabine", (0, 0, 1.25), (1.4, 2.4, 2.5), mat("cabine", (0.85, 0.85, 0.82), 0.2, 0.5), bevel=0.05)
    for sy in (-1, 1):
        plane("vitre", (0, sy * 1.205, 1.6), 1.2, 1.0, mat("vitre", (0.1, 0.15, 0.2), 0.3, 0.05), facing=sy * -1)
    box("ilot", (0, 0, 0.12), (1.6, 6.0, 0.25), mat("ilot", (0.95, 0.75, 0.1), rough=0.6), bevel=0.05)
    export("pile_peage")


def chevron():
    """Balise de divergence (nez de bretelle) : panneau blanc à chevrons sur un poteau."""
    reset()
    box("poteau", (0, 0.05, 0.8), (0.07, 0.07, 1.6), mat("galva", **GALVA))
    box("plaque", (0, 0.0, 1.6), (0.6, 0.03, 0.6), mat("blanc", (0.95, 0.95, 0.93), rough=0.4), bevel=0.01)
    plane("face", (0, -0.016, 1.6), 0.56, 0.56, mat("chevrons", (1, 1, 1)))
    export("chevron")


def main():
    os.makedirs(OUT, exist_ok=True)
    for f in (glissiere, gba, borne_sos, panneau_bleu, panneau_haut, potence, rond, grillage, absorbeur, peage, pile_peage,
              chevron):
        f()


if __name__ == "__main__":
    main()
