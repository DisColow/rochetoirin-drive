"""Calage d'un bâtiment sur mesure sur ses photos Street View (méthode de la boulangerie, demande du 13/10 : « tout
refaire comme la boulangerie »). Le relevé (releves/<id>.json) est projeté en fil de fer sur chaque photo du cache
(streetview/batiments/, caméra exacte : position, cap, inclinaison, champ) : arêtes de l'emprise au sol et à l'égout
(rouge), faîtage approché (jaune), ouvertures (cyan), enseignes et affichettes (magenta). On corrige le relevé jusqu'à
ce que les traits tombent sur les arêtes, fenêtres et portes des photos.
Planche : SV_DIR/../planches/calage_<id>.jpg (cache privé : photos Google, jamais dans le dépôt).
Lancer depuis pipeline/ : python3 sur_mesure/calage.py <id> [<id>…]"""
import json, math, os, sys
import numpy as np
from PIL import Image, ImageDraw

ICI = os.path.dirname(os.path.abspath(__file__))
PIPE = os.path.dirname(ICI)
sys.path.insert(0, PIPE); sys.path.insert(0, ICI)
SV = os.environ.get("SV_DIR", os.path.join(PIPE, "..", "..", "rochetoirin-streetview", "streetview", "batiments"))
PLANCHES = os.path.join(os.path.dirname(SV), "planches")
CAM_H = 2.5
DECORS = ("enseigne", "lettres", "affiche", "logo", "bandeau")


def projeter(v, cam, cap, tang, fov, W, H, ycam):
    d = (v[0] - cam[0], -(v[2] - cam[1]), v[1] - ycam)          # est, nord, haut
    h, p = math.radians(cap), math.radians(tang)
    f = (math.sin(h) * math.cos(p), math.cos(h) * math.cos(p), math.sin(p))
    r = (math.cos(h), -math.sin(h), 0.0)
    u = (r[1] * f[2] - r[2] * f[1], r[2] * f[0] - r[0] * f[2], r[0] * f[1] - r[1] * f[0])
    z = sum(a * b for a, b in zip(d, f))
    if z < 0.5:
        return None
    k = (W / 2) / math.tan(math.radians(fov) / 2)
    return (W / 2 + sum(a * b for a, b in zip(d, r)) / z * k, H / 2 - sum(a * b for a, b in zip(d, u)) / z * k)


def corriger(v, R):
    """Caméra corrigée par le relevé : "cams": {nom: [dx, dz, dcap, dpitch]} (position et cap Google parfois décalés
    de quelques mètres / degrés par rapport au repère IGN du jeu)."""
    c = R.get("cams", {}).get(v["nom"])
    if not c:
        return v
    c = list(c) + [0, 0, 0, 0]
    return dict(v, cam=[v["cam"][0] + c[0], v["cam"][1] + c[1]], heading=v["heading"] + c[2], pitch=v["pitch"] + c[3])


def segments(B):
    """Arêtes (paires de points du monde (x, y, z)) et couleurs, d'après le relevé interprété par batiment.py."""
    s = []
    c0, sol = B.c, B.sol
    W = lambda p, y: (float(c0[0] + p[0]), sol + y, float(c0[1] + p[1]))
    for c in B.cotes:
        s.append((W(c["p0"], 0), W(c["p1"], 0), "red"))
        s.append((W(c["p0"], B.EG), W(c["p1"], B.EG), "red"))
        s.append((W(c["p0"], 0), W(c["p0"], B.EG), "red"))
        for op in c["ops"]:
            n = int(op.get("n", 1))
            f0, f1 = op.get("x", [0.4, 0.6])
            v0, v1 = op.get("y", [0.0, 2.2])
            if n > 1:
                larg = float(op.get("l", 1.0)) / c["L"]
                pas = (f1 - f0 - larg) / (n - 1)
                xs = [(f0 + i * pas, f0 + i * pas + larg) for i in range(n)]
            else:
                xs = [(f0, f1)]
            col = "magenta" if op["t"] in DECORS else "cyan"
            for a0, a1 in xs:
                pa, pb = B.pt_face(c, a0), B.pt_face(c, a1)
                q = [W(pa, v0), W(pb, v0), W(pb, v1), W(pa, v1)]
                s += [(q[i], q[(i + 1) % 4], col) for i in range(4)]
    # faîtage approché : axe du grand côté du rectangle orienté, à la hauteur du faîtage
    if B.FA > B.EG + 0.2:
        r = np.asarray(B.g.minimum_rotated_rectangle.exterior.coords)[:4]
        e = [r[1] - r[0], r[2] - r[1]]
        i = int(np.argmax([np.hypot(*v) for v in e]))
        a = (r[(i + 3) % 4] + r[i]) / 2 if i == 0 else (r[0] + r[1]) / 2
        m1, m2 = (r[0] + r[3]) / 2, (r[1] + r[2]) / 2
        if i == 1:
            m1, m2 = (r[0] + r[1]) / 2, (r[2] + r[3]) / 2
        s.append(((m1[0], sol + B.FA, m1[1]), (m2[0], sol + B.FA, m2[1]), "yellow"))
    return s


