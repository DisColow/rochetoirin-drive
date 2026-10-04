"""Tableau de textures des bâtiments (une couche de 1024² par matériau) -> godot/assets/bld/
 - albedo.png : RVB + alpha = masque de vitrage (reflets du ciel) ;
 - normal.png : normale (RVB) + alpha = rugosité.
Murs, toits : photos PBR Poly Haven / ambientCG (CC0). Ouvertures (fenêtres, volets, portes, vitrines) composées à
partir de ces photos. L'ordre des couches (LAYERS) est partagé avec build_buildings.py et le shader."""
import os
import numpy as np
from PIL import Image, ImageFilter

S = 1024
OUT = "../godot/assets/bld"
# nom, source, mètres couverts par la texture (u, v)
LAYERS = [
    ("crepi", "acg/Plaster003", 2.5),
    ("crepi_ancien", "ph/medieval_wall_01", 3.0),
    ("pierre", "ph/old_stone_wall", 2.5),
    ("pierre_taillee", "ph/rustic_stone_wall", 2.5),
    ("brique", "acg/Bricks085", 2.0),
    ("bardage_bois", "ph/wood_plank_wall", 2.5),
    ("bardage_metal", "acg/CorrugatedSteel005", 2.5),
    ("beton", "ph/concrete_wall_008", 3.0),
    ("tuile_meca", "ph/clay_roof_tiles_03", 2.5),
    ("tuile_ancienne", "ph/clay_roof_tiles_02", 2.5),
    ("tuile_mousse", "ph/ceramic_roof_01", 2.5),
    ("tuile_grise", "ph/grey_roof_tiles", 2.5),
    ("toit_plat", "ph2/gravel_road", 4.0),
    ("fenetre", None, 1.0),
    ("fenetre_volet_roulant", None, 1.0),
    ("volet", None, 1.0),
    ("porte", None, 1.0),
    ("porte_garage", None, 1.0),
    ("vitrine", None, 1.0),
]
IDX = {n: i for i, (n, _, _) in enumerate(LAYERS)}


def _files(src):
    kind, name = src.split("/")
    if kind == "ph2":
        d = "data/ph/%s/" % name
        return d + "diff.jpg", d + "nor_gl.jpg", d + "rough.jpg"
    if kind == "ph":
        d = "data/ph/%s/" % name
        return d + "diff.jpg", d + "nor_gl.jpg", d + "rough.jpg"
    d = "data/acg/%s/%s_1K-JPG_" % (name, name)
    return d + "Color.jpg", d + "NormalGL.jpg", d + "Roughness.jpg"


def _load(p, mode="RGB"):
    return np.asarray(Image.open(p).convert(mode).resize((S, S), Image.LANCZOS)).astype(np.float32) / 255


