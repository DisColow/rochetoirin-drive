"""Bibliothèque de matières partagée des bâtiments sur mesure (v6.38, solution A de l'issue #13 : l'APK dépassait
2 Go avec un atlas par bâtiment). Une tuile neutre (teinte de référence BASE) par type de matière, qui se raccorde dans
les deux sens (période PERIODE m) ; le shader (sur_mesure.gdshaderinc) la teinte avec la couleur du relevé
(couleur / BASE), comme le faisait la peinture par bâtiment (matiere(), toiture() de batiment.py).
Sortie : godot/assets/sur_mesure/_bib.png (CASES × CASES cases de CELL px : marge de GOUTTE px recopiée par raccord,
pour les mipmaps). fond(z, mur) peint le même motif dans une zone de l'atlas d'un bâtiment (marges des
décalcomanies : raccord exact avec le mur).
Lancer depuis pipeline/ : python3 sur_mesure/bibliotheque.py"""
import math, os, random
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi

ICI = os.path.dirname(os.path.abspath(__file__))
GOD = os.path.join(os.path.dirname(ICI), "..", "godot")
SORTIE = os.path.join(GOD, "assets", "sur_mesure", "_bib.png")
PERIODE = 4.0           # m
CONTENU = 448           # px pour PERIODE (112 px/m)
GOUTTE = 32
CELL = CONTENU + 2 * GOUTTE     # 512
CASES = 4                        # 4 × 4 cases : atlas de 2048 px
BASE = (200, 200, 200)           # teinte de référence des tuiles neutres
KINDS = ["enduit", "bardage", "bardageh", "bois", "pierre", "brique", "beton",
         "tuile", "tuile_brune", "ardoise", "fibro", "bac"]
DEFAUT = {"pierre": (150, 128, 100), "brique": (138, 88, 58), "beton": (196, 192, 184), "bois": (110, 80, 52),
          "bardage": (170, 174, 178), "bardageh": (126, 133, 141), "enduit": (220, 210, 190),
          "tuile": (150, 78, 56), "tuile_brune": (120, 72, 52), "ardoise": (70, 74, 82), "fibro": (176, 176, 168),
          "bac": (150, 60, 50)}


def hexc(s, defaut):
    if not s or "#" not in s:
        return defaut
    h = s.split("#")[-1]
    try:
        return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))
    except ValueError:
        return defaut


def kind_de(mat, toit=False):
    k = (mat or "").split("#")[0] or ("tuile" if toit else "enduit")
    if k not in KINDS:
        k = "tuile" if toit else "enduit"
    return k


def couleur(mat, toit=False):
    k = kind_de(mat, toit)
    return hexc(mat, DEFAUT[k])


def slot(mat, toit=False):
    return KINDS.index(kind_de(mat, toit))


def _f(c, f):
    return tuple(int(max(0, min(255, v * f))) for v in c)


