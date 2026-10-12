"""Vitrines et portes des commerces en aplat (v6.18, directive de l'utilisateur : docs/kb/aplats.md). Remplace les
modèles Blender en relief (blender_commerces.py : cadre saillant de 13 cm, intérieur creusé à 35 cm, 650 à 940
triangles) par des quads collés au mur (2 et 1,5 cm devant), mêmes noms de matériaux (cadre, socle, verre,
interieur, chrome : matériaux de shops.gd) et mêmes dimensions (1 m de large, 2,915 m de haut, mis à l'échelle par
instance) : une vitrine = 14 triangles. Les autres détails muraux (pilastre, coffre_rideau, porte_sectionnelle,
bardage, bandeau, enseigne, affiche) sont aplatis : chaque matériau devient un quad à 1–2 cm du mur, à l'emprise et
aux coordonnées de texture de sa face avant. Gardés en volume (structures extérieures) : banne, auvent, marquise,
lampes, terrasse, ombrière, totem, pompes… À lancer après blender_commerces.py (qui réécrit ces .glb).
Lancer depuis pipeline/ : python3 build_shops_plats.py"""
import json, struct
import numpy as np
from glb import write_glb

OUT = "../godot/assets/shops"
ZI, ZV = 0.015, 0.02          # intérieur peint, puis vitrage et cadre (aplats, sans épaisseur)


def quads(rects, z):
    """[(x0, y0, x1, y1)] -> positions, normales, uv, indices (face vers +z)."""
    P, U, I = [], [], []
    for x0, y0, x1, y1 in rects:
        o = len(P)
        P += [(x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z)]
        U += [(x0 + 0.5, 1 - y0 / 2.915), (x1 + 0.5, 1 - y0 / 2.915), (x1 + 0.5, 1 - y1 / 2.915), (x0 + 0.5, 1 - y1 / 2.915)]
        I += [o, o + 1, o + 2, o, o + 2, o + 3]
    P = np.array(P, np.float32)
    return P, np.tile([0, 0, 1.0], (len(P), 1)).astype(np.float32), np.array(U, np.float32), np.array(I, np.uint32)


def modele(nom, bas, socle_h, verre, chrome=None):
    prims = []
    for mat, rects, z in (("socle", [(-0.5, 0.0, 0.5, socle_h)], ZV),
                          ("cadre", [(-0.5, bas, -0.45, 2.915), (0.45, bas, 0.5, 2.915), (-0.45, verre[3], 0.45, 2.915),
                                     (-0.45, bas, 0.45, verre[1])], ZV),
                          ("interieur", [(-0.45, verre[1], 0.45, verre[3])], ZI),
                          ("verre", [verre], ZV)):
        prims.append((mat,) + quads(rects, z))
    if chrome:
        prims.append(("chrome",) + quads([chrome], ZV + 0.002))
    write_glb("%s/%s.glb" % (OUT, nom), prims, node_name=nom)
    print(nom, sum(len(p[4]) // 3 for p in prims), "triangles")


modele("vitrine", 0.4, 0.4, (-0.45, 0.44, 0.45, 2.86))
modele("porte", 0.04, 0.04, (-0.45, 0.2, 0.45, 2.85), chrome=(0.285, 0.75, 0.315, 1.45))


def lire(nom):
    """Primitives d'un .glb : [(matériau, positions, normales, uv)]."""
    b = open("%s/%s.glb" % (OUT, nom), "rb").read()
    n = struct.unpack("<I", b[12:16])[0]
    j = json.loads(b[20:20 + n]); data = b[20 + n + 8:]
    def acc(i, k):
        a = j["accessors"][i]; v = j["bufferViews"][a["bufferView"]]
        o = v.get("byteOffset", 0) + a.get("byteOffset", 0)
        return np.frombuffer(data[o:o + a["count"] * k * 4], np.float32).reshape(-1, k)
    out = []
    for m in j["meshes"]:
        for p in m["primitives"]:
            at = p["attributes"]
            out.append((j["materials"][p["material"]]["name"], acc(at["POSITION"], 3), acc(at["NORMAL"], 3),
                        acc(at["TEXCOORD_0"], 2) if "TEXCOORD_0" in at else None))
    return out


def aplatir(nom):
    """Chaque matériau -> un quad face au dehors (+z) à l'emprise (x, y) de sa face avant, uv repris aux coins."""
    prims = []
    for k, (mat, P, Nn, UV) in enumerate(lire(nom)):
        av = Nn[:, 2] > 0.5
        F = P[av] if av.sum() >= 3 else P
        x0, y0, x1, y1 = F[:, 0].min(), F[:, 1].min(), F[:, 0].max(), F[:, 1].max()
        if x1 - x0 < 1e-3 or y1 - y0 < 1e-3:
            continue
        def uv_coin(x, y):
            if UV is None:
                return ((x - x0) / (x1 - x0), 1 - (y - y0) / (y1 - y0))
            Q = P[av] if av.sum() >= 3 else P
            U = UV[av] if av.sum() >= 3 else UV
            i = np.argmin((Q[:, 0] - x) ** 2 + (Q[:, 1] - y) ** 2)
            return tuple(U[i])
        z = 0.01 + 0.002 * k
        Pq = np.array([(x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z)], np.float32)
        Uq = np.array([uv_coin(x0, y0), uv_coin(x1, y0), uv_coin(x1, y1), uv_coin(x0, y1)], np.float32)
        prims.append((mat, Pq, np.tile([0, 0, 1.0], (4, 1)).astype(np.float32), Uq, np.array([0, 1, 2, 0, 2, 3], np.uint32)))
    write_glb("%s/%s.glb" % (OUT, nom), prims, node_name=nom)
    print(nom, len(prims) * 2, "triangles (aplat)")


for nom in ("pilastre", "coffre_rideau", "porte_sectionnelle", "bardage", "bandeau", "enseigne", "affiche"):
    aplatir(nom)
