"""Essences de la végétation du bourg : classement des houppiers détectés sur l'orthophoto, appris sur des végétaux
reconnus à l'œil dans Street View (data/veg_labels.json : id du houppier -> classe).

Classes : C sapin / épicéa / pin, T thuya / cyprès (haies et colonnes), L laurier / photinia / persistant à larges
feuilles, F grand feuillu, P petit arbre / fruitier / arbre d'ornement, B arbuste caduc / buisson.
Caractéristiques (orthophoto 20 cm, disque du houppier) : couleur moyenne, luminance et contraste, part de pixels
sombres, rayon, allongement de la tache verte (une haie est une bande), indice de vert.
"""
import json, os
import numpy as np
from scipy import ndimage as ndi

HERE = os.path.dirname(os.path.abspath(__file__))
CLASSES = "CTLFPB"


def features(v, cands):
    img = v.img
    res = v.res
    out = []
    for x, z, t, h in cands:
        r = max(0.6, min(6.0, (h - 1.8) / 1.2 if h < 3.6 else (h - 3.0) / 3.0))
        i, j = int((x - v.x0) / res), int((z - v.z0) / res)
        R = int(max(3, r / res))
        a = img[max(0, j - R):j + R + 1, max(0, i - R):i + R + 1]
        if a.size == 0:
            out.append(np.zeros(12)); continue
        yy, xx = np.mgrid[:a.shape[0], :a.shape[1]]
        m = (yy - a.shape[0] / 2) ** 2 + (xx - a.shape[1] / 2) ** 2 <= R * R
        p = a[m]
        L = p.mean(axis=1)
        exg = 2 * p[:, 1] - p[:, 0] - p[:, 2]
        # allongement de la tache verte locale (fenêtre de 8 m, masque à 0,5 m)
        ci, cj = int((x - v.x0) / v.c), int((z - v.z0) / v.c)
        w = v.tree[max(0, cj - 8):cj + 9, max(0, ci - 8):ci + 9]
        lab, n = ndi.label(w)
        el = 1.0
        if n:
            k = lab[min(8, lab.shape[0] - 1), min(8, lab.shape[1] - 1)] or (np.bincount(lab.ravel())[1:].argmax() + 1)
            ys, xs = np.nonzero(lab == k)
            if len(xs) > 3:
                ev = np.linalg.eigvalsh(np.cov(np.vstack([xs, ys])))
                el = float(np.sqrt(max(ev[1], 1e-3) / max(ev[0], 1e-3)))
        out.append(np.array([p[:, 0].mean(), p[:, 1].mean(), p[:, 2].mean(), L.mean(), L.std(), (L < 70).mean(),
                             exg.mean(), r, min(el, 8.0), h, (p[:, 2] > p[:, 0]).mean(), np.percentile(L, 90)]))
    return np.array(out)


def train_predict(v, cands, labels):
    from sklearn.ensemble import RandomForestClassifier
    from sklearn.model_selection import cross_val_score
    X = features(v, cands)
    ids = [int(k) for k in labels]
    y = np.array([CLASSES.index(labels[str(k)]) for k in ids])
    clf = RandomForestClassifier(n_estimators=300, min_samples_leaf=2, class_weight="balanced", random_state=1)
    acc = cross_val_score(clf, X[ids], y, cv=5).mean()
    clf.fit(X[ids], y)
    pred = clf.predict(X)
    for k, c in zip(ids, y):
        pred[k] = c                                   # vus dans Street View : classe relevée
    return [CLASSES[p] for p in pred], acc


class Species:
    """Essence de chaque houppier : relevée sur Street View si le végétal y est vu, sinon celle des voisins relevés
    (haies et plantations homogènes par propriété : 64 % d'accord avec le plus proche voisin), compatible avec la taille."""

    TREES, SMALL = set("FCP"), set("BLT")

    def __init__(self):
        p = os.path.join(HERE, "veg_labels.json")
        self.lab = {int(k): v for k, v in json.load(open(p)).items()} if os.path.exists(p) else {}
        self.pos = {}

    def register(self, idx, x, z):
        if idx in self.lab:
            self.pos[idx] = (x, z)

    def classify(self, idx, x, z, r, dark):
        if idx in self.lab:
            return self.lab[idx]
        ok = self.TREES if r >= 2.2 else (self.SMALL if r < 1.2 else set("FPBLTC"))
        votes = {}
        for k, (px, pz) in self.pos.items():
            c = self.lab[k]
            d = ((px - x) ** 2 + (pz - z) ** 2) ** 0.5
            if d < 15 and c in ok:
                votes[c] = votes.get(c, 0) + 1 / (1 + d)
        if dark and r >= 1.2 and "C" in ok:
            votes["C"] = votes.get("C", 0) + 0.3
        if votes:
            return max(votes, key=votes.get)
        if r >= 2.6:
            return "C" if dark else "F"
        return "P" if r >= 1.4 else ("T" if dark else "B")


_POINTS = None


def labeled_points():
    """[(x, z, classe)] des végétaux relevés sur Street View (positions des houppiers de l'orthophoto)."""
    global _POINTS
    if _POINTS is None:
        p = os.path.join(HERE, "veg_labels.json")
        lab = {int(k): v for k, v in json.load(open(p)).items()} if os.path.exists(p) else {}
        from prepare_village import Village
        raw = Village().trees(lambda x, z, r: False, raw=True) if lab else []
        _POINTS = [(raw[k][0], raw[k][1], c) for k, c in lab.items() if k < len(raw)]
    return _POINTS


def hedge_kind(x, z, radius=12.0):
    """'T' (thuyas) ou 'L' (lauriers, photinias) d'après les haies relevées à proximité, sinon None."""
    v = {}
    for px, pz, c in labeled_points():
        if c in "TL":
            d = ((px - x) ** 2 + (pz - z) ** 2) ** 0.5
            if d < radius:
                v[c] = v.get(c, 0) + 1 / (1 + d)
    return max(v, key=v.get) if v else None
