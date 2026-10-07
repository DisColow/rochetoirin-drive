"""Équipements sportifs (OSM) : terrains (leisure=pitch, sport=*), stades, pistes d'athlétisme, complexes sportifs.
Sortie : data/osm_sport.json (contours inclus)."""
import json, time, urllib.parse, urllib.request, collections
BB = "45.53,5.19,45.67,5.53"
q = """[out:json][timeout:300];(
way["leisure"~"^(pitch|stadium|track|sports_centre)$"](%(b)s);
relation["leisure"~"^(pitch|stadium|sports_centre)$"](%(b)s);
);out geom tags;""" % dict(b=BB)
b = b""
for k in range(8):
    u = ("https://overpass-api.de/api/interpreter", "https://maps.mail.ru/osm/tools/overpass/api/interpreter")[k % 2]
    try:
        b = urllib.request.urlopen(urllib.request.Request(u, data=urllib.parse.urlencode(dict(data=q)).encode()), timeout=600).read()
        if b[:1] == b"{":
            break
    except Exception as e:
        print("nouvel essai", u, e); time.sleep(10 * (k + 1))
open("data/osm_sport.json", "wb").write(b)
d = json.loads(b)
print(len(d["elements"]), collections.Counter((e["tags"].get("leisure"), e["tags"].get("sport")) for e in d["elements"]).most_common(25))
