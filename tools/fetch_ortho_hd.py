"""Orthophotographies IGN en haute définition (rééchantillonnées à 10 cm) sur une emprise réduite, pour redessiner
les propriétés à la main (rue du Balcon). Plusieurs millésimes : l'été 2021 est le plus lisible (ombres courtes),
2024 sert à vérifier l'état récent. Licence Ouverte (IGN).

Usage : python3 fetch_ortho_hd.py [x0 z0 x1 z1]  (repère local, défaut = rue du Balcon)
Sortie : data/ortho_hd_<année>.jpg + data/ortho_hd.json (emprise, résolution)
"""
import io, json, os, sys, time, urllib.request
from PIL import Image
from geo import to_lonlat

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "data")
BBOX = (-560.0, -60.0, -240.0, 150.0)
RES = 0.10
TILE = 100.0
LAYERS = {"2021": "ORTHOIMAGERY.ORTHOPHOTOS2021", "2024": "ORTHOIMAGERY.ORTHOPHOTOS2024"}
URL = ("https://data.geopf.fr/wms-r/wms?SERVICE=WMS&VERSION=1.3.0&REQUEST=GetMap&LAYERS={layer}"
       "&STYLES=&CRS=EPSG:4326&BBOX={la0},{lo0},{la1},{lo1}&WIDTH={w}&HEIGHT={h}&FORMAT=image/jpeg")


def fetch(layer, X0, Z0, X1, Z1):
    W, H = int(round((X1 - X0) / RES)), int(round((Z1 - Z0) / RES))
    out = Image.new("RGB", (W, H))
    x = X0
    while x < X1 - 1e-6:
        z = Z0
        x1 = min(X1, x + TILE)
        while z < Z1 - 1e-6:
            z1 = min(Z1, z + TILE)
            lo0, la1 = to_lonlat(x, z); lo1, la0 = to_lonlat(x1, z1)
            w, h = int(round((x1 - x) / RES)), int(round((z1 - z) / RES))
            u = URL.format(layer=layer, la0=la0, lo0=lo0, la1=la1, lo1=lo1, w=w, h=h)
            for k in range(6):
                try:
                    img = Image.open(io.BytesIO(urllib.request.urlopen(u, timeout=120).read())).convert("RGB")
                    break
                except Exception as e:
                    print("nouvel essai", k, e)
                    time.sleep(4 * (k + 1))
            else:
                raise SystemExit("échec " + u)
            out.paste(img, (int(round((x - X0) / RES)), int(round((z - Z0) / RES))))
            z = z1
        x = x1
    return out


def main():
    X0, Z0, X1, Z1 = (float(v) for v in sys.argv[1:5]) if len(sys.argv) >= 5 else BBOX
    for year, layer in LAYERS.items():
        img = fetch(layer, X0, Z0, X1, Z1)
        img.save(os.path.join(DATA, "ortho_hd_%s.jpg" % year), quality=93)
        print(year, img.size)
    json.dump(dict(x0=X0, z0=Z0, x1=X1, z1=Z1, res=RES, years=list(LAYERS)), open(os.path.join(DATA, "ortho_hd.json"), "w"))


if __name__ == "__main__":
    main()
