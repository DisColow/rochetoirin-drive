"""Voiture en sprite pixel art : les rendus de blender_sprite.py (data/sprite_raw, 3 × la taille finale) sont réduits
à 256 × 218, posterisés sur une palette commune de 48 couleurs (rouge de la voiture du père, beige doré, chromes,
vitres), bordés d'un trait sombre d'un pixel et rangés dans un atlas de deux pages (4096 px de large au plus : limite
des téléphones). Toutes les vues viennent du même modèle 3D : angles et tailles cohérents d'une vue à l'autre.
Sorties : ../godot/assets/car/sprite.png + sprite2.png (RGBA, 16 colonnes × 12 lignes chacune), sprite_feux.png +
sprite_feux2.png (R = feux arrière, V = phares, B = vitres : gouttes et essuie-glace arrière sous la pluie),
ombre.png (ombre portée en pixel art, vue de dessus), sprite.json (grille, pages, angles, hauteurs, braquages, taille
en mètres, cadre de la lunette arrière de chaque vue)."""
import json, os
import numpy as np
from PIL import Image

RAW = "data/sprite_raw"
OUT = "../godot/assets/car"
N_AZ, ELS, STEERS = 32, [6, 20, 38, 60], [-0.38, 0.0, 0.38]
FW, FH, K = 256, 218, 3
COLS, PAGE_ROWS = 16, 12
ORTHO = 6.6
NCOL = 48


def down(a):
    """Réduction K × K avec alpha prémultiplié (bords nets, pas de halo)."""
    a = a.astype(np.float32) / 255.0
    rgb, al = a[..., :3] * a[..., 3:4], a[..., 3:4]
    h, w = al.shape[0] // K, al.shape[1] // K
    f = lambda x: x.reshape(h, K, w, K, -1).mean((1, 3))
    rgb, al = f(rgb), f(al)
    return np.concatenate([rgb / np.maximum(al, 1e-6), al], -1)


def grade(x):
    """Contraste léger, saturation à peine relevée et un peu assombri : le bordeaux de la planche de référence."""
    x = np.clip((x - 0.5) * 1.08 + 0.5, 0, 1) * 0.9
    g = x.mean(-1, keepdims=True)
    return np.clip(g + (x - g) * 1.04, 0, 1)


def pixelize(c, pal_img):
    """Une vue réduite -> pixel art : palette commune, contour sombre d'un pixel, reflet sous le contour haut."""
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
    out = np.zeros((c.shape[0], c.shape[1], 4), np.uint8)
    out[al, :3] = rgb[al]; out[al, 3] = 255
    ec = acc[edge] / np.maximum(cnt[edge, None], 1)
    out[edge, :3] = (ec * 0.28 + np.array([8, 4, 10])).clip(0, 255).astype(np.uint8); out[edge, 3] = 255
    # reflet : un pixel plus clair sous le contour haut des surfaces (lumière venant d'en haut)
    top = al & ~np.roll(al, 1, 0)
    out[top, :3] = np.minimum(255, out[top, :3].astype(np.int32) + 38).astype(np.uint8)
    return out


