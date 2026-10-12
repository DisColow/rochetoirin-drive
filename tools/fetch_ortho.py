"""Orthophotographie IGN (BD ORTHO 20 cm, Licence Ouverte) sur le village de Rochetoirin.

Sert à prepare_village.py : couleur réelle des toits, arbres et haies, piscines, cours et pelouses.
Sortie : data/ortho_village.jpg (+ data/ortho_village.json : emprise en mètres locaux).
"""
import io, json, os, time, urllib.request
from PIL import Image
from geo import to_lonlat

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "data")
# emprise (m, repère local) : bourg + rue du Balcon
X0, X1, Z0, Z1 = -660.0, 420.0, -160.0, 720.0
RES = 0.25            # m / pixel
TILE = 256.0          # m par requête
URL = ("https://data.geopf.fr/wms-r/wms?SERVICE=WMS&VERSION=1.3.0&REQUEST=GetMap&LAYERS=ORTHOIMAGERY.ORTHOPHOTOS"
       "&STYLES=&CRS=EPSG:4326&BBOX={la0},{lo0},{la1},{lo1}&WIDTH={w}&HEIGHT={h}&FORMAT=image/jpeg")


def main():
    W, H = int((X1 - X0) / RES), int((Z1 - Z0) / RES)
    out = Image.new("RGB", (W, H))
    x = X0
    while x < X1:
        z = Z0
        while z < Z1:
            x1, z1 = min(X1, x + TILE), min(Z1, z + TILE)
            lo0, la1 = to_lonlat(x, z); lo1, la0 = to_lonlat(x1, z1)
            w, h = int(round((x1 - x) / RES)), int(round((z1 - z) / RES))
            u = URL.format(la0=la0, lo0=lo0, la1=la1, lo1=lo1, w=w, h=h)
            for k in range(5):
                try:
                    img = Image.open(io.BytesIO(urllib.request.urlopen(u, timeout=120).read())).convert("RGB")
                    break
                except Exception as e:
                    print("nouvel essai", k, e); time.sleep(5 * (k + 1))
            out.paste(img, (int(round((x - X0) / RES)), int(round((z - Z0) / RES))))
            z = z1
        x = min(X1, x + TILE)
        print("colonne", x)
    out.save(os.path.join(DATA, "ortho_village.jpg"), quality=92)
    json.dump(dict(x0=X0, x1=X1, z0=Z0, z1=Z1, res=RES), open(os.path.join(DATA, "ortho_village.json"), "w"))


if __name__ == "__main__":
    main()
