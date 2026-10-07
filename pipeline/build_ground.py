"""Sol de près : carte des végétations basses (1 m) et ombres douces précalculées (occlusion ambiante).

Carte (../godot/world/ground/g_i_j.bin, 1024 × 1024 quartets, ligne = z) — catégories :
 0 rien (route + trottoir + 0,4 m, bâtiments, clôtures et haies, eau, champs labourés, roche)
 1 pelouse (zones habitées : herbe rase, pâquerettes)      2 pré (herbe haute, fleurs des champs)
 3 bas-côté (herbe folle, graminées hautes, quelques fleurs) 4 sous-bois (fougères, feuilles mortes)
Le jeu (grass.gd) y pose des touffes près de la voiture : rien ne pousse sur la route.

Ombres douces (ao_region, utilisée par prepare_terrain.py pour la teinte du terrain) : pied des bâtiments assombri
sur 2 à 3 m, sous les houppiers (LiDAR MNH) et le long des haies.
Ordre : après build_fences.py et build_water.py ; prepare_terrain.py (qui appelle ao_region) ; puis ce script."""
import json, os, pickle, shutil
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi
from shapely.geometry import LineString
from build_roads import REG

OUT = "../godot/world/ground"
N = 1024
_cache = {}


def _buildings():
    if "b" not in _cache:
        from build_buildings import load
        _cache["b"] = [g for _, g in load()]
    return _cache["b"]


def _poly_raster(polys, i, j, grow=0.0):
    im = Image.new("L", (N, N), 0); d = ImageDraw.Draw(im)
    x0, z0 = i * REG, j * REG
    for g in polys:
        b = g.bounds
        if b[2] < x0 - 5 or b[0] > x0 + REG + 5 or b[3] < z0 - 5 or b[1] > z0 + REG + 5:
            continue
        if grow:
            g = g.buffer(grow)
        for p in getattr(g, "geoms", [g]):
            if p.geom_type != "Polygon":
                continue
            d.polygon([(x - x0, z - z0) for x, z in p.exterior.coords], fill=1)
    return np.asarray(im, bool)


def building_mask(i, j):
    p = "data/bld_raster/r_%d_%d.npy" % (i, j)
    if os.path.exists(p):
        return np.unpackbits(np.load(p))[:N * N].reshape(N, N).astype(bool)
    os.makedirs("data/bld_raster", exist_ok=True)
    m = _poly_raster(_buildings(), i, j)
    np.save(p, np.packbits(m))
    return m


def canopy(i, j):
    p = "data/mnh/r_%d_%d.npy" % (i, j)
    return np.load(p).astype(np.float32) / 8.0 if os.path.exists(p) else np.zeros((N, N), np.float32)


def ao_region(i, j):
    """Facteur d'éclairage (0,6 à 1) à 2 m de pas (512²) : pied des murs, sous les arbres."""
    b = building_mask(i, j)
    d = ndi.distance_transform_edt(~b)
    ao_b = 1.0 - 0.38 * np.exp(-d / 1.6)
    ao_b[b] = 0.62
    c = ndi.gaussian_filter((canopy(i, j) > 2.5).astype(np.float32), 2.0)
    ao_c = 1.0 - 0.28 * c
    ao = ao_b * ao_c
    return ao.reshape(512, 2, 512, 2).mean(axis=(1, 3))


def _fence_lines(i, j):
    """Haies, murs, clôtures (world/fences) : segments avec demi-épaisseur."""
    out = []
    for tx in range(i * 4 - 1, i * 4 + 5):
        for tz in range(j * 4 - 1, j * 4 + 5):
            p = "../godot/world/fences/f_%d_%d.bin" % (tx, tz)
            if not os.path.exists(p):
                continue
            a = np.fromfile(p, "<f4"); o = 0
            while o + 16 <= len(a):
                t, n = int(a[o]), int(a[o + 1]); w = float(a[o + 6])
                P = a[o + 16:o + 16 + n * 3].reshape(-1, 3)[:, [0, 2]]
                if t in (1, 2, 3, 6):
                    half = w / 2 if t == 1 else max(w, 0.1)
                    out.append((P, half + 0.35))
                o += 16 + n * 3
    return out


def main():
    shutil.rmtree(OUT, ignore_errors=True); os.makedirs(OUT)
    plan = json.load(open("data/routes_plan.json"))
    ways = pickle.load(open("data/roads.pkl", "rb"))["ways"]
    roads = [LineString(w["P"]).buffer(w["w"] / 2 + (1.6 if any(w["sidewalk"]) else 0.0) + 0.4)
             for w in ways if len(w["P"]) > 1]
    verge_band = [LineString(w["P"]).buffer(w["w"] / 2 + (1.6 if any(w["sidewalk"]) else 0.0) + 3.5)
                  for w in ways if len(w["P"]) > 1 and w["cls"] not in ("service", "track", "pedestrian")]
    CV = np.load("data/eau_carve.npz")["pts"] if os.path.exists("data/eau_carve.npz") else np.zeros((0, 3))
    stats = np.zeros(5, np.int64)
    for (i, j) in [tuple(r) for r in plan["regions"]]:
        C = np.fromfile("../godot/import/terrain/r_%d_%d.c.raw" % (i, j), "<u4").reshape(512, 512)
        base = (C >> 27) & 0x1F; over = (C >> 22) & 0x1F; blend = (C >> 14) & 0xFF
        up = lambda a: np.repeat(np.repeat(a, 2, 0), 2, 1)
        base, over, blend = up(base), up(over), up(blend)
        cat = np.where(base == 0, 1, np.where(base == 1, 2, 4)).astype(np.uint8)
        # champs labourés / chaume (cultures 3D ou terre nue), roche : rien
        cat[(over == 4) & (blend > 110)] = 0
        cat[(over == 3) & (blend > 140)] = 0
        # bas-côtés des routes : herbe folle
        vb = _poly_raster(verge_band, i, j)
        cat[vb & (cat > 0) & (cat != 4)] = 3
        # exclusions
        cat[_poly_raster(roads, i, j)] = 0
        cat[ndi.binary_dilation(building_mask(i, j), iterations=1)] = 0
        im = Image.new("L", (N, N), 0); d = ImageDraw.Draw(im)
        for P, half in _fence_lines(i, j):
            pts = [(x - i * REG, z - j * REG) for x, z in P]
            if len(pts) > 1:
                d.line(pts, fill=1, width=max(1, int(round(half * 2))))
        cat[np.asarray(im, bool)] = 0
        if len(CV):
            sel = (CV[:, 0] >= i * REG - 2) & (CV[:, 0] < (i + 1) * REG + 2) & (CV[:, 1] >= j * REG - 2) & (CV[:, 1] < (j + 1) * REG + 2)
            q = CV[sel]
            if len(q):
                xi = np.clip((q[:, 0] - i * REG).astype(int), 0, N - 1); zi = np.clip((q[:, 1] - j * REG).astype(int), 0, N - 1)
                wet = np.zeros((N, N), bool); wet[zi, xi] = True
                cat[ndi.binary_dilation(wet, iterations=2)] = 0
        stats += np.bincount(cat.ravel(), minlength=5)[:5]
        packed = (cat[:, 0::2] | (cat[:, 1::2] << 4)).astype(np.uint8)
        packed.tofile("%s/g_%d_%d.bin" % (OUT, i, j))
    tot = stats.sum()
    print("sol : " + ", ".join("%s %.0f %%" % (n, 100 * s / tot) for n, s in
                               zip(["rien", "pelouse", "pré", "bas-côté", "sous-bois"], stats)))


if __name__ == "__main__":
    main()
