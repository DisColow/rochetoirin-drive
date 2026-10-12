"""Télécharge les données de décor de l'IGN (Géoplateforme, WFS) autour de Rochetoirin.

BD TOPO : bâtiments, végétation, haies, hydrographie, cimetières, terrains de sport,
lignes électriques, pylônes.  RPG : parcelles agricoles et leurs cultures.
Sorties : data/wfs_<couche>.json (GeoJSON, coordonnées lon/lat).
"""
import json, os, sys, time, urllib.parse, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
WFS = "https://data.geopf.fr/wfs/ows"
BBOX = (45.556, 5.385, 45.615, 5.447)   # lat_min, lon_min, lat_max, lon_max

LAYERS = {
    "batiment": "BDTOPO_V3:batiment",
    "vegetation": "BDTOPO_V3:zone_de_vegetation",
    "haie": "BDTOPO_V3:haie",
    "surface_eau": "BDTOPO_V3:surface_hydrographique",
    "cours_eau": "BDTOPO_V3:troncon_hydrographique",
    "cimetiere": "BDTOPO_V3:cimetiere",
    "sport": "BDTOPO_V3:terrain_de_sport",
    "ligne_electrique": "BDTOPO_V3:ligne_electrique",
    "pylone": "BDTOPO_V3:pylone",
    "rpg": "LANDUSE.AGRICULTURE2025:parcelles_graphiques",
}


BBOX_FAR = (45.503, 5.309, 45.668, 5.523)   # anneau lointain (grille de 60 m)
FAR_LAYERS = {"vegetation_far": "BDTOPO_V3:zone_de_vegetation", "surface_eau_far": "BDTOPO_V3:surface_hydrographique",
              "batiment_far": "BDTOPO_V3:batiment"}


def get(layer, start, bbox=BBOX):
    q = dict(SERVICE="WFS", VERSION="2.0.0", REQUEST="GetFeature", TYPENAMES=layer,
             OUTPUTFORMAT="application/json", SRSNAME="EPSG:4326", COUNT="5000", STARTINDEX=str(start),
             BBOX="%f,%f,%f,%f,urn:ogc:def:crs:EPSG::4326" % bbox)
    url = WFS + "?" + urllib.parse.urlencode(q)
    for attempt in range(6):
        try:
            return json.load(urllib.request.urlopen(url, timeout=300))
        except Exception as e:
            print("  retry", attempt, e, flush=True)
            time.sleep(2 ** attempt)
    raise RuntimeError(layer)


def fetch(name, layer, bbox=BBOX):
    path = os.path.join(HERE, "data", "wfs_%s.json" % name)
    if os.path.exists(path):
        print(name, "déjà présent"); return
    feats, start = [], 0
    while True:
        d = get(layer, start, bbox)
        f = d.get("features", [])
        feats += f
        print(name, len(feats), flush=True)
        if len(f) < 5000:
            break
        start += 5000
    json.dump({"type": "FeatureCollection", "features": feats}, open(path, "w"))


if __name__ == "__main__":
    for n, l in LAYERS.items():
        if len(sys.argv) > 1 and n not in sys.argv[1:]:
            continue
        fetch(n, l)
    for n, l in FAR_LAYERS.items():
        if len(sys.argv) > 1 and n not in sys.argv[1:]:
            continue
        fetch(n, l, BBOX_FAR)
