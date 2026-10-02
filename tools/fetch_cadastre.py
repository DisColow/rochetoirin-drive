"""Parcelles cadastrales (IGN Parcellaire Express, Licence Ouverte) autour de la rue du Balcon.

Les limites de parcelles servent à placer clôtures, murets, haies et portails (prepare_quartier.py).
Sortie : data/cadastre_balcon.json
"""
import json, os, time, urllib.request, urllib.parse
from geo import to_lonlat

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "data")
ZONE = (-600.0, -160.0, -180.0, 230.0)    # x0, z0, x1, z1 (m, repère local)


def main():
    x0, z0, x1, z1 = ZONE
    lo0, la1 = to_lonlat(x0, z0); lo1, la0 = to_lonlat(x1, z1)
    q = dict(SERVICE="WFS", VERSION="2.0.0", REQUEST="GetFeature", TYPENAMES="CADASTRALPARCELS.PARCELLAIRE_EXPRESS:parcelle",
             BBOX="%f,%f,%f,%f,urn:ogc:def:crs:EPSG::4326" % (la0, lo0, la1, lo1), outputFormat="application/json", count="2000")
    url = "https://data.geopf.fr/wfs/ows?" + urllib.parse.urlencode(q)
    for k in range(6):
        try:
            d = json.load(urllib.request.urlopen(url, timeout=120))
            break
        except Exception as e:
            print("nouvel essai", k, e); time.sleep(5 * (k + 1))
    json.dump(d, open(os.path.join(DATA, "cadastre_balcon.json"), "w"))
    print(len(d["features"]), "parcelles")


if __name__ == "__main__":
    main()
