"""Champs cultivés en 3D : parcelles RPG 2024 par tuile de 256 m (polygones découpés à la tuile), type de culture et
direction des rangs (grand côté du champ). Le jeu génère les rangs autour de la voiture (scripts/crops.gd).
Types : 0 maïs (MIS, MIE, SOG, SGH ...), 1 céréales (blé, orge, triticale, avoine, seigle), 2 colza / soja / pois
(feuillage), 3 tournesol.
Sortie : ../godot/world/crops/c_tx_tz.bin : int32 n ; par champ : int32 type, float32 dir_x, dir_z, int32 nb points,
float32 (x, z) × nb (contour extérieur)."""
import json, math, os, shutil, struct
import numpy as np
from shapely.geometry import shape, box, Polygon
from shapely.ops import transform
import geo

OUT = "../godot/world/crops"
TILE = 256.0
TYPES = {"MIS": 0, "MIE": 0, "MID": 0, "SOG": 0, "SGH": 0, "SGP": 0,
         "BTH": 1, "BTP": 1, "BDH": 1, "BDP": 1, "ORH": 1, "ORP": 1, "TTH": 1, "TTP": 1, "AVH": 1, "AVP": 1, "SGH_": 1,
         "SEH": 1, "SEP": 1, "CPL": 1, "EPE": 1,
         "CZH": 2, "CZP": 2, "SOJ": 2, "PPO": 2, "PHI": 2, "FVL": 2, "LDH": 2, "LDP": 2, "MCR": 2,
         "TRN": 3}


def main():
    shutil.rmtree(OUT, ignore_errors=True); os.makedirs(OUT)
    zone = Polygon(json.load(open("data/routes_plan.json"))["zone"]).buffer(200)
    # chaussées (+ 1,2 m) : les cultures s'arrêtent avant la route
    import pickle
    from shapely.geometry import LineString
    from shapely.strtree import STRtree
    ways = pickle.load(open("data/roads.pkl", "rb"))["ways"]
    roads = [LineString(w["P"]).buffer(w["w"] / 2 + 1.2 + (1.6 if any(w["sidewalk"]) else 0.0)
                                       + {"motorway": 11.0, "motorway_link": 5.0}.get(w["cls"], 0.0), cap_style="flat")
             for w in ways if len(w["P"]) > 1]
    rtree = STRtree(roads)
    tiles = {}
    stats = {}
    for f in json.load(open("data/rpg.json"))["features"]:
        t = TYPES.get(f["properties"].get("code_cultu") or "")
        if t is None:
            continue
        g = transform(lambda x, y, z=None: geo.to_local(x, y), shape(f["geometry"])).buffer(-1.5)   # tournière
        if g.is_empty or not g.intersects(zone):
            continue
        near = [roads[k] for k in rtree.query(g)]
        if near:
            from shapely.ops import unary_union
            g = g.difference(unary_union(near))
        for p in getattr(g, "geoms", [g]):
            if p.area < 400:
                continue
            r = p.minimum_rotated_rectangle
            C = np.asarray(r.exterior.coords)[:4]
            e = [C[1] - C[0], C[2] - C[1]]
            d = e[int(np.argmax([np.hypot(*v) for v in e]))]
            d = d / np.hypot(*d)
            mnx, mnz, mxx, mxz = p.bounds
            for tx in range(int(mnx // TILE), int(mxx // TILE) + 1):
                for tz in range(int(mnz // TILE), int(mxz // TILE) + 1):
                    q = p.intersection(box(tx * TILE, tz * TILE, (tx + 1) * TILE, (tz + 1) * TILE))
                    for part in getattr(q, "geoms", [q]):
                        if part.geom_type != "Polygon" or part.area < 50:
                            continue
                        tiles.setdefault((tx, tz), []).append((t, d, np.asarray(part.exterior.coords, np.float32)[:-1]))
            stats[t] = stats.get(t, 0) + p.area / 1e4
    for (tx, tz), fl in tiles.items():
        with open("%s/c_%d_%d.bin" % (OUT, tx, tz), "wb") as fh:
            fh.write(struct.pack("<i", len(fl)))
            for t, d, P in fl:
                fh.write(struct.pack("<iffi", t, float(d[0]), float(d[1]), len(P)))
                fh.write(P.astype("<f4").tobytes())
    print(len(tiles), "tuiles ; hectares par type :", {k: round(v) for k, v in stats.items()})


if __name__ == "__main__":
    main()
