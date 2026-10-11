"""Parkings (OSM) : contours amenity=parking (surface, type), places amenity=parking_space s'il y en a.
Sortie : data/osm_parking.json (géométries incluses), pour build_parking.py."""
import json, time, urllib.parse, urllib.request
BB = "45.53,5.19,45.67,5.53"
q = """[out:json][timeout:300];(
way["amenity"="parking"](%(b)s);
relation["amenity"="parking"](%(b)s);
way["amenity"="parking_space"](%(b)s);
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
open("data/osm_parking.json", "wb").write(b)
d = json.loads(b)
import collections
print(collections.Counter((e["type"], e["tags"].get("amenity"), e["tags"].get("parking"), e["tags"].get("surface")) for e in d["elements"]).most_common(12))
