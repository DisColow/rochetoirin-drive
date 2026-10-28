"""Vues cockpit en pixel art des voitures du garage (#95 ; le pick-up de départ garde build_cockpit.py), même procédé
que build_cockpit.py (Test Drive, Vette!, Lotus : 480 pixels de large, palettes restreintes, ombrage tramé, contours
d'un pixel) et mêmes calques, mêmes repères pour scripts/cockpit.gd :
  dash.png (480 × 100), glow.png (ce qui s'éclaire la nuit), glass.png (reflets des cadrans), top.png (480 × 40 :
  pavillon, pare-soleil, rétroviseur), wheel.png (160 × 160), pillar.png (montants), pine.png, meta.json.
Chaque voiture a son habitacle, d'après le vrai (couleurs, compteurs, volant, autoradio ou GPS, aérateurs…) :
  - Citrouille Deuche : planche en tôle peinte, petit compteur à gauche, volant à une branche, levier « parapluie » ;
  - Renaud Cinq : bloc compteur rectangulaire, deux cadrans, autoradio à cassette ;
  - Renaud Tango : pas de compteur derrière le volant, afficheur numérique au milieu de la planche, aérateurs ronds ;
  - Pijo 106, 206 : casquette arrondie, cadrans blancs (206) ou noirs, autoradio ;
  - Renaud Clia : combiné à deux cadrans et afficheur central ;
  - Renaud Espèce : compteur numérique au centre de la planche, écran GPS escamotable ;
  - Renaud Lagune : deux cadrans, écran GPS au centre, lecteur de carte-clé ;
  - Pijo 306 Maxi : planche de course nue, afficheur de course, interrupteurs à bascule, arceau ;
  - Porc'Che 119 GT3 RS : cinq cadrans (compte-tours jaune au centre), alcantara, arceau, écran GPS ;
  - autobus B1 de la ligne de bus (#148) : planche grise, compteur et manomètre, grand volant à deux branches.
Les voitures sans GPS n'ont pas d'écran : la mini-carte reste affichée (hud.gd).
Sorties : ../godot/assets/cockpit/<id>/ ; aperçu : python3 build_cockpits.py --apercu <capture du jeu>."""
import json, math, os, sys
import numpy as np
from PIL import Image
import build_cockpit as B
from build_cockpit import Canvas, BAYER

W = 480
BASE = "../godot/assets/cockpit"


def rampe(c0, c1, n=10, chaud=(1.06, 1.0, 0.92), froid=(0.92, 0.95, 1.08)):
    """Palette de n teintes du sombre au clair : ombres tirées vers le bleu, lumières vers le chaud."""
    out = []
    for k in range(n):
        t = k / (n - 1)
        col = [c0[i] + (c1[i] - c0[i]) * t for i in range(3)]
        tint = [froid[i] + (chaud[i] - froid[i]) * t for i in range(3)]
        out.append(tuple(int(np.clip(col[i] * tint[i], 0, 255)) for i in range(3)))
    return out


def hx(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))


