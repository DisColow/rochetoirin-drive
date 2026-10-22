"""Panorama lointain allégé (#124 étape 2) : godot/world/far/pano.glb (relief à 500 m sur ±75 km, 173 000 triangles
d'un seul tenant : ses niveaux de détail ne s'appliquent jamais, la caméra est toujours dans sa boîte) simplifié par
contraction d'arêtes à erreur quadrique (pyfqmr : garde les crêtes et la silhouette des Alpes, enlève les plaines),
bords conservés (trou des environs, limite à 75 km). UV recalculés (fonction linéaire de x, z), normales recalculées.
Contrôle : silhouette de l'horizon vue de trois points de la carte, écart en degrés et en pixels (écran de 1280 px,
champ de 62°) entre le panorama complet et l'allégé.
À relancer après build_assets.py (qui réécrit pano.glb depuis data/dem/pano.npy) :
python3 alleger_pano.py [--cible=30000] [--essai] (--essai : mesure seulement, pano.glb inchangé)."""
import json, struct, sys
import numpy as np
import pyfqmr
from glb import write_glb

PANO = "../godot/world/far/pano.glb"
OBS = [(-126.0, 447.0, 59.0), (-10860.0, 240.0, -920.0), (-8411.0, 223.0, -7187.0)]   # Rochetoirin, Bourgoin, autoroute


def lire(path):
    b = open(path, "rb").read()
    L = struct.unpack("<I", b[12:16])[0]
    j = json.loads(b[20:20 + L])
    o = 20 + L
    bin_ = b[o + 8:o + 8 + struct.unpack("<I", b[o:o + 4])[0]]

    def acc(i, dt, n):
        a = j["accessors"][i]
        v = j["bufferViews"][a["bufferView"]]
        d = np.frombuffer(bin_, dt, a["count"] * n, v.get("byteOffset", 0) + a.get("byteOffset", 0))
        return d.reshape(-1, n) if n > 1 else d
    pr = j["meshes"][0]["primitives"][0]
    return (acc(pr["attributes"]["POSITION"], np.float32, 3).astype(np.float64), acc(pr["attributes"]["TEXCOORD_0"], np.float32, 2),
            acc(pr["indices"], np.uint32, 1).reshape(-1, 3), j["materials"][pr["material"]]["name"])


def normales(P, F):
    N = np.zeros_like(P)
    g = np.cross(P[F[:, 1]] - P[F[:, 0]], P[F[:, 2]] - P[F[:, 0]])
    for k in range(3):
        np.add.at(N, F[:, k], g)
    N[N[:, 1] < 0] *= -1.0
    return N / np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-9)


def silhouette(P, F, o, pas=0.1):
    """Hauteur angulaire maximale (degrés) de l'horizon par azimut (pas en degrés). Sur un maillage de triangles, le point
    le plus haut vu dans une direction est sur une arête : chaque arête est échantillonnée tous les 0,02° d'azimut."""
    E = np.unique(np.sort(np.concatenate([F[:, [0, 1]], F[:, [1, 2]], F[:, [0, 2]]]), axis=1), axis=0)
    A, B = P[E[:, 0]], P[E[:, 1]]
    za = np.degrees(np.arctan2(A[:, 0] - o[0], A[:, 2] - o[2]))
    zb = np.degrees(np.arctan2(B[:, 0] - o[0], B[:, 2] - o[2]))
    dz = np.abs((zb - za + 180.0) % 360.0 - 180.0)
    n = np.clip(np.ceil(dz / 0.02).astype(int) + 2, 2, 4000)
    idx = np.repeat(np.arange(len(E)), n)
    t = (np.arange(n.sum()) - np.repeat(np.cumsum(n) - n, n)) / np.repeat(n - 1, n)
    S = A[idx] + (B[idx] - A[idx]) * t[:, None]
    d = np.hypot(S[:, 0] - o[0], S[:, 2] - o[2])
    ok = d > 500.0
    az = np.degrees(np.arctan2(S[ok, 0] - o[0], S[ok, 2] - o[2])) % 360.0
    el = np.degrees(np.arctan2(S[ok, 1] - o[1], d[ok]))
    k = np.minimum((az / pas).astype(int), int(360 / pas) - 1)
    h = np.full(int(360 / pas), -90.0)
    np.maximum.at(h, k, el)
    return h


