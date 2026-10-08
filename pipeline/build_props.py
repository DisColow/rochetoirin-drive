"""Vie des villages : voitures garées dans les cours, poubelles, tracteurs dans les fermes.
Placement logique (rien ne déborde sur la route, rien dans un bâtiment ni à travers une clôture) :
 - voitures : derrière un portail sur trois sur cinq (data/fences_gates.json, fait par build_fences.py), dans l'axe
   de l'entrée, capot vers la maison ; parfois une deuxième à côté ; la caisse doit tenir dans la parcelle (reculée de
   0,6 m des limites), hors des bâtiments et hors de l'emprise des routes ;
 - poubelles (verte, à couvercle jaune) : à côté du portail, à l'intérieur ;
 - tracteurs : près d'un grand bâtiment agricole, dans sa parcelle, hors des routes et des bâtiments.
Modèles procéduraux (années 80 à 2000, comme dans un village de l'Isère) : citadine (Clio, 205), compacte (306,
Mégane), break (Laguna, 406), ludospace (Kangoo, Berlingo), tracteur, poubelle.
Sorties : ../godot/assets/props/*.glb ; ../godot/world/props/pp_tx_tz.bin : int32 n puis n × (type, x, y, z, cap, r, g, b)
en float32 (couleur de la carrosserie)."""
import hashlib, json, math, os, pickle, shutil
from collections import defaultdict
import numpy as np
from shapely.geometry import LineString, Point, Polygon
from shapely import affinity
from glb import write_glb
from build_espace import Builder
from build_vegetation import Carved
from build_fences import Local, load_parcels, polys_of
from build_buildings import load as load_buildings

OUT_A = "../godot/assets/props"
OUT_W = "../godot/world/props"
TILE = 256.0

PAINTS = [((0.92, 0.92, 0.9), 20), ((0.62, 0.64, 0.66), 18), ((0.18, 0.19, 0.2), 10), ((0.06, 0.06, 0.07), 6),
          ((0.12, 0.18, 0.36), 10), ((0.55, 0.05, 0.05), 10), ((0.12, 0.26, 0.17), 6), ((0.72, 0.66, 0.52), 5),
          ((0.30, 0.12, 0.16), 4), ((0.85, 0.75, 0.25), 2), ((0.25, 0.42, 0.62), 5), ((0.40, 0.42, 0.44), 6)]
TRACTORS = [(0.16, 0.42, 0.14), (0.62, 0.08, 0.06), (0.10, 0.24, 0.55), (0.85, 0.42, 0.06)]


def rnd(key, salt=""):
    return int(hashlib.md5((str(key) + salt).encode()).hexdigest()[:8], 16) / 2 ** 32


def pick(key, salt, items):
    r = rnd(key, salt) * sum(w for _, w in items)
    for v, w in items:
        r -= w
        if r <= 0:
            return v
    return items[-1][0]


# ================================================================================================ modèles
CARS = {
    # longueur, largeur, empattement, rayon de roue, silhouette (z, y) de l'avant (−z) à l'arrière, ceinture
    1: dict(L=3.72, W=1.62, wb=2.45, R=0.29, belt=0.92,
            top=[(0, 0.55), (0.05, 0.72), (0.7, 0.86), (1.25, 1.36), (1.55, 1.40), (3.15, 1.38), (3.55, 1.20), (3.72, 0.95)],
            ws=(0.72, 1.25), rw=(3.2, 3.62)),
    2: dict(L=4.1, W=1.70, wb=2.6, R=0.30, belt=0.95,
            top=[(0, 0.56), (0.06, 0.74), (0.85, 0.90), (1.45, 1.38), (1.75, 1.43), (3.35, 1.40), (3.85, 1.12), (4.1, 0.98)],
            ws=(0.88, 1.45), rw=(3.4, 3.95)),
    3: dict(L=4.6, W=1.75, wb=2.72, R=0.31, belt=0.96,
            top=[(0, 0.56), (0.06, 0.74), (0.95, 0.92), (1.6, 1.40), (1.9, 1.46), (4.35, 1.44), (4.55, 1.30), (4.6, 1.0)],
            ws=(0.97, 1.6), rw=(4.4, 4.58)),
    4: dict(L=4.0, W=1.68, wb=2.6, R=0.30, belt=1.02,
            top=[(0, 0.6), (0.06, 0.82), (0.75, 1.0), (1.25, 1.75), (1.45, 1.80), (3.9, 1.80), (3.98, 1.70), (4.0, 1.0)],
            ws=(0.78, 1.25), rw=(3.92, 3.99)),
}


