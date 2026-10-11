"""Vue cockpit de l'Espace I en pixel art, à la manière des vieux jeux de voitures (Test Drive, Vette!, Lotus) :
images à basse résolution (480 pixels de large, affichées en gros pixels), palette restreinte, ombrage calculé sur
des reliefs simples puis réduit à quelques teintes avec un tramage ordonné, contours d'un pixel.
Sorties : ../godot/assets/cockpit/
  dash.png   (480 × 100) planche de bord, ancrée en bas de l'écran : capot des compteurs, compteurs (sans aiguilles),
             aérateurs, autoradio, commandes de chauffage, sélecteur de la boîte, boîte à gants, vignette auto ;
  glow.png   (480 × 100) ce qui s'éclaire la nuit (graduations, chiffres, autoradio) ;
  top.png    (480 × 40)  pavillon, pare-soleil, plafonnier et rétroviseur (glace transparente : vue arrière en jeu) ;
  wheel.png  (160 × 160) volant deux branches (centre au milieu), tourné en jeu ;
  hand_l.png, hand_r.png mains sur la jante ; sleeve.png, pillar.png textures des bras et des montants ;
  pine.png   désodorisant « sapin » pendu au rétroviseur ;
  meta.json  positions utiles au script (compteurs, glace du rétro, voyants, écran de l'autoradio).
Aperçu : data/cockpit_apercu.png (si une capture du jeu est donnée en argument)."""
import json, math, os, sys
import numpy as np
from PIL import Image
from scipy import ndimage

OUT = "../godot/assets/cockpit"
W = 480

BAYER = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) / 16.0 + 1 / 32


def hexes(*h):
    return [tuple(int(x[i:i + 2], 16) for i in (1, 3, 5)) for x in h]


RAMP = {
    # ombres tirant sur le bleu-violet, lumières sur le chaud (pixel art « à l'ancienne »)
    "dash": hexes("#07070c", "#0f0f16", "#17171f", "#1f2029", "#292a33", "#34353e", "#41414a", "#504f57", "#625f66", "#78736f"),
    "liner": hexes("#2a2532", "#3c3540", "#514851", "#675c61", "#7e7270", "#968a80", "#ada192", "#c4b9a5", "#d9cfba", "#ebe3cf"),
    "pillar": hexes("#1e1b24", "#2d2930", "#3e393e", "#504a4c", "#645c5b", "#79706c", "#8d847c", "#a2988c"),
    "rubber": hexes("#040407", "#0a0a10", "#111118", "#191a22", "#22232c", "#2d2e37", "#3a3a44", "#4a4a53", "#605f67", "#7c7a80"),
    "chrome": hexes("#1a1b25", "#2e3040", "#47495a", "#636676", "#828593", "#a3a6b1", "#c3c6ce", "#dfe2e7", "#f3f4f6", "#ffffff"),
    "skin": hexes("#3d2218", "#5c3423", "#7c4a32", "#9c6346", "#b97f5d", "#d39c79", "#e8bb98"),
    "sleeve": hexes("#0d1220", "#151d33", "#1f2a47", "#2b3a5e", "#3a4c75", "#4d618c"),
    "door": hexes("#0a0a10", "#121219", "#1b1b23", "#25252e", "#30303a", "#3d3c46", "#4c4a53", "#5e5b61"),
    "face": hexes("#030305", "#08080c", "#0e0e14", "#15151c"),
    "pine": hexes("#06200f", "#0b3417", "#124a1f", "#1b6227", "#277b30", "#3a963c", "#58b04c", "#80c862"),
    "red": hexes("#2a0608", "#4a0a0d", "#701114", "#97191a", "#bd2a22", "#de4a33"),
}
LIGHT = np.array([-0.35, -0.75, 0.56])
LIGHT /= np.linalg.norm(LIGHT)
rng = np.random.default_rng(7)

# police 3 × 5 (chiffres et quelques lettres)
FONT = {
    "0": "111101101101111", "1": "010110010010111", "2": "111001111100111", "3": "111001111001111",
    "4": "101101111001001", "5": "111100111001111", "6": "111100111101111", "7": "111001010010010",
    "8": "111101111101111", "9": "111101111001111", "P": "111101111100100", "R": "110101110101101",
    "N": "101111111111101", "D": "110101101101110", "E": "111100110100111", "S": "111100111001111",
    "A": "010101111101101", "C": "111100100100111", "F": "111100110100100", "M": "101111111101101",
    "H": "101101111101101", "L": "100100100100111", "K": "101101110101101", "T": "111010010010010",
    ".": "000000000000010", " ": "000000000000000", "/": "001001010100100", "-": "000000111000000",
}


