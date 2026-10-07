"""Autoroutes : glissières de sécurité le long des chaussées (interrompues aux bretelles), bornes d'appel d'urgence
orange (positions OSM, posées au bord de la bande d'arrêt d'urgence), panneaux bleus de présignalisation des sorties
(numéro et destinations, à 1 000 m et 500 m), balises à chevrons au nez des bretelles, gares de péage (auvent au-dessus
de la chaussée, cabines et piles hors des voies).
Rien sur la chaussée : tout est posé au-delà du bord de la route (bande d'arrêt d'urgence comprise).
Modèles : blender_autoroute.py. Sorties : ../godot/assets/autoroute/panneaux.png (atlas des panneaux, cases 512 × 256),
../godot/world/autoroute/r_tx_tz.bin : int32 n, n × 17 float32 (modèle, base 3 × 3 colonnes, origine, 4 données)."""
import json, math, os, pickle, shutil
from collections import defaultdict
import numpy as np
from PIL import Image, ImageDraw, ImageFont
import geo

OUT_A = "../godot/assets/autoroute"
OUT_W = "../godot/world/autoroute"
TILE = 256.0
MODELS = ["glissiere", "borne_sos", "panneau_bleu", "peage", "pile_peage", "chevron"]
MID = {n: i for i, n in enumerate(MODELS)}
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
BLUE = (16, 62, 140)


