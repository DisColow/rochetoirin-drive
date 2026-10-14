"""Moteur commun des bâtiments sur mesure (méthode du restaurant « Le Rochefestin », directive du 13/10 : tous les
bâtiments non résidentiels). Un relevé JSON par bâtiment (sur_mesure/releves/*.json), écrit d'après les photos Street
View du cache (streetview/batiments/) ; le moteur fait le reste :
- emprise : celle du cadastre (BD TOPO), sol : relief terrassé du jeu (CarvedDEM), murs prolongés sous le sol ;
- murs plats sur chaque côté de l'emprise, peints dans un atlas (matière, soubassement, chaînages, ouvertures, enseignes,
  affichettes : seuls les titres sont lisibles, le reste en gribouillis) ;
- toits par rectangles (décomposition de build_buildings.py) : 2pans, 4pans, plat (acrotère), appentis ;
- volumes seulement pour les structures extérieures (auvents, porches, stores, appliques, poubelles, cuves, silos,
  clocher, contreforts…), collisions en boîtes (BoxShape3D).
Sorties : godot/assets/sur_mesure/<id>.glb + <id>.png, entrées de godot/world/sur_mesure.json (fusionné).

Format du relevé (mesures approximatives : reconnaissable, pas exact) :
{
 "id": "ecole", "cleabs": "BATIMENT…", "nom": "Nom parodique (vrai rôle)", "remplace_commerce": [],
 "mur": "enduit#e8dcc8" | "bardage#a0a4a8" | "bardageh#7c858d" (nervures horizontales) | "bois#6a4a30" | "pierre#9a8466" | "brique" | "beton#c8c4bc",
 "volumes": [{"rect": [u0, v0, u1, v1], "rot": degrés, "egout", "faitage", "toit", "faces", …}] (facultatif : plusieurs volumes en
   mètres dans le repère cadre() — coin du rectangle orienté de l'emprise, u le long du grand côté ; grille du calage),
 "remplace_bati_extra": [cleabs…] (bâtiments BD TOPO voisins absorbés par ce modèle, ex. une aile),
 "sol": "haut" (pente : hauteurs comptées depuis le point haut de l'emprise et non le point bas),
 "simplifier": 1.5 (tolérance de simplification de l'emprise, m ; 0,3 par défaut), "decal": [dx, dz], "rot": degrés, "echelle": [sx, sz] (facultatifs : emprise recalée sur les photos, calage.py),
 "soubassement": "#rrggbb" ou "matière#rrggbb" (facultatif), "h_soub": 0.5, "chainages": "#rrggbb" (facultatif),
 "ouvert": true (abri sur poteaux ; "pignons_clos": true = pignons bardés, "bardage_haut": 1.5 = bande de bardage sous l'égout, m),
 "toit": {"type": "2pans|4pans|plat|appentis|sheds|berceau" (sheds : dents de scie, "pas" en m ; berceau : voûte), "matiere": "tuile|tuile_brune|bac#rrggbb|fibro|ardoise",
          "bas": "S" (appentis : côté bas), "faitage_long": true (2pans : faîtage le long du grand côté)},
 "egout": 6.0, "faitage": 8.5,
 "faces": {"S": [ouvertures…], "E": […]}    clés : N NE E SE S SO O NO (côté de l'emprise tourné vers là ; le plus long)
 ouverture : {"t": type, "x": [début, fin] en fraction de la façade vue de dehors (0 = gauche), "y": [bas, haut] (m),
              "n": nombre (répété régulièrement sur x), "c": "#couleur", "txt": "texte", "titre": "TITRE",
              "entourage": "#couleur" (encadrement peint autour, "e_ent" : largeur en m, 0,16 par défaut)}
   types : fenetre, fenetre_volets (volets ouverts), volets_clos, porte, porte_vitree, vitrine, garage, rideau,
           grille, bandeau, enseigne, lettres, affiche, logo, ogive (église), rosace, bande_vitree, porte_grange
 "extras": [{"t": "auvent|store|porche|marquise", "face": "S", "x": [f0, f1], "y": 3.0, "p": 1.2, "c": "#…"},
            {"t": "applique|poubelle", "face": "S", "x": [f…], "y": 3.0}, {"t": "cuve|silo", "face": "E", "x": 0.5,
             "d": 3.0, "r": 1.5, "h": 6}, {"t": "clocher", "face": "O", "x": 0.5, "w": 4, "h": 16, "fleche": 9},
            {"t": "contreforts", "face": "S", "x": [f…], "h": 5}, {"t": "cheminee", "x": 0.3, "y": 0.5},
            {"t": "charpente", "face": "N", "x": [f0, f1], "y": 3.0 (égout), "p": 5.0 (avancée), "h": 5.6 (faîtage),
             "c": "#bois"} (grand porche ouvert à ferme apparente)]
}
Lancer depuis pipeline/ : python3 sur_mesure/batiment.py [id…]"""
import glob, json, math, os, random, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from shapely.geometry import shape, Polygon, Point
from shapely.ops import transform
import shapely

ICI = os.path.dirname(os.path.abspath(__file__))
PIPE = os.path.dirname(ICI)
sys.path.insert(0, PIPE); sys.path.insert(0, os.path.join(PIPE, "boulangerie"))
import geo
from glb import write_glb
from build_boulangerie import Zone, bruit, ombre, griffonnage, F_SANS, F_SERIF, F_ENS, F_MAIN
from build_boulangerie import texte as _texte
import bibliotheque as BIB
from scipy import ndimage as _ndi
# v6.38 (issue #13, APK > 2 Go) : fond des murs et des toits pris dans la bibliothèque partagée (bibliotheque.py) ;
# seules les « décalcomanies » (ouvertures, enseignes, soubassements, chaînages, ombre sous l'égout : tout ce qui
# diffère du fond, découpé automatiquement) restent dans un petit atlas par bâtiment. SM_BIB=0 : ancien atlas complet.
MODE_BIB = os.environ.get("SM_BIB", "1") == "1"
VIRT = 4096                                # atlas de travail (virtuel) en mode bibliothèque


def texte(img, box, txt, font, col, **kw):
    """Texte ajusté ; trop petit pour être lu (moins de 8 px) : un trait de gribouillis à la place."""
    x0, y0, x1, y1 = box
    if y1 - y0 < 8 or x1 - x0 < 8 or not txt:
        ImageDraw.Draw(img).line([(x0, (y0 + y1) / 2), (x1, (y0 + y1) / 2)], fill=col, width=1)
        return
    _texte(img, box, txt, font, col, **kw)

GOD = os.path.join(PIPE, "..", "godot")
OUT_A = os.path.join(GOD, "assets", "sur_mesure")
ATLAS = 1024                    # par bâtiment (mémoire vidéo : 138 bâtiments à terme, chargés autour de la caméra)
import build_boulangerie as _BB
_BB.ATLAS = ATLAS               # Zone.uv divise par l'ATLAS de build_boulangerie
MUR_C, TOIT_C, PETIT_C = (0.85, 0.0, 1.0), (0.7, 1.0, 0.0), (0.6, 0.0, 0.0)   # couleur de sommet (sur_mesure.gdshader)
DECORS = ("enseigne", "lettres", "affiche", "logo", "bandeau")
CAPS = {"N": 0, "NE": 45, "E": 90, "SE": 135, "S": 180, "SO": 225, "O": 270, "NO": 315}


def hexc(s, defaut=(200, 200, 200)):
    if not s or "#" not in s:
        return defaut
    h = s.split("#")[1][:6]
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def assombrir(c, f):
    return tuple(max(0, min(255, int(v * f))) for v in c)


# ================================================================ peinture
class Atlas:
    """Rangement en étagères dans l'atlas (taille × taille ; ATLAS par défaut)."""
    def __init__(self, taille=ATLAS):
        self.T = taille
        self.img = Image.new("RGB", (taille, taille), (128, 128, 128))
        self.msk = Image.new("L", (taille, taille), 0)
        self.x = self.y = self.hl = 0

    def zone(self, w, h, s):
        W, H = int(math.ceil(w * s)) + 2, int(math.ceil(h * s)) + 2
        if self.x + W > self.T:
            self.x, self.y, self.hl = 0, self.y + self.hl + 2, 0
        if self.y + H > self.T:
            raise ValueError("atlas plein")
        z = Zone(self.img, self.msk, self.x + 1, self.y + 1, W - 2, H - 2, s)
        self.x += W + 2; self.hl = max(self.hl, H)
        return z


def matiere(z, mur, seed):
    """Fond de mur : enduit, bardage, bois, pierre, brique, béton (blocs)."""
    img = z.img
    x0, y0, x1, y1 = int(z.x0), int(z.y0), int(z.x0 + z.w), int(z.y0 + z.h)
    d = ImageDraw.Draw(img)
    kind = mur.split("#")[0]
    c = hexc(mur, {"pierre": (150, 128, 100), "brique": (138, 88, 58), "beton": (196, 192, 184),
                   "bois": (110, 80, 52), "bardage": (170, 174, 178), "bardageh": (126, 133, 141)}.get(kind, (220, 210, 190)))
    d.rectangle((x0, y0, x1, y1), fill=c)
    r = random.Random(seed)
    s = z.s
    if kind == "bardage":                                  # nervures verticales (25 cm, 50 cm si l'atlas est serré)
        k = 0
        pas = 0.25 if s >= 32 else 0.5                     # moins de 8 px par nervure : moiré au loin (v6.26)
        while x0 + k * pas * s < x1:
            x = x0 + k * pas * s
            d.line((x, y0, x, y1), fill=assombrir(c, 0.88), width=max(1, int(0.03 * s)))
            d.line((x + max(1, 0.04 * s), y0, x + max(1, 0.04 * s), y1), fill=assombrir(c, 1.04), width=1)
            k += 1
    elif kind == "bardageh":                                # bardage à nervures horizontales (tous les 30 cm)
        k = 0
        while y0 + k * 0.3 * s < y1:
            y = y0 + k * 0.3 * s
            d.line((x0, y, x1, y), fill=assombrir(c, 0.84), width=max(1, int(0.04 * s)))
            d.line((x0, y + max(1, 0.05 * s), x1, y + max(1, 0.05 * s)), fill=assombrir(c, 1.06), width=1)
            k += 1
    elif kind == "bois":                                    # planches verticales
        k = 0
        while x0 + k * 0.18 * s < x1:
            x = x0 + k * 0.18 * s
            d.rectangle((x, y0, x + 0.18 * s, y1), fill=assombrir(c, r.uniform(0.82, 1.12)))
            d.line((x, y0, x, y1), fill=assombrir(c, 0.55), width=1)
            k += 1
    elif kind in ("pierre", "brique", "beton"):
        bh, bw = {"pierre": (0.28, 0.45), "brique": (0.065, 0.22), "beton": (0.2, 0.5)}[kind]
        if bh * s < 3:                                     # atlas serré : briques de moins de 3 px -> rangs groupés
            bh, bw = 3.0 / s, max(bw, 9.0 / s)
        joint = {"pierre": assombrir(c, 0.72), "brique": (176, 160, 136), "beton": assombrir(c, 0.85)}[kind]
        d.rectangle((x0, y0, x1, y1), fill=joint)
        y, k = y1, 0
        while y > y0:
            h = bh * s * (r.uniform(0.75, 1.25) if kind == "pierre" else 1)
            x = x0 - (bw * s / 2 if k % 2 else 0)
            while x < x1:
                w = bw * s * (r.uniform(0.6, 1.5) if kind == "pierre" else 1)
                f = r.uniform(0.8, 1.15) if kind != "beton" else r.uniform(0.95, 1.04)
                d.rectangle((x + 1, y - h + 1, x + w - 1, y - 1), fill=assombrir(c, f))
                x += w
            y -= h; k += 1
    bruit(img, (x0, y0, x1, y1), 5 if kind in ("enduit", "") else 3, seed=seed)


