"""Bord « cascade » façon Golden Sun 2 (#157, option du jeu) : le long de la limite de la zone jouable
(world/zone.json, build_zone.py), un point tous les PAS m avec sa normale vers l'extérieur et la hauteur du relief
terrassé (celui du jeu) à DECALAGES m à l'intérieur ; cascade.gd en fait la bande d'eau qui coule vers le vide et le
rideau qui tombe dans la mer de nuages, à Y_NUAGES (sous le point le plus bas de la zone).
Sortie : ../godot/world/cascade.bin = int32 n, float32 y_nuages, puis n × (x, z, nx, nz, h aux DECALAGES).
Lancer depuis pipeline/ après build_zone.py : python3 build_cascade.py"""
import json
import numpy as np
import shapely
from shapely.geometry import Polygon
from build_buildings import CarvedDEM

PAS = 4.0
DECALAGES = (0.0, 3.0, 6.0, 10.0, 14.0)

z = Polygon(json.load(open("../godot/world/zone.json"))["pts"])
if not z.exterior.is_ccw:
    z = Polygon(list(z.exterior.coords)[::-1])
ext = z.exterior
n = int(ext.length // PAS)
s = np.arange(n) * (ext.length / n)
p = np.array([ext.interpolate(v).coords[0] for v in s])
t = np.roll(p, -1, 0) - np.roll(p, 1, 0)
t /= np.linalg.norm(t, axis=1)[:, None]
nrm = np.stack([t[:, 1], -t[:, 0]], 1)        # sens trigonométrique : l'extérieur est à droite de la tangente
# contrôle : un point 5 m dehors selon la normale n'est pas dans la zone
assert not shapely.contains_xy(z, *(p[::50] + nrm[::50] * 5.0).T).any()
dem = CarvedDEM()
hs = [dem.h(*(p - nrm * d).T) for d in DECALAGES]
# point le plus bas de la zone (grille de 50 m) : la mer de nuages passe dessous
x0, z0, x1, z1 = z.bounds
gx, gz = np.meshgrid(np.arange(x0, x1, 50.0), np.arange(z0, z1, 50.0))
m = shapely.contains_xy(z, gx.ravel(), gz.ravel())
y_nuages = float(dem.h(gx.ravel()[m], gz.ravel()[m]).min()) - 40.0
data = np.column_stack([p, nrm] + hs).astype("<f4")
with open("../godot/world/cascade.bin", "wb") as f:
    np.array([n], "<i4").tofile(f)
    np.array([y_nuages], "<f4").tofile(f)
    data.tofile(f)
print("%d points (%.1f km de limite), bord de %.0f à %.0f m, mer de nuages à %.0f m"
      % (n, ext.length / 1000, hs[0].min(), hs[0].max(), y_nuages))
