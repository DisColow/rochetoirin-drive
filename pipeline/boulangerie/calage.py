"""Calage du relevé de la boulangerie sur les photos Street View (cache privé streetview/boulangerie/) : le modèle
(releve.json) est projeté en fil de fer sur chaque photo avec la position, le cap, l'inclinaison et le champ exacts de la
caméra ; on corrige le relevé jusqu'à ce que les traits tombent sur les arêtes, fenêtres et portes des photos.
Usage : python3 calage.py [photo ...] -> planche JPEG (chemin en sortie)."""
import json, math, os, sys
from PIL import Image, ImageDraw

ICI = os.path.dirname(os.path.abspath(__file__))
SV = "/home/user/rochetoirin-streetview/streetview/boulangerie"
CAM_H = 2.5            # hauteur de la caméra de la voiture Google au-dessus du sol (m)


def charger():
    return json.load(open(os.path.join(ICI, "releve.json")))


def repere(m):
    """(u, v, y) du bâtiment -> (x, y, z) du monde. u le long de la rue (vers l'est), v vers l'intérieur (sud)."""
    ox, oz = m["origine"]
    a = math.radians(m["angle"])
    e = (math.cos(a), math.sin(a))
    n = (-math.sin(a), math.cos(a))
    return lambda u, v, y=0.0: (ox + e[0] * u + n[0] * v, y, oz + e[1] * u + n[1] * v)


def segments(m):
    """Arêtes du modèle (paires de points du monde) et leur couleur."""
    P = repere(m)
    L, D, He, Hr = m["longueur"], m["profondeur"], m["egout"], m["faitage"]
    s = []
    coins = [(0, 0), (L, 0), (L, D), (0, D)]
    for i in range(4):
        (u0, v0), (u1, v1) = coins[i], coins[(i + 1) % 4]
        s.append((P(u0, v0, 0), P(u1, v1, 0), "red"))
        s.append((P(u0, v0, He), P(u1, v1, He), "red"))
        s.append((P(u0, v0, 0), P(u0, v0, He), "red"))
    # toit à deux pans, faîtage le long de u (pignons en u = 0 et u = L), débords
    db, dp = m["debord_bas"], m["debord_pignon"]
    vr = D / 2
    for u in (-dp, L + dp):
        s.append((P(u, -db, He - db * (Hr - He) / vr), P(u, vr, Hr), "yellow"))
        s.append((P(u, vr, Hr), P(u, D + db, He - db * (Hr - He) / vr), "yellow"))
    s.append((P(-dp, vr, Hr), P(L + dp, vr, Hr), "yellow"))
    s.append((P(-dp, -db, He - db * (Hr - He) / vr), P(L + dp, -db, He - db * (Hr - He) / vr), "yellow"))
    # petit pignon côté rue
    g = m.get("pignon_rue")
    if g:
        uc, w, h = g["centre"], g["largeur"], g["sommet"]
        s.append((P(uc - w / 2, -db, He), P(uc, -db, h), "orange"))
        s.append((P(uc, -db, h), P(uc + w / 2, -db, He), "orange"))
    # ouvertures : face N (v = 0, u croissant), E (u = L, v croissant)
    for o in m.get("ouvertures", []):
        f, a0, a1, y0, y1 = o["face"], o["de"], o["a"], o["bas"], o["haut"]
        pt = (lambda a, y: P(a, 0, y)) if f == "N" else (lambda a, y: P(L, a, y))
        c = o.get("couleur", "cyan")
        s += [(pt(a0, y0), pt(a1, y0), c), (pt(a1, y0), pt(a1, y1), c), (pt(a1, y1), pt(a0, y1), c), (pt(a0, y1), pt(a0, y0), c)]
    for (q0, q1) in m.get("traits", []):
        s.append((P(*q0), P(*q1), "magenta"))
    return s


def projeter(v, cam, cap, tang, fov, W, H, sol):
    cx, cz = cam
    d = (v[0] - cx, -(v[2] - cz), v[1] - (sol + CAM_H))          # est, nord, haut
    h, p = math.radians(cap), math.radians(tang)
    f = (math.sin(h) * math.cos(p), math.cos(h) * math.cos(p), math.sin(p))
    r = (math.cos(h), -math.sin(h), 0.0)
    u = (r[1] * f[2] - r[2] * f[1], r[2] * f[0] - r[0] * f[2], r[0] * f[1] - r[1] * f[0])
    z = sum(a * b for a, b in zip(d, f))
    if z < 0.5:
        return None
    k = (W / 2) / math.tan(math.radians(fov) / 2)
    return (W / 2 + sum(a * b for a, b in zip(d, r)) / z * k, H / 2 - sum(a * b for a, b in zip(d, u)) / z * k)


def dessiner(nom, m):
    ix = json.load(open(SV + "/index.json"))[nom]
    im = Image.open("%s/%s.jpg" % (SV, nom)).convert("RGB")
    W, H = im.size
    d = ImageDraw.Draw(im)
    sol = m.get("sol_cam", {}).get(ix["pano"], 0.0)
    for a, b, c in segments(m):
        pa = projeter(a, ix["cam"], ix["heading"], ix["pitch"], ix["fov"], W, H, sol)
        pb = projeter(b, ix["cam"], ix["heading"], ix["pitch"], ix["fov"], W, H, sol)
        if pa and pb:
            d.line([pa, pb], fill=c, width=1)
    d.text((6, 6), nom, fill="white")
    return im


if __name__ == "__main__":
    m = charger()
    noms = sys.argv[1:] or ["b_haut", "f_pignon", "f_est_zoom", "f_angle_zoom", "b_angle", "c_est"]
    ims = [dessiner(n, m) for n in noms]
    col = 3
    out = Image.new("RGB", (640 * col, 640 * ((len(ims) + col - 1) // col)))
    for i, im in enumerate(ims):
        out.paste(im, ((i % col) * 640, (i // col) * 640))
    p = "/tmp/claude-0/-home-user/2cff0bea-6915-5af5-9412-60b47b93c8bd/scratchpad/t/calage.jpg"
    out.save(p, quality=90)
    print(p)
