"""Orthophotos IGN : couleur du terrain par région (512 px = 2 m/px, alignés sur les sommets Terrain3D)
et image basse résolution des environs (25 m/px) pour l'horizon."""
import io, json, os, time, urllib.request
from concurrent.futures import ThreadPoolExecutor
from PIL import Image
from geo import to_lonlat
OUT = "data/ortho"; os.makedirs(OUT, exist_ok=True)
URL = ("https://data.geopf.fr/wms-r/wms?SERVICE=WMS&VERSION=1.3.0&REQUEST=GetMap&LAYERS=ORTHOIMAGERY.ORTHOPHOTOS"
       "&STYLES=&CRS=EPSG:4326&BBOX={la0},{lo0},{la1},{lo1}&WIDTH={w}&HEIGHT={h}&FORMAT=image/jpeg")
def get(x0, z0, step, w, h):
    lo0, la1 = to_lonlat(x0 - step / 2, z0 - step / 2); lo1, la0 = to_lonlat(x0 + step * (w - 0.5), z0 + step * (h - 0.5))
    u = URL.format(la0=la0, lo0=lo0, la1=la1, lo1=lo1, w=w, h=h)
    for k in range(8):
        try:
            return Image.open(io.BytesIO(urllib.request.urlopen(u, timeout=120).read())).convert("RGB")
        except Exception:
            time.sleep(3 * (k + 1))
    raise SystemExit(u)
def reg(r):
    i, j = r; p = "%s/r_%d_%d.jpg" % (OUT, i, j)
    if not os.path.exists(p):
        get(i * 1024.0, j * 1024.0, 2.0, 512, 512).save(p, quality=92)
regs = json.load(open("data/routes_plan.json"))["regions"]
with ThreadPoolExecutor(6) as ex:
    list(ex.map(reg, [tuple(r) for r in regs]))
nm = json.load(open("data/dem/near.json"))
if not os.path.exists(OUT + "/near.jpg"):
    im = Image.new("RGB", (nm["w"], nm["h"]))
    for a in range(0, nm["w"], 760):
        for b in range(0, nm["h"], 560):
            im.paste(get(nm["x0"] + a * nm["step"], nm["z0"] + b * nm["step"], nm["step"], 760, 560), (a, b))
    im.save(OUT + "/near.jpg", quality=90)
if not os.path.exists(OUT + "/pano.jpg"):
    # relief lointain : ±75 km, 301 points de 500 m -> image 1204 px (125 m/px)
    im = Image.new("RGB", (1204, 1204))
    for a in range(0, 1204, 301):
        for b in range(0, 1204, 301):
            im.paste(get(-75000 + a * 124.6, -75000 + b * 124.6, 124.6, 301, 301), (a, b))
    im.save(OUT + "/pano.jpg", quality=90)
print("ok")
