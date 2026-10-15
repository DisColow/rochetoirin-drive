"""Vinyles du garage (issue #43) -> ../godot/assets/garage/vinyles.png : 4 bandes de 1024 × 256 (RGBA), vues de côté
de la voiture (u : arrière -> avant, v : haut -> bas), lues par scripts/carrosserie.gdshader. Dessin à 4 × puis réduit
(bords lissés, coupés au seuil dans le jeu). Bandes : 0 flammes, 1 éclairs, 2 damier, 3 camouflage."""
import math, os, random
from PIL import Image, ImageDraw, ImageFilter

K = 4
W, H = 1024 * K, 256 * K
OUT = "../godot/assets/garage/vinyles.png"
random.seed(43)


def flammes():
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    # langues de feu qui partent de l'avant (à droite) et filent vers l'arrière, plus longues au milieu
    for couche, (col, ep) in enumerate([((40, 10, 5, 255), 1.0), ((200, 30, 10, 255), 0.86), ((255, 120, 10, 255), 0.66), ((255, 220, 60, 255), 0.42)]):
        for i in range(5):
            y0 = H * (0.22 + 0.56 * i / 4)
            longueur = W * (0.42 + 0.30 * math.sin(math.pi * i / 4) + 0.05 * random.random()) * (0.75 + 0.25 * ep)
            demi = H * 0.15 * ep
            pts_h, pts_b = [], []
            n = 40
            for k in range(n + 1):
                t = k / n
                x = W - t * longueur
                ond = math.sin(t * 5.0 + i) * H * 0.07 * t
                larg = demi * (1 - t) ** 0.8
                pts_h.append((x, y0 + ond - larg))
                pts_b.append((x, y0 + ond + larg))
            d.polygon(pts_h + pts_b[::-1] + [(W, y0 + demi)], fill=col)
    return im


def eclairs():
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    for col, ep in [((20, 20, 30, 255), 1.0), ((255, 235, 60, 255), 0.62)]:
        for y0, x0, x1 in [(0.42, 0.95, 0.15), (0.62, 0.80, 0.45)]:
            pts = []
            x, y = W * x0, H * y0
            pas = (x1 - x0) * W / 6
            for k in range(7):
                pts.append((x + pas * k, y + (H * 0.12 if k % 2 else -H * 0.12) * (1 - k / 7)))
            haut = [(px, py - H * 0.075 * ep * (1 - k / 7)) for k, (px, py) in enumerate(pts)]
            bas = [(px, py + H * 0.075 * ep * (1 - k / 7)) for k, (px, py) in enumerate(pts)]
            d.polygon(haut + bas[::-1], fill=col)
    return im


def damier():
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    c = H // 12
    y0 = int(H * 0.55)
    for j in range(3):
        for i in range(W // c + 1):
            # le damier s'efface vers l'avant en cases qui s'espacent
            if i * c > W * 0.75 and random.random() < (i * c / W - 0.75) * 4:
                continue
            col = (245, 245, 245, 255) if (i + j) % 2 else (15, 15, 15, 255)
            d.rectangle([i * c, y0 + j * c, i * c + c - 1, y0 + j * c + c - 1], fill=col)
    return im


def camouflage():
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    for col in [(70, 80, 45, 255), (40, 45, 30, 255), (120, 110, 75, 255)]:
        for _ in range(60):
            x, y = random.random() * W, random.random() * H
            r = H * (0.05 + 0.08 * random.random())
            pts = [(x + r * (1 + 0.6 * math.sin(a * 3 + x)) * math.cos(a) * 1.8, y + r * (1 + 0.5 * math.cos(a * 2 + y)) * math.sin(a))
                   for a in [k / 14 * math.tau for k in range(14)]]
            d.polygon(pts, fill=col)
    return im


atlas = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
for k, f in enumerate([flammes, eclairs, damier, camouflage]):
    b = f().filter(ImageFilter.GaussianBlur(K * 0.6)).resize((1024, 256), Image.LANCZOS)
    atlas.paste(b, (0, 256 * k))
os.makedirs(os.path.dirname(OUT), exist_ok=True)
atlas.save(OUT)
print(OUT)
