"""Texture de fumée animée (façon Call of Duty 2 : grosses volutes éclairées) pour les effets des roues (fumee.gd).
Planche 4 × 4 de 16 images de 128 px : une bouffée de fumée qui gonfle, se déchire et se dissipe. Canaux : RVB = normale
de la surface de la volute (éclairage par le soleil dans le shader), A = densité. Bruit fractal 3D (valeur) tranché
dans le temps, donc les images s'enchaînent sans saut.
Sortie : ../godot/assets/fx/fumee.png"""
import os
import numpy as np
from PIL import Image

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "godot", "assets", "fx")
N = 128
G = 4
rng = np.random.default_rng(7)
LAT = rng.random((24, 24, 24))


def bruit(x, y, z):
    """Bruit de valeur 3D périodique, interpolation douce."""
    s = LAT.shape[0]
    xi, yi, zi = np.floor(x).astype(int), np.floor(y).astype(int), np.floor(z).astype(int)
    fx, fy, fz = x - xi, y - yi, z - zi
    u, v, w = [t * t * (3 - 2 * t) for t in (fx, fy, fz)]
    def L(a, b, c):
        return LAT[(xi + a) % s, (yi + b) % s, (zi + c) % s]
    x00 = L(0, 0, 0) * (1 - u) + L(1, 0, 0) * u
    x10 = L(0, 1, 0) * (1 - u) + L(1, 1, 0) * u
    x01 = L(0, 0, 1) * (1 - u) + L(1, 0, 1) * u
    x11 = L(0, 1, 1) * (1 - u) + L(1, 1, 1) * u
    return (x00 * (1 - v) + x10 * v) * (1 - w) + (x01 * (1 - v) + x11 * v) * w


def fbm(x, y, z, oct=5):
    t = 0.0; a = 0.5; f = 1.0
    for _ in range(oct):
        t = t + a * bruit(x * f, y * f, z * f)
        a *= 0.5; f *= 2.03
    return t


BLOBS = [(rng.uniform(-0.38, 0.38), rng.uniform(-0.3, 0.38), rng.uniform(0.2, 0.34)) for _ in range(9)]


def image(k):
    p = k / (G * G - 1)                                   # 0 … 1 : âge de la bouffée
    yy, xx = np.mgrid[0:N, 0:N] / (N - 1) * 2 - 1
    z = 3.0 + p * 3.0
    # coordonnées tordues par la turbulence (volutes), de plus en plus avec l'âge
    wx = (fbm(xx * 1.6 + 7, yy * 1.6, z) - 0.5) * (0.35 + 0.5 * p)
    wy = (fbm(xx * 1.6, yy * 1.6 + 3, z + 4) - 0.5) * (0.35 + 0.5 * p)
    X, Y = xx + wx, yy + wy
    # amas de boules (chou-fleur) qui gonflent
    f = np.zeros_like(xx)
    for bx, by, rs in BLOBS:
        r = rs * (0.75 + 0.6 * p)
        f += np.exp(-((X - bx * (0.8 + 0.4 * p)) ** 2 + (Y - by * (0.8 + 0.4 * p)) ** 2) / (r * r))
    f += (fbm(X * 4.0, Y * 4.0, z * 1.3) - 0.5) * 0.7      # bords effilochés
    seuil = 0.45 + 0.35 * p
    d = np.clip((f - seuil) / 0.55, 0, 1)
    d = d * d * (3 - 2 * d) * (1.0 - 0.5 * p ** 1.5)      # se dissipe
    bord = np.clip(1.0 - np.sqrt(xx ** 2 + yy ** 2), 0, 1) ** 0.35
    d = d * bord
    # normale : relief du champ (bosses du chou-fleur)
    h = f * 1.2
    gx = np.gradient(h, axis=1) * N * 0.05
    gy = np.gradient(h, axis=0) * N * 0.05
    nx, ny, nz = -gx, gy, np.ones_like(gx)
    l = np.sqrt(nx ** 2 + ny ** 2 + nz ** 2)
    rgb = np.stack([nx / l, ny / l, nz / l], -1) * 0.5 + 0.5
    return np.dstack([rgb, d]).clip(0, 1)


def main():
    os.makedirs(OUT, exist_ok=True)
    planche = np.zeros((N * G, N * G, 4))
    for k in range(G * G):
        i, j = k % G, k // G
        planche[j * N:(j + 1) * N, i * N:(i + 1) * N] = image(k)
    Image.fromarray((planche * 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, "fumee.png"))
    # aperçu : densité seule, sur fond sombre
    a = planche[..., 3:4]
    nrm = planche[..., :3] * 2 - 1
    L = np.array([0.6, 0.6, 0.53])
    lum = np.clip((nrm * L).sum(-1, keepdims=True), 0, 1) * 0.6 + 0.4
    ap = (np.array([0.35, 0.5, 0.7]) * (1 - a) + 0.9 * lum * a)
    Image.fromarray((ap * 255).astype(np.uint8)).save(os.path.join(OUT, "..", "..", "..", "docs", "apercus", "fumee_planche.jpg"))
    print("fumée :", os.path.join(OUT, "fumee.png"))


if __name__ == "__main__":
    main()
