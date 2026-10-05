"""Tableau de textures des clôtures (une couche de 512² par matériau) -> godot/assets/fence/
 - albedo.png : RVB + alpha = découpe (grillages, grilles, feuillage des bords de haie) ;
 - normal.png : normale (RVB) + alpha = rugosité.
Haies : feuillage composé à partir des rameaux des modèles d'arbres (Sketchfab, voir data/trees_credits.json),
semés en couches (les plus profonds plus sombres) ; murs : photos PBR (Poly Haven / ambientCG, CC0) ; grillages,
grilles, panneaux : dessinés. Les couleurs neutres sont teintées par clôture (couleur de sommet).
L'ordre des couches (LAYERS) est partagé avec build_fences.py."""
import os
import numpy as np
from PIL import Image
from scipy import ndimage as ndi

S = 512
OUT = "../godot/assets/fence"
TREES = "../godot/import/trees"
# nom, mètres couverts par la texture (u, v)
LAYERS = [
    ("haie_thuya", 1.2), ("haie_laurier", 1.5), ("haie_photinia", 1.5), ("haie_champetre", 2.0),
    ("bord_thuya", 1.2), ("bord_laurier", 1.5), ("bord_photinia", 1.5), ("bord_champetre", 2.0),
    ("crepi", 2.5), ("pierre", 2.0), ("beton", 2.0),
    ("grillage_rigide", 0.5), ("grillage_losange", 0.5), ("occultant", 1.0), ("bois", 2.0),
    ("grille", 1.0), ("metal", 1.0), ("portail_plein", 1.0),
]
IDX = {n: i for i, (n, _) in enumerate(LAYERS)}
SCALE = {n: m for n, m in LAYERS}


def _load(p, mode="RGB"):
    return np.asarray(Image.open(p).convert(mode).resize((S, S), Image.LANCZOS)).astype(np.float32) / 255