def chaine(z, u, v0, v1, cote, col, l=0.36):
    v, k = v0, 0
    while v < v1:
        w = l if k % 2 == 0 else l * 0.62
        a, b = (u, u + cote * w) if cote > 0 else (u + cote * w, u)
        z.rect(a, v, b, min(v + 0.32, v1), col)
        v += 0.34; k += 1


def vitrage(z, u0, v0, u1, v1, allume=False, haut=(84, 96, 108), bas=(30, 34, 40)):
    a, b = z.px(u0, v1), z.px(u1, v0)
    for y in range(int(a[1]), int(b[1])):
        t = (y - a[1]) / max(1, b[1] - a[1])
        z.d.line([(a[0], y), (b[0] - 1, y)], fill=tuple(int(p * (1 - t) + q * t) for p, q in zip(haut, bas)))
    z.m.rectangle([a[0], a[1], b[0] - 1, b[1] - 1], fill=255 if allume else 128)


def volets(z, u0, v0, u1, v1, col):
    z.rect(u0, v0, u1, v1, col)
    n = max(3, int((u1 - u0) / 0.11))
    for k in range(1, n):
        u = u0 + k * (u1 - u0) / n
        z.line(u, v0, u, v1, assombrir(col, 0.85), 1)
    z.line((u0 + u1) / 2, v0, (u0 + u1) / 2, v1, assombrir(col, 0.6), 2)
    for v in (v0 + 0.15, v1 - 0.15):
        z.rect(u0 - 0.03, v - 0.012, u0 + 0.14, v + 0.012, (40, 40, 44))
        z.rect(u1 - 0.14, v - 0.012, u1 + 0.03, v + 0.012, (40, 40, 44))
    ombre(z, u0, v0, u1, v1, 0.04, 0.2)


def ouverture(z, op, u0, v0, u1, v1, mur_c):
    """Peint une ouverture ou un décor mural dans la zone (mètres de la façade)."""
    t = op["t"]
    c = hexc(op.get("c"), None)
    w, h = u1 - u0, v1 - v0
    if op.get("entourage"):                               # encadrement (pierre, enduit lissé) autour de l'ouverture
        e = float(op.get("e_ent", 0.16))
        z.rect(u0 - e, v0 - e * 0.6, u1 + e, v1 + e, hexc(op["entourage"]))
        ombre(z, u0 - e, v0 - e * 0.6, u1 + e, v1 + e, 0.03, 0.15)
    if t == "matiere":                                    # bande d'une autre matière (haut en bois, bandeau anthracite…)
        a, b = z.px(u0, v1), z.px(u1, v0)
        sub = Zone(z.img, z.msk, a[0], a[1], max(1, b[0] - a[0]), max(1, b[1] - a[1]), z.s)
        matiere(sub, op.get("mur", "bardage#404448"), int(abs(u0 * 7 + v0 * 13)))
        if op.get("liseré"):
            z.rect(u0, v0 - 0.06, u1, v0, hexc(op["liseré"]))
        return
    if t in ("fenetre", "fenetre_volets", "porte_vitree", "vitrine", "bande_vitree"):
        cadre = c or ((236, 236, 231) if t != "vitrine" else (60, 62, 66))
        z.rect(u0, v0, u1, v1, cadre)
        f = 0.05 if t != "vitrine" else 0.07
        vitrage(z, u0 + f, v0 + f, u1 - f, v1 - f, allume=t in ("vitrine", "porte_vitree"))
        if t in ("fenetre", "fenetre_volets") and w > 0.5:
            z.rect((u0 + u1) / 2 - 0.025, v0 + f, (u0 + u1) / 2 + 0.025, v1 - f, cadre, 0)
        if t in ("vitrine", "bande_vitree"):
            n = max(1, int(w / 1.6))
            for k in range(1, n):
                u = u0 + k * w / n
                z.rect(u - 0.03, v0, u + 0.03, v1, cadre, 0)
        ombre(z, u0 + f, v0 + f, u1 - f, v1 - f, 0.08, 0.4)
        if t in ("fenetre", "fenetre_volets"):
            z.rect(u0 - 0.05, v0 - 0.07, u1 + 0.05, v0, (200, 196, 188))
        if t == "fenetre_volets":
            vc = hexc(op.get("volets"), (120, 130, 140))
            for s0 in (u0 - 0.04 - w / 2, u1 + 0.04):
                volets(z, s0, v0, s0 + w / 2, v1, vc)
    elif t == "volets_clos":
        z.rect(u0 - 0.06, v0 - 0.06, u1 + 0.06, v1 + 0.06, assombrir(mur_c, 0.9))
        volets(z, u0, v0, u1, v1, c or (120, 130, 140))
        z.rect(u0 - 0.05, v0 - 0.07, u1 + 0.05, v0, (200, 196, 188))
    elif t in ("porte", "porte_grange"):
        c = c or (90, 62, 44)
        z.rect(u0 - 0.06, v0, u1 + 0.06, v1 + 0.06, assombrir(mur_c, 0.85))
        z.rect(u0, v0, u1, v1, c)
        n = max(2, int(w / (0.18 if t == "porte_grange" else 0.3)))
        for k in range(1, n):
            u = u0 + k * w / n
            z.line(u, v0, u, v1, assombrir(c, 0.75), 1)
        if t == "porte_grange" or w > 1.4:
            z.line((u0 + u1) / 2, v0, (u0 + u1) / 2, v1, assombrir(c, 0.5), 2)
        z.rect(u1 - 0.14, v0 + 0.95, u1 - 0.08, v0 + 1.02, (40, 40, 40))
        ombre(z, u0, v0, u1, v1, 0.08, 0.45)
    elif t in ("garage", "rideau"):
        c = c or ((214, 214, 210) if t == "garage" else (176, 172, 166))
        z.rect(u0 - 0.06, v0, u1 + 0.06, v1 + 0.06, assombrir(mur_c, 0.85))
        z.rect(u0, v0, u1, v1, c)
        pas = 0.5 if t == "garage" else 0.06
        v = v0 + pas
        while v < v1:
            z.line(u0, v, u1, v, assombrir(c, 0.78), 1 if t == "rideau" else 2)
            v += pas
        ombre(z, u0, v0, u1, v1, 0.07, 0.4)
    elif t == "grille":
        z.rect(u0, v0, u1, v1, (40, 40, 44))
        vitrage(z, u0 + 0.04, v0 + 0.04, u1 - 0.04, v1 - 0.04)
        k = 1
        while u0 + k * 0.1 < u1:
            z.rect(u0 + k * 0.1 - 0.012, v0, u0 + k * 0.1 + 0.012, v1, (70, 70, 74), 0); k += 1
    elif t == "ogive":                                    # fenêtre gothique (église)
        cad = assombrir(mur_c, 1.15)
        z.rect(u0 - 0.12, v0 - 0.12, u1 + 0.12, v1 - w / 2, cad)
        z.d.ellipse([*z.px(u0 - 0.12, v1 + 0.12), *z.px(u1 + 0.12, v1 - w - 0.12)], fill=cad)
        z.rect(u0, v0, u1, v1 - w / 2, (56, 62, 80), 128)
        z.d.ellipse([*z.px(u0, v1), *z.px(u1, v1 - w)], fill=(56, 62, 80))
        z.m.ellipse([*z.px(u0, v1), *z.px(u1, v1 - w)], fill=128)
        for k in range(1, 4):
            z.line(u0, v0 + k * (h - w / 2) / 4, u1, v0 + k * (h - w / 2) / 4, (90, 80, 70), 1)
        z.line((u0 + u1) / 2, v0, (u0 + u1) / 2, v1 - 0.1, (90, 80, 70), 1)
    elif t == "rosace":
        cx, cy = (u0 + u1) / 2, (v0 + v1) / 2
        r = min(w, h) / 2
        z.d.ellipse([*z.px(cx - r - 0.1, cy + r + 0.1), *z.px(cx + r + 0.1, cy - r - 0.1)], fill=assombrir(mur_c, 1.15))
        z.d.ellipse([*z.px(cx - r, cy + r), *z.px(cx + r, cy - r)], fill=(70, 70, 110))
        for k in range(8):
            a = k * math.pi / 4
            z.line(cx, cy, cx + math.cos(a) * r, cy + math.sin(a) * r, (110, 96, 80), 2)
    elif t == "bandeau":
        z.rect(u0, v0, u1, v1, c or (60, 60, 64))
        if op.get("txt"):
            a, b = z.px(u0 + 0.1, v1 - 0.06), z.px(u1 - 0.1, v0 + 0.06)
            texte(z.img, (a[0], a[1], b[0], b[1]), op["txt"], F_SANS, hexc(op.get("tc"), (250, 250, 250)))
    elif t == "enseigne":                                  # panneau : nom parodique (lisible), sous-titre griffonné
        fond = c or (250, 248, 240)
        z.rect(u0, v0, u1, v1, assombrir(fond, 0.6)); z.rect(u0 + 0.04, v0 + 0.04, u1 - 0.04, v1 - 0.04, fond)
        a, b = z.px(u0 + 0.12, v1 - 0.08), z.px(u1 - 0.12, v0 + (h * 0.32 if op.get("sous") else 0.08))
        texte(z.img, (a[0], a[1], b[0], b[1]), op.get("txt", ""), F_SANS, hexc(op.get("tc"), (40, 40, 48)))
        if op.get("sous"):
            a, b = z.px(u0 + 0.2, v0 + h * 0.3), z.px(u1 - 0.2, v0 + 0.06)
            griffonnage(z.img, (a[0], a[1], b[0], b[1]), 1, hash(op.get("txt", "")) % 1000)
    elif t == "lettres":                                   # lettres posées sur le mur, ombre portée
        a, b = z.px(u0, v1), z.px(u1, v0)
        tc = hexc(op.get("tc"), (240, 240, 244))
        texte(z.img, (a[0] + 2, a[1] + 2, b[0] + 2, b[1] + 2), op.get("txt", ""), F_SANS, assombrir(mur_c, 0.55))
        texte(z.img, (a[0], a[1], b[0], b[1]), op.get("txt", ""), F_SANS, tc)
    elif t == "affiche":                                   # affichette : titre lisible, le reste en gribouillis
        z.rect(u0, v0, u1, v1, c or (250, 248, 240))
        a, b = z.px(u0 + 0.03, v1 - 0.03), z.px(u1 - 0.03, v1 - h * 0.25)
        texte(z.img, (a[0], a[1], b[0], b[1]), op.get("titre", "INFO"), F_SANS, hexc(op.get("tc"), (40, 40, 60)))
        a, b = z.px(u0 + 0.05, v1 - h * 0.3), z.px(u1 - 0.05, v0 + 0.04)
        griffonnage(z.img, (a[0], a[1], b[0], b[1]), max(2, int((b[1] - a[1]) / 9)), int(u0 * 100))
    elif t == "logo":
        cx, cy = (u0 + u1) / 2, (v0 + v1) / 2
        r = min(w, h) / 2
        z.d.ellipse([*z.px(cx - r, cy + r), *z.px(cx + r, cy - r)], fill=c or (200, 40, 40))
        a, b = z.px(cx - r * 0.7, cy + r * 0.6), z.px(cx + r * 0.7, cy - r * 0.6)
        texte(z.img, (a[0], a[1], b[0], b[1]), op.get("txt", "?"), F_SERIF, hexc(op.get("tc"), (250, 250, 250)))


