"""Atlas des panneaux français (dessinés d'après les formes réglementaires, 256 px par case, fond transparent).
Cases : voir CELLS. Panneaux d'agglomération (EB10 / EB20) dans un atlas à part, 512 × 256 par nom.
Sorties : ../godot/assets/tex/signs_atlas.png, ../godot/assets/tex/signs_city.png, data/signs_city.json"""
import json, math, os
from PIL import Image, ImageDraw, ImageFont

C = 256
RED = (200, 16, 30, 255); WHITE = (255, 255, 255, 255); BLACK = (20, 20, 20, 255); BLUE = (20, 70, 160, 255)
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
SPEEDS = [10, 15, 20, 30, 40, 45, 50, 60, 70, 80, 90, 110, 130]
CELLS = ["stop", "give_way", "bus", "voie_verte", "fin_voie_verte", "cerf", "danger", "blank"] + ["b14_%d" % v for v in SPEEDS]


def font(sz):
    return ImageFont.truetype(FONT, sz)


def text_c(d, xy, t, f, fill):
    b = d.textbbox((0, 0), t, font=f)
    d.text((xy[0] - (b[2] - b[0]) / 2 - b[0], xy[1] - (b[3] - b[1]) / 2 - b[1]), t, font=f, fill=fill)


def cell(kind):
    im = Image.new("RGBA", (C * 4, C * 4), (0, 0, 0, 0))          # dessin à 4x puis réduction (anticrénelage)
    d = ImageDraw.Draw(im); S = C * 4; c = S / 2
    if kind == "stop":
        R = S * 0.48
        pts = [(c + R * math.cos(math.radians(22.5 + 45 * k)), c + R * math.sin(math.radians(22.5 + 45 * k))) for k in range(8)]
        d.polygon(pts, fill=WHITE)
        pts = [(c + R * 0.92 * math.cos(math.radians(22.5 + 45 * k)), c + R * 0.92 * math.sin(math.radians(22.5 + 45 * k))) for k in range(8)]
        d.polygon(pts, fill=RED)
        text_c(d, (c, c), "STOP", font(int(S * 0.27)), WHITE)
    elif kind in ("give_way", "cerf", "danger"):
        R = S * 0.49
        if kind == "give_way":          # triangle pointe en bas
            pts = [(c - R, c - R * 0.80), (c + R, c - R * 0.80), (c, c + R * 0.95)]
            inner = [(c - R * 0.62, c - R * 0.58), (c + R * 0.62, c - R * 0.58), (c, c + R * 0.50)]
        else:
            pts = [(c - R, c + R * 0.80), (c + R, c + R * 0.80), (c, c - R * 0.95)]
            inner = [(c - R * 0.62, c + R * 0.58), (c + R * 0.62, c + R * 0.58), (c, c - R * 0.50)]
        d.polygon(pts, fill=RED); d.polygon(inner, fill=WHITE)
        if kind == "cerf":
            d.ellipse((c - 70, c - 10, c + 70, c + 90), fill=BLACK)
            d.rectangle((c - 50, c + 60, c - 35, c + 160), fill=BLACK); d.rectangle((c + 35, c + 60, c + 50, c + 160), fill=BLACK)
        elif kind == "danger":
            d.rectangle((c - 22, c - 60, c + 22, c + 110), fill=BLACK); d.ellipse((c - 26, c + 140, c + 26, c + 192), fill=BLACK)
    elif kind.startswith("b14_"):
        v = kind[4:]
        d.ellipse((S * 0.02, S * 0.02, S * 0.98, S * 0.98), fill=RED)
        d.ellipse((S * 0.14, S * 0.14, S * 0.86, S * 0.86), fill=WHITE)
        text_c(d, (c, c), v, font(int(S * (0.42 if len(v) < 3 else 0.33))), BLACK)
    elif kind == "bus":
        d.rounded_rectangle((S * 0.08, S * 0.08, S * 0.92, S * 0.92), radius=40, fill=BLUE)
        d.rounded_rectangle((S * 0.13, S * 0.13, S * 0.87, S * 0.87), radius=30, outline=WHITE, width=14)
        d.rounded_rectangle((S * 0.28, S * 0.26, S * 0.72, S * 0.68), radius=30, fill=WHITE)
        d.rectangle((S * 0.33, S * 0.32, S * 0.67, S * 0.46), fill=BLUE)
        d.ellipse((S * 0.32, S * 0.62, S * 0.42, S * 0.72), fill=WHITE); d.ellipse((S * 0.58, S * 0.62, S * 0.68, S * 0.72), fill=WHITE)
        text_c(d, (c, S * 0.81), "BUS", font(int(S * 0.11)), WHITE)
    elif kind in ("voie_verte", "fin_voie_verte"):
        d.rectangle((S * 0.06, S * 0.06, S * 0.94, S * 0.94), fill=(20, 130, 60, 255))
        d.rectangle((S * 0.10, S * 0.10, S * 0.90, S * 0.90), outline=WHITE, width=12)
        text_c(d, (c, c - 60), "VOIE", font(int(S * 0.15)), WHITE); text_c(d, (c, c + 70), "VERTE", font(int(S * 0.15)), WHITE)
        if kind.startswith("fin"):
            d.line((S * 0.12, S * 0.88, S * 0.88, S * 0.12), fill=RED, width=36)
    return im.resize((C, C), Image.LANCZOS)


