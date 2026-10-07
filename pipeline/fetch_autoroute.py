"""Autoroutes (OSM) : échangeurs (numéros de sortie, noms), bretelles avec leurs destinations, gares de péage,
bornes d'appel d'urgence. Sortie : data/osm_autoroute.json."""
import json, time, urllib.parse, urllib.request, collections
BB = "45.50,5.10,45.70,5.60"
q = """[out:json][timeout:300];(
node["highway"="motorway_junction"](%(b)s);
way["highway"~"^(motorway|motorway_link)$"](%(b)s);
node["barrier"="toll_booth"](%(b)s);
way["barrier"="toll_booth"](%(b)s);
node["highway"="toll_gantry"](%(b)s);
node["emergency"="phone"](%(b)s);
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
open("data/osm_autoroute.json", "wb").write(b)
d = json.loads(b)
print(len(d["elements"]), collections.Counter(e["tags"].get("highway") or e["tags"].get("barrier") or e["tags"].get("emergency") for e in d["elements"]))
print([(e["tags"].get("ref"), e["tags"].get("name"), e["tags"].get("exit_to")) for e in d["elements"] if e["tags"].get("highway") == "motorway_junction"][:30])
print(collections.Counter(e["tags"].get("destination") for e in d["elements"] if e["tags"].get("highway") == "motorway_link" and e["tags"].get("destination")).most_common(20))
