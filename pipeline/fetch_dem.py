"""Relief IGN RGE ALTI (WMS ELEVATION.ELEVATIONGRIDCOVERAGE.HIGHRES, float32) :
 - régions jouables : 512 × 512 points au pas de 2 m (sommets Terrain3D en x0 + 2i) -> data/dem/r_<i>_<j>.npy
 - environs : pas de 25 m sur 40 × 30 km -> data/dem/near.npy
"""
import json, os, sys, time, urllib.request, urllib.parse
from concurrent.futures import ThreadPoolExecutor
import numpy as np
from geo import to_lonlat
OUT = "data/dem"; os.makedirs(OUT, exist_ok=True)
URL = ("https://data.geopf.fr/wms-r/wms?SERVICE=WMS&VERSION=1.3.0&REQUEST=GetMap&LAYERS=ELEVATION.ELEVATIONGRIDCOVERAGE.HIGHRES"
       "&STYLES=&CRS=EPSG:4326&BBOX={la0},{lo0},{la1},{lo1}&WIDTH={w}&HEIGHT={h}&FORMAT=image/x-bil;bits=32")

def grid(x0, z0, step, w, h):
    """Points x0 + step*i, z0 + step*j (i < w, j < h) : bbox décalée d'un demi-pas (centres de pixels)."""
    lo0, la1 = to_lonlat(x0 - step / 2, z0 - step / 2)
    lo1, la0 = to_lonlat(x0 + step * (w - 0.5), z0 + step * (h - 0.5))
    u = URL.format(la0=la0, lo0=lo0, la1=la1, lo1=lo1, w=w, h=h)
    for k in range(8):
        try:
            b = urllib.request.urlopen(u, timeout=120).read()
            a = np.frombuffer(b, "<f4").reshape(h, w)
            if (a < -100).mean() < 0.5:
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
    np.save(p, grid(i * 1024.0, j * 1024.0, 2.0, 512, 512).astype(np.float32))

if __name__ == "__main__":
    regs = json.load(open("data/routes_plan.json"))["regions"]
    with ThreadPoolExecutor(6) as ex:
        list(ex.map(region, [tuple(r) for r in regs]))
    print(len(regs), "régions")
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
