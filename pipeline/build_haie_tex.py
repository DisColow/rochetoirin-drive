"""Textures des touffes de haie (feuilles dessinées une à une, fond transparent) -> ../godot/assets/fence/feuilles.png
Atlas 2 × 2 de 512² : thuya (rameaux en écailles), laurier-palme (grandes feuilles vernissées), photinia (pousses
rouges), haie champêtre (charme, aubépine, noisetier : petites feuilles variées, rameaux). Chaque case est une touffe
ronde, dense au centre, découpée sur les bords. Utilisée par blender_haies.py (UV) et fences.gd (matériau)."""
import math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

S = 512
OUT = "../godot/assets/fence/feuilles.png"


def leaf(d, cx, cy, L, W, ang, col, vein=None, hi=None):
    """Feuille en amande (polygone), nervure centrale, reflet."""
    ca, sa = math.cos(ang), math.sin(ang)
    pts = []
    for k in range(13):
        t = k / 12
        x = (t - 0.5) * L
        y = math.sin(math.pi * t) ** 0.8 * W / 2
        pts.append((x, y))
    pts += [(x, -y) for x, y in pts[::-1]]
    P = [(cx + x * ca - y * sa, cy + x * sa + y * ca) for x, y in pts]
    d.polygon(P, fill=col)
    if hi:
        Q = [(cx + (x * 0.6) * ca - (y * 0.35 - W * 0.12) * sa, cy + (x * 0.6) * sa + (y * 0.35 - W * 0.12) * ca)
             for x, y in pts]
        d.polygon(Q, fill=hi)
    if vein:
        d.line([(cx - L / 2 * ca, cy - L / 2 * sa), (cx + L / 2 * ca, cy + L / 2 * sa)], fill=vein, width=1)


def cluster(rng, n, R=230):
    """Positions dans un disque, plus denses au centre."""
    r = R * np.sqrt(rng.random(n)) ** 1.25
    a = rng.random(n) * 2 * math.pi
    return S / 2 + r * np.cos(a), S / 2 + r * np.sin(a), r / R


def shade(c, k):
    return tuple(int(max(0, min(255, v * k))) for v in c)


def laurier(rng, red=False):
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    X, Y, R = cluster(rng, 420 if not red else 700)
    order = np.argsort(R)[::-1]                       # bords d'abord, centre par-dessus
    for i in order:
        k = 0.55 + 0.6 * (1 - R[i]) * rng.random() ** 0.5
        if red and rng.random() < 0.35 * (1 - R[i] * 0.5):
            base = (150 + 60 * rng.random(), 30 + 25 * rng.random(), 25)
        else:
            base = (38, 78 + 30 * rng.random(), 30) if not red else (42, 80 + 25 * rng.random(), 36)
        c = shade(base, k)
        L = (52 if not red else 34) * (0.75 + 0.5 * rng.random()); W = L * (0.36 if not red else 0.42)
        leaf(d, X[i], Y[i], L, W, rng.random() * math.pi * 2, c + (255,), vein=shade(c, 1.35) + (255,),
             hi=shade(c, 1.45) + (255,) if rng.random() < 0.55 else None)
    return im


def thuya(rng):
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0)); d = ImageDraw.Draw(im)

    def spray(x, y, ang, L, depth, c):
        if depth == 0 or L < 5:
            return
        n = int(L / 4)
        for k in range(n):
            t = k / max(n - 1, 1)
            px, py = x + math.cos(ang) * L * t, y + math.sin(ang) * L * t
            r = 3.2 * (1 - 0.5 * t) + 0.6
            d.ellipse([px - r, py - r * 0.8, px + r, py + r * 0.8], fill=shade(c, 0.9 + 0.25 * rng.random()) + (255,))
        for k in range(1, 5):
            t = k / 5
            px, py = x + math.cos(ang) * L * t, y + math.sin(ang) * L * t
            for s in (-1, 1):
                spray(px, py, ang + s * (0.7 + 0.2 * rng.random()), L * 0.45, depth - 1, shade(c, 1.05))
    X, Y, R = cluster(rng, 90, 165)
    for i in np.argsort(R)[::-1]:
        k = 0.55 + 0.6 * (1 - R[i])
        c = shade((36 + 14 * rng.random(), 74 + 22 * rng.random(), 30), k)
        spray(X[i], Y[i], rng.random() * math.pi * 2, 45 + 30 * rng.random(), 3, c)
    return im


def champetre(rng):
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    X, Y, R = cluster(rng, 30)
    for i in range(30):                               # rameaux
        a = rng.random() * math.pi * 2
        d.line([(X[i], Y[i]), (X[i] + 60 * math.cos(a), Y[i] + 60 * math.sin(a))], fill=(78, 62, 44, 255), width=2)
    X, Y, R = cluster(rng, 1100)
    for i in np.argsort(R)[::-1]:
        k = 0.5 + 0.65 * (1 - R[i]) * rng.random() ** 0.4
        sp = rng.random()
        base = (60, 105, 34) if sp < 0.4 else (78, 112, 40) if sp < 0.7 else (50, 92, 44)
        c = shade(base, k)
        L = (22 if sp < 0.4 else 28 if sp < 0.7 else 18) * (0.8 + 0.4 * rng.random())
        leaf(d, X[i], Y[i], L, L * 0.62, rng.random() * math.pi * 2, c + (255,), vein=shade(c, 1.3) + (255,))
    return im


def main():
    rng = np.random.default_rng(7)
    cells = [thuya(rng), laurier(rng), laurier(rng, red=True), champetre(rng)]
    A = Image.new("RGBA", (2 * S, 2 * S), (0, 0, 0, 0))
    for i, c in enumerate(cells):
        # bords légèrement assombris (ombre interne de la touffe), alpha net
        a = np.asarray(c).astype(np.float32)
        al = a[..., 3:4] / 255
        blur = np.asarray(c.split()[3].filter(ImageFilter.GaussianBlur(10))).astype(np.float32)[..., None] / 255
        a[..., :3] *= 0.6 + 0.4 * blur
        # couleur prolongée sous les zones transparentes (pas de liseré sombre au filtrage)
        bg = np.asarray(Image.fromarray(a.astype(np.uint8)).filter(ImageFilter.BoxBlur(6))).astype(np.float32)
        a[..., :3] = np.where(al > 0.5, a[..., :3], bg[..., :3] / np.maximum(bg[..., 3:4] / 255, 0.05))
        A.paste(Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)), ((i % 2) * S, (i // 2) * S))
    A.save(OUT)
    print("feuilles :", OUT)


if __name__ == "__main__":
    main()