class Atlas:
    W, CW, CH = 4096, 512, 256

    def __init__(self):
        self.img = Image.new("RGB", (self.W, self.W), BLUE)
        self.cells = {}

    def panel(self, num, dests, dist):
        key = (num, tuple(dests), dist)
        if key in self.cells:
            return self.cells[key]
        i = len(self.cells)
        if i >= (self.W // self.CW) * (self.W // self.CH):
            return next(iter(self.cells.values()))
        cx, cy = (i % 8) * self.CW, (i // 8) * self.CH
        c = Image.new("RGB", (self.CW, self.CH), BLUE)
        d = ImageDraw.Draw(c)
        d.rounded_rectangle([6, 6, self.CW - 7, self.CH - 7], 18, outline=(255, 255, 255), width=6)
        y = 18
        if num:
            # cartouche du numéro de sortie (blanc, chiffres bleus), à gauche
            f = ImageFont.truetype(FONT, 40)
            d.rounded_rectangle([22, y, 150, y + 58], 10, fill=(255, 255, 255))
            t = "SORTIE" if len(num) > 3 else "SORTIE " + num
            ft = ImageFont.truetype(FONT, 22 if len(t) > 8 else 28)
            b = ft.getbbox(t)
            d.text((86 - (b[2] - b[0]) // 2, y + 29 - (b[3] - b[1]) // 2 - b[1]), t, font=ft, fill=BLUE)
        if dist:
            fd = ImageFont.truetype(FONT, 34)
            b = fd.getbbox(dist)
            d.text((self.CW - 30 - (b[2] - b[0]), y + 8), dist, font=fd, fill=(255, 255, 255))
        lines = dests[:3]
        ys = 92 if num or dist else 40
        hh = (self.CH - ys - 22) // max(1, len(lines))
        for k, ln in enumerate(lines):
            s = 40
            while s > 14:
                f = ImageFont.truetype(FONT, s)
                b = f.getbbox(ln)
                if b[2] - b[0] <= self.CW - 60 and b[3] - b[1] <= hh - 4:
                    break
                s -= 2
            d.text((30, ys + k * hh + (hh - (b[3] - b[1])) // 2 - b[1]), ln, font=f, fill=(255, 255, 255))
        self.img.paste(c, (cx, cy))
        r = (cx / self.W, cy / self.W, self.CW / self.W, self.CH / self.W)
        self.cells[key] = r
        return r


def basis_along(t, slope=0.0, length=1.0):
    """Base : x le long de t (avec la pente, longueur length), y en haut, z à gauche de t."""
    X = (t[0] * length, slope, t[1] * length)
    Z = (-t[1], 0.0, t[0])
    return X + (0.0, 1.0, 0.0) + Z


def basis_facing(n, sx=1.0, sy=1.0):
    """Base d'un objet dont le +z regarde dans la direction n (plan), x = n tourné de -90°."""
    X = (n[1] * sx, 0.0, -n[0] * sx)
    return X + (0.0, sy, 0.0) + (n[0], 0.0, n[1])


def main():
    os.makedirs(OUT_A, exist_ok=True)
    shutil.rmtree(OUT_W, ignore_errors=True); os.makedirs(OUT_W)
    ways = pickle.load(open("data/roads.pkl", "rb"))["ways"]
    mw = [w for w in ways if w["cls"] == "motorway" and len(w["P"]) > 1]
    links = [w for w in ways if w["cls"] == "motorway_link" and len(w["P"]) > 1]
    osm = json.load(open("data/osm_autoroute.json"))["elements"]
    jref = {e["id"]: e["tags"].get("ref") for e in osm if e["type"] == "node" and e["tags"].get("highway") == "motorway_junction"}
    ldest = {}
    for e in osm:
        if e["type"] == "way" and e["tags"].get("highway") == "motorway_link":
            nd = e.get("nodes") or []
            dest = e["tags"].get("destination") or e["tags"].get("destination:ref") or ""
            if dest:
                ldest[e["id"]] = dest
    # noeuds de raccordement des bretelles sur les chaussées d'autoroute
    mnodes = defaultdict(list)
    for w in mw:
        for k, n in enumerate(w["nodes"]):
            mnodes[n].append((w, w["s"][w["idx"][k]]))
    atlas = Atlas()
    inst = []
    stats = defaultdict(int)

    def pos(w, s, off):
        """Point de la chaussée w à l'abscisse s, décalé de off (positif à droite du sens de circulation)."""
        k = int(np.clip(np.searchsorted(w["s"], s), 1, len(w["s"]) - 1))
        a = (s - w["s"][k - 1]) / max(w["s"][k] - w["s"][k - 1], 1e-6)
        P = w["P"][k - 1] + (w["P"][k] - w["P"][k - 1]) * a
        T = w["T"][k - 1]; N = w["N"][k - 1]
        y = w["y"][k - 1] + (w["y"][k] - w["y"][k - 1]) * a
        right = -np.asarray(N)                    # N est à gauche du sens de la polyligne
        return P + right * off, np.asarray(T), right, y

    # bretelles : sorties (début sur l'autoroute) -> panneaux et chevrons
    breaks = defaultdict(list)            # chaussée -> abscisses où la glissière s'interrompt
    for l in links:
        n0, n1 = l["nodes"][0], l["nodes"][-1]
        for n, is_exit in ((n0, True), (n1, False)):
            for (w, s) in mnodes.get(n, []):
                breaks[id(w)].append(s)
                if not is_exit:
                    continue
                dests = [d.strip() for d in ldest.get(l["id"], "").split(";") if d.strip()]
                if not dests:
                    dests = ["Toutes directions"]
                num = jref.get(n) or ""
                hw = w["w"] / 2
                for dist in (1000.0, 500.0):
                    if s - dist < 5:
                        continue
                    p, T, R, y = pos(w, s - dist, hw + 2.5)
                    cell = atlas.panel(num, dests, "%d m" % dist)
                    face = -T                                     # face vers les voitures qui arrivent
                    inst.append((MID["panneau_bleu"],) + basis_facing(face, 4.6, 2.3) + (p[0], y + 2.5, p[1]) + cell)
                    stats["panneaux"] += 1
                # balise à chevrons au nez de la bretelle (60 m après la divergence, entre les deux voies)
                p, T, R, y = pos(w, s + 60.0, hw + 1.6)
                inst.append((MID["chevron"],) + basis_facing(-T) + (p[0], y, p[1], 0, 0, 0, 0))
                stats["chevrons"] += 1
    # glissières : des deux côtés de chaque chaussée, interrompues 250 m autour des raccordements de bretelles
    for w in mw:
        hw = w["w"] / 2
        L = w["s"][-1]
        brk = breaks.get(id(w), [])
        for side in (1, -1):
            s = 2.0
            while s + 4.0 < L:
                if any(abs(s - b) < 250.0 for b in brk) or w["bridge"]:
                    s += 4.0
                    continue
                pa, T, R, ya = pos(w, s, side * (hw + 0.7))
                pb, _, _, yb = pos(w, s + 4.0, side * (hw + 0.7))
                t = (pb - pa); Lt = np.linalg.norm(t); t = t / max(Lt, 1e-6)
                # +z du modèle (côté route) vers la chaussée
                if side > 0:
                    X = (t[0] * Lt, yb - ya, t[1] * Lt); Z = (-t[1], 0.0, t[0])
                    org = pa
                else:
                    X = (-t[0] * Lt, ya - yb, -t[1] * Lt); Z = (t[1], 0.0, -t[0])
                    org = pb
                inst.append((MID["glissiere"],) + X + (0.0, 1.0, 0.0) + Z + (org[0], (ya if side > 0 else yb) - 0.05, org[1], 0, 0, 0, 0))
                stats["travées de glissière"] += 1
                s += 4.0
    # bornes d'appel d'urgence (OSM), au bord de la bande d'arrêt d'urgence de la chaussée la plus proche
    for e in osm:
        if e["type"] != "node" or e["tags"].get("emergency") != "phone":
            continue
        x, z = geo.to_local(e["lon"], e["lat"])
        best = None
        for w in mw:
            d = np.hypot(w["P"][:, 0] - x, w["P"][:, 1] - z)
            k = int(np.argmin(d))
            if best is None or d[k] < best[0]:
                best = (d[k], w, w["s"][k])
        if best is None or best[0] > 40:
            continue
        _, w, s = best
        p, T, R, y = pos(w, s, w["w"] / 2 + 1.6)
        inst.append((MID["borne_sos"],) + basis_facing(-R) + (p[0], y - 0.05, p[1], 0, 0, 0, 0))
        stats["bornes SOS"] += 1
    # gares de péage (OSM barrier=toll_booth) : auvent au-dessus de la route, piles et cabines hors des voies
    for e in osm:
        if e["tags"].get("barrier") != "toll_booth":
            continue
        if e["type"] == "node":
            x, z = geo.to_local(e["lon"], e["lat"])
        else:
            g = e.get("geometry") or []
            if not g:
                continue
            x, z = geo.to_local(np.mean([q["lon"] for q in g]), np.mean([q["lat"] for q in g]))
        best = None
        for w in mw + links:
            d = np.hypot(w["P"][:, 0] - x, w["P"][:, 1] - z)
            k = int(np.argmin(d))
            if best is None or d[k] < best[0]:
                best = (d[k], w, w["s"][k])
        if best is None or best[0] > 25:
            continue
        _, w, s = best
        p, T, R, y = pos(w, s, 0.0)
        hw = w["w"] / 2
        inst.append((MID["peage"],) + basis_along(T, 0.0, 8.0)[:3] + (0.0, 1.0, 0.0) + (R[0] * (hw + 2.0) / 4.5, 0.0, R[1] * (hw + 2.0) / 4.5)
                    + (p[0], y, p[1], 0, 0, 0, 0))
        for sg in (1, -1):
            q = p + R * sg * (hw + 1.6)
            inst.append((MID["pile_peage"],) + basis_facing(R * sg) + (q[0], y, q[1], 0, 0, 0, 0))
        stats["péages"] += 1
    atlas.img.save(OUT_A + "/panneaux.png")
    T_ = defaultdict(list)
    for r in inst:
        T_[(int(math.floor(r[10] / TILE)), int(math.floor(r[12] / TILE)))].append(r)
    for (tx, tz), S in T_.items():
        open("%s/r_%d_%d.bin" % (OUT_W, tx, tz), "wb").write(np.int32(len(S)).tobytes() + np.array(S, "<f4").tobytes())
    print(dict(stats), len(T_), "tuiles,", len(atlas.cells), "panneaux différents")


if __name__ == "__main__":
    main()