def car(spec):
    B = Builder()
    L, W, wb, R, belt = spec["L"], spec["W"], spec["wb"], spec["R"], spec["belt"]
    zs_, ys_ = zip(*spec["top"])
    z0 = -L / 2
    top = lambda z: float(np.interp(z - z0, zs_, ys_))
    hw = lambda z: W / 2 * float(np.interp(z - z0, [0, 0.1, 0.5, L - 0.4, L - 0.08, L], [0.9, 0.96, 1.0, 1.0, 0.97, 0.92]))
    bot = 0.24
    arches = (z0 + (L - wb) / 2 - 0.05, z0 + (L - wb) / 2 - 0.05 + wb)
    ws0, ws1 = z0 + spec["ws"][0], z0 + spec["ws"][1]
    rw0, rw1 = z0 + spec["rw"][0], z0 + spec["rw"][1]

    def prof(z):
        yt, w = top(z), hw(z)
        s = float(np.clip((yt - belt - 0.1) / 0.3, 0, 1))
        lv = lambda y: min(y, yt - 0.02)
        return [(0.0, bot), (w - 0.06, bot), (w, bot + 0.06), (w, lv(0.5)), (w, lv(0.7)), (w, lv(belt)),
                (w - 0.12 * s, yt - 0.06 * s), (w - 0.05 - 0.15 * s, yt), (0.0, yt)]

    zs = sorted(set(np.round(np.r_[np.linspace(z0, -z0, 70), [ws0, ws1, rw0, rw1]], 4)))
    rings = []
    for z in zs:
        h = prof(z)
        rings.append((z, [(x, y) for x, y in h] + [(-x, y) for x, y in reversed(h[1:-1])]))
    for (za, ra), (zb, rb) in zip(rings[:-1], rings[1:]):
        k = len(ra)
        for j in range(k):
            a = (ra[j][0], ra[j][1], za); b = (ra[(j + 1) % k][0], ra[(j + 1) % k][1], za)
            c = (rb[(j + 1) % k][0], rb[(j + 1) % k][1], zb); d = (rb[j][0], rb[j][1], zb)
            cen = np.mean([a, b, c, d], axis=0); zm = cen[2]
            out = cen - np.array([0.0, (bot + top(zm)) / 2, zm]); out[2] = 0
            if np.linalg.norm(out) < 1e-6:
                continue
            if abs(cen[0]) > hw(zm) - 0.2 and any(math.hypot(zm - zz, cen[1] - R) < R + 0.05 for zz in arches):
                continue
            n = np.cross(np.subtract(b, a), np.subtract(d, a))
            if np.dot(n, out) < 0:
                n = -n
            n = n / max(np.linalg.norm(n), 1e-9)
            y = cen[1]
            if n[1] < -0.9:
                m = "plastic"
            elif ws0 < zm < ws1 and n[1] > 0.3 and abs(cen[0]) < hw(zm) - 0.07:
                m = "glass"
            elif rw0 < zm < rw1 and n[1] > 0.2 and abs(cen[0]) < hw(zm) - 0.07:
                m = "glass"
            elif abs(n[0]) > 0.45 and belt + 0.03 < y < top(zm) - 0.05 and ws1 - 0.05 < zm < rw0 + 0.05:
                m = "glass"
            elif y < 0.36:
                m = "plastic"
            else:
                m = "paint"
            B.quad(m, a, b, c, d, out)
    # faces avant et arrière
    for z, sg in ((zs[0], -1), (zs[-1], 1)):
        h = prof(z)
        for j in range(len(h) - 1):
            (xa, ya), (xb, yb) = h[j], h[j + 1]
            ym = (ya + yb) / 2
            m = "plastic" if ym < 0.38 else ("glass" if sg > 0 and spec["rw"][1] > L - 0.1 and belt < ym < top(z) - 0.05 else "paint")
            B.quad(m, (-xa, ya, z), (xa, ya, z), (xb, yb, z), (-xb, yb, z), (0, 0, sg))
    # détails : phares, feux, calandre, plaques, rétroviseurs
    zf, zr = zs[0] - 0.004, zs[-1] + 0.004
    yl = min(top(zs[0] + 0.02) - 0.08, 0.68)
    for sx in (-1, 1):
        B.box("lamp", (sx * (W / 2 - 0.22), yl, zf), (0.14, 0.05, 0.006))
        B.box("tail", (sx * (W / 2 - 0.14), yl + 0.05, zr), (0.11, 0.07, 0.006))
        B.box("plastic", (sx * (hw(ws0) + 0.05), belt + 0.08, ws1 - 0.15), (0.05, 0.05, 0.08))
    B.box("plastic", (0, yl - 0.02, zf), (W / 2 - 0.42, 0.05, 0.006))
    B.box("plate", (0, 0.42, zf - 0.002), (0.24, 0.05, 0.004))
    B.box("plate", (0, 0.45, zr + 0.002), (0.24, 0.05, 0.004))
    # roues (pneu + enjoliveur), posées dans les passages
    for za in arches:
        for sx in (-1, 1):
            cx = sx * (hw(za) - 0.12)
            n = 14
            for i in range(n):
                a0 = 2 * math.pi * i / n; a1 = 2 * math.pi * (i + 1) / n
                p = lambda r, a, x: (x, R + r * math.cos(a), za + r * math.sin(a))
                B.quad("rubber", p(R, a0, cx - 0.09), p(R, a0, cx + 0.09), p(R, a1, cx + 0.09), p(R, a1, cx - 0.09),
                       (0, math.cos((a0 + a1) / 2), math.sin((a0 + a1) / 2)))
                xo = cx + sx * 0.092
                B.tri("hubcap", (xo, R, za), p(R * 0.68, a0, xo), p(R * 0.68, a1, xo), (sx, 0, 0))
                B.tri("rubber", (xo - sx * 0.001, R, za), p(R, a0, xo - sx * 0.001), p(R, a1, xo - sx * 0.001), (sx, 0, 0))
    return B