def planche(ident):
    from batiment import Batiment
    from build_buildings import CarvedDEM
    R = json.load(open(os.path.join(ICI, "releves", ident + ".json")))
    feats = {f["properties"]["cleabs"]: f for f in json.load(open(os.path.join(PIPE, "data/batiments.json")))["features"]}
    dem = CarvedDEM()
    from batiment import CAPS, volumes, cadre
    feat = feats[R["cleabs"]]
    Bs = [Batiment(sub, feat, dem) for sub in volumes(R, feat)]
    idx = json.load(open(os.path.join(SV, "index.json")))
    vues = idx.get(R["cleabs"], {}).get("vues", [])
    segs, etiq = [], []            # etiq : (point, texte) : nom de chaque façade au milieu, à mi-hauteur d'égout
    # grille au sol tous les 5 m dans le repère du bâtiment (u le long du grand côté, v en travers) : volumes
    o, u, v, L, W = cadre(feat)
    y0 = min(B.sol for B in Bs)
    P3 = lambda a, b: (float(o[0] + u[0] * a + v[0] * b), y0, float(o[1] + u[1] * a + v[1] * b))
    for a in np.arange(0, L + 0.01, 5.0):
        segs.append((P3(a, -2), P3(a, W + 2), "white"))
        etiq.append((P3(a, -2.5), "u%d" % a))
    for b in np.arange(0, W + 0.01, 5.0):
        segs.append((P3(-2, b), P3(L + 2, b), "white"))
        etiq.append((P3(-3, b), "v%d" % b))
    for B in Bs:
        segs += segments(B)
    for B in Bs:
      for c in B.cotes:
        k = min(CAPS, key=lambda k: abs((c["cap"] - CAPS[k] + 180) % 360 - 180))
        m = (c["p0"] + c["p1"]) / 2
        etiq.append(((float(B.c[0] + m[0]), B.sol + B.EG * 0.5, float(B.c[1] + m[1])), "%s %.0fm" % (k, c["L"])))
        g0 = B.pt_face(c, 0.0)                                   # x = 0 (gauche vue de dehors) : trait vert
        segs.append(((float(B.c[0] + g0[0]), B.sol, float(B.c[1] + g0[1])),
                     (float(B.c[0] + g0[0]), B.sol + B.EG, float(B.c[1] + g0[1])), "lime"))
    ims = []
    for v in vues:
        v = corriger(v, R)
        p = os.path.join(SV, v["nom"] + ".jpg")
        if not os.path.exists(p):
            continue
        im = Image.open(p).convert("RGB")
        Wd, Hd = im.size
        ycam = float(dem.h(np.array([v["cam"][0]]), np.array([v["cam"][1]]))[0]) + CAM_H
        d = ImageDraw.Draw(im)
        for a, b, col in segs:
            pa = projeter(a, v["cam"], v["heading"], v["pitch"], v["fov"], Wd, Hd, ycam)
            pb = projeter(b, v["cam"], v["heading"], v["pitch"], v["fov"], Wd, Hd, ycam)
            if pa and pb:
                d.line([pa, pb], fill=col, width=2 if col == "lime" else 1)
        for q, t in etiq:
            pq = projeter(q, v["cam"], v["heading"], v["pitch"], v["fov"], Wd, Hd, ycam)
            if pq:
                d.text((pq[0] - 12, pq[1]), t, fill="yellow")
        d.text((6, 6), "%s  %s" % (ident, v["nom"]), fill="white")
        ims.append(im)
    if not ims:
        print(ident, ": aucune photo")
        return None
    out = Image.new("RGB", (640 * len(ims), 640))
    for i, im in enumerate(ims):
        out.paste(im.resize((640, 640)), (i * 640, 0))
    os.makedirs(PLANCHES, exist_ok=True)
    q = os.path.join(PLANCHES, "calage_%s.jpg" % ident)
    out.save(q, quality=88)
    print(q)
    return q


if __name__ == "__main__":
    for a in sys.argv[1:]:
        planche(a)
