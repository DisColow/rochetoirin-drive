"""Restaurant « Le Rochetoirin » (accolé à l'ouest de la boulangerie), v6.20, demande de l'utilisateur : bon nombre de
fenêtres et bonne position, bonne devanture, enseigne parodique (« Le Rochefestin »), couleurs, éléments extérieurs et
affichettes ; un maximum d'aplats, seuls les titres lisibles (le reste en gribouillis). Méthode rapide (« reconnaissable,
pas exact ») : emprise du cadastre recalée sur le repère de la boulangerie, travées comptées sur les photos du cache
(a_o, e_sudouest, f_arriere : voir releve_restaurant.md), outils de peinture et de maillage de build_boulangerie.py.
Sorties : godot/assets/sur_mesure/restaurant.glb + restaurant.png, entrée « restaurant » de godot/world/sur_mesure.json.
Lancer depuis pipeline/ : python3 boulangerie/build_restaurant.py"""
import json, math, os, random, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ICI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, ICI)
import build_boulangerie as BB
from build_boulangerie import Zone, bruit, ombre, texte, griffonnage, Mesh, loc, boite, barre, write_glb, F_SANS, F_SERIF, F_MAIN

GOD, OUT_A = BB.GOD, BB.OUT_A
ATLAS = BB.ATLAS

# ---------------------------------------------------------------- relevé (m), repère de la boulangerie (a vers l'ouest
# le long de la rue, b vers le sud, origine : angle nord-est de la boulangerie au sol) — releve_restaurant.md
A0, AC, A1 = 9.3, 13.0, 26.3      # corps est (A, haut, en retrait) de A0 à AC ; corps principal (C) de AC à A1
BA = 1.6                          # retrait du corps A (le rez-de-chaussée en briques comble le retrait)
CD = 10.0                         # profondeur du corps principal
CE, CF = 6.0, 8.7                 # corps principal : égout, faîtage (parallèle à la rue)
AE, AF, AD = 7.3, 9.5, 9.0        # corps est : égout, faîtage, fond (b)
HB = 2.95                         # rez-de-chaussée en briques (devant du corps A), toit en appentis
SALLE = dict(a0=A0, a1=A1, b0=CD, b1=21.0, h=3.6, ea0=7.0, eb0=13.5)   # salle arrière, toit plat (+ aile est)
VER = dict(a0=5.0, a1=16.0, b0=21.0, b1=28.5, h=3.0)                  # véranda (pergola grise vitrée, f_arriere)

C_MUR = (196, 82, 72)             # enduit rouge
C_JAUNE = (228, 204, 132)         # chaînages, encadrements, soubassement
C_VOLET = (158, 174, 196)         # volets gris-bleu clair
C_BRIQUE = (138, 88, 58)
C_BOIS = (168, 112, 58)
C_PORTE = (74, 46, 34)
C_TUILE = BB.C_TUILE
C_GRIS = (74, 78, 82)             # pergola, débords
NOM = "Le Rochefestin"            # parodie de « Le Rochetoirin »

rng = random.Random(5)


# ---------------------------------------------------------------- peinture
def enduit(img, z, seed):
    x0, y0 = int(z.x0), int(z.y0)
    ImageDraw.Draw(img).rectangle((x0, y0, x0 + z.w - 1, y0 + z.h - 1), fill=C_MUR)
    bruit(img, (x0, y0, x0 + z.w, y0 + z.h), 5, seed=seed)


def soubassement(z, u0, u1, h=0.55):
    z.rect(u0, -0.1, u1, h, C_JAUNE)


def chainage(z, u, v0, v1, cote=1, l=0.38):
    """Chaîne d'angle jaune (pierres alternées), le long du bord u, vers l'intérieur (cote = +1 ou -1)."""
    v, k = v0, 0
    while v < v1:
        w = l if k % 2 == 0 else l * 0.62
        a, b = (u, u + cote * w) if cote > 0 else (u + cote * w, u)
        z.rect(a, v, b, min(v + 0.32, v1), C_JAUNE)
        z.line(a, v, b, v, (196, 172, 104), 1)
        v += 0.34; k += 1


