"""Animaux dans les prés et clôtures des pâtures (la logique prime sur la donnée brute) :
 - prairies du RPG (PPH permanentes, PTR temporaires, SPH pâturées) : environ une sur deux est pâturée ;
 - petites prairies près des maisons : chevaux ou moutons ; ailleurs : troupeau de vaches (Montbéliardes surtout,
   quelques Charolaises), environ 1,2 bête par hectare, en 1 ou 2 groupes, à l'écart des bords ;
 - les prés pâturés sont clos : piquets et 3 fils de barbelé posés 0,7 m à l'intérieur de la parcelle, coupés près
   des routes (jamais sur la chaussée ni le trottoir), des bâtiments et là où une haie ferme déjà le pré.
Modèles : blender_animaux.py. Sortie : ../godot/world/animaux/a_tx_tz.bin : int32 n, n × 17 float32
(modèle 0 vache, 1 mouton, 2 cheval, 3 travée de clôture ; base 3 × 3 colonnes, origine, robe, phase, 0, 0)."""
import hashlib, json, math, os, pickle, shutil
from collections import defaultdict
import numpy as np
from shapely.geometry import shape, LineString, Point, Polygon
from shapely.ops import transform
import geo
from build_fences import Local, lines_of
from build_vegetation import Carved
from build_buildings import load as load_buildings

OUT = "../godot/world/animaux"
TILE = 256.0
PRES = ("PPH", "PTR", "SPH", "PRL")


def rnd(key, salt=""):
    return int(hashlib.md5((str(key) + salt).encode()).hexdigest()[:8], 16) / 2 ** 32


def inst(model, p, y, ang, custom, sx=1.0):
    c, s = math.cos(ang), math.sin(ang)
    X = (c * sx, 0.0, -s * sx); Y = (0.0, 1.0, 0.0); Z = (s, 0.0, c)
    return (model,) + X + Y + Z + (p[0], y, p[1]) + tuple(custom)


