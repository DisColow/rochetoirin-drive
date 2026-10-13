"""Boulangerie de Rochetoirin (demande de l'utilisateur, v6.17) : modèle sur mesure d'après le relevé Street View
(releve.md, calage.py), façades « en aplat » à la manière des anciens GTA (portes, fenêtres, volets, devanture peints
sur la texture des murs, avec leurs ombres) ; en volume seulement ce qui dépasse franchement : toits et débords, petit
pignon côté rue, annexe à terrasse, escalier extérieur, rampe et sa rambarde, enseigne en drapeau, descentes d'eau,
cheminée, climatiseur, poubelles. Enseigne parodique « Chez Flonflon » ; affiche « Horaires » griffonnée.
Sorties : godot/assets/sur_mesure/boulangerie.glb (matériau « facade » : couleur de sommet = rugosité, toit, mur),
boulangerie.png (atlas ; alpha 0 = mur, 0,5 = vitre, 1 = vitre éclairée la nuit), godot/world/sur_mesure.json
(position, sol, bâtiment BD TOPO et commerce OSM remplacés).
Lancer depuis pipeline/ : python3 boulangerie/build_boulangerie.py"""
import json, math, os, random, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ICI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(ICI))
from glb import write_glb

GOD = os.path.join(ICI, "..", "..", "godot")
OUT_A = os.path.join(GOD, "assets", "sur_mesure")
POL = os.path.join(ICI, "..", "sources", "polices")
F_ENS = os.path.join(POL, "KaushanScript-Regular.ttf")       # lettrage doré de la devanture (cursive épaisse)
F_MAIN = os.path.join(POL, "Caveat.ttf")                     # écriture à la main (gribouillis des horaires)
F_SANS = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
F_SERIF = "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf"

# ---------------------------------------------------------------- relevé (m) — voir releve.md
NE = (49.26, 409.80)                      # angle nord-est au pied du mur (repère du jeu : x est, z sud)
TH = math.atan2(0.450, 0.893)
W_ = (-math.cos(TH), -math.sin(TH))       # a : vers l'ouest le long de la façade nord
N_ = (-math.sin(TH), math.cos(TH))        # b : vers le sud le long de la façade est (pignon)
L, D = 9.3, 7.7                           # façade nord (rue), pignon est
EGOUT, FAITE = 7.5, 9.3
BR = D / 2                                # faîtage au milieu du pignon, parallèle à la rue
PENTE = (FAITE - EGOUT) / BR
DEB, DEBP = 0.5, 0.35                     # débords de toit : bas de pente, pignon
XG = dict(c=8.0, l=2.5, h=8.75)           # petit pignon côté rue (centre a, largeur, sommet)
ANX = dict(a0=0.6, a1=L, b0=D, b1=13.0, h=3.0, bal=1.0)   # annexe à terrasse (balustrade en bois)
ESC = dict(a0=-0.45, a1=0.55, b_pied=12.9, b_haut=9.8)    # escalier extérieur le long de l'annexe
RAMPE = dict(a0=-1.35, b0=0.45, b_plat=3.3, b1=5.6, h=0.15)  # plateforme devant la vitrine, rampe vers le sud

# couleurs relevées sur les photos (corrigées de l'éclairage)
C_MUR = (198, 181, 162)
C_VIOLET = (92, 54, 70)
C_ORANGE = (226, 146, 92)
C_CREME = (241, 205, 170)
C_OR = (222, 182, 96)
C_RIDEAU = (178, 172, 162)
C_VOLET_GRIS = (44, 46, 50)
C_VOLET_BOIS = (80, 50, 34)
C_TUILE = (150, 78, 56)
C_BOIS = (122, 96, 76)
C_BOIS_GRIS = (128, 114, 100)
C_ZINC = (150, 150, 146)

ATLAS = 2048
rng = random.Random(7)


# ---------------------------------------------------------------- peinture de l'atlas
class Zone:
    """Région de l'atlas peinte en mètres : (x0, y0, w, h) en pixels, s px/m, origine en bas à gauche."""
    def __init__(self, img, msk, x0, y0, w, h, s):
        self.img, self.msk, self.x0, self.y0, self.w, self.h, self.s = img, msk, x0, y0, w, h, s
        self.d = ImageDraw.Draw(img); self.m = ImageDraw.Draw(msk)

    def px(self, u, v):
        return (self.x0 + u * self.s, self.y0 + self.h - v * self.s)

    def rect(self, u0, v0, u1, v1, col, msk=None):
        a, b = self.px(u0, v1), self.px(u1, v0)
        r = [a[0], a[1], max(a[0], b[0] - 1), max(a[1], b[1] - 1)]
        self.d.rectangle(r, fill=col)
        if msk is not None:
            self.m.rectangle(r, fill=msk)

    def poly(self, pts, col):
        self.d.polygon([self.px(u, v) for u, v in pts], fill=col)

    def line(self, u0, v0, u1, v1, col, w=1):
        self.d.line([self.px(u0, v0), self.px(u1, v1)], fill=col, width=w)

    def uv(self, u, v):
        x, y = self.px(u, v)
        return (x / ATLAS, y / ATLAS)


