"""Itinéraires réels (plus court chemin OSM pondéré par la vitesse) de Rochetoirin vers les communes demandées."""
import json, math
import networkx as nx
from geo import to_local
d = json.load(open("data/osm.json"))
N = {e["id"]: (e["lon"], e["lat"]) for e in d["elements"] if e["type"] == "node"}
SPEED = dict(motorway=110, motorway_link=60, trunk=90, primary=80, primary_link=50, secondary=70, secondary_link=50,
             tertiary=60, tertiary_link=40, unclassified=45, residential=35, living_street=15)
G = nx.Graph()
for e in d["elements"]:
    if e["type"] != "way":
        continue
    hw = e.get("tags", {}).get("highway")
    if hw not in SPEED:
        continue
    for a, b in zip(e["nodes"][:-1], e["nodes"][1:]):
        xa, za = to_local(*N[a]); xb, zb = to_local(*N[b])
        L = math.hypot(float(xb - xa), float(zb - za))
        G.add_edge(a, b, w=L / SPEED[hw], L=L)
pts = {}
for n, (lo, la) in N.items():
    if n in G:
        pts[n] = tuple(float(v) for v in to_local(lo, la))
def nearest(x, z):
    return min(pts, key=lambda n: (pts[n][0] - x) ** 2 + (pts[n][1] - z) ** 2)
T = {"Rochetoirin": (0, 0), "Saint-Chef": (-4387, -5876), "L'Isle-d'Abeau": (-14569, -3778), "Saint-Clair-de-la-Tour": (5482, 1639), "La Tour-du-Pin": (2354, 1318)}
src = nearest(*T["Rochetoirin"])
out = {}
for k, p in T.items():
    if k == "Rochetoirin":
        continue
    path = nx.shortest_path(G, src, nearest(*p), weight="w")
    L = sum(G[a][b]["L"] for a, b in zip(path[:-1], path[1:]))
    t = sum(G[a][b]["w"] for a, b in zip(path[:-1], path[1:])) * 60
    out[k] = [pts[n] for n in path]
    print("%-24s %.1f km  %.0f min" % (k, L / 1000, t))
json.dump(dict(towns=T, routes=out), open("data/routes_plan.json", "w"))
# Saint-Clair : par La Tour-du-Pin (itinéraire naturel)
a = nearest(*T["La Tour-du-Pin"]); b = nearest(*T["Saint-Clair-de-la-Tour"])
out["Saint-Clair-de-la-Tour"] = out["La Tour-du-Pin"] + [pts[n] for n in nx.shortest_path(G, a, b, weight="w")]
# zone jouable : ancienne zone + couloirs (450 m) + communes (rayon 1,2 km) ; régions Terrain3D de 1024 m
from shapely.geometry import LineString, Point, box
from shapely.ops import unary_union
parts = [box(-2300, -3100, 2300, 3100)]
for k, p in out.items():
    parts.append(LineString(p).buffer(450))
for k, p in T.items():
    parts.append(Point(p).buffer(1200))
Z = unary_union(parts)
R = 1024.0
regs = []
mnx, mnz, mxx, mxz = Z.bounds
import math as m
for i in range(int(m.floor(mnx / R)), int(m.ceil(mxx / R))):
    for j in range(int(m.floor(mnz / R)), int(m.ceil(mxz / R))):
        if Z.intersects(box(i * R, j * R, (i + 1) * R, (j + 1) * R)):
            regs.append((i, j))
print(len(regs), "régions de 1 km ; aire jouable %.0f km²" % (Z.area / 1e6))
json.dump(dict(towns=T, routes=out, regions=regs, zone=list(Z.exterior.coords)), open("data/routes_plan.json", "w"))
