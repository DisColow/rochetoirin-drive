"""Orthophotos IGN à 0,5 m/px des régions jouables (2048 px par région de 1024 m), pour repérer ce que la photo à
2 m/px ne montre pas : piscines des jardins (build_pools.py).
Sortie : data/ortho_hd/r_i_j.jpg (pixel (0, 0) centré en (i·1024 + 0,25, j·1024 + 0,25), ligne = z)."""
import io, json, os, time, urllib.request
from concurrent.futures import ThreadPoolExecutor
from PIL import Image
from geo import to_lonlat

URL = ("https://data.geopf.fr/wms-r/wms?SERVICE=WMS&VERSION=1.3.0&REQUEST=GetMap&LAYERS=ORTHOIMAGERY.ORTHOPHOTOS"
       "&STYLES=&CRS=EPSG:4326&BBOX={la0},{lo0},{la1},{lo1}&WIDTH={w}&HEIGHT={h}&FORMAT=image/jpeg")


def get(x0, z0, step, w, h):
    """Image w × h dont le pixel (0, 0) est centré en (x0, z0), pas de step m (comme fetch_ortho.py)."""
    lo0, la1 = to_lonlat(x0 - step / 2, z0 - step / 2); lo1, la0 = to_lonlat(x0 + step * (w - 0.5), z0 + step * (h - 0.5))
    u = URL.format(la0=la0, lo0=lo0, la1=la1, lo1=lo1, w=w, h=h)
    for k in range(8):
        try:
            return Image.open(io.BytesIO(urllib.request.urlopen(u, timeout=120).read())).convert("RGB")
        except Exception:
            time.sleep(3 * (k + 1))
    raise SystemExit(u)

OUT = "data/ortho_hd"
RES = 0.5


def reg(r):
    i, j = r
    p = "%s/r_%d_%d.jpg" % (OUT, i, j)
    if os.path.exists(p):
        return
    im = Image.new("RGB", (2048, 2048))
    for a in (0, 1024):
        for b in (0, 1024):
            im.paste(get(i * 1024.0 + RES / 2 + a * RES, j * 1024.0 + RES / 2 + b * RES, RES, 1024, 1024), (a, b))
    im.save(p, quality=88)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    regs = [tuple(r) for r in json.load(open("data/routes_plan.json"))["regions"]]
    with ThreadPoolExecutor(4) as ex:
        list(ex.map(reg, regs))
    print(len(regs), "régions")
