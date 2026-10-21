"""Voies ferrées (OSM, #125) : voies en service (railway=rail, avec leurs voies de service), passages à niveau
(railway=level_crossing, crossing:barrier…) et quais. Sortie : data/osm_rails.json (géométries incluses).
Lancer depuis pipeline/ : python3 fetch_rails.py"""
import json, time, urllib.parse, urllib.request, collections
BB = "45.51,5.165,45.67,5.53"
q = """[out:json][timeout:300];(
way["railway"~"^(rail|light_rail)$"](%(b)s);
node["railway"~"^(level_crossing|crossing)$"](%(b)s);
way["railway"="platform"](%(b)s);
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
open("data/osm_rails.json", "wb").write(b)
d = json.loads(b)
print(collections.Counter((e["type"], e["tags"].get("railway"), e["tags"].get("service", "")) for e in d["elements"]))
