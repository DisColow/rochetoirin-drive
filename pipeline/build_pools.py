"""Piscines des jardins, repérées sur l'orthophoto IGN à 0,5 m/px (fetch_ortho_hd.py) : eau bleu turquoise claire.
La logique prime sur la donnée : on ne garde une tache que si c'est vraisemblablement une piscine privée
 - surface de 9 à 120 m², petit côté d'au moins 2,4 m, allongement < 3,5 (pas une rivière, une bâche, une voiture) ;
 - entièrement dans une parcelle cadastrale habitée (une maison dessus), à plus de 0,8 m de ses limites : jamais hors
   des propriétés ;
 - jamais sur un bâtiment (toit bleu, bâche), une route, un trottoir, un parking ou dans l'eau (étangs, rivières).
Forme : rectangle orienté (rectangle minimal de la tache) ou ronde (piscine hors-sol, tache circulaire).
Sortie : ../godot/world/pools.json [{x, z, y, L, W, a, round, hors_sol}] (y : sol le plus haut sous la piscine),
data/pools.pkl (polygones, pour build_ground.py et build_props.py).
Ordre : après build_buildings.py et fetch_cadastre.py ; avant build_ground.py et build_props.py."""
import json, math, os, pickle
import numpy as np
from PIL import Image
from scipy import ndimage as ndi
import shapely
from shapely.geometry import LineString, Polygon, MultiPoint, shape
from shapely.prepared import prep
from build_fences import Local, load_parcels
from build_buildings import load as load_buildings, classify
from build_vegetation import Carved
from build_roads import REG

RES = 0.5
OUT = "../godot/world/pools.json"


def candidates(i, j):
    p = "data/ortho_hd/r_%d_%d.jpg" % (i, j)
    if not os.path.exists(p):
        return []
    a = np.asarray(Image.open(p)).astype(np.float32)
    R, G, B = a[..., 0], a[..., 1], a[..., 2]
    L = (R + G + B) / 3
    m = (B > R + 35) & (B > G - 5) & (G > R + 10) & (L > 90)
    m = ndi.binary_opening(m, iterations=1)
    lab, n = ndi.label(m)
    out = []
    for k, sl in enumerate(ndi.find_objects(lab), 1):
        mk = lab[sl] == k
        area = mk.sum() * RES * RES
        if area < 9 or area > 120:
            continue
        js, is_ = np.nonzero(mk)
        x = i * REG + RES / 2 + (sl[1].start + is_) * RES
        z = j * REG + RES / 2 + (sl[0].start + js) * RES
        hull = MultiPoint(np.c_[x, z]).convex_hull.buffer(RES / 2, join_style="mitre")
        if hull.area < 9:
            continue
        rr = hull.minimum_rotated_rectangle
        c = np.asarray(rr.exterior.coords)[:4]
        e1, e2 = c[1] - c[0], c[2] - c[1]
        l1, l2 = float(np.hypot(*e1)), float(np.hypot(*e2))
        Lg, W = max(l1, l2), min(l1, l2)
        if W < 2.4 or Lg / W > 3.5:
            continue
        fill = area / hull.area
        circ = hull.length ** 2 / (4 * math.pi * hull.area)
        rnd_ = fill < 0.9 and circ < 1.12 and Lg / W < 1.15
        ang = math.atan2(*(e1 if l1 >= l2 else e2)[::-1])
        out.append(dict(poly=hull if rnd_ else rr, c=np.asarray(hull.centroid.coords[0]), L=Lg, W=W, a=ang,
                        round=rnd_, area=area))
    return out


def main():
    plan = json.load(open("data/routes_plan.json"))
    zone = prep(Polygon(plan["zone"]))
    ways = pickle.load(open("data/roads.pkl", "rb"))["ways"]
    ROAD = Local([LineString(w["P"]).buffer(w["w"] / 2 + (1.6 if any(w["sidewalk"]) else 0.0) + 1.0)
                  for w in ways if len(w["P"]) > 1])
    blds = load_buildings()
    BLD = Local([g.buffer(0.5) for _, g in blds])
    homes = Local([g for p, g in blds if classify(p, g) in ("maison", "collectif") and g.area > 40])
    parcels = [g for _, g in load_parcels()]
    PAR = Local(parcels)
    water = []
    if os.path.exists("data/eau_surfaces.json"):
        from build_fences import to_local_geom
        for f in json.load(open("data/eau_surfaces.json"))["features"]:
            if f.get("geometry"):
                water.append(to_local_geom(shape(f["geometry"])).buffer(2.0))
    WAT = Local(water)
    PK = Local([l["geom"] for l in pickle.load(open("data/parkings.pkl", "rb"))["lots"]]) if os.path.exists("data/parkings.pkl") else Local([])
    dem = Carved()
    stats = dict(taches=0, hors_zone=0, route=0, batiment=0, eau=0, parking=0, hors_propriete=0, gardees=0)
    out, polys = [], []
    for (i, j) in [tuple(r) for r in plan["regions"]]:
        for c in candidates(i, j):
            stats["taches"] += 1
            g = c["poly"]
            deck = g.buffer(0.35, join_style="mitre")                     # margelle comprise
            if not zone.contains(g.centroid):
                stats["hors_zone"] += 1; continue
            if ROAD.near(deck, 0.0):
                stats["route"] += 1; continue
            if BLD.near(deck, 0.0):
                stats["batiment"] += 1; continue
            if WAT.near(g, 0.0):
                stats["eau"] += 1; continue
            if PK.near(deck, 0.5):
                stats["parking"] += 1; continue
            # dans une parcelle habitée, loin de ses limites (jamais hors des propriétés)
            ok = False
            for par in PAR.near(g.centroid, 0.0):
                if par.buffer(-0.8).contains(deck) and any(h.intersection(par).area > 20 for h in homes.near(par, 0.0)):
                    ok = True; break
            if not ok:
                stats["hors_propriete"] += 1; continue
            if any(p.intersects(deck) for p in polys[-50:]):
                continue
            ring = np.asarray(deck.exterior.coords)
            hs = dem.h(ring[:, 0], ring[:, 1])
            x, z = c["c"]
            out.append(dict(x=round(float(x), 2), z=round(float(z), 2), y=round(float(hs.max()) + 0.05, 2),
                            y0=round(float(hs.min()), 2), L=round(c["L"], 2), W=round(c["W"], 2),
                            a=round(c["a"], 4), round=bool(c["round"])))
            polys.append(deck)
            stats["gardees"] += 1
    json.dump(out, open(OUT, "w"))
    pickle.dump(polys, open("data/pools.pkl", "wb"))
    print(stats)


if __name__ == "__main__":
    main()
