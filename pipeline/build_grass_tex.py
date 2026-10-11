"""Planche des touffes de végétation basse (4 × 2 cases de 256 px, fond transparent) -> godot/assets/veg/grass_albedo.png
 0 pelouse rase   1 pelouse et pâquerettes   2 herbe haute de pré   3 fleurs des champs (coquelicots, boutons d'or, bleuets)
 4 graminées de bas-côté (épis)   5 bas-côté fleuri (achillée, chicorée)   6 fougère   7 sous-bois (pousses, feuilles)
Dessin procédural : brins effilés et courbés, teintes variées, base plus sombre."""
import math, os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

S = 256
OUT = "../godot/assets/veg/grass_albedo.png"


def blade(d, rng, x0, h, lean, w0, col, curve=0.3):
    """Brin effilé : polygone le long d'une courbe."""
    n = 8
    pts_l, pts_r = [], []
    for k in range(n + 1):
        t = k / n
        x = x0 + lean * h * (t + curve * t * t)
        y = S - 2 - h * t
        w = w0 * (1 - t) ** 0.8
        pts_l.append((x - w, y)); pts_r.append((x + w, y))
    shade = 0.75 + 0.35 * rng.random()
    c = tuple(int(min(255, v * shade)) for v in col) + (255,)
    d.polygon(pts_l + pts_r[::-1], fill=c)
    return pts_l[-1]


def greens(rng, dry=0.0):
    base = np.array([62, 105, 38]) * (1 - dry) + np.array([150, 140, 80]) * dry
    return tuple((base * rng.uniform(0.8, 1.2, 3)).astype(int))


def tuft(img, rng, nblades, hmin, hmax, wid, dry=0.0, spread=0.35):
    d = ImageDraw.Draw(img)
    for _ in range(nblades):
        x0 = S / 2 + rng.normal(0, S * spread * 0.35)
        h = rng.uniform(hmin, hmax) * S
        lean = rng.normal(0, 0.25)
        blade(d, rng, x0, h, lean, wid * rng.uniform(0.7, 1.3), greens(rng, dry * rng.random()))
    return d


def flower(d, x, y, r, petal, centre, n=6):
    for k in range(n):
        a = 2 * math.pi * k / n
        px, py = x + math.cos(a) * r, y + math.sin(a) * r * 0.6
        d.ellipse((px - r * 0.7, py - r * 0.45, px + r * 0.7, py + r * 0.45), fill=petal)
    d.ellipse((x - r * 0.45, y - r * 0.35, x + r * 0.45, y + r * 0.35), fill=centre)


def stem_flower(d, rng, h, petal, centre, r):
    x0 = S / 2 + rng.normal(0, S * 0.15)
    top = blade(d, rng, x0, h, rng.normal(0, 0.12), 1.6, (55, 95, 35), curve=0.1)
    flower(d, top[0], top[1], r, petal, centre)


def fern(img, rng):
    d = ImageDraw.Draw(img)
    for f in range(7):
        ang = math.radians(rng.uniform(-60, 60))
        L = rng.uniform(0.55, 0.95) * S
        x0, y0 = S / 2 + rng.normal(0, 10), S - 2
        col = greens(rng, 0.05)
        pts = []
        for k in range(14):
            t = k / 13
            x = x0 + math.sin(ang) * L * t + math.sin(ang) * L * 0.25 * t * t
            y = y0 - math.cos(ang) * L * t + L * 0.18 * t * t
            pts.append((x, y))
        d.line(pts, fill=col + (255,), width=2)
        for k in range(2, 13):
            (x, y), (x2, y2) = pts[k], pts[k + 1]
            dx, dy = x2 - x, y2 - y; nl = math.hypot(dx, dy) or 1
            nx, ny = -dy / nl, dx / nl
            pl = (1 - k / 13) * 30 + 6
            for s in (-1, 1):
                d.polygon([(x, y), (x + nx * pl * s + dx * 0.5, y + ny * pl * s + dy * 0.5), (x2, y2)], fill=col + (255,))


