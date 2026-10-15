"""Touffes des champs façon GTA San Andreas (issue #61) -> ../godot/assets/veg/touffes_albedo.png (2048 × 2048).
Au lieu d'un sprite par plant, un plan montre une bande de champ : plusieurs plants de l'atlas des plants
(plants_albedo.png de tools/bake_cultures.gd, cases de 256 × 512 px : largeur = hauteur / 2) collés sur trois
profondeurs (les plus lointains plus sombres et un peu plus bas). Cases de 512 × 512 px : 4 cultures (lignes) ×
4 variantes (colonnes) ; une case = LARGEUR m de large sur la hauteur de case de la culture (crops.gd HCASE).
Lue par crops.gd / crops_plants.gdshader.   python3 build_touffes.py"""
import random
from PIL import Image, ImageEnhance

SRC = "../godot/assets/veg/plants_albedo.png"
OUT = "../godot/assets/veg/touffes_albedo.png"
HCASE = [3.0, 1.2, 1.4, 2.4]          # crops.gd
STEP = [0.22, 0.30, 0.38, 0.34]       # crops.gd : pieds sur le rang (m)
DENS = [1.0, 2.2, 1.9, 1.0]           # plants par case en plus (céréales et colza : touffes serrées, sans trou)
LARGEUR = 2.4                         # largeur d'une touffe (m) ; crops.gd LARGEUR
C = 512

src = Image.open(SRC).convert("RGBA")
atlas = Image.new("RGBA", (4 * C, 4 * C), (0, 0, 0, 0))
for t in range(4):
    kx = HCASE[t] / LARGEUR                       # px/m horizontal de la case / px/m de la source
    pw = max(8, round(256 * kx))
    for v in range(4):
        rng = random.Random(61 * 10 + t * 4 + v)
        case = Image.new("RGBA", (C, C), (0, 0, 0, 0))
        # trois profondeurs, de la plus lointaine à la plus proche
        for couche, (lum, bas) in enumerate([(0.72, 10), (0.86, 5), (1.0, 0)]):
            n = round(LARGEUR / STEP[t] * (0.55 if couche < 2 else 0.7) * DENS[t])
            for i in range(n):
                k = rng.randrange(8)
                pl = src.crop((k * 256, t * 512, k * 256 + 256, t * 512 + 512))
                if rng.random() < 0.5:
                    pl = pl.transpose(Image.FLIP_LEFT_RIGHT)
                s = rng.uniform(0.88, 1.05) * (0.94 if couche == 0 else 1.0)
                w, h = max(4, round(pw * s)), round(512 * s)
                pl = pl.resize((w, h), Image.LANCZOS)
                r, g, b, a = pl.split()
                rgb = ImageEnhance.Brightness(Image.merge("RGB", (r, g, b))).enhance(lum * rng.uniform(0.93, 1.05))
                pl = Image.merge("RGBA", (*rgb.split(), a))
                x = round((i + rng.uniform(0.0, 1.0)) / n * C - w / 2)
                case.alpha_composite(pl, (max(-w // 2, min(C - w // 2, x)), C - h - bas))
        # bords gauche et droit adoucis : les touffes voisines se chevauchent sans couture nette
        a = case.getchannel("A").load()
        for y in range(C):
            for x in list(range(24)) + list(range(C - 24, C)):
                e = min(x, C - 1 - x) / 24.0
                a[x, y] = int(a[x, y] * (0.4 + 0.6 * e)) if a[x, y] else 0
        atlas.paste(case, (v * C, t * C))
atlas.save(OUT)
print(OUT)
