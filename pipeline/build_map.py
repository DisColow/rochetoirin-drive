"""Carte du jeu : orthophoto de la zone (6 m/px) + routes dessinées, et points de téléportation sur les routes.
Sorties : ../godot/assets/tex/map.jpg, ../godot/world/map.json (emprise, communes), ../godot/world/teleport.bin
(float32 : x, z, y, cap en degrés, tous les 8 m le long des routes carrossables)."""
import json, math, pickle
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from shapely.geometry import Polygon, Point
from shapely.prepared import prep

RES = 6.0
plan = json.load(open("data/routes_plan.json"))
Z = Polygon(plan["zone"])
mnx, mnz, mxx, mxz = Z.buffer(400).bounds
W, H = int((mxx - mnx) / RES), int((mxz - mnz) / RES)
# fond : environs (25 m/px) puis régions (2 m/px réduites)
nm = json.load(open("data/dem/near.json"))
near = Image.open("data/ortho/near.jpg")
sx = nm["step"] / RES
crop = near.crop((int((mnx - nm["x0"]) / nm["step"]), int((mnz - nm["z0"]) / nm["step"]),
                  int((mxx - nm["x0"]) / nm["step"]), int((mxz - nm["z0"]) / nm["step"])))
img = crop.resize((W, H), Image.BILINEAR).filter(ImageFilter.GaussianBlur(1))
for i, j in plan["regions"]:
    r = Image.open("data/ortho/r_%d_%d.jpg" % (i, j)).resize((int(1024 / RES), int(1024 / RES)), Image.LANCZOS)
    img.paste(r, (int((i * 1024 - mnx) / RES), int((j * 1024 - mnz) / RES)))
# assombrir hors zone jouable
mask = Image.new("L", (W, H), 0)
ImageDraw.Draw(mask).polygon([((x - mnx) / RES, (z - mnz) / RES) for x, z in Z.exterior.coords], fill=255)
dark = Image.eval(img, lambda v: int(v * 0.45))
img = Image.composite(img, dark, mask.filter(ImageFilter.GaussianBlur(6)))
# routes
ways = pickle.load(open("data/roads.pkl", "rb"))["ways"]
d = ImageDraw.Draw(img)
WID = {"motorway": 5, "trunk": 4, "primary": 4, "secondary": 3.5, "tertiary": 3, "motorway_link": 2.5}
COL = {"motorway": (240, 90, 80), "trunk": (250, 170, 70), "primary": (250, 200, 80), "secondary": (250, 225, 120)}
for layer in (0, 1):
    for w in sorted(ways, key=lambda w: WID.get(w["cls"], 1.5)):
        pts = [((x - mnx) / RES, (z - mnz) / RES) for x, z in w["P"][::2]]
        if len(pts) < 2:
            continue
        wd = WID.get(w["cls"], 2.0 if w["paved"] else 1.2)
        if layer == 0:
            d.line(pts, fill=(30, 30, 30), width=int(wd + 2), joint="curve")
        else:
            d.line(pts, fill=COL.get(w["cls"], (255, 255, 255) if w["paved"] else (200, 180, 140)), width=int(wd), joint="curve")
img.save("../godot/assets/tex/map.jpg", quality=88)
# points de téléportation
zp = prep(Z)
pts = []
for w in ways:
    if w["bridge"] or w["cls"] in ("track", "pedestrian"):
        continue
    for s in np.arange(4.0, w["s"][-1] - 2, 8.0):
        k = int(np.searchsorted(w["s"], s)) - 1
        k = min(max(k, 0), len(w["P"]) - 2)
        T = w["P"][k + 1] - w["P"][k]; T /= max(np.linalg.norm(T), 1e-9)
        Nr = np.array([-T[1], T[0]])
        P = w["P"][k] + Nr * (w["w"] / 4 if not w["oneway"] else 0.0)     # voie de droite
        if not zp.contains(Point(P)):
            continue
        pts.append((P[0], P[1], float(np.interp(s, w["s"], w["y"])) + 0.6, math.degrees(math.atan2(T[0], -T[1])) % 360))
np.array(pts, "<f4").tofile("../godot/world/teleport.bin")
towns = {k: v for k, v in plan["towns"].items()}
json.dump(dict(x0=mnx, z0=mnz, res=RES, w=W, h=H, towns=towns), open("../godot/world/map.json", "w"))
print("carte %dx%d, %d points de téléportation" % (W, H, len(pts)))