def tractor():
    B = Builder()
    # roues arrière hautes, avant petites ; capot, cabine vitrée, ailes
    def wheel(cx, cz, r, w):
        n = 18
        for i in range(n):
            a0 = 2 * math.pi * i / n; a1 = 2 * math.pi * (i + 1) / n
            p = lambda rr, a, x: (x, r + rr * math.cos(a), cz + rr * math.sin(a))
            B.quad("rubber", p(r, a0, cx - w), p(r, a0, cx + w), p(r, a1, cx + w), p(r, a1, cx - w),
                   (0, math.cos((a0 + a1) / 2), math.sin((a0 + a1) / 2)))
            sx = 1 if cx > 0 else -1
            B.tri("rim", (cx + sx * w, r, cz), p(r * 0.6, a0, cx + sx * w), p(r * 0.6, a1, cx + sx * w), (sx, 0, 0))
            B.tri("rubber", (cx + sx * (w - 0.001), r, cz), p(r, a0, cx + sx * (w - 0.001)), p(r, a1, cx + sx * (w - 0.001)), (sx, 0, 0))
    for sx in (-1, 1):
        wheel(sx * 0.82, 0.85, 0.78, 0.25)
        wheel(sx * 0.72, -1.25, 0.48, 0.15)
        B.box("paint", (sx * 0.82, 1.68, 0.85), (0.27, 0.04, 0.55))             # ailes arrière
    B.box("paint", (0, 1.05, -1.0), (0.42, 0.42, 1.1))                          # capot
    B.box("plastic", (0, 0.62, -0.6), (0.36, 0.2, 1.3))                         # châssis
    B.box("plastic", (0, 1.05, -2.11), (0.36, 0.3, 0.02))                       # calandre
    B.box("lamp", (0.25, 1.32, -2.12), (0.06, 0.04, 0.01)); B.box("lamp", (-0.25, 1.32, -2.12), (0.06, 0.04, 0.01))
    B.box("plastic", (0, 1.3, 0.75), (0.55, 0.35, 0.55))                        # bas de cabine
    for sx in (-1, 1):
        for sz in (-1, 1):
            B.box("plastic", (sx * 0.55, 2.15, 0.75 + sz * 0.52), (0.03, 0.5, 0.03))
    B.box("glass", (0, 2.15, 0.22), (0.52, 0.48, 0.01)); B.box("glass", (0, 2.15, 1.28), (0.52, 0.48, 0.01))
    B.box("glass", (0.555, 2.15, 0.75), (0.01, 0.48, 0.5)); B.box("glass", (-0.555, 2.15, 0.75), (0.01, 0.48, 0.5))
    B.box("paint", (0, 2.68, 0.75), (0.62, 0.05, 0.62))                         # toit
    B.box("plastic", (0.25, 1.75, -1.6), (0.04, 0.35, 0.04))                    # échappement
    return B


