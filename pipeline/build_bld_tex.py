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
    # bâtiments emblématiques (étape 4)
    ("ardoise", "ph/roof_slates_02", 2.0),
    ("pierre_claire", "ph/old_stone_wall", 2.5),
    ("vitrail_cintre", None, 1.0),
    ("vitrail_ogive", None, 1.0),
    ("abat_son", None, 1.0),
    ("portail_cintre", None, 1.0),
    ("portail_ogive", None, 1.0),
    ("rosace", None, 1.0),
    ("horloge", None, 1.0),
    ("drapeau_fr", None, 1.0),
    ("drapeau_eu", None, 1.0),
    ("plaque_mairie", None, 1.0),
    ("plaque_hdv", None, 1.0),
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


# ------------------------------------------------------------------------------------------------ monuments
def _stone_frame():
    """Encadrement en pierre de taille claire (fond des baies d'église), non teinté par le bâtiment."""
    st = _load("data/ph/rustic_stone_wall/diff.jpg")
    lum = st.mean(2, keepdims=True)
    col = np.clip(0.72 + (lum - lum.mean()) * 0.6, 0, 1) * np.array([1.0, 0.95, 0.86])
    h = (lum[..., 0] - lum.mean()) * 1.5 + 1.0
    return col, h


def _arch_mask(x0, x1, y_top, y_bot, pointed):
    """Masque d'une baie en plein cintre ou en ogive (coordonnées 0-1, y vers le bas)."""
    yy, xx = np.mgrid[0:S, 0:S] / S
    w = (x1 - x0) / 2; cx = (x0 + x1) / 2
    if pointed:
        r = w * 1.6
        spring = y_top + r * 0.95
        left = (xx - (cx + w - r)) ** 2 + (yy - spring) ** 2 <= r * r
        right = (xx - (cx - w + r)) ** 2 + (yy - spring) ** 2 <= r * r
        arch = left & right & (yy < spring)
    else:
        spring = y_top + w
        arch = ((xx - cx) ** 2 + (yy - spring) ** 2 <= w * w) & (yy < spring)
    rect = (yy >= spring) & (yy <= y_bot) & (xx >= x0) & (xx <= x1)
    return (arch | rect) & (xx >= x0) & (xx <= x1)


def _stained(seed):
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:S, 0:S] / S
    # losanges sertis de plomb, couleurs profondes (vues de l'extérieur : sombres et réfléchissantes)
    u = (xx + yy) * 14; v = (xx - yy) * 14
    cell = (np.floor(u).astype(int) * 31 + np.floor(v).astype(int) * 17) % 7
    pal = np.array([[0.10, 0.14, 0.32], [0.30, 0.08, 0.08], [0.32, 0.26, 0.10], [0.12, 0.22, 0.16], [0.16, 0.16, 0.26],
                    [0.24, 0.12, 0.22], [0.18, 0.20, 0.30]])
    col = pal[cell] * (0.8 + 0.4 * rng.random((S, S, 1)))
    lead = (np.abs(u - np.round(u)) < 0.06) | (np.abs(v - np.round(v)) < 0.06)
    col[lead] = 0.05
    return col, lead


def church_window(pointed):
    col, h = _stone_frame()
    m = _arch_mask(0.16, 0.84, 0.04, 0.97, pointed)
    inner = _arch_mask(0.22, 0.78, 0.10, 0.97, pointed)
    gl, lead = _stained(2 if pointed else 3)
    col[m] = col[m] * 0.85
    col[inner] = gl[inner]
    h[m] = 0.6; h[inner] = 0.0 + lead[inner] * 0.15
    glass = inner.astype(np.float32)
    return col, _normal_from_height(h, 5.0), np.where(inner, 0.06, 0.75).astype(np.float32), glass


def louvre():
    col, h = _stone_frame()
    inner = _arch_mask(0.2, 0.8, 0.06, 0.98, False)
    yy = np.mgrid[0:S, 0:S][0] / S
    slat = (yy * 22) % 1.0
    wood = np.dstack([0.30 + 0.25 * slat, 0.27 + 0.22 * slat, 0.24 + 0.18 * slat])
    col[inner] = (wood * 0.9)[inner]
    h[inner] = slat[inner] * 0.5
    return col, _normal_from_height(h, 8.0), np.full((S, S), 0.7, np.float32), np.zeros((S, S), np.float32)


def portal(pointed):
    col, h = _stone_frame()
    m = _arch_mask(0.08, 0.92, 0.02, 1.0, pointed)
    door = _arch_mask(0.16, 0.84, 0.10, 1.0, pointed)
    wood = _load("data/ph/rough_pine_door/diff.jpg")
    yy, xx = np.mgrid[0:S, 0:S] / S
    col[m] *= 0.88
    # tympan en pierre au-dessus des vantaux, vantaux en bois sombre
    leaf = door & (yy > 0.42)
    col[door] = col[door] * 0.92
    col[leaf] = (wood * np.array([0.75, 0.62, 0.5]))[leaf]
    seam = leaf & (np.abs(xx - 0.5) < 0.006)
    col[seam] = 0.08
    h[m] = 0.7; h[door] = 0.4; h[leaf] = 0.2 + wood.mean(2)[leaf] * 0.2
    return col, _normal_from_height(h, 5.0), np.full((S, S), 0.7, np.float32), np.zeros((S, S), np.float32)


