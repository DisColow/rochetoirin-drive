"""Kit de détails des maisons fait avec Blender, posé par build_buildings.py sur chaque ouverture et chaque toit
(affiché près de la caméra, par-dessus les textures des façades) :
 - fenetre : dormant, deux vantaux à petits-bois, vitrage, poignée (ouverture 1 × 1, mise à l'échelle) ;
 - fenetre_vr : idem + coffre et tablier de volet roulant à demi baissé ;
 - volet : volet battant ouvert, lames verticales, barres et écharpe, pentures (1 × 1, couleur d'instance) ;
 - porte : porte d'entrée à panneaux moulurés et imposte vitrée, poignée, seuil ;
 - garage : porte sectionnelle à rainures horizontales et hublots ;
 - marquise : auvent vitré sur consoles en fer forgé au-dessus de la porte ;
 - faitiere : 1 m de tuiles faîtières rondes (deux tuiles) ;
 - mitron : chapeau de cheminée (dalle sur plots + mitron en terre cuite) ;
 - antenne : antenne râteau sur mât haubané ;
 - parabole : antenne satellite sur console murale.
Repère (après export glTF) : x le long du mur, y en haut, +z vers l'extérieur (ouvertures : coin bas-gauche à l'origine,
taille 1 × 1).  Lancer avec le Python où bpy est installé :  <venv>/bin/python blender_maisons.py
Sorties : ../godot/assets/maisons/<nom>.glb"""
import math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
import bmesh
import mathutils
import blender_commerces
from blender_commerces import reset, mat, box, cyl, export, obj_from_bm

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "godot", "assets", "maisons")
blender_commerces.OUT = OUT


def B(c, s, m, bevel=0.0):
    """Pavé : c = (x, y_haut, z_extérieur) dans le repère du kit -> Blender (x, -z, y)."""
    return box("p", (c[0], -c[2], c[1]), (s[0], s[2], s[1]), m, bevel=bevel)


def M():
    return dict(
        bois=mat("menuiserie", (0.92, 0.92, 0.9), rough=0.45),
        verre=mat("vitrage", (0.1, 0.12, 0.14), metal=0.3, rough=0.05),
        couleur=mat("couleur", (0.6, 0.45, 0.3), rough=0.6),
        fer=mat("fer", (0.08, 0.08, 0.09), metal=0.6, rough=0.4),
        alu=mat("alu", (0.75, 0.76, 0.78), metal=0.7, rough=0.3),
        terre=mat("terre_cuite", (0.62, 0.32, 0.2), rough=0.7),
        beton=mat("beton_kit", (0.66, 0.65, 0.62), rough=0.85),
        blanc=mat("blanc_kit", (0.93, 0.93, 0.91), rough=0.5),
    )


def fenetre(name="fenetre", vr=False):
    reset(); m = M()
    t, d = 0.06, 0.07                                   # dormant : épaisseur vue, profondeur
    for c, s in (((0.5, t / 2, d / 2), (1, t, d)), ((0.5, 1 - t / 2, d / 2), (1, t, d)),
                 ((t / 2, 0.5, d / 2 + 0.003), (t, 1.0, d + 0.006)), ((1 - t / 2, 0.5, d / 2 + 0.003), (t, 1.0, d + 0.006))):
        B(c, s, m["bois"])
    # deux vantaux : cadres, petits-bois (3 carreaux chacun), vitrage légèrement en retrait
    for x0 in (t, 0.5):
        w = 0.5 - t
        xc = x0 + w / 2
        for c, s in (((xc, t + 0.025, 0.05), (w, 0.05, 0.04)), ((xc, 1 - t - 0.025, 0.05), (w, 0.05, 0.04)),
                     ((x0 + 0.025, 0.5, 0.053), (0.05, 1 - 2 * t, 0.046)), ((x0 + w - 0.025, 0.5, 0.053), (0.05, 1 - 2 * t, 0.046))):
            B(c, s, m["bois"])
        for k in (1, 2):
            B((xc, t + (1 - 2 * t) * k / 3, 0.055), (w - 0.06, 0.018, 0.02), m["bois"])
        B((xc, 0.5, 0.035), (w - 0.04, 1 - 2 * t - 0.04, 0.006), m["verre"])
    B((0.5 - 0.035, 0.5, 0.085), (0.015, 0.09, 0.02), m["alu"])          # crémone
    if vr:
        B((0.5, 1.07, 0.06), (1.08, 0.16, 0.2), m["blanc"], 0.01)           # coffre
        for k in range(9):                                                 # tablier à demi baissé (lames)
            B((0.5, 0.99 - k * 0.045, 0.13), (0.98, 0.04, 0.012), m["blanc"])
        for x in (0.02, 0.98):
            B((x, 0.5, 0.13), (0.03, 1.0, 0.03), m["blanc"])               # coulisses
    export(name)


