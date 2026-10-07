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
GALVA = dict(col=(0.62, 0.64, 0.66), metal=0.85, rough=0.35)


def glissiere():
    """Travée de 1 m (mise à l'échelle en jeu, 4 m d'ordinaire) : poteau à l'origine, lisse ondulée vers +x."""
    reset()
    m = mat("galva", **GALVA)
    box("poteau", (0, 0.12, 0.38), (0.1, 0.06, 0.76), m, bevel=0.005)
    # lisse en W : profil ondulé extrudé le long de x
    bm = bmesh.new()
    prof = [(-0.0, 0.46), (-0.05, 0.52), (-0.0, 0.58), (-0.05, 0.64), (-0.0, 0.70), (-0.05, 0.76)]
    prof = [(y, z) for y, z in [(0.0, 0.45), (-0.06, 0.52), (0.0, 0.6), (-0.06, 0.68), (0.0, 0.75)]]
    rows = []
    for x in (0.0, 1.0):
        rows.append([bm.verts.new((x, y, z)) for y, z in prof])
    for j in range(len(prof) - 1):
        bm.faces.new([rows[0][j], rows[1][j], rows[1][j + 1], rows[0][j + 1]])
    bm.normal_update()
    o = obj_from_bm(bm, "lisse", m)
    md = o.modifiers.new("ep", "SOLIDIFY"); md.thickness = 0.004
    box("ecarteur", (0, 0.05, 0.6), (0.08, 0.12, 0.2), m, bevel=0.005)
    export("glissiere")


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
    for f in (glissiere, borne_sos, panneau_bleu, peage, pile_peage, chevron):
        f()


if __name__ == "__main__":
    main()