# ================================================================ fiches des habitacles
# planche : (sombre, clair) ; dessus : couleur du dessus de planche ; casquette : (x0, x1, haut) ou None ;
# cadrans : [(nom, cx, cy, r, fond, graduations)] ; numerique : (x, y, l, h) afficheur de vitesse ;
# centre : "gps" | "radio" | "k7" | "course" | None ; volant : (branches, rampe, repère, logo) ;
# pavillon : (sombre, clair) ; arceau : bool ; boite : "manuelle" | "auto"
STYLES = {
    "deuche": dict(planche=(hx("#3a0d0e"), hx("#c23a32")), dessus=(hx("#1a1a1e"), hx("#6a6a70")), casquette=None,
                   cadrans=[("speed", 120, 46, 13, "creme", 120)], numerique=None, centre=None, vide_poche=True,
                   aerateurs=[], volant=(1, (hx("#101012"), hx("#6c6a68")), None, "citrouille"), rayon=72, epaisseur=6,
                   pavillon=(hx("#6d6a63"), hx("#e3ddcc")), toile=True, arceau=False, boite="manuelle", parapluie=True,
                   portes=(hx("#2a2a2e"), hx("#8a8a90"))),
    "r5": dict(planche=(hx("#0a0908"), hx("#5a4a3c")), dessus=(hx("#0c0b0a"), hx("#4e4238")), casquette=(170, 310, 6, "rect"),
               cadrans=[("speed", 214, 42, 16, "noir", 160), ("rpm", 266, 42, 16, "noir", 7000)], numerique=None,
               centre="k7", aerateurs=[(96, 36, 124, 50, "rect"), (356, 36, 384, 50, "rect")],
               volant=(2, (hx("#070707"), hx("#585550")), None, "renaud"), rayon=74, epaisseur=8,
               pavillon=(hx("#4d4338"), hx("#c9b89a")), arceau=False, boite="manuelle", portes=(hx("#1d1813"), hx("#6e5a46"))),
    "twingo": dict(planche=(hx("#0b1010"), hx("#5b6d68")), dessus=(hx("#1f3a39"), hx("#4fa59a")), casquette=None,
                   cadrans=[], numerique=(214, 20, 52, 14), centre="radio",
                   aerateurs=[(80, 40, 104, 64, "rond"), (376, 40, 400, 64, "rond"), (300, 46, 318, 64, "rond")],
                   volant=(3, (hx("#0b0b0d"), hx("#5d5f63")), None, "renaud"), rayon=72, epaisseur=8,
                   pavillon=(hx("#4a4c52"), hx("#c8cad0")), arceau=False, boite="manuelle", portes=(hx("#173230"), hx("#5bb0a4")),
                   tissu=(hx("#2a2350"), hx("#e05a9a"))),
    "p106": dict(planche=(hx("#08080a"), hx("#55565c")), dessus=(hx("#0a0a0c"), hx("#4a4b50")), casquette=(176, 304, 4, "rond"),
                 cadrans=[("speed", 216, 42, 17, "noir", 200), ("rpm", 264, 42, 17, "noir", 7000)], numerique=None,
                 centre="radio", aerateurs=[(92, 34, 118, 52, "rect"), (330, 30, 350, 46, "rect"), (362, 30, 382, 46, "rect")],
                 volant=(4, (hx("#060607"), hx("#55565b")), None, "pijo"), rayon=74, epaisseur=8,
                 pavillon=(hx("#4a4a50"), hx("#b9b9c0")), arceau=False, boite="manuelle", portes=(hx("#121214"), hx("#5a5b61"))),
    "clio": dict(planche=(hx("#0c0d12"), hx("#5f6475")), dessus=(hx("#0e0f14"), hx("#525768")), casquette=(172, 308, 5, "rond"),
                 cadrans=[("speed", 210, 42, 17, "noir", 200), ("rpm", 270, 42, 15, "noir", 7000)], numerique=(232, 52, 16, 6),
                 centre="radio", aerateurs=[(94, 32, 120, 50, "rond"), (322, 24, 346, 38, "rect"), (356, 24, 380, 38, "rect")],
                 volant=(3, (hx("#09090c"), hx("#5d6070")), None, "renaud"), rayon=74, epaisseur=9,
                 pavillon=(hx("#545866"), hx("#c7cad6")), arceau=False, boite="manuelle", portes=(hx("#15171f"), hx("#5d6478"))),
    "espace": dict(planche=(hx("#0e0e10"), hx("#6c6c72")), dessus=(hx("#121214"), hx("#5d5d64")), casquette=None,
                   cadrans=[], numerique=(214, 16, 52, 16), centre="gps", gps=(314, 24, 48, 34),
                   aerateurs=[(84, 36, 110, 56, "rect"), (370, 36, 396, 56, "rect")],
                   volant=(4, (hx("#0b0b0d"), hx("#5f5f66")), None, "renaud"), rayon=74, epaisseur=9,
                   pavillon=(hx("#5c5a56"), hx("#d2cfc6")), arceau=False, boite="auto", portes=(hx("#1a1a1d"), hx("#76767c"))),
    "p206": dict(planche=(hx("#0b0b0e"), hx("#5a5b63")), dessus=(hx("#0c0c0f"), hx("#4c4d55")), casquette=(170, 310, 6, "rond"),
                 cadrans=[("speed", 210, 42, 17, "blanc", 220), ("rpm", 270, 42, 17, "blanc", 7000)], numerique=None,
                 centre="radio", aerateurs=[(92, 32, 118, 50, "rond"), (330, 26, 350, 42, "rond"), (362, 26, 382, 42, "rond")],
                 volant=(4, (hx("#07070a"), hx("#56575e")), None, "pijo"), rayon=74, epaisseur=9,
                 pavillon=(hx("#4f4f56"), hx("#c3c3ca")), arceau=False, boite="manuelle", portes=(hx("#141418"), hx("#60616a"))),
    "laguna": dict(planche=(hx("#141416"), hx("#7a7a80")), dessus=(hx("#141416"), hx("#5e5e64")), casquette=(172, 308, 6, "rond"),
                   cadrans=[("speed", 212, 42, 18, "noir", 240), ("rpm", 268, 42, 18, "noir", 7000)], numerique=None,
                   centre="gps", gps=(316, 20, 46, 32), carte=True,
                   aerateurs=[(90, 32, 116, 50, "rect"), (322, 56, 342, 70, "rect"), (336, 56, 356, 70, "rect")],
                   volant=(4, (hx("#0d0d0f"), hx("#66666c")), None, "renaud"), rayon=74, epaisseur=9,
                   pavillon=(hx("#5e5b54"), hx("#d6d1c4")), arceau=False, boite="manuelle", portes=(hx("#1d1d20"), hx("#7c7c82"))),
    "p306": dict(planche=(hx("#060607"), hx("#3b3c42")), dessus=(hx("#060607"), hx("#2e2f34")), casquette=None,
                 cadrans=[], numerique=(206, 22, 68, 22), centre="course",
                 aerateurs=[], volant=(3, (hx("#0d0d10"), hx("#3d3f47")), (255, 210, 0), "pijo"), rayon=66, epaisseur=10,
                 pavillon=(hx("#121214"), hx("#4a4a50")), arceau=True, boite="manuelle", portes=(hx("#0b0b0d"), hx("#3e3f45")),
                 baquet=True),
    "gt3": dict(planche=(hx("#060607"), hx("#3e3e44")), dessus=(hx("#070708"), hx("#38383e")), casquette=(160, 320, 4, "rond"),
                cadrans=[("rpm", 240, 40, 22, "noir_jaune", 9000), ("speed", 196, 46, 14, "noir", 320), ("temp", 162, 52, 9, "noir", 0),
                         ("oil", 284, 46, 14, "noir", 0), ("fuel", 318, 52, 9, "noir", 0)], numerique=(230, 50, 20, 6),
                centre="gps", gps=(356, 30, 44, 28),
                aerateurs=[(96, 34, 122, 48, "rect"), (410, 34, 436, 48, "rect")],
                volant=(3, (hx("#09090b"), hx("#4a4a50")), (250, 205, 30), "porcche"), rayon=70, epaisseur=10,
                pavillon=(hx("#0c0c0e"), hx("#3e3e44")), arceau=True, boite="auto", portes=(hx("#0b0b0d"), hx("#45454c"))),
    # autobus de la ligne (#148) : grande planche grise plate, compteur et manomètre d'air, grand volant presque à plat
    "bus": dict(planche=(hx("#1a1c20"), hx("#7c8088")), dessus=(hx("#202226"), hx("#62666e")), casquette=(168, 312, 8, "rect"),
                cadrans=[("speed", 214, 44, 18, "noir", 100), ("rpm", 266, 44, 18, "noir", 3000)], numerique=None,
                centre="radio", aerateurs=[(60, 40, 96, 54, "rect"), (384, 40, 420, 54, "rect")],
                volant=(2, (hx("#0c0c0e"), hx("#4a4c52")), None, None), rayon=82, epaisseur=9,
                pavillon=(hx("#6a6c70"), hx("#d8dadc")), arceau=False, boite="auto", portes=(hx("#2c2e33"), hx("#8a8e96"))),
}
FONDS = {"noir": ((10, 10, 12), (235, 238, 242), (255, 110, 40)), "blanc": ((228, 228, 222), (20, 20, 24), (230, 60, 30)),
         "creme": ((222, 214, 190), (30, 26, 20), (200, 40, 30)), "noir_jaune": ((250, 205, 40), (10, 10, 12), (220, 30, 20))}