def volet():
    reset(); m = M()
    n = 5
    for k in range(n):                                                     # lames verticales jointives
        x = (k + 0.5) / n
        B((x, 0.5, 0.017), (1 / n - 0.008, 1.0, 0.03), m["couleur"], 0.004)
    for y in (0.16, 0.84):                                                 # barres
        B((0.5, y, 0.042), (0.94, 0.09, 0.025), m["couleur"], 0.004)
    # écharpe en diagonale entre les barres
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    L = math.hypot(0.8, 0.62)
    for v in bm.verts:
        v.co.x *= L; v.co.y *= 0.022; v.co.z *= 0.08
    bmesh.ops.rotate(bm, verts=bm.verts, matrix=mathutils.Matrix.Rotation(math.atan2(0.62, 0.8), 3, "Y"))
    for v in bm.verts:
        v.co.x += 0.5; v.co.y -= 0.042; v.co.z += 0.5
    obj_from_bm(bm, "echarpe", m["couleur"])
    for y in (0.16, 0.84):                                                 # pentures noires
        B((0.25, y, 0.058), (0.5, 0.035, 0.008), m["fer"])
    export("volet")


def porte():
    reset(); m = M()
    t = 0.07
    for c, s in (((0.5, 1 - t / 2, 0.04), (1, t, 0.08)), ((t / 2, 0.5, 0.043), (t, 1, 0.086)), ((1 - t / 2, 0.5, 0.043), (t, 1, 0.086))):
        B(c, s, m["bois"])
    B((0.5, 0.42, 0.03), (1 - 2 * t, 0.84, 0.04), m["couleur"], 0.004)    # vantail
    for y0, y1 in ((0.08, 0.36), (0.42, 0.7)):                            # panneaux moulurés
        for x0, x1 in ((0.13, 0.47), (0.53, 0.87)):
            B(((x0 + x1) / 2, (y0 + y1) / 2, 0.055), (x1 - x0, y1 - y0, 0.012), m["couleur"], 0.006)
    B((0.5, 0.92, 0.02), (1 - 2 * t, 0.1, 0.006), m["verre"])             # imposte vitrée
    B((0.5, 0.86, 0.03), (1 - 2 * t, 0.025, 0.04), m["bois"])
    B((0.82, 0.46, 0.08), (0.12, 0.018, 0.03), m["alu"])                  # béquille
    B((0.82, 0.44, 0.065), (0.035, 0.09, 0.012), m["alu"])
    B((0.5, -0.02, 0.12), (1.2, 0.04, 0.3), m["beton"], 0.006)            # seuil
    export("porte")


def garage():
    reset(); m = M()
    B((0.5, 0.5, 0.02), (1, 1, 0.03), m["blanc"])
    for k in range(1, 5):
        B((0.5, k / 5, 0.04), (0.99, 0.018, 0.012), m["blanc"])           # joints des sections
        for j in range(4):
            B((0.5, (k - 0.5) / 5, 0.036), (0.99, 0.006, 0.004), m["blanc"])
    for j in range(4):
        B((0.2 + j * 0.2, 0.7, 0.04), (0.11, 0.07, 0.006), m["verre"])  # hublots
    export("garage")


def marquise():
    reset(); m = M()
    # auvent vitré incliné (1 m de large, 0,7 m de saillie), consoles en fer forgé
    bm = bmesh.new()
    pts = [(-0.05, 0.0, 0.0), (1.05, 0.0, 0.0), (1.05, 0.68, -0.14), (-0.05, 0.68, -0.14)]
    vs = [bm.verts.new((x, -z, y)) for x, z, y in [(p[0], p[1], p[2]) for p in pts]]
    bm.faces.new(vs)
    me = obj_from_bm(bm, "verre", m["verre"])
    me.modifiers.new("ep", "SOLIDIFY").thickness = 0.015
    for x in (0.0, 1.0):
        B((x, -0.06, 0.34), (0.03, 0.03, 0.68), m["fer"])
        # console en quart de cercle (segments)
        for k in range(6):
            a = math.pi / 2 * k / 6
            B((x, -0.06 - 0.3 * (1 - math.cos(a)) - 0.05, 0.3 * math.sin(a) + 0.02), (0.02, 0.06, 0.02), m["fer"])
    for z in (0.02, 0.66):
        B((0.5, -0.07 if z > 0.1 else 0.0, z), (1.1, 0.03, 0.03), m["fer"])
    export("marquise")