def rose():
    col, h = _stone_frame()
    yy, xx = np.mgrid[0:S, 0:S] / S
    r = np.hypot(xx - 0.5, yy - 0.5); a = np.arctan2(yy - 0.5, xx - 0.5)
    gl, lead = _stained(4)
    disk = r < 0.40
    petals = (np.cos(a * 12) * 0.5 + 0.5) > 0.25
    glass = disk & ((r < 0.10) | ((r > 0.13) & (r < 0.37) & petals))
    col[r < 0.46] *= 0.85
    col[glass] = gl[glass]
    h[r < 0.46] = 0.6; h[glass] = 0.0
    return col, _normal_from_height(h, 5.0), np.where(glass, 0.06, 0.75).astype(np.float32), glass.astype(np.float32)


def clock():
    from PIL import ImageDraw
    col, h = _stone_frame()
    im = Image.new("RGB", (S, S), (0, 0, 0)); d = ImageDraw.Draw(im)
    d.ellipse((90, 90, S - 90, S - 90), fill=(235, 232, 222), outline=(40, 40, 40), width=18)
    import math as m
    for k in range(60):
        a = k / 60 * 2 * m.pi; L = 60 if k % 5 == 0 else 22; w = 14 if k % 5 == 0 else 5
        c = S / 2; R = S / 2 - 120
        d.line((c + m.sin(a) * R, c - m.cos(a) * R, c + m.sin(a) * (R - L), c - m.cos(a) * (R - L)), fill=(25, 25, 25), width=w)
    c = S / 2
    d.line((c, c, c + 150, c - 160), fill=(20, 20, 20), width=26)       # 10 h 10 : aiguilles
    d.line((c, c, c - 260, c - 120), fill=(20, 20, 20), width=16)
    a = np.asarray(im).astype(np.float32) / 255
    face = a.sum(2) > 0.05
    col[face] = a[face]
    h[face] = 0.9
    return col, _normal_from_height(h, 3.0), np.full((S, S), 0.5, np.float32), np.zeros((S, S), np.float32)


def flag(kind):
    yy, xx = np.mgrid[0:S, 0:S] / S
    if kind == "fr":
        col = np.where(xx[..., None] < 1 / 3, np.array([0.0, 0.2, 0.58]),
                       np.where(xx[..., None] < 2 / 3, np.array([0.96, 0.96, 0.96]), np.array([0.88, 0.16, 0.18])))
    else:
        col = np.zeros((S, S, 3)) + np.array([0.0, 0.2, 0.6])
        import math as m
        for k in range(12):
            a = k / 12 * 2 * m.pi
            cx, cy = 0.5 + 0.30 * m.sin(a), 0.5 - 0.30 * m.cos(a)
            col[np.hypot(xx - cx, (yy - cy)) < 0.035] = np.array([1.0, 0.82, 0.0])
    # plis du tissu
    shade = 0.82 + 0.18 * np.sin(xx * 14 + np.sin(yy * 5) * 1.5)
    col = col * shade[..., None]
    h = np.sin(xx * 14 + np.sin(yy * 5) * 1.5) * 0.5
    return col, _normal_from_height(h, 6.0), np.full((S, S), 0.8, np.float32), np.zeros((S, S), np.float32)


def plaque(text):
    from PIL import ImageDraw, ImageFont
    im = Image.new("RGB", (1024, 240), (24, 38, 78)); d = ImageDraw.Draw(im)
    d.rectangle((8, 8, 1015, 231), outline=(214, 182, 96), width=8)
    f = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf", 150 if len(text) < 8 else 104)
    w = d.textlength(text, font=f)
    d.text(((1024 - w) / 2, 120), text, font=f, fill=(236, 214, 140), anchor="lm")
    col = np.asarray(im.resize((S, S), Image.LANCZOS)).astype(np.float32) / 255
    h = col.mean(2)
    return col, _normal_from_height(h, 2.0), np.full((S, S), 0.35, np.float32), np.zeros((S, S), np.float32)


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
                                      "volet": shutter, "porte": door, "porte_garage": garage, "vitrine": shop,
                                      "vitrail_cintre": lambda: church_window(False), "vitrail_ogive": lambda: church_window(True),
                                      "abat_son": louvre, "portail_cintre": lambda: portal(False),
                                      "portail_ogive": lambda: portal(True), "rosace": rose, "horloge": clock,
                                      "drapeau_fr": lambda: flag("fr"), "drapeau_eu": lambda: flag("eu"),
                                      "plaque_mairie": lambda: plaque("MAIRIE"),
                                      "plaque_hdv": lambda: plaque("HÔTEL DE VILLE")}[name]()
        if name == "toit_plat":                                         # gravillons gris d'étanchéité
            col = np.clip(col.mean(2, keepdims=True) / col.mean() * np.array([0.52, 0.52, 0.50]), 0, 1)
        if name == "crepi_ancien":                                      # taches moins orangées
            lum = col.mean(2, keepdims=True)
            col = np.clip(lum + (col - lum) * 0.45, 0, 1) / lum.mean() * 0.8
        if name == "pierre_claire":                                     # moellons calcaires clairs (églises)
            lum = col.mean(2, keepdims=True)
            col = np.clip(lum + (col - lum) * 0.35, 0, 1) / lum.mean() * np.array([0.74, 0.69, 0.6])
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
