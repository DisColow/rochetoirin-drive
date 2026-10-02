"""Vues Street View de points d'intérêt (mobilier, arrêts de bus…) pour les modéliser d'après la réalité.

Clé lue dans GOOGLE_MAPS_API_KEY (jamais écrite dans le dépôt). Usage : python3 fetch_sv_points.py points.json
points.json : [{"name": ..., "x": ..., "z": ...}, ...] -> data/streetview/points/<name>.jpg + index.json
"""
import json, math, os, sys, urllib.parse, urllib.request
from geo import to_local, to_lonlat

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "data", "streetview", "points")
KEY = os.environ.get("GOOGLE_MAPS_API_KEY", "")


def get(url):
    return urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "rochetoirin-drive"}), timeout=60).read()


def main(path):
    if not KEY:
        sys.exit("GOOGLE_MAPS_API_KEY absente")
    os.makedirs(OUT, exist_ok=True)
    idx_path = os.path.join(OUT, "index.json")
    index = json.load(open(idx_path)) if os.path.exists(idx_path) else {}
    for p in json.load(open(path)):
        lon, lat = to_lonlat(p["x"], p["z"])
        meta = json.loads(get("https://maps.googleapis.com/maps/api/streetview/metadata?" + urllib.parse.urlencode(
            dict(location="%f,%f" % (lat, lon), radius=60, source="outdoor", key=KEY))))
        if meta.get("status") != "OK":
            print(p["name"], "pas de vue"); continue
        cx, cz = (float(v) for v in to_local(meta["location"]["lng"], meta["location"]["lat"]))
        heading = math.degrees(math.atan2(p["x"] - cx, -(p["z"] - cz))) % 360
        d = math.hypot(p["x"] - cx, p["z"] - cz)
        fov = 70 if d > 12 else 90
        img = get("https://maps.googleapis.com/maps/api/streetview?" + urllib.parse.urlencode(dict(
            size="640x480", pano=meta["pano_id"], heading="%.1f" % heading, pitch="0", fov=fov, source="outdoor", key=KEY)))
        open(os.path.join(OUT, p["name"] + ".jpg"), "wb").write(img)
        index[p["name"]] = dict(cam=[cx, cz], heading=heading, fov=fov, dist=d, date=meta.get("date"), target=[p["x"], p["z"]])
        print(p["name"], "%.0f m" % d, meta.get("date"))
    json.dump(index, open(idx_path, "w"), indent=1)


if __name__ == "__main__":
    main(sys.argv[1])