def main():
    frames = []
    for ei in range(len(ELS)):
        for a in range(N_AZ):
            for si in range(len(STEERS)):
                c = down(np.asarray(Image.open("%s/c_%d_%02d_%d.png" % (RAW, ei, a, si)).convert("RGBA")))
                m = down(np.asarray(Image.open("%s/m_%d_%02d_%d.png" % (RAW, ei, a, si)).convert("RGBA")))
                # vitres : reflets gardés dans les tons ardoise (le ciel rasant les rendait beiges une fois quantifiés)
                g = (m[..., 2] * (m[..., 3] > 0.3)) > 0.35
                lum = c[..., :3][g].mean(-1, keepdims=True)
                c[..., :3][g] = np.minimum(np.array([0.30, 0.35, 0.42]) * (0.55 + 0.9 * lum), [0.62, 0.68, 0.78])
                frames.append((c, m))
    # palette commune : contraste et saturation relevés façon pixel art, puis quantification
    opaque = np.concatenate([c[..., :3][c[..., 3] > 0.5] for c, _ in frames])
    sample = grade(opaque[np.random.default_rng(1).choice(len(opaque), min(len(opaque), 200000), replace=False)])
    pal_img = Image.fromarray((sample[None] * 255).astype(np.uint8)).quantize(NCOL, method=Image.Quantize.MEDIANCUT)
    per = COLS * PAGE_ROWS
    pages = (len(frames) + per - 1) // per
    atlas = np.zeros((pages, PAGE_ROWS * FH, COLS * FW, 4), np.uint8)
    feux = np.zeros((pages, PAGE_ROWS * FH, COLS * FW, 3), np.uint8)
    rear = []                                       # cadre de la lunette arrière (pixels de la case) ou None
    from scipy import ndimage as ndi
    for i, (c, m) in enumerate(frames):
        out = pixelize(c, pal_img)
        pg, k = divmod(i, per)
        r, cl = divmod(k, COLS)
        atlas[pg, r * FH:(r + 1) * FH, cl * FW:(cl + 1) * FW] = out
        mk = (m[..., :3] * (m[..., 3:4] > 0.3) > 0.35).astype(np.uint8) * 255
        feux[pg, r * FH:(r + 1) * FH, cl * FW:(cl + 1) * FW] = mk
        # lunette arrière : plus grande vitre des vues de derrière (à moins de 45° de l'arrière)
        ei_, rest = divmod(i, N_AZ * len(STEERS))
        a_ = rest // len(STEERS)
        box = None
        if (a_ <= 4 or a_ >= N_AZ - 4) and ELS[ei_] < 50:
            g = mk[..., 2] > 0
            lab, n = ndi.label(g)
            if n:
                sizes = ndi.sum(g, lab, range(1, n + 1))
                ys, xs = np.where(lab == 1 + int(np.argmax(sizes)))
                box = [int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())]
        rear.append(box)
    os.makedirs(OUT, exist_ok=True)
    for pg in range(pages):
        sfx = "" if pg == 0 else str(pg + 1)
        Image.fromarray(atlas[pg], "RGBA").save(OUT + "/sprite%s.png" % sfx, optimize=True)
        Image.fromarray(feux[pg], "RGB").save(OUT + "/sprite_feux%s.png" % sfx, optimize=True)
    ombre()
    json.dump(dict(cols=COLS, rows=PAGE_ROWS, pages=pages, frame=[FW, FH], n_az=N_AZ, els=ELS, steers=STEERS,
                   size=[ORTHO, ORTHO * FH / FW], center_y=0.9, rear=rear), open(OUT + "/sprite.json", "w"))
    print("atlas", atlas.shape, len(frames), "vues")


def ombre():
    """Ombre portée en pixel art, vue de dessus : empreinte de l'Espace (4,25 × 1,77 m, coins arrondis) à 12 px/m,
    pleine au centre, bord tramé (damier) ; posée sous la voiture par car.gd en mode sprite."""
    ppm = 32
    w, h = int(2.3 * ppm), int(4.9 * ppm)
    yy, xx = np.mgrid[0:h, 0:w]
    x = (xx + 0.5) / ppm - 1.15; z = (yy + 0.5) / ppm - 2.45
    hx, hz, r = 0.92, 2.15, 0.35
    dx = np.maximum(np.abs(x) - (hx - r), 0); dz = np.maximum(np.abs(z) - (hz - r), 0)
    d = np.hypot(dx, dz) - r                     # < 0 : dedans
    a = np.where(d < -0.12, 150, 0)
    ring = (d >= -0.12) & (d < 0.06)
    a = np.where(ring & ((xx + yy) % 2 == 0), 105, a)
    img = np.zeros((h, w, 4), np.uint8)
    img[..., :3] = (12, 10, 18)
    img[..., 3] = a
    Image.fromarray(img.astype(np.uint8), "RGBA").save(OUT + "/ombre.png")


if __name__ == "__main__":
    main()
