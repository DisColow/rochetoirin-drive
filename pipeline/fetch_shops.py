"""Commerces et services (OSM) : magasins, stations-service, pharmacies, banques, poste, cafés, restaurants, garages…
Sortie : data/osm_shops.json (points et contours, avec nom et marque ; les marques sont parodiées en jeu)."""
import json, time, urllib.parse, urllib.request, collections
BB = "45.53,5.19,45.67,5.53"
q = """[out:json][timeout:300];(
nwr["shop"](%(b)s);
nwr["amenity"~"^(fuel|pharmacy|bank|post_office|restaurant|cafe|bar|pub|fast_food|car_wash|marketplace)$"](%(b)s);
nwr["craft"~"^(hairdresser|bakery)$"](%(b)s);
);out center tags;""" % dict(b=BB)
b = b""
for k in range(8):
    u = ("https://overpass-api.de/api/interpreter", "https://maps.mail.ru/osm/tools/overpass/api/interpreter")[k % 2]
    try:
        b = urllib.request.urlopen(urllib.request.Request(u, data=urllib.parse.urlencode(dict(data=q)).encode()), timeout=600).read()
        if b[:1] == b"{":
            break
    except Exception as e:
        print("nouvel essai", u, e); time.sleep(10 * (k + 1))
open("data/osm_shops.json", "wb").write(b)
d = json.loads(b)
c = collections.Counter(e["tags"].get("shop") or e["tags"].get("amenity") or e["tags"].get("craft") for e in d["elements"])
print(len(d["elements"]), c.most_common(40))
print(collections.Counter(e["tags"].get("brand") for e in d["elements"] if e["tags"].get("brand")).most_common(60))