def _normal_from_height(h, strength=6.0):
    gy, gx = np.gradient(h)
    n = np.dstack([-gx * strength, gy * strength, np.ones_like(h)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return n * 0.5 + 0.5


def _sprite(path, crop=None):
    im = Image.open(path).convert("RGBA")
    if crop:
        w, h = im.size
        im = im.crop((int(crop[0] * w), int(crop[1] * h), int(crop[2] * w), int(crop[3] * h)))
    bb = im.getchannel("A").point(lambda v: 255 if v > 100 else 0).getbbox()
    im = im.crop(bb)
    r = 260 / max(im.size)                     # rameaux réduits une fois (rotations rapides)
    return im.resize((max(2, int(im.size[0] * r)), max(2, int(im.size[1] * r))), Image.LANCZOS) if r < 1 else im


def foliage(sprites, n, size, tint, seed, fringe=False, red=0.0):
    """Feuillage dense : rameaux semés du fond vers l'avant (raccord périodique). fringe : bord supérieur clairsemé
    (alpha), le bas plein."""
    rng = np.random.default_rng(seed)
    col = np.zeros((S, S, 3), np.float32); col[:] = np.array([0.035, 0.05, 0.025])
    hgt = np.zeros((S, S), np.float32); cov = np.zeros((S, S), np.float32)
    depth = np.sort(rng.random(n))
    for d in depth:
        sp = sprites[rng.integers(len(sprites))]
        s = int(size * rng.uniform(0.7, 1.3))
        im = sp.rotate(rng.uniform(0, 360), expand=True, resample=Image.BILINEAR)
        r = s / max(im.size)
        im = im.resize((max(2, int(im.size[0] * r)), max(2, int(im.size[1] * r))), Image.BILINEAR)
        a = np.asarray(im).astype(np.float32) / 255
        al = (a[..., 3] > 0.45).astype(np.float32)
        shade = (0.35 + 0.75 * d) * rng.uniform(0.85, 1.15)
        c = a[..., :3] * tint * shade
        if red > 0 and rng.random() < red:                    # photinia : jeunes pousses rouges
            lum = c.mean(2, keepdims=True)
            c = lum * np.array([1.7, 0.6, 0.45])
        x0 = rng.integers(S)
        if fringe:
            y0 = int(S * (0.1 + 0.9 * rng.random() ** 0.6)) - a.shape[0] // 2
        else:
            y0 = rng.integers(S)
        h_, w_ = al.shape
        for ox in (0, -S):
            for oy in ((0, -S) if not fringe else (0,)):
                xa, ya = x0 + ox, y0 + oy
                xs0, ys0 = max(0, xa), max(0, ya)
                xs1, ys1 = min(S, xa + w_), min(S, ya + h_)
                if xs1 <= xs0 or ys1 <= ys0:
                    continue
                m = al[ys0 - ya:ys1 - ya, xs0 - xa:xs1 - xa] > 0
                col[ys0:ys1, xs0:xs1][m] = c[ys0 - ya:ys1 - ya, xs0 - xa:xs1 - xa][m]
                hgt[ys0:ys1, xs0:xs1][m] = d
                cov[ys0:ys1, xs0:xs1][m] = 1.0
    if fringe:
        yy = np.mgrid[0:S, 0:S][0] / S
        cov = np.maximum(cov, (yy > 0.82).astype(np.float32))
        col[cov == 0] = col[cov > 0].mean(0)
    nor = _normal_from_height(ndi.gaussian_filter(hgt, 0.8), 3.0)
    rough = np.full((S, S), 0.55, np.float32) if red == 0 else np.full((S, S), 0.45, np.float32)
    return col, nor, rough, cov if fringe else np.ones((S, S), np.float32)


def photo(src, gain=1.0, desat=1.0):
    d = "data/" + src
    if src.startswith("acg/"):
        name = src.split("/")[1]
        f = ("data/acg/%s/%s_1K-JPG_" % (name, name))
        c, n, r = _load(f + "Color.jpg"), _load(f + "NormalGL.jpg"), _load(f + "Roughness.jpg", "L")
    else:
        c, n, r = _load(d + "/diff.jpg"), _load(d + "/nor_gl.jpg"), _load(d + "/rough.jpg", "L")
    lum = c.mean(2, keepdims=True)
    c = np.clip(lum + (c - lum) * desat, 0, 1)
    c = np.clip(c / c.mean() * gain, 0, 1)
    return c, n, r, np.ones((S, S), np.float32)


def wires(vert_px, horz_px, thick, horz_thick=None, diamond=False, bars=False):
    """Fils (blancs, teintés en jeu) sur fond transparent ; hauteur pour la normale."""
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    if diamond:
        u = (xx + yy) % vert_px; v = (xx - yy) % vert_px
        m = (np.minimum(u, vert_px - u) < thick) | (np.minimum(v, vert_px - v) < thick)
        hgt = np.maximum(1 - np.minimum(u, vert_px - u) / thick, 1 - np.minimum(v, vert_px - v) / thick)
    else:
        u = xx % vert_px; du = np.minimum(u, vert_px - u)
        m = du < thick
        hgt = np.clip(1 - du / thick, 0, 1)
        if horz_px:
            v = yy % horz_px; dv = np.minimum(v, horz_px - v)
            ht = horz_thick or thick
            m |= dv < ht
            hgt = np.maximum(hgt, np.clip(1 - dv / ht, 0, 1))
    hgt = np.sqrt(np.clip(hgt, 0, 1))
    col = np.dstack([0.55 + 0.35 * hgt] * 3)
    return col, _normal_from_height(hgt, 2.0), np.full((S, S), 0.4, np.float32), m.astype(np.float32)


def grille():
    """Grille à barreaux : traverses haute et basse, barreaux de 16 mm tous les 11 cm (1 m couvert)."""
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    px = S / 1.0
    u = xx % (0.11 * px); du = np.minimum(u, 0.11 * px - u)
    m = du < 0.008 * px
    hgt = np.clip(1 - du / (0.008 * px), 0, 1)
    for yc in (0.06, 0.94):
        dv = np.abs(yy - yc * S)
        m |= dv < 0.02 * px
        hgt = np.maximum(hgt, np.clip(1 - dv / (0.02 * px), 0, 1))
    hgt = np.sqrt(hgt)
    col = np.dstack([0.5 + 0.35 * hgt] * 3)
    return col, _normal_from_height(hgt, 2.0), np.full((S, S), 0.35, np.float32), m.astype(np.float32)


def occultant():
    """Lames composites horizontales de 15 cm, rainurées (teintées : anthracite, gris, brun)."""
    rng = np.random.default_rng(5)
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    v = (yy / S * 1.0) % 0.15 / 0.15
    hgt = np.clip(np.minimum(v, 1 - v) / 0.04, 0, 1) * 0.6 + 0.05 * np.sin(xx * 0.9 + rng.random() * 3) ** 2
    hgt += ndi.gaussian_filter(rng.normal(0, 0.15, (S, S)), (0.5, 6))
    col = np.dstack([0.75 + 0.1 * hgt] * 3)
    return col, _normal_from_height(hgt, 2.5), np.full((S, S), 0.5, np.float32), np.ones((S, S), np.float32)


def portail_plein():
    """Vantail plein : cadre et lames horizontales en relief (teinté : blanc, gris, anthracite)."""
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32) / S
    hgt = np.zeros((S, S), np.float32)
    frame = (xx < 0.05) | (xx > 0.95) | (yy < 0.05) | (yy > 0.95)
    v = (yy * 6) % 1
    hgt += np.clip(np.minimum(v, 1 - v) / 0.08, 0, 1) * 0.5
    hgt[frame] = 1.0
    col = np.dstack([0.82 + 0.08 * hgt] * 3)
    return col, _normal_from_height(ndi.gaussian_filter(hgt, 1.0), 4.0), np.full((S, S), 0.35, np.float32), np.ones((S, S), np.float32)


def metal():
    rng = np.random.default_rng(9)
    h = ndi.gaussian_filter(rng.normal(0, 1, (S, S)), 3) * 0.1
    col = np.dstack([0.8 + h] * 3)
    return col, _normal_from_height(h, 1.0), np.full((S, S), 0.4, np.float32), np.ones((S, S), np.float32)


def main():
    os.makedirs(OUT, exist_ok=True)
    laurel = [_sprite(TREES + "/feuillu/textures/normal_leaves_diffuse.png", (0, 0, 0.5, 1)),
              _sprite(TREES + "/feuillu/textures/normal_leaves_diffuse.png", (0.5, 0, 1, 1))]
    conif = [_sprite(TREES + "/epicea/textures/M_Branch.001_baseColor.png", (k * 0.25, 0, k * 0.25 + 0.25, 0.5)) for k in range(4)]
    beech = [_sprite(TREES + "/peuplier/textures/Material.001_diffuse.png")]
    oak = [_sprite(TREES + "/chene2/textures/oak_leaf_1Mat_baseColor.png")]
    gen = {
        "haie_thuya": lambda f=False: foliage(conif, 900 if not f else 500, 70, np.array([0.62, 1.05, 0.42]), 1, f),
        "haie_laurier": lambda f=False: foliage(laurel, 700 if not f else 380, 120, np.array([0.62, 0.92, 0.55]), 2, f),
        "haie_photinia": lambda f=False: foliage(beech, 650 if not f else 360, 110, np.array([0.75, 0.95, 0.6]), 3, f, red=0.15),
        "haie_champetre": lambda f=False: foliage(oak + laurel + beech, 650 if not f else 360, 120, np.array([0.85, 1.0, 0.7]), 4, f),
    }
    A, Nm = [], []
    for name, _ in LAYERS:
        if name.startswith("haie_"):
            col, nor, rough, alpha = gen[name]()
        elif name.startswith("bord_"):
            col, nor, rough, alpha = gen["haie_" + name[5:]](True)
        elif name == "crepi":
            col, nor, rough, alpha = photo("acg/Plaster003", 0.86, 0.2)
        elif name == "pierre":
            col, nor, rough, alpha = photo("ph/old_stone_wall", 0.85, 0.7)
        elif name == "beton":
            col, nor, rough, alpha = photo("ph/concrete_wall_008", 0.75, 0.3)
        elif name == "bois":
            col, nor, rough, alpha = photo("ph/wood_plank_wall", 0.55, 0.9)
        elif name == "grillage_rigide":
            # panneau soudé : fils verticaux tous les 5 cm, horizontaux tous les 20 cm (0,5 m couvert)
            col, nor, rough, alpha = wires(S * 0.1, S * 0.4, 3.6, 3.6)
        elif name == "grillage_losange":
            col, nor, rough, alpha = wires(S * 0.1, 0, 2.4, diamond=True)
        elif name == "occultant":
            col, nor, rough, alpha = occultant()
        elif name == "grille":
            col, nor, rough, alpha = grille()
        elif name == "metal":
            col, nor, rough, alpha = metal()
        elif name == "portail_plein":
            col, nor, rough, alpha = portail_plein()
        A.append(np.dstack([col, alpha])); Nm.append(np.dstack([nor, rough]))
        print(name, np.round(col.reshape(-1, 3).mean(0), 2), "couverture %.2f" % alpha.mean())
    for arr, f in ((A, "albedo"), (Nm, "normal")):
        img = (np.clip(np.vstack(arr), 0, 1) * 255).astype(np.uint8)
        Image.fromarray(img, "RGBA").save("%s/%s.png" % (OUT, f))
        open("%s/%s.png.import" % (OUT, f), "w").write(
            '[remap]\n\nimporter="2d_array_texture"\ntype="CompressedTexture2DArray"\n\n[params]\n\n'
            'compress/mode=2\ncompress/high_quality=false\ncompress/lossy_quality=0.7\ncompress/hdr_compression=1\n'
            'compress/channel_pack=0\nmipmaps/generate=true\nmipmaps/limit=-1\nslices/horizontal=1\nslices/vertical=%d\n'
            % len(LAYERS))
    prev = []
    for a in A:
        bg = np.where((np.mgrid[0:S, 0:S][0] // 32 + np.mgrid[0:S, 0:S][1] // 32) % 2, 0.85, 0.6)[..., None]
        prev.append(a[..., :3] * a[..., 3:] + bg * (1 - a[..., 3:]))
    Image.fromarray((np.clip(np.hstack(prev), 0, 1) * 255).astype(np.uint8)).resize((160 * len(A), 160)).save("data/fence_tex_preview.jpg")


if __name__ == "__main__":
    main()
