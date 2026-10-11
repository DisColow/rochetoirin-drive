"""Arbres réels : détectés sur la hauteur de canopée LiDAR HD (IGN MNH, 1 m) — position, hauteur, largeur de couronne.
Essence : zones de végétation BD TOPO (feuillus, mixte, peupleraie, verger), couleur de l'orthophoto (conifères sombres
et bleutés), forme de la couronne (peuplier : haut et étroit), vergers de noyers (RPG « NOX »).
Les toits (bâtiments BD TOPO) et les chaussées sont exclus (le MNH mesure aussi les bâtiments).
Sortie : ../godot/world/veg/v_tx_tz.bin par tuile de 256 m : float32 (x, y, z, hauteur, rotation, essence, couronne,
teinte) ; ordre : grands arbres d'abord puis aléatoire (le réglage de densité affiche un préfixe de la liste).
Essences (indices) : 0 chene, 1 feuillu, 2 chene2, 3 bouleau, 4 peuplier, 5 epicea, 6 sapin, 7 pin."""
import json, os, pickle, shutil
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi
from scipy.spatial import cKDTree
import shapely
from shapely.geometry import shape
from shapely.ops import transform
import geo
from build_roads import DEM, REG, samples, road_height_fn

OUT = "../godot/world/veg"
TILE = 256.0
SPECIES = ["chene", "feuillu", "chene2", "bouleau", "peuplier", "epicea", "sapin", "pin"]
_meta = json.load(open("../godot/assets/veg/meta.json"))
CROWN = np.array([_meta[n]["crown"] for n in SPECIES])          # rayon de couronne du modèle / hauteur


def polys_local(path, key=None):
    out = []
    for f in json.load(open(path))["features"]:
        g = transform(lambda x, y, z=None: geo.to_local(x, y), shape(f["geometry"])).buffer(0)
        if not g.is_empty:
            out.append((f["properties"].get(key) if key else None, g))
    return out


def raster_region(polys, i, j, res=1.0, n=1024, value=1):
    im = Image.new("L", (n, n), 0); d = ImageDraw.Draw(im)
    x0, z0 = i * REG, j * REG
    from shapely.geometry import box
    bb = box(x0 - 50, z0 - 50, x0 + REG + 50, z0 + REG + 50)
    for v, g in polys:
        if not g.intersects(bb):
            continue
        for p in getattr(g, "geoms", [g]):
            if p.geom_type != "Polygon":
                continue
            d.polygon([((x - x0) / res, (z - z0) / res) for x, z in p.exterior.coords], fill=value if not callable(value) else value(v))
            for r in p.interiors:
                d.polygon([((x - x0) / res, (z - z0) / res) for x, z in r.coords], fill=0)
    return np.asarray(im)


class Carved(DEM):
    def __init__(self):
        super().__init__()
        for k in list(self.reg):
            p = "data/dem_carved/r_%d_%d.npy" % k
            if os.path.exists(p):
                self.reg[k] = np.load(p)


