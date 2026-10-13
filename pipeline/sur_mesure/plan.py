"""Vue en plan d'un bâtiment sur mesure : orthophoto IGN à 20 cm (Géoplateforme, gratuite, mise en cache dans
data/ortho_bat/), emprise BD TOPO (rouge), volumes du relevé (cyan), grille du repère cadre() tous les mètres
(tous les 5 m, chiffrée) : on y lit les volumes (aile, corps principal, appentis) et les faîtages des toits.
Planche : SV_DIR/../planches/plan_<id>.jpg. Lancer depuis pipeline/ : python3 sur_mesure/plan.py <id> [<id>…]"""
import json, os, sys
import numpy as np
from PIL import Image, ImageDraw

ICI = os.path.dirname(os.path.abspath(__file__))
PIPE = os.path.dirname(ICI)
sys.path.insert(0, PIPE); sys.path.insert(0, ICI)
from calage import PLANCHES
from fetch_ortho_hd import get

RES = 0.2
MARGE = 8.0
ZOOM = 4                      # px de planche par px d'ortho


def plan(ident):
    from batiment import emprise, cadre, volumes
    R = json.load(open(os.path.join(ICI, "releves", ident + ".json")))
    feat = next(f for f in json.load(open(os.path.join(PIPE, "data/batiments.json")))["features"]
                if f["properties"]["cleabs"] == R["cleabs"])
    g = emprise(feat)
    x0, z0, x1, z1 = g.bounds
    x0 -= MARGE; z0 -= MARGE; x1 += MARGE; z1 += MARGE
    w, h = int((x1 - x0) / RES), int((z1 - z0) / RES)
    cache = os.path.join(PIPE, "data", "ortho_bat", R["cleabs"] + ".jpg")
    os.makedirs(os.path.dirname(cache), exist_ok=True)
    if not os.path.exists(cache):
        get(x0, z0, RES, w, h).save(cache, quality=92)
    im = Image.open(cache).convert("RGB")
    im = im.resize((im.width * ZOOM // 2, im.height * ZOOM // 2), Image.LANCZOS)
    k = ZOOM / 2 / RES
    px = lambda x, z: ((x - x0) * k, (z - z0) * k)
    d = ImageDraw.Draw(im)
    o, u, v, L, W = cadre(feat)
    for a in range(-2, int(L) + 3):
        for b0, b1 in ((-2, W + 2),):
            p0, p1 = o + u * a + v * b0, o + u * a + v * b1
            d.line([px(*p0), px(*p1)], fill=(255, 255, 255) if a % 5 == 0 else (150, 150, 150), width=1)
        if a % 5 == 0:
            d.text(px(*(o + u * a + v * -3)), "u%d" % a, fill="yellow")
    for b in range(-2, int(W) + 3):
        p0, p1 = o + u * -2 + v * b, o + u * (L + 2) + v * b
        d.line([px(*p0), px(*p1)], fill=(255, 255, 255) if b % 5 == 0 else (150, 150, 150), width=1)
        if b % 5 == 0:
            d.text(px(*(o + u * -4 + v * b)), "v%d" % b, fill="yellow")
    d.line([px(*q) for q in g.exterior.coords], fill="red", width=2)
    if R.get("volumes"):
        for sub in volumes(R, feat):
            P = sub["poly"] + [sub["poly"][0]]
            d.line([px(*q) for q in P], fill="cyan", width=2)
            c = np.mean(np.asarray(sub["poly"]), 0)
            d.text(px(*c), "%s %.1f/%.1f" % (sub["id"][-2:], sub.get("egout", 0), sub.get("faitage", 0)), fill="cyan")
    os.makedirs(PLANCHES, exist_ok=True)
    q = os.path.join(PLANCHES, "plan_%s.jpg" % ident)
    im.save(q, quality=88)
    print(q)


if __name__ == "__main__":
    for a in sys.argv[1:]:
        plan(a)