# ================================================================ géométrie
class Mesh:
    def __init__(self):
        self.P, self.N, self.UV, self.C, self.I = [], [], [], [], []

    def poly(self, pts, uvs, col, n=None):
        """Polygone convexe (3 ou 4 points, monde relatif à la pose)."""
        P = [np.asarray(p, float) for p in pts]
        if n is None:
            v = np.cross(P[1] - P[0], P[2] - P[0])
            n = v / (np.linalg.norm(v) + 1e-9)
        o = len(self.P)
        for p, t in zip(P, uvs):
            self.P.append(p); self.N.append(n); self.UV.append(t); self.C.append(col)
        for k in range(1, len(P) - 1):
            self.I += [o, o + k, o + k + 1]


def uv4(z):
    return [z.uv(0, 0), z.uv(z.w / z.s, 0), z.uv(z.w / z.s, z.h / z.s), z.uv(0, z.h / z.s)]


def boite(M, z, c0, c1, ax, h0, h1, col=PETIT_C, dessous=False):
    """Boîte orientée : c0, c1 = coins opposés (x, z) dans le repère (ax = angle du grand axe), hauteurs h0, h1."""
    ca, sa = math.cos(ax), math.sin(ax)
    def W(u, v, y):
        return (u * ca - v * sa, y, u * sa + v * ca)
    (u0, v0), (u1, v1) = c0, c1
    uv = uv4(z)
    C = [(u0, v0), (u1, v0), (u1, v1), (u0, v1)]
    for i in range(4):
        (a, b), (p, q) = C[i], C[(i + 1) % 4]
        M.poly([W(a, b, h0), W(p, q, h0), W(p, q, h1), W(a, b, h1)], uv, col)
    M.poly([W(u0, v0, h1), W(u0, v1, h1), W(u1, v1, h1), W(u1, v0, h1)], uv, col)
    if dessous:
        M.poly([W(u0, v0, h0), W(u1, v0, h0), W(u1, v1, h0), W(u0, v1, h0)], uv, col)


def emprise(feat):
    g = transform(lambda x, y, z=None: geo.to_local(x, y), shape(feat["geometry"])).buffer(0)
    if g.geom_type == "MultiPolygon":
        g = max(g.geoms, key=lambda q: q.area)
    return g


def cadre(feat):
    """Repère en mètres du bâtiment (volumes, grille du calage) : origine au coin du rectangle orienté de l'emprise
    BD TOPO, u le long du grand côté, v en travers. Retourne (origine, u, v, L, W)."""
    from build_buildings import obb_frame
    g = emprise(feat)
    a, c, r = obb_frame(g)
    u = np.array([math.cos(a), math.sin(a)]); v = np.array([-math.sin(a), math.cos(a)])
    P = np.asarray(r.exterior.coords)[:4] - np.asarray(c)
    us, vs = P @ u, P @ v
    o = np.asarray(c) + u * us.min() + v * vs.min()
    return o, u, v, float(us.max() - us.min()), float(vs.max() - vs.min())


def volumes(R, feat):
    """Relevé à plusieurs volumes -> sous-relevés (un modèle chacun). "volumes": [{"rect": [u0, v0, u1, v1] (m, repère
    cadre()), "egout", "faitage", "toit", "faces", "mur", "extras"…}] ; le reste du relevé sert de valeurs par défaut."""
    if not R.get("volumes"):
        return [R]
    o, u, v, L, W = cadre(feat)
    base = {k: x for k, x in R.items() if k not in ("volumes", "faces", "extras")}
    out = []
    for k, V in enumerate(R["volumes"]):
        u0, v0, u1, v1 = V["rect"]
        q = np.array([(u0, v0), (u1, v0), (u1, v1), (u0, v1)], float)
        if V.get("rot"):                                   # volume en biais : tourné autour de son centre (degrés)
            t = math.radians(float(V["rot"])); m = q.mean(0)
            q = (q - m) @ np.array([[math.cos(t), math.sin(t)], [-math.sin(t), math.cos(t)]]) + m
        poly = [tuple(o + u * a + v * b) for a, b in q]
        sub = dict(base, **{x: y for x, y in V.items() if x not in ("rect", "rot")})
        sub.update(id="%s_%d" % (R["id"], k) if k else R["id"], poly=poly, simplifier=0.05)
        if k:
            sub["remplace_commerce"] = []
        out.append(sub)
    return out


class Batiment:
    def __init__(self, R, feat, dem):
        self.R = R
        if R.get("poly"):                                  # volume (main : "volumes") : emprise imposée
            g = Polygon(R["poly"])
        else:
            g = emprise(feat)
        g = shapely.geometry.polygon.orient(shapely.simplify(g, float(R.get("simplifier", 0.3))), 1.0)
        # calage sur les photos (sur_mesure/calage.py) : emprise BD TOPO décalée / tournée / redimensionnée
        if R.get("rot") or R.get("decal") or R.get("echelle"):
            import shapely.affinity as sa
            if R.get("echelle"):
                e = R["echelle"]
                g = sa.scale(g, e[0], e[1] if len(e) > 1 else e[0], origin="centroid")
            if R.get("rot"):
                g = sa.rotate(g, float(R["rot"]), origin="centroid")
            if R.get("decal"):
                g = sa.translate(g, float(R["decal"][0]), float(R["decal"][1]))
        self.g = g
        ring = np.asarray(g.exterior.coords)
        gr = dem.h(ring[:, 0], ring[:, 1])
        self.sol, self.pente = float(gr.min()), float(gr.max() - gr.min())
        if R.get("sol") == "haut":                       # terrain en pente, entrée côté haut : hauteurs depuis le haut
            self.sol = float(gr.max())
        self.c = np.array([g.centroid.x, g.centroid.y])
        self.BAS = -(self.pente + 1.0)
        self.EG = float(R.get("egout", 4.0))
        self.FA = float(R.get("faitage", self.EG + 2.0))
        # côtés : p0, p1 relatifs au centre, longueur, normale extérieure, cap (0 = nord)
        P = ring - self.c
        self.cotes = []
        for k in range(len(P) - 1):
            p0, p1 = P[k], P[k + 1]
            d = p1 - p0; L = float(np.hypot(*d))
            if L < 0.3:
                continue
            n = np.array([d[1], -d[0]]) / L
            cap = math.degrees(math.atan2(n[0], -n[1])) % 360
            self.cotes.append(dict(p0=p0, p1=p1, L=L, n=n, cap=cap, top=self.EG, ops=[]))
        for k, ops in R.get("faces", {}).items():
            c = self.face(k)
            if c is not None:
                c["ops"] += ops
        for k, m in R.get("mur_faces", {}).items():          # matière propre à une façade (pignon en bois…)
            c = self.face(k)
            if c is not None:
                c["mur"] = m

    def face(self, k):
        cap = CAPS[k]
        best, bs = None, 0.0
        for c in self.cotes:
            dd = abs((c["cap"] - cap + 180) % 360 - 180)
            if dd <= 50:
                s = c["L"] * math.cos(math.radians(dd))
                if s > bs:
                    best, bs = c, s
        return best

    def pt_face(self, c, f, recul=0.0):
        """Point (x, z) relatif au centre à la fraction f de la façade vue de dehors (0 = gauche), recul vers dehors."""
        p = c["p1"] + (c["p0"] - c["p1"]) * f          # vue de dehors, la gauche est du côté de p1
        return p + c["n"] * recul


