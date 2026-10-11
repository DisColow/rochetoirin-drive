"""Parcelles cadastrales (IGN Parcellaire Express, Licence Ouverte) des régions jouables : les limites des parcelles
habitées portent les clôtures, murets, haies et portails (build_fences.py).
Sortie : data/cadastre/r_i_j.json (une région de 1024 m, parcelles qui la touchent)."""
import json, os, time
import urllib.parse
import geo
from fetch_vegetation import get, WFS, REG


def main():
    os.makedirs("data/cadastre", exist_ok=True)
    for i, j in json.load(open("data/routes_plan.json"))["regions"]:
        out = "data/cadastre/r_%d_%d.json" % (i, j)
        if os.path.exists(out):
            continue
        lon0, lat1 = geo.to_lonlat(i * REG, j * REG)
        lon1, lat0 = geo.to_lonlat((i + 1) * REG, (j + 1) * REG)
        feats, start = [], 0
        while True:
            q = dict(SERVICE="WFS", VERSION="2.0.0", REQUEST="GetFeature", TYPENAMES="CADASTRALPARCELS.PARCELLAIRE_EXPRESS:parcelle",
                     COUNT=5000, STARTINDEX=start, OUTPUTFORMAT="application/json", SRSNAME="EPSG:4326",
                     BBOX="%f,%f,%f,%f,urn:ogc:def:crs:EPSG::4326" % (lat0, lon0, lat1, lon1))
            for k in range(8):
                try:
                    d = json.loads(get(WFS + "?" + urllib.parse.urlencode(q)))
                    break
                except ValueError:
                    print("réponse invalide, nouvel essai"); time.sleep(10 * (k + 1))
            feats += [dict(type="Feature", geometry=f["geometry"], properties={"id": f["properties"].get("idu")})
                      for f in d["features"]]
            if len(d["features"]) < 5000:
                break
            start += 5000
        json.dump(dict(type="FeatureCollection", features=feats), open(out, "w"))
        print("cadastre", i, j, len(feats))


if __name__ == "__main__":
    main()
