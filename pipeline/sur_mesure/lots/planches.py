"""Revue d'une commune (v6.34) : liste des bâtiments non résidentiels photographiés (lots/<lot>_liste.json : indice,
cleabs, usage, nature, hauteur BD TOPO, face la plus vue des caméras) et planches de revue de 9 bâtiments (une photo
chacun) dans le scratchpad / SC_DIR (photos Google : jamais dans le dépôt).
Lancer depuis pipeline/ : python3 sur_mesure/lots/planches.py <lot> <commune> <préfixe>"""
import json, os, sys
import numpy as np
from PIL import Image, ImageDraw
ICI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(ICI)); sys.path.insert(0, os.path.dirname(os.path.dirname(ICI)))
from fetch_sv_batiments import batiments
from batiment import Batiment, CAPS
from build_buildings import CarvedDEM

SV = os.environ.get("SV_DIR", "../../rochetoirin-streetview/streetview/batiments")


def main(lot, commune, pre, out):
    idx = json.load(open(os.path.join(SV, "index.json")))
    feats = {f["properties"]["cleabs"]: f for f in json.load(open("data/batiments.json"))["features"]}
    dem = CarvedDEM()
    faits = {c for v in json.load(open("../godot/world/sur_mesure.json")).values() for c in v.get("remplace_bati", [])}
    vis = [(c, u, g) for c, u, g in batiments(commune) if idx.get(c, {}).get("vues") and c not in faits]
    vis.sort(key=lambda t: (round(t[2].centroid.x / 150), t[2].centroid.y))
    liste = []
    for k, (c, u, g) in enumerate(vis):
        p = feats[c]["properties"]
        h = float(p.get("hauteur") or 6.0)
        R = {"id": "%s_%d" % (pre, k), "cleabs": c, "mur": "enduit#e0d8c8", "toit": {"type": "2pans", "matiere": "tuile"},
             "egout": round(max(2.5, h * 0.75), 1), "faitage": round(max(3.5, h), 1)}
        vue, Lv = "S", 0
        try:
            B = Batiment(R, feats[c], dem)
            cams = [np.array(v["cam"]) for v in idx[c]["vues"]]
            best = max(B.cotes, key=lambda cc: (sum(np.dot(cm - (B.c + (cc["p0"] + cc["p1"]) / 2), cc["n"]) > 0 for cm in cams), cc["L"]))
            vue = min(CAPS, key=lambda q: abs((best["cap"] - CAPS[q] + 180) % 360 - 180)); Lv = best["L"]
        except Exception:
            pass
        liste.append(dict(k=k, cleabs=c, usage=u, nature=p.get("nature"), h=h, aire=round(g.area), vue=vue, Lvue=round(Lv), R=R))
    json.dump(liste, open(os.path.join(ICI, lot + "_liste.json"), "w"), indent=0, ensure_ascii=False)
    os.makedirs(out, exist_ok=True)
    T = 300
    for s in range(0, len(liste), 9):
        grp = liste[s:s + 9]
        im = Image.new("RGB", (3 * T, T * ((len(grp) + 2) // 3)), "black")
        d = ImageDraw.Draw(im)
        for i, e in enumerate(grp):
            v = idx[e["cleabs"]]["vues"][0]
            f = os.path.join(SV, v["nom"] + ".jpg")
            x, y = (i % 3) * T, (i // 3) * T
            if os.path.exists(f):
                im.paste(Image.open(f).convert("RGB").resize((T, T)), (x, y))
            d.rectangle((x, y, x + T, y + 24), fill="black")
            d.text((x + 3, y + 1), "%s_%d %s/%s" % (pre, e["k"], e["usage"][:12], (e["nature"] or "")[:14]), fill="yellow")
            d.text((x + 3, y + 12), "h%.0f %dm2 vue=%s(%dm)" % (e["h"], e["aire"], e["vue"], e["Lvue"]), fill="yellow")
        im.save(os.path.join(out, "%s_%02d.jpg" % (pre, s // 9)), quality=80)
    print(commune, ":", len(liste), "bâtiments,", (len(liste) + 8) // 9, "planches")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3],
         os.environ.get("SC_DIR", "/tmp/claude-0/-home-user/2cff0bea-6915-5af5-9412-60b47b93c8bd/scratchpad/rev"))