def construire(R, feat, dem, remplir=0.4):
    B = Batiment(R, feat, dem)
    taille = ATLAS
    if R.get("densite"):                               # atlas juste assez grand pour ~densite px/m (lots de communes)
        d = float(R["densite"])
        besoin = sum(c["L"] * (B.FA + 0.4) for c in B.cotes) * d * d / 0.7 + 220 * 220
        taille = next((t for t in (256, 384, 512, 768, 1024) if t * t >= besoin), 1024)
    taille_ref = taille                                # densité des façades : celle de l'ancien atlas (rendu identique)
    if MODE_BIB:
        taille = VIRT
    _BB.ATLAS = taille                                 # Zone.uv divise par cette taille
    A = Atlas(taille)
    M = Mesh()
    boites = []
    mur = R.get("mur", "enduit#e0d6c4")
    mur_c = hexc(mur, (220, 210, 190))
    toit = R.get("toit", {"type": "2pans", "matiere": "tuile"})
    # ---- plan des toits (rectangles), avant la peinture : les pignons montent les murs à la hauteur du faîtage
    from build_buildings import decompose, rot
    dec = decompose(B.g)
    if dec is None:                    # 2e essai : emprise simplifiée (pans coupés, petits décrochements)
        dec = decompose(shapely.simplify(B.g, 1.2))
    if dec is None and B.g.area / B.g.minimum_rotated_rectangle.area > 0.75:
        from build_buildings import obb_frame
        a_, c_, r_ = obb_frame(B.g)
        dec = (None, [Polygon(rot(np.asarray(r_.exterior.coords), -a_, c_)).bounds], a_, c_)
    if dec is None:
        dec = (None, None, None, None)
    _, rects, ang, cen = dec
    libre = rects is None              # forme quelconque : toit plat qui suit l'emprise (pas de pans sur un rectangle)
    if libre:
        from build_buildings import obb_frame
        ang, cen, r = obb_frame(B.g)
        rects = []
        toit = dict(toit, type="plat")
    EG, FA = B.EG, B.FA
    ty = toit.get("type", "2pans")
    plans = []
    for (x0, z0, x1, z1) in rects:
        long_x = (x1 - x0) >= (z1 - z0)
        if toit.get("faitage_long") is False:
            long_x = not long_x
        plans.append((x0, z0, x1, z1, long_x))
    # pignons : triangles sur les côtés courts des rectangles (2pans) -> hauteur des zones de façade concernées
    def monde(px, pz):
        q = rot(np.array([[px, pz]]), ang, cen)[0]
        return q - B.c
    pignons = []
    if ty == "2pans":
        for (x0, z0, x1, z1, lx) in plans:
            if lx:
                ends = [((x0, z0), (x0, z1)), ((x1, z1), (x1, z0))]
            else:
                ends = [((x1, z0), (x0, z0)), ((x0, z1), (x1, z1))]
            for e0, e1 in ends:
                a, b = monde(*e0), monde(*e1)
                # côté de l'emprise porteur : colinéaire et proche
                best, bd = None, 0.8
                for c in B.cotes:
                    dv = c["p1"] - c["p0"]
                    t = (b - a) / (np.linalg.norm(b - a) + 1e-9)
                    if abs(abs(np.dot(dv / c["L"], t)) - 1) > 0.05:
                        continue
                    dist = abs(np.dot((a + b) / 2 - c["p0"], c["n"]))
                    if dist < bd:
                        best, bd = c, dist
                if best is not None:
                    best["top"] = max(best["top"], FA)
                pignons.append((a, b, best))
    elif ty == "appentis":
        bas = B.face(toit.get("bas", "S"))
        for c in B.cotes:
            if bas is not None and c is not bas and np.dot(c["n"], bas["n"]) > -0.3:
                c["top"] = FA
    # ---- peinture des façades
    decors = []
    tot = sum(c["L"] * (c["top"] + 0.2) for c in B.cotes)
    s = max(8.0, min(40.0, math.sqrt(remplir * taille_ref * taille_ref / max(tot, 1.0))))
    if R.get("densite"):                               # lots de communes (v6.34) : atlas réduit, ~densite px/m
        s = min(s, float(R["densite"]))
    seed = abs(hash(R["id"])) % 1000
    for k, c in enumerate(B.cotes):
        z = c["z"] = A.zone(c["L"], c["top"] + 0.2, s)
        c["mat"] = c.get("mur", mur)
        if MODE_BIB:
            BIB.fond(z, c["mat"])
        else:
            matiere(z, c["mat"], seed + k)
        if R.get("soubassement") and MODE_BIB:              # panneau de la bibliothèque (pas de décalcomanie)
            sm = R["soubassement"] if not R["soubassement"].startswith("#") else "enduit" + R["soubassement"]
            _panneau(c, z, 0.0, -0.1, c["L"], float(R.get("h_soub", 0.5)), sm)
        elif R.get("soubassement"):
            if R["soubassement"].startswith("#"):
                z.rect(0, -0.1, c["L"], float(R.get("h_soub", 0.5)), hexc(R["soubassement"]))
            else:                                            # soubassement d'une autre matière (parpaings sous bardage…)
                ouverture(z, {"t": "matiere", "mur": R["soubassement"]}, 0, -0.1, c["L"],
                          float(R.get("h_soub", 0.5)), None)
        if R.get("chainages"):
            chaine(z, 0, R.get("h_soub", 0.5), EG, 1, hexc(R["chainages"]))
            chaine(z, c["L"], R.get("h_soub", 0.5), EG, -1, hexc(R["chainages"]))
        for op in c["ops"]:
            n = int(op.get("n", 1))
            f0, f1 = op.get("x", [0.4, 0.6])
            v0, v1 = op.get("y", [0.0, 2.2])
            if n > 1:                                        # n ouvertures régulières entre f0 et f1
                larg = float(op.get("l", 1.0)) / c["L"]
                pas = (f1 - f0 - larg) / (n - 1)
                xs = [(f0 + i * pas, f0 + i * pas + larg) for i in range(n)]
            else:
                xs = [(f0, f1)]
            for a0, a1 in xs:
                if op["t"] in DECORS:          # enseignes, lettres, affichettes : aplat à part, en haute définition
                    w_, h_ = (a1 - a0) * c["L"], v1 - v0
                    sd = max(s, min(140.0, 260.0 / max(h_, 0.3), 0.85 * taille_ref / max(w_, 0.3), 120.0 / max(h_, 0.1)))
                    if R.get("densite"):                     # atlas réduit : titre lisible sans plus (~40 px/m)
                        sd = min(sd, max(s, 40.0))
                    zd = A.zone(w_, h_, sd)
                    zd.rect(-0.05, -0.05, w_ + 0.05, h_ + 0.05, mur_c if op["t"] == "lettres" else (250, 248, 240))
                    ouverture(zd, op, 0, 0, w_, h_, mur_c)
                    decors.append((c, a0 * c["L"], a1 * c["L"], v0, v1, zd))
                elif op["t"] == "matiere" and MODE_BIB:     # bande d'une autre matière : panneau de la bibliothèque
                    _panneau(c, z, a0 * c["L"], v0, a1 * c["L"], v1, op.get("mur", "bardage#404448"))
                    if op.get("liseré"):
                        z.rect(a0 * c["L"], v0 - 0.06, a1 * c["L"], v0, hexc(op["liseré"]))
                else:
                    ouverture(z, op, a0 * c["L"], v0, a1 * c["L"], v1, mur_c)
        # ombre sous l'égout (mode bibliothèque : faite par le shader, d'après la hauteur d'égout de chaque sommet)
        if MODE_BIB:
            continue
        a, b = z.px(0, EG), z.px(c["L"], EG - 0.45)
        reg = np.asarray(A.img.crop((int(a[0]), int(a[1]), int(b[0]), int(b[1])))).astype(np.float32)
        if reg.size:
            f = np.linspace(0.62, 1.0, reg.shape[0])[:, None, None]
            A.img.paste(Image.fromarray(np.clip(reg * f, 0, 255).astype(np.uint8)), (int(a[0]), int(a[1])))
    # ---- matières des toits et des petits volumes (cases unies) ; décors en relief
    mt = toit.get("matiere", "tuile")
    zt = A.zone(12, 12, min(16.0, float(R.get("densite", 16))))
    toiture(zt, mt, seed)
    unis = {}
    def uni(nom, col):
        if nom not in unis:
            z = A.zone(1.5, 1.5, 16)
            z.rect(-0.1, -0.1, 1.6, 1.6, col); bruit(A.img, (int(z.x0), int(z.y0), int(z.x0 + z.w), int(z.y0 + z.h)), 4, seed=len(unis))
            unis[nom] = z
        return unis[nom]
    # ---- murs
    V0 = 0.02
    unis_tot = unis
    for c in B.cotes:
        z = c["z"]
        p0, p1, L = c["p0"], c["p1"], c["L"]
        n3 = (c["n"][0], 0.0, c["n"][1])
        if R.get("ouvert"):                              # abri ouvert : poteaux tous les 5 m environ, pas de mur
            zpo = uni("poteau", hexc(R.get("c_poteaux"), (120, 124, 128)))
            k = max(1, int(round(L / 5.0)))
            for i in range(k):
                q = p0 + (p1 - p0) * (i / k)
                M_box(M, zpo, q, 0.0, 0.1, 0.1, B.BAS, EG)
            hb = float(R.get("bardage_haut", 0))            # bande de bardage sous l'égout (stabulation)
            if hb > 0:
                c.setdefault("pieces", []).append([(0, EG - hb), (L, EG - hb), (L, EG), (0, EG)])
                M.poly([(p0[0], EG - hb, p0[1]), (p1[0], EG - hb, p1[1]), (p1[0], EG, p1[1]), (p0[0], EG, p0[1])],
                       [z.uv(L, EG - hb), z.uv(0, EG - hb), z.uv(0, EG), z.uv(L, EG)], MUR_C, n3)
            continue
        c.setdefault("pieces", []).append([(0, 0), (L, 0), (L, EG), (0, EG)])
        for (y0, y1, va, vb) in ((B.BAS, 0.0, V0, V0), (0.0, EG, 0.0, EG)):
            M.poly([(p0[0], y0, p0[1]), (p1[0], y0, p1[1]), (p1[0], y1, p1[1]), (p0[0], y1, p0[1])],
                   [z.uv(L, va), z.uv(0, va), z.uv(0, vb), z.uv(L, vb)], MUR_C, n3)
    # ---- décors en aplat (1,2 cm devant le mur)
    for c, u0, u1, v0, v1, zd in decors:
        def P_(u, y):
            q = c["p1"] + (c["p0"] - c["p1"]) * (u / c["L"]) + c["n"] * 0.012
            return (q[0], y, q[1])
        w_, h_ = u1 - u0, v1 - v0
        M.poly([P_(u0, v0), P_(u1, v0), P_(u1, v1), P_(u0, v1)],
               [zd.uv(0, 0), zd.uv(w_, 0), zd.uv(w_, h_), zd.uv(0, h_)], PETIT_C, (c["n"][0], 0.0, c["n"][1]))
    # ---- toits
    deb = 0.0 if ty == "plat" else float(toit.get("debord", 0.4))
    zbo = uni("bois_ferme", hexc(R.get("c_poteaux"), (150, 104, 62)))

    def ferme(pa, pb, pm):
        """Ferme de charpente apparente (abri ouvert) : entrait, arbalétriers, poinçon, contrefiches."""
        pa, pb, pm = np.asarray(pa, float), np.asarray(pb, float), np.asarray(pm, float)
        pc = (pa + pb) / 2
        poutre(M, zbo, pa, pb, 0.2)
        poutre(M, zbo, pa, pm, 0.18); poutre(M, zbo, pb, pm, 0.18)
        poutre(M, zbo, pc, pm, 0.16)
        for s_ in (pa, pb):
            poutre(M, zbo, pc + [0, 0.15, 0], (s_ + pm) / 2, 0.12)
    zr = uni("rive", (226, 222, 214) if ty != "plat" else assombrir(mur_c, 0.9))
    def tile_quad(Q, col=TOIT_C):
        """Pan de toit (4 points monde) découpé en cases de 12 m (l'atlas ne se répète pas)."""
        Q = [np.asarray(q, float) for q in Q]
        lu = np.linalg.norm(Q[1] - Q[0]); lv = np.linalg.norm(Q[3] - Q[0])
        nu, nv = max(1, int(math.ceil(lu / 11.5))), max(1, int(math.ceil(lv / 11.5)))
        for i in range(nu):
            for j in range(nv):
                def P(a, b):
                    return Q[0] + (Q[1] - Q[0]) * a + (Q[3] - Q[0]) * b + (Q[2] - Q[1] - Q[3] + Q[0]) * a * b
                a0, a1, b0, b1 = i / nu, (i + 1) / nu, j / nv, (j + 1) / nv
                du, dv = lu / nu, lv / nv
                M.poly([P(a0, b0), P(a1, b0), P(a1, b1), P(a0, b1)],
                       [zt.uv(0, 0), zt.uv(du, 0), zt.uv(du, dv), zt.uv(0, dv)], col)
    def W3(px, pz, y):
        q = monde(px, pz)
        return (q[0], y, q[1])
    for (x0, z0, x1, z1, lx) in plans:
        if ty == "sheds":
            # toit en dents de scie (v6.30) : pans de couverture inclinés et verrières verticales, dents de « pas » m
            # le long du grand côté, pignons triangulaires sur les deux longs côtés
            pas = float(toit.get("pas", 6.0))
            zv = uni("verriere_shed", (70, 84, 96))
            zm2 = uni("mur_shed", mur_c)
            if lx:
                n_ = max(1, int(round((x1 - x0) / pas))); w_ = (x1 - x0) / n_
                for i in range(n_):
                    xa, xb = x0 + i * w_, x0 + (i + 1) * w_
                    tile_quad([W3(xa, z0, EG), W3(xa, z1, EG), W3(xb, z1, FA), W3(xb, z0, FA)])
                    M.poly([W3(xb, z0, EG), W3(xb, z1, EG), W3(xb, z1, FA), W3(xb, z0, FA)], uv4(zv), PETIT_C)
                    for zz in (z0, z1):
                        M.poly([W3(xa, zz, EG), W3(xb, zz, EG), W3(xb, zz, FA)], uv4(zm2)[:3], MUR_C)
            else:
                n_ = max(1, int(round((z1 - z0) / pas))); w_ = (z1 - z0) / n_
                for i in range(n_):
                    za, zb = z0 + i * w_, z0 + (i + 1) * w_
                    tile_quad([W3(x0, za, EG), W3(x1, za, EG), W3(x1, zb, FA), W3(x0, zb, FA)])
                    M.poly([W3(x0, zb, EG), W3(x1, zb, EG), W3(x1, zb, FA), W3(x0, zb, FA)], uv4(zv), PETIT_C)
                    for xx in (x0, x1):
                        M.poly([W3(xx, za, EG), W3(xx, zb, EG), W3(xx, zb, FA)], uv4(zm2)[:3], MUR_C)
            continue
        if ty == "berceau":
            # tunnel agricole (v6.31) : voûte en plein cintre de l'égout au faîtage, bouts fermés par la même bâche
            n_ = 10
            if lx:
                zm, hw = (z0 + z1) / 2, (z1 - z0) / 2
                prof = [(zm - hw * math.cos(math.pi * i / n_), EG + (FA - EG) * math.sin(math.pi * i / n_)) for i in range(n_ + 1)]
                P_ = lambda x, k: W3(x, prof[k][0], prof[k][1])
                ends = (x0, x1)
            else:
                xm, hw = (x0 + x1) / 2, (x1 - x0) / 2
                prof = [(xm - hw * math.cos(math.pi * i / n_), EG + (FA - EG) * math.sin(math.pi * i / n_)) for i in range(n_ + 1)]
                P_ = lambda zz, k: W3(prof[k][0], zz, prof[k][1])
                ends = (z0, z1)
            for k in range(n_):
                tile_quad([P_(ends[0], k), P_(ends[0], k + 1), P_(ends[1], k + 1), P_(ends[1], k)])
            for e in ends:
                for k in range(n_):
                    c0 = P_(e, 0); c1 = P_(e, n_)
                    base = ((c0[0] + c1[0]) / 2, EG, (c0[2] + c1[2]) / 2)
                    M.poly([base, P_(e, k), P_(e, k + 1)], uv4(zt)[:3], TOIT_C)
            continue
        if ty == "plat":
            tile_quad([W3(x0, z0, EG), W3(x0, z1, EG), W3(x1, z1, EG), W3(x1, z0, EG)])
            for (a, b), (p, q) in (((x0, z0), (x1, z0)), ((x1, z0), (x1, z1)), ((x1, z1), (x0, z1)), ((x0, z1), (x0, z0))):
                M.poly([W3(a, b, EG), W3(p, q, EG), W3(p, q, EG + 0.35), W3(a, b, EG + 0.35)], uv4(zr), PETIT_C)
            continue
        if not lx:          # on travaille dans un repère où le faîtage est le long de x
            pass
        X0, Z0, X1, Z1 = x0 - deb, z0 - deb, x1 + deb, z1 + deb
        if ty == "appentis":
            bas = B.face(toit.get("bas", "S"))
            # pente vers le côté « bas » : on choisit le bord (z0 ou z1, x0 ou x1) le plus aligné sur sa normale
            cands = {"z0": monde(0, -1) - monde(0, 0), "z1": monde(0, 1) - monde(0, 0),
                     "x0": monde(-1, 0) - monde(0, 0), "x1": monde(1, 0) - monde(0, 0)}
            kb = max(cands, key=lambda k: np.dot(cands[k], bas["n"]) if bas else (1 if k == "z1" else 0))
            yb, yh = EG - deb * 0.25, FA
            pts = {"z0": [(X0, Z0, yb), (X1, Z0, yb), (X1, Z1, yh), (X0, Z1, yh)],
                   "z1": [(X0, Z1, yb), (X0, Z0, yh), (X1, Z0, yh), (X1, Z1, yb)],
                   "x0": [(X0, Z0, yb), (X1, Z0, yh), (X1, Z1, yh), (X0, Z1, yb)],
                   "x1": [(X1, Z0, yb), (X1, Z1, yb), (X0, Z1, yh), (X0, Z0, yh)]}[kb]
            tile_quad([W3(*p) for p in pts])
            continue
        if lx:
            zm = (z0 + z1) / 2; pente = (FA - EG) / max(0.5, (z1 - z0) / 2)
            yb = EG - deb * pente
            if ty == "4pans":
                hx = min((z1 - z0) / 2, (x1 - x0) / 2)
                r0, r1 = x0 + hx, x1 - hx
                tile_quad([W3(X0, Z0, yb), W3(X1, Z0, yb), W3(r1, zm, FA), W3(r0, zm, FA)])
                tile_quad([W3(X1, Z1, yb), W3(X0, Z1, yb), W3(r0, zm, FA), W3(r1, zm, FA)])
                for (xa, xr) in ((X0, r0), (X1, r1)):
                    M.poly([W3(xa, Z0, yb), W3(xr, zm, FA), W3(xa, Z1, yb)], [zt.uv(0, 0), zt.uv(3, 4), zt.uv(6, 0)], TOIT_C)
            else:
                tile_quad([W3(X0, Z0, yb), W3(X1, Z0, yb), W3(X1, zm, FA), W3(X0, zm, FA)])
                tile_quad([W3(X1, Z1, yb), W3(X0, Z1, yb), W3(X0, zm, FA), W3(X1, zm, FA)])
                M.poly([W3(X0, zm - 0.12, FA + 0.05), W3(X1, zm - 0.12, FA + 0.05), W3(X1, zm + 0.12, FA + 0.12),
                        W3(X0, zm + 0.12, FA + 0.12)], uv4(zr), TOIT_C)
            for zz in (Z0, Z1):
                M.poly([W3(X0, zz, yb - 0.12), W3(X1, zz, yb - 0.12), W3(X1, zz, yb), W3(X0, zz, yb)], uv4(zr), PETIT_C)
            if R.get("ouvert") and ty == "2pans":
                for xx in np.linspace(x0, x1, max(2, int(round((x1 - x0) / 4.0)) + 1)):
                    ferme(W3(xx, z0, EG), W3(xx, z1, EG), W3(xx, zm, FA - 0.15))
        else:
            xm = (x0 + x1) / 2; pente = (FA - EG) / max(0.5, (x1 - x0) / 2)
            yb = EG - deb * pente
            if ty == "4pans":
                hz = min((z1 - z0) / 2, (x1 - x0) / 2)
                r0, r1 = z0 + hz, z1 - hz
                tile_quad([W3(X0, Z1, yb), W3(X0, Z0, yb), W3(xm, r0, FA), W3(xm, r1, FA)])
                tile_quad([W3(X1, Z0, yb), W3(X1, Z1, yb), W3(xm, r1, FA), W3(xm, r0, FA)])
                for (za, zr_) in ((Z0, r0), (Z1, r1)):
                    M.poly([W3(X0, za, yb), W3(xm, zr_, FA), W3(X1, za, yb)], [zt.uv(0, 0), zt.uv(3, 4), zt.uv(6, 0)], TOIT_C)
            else:
                tile_quad([W3(X0, Z1, yb), W3(X0, Z0, yb), W3(xm, Z0, FA), W3(xm, Z1, FA)])
                tile_quad([W3(X1, Z0, yb), W3(X1, Z1, yb), W3(xm, Z1, FA), W3(xm, Z0, FA)])
                M.poly([W3(xm - 0.12, Z0, FA + 0.05), W3(xm - 0.12, Z1, FA + 0.05), W3(xm + 0.12, Z1, FA + 0.12),
                        W3(xm + 0.12, Z0, FA + 0.12)], uv4(zr), TOIT_C)
            for xx in (X0, X1):
                M.poly([W3(xx, Z0, yb - 0.12), W3(xx, Z1, yb - 0.12), W3(xx, Z1, yb), W3(xx, Z0, yb)], uv4(zr), PETIT_C)
            if R.get("ouvert") and ty == "2pans":
                for zz in np.linspace(z0, z1, max(2, int(round((z1 - z0) / 4.0)) + 1)):
                    ferme(W3(x0, zz, EG), W3(x1, zz, EG), W3(xm, zz, FA - 0.15))
    # pignons (triangles), texture du côté porteur ; abri ouvert : pignons ouverts (fermes apparentes)
    for a, b, c in ([] if (R.get("ouvert") and not R.get("pignons_clos")) or ty == "berceau" else pignons):
        m = (a + b) / 2
        if c is not None:
            def u_de(p):
                return float(c["L"] - np.dot(p - c["p0"], (c["p1"] - c["p0"]) / c["L"]))
            z = c["z"]
            uvs = [z.uv(u_de(a), EG), z.uv(u_de(b), EG), z.uv(u_de(m), FA)]
            c.setdefault("pieces", []).append([(u_de(a), EG), (u_de(b), EG), (u_de(m), FA)])
        else:
            z = uni("mur", mur_c); uvs = [z.uv(0, 0), z.uv(1.5, 0), z.uv(0.75, 1.5)]
        M.poly([(a[0], EG, a[1]), (b[0], EG, b[1]), (m[0], FA, m[1])], uvs, MUR_C)
    # appentis : murs relevés jusqu'au toit sur les côtés hauts (trapèzes)
    if ty == "appentis":
        for c in B.cotes:
            if c["top"] > EG + 0.1:
                z = c["z"]; p0, p1, L = c["p0"], c["p1"], c["L"]
                c.setdefault("pieces", []).append([(0, EG), (L, EG), (L, FA), (0, FA)])
                M.poly([(p0[0], EG, p0[1]), (p1[0], EG, p1[1]), (p1[0], FA, p1[1]), (p0[0], FA, p0[1])],
                       [z.uv(L, EG), z.uv(0, EG), z.uv(0, FA), z.uv(L, FA)], MUR_C)
    if libre:
        from build_buildings import tri_polygon, boites as boites_de
        V, T = tri_polygon(B.g)
        V = V - B.c
        T = np.asarray(T).reshape(-1, 3)
        zp = uni("toit_plat", (112, 112, 108))
        mn, ex = V.min(0), np.maximum(V.max(0) - V.min(0), 1e-3)
        for t_ in T:
            q = [(V[i][0], EG, V[i][1]) for i in t_]
            M.poly(q, [zp.uv(1.5 * (V[i][0] - mn[0]) / ex[0], 1.5 * (V[i][1] - mn[1]) / ex[1]) for i in t_], TOIT_C,
                   np.array([0, 1.0, 0]))
        for c in B.cotes:
            p0, p1 = c["p0"], c["p1"]
            M.poly([(p0[0], EG, p0[1]), (p1[0], EG, p1[1]), (p1[0], EG + 0.35, p1[1]), (p0[0], EG + 0.35, p0[1])], uv4(zr), PETIT_C)
        PP = np.vstack([np.c_[V[:, 0], np.full(len(V), B.BAS), V[:, 1]], np.c_[V[:, 0], np.full(len(V), EG), V[:, 1]]])
        boites += [list(b) for b in boites_de(PP, T.ravel())]
    # ---- collisions : un rectangle = une boîte
    lacet = -ang
    for (x0, z0, x1, z1, lx) in ([] if R.get("ouvert") else plans):
        q = monde((x0 + x1) / 2, (z0 + z1) / 2)
        h = EG if ty != "plat" else EG + 0.35
        boites.append([q[0], (B.BAS + h) / 2, q[1], (x1 - x0) / 2, (h - B.BAS) / 2, (z1 - z0) / 2, lacet])
    # ---- décors en volume
    for e in R.get("extras", []):
        t = e["t"]
        c = B.face(e["face"]) if "face" in e else None
        if t in ("auvent", "porche", "marquise", "store") and c is not None:
            f0, f1 = e.get("x", [0.3, 0.7])
            y, p = float(e.get("y", 3.0)), float(e.get("p", 1.2))
            a, b = B.pt_face(c, f0), B.pt_face(c, f1)
            ao, bo = a + c["n"] * p, b + c["n"] * p
            col = hexc(e.get("c"), (150, 78, 56) if t == "porche" else (90, 92, 96))
            if t == "store":
                zs = uni("store" + e.get("c", ""), col)
                M.poly([(a[0], y, a[1]), (b[0], y, b[1]), (bo[0], y - 0.6, bo[1]), (ao[0], y - 0.6, ao[1])], uv4(zs), PETIT_C)
                M.poly([(ao[0], y - 0.6, ao[1]), (bo[0], y - 0.6, bo[1]), (bo[0], y - 0.85, bo[1]), (ao[0], y - 0.85, ao[1])], uv4(zs), PETIT_C)
                continue
            if t == "porche":
                tile_quad([(ao[0], y, ao[1]), (bo[0], y, bo[1]), (b[0], y + 0.6, b[1]), (a[0], y + 0.6, a[1])])
                zb = uni("bois", (110, 76, 46))
                for q in (ao, bo):
                    M_post(M, zb, q - c["n"] * 0.1, y)
            else:
                zm_ = uni("auvent" + e.get("c", ""), col)
                M.poly([(a[0], y, a[1]), (b[0], y, b[1]), (bo[0], y - 0.15, bo[1]), (ao[0], y - 0.15, ao[1])], uv4(zm_), PETIT_C)
                M.poly([(ao[0], y - 0.15, ao[1]), (bo[0], y - 0.15, bo[1]), (bo[0], y - 0.35, bo[1]), (ao[0], y - 0.35, ao[1])], uv4(zm_), PETIT_C)
        elif t == "charpente" and c is not None:
            # grand porche ouvert à charpente apparente (v6.28) : toit à deux pans sorti de la façade, pignon vers
            # l'extérieur, poteaux et ferme en bois (entrait, arbalétriers, poinçon, contrefiches) en volume
            f0, f1 = e.get("x", [0.2, 0.6])
            y, p = float(e.get("y", 3.0)), float(e.get("p", 5.0))
            hf = float(e.get("h", y + 2.4))
            a, b = B.pt_face(c, f0), B.pt_face(c, f1)
            n = c["n"]
            m = (a + b) / 2
            dbd = 0.5
            A3 = lambda q, yy: (float(q[0]), yy, float(q[1]))
            ao, bo, mo = a + n * (p + dbd), b + n * (p + dbd), m + n * (p + dbd)
            tile_quad([A3(a, y), A3(ao, y), A3(mo, hf), A3(m, hf)])
            tile_quad([A3(m, hf), A3(mo, hf), A3(bo, y), A3(b, y)])
            zb = uni("bois" + e.get("c", ""), hexc(e.get("c"), (128, 84, 48)))
            ap, bp, mp = a + n * p, b + n * p, m + n * p
            nb = max(1, int(round(p / 4.0)))
            for k in range(nb + 1):                               # fermes : en façade, puis tous les ~4 m
                t_ = k / nb
                if t_ == 0:
                    continue
                aa, bb, mm = a + n * p * t_, b + n * p * t_, m + n * p * t_
                poutre(M, zb, A3(aa, y), A3(bb, y), 0.2)                  # entrait
                poutre(M, zb, A3(aa, y), A3(mm, hf - 0.1), 0.18)          # arbalétriers
                poutre(M, zb, A3(bb, y), A3(mm, hf - 0.1), 0.18)
                poutre(M, zb, A3(mm, y), A3(mm, hf - 0.1), 0.16)          # poinçon
                for s_ in (aa, bb):                                       # contrefiches
                    q1 = (np.asarray(s_) + mm) / 2
                    poutre(M, zb, A3(mm, y + 0.15), A3(q1, y + (hf - y) / 2), 0.12)
                for q in (aa, bb):
                    M_box(M, zb, q, 0.0, 0.11, 0.11, 0.0, y)              # poteaux
                    boites.append([float(q[0]), y / 2, float(q[1]), 0.12, y / 2, 0.12, 0.0])
            poutre(M, zb, A3(m, hf - 0.1), A3(mp, hf - 0.1), 0.18)        # faîtière
            for s_, o_ in ((a, ap), (b, bp)):                             # sablières
                poutre(M, zb, A3(s_, y), A3(o_, y), 0.18)
        elif t in ("applique", "poubelle") and c is not None:
            for f in (e["x"] if isinstance(e["x"], list) else [e["x"]]):
                q = B.pt_face(c, f, 0.12 if t == "applique" else 0.45)
                ax_ = math.atan2(c["n"][1], c["n"][0])
                if t == "applique":
                    z_ = uni("lampe", (214, 218, 222))
                    M_box(M, z_, q, ax_, 0.12, 0.2, float(e.get("y", 3.0)), float(e.get("y", 3.0)) + 0.25)
                else:
                    z_ = uni("poubelle" + e.get("c", ""), hexc(e.get("c"), (60, 66, 70)))
                    M_box(M, z_, q, ax_, 0.3, 0.3, 0.0, 1.05)
        elif t in ("cuve", "silo") and c is not None:
            q = B.pt_face(c, float(e.get("x", 0.5)), float(e.get("d", 2.5)))
            r, h = float(e.get("r", 1.2)), float(e.get("h", 3.0))
            z_ = uni(t + e.get("c", ""), hexc(e.get("c"), (200, 204, 206)))
            cylindre(M, z_, q, r, 0.0, h, cone=(r * 0.5 if t == "silo" else 0.0))
            boites.append([q[0], h / 2, q[1], r * 0.8, h / 2, r * 0.8, 0.0])
        elif t == "clocher" and c is not None:
            q = B.pt_face(c, float(e.get("x", 0.5)), -float(e.get("w", 4)) / 2 + float(e.get("saillie", 0.0)))
            w, h, fl = float(e.get("w", 4)), float(e.get("h", 16)), float(e.get("fleche", 8))
            ax_ = math.atan2(c["n"][1], c["n"][0])
            zc = uni("clocher", mur_c)
            M_box(M, zc, q, ax_, w / 2, w / 2, B.BAS, h)
            # abat-sons (aplats sombres) sur les quatre faces
            za = uni("abatson", (60, 50, 44))
            for k in range(4):
                a_ = ax_ + k * math.pi / 2
                nn = np.array([math.cos(a_), math.sin(a_)]); tt = np.array([-nn[1], nn[0]])
                o = q + nn * (w / 2 + 0.01)
                pa, pb = o - tt * w * 0.2, o + tt * w * 0.2
                M.poly([(pa[0], h - 3.2, pa[1]), (pb[0], h - 3.2, pb[1]), (pb[0], h - 1.2, pb[1]), (pa[0], h - 1.2, pa[1])], uv4(za), PETIT_C)
            zf = uni("fleche", hexc(e.get("c_fleche"), (90, 96, 104)))
            for k in range(4):
                a_ = ax_ + k * math.pi / 2 + math.pi / 4
                b_ = a_ + math.pi / 2
                rr = w / 2 * math.sqrt(2) + 0.2
                pa = q + rr * np.array([math.cos(a_), math.sin(a_)]); pb = q + rr * np.array([math.cos(b_), math.sin(b_)])
                M.poly([(pa[0], h, pa[1]), (pb[0], h, pb[1]), (q[0], h + fl, q[1])], uv4(zf)[:3], TOIT_C)
            boites.append([q[0], (B.BAS + h) / 2, q[1], w / 2, (h - B.BAS) / 2, w / 2, -ax_])
        elif t == "contreforts" and c is not None:
            zc = uni("contrefort", assombrir(mur_c, 0.95))
            ax_ = math.atan2(c["n"][1], c["n"][0])
            for f in e["x"]:
                q = B.pt_face(c, f, 0.4)
                M_box(M, zc, q, ax_, 0.4, 0.35, B.BAS, float(e.get("h", EG * 0.8)))
        elif t == "cheminee" and plans:
            q = monde(*[(lo + (hi - lo) * fr) for (lo, hi), fr in zip(((plans[0][0], plans[0][2]), (plans[0][1], plans[0][3])),
                                                                        (e.get("x", 0.3), e.get("y", 0.5)))])
            zc = uni("cheminee", hexc(e.get("c"), mur_c))
            M_box(M, zc, q, -ang, 0.3, 0.3, EG, FA + 0.8)
    if MODE_BIB:
        A = _compacter(B, A, M, mt, zt, unis, decors)
    return B, A, M, boites