def volets_clos(z, u0, v0, u1, v1, porte=False):
    """Volets gris-bleu fermés : planches verticales, barres et écharpe en Z, pentures sombres."""
    z.rect(u0, v0, u1, v1, C_VOLET)
    n = max(4, int((u1 - u0) / 0.11))
    for k in range(1, n):
        u = u0 + k * (u1 - u0) / n
        z.line(u, v0, u, v1, (132, 146, 168), 1)
    um = (u0 + u1) / 2
    z.line(um, v0, um, v1, (100, 110, 128), 2)
    for v in (v0 + 0.16, v1 - 0.16) + (((v0 + v1) / 2,) if porte else ()):
        z.rect(u0 + 0.03, v - 0.03, u1 - 0.03, v + 0.03, (140, 156, 178))
        z.rect(u0 - 0.04, v - 0.012, u0 + 0.14, v + 0.012, (40, 40, 44))
        z.rect(u1 - 0.14, v - 0.012, u1 + 0.04, v + 0.012, (40, 40, 44))
    z.line(u0 + 0.05, v0 + 0.2, um - 0.05, v1 - 0.2, (132, 146, 168), 2)
    z.line(um + 0.05, v0 + 0.2, u1 - 0.05, v1 - 0.2, (132, 146, 168), 2)
    ombre(z, u0, v0, u1, v1, 0.05, 0.25)


def encadrement(z, u0, v0, u1, v1, e=0.11, appui=True):
    z.rect(u0 - e, v0 - (0.06 if appui else 0), u1 + e, v1 + e, C_JAUNE)
    if appui:
        z.rect(u0 - e - 0.05, v0 - 0.1, u1 + e + 0.05, v0 - 0.02, (236, 226, 196))
        z.rect(u0 - e - 0.05, v0 - 0.14, u1 + e + 0.05, v0 - 0.10, (120, 60, 52))


def baie(z, u0, v0, u1, v1, mode="clos", appui=True):
    """Ouverture peinte : encadrement jaune, puis volets clos, ou fenêtre ouverte (vitrage + volets rabattus)."""
    encadrement(z, u0, v0, u1, v1, appui=appui)
    if mode == "clos":
        volets_clos(z, u0, v0, u1, v1, porte=not appui)
    else:
        z.rect(u0, v0, u1, v1, (236, 230, 214))
        f = 0.06
        a, b = z.px(u0 + f, v1 - f), z.px(u1 - f, v0 + f)
        for y in range(int(a[1]), int(b[1])):
            t = (y - a[1]) / max(1, b[1] - a[1])
            c = tuple(int(c0 * (1 - t) + c1 * t) for c0, c1 in zip((118, 132, 146), (40, 44, 50)))
            z.d.line([(a[0], y), (b[0] - 1, y)], fill=c)
        z.m.rectangle([a[0], a[1], b[0] - 1, b[1] - 1], fill=255)
        z.rect((u0 + u1) / 2 - 0.025, v0 + f, (u0 + u1) / 2 + 0.025, v1 - f, (236, 230, 214), 0)
        ombre(z, u0 + f, v0 + f, u1 - f, v1 - f, 0.09, 0.45)
        lw = (u1 - u0) / 2
        for s0 in (u0 - 0.11 - lw, u1 + 0.11):           # volets ouverts contre le mur
            volets_clos(z, s0, v0 - 0.02, s0 + lw, v1 + 0.02)


def ombre_egout(img, z, v, prof=0.4):
    a, b = z.px(0, v), z.px(z.w / z.s, v - prof)
    reg = np.asarray(img.crop((int(a[0]), int(a[1]), int(b[0]), int(b[1])))).astype(np.float32)
    f = np.linspace(0.6, 1.0, reg.shape[0])[:, None, None]
    img.paste(Image.fromarray(np.clip(reg * f, 0, 255).astype(np.uint8)), (int(a[0]), int(a[1])))


def briques(img, z, seed):
    x0, y0, x1, y1 = int(z.x0), int(z.y0), int(z.x0 + z.w), int(z.y0 + z.h)
    r = random.Random(seed)
    d = ImageDraw.Draw(img)
    d.rectangle((x0, y0, x1, y1), fill=(176, 160, 136))                  # joints clairs
    bh, bw = 0.065 * z.s, 0.22 * z.s
    y, k = y0, 0
    while y < y1:
        x = x0 - (bw / 2 if k % 2 else 0)
        while x < x1:
            f = r.uniform(0.72, 1.18)
            c = tuple(int(v * f) for v in C_BRIQUE)
            if r.random() < 0.12:
                c = (176, 128, 70)                                       # briques claires (ocre) mêlées
            d.rectangle((x + 1, y + 1, x + bw - 1, y + bh - 1), fill=c)
            x += bw
        y += bh; k += 1
    bruit(img, (x0, y0, x1, y1), 4, seed=seed)