def main():
    shutil.rmtree(OUT, ignore_errors=True); os.makedirs(OUT)
    dem = Carved()
    regions = [tuple(r) for r in json.load(open("data/routes_plan.json"))["regions"]]
    from build_buildings import load
    blds = [(None, g.buffer(1.5)) for _, g in load()]
    ZN = {"Forêt fermée de feuillus": 1, "Bois": 1, "Forêt ouverte": 1, "Haie": 2, "Lande ligneuse": 2,
          "Forêt fermée mixte": 3, "Forêt fermée de conifères": 4, "Peupleraie": 5, "Verger": 6, "Vigne": 7}
    zones = polys_local("data/vegetation_zones.json", "nature")
    zones = [(ZN.get(v, 0), g) for v, g in zones if ZN.get(v, 0)]
    walnut = [(8, g) for v, g in polys_local("data/rpg.json", "code_cultu") if v == "NOX"]
    ways = pickle.load(open("data/roads.pkl", "rb"))["ways"]
    rf = road_height_fn(samples(ways))
    # emprise autoroutière : ni arbre ni arbuste jusqu'à la clôture (~10 m au-delà de la chaussée)
    Sm = samples([w for w in ways if w["cls"] in ("motorway", "motorway_link")])
    Sm[:, 3] += 8.0
    rfm = road_height_fn(Sm)
    rng = np.random.default_rng(11)
    trees = []
    for (i, j) in regions:
        p = "data/mnh/r_%d_%d.npy" % (i, j)
        if not os.path.exists(p):
            continue
        chm = np.load(p).astype(np.float32) / 8.0
        bm = raster_region(blds, i, j) > 0
        chm[bm] = 0.0
        zone = raster_region(zones + walnut, i, j, value=lambda v: v)
        xs = i * REG + np.arange(1024) + 0.5; zs = j * REG + np.arange(1024) + 0.5
        X, Z = np.meshgrid(xs, zs)
        _, sd = rf(X.ravel(), Z.ravel())
        road = sd.reshape(X.shape) < 0.6
        road |= rfm(X.ravel(), Z.ravel())[1].reshape(X.shape) < 0.0
        chm[road] = 0.0
        sm = ndi.gaussian_filter(chm, 1.0)
        # sommets de couronne : maximum local sur une fenêtre qui grandit avec la hauteur
        m5 = ndi.maximum_filter(sm, size=5); m9 = ndi.maximum_filter(sm, size=9)
        peak = (sm >= 3.0) & (((sm >= 12) & (sm == m9)) | ((sm < 12) & (sm == m5)))
        pz, px_ = np.nonzero(peak)
        if len(px_) == 0:
            continue
        h = chm[pz, px_]
        h = np.maximum(h, sm[pz, px_])
        # largeur de couronne : pixels au-dessus de 60 % de la hauteur dans une fenêtre de 15 m
        r_est = []
        for a, b, hh in zip(pz, px_, h):
            w = sm[max(0, a - 7):a + 8, max(0, b - 7):b + 8]
            r_est.append(np.sqrt((w > 0.6 * hh).sum() / np.pi))
        r_est = np.array(r_est)
        # couleur (orthophoto 2 m) au sommet
        O = np.asarray(Image.open("data/ortho/r_%d_%d.jpg" % (i, j))).astype(np.float32)
        Ob = ndi.uniform_filter(O, (3, 3, 1))
        c = Ob[np.clip(pz // 2, 0, 511), np.clip(px_ // 2, 0, 511)]
        lum = c.mean(1); exg = 2 * c[:, 1] - c[:, 0] - c[:, 2]; blue = c[:, 2] - c[:, 0]
        zcls = zone[pz, px_]
        sp = np.full(len(h), 1)
        u = rng.random(len(h))
        # feuillus : chêne pour les grands arbres, sinon mélange
        sp = np.where(h >= 16, np.where(u < 0.55, 0, np.where(u < 0.85, 1, 2)), np.where(u < 0.4, 1, np.where(u < 0.7, 2, np.where(u < 0.85, 0, 3))))
        # conifères de jardin / isolés : très sombres et bleutés, hors des bois de feuillus (ombres trompeuses)
        conifer = (lum < 58) & (blue > 0) & (exg < 18) & ((zcls == 0) | (zcls == 2))
        sp = np.where(conifer & (zcls != 5) & (zcls != 6) & (zcls != 8), np.where(u < 0.45, 6, np.where(u < 0.8, 5, 7)), sp)
        mixed = zcls == 3
        sp = np.where(mixed & (u < 0.4), np.where(u < 0.2, 6, 5), sp)
        sp = np.where(zcls == 4, np.where(u < 0.5, 6, np.where(u < 0.85, 5, 7)), sp)
        narrow = (h > 15) & (r_est < 0.16 * h)
        sp = np.where((zcls == 5) | (narrow & ~conifer), 4, sp)
        sp = np.where((zcls == 6) | (zcls == 8), np.where(zcls == 8, 1, 2), sp)
        sp = np.where(sp == 6, 5, sp)       # sapin (racines apparentes démesurées à grande échelle) -> épicéa
        crown = np.clip(np.where(r_est > 0.5, r_est, 0.3 * h), 0.8, 0.45 * h + 1)
        x = i * REG + px_ + 0.5; z = j * REG + pz + 0.5
        # rien ne déborde sur la route : la couronne du modèle (rayon = part de la hauteur propre à chaque essence)
        # doit rester hors de la chaussée ; sinon arbre plus petit qui tient sur le bas-côté, ou supprimé (< 3 m)
        _, sdt = rf(x, z)
        ratio = CROWN[sp]
        hmax = (sdt - 0.4) / ratio
        h = np.minimum(h, hmax)
        ok = h >= 3.0
        x, z, h, sp, crown, pz, px_ = x[ok], z[ok], h[ok], sp[ok], crown[ok], pz[ok], px_[ok]
        y = dem.h(x, z)
        tint = 0.88 + 0.24 * rng.random(len(h))
        rot = rng.random(len(h)) * 2 * np.pi
        trees.append(np.c_[x, y, z, h, rot, sp, crown, tint].astype(np.float32))
        print("région", i, j, len(h), "arbres")
    T = np.vstack(trees)
    # ordre : grands arbres d'abord (toujours affichés), puis aléatoire
    key = rng.random(len(T)) * (1.0 - 0.75 * np.clip((T[:, 3] - 10) / 12, 0, 1))
    T = T[np.argsort(key)]
    tk = np.floor(T[:, [0, 2]] / TILE).astype(int)
    order = np.lexsort((np.arange(len(T)), tk[:, 1], tk[:, 0]))
    T, tk = T[order], tk[order]
    keys, starts = np.unique(tk, axis=0, return_index=True)
    ends = np.r_[starts[1:], len(T)]
    for (tx, tz), a, b in zip(keys, starts, ends):
        T[a:b].astype("<f4").tofile("%s/v_%d_%d.bin" % (OUT, tx, tz))
    counts = np.bincount(T[:, 5].astype(int), minlength=len(SPECIES))
    print(len(T), "arbres,", len(keys), "tuiles ;", dict(zip(SPECIES, counts.tolist())),
          "; hauteur médiane %.1f m, max %.1f m" % (np.median(T[:, 3]), T[:, 3].max()))


if __name__ == "__main__":
    main()
