"""Couleurs réelles des façades (enduit, volets) mesurées sur les vues Street View (fetch_streetview.py).

Pour chaque maison : l'emprise BD TOPO et sa hauteur sont projetées dans l'image (position, cap,
inclinaison et champ de la caméra connus) ; on échantillonne les pixels du mur au-dessus des haies
et des clôtures, en écartant ciel, végétation et ombres profondes.
  * enduit : médiane des pixels du mur ;
  * volets : couleur dominante nettement différente de l'enduit (bois brun, blanc, gris, bleu, vert, bordeaux).
Sortie : data/facades.json  { cleabs: {"wall": [r,g,b], "shutter": index 0-5 ou null, "n": pixels} }
"""
import json, math, os
import numpy as np
from PIL import Image, ImageDraw
from shapely.geometry import Polygon
from shapely.geometry.polygon import orient

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "data")
SV = os.environ.get("STREETVIEW_DIR", os.path.join(DATA, "streetview"))
CAM_H = 2.5
# mêmes teintes que SHUT[] du shader des façades (PROPS_FS)
SHUT = np.array([(0.42, 0.28, 0.18), (0.86, 0.86, 0.83), (0.66, 0.68, 0.68), (0.42, 0.53, 0.60), (0.35, 0.47, 0.37), (0.47, 0.17, 0.15)])


class Camera:
    def __init__(self, info, cy):
        hd, pt = math.radians(info["heading"]), math.radians(info["pitch"])
        self.W, self.H = info["size"]
        self.c = np.array([info["cam"][0], cy, info["cam"][1]])
        self.f = np.array([math.sin(hd) * math.cos(pt), math.sin(pt), -math.cos(hd) * math.cos(pt)])
        self.r = np.array([math.cos(hd), 0.0, math.sin(hd)])
        self.u = np.cross(self.r, self.f)
        self.s = (self.W / 2) / math.tan(math.radians(info["fov"]) / 2)

    def project(self, p):
        v = np.asarray(p, float) - self.c
        z = v @ self.f
        if z < 0.5:
            return None
        return (self.W / 2 + self.s * (v @ self.r) / z, self.H / 2 - self.s * (v @ self.u) / z)


def facade_quads(cam, poly, ground, wall_top):
    """Murs tournés vers la caméra : quadrilatères (sol + 0,3 m .. égout) projetés."""
    poly = orient(poly.simplify(0.3), 1.0)
    ring = list(poly.exterior.coords)[:-1]
    out = []
    for k in range(len(ring)):
        a, b = np.array(ring[k]), np.array(ring[(k + 1) % len(ring)])
        L = np.linalg.norm(b - a)
        if L < 2.0:
            continue
        n = np.array([(b - a)[1], -(b - a)[0]]) / L          # extérieur (anneau CCW, x Est / z Sud)
        mid = (a + b) / 2
        if n @ (cam.c[[0, 2]] - mid) <= 0:
            continue
        pts = [cam.project((p[0], y, p[1])) for p, y in ((a, ground + 0.3), (b, ground + 0.3), (b, wall_top), (a, wall_top))]
        if any(q is None for q in pts):
            continue
        out.append((pts, L))
    return out


