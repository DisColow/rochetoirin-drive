"""Restaurants et snacks (#151, activité « Livreur de repas », scripts/livreur.gd) : points OSM amenity=restaurant /
fast_food de data/osm_shops.json dans la zone de jeu, avec le nom de leur enseigne en jeu (même tirage que
build_shops.py : parodie de la marque, sinon nom inventé selon le métier ; jamais le nom du vrai commerçant).
Sortie : ../godot/world/restos.json = [{x, z, nom, metier, cuisine}].
python3 build_restos.py"""
import json, os
from shapely.geometry import Point, Polygon
import geo
import build_shops as B

ICI = os.path.dirname(os.path.abspath(__file__))
SORTIE = os.path.join(ICI, "..", "godot", "world", "restos.json")


def nom_enseigne(tags, kind, key):
    """Comme sign_for de build_shops.main."""
    brand = tags.get("brand") or ""
    if brand in B.PARODIES:
        return B.PARODIES[brand][0]
    lab, names, bg, fg, font, acc = B.GENERIC.get(kind, B.OTHER)
    return names[int(B.rnd(key, "nom") * len(names))]


os.chdir(ICI)
zone = Polygon(json.load(open("data/routes_plan.json"))["zone"])
d = json.load(open("data/osm_shops.json"))
out = []
for e in d["elements"]:
    t = e.get("tags", {})
    kind = t.get("amenity")
    if kind not in ("restaurant", "fast_food"):
        continue
    if "lon" in e:
        lon, lat = e["lon"], e["lat"]
    elif "center" in e:
        lon, lat = e["center"]["lon"], e["center"]["lat"]
    else:
        continue
    x, z = geo.to_local(lon, lat)
    if not zone.contains(Point(float(x), float(z))):
        continue
    key = e["id"]
    out.append({"x": round(float(x), 1), "z": round(float(z), 1), "nom": nom_enseigne(t, kind, key), "metier": kind,
                "cuisine": t.get("cuisine", "")})
out.sort(key=lambda r: (r["x"], r["z"]))
json.dump(out, open(SORTIE, "w"), ensure_ascii=False)
print(len(out), "restaurants ->", SORTIE)
