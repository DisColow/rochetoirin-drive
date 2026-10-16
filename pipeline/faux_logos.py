"""Faux logos des voitures du garage (#95, choix de l'utilisateur : « faux logo et noms parodiés ») :
  - emblèmes dessinés ici -> ../godot/import/voitures/_logos/<marque>.png (posés en relief par
    blender_voitures_joueur.py à la place des badges en volume) ;
  - textures photo (Clio, 106) : badge et nom de la marque effacés (comblés avec la carrosserie autour), faux
    emblème peint à sa place. Les textures d'origine sont gardées à côté (*.orig.png) : le script repart toujours
    d'elles.
Marques : Renaud (hexagone et R), Pijo (tête de chat), Citrouille (citrouille), Porc'Che (écusson au groin)."""
import math, os, shutil
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "godot", "import", "voitures")
LOGOS = os.path.join(SRC, "_logos")
CHROME = (205, 208, 214, 255)
SOMBRE = (40, 42, 48, 255)

# textures photo : zones à effacer (x0, y0, x1, y1, en pixels de la texture d'origine) et emblèmes à peindre
RETOUCHES = {
    "clio": ("textures/Material_baseColor.png",
             [(325, 296, 346, 301), (405, 296, 417, 301)],                       # « RENAULT », « Clio » (hayon)
             [((369, 305, 377, 313), "renaud"), ((370, 424, 379, 433), "renaud")]),   # losanges arrière, avant
    # 2 CV : doubles chevrons peints sur la calandre (même atlas pour « material » et « Grid », relief dans la normale)
    "deuche": (["textures/material_baseColor.png", "textures/Grid_baseColor.png", "textures/Grid_normal.png"],
               [(3105, 2228, 3446, 2437)],
               [((3165, 2222, 3385, 2442), "citrouille")]),
    "p106": ("textures/unnamed.036_baseColor.png",
             [(110, 126, 129, 131), (212, 126, 232, 131)],                       # « PEUGEOT », « 106 »
             [((163, 76, 179, 87), "pijo"), ((165, 121, 175, 131), "pijo")]),        # lions avant, arrière
}


def renaud(d, s):
    c = s / 2
    pts = [(c + math.sin(a) * s * 0.36, c - math.cos(a) * s * 0.46) for a in [k * math.pi / 3 for k in range(6)]]
    d.polygon(pts, fill=CHROME)
    pts2 = [(c + (x - c) * 0.72, c + (y - c) * 0.72) for x, y in pts]
    d.polygon(pts2, fill=SOMBRE)
    w = s * 0.07
    d.line([(c - s * 0.1, c + s * 0.2), (c - s * 0.1, c - s * 0.2)], fill=CHROME, width=int(w))
    d.arc([c - s * 0.16, c - s * 0.2, c + s * 0.12, c], -90, 90, fill=CHROME, width=int(w))
    d.line([(c - s * 0.02, c), (c + s * 0.12, c + s * 0.2)], fill=CHROME, width=int(w))


def pijo(d, s):
    c = s / 2
    d.ellipse([s * 0.06, s * 0.06, s * 0.94, s * 0.94], fill=CHROME)
    d.ellipse([s * 0.14, s * 0.14, s * 0.86, s * 0.86], fill=SOMBRE)
    d.ellipse([c - s * 0.24, c - s * 0.12, c + s * 0.24, c + s * 0.28], fill=CHROME)          # tête du chat
    d.polygon([(c - s * 0.24, c), (c - s * 0.22, c - s * 0.32), (c - s * 0.05, c - s * 0.1)], fill=CHROME)
    d.polygon([(c + s * 0.24, c), (c + s * 0.22, c - s * 0.32), (c + s * 0.05, c - s * 0.1)], fill=CHROME)
    for sx in (-1, 1):
        d.ellipse([c + sx * s * 0.1 - s * 0.04, c + s * 0.02, c + sx * s * 0.1 + s * 0.04, c + s * 0.1], fill=SOMBRE)


def citrouille(d, s):
    c = s / 2
    for dx in (-0.2, 0.2, 0.0):
        d.ellipse([c + dx * s - s * 0.26, c - s * 0.24, c + dx * s + s * 0.26, c + s * 0.36], fill=CHROME,
                  outline=SOMBRE, width=max(1, int(s * 0.03)))
    d.rectangle([c - s * 0.04, c - s * 0.4, c + s * 0.04, c - s * 0.22], fill=CHROME)


def porcche(d, s):
    c = s / 2
    d.polygon([(s * 0.12, s * 0.1), (s * 0.88, s * 0.1), (s * 0.88, s * 0.55), (c, s * 0.95), (s * 0.12, s * 0.55)],
              fill=(212, 170, 60, 255))
    d.polygon([(s * 0.18, s * 0.16), (s * 0.82, s * 0.16), (s * 0.82, s * 0.53), (c, s * 0.86), (s * 0.18, s * 0.53)],
              fill=(160, 30, 30, 255))
    d.ellipse([c - s * 0.2, c - s * 0.1, c + s * 0.2, c + s * 0.18], fill=(240, 150, 170, 255))      # groin
    for sx in (-1, 1):
        d.ellipse([c + sx * s * 0.08 - s * 0.04, c - s * 0.0, c + sx * s * 0.08 + s * 0.04, c + s * 0.08],
                  fill=(120, 40, 60, 255))


DESSINS = {"renaud": renaud, "pijo": pijo, "citrouille": citrouille, "porcche": porcche}


def emblème(marque, taille):
    k = 8
    im = Image.new("RGBA", (taille * k, taille * k), (0, 0, 0, 0))
    DESSINS[marque](ImageDraw.Draw(im), taille * k)
    return im.resize((taille, taille), Image.LANCZOS)


def effacer(im, box):
    """Comble la zone avec la carrosserie autour : interpolation verticale entre la ligne du dessus et du dessous."""
    x0, y0, x1, y1 = box
    px = im.load()
    for x in range(x0, x1):
        a = px[x, max(0, y0 - 1)]; b = px[x, min(im.height - 1, y1)]
        for y in range(y0, y1):
            t = (y - y0 + 1) / (y1 - y0 + 1)
            px[x, y] = tuple(int(a[i] * (1 - t) + b[i] * t) for i in range(len(a)))


def main():
    os.makedirs(LOGOS, exist_ok=True)
    for m in DESSINS:
        emblème(m, 256).save(os.path.join(LOGOS, m + ".png"))
    for cid, (texs, zones, logos) in RETOUCHES.items():
        for tex in ([texs] if isinstance(texs, str) else texs):
            f = os.path.join(SRC, cid, tex)
            orig = f[:-4] + ".orig.png"
            if not os.path.exists(orig):
                shutil.copy(f, orig)
            im = Image.open(orig).convert("RGBA")
            for z in zones:
                effacer(im, z)
            normale = "normal" in tex
            for (x0, y0, x1, y1), m in logos:
                effacer(im, (x0, y0, x1, y1))
                if not normale:                   # carte de relief : seulement aplanie
                    e = emblème(m, max(x1 - x0, y1 - y0))
                    im.alpha_composite(e, (x0 + (x1 - x0 - e.width) // 2, y0 + (y1 - y0 - e.height) // 2))
            im.convert("RGB").save(f)
            print("retouché", cid, tex)


if __name__ == "__main__":
    main()