def bruit(img, box, amp, grain=1.0, seed=0):
    """Grain d'enduit / matière : bruit fin + taches douces, dans la boîte (pixels)."""
    x0, y0, x1, y1 = [int(v) for v in box]
    w, h = x1 - x0, y1 - y0
    r = np.random.default_rng(seed)
    a = np.asarray(img.crop((x0, y0, x1, y1))).astype(np.float32)
    fin = r.normal(0, amp, (h, w, 1))
    gros = np.asarray(Image.fromarray((r.random((max(2, h // 24), max(2, w // 24))) * 255).astype(np.uint8))
                      .resize((w, h), Image.BICUBIC)).astype(np.float32)[..., None] / 255.0 - 0.5
    a = a * (1.0 + gros * 0.05 * grain) + fin
    img.paste(Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)), (x0, y0))


def ombre(z, u0, v0, u1, v1, prof=0.10, fort=0.55):
    """Ombre portée d'une embrasure (en haut et à gauche, soleil de face) : donne la profondeur sans volume."""
    a, b = z.px(u0, v1), z.px(u1, v0)
    e = max(2, int(prof * z.s))
    reg = z.img.crop((int(a[0]), int(a[1]), int(b[0]), int(b[1]))).convert("RGB")
    arr = np.asarray(reg).astype(np.float32)
    hh, ww = arr.shape[:2]
    m = np.ones((hh, ww, 1), np.float32)
    for i in range(min(e, hh)):
        m[i, :, 0] *= 1 - fort * (1 - i / e)
    for j in range(min(e, ww)):
        m[:, j, 0] *= 1 - fort * 0.7 * (1 - j / e)
    z.img.paste(Image.fromarray(np.clip(arr * m, 0, 255).astype(np.uint8)), (int(a[0]), int(a[1])))


def fenetre(z, u0, v0, u1, v1, carreaux=3, eclairee=False, volets=None, appui=True):
    """Fenêtre à deux battants peinte : embrasure, cadre blanc, petits bois, vitrage (reflet du ciel), appui en pierre,
    volets ouverts (gris, persiennes) de part et d'autre si volets='ouverts'."""
    lw = u1 - u0
    if volets == "ouverts":
        for s0 in (u0 - lw / 2 - 0.02, u1 + 0.02):
            z.rect(s0, v0 - 0.02, s0 + lw / 2, v1 + 0.02, C_VOLET_GRIS)
            n = int((v1 - v0) / 0.07)
            for k in range(n):
                v = v0 + 0.03 + k * (v1 - v0 - 0.06) / n
                z.line(s0 + 0.03, v, s0 + lw / 2 - 0.03, v, (64, 67, 72), max(1, int(0.012 * z.s)))
            z.line(s0, v1, s0, v0, (28, 29, 32), 1)
    z.rect(u0, v0, u1, v1, (236, 236, 231))                              # dormant
    f = 0.06
    # vitrage : bleu-gris sombre, reflet du ciel plus clair en haut
    a, b = z.px(u0 + f, v1 - f), z.px(u1 - f, v0 + f)
    for y in range(int(a[1]), int(b[1])):
        t = (y - a[1]) / max(1, b[1] - a[1])
        c = tuple(int(c0 * (1 - t) + c1 * t) for c0, c1 in zip((122, 140, 156), (46, 54, 63)))
        z.d.line([(a[0], y), (b[0] - 1, y)], fill=c)
    z.m.rectangle([a[0], a[1], b[0] - 1, b[1] - 1], fill=255 if eclairee else 128)
    um = (u0 + u1) / 2
    z.rect(um - 0.025, v0 + f, um + 0.025, v1 - f, (236, 236, 231), 0)      # battement central
    for k in range(1, carreaux):
        v = v0 + f + k * (v1 - v0 - 2 * f) / carreaux
        z.rect(u0 + f, v - 0.012, u1 - f, v + 0.012, (236, 236, 231), 0)    # petits bois
    ombre(z, u0 + f, v0 + f, u1 - f, v1 - f, 0.09, 0.45)
    if appui:
        z.rect(u0 - 0.06, v0 - 0.07, u1 + 0.06, v0, (196, 192, 184))
        z.rect(u0 - 0.06, v0 - 0.10, u1 + 0.06, v0 - 0.07, tuple(int(c * 0.62) for c in C_MUR))


def volets_fermes(z, u0, v0, u1, v1):
    """Volets bois fermés (rez-de-chaussée, façade nord) : planches verticales, pentures noires."""
    z.rect(u0, v0, u1, v1, C_VOLET_BOIS)
    n = 8
    for k in range(1, n):
        u = u0 + k * (u1 - u0) / n
        z.line(u, v0, u, v1, (70, 44, 28), 1)
    um = (u0 + u1) / 2
    z.line(um, v0, um, v1, (40, 26, 18), 2)
    for v in (v0 + 0.18, v1 - 0.18):
        z.rect(u0 + 0.02, v - 0.025, um - 0.04, v + 0.025, (24, 22, 22))
        z.rect(um + 0.04, v - 0.025, u1 - 0.02, v + 0.025, (24, 22, 22))
    ombre(z, u0, v0, u1, v1, 0.05, 0.3)
    z.rect(u0 - 0.06, v0 - 0.07, u1 + 0.06, v0, (196, 192, 184))


def lames(z, u0, v0, u1, v1):
    """Bardage violet à lames horizontales (devanture)."""
    z.rect(u0, v0, u1, v1, C_VIOLET)
    v = v0
    k = 0
    while v < v1:
        z.line(u0, v, u1, v, (66, 36, 50), 1)
        if k % 2:
            z.rect(u0, v + 0.01, u1, v + 0.035, (104, 63, 80))
        v += 0.065; k += 1


def rideau(z, u0, v0, u1, v1):
    """Rideau métallique baissé (tel que sur toutes les photos) : lames fines, barre basse, coulisses."""
    z.rect(u0, v0, u1, v1, C_RIDEAU)
    v = v0 + 0.08
    while v < v1:
        z.line(u0, v, u1, v, (178, 172, 162), 1)
        v += 0.05
    z.rect(u0, v0, u1, v0 + 0.06, (150, 146, 140))
    z.rect(u0 - 0.05, v0, u0, v1, (120, 118, 116)); z.rect(u1, v0, u1 + 0.05, v1, (120, 118, 116))
    ombre(z, u0, v0, u1, v1, 0.05, 0.25)


def texte(img, box, txt, font, col, contour=None, centre=True):
    """Texte ajusté dans la boîte (pixels), contour sombre facultatif."""
    x0, y0, x1, y1 = box
    d = ImageDraw.Draw(img)
    s = int(y1 - y0)
    while s > 6:
        f = ImageFont.truetype(font, s)
        bb = d.textbbox((0, 0), txt, font=f, stroke_width=2 if contour else 0)
        if bb[2] - bb[0] <= x1 - x0 and bb[3] - bb[1] <= y1 - y0:
            break
        s -= 1
    w, h = bb[2] - bb[0], bb[3] - bb[1]
    x = x0 + ((x1 - x0) - w) / 2 - bb[0] if centre else x0 - bb[0]
    y = y0 + ((y1 - y0) - h) / 2 - bb[1]
    d.text((x, y), txt, font=f, fill=col, stroke_width=2 if contour else 0, stroke_fill=contour)


def griffonnage(img, box, lignes, seed):
    """Lignes de faux texte manuscrit (gribouillis), pas de vrai contenu."""
    r = random.Random(seed)
    x0, y0, x1, y1 = box
    d = ImageDraw.Draw(img)
    h = (y1 - y0) / lignes
    for i in range(lignes):
        y = y0 + (i + 0.5) * h
        x = x0 + r.uniform(0, 4)
        xe = x1 - r.uniform(0, (x1 - x0) * 0.35)
        pts = []
        while x < xe:
            pts.append((x, y + r.uniform(-h * 0.22, h * 0.22)))
            x += r.uniform(2.0, 4.5)
        if len(pts) > 1:
            d.line(pts, fill=(40, 40, 60), width=1)


def logo(img, cx, cy, r, mot="Flonflon"):
    """Médaillon de l'enseigne parodique : couronne dorée, fond brun, épi et nom."""
    d = ImageDraw.Draw(img)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=C_OR, outline=(90, 60, 30), width=max(1, r // 10))
    r2 = r * 0.78
    d.ellipse([cx - r2, cy - r2, cx + r2, cy + r2], fill=(84, 46, 30))
    texte(img, (cx - r2 * 0.85, cy - r2 * 0.30, cx + r2 * 0.85, cy + r2 * 0.30), mot, F_ENS, C_OR)
    for k in range(5):                                         # petit épi
        a = math.radians(-90 + (k - 2) * 12)
        d.ellipse([cx + math.cos(a) * r2 * 0.62 - 2, cy + math.sin(a) * r2 * 0.62 - 3,
                   cx + math.cos(a) * r2 * 0.62 + 2, cy + math.sin(a) * r2 * 0.62 + 3], fill=C_OR)


def peindre():
    img = Image.new("RGB", (ATLAS, ATLAS), C_MUR)
    msk = Image.new("L", (ATLAS, ATLAS), 0)
    Z = {}

    # ---- pignon est (vitrine), 80 px/m : b de 0 (angle nord-est) à 7,7 m, vu de face (nord à droite)
    zE = Z["E"] = Zone(img, msk, 0, 0, 616, 744, 80)
    bruit(img, (0, 0, 616, 744), 5, seed=1)
    # u = D - b (le nord est à droite quand on regarde la façade est)
    U = lambda b: D - b
    fenetre(zE, U(3.74), 3.93, U(2.73), 5.60, carreaux=3, eclairee=True, volets="ouverts")
    fenetre(zE, U(3.48), 6.70, U(2.91), 7.77, carreaux=2)
    # devanture : bardage violet de l'angle à 4,05 m, haut 3,1 m
    lames(zE, U(4.05), 0.0, U(0.0), 3.10)
    zE.rect(U(4.05), 3.04, U(0.0), 3.10, C_ORANGE)               # liseré haut
    zE.rect(U(4.05), 0.0, U(0.0), 0.06, (60, 32, 44))
    rideau(zE, U(2.91), 0.27, U(0.80), 2.20)
    zE.rect(U(2.97), 0.15, U(2.91), 2.62, C_ORANGE); zE.rect(U(0.80), 0.15, U(0.74), 2.62, C_ORANGE)  # montants
    zE.rect(U(2.98), 0.15, U(0.73), 0.27, (180, 176, 170))       # seuil de la vitrine
    # ---- pignon : rive du toit et un peu d'ombre sous le débord
    zE.poly([(0, EGOUT), (D / 2, FAITE), (D, EGOUT), (D, 9.3 + 1), (0, 9.3 + 1)], C_MUR)
    a = zE.px(0, FAITE + 0.2)
    sh = Image.new("L", (616, 744), 0)
    ImageDraw.Draw(sh).polygon([(0, 744 - EGOUT * 80), (D / 2 * 80, 744 - FAITE * 80), (D * 80, 744 - EGOUT * 80),
                                (D * 80, 744 - EGOUT * 80 + 14), (D / 2 * 80, 744 - FAITE * 80 + 14), (0, 744 - EGOUT * 80 + 14)], fill=90)
    sh = sh.filter(ImageFilter.GaussianBlur(5))
    base = img.crop((0, 0, 616, 744))
    img.paste(Image.composite(Image.new("RGB", base.size, (90, 80, 74)), base, sh), (0, 0))
    # coffret électrique, boîte aux lettres (aplats)
    zE.rect(U(5.34), 1.02, U(4.98), 1.40, (232, 230, 224)); ombre(zE, U(5.34), 1.02, U(4.98), 1.40, 0.02, 0.2)
    zE.rect(U(7.60), 1.25, U(6.85), 1.51, (214, 190, 120)); zE.line(U(7.55), 1.42, U(6.9), 1.42, (90, 80, 50), 1)

    # ---- façade nord (rue), 80 px/m : a de 0 (angle nord-est, à gauche vu de la rue... à droite) — vue de face
    zN = Z["N"] = Zone(img, msk, 624, 0, 744, 700, 80)
    bruit(img, (624, 0, 624 + 744, 700), 5, seed=2)
    # vue de la rue (vers le sud), l'est est à gauche : u = a
    zN.poly([(XG["c"] - XG["l"] / 2, EGOUT), (XG["c"], XG["h"]), (XG["c"] + XG["l"] / 2, EGOUT)], C_MUR)
    fenetre(zN, 7.52, 6.41, 8.46, 7.86, carreaux=2, eclairee=True)
    fenetre(zN, 7.47, 3.82, 8.38, 5.56, carreaux=3, volets="ouverts")
    zN.rect(7.49 - 0.04, 1.02, 8.40 + 0.04, 2.70, (200, 196, 188))
    volets_fermes(zN, 7.49, 1.05, 8.40, 2.66)
    lames(zN, 0.0, 0.0, 5.0, 3.05)
    zN.rect(0.0, 2.98, 5.0, 3.05, C_ORANGE); zN.rect(0.0, 1.05, 5.0, 1.13, C_ORANGE); zN.rect(0.0, 0.0, 5.0, 0.05, (60, 32, 44))
    rideau(zN, 0.6, 0.2, 2.6, 2.45)
    zN.rect(2.6, 0.12, 2.66, 2.62, C_ORANGE); zN.rect(0.54, 0.12, 0.6, 2.62, C_ORANGE)
    # boîtes aux lettres (4) et coffrets
    for i in range(2):
        for j in range(2):
            zN.rect(5.08 + i * 0.52, 0.22 + j * 0.30, 5.56 + i * 0.52, 0.49 + j * 0.30, (190, 192, 194))
            zN.line(5.12 + i * 0.52, 0.44 + j * 0.30, 5.50 + i * 0.52, 0.44 + j * 0.30, (120, 122, 126), 1)
    # ombre douce sous l'égout (débord de 50 cm)
    a, b = zN.px(0, EGOUT), zN.px(L, EGOUT - 0.35)
    reg = np.asarray(img.crop((int(a[0]), int(a[1]), int(b[0]), int(b[1])))).astype(np.float32)
    f = np.linspace(0.62, 1.0, reg.shape[0])[:, None, None]
    img.paste(Image.fromarray(np.clip(reg * f, 0, 255).astype(np.uint8)), (int(a[0]), int(a[1])))

    # ---- façade sud (au-dessus de l'annexe) et pignon ouest (au-dessus du restaurant), 40 px/m
    zS = Z["S"] = Zone(img, msk, 1376, 0, 372, 300, 40)
    bruit(img, (1376, 0, 1748, 300), 5, seed=3)
    fenetre(zS, 2.2, 4.0, 3.1, 5.6, carreaux=3, volets="ouverts")
    fenetre(zS, 6.2, 4.0, 7.1, 5.6, carreaux=3, eclairee=True, volets="ouverts")
    zW = Z["W"] = Zone(img, msk, 1376, 304, 308, 372, 40)
    bruit(img, (1376, 304, 1684, 676), 5, seed=4)

    # ---- annexe : face est (porte en arc, sous l'escalier) et face sud, 80 / 40 px/m
    zA = Z["AE"] = Zone(img, msk, 0, 752, 424, 240, 80)
    bruit(img, (0, 752, 424, 992), 5, seed=5)
    Ua = lambda b: ANX["b1"] - b
    zA.rect(Ua(9.45), 0.0, Ua(8.54), 1.95, (70, 50, 38))
    a0, a1 = zA.px(Ua(9.45), 2.42), zA.px(Ua(8.54), 1.5)
    zA.d.ellipse([a0[0], a0[1], a1[0], a1[1]], fill=(70, 50, 38))
    ombre(zA, Ua(9.45), 0.0, Ua(8.54), 2.3, 0.08, 0.4)
    for k in range(5):
        zA.line(Ua(9.4) + k * 0.18, 0.05, Ua(9.4) + k * 0.18, 2.2, (52, 36, 26), 1)
    zA.rect(0, ANX["h"] - 0.12, 424 / 80, ANX["h"], (180, 176, 168))  # couvertine de la terrasse
    zAS = Z["AS"] = Zone(img, msk, 432, 752, 348, 120, 40)
    bruit(img, (432, 752, 780, 872), 5, seed=6)
    zAS.rect(0, ANX["h"] - 0.12, 348 / 40, ANX["h"], (180, 176, 168))

    # ---- toits (40 px/m) : tuiles mécaniques rouges, rangs tous les 33 cm, mousse légère
    def tuiles(box, seed):
        x0, y0, x1, y1 = box
        r = random.Random(seed)
        d = ImageDraw.Draw(img)
        d.rectangle(box, fill=C_TUILE)
        y = y0
        while y < y1:
            off = r.uniform(0, 8)
            x = x0 - off
            while x < x1:
                c = tuple(int(v * r.uniform(0.86, 1.1)) for v in C_TUILE)
                d.rectangle([x, y, x + 9, y + 12], fill=c)
                d.line([x + 9, y, x + 9, y + 12], fill=(96, 48, 36))
                x += 10
            d.line([x0, y + 12, x1, y + 12], fill=(88, 44, 34))
            y += 13
        bruit(img, box, 4, grain=2.0, seed=seed)
    Z["TN"] = Zone(img, msk, 0, 1000, 392, 200, 40); tuiles((0, 1000, 392, 1200), 11)
    Z["TS"] = Zone(img, msk, 400, 1000, 392, 200, 40); tuiles((400, 1000, 792, 1200), 12)
    Z["TX"] = Zone(img, msk, 800, 1000, 128, 128, 40); tuiles((800, 1000, 928, 1128), 13)
    # sous-face du débord : chevrons apparents
    zSO = Z["SO"] = Zone(img, msk, 936, 1000, 256, 64, 40)
    ImageDraw.Draw(img).rectangle((936, 1000, 1192, 1064), fill=(118, 96, 78))
    for k in range(0, 256, 22):
        ImageDraw.Draw(img).rectangle((936 + k, 1000, 936 + k + 5, 1064), fill=(72, 52, 40))

    # ---- décors en haute définition (posés en aplat à 1 cm du mur)
    def zone_hd(nom, x0, y0, w, h, s):
        Z[nom] = Zone(img, msk, x0, y0, w, h, s)
        return Z[nom]
    # enseigne est : « Boulangerie (médaillon) Pâtisserie », 3,6 × 0,5 m à 200 px/m
    ze = zone_hd("ENS_E", 0, 1208, 720, 100, 200)
    lames(ze, 0, 0, 3.6, 0.5)
    texte(img, (12, 1214, 330, 1302), "Boulangerie", F_ENS, C_OR, contour=(52, 30, 20))
    texte(img, (392, 1214, 712, 1302), "Pâtisserie", F_ENS, C_OR, contour=(52, 30, 20))
    logo(img, 360, 1258, 44)
    # bandeau orange du store : faux numéro de téléphone
    zt = zone_hd("TEL", 0, 1312, 580, 76, 200)
    ImageDraw.Draw(img).rectangle((0, 1312, 580, 1388), fill=C_CREME)
    ImageDraw.Draw(img).rectangle((0, 1312, 580, 1320), fill=C_ORANGE)
    ImageDraw.Draw(img).rectangle((0, 1380, 580, 1388), fill=C_ORANGE)
    texte(img, (120, 1326, 460, 1374), "04 74 00 00 00", F_SANS, (120, 50, 30))
    # affiche des horaires (demande de l'utilisateur) : titre lisible, le reste en gribouillis
    zh = zone_hd("HOR", 728, 1208, 160, 224, 400)
    ImageDraw.Draw(img).rectangle((728, 1208, 888, 1432), fill=(196, 40, 36))
    ImageDraw.Draw(img).rectangle((738, 1218, 878, 1422), fill=(250, 248, 240))
    texte(img, (744, 1224, 872, 1262), "HORAIRES", F_SANS, (170, 30, 28))
    griffonnage(img, (746, 1272, 870, 1412), 8, 21)
    # façade nord : « Boulangerie / Pâtisserie » sur deux lignes, panneau sombre au médaillon, médaillon
    zn = zone_hd("ENS_N", 896, 1208, 320, 140, 200)
    lames(zn, 0, 0, 1.6, 0.7)
    texte(img, (900, 1212, 1212, 1278), "Boulangerie", F_ENS, C_OR, contour=(52, 30, 20))
    texte(img, (900, 1278, 1212, 1344), "Pâtisserie", F_ENS, C_OR, contour=(52, 30, 20))
    zp = zone_hd("PANNEAU_N", 1224, 1208, 140, 150, 200)
    ImageDraw.Draw(img).rectangle((1224, 1208, 1364, 1358), fill=(26, 22, 24))
    logo(img, 1294, 1262, 36)
    griffonnage(img, (1240, 1306, 1350, 1350), 3, 22)
    zl = zone_hd("LOGO", 1372, 1208, 100, 100, 200)
    ImageDraw.Draw(img).rectangle((1372, 1208, 1472, 1308), fill=C_VIOLET)
    logo(img, 1422, 1258, 46)
    # enseigne en drapeau (deux faces) : « Chez Flonflon », baguette
    for k, x0 in enumerate((1480, 1600)):
        zone_hd("DRAP%d" % k, x0, 1208, 112, 192, 160)
        d = ImageDraw.Draw(img)
        d.rectangle((x0, 1208, x0 + 112, 1400), fill=(40, 26, 30))
        d.rectangle((x0 + 4, 1212, x0 + 108, 1396), outline=C_OR, width=2)
        texte(img, (x0 + 10, 1222, x0 + 102, 1262), "Chez", F_ENS, C_OR)
        texte(img, (x0 + 8, 1262, x0 + 104, 1306), "Flonflon", F_ENS, C_OR)
        d.rounded_rectangle((x0 + 20, 1326, x0 + 92, 1342), 8, fill=(214, 160, 80))
        for j in range(4):
            d.line((x0 + 30 + j * 15, 1330, x0 + 38 + j * 15, 1338), fill=(160, 100, 40), width=2)
        texte(img, (x0 + 10, 1356, x0 + 102, 1386), "Boulangerie", F_SERIF, (230, 210, 170))

    # ---- teintes unies (petits volumes) : 64 × 64
    unis = dict(bois=C_BOIS, bois_gris=C_BOIS_GRIS, fer=(58, 60, 62), zinc=C_ZINC, blanc=(226, 226, 222),
                beton=(176, 172, 164), poubelle=(70, 74, 78), couvercle_j=(212, 176, 40), couvercle_g=(80, 84, 88),
                cheminee=C_MUR, mur=C_MUR, violet=C_VIOLET, rive=(214, 204, 192), sombre=(30, 30, 32))
    for k, (nom, c) in enumerate(unis.items()):
        x0, y0 = (k % 16) * 64, 1440 + (k // 16) * 64
        ImageDraw.Draw(img).rectangle((x0, y0, x0 + 63, y0 + 63), fill=c)
        bruit(img, (x0, y0, x0 + 64, y0 + 64), 4, seed=40 + k)
        Z["u_" + nom] = Zone(img, msk, x0 + 8, y0 + 8, 48, 48, 48)
    out = Image.merge("RGBA", (*img.split(), msk))
    return out, Z


# ---------------------------------------------------------------- géométrie (repère local a, b, y -> monde)
class Mesh:
    def __init__(self):
        self.P, self.N, self.UV, self.C, self.I = [], [], [], [], []

    def quad(self, q, uvs, col, nrm=None):
        """q : 4 points locaux (a, b, y) ; uvs : 4 uv ; col : (rugosité, toit, mur)."""
        Q = [loc(*p) for p in q]
        if nrm is None:
            v = np.cross(np.subtract(Q[1], Q[0]), np.subtract(Q[3], Q[0]))
            nrm = v / (np.linalg.norm(v) + 1e-9)
        o = len(self.P)
        for p, t in zip(Q, uvs):
            self.P.append(p); self.N.append(nrm); self.UV.append(t); self.C.append(col)
        self.I += [o, o + 1, o + 2, o, o + 2, o + 3]

    def tri(self, q, uvs, col):
        Q = [loc(*p) for p in q]
        v = np.cross(np.subtract(Q[1], Q[0]), np.subtract(Q[2], Q[0]))
        nrm = v / (np.linalg.norm(v) + 1e-9)
        o = len(self.P)
        for p, t in zip(Q, uvs):
            self.P.append(p); self.N.append(nrm); self.UV.append(t); self.C.append(col)
        self.I += [o, o + 1, o + 2]


def loc(a, b, y):
    """(a, b, y) locaux -> (x, y, z) du monde, relatifs au point de pose (angle nord-est au sol)."""
    return (a * W_[0] + b * N_[0], y, a * W_[1] + b * N_[1])


MUR, TOIT, PETIT = (0.85, 0.0, 1.0), (0.7, 1.0, 0.0), (0.6, 0.0, 0.0)
BAS = -1.5      # les murs descendent sous le sol (terrain irrégulier)


def boite(M, Z, nom, a0, a1, b0, b1, y0, y1, col=PETIT, dessus=True, dessous=False):
    z = Z["u_" + nom]
    uv = [z.uv(0, 0), z.uv(1, 0), z.uv(1, 1), z.uv(0, 1)]
    c = [(a0, b0), (a1, b0), (a1, b1), (a0, b1)]
    for i in range(4):
        (p, q), (r, s) = c[i], c[(i + 1) % 4]
        M.quad([(p, q, y0), (r, s, y0), (r, s, y1), (p, q, y1)], uv, col)
    if dessus:
        M.quad([(a0, b0, y1), (a0, b1, y1), (a1, b1, y1), (a1, b0, y1)], uv, col)
    if dessous:
        M.quad([(a0, b0, y0), (a1, b0, y0), (a1, b1, y0), (a0, b1, y0)], uv, col)


def barre(M, Z, nom, p0, p1, r, col=PETIT):
    """Barre de section carrée r × r entre deux points locaux (main courante, tube)."""
    p0, p1 = np.array(p0, float), np.array(p1, float)
    d = p1 - p0; d /= np.linalg.norm(d)
    up = np.array([0, 0, 1.0]) if abs(d[2]) < 0.9 else np.array([1.0, 0, 0])
    s = np.cross(d, up); s /= np.linalg.norm(s); t = np.cross(s, d)
    z = Z["u_" + nom]
    uv = [z.uv(0, 0), z.uv(1, 0), z.uv(1, 1), z.uv(0, 1)]
    cs = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
    for i in range(4):
        e0 = (s * cs[i][0] + t * cs[i][1]) * r / 2
        e1 = (s * cs[(i + 1) % 4][0] + t * cs[(i + 1) % 4][1]) * r / 2
        M.quad([tuple(p0 + e0), tuple(p1 + e0), tuple(p1 + e1), tuple(p0 + e1)], uv, col)


def construire(Z):
    M = Mesh()
    C = []          # collisions : boîtes (a0, a1, b0, b1, y0, y1)
    zE, zN, zS, zW = Z["E"], Z["N"], Z["S"], Z["W"]
    V0 = 0.02           # sous le sol, la texture reprend le pied du mur (pas la zone voisine de l'atlas)
    # ---- murs du corps principal (façade est : a = 0 ; nord : b = 0 ; ouest : a = L ; sud : b = D)
    U = lambda b: D - b
    for (y0, y1, v0, v1) in ((BAS, 0.0, V0, V0), (0.0, EGOUT, 0.0, EGOUT)):   # partie enterrée : pied du mur étiré
        M.quad([(0, D, y0), (0, 0, y0), (0, 0, y1), (0, D, y1)],
               [zE.uv(U(D), v0), zE.uv(U(0), v0), zE.uv(U(0), v1), zE.uv(U(D), v1)], MUR)
    M.tri([(0, D, EGOUT), (0, 0, EGOUT), (0, BR, FAITE)], [zE.uv(0, EGOUT), zE.uv(D, EGOUT), zE.uv(D / 2, FAITE)], MUR)
    for (y0, y1, v0, v1) in ((BAS, 0.0, V0, V0), (0.0, EGOUT, 0.0, EGOUT)):
        M.quad([(0, 0, y0), (L, 0, y0), (L, 0, y1), (0, 0, y1)],
               [zN.uv(0, v0), zN.uv(L, v0), zN.uv(L, v1), zN.uv(0, v1)], MUR)
    g0, g1 = XG["c"] - XG["l"] / 2, XG["c"] + XG["l"] / 2
    M.tri([(g0, 0, EGOUT), (g1, 0, EGOUT), (XG["c"], 0, XG["h"])], [zN.uv(g0, EGOUT), zN.uv(g1, EGOUT), zN.uv(XG["c"], XG["h"])], MUR)
    M.quad([(L, D, 0), (0, D, 0), (0, D, EGOUT), (L, D, EGOUT)],
           [zS.uv(0, 0), zS.uv(L, 0), zS.uv(L, EGOUT), zS.uv(0, EGOUT)], MUR)
    M.quad([(L, 0, 0), (L, D, 0), (L, D, EGOUT), (L, 0, EGOUT)],
           [zW.uv(0, 0), zW.uv(D, 0), zW.uv(D, EGOUT), zW.uv(0, EGOUT)], MUR)
    M.tri([(L, 0, EGOUT), (L, D, EGOUT), (L, BR, FAITE)], [zW.uv(0, EGOUT), zW.uv(D, EGOUT), zW.uv(D / 2, FAITE)], MUR)
    C.append((0, L, 0, D, BAS, EGOUT))
    # ---- toit à deux pans : débords, épaisseur (rive), sous-face à chevrons
    ep = 0.16
    yb = EGOUT - DEB * PENTE
    tn, ts, tx, so = Z["TN"], Z["TS"], Z["TX"], Z["SO"]
    lp = math.hypot(BR + DEB, FAITE - yb)
    for (b_bas, zt, sgn) in ((-DEB, tn, 1), (D + DEB, ts, -1)):
        M.quad([(-DEBP, b_bas, yb + ep), (L + 0.05, b_bas, yb + ep), (L + 0.05, BR, FAITE + ep), (-DEBP, BR, FAITE + ep)],
               [zt.uv(0, 0), zt.uv(9.8, 0), zt.uv(9.8, lp), zt.uv(0, lp)], TOIT)
        M.quad([(-DEBP, BR, FAITE), (L + 0.05, BR, FAITE), (L + 0.05, b_bas, yb), (-DEBP, b_bas, yb)],
               [so.uv(0, 0), so.uv(6.4, 0), so.uv(6.4, 1.6), so.uv(0, 1.6)], PETIT)
        z = Z["u_rive"]
        M.quad([(-DEBP, b_bas, yb), (L + 0.05, b_bas, yb), (L + 0.05, b_bas, yb + ep), (-DEBP, b_bas, yb + ep)],
               [z.uv(0, 0), z.uv(1, 0), z.uv(1, 1), z.uv(0, 1)], PETIT)
        # gouttière
        boite(M, Z, "zinc", -DEBP, L, b_bas - sgn * 0.12, b_bas, yb - 0.12, yb + 0.02)
    for (b_bas) in (-DEB, D + DEB):                      # rives du pignon est
        z = Z["u_rive"]
        M.quad([(-DEBP, b_bas, yb), (-DEBP, BR, FAITE), (-DEBP, BR, FAITE + ep), (-DEBP, b_bas, yb + ep)],
               [z.uv(0, 0), z.uv(1, 0), z.uv(1, 1), z.uv(0, 1)], PETIT)
    # faîtière
    boite(M, Z, "rive", -DEBP, L + 0.05, BR - 0.12, BR + 0.12, FAITE + ep - 0.02, FAITE + ep + 0.12, TOIT)
    # ---- petit pignon côté rue : deux pans jusqu'à la noue
    hx = XG["h"] + 0.12
    bnoue = (hx - EGOUT) / PENTE
    for gs in (g0 - 0.15, g1 + 0.15):
        M.quad([(gs, -0.45, EGOUT - 0.12), (XG["c"], -0.45, hx), (XG["c"], bnoue, hx), (gs, 0.1, EGOUT + 0.05)],
               [tx.uv(0, 0), tx.uv(1.4, 0), tx.uv(1.4, 3.0), tx.uv(0, 3.0)], TOIT)
        M.quad([(gs, 0.1, EGOUT - 0.02), (XG["c"], bnoue, hx - 0.1), (XG["c"], -0.45, hx - 0.1), (gs, -0.45, EGOUT - 0.14)],
               [so.uv(0, 0), so.uv(2, 0), so.uv(2, 1.6), so.uv(0, 1.6)], PETIT)
    # cheminée (pan nord, côté est)
    boite(M, Z, "cheminee", 5.2, 5.75, 1.6, 2.2, EGOUT, FAITE + 0.6)
    boite(M, Z, "rive", 5.12, 5.83, 1.52, 2.28, FAITE + 0.6, FAITE + 0.7)
    # descentes d'eau : angle nord-est, angle sud-est, ouest de la façade nord
    for (a, b) in ((0.08, -0.12), (0.08, D + 0.12), (L - 0.12, -0.12)):
        boite(M, Z, "zinc", a - 0.05, a + 0.05, b - 0.05, b + 0.05, 0.0, yb)
    # ---- annexe à terrasse (en retrait de 0,6 m), balustrade en bois, couvertine
    za, zas = Z["AE"], Z["AS"]
    Ua = lambda b: ANX["b1"] - b
    a0, a1, b0, b1, h = ANX["a0"], ANX["a1"], ANX["b0"], ANX["b1"], ANX["h"]
    for (y0, y1, v0, v1) in ((BAS, 0.0, V0, V0), (0.0, h, 0.0, h)):
        M.quad([(a0, b1, y0), (a0, b0, y0), (a0, b0, y1), (a0, b1, y1)],
               [za.uv(Ua(b1), v0), za.uv(Ua(b0), v0), za.uv(Ua(b0), v1), za.uv(Ua(b1), v1)], MUR)
        M.quad([(a1, b1, y0), (a0, b1, y0), (a0, b1, y1), (a1, b1, y1)],
               [zas.uv(0, v0), zas.uv(a1 - a0, v0), zas.uv(a1 - a0, v1), zas.uv(0, v1)], MUR)
    boite(M, Z, "beton", a0, a1, b0, b1, h - 0.05, h, PETIT)                        # dalle de la terrasse
    C.append((a0, a1, b0, b1, BAS, h))
    # balustrade : lisse haute, lisse basse, lames verticales (côtés est et sud)
    for (p, q) in (((a0 + 0.05, b0 + 0.05), (a0 + 0.05, b1 - 0.05)), ((a0 + 0.05, b1 - 0.05), (a1, b1 - 0.05))):
        barre(M, Z, "bois_gris", (p[0], p[1], h + ANX["bal"]), (q[0], q[1], h + ANX["bal"]), 0.07)
        barre(M, Z, "bois_gris", (p[0], p[1], h + 0.1), (q[0], q[1], h + 0.1), 0.05)
        n = int(math.hypot(q[0] - p[0], q[1] - p[1]) / 0.14)
        for k in range(n + 1):
            t = k / max(1, n)
            x, y = p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t
            boite(M, Z, "bois_gris", x - 0.035, x + 0.035, y - 0.01, y + 0.01, h, h + ANX["bal"], dessus=False)
    # ---- escalier extérieur en bois, le long de l'annexe (monte vers le nord), palier devant la porte-fenêtre
    e0, e1 = ESC["a0"], ESC["a1"]
    bp, bh = ESC["b_pied"], ESC["b_haut"]
    n = 17
    for k in range(n):
        y = (k + 1) * h / n
        bb = bp - (k + 1) * (bp - bh) / n
        boite(M, Z, "bois", e0, e1, bb, bb + (bp - bh) / n + 0.03, y - 0.05, y, dessous=True)
    boite(M, Z, "bois", e0, e1, b0 + 0.3, bh, h - 0.08, h, dessous=True)               # palier
    for a in (e0, e1):
        barre(M, Z, "bois", (a, bp, 0.1), (a, bh, h), 0.07)                             # limons
        barre(M, Z, "bois_gris", (a if a == e0 else e0, bp, 1.0), (e0, bh, h + 1.0), 0.07) if a == e0 else None
    for k in range(9):
        t = k / 8
        bb = bp - t * (bp - bh)
        boite(M, Z, "bois_gris", e0 - 0.01, e0 + 0.01, bb - 0.04, bb + 0.04, t * h + 0.1, t * h + 1.0, dessus=False)
    barre(M, Z, "bois_gris", (e0, bh, h + 1.0), (e0, b0 + 0.3, h + 1.0), 0.07)
    boite(M, Z, "bois", e0 - 0.05, e0 + 0.05, b0 + 0.3, b0 + 0.4, 0.0, h)            # poteau du palier
    # collision de l'escalier : volée en rampe
    C.append(("rampe", e0, e1, bp, bh, 0.0, h))
    # ---- plateforme et rampe devant la vitrine, rambarde en tube
    r = RAMPE
    hp = r["h"]
    zb = Z["u_beton"]; uvb = [zb.uv(0, 0), zb.uv(1, 0), zb.uv(1, 1), zb.uv(0, 1)]
    M.quad([(r["a0"], r["b0"], hp), (r["a0"], r["b_plat"], hp), (0, r["b_plat"], hp), (0, r["b0"], hp)], uvb, PETIT)
    M.quad([(r["a0"], r["b_plat"], hp), (r["a0"], r["b1"], 0.0), (0, r["b1"], 0.0), (0, r["b_plat"], hp)], uvb, PETIT)
    M.quad([(r["a0"], r["b0"], -0.3), (r["a0"], r["b0"], hp), (0, r["b0"], hp), (0, r["b0"], -0.3)], uvb, PETIT)
    M.quad([(r["a0"], r["b0"], -0.3), (r["a0"], r["b_plat"], -0.3), (r["a0"], r["b_plat"], hp), (r["a0"], r["b0"], hp)], uvb, PETIT)
    M.quad([(r["a0"], r["b_plat"], -0.3), (r["a0"], r["b1"], -0.3), (r["a0"], r["b1"], 0.0), (r["a0"], r["b_plat"], hp)], uvb, PETIT)
    C.append(("plateforme", r["a0"], 0, r["b0"], r["b_plat"], -0.3, hp))
    ar = r["a0"] + 0.06
    posts = [0.74, 2.35, 3.95, 5.37]
    hy = lambda b: hp if b <= r["b_plat"] else hp * (r["b1"] - b) / (r["b1"] - r["b_plat"])
    for b in posts:
        boite(M, Z, "fer", ar - 0.025, ar + 0.025, b - 0.025, b + 0.025, hy(b), hy(b) + 1.0, dessus=True)
    for yy in (1.0, 0.5):
        barre(M, Z, "fer", (ar, posts[0], hy(posts[0]) + yy), (ar, r["b_plat"], hp + yy), 0.045)
        barre(M, Z, "fer", (ar, r["b_plat"], hp + yy), (ar, posts[-1], hy(posts[-1]) + yy), 0.045)
    barre(M, Z, "fer", (ar, posts[0], hp + 1.0), (0.02, posts[0], hp + 1.0), 0.045)     # retour vers le mur
    # ---- décors en aplat (1 cm devant le mur) : enseignes, bandeau, horaires, panneau, médaillon
    def decal(nom, face, u0, u1, v0, v1):
        z = Z[nom]
        w, hh = z.w / z.s, z.h / z.s
        uv = [z.uv(0, 0), z.uv(w, 0), z.uv(w, hh), z.uv(0, hh)]
        e = 0.012
        if face == "E":       # sur la façade est, u = b vers le nord… (b décroissant vers la droite)
            M.quad([(-e, u1, v0), (-e, u0, v0), (-e, u0, v1), (-e, u1, v1)], uv, PETIT)
        else:                 # façade nord, u = a vers l'ouest (vue de la rue : de gauche à droite)
            M.quad([(u0, -e, v0), (u1, -e, v0), (u1, -e, v1), (u0, -e, v1)], uv, PETIT)
    decal("ENS_E", "E", 0.25, 3.85, 2.62, 3.12)
    decal("TEL", "E", 0.68, 3.58, 2.20, 2.58)
    decal("HOR", "E", 3.34, 3.74, 1.08, 1.64)
    decal("ENS_N", "N", 3.0, 4.6, 2.08, 2.78)
    decal("PANNEAU_N", "N", 3.30, 4.00, 1.00, 1.75)
    decal("LOGO", "N", 1.0, 1.5, 2.48, 2.98)
    # enseigne en drapeau à l'angle nord-est (perpendiculaire à la façade nord), potence en fer
    for k, s in enumerate((-1, 1)):
        z = Z["DRAP%d" % k]
        uv = [z.uv(0, 0), z.uv(0.7, 0), z.uv(0.7, 1.2), z.uv(0, 1.2)]
        a = 0.35 + s * 0.02
        if s < 0:
            M.quad([(a, -0.95, 3.5), (a, -0.25, 3.5), (a, -0.25, 4.7), (a, -0.95, 4.7)], uv, PETIT)
        else:
            M.quad([(a, -0.25, 3.5), (a, -0.95, 3.5), (a, -0.95, 4.7), (a, -0.25, 4.7)], uv, PETIT)
    barre(M, Z, "fer", (0.35, 0.0, 4.75), (0.35, -1.0, 4.75), 0.04)
    boite(M, Z, "sombre", 0.31, 0.39, -1.0, -0.2, 3.48, 3.5)
    # climatiseur, poubelles (devant l'annexe)
    boite(M, Z, "blanc", -0.32, 0.0, 6.66, 7.58, 0.05, 0.72)
    for k, (bb, cv) in enumerate(((11.35, "couvercle_g"), (11.95, "couvercle_g"), (12.55, "couvercle_j"))):
        boite(M, Z, "poubelle", -0.35, 0.25, bb - 0.28, bb + 0.28, 0.0, 1.0)
        boite(M, Z, cv, -0.4, 0.28, bb - 0.3, bb + 0.3, 1.0, 1.06)
    C.append(("poubelles", -0.4, 0.28, 11.0, 12.9, 0.0, 1.06))
    return M, C


def main():
    atlas, Z = peindre()
    os.makedirs(OUT_A, exist_ok=True)
    atlas.save(os.path.join(OUT_A, "boulangerie.png"))
    M, C = construire(Z)
    prim = ("facade", np.array(M.P), np.array(M.N), np.array(M.UV), np.array(M.I, np.uint32), np.array(M.C))
    # collisions : boîtes et rampes (prismes) en triangles
    CP, CI = [], []
    for c in C:
        if isinstance(c[0], str):
            kind, a0, a1, b0, b1, y0, y1 = c
        else:
            kind = "boite"; a0, a1, b0, b1, y0, y1 = c
        if kind == "rampe":       # volée d'escalier : plan incliné de b0 (bas) à b1 (haut)
            q = [(a0, b0, y0), (a1, b0, y0), (a1, b1, y1), (a0, b1, y1), (a0, b0, y0 - 0.3), (a1, b0, y0 - 0.3), (a1, b1, y0 - 0.3), (a0, b1, y0 - 0.3)]
        else:
            q = [(a0, b0, y1), (a1, b0, y1), (a1, b1, y1), (a0, b1, y1), (a0, b0, y0), (a1, b0, y0), (a1, b1, y0), (a0, b1, y0)]
        o = len(CP)
        CP += [loc(*p) for p in q]
        CI += [o + i for i in (0, 1, 2, 0, 2, 3, 4, 6, 5, 4, 7, 6, 0, 4, 5, 0, 5, 1, 1, 5, 6, 1, 6, 2, 2, 6, 7, 2, 7, 3, 3, 7, 4, 3, 4, 0)]
    CP = np.array(CP, np.float32)
    col = ("collision", CP, np.tile([0, 1, 0], (len(CP), 1)), CP[:, [0, 2]], np.array(CI, np.uint32))
    write_glb(os.path.join(OUT_A, "boulangerie.glb"), {"boulangerie": [prim], "col": [col]}, fix_winding=False)
    sol = 450.30
    # collisions en boîtes (v6.18 : BoxShape3D seulement) : [cx, cy, cz, demi-a, demi-y, demi-b, lacet], repère de pose
    lacet = math.atan2(-W_[1], W_[0])
    boites = []
    for c in C:
        a0, a1, b0, b1, y0, y1 = c[1:] if isinstance(c[0], str) else c
        cx, cy, cz = loc((a0 + a1) / 2, (b0 + b1) / 2, (y0 + y1) / 2)
        boites.append([round(v, 3) for v in (cx, cy, cz, abs(a1 - a0) / 2, abs(y1 - y0) / 2, abs(b1 - b0) / 2, lacet)])
    sp = os.path.join(GOD, "world", "sur_mesure.json")
    pose = json.load(open(sp)) if os.path.exists(sp) else {}     # autres bâtiments sur mesure gardés (restaurant…)
    pose.update({"boulangerie": {"boites": boites, "glb": "res://assets/sur_mesure/boulangerie.glb", "atlas": "res://assets/sur_mesure/boulangerie.png",
                            "pos": [NE[0], sol, NE[1]], "remplace_bati": ["BATIMENT0000000301133203"],
                            "remplace_commerce": ["n3646424189"], "nom": "Chez Flonflon (boulangerie de Rochetoirin)"}})
    json.dump(pose, open(sp, "w"), indent=1, ensure_ascii=False)
    print("boulangerie : %d sommets, %d triangles, %d boîtes de collision" % (len(M.P), len(M.I) // 3, len(C)))


if __name__ == "__main__":
    main()