def tuiles(img, box, seed):
    x0, y0, x1, y1 = box
    r = random.Random(seed)
    d = ImageDraw.Draw(img)
    d.rectangle(box, fill=C_TUILE)
    y = y0
    while y < y1:
        x = x0 - r.uniform(0, 8)
        while x < x1:
            c = tuple(int(v * r.uniform(0.86, 1.1)) for v in C_TUILE)
            d.rectangle([x, y, x + 9, y + 12], fill=c)
            d.line([x + 9, y, x + 9, y + 12], fill=(96, 48, 36))
            x += 10
        d.line([x0, y + 12, x1, y + 12], fill=(88, 44, 34))
        y += 13
    bruit(img, box, 4, grain=2.0, seed=seed)


def affiche(img, box, titre, seed, fond=(250, 248, 240), cadre=None, encre=(40, 40, 60)):
    """Affichette : titre lisible, le reste en gribouillis (demande de l'utilisateur)."""
    x0, y0, x1, y1 = box
    d = ImageDraw.Draw(img)
    if cadre:
        d.rectangle(box, fill=cadre)
        x0, y0, x1, y1 = x0 + 6, y0 + 6, x1 - 6, y1 - 6
    d.rectangle((x0, y0, x1, y1), fill=fond)
    th = max(12, int((y1 - y0) * 0.2))
    texte(img, (x0 + 4, y0 + 3, x1 - 4, y0 + 3 + th), titre, F_SANS, encre)
    griffonnage(img, (x0 + 6, y0 + th + 10, x1 - 6, y1 - 6), max(3, int((y1 - y0 - th) / 14)), seed)


