"""Cinémas (OSM amenity=cinema) de la zone, avec leur contour quand il existe.
Sortie : data/osm_cinemas.json (le nom est parodié en jeu par build_shops.py)."""
import json, time, urllib.parse, urllib.request
BB = "45.53,5.19,45.67,5.53"
q = """[out:json][timeout:120];nwr["amenity"="cinema"](%s);out center tags geom;""" % BB
b = b""
for k in range(8):
    u = ("https://overpass.private.coffee/api/interpreter", "https://overpass.kumi.systems/api/interpreter",
         "https://overpass-api.de/api/interpreter", "https://maps.mail.ru/osm/tools/overpass/api/interpreter")[k % 4]
    try:
        b = urllib.request.urlopen(urllib.request.Request(u, data=urllib.parse.urlencode(dict(data=q)).encode()), timeout=300).read()
        if b[:1] == b"{":
            break
    except Exception as e:
        print("nouvel essai", u, e); time.sleep(10 * (k + 1))
open("data/osm_cinemas.json", "wb").write(b)
for e in json.loads(b)["elements"]:
    c = e.get("center") or e
    print(e["type"], e["id"], e["tags"].get("name"), c.get("lat"), c.get("lon"), e["tags"].get("screen"))