def _tuile(kind, seed=3):
    """Tuile neutre de PERIODE m (CONTENU px), raccord dans les deux sens : éléments dessinés sur une toile 3 × 3."""
    N = CONTENU; s = N / PERIODE
    T = Image.new("RGB", (3 * N, 3 * N), BASE)
    d = ImageDraw.Draw(T)
    r = random.Random(seed)
    els = []                                              # (rectangle | ligne, coordonnées en px de la période, couleur, largeur)
    c = BASE
    if kind == "bardage":
        n = int(round(PERIODE / 0.25)); pas = N / n
        for k in range(n):
            x = k * pas
            els.append(("l", (x, 0, x, N), _f(c, 0.88), max(1, int(0.03 * s))))
            els.append(("l", (x + 0.04 * s, 0, x + 0.04 * s, N), _f(c, 1.04), 1))
    elif kind == "bardageh":
        n = int(round(PERIODE / 0.3)); pas = N / n
        for k in range(n):
            y = k * pas
            els.append(("l", (0, y, N, y), _f(c, 0.84), max(1, int(0.04 * s))))
            els.append(("l", (0, y + 0.05 * s, N, y + 0.05 * s), _f(c, 1.06), 1))
    elif kind == "bois":
        n = int(round(PERIODE / 0.18)); pas = N / n
        for k in range(n):
            x = k * pas
            els.append(("r", (x, 0, x + pas, N), _f(c, r.uniform(0.82, 1.12)), 0))
            els.append(("l", (x, 0, x, N), _f(c, 0.55), 1))
    elif kind in ("pierre", "brique", "beton"):
        bh, bw = {"pierre": (0.28, 0.45), "brique": (0.065, 0.22), "beton": (0.2, 0.5)}[kind]
        rows = int(round(PERIODE / bh)); bh = PERIODE / rows
        if kind != "pierre":
            cols = int(round(PERIODE / bw)); bw = PERIODE / cols
        joint = {"pierre": _f(c, 0.72), "brique": _f(c, 1.3), "beton": _f(c, 0.85)}[kind]
        els.append(("r", (0, 0, N, N), joint, 0))
        for k in range(rows):
            y0 = k * bh * s
            x = -(bw * s / 2 if k % 2 else 0)
            while x < N:
                w = bw * s * (r.uniform(0.6, 1.5) if kind == "pierre" else 1)
                f = r.uniform(0.8, 1.15) if kind != "beton" else r.uniform(0.95, 1.04)
                els.append(("r", (x + 1, y0 + 1, x + w - 1, y0 + bh * s - 1), _f(c, f), 0))
                x += w
    elif kind in ("tuile", "tuile_brune", "ardoise"):
        rh, rw = (0.33, 0.25) if kind != "ardoise" else (0.2, 0.3)
        rows = int(round(PERIODE / rh)); rh = PERIODE / rows
        cols = int(round(PERIODE / rw)); rw = PERIODE / cols
        for k in range(rows):
            y = k * rh * s; dx = r.uniform(0, rw * s)
            for j in range(cols + 1):
                x = j * rw * s - dx
                els.append(("r", (x, y, x + rw * s - 1, y + rh * s - 1), _f(c, r.uniform(0.86, 1.1)), 0))
            els.append(("l", (0, y + rh * s - 1, N, y + rh * s - 1), _f(c, 0.62), 1))
    elif kind in ("fibro", "bac"):
        pas = 0.2 if kind == "bac" else 0.18
        n = int(round(PERIODE / pas)); pas = N / n
        for k in range(n):
            x = k * pas
            els.append(("l", (x, 0, x, N), _f(c, 0.75), max(1, int(0.04 * s))))
    for ox in (0, N, 2 * N):
        for oy in (0, N, 2 * N):
            for t, (a, b, e, f_), col, w in els:
                if t == "r":
                    d.rectangle((a + ox, b + oy, e + ox, f_ + oy), fill=col)
                else:
                    d.line((a + ox, b + oy, e + ox, f_ + oy), fill=col, width=w)
    a = np.asarray(T).astype(np.float32)[N:2 * N, N:2 * N]
    # grain : bruit fin + taches douces, périodiques (comme bruit() de la boulangerie, en raccord)
    rg = np.random.default_rng(seed)
    amp = 5 if kind == "enduit" else (4 if kind in KINDS[7:] else 3)
    fin = rg.normal(0, amp, (N, N, 1))
    gros = ndi.gaussian_filter(rg.random((N, N)), N / 40, mode="wrap")
    gros = (gros - gros.mean()) / (gros.std() + 1e-6) * 0.29
    a = a * (1.0 + gros[..., None] * 0.05 * (2.0 if kind in KINDS[7:] else 1.0)) + fin
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), "RGB")


_cache = {}


def tuile(kind):
    if kind not in _cache:
        _cache[kind] = _tuile(kind, seed=3 + KINDS.index(kind))
    return _cache[kind]


def construire_atlas():
    W = CELL * CASES
    A = Image.new("RGB", (W, W), BASE)
    for i, k in enumerate(KINDS):
        t = np.asarray(tuile(k))
        big = np.tile(t, (3, 3, 1))
        cx, cy = (i % CASES) * CELL, (i // CASES) * CELL
        c = big[CONTENU - GOUTTE:2 * CONTENU + GOUTTE, CONTENU - GOUTTE:2 * CONTENU + GOUTTE]
        A.paste(Image.fromarray(c), (cx, cy))
    A.save(SORTIE)
    return SORTIE


def fond(z, mat, toit=False):
    """Peint dans la zone z (atlas d'un bâtiment, s px/m, origine en bas à gauche) le motif de la bibliothèque, teinté,
    calé comme sur le mur (u, v en mètres depuis l'origine de la zone) : raccord exact avec les décalcomanies."""
    k = kind_de(mat, toit)
    c = np.array(couleur(mat, toit), np.float32) / np.array(BASE, np.float32)
    s = z.s
    per = max(4, int(round(PERIODE * s)))
    t = tuile(k).resize((per, per), Image.LANCZOS)
    t = np.asarray(t).astype(np.float32)
    w, h = int(math.ceil(z.w)), int(math.ceil(z.h))
    # pixel (x, y) de la zone -> u = x / s, v = (h - y) / s ; motif : colonne u / P, ligne (-v / P) (sens du shader)
    xs = (np.arange(w) * per / (PERIODE * s)).astype(np.int64) % per
    ys = ((np.arange(h) - h) * per / (PERIODE * s)).astype(np.int64) % per
    img = t[ys][:, xs] * c
    z.img.paste(Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)), (int(z.x0), int(z.y0)))


if __name__ == "__main__":
    print(construire_atlas())