class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.px = np.zeros((h, w, 4), np.uint8)
        self.yy, self.xx = np.mgrid[0:h, 0:w].astype(np.float64)

    # ------------------------------------------------------------ formes
    def rect(self, x0, y0, x1, y1):
        return (self.xx >= x0) & (self.xx < x1) & (self.yy >= y0) & (self.yy < y1)

    def rrect(self, x0, y0, x1, y1, r):
        cx = np.clip(self.xx + 0.5, x0 + r, x1 - r); cy = np.clip(self.yy + 0.5, y0 + r, y1 - r)
        return ((self.xx + 0.5 - cx) ** 2 + (self.yy + 0.5 - cy) ** 2 <= r * r) & self.rect(x0, y0, x1, y1)

    def disc(self, cx, cy, r):
        return (self.xx + 0.5 - cx) ** 2 + (self.yy + 0.5 - cy) ** 2 <= r * r

    def poly(self, pts):
        from matplotlib.path import Path
        p = Path(pts)
        ins = p.contains_points(np.c_[self.xx.ravel() + 0.5, self.yy.ravel() + 0.5])
        return ins.reshape(self.h, self.w)

    # ------------------------------------------------------------ ombrage
    def shade(self, mask, height, ramp, amb=0.3, bias=0.0, grain=0.0, spec=0.0, scale=1.0):
        """Ombrage d'un relief (hauteur en pixels) éclairé d'en haut à gauche, réduit à la palette par tramage."""
        gy, gx = np.gradient(height * scale)
        n = np.dstack([-gx, -gy, np.ones_like(gx)])
        n /= np.linalg.norm(n, axis=2, keepdims=True)
        d = np.clip(n @ LIGHT, 0, 1)
        v = amb + (1 - amb) * d + bias
        if spec:
            v += spec * np.clip(d - 0.85, 0, 1) * 6
        if grain:
            # grain de similicuir : motif régulier de 2 × 2 pixels + un peu de bruit
            pat = (((self.xx.astype(int) // 2) + (self.yy.astype(int) // 2) * 3) % 5 == 0) * 1.0
            v += (pat - 0.2) * grain * 1.6 + rng.normal(0, grain * 0.4, v.shape)
        self.fill(mask, v, ramp)

    def fill(self, mask, v, ramp):
        R = RAMP[ramp] if isinstance(ramp, str) else ramp
        b = BAYER[(self.yy.astype(int) % 4), (self.xx.astype(int) % 4)]
        idx = np.clip(np.floor(np.asarray(v) * (len(R) - 1) + b), 0, len(R) - 1).astype(int)
        cols = np.array(R, np.uint8)[idx]
        self.px[mask, :3] = cols[mask] if cols.ndim == 3 else cols
        self.px[mask, 3] = 255

    def ao(self, mask, occ, reach=4.0, strength=0.45):
        """Ombre portée douce sur mask par les pixels occ (occlusion près des arêtes), assombrit les couleurs déjà posées."""
        d = ndimage.distance_transform_edt(~occ)
        k = np.clip(1.0 - d / reach, 0, 1) * strength * mask * ~occ
        b = BAYER[(self.yy.astype(int) % 4), (self.xx.astype(int) % 4)]
        k = np.where(k > b * 0.9, k, k * 0.4)
        self.px[..., :3] = (self.px[..., :3] * (1.0 - k[..., None])).astype(np.uint8)

    def glint(self, x, y, col=(255, 255, 255), size=1):
        """Éclat de lumière en croix (reflet spéculaire)."""
        for dx, dy in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)) if size > 1 else ((0, 0),):
            self.put(x + dx, y + dy, col)

    def flat(self, mask, col, a=255):
        self.px[mask, :3] = col
        self.px[mask, 3] = a

    def outline(self, mask, col, inner=True):
        """Contour d'un pixel (dans la forme si inner, sinon autour)."""
        er = ndimage.binary_erosion(mask) if inner else mask
        dl = mask if inner else ndimage.binary_dilation(mask)
        edge = dl & ~er
        self.flat(edge, col)

    def bevel(self, mask, r, curve=1.0):
        """Relief arrondi : hauteur croissante depuis le bord jusqu'à r pixels."""
        d = ndimage.distance_transform_edt(mask)
        t = np.clip(d / r, 0, 1)
        return np.sqrt(1 - (1 - t) ** 2) * r * curve

    def text(self, x, y, s, col, a=255):
        for ch in s:
            g = FONT.get(ch.upper(), FONT[" "])
            for k, bit in enumerate(g):
                if bit == "1":
                    xx, yy = x + k % 3, y + k // 3
                    if 0 <= xx < self.w and 0 <= yy < self.h:
                        self.px[yy, xx, :3] = col; self.px[yy, xx, 3] = a
            x += 4

    def put(self, x, y, col, a=255):
        x, y = int(round(x)), int(round(y))
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[y, x, :3] = col; self.px[y, x, 3] = a

    def line(self, x0, y0, x1, y1, col, a=255):
        n = int(max(abs(x1 - x0), abs(y1 - y0))) + 1
        for t in np.linspace(0, 1, n):
            self.put(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, col, a)

    def save(self, name):
        Image.fromarray(self.px, "RGBA").save(os.path.join(OUT, name))


# ================================================================ planche de bord (480 × 100)
GAUGES = {"speed": (209, 39, 19), "rpm": (271, 39, 19), "fuel": (240, 29, 8), "temp": (240, 50, 8)}
LCD = (343, 57, 26, 7)            # écran de l'autoradio (x, y, l, h) : heure en jeu
LAMPS = [(196, 60), (204, 60), (276, 60), (284, 60)]   # voyants (phares, clignotants…)
GEAR = (352, 91)                  # « P R N D » du sélecteur


def dash():
    c = Canvas(W, 100)
    g = Canvas(W, 100)            # lumières de nuit
    top_y = 13 + 3 * ((c.xx - 240) / 240) ** 2           # pied du pare-brise
    edge_y = 29 + 4 * ((c.xx - 240) / 240) ** 2          # arête avant de la planche
    # face avant de la planche (verticale, sombre, légèrement bombée) + grain du plastique
    face = c.yy >= edge_y
    h = -((c.yy - edge_y) / 70.0) ** 2 * 26 + 2 * np.sin(c.xx / 37.0)
    c.shade(face, h, "dash", amb=0.18, bias=-0.06, grain=0.025)
    # dessus de la planche (presque horizontal : éclairé par le ciel)
    topm = (c.yy >= top_y) & (c.yy < edge_y)
    ht = -(c.yy - top_y) * 0.6
    c.shade(topm, ht, "dash", amb=0.5, bias=0.1, grain=0.02)
    # grille de dégivrage le long du pare-brise
    for x in range(64, 418, 3):
        y = int(round(13 + 3 * ((x - 240) / 240) ** 2)) + 2
        c.flat(c.rect(x, y, x + 2, y + 2), RAMP["dash"][0])
    # arête avant arrondie : liseré clair puis ombre
    lip = (c.yy >= edge_y - 1) & (c.yy < edge_y + 1)
    c.fill(lip, 0.75 - 0.4 * (c.yy >= edge_y), "dash")
    c.flat((c.yy >= edge_y + 1) & (c.yy < edge_y + 3), RAMP["dash"][0])
    # vignette auto et contrôle technique dans le coin du pare-brise (passager)
    c.flat(c.rect(432, 3, 440, 11), (205, 205, 196)); c.flat(c.rect(433, 4, 439, 10), (40, 120, 170))
    c.text(434, 5, "8", (230, 220, 90))
    c.flat(c.rect(442, 4, 448, 10), (220, 220, 210)); c.flat(c.rect(443, 5, 447, 9), (60, 150, 70))

    # ---------------------------------------------------------------- capot des compteurs
    hood = c.rrect(162, 0, 318, 40, 9)
    c.shade(hood, c.bevel(hood, 7), "dash", amb=0.28, bias=0.02, grain=0.03, scale=1.2)
    c.outline(hood, RAMP["dash"][0])
    seam = c.rrect(165, 3, 315, 40, 7) & ~c.rrect(166, 4, 314, 40, 6) & (((c.xx + c.yy).astype(int) % 3) == 0) & (c.yy < 30)
    c.flat(seam, RAMP["dash"][6])
    recess = c.rrect(172, 12, 308, 66, 6)
    # creux : ombre portée par la visière en haut, plus clair vers le bas
    v = 0.05 + 0.22 * np.clip((c.yy - 12) / 50.0, 0, 1)
    c.fill(recess, v, "dash")
    c.outline(recess, RAMP["dash"][0])
    c.flat(c.rect(176, 66, 304, 67) & ~recess, RAMP["dash"][4])
    # compteurs : lunette chromée, fond noir mat, graduations
    for name, (cx, cy, r) in GAUGES.items():
        ring = c.disc(cx, cy, r + 1.5) & ~c.disc(cx, cy, r - 0.5)
        hgt = np.cos(np.clip((np.hypot(c.xx + 0.5 - cx, c.yy + 0.5 - cy) - r) / 2.0, -1.5, 1.5)) * 3
        c.shade(ring, hgt, "chrome", amb=0.35, bias=-0.05, scale=2.0)
        fc = c.disc(cx, cy, r - 0.5)
        c.fill(fc, 0.35 + 0.4 * np.clip((cy - c.yy) / r, 0, 1) * 0.5, "face")
        # éclat de lumière sur la lunette (en haut à gauche) et ombre de la visière sur le haut du cadran
        c.glint(cx - r * 0.62, cy - r * 0.72, RAMP["chrome"][9], 2 if r > 10 else 1)
        c.ao(fc, ~c.rect(0, int(cy - r * 0.35), W, 100), reach=r * 0.6, strength=0.5)
    def ticks(cx, cy, r, a0, a1, n, major, labels):
        for k in range(n + 1):
            a = math.radians(a0 + (a1 - a0) * k / n)
            big = k % major == 0
            r0 = r - (5 if big else 3.5)
            col = (235, 235, 228) if big else (150, 150, 145)
            for cv, cl in ((c, col), (g, (255, 150, 60) if big else (200, 110, 45))):
                cv.line(cx + math.sin(a) * r0, cy - math.cos(a) * r0, cx + math.sin(a) * (r - 1.5), cy - math.cos(a) * (r - 1.5), cl)
        for k, s in labels:
            a = math.radians(a0 + (a1 - a0) * k / n)
            x = cx + math.sin(a) * (r - 9.5) - (len(s) * 4 - 1) / 2; y = cy - math.cos(a) * (r - 9.5) - 2.5
            for cv, cl in ((c, (220, 220, 214)), (g, (255, 170, 80))):
                cv.text(int(round(x)), int(round(y)), s, cl)
    sx, sy, sr = GAUGES["speed"]
    ticks(sx, sy, sr, -125, 125, 20, 4, [(8, "80"), (16, "160")])
    c.text(sx - 5, sy + 7, "KM/H", (120, 120, 115)); g.text(sx - 5, sy + 7, "KM/H", (170, 95, 40))
    rx, ry, rr = GAUGES["rpm"]
    ticks(rx, ry, rr, -125, 125, 14, 2, [(4, "2"), (8, "4"), (12, "6")])
    for k in range(11, 15):                                  # zone rouge
        a = math.radians(-125 + 250 * k / 14)
        for t in np.linspace(rr - 3.5, rr - 1.5, 3):
            c.put(rx + math.sin(a) * t, ry - math.cos(a) * t, (200, 30, 25)); g.put(rx + math.sin(a) * t, ry - math.cos(a) * t, (255, 40, 30))
    for name in ("fuel", "temp"):
        cx, cy, r = GAUGES[name]
        for a in (-60, 0, 60):
            aa = math.radians(a)
            for cv, cl in ((c, (200, 200, 195)), (g, (255, 150, 60))):
                cv.line(cx + math.sin(aa) * (r - 3), cy - math.cos(aa) * (r - 3), cx + math.sin(aa) * (r - 1), cy - math.cos(aa) * (r - 1), cl)
        c.put(cx + math.sin(math.radians(60)) * (r - 2), cy - math.cos(math.radians(60)) * (r - 2), (200, 40, 30))
    # voyants éteints
    for (x, y) in LAMPS:
        c.flat(c.rect(x - 2, y - 2, x + 3, y + 2), RAMP["face"][1])
    # ---------------------------------------------------------------- aérateurs
    def vent(x0, y0, x1, y1):
        fr = c.rrect(x0, y0, x1, y1, 2)
        c.shade(fr, c.bevel(fr, 2), "dash", amb=0.3, bias=0.06, scale=1.5)
        inner = c.rect(x0 + 2, y0 + 2, x1 - 2, y1 - 2)
        c.flat(inner, RAMP["dash"][0])
        for y in range(y0 + 3, y1 - 2, 2):
            c.fill(c.rect(x0 + 2, y, x1 - 2, y + 1), 0.42, "dash")
        c.flat(c.rect((x0 + x1) // 2 - 1, y0 + 2, (x0 + x1) // 2 + 1, y1 - 2), RAMP["dash"][3])
    vent(96, 38, 132, 54); vent(326, 36, 352, 52); vent(356, 36, 382, 52); vent(436, 38, 470, 54)
    # ---------------------------------------------------------------- autoradio K7 + chauffage + sélecteur
    rad = c.rect(326, 55, 384, 75)
    c.shade(rad, c.bevel(rad, 2), "dash", amb=0.2, bias=-0.04, scale=1.2)
    c.outline(rad, RAMP["dash"][0])
    lx, ly, lw, lh = LCD
    c.flat(c.rect(lx, ly, lx + lw, ly + lh), (12, 26, 18))
    g.flat(c.rect(lx, ly, lx + lw, ly + lh), (20, 60, 35))
    c.flat(c.rect(330, 66, 380, 68), RAMP["dash"][0])                     # fente de la cassette
    c.flat(c.rect(330, 68, 380, 69), RAMP["dash"][4])
    for x in (333, 371):                                                # boutons rotatifs
        k = c.disc(x + 2.5, 61, 3.2)
        c.shade(k, c.bevel(k, 3), "chrome", amb=0.25, scale=1.3)
    for i in range(6):                                                  # touches de présélection
        b = c.rect(331 + i * 8, 70, 337 + i * 8, 73)
        c.shade(b, c.bevel(b, 1), "dash", amb=0.45, bias=0.1)
    heat = c.rect(326, 77, 384, 89)
    c.shade(heat, c.bevel(heat, 2), "dash", amb=0.25, bias=0.0, scale=1.2)
    c.outline(heat, RAMP["dash"][0])
    for i, kx in enumerate((340, 356, 369)):
        c.flat(c.rect(330, 79 + i * 3, 380, 80 + i * 3), RAMP["dash"][0])
        kn = c.rect(kx - 2, 78 + i * 3, kx + 2, 81 + i * 3)
        c.shade(kn, c.bevel(kn, 1), "chrome", amb=0.3)
    c.flat(c.rect(330, 79, 334, 80), (40, 70, 160)); c.flat(c.rect(376, 79, 380, 80), (170, 40, 30))
    cons = c.rect(330, 89, 382, 100)
    c.shade(cons, c.bevel(cons, 3) + 0 * c.xx, "dash", amb=0.2, bias=-0.03, grain=0.03)
    gx0, gy0 = GEAR
    c.flat(c.rect(gx0 - 2, gy0 - 2, gx0 + 31, gy0 + 7), RAMP["dash"][0])
    for i, ch in enumerate("PRND"):
        c.text(gx0 + i * 8, gy0, ch, (130, 130, 125))
    # haut-parleurs sur le dessus de la planche (grilles percées)
    for (x0, x1) in ((66, 122), (358, 414)):
        hp = c.rrect(x0, 17, x1, 26, 3)
        c.shade(hp, c.bevel(hp, 2), "dash", amb=0.3, bias=-0.06, scale=1.2)
        dots = hp & (c.xx.astype(int) % 2 == 0) & (c.yy.astype(int) % 2 == 1) & ndimage.binary_erosion(hp, iterations=2)
        c.flat(dots, RAMP["dash"][0])
        c.outline(hp, RAMP["dash"][1])
    # baguette alu brossé le long de la face de la planche
    for (x0, x1) in ((34, 160), (320, 396)):
        bg_ = c.rect(x0, 0, x1, 100) & (c.yy >= edge_y + 9) & (c.yy < edge_y + 11)
        c.fill(bg_, 0.55 + 0.25 * (c.yy < edge_y + 10) + 0.08 * np.sin(c.xx * 0.9), "chrome")
    # interrupteurs à bascule (antibrouillards, dégivrage, plafonnier) avec pictos
    for i, col in enumerate(((240, 200, 40), (240, 140, 30), (120, 200, 255))):
        x0 = 138 + i * 8
        sw = c.rrect(x0, 46, x0 + 6, 58, 1)
        c.shade(sw, c.bevel(sw, 1.5) + (c.yy < 52) * 1.0, "dash", amb=0.35, bias=0.06, scale=1.3)
        c.outline(sw, RAMP["dash"][0])
        c.put(x0 + 3, 49, col); c.put(x0 + 2, 49, tuple(int(v * 0.6) for v in col))
        g.put(x0 + 3, 49, col)
    # bouton des feux de détresse (triangle rouge) au-dessus des aérateurs centraux
    hz = c.rrect(348, 29, 360, 35, 1)
    c.shade(hz, c.bevel(hz, 1.5), "red", amb=0.35, scale=1.3)
    c.outline(hz, RAMP["red"][0])
    for k in range(4):
        c.put(354 - k * 0.5, 30.5 + k, (255, 220, 200)); c.put(354 + k * 0.5, 30.5 + k, (255, 220, 200))
    # allume-cigare (bague chromée) sur la console
    lg = c.disc(339.5, 94.5, 3.2) & ~c.disc(339.5, 94.5, 1.8)
    c.shade(lg, c.bevel(lg, 1.5), "chrome", amb=0.3, scale=1.4)
    c.flat(c.disc(339.5, 94.5, 1.8), RAMP["dash"][0])
    # ---------------------------------------------------------------- côté passager : boîte à gants, inscription
    gb = c.rrect(398, 58, 474, 92, 3)
    c.shade(gb, c.bevel(gb, 3) * 0.6 - ((c.yy - 58) / 34.0) ** 2 * 6, "dash", amb=0.2, bias=-0.02, grain=0.04, scale=1.3)
    c.outline(gb, RAMP["dash"][0])
    lk = c.rect(432, 61, 440, 65)
    c.shade(lk, c.bevel(lk, 1.5), "chrome", amb=0.35)
    c.text(402, 33, "ESPACE", (95, 96, 102))
    # ---------------------------------------------------------------- portières (garnitures)
    for (x0, x1, sgn) in ((0, 30, 1), (456, 480, -1)):
        dm = c.rect(x0, 0, x1, 100) & (c.yy > 6 + ((c.xx - x0) if sgn > 0 else (x1 - c.xx)) * 0.5)
        hd = c.bevel(dm, 6) + (100 - c.yy) * 0.05
        c.shade(dm, hd, "door", amb=0.22, bias=-0.04, grain=0.04)
        c.outline(dm, RAMP["door"][0])
    for (x0, x1) in ((6, 24), (462, 476)):
        hd = c.rrect(x0, 44, x1, 52, 3)
        c.shade(hd, c.bevel(hd, 2), "chrome", amb=0.25, bias=-0.1, scale=1.3)
        c.flat(c.rect(x0 + 3, 47, x1 - 3, 49), RAMP["dash"][0])
    # bouton de verrouillage
    k = c.rect(18, 22, 21, 26); c.shade(k, c.bevel(k, 1), "chrome", amb=0.4)
    # ombres douces : la planche s'assombrit autour des éléments en relief
    raised = (c.rrect(162, 0, 318, 40, 9) | c.rect(326, 55, 384, 75) | c.rect(326, 77, 384, 89) | c.rrect(398, 58, 474, 92, 3))
    c.ao(face & ~raised, raised, reach=3.5, strength=0.35)
    c.save("dash.png"); g.save("glow.png")
    # verre des compteurs : reflets en diagonale, posés par-dessus les aiguilles
    gl = Canvas(W, 100)
    for name, (cx, cy, r) in GAUGES.items():
        fc = gl.disc(cx, cy, r - 0.5)
        u = (gl.xx - cx) + (gl.yy - cy) * 0.7
        streak = fc & (((u > -r * 0.55) & (u < -r * 0.35)) | ((u > -r * 0.2) & (u < -r * 0.12)))
        streak &= (gl.yy < cy)
        gl.flat(streak, (200, 215, 235), 46)
        gl.put(cx - r * 0.45, cy - r * 0.55, (255, 255, 255), 150)
    gl.save("glass.png")
    return {"gauges": GAUGES, "lcd": LCD, "lamps": LAMPS, "gear": GEAR}


# ================================================================ pavillon, pare-soleil, rétroviseur (480 × 40)
MIRROR = (284, 15, 52, 15)           # glace (x, y, l, h) : le conducteur est à gauche, le rétro apparaît à droite du centre


def top():
    c = Canvas(W, 40)
    ly = 9 + 6 * ((c.xx - 240) / 240) ** 2
    lin = c.yy < ly
    c.shade(lin, -(c.yy) * 0.8 + 1.5 * np.sin(c.xx / 9.0) * 0, "liner", amb=0.25, bias=-0.1, grain=0.03)
    perf = lin & (c.xx.astype(int) % 3 == 1) & (c.yy.astype(int) % 3 == 1) & (c.yy < ly - 2)
    c.px[perf, :3] = (c.px[perf, :3] * 0.82).astype(np.uint8)
    c.flat((c.yy >= ly - 1) & (c.yy < ly), RAMP["liner"][0])
    # bande teintée bleu-vert en haut du pare-brise (années 80), tramée vers le bas
    band = (c.yy >= ly + 1.5) & (c.yy < ly + 16)
    tt = np.clip((c.yy - ly - 1.5) / 14.5, 0, 1)
    keep = band & (tt < 1.0 - BAYER[(c.yy.astype(int) % 4), (c.xx.astype(int) % 4)] * 0.9)
    c.px[keep, 0] = 40; c.px[keep, 1] = 110; c.px[keep, 2] = 120
    c.px[keep, 3] = (np.clip(110 - tt[keep] * 70, 30, 255)).astype(np.uint8)
    # baguette noire en haut du pare-brise
    c.flat((c.yy >= ly) & (c.yy < ly + 1.5), RAMP["dash"][1])
    # plafonnier
    dl = c.rrect(230, 1, 250, 7, 2)
    c.shade(dl, c.bevel(dl, 2), "liner", amb=0.6, bias=0.2)
    c.outline(dl, RAMP["liner"][1])
    c.flat(c.rect(233, 3, 247, 5), RAMP["liner"][8]); c.glint(236, 3, (255, 255, 245))
    # pare-soleil relevés (conducteur plus près, donc plus grand)
    for (x0, y0, x1, y1, r) in ((36, 6, 196, 27, 5), (292, 7, 440, 23, 4)):
        v = c.rrect(x0, y0, x1, y1, r)
        c.shade(v, c.bevel(v, 4) + (c.yy - y0) * 0.3, "liner", amb=0.3, bias=-0.02, grain=0.03, scale=1.2)
        c.outline(v, RAMP["liner"][1])
        # couture
        st = c.rrect(x0 + 3, y0 + 3, x1 - 3, y1 - 3, max(1, r - 2)) & ~c.rrect(x0 + 4, y0 + 4, x1 - 4, y1 - 4, max(1, r - 3))
        st &= ((c.xx + c.yy) % 3 != 0)
        c.flat(st, RAMP["liner"][2])
        # charnière
        hb = c.rect(x1 - 14 if x0 < 200 else x0 + 6, y0 - 4, (x1 - 6) if x0 < 200 else x0 + 14, y0 + 2)
        c.shade(hb, c.bevel(hb, 1.5), "dash", amb=0.4)
    # rétroviseur intérieur : pied, coque noire, glace transparente
    mx, my, mw, mh = MIRROR
    sx = mx + mw // 2
    c.flat(c.rect(sx - 3, 6, sx + 3, 13), RAMP["dash"][2]); c.flat(c.rect(sx - 2, 6, sx - 1, 13), RAMP["dash"][4])
    shell = c.rrect(mx - 4, my - 3, mx + mw + 4, my + mh + 3, 4)
    c.shade(shell, c.bevel(shell, 3), "rubber", amb=0.3, bias=0.08, scale=1.4)
    c.outline(shell, RAMP["rubber"][0])
    glass = c.rect(mx, my, mx + mw, my + mh)
    c.px[glass] = 0
    c.flat(c.rect(mx, my, mx + mw, my + 1), RAMP["rubber"][0])
    c.save("top.png")
    return {"mirror": MIRROR}


# ================================================================ volant (160 × 160, centre au milieu)
WR, WT = 74, 8


def wheel():
    c = Canvas(160, 160)
    cx = cy = 80
    d = np.hypot(c.xx + 0.5 - cx, c.yy + 0.5 - cy)
    rim = (d <= WR) & (d >= WR - WT)
    # jante en tore : hauteur en demi-cercle dans l'épaisseur
    t = np.clip((d - (WR - WT / 2)) / (WT / 2), -1, 1)
    hr = np.sqrt(1 - t ** 2) * WT / 2
    # branches (Espace I phase 2 : deux branches larges, légèrement plongeantes) et moyeu rembourré
    sp = np.zeros_like(rim)
    for sgn in (-1, 1):
        sp |= c.poly([(cx + sgn * 20, cy - 6), (cx + sgn * (WR - 3), cy + 4), (cx + sgn * (WR - 3), cy + 15), (cx + sgn * 20, cy + 16)])
    hub = c.rrect(cx - 28, cy - 20, cx + 28, cy + 24, 10)
    body = (sp | hub) & (d < WR - 2)
    hb = c.bevel(body, 5)
    c.shade(body & ~rim, hb, "rubber", amb=0.25, bias=0.05, grain=0.02, scale=1.1)
    c.outline(body & ~rim, RAMP["rubber"][0])
    ang = np.degrees(np.arctan2(c.yy + 0.5 - cy, c.xx + 0.5 - cx))
    grips = rim | (((np.abs(ang) < 14) | (np.abs(ang) > 166)) & (d <= WR + 1) & (d >= WR - WT - 1))
    t2 = np.clip((d - (WR - WT / 2)) / (WT / 2 + 1), -1, 1)
    hr2 = np.sqrt(1 - t2 ** 2) * WT / 2
    c.shade(grips, hr2, "rubber", amb=0.22, bias=0.06, spec=0.9, grain=0.03, scale=1.0)
    c.outline(grips, RAMP["rubber"][0])
    # couture intérieure du cuir et reflet du ciel sur le haut de la jante
    stitch = (np.abs(d - (WR - WT + 1.5)) < 0.5) & ((np.round(ang).astype(int) % 4) == 0)
    c.flat(stitch, RAMP["rubber"][6])
    shine = (np.abs(d - (WR - 2.5)) < 0.7) & (ang < -110) & (ang > -160)
    c.flat(shine, RAMP["rubber"][9])
    # rembourrage du moyeu : deux nervures horizontales
    for yy in (cy - 12, cy + 15):
        c.flat(c.rect(cx - 22, yy, cx + 22, yy + 1) & hub, RAMP["rubber"][1])
        c.flat(c.rect(cx - 22, yy + 1, cx + 22, yy + 2) & hub, RAMP["rubber"][5])
    # ovale « Fjord » (parodie de l'ovale Ford) : bleu nuit cerclé de chrome, signature blanche ondulée
    ex, ey = (c.xx + 0.5 - cx) / 11.0, (c.yy + 0.5 - cy) / 6.5
    oval = ex ** 2 + ey ** 2 <= 1.0
    inner = ((c.xx + 0.5 - cx) / 9.5) ** 2 + ((c.yy + 0.5 - cy) / 5.0) ** 2 <= 1.0
    c.shade(oval & ~inner, c.bevel(oval & ~inner, 1.2), "chrome", amb=0.45, scale=1.5)
    c.flat(inner, (22, 48, 120))
    c.flat(inner & (c.yy < cy - 2), (40, 76, 160))                # reflet du haut
    wave = inner & (np.abs(c.yy + 0.5 - (cy + 1.6 * np.sin((c.xx - cx) * 0.75))) < 0.75) & (np.abs(c.xx - cx) <= 6)
    c.flat(wave, (235, 238, 245))
    c.save("wheel.png")
    return {"wheel_r": WR, "wheel_t": WT}


def hand(mirror):
    """Main qui empoigne la jante (vue du conducteur : dos de la main, doigts repliés sur la jante)."""
    c = Canvas(22, 20)
    m = c.rrect(3, 3, 19, 17, 6)
    m |= c.rrect(1, 7, 7, 15, 3)                             # pouce
    h = c.bevel(m, 4)
    c.shade(m, h, "skin", amb=0.3, bias=0.0, grain=0.02, scale=1.1)
    c.outline(m, RAMP["skin"][0])
    for y in (7, 10, 13):                                    # plis des doigts
        c.flat(c.rect(9, y, 17, y + 1), RAMP["skin"][2])
    c.flat(c.rect(8, 15, 18, 16), RAMP["skin"][1])
    img = c.px[:, ::-1] if mirror else c.px
    Image.fromarray(np.ascontiguousarray(img), "RGBA").save(os.path.join(OUT, "hand_r.png" if mirror else "hand_l.png"))


def strip(name, ramp, w=16, h=8, amb=0.25):
    """Texture d'ombrage transversal (montants de pare-brise, manches) : cylindre éclairé de côté."""
    c = Canvas(w, h)
    t = (c.xx + 0.5) / w * 2 - 1
    c.shade(np.ones((h, w), bool), np.sqrt(np.clip(1 - t ** 2, 0, 1)) * w * 0.5, ramp, amb=amb, grain=0.01)
    c.save(name)


def pine():
    c = Canvas(11, 18)
    m = c.poly([(5.5, 0), (9, 5), (7, 5), (10.5, 10), (7.5, 10), (11, 16), (0, 16), (3.5, 10), (0.5, 10), (4, 5), (2, 5)])
    c.shade(m, c.bevel(m, 2), "pine", amb=0.35, scale=1.3)
    c.outline(m, RAMP["pine"][0])
    c.flat(c.rect(5, 16, 6, 18), (110, 80, 50))
    c.save("pine.png")


def preview(shot):
    """Aperçu : capture du jeu ramenée à 480 px de large + calques du cockpit, agrandi ×3."""
    bg = Image.open(shot).convert("RGBA")
    H = int(round(bg.height * W / bg.width))
    bg = bg.resize((W, H), Image.LANCZOS)
    def lay(name, x, y, rot=0.0):
        im = Image.open(os.path.join(OUT, name))
        if rot:
            im = im.rotate(rot, resample=Image.NEAREST)
        bg.alpha_composite(im, (int(x), int(y)))
    lay("top.png", 0, 0)
    lay("dash.png", 0, H - 100)
    lay("wheel.png", 240 - 80, H - 100 + 80 - 80, rot=12)
    out = bg.resize((W * 3, H * 3), Image.NEAREST)
    out.save("data/cockpit_apercu.png")


def main():
    os.makedirs(OUT, exist_ok=True)
    meta = {}
    meta.update(dash()); meta.update(top()); meta.update(wheel())
    strip("pillar.png", "pillar", 16, 8, amb=0.2)
    pine()
    json.dump(meta, open(os.path.join(OUT, "meta.json"), "w"))
    if len(sys.argv) > 1:
        preview(sys.argv[1])
    print("cockpit :", sorted(os.listdir(OUT)))


if __name__ == "__main__":
    main()
