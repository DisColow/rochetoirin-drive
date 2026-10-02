"""Vérification automatique de la cohérence de la scène (règle « la logique prime », docs/kb/21-coherence.md).

Lit les assets générés et data/surfaces.pkl (enrobé + trottoirs, écrit par prepare_street.py) et compte :
  * troncs d'arbres / arbustes sur la chaussée ou les trottoirs ;
  * obstacles (clôtures, haies, murets, mobilier, voitures) empiétant sur la chaussée, ou sur les trottoirs
    (sauf poteaux : lampadaires, panneaux) ;
  * piscines touchant une route ou un bâtiment ;
  * routes qui se chevauchent hors carrefours ;
  * trous dans les clôtures / haies d'une même limite.
Sortie : résumé + data/coherence.json (positions, pour corriger). Code de retour 1 s'il reste des violations.
"""
import json, math, os, pickle, struct, sys
import numpy as np
from shapely.geometry import Point, Polygon, LineString
from shapely.strtree import STRtree
from shapely.ops import unary_union
import shapely

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "data")
ASSETS = os.path.join(HERE, "..", "app", "src", "main", "assets")


def rings(path):
    b = open(path, "rb").read(); n = struct.unpack("<i", b[4:8])[0]; p = 8; out = []
    for _ in range(n):
        k = struct.unpack("<i", b[p:p + 4])[0]
        out.append(np.frombuffer(b[p + 4:p + 4 + k * 8], "<f4").reshape(-1, 2).astype(float)); p += 4 + k * 8
    return out


def trees():
    b = open(os.path.join(ASSETS, "trees.bin"), "rb").read(); n = struct.unpack("<i", b[24:28])[0]; p = 28; out = []
    for _ in range(n):
        c = struct.unpack("<i", b[p + 8:p + 12])[0]; p += 12
        out.append(np.frombuffer(b[p:p + c * 24], "<f4").reshape(-1, 6)); p += c * 24
    return np.vstack(out)


def main():
    S = pickle.load(open(os.path.join(DATA, "surfaces.pkl"), "rb"))
    road = S["carriage"].buffer(-0.15)
    walk = S["walk"]
    shapely.prepare(road); shapely.prepare(walk)
    rep = {}
    # --- arbres
    T = trees()
    pts = shapely.points(T[:, 0], T[:, 2])
    on_road = shapely.contains(road, pts)
    on_walk = shapely.contains(walk, pts)
    rep["arbres sur la chaussée"] = T[on_road][:, [0, 2]].round(1).tolist()
    rep["arbres sur les trottoirs"] = T[on_walk & ~on_road][:, [0, 2]].round(1).tolist()
    # --- obstacles posés par prepare_street (clôtures, haies, mobilier…) : après les bâtiments dans collide.bin
    allr = rings(os.path.join(ASSETS, "collide.bin"))
    nb = len(rings(os.path.join(DATA, "collide_buildings.bin")))
    obs = [Polygon(r).buffer(0) for r in allr[nb:] if len(r) >= 3]
    bad_r, bad_w = [], []
    for g in obs:
        if g.is_empty or g.area < 1e-4:
            continue
        pole = g.area < 0.6
        ov = lambda big: shapely.clip_by_rect(big, *g.bounds).intersection(g).area if big.intersects(g) else 0.0
        if ov(road) > 0.05 * g.area + 0.02:
            bad_r.append(list(np.round(g.centroid.coords[0], 1)))
        elif not pole and ov(walk) > 0.25 * g.area:
            bad_w.append(list(np.round(g.centroid.coords[0], 1)))
    rep["obstacles sur la chaussée"] = bad_r
    rep["obstacles sur les trottoirs"] = bad_w
    # --- piscines
    pp = os.path.join(DATA, "pools.json")
    bad_p = []
    if os.path.exists(pp):
        bl = [Polygon(r).buffer(0) for r in allr[:nb] if len(r) >= 3]
        bt = STRtree(bl)
        for ring in json.load(open(pp)):
            g = Polygon(ring)
            if g.distance(S["carr_ext"]) < 2.0 or any(bl[k].intersects(g) for k in bt.query(g)):
                bad_p.append(list(np.round(g.centroid.coords[0], 1)))
    rep["piscines mal placées"] = bad_p
    # --- routes superposées (hors carrefours : on retire 1,5 × la largeur autour des nœuds partagés)
    rows = pickle.load(open(os.path.join(DATA, "road_rows.pkl"), "rb"))
    rib, ends = [], []
    for r in rows:
        if r["cls"] == "rail" or r["bridge"] or len(r["P"]) < 2:
            continue
        rib.append((LineString(r["P"]).buffer(r["width"] / 2 - 0.2, cap_style=2), r))
    nodes = {}
    for _, r in rib:
        for n in r["part"]:
            nodes[n] = nodes.get(n, 0) + 1
    tree = STRtree([g for g, _ in rib])
    over = []
    for i, (g, r) in enumerate(rib):
        for j in tree.query(g):
            if j <= i:
                continue
            h, r2 = rib[j]
            inter = g.intersection(h)
            if inter.area < 15:
                continue
            if {r["cls"], r2["cls"]} <= {"motorway", "motorway_link"} and r["cls"] != r2["cls"]:
                continue                                 # bretelle d'autoroute : biseau de sortie / d'entrée
            shared = set(r["part"]) & set(r2["part"])
            # zone de carrefour : autour des extrémités des deux voies
            jz = unary_union([Point(q).buffer(max(r["width"], r2["width"]) * 1.6 + 4.0)
                              for q in (r["P"][0], r["P"][-1], r2["P"][0], r2["P"][-1])])
            rest = inter.difference(jz).area
            if rest > 15:
                over.append(dict(a=r.get("name") or r["cls"], b=r2.get("name") or r2["cls"], m2=round(rest),
                                 at=list(np.round(inter.centroid.coords[0], 1))))
    rep["routes superposées"] = over
    # --- trous dans les clôtures (journal écrit par prepare_quartier)
    fp = os.path.join(DATA, "fences.json")
    gaps = []
    blds = [Polygon(r).buffer(0.3) for r in allr[:nb] if len(r) >= 3]
    btree = STRtree(blds)
    if os.path.exists(fp):
        F = json.load(open(fp))
        by = {}
        for s in F["segments"]:
            by.setdefault(s["line"], []).append(s)
        for line, segs in by.items():
            segs.sort(key=lambda s: s["t0"])
            for s0, s1 in zip(segs, segs[1:]):
                g = s1["t0"] - s0["t1"]
                if s0.get("gate") or s1.get("gate"):
                    continue
                if 0.25 < g < 6.0:
                    pt = Point(s0["b"])
                    if any(blds[k].distance(pt) < 1.5 for k in btree.query(pt.buffer(3))):
                        continue                         # mur de maison en limite : la clôture s'y appuie
                    gaps.append(dict(line=line, at=s0["b"], m=round(g, 2)))
    rep["trous dans les clôtures"] = gaps
    json.dump(rep, open(os.path.join(DATA, "coherence.json"), "w"), indent=0)
    tot = 0
    for k, v in rep.items():
        print("%5d  %s" % (len(v), k)); tot += len(v)
    print("total :", tot)
    return tot


if __name__ == "__main__":
    sys.exit(1 if main() else 0)
