"""Distance signée à la limite de la zone jouable (world/zone.json, build_zone.py), pour le bord « cascade » façon Golden
Sun 2 (#157) : les matériaux du sol s'effacent au-delà de la limite, l'eau du bord coule dans les derniers mètres.
Grille de PAS m couvrant la zone et MARGE m autour ; valeur octet = 128 + distance / ECHELLE (positive hors de la zone),
bornée à ±127 (±127 × ECHELLE m), lue filtrée par les shaders (la distance, presque linéaire près du bord, s'interpole
bien). Sortie : ../godot/world/zone_sdf.bin = en-tête (int32 l, h ; float32 x0, z0, pas, echelle) puis l × h octets.
Lancer depuis pipeline/ après build_zone.py : python3 build_zone_sdf.py"""
import json
import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import distance_transform_edt
import shapely
from shapely.geometry import Polygon

PAS, FIN, MARGE, ECHELLE = 16.0, 4.0, 400.0, 1.0

pts = np.array(json.load(open("../godot/world/zone.json"))["pts"], float)
x0, z0 = pts.min(0) - MARGE
x1, z1 = pts.max(0) + MARGE
k = int(PAS / FIN)
l, h = int(np.ceil((x1 - x0) / PAS)) + 1, int(np.ceil((z1 - z0) / PAS)) + 1
im = Image.new("L", (l * k, h * k), 0)
# centre du pixel j (coordonnée PIL j + 0,5) en x0 + j × FIN : la case i de la grille tombe pile en x0 + i × PAS
ImageDraw.Draw(im).polygon([((x - x0) / FIN + 0.5, (z - z0) / FIN + 0.5) for x, z in pts], fill=1)
dedans = np.array(im, bool)
d = (distance_transform_edt(~dedans) - distance_transform_edt(dedans)) * FIN      # + hors de la zone
d = d[::k, ::k][:h, :l]
# près du bord (là où l'on regarde) : distance exacte au polygone (la grille fine fait ±3 m d'erreur)
z = Polygon(pts)
j, i = np.nonzero(np.abs(d) < 140.0)
gx, gz = x0 + i * PAS, z0 + j * PAS
ex = shapely.distance(z.exterior, shapely.points(gx, gz))
d[j, i] = np.where(shapely.contains_xy(z, gx, gz), -ex, ex)
v = np.clip(np.round(128 + d / ECHELLE), 0, 255).astype(np.uint8)
with open("../godot/world/zone_sdf.bin", "wb") as f:
    np.array([l, h], "<i4").tofile(f)
    np.array([x0, z0, PAS, ECHELLE], "<f4").tofile(f)
    v.tofile(f)
print("%d × %d cases de %.0f m, %.1f Mo" % (l, h, PAS, l * h / 1e6))
