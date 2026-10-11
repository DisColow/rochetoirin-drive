"""Village de Rochetoirin modélisé d'après l'orthophotographie IGN (BD ORTHO 20 cm, Licence Ouverte).

Données : data/ortho_village.jpg (tools/fetch_ortho.py). Couvre le bourg et la rue du Balcon.

À partir de la photo aérienne :
  * couleur réelle de chaque toit (médiane des pixels sous l'emprise BD TOPO) ;
  * arbres, arbustes et haies à leur vraie place (houppiers détectés : position, diamètre → hauteur,
    conifères sombres vs feuillus) — remplacent les arbres générés au hasard dans cette zone ;
  * piscines (forme, orientation) ;
  * cours et allées en enrobé/gravier vs pelouses autour des maisons.
"""
import json, math, os
import numpy as np
from PIL import Image
from scipy import ndimage as ndi
from shapely.geometry import Polygon, Point

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "data")
T_OAK, T_BUSH, T_POPLAR, T_CONIFER, T_FRUIT, T_SHRUB = range(6)


class Village:
    def __init__(self):
        meta = json.load(open(os.path.join(DATA, "ortho_village.json")))
        self.x0, self.x1, self.z0, self.z1, self.res = meta["x0"], meta["x1"], meta["z0"], meta["z1"], meta["res"]
        self.img = np.asarray(Image.open(os.path.join(DATA, "ortho_village.jpg"))).astype(np.float32)
        # analyse à 0,5 m
        f = int(round(0.5 / self.res))
        h, w = self.img.shape[0] // f * f, self.img.shape[1] // f * f
        a = self.img[:h, :w].reshape(h // f, f, w // f, f, 3).mean(axis=(1, 3))
        self.c = 0.5
        R, G, B = a[..., 0], a[..., 1], a[..., 2]
        L = (R + G + B) / 3
        exg = 2 * G - R - B
        sat = a.max(axis=2) - a.min(axis=2)
        self.pool = (B > R + 35) & (B > G - 5) & (L > 90)
        self.pool = ndi.binary_opening(self.pool, iterations=1)
        # houppiers : verts, pas trop clairs et texturés (ombres internes) ; une pelouse est lisse
        mu = ndi.uniform_filter(L, 5)
        sd = np.sqrt(np.maximum(ndi.uniform_filter(L * L, 5) - mu * mu, 0))
        tree = (exg > 10) & (L < 130) & (sd > 9) & ~self.pool
        self.tree = ndi.binary_closing(ndi.binary_opening(tree, iterations=1), iterations=2)
        self.dark = (L < 75) & (exg > 8)
        self.paved = (sat < 20) & (L > 120) & (sd < 12) & ~self.tree
        self.L = L

    # ------------------------------------------------------------------ repères
    def contains(self, x, z, m=0.0):
        return self.x0 + m <= x <= self.x1 - m and self.z0 + m <= z <= self.z1 - m

    def rect(self):
        return Polygon([(self.x0, self.z0), (self.x1, self.z0), (self.x1, self.z1), (self.x0, self.z1)])

    def _ij(self, x, z, res):
        return int((x - self.x0) / res), int((z - self.z0) / res)

    # ------------------------------------------------------------------ toits
    def roof_color(self, poly):
        """Couleur médiane du toit (pixels à 25 cm sous l'emprise rétrécie), ou None."""
        if not self.contains(poly.centroid.x, poly.centroid.y, 2):
            return None
        q = poly.buffer(-0.8)
        if q.is_empty:
            q = poly
        mnx, mnz, mxx, mxz = q.bounds
        i0, j0 = self._ij(mnx, mnz, self.res); i1, j1 = self._ij(mxx, mxz, self.res)
        i0, j0 = max(i0, 0), max(j0, 0)
        i1, j1 = min(i1, self.img.shape[1] - 1), min(j1, self.img.shape[0] - 1)
        if i1 <= i0 or j1 <= j0:
            return None
        from shapely import vectorized
        xs = self.x0 + (np.arange(i0, i1) + 0.5) * self.res
        zs = self.z0 + (np.arange(j0, j1) + 0.5) * self.res
        X, Z = np.meshgrid(xs, zs)
        m = vectorized.contains(q, X, Z)
        px = self.img[j0:j1, i0:i1][m]
        if len(px) < 20:
            return None
        Lp = px.mean(axis=1)
        px = px[(Lp > 45) & (Lp < 235)]        # ni ombres portées ni reflets
        if len(px) < 20:
            return None
        c = np.median(px, axis=0) / 255.0
        # l'orthophoto est voilée de bleu : on classe le toit (tuile ou gris) et on recolore
        # dans une gamme réaliste en gardant la clarté et la nuance mesurées
        lum = float(c.mean()); red = float(c[0] - (c[1] + c[2]) / 2)
        if red > 0.05:
            tone = float(np.clip((red - 0.05) / 0.2, 0, 1))
            base = np.array([0.58, 0.40, 0.33]) * (1 - tone) + np.array([0.78, 0.40, 0.24]) * tone
            c = np.clip(base * np.clip(lum / 0.52, 0.65, 1.3), 0, 1)
        else:
            c = np.clip(np.array([lum, lum, lum * 1.03]) * 0.95, 0.05, 0.95)
        return tuple(float(v) for v in c)

    # ------------------------------------------------------------------ arbres
    def trees(self, blocked, raw=False):
        """[(x, z, type, hauteur)] ; blocked(x, z, rayon) -> True si l'emplacement est interdit (route, maison, haie).
        Essences d'après Street View (vegetation.Species) ; raw=True : types bruts (indices des houppiers inchangés)."""
        d = ndi.distance_transform_edt(self.tree) * self.c        # rayon local du houppier (m)
        out = []
        taken = np.zeros_like(self.tree)
        # du plus gros au plus petit houppier, avec suppression des voisins
        peaks = (d == ndi.maximum_filter(d, size=5)) & (d >= 0.6)
        js, is_ = np.nonzero(peaks)
        order = np.argsort(-d[js, is_])
        cands = []
        for k in order:
            j, i = js[k], is_[k]
            if taken[j, i]:
                continue
            r = float(d[j, i])
            x = self.x0 + (i + 0.5) * self.c; z = self.z0 + (j + 0.5) * self.c
            rr = int(max(2, r * 1.5 / self.c))
            taken[max(0, j - rr):j + rr + 1, max(0, i - rr):i + rr + 1] = True
            conifer = self.dark[max(0, j - 2):j + 3, max(0, i - 2):i + 3].mean() > 0.6
            cands.append((x, z, r, conifer, i, j))
        if raw:
            for x, z, r, conifer, i, j in cands:
                if r < 1.4:
                    t, h = (T_BUSH if r < 1.1 else T_SHRUB), 1.8 + r * 1.2
                elif conifer:
                    t, h = T_CONIFER, min(18.0, 3.0 + r * 3.2)
                elif r < 2.6:
                    t, h = T_FRUIT, 3.0 + r * 1.6
                else:
                    t, h = T_OAK, min(24.0, 3.0 + r * 3.0)
                if not blocked(x, z, r):
                    out.append((x, z, t, h))
            return out
        from vegetation import Species
        sp = Species()
        for idx, (x, z, r, conifer, i, j) in enumerate(cands):
            sp.register(idx, x, z)
        self.species_count = {}
        for idx, (x, z, r, conifer, i, j) in enumerate(cands):
            if blocked(x, z, r):
                continue
            cls = sp.classify(idx, x, z, r, conifer)
            self.species_count[cls] = self.species_count.get(cls, 0) + 1
            if cls == "X":
                continue                                   # fausse détection (pelouse) vue sur Street View
            rng_ = (i * 7919 + j * 104729) % 100
            # modèles 3D (Poly Haven, CC0) en imposteurs : type = 6 + modèle + (rayon / hauteur) / 2
            if cls == "T":                                 # thuya / cyprès : colonne dense (cône procédural)
                out.append((x, z, T_CONIFER, 2.0 + r * 2.4))
                continue
            if cls == "F":
                h, model = (min(24.0, 3.0 + r * 3.0) if r >= 2.0 else 4.0 + r * 2.5), (0 if rng_ < 65 else 1)
            elif cls == "P":
                h, model = 3.0 + r * 1.6, (2 if rng_ < 50 else (1 if rng_ < 80 else 3))
            elif cls == "C":
                h, model = min(20.0, 4.0 + r * 3.4), (6 if rng_ < 70 else 7)
            elif cls == "L" and r >= 1.3:
                h, model = 1.8 + r * 1.3, 4                # grand laurier, photinia : persistant dense (modèle 3D)
            elif cls == "L":                               # petit laurier taillé : boule dense
                out.append((x, z, T_BUSH, 1.6 + r * 1.2))
                continue
            else:                                          # arbuste de jardin : boule dense (procédural)
                out.append((x, z, T_BUSH if r < 1.1 else T_SHRUB, max(1.2, 1.0 + r * 1.1)))
                continue
            out.append((x, z, 6 + model + min(0.49, r / h / 2), h))
        return out

    # ------------------------------------------------------------------ piscines
    def pools(self):
        lab, n = ndi.label(self.pool)
        out = []
        for k, sl in enumerate(ndi.find_objects(lab), 1):
            m = lab[sl] == k
            area = m.sum() * self.c * self.c
            if area < 7 or area > 160:
                continue
            js, is_ = np.nonzero(m)
            pts = [(self.x0 + (sl[1].start + i + 0.5) * self.c, self.z0 + (sl[0].start + j + 0.5) * self.c) for j, i in zip(js, is_)]
            mp = Polygon(pts).convex_hull if len(pts) >= 3 else None
            if mp is None or mp.area < 5:
                continue
            fill_ratio = area / mp.area
            round_ = fill_ratio < 0.86 and abs(mp.length ** 2 / (4 * math.pi * mp.area) - 1) < 0.25
            out.append((mp.minimum_rotated_rectangle if not round_ else mp, round_))
        return out

    # ------------------------------------------------------------------ sol
    def landcover(self, cl, X0, Z0, res, zone, GARDEN, YARD, MEADOW, FOREST=None):
        """Dans la zone habitée : enrobé/gravier (cours, allées) ou pelouse, cellule par cellule (res m)."""
        from shapely import vectorized
        f = int(round(res / self.c))
        h, w = self.paved.shape[0] // f, self.paved.shape[1] // f
        paved = self.paved[:h * f, :w * f].reshape(h, f, w, f).mean(axis=(1, 3))
        treec = self.tree[:h * f, :w * f].reshape(h, f, w, f).mean(axis=(1, 3))
        xs = self.x0 + (np.arange(w) + 0.5) * res; zs = self.z0 + (np.arange(h) + 0.5) * res
        X, Z = np.meshgrid(xs, zs)
        inz = vectorized.contains(zone, X, Z)
        n = 0
        for j in range(h):
            for i in range(w):
                ci = int((X[j, i] - X0) / res); cj = int((Z[j, i] - Z0) / res)
                if not (0 <= cj < cl.shape[0] and 0 <= ci < cl.shape[1]):
                    continue
                # sous-bois de la BD TOPO là où la photo ne montre plus d'arbres (coupe, jardin)
                if FOREST is not None and cl[cj, ci] == FOREST and treec[j, i] < 0.15:
                    cl[cj, ci] = GARDEN if inz[j, i] else MEADOW
                    continue
                if not inz[j, i]:
                    continue
                if cl[cj, ci] not in (MEADOW, GARDEN):       # parkings et cours déjà connus : inchangés
                    continue
                cl[cj, ci] = YARD if paved[j, i] > 0.6 and treec[j, i] < 0.3 else GARDEN
                n += 1
        return n
