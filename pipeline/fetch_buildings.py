"""Bâtiments BD TOPO (IGN, WFS) et ralentisseurs OSM sur la zone jouable.
Sorties : data/batiments.json (GeoJSON lon/lat, pagination), data/osm_calming.json"""
import json, os, time, urllib.parse, urllib.request
WFS = "https://data.geopf.fr/wfs/ows"
BB = (45.53, 5.19, 45.67, 5.53)
def get(u, tries=6):
    for k in range(tries):
        try:
            return urllib.request.urlopen(u, timeout=300).read()
        except Exception as e:
            print("nouvel essai", e); time.sleep(5 * (k + 1))
    raise SystemExit(u)
if not os.path.exists("data/batiments.json"):
    feats, start = [], 0
    while True:
        q = dict(SERVICE="WFS", VERSION="2.0.0", REQUEST="GetFeature", TYPENAMES="BDTOPO_V3:batiment", COUNT=5000,
                 STARTINDEX=start, OUTPUTFORMAT="application/json", SRSNAME="EPSG:4326",
                 BBOX="%f,%f,%f,%f,urn:ogc:def:crs:EPSG::4326" % BB)
        d = json.loads(get(WFS + "?" + urllib.parse.urlencode(q)))
        feats += d["features"]
        print(len(feats))
        if len(d["features"]) < 5000:
            break
        start += 5000
    json.dump(dict(type="FeatureCollection", features=feats), open("data/batiments.json", "w"))
q = '[out:json][timeout:300];(node["traffic_calming"](%f,%f,%f,%f);way["traffic_calming"](%f,%f,%f,%f););(._;>;);out body;' % (BB * 2)
for k in range(8):
    u = ("https://maps.mail.ru/osm/tools/overpass/api/interpreter", "https://overpass-api.de/api/interpreter")[k % 2]
    try:
        b = urllib.request.urlopen(urllib.request.Request(u, data=urllib.parse.urlencode(dict(data=q)).encode()), timeout=600).read()
    except Exception as e:
        print("nouvel essai", u, e); time.sleep(10 * (k + 1)); continue
    if b[:1] == b"{":
        open("data/osm_calming.json", "wb").write(b); break
d = json.load(open("data/osm_calming.json"))
import collections
print(collections.Counter(e["tags"].get("traffic_calming") for e in d["elements"] if "tags" in e and "traffic_calming" in e["tags"]))