def _normal_from_height(h, strength=6.0):
    gy, gx = np.gradient(h)
    n = np.dstack([-gx * strength, gy * strength, np.ones_like(h)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return n * 0.5 + 0.5


def _rect(a, x0, y0, x1, y1, v):
    a[int(y0 * S):int(y1 * S), int(x0 * S):int(x1 * S)] = v


def window(roller=False):
    """Fenêtre française à deux vantaux, cadre PVC blanc, petits bois, voilage léger ; volet roulant optionnel."""
    rng = np.random.default_rng(3 if roller else 1)
    col = np.zeros((S, S, 3), np.float32); h = np.zeros((S, S), np.float32); glass = np.zeros((S, S), np.float32)
    rough = np.full((S, S), 0.5, np.float32)
    frame = np.array([0.90, 0.90, 0.88])
    col[:] = frame; h[:] = 1.0
    top = 0.0
    if roller:
        # coffre et lames du volet roulant (photo de rideau métallique éclaircie)
        sl = _load("data/ph/painted_metal_shutter/diff.jpg")
        lum = sl.mean(2, keepdims=True)
        sl = np.clip(0.55 + (lum - lum.mean()) * 1.6, 0, 1) * np.array([0.95, 0.93, 0.88])
        top = 0.32
        col[:int(top * S)] = sl[:int(top * S)]
        h[:int(top * S)] = 0.6 + (lum[:int(top * S), :, 0] - lum.mean()) * 0.8
        _rect(col, 0, 0, 1, 0.05, frame * 0.97); _rect(h, 0, 0, 1, 0.05, 1.2)
    y0 = top + 0.05
    # vitrage : intérieur sombre, voilage plus clair, léger dégradé
    yy, xx = np.mgrid[0:S, 0:S] / S
    interior = 0.07 + 0.05 * (1 - yy) + rng.normal(0, 0.008, (S, S))
    voile = 0.32 + 0.06 * np.sin(xx * 90) ** 2
    gl = np.dstack([interior * 0.9 + voile * 0.55, interior * 0.95 + voile * 0.55, interior + voile * 0.56])
    for x0, x1 in ((0.07, 0.475), (0.525, 0.93)):
        for k in range(3):
            pa = y0 + (0.95 - y0) * k / 3; pb = y0 + (0.95 - y0) * (k + 1) / 3
            sy0, sy1 = pa + 0.012, pb - 0.012
            sx0, sx1 = x0 + 0.012, x1 - 0.012
            sl = (slice(int(sy0 * S), int(sy1 * S)), slice(int(sx0 * S), int(sx1 * S)))
            col[sl] = gl[sl]; h[sl] = 0.0; glass[sl] = 1.0; rough[sl] = 0.05
    # pièce d'appui (bas) un peu plus sombre
    _rect(col, 0, 0.95, 1, 1, frame * 0.8)
    return col, _normal_from_height(h), rough, glass


def shutter():
    """Volet battant à lames verticales, gris clair (teinté par bâtiment)."""
    w = _load("data/ph/wood_shutter/diff.jpg")
    lum = w.mean(2)
    v = np.clip(0.78 + (lum - lum.mean()) * 1.2, 0, 1)
    col = np.dstack([v, v, v])
    # barres et écharpe en Z
    h = (lum - lum.mean()) * 2
    for a, b in ((0.12, 0.18), (0.82, 0.88)):
        _rect(col, 0, a, 1, b, 0.84); _rect(h, 0, a, 1, b, 0.8)
    n = _load("data/ph/wood_shutter/nor_gl.jpg")
    nh = _normal_from_height(h, 3.0)
    nn = n * 0.5 + nh * 0.5
    return col, nn, np.full((S, S), 0.6, np.float32), np.zeros((S, S), np.float32)


def door():
    c = Image.open("data/acg/Door001/Door001_1K-JPG_Color.jpg").convert("RGB")
    n = Image.open("data/acg/Door001/Door001_1K-JPG_NormalGL.jpg").convert("RGB")
    a = np.asarray(Image.open("data/acg/Door001/Door001_1K-JPG_Opacity.jpg").convert("L"))
    cols = np.where(a.mean(0) > 128)[0]; rows = np.where(a.mean(1) > 128)[0]
    box = (int(cols[0]), int(rows[0]), int(cols[-1]) + 1, int(rows[-1]) + 1)
    col = np.asarray(c.crop(box).resize((S, S), Image.LANCZOS)).astype(np.float32) / 255
    nor = np.asarray(n.crop(box).resize((S, S), Image.LANCZOS)).astype(np.float32) / 255
    glass = ((col.max(2) - col.min(2)) < 0.06) & (col.mean(2) > 0.35)
    glass = np.asarray(Image.fromarray((glass * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(5))) > 0
    col[glass] = col[glass] * 0.25
    return col, nor, np.where(glass, 0.05, 0.55).astype(np.float32), glass.astype(np.float32)


def garage():
    sl = _load("data/ph/painted_metal_shutter/diff.jpg")
    lum = sl.mean(2)
    v = np.clip(0.8 + (lum - lum.mean()) * 1.3, 0, 1)
    col = np.dstack([v, v, v * 0.98])
    h = (lum - lum.mean()) * 3
    _rect(col, 0, 0, 0.03, 1, 0.7); _rect(col, 0.97, 0, 1, 1, 0.7); _rect(col, 0, 0, 1, 0.03, 0.7)
    return col, _normal_from_height(h, 4.0), np.full((S, S), 0.45, np.float32), np.zeros((S, S), np.float32)


def shop():
    rng = np.random.default_rng(5)
    col = np.zeros((S, S, 3), np.float32); h = np.ones((S, S), np.float32)
    frame = np.array([0.22, 0.23, 0.25]); col[:] = frame
    glass = np.zeros((S, S), np.float32); rough = np.full((S, S), 0.4, np.float32)
    yy, xx = np.mgrid[0:S, 0:S] / S
    inside = 0.12 + 0.10 * (yy > 0.7) + 0.05 * np.sin(xx * 25) ** 2 + rng.normal(0, 0.01, (S, S))
    for x0, x1 in ((0.03, 0.49), (0.51, 0.97)):
        sl = (slice(int(0.22 * S), int(0.97 * S)), slice(int(x0 * S), int(x1 * S)))
        col[sl] = np.dstack([inside, inside * 1.02, inside * 1.05])[sl]; h[sl] = 0; glass[sl] = 1; rough[sl] = 0.05
    # bandeau d'enseigne
    _rect(col, 0, 0.02, 1, 0.18, np.array([0.80, 0.78, 0.74])); _rect(h, 0, 0.02, 1, 0.18, 1.3)
    return col, _normal_from_height(h, 3.0), rough, glass


def main():
    os.makedirs(OUT, exist_ok=True)
    A, Nm = [], []
    for name, src, _ in LAYERS:
        if src:
            c, n, r = _files(src)
            col = _load(c); nor = _load(n); rough = _load(r, "L")
            glass = np.zeros((S, S), np.float32)
        else:
            col, nor, rough, glass = {"fenetre": lambda: window(False), "fenetre_volet_roulant": lambda: window(True),
                                      "volet": shutter, "porte": door, "porte_garage": garage, "vitrine": shop}[name]()
        if name == "toit_plat":                                         # gravillons gris d'étanchéité
            col = np.clip(col.mean(2, keepdims=True) / col.mean() * np.array([0.52, 0.52, 0.50]), 0, 1)
        if name == "crepi_ancien":                                      # taches moins orangées
            lum = col.mean(2, keepdims=True)
            col = np.clip(lum + (col - lum) * 0.45, 0, 1) / lum.mean() * 0.8
        if name in ("crepi",):
            col = np.clip(col / col.mean() * 0.86, 0, 1)                 # crépi blanc neutre, teinté par bâtiment
        A.append(np.dstack([col, glass])); Nm.append(np.dstack([nor, rough]))
        print(name, np.round(col.reshape(-1, 3).mean(0), 2))
    for arr, f in ((A, "albedo"), (Nm, "normal")):
        img = (np.clip(np.vstack(arr), 0, 1) * 255).astype(np.uint8)
        Image.fromarray(img, "RGBA").save("%s/%s.png" % (OUT, f))
        open("%s/%s.png.import" % (OUT, f), "w").write(
            '[remap]\n\nimporter="2d_array_texture"\ntype="CompressedTexture2DArray"\n\n[params]\n\n'
            'compress/mode=2\ncompress/high_quality=false\ncompress/lossy_quality=0.7\ncompress/hdr_compression=1\n'
            'compress/channel_pack=0\nmipmaps/generate=true\nmipmaps/limit=-1\nslices/horizontal=1\nslices/vertical=%d\n'
            % len(LAYERS))
    # aperçu
    prev = Image.fromarray((np.clip(np.hstack([a[..., :3] for a in A]), 0, 1) * 255).astype(np.uint8)).resize((128 * len(A), 128))
    prev.save("data/bld_tex_preview.jpg")


if __name__ == "__main__":
    main()
