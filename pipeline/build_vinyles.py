"""Vinyles du garage (issues #43, #54) -> ../godot/assets/garage/vinyles.png : 10 bandes de 1024 × 256 (RGBA), vues de
côté de la voiture (u : arrière -> avant, v : haut -> bas), lues par scripts/carrosserie.gdshader (BANDES). Dessin à
4 × puis réduit (bords lissés, coupés au seuil dans le jeu). Bandes : 0 flammes, 1 éclairs, 2 damier, 3 camouflage,
4 tribal, 5 étoiles, 6 éclaboussures, 7 rayures obliques, 8 dents de requin, 9 filets rétro."""
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


def tribal():
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    # pointes courbes qui partent de l'avant, noires cernées de blanc
    for col, ep in [((240, 240, 240, 255), 1.0), ((15, 15, 18, 255), 0.7)]:
        for i, (y0, l, sens) in enumerate([(0.35, 0.55, -1), (0.55, 0.75, 1), (0.72, 0.45, -1)]):
            haut, bas = [], []
            n = 30
            for k in range(n + 1):
                t = k / n
                x = W * (0.98 - t * l)
                y = H * (y0 + sens * 0.18 * math.sin(t * math.pi * 0.9) * t)
                e = H * 0.13 * ep * (1 - t) ** 1.1
                haut.append((x, y - e)); bas.append((x, y + e))
            d.polygon(haut + bas[::-1], fill=col)
    return im


def etoiles():
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    for _ in range(26):
        x, y = random.random() * W, H * (0.3 + 0.5 * random.random())
        r = H * (0.05 + 0.08 * random.random()) * (0.5 + x / W)
        pts = [(x + (r if k % 2 == 0 else r * 0.42) * math.sin(k * math.pi / 5), y - (r if k % 2 == 0 else r * 0.42) * math.cos(k * math.pi / 5)) for k in range(10)]
        d.polygon(pts, fill=(250, 250, 250, 255))
    return im


def eclaboussures():
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    for col in [(240, 40, 120, 255), (40, 200, 240, 255), (250, 220, 40, 255)]:
        cx, cy = W * (0.25 + 0.5 * random.random()), H * (0.45 + 0.2 * random.random())
        for _ in range(40):
            a = random.random() * math.tau; r = H * 0.35 * random.random() ** 0.6
            x, y = cx + math.cos(a) * r * 2.2, cy + math.sin(a) * r
            e = H * (0.015 + 0.06 * random.random()) * (1 - r / (H * 0.4))
            d.ellipse([x - e * 1.5, y - e, x + e * 1.5, y + e], fill=col)
        d.ellipse([cx - H * 0.2, cy - H * 0.12, cx + H * 0.2, cy + H * 0.12], fill=col)
    return im


def rayures():
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    for i in range(5):
        x = W * (0.55 + 0.07 * i)
        e = W * 0.022
        d.polygon([(x, H * 0.25), (x + e, H * 0.25), (x - H * 0.45 + e, H * 0.85), (x - H * 0.45, H * 0.85)], fill=(245, 245, 245, 255))
    return im


def dents():
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    x0, x1, y0, y1 = W * 0.84, W * 0.995, H * 0.42, H * 0.78
    d.rectangle([x0, y0, x1, y1], fill=(15, 15, 18, 255))
    for k in range(6):                                # dents blanches en haut et en bas de la gueule
        a = y0 + (y1 - y0) * (k / 6)
        d.polygon([(x0, a), (x0, a + (y1 - y0) / 6), (x0 + W * 0.05, a + (y1 - y0) / 12)], fill=(245, 245, 245, 255))
    d.ellipse([W * 0.80, H * 0.36, W * 0.83, H * 0.42], fill=(15, 15, 18, 255))      # œil
    d.ellipse([W * 0.81, H * 0.375, W * 0.82, H * 0.395], fill=(245, 245, 245, 255))
    return im


def retro():
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    for k, col in enumerate([(240, 120, 20, 255), (240, 200, 40, 255), (200, 40, 30, 255)]):
        y = H * (0.5 + 0.055 * k)
        d.rectangle([0, y, W * (0.9 - 0.04 * k), y + H * 0.035], fill=col)
    return im


BANDES = [flammes, eclairs, damier, camouflage, tribal, etoiles, eclaboussures, rayures, dents, retro]
atlas = Image.new("RGBA", (1024, 256 * len(BANDES)), (0, 0, 0, 0))
for k, f in enumerate(BANDES):
    b = f().filter(ImageFilter.GaussianBlur(K * 0.6)).resize((1024, 256), Image.LANCZOS)
    atlas.paste(b, (0, 256 * k))
os.makedirs(os.path.dirname(OUT), exist_ok=True)
atlas.save(OUT)
print(OUT)