def analyse(img, quads, ground, wall_top, cam):
    W, H = img.size
    mask = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(mask)
    for pts, L in quads:
        d.polygon([tuple(q) for q in pts], fill=255)
    m = np.array(mask) > 0
    # cadrage : la maison doit être vue en entier ou presque (sinon gros plan sur l'enduit, volets introuvables)
    if m.mean() > 0.70 or not m.any(axis=1)[: H // 12].sum() < H // 12:
        return None
    a = np.asarray(img.convert("RGB")).astype(np.float32)
    R, G, B = a[..., 0], a[..., 1], a[..., 2]
    Lum = (R + G + B) / 3
    exg = 2 * G - R - B
    sky = (B > R + 18) & (Lum > 140)
    if sky[: H // 4].mean() < 0.04:          # pas de ciel en haut de l'image : gros plan sur un mur
        return None
    ok = m & (exg < 14) & ~sky & (Lum > 55) & (Lum < 250)
    # au-dessus des haies et clôtures (~2,3 m) : moitié haute des quadrilatères
    ys = np.where(m.any(axis=1))[0]
    if len(ys) == 0:
        return None
    upper = np.zeros_like(m)
    cut = ys.min() + (ys.max() - ys.min()) * 0.62
    upper[: int(cut), :] = True
    # qualité : assez de mur visible (pas masqué par une haie) et image nette (pas floutée par Google)
    vis = (ok & upper).sum() / max(1, (m & upper).sum())
    if vis < 0.30:
        return None
    gx = np.abs(np.diff(Lum, axis=1))[m[:, 1:]]
    if gx.size and float(np.mean(gx)) < 2.5:
        return None
    px = a[ok & upper]
    if len(px) < 250:
        return None
    wall = np.median(px, axis=0)
    # volets : pixels du mur nettement différents de l'enduit, ni vitres (sombres) ni ciel
    dist = np.linalg.norm(a - wall, axis=2)
    cand = a[ok & (dist > 55) & (Lum > 45)]
    shutter = None
    if len(cand) > 0.03 * ok.sum() and len(cand) > 60:
        c = cand / 255.0
        dd = np.linalg.norm(c[:, None, :] - SHUT[None, :, :], axis=2)
        lab = dd.argmin(axis=1)
        good = dd.min(axis=1) < 0.22
        counts = np.bincount(lab[good], minlength=6)
        # le blanc ne compte que si l'enduit n'est pas déjà clair
        if (wall / 255.0).mean() > 0.75:
            counts[1] = 0
        counts[4] = counts[4] // 3          # le « vert » est souvent un reste de feuillage
        if counts.max() > 40:
            shutter = int(counts.argmax())
    return dict(wall=[float(x) / 255 for x in wall], shutter=shutter, n=int(len(px)), vis=float(vis))


def main(debug_dir=None):
    from prepare_decor import load, loc, polys, read_grid
    from prepare_data import Grid
    H_, x0, z0, st = read_grid(os.path.join(HERE, "..", "app", "src", "main", "assets", "terrain.bin"))
    terrain = Grid(H_, x0, z0, st)
    index = json.load(open(os.path.join(SV, "index.json")))
    out = {}
    blds = {}
    for f in load("batiment"):
        if f["properties"]["cleabs"] in index:
            ps = polys(loc(f["geometry"]))
            if ps:
                blds[f["properties"]["cleabs"]] = (max(ps, key=lambda q: q.area), f["properties"])
    for k, (cle, info) in enumerate(sorted(index.items())):
        if cle not in blds:
            continue
        poly, pr = blds[cle]
        xs, zs = np.array(poly.exterior.coords).T
        ground = float(terrain.height(xs, zs).min())
        h = float(pr.get("hauteur") or 6.0)
        wall_top = ground + max(h, 2.6)
        cam = Camera(info, float(terrain.height(*info["cam"])) + CAM_H)
        img = Image.open(os.path.join(SV, cle + ".jpg"))
        quads = facade_quads(cam, poly, ground, wall_top)
        if not quads:
            continue
        res = analyse(img, quads, ground, wall_top, cam)
        if res:
            out[cle] = res
        if debug_dir and k < 24:
            dbg = img.convert("RGB").copy(); d = ImageDraw.Draw(dbg)
            for pts, L in quads:
                d.line([tuple(q) for q in pts] + [tuple(pts[0])], fill=(0, 255, 0), width=2)
                d.line([tuple(pts[3]), tuple(pts[2])], fill=(255, 0, 0), width=2)
            if res:
                d.rectangle([5, 5, 60, 40], fill=tuple(int(c * 255) for c in res["wall"]))
                if res["shutter"] is not None:
                    d.rectangle([65, 5, 100, 40], fill=tuple(int(c * 255) for c in SHUT[res["shutter"]]))
            dbg.save(os.path.join(debug_dir, "%02d.jpg" % k))
    json.dump(out, open(os.path.join(DATA, "facades.json"), "w"))
    print(len(out), "façades mesurées sur", len(index))


if __name__ == "__main__":
    import sys
    main(sys.argv[1] if len(sys.argv) > 1 else None)
