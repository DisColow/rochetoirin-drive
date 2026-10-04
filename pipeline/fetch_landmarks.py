"""Bâtiments emblématiques (OSM) de la zone : mairies, églises, chapelles, châteaux, tours, monuments, musées,
châteaux d'eau. Sortie : data/osm_landmarks.json (avec géométries des chemins / relations)."""
import json, time, urllib.parse, urllib.request
BB = "45.53,5.19,45.67,5.53"
q = """[out:json][timeout:300];(
nwr["amenity"="townhall"](%(b)s);
nwr["amenity"="place_of_worship"](%(b)s);
nwr["building"~"^(church|chapel|cathedral|castle|tower)$"](%(b)s);
nwr["historic"~"^(castle|monument|memorial|tower|church|ruins|manor|city_gate|fort|chapel|wayside_cross|wayside_shrine)$"](%(b)s);
nwr["tourism"~"^(attraction|museum)$"](%(b)s);
nwr["man_made"~"^(water_tower|tower)$"](%(b)s);
nwr["amenity"~"^(school|post_office|library|theatre|hospital|fire_station|police)$"]["building"](%(b)s);
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
open("data/osm_landmarks.json", "wb").write(b)
d = json.loads(b)
print(len(d["elements"]))
