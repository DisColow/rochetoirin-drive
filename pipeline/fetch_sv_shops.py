"""Photos Street View des devantures des commerces (clé : variable GOOGLE_MAPS_API_KEY, jamais écrite).
Cache privé d'abord (SV_DIR, par défaut ../../rochetoirin-streetview/streetview/shops) : rien n'est retéléchargé.
Pour chaque commerce OSM de la zone (data/osm_shops.json) : panorama extérieur le plus proche (métadonnées, gratuites),
vue cadrée sur le point du commerce (cap depuis le panorama, champ selon la distance), 640 × 480.
Sortie : SV_DIR/<osm_id>.jpg + index.json {id: {pano, date, cap, dist, trade}} ; sans panorama à moins de 45 m : None.
Ces photos servent à décrire chaque devanture à la main (sources/shops_sv.txt), lue par build_shops.py."""
import json, math, os, sys, time, urllib.parse
from shapely.geometry import Point, Polygon
from shapely.prepared import prep
import geo
from fetch_sv_landmarks import get

KEY = os.environ.get("GOOGLE_MAPS_API_KEY", "")
OUT = os.environ.get("SV_DIR", "../../rochetoirin-streetview/streetview/shops")
API = "https://maps.googleapis.com/maps/api/streetview"


def shops():
    zone = prep(Polygon(json.load(open("data/routes_plan.json"))["zone"]))
    out = []
    for e in json.load(open("data/osm_shops.json"))["elements"]:
        t = e.get("tags", {})
        trade = t.get("shop") or t.get("amenity")
        if not trade or trade == "vacant":
            continue
        if e["type"] == "node":
            lon, lat = e["lon"], e["lat"]
        elif "center" in e:
            lon, lat = e["center"]["lon"], e["center"]["lat"]
        else:
            continue
        x, z = geo.to_local(lon, lat)
        if zone.contains(Point(float(x), float(z))):
            out.append(dict(id="%s%d" % (e["type"][0], e["id"]), trade=trade, lon=lon, lat=lat))
    return out


def heading(lat0, lon0, lat1, lon1):
    dx = (lon1 - lon0) * math.cos(math.radians(lat0)); dy = lat1 - lat0
    return (math.degrees(math.atan2(dx, dy)) + 360) % 360, math.hypot(dx, dy) * 111132.0


def main():
    os.makedirs(OUT, exist_ok=True)
    idx_p = os.path.join(OUT, "index.json")
    index = json.load(open(idx_p)) if os.path.exists(idx_p) else {}
    S = shops()
    todo = [s for s in S if s["id"] not in index]
    print(len(S), "commerces,", len(todo), "à télécharger")
    if todo and not KEY:
        sys.exit("GOOGLE_MAPS_API_KEY absente et images manquantes dans le cache")
    n = 0
    for k, s in enumerate(todo):
        m = get(API + "/metadata?" + urllib.parse.urlencode(dict(location="%f,%f" % (s["lat"], s["lon"]), radius=45,
                                                                  source="outdoor", key=KEY)))
        if not m or m.get("status") != "OK":
            index[s["id"]] = None
        else:
            plat, plon = m["location"]["lat"], m["location"]["lng"]
            cap, d = heading(plat, plon, s["lat"], s["lon"])
            fov = 90 if d < 12 else 75 if d < 25 else 60
            img = get(API + "?" + urllib.parse.urlencode(dict(size="640x480", pano=m["pano_id"], heading="%.1f" % cap,
                                                              pitch=8 if d < 15 else 4, fov=fov, key=KEY)), binary=True)
            if img and img[:2] == b"\xff\xd8":
                open(os.path.join(OUT, s["id"] + ".jpg"), "wb").write(img); n += 1
                index[s["id"]] = dict(pano=m["pano_id"], date=m.get("date"), cap=round(cap, 1), dist=round(d, 1),
                                      trade=s["trade"])
            else:
                index[s["id"]] = None
        if k % 25 == 0:
            json.dump(index, open(idx_p, "w"))
            print(k, "/", len(todo), "photos", n)
        time.sleep(0.05)
    json.dump(index, open(idx_p, "w"), indent=0)
    print("photos nouvelles :", n, "; sans panorama :", sum(1 for v in index.values() if v is None))


if __name__ == "__main__":
    main()
