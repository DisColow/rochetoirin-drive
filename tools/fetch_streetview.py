"""Vues Street View des façades du village (API Google Street View Static, clé personnelle).

Clé lue dans la variable d'environnement GOOGLE_MAPS_API_KEY (jamais écrite dans le dépôt).
Pour chaque maison du bourg (zone de l'orthophoto) : panorama le plus proche de la façade côté rue,
image cadrée sur la maison. Les images servent seulement de référence pour mesurer la couleur
des enduits et des volets (prepare_facades.py) ; elles restent hors du dépôt (STREETVIEW_DIR,
par défaut tools/data/streetview/, non versionné).

Sortie : STREETVIEW_DIR/<cleabs>.jpg + index.json (caméra : position, cap, inclinaison, champ).
"""
import json, math, os, sys, time, urllib.parse, urllib.request
import numpy as np
from shapely.geometry import Point, LineString
from geo import to_local, to_lonlat

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "data")
OUT = os.environ.get("STREETVIEW_DIR", os.path.join(DATA, "streetview"))
KEY = os.environ.get("GOOGLE_MAPS_API_KEY", "")
W, H = 640, 480
CAM_H = 2.5            # hauteur approximative de la caméra Google au-dessus du sol (m)


def get(url, binary=False):
    for k in range(5):
        try:
            r = urllib.request.urlopen(url, timeout=60).read()
            return r if binary else json.loads(r)
        except Exception as e:
            print("nouvel essai", k, e); time.sleep(3 * (k + 1))
    return None


def main():
    if not KEY:
        sys.exit("GOOGLE_MAPS_API_KEY absente")
    os.makedirs(OUT, exist_ok=True)
    from prepare_decor import load, loc, polys
    from prepare_village import Village
    import pickle
    v = Village()
    rows = pickle.load(open(os.path.join(DATA, "road_rows.pkl"), "rb"))
    roads = [LineString(r["P"]) for r in rows if r["cls"] not in ("rail", "motorway", "track") and len(r["P"]) > 1]
    from shapely.strtree import STRtree
    rt = STRtree(roads)
    idx_path = os.path.join(OUT, "index.json")
    index = json.load(open(idx_path)) if os.path.exists(idx_path) else {}
    meta_cache = {}
    todo = []
    for f in load("batiment"):
        pr = f["properties"]
        for p in polys(loc(f["geometry"])):
            if v.contains(p.centroid.x, p.centroid.y, 5) and p.area > 35 and \
                    pr.get("usage_1") in ("Résidentiel", "Indifférencié", "Commercial et services"):
                todo.append((pr["cleabs"], p, pr))
    print(len(todo), "bâtiments")
    nimg = 0
    for cle, p, pr in todo:
        if cle in index:
            continue
        c = p.centroid
        # point de rue le plus proche de la maison
        near = rt.query(c.buffer(80))
        if len(near) == 0:
            continue
        road = min((roads[k] for k in near), key=lambda L: L.distance(c))
        q = road.interpolate(road.project(c))
        if q.distance(c) > 70:
            continue
        lon, lat = to_lonlat(q.x, q.y)
        key = (round(float(lat), 5), round(float(lon), 5))
        meta = meta_cache.get(key) or get("https://maps.googleapis.com/maps/api/streetview/metadata?" + urllib.parse.urlencode(
            dict(location="%f,%f" % key, radius=40, source="outdoor", key=KEY)))
        meta_cache[key] = meta
        if not meta or meta.get("status") != "OK":
            continue
        cx, cz = to_local(meta["location"]["lng"], meta["location"]["lat"])
        cx, cz = float(cx), float(cz)
        # cadrage : cap vers le centre de la maison, champ couvrant l'emprise
        ring = np.array(p.exterior.coords)
        ang = [math.atan2(x - cx, -(z - cz)) for x, z in ring]
        mid = math.atan2(c.x - cx, -(c.y - cz))
        rel = [((a - mid + math.pi) % (2 * math.pi)) - math.pi for a in ang]
        span = max(rel) - min(rel)
        heading = math.degrees(mid + (max(rel) + min(rel)) / 2) % 360
        fov = float(np.clip(math.degrees(span) * 1.25 + 8, 35, 110))
        d = c.distance(Point(cx, cz))
        h = float(pr.get("hauteur") or 6.0)
        pitch = float(np.clip(math.degrees(math.atan2(h * 0.55 - CAM_H, d)), -5, 25))
        url = "https://maps.googleapis.com/maps/api/streetview?" + urllib.parse.urlencode(dict(
            size="%dx%d" % (W, H), pano=meta["pano_id"], heading="%.1f" % heading, pitch="%.1f" % pitch,
            fov="%.1f" % fov, source="outdoor", key=KEY))
        img = get(url, binary=True)
        if not img:
            continue
        open(os.path.join(OUT, cle + ".jpg"), "wb").write(img)
        index[cle] = dict(pano=meta["pano_id"], date=meta.get("date"), cam=[cx, cz], heading=heading, pitch=pitch, fov=fov,
                          size=[W, H], dist=d)
        nimg += 1
        if nimg % 20 == 0:
            json.dump(index, open(idx_path, "w"))
            print(nimg, "images")
    json.dump(index, open(idx_path, "w"))
    print(nimg, "nouvelles images,", len(index), "au total")


if __name__ == "__main__":
    main()