def main():
    cible = 30000
    for a in sys.argv[1:]:
        if a.startswith("--cible="):
            cible = int(a.split("=")[1])
    P, UV, F, nom = lire(PANO)
    # UV = fonction linéaire de x et z (orthophoto du panorama)
    A = np.c_[P[:, 0], P[:, 2], np.ones(len(P))]
    cu, ru = np.linalg.lstsq(A, UV[:, 0], rcond=None)[:2]
    cv, rv = np.linalg.lstsq(A, UV[:, 1], rcond=None)[:2]
    print("UV : écart max %.2e / %.2e" % (np.abs(A @ cu - UV[:, 0]).max(), np.abs(A @ cv - UV[:, 1]).max()))
    # erreur jugée en angle et non en mètres : hauteurs divisées par la distance au trou des environs (zone de jeu)
    # avant la simplification, remises ensuite (un mètre d'écart à 2 km se voit bien plus qu'à 60 km)
    c = P[F].mean(axis=1)                                  # cases de 500 m couvertes par des triangles
    g = np.floor((c[:, [0, 2]] + 75000.0) / 500.0).astype(int)
    plein = np.zeros((300, 300), bool)
    plein[g[:, 0], g[:, 1]] = True
    ti, tj = np.where(~plein)
    trou = (ti.min() * 500.0 - 75000.0, tj.min() * 500.0 - 75000.0, ti.max() * 500.0 - 74500.0, tj.max() * 500.0 - 74500.0)
    print("trou des environs : x %.0f..%.0f, z %.0f..%.0f" % (trou[0], trou[2], trou[1], trou[3]))

    def echelle(X):
        dx = np.maximum(np.maximum(trou[0] - X[:, 0], X[:, 0] - trou[2]), 0.0)
        dz = np.maximum(np.maximum(trou[1] - X[:, 2], X[:, 2] - trou[3]), 0.0)
        return 2000.0 / (np.hypot(dx, dz) + 2000.0)
    Pw = P.copy()
    Pw[:, 1] *= echelle(P)
    s = pyfqmr.Simplify()
    s.setMesh(Pw, F)
    s.simplify_mesh(target_count=cible, aggressiveness=7, preserve_border=True, verbose=0)
    P2, F2, _ = s.getMesh()
    P2 = np.asarray(P2, np.float64); F2 = np.asarray(F2, np.uint32)
    P2[:, 1] /= echelle(P2)
    print("triangles : %d -> %d, sommets %d -> %d" % (len(F), len(F2), len(P), len(P2)))
    pire = 0.0
    for o in OBS:
        h1, h2 = silhouette(P, F, o), silhouette(P2, F2, o)
        v = (h1 > -89) & (h2 > -89)
        e = np.abs(h1[v] - h2[v])
        pire = max(pire, float(e.max()))
        print("silhouette vue de (%.0f, %.0f) : écart moyen %.4f°, 99 %% sous %.4f°, pire %.4f° (%.2f px sur 1280 px / 62°)" % (
            o[0], o[2], e.mean(), np.percentile(e, 99), e.max(), e.max() * 1280 / 62))
    if "--essai" in sys.argv:
        return
    N2 = normales(P2, F2)
    A2 = np.c_[P2[:, 0], P2[:, 2], np.ones(len(P2))]
    UV2 = np.c_[A2 @ cu, A2 @ cv].astype(np.float32)
    write_glb(PANO, [(nom, P2.astype(np.float32), N2.astype(np.float32), UV2, F2.ravel())], fix_winding=True)
    print("écrit", PANO)


if __name__ == "__main__":
    main()