def main():
    rng = np.random.default_rng(12)
    cells = []
    for k in range(8):
        img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        if k == 0:
            tuft(img, rng, 70, 0.25, 0.5, 2.6, spread=0.5)
        elif k == 1:
            d = tuft(img, rng, 55, 0.22, 0.45, 2.6, spread=0.5)
            for _ in range(6):
                x, y = S / 2 + rng.normal(0, 45), S - rng.uniform(20, 90)
                flower(d, x, y, 7, (245, 245, 240), (235, 200, 40), n=10)
        elif k == 2:
            tuft(img, rng, 60, 0.55, 0.98, 2.4, dry=0.25)
        elif k == 3:
            d = tuft(img, rng, 40, 0.45, 0.85, 2.2, dry=0.2)
            for _ in range(5):
                c = [((205, 30, 25), (30, 20, 20)), ((240, 200, 30), (200, 150, 20)), ((70, 100, 210), (40, 50, 120))][int(rng.integers(3))]
                stem_flower(d, rng, rng.uniform(0.55, 0.9) * S, c[0], c[1], rng.uniform(7, 11))
        elif k == 4:
            d = tuft(img, rng, 45, 0.5, 0.95, 2.0, dry=0.55)
            for _ in range(8):                                         # épis
                x0 = S / 2 + rng.normal(0, 40)
                top = blade(d, rng, x0, rng.uniform(0.7, 0.98) * S, rng.normal(0, 0.15), 1.3, (120, 125, 70), curve=0.05)
                d.ellipse((top[0] - 4, top[1] - 2, top[0] + 4, top[1] + 22), fill=(170, 160, 105, 255))
        elif k == 5:
            d = tuft(img, rng, 40, 0.4, 0.85, 2.2, dry=0.35)
            for _ in range(4):
                c = [((240, 238, 228), (220, 215, 190)), ((110, 140, 215), (60, 80, 150))][int(rng.integers(2))]
                stem_flower(d, rng, rng.uniform(0.5, 0.9) * S, c[0], c[1], rng.uniform(6, 9))
        elif k == 6:
            fern(img, rng)
        elif k == 7:
            d = tuft(img, rng, 25, 0.2, 0.55, 2.8, dry=0.1)
            for _ in range(14):                                        # feuilles mortes au pied
                x, y = S / 2 + rng.normal(0, 60), S - rng.uniform(4, 30)
                c = tuple(int(v) for v in rng.uniform([110, 70, 30], [160, 110, 50])) + (255,)
                d.ellipse((x - 9, y - 4, x + 9, y + 4), fill=c)
        # assombrit la base (ombre au pied de la touffe)
        a = np.asarray(img).astype(np.float32)
        yy = np.linspace(0, 1, S)[:, None]
        a[..., :3] *= (0.55 + 0.45 * (1 - yy) ** 0.6 + 0.0)[..., None] * 1.0
        a[..., :3] = np.clip(a[..., :3] * 1.15, 0, 255)
        cells.append(Image.fromarray(a.astype(np.uint8), "RGBA"))
    atlas = Image.new("RGBA", (S * 4, S * 2), (0, 0, 0, 0))
    for k, c in enumerate(cells):
        atlas.paste(c, ((k % 4) * S, (k // 4) * S))
    # débord de couleur sous les pixels transparents (pas de liseré sombre au filtrage)
    arr = np.asarray(atlas).astype(np.float32)
    rgb, al = arr[..., :3], arr[..., 3:] / 255
    blur = np.asarray(Image.fromarray(np.uint8(rgb * al)).filter(ImageFilter.GaussianBlur(6))).astype(np.float32)
    wb = np.asarray(Image.fromarray(np.uint8(al[..., 0] * 255)).filter(ImageFilter.GaussianBlur(6))).astype(np.float32)[..., None] / 255
    fill = blur / np.maximum(wb, 1e-3)
    rgb = np.where(al > 0.5, rgb, np.clip(fill, 0, 255))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    Image.fromarray(np.dstack([rgb, arr[..., 3]]).astype(np.uint8), "RGBA").save(OUT)
    prev = Image.new("RGB", atlas.size, (150, 170, 190)); prev.paste(atlas, (0, 0), atlas)
    prev.save("data/grass_preview.jpg")
    print("planche", atlas.size)


if __name__ == "__main__":
    main()
