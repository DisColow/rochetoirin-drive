"""Relief IGN (WMS, float32) :
 - régions jouables : 512 × 512 points au pas de 2 m (sommets Terrain3D en x0 + 2i) -> data/dem/r_<i>_<j>.npy, d'après
   le MNT LiDAR HD à 1 m moyenné par carrés de 2 × 2 (centrés sur les sommets) ; là où le LiDAR HD manque, RGE ALTI
   lissé : servi en EPSG:4326, il arrive agrandi « au plus proche » depuis sa grille de 5 m, en marches d'escalier
   (paires de valeurs identiques puis saut) qui faisaient des plateaux sur toutes les pentes ;
 - environs : pas de 25 m sur 40 × 30 km -> data/dem/near.npy (RGE ALTI, sous-échantillonné : pas de marches)
"""
import json, os, sys, time, urllib.request, urllib.parse
from concurrent.futures import ThreadPoolExecutor
import numpy as np
from scipy import ndimage as ndi
from geo import to_lonlat
OUT = "data/dem"; os.makedirs(OUT, exist_ok=True)
URL = ("https://data.geopf.fr/wms-r/wms?SERVICE=WMS&VERSION=1.3.0&REQUEST=GetMap&LAYERS={layer}"
       "&STYLES=&CRS=EPSG:4326&BBOX={la0},{lo0},{la1},{lo1}&WIDTH={w}&HEIGHT={h}&FORMAT=image/x-bil;bits=32")
RGE = "ELEVATION.ELEVATIONGRIDCOVERAGE.HIGHRES"
LIDAR = "IGNF_LIDAR-HD_MNT_ELEVATION.ELEVATIONGRIDCOVERAGE.LAMB93"

def grid(x0, z0, step, w, h, layer=RGE, allow_empty=False):
    """Points x0 + step*i, z0 + step*j (i < w, j < h) : bbox décalée d'un demi-pas (centres de pixels)."""
    lo0, la1 = to_lonlat(x0 - step / 2, z0 - step / 2)
    lo1, la0 = to_lonlat(x0 + step * (w - 0.5), z0 + step * (h - 0.5))
    u = URL.format(layer=layer, la0=la0, lo0=lo0, la1=la1, lo1=lo1, w=w, h=h)
    for k in range(8):
        try:
            b = urllib.request.urlopen(u, timeout=120).read()
            a = np.frombuffer(b, "<f4").reshape(h, w)
            if allow_empty or (a < -100).mean() < 0.5:
                return a
            raise ValueError("vide")
        except Exception as e:
            time.sleep(3 * (k + 1))
    raise SystemExit("échec " + u)

def region(ij):
    i, j = ij
    p = "%s/r_%d_%d.npy" % (OUT, i, j)
    if os.path.exists(p):
        return
    x0, z0 = i * 1024.0, j * 1024.0
    rge = grid(x0, z0, 2.0, 512, 512).astype(np.float64)
    rge = ndi.gaussian_filter(rge, 1.3, mode="nearest")              # efface les marches de la grille de 5 m
    # LiDAR HD : points à x0 - 0.5 + k (1 m), moyennés par 2 × 2 autour de chaque sommet x0 + 2i
    li = grid(x0 - 0.5, z0 - 0.5, 1.0, 1024, 1024, LIDAR, allow_empty=True).astype(np.float64)
    ok = li > -100
    s = (np.where(ok, li, 0.0)).reshape(512, 2, 512, 2).sum(axis=(1, 3))
    n = ok.reshape(512, 2, 512, 2).sum(axis=(1, 3))
    lid = np.where(n > 0, s / np.maximum(n, 1), np.nan)
    good = n == 4
    # raccord progressif (12 m) entre LiDAR HD et RGE ALTI au bord de la couverture
    w = np.clip(ndi.distance_transform_edt(good) / 6.0, 0.0, 1.0) if good.any() else np.zeros(good.shape)
    out = np.where(good, w * np.nan_to_num(lid) + (1 - w) * rge, rge)
    np.save(p, out.astype(np.float32))
    return float(good.mean())

if __name__ == "__main__":
    regs = json.load(open("data/routes_plan.json"))["regions"]
    with ThreadPoolExecutor(6) as ex:
        cov = [c for c in ex.map(region, [tuple(r) for r in regs]) if c is not None]
    print(len(regs), "régions ; couverture LiDAR HD moyenne des régions récupérées : %.1f %%" % (100 * np.mean(cov) if cov else 0))
    if not os.path.exists(OUT + "/near.npy"):
        # environs : x -24..+14 km, z -16..+12 km au pas de 25 m (tuiles de 400 px)
        X0, Z0, S = -24000.0, -16000.0, 25.0
        W, H = 1520, 1120
        A = np.zeros((H, W), np.float32)
        jobs = [(a, b) for a in range(0, W, 380) for b in range(0, H, 280)]
        def tile(ab):
            a, b = ab
            A[b:b + 280, a:a + 380] = grid(X0 + a * S, Z0 + b * S, S, 380, 280)
        with ThreadPoolExecutor(6) as ex:
            list(ex.map(tile, jobs))
        np.save(OUT + "/near.npy", A)
        json.dump(dict(x0=X0, z0=Z0, step=S, w=W, h=H), open(OUT + "/near.json", "w"))
        print("environs", A.min(), A.max())