def faitiere():
    reset(); m = M()
    for k in range(2):                                                     # deux tuiles rondes par mètre
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=False, segments=10, radius1=0.13, radius2=0.115, depth=0.52)
        bmesh.ops.rotate(bm, verts=bm.verts, matrix=mathutils.Matrix.Rotation(math.pi / 2, 3, "Y"))
        # demi-cylindre : on écrase la moitié basse
        for v in bm.verts:
            v.co.z = max(v.co.z, 0.0) * 0.9
            v.co.x += 0.25 + k * 0.5
        o = obj_from_bm(bm, "tuile", m["terre"])
        o.modifiers.new("ep", "SOLIDIFY").thickness = 0.02
    B((0.5, 0.02, 0.0), (1.0, 0.04, 0.14), m["beton"])                   # embarrure (mortier)
    export("faitiere")


def mitron():
    reset(); m = M()
    for x in (-0.22, 0.22):
        for z in (-0.16, 0.16):
            B((x, 0.06, z), (0.06, 0.12, 0.06), m["beton"])
    B((0.0, 0.15, 0.0), (0.75, 0.06, 0.6), m["beton"], 0.01)              # dalle de couverture
    cyl("mitron", (0.0, 0.0, 0.33), 0.09, 0.3, m["terre"], n=10)
    cyl("mitron2", (0.0, 0.0, 0.5), 0.11, 0.06, m["terre"], n=10)
    export("mitron")


def antenne():
    reset(); m = M()
    cyl("mat", (0, 0, 1.2), 0.025, 2.4, m["alu"], n=8)
    # râteau : bôme le long de x, brins en travers, réflecteur
    cyl("bome", (0.0, 0, 2.3), 0.012, 1.6, m["alu"], n=6, axis="X")
    for k in range(9):
        x = -0.7 + k * 0.17
        cyl("brin", (x, 0, 2.3), 0.005, 0.5 - k * 0.03, m["alu"], n=4, axis="Y")
    for z in (2.15, 2.45):
        cyl("refl", (-0.8, 0, z), 0.005, 0.6, m["alu"], n=4, axis="Y")
    cyl("rateau2", (0.15, 0, 1.75), 0.01, 0.9, m["alu"], n=6, axis="X")
    for k in range(6):
        cyl("brin2", (-0.25 + k * 0.15, 0, 1.75), 0.004, 0.32, m["alu"], n=4, axis="Y")
    B((0, 0.05, 0), (0.3, 0.1, 0.3), m["fer"])
    export("antenne")


def parabole():
    reset(); m = M()
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=False, segments=20, radius1=0.32, radius2=0.03, depth=0.1)
    # axe du cône vers l'extérieur (-Y Blender), incliné vers le ciel
    bmesh.ops.rotate(bm, verts=bm.verts, matrix=mathutils.Matrix.Rotation(math.radians(90 - 28), 3, "X"))
    for v in bm.verts:
        v.co.y -= 0.42; v.co.z += 0.12
    o = obj_from_bm(bm, "plat", m["blanc"])
    o.modifiers.new("ep", "SOLIDIFY").thickness = 0.012
    B((0, 0.0, 0.2), (0.04, 0.04, 0.4), m["blanc"])                        # console
    B((0, 0.0, 0.02), (0.12, 0.2, 0.03), m["blanc"])
    B((0, 0.25, 0.62), (0.02, 0.02, 0.35), m["fer"])                       # bras de la tête
    B((0, 0.25, 0.8), (0.05, 0.05, 0.06), m["fer"])
    export("parabole")


def main():
    os.makedirs(OUT, exist_ok=True)
    fenetre(); fenetre("fenetre_vr", vr=True); volet(); porte(); garage(); marquise(); faitiere(); mitron()
    antenne(); parabole()


if __name__ == "__main__":
    main()