def main():
    shutil.rmtree(OUT, ignore_errors=True); os.makedirs(OUT)
    dem = Carved()
    zone = Polygon(json.load(open("data/routes_plan.json"))["zone"])
    ways = [w for w in pickle.load(open("data/roads.pkl", "rb"))["ways"] if len(w["P"]) > 1]
    ROAD = Local([LineString(w["P"]).buffer(w["w"] / 2 + (1.6 if any(w["sidewalk"]) else 0.0) + 1.0) for w in ways])
    blds = load_buildings()
    BLD = Local([g.buffer(1.0) for _, g in blds])
    HOUSE = Local([g for p, g in blds if p.get("usage_1") == "Résidentiel"])
    haies = [transform(lambda x, y, z=None: geo.to_local(x, y), shape(f["geometry"])) for f in json.load(open("data/haies.json"))["features"]]
    HEDGE = Local(haies)
    out = []
    stats = defaultdict(int)
    for f in json.load(open("data/rpg.json"))["features"]:
        pr = f["properties"]
        if pr.get("code_cultu") not in PRES:
            continue
        g = transform(lambda x, y, z=None: geo.to_local(x, y), shape(f["geometry"])).buffer(0)
        if g.geom_type != "Polygon":
            g = max(getattr(g, "geoms", [g]), key=lambda q: q.area)
        if g.is_empty or not zone.contains(g.centroid):
            continue
        key = pr.get("id_parcel") or "%s_%s" % (pr.get("num_ilot"), pr.get("num_parcel"))
        if rnd(key, "pature") > 0.5:
            continue
        ha = g.area / 1e4
        near_house = HOUSE.dist(g.centroid, 200.0) < 150.0 + math.sqrt(g.area) / 2
        if ha < 1.5 and near_house:
            sp = 2 if rnd(key, "esp") < 0.5 else 1
            n = int(1 + rnd(key, "n") * 3) if sp == 2 else int(4 + rnd(key, "n") * 7)
        else:
            sp = 0
            n = int(np.clip(ha * 1.2, 3, 22))
        inner = g.buffer(-6.0)
        if inner.is_empty or inner.area < 30:
            continue
        # troupeau : 1 ou 2 groupes
        minx, miny, maxx, maxy = inner.bounds
        centers = []
        for k in range(40):
            p = Point(minx + rnd(key, "cx%d" % k) * (maxx - minx), miny + rnd(key, "cy%d" % k) * (maxy - miny))
            if inner.contains(p) and not BLD.near(p, 3.0):
                centers.append(p)
                if len(centers) >= (2 if n > 8 else 1):
                    break
        if not centers:
            continue
        placed = []
        robe = rnd(key, "robe")
        for i in range(n * 4):
            if len(placed) >= n:
                break
            c = centers[i % len(centers)]
            r = 2.0 + rnd(key, "r%d" % i) * (6.0 + n * 0.6)
            a = rnd(key, "a%d" % i) * math.tau
            p = (c.x + math.cos(a) * r, c.y + math.sin(a) * r)
            if not inner.contains(Point(p)) or any(math.hypot(p[0] - q[0], p[1] - q[1]) < (2.6 if sp != 1 else 1.3) for q in placed):
                continue
            placed.append(p)
            y = float(dem.h(np.array([p[0]]), np.array([p[1]]))[0])
            # robe : vaches surtout pie rouge (Montbéliarde), parfois blanches (Charolaise) ; chevaux bais, alezans, gris
            rb = (0.0 if robe < 0.75 else 1.0) if sp == 0 else (rnd(key, "rb%d" % i) if sp == 2 else 0.0)
            out.append(inst(sp, p, y, rnd(key, "h%d" % i) * math.tau, (rb, rnd(key, "ph%d" % i), 0.0, 0.0)))
        stats[("vaches", "moutons", "chevaux")[sp]] += len(placed)
        # clôture : contour intérieur, coupé près des routes, des bâtiments et des haies
        ring = LineString(g.buffer(-0.7).exterior.coords) if not g.buffer(-0.7).is_empty and g.buffer(-0.7).geom_type == "Polygon" else None
        if ring is None:
            continue
        cut = ROAD.cut(ring)
        for ln in lines_of(cut):
            L = ln.length
            if L < 2.0:
                continue
            n_sp = max(1, int(math.ceil(L / 4.0)))
            for k in range(n_sp):
                a = np.asarray(ln.interpolate(k * L / n_sp).coords[0]); b = np.asarray(ln.interpolate((k + 1) * L / n_sp).coords[0])
                m = (a + b) / 2
                if BLD.near(Point(m), 0.0) or HEDGE.near(Point(m), 1.5):
                    continue
                ya = float(dem.h(np.array([a[0]]), np.array([a[1]]))[0]); yb = float(dem.h(np.array([b[0]]), np.array([b[1]]))[0])
                v = np.array([b[0] - a[0], yb - ya, b[1] - a[1]])
                X = tuple(v); Y = (0.0, 1.0, 0.0)
                h = np.array([v[0], 0, v[2]]); h /= max(np.linalg.norm(h), 1e-6)
                Z = (-h[2], 0.0, h[0])
                out.append((3,) + X + Y + Z + (a[0], ya - 0.05, a[1], 0.0, 0.0, 0.0, 0.0))
                out.append((4, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, a[0], ya - 0.05, a[1], 0.0, 0.0, 0.0, 0.0))
                stats["travées"] += 1
    T = defaultdict(list)
    for r in out:
        T[(int(math.floor(r[10] / TILE)), int(math.floor(r[12] / TILE)))].append(r)
    for (tx, tz), S in T.items():
        open("%s/a_%d_%d.bin" % (OUT, tx, tz), "wb").write(np.int32(len(S)).tobytes() + np.array(S, "<f4").tobytes())
    print(dict(stats), len(T), "tuiles")


if __name__ == "__main__":
    main()
