"""Lignes électriques (OSM : lignes haute tension et pylônes, lignes basse / moyenne tension et poteaux) et lampadaires.
Sortie : data/osm_power.json (géométries incluses)."""
import json, time, urllib.parse, urllib.request
BB = "45.53,5.19,45.67,5.53"
q = """[out:json][timeout:300];(
way["power"~"^(line|minor_line|cable)$"](%(b)s);
node["power"~"^(tower|pole)$"](%(b)s);
node["highway"="street_lamp"](%(b)s);
node["man_made"="utility_pole"](%(b)s);
);out geom tags;""" % dict(b=BB)
b = b""
for k in range(8):
    u = ("https://maps.mail.ru/osm/tools/overpass/api/interpreter", "https://overpass-api.de/api/interpreter")[k % 2]
    try:
        b = urllib.request.urlopen(urllib.request.Request(u, data=urllib.parse.urlencode(dict(data=q)).encode()), timeout=600).read()
        if b[:1] == b"{":
            break
    except Exception as e:
        print("nouvel essai", u, e); time.sleep(10 * (k + 1))
open("data/osm_power.json", "wb").write(b)
d = json.loads(b)
import collections
print(collections.Counter((e["type"], e["tags"].get("power") or e["tags"].get("highway") or e["tags"].get("man_made")) for e in d["elements"]))
