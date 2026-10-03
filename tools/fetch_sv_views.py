"""Vues Street View ciblées (une maison, un portail…) depuis des panoramas déjà connus (data/streetview/rues/index.json).

Clé lue dans GOOGLE_MAPS_API_KEY (jamais écrite dans le dépôt). Avant tout appel : copier le cache privé
DisColow/rochetoirin-streetview ; une vue déjà présente (même nom) n'est pas retéléchargée. Après : pousser les
nouvelles images dans le cache privé.
Usage : python3 fetch_sv_views.py vues.json
vues.json : [{"name": ..., "pano": <clé de rues/index.json>, "target": [x, z] | "heading": h, "fov": 75, "pitch": 6}, ...]
-> data/streetview/vues/<name>.jpg + index.json
"""
import json, math, os, sys, urllib.parse, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
SV = os.path.join(HERE, "data", "streetview")
OUT = os.path.join(SV, "vues")
KEY = os.environ.get("GOOGLE_MAPS_API_KEY", "")


def main(path):
    import rue_balcon
    rues = json.load(open(os.path.join(SV, "rues", "index.json")))
    os.makedirs(OUT, exist_ok=True)
    idx_path = os.path.join(OUT, "index.json")
    index = json.load(open(idx_path)) if os.path.exists(idx_path) else {}
    n = 0
    for v in json.load(open(path)):
        if v["name"] in index and os.path.exists(os.path.join(OUT, v["name"] + ".jpg")):
            continue
        if not KEY:
            sys.exit("GOOGLE_MAPS_API_KEY absente")
        p = rues[v["pano"]]
        cam = rue_balcon.sv_cam_fix(p["cam"], p.get("date"))       # position réelle (panoramas 2014 décalés)
        if "target" in v:
            tx, tz = v["target"]
            heading = math.degrees(math.atan2(tx - cam[0], -(tz - cam[1]))) % 360
        else:
            heading = v["heading"]
        fov, pitch = v.get("fov", 75), v.get("pitch", 5)
        img = urllib.request.urlopen(urllib.request.Request(
            "https://maps.googleapis.com/maps/api/streetview?" + urllib.parse.urlencode(dict(
                size="640x480", pano=p["pano"], heading="%.1f" % heading, pitch="%.1f" % pitch, fov=fov,
                source="outdoor", key=KEY)), headers={"User-Agent": "rochetoirin-drive"}), timeout=60).read()
        open(os.path.join(OUT, v["name"] + ".jpg"), "wb").write(img)
        index[v["name"]] = dict(pano=p["pano"], key=v["pano"], cam=cam, heading=heading, fov=fov, pitch=pitch,
                                date=p.get("date"), target=v.get("target"))
        n += 1
        print(v["name"], "cap %.0f" % heading, p.get("date"))
    json.dump(index, open(idx_path, "w"), indent=1)
    print(n, "images téléchargées")


if __name__ == "__main__":
    main(sys.argv[1])
