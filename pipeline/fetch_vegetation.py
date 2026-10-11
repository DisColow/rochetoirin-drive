"""Végétation : hauteur de canopée LiDAR HD (IGN MNH, 1 m) par région, zones de végétation et haies BD TOPO, parcelles
agricoles RPG 2024 (culture de chaque champ).
Sorties : data/mnh/r_i_j.npy (uint8, hauteur × 8, 1024², pas de 1 m, ligne = z), data/vegetation_zones.json,
data/haies.json, data/rpg.json"""
import json, os, time, urllib.parse, urllib.request
import numpy as np
import geo

REG = 1024.0
WMS = "https://data.geopf.fr/wms-r/wms"
WFS = "https://data.geopf.fr/wfs/ows"
BB = (45.53, 5.19, 45.67, 5.53)


def get(u, tries=6):
    for k in range(tries):
        try:
            return urllib.request.urlopen(u, timeout=300).read()
        except Exception as e:
            print("nouvel essai", e); time.sleep(5 * (k + 1))
    raise SystemExit(u)


def mnh():
    os.makedirs("data/mnh", exist_ok=True)
    for i, j in json.load(open("data/routes_plan.json"))["regions"]:
        p = "data/mnh/r_%d_%d.npy" % (i, j)
        if os.path.exists(p):
            continue
        # cellule k centrée sur x = i*1024 + k + 0,5 : emprise WMS alignée sur les bords des pixels
        lon0, lat1 = geo.to_lonlat(i * REG, j * REG)
        lon1, lat0 = geo.to_lonlat((i + 1) * REG, (j + 1) * REG)
        q = dict(SERVICE="WMS", VERSION="1.3.0", REQUEST="GetMap", STYLES="", CRS="EPSG:4326",
                 LAYERS="IGNF_LIDAR-HD_MNH_ELEVATION.ELEVATIONGRIDCOVERAGE.LAMB93",
                 BBOX="%.8f,%.8f,%.8f,%.8f" % (lat0, lon0, lat1, lon1), WIDTH=1024, HEIGHT=1024, FORMAT="image/x-bil;bits=32")
        b = get(WMS + "?" + urllib.parse.urlencode(q))
        if len(b) != 1024 * 1024 * 4:
            print("réponse inattendue", i, j, b[:200]); continue
        a = np.frombuffer(b, "<f4").reshape(1024, 1024)
        a = np.nan_to_num(np.where(a < -100, 0, a), nan=0.0)
        np.save(p, np.clip(a * 8, 0, 255).astype(np.uint8))
        print("mnh", i, j, "%.0f %% couvert > 3 m" % (100 * (a > 3).mean()))


def wfs(typename, out, extra=None):
    if os.path.exists(out):
        return
    feats, start = [], 0
    while True:
        q = dict(SERVICE="WFS", VERSION="2.0.0", REQUEST="GetFeature", TYPENAMES=typename, COUNT=5000, STARTINDEX=start,
                 OUTPUTFORMAT="application/json", SRSNAME="EPSG:4326", BBOX="%f,%f,%f,%f,urn:ogc:def:crs:EPSG::4326" % BB)
        d = json.loads(get(WFS + "?" + urllib.parse.urlencode(q)))
        feats += d["features"]
        print(typename, len(feats))
        if len(d["features"]) < 5000:
            break
        start += 5000
    json.dump(dict(type="FeatureCollection", features=feats), open(out, "w"))


if __name__ == "__main__":
    wfs("BDTOPO_V3:zone_de_vegetation", "data/vegetation_zones.json")
    wfs("BDTOPO_V3:haie", "data/haies.json")
    wfs("IGNF_RPG_PARCELLES-AGRICOLES-CATEGORISEES_2024:parcelles_agricole_categorisees_2024", "data/rpg.json")
    mnh()