def _sous_zone(z, u0, v0, u1, v1):
    a, b = z.px(max(0.0, u0), v1), z.px(u1, max(0.0, v0))
    x0, y0 = int(round(a[0])), int(round(a[1]))
    return Zone(z.img, z.msk, x0, y0, max(1, int(round(b[0])) - x0), max(1, int(round(b[1])) - y0), z.s), (x0, y0)


def _panneau(c, z, u0, v0, u1, v1, mat):
    """Mode bibliothèque : bande d'une autre matière (soubassement, bardage haut…) : peinte dans la zone (pour les
    marges des décalcomanies qui la chevauchent) et posée en panneau de la bibliothèque, 6 mm devant le mur."""
    sz, _ = _sous_zone(z, u0, v0, u1, v1)
    _fond_cale(z, sz, mat)
    c.setdefault("panneaux", []).append((max(0.0, u0), max(0.0, v0), u1, v1, mat))


def _fond_cale(z, sz, mat):
    """Motif de la bibliothèque dans une sous-zone, calé sur l'origine de la façade (même raccord que le shader)."""
    k = BIB.kind_de(mat); col = np.array(BIB.couleur(mat), np.float32) / np.array(BIB.BASE, np.float32)
    per = max(4, int(round(BIB.PERIODE * z.s)))
    t = np.asarray(BIB.tuile(k).resize((per, per), Image.LANCZOS)).astype(np.float32)
    w, h = int(sz.w), int(sz.h)
    H = int(math.ceil(z.h))
    gx = np.arange(w) + (sz.x0 - z.x0); gy = np.arange(h) + (sz.y0 - z.y0)
    xs = (gx * per / (BIB.PERIODE * z.s)).astype(np.int64) % per
    ys = ((gy - H) * per / (BIB.PERIODE * z.s)).astype(np.int64) % per
    img = t[ys][:, xs] * col
    z.img.paste(Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)), (int(sz.x0), int(sz.y0)))


