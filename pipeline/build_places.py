"""Lieux nommés des activités (fetch_places.py + monuments de fetch_landmarks.py) -> ../godot/world/places.json :
[{n: nom affiché, k: catégorie, c: commune, x, z, y}] dans la zone jouable, triés par commune puis par nom, sans doublon
(même nom à moins de 150 m). Nom affiché : « Gare de Bourgoin-Jallieu », « Mairie de Saint-Chef », sinon le nom OSM.
Catégories : gare, mairie, culte, ecole, sante, poste, sport, culture, chateau, parc, place, hameau, service."""
import json
import numpy as np
from shapely.geometry import Point, Polygon, shape
from shapely.prepared import prep
import geo
from build_vegetation import Carved

KIND = {
    "station": "gare", "halt": "gare", "townhall": "mairie", "place_of_worship": "culte", "school": "ecole",
    "college": "ecole", "university": "ecole", "kindergarten": "ecole", "hospital": "sante", "clinic": "sante",
    "nursing_home": "sante", "post_office": "poste", "stadium": "sport", "sports_centre": "sport",
    "swimming_pool": "sport", "golf_course": "sport", "library": "culture", "cinema": "culture", "theatre": "culture",
    "museum": "culture", "community_centre": "culture", "castle": "chateau", "ruins": "chateau", "monument": "chateau",
    "memorial": "chateau", "park": "parc", "viewpoint": "parc", "attraction": "parc", "square": "place",
    "marketplace": "place", "hamlet": "hameau", "village": "hameau", "neighbourhood": "hameau", "quarter": "hameau",
    "suburb": "hameau", "police": "service", "fire_station": "service", "bus_station": "service",
}


def label(t, kind, commune):
    n = t["name"].strip()
    if kind == "gare":
        return n if n.lower().startswith("gare") else "Gare de " + n
    if kind == "mairie" and "mairie" not in n.lower() and "hôtel de ville" not in n.lower():
        return "Mairie de " + n if n == commune else "Mairie — " + n
    return n


def main():
    zone = prep(Polygon(json.load(open("data/routes_plan.json"))["zone"]))
    communes = [(k, prep(shape(g))) for k, g in json.load(open("data/communes.json")).items()]
    dem = Carved()
    els = json.load(open("data/osm_places.json"))["elements"]
    try:
        els += [e for e in json.load(open("data/osm_landmarks.json"))["elements"] if e.get("tags", {}).get("name")]
    except FileNotFoundError:
        pass
    out = []
    for e in els:
        t = e.get("tags", {})
        typ = t.get("railway") or t.get("amenity") or t.get("leisure") or t.get("tourism") or t.get("historic") or t.get("place")
        kind = KIND.get(typ)
        if not kind or not t.get("name"):
            continue
        if "lon" in e:
            lon, lat = e["lon"], e["lat"]
        elif "center" in e:
            lon, lat = e["center"]["lon"], e["center"]["lat"]
        elif "geometry" in e:
            g = e["geometry"]; lon = sum(p["lon"] for p in g) / len(g); lat = sum(p["lat"] for p in g) / len(g)
        else:
            continue
        x, z = (float(v) for v in geo.to_local(lon, lat))
        P = Point(x, z)
        if not zone.contains(P):
            continue
        com = next((k for k, g in communes if g.contains(P)), "")
        n = label(t, kind, com)
        if any(o["n"] == n and (o["x"] - x) ** 2 + (o["z"] - z) ** 2 < 150 ** 2 for o in out):
            continue
        y = float(dem.h(np.array([x]), np.array([z]))[0])
        out.append(dict(n=n, k=kind, c=com, x=round(x, 1), z=round(z, 1), y=round(y, 1)))
    out.sort(key=lambda o: (o["c"], o["n"]))
    json.dump(out, open("../godot/world/places.json", "w"), ensure_ascii=False, separators=(",", ":"))
    from collections import Counter
    print(len(out), "lieux", dict(Counter(o["k"] for o in out)))


if __name__ == "__main__":
    main()
