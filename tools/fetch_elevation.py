"""Télécharge l'altimétrie IGN RGE ALTI (API Géoplateforme) sur une grille régulière.

Produit data/elev_inner.npy (grille fine, zone jouable) et data/elev_outer.npy
(grille grossière, horizon lointain). Les fichiers déjà présents ne sont pas re-téléchargés.
"""
import json, os, sys, time, urllib.request
import numpy as np
from geo import INNER, OUTER, PANO, grid_lonlat

API = "https://data.geopf.fr/altimetrie/1.0/calcul/alti/rest/elevation.json"
HERE = os.path.dirname(os.path.abspath(__file__))
BATCH = 5000


def fetch(lons, lats):
    body = json.dumps({"lon": "|".join("%.7f" % v for v in lons),
                       "lat": "|".join("%.7f" % v for v in lats),
                       "resource": "ign_rge_alti_wld", "zonly": "true",
                       "delimiter": "|"}).encode()
    for attempt in range(6):
        try:
            req = urllib.request.Request(API, data=body, headers={"Content-Type": "application/json"})
            r = json.load(urllib.request.urlopen(req, timeout=180))
            return r["elevations"]
        except Exception as e:  # réseau / limitation de débit
            print("  retry", attempt, e, flush=True)
            time.sleep(2 ** attempt)
    raise RuntimeError("échec IGN")


def fetch_grid(spec, out):
    path = os.path.join(HERE, "data", out)
    if os.path.exists(path):
        print(out, "déjà présent"); return
    lon, lat = grid_lonlat(spec)
    flat_lon, flat_lat = lon.ravel(), lat.ravel()
    z = np.zeros(flat_lon.size, dtype=np.float32)
    for i in range(0, flat_lon.size, BATCH):
        z[i:i + BATCH] = fetch(flat_lon[i:i + BATCH], flat_lat[i:i + BATCH])
        print(out, i + BATCH, "/", flat_lon.size, flush=True)
    z = z.reshape(lon.shape)
    # l'API renvoie -99999 hors couverture : on bouche avec la médiane
    bad = z < -1000
    if bad.any():
        z[bad] = np.median(z[~bad])
    np.save(path, z)


if __name__ == "__main__":
    fetch_grid(OUTER, "elev_outer.npy")
    fetch_grid(INNER, "elev_inner.npy")
    fetch_grid(PANO, "elev_pano.npy")
