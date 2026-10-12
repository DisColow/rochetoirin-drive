"""Assemble les vues des arbres (bake.js) en deux atlas pour le jeu.

trees_imp_col.webp : couleur (sRGB) + couverture ; trees_imp_nrm.webp : normale dans le repère du modèle + profondeur.
Une ligne par modèle, 8 colonnes = 8 directions de vue (0°, 45°, …), cellules de 256 px.
trees_imp.json : taille de cellule S, hauteur H (unités du modèle) par modèle.
"""
import json, math, os, sys
import numpy as np
from PIL import Image
from scipy.ndimage import distance_transform_edt

HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.environ.get("TREE_WORK", HERE)
ASSETS = os.path.join(HERE, "..", "..", "app", "src", "main", "assets")
# (dossier de bake, teinte du feuillage) ; dossier « modèle__nœud » pour une variante isolée d'un fichier
MODELS = [("island_tree_01", (0.80, 0.97, 0.85)), ("island_tree_02", (0.80, 0.97, 0.85)),
          ("island_tree_03", (0.80, 0.97, 0.85)), ("tree_small_02", (0.80, 0.97, 0.85)),
          ("searsia_lucida__searsia_lucida_a_LOD0", (0.78, 0.95, 0.80)), ("searsia_lucida__searsia_lucida_e_LOD0", (0.78, 0.95, 0.80)),
          ("fir_tree_01__fir_tree_01_a_LOD0", (0.55, 0.80, 0.62)), ("fir_tree_01__fir_tree_01_b_LOD0", (0.55, 0.80, 0.62))]
N, CELL = 8, 256


def down(a, w):
    """Réduction 2x pondérée par la couverture."""
    h2, w2 = a.shape[0] // 2, a.shape[1] // 2
    a4 = a.reshape(h2, 2, w2, 2, -1); w4 = w.reshape(h2, 2, w2, 2, 1)
    s = (a4 * w4).sum(axis=(1, 3)); ws = w4.sum(axis=(1, 3))
    return s / np.maximum(ws, 1e-6), ws[..., 0] / 4


col = np.zeros((CELL * len(MODELS), CELL * N, 4), np.uint8)
nrm = np.zeros_like(col)
info = []
for j, (m, tint) in enumerate(MODELS):
    o = json.load(open(os.path.join(WORK, "out", m, "info.json")))
    info.append(dict(name=m, S=o["S"], H=o["H"], R=o["R"]))
    for k in range(N):
        c = np.asarray(Image.open(os.path.join(WORK, "out", m, "col%d.png" % k))).astype(float) / 255
        n = np.asarray(Image.open(os.path.join(WORK, "out", m, "nrm%d.png" % k))).astype(float) / 255
        d = np.asarray(Image.open(os.path.join(WORK, "out", m, "dep%d.png" % k))).astype(float) / 255
        a = c[..., 3]
        # normale de vue -> repère du modèle (caméra en (sin θ, 0, cos θ), droite (cos θ, 0, -sin θ))
        th = 2 * math.pi * k / N
        nv = n[..., :3] * 2 - 1
        r = np.array([math.cos(th), 0, -math.sin(th)]); u = np.array([0, 1.0, 0]); f = np.array([math.sin(th), 0, math.cos(th)])
        nm = nv[..., :1] * r + nv[..., 1:2] * u + nv[..., 2:3] * f
        rgb = c[..., :3]
        # feuillage un peu plus vert (essences du Bas-Dauphiné plutôt que méditerranéennes)
        leaf = (rgb[..., 1] > rgb[..., 0] * 0.95) & (rgb[..., 1] > rgb[..., 2])
        rgb[leaf] *= np.array(tint)
        cc, cov = down(rgb, a); nn, _ = down(nm, a); dd, _ = down(d[..., :1], a)
        nn /= np.maximum(np.linalg.norm(nn, axis=2, keepdims=True), 1e-6)
        # couleurs prolongées sous les zones transparentes (pas de liseré sombre avec les mipmaps)
        hole = cov < 0.02
        if hole.any() and (~hole).any():
            _, (iy, ix) = distance_transform_edt(hole, return_indices=True)
            cc = cc[iy, ix]; nn = nn[iy, ix]; dd = dd[iy, ix]
        y0, x0 = j * CELL, k * CELL
        col[y0:y0 + CELL, x0:x0 + CELL, :3] = np.clip(cc * 255 + 0.5, 0, 255)
        col[y0:y0 + CELL, x0:x0 + CELL, 3] = np.clip(cov * 255 + 0.5, 0, 255)
        nrm[y0:y0 + CELL, x0:x0 + CELL, :3] = np.clip((nn * 0.5 + 0.5) * 255 + 0.5, 0, 255)
        nrm[y0:y0 + CELL, x0:x0 + CELL, 3] = np.clip(dd[..., 0] * 255 + 0.5, 0, 255)
Image.fromarray(col).save(os.path.join(ASSETS, "trees_imp_col.webp"), lossless=True, method=6)
Image.fromarray(nrm).save(os.path.join(ASSETS, "trees_imp_nrm.webp"), lossless=True, method=6)
json.dump(info, open(os.path.join(ASSETS, "trees_imp.json"), "w"), indent=1)
print(info)
