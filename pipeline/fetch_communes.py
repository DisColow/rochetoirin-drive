"""Limites des communes (OSM admin_level=8) de la zone : data/communes.json (polygones en repère local)."""
import json, time, urllib.parse, urllib.request
from shapely.geometry import LineString
from shapely.ops import polygonize, unary_union
from geo import to_local
BB = (45.53, 5.19, 45.67, 5.53)
q = '[out:json][timeout:300];rel["boundary"="administrative"]["admin_level"="8"](%f,%f,%f,%f);out body;>;out skel qt;' % BB
b = b""
for k in range(8):
    u = ("https://maps.mail.ru/osm/tools/overpass/api/interpreter", "https://overpass-api.de/api/interpreter")[k % 2]
    try:
        b = urllib.request.urlopen(urllib.request.Request(u, data=urllib.parse.urlencode(dict(data=q)).encode()), timeout=600).read()
        if b[:1] == b"{":
            break
    except Exception as e:
        print("nouvel essai", u, e); time.sleep(10 * (k + 1))
d = json.loads(b)
N = {e["id"]: (e["lon"], e["lat"]) for e in d["elements"] if e["type"] == "node"}
W = {e["id"]: e["nodes"] for e in d["elements"] if e["type"] == "way"}
out = {}
for r in d["elements"]:
    if r["type"] != "relation":
        continue
    lines = []
    for m in r["members"]:
        if m["type"] == "way" and m["ref"] in W and m.get("role") in ("outer", ""):
            pts = [N[n] for n in W[m["ref"]] if n in N]
            if len(pts) > 1:
                x, z = to_local([p[0] for p in pts], [p[1] for p in pts])
                lines.append(LineString(list(zip(x, z))))
    poly = unary_union(list(polygonize(unary_union(lines))))
    if not poly.is_empty:
        out[r["tags"].get("name", "?")] = poly.simplify(5).__geo_interface__
json.dump(out, open("data/communes.json", "w"))
print(len(out), sorted(out))
