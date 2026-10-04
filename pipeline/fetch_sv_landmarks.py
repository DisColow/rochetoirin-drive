"""Photos de référence Street View des bâtiments emblématiques (clé : variable GOOGLE_MAPS_API_KEY, jamais écrite).
Cache privé d'abord (SV_DIR, par défaut ../../rochetoirin-streetview/streetview/landmarks) : rien n'est retéléchargé.
Pour chaque monument : 2 panoramas proches sur des routes, vues cadrées sur le monument (inclinaison selon distance).
Sortie : SV_DIR/<osm_id>_<k>.jpg + index.json."""
import json, math, os, pickle, sys, time, urllib.parse, urllib.request
import numpy as np
from shapely.geometry import Point, Polygon, LineString
from shapely.prepared import prep
import geo

KEY = os.environ.get("GOOGLE_MAPS_API_KEY", "")
OUT = os.environ.get("SV_DIR", "../../rochetoirin-streetview/streetview/landmarks")
KINDS = ("place_of_worship", "townhall", "castle", "tower", "chapel", "memorial", "museum")


def get(u, binary=False):
    for k in range(4):
        try:
            r = urllib.request.urlopen(u, timeout=60).read()
            return r if binary else json.loads(r)
        except Exception as e:
            print("nouvel essai", e); time.sleep(3 * (k + 1))
    return None


def landmarks():
    zone = prep(Polygon(json.load(open("data/routes_plan.json"))["zone"]))
    out = []
    for e in json.load(open("data/osm_landmarks.json"))["elements"]:
        t = e.get("tags", {})
        kind = t.get("amenity") or t.get("historic") or t.get("building") or t.get("tourism")
        if kind not in KINDS or (kind == "memorial" and not t.get("name")) or t.get("religion") == "muslim":
            continue
        if e["type"] == "node":
            x, z = geo.to_local(e["lon"], e["lat"]); poly = Point(float(x), float(z)).buffer(4)
        elif e["type"] == "way" and "geometry" in e:
            g = e["geometry"]; x, z = geo.to_local([p["lon"] for p in g], [p["lat"] for p in g])
            poly = Polygon(list(zip(x, z))).buffer(0)
        else:
            continue
        if zone.contains(poly.centroid):
            out.append(dict(id="%s%d" % (e["type"][0], e["id"]), kind=kind, name=t.get("name", ""), poly=poly, tags=t))
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    idx_p = os.path.join(OUT, "index.json")
    index = json.load(open(idx_p)) if os.path.exists(idx_p) else {}
    L = landmarks()
    print(len(L), "monuments")
    if not KEY and any("%s_0" % l["id"] not in index for l in L):
        sys.exit("GOOGLE_MAPS_API_KEY absente et images manquantes dans le cache")
    ways = pickle.load(open("data/roads.pkl", "rb"))["ways"]
    pts = np.vstack([w["P"] for w in ways if w["cls"] not in ("motorway", "track", "motorway_link")])
    n = 0
    for l in L:
        c = l["poly"].centroid
        H = 25.0 if l["kind"] in ("place_of_worship", "castle", "tower") else 12.0
        d = np.hypot(pts[:, 0] - c.x, pts[:, 1] - c.y) - math.sqrt(l["poly"].area) / 2
        cand = np.argsort(np.abs(d - 30.0))
        used = []
        for i in cand[:400]:
            if len([k for k in index if k.startswith(l["id"] + "_")]) >= 2:
                break
            p = pts[i]
            if d[i] < 8 or d[i] > 90 or any(np.hypot(*(p - u)) < 25 for u in used):
                continue
            used.append(p)
            k = "%s_%d" % (l["id"], len([k for k in index if k.startswith(l["id"] + "_")]))
            lon, lat = geo.to_lonlat(p[0], p[1])
            m = get("https://maps.googleapis.com/maps/api/streetview/metadata?" + urllib.parse.urlencode(
                dict(location="%f,%f" % (lat, lon), radius=30, source="outdoor", key=KEY)))
            if not m or m.get("status") != "OK":
                continue
            px, pz = geo.to_local(m["location"]["lng"], m["location"]["lat"])
            dx, dz = c.x - float(px), c.y - float(pz)
            dist = math.hypot(dx, dz)
            heading = math.degrees(math.atan2(dx, -dz)) % 360
            pitch = min(35.0, math.degrees(math.atan2(H * 0.45, max(dist, 5))))
            fov = float(np.clip(math.degrees(2 * math.atan2(math.sqrt(l["poly"].area) * 0.8 + 6, max(dist, 5))), 50, 110))
            img = get("https://maps.googleapis.com/maps/api/streetview?" + urllib.parse.urlencode(
                dict(size="640x480", pano=m["pano_id"], heading=heading, pitch=pitch, fov=fov, key=KEY)), True)
            if not img:
                continue
            open(os.path.join(OUT, k + ".jpg"), "wb").write(img)
            index[k] = dict(name=l["name"], kind=l["kind"], cam=[float(px), float(pz)], heading=heading, pitch=pitch,
                            fov=fov, date=m.get("date"), target=[c.x, c.y])
            n += 1
            json.dump(index, open(idx_p, "w"), ensure_ascii=False, indent=1)
            print(k, l["kind"], l["name"], "%.0f m" % dist)
    print(n, "nouvelles images")


if __name__ == "__main__":
    main()