def _compacter(B, A, M, mt, zt, unis, decors):
    """Mode bibliothèque : (1) les sommets des murs et des toits passent en coordonnées de la bibliothèque (mètres /
    PERIODE, UV2 = (case + 1, couleur RVB entière)) ; (2) ce qui diffère du fond sur chaque façade est découpé en
    décalcomanies (rectangles, découpés aux morceaux visibles de la façade) posées 9 mm devant le mur ; (3) un petit
    atlas reçoit ces décalcomanies, les enseignes et les petites cases unies. Renvoie le nouvel Atlas."""
    T = A.T
    faces = [c for c in B.cotes if c.get("z") is not None]
    autres = list(unis.values()) + [d[5] for d in decors]
    def rect(z):
        return (z.x0 - 1.5, z.y0 - 1.5, z.x0 + z.w + 1.5, z.y0 + z.h + 1.5)
    def dans(r, x, y):
        return r[0] <= x <= r[2] and r[1] <= y <= r[3]
    def packe(c):
        return float((c[0] << 16) | (c[1] << 8) | c[2])
    # ---- décalcomanies : ce qui diffère du fond de la bibliothèque, par façade
    items = []                                     # (x0, y0, w, h) dans l'atlas de travail, zone ou None
    decals = []                                    # (face, (x0, y0, x1, y1) px de la zone, index de l'item)
    img = np.asarray(A.img).astype(np.int16); msk = np.asarray(A.msk)
    for c in faces:
        z = c["z"]
        x0, y0 = int(round(z.x0)), int(round(z.y0)); w, h = int(math.ceil(z.w)), int(math.ceil(z.h))
        fin = img[y0:y0 + h, x0:x0 + w]
        t_img = Image.new("RGB", (w, h)); t_msk = Image.new("L", (w, h))
        tz = Zone(t_img, t_msk, 0, 0, w, h, z.s)
        BIB.fond(tz, c["mat"])
        for (pu0, pv0, pu1, pv1, pm) in c.get("panneaux", []):
            sz, _ = _sous_zone(tz, pu0, pv0, pu1, pv1)
            _fond_cale(tz, sz, pm)
        bg = np.asarray(t_img).astype(np.int16)
        diff = (np.abs(fin - bg).max(-1) > 3) | (msk[y0:y0 + h, x0:x0 + w] > 0)
        if not diff.any():
            continue
        diff = _ndi.binary_dilation(diff, iterations=2)
        lab, n = _ndi.label(diff)
        boxes = [[sl[1].start, sl[0].start, sl[1].stop, sl[0].stop] for sl in _ndi.find_objects(lab)]
        fus = True
        while fus:                                  # boîtes qui se touchent : fusionnées
            fus = False
            for i in range(len(boxes)):
                for j in range(i + 1, len(boxes)):
                    a, b = boxes[i], boxes[j]
                    if a[0] <= b[2] + 2 and b[0] <= a[2] + 2 and a[1] <= b[3] + 2 and b[1] <= a[3] + 2:
                        boxes[i] = [min(a[0], b[0]), min(a[1], b[1]), max(a[2], b[2]), max(a[3], b[3])]
                        del boxes[j]; fus = True; break
                if fus:
                    break
        MAXW = 256                                   # bandes longues (soubassements…) en morceaux
        for bx in boxes:
            bx = [max(0, bx[0]), max(0, bx[1]), min(w, bx[2]), min(h, bx[3])]
            xa = bx[0]
            while xa < bx[2]:
                xb = min(bx[2], xa + MAXW)
                p_ = [xa, bx[1], xb, bx[3]]
                items.append((x0 + p_[0], y0 + p_[1], p_[2] - p_[0], p_[3] - p_[1]))
                decals.append((c, p_, len(items) - 1))
                xa = xb
    base_autres = len(items)
    for z in autres:
        items.append((int(round(z.x0)) - 1, int(round(z.y0)) - 1, int(math.ceil(z.w)) + 2, int(math.ceil(z.h)) + 2))
    # ---- rangement dans le petit atlas (étagères ; 2 px de bord recopié autour de chaque morceau) : atlas
    #      rectangulaire (largeur du plus large morceau, hauteur au plus juste, multiples de 16)
    PAD = 2
    aire = sum((w + 2 * PAD) * (h + 2 * PAD) for _, _, w, h in items)
    larg = max([w + 2 * PAD for _, _, w, _ in items] + [64])
    Wt = int(math.ceil(max(larg, math.sqrt(aire * 1.15)) / 16.0) * 16)
    place, x, y, hl = {}, 0, 0, 0
    for i in sorted(range(len(items)), key=lambda i: -items[i][3]):
        w, h = items[i][2] + 2 * PAD, items[i][3] + 2 * PAD
        if x + w > Wt:
            x, y, hl = 0, y + hl, 0
        place[i] = (x + PAD, y + PAD); x += w; hl = max(hl, h)
    Ht = int(math.ceil(max(16, y + hl) / 16.0) * 16)
    taille = Wt
    N = Atlas(16)
    N.T, N.H = Wt, Ht
    src_i = np.asarray(A.img); src_m = np.asarray(A.msk)
    out_i = np.zeros((Ht, Wt, 3), np.uint8) + 128; out_m = np.zeros((Ht, Wt), np.uint8)
    for i, (sx, sy, w, h) in enumerate(items):
        dx, dy = place[i]
        bi = np.pad(src_i[sy:sy + h, sx:sx + w], ((PAD, PAD), (PAD, PAD), (0, 0)), mode="edge")
        bm = np.pad(src_m[sy:sy + h, sx:sx + w], ((PAD, PAD), (PAD, PAD)), mode="edge")
        out_i[dy - PAD:dy + h + PAD, dx - PAD:dx + w + PAD] = bi
        out_m[dy - PAD:dy + h + PAD, dx - PAD:dx + w + PAD] = bm
    N.img = Image.fromarray(out_i); N.msk = Image.fromarray(out_m)
    # ---- sommets existants : bibliothèque (murs, toits) ou nouvelle place (cases unies, enseignes)
    rf = [(rect(c["z"]), c) for c in faces]
    rt = rect(zt)
    ra = [(rect(z), base_autres + k, z) for k, z in enumerate(autres)]
    M.UV2 = []
    for i, (u, v) in enumerate(M.UV):
        x, y = u * T, v * T
        uv2 = (0.0, 255.0, 255.0, 255.0)
        for r, c in rf:
            if dans(r, x, y):
                z = c["z"]
                mu, mv = (x - z.x0) / z.s, (z.y0 + z.h - y) / z.s
                M.UV[i] = (mu / BIB.PERIODE, -mv / BIB.PERIODE)
                uv2 = (BIB.slot(c["mat"]) + 1.0,) + tuple(BIB.couleur(c["mat"]))
                break
        else:
            if dans(rt, x, y):
                mu, mv = (x - zt.x0) / zt.s, (zt.y0 + zt.h - y) / zt.s
                M.UV[i] = (mu / BIB.PERIODE, -mv / BIB.PERIODE)
                uv2 = (BIB.slot(mt, True) + 1.0,) + tuple(BIB.couleur(mt, True))
            else:
                for r, k, z in ra:
                    if dans(r, x, y):
                        sx, sy = items[k][0], items[k][1]
                        dx, dy = place[k]
                        M.UV[i] = ((x - sx + dx) / Wt, (y - sy + dy) / Ht)
                        break
        M.UV2.append(uv2)
    from shapely.geometry import box as _box
    # ---- panneaux de la bibliothèque (soubassements, bandes d'autre matière), 6 mm devant le mur
    for c in faces:
        n3 = (c["n"][0], 0.0, c["n"][1])
        for (pu0, pv0, pu1, pv1, pm) in c.get("panneaux", []):
            for pc in c.get("pieces", []):
                inter = _box(pu0, pv0, pu1, pv1).intersection(Polygon(pc))
                if inter.is_empty or inter.area < 1e-4 or inter.geom_type != "Polygon":
                    continue
                pts = list(inter.exterior.coords)[:-1]
                def P6(uu, vv):
                    q = c["p1"] + (c["p0"] - c["p1"]) * (uu / c["L"]) + c["n"] * 0.006
                    return (q[0], vv, q[1])
                o = len(M.P)
                M.poly([P6(a, b) for a, b in pts], [(a / BIB.PERIODE, -b / BIB.PERIODE) for a, b in pts], MUR_C, n3)
                M.UV2 += [(BIB.slot(pm) + 1.0,) + tuple(BIB.couleur(pm))] * (len(M.P) - o)
    # ---- décalcomanies en aplat, 9 mm devant le mur (entre panneaux à 6 mm et enseignes à 1,2 cm), découpées aux morceaux visibles de la façade
    for c, bx, k in decals:
        z = c["z"]; s_ = z.s; h = int(math.ceil(z.h))
        u0, u1 = bx[0] / s_, bx[2] / s_
        v0, v1 = (h - bx[3]) / s_, (h - bx[1]) / s_
        db = _box(u0, v0, u1, v1)
        dx, dy = place[k]
        n3 = (c["n"][0], 0.0, c["n"][1])
        for pc in c.get("pieces", []):
            inter = db.intersection(Polygon(pc))
            if inter.is_empty or inter.area < 1e-4 or inter.geom_type != "Polygon":
                continue
            pts = list(inter.exterior.coords)[:-1]
            def P_(uu, vv):
                q = c["p1"] + (c["p0"] - c["p1"]) * (uu / c["L"]) + c["n"] * 0.009
                return (q[0], vv, q[1])
            def UVd(uu, vv):
                px_ = uu * s_ - bx[0] + dx
                py_ = (h - vv * s_) - bx[1] + dy
                return (px_ / Wt, py_ / Ht)
            o = len(M.P)
            M.poly([P_(a, b) for a, b in pts], [UVd(a, b) for a, b in pts], MUR_C, n3)
            M.UV2 += [(0.0, 255.0, 255.0, 255.0)] * (len(M.P) - o)
    eg = float(B.EG)
    M.C = [tuple(cc[:3]) + (eg / 64.0,) for cc in M.C]
    return N


