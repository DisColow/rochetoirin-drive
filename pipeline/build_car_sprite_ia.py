"""Voiture en sprite à partir de la planche fournie par l'utilisateur (sources/espace_sprites.jpg, fond vert, vues
dessinées par une IA) : détourage (fond vert, liseré vert neutralisé), découpage des vues, classement par angle et
hauteur de caméra, mise à l'échelle commune (dimensions réelles de l'Espace projetées), miroir pour les angles
symétriques, rangement dans l'atlas lu par le jeu (32 angles × 4 hauteurs, un seul braquage).
Sorties : ../godot/assets/car/sprite.png, sprite_feux.png, sprite.json (même format que build_car_sprite.py)."""
import json, math
import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage as ndi

SRC = "sources/espace_sprites.jpg"
OUT = "../godot/assets/car"
N_AZ, ELS = 32, [6, 20, 38, 60]
FW, FH = 256, 218
COLS = 16
ORTHO = 5.6
PX = FW / ORTHO                                   # pixels par mètre
LEN, WID, HGT = 4.24, 1.77, 1.62

# vues de la planche, dans l'ordre de détection (de haut en bas, de gauche à droite après tri) :
# (angle de la caméra autour de la voiture en degrés : 0 derrière, 90 flanc gauche, 180 face, 270 flanc droit ;
#  hauteur de la caméra en degrés)
VIEWS = {
    0: (180, 28), 1: (0, 30), 5: (270, 10), 6: (180, 25), 2: (315, 32), 4: (45, 32), 3: (55, 38),
    7: (225, 32), 10: (238, 30), 11: (245, 26), 13: (0, 12), 9: (135, 30), 8: (128, 32), 12: (60, 26),
    14: (180, 72), 15: (180, 75), 20: (222, 55), 16: (180, 70), 19: (140, 55), 17: (145, 60), 18: (180, 14),
    21: (62, 16), 26: (270, 5), 27: (270, 5), 25: (180, 12), 22: (130, 20), 24: (28, 26), 23: (50, 26),
    32: (90, 5), 33: (270, 6), 31: (0, 15), 30: (318, 26), 28: (332, 26), 29: (40, 24),
}


def cut():
    im = np.asarray(Image.open(SRC).convert("RGB")).astype(np.int32)
    r, g, b = im[..., 0], im[..., 1], im[..., 2]
    bg = (g > 120) & (g > r + 50) & (g > b + 50)
    fg = ndi.binary_opening(~bg, iterations=1)
    lab, n = ndi.label(ndi.binary_closing(fg, iterations=3))
    objs = ndi.find_objects(lab)
    sizes = ndi.sum(np.ones_like(lab), lab, range(1, n + 1))
    keep = [i for i in range(n) if sizes[i] > 3000]
    out = {}
    for k, i in enumerate(keep):
        sl = objs[i]
        a = im[sl].copy()
        m = (lab[sl] == i + 1) & fg[sl]
        m = ndi.binary_fill_holes(m)
        m = ndi.binary_erosion(m, iterations=1)                    # retire le liseré vert de la compression
        # vert résiduel neutralisé (reflets verts des vitres gardés : seulement les pixels très verts du bord)
        edge = m & ~ndi.binary_erosion(m, iterations=2)
        gg = a[..., 1]; lim = np.maximum(a[..., 0], a[..., 2]) + 12
        a[..., 1] = np.where(edge & (gg > lim), lim, gg)
        # vitres teintées en vert sur la planche -> gris bleuté comme sur les autres vues (même luminance)
        a = np.clip(a, 0, 255)
        lum = a.mean(-1)
        gl = m & (a[..., 1] > a[..., 0] + 25) & (a[..., 1] > a[..., 2] + 15)
        a[gl] = np.clip(np.c_[lum[gl] * 0.62, lum[gl] * 0.72, lum[gl] * 0.85], 0, 255).astype(np.int32)
        rgba = np.dstack([a, m * 255]).astype(np.uint8)
        out[k] = Image.fromarray(rgba)
    return out


def expected(az, el):
    """Taille projetée (px) de la boîte de la voiture vue depuis (az, el), en projection orthographique."""
    A, E = math.radians(az), math.radians(el)
    w = abs(LEN * math.sin(A)) + abs(WID * math.cos(A))
    depth = abs(LEN * math.cos(A)) + abs(WID * math.sin(A))
    h = HGT * math.cos(E) + depth * math.sin(E)
    return w * PX, h * PX


def main():
    views = cut()
    cand = []                                       # (az, el, image, miroir)
    for k, (az, el) in VIEWS.items():
        if k not in views:
            continue
        im = views[k]
        cand.append((az % 360, el, im, False))
        cand.append(((360 - az) % 360, el, im.transpose(Image.FLIP_LEFT_RIGHT), True))
    atlas = Image.new("RGBA", (COLS * FW, math.ceil(N_AZ * len(ELS) / COLS) * FH), (0, 0, 0, 0))
    feux = Image.new("RGB", atlas.size, (0, 0, 0))
    for ei, el in enumerate(ELS):
        for a in range(N_AZ):
            az = 360 * a / N_AZ
            def cost(c):
                d = abs((c[0] - az + 180) % 360 - 180)
                return d + abs(c[1] - el) * 0.8 + (3 if c[3] else 0)
            c = min(cand, key=cost)
            im = c[2]
            ew, eh = expected(c[0], c[1])
            bx = im.getbbox()
            im = im.crop(bx)
            s = ew / im.width                       # échelle sur la largeur projetée (la plus fiable)
            nw, nh = max(1, round(im.width * s)), max(1, round(im.height * s))
            im = im.resize((nw, nh), Image.LANCZOS)
            arr = np.asarray(im).copy()
            arr[..., 3] = np.where(arr[..., 3] > 110, 255, 0)
            im = Image.fromarray(arr).filter(ImageFilter.UnsharpMask(1.2, 60, 2))
            arr = np.asarray(im).copy()
            # feux : rouges vifs (arrière) quand l'arrière est visible ; blancs très clairs (phares) quand l'avant l'est
            rr, gg, bb, al = [arr[..., i].astype(int) for i in range(4)]
            front = 90 < c[0] < 270 or c[1] > 65
            back = not (100 < c[0] < 260)
            tail = (rr > 170) & (gg < 90) & (bb < 90) & (al > 0) & back
            head = (rr > 205) & (gg > 205) & (bb > 190) & (al > 0) & front
            # les phares sont en bas de la caisse : pas les reflets du pare-brise
            ys = np.arange(arr.shape[0])[:, None] > arr.shape[0] * 0.45
            head &= ys
            i = ei * N_AZ + a
            r, cl = divmod(i, COLS)
            ox = cl * FW + (FW - nw) // 2; oy = r * FH + (FH - nh) // 2
            atlas.alpha_composite(Image.fromarray(arr), (ox, oy))
            m = np.zeros((nh, nw, 3), np.uint8); m[tail, 0] = 255; m[head, 1] = 255
            feux.paste(Image.fromarray(m), (ox, oy))
    atlas.save(OUT + "/sprite.png", optimize=True)
    feux.save(OUT + "/sprite_feux.png", optimize=True)
    json.dump(dict(cols=COLS, rows=atlas.height // FH, frame=[FW, FH], n_az=N_AZ, els=ELS, steers=[0.0],
                   size=[ORTHO, ORTHO * FH / FW], center_y=0.85), open(OUT + "/sprite.json", "w"))
    print("atlas", atlas.size, len(VIEWS), "vues de la planche")


if __name__ == "__main__":
    main()