def peindre():
    img = Image.new("RGB", (ATLAS, ATLAS), C_MUR)
    msk = Image.new("L", (ATLAS, ATLAS), 0)
    Z = {}

    # ---- façade nord du corps principal (rue), 64 px/m, u = a - AC (vue de la rue : est à gauche)
    LC = A1 - AC
    zC = Z["C"] = Zone(img, msk, 0, 0, int(LC * 64) + 1, int((CE + 0.2) * 64), 64)
    enduit(img, zC, 1)
    soubassement(zC, 0, LC)
    chainage(zC, 0, 0.55, CE, 1); chainage(zC, LC, 0.55, CE, -1)
    # travées (de l'est à l'ouest) : 1 volets clos / fenêtre close ; 2 fenêtre ouverte / porte ; 3 grande fenêtre / grande baie
    baie(zC, 2.6, 3.75, 3.45, 5.15)
    baie(zC, 2.6, 0.80, 3.40, 2.45)
    baie(zC, 6.1, 3.75, 6.9, 5.20, mode="ouvert")
    baie(zC, 5.95, 0.0, 7.0, 2.35, appui=False)
    baie(zC, 10.05, 3.70, 11.15, 5.35)
    baie(zC, 9.9, 0.55, 11.4, 2.60)
    ombre_egout(img, zC, CE + 0.2, 0.55)

    # ---- mur est du corps principal au-dessus du rez-de-chaussée en briques (b de 0 à BA), 64 px/m, u = BA - b
    zCE = Z["CE"] = Zone(img, msk, 856, 0, int(BA * 64) + 1, int((CE + 0.2) * 64), 64)
    enduit(img, zCE, 2)
    chainage(zCE, BA, 0.0, CE, -1)

    # ---- façade nord du corps est (en retrait), 64 px/m, u = a - A0
    LA = AC - A0
    zA = Z["A"] = Zone(img, msk, 968, 0, int(LA * 64) + 1, int((AE + 0.2) * 64), 64)
    enduit(img, zA, 3)
    chainage(zA, 0, 0.0, AE, 1)
    baie(zA, 1.45, 4.3, 2.35, 5.85)
    ombre_egout(img, zA, AE + 0.2, 0.5)

    # ---- rez-de-chaussée en briques sous le porche (b = 0), 128 px/m, u = a - A0
    zB = Z["B"] = Zone(img, msk, 1216, 0, int(LA * 128) + 1, int((HB + 0.05) * 128), 128)
    briques(img, zB, 4)
    zB.rect(0.10, 0.12, 0.48, 0.80, (226, 224, 218)); ombre(zB, 0.10, 0.12, 0.48, 0.80, 0.02, 0.2)   # coffret
    zB.rect(0.58, 1.05, 0.76, 1.30, (30, 30, 32))                                                     # boîte aux lettres
    zB.rect(0.80, 0.12, 1.55, 2.50, (52, 40, 32))                                                     # renfoncement
    zB.rect(0.88, 0.16, 1.48, 2.36, C_BOIS)                                                           # porte vitrée en bois
    zB.rect(0.98, 0.95, 1.38, 2.22, (56, 62, 70), 128)
    zB.rect(0.98, 0.26, 1.38, 0.85, (138, 92, 46))
    ombre(zB, 0.80, 0.12, 1.55, 2.50, 0.14, 0.6)
    zB.rect(1.68, 0.92, 2.10, 1.52, (70, 50, 36))                                                     # vitrine à menu
    zB.rect(2.18, 1.20, 2.30, 1.40, (196, 36, 40))                                                    # plaque rouge
    zB.rect(2.18, 1.72, 2.32, 1.88, (226, 226, 222))
    zB.rect(2.40, 0.0, 3.08, 2.20, (60, 40, 30))                                                      # entrée
    zB.rect(2.46, 0.0, 3.02, 2.14, C_PORTE)
    zB.rect(2.55, 0.95, 2.93, 1.98, (48, 54, 62), 128)
    ombre(zB, 2.40, 0.0, 3.08, 2.20, 0.06, 0.45)
    zB.rect(3.16, 0.98, 3.56, 1.55, (70, 50, 36))                                                     # 2e vitrine

    # ---- murs moins vus, 32 px/m : pignon ouest du corps principal, sud, pignon ouest du corps est, salle, véranda
    def zone(nom, x0, y0, l, h, s=32, seed=9):
        z = Z[nom] = Zone(img, msk, x0, y0, int(l * s) + 1, int(h * s) + 1, s)
        enduit(img, z, seed)
        return z
    zW = zone("CW", 0, 420, CD, CF + 0.2, seed=10)               # u = b
    soubassement(zW, 0, CD); chainage(zW, 0, 0.55, CE, 1)
    baie(zW, 6.4, 3.8, 7.2, 5.2); baie(zW, 2.4, 3.8, 3.2, 5.2)
    zS = zone("CS", 340, 420, LC, CE + 0.2, seed=11)             # u = A1 - a (vue du sud)
    for u in (2.5, 6.5, 10.5):
        baie(zS, u, 3.9, u + 0.8, 5.2)
    zAW = zone("AW", 780, 420, AD - BA, AF + 0.2, seed=12)        # pignon ouest du corps est (au-dessus du toit voisin)
    zAS = zone("AS", 1020, 420, LA, AE + 0.2, seed=13)
    baie(zAS, 1.3, 4.3, 2.1, 5.6)
    L_SALLE = 2 * (SALLE["b1"] - SALLE["b0"]) + (SALLE["a1"] - SALLE["ea0"]) + 4
    zH = zone("H", 0, 740, L_SALLE, SALLE["h"] + 0.2, seed=14)
    soubassement(zH, 0, L_SALLE)
    for u in np.arange(2.0, L_SALLE - 2, 4.5):
        baie(zH, u, 0.9, u + 1.0, 2.3)
    # véranda : vitrages (intérieur deviné : tables nappées, chaises), montants gris
    LV = 2 * (VER["b1"] - VER["b0"]) + (VER["a1"] - VER["a0"])
    zV = Z["V"] = Zone(img, msk, 0, 880, int(LV * 40) + 1, int(VER["h"] * 40) + 1, 40)
    zV.rect(0, 0, LV, VER["h"], (40, 42, 46))
    zV.rect(0, 0, LV, 0.8, (96, 98, 102))
    for u in np.arange(0.4, LV - 0.6, 1.6):
        zV.rect(u, 0.55, u + 0.9, 0.78, (238, 238, 232))          # nappes
        zV.rect(u + 0.1, 0.0, u + 0.16, 0.55, (210, 210, 206)); zV.rect(u + 0.74, 0.0, u + 0.8, 0.55, (210, 210, 206))
        zV.rect(u - 0.2, 0.0, u - 0.05, 0.9, (66, 68, 72)); zV.rect(u + 0.95, 0.0, u + 1.1, 0.9, (66, 68, 72))
    for k in range(int(LV / 2.2) + 2):
        zV.rect(k * 2.2 - 0.05, 0, k * 2.2 + 0.05, VER["h"], C_GRIS)
    zV.rect(0, VER["h"] - 0.3, LV, VER["h"], C_GRIS)
    zV.m.rectangle([0, 880, int(LV * 40), 880 + int(VER["h"] * 40)], fill=128)

    # ---- toits : tuiles (40 px/m)
    Z["TC"] = Zone(img, msk, 0, 1010, 600, 240, 40); tuiles(img, (0, 1010, 600, 1250), 21)
    Z["TA"] = Zone(img, msk, 610, 1010, 160, 240, 40); tuiles(img, (610, 1010, 770, 1250), 22)
    Z["TB"] = Zone(img, msk, 780, 1010, 160, 100, 40); tuiles(img, (780, 1010, 940, 1110), 23)

    # ---- décors en haute définition (aplats à 1 cm du mur)
    d = ImageDraw.Draw(img)
    # lettres « Le Rochefestin » : lettres découpées gris-bleu clair, ombre portée
    Z["NOM"] = Zone(img, msk, 0, 1260, 640, 100, 256)
    d.rectangle((0, 1260, 640, 1360), fill=C_MUR); bruit(img, (0, 1260, 640, 1360), 5, seed=30)
    texte(img, (14, 1278, 634, 1350), NOM, F_SANS, (90, 40, 36))
    texte(img, (8, 1270, 628, 1342), NOM, F_SANS, (226, 232, 240))
    # enseigne carrée « F. » (parodie du logo « R. ») et plaque « Cosy · Trad · Festin »
    Z["LOGO"] = Zone(img, msk, 650, 1260, 280, 240, 200)
    d.rectangle((650, 1260, 930, 1500), fill=(40, 36, 38))
    d.rectangle((656, 1266, 924, 1494), fill=(246, 244, 240))
    d.rectangle((716, 1300, 870, 1454), outline=(50, 50, 54), width=3)
    texte(img, (730, 1306, 856, 1446), "F", F_SERIF, (40, 40, 44))
    d.ellipse((862, 1420, 878, 1436), fill=(196, 36, 40))
    griffonnage(img, (672, 1300, 704, 1450), 6, 31)
    Z["PLAQUE"] = Zone(img, msk, 940, 1260, 280, 56, 200)
    d.rectangle((940, 1260, 1220, 1316), fill=(40, 36, 38))
    d.rectangle((944, 1264, 1216, 1312), fill=(246, 244, 240))
    texte(img, (950, 1268, 1210, 1308), "Cosy · Trad · Festin", F_SANS, (40, 40, 44))
    # affichettes (titres lisibles) : menu, carte, horaires sur la porte, plaque rouge
    Z["MENU"] = Zone(img, msk, 1230, 1260, 168, 240, 400)
    affiche(img, (1230, 1260, 1398, 1500), "MENU", 32, cadre=(70, 50, 36))
    Z["CARTE"] = Zone(img, msk, 1408, 1260, 160, 228, 400)
    affiche(img, (1408, 1260, 1568, 1488), "LA CARTE", 33, cadre=(70, 50, 36))
    Z["HOR"] = Zone(img, msk, 1578, 1260, 120, 160, 400)
    affiche(img, (1578, 1260, 1698, 1420), "HORAIRES", 34)
    Z["ROUGE"] = Zone(img, msk, 1708, 1260, 48, 80, 400)
    d.rectangle((1708, 1260, 1756, 1340), fill=(196, 36, 40))
    texte(img, (1712, 1266, 1752, 1286), "R", F_SANS, (250, 240, 230))
    griffonnage(img, (1712, 1292, 1752, 1334), 3, 35)

    # ---- teintes unies (petits volumes)
    unis = dict(bois=(120, 78, 44), fer=(58, 60, 62), zinc=(150, 150, 146), blanc=(226, 226, 222),
                gris=C_GRIS, beton=(176, 172, 164), poubelle=(56, 60, 64), toit_plat=(110, 110, 106),
                rive=(222, 218, 210), mur=C_MUR, sombre=(30, 30, 32), lampe=(214, 218, 222))
    for k, (nom, c) in enumerate(unis.items()):
        x0, y0 = (k % 16) * 64, 1520 + (k // 16) * 64
        d.rectangle((x0, y0, x0 + 63, y0 + 63), fill=c)
        bruit(img, (x0, y0, x0 + 64, y0 + 64), 4, seed=40 + k)
        Z["u_" + nom] = Zone(img, msk, x0 + 8, y0 + 8, 48, 48, 48)
    return Image.merge("RGBA", (*img.split(), msk)), Z


# ---------------------------------------------------------------- géométrie
MUR, TOIT, PETIT = BB.MUR, BB.TOIT, BB.PETIT
BAS = -2.0           # murs prolongés sous le sol (le terrain descend vers l'ouest)
V0 = 0.02


def mur(M, z, p0, p1, y0, y1, u0, u1, v0=None):
    """Mur plat de p0 à p1 (a, b), face extérieure à droite du sens de marche ; u0 -> u1 dans la zone."""
    for (ya, yb, va, vb) in ((BAS, y0, V0, V0), (y0, y1, y0 if v0 is None else v0, y1 if v0 is None else v0 + y1 - y0)):
        if yb <= ya:
            continue
        M.quad([(p0[0], p0[1], ya), (p1[0], p1[1], ya), (p1[0], p1[1], yb), (p0[0], p0[1], yb)],
               [z.uv(u0, va), z.uv(u1, va), z.uv(u1, vb), z.uv(u0, vb)], MUR)


def toit2pans(M, Z, zt, a0, a1, b0, b1, eg, fa, deb=0.45, debp=0.3, pignon_est=True, pignon_ouest=True):
    """Toit à deux pans, faîtage parallèle à la rue (le long de a), débords, rives, gouttières, faîtière."""
    br = (b0 + b1) / 2
    pente = (fa - eg) / (br - b0)
    yb = eg - deb * pente
    ep = 0.15
    lp = math.hypot(br - b0 + deb, fa - yb)
    e0, e1 = a0 - (debp if pignon_est else 0), a1 + (debp if pignon_ouest else 0)
    so = Z["u_rive"]
    for (bb, sg) in ((b0 - deb, 1), (b1 + deb, -1)):
        M.quad([(e0, bb, yb + ep), (e1, bb, yb + ep), (e1, br, fa + ep), (e0, br, fa + ep)],
               [zt.uv(0, 0), zt.uv(e1 - e0, 0), zt.uv(e1 - e0, lp), zt.uv(0, lp)], TOIT)
        M.quad([(e0, br, fa), (e1, br, fa), (e1, bb, yb), (e0, bb, yb)],
               [so.uv(0, 0), so.uv(1, 0), so.uv(1, 1), so.uv(0, 1)], PETIT)
        M.quad([(e0, bb, yb), (e1, bb, yb), (e1, bb, yb + ep), (e0, bb, yb + ep)],
               [so.uv(0, 0), so.uv(1, 0), so.uv(1, 1), so.uv(0, 1)], PETIT)
        boite(M, Z, "gris", e0, e1, bb - sg * 0.13, bb, yb - 0.13, yb + 0.02)               # gouttière
    for a in ((e0,) if pignon_est else ()) + ((e1,) if pignon_ouest else ()):
        for (bb) in (b0 - deb, b1 + deb):
            M.quad([(a, bb, yb), (a, br, fa), (a, br, fa + ep), (a, bb, yb + ep)],
                   [so.uv(0, 0), so.uv(1, 0), so.uv(1, 1), so.uv(0, 1)], PETIT)
    boite(M, Z, "rive", e0, e1, br - 0.12, br + 0.12, fa + ep - 0.02, fa + ep + 0.12, TOIT)


def pignon(M, z, a, b0, b1, eg, fa, sens, u_de_b):
    """Triangle du pignon (mur a = cte) de l'égout au faîtage."""
    br = (b0 + b1) / 2
    q = [(a, b0, eg), (a, b1, eg), (a, br, fa)] if sens > 0 else [(a, b1, eg), (a, b0, eg), (a, br, fa)]
    M.tri(q, [z.uv(u_de_b(p[1]), p[2]) for p in q], MUR)


def construire(Z):
    M = Mesh()
    C = []
    zC, zCE, zA, zB = Z["C"], Z["CE"], Z["A"], Z["B"]
    LC, LA = A1 - AC, AC - A0
    # ---- corps principal (C) : façade nord, mur est au-dessus des briques, pignon ouest, façade sud
    mur(M, zC, (AC, 0), (A1, 0), 0.0, CE, 0, LC)
    M.quad([(AC, BA, HB), (AC, 0, HB), (AC, 0, CE), (AC, BA, CE)],
           [zCE.uv(0, HB), zCE.uv(BA, HB), zCE.uv(BA, CE), zCE.uv(0, CE)], MUR)
    zW = Z["CW"]
    mur(M, zW, (A1, 0), (A1, CD), 0.0, CE, 0, CD)
    pignon(M, zW, A1, 0, CD, CE, CF, 1, lambda b: b)
    zS = Z["CS"]
    mur(M, zS, (A1, CD), (AC, CD), SALLE["h"] - 0.1, CE, 0, LC, v0=SALLE["h"] - 0.1)
    toit2pans(M, Z, Z["TC"], AC, A1, 0, CD, CE, CF, pignon_est=False)
    C.append((AC, A1, 0, CD, BAS, CE))
    # pignon est du corps principal, au-dessus du toit du corps est : caché (le corps est est plus haut)
    # ---- corps est (A), plus haut, en retrait de BA
    mur(M, zA, (A0, BA), (AC, BA), HB, AE, 0, LA, v0=HB)
    zAW = Z["AW"]
    M.quad([(AC, BA, CE - 0.3), (AC, AD, CE - 0.3), (AC, AD, AE), (AC, BA, AE)],
           [zAW.uv(0, CE - 0.3), zAW.uv(AD - BA, CE - 0.3), zAW.uv(AD - BA, AE), zAW.uv(0, AE)], MUR)
    pignon(M, zAW, AC, BA, AD, AE, AF, 1, lambda b: b - BA)
    zAS = Z["AS"]
    mur(M, zAS, (AC, AD), (A0, AD), SALLE["h"] - 0.1, AE, 0, LA, v0=SALLE["h"] - 0.1)
    toit2pans(M, Z, Z["TA"], A0, AC, BA, AD, AE, AF, deb=0.4, pignon_est=False, pignon_ouest=False)
    C.append((A0, AC, BA, AD, BAS, AE))
    # ---- rez-de-chaussée en briques devant le corps est, toit en appentis de tuiles (porche) qui déborde sur la rue
    mur(M, zB, (A0, 0), (AC, 0), 0.0, HB, 0, LA)
    C.append((A0, AC, 0, BA, BAS, HB))
    tb = Z["TB"]
    bd = -0.75                                  # débord du porche
    yb, yh = HB - 0.25, HB + 0.55
    M.quad([(A0, bd, yb + 0.1), (AC + 0.1, bd, yb + 0.1), (AC + 0.1, BA, yh + 0.1), (A0, BA, yh + 0.1)],
           [tb.uv(0, 0), tb.uv(LA + 0.1, 0), tb.uv(LA + 0.1, 2.4), tb.uv(0, 2.4)], TOIT)
    so = Z["u_bois"]
    M.quad([(A0, BA, yh), (AC + 0.1, BA, yh), (AC + 0.1, bd, yb), (A0, bd, yb)],
           [so.uv(0, 0), so.uv(1, 0), so.uv(1, 1), so.uv(0, 1)], PETIT)
    boite(M, Z, "bois", A0, AC + 0.1, bd - 0.04, bd + 0.04, yb - 0.18, yb + 0.1)          # planche de rive
    boite(M, Z, "bois", AC + 0.02, AC + 0.1, bd, 0, yb - 0.1, yb + 0.1)                   # retour ouest
    # poteau et jambe de force en bois devant le renfoncement de la porte
    boite(M, Z, "bois", A0 + 0.72, A0 + 0.86, -0.07, 0.07, 0.0, yb)
    barre(M, Z, "bois", (A0 + 0.79, -0.02, 1.4), (A0 + 0.79, bd + 0.1, yb - 0.1), 0.1)
    boite(M, Z, "beton", A0 + 0.75, A0 + 1.6, -0.45, 0.0, -0.3, 0.16)                      # marche
    boite(M, Z, "poubelle", AC + 0.1, AC + 0.6, -0.6, -0.12, 0.0, 1.0)
    # ---- appliques (cubes blancs) sur la façade nord, à 3,2 m
    for a in (AC + 4.5, AC + 8.0, AC + 12.4):
        boite(M, Z, "lampe", a - 0.12, a + 0.12, -0.18, 0.0, 3.1, 3.34, dessous=True)
    # ---- décors en aplat
    def decal(nom, face, u0, u1, v0, v1, e=0.012):
        z = Z[nom]
        w, hh = z.w / z.s, z.h / z.s
        uv = [z.uv(0, 0), z.uv(w, 0), z.uv(w, hh), z.uv(0, hh)]
        if face == "N":
            M.quad([(u0, -e, v0), (u1, -e, v0), (u1, -e, v1), (u0, -e, v1)], uv, PETIT)
        else:                 # mur est du corps principal (a = AC, face à l'est), u = b depuis la rue
            M.quad([(AC - e, u1, v0), (AC - e, u0, v0), (AC - e, u0, v1), (AC - e, u1, v1)], uv, PETIT)
    decal("NOM", "N", AC + 5.0, AC + 8.0, 2.95, 3.42)
    decal("LOGO", "E", 0.18, 1.48, 4.35, 5.55)
    decal("PLAQUE", "E", 0.18, 1.48, 3.95, 4.21)
    decal("MENU", "N", A0 + 1.70, A0 + 2.08, 0.96, 1.50)
    decal("CARTE", "N", A0 + 3.18, A0 + 3.54, 1.00, 1.52)
    decal("HOR", "N", A0 + 2.62, A0 + 2.86, 1.25, 1.57, e=0.014)
    decal("ROUGE", "N", A0 + 2.18, A0 + 2.30, 1.20, 1.40)
    # ---- salle arrière (toit plat), avec l'aile est derrière la boulangerie
    zH = Z["H"]
    s = SALLE
    pts = [(s["a1"], s["b0"]), (s["a1"], s["b1"]), (s["ea0"], s["b1"]), (s["ea0"], s["eb0"]), (A0, s["eb0"])]
    u = 0.0
    for p0, p1 in zip(pts, pts[1:]):
        l = math.hypot(p1[0] - p0[0], p1[1] - p0[1])
        mur(M, zH, p0, p1, 0.0, s["h"], u, u + l)
        u += l
    tp = Z["u_toit_plat"]
    for (a0, a1, b0, b1) in ((A0, s["a1"], s["b0"], s["b1"]), (s["ea0"], A0, s["eb0"], s["b1"])):
        M.quad([(a0, b0, s["h"]), (a0, b1, s["h"]), (a1, b1, s["h"]), (a1, b0, s["h"])],
               [tp.uv(0, 0), tp.uv(1, 0), tp.uv(1, 1), tp.uv(0, 1)], PETIT)
        boite(M, Z, "rive", a0 - 0.05, a1 + 0.05, b1 - 0.05, b1 + 0.05, s["h"] - 0.05, s["h"] + 0.15)
        C.append((a0, a1, b0, b1, BAS, s["h"]))
    boite(M, Z, "rive", s["a1"] - 0.05, s["a1"] + 0.05, s["b0"], s["b1"], s["h"] - 0.05, s["h"] + 0.15)
    # ---- véranda (pergola grise, vitrages peints)
    v = VER
    zV = Z["V"]
    pts = [(v["a1"], v["b0"]), (v["a1"], v["b1"]), (v["a0"], v["b1"]), (v["a0"], v["b0"])]
    u = 0.0
    for p0, p1 in zip(pts, pts[1:]):
        l = math.hypot(p1[0] - p0[0], p1[1] - p0[1])
        M.quad([(p0[0], p0[1], 0.0), (p1[0], p1[1], 0.0), (p1[0], p1[1], v["h"]), (p0[0], p0[1], v["h"])],
               [zV.uv(u, 0), zV.uv(u + l, 0), zV.uv(u + l, v["h"]), zV.uv(u, v["h"])], PETIT)
        u += l
    boite(M, Z, "gris", v["a0"] - 0.1, v["a1"] + 0.1, v["b0"], v["b1"] + 0.1, v["h"], v["h"] + 0.25)
    C.append((v["a0"], v["a1"], v["b0"], v["b1"], BAS, v["h"]))
    return M, C


def main():
    atlas, Z = peindre()
    os.makedirs(OUT_A, exist_ok=True)
    atlas.save(os.path.join(OUT_A, "restaurant.png"))
    M, C = construire(Z)
    prim = ("facade", np.array(M.P), np.array(M.N), np.array(M.UV), np.array(M.I, np.uint32), np.array(M.C))
    write_glb(os.path.join(OUT_A, "restaurant.glb"), {"restaurant": [prim]}, fix_winding=False)
    lacet = math.atan2(-BB.W_[1], BB.W_[0])
    boites = []
    for (a0, a1, b0, b1, y0, y1) in C:
        cx, cy, cz = loc((a0 + a1) / 2, (b0 + b1) / 2, (y0 + y1) / 2)
        boites.append([round(x, 3) for x in (cx, cy, cz, abs(a1 - a0) / 2, abs(y1 - y0) / 2, abs(b1 - b0) / 2, lacet)])
    p = os.path.join(GOD, "world", "sur_mesure.json")
    pose = json.load(open(p)) if os.path.exists(p) else {}
    pose["restaurant"] = {"boites": boites, "glb": "res://assets/sur_mesure/restaurant.glb",
                          "atlas": "res://assets/sur_mesure/restaurant.png", "pos": [BB.NE[0], 450.30, BB.NE[1]],
                          "remplace_bati": ["BATIMENT0000000301133202"], "remplace_commerce": ["n3646424190"],
                          "nom": NOM + " (restaurant Le Rochetoirin)"}
    json.dump(pose, open(p, "w"), indent=1, ensure_ascii=False)
    print("restaurant : %d sommets, %d triangles, %d boîtes de collision" % (len(M.P), len(M.I) // 3, len(C)))


if __name__ == "__main__":
    main()