def M_box(M, z, q, ax, hx, hz, y0, y1):
    """Petite boîte centrée en q (monde relatif), tournée de ax (rad, autour de y), demi-tailles hx (le long de n), hz."""
    ca, sa = math.cos(ax), math.sin(ax)
    def W(u, v, y):
        return (q[0] + u * ca - v * sa, y, q[1] + u * sa + v * ca)
    uv = uv4(z)
    C = [(-hx, -hz), (hx, -hz), (hx, hz), (-hx, hz)]
    for i in range(4):
        (a, b), (p, r) = C[i], C[(i + 1) % 4]
        M.poly([W(a, b, y0), W(p, r, y0), W(p, r, y1), W(a, b, y1)], uv, PETIT_C)
    M.poly([W(-hx, -hz, y1), W(-hx, hz, y1), W(hx, hz, y1), W(hx, -hz, y1)], uv, PETIT_C)


def poutre(M, z, p0, p1, w=0.16):
    """Poutre de section carrée w entre deux points 3D (monde relatif) : charpentes apparentes."""
    p0, p1 = np.asarray(p0, float), np.asarray(p1, float)
    d = p1 - p0
    e1 = np.cross(d, [0.0, 1.0, 0.0])
    if np.linalg.norm(e1) < 1e-6:
        e1 = np.array([1.0, 0.0, 0.0])
    e1 = e1 / np.linalg.norm(e1) * w / 2
    e2 = np.cross(e1, d); e2 = e2 / (np.linalg.norm(e2) + 1e-9) * w / 2
    C = [e1 + e2, -e1 + e2, -e1 - e2, e1 - e2]
    uv = uv4(z)
    for i in range(4):
        a, b = C[i], C[(i + 1) % 4]
        M.poly([p0 + a, p0 + b, p1 + b, p1 + a], uv, PETIT_C)