def bin_():
    B = Builder()
    B.box("paint", (0, 0.5, 0), (0.29, 0.48, 0.36))
    B.box("lid", (0, 1.0, 0.0), (0.31, 0.03, 0.38))
    for sx in (-1, 1):
        B.box("rubber", (sx * 0.24, 0.1, 0.36), (0.04, 0.1, 0.1))
    return B


def models():
    os.makedirs(OUT_A, exist_ok=True)
    for t, spec in CARS.items():
        write_glb("%s/car%d.glb" % (OUT_A, t), car(spec).prims(smooth=("paint", "glass")), "car%d" % t)
    write_glb(OUT_A + "/tractor.glb", tractor().prims(smooth=()), "tractor")
    write_glb(OUT_A + "/bin.glb", bin_().prims(smooth=()), "bin")


# ================================================================================================ placement
def main():
    models()
    shutil.rmtree(OUT_W, ignore_errors=True); os.makedirs(OUT_W)
    plan = json.load(open("data/routes_plan.json"))
    zone = Polygon(plan["zone"]).buffer(150)
    dem = Carved()
    ways = pickle.load(open("data/roads.pkl", "rb"))["ways"]
    ROAD = Local([LineString(w["P"]).buffer(w["w"] / 2 + (1.6 if any(w["sidewalk"]) else 0.0) + 0.5
                                            + {"motorway": 10.0, "motorway_link": 4.0}.get(w["cls"], 0.0))
                  for w in ways if len(w["P"]) > 1])
    blds = load_buildings()
    BLD = Local([g.buffer(0.4) for _, g in blds])
    parcels = load_parcels()
    PAR = Local([g for _, g in parcels])
    EDGE = Local([LineString(g.exterior.coords) for _, g in parcels])
    gates = json.load(open("data/fences_gates.json"))
    out = []
    used = []

    def free(box, inner=None):
        if ROAD.near(box, 0.0) or BLD.near(box, 0.0):
            return False
        if any(box.intersects(u) for u in used):
            return False
        if inner is not None:
            return box.within(inner)
        return not EDGE.near(box, 0.6)

    def rect(c, d, L, W):
        d = d / np.linalg.norm(d); n = np.array([-d[1], d[0]])
        pts = [c + d * L / 2 + n * W / 2, c - d * L / 2 + n * W / 2, c - d * L / 2 - n * W / 2, c + d * L / 2 - n * W / 2]
        return Polygon(pts)

    ncar = nbin = 0
    for gi, g in enumerate(gates):
        a, b = np.array(g["a"]), np.array(g["b"])
        m = (a + b) / 2
        if not zone.contains(Point(m)):
            continue
        t = (b - a) / max(np.linalg.norm(b - a), 1e-6)
        n = np.array([-t[1], t[0]])
        # côté intérieur : celui qui s'éloigne de la route
        if ROAD.dist(Point(m + n * 3)) < ROAD.dist(Point(m - n * 3)):
            n = -n
        par = [p for p in PAR.near(Point(m + n * 3), 0.0)]
        if not par:
            continue
        inner = par[0].buffer(-0.6)
        if rnd(gi, "car") < 0.62:
            typ = pick(gi, "type", [(1, 34), (2, 30), (3, 18), (4, 18)])
            L = CARS[typ]["L"] + 0.2; W = CARS[typ]["W"] + 0.25
            for back in (1.2, 2.0, 3.0):
                c = m + n * (back + L / 2)
                box = rect(c, n, L, W)
                if free(box, inner):
                    used.append(box)
                    col = pick(gi, "col", PAINTS)
                    cap = math.degrees(math.atan2(-n[0], -n[1]))          # capot (−z du modèle) vers la maison
                    out.append((typ, c[0], c[1], cap, col)); ncar += 1
                    # deuxième voiture à côté
                    if rnd(gi, "car2") < 0.22:
                        typ2 = pick(gi, "type2", [(1, 40), (2, 30), (4, 30)])
                        L2 = CARS[typ2]["L"] + 0.2
                        for side in (1, -1):
                            c2 = m + n * (back + L2 / 2) + t * side * (W + 0.6)
                            box2 = rect(c2, n, L2, CARS[typ2]["W"] + 0.25)
                            if free(box2, inner):
                                used.append(box2)
                                out.append((typ2, c2[0], c2[1], cap, pick(gi, "col2", PAINTS))); ncar += 1
                                break
                    break
        if rnd(gi, "bin") < 0.4:
            half = np.linalg.norm(b - a) / 2
            for side in (1, -1):
                c = m + n * 0.9 + t * side * (half + 0.7)
                box = rect(c, t, 1.4, 0.8)
                if free(box, inner):
                    used.append(box)
                    capb = math.degrees(math.atan2(n[0], n[1]))
                    out.append((6, c[0] - t[0] * side * 0.33, c[1] - t[1] * side * 0.33, capb, (0.16, 0.36, 0.2)))
                    out.append((6, c[0] + t[0] * side * 0.33, c[1] + t[1] * side * 0.33, capb, (0.42, 0.44, 0.45)))
                    nbin += 2
                    break
    # voitures sur les places de parking (parking.py) : un tiers des places occupées, garées en marche avant
    npk = 0
    if os.path.exists("data/parkings.pkl"):
        for li, lot in enumerate(pickle.load(open("data/parkings.pkl", "rb"))["lots"]):
            for si, c in enumerate(lot["stalls"]):
                key = "pk%d_%d" % (li, si)
                if rnd(key, "occ") > 0.34:
                    continue
                c = np.asarray(c)
                ctr = c.mean(axis=0)
                along = c[1] - c[0]; deep = c[3] - c[0]
                parallel = np.linalg.norm(along) > np.linalg.norm(deep)
                v = along if parallel else deep                       # capot : vers le fond de la place
                if parallel and rnd(key, "dir") < 0.5:
                    v = -v
                typ = pick(key, "type", [(1, 34), (2, 30), (3, 18), (4, 18)])
                box = rect(ctr, v, CARS[typ]["L"] + 0.1, CARS[typ]["W"] + 0.1)
                if ROAD.near(box, 0.0) or BLD.near(box, 0.0):
                    continue
                used.append(box)
                out.append((typ, ctr[0], ctr[1], math.degrees(math.atan2(-v[0], -v[1])), pick(key, "col", PAINTS)))
                npk += 1
    print(npk, "voitures sur les parkings")
    # tracteurs près des grands bâtiments agricoles
    ntr = 0
    for k, (props, g) in enumerate(blds):
        if props.get("usage_1") != "Agricole" or g.area < 150 or not zone.contains(g.centroid):
            continue
        if rnd(k, "tr") > 0.45:
            continue
        par = PAR.near(g.centroid, 0.0)
        inner = par[0].buffer(-0.6) if par else None
        cx, cy = g.centroid.x, g.centroid.y
        R0 = math.sqrt(g.area) / 2 + 4
        for i in range(16):
            ang = rnd(k, "a%d" % i) * 2 * math.pi
            c = np.array([cx + math.cos(ang) * (R0 + i * 0.6), cy + math.sin(ang) * (R0 + i * 0.6)])
            d = np.array([math.cos(ang + 1.3), math.sin(ang + 1.3)])
            box = rect(c, d, 4.6, 2.5)
            if free(box, inner):
                used.append(box)
                out.append((5, c[0], c[1], math.degrees(math.atan2(-d[0], -d[1])), pick(k, "tc", [(c_, 1) for c_ in TRACTORS])))
                ntr += 1
                break
    T = defaultdict(list)
    for typ, x, z, cap, col in out:
        y = float(dem.h(np.array([x]), np.array([z]))[0])
        T[(int(math.floor(x / TILE)), int(math.floor(z / TILE)))].append((typ, x, y, z, cap) + tuple(col))
    for (tx, tz), S in T.items():
        open("%s/pp_%d_%d.bin" % (OUT_W, tx, tz), "wb").write(np.int32(len(S)).tobytes() + np.array(S, "<f4").tobytes())
    print(ncar, "voitures,", nbin, "poubelles,", ntr, "tracteurs,", len(T), "tuiles")


if __name__ == "__main__":
    main()
