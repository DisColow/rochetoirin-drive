"""Vue cockpit du Ford Ranger Raptor (v6.43, #133 ; avant : Espace I) en pixel art, à la manière des vieux jeux de voitures (Test Drive, Vette!, Lotus) :
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
    # Raptor : intérieur noir, accents « Code Orange », écrans
    "black": hexes("#040406", "#08080c", "#0d0d12", "#131319", "#1a1a21", "#22222a", "#2c2c35", "#383842", "#46454f", "#57555d"),
    "orange": hexes("#3a1204", "#5c1e06", "#86300a", "#b0430d", "#d65a12", "#f0761d", "#ff9640", "#ffb871"),
    "magnesium": hexes("#26272c", "#3a3b42", "#50525a", "#686a73", "#82848c", "#9c9ea5", "#b6b8be", "#d0d1d5"),
    "screen": hexes("#02040a", "#050a16", "#091224", "#0e1c34", "#152847", "#1e365c"),
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
    "O": "111101101101111", "B": "110101110101110", "G": "111100101101111", "I": "111010010010111",
    "U": "101101101101111", "W": "101101111111101", "X": "101101010101101", "Y": "101101010010010",
    ":": "000010000010000",
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
# Ford Ranger Raptor (2023) : combiné numérique 12,4" derrière le volant (compteurs virtuels), écran central vertical
# 12", aérateurs verticaux, commandes de climatisation sous l'écran, sélecteur électronique et molette des modes de
# conduite sur la console ; liseré orange « Code Orange » sur la planche, inscription RAPTOR côté passager.
GAUGES = {"speed": (209, 39, 19), "rpm": (271, 39, 19), "fuel": (240, 29, 8), "temp": (240, 50, 8)}
SCR = (313, 21, 50, 58)           # écran central (x, y, l, h)
LCD = (316, 23, 30, 7)            # barre d'état de l'écran : heure en jeu
LAMPS = [(190, 63), (198, 63), (282, 63), (290, 63)]   # voyants (phares, clignotants…) en bas du combiné
GEAR = (322, 92)                  # « P R N D » à côté du sélecteur


def dash():
    c = Canvas(W, 100)
    g = Canvas(W, 100)            # lumières de nuit
    top_y = 13 + 3 * ((c.xx - 240) / 240) ** 2           # pied du pare-brise
    edge_y = 27 + 4 * ((c.xx - 240) / 240) ** 2          # arête avant de la planche
    # face avant (noire, bombée) + grain du plastique moussé
    face = c.yy >= edge_y
    h = -((c.yy - edge_y) / 70.0) ** 2 * 26 + 2 * np.sin(c.xx / 41.0)
    c.shade(face, h, "black", amb=0.22, bias=-0.02, grain=0.022)
    # dessus de la planche (éclairé par le ciel), surpiqûre orange le long de l'arête
    topm = (c.yy >= top_y) & (c.yy < edge_y)
    c.shade(topm, -(c.yy - top_y) * 0.6, "black", amb=0.5, bias=0.12, grain=0.02)
    for x in range(64, 418, 3):
        y = int(round(13 + 3 * ((x - 240) / 240) ** 2)) + 2
        c.flat(c.rect(x, y, x + 2, y + 2), RAMP["black"][0])
    lip = (c.yy >= edge_y - 1) & (c.yy < edge_y + 1)
    c.fill(lip, 0.72 - 0.4 * (c.yy >= edge_y), "black")
    c.flat((c.yy >= edge_y + 1) & (c.yy < edge_y + 3), RAMP["black"][0])
    st = (np.abs(c.yy - (edge_y - 2.5)) < 0.5) & ((c.xx.astype(int) % 3) != 0) & ((c.xx < 160) | (c.xx > 322))
    c.flat(st, RAMP["orange"][4])
    # liseré « Code Orange » sur la face de la planche (côté conducteur et passager)
    for (x0, x1) in ((34, 158), (372, 456)):
        band = c.rect(x0, 0, x1, 100) & (c.yy >= edge_y + 9) & (c.yy < edge_y + 12)
        c.fill(band, 0.45 + 0.3 * (c.yy < edge_y + 10) + 0.05 * np.sin(c.xx * 0.7), "orange")
        c.flat(c.rect(x0, 0, x1, 100) & (c.yy >= edge_y + 12) & (c.yy < edge_y + 13), RAMP["black"][0])
        g.flat(band, (255, 120, 40), 140)                  # éclairage d'ambiance de nuit
    # vignette du contrôle technique dans le coin du pare-brise (passager)
    c.flat(c.rect(432, 3, 440, 11), (205, 205, 196)); c.flat(c.rect(433, 4, 439, 10), (40, 120, 170))
    c.text(434, 5, "8", (230, 220, 90))

    # ---------------------------------------------------------------- casquette et combiné numérique
    hood = c.rrect(166, 2, 314, 30, 8)
    c.shade(hood, c.bevel(hood, 6), "black", amb=0.3, bias=0.04, grain=0.03, scale=1.2)
    c.outline(hood, RAMP["black"][0])
    stitch = c.rrect(169, 5, 311, 30, 6) & ~c.rrect(170, 6, 310, 30, 5) & (((c.xx + c.yy).astype(int) % 3) == 0) & (c.yy < 24)
    c.flat(stitch, RAMP["orange"][5])
    bez = c.rrect(172, 12, 308, 70, 5)                                 # cadre noir laqué
    c.shade(bez, c.bevel(bez, 3), "black", amb=0.35, bias=0.08, spec=0.6, scale=1.4)
    scr = c.rrect(175, 15, 305, 67, 3)                                 # dalle : noir bleuté, plus sombre en haut
    c.fill(scr, 0.08 + 0.35 * np.clip((c.yy - 15) / 52.0, 0, 1), "screen")
    g.flat(scr, (8, 14, 28), 255)
    # compteurs virtuels : anneau orange en arc, graduations blanches, fond dégradé
    for name, (cx, cy, r) in GAUGES.items():
        dd = np.hypot(c.xx + 0.5 - cx, c.yy + 0.5 - cy)
        ang = np.degrees(np.arctan2(c.xx + 0.5 - cx, -(c.yy + 0.5 - cy)))
        arc = (np.abs(dd - r) < (1.0 if r > 10 else 0.7)) & (np.abs(ang) <= 125)
        for cv in (c, g):
            cv.flat(arc, RAMP["orange"][5] if cv is c else (255, 130, 40))
        inner = (np.abs(dd - (r - 2.2)) < 0.5) & (np.abs(ang) <= 125)
        c.flat(inner, RAMP["screen"][5]); g.flat(inner, (40, 70, 120))
        c.fill(dd < r - 3, 0.25 + 0.3 * np.clip((cy - c.yy) / r, 0, 1), "screen")
    def ticks(cx, cy, r, a0, a1, n, major, labels):
        for k in range(n + 1):
            a = math.radians(a0 + (a1 - a0) * k / n)
            big = k % major == 0
            r0 = r - (5 if big else 3.5)
            col = (235, 238, 245) if big else (120, 140, 170)
            for cv, cl in ((c, col), (g, (230, 236, 255) if big else (110, 140, 200))):
                cv.line(cx + math.sin(a) * r0, cy - math.cos(a) * r0, cx + math.sin(a) * (r - 2.5), cy - math.cos(a) * (r - 2.5), cl)
        for k, txt in labels:
            a = math.radians(a0 + (a1 - a0) * k / n)
            x = cx + math.sin(a) * (r - 9.5) - (len(txt) * 4 - 1) / 2; y = cy - math.cos(a) * (r - 9.5) - 2.5
            for cv, cl in ((c, (215, 222, 235)), (g, (220, 230, 255))):
                cv.text(int(round(x)), int(round(y)), txt, cl)
    sx, sy, sr = GAUGES["speed"]
    ticks(sx, sy, sr, -125, 125, 20, 4, [(8, "80"), (16, "160")])
    c.text(sx - 5, sy + 7, "KM/H", (110, 130, 160)); g.text(sx - 5, sy + 7, "KM/H", (110, 140, 200))
    rx, ry, rr = GAUGES["rpm"]
    ticks(rx, ry, rr, -125, 125, 14, 2, [(4, "2"), (8, "4"), (12, "6")])
    for k in range(10, 15):                                  # zone rouge
        a = math.radians(-125 + 250 * k / 14)
        for t in np.linspace(rr - 3.5, rr - 1.5, 3):
            c.put(rx + math.sin(a) * t, ry - math.cos(a) * t, (220, 40, 30)); g.put(rx + math.sin(a) * t, ry - math.cos(a) * t, (255, 50, 35))
    for name in ("fuel", "temp"):
        cx, cy, r = GAUGES[name]
        for a in (-60, 0, 60):
            aa = math.radians(a)
            for cv, cl in ((c, (200, 210, 225)), (g, (210, 225, 255))):
                cv.line(cx + math.sin(aa) * (r - 3), cy - math.cos(aa) * (r - 3), cx + math.sin(aa) * (r - 1), cy - math.cos(aa) * (r - 1), cl)
    # logo du mode de conduite (Baja) et pictogramme du pick-up entre les compteurs
    c.text(232, 61, "BAJA", RAMP["orange"][6]); g.text(232, 61, "BAJA", (255, 150, 60))
    for (x, y) in LAMPS:
        c.flat(c.rect(x - 2, y - 2, x + 3, y + 2), RAMP["screen"][1])
    # ---------------------------------------------------------------- aérateurs verticaux (Ranger 2023)
    def vent(x0, y0, x1, y1):
        fr = c.rrect(x0, y0, x1, y1, 2)
        c.shade(fr, c.bevel(fr, 2), "black", amb=0.3, bias=0.08, scale=1.5)
        c.outline(fr, RAMP["black"][0])
        inner = c.rect(x0 + 2, y0 + 2, x1 - 2, y1 - 2)
        c.flat(inner, RAMP["black"][0])
        for x in range(x0 + 3, x1 - 2, 2):
            c.fill(c.rect(x, y0 + 2, x + 1, y1 - 2), 0.4, "black")
        c.shade(c.rect(x0 + 2, (y0 + y1) // 2 - 1, x1 - 2, (y0 + y1) // 2 + 1), c.bevel(c.rect(x0 + 2, (y0 + y1) // 2 - 1, x1 - 2, (y0 + y1) // 2 + 1), 1), "magnesium", amb=0.4)
    vent(98, 33, 126, 61); vent(300, 26, 310, 64); vent(366, 26, 376, 64); vent(438, 33, 464, 61)
    # ---------------------------------------------------------------- écran central vertical 12"
    sx0, sy0, sw, sh = SCR
    fr = c.rrect(sx0 - 3, sy0 - 3, sx0 + sw + 3, sy0 + sh + 3, 3)
    c.shade(fr, c.bevel(fr, 2), "black", amb=0.35, bias=0.06, spec=0.7, scale=1.4)
    c.outline(fr, RAMP["black"][0])
    sc = c.rect(sx0, sy0, sx0 + sw, sy0 + sh)
    # carte de navigation : fond sombre, îlots, routes, itinéraire bleu, flèche de position
    mp = Canvas(sw, sh)
    base = (14, 22, 34)
    mp.flat(np.ones((sh, sw), bool), base)
    rr = np.random.default_rng(3)
    for _ in range(9):
        x, y = rr.integers(0, sw), rr.integers(10, sh)
        mp.flat(mp.rrect(x - 6, y - 4, x + 6, y + 4, 2), (22, 34, 30))
    for (a, b) in (((0, 30), (sw, 22)), ((12, 9), (20, sh)), ((0, 46), (sw, 50)), ((34, 9), (30, sh)), ((0, 16), (sw, 38))):
        mp.line(a[0], a[1], b[0], b[1], (70, 80, 96))
    mp.line(20, sh - 10, 20, 30, (60, 150, 255)); mp.line(20, 30, sw, 22, (60, 150, 255))
    mp.line(21, sh - 10, 21, 30, (60, 150, 255))
    for k, (dx, dy) in enumerate(((0, 0), (-1, 1), (1, 1), (-2, 2), (2, 2), (0, 1))):
        mp.put(20 + dx, sh - 12 + dy, (255, 255, 255))
    mp.flat(mp.rect(0, 0, sw, 9), (6, 10, 18))                        # barre d'état (heure)
    mp.flat(mp.rect(0, sh - 6, sw, sh), (10, 14, 24))                 # barre des raccourcis
    for k in range(5):
        mp.flat(mp.rect(3 + k * 10, sh - 4, 7 + k * 10, sh - 2), (90, 110, 140) if k != 2 else RAMP["orange"][5])
    c.px[sy0:sy0 + sh, sx0:sx0 + sw] = mp.px
    g.px[sy0:sy0 + sh, sx0:sx0 + sw] = mp.px                           # l'écran éclaire aussi la nuit
    # commandes de climatisation sous l'écran : rangée de touches + deux bascules de température
    cl = c.rrect(306, 82, 370, 92, 2)
    c.shade(cl, c.bevel(cl, 2), "black", amb=0.3, bias=0.04, scale=1.2)
    c.outline(cl, RAMP["black"][0])
    for k in range(6):
        b = c.rect(318 + k * 7, 84, 323 + k * 7, 90)
        c.shade(b, c.bevel(b, 1), "black", amb=0.5, bias=0.12)
        c.put(320 + k * 7, 86, (230, 230, 235)); g.put(320 + k * 7, 86, (255, 255, 255))
    for x in (309, 361):
        b = c.rrect(x, 83, x + 6, 91, 1)
        c.shade(b, c.bevel(b, 1.5), "black", amb=0.45, bias=0.1)
        c.put(x + 3, 85, (60, 140, 255) if x < 330 else (255, 80, 50)); c.put(x + 3, 89, (60, 140, 255) if x < 330 else (255, 80, 50))
    # console : sélecteur électronique (petit levier) et molette des modes de conduite cerclée d'orange
    cons = c.rect(304, 92, 372, 100)
    c.shade(cons, c.bevel(cons, 2), "black", amb=0.25, bias=-0.02, grain=0.03)
    lev = c.rrect(312, 92, 320, 100, 2)
    c.shade(lev, c.bevel(lev, 3), "black", amb=0.4, bias=0.1, spec=0.6, scale=1.3)
    c.outline(lev, RAMP["black"][0])
    gx0, gy0 = GEAR
    for i, ch in enumerate("PRND"):
        c.text(gx0 + i * 8, gy0, ch, (120, 120, 128))
    kn = c.disc(360.5, 96.5, 4.6)
    ring = kn & ~c.disc(360.5, 96.5, 3.4)
    c.shade(ring, c.bevel(ring, 1), "orange", amb=0.45, scale=1.3)
    c.shade(c.disc(360.5, 96.5, 3.4), c.bevel(c.disc(360.5, 96.5, 3.4), 2.5), "magnesium", amb=0.35, scale=1.4)
    g.flat(ring, (255, 120, 40))
    # bouton des feux de détresse au-dessus de l'écran
    hz = c.rrect(332, 12, 344, 18, 1)
    c.shade(hz, c.bevel(hz, 1.5), "red", amb=0.35, scale=1.3)
    c.outline(hz, RAMP["red"][0])
    for k in range(4):
        c.put(338 - k * 0.5, 13.5 + k, (255, 220, 200)); c.put(338 + k * 0.5, 13.5 + k, (255, 220, 200))
    # côté conducteur : commodo des phares rond à gauche du volant
    lt = c.disc(146.5, 70.5, 6)
    c.shade(lt, c.bevel(lt, 3), "black", amb=0.35, bias=0.06, scale=1.3)
    c.outline(lt, RAMP["black"][0])
    c.flat(c.disc(146.5, 70.5, 1.5), RAMP["magnesium"][5])
    # ---------------------------------------------------------------- côté passager : boîte à gants, RAPTOR
    gb = c.rrect(384, 60, 474, 92, 3)
    c.shade(gb, c.bevel(gb, 3) * 0.6 - ((c.yy - 60) / 32.0) ** 2 * 6, "black", amb=0.22, bias=0.0, grain=0.04, scale=1.3)
    c.outline(gb, RAMP["black"][0])
    gh = c.rect(420, 62, 438, 65)
    c.shade(gh, c.bevel(gh, 1.5), "magnesium", amb=0.35)
    for k, ch in enumerate("RAPTOR"):                                   # lettres en relief (ombre d'un pixel)
        c.text(398 + k * 5, 51, ch, RAMP["black"][0])
        c.text(398 + k * 5, 50, ch, RAMP["black"][9])
    # ---------------------------------------------------------------- portières (garnitures noires, surpiqûres orange)
    for (x0, x1, sgn) in ((0, 30, 1), (456, 480, -1)):
        dm = c.rect(x0, 0, x1, 100) & (c.yy > 6 + ((c.xx - x0) if sgn > 0 else (x1 - c.xx)) * 0.5)
        hd = c.bevel(dm, 6) + (100 - c.yy) * 0.05
        c.shade(dm, hd, "black", amb=0.22, bias=0.0, grain=0.04)
        c.outline(dm, RAMP["black"][0])
        sti = dm & (np.abs(c.yy - 36) < 0.5) & (c.xx.astype(int) % 3 != 0)
        c.flat(sti, RAMP["orange"][4])
    for (x0, x1) in ((6, 24), (462, 476)):
        hd = c.rrect(x0, 44, x1, 52, 3)
        c.shade(hd, c.bevel(hd, 2), "magnesium", amb=0.25, bias=-0.05, scale=1.3)
        c.flat(c.rect(x0 + 3, 47, x1 - 3, 49), RAMP["black"][0])
    raised = (c.rrect(166, 2, 314, 30, 8) | c.rrect(310, 18, 366, 82, 3) | c.rrect(306, 82, 370, 92, 2) | c.rrect(384, 60, 474, 92, 3))
    c.ao(face & ~raised, raised, reach=3.5, strength=0.35)
    c.save("dash.png"); g.save("glow.png")
    # verre du combiné : reflets en diagonale
    gl = Canvas(W, 100)
    sc2 = gl.rrect(175, 15, 305, 67, 3)
    u = gl.xx + gl.yy * 0.8
    streak = sc2 & (((u > 200) & (u < 214)) | ((u > 222) & (u < 226)))
    gl.flat(streak, (200, 215, 235), 30)
    s2 = gl.rect(sx0, sy0, sx0 + sw, sy0 + sh) & (((u > 340) & (u < 350)))
    gl.flat(s2, (200, 215, 235), 26)
    gl.save("glass.png")
    return {"gauges": GAUGES, "lcd": LCD, "lamps": LAMPS, "gear": GEAR}


# ================================================================ pavillon, pare-soleil, rétroviseur (480 × 40)
MIRROR = (284, 15, 52, 15)           # glace (x, y, l, h) : le conducteur est à gauche, le rétro apparaît à droite du centre


def top():
    c = Canvas(W, 40)
    ly = 9 + 6 * ((c.xx - 240) / 240) ** 2
    lin = c.yy < ly
    c.shade(lin, -(c.yy) * 0.8, "black", amb=0.3, bias=0.02, grain=0.03)           # ciel de toit noir (Raptor)
    perf = lin & (c.xx.astype(int) % 3 == 1) & (c.yy.astype(int) % 3 == 1) & (c.yy < ly - 2)
    c.px[perf, :3] = (c.px[perf, :3] * 0.8).astype(np.uint8)
    c.flat((c.yy >= ly - 1) & (c.yy < ly), RAMP["black"][0])
    band = (c.yy >= ly + 1.5) & (c.yy < ly + 12)                                   # pare-brise teinté en haut
    tt = np.clip((c.yy - ly - 1.5) / 10.5, 0, 1)
    keep = band & (tt < 1.0 - BAYER[(c.yy.astype(int) % 4), (c.xx.astype(int) % 4)] * 0.9)
    c.px[keep, 0] = 20; c.px[keep, 1] = 40; c.px[keep, 2] = 60
    c.px[keep, 3] = (np.clip(120 - tt[keep] * 80, 30, 255)).astype(np.uint8)
    c.flat((c.yy >= ly) & (c.yy < ly + 1.5), RAMP["black"][1])
    # console de plafond : 6 interrupteurs auxiliaires (Raptor), liseuses, bouton SOS
    oc = c.rrect(206, 0, 274, 11, 3)
    c.shade(oc, c.bevel(oc, 2), "black", amb=0.4, bias=0.06, spec=0.5, scale=1.3)
    c.outline(oc, RAMP["black"][0])
    for k in range(6):
        sw_ = c.rect(219 + k * 7, 3, 224 + k * 7, 8)
        c.shade(sw_, c.bevel(sw_, 1) + (c.yy < 5) * 0.8, "black", amb=0.5, bias=0.14)
        c.put(221 + k * 7, 4, RAMP["orange"][6])
    for x in (209, 267):
        lm = c.rect(x, 3, x + 5, 8)
        c.shade(lm, c.bevel(lm, 1.5), "liner", amb=0.6, bias=0.2)
    # pare-soleil relevés (noirs)
    for (x0, y0, x1, y1, r) in ((36, 6, 196, 27, 5), (292, 7, 440, 23, 4)):
        v = c.rrect(x0, y0, x1, y1, r)
        c.shade(v, c.bevel(v, 4) + (c.yy - y0) * 0.3, "black", amb=0.35, bias=0.04, grain=0.03, scale=1.2)
        c.outline(v, RAMP["black"][0])
        st_ = c.rrect(x0 + 3, y0 + 3, x1 - 3, y1 - 3, max(1, r - 2)) & ~c.rrect(x0 + 4, y0 + 4, x1 - 4, y1 - 4, max(1, r - 3))
        st_ &= ((c.xx + c.yy) % 3 != 0)
        c.flat(st_, RAMP["black"][6])
        hb = c.rect(x1 - 14 if x0 < 200 else x0 + 6, y0 - 4, (x1 - 6) if x0 < 200 else x0 + 14, y0 + 2)
        c.shade(hb, c.bevel(hb, 1.5), "black", amb=0.45)
    # rétroviseur intérieur sans cadre (bord fin), pied avec capteur de pluie
    mx, my, mw, mh = MIRROR
    sx = mx + mw // 2
    c.flat(c.rect(sx - 4, 5, sx + 4, 13), RAMP["black"][2]); c.flat(c.rect(sx - 3, 6, sx - 2, 13), RAMP["black"][5])
    shell = c.rrect(mx - 2, my - 2, mx + mw + 2, my + mh + 2, 3)
    c.shade(shell, c.bevel(shell, 2), "black", amb=0.35, bias=0.1, spec=0.6, scale=1.4)
    c.outline(shell, RAMP["black"][0])
    glass = c.rect(mx, my, mx + mw, my + mh)
    c.px[glass] = 0
    c.save("top.png")
    return {"mirror": MIRROR}


# ================================================================ volant (160 × 160, centre au milieu)
WR, WT = 74, 9


def wheel():
    """Volant du Raptor : jante épaisse en cuir perforé, repère rouge à midi, surpiqûres orange, trois branches avec
    commandes, coussin de sac gonflable presque carré avec l'ovale Ford, palettes en magnésium derrière."""
    c = Canvas(160, 160)
    cx = cy = 80
    d = np.hypot(c.xx + 0.5 - cx, c.yy + 0.5 - cy)
    ang = np.degrees(np.arctan2(c.yy + 0.5 - cy, c.xx + 0.5 - cx))
    # palettes au volant (magnésium), dépassant derrière la jante à 3 h et 9 h
    for sgn in (-1, 1):
        pd = c.poly([(cx + sgn * 52, cy - 16), (cx + sgn * 70, cy - 22), (cx + sgn * 72, cy - 4), (cx + sgn * 54, cy - 2)])
        c.shade(pd, c.bevel(pd, 2), "magnesium", amb=0.3, spec=0.8, scale=1.3)
        c.outline(pd, RAMP["magnesium"][0])
    # branches : deux horizontales (commandes) et une en bas
    sp = np.zeros_like(d, dtype=bool)
    for sgn in (-1, 1):
        sp |= c.poly([(cx + sgn * 20, cy - 8), (cx + sgn * (WR - 3), cy - 2), (cx + sgn * (WR - 3), cy + 12), (cx + sgn * 20, cy + 14)])
    sp |= c.poly([(cx - 9, cy + 18), (cx + 9, cy + 18), (cx + 6, cy + WR - 3), (cx - 6, cy + WR - 3)])
    hub = c.rrect(cx - 25, cy - 22, cx + 25, cy + 22, 7)
    body = (sp | hub) & (d < WR - 2)
    c.shade(body, c.bevel(body, 5), "black", amb=0.3, bias=0.05, grain=0.02, scale=1.1)
    c.outline(body, RAMP["black"][0])
    # garnitures magnésium sur les branches et touches
    for sgn in (-1, 1):
        tr = c.poly([(cx + sgn * 26, cy + 9), (cx + sgn * (WR - 6), cy + 7), (cx + sgn * (WR - 6), cy + 10), (cx + sgn * 26, cy + 12)])
        c.shade(tr, c.bevel(tr, 1), "magnesium", amb=0.35, spec=0.6)
        for k in range(3):
            bx = cx + sgn * (32 + k * 9)
            b = c.rrect(bx - 3, cy - 4, bx + 3, cy + 3, 1)
            c.shade(b, c.bevel(b, 1.5), "black", amb=0.5, bias=0.12)
            c.put(bx, cy - 1, (220, 220, 225))
    # jante en tore, cuir perforé sur les côtés
    rim = (d <= WR) & (d >= WR - WT)
    t = np.clip((d - (WR - WT / 2)) / (WT / 2), -1, 1)
    hr = np.sqrt(1 - t ** 2) * WT / 2
    c.shade(rim, hr, "black", amb=0.25, bias=0.08, spec=0.9, grain=0.025, scale=1.0)
    perf = rim & (np.abs(np.abs(ang) - 90) > 35) & ((c.xx.astype(int) + c.yy.astype(int) * 2) % 3 == 0) & (np.abs(t) < 0.6)
    c.px[perf, :3] = (c.px[perf, :3] * 0.6).astype(np.uint8)
    c.outline(rim, RAMP["black"][0])
    # repère rouge à midi
    mark = rim & (np.abs(ang + 90) < 4.5)
    c.shade(mark, hr, "red", amb=0.4, scale=1.0)
    # surpiqûres orange de part et d'autre du repère et sur l'intérieur de la jante
    stitch = (np.abs(d - (WR - WT + 1.5)) < 0.5) & ((np.round(ang).astype(int) % 4) == 0)
    c.flat(stitch, RAMP["orange"][5])
    c.flat(rim & (np.abs(np.abs(ang + 90) - 5.5) < 0.6), RAMP["orange"][5])
    shine = (np.abs(d - (WR - 2.5)) < 0.7) & (ang < -110) & (ang > -160)
    c.flat(shine, RAMP["black"][9])
    # coussin : nervure et ovale Ford (bleu nuit cerclé de chrome, écriture blanche)
    c.flat(c.rect(cx - 19, cy + 14, cx + 19, cy + 15) & hub, RAMP["black"][1])
    c.flat(c.rect(cx - 19, cy + 15, cx + 19, cy + 16) & hub, RAMP["black"][6])
    ex, ey = (c.xx + 0.5 - cx) / 11.0, (c.yy + 0.5 - cy) / 6.0
    oval = ex ** 2 + ey ** 2 <= 1.0
    inner = ((c.xx + 0.5 - cx) / 9.5) ** 2 + ((c.yy + 0.5 - cy) / 4.6) ** 2 <= 1.0
    c.shade(oval & ~inner, c.bevel(oval & ~inner, 1.2), "chrome", amb=0.45, scale=1.5)
    c.flat(inner, (16, 42, 110))
    c.flat(inner & (c.yy < cy - 2), (34, 70, 150))
    word = inner & (np.abs(c.yy + 0.5 - (cy + 0.8 * np.sin((c.xx - cx) * 0.9))) < 0.7) & (np.abs(c.xx - cx) <= 6)
    c.flat(word, (235, 238, 245))
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
    strip("pillar.png", "black", 16, 8, amb=0.3)              # montants noirs (Raptor)
    pine()
    json.dump(meta, open(os.path.join(OUT, "meta.json"), "w"))
    if len(sys.argv) > 1:
        preview(sys.argv[1])
    print("cockpit :", sorted(os.listdir(OUT)))


if __name__ == "__main__":
    main()
