"""Vinyles du garage (issues #43, #54, #94) -> ../godot/assets/garage/vinyles.png : 21 bandes de 1024 × 256 (RGBA), vues de
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


# ---- v6.58 (#94) : onze vinyles de plus
def chevrons():
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    for k in range(6):
        x = W * (0.30 + 0.11 * k); e = W * 0.035; m = H * 0.55
        d.polygon([(x, H * 0.30), (x + e, H * 0.30), (x + e + H * 0.22, m), (x + e, H * 0.80), (x, H * 0.80), (x + H * 0.22, m)],
                  fill=(250, 200, 30, 255) if k % 2 == 0 else (20, 20, 22, 255))
    return im


def vagues():
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    for j, col in enumerate([(20, 90, 200, 255), (40, 160, 230, 255), (230, 245, 255, 255)]):
        pts = []
        for i in range(201):
            x = W * i / 200
            pts.append((x, H * (0.62 + 0.06 * j) + math.sin(i / 200 * math.tau * 3 + j) * H * 0.07))
        d.polygon(pts + [(W, H), (0, H)], fill=col)
    return im


def pois():
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    r = H * 0.045
    for j in range(4):
        for i in range(18):
            x = W * (i + 0.5 * (j % 2) + 0.5) / 18; y = H * (0.30 + 0.15 * j)
            d.ellipse([x - r, y - r, x + r, y + r], fill=(245, 245, 245, 255))
    return im


def tigre():
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    for k in range(18):
        x = W * (0.05 + 0.9 * k / 17) + random.uniform(-W * 0.01, W * 0.01)
        h = H * random.uniform(0.35, 0.6); e = W * random.uniform(0.012, 0.022); y0 = H * random.uniform(0.2, 0.35)
        d.polygon([(x, y0), (x + e, y0 + h * 0.15), (x + e * 0.4, y0 + h * 0.5), (x + e * 1.2, y0 + h), (x - e * 0.3, y0 + h * 0.55),
                   (x - e * 0.6, y0 + h * 0.2)], fill=(15, 12, 10, 255))
    return im


def hexagones():
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    r = H * 0.075
    for j in range(7):
        for i in range(40):
            x = i * r * 1.75 + (r * 0.87 if j % 2 else 0); y = H * 0.2 + j * r * 1.5
            if x < W * 0.35 or random.random() < 0.15:
                continue
            pts = [(x + r * math.cos(a), y + r * math.sin(a)) for a in [math.pi / 6 + k * math.pi / 3 for k in range(6)]]
            d.polygon(pts, outline=(240, 240, 240, 255), width=int(K * 4))
    return im


def pixels():
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    c = H // 10
    cols = [(255, 60, 140, 255), (60, 220, 255, 255), (255, 230, 50, 255), (120, 255, 90, 255)]
    for j in range(3, 9):
        for i in range(W // c):
            p = (i * c / W)
            if random.random() < p * 1.1 - 0.15:
                d.rectangle([i * c, j * c, i * c + c - K * 2, j * c + c - K * 2], fill=random.choice(cols))
    return im


def numero():
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    cx, cy, r = W * 0.5, H * 0.52, H * 0.27
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(250, 250, 250, 255))
    # « 77 » dessiné en segments épais (pas de police nécessaire)
    e = r * 0.16
    for dx in (-r * 0.42, r * 0.10):
        x0 = cx + dx; y0 = cy - r * 0.55
        d.rectangle([x0, y0, x0 + r * 0.42, y0 + e], fill=(20, 20, 22, 255))
        d.polygon([(x0 + r * 0.42 - e, y0), (x0 + r * 0.42, y0), (x0 + r * 0.12, cy + r * 0.55), (x0 + r * 0.12 - e, cy + r * 0.55)], fill=(20, 20, 22, 255))
    d.rectangle([0, cy - H * 0.03, cx - r, cy + H * 0.03], fill=(250, 250, 250, 255))
    return im


def circuit():
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    for k in range(14):
        x, y = W * random.uniform(0.25, 1.0), H * random.uniform(0.3, 0.8)
        pts = [(x, y)]
        for _ in range(4):
            if random.random() < 0.5:
                x -= W * random.uniform(0.03, 0.12)
            else:
                dy = H * random.uniform(0.05, 0.15) * random.choice([-1, 1]); x -= abs(dy); y = min(max(y + dy, H * 0.25), H * 0.85)
            pts.append((x, y))
        d.line(pts, fill=(60, 255, 160, 255), width=int(K * 4))
        d.ellipse([pts[-1][0] - K * 7, pts[-1][1] - K * 7, pts[-1][0] + K * 7, pts[-1][1] + K * 7], fill=(60, 255, 160, 255))
    return im


def griffures():
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    for k in range(3):
        x = W * (0.55 + 0.05 * k); y = H * (0.28 + 0.04 * k)
        pts_h, pts_b = [], []
        for i in range(21):
            t = i / 20; px = x - t * W * 0.35; py = y + t * H * 0.45; e = H * 0.05 * math.sin(math.pi * t)
            pts_h.append((px, py - e)); pts_b.append((px, py + e))
        d.polygon(pts_h + pts_b[::-1], fill=(20, 20, 22, 255))
    return im


def tricolore():
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    for k, col in enumerate([(0, 45, 145, 255), (245, 245, 245, 255), (210, 20, 40, 255)]):
        y = H * (0.48 + 0.07 * k)
        d.rectangle([0, y, W, y + H * 0.07], fill=col)
    return im


def coucher():
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    cx, cy, r = W * 0.62, H * 0.78, H * 0.48
    for yy in range(int(cy - r), int(cy)):
        t = (yy - (cy - r)) / r                       # 0 haut -> 1 horizon
        if t > 0.45 and int((t - 0.45) * 22) % 2 == 1:
            continue                                  # bandes vides de plus en plus serrées vers l'horizon
        dx = math.sqrt(max(0.0, r * r - (yy - cy) ** 2))
        d.line([(cx - dx, yy), (cx + dx, yy)], fill=(255, int(215 - 160 * t), int(60 + 140 * t), 255))
    d.rectangle([0, cy, W, cy + H * 0.035], fill=(255, 60, 160, 255))
    return im


BANDES = [flammes, eclairs, damier, camouflage, tribal, etoiles, eclaboussures, rayures, dents, retro,
          chevrons, vagues, pois, tigre, hexagones, pixels, numero, circuit, griffures, tricolore, coucher]
atlas = Image.new("RGBA", (1024, 256 * len(BANDES)), (0, 0, 0, 0))
for k, f in enumerate(BANDES):
    b = f().filter(ImageFilter.GaussianBlur(K * 0.6)).resize((1024, 256), Image.LANCZOS)
    atlas.paste(b, (0, 256 * k))
os.makedirs(os.path.dirname(OUT), exist_ok=True)
atlas.save(OUT)
print(OUT)