# ================================================================ planche de bord
def planche(st):
    c = Canvas(W, 100); g = Canvas(W, 100)
    R = rampe(*st["planche"]); RD = rampe(*st["dessus"])
    top_y = 13 + 3 * ((c.xx - 240) / 240) ** 2
    edge_y = 27 + 4 * ((c.xx - 240) / 240) ** 2
    face = c.yy >= edge_y
    h = -((c.yy - edge_y) / 70.0) ** 2 * 24 + 2 * np.sin(c.xx / 37.0)
    c.shade(face, h, R, amb=0.25, bias=-0.02, grain=0.02 if not st.get("vide_poche") else 0.008)
    topm = (c.yy >= top_y) & (c.yy < edge_y)
    c.shade(topm, -(c.yy - top_y) * 0.6, RD, amb=0.5, bias=0.12, grain=0.018)
    c.flat((c.yy >= edge_y) & (c.yy < edge_y + 1.5), RD[0])
    if st.get("vide_poche"):
        # 2 CV : planche en tôle peinte, vide-poche sur toute la largeur (ouverture sombre, rebord tubulaire)
        vp = (c.yy >= edge_y + 18) & (c.yy < edge_y + 30) & (c.xx > 40) & (c.xx < 440)
        c.flat(vp, (12, 12, 14))
        lip = (np.abs(c.yy - (edge_y + 17)) < 1.5) & (c.xx > 40) & (c.xx < 440)
        c.shade(lip, c.bevel(lip, 1.5), "chrome", amb=0.35, scale=1.3)
    if st.get("tissu"):
        # Twingo : bande de tissu coloré sur la face de la planche
        T = rampe(*st["tissu"])
        band = face & (c.yy >= edge_y + 30) & (c.yy < edge_y + 44) & (c.xx > 120) & (c.xx < 450)
        pat = 0.45 + 0.35 * (((c.xx // 3).astype(int) + (c.yy // 3).astype(int)) % 3 == 0) + 0.1 * np.sin(c.xx * 0.3)
        c.fill(band, pat, T)
    # ------------------------------------------------ casquette et combiné
    if st["casquette"]:
        x0, x1, hh, forme = st["casquette"]
        hood = c.rrect(x0, hh, x1, 34, 10 if forme == "rond" else 3)
        c.shade(hood, c.bevel(hood, 6), R, amb=0.3, bias=0.04, grain=0.02, scale=1.2)
        c.outline(hood, R[0])
        bez = c.rrect(x0 + 6, hh + 10, x1 - 6, 70, 5 if forme == "rond" else 2)
        c.shade(bez, c.bevel(bez, 3), R, amb=0.3, bias=0.02, spec=0.5, scale=1.3)
        cav = c.rrect(x0 + 9, hh + 13, x1 - 9, 67, 4 if forme == "rond" else 1)
        c.flat(cav, (8, 8, 10)); g.flat(cav, (4, 4, 6))
    for (nom, cx, cy, r, fond, maxi) in st["cadrans"]:
        cadran(c, g, nom, cx, cy, r, fond, maxi)
    if st["numerique"]:
        x, y, w, hh = st["numerique"]
        fr = c.rrect(x - 3, y - 3, x + w + 3, y + hh + 3, 2)
        c.shade(fr, c.bevel(fr, 2), R, amb=0.35, bias=0.06, spec=0.5, scale=1.4)
        c.outline(fr, R[0])
        lcd = c.rect(x, y, x + w, y + hh)
        course = st["centre"] == "course"
        c.flat(lcd, (10, 14, 10) if not course else (6, 8, 14))
        g.flat(lcd, (6, 10, 8) if not course else (4, 6, 10))
        if course:
            # afficheur de course : barre de régime à diodes en haut, rapport au milieu
            for k in range(12):
                col = (40, 200, 60) if k < 7 else ((240, 200, 30) if k < 10 else (240, 50, 30))
                c.flat(c.rect(x + 3 + k * 5, y + 2, x + 6 + k * 5, y + 4), tuple(v // 4 for v in col))
                g.flat(c.rect(x + 3 + k * 5, y + 2, x + 6 + k * 5, y + 4), tuple(v // 3 for v in col))
    # ------------------------------------------------ centre : autoradio, GPS, course
    centre = st["centre"]
    meta = {}
    if centre in ("radio", "k7"):
        rx, ry = 316, 46
        fr = c.rrect(rx - 4, ry - 4, rx + 52, ry + 16, 2)
        c.shade(fr, c.bevel(fr, 2), R, amb=0.3, bias=0.04, scale=1.3); c.outline(fr, R[0])
        face_r = c.rect(rx - 1, ry - 1, rx + 49, ry + 13)
        c.shade(face_r, c.bevel(face_r, 1.5), "black", amb=0.35, bias=0.06, spec=0.4)
        c.flat(c.rect(rx + 2, ry + 1, rx + 32, ry + 8), (8, 18, 10)); g.flat(c.rect(rx + 2, ry + 1, rx + 32, ry + 8), (4, 12, 6))
        if centre == "k7":
            c.flat(c.rect(rx + 4, ry + 9, rx + 44, ry + 12), (4, 4, 5))       # fente de la cassette
        for k in range(4):
            b = c.rect(rx + 35 + (k % 2) * 6, ry + 1 + (k // 2) * 6, rx + 39 + (k % 2) * 6, ry + 5 + (k // 2) * 6)
            c.shade(b, c.bevel(b, 1), "black", amb=0.5, bias=0.14)
        for kx in (rx + 4, rx + 44):
            k_ = c.disc(kx + 0.5, ry + 10.5, 2.4)
            c.shade(k_, c.bevel(k_, 2), "chrome", amb=0.35, scale=1.3)
        meta["lcd"] = [rx + 1, ry + 1, 30, 7]
    elif centre == "gps":
        gx, gy, gw, gh = st["gps"]
        fr = c.rrect(gx - 3, gy - 3, gx + gw + 3, gy + gh + 3, 3)
        c.shade(fr, c.bevel(fr, 2), "black", amb=0.35, bias=0.06, spec=0.7, scale=1.4); c.outline(fr, (4, 4, 6))
        c.flat(c.rect(gx, gy, gx + gw, gy + gh), (10, 16, 26)); g.flat(c.rect(gx, gy, gx + gw, gy + gh), (10, 16, 26))
        meta["screen_map"] = [gx, gy, gw, gh]
        meta["lcd"] = [gx, gy + gh + 5, 30, 7]
        c.flat(c.rect(gx, gy + gh + 5, gx + 30, gy + gh + 12), (8, 18, 10))
    elif centre == "course":
        # panneau d'interrupteurs à bascule (allumage, démarreur, essuie-glace, pompe, ventilateur), coupe-circuit rouge
        p = c.rrect(300, 46, 384, 74, 2)
        c.shade(p, c.bevel(p, 2), "magnesium", amb=0.35, bias=0.0, scale=1.2); c.outline(p, (10, 10, 12))
        for k in range(5):
            x = 306 + k * 15
            c.flat(c.rect(x, 52, x + 6, 62), (16, 16, 18))
            c.shade(c.rect(x + 1, 50, x + 5, 56), c.bevel(c.rect(x + 1, 50, x + 5, 56), 1.5), "chrome", amb=0.4)
            c.flat(c.rect(x, 65, x + 7, 68), (230, 230, 220))
        cc = c.disc(394.5, 60.5, 6)
        c.shade(cc, c.bevel(cc, 3), "red", amb=0.35, scale=1.3); c.outline(cc, (40, 6, 6))
        pass                               # pas d'horloge : l'afficheur de course suffit
    # ------------------------------------------------ aérateurs
    for (x0, y0, x1, y1, forme) in st["aerateurs"]:
        if forme == "rond":
            cx, cy, r = (x0 + x1) / 2, (y0 + y1) / 2, (x1 - x0) / 2
            fr = c.disc(cx, cy, r)
            c.shade(fr, c.bevel(fr, 2), "chrome" if st.get("tissu") else R, amb=0.3, bias=0.08, scale=1.4)
            c.outline(fr, (6, 6, 8))
            c.flat(c.disc(cx, cy, r - 2.5), (8, 8, 10))
            for k in range(-2, 3):
                c.fill(c.rect(x0 + 3, cy + k * 2.5, x1 - 3, cy + k * 2.5 + 1) & c.disc(cx, cy, r - 2.5), 0.45, R)
        else:
            fr = c.rrect(x0, y0, x1, y1, 2)
            c.shade(fr, c.bevel(fr, 2), R, amb=0.3, bias=0.08, scale=1.5); c.outline(fr, R[0])
            c.flat(c.rect(x0 + 2, y0 + 2, x1 - 2, y1 - 2), R[0])
            for y in range(y0 + 3, y1 - 2, 2):
                c.fill(c.rect(x0 + 2, y, x1 - 2, y + 1), 0.4, R)
    # ------------------------------------------------ levier « parapluie » de la 2 CV, sortant de la planche
    if st.get("parapluie"):
        for t in np.linspace(0, 1, 40):
            x = 300 - t * 46; y = 52 + t * 22 - 10 * math.sin(t * math.pi)
            c.flat(c.disc(x, y, 2.2), (10, 10, 12)); c.put(x - 0.5, y - 1, (90, 90, 96))
        bo = c.disc(253.5, 74.5, 5)
        c.shade(bo, c.bevel(bo, 3), "black", amb=0.3, spec=0.7, scale=1.3); c.outline(bo, (0, 0, 0))
    # ------------------------------------------------ lecteur de carte-clé (Lagune)
    if st.get("carte"):
        fr = c.rrect(296, 74, 330, 84, 2)
        c.shade(fr, c.bevel(fr, 2), R, amb=0.35, scale=1.3); c.outline(fr, R[0])
        c.flat(c.rect(300, 78, 326, 80), (4, 4, 5))
        c.flat(c.rect(304, 70, 322, 79), (230, 230, 225)); c.flat(c.rect(305, 71, 310, 74), (30, 60, 140))
    # ------------------------------------------------ boîte à gants et portières
    gb = c.rrect(390, 62, 472, 94, 4)
    if not st.get("vide_poche") and centre != "course":
        c.shade(gb, c.bevel(gb, 3) * 0.6 - ((c.yy - 62) / 32.0) ** 2 * 6, R, amb=0.22, grain=0.03, scale=1.3)
        c.outline(gb, R[0])
        c.shade(c.rect(424, 64, 440, 67), c.bevel(c.rect(424, 64, 440, 67), 1.5), "chrome" if centre != "course" else R, amb=0.35)
    P = rampe(*st["portes"])
    for (x0, x1, sgn) in ((0, 30, 1), (456, 480, -1)):
        dm = c.rect(x0, 0, x1, 100) & (c.yy > 6 + ((c.xx - x0) if sgn > 0 else (x1 - c.xx)) * 0.5)
        c.shade(dm, c.bevel(dm, 6) + (100 - c.yy) * 0.05, P, amb=0.22, grain=0.03)
        c.outline(dm, P[0])
    # ------------------------------------------------ sélecteur de boîte (lettres ou grille des vitesses)
    meta["gear"] = [336, 92]
    meta["boite"] = st["boite"]
    if st["boite"] == "auto":
        for i, ch in enumerate("PRND"):
            c.text(336 + i * 8, 92, ch, (120, 120, 128))
    elif not st.get("parapluie"):
        # levier de vitesses : soufflet en cuir plissé, pommeau rond (grille des vitesses gravée dessus)
        souf = c.poly([(338, 100), (366, 100), (360, 88), (344, 88)])
        c.shade(souf, c.bevel(souf, 3) + np.sin(c.yy * 1.6) * 0.8, "black", amb=0.25, grain=0.04, scale=1.2)
        c.outline(souf, (2, 2, 3))
        c.flat(c.rect(350, 80, 354, 90), (24, 24, 28)); c.put(351, 81, (90, 90, 96))
        po = c.disc(352.5, 79.5, 5.5)
        c.shade(po, c.bevel(po, 4), "black" if st.get("baquet") is None else "chrome", amb=0.3, spec=0.8, scale=1.3)
        c.outline(po, (2, 2, 3))
        for (x, y) in ((350, 77), (352, 77), (354, 77), (350, 80), (352, 80), (354, 80)):
            c.put(x, y, (150, 150, 158))
        meta["gear"] = [356, 92]
    # commodos (éclairage à gauche, essuie-glaces à droite) dépassant de part et d'autre du volant
    for (x0, x1, y) in ((158, 186, 74), (294, 322, 74)):
        tige = c.rect(x0, y - 1, x1, y + 2)
        c.shade(tige, c.bevel(tige, 1.5), R, amb=0.3, bias=0.08, spec=0.4, scale=1.4)
        c.outline(tige, R[0])
        bout = c.disc(x0 + 1.5 if x0 < 240 else x1 - 1.5, y + 0.5, 2.6)
        c.shade(bout, c.bevel(bout, 2), R, amb=0.35, bias=0.1, scale=1.3)
    # bouton des feux de détresse (sauf 2 CV)
    if not st.get("parapluie"):
        hzx = 296 if centre != "course" else 268
        hz = c.rrect(hzx, 26, hzx + 10, 32, 1)
        c.shade(hz, c.bevel(hz, 1.5), "red", amb=0.35, scale=1.3); c.outline(hz, (40, 6, 6))
        for k in range(3):
            c.put(hzx + 5 - k * 0.5, 27 + k, (255, 220, 200)); c.put(hzx + 5 + k * 0.5, 27 + k, (255, 220, 200))
    # Tango : interrupteurs de couleur sous l'autoradio
    if st.get("tissu"):
        for k, col in enumerate(((240, 200, 40), (60, 180, 90), (60, 120, 220), (230, 70, 120))):
            b = c.rrect(318 + k * 11, 66, 326 + k * 11, 72, 2)
            c.shade(b, c.bevel(b, 1.5), rampe(tuple(v // 3 for v in col), col, 6), amb=0.4, scale=1.3)
            c.outline(b, (8, 8, 10))
    # 306 Maxi : boîtier « tripmaster » du copilote (deux afficheurs rouges) sur la planche côté passager
    if centre == "course":
        tb = c.rrect(400, 50, 468, 78, 3)
        c.shade(tb, c.bevel(tb, 2), "black", amb=0.35, bias=0.05, spec=0.5, scale=1.3); c.outline(tb, (2, 2, 3))
        for y in (54, 65):
            c.flat(c.rect(406, y, 446, y + 8), (24, 4, 4)); g.flat(c.rect(406, y, 446, y + 8), (20, 3, 3))
            c.text(408, y + 2, "12.48" if y == 54 else "0.35", (200, 40, 30)); g.text(408, y + 2, "12.48" if y == 54 else "0.35", (255, 60, 40))
        for k in range(3):
            b = c.disc(455.5, 56.5 + k * 7, 2.6)
            c.shade(b, c.bevel(b, 2), "chrome", amb=0.35, scale=1.3)
    # GT3 : bande de carbone sur la planche côté passager, surpiqûres jaunes le long de l'arête
    if st.get("volant") and st["volant"][3] == "porcche":
        band = face & (c.yy >= edge_y + 8) & (c.yy < edge_y + 16) & (c.xx > 406) & (c.xx < 456)
        tw = ((((c.xx // 2) + (c.yy // 2)).astype(int) % 2) == 0)
        c.fill(band, 0.25 + 0.25 * tw, "black")
        st_ = (np.abs(c.yy - (edge_y - 2.5)) < 0.5) & ((c.xx.astype(int) % 3) != 0) & ((c.xx < 150) | (c.xx > 330))
        c.flat(st_, (230, 190, 30))
    meta["lamps"] = [[226, 64], [232, 64], [248, 64], [254, 64]]
    c.save("dash.png"); g.save("glow.png")
    # reflets sur les verres des cadrans
    gl = Canvas(W, 100)
    u = gl.xx + gl.yy * 0.8
    for (nom, cx, cy, r, fond, maxi) in st["cadrans"]:
        ins = gl.disc(cx, cy, r - 1)
        gl.flat(ins & (((u - cx - cy * 0.8) > -r * 0.7) & ((u - cx - cy * 0.8) < -r * 0.45)), (210, 220, 235), 34)
    gl.save("glass.png")
    G = {n: [cx, cy, r] for (n, cx, cy, r, f, m) in st["cadrans"]}
    meta["gauges"] = G
    meta["maxi"] = {n: m for (n, cx, cy, r, f, m) in st["cadrans"]}
    if st["numerique"]:
        meta["digital"] = list(st["numerique"])
    if centre == "course":
        meta["course"] = list(st["numerique"])
    return meta


def cadran(c, g, nom, cx, cy, r, fond, maxi):
    F, T, Z = FONDS[fond]
    bord = c.disc(cx, cy, r + 2)
    c.shade(bord, c.bevel(bord, 2), "chrome", amb=0.3, spec=0.5, scale=1.3)
    c.outline(bord, (6, 6, 8))
    f_ = c.disc(cx, cy, r)
    c.fill(f_, 0.5 + 0.15 * np.clip((cy - c.yy) / r, -1, 1), rampe(tuple(int(v * 0.75) for v in F), F, 6))
    g.flat(f_, tuple(int(v * 0.12) for v in F) if fond != "blanc" else (30, 30, 34))
    dd = np.hypot(c.xx + 0.5 - cx, c.yy + 0.5 - cy)
    ang = np.degrees(np.arctan2(c.xx + 0.5 - cx, -(c.yy + 0.5 - cy)))
    n = 10 if r > 12 else 4
    for k in range(n + 1):
        a = math.radians(-125 + 250 * k / n)
        big = k % 2 == 0
        r0 = r - (4 if big else 2.5)
        for cv, cl in ((c, T), (g, (230, 236, 255) if fond != "blanc" else (255, 240, 200))):
            cv.line(cx + math.sin(a) * r0, cy - math.cos(a) * r0, cx + math.sin(a) * (r - 1.2), cy - math.cos(a) * (r - 1.2), cl)
    if nom == "rpm" or nom == "speed":
        zr = (np.abs(dd - (r - 1.6)) < 0.8) & (ang > 75) & (ang <= 125)
        c.flat(zr, Z); g.flat(zr, Z)
    if r >= 14 and maxi:
        etiq = [(0.5, str(int(maxi / 2) if nom != "rpm" else int(maxi / 2000)))]
        for t, txt in etiq:
            a = math.radians(-125 + 250 * t)
            x = cx + math.sin(a) * (r - 8) - (len(txt) * 4 - 1) / 2; y = cy - math.cos(a) * (r - 8) - 2.5
            c.text(int(round(x)), int(round(y)), txt, T); g.text(int(round(x)), int(round(y)), txt, (220, 230, 255))


# ================================================================ pavillon (480 × 40) : ciel de toit, pare-soleil, rétro
def pavillon(st):
    c = Canvas(W, 40)
    L = rampe(*st["pavillon"])
    ly = 9 + 6 * ((c.xx - 240) / 240) ** 2
    lin = c.yy < ly
    c.shade(lin, -(c.yy) * 0.8, L, amb=0.35, bias=0.05, grain=0.025)
    if st.get("toile"):
        # 2 CV : capote en toile roulée (bourrelet) au bord du pare-brise
        c.shade(lin & (c.yy > ly - 5), c.bevel(lin & (c.yy > ly - 5), 3), L, amb=0.3, grain=0.05, scale=1.3)
    c.flat((c.yy >= ly - 1) & (c.yy < ly), L[0])
    band = (c.yy >= ly + 1.5) & (c.yy < ly + 10)
    tt = np.clip((c.yy - ly - 1.5) / 8.5, 0, 1)
    keep = band & (tt < 1.0 - BAYER[(c.yy.astype(int) % 4), (c.xx.astype(int) % 4)] * 0.9)
    c.px[keep, 0] = 22; c.px[keep, 1] = 40; c.px[keep, 2] = 56
    c.px[keep, 3] = (np.clip(110 - tt[keep] * 80, 30, 255)).astype(np.uint8)
    for (x0, y0, x1, y1, r) in ((40, 6, 192, 25, 4), (296, 7, 438, 22, 4)):
        v = c.rrect(x0, y0, x1, y1, r)
        c.shade(v, c.bevel(v, 4) + (c.yy - y0) * 0.3, L, amb=0.35, bias=0.02, grain=0.03, scale=1.2)
        c.outline(v, L[0])
    if st.get("arceau"):
        # arceau de sécurité : tube transversal au-dessus du pare-brise (gris acier, ou rouge sur la 306 de rallye)
        tube = (np.abs(c.yy - (ly + 3)) < 3)
        c.shade(tube, c.bevel(tube, 3), "chrome" if st.get("boite") == "auto" else "red", amb=0.3, spec=0.6, scale=1.3)
        c.outline(tube, (8, 8, 10))
    mx, my, mw, mh = 284, 15, 52, 15
    sx = mx + mw // 2
    c.flat(c.rect(sx - 3, 4, sx + 3, 13), L[2])
    shell = c.rrect(mx - 3, my - 3, mx + mw + 3, my + mh + 3, 4)
    c.shade(shell, c.bevel(shell, 2), "black", amb=0.35, bias=0.1, spec=0.6, scale=1.4)
    c.outline(shell, (4, 4, 6))
    c.px[c.rect(mx, my, mx + mw, my + mh)] = 0
    c.save("top.png")
    return {"mirror": [mx, my, mw, mh]}


# ================================================================ volant (160 × 160)
def volant(st):
    nb, rv, marque, logo = st["volant"]
    WR, WT = st["rayon"], st["epaisseur"]
    V = rampe(*rv)
    c = Canvas(160, 160)
    cx = cy = 80
    d = np.hypot(c.xx + 0.5 - cx, c.yy + 0.5 - cy)
    ang = np.degrees(np.arctan2(c.yy + 0.5 - cy, c.xx + 0.5 - cx))
    sp = np.zeros_like(d, dtype=bool)
    if nb == 1:
        # 2 CV : une seule branche, du moyeu vers 7 h
        sp |= c.poly([(cx - 6, cy - 2), (cx + 6, cy + 4), (cx - 42, cy + 58), (cx - 52, cy + 50)])
    if nb in (2, 4):
        for sgn in (-1, 1):
            sp |= c.poly([(cx + sgn * 14, cy - 2), (cx + sgn * (WR - 2), cy + 6), (cx + sgn * (WR - 2), cy + 14), (cx + sgn * 14, cy + 12)])
    if nb == 4:
        for sgn in (-1, 1):
            sp |= c.poly([(cx + sgn * 8, cy + 12), (cx + sgn * 18, cy + 14), (cx + sgn * 40, cy + WR - 12), (cx + sgn * 30, cy + WR - 6)])
    if nb == 3:
        for sgn in (-1, 1):
            sp |= c.poly([(cx + sgn * 16, cy - 6), (cx + sgn * (WR - 2), cy - 2), (cx + sgn * (WR - 2), cy + 10), (cx + sgn * 16, cy + 12)])
        sp |= c.poly([(cx - 8, cy + 14), (cx + 8, cy + 14), (cx + 6, cy + WR - 2), (cx - 6, cy + WR - 2)])
    hub = c.disc(cx, cy, 16 if nb != 1 else 9) if nb in (1, 3) else c.rrect(cx - 22, cy - 18, cx + 22, cy + 18, 8)
    body = (sp | hub) & (d < WR - 1)
    c.shade(body, c.bevel(body, 5), V, amb=0.3, bias=0.05, grain=0.02, scale=1.1)
    c.outline(body, V[0])
    rim = (d <= WR) & (d >= WR - WT)
    t = np.clip((d - (WR - WT / 2)) / (WT / 2), -1, 1)
    hr = np.sqrt(1 - t ** 2) * WT / 2
    c.shade(rim, hr, V, amb=0.25, bias=0.08, spec=0.8, grain=0.03, scale=1.0)
    c.outline(rim, V[0])
    if marque:
        m = rim & (np.abs(ang + 90) < 4)
        c.flat(m, marque)
    shine = (np.abs(d - (WR - 2)) < 0.7) & (ang < -110) & (ang > -160)
    c.flat(shine, V[-1])
    # faux logo sur le moyeu (emblème de faux_logos.py, réduit)
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import faux_logos
    if logo:                                # bus : moyeu nu
        e = faux_logos.emblème(logo, 16 if nb != 1 else 12)
        im = Image.fromarray(c.px, "RGBA")
        im.alpha_composite(e, (cx - e.width // 2, cy - e.height // 2))
        c.px = np.array(im)
    c.save("wheel.png")
    return {"wheel_r": WR, "wheel_t": WT}


def apercu(cid, shot):
    out_dir = os.path.join(BASE, cid)
    bg = Image.open(shot).convert("RGBA")
    H = int(round(bg.height * W / bg.width))
    bg = bg.resize((W, H), Image.LANCZOS)
    for name, x, y, rot in (("top.png", 0, 0, 0), ("dash.png", 0, H - 100, 0), ("wheel.png", 160, H - 100, 10)):
        im = Image.open(os.path.join(out_dir, name))
        if rot:
            im = im.rotate(rot, resample=Image.NEAREST)
        bg.alpha_composite(im, (x, y))
    return bg.resize((W * 2, H * 2), Image.NEAREST)


def main():
    args = sys.argv[1:]
    shot = None
    if "--apercu" in args:
        shot = args[args.index("--apercu") + 1]
        args = [a for a in args if a not in ("--apercu", shot)]
    ids = args or list(STYLES)
    planches = []
    for cid in ids:
        st = STYLES[cid]
        B.OUT = os.path.join(BASE, cid)
        os.makedirs(B.OUT, exist_ok=True)
        meta = {}
        meta.update(planche(st)); meta.update(pavillon(st)); meta.update(volant(st))
        B.strip("pillar.png", rampe(*st["portes"]), 16, 8, amb=0.3)
        B.pine()
        json.dump(meta, open(os.path.join(B.OUT, "meta.json"), "w"))
        print("cockpit", cid, sorted(os.listdir(B.OUT)))
        if shot:
            planches.append(apercu(cid, shot))
    if planches:
        w, h = planches[0].size
        o = Image.new("RGB", (w * 2, h * ((len(planches) + 1) // 2)))
        for i, p in enumerate(planches):
            o.paste(p.convert("RGB"), ((i % 2) * w, (i // 2) * h))
        o.save("data/cockpits_apercu.jpg", quality=88)


if __name__ == "__main__":
    main()