def M_post(M, z, q, h):
    M_box(M, z, q, 0.0, 0.08, 0.08, 0.0, h)


def cylindre(M, z, q, r, y0, y1, cone=0.0, n=12):
    uv = uv4(z)
    for k in range(n):
        a0, a1 = 2 * math.pi * k / n, 2 * math.pi * (k + 1) / n
        p0 = (q[0] + r * math.cos(a0), q[1] + r * math.sin(a0)); p1 = (q[0] + r * math.cos(a1), q[1] + r * math.sin(a1))
        M.poly([(p0[0], y0, p0[1]), (p1[0], y0, p1[1]), (p1[0], y1, p1[1]), (p0[0], y1, p0[1])], uv, PETIT_C)
        M.poly([(p0[0], y1, p0[1]), (p1[0], y1, p1[1]), (q[0], y1 + cone, q[1])], uv[:3], PETIT_C)


def toiture(z, mt, seed):
    img = z.img
    x0, y0, x1, y1 = int(z.x0), int(z.y0), int(z.x0 + z.w), int(z.y0 + z.h)
    d = ImageDraw.Draw(img)
    r = random.Random(seed)
    kind = mt.split("#")[0]
    base = {"tuile": (150, 78, 56), "tuile_brune": (120, 72, 52), "ardoise": (70, 74, 82), "fibro": (176, 176, 168),
            "bac": (150, 60, 50)}.get(kind, (150, 78, 56))
    base = hexc(mt, base)
    d.rectangle((x0, y0, x1, y1), fill=base)
    s = z.s
    if kind in ("tuile", "tuile_brune", "ardoise"):
        rh, rw = (0.33, 0.25) if kind != "ardoise" else (0.2, 0.3)
        y = y0
        while y < y1:
            x = x0 - r.uniform(0, rw * s)
            while x < x1:
                d.rectangle([x, y, x + rw * s - 1, y + rh * s - 1], fill=assombrir(base, r.uniform(0.86, 1.1)))
                x += rw * s
            d.line([x0, y + rh * s - 1, x1, y + rh * s - 1], fill=assombrir(base, 0.62))
            y += rh * s
    else:                                         # bac acier / fibrociment : ondes parallèles à la pente (verticales)
        pas = 0.2 if kind == "bac" else 0.18
        x = x0
        while x < x1:
            d.line([x, y0, x, y1], fill=assombrir(base, 0.75), width=max(1, int(0.04 * s)))
            x += pas * s
    bruit(img, (x0, y0, x1, y1), 4, grain=2.0, seed=seed)


def deux_faces(P, N, UV, I, C, UV2=None):
    """v6.26 : le shader est en cull_back (en cull_disabled, les faces arrière des grands murs plats s'ombraient
    elles-mêmes : acné d'ombre en anneaux). Triangles orientés selon leurs normales (write_glb fix_winding) ; seuls
    les toits et les petits volumes (débords, auvents, marquises : leur dessous se voit de la rue) sont doublés côté
    intérieur, normales inversées. Les murs (couleur de sommet b > 0,5) restent à une face."""
    T = I.reshape(-1, 3)
    dbl = T[C[T[:, 0], 2] < 0.5]
    if len(dbl):
        u = np.unique(dbl)
        remap = np.full(len(P), -1, np.int64); remap[u] = len(P) + np.arange(len(u))
        P = np.vstack([P, P[u]]); N = np.vstack([N, -N[u]]); UV = np.vstack([UV, UV[u]]); C = np.vstack([C, C[u]])
        if UV2 is not None:
            UV2 = np.vstack([UV2, UV2[u]])
        T = np.vstack([T, remap[dbl][:, ::-1]])
    return ("facade", P, N, UV, T.astype(np.uint32).ravel(), C, UV2)


def main():
    from build_buildings import CarvedDEM
    dem = CarvedDEM()
    feats = {f["properties"]["cleabs"]: f for f in json.load(open(os.path.join(PIPE, "data/batiments.json")))["features"]}
    voulus = set(sys.argv[1:])
    sp = os.path.join(GOD, "world", "sur_mesure.json")
    pose = json.load(open(sp)) if os.path.exists(sp) else {}
    os.makedirs(OUT_A, exist_ok=True)
    todo = []
    for p in sorted(glob.glob(os.path.join(ICI, "releves", "*.json"))):
        R0 = json.load(open(p))
        if voulus and R0["id"] not in voulus:
            continue
        for k in list(pose):                               # anciens volumes de ce bâtiment
            if k.startswith(R0["id"] + "_") and k[len(R0["id"]) + 1:].isdigit():
                del pose[k]
        vols = volumes(R0, feats[R0["cleabs"]])
        todo += [(R, k == 0) for k, R in enumerate(vols)]
    for R, premier in todo:
        B = None
        for remplir in (0.4, 0.3, 0.22, 0.15, 0.1, 0.06):  # atlas plein : façades moins détaillées
            try:
                B, A, M, boites = construire(R, feats[R["cleabs"]], dem, remplir)
                break
            except ValueError:
                continue
        if B is None:                                       # jamais le modèle du bâtiment précédent
            print("%-22s ÉCHEC : atlas trop petit" % R["id"])
            continue
        out = Image.merge("RGBA", (*A.img.split(), A.msk))
        out.save(os.path.join(OUT_A, R["id"] + ".png"))
        uv2 = np.array(M.UV2, np.float32) if getattr(M, "UV2", None) is not None and len(M.UV2) == len(M.P) else None
        prim = deux_faces(np.array(M.P, np.float32), np.array(M.N, np.float32), np.array(M.UV, np.float32),
                          np.array(M.I, np.uint32), np.array(M.C, np.float32), uv2)
        if uv2 is not None:                                 # v6.38 : UV2 = (case + 1, couleur RVB entière, exacte en float32)
            nom, P_, N_, UV_, I_, C_, U2 = prim
            rgb = np.round(U2[:, 1:4]).astype(np.int64)
            packe = ((rgb[:, 0] << 16) | (rgb[:, 1] << 8) | rgb[:, 2]).astype(np.float32)
            prim = (nom, P_, N_, UV_, I_, C_, np.c_[U2[:, 0], packe].astype(np.float32))
        write_glb(os.path.join(OUT_A, R["id"] + ".glb"), {R["id"]: [prim]}, fix_winding=True)
        pose[R["id"]] = {"boites": [[round(float(v), 3) for v in b] for b in boites],
                         "glb": "res://assets/sur_mesure/%s.glb" % R["id"], "atlas": "res://assets/sur_mesure/%s.png" % R["id"],
                         "pos": [round(float(B.c[0]), 3), round(B.sol, 3), round(float(B.c[1]), 3)],
                         "remplace_bati": ([R["cleabs"]] + R.get("remplace_bati_extra", [])) if premier else [], "remplace_commerce": R.get("remplace_commerce", []),
                         "nom": R.get("nom", R["id"]), "une_face": True}
        print("%-22s %5d triangles, %d boîtes, atlas %d px/m, %d × %d px" % (R["id"], len(M.I) // 3, len(boites),
                                                                  int(B.cotes[0]["z"].s), A.T, getattr(A, "H", A.T)))
    json.dump(pose, open(sp, "w"), indent=1, ensure_ascii=False)


if __name__ == "__main__":
    main()
