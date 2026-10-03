"""Vues Street View le long d'une rue (avant / gauche / droite / arrière à chaque panorama) pour la modéliser
d'après la réalité et comparer au jeu (mêmes caméras dans le harnais WebGL).

Clé lue dans GOOGLE_MAPS_API_KEY (jamais écrite dans le dépôt). Avant tout appel : copier le cache privé
DisColow/rochetoirin-streetview ; les panoramas déjà présents dans index.json ne sont pas retéléchargés.
Usage : python3 fetch_sv_street.py "Rue du Balcon" ["Impasse du Balcon" ...] [--step 10]
-> data/streetview/rues/<pano>_<f|l|r|b>.jpg + index.json
"""
import json, math, os, pickle, sys, urllib.parse, urllib.request
import numpy as np
from geo import to_local, to_lonlat

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "data", "streetview", "rues")
KEY = os.environ.get("GOOGLE_MAPS_API_KEY", "")
DIRS = {"f": 0, "r": 90, "b": 180, "l": 270}


def get(url):
    return urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "rochetoirin-drive"}), timeout=60).read()


def samples(names, step):
    rows = pickle.load(open(os.path.join(HERE, "data", "road_rows.pkl"), "rb"))
    out = []
    for r in rows:
        if (r.get("name") or "") not in names:
            continue
        P = np.array(r["P"], float)
        seg = np.hypot(*np.diff(P, axis=0).T); s = np.r_[0, np.cumsum(seg)]
        for t in np.arange(0, s[-1] + 0.1, step):
            k = min(np.searchsorted(s, t, side="right") - 1, len(seg) - 1)
            u = (t - s[k]) / max(seg[k], 1e-6)
            p = P[k] + (P[k + 1] - P[k]) * u
            d = (P[k + 1] - P[k]) / max(seg[k], 1e-6)
            out.append((r["name"], float(p[0]), float(p[1]), math.degrees(math.atan2(d[0], -d[1])) % 360))
    return out


def main(names, step=10.0):
    if not KEY:
        sys.exit("GOOGLE_MAPS_API_KEY absente")
    os.makedirs(OUT, exist_ok=True)
    idx_path = os.path.join(OUT, "index.json")
    index = json.load(open(idx_path)) if os.path.exists(idx_path) else {}
    seen = {v["pano"] for v in index.values()}
    n_img = 0
    for name, x, z, hd in samples(names, step):
        lon, lat = to_lonlat(x, z)
        meta = json.loads(get("https://maps.googleapis.com/maps/api/streetview/metadata?" + urllib.parse.urlencode(
            dict(location="%f,%f" % (lat, lon), radius=8, source="outdoor", key=KEY))))
        if meta.get("status") != "OK" or meta["pano_id"] in seen:
            continue
        seen.add(meta["pano_id"])
        cx, cz = (float(v) for v in to_local(meta["location"]["lng"], meta["location"]["lat"]))
        key = meta["pano_id"][:10].replace("-", "_")
        for dname, off in DIRS.items():
            h = (hd + off) % 360
            img = get("https://maps.googleapis.com/maps/api/streetview?" + urllib.parse.urlencode(dict(
                size="640x480", pano=meta["pano_id"], heading="%.1f" % h, pitch="0", fov=90, source="outdoor", key=KEY)))
            open(os.path.join(OUT, "%s_%s.jpg" % (key, dname)), "wb").write(img)
            n_img += 1
        index[key] = dict(pano=meta["pano_id"], rue=name, cam=[cx, cz], heading=hd, fov=90, date=meta.get("date"),
                          sample=[x, z])
        print(name, key, "(%.0f, %.0f)" % (cx, cz), meta.get("date"))
    json.dump(index, open(idx_path, "w"), indent=1)
    print(n_img, "images téléchargées")


if __name__ == "__main__":
    a = sys.argv[1:]
    step = 10.0
    if "--step" in a:
        i = a.index("--step"); step = float(a[i + 1]); a = a[:i] + a[i + 2:]
    main(set(a), step)
