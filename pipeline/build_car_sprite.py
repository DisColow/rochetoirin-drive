"""Voiture en sprite pixel art : les rendus de blender_sprite.py (data/sprite_raw, 3 × la taille finale) sont réduits
à 160 × 136, posterisés sur une palette commune de 40 couleurs (rouge bordeaux, beige doré, chromes, vitres), bordés
d'un trait sombre d'un pixel et rangés dans un atlas.
Sorties : ../godot/assets/car/sprite.png (RGBA, 24 colonnes × 16 lignes), sprite_feux.png (R = feux arrière,
V = phares), sprite.json (grille, angles, hauteurs, braquages, taille en mètres)."""
import json, os
import numpy as np
from PIL import Image

RAW = "data/sprite_raw"
OUT = "../godot/assets/car"
N_AZ, ELS, STEERS = 32, [6, 20, 38, 60], [-0.38, 0.0, 0.38]
FW, FH, K = 160, 136, 3
COLS = 24
ORTHO = 5.6
NCOL = 40


def down(a):
    """Réduction K × K avec alpha prémultiplié (bords nets, pas de halo)."""
    a = a.astype(np.float32) / 255.0
    rgb, al = a[..., :3] * a[..., 3:4], a[..., 3:4]
    h, w = al.shape[0] // K, al.shape[1] // K
    f = lambda x: x.reshape(h, K, w, K, -1).mean((1, 3))
    rgb, al = f(rgb), f(al)
    return np.concatenate([rgb / np.maximum(al, 1e-6), al], -1)


def main():
    frames = []
    for ei in range(len(ELS)):
        for a in range(N_AZ):
            for si in range(len(STEERS)):
                c = down(np.asarray(Image.open("%s/c_%d_%02d_%d.png" % (RAW, ei, a, si)).convert("RGBA")))
                m = down(np.asarray(Image.open("%s/m_%d_%02d_%d.png" % (RAW, ei, a, si)).convert("RGBA")))
                frames.append((c, m))
    # palette commune : contraste et saturation relevés façon pixel art, puis quantification
    opaque = np.concatenate([c[..., :3][c[..., 3] > 0.5] for c, _ in frames])
    def grade(x):
        x = np.clip((x - 0.5) * 1.12 + 0.5, 0, 1)
        g = x.mean(-1, keepdims=True)
        return np.clip(g + (x - g) * 1.25, 0, 1)
    sample = grade(opaque[np.random.default_rng(1).choice(len(opaque), min(len(opaque), 200000), replace=False)])
    pal_img = Image.fromarray((sample[None] * 255).astype(np.uint8)).quantize(NCOL, method=Image.Quantize.MEDIANCUT)
    rows = (len(frames) + COLS - 1) // COLS
    atlas = np.zeros((rows * FH, COLS * FW, 4), np.uint8)
    feux = np.zeros((rows * FH, COLS * FW, 3), np.uint8)
    for i, (c, m) in enumerate(frames):
        rgb = (grade(c[..., :3]) * 255).astype(np.uint8)
        q = Image.fromarray(rgb).quantize(palette=pal_img, dither=Image.Dither.NONE).convert("RGB")
        rgb = np.asarray(q).copy()
        al = c[..., 3] > 0.45
        # trait de contour : pixels transparents qui touchent la voiture -> teinte voisine très assombrie
        nb = np.zeros_like(al)
        acc = np.zeros(rgb.shape, np.float32); cnt = np.zeros(al.shape, np.float32)
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            sh = np.roll(al, (dy, dx), (0, 1))
            shc = np.roll(rgb, (dy, dx), (0, 1)).astype(np.float32)
            nb |= sh
            acc += shc * sh[..., None]; cnt += sh
        edge = nb & ~al
        out = np.zeros((FH, FW, 4), np.uint8)
        out[al, :3] = rgb[al]; out[al, 3] = 255
        ec = acc[edge] / np.maximum(cnt[edge, None], 1)
        out[edge, :3] = (ec * 0.28 + np.array([8, 4, 10])).clip(0, 255).astype(np.uint8); out[edge, 3] = 255
        # reflet : un pixel plus clair sous le contour haut des surfaces (lumière venant d'en haut)
        top = al & ~np.roll(al, 1, 0)
        out[top, :3] = np.minimum(255, out[top, :3].astype(np.int32) + 38).astype(np.uint8)
        r, cl = divmod(i, COLS)
        atlas[r * FH:(r + 1) * FH, cl * FW:(cl + 1) * FW] = out
        mk = (m[..., :3] * (m[..., 3:4] > 0.3) > 0.35).astype(np.uint8) * 255
        feux[r * FH:(r + 1) * FH, cl * FW:(cl + 1) * FW] = mk
    os.makedirs(OUT, exist_ok=True)
    Image.fromarray(atlas, "RGBA").save(OUT + "/sprite.png", optimize=True)
    Image.fromarray(feux, "RGB").save(OUT + "/sprite_feux.png", optimize=True)
    json.dump(dict(cols=COLS, rows=rows, frame=[FW, FH], n_az=N_AZ, els=ELS, steers=STEERS, size=[ORTHO, ORTHO * FH / FW],
                   center_y=0.88), open(OUT + "/sprite.json", "w"))
    print("atlas", atlas.shape, len(frames), "vues")


if __name__ == "__main__":
    main()