def city(name, exit_=False):
    W, H = 2048, 1024
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    d.rounded_rectangle((20, 120, W - 20, H - 120), radius=60, fill=WHITE)
    d.rounded_rectangle((60, 160, W - 60, H - 160), radius=40, outline=RED if exit_ else BLACK, width=40)
    words = name.upper().split()
    # une ou deux lignes
    lines = [" ".join(words)]
    f = font(200)
    if d.textbbox((0, 0), lines[0], font=f)[2] > W - 260 and len(words) > 1:
        h = len(words) // 2 + len(words) % 2
        lines = [" ".join(words[:h]), " ".join(words[h:])]
    sz = 200
    while sz > 60 and max(d.textbbox((0, 0), l, font=font(sz))[2] for l in lines) > W - 260:
        sz -= 10
    for i, l in enumerate(lines):
        text_c(d, (W / 2, H / 2 + (i - (len(lines) - 1) / 2) * sz * 1.15), l, font(sz), BLACK)
    if exit_:
        d.line((140, H - 220, W - 140, 220), fill=RED, width=70)
    return im.resize((512, 256), Image.LANCZOS)


def build(city_names):
    os.makedirs("../godot/assets/tex", exist_ok=True)
    A = Image.new("RGBA", (C * 8, C * 8), (0, 0, 0, 0))
    for i, k in enumerate(CELLS):
        A.paste(cell(k), ((i % 8) * C, (i // 8) * C))
    A.save("../godot/assets/tex/signs_atlas.png")
    names = sorted(set(city_names))[:16]
    B = Image.new("RGBA", (2048, 2048), (0, 0, 0, 0))
    for i, n in enumerate(names):
        B.paste(city(n), ((i % 4) * 512, (i // 4) * 512))
        B.paste(city(n, True), ((i % 4) * 512, (i // 4) * 512 + 256))
    B.save("../godot/assets/tex/signs_city.png")
    json.dump(names, open("data/signs_city.json", "w"))
    return names


def uv_cell(kind):
    """Coin haut-gauche et taille de la case dans l'atlas (uv 0-1)."""
    i = CELLS.index(kind)
    return ((i % 8) / 8.0, (i // 8) / 8.0, 1 / 8.0)


def uv_city(names, name, exit_=False):
    i = names.index(name)
    return ((i % 4) / 4.0, (i // 4) / 4.0 + (0.125 if exit_ else 0.0), 0.25, 0.125)


if __name__ == "__main__":
    build(["Rochetoirin", "La Tour-du-Pin", "Saint-Clair-de-la-Tour", "Saint-Chef"])
    print("ok")
