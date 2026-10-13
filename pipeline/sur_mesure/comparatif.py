"""Comparatif photo / jeu des bâtiments sur mesure (méthode de la boulangerie) : le jeu est capturé exactement depuis
chaque caméra Street View du bâtiment (position, cap, inclinaison, champ ; 640 × 640, champ vertical = horizontal),
puis chaque photo est mise à côté de la capture. Planche : SV_DIR/../planches/cmp_<id>.jpg (cache privé).
Lancer depuis pipeline/ (après batiment.py et l'import Godot) : python3 sur_mesure/comparatif.py <id> [<id>…]"""
import json, math, os, subprocess, sys
import numpy as np
from PIL import Image, ImageDraw

ICI = os.path.dirname(os.path.abspath(__file__))
PIPE = os.path.dirname(ICI)
sys.path.insert(0, PIPE); sys.path.insert(0, ICI)
from calage import SV, PLANCHES, CAM_H, corriger

GOD = os.path.join(PIPE, "..", "godot")
SHOTS = os.path.expanduser("~/.local/share/godot/app_userdata/Rochetoirin Simulator/shots")
TMP = os.environ.get("TMPDIR_CMP", "/tmp/claude-0/-home-user/2cff0bea-6915-5af5-9412-60b47b93c8bd/scratchpad")


def main(ids):
    from build_buildings import CarvedDEM
    dem = CarvedDEM()
    idx = json.load(open(os.path.join(SV, "index.json")))
    shots, par = [], {}
    for ident in ids:
        R = json.load(open(os.path.join(ICI, "releves", ident + ".json")))
        for v in idx.get(R["cleabs"], {}).get("vues", []):
            v = corriger(v, R)
            y = float(dem.h(np.array([v["cam"][0]]), np.array([v["cam"][1]]))[0]) + CAM_H
            h, p = math.radians(v["heading"]), math.radians(v["pitch"])
            d = (math.sin(h) * math.cos(p), math.sin(p), -math.cos(h) * math.cos(p))
            pos = [v["cam"][0], y, v["cam"][1]]
            shots.append(dict(name="cmp_" + v["nom"], pos=pos, look=[pos[i] + d[i] * 10 for i in range(3)],
                              fov=v["fov"], hud=False))
            par.setdefault(ident, []).append(v["nom"])
    js = os.path.join(TMP, "cmp_shots.json")
    json.dump(shots, open(js, "w"))
    subprocess.run(["timeout", "1500", "xvfb-run", "-a", "godot", "--path", GOD, "--resolution", "640x640", "--",
                    "--shots=" + js], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    os.makedirs(PLANCHES, exist_ok=True)
    for ident, noms in par.items():
        out = Image.new("RGB", (1280, 640 * len(noms)))
        for k, n in enumerate(noms):
            out.paste(Image.open(os.path.join(SV, n + ".jpg")).convert("RGB").resize((640, 640)), (0, k * 640))
            g = os.path.join(SHOTS, "cmp_%s.png" % n)
            if os.path.exists(g):
                out.paste(Image.open(g).convert("RGB").resize((640, 640)), (640, k * 640))
            ImageDraw.Draw(out).text((646, k * 640 + 6), "jeu", fill="white")
        q = os.path.join(PLANCHES, "cmp_%s.jpg" % ident)
        out.save(q, quality=85)
        print(q)


if __name__ == "__main__":
    main(sys.argv[1:])
