"""Atlas des cultures (1024 × 6144 : 4 bandes de 3 m × 3 m vues de côté, sol en bas, puis 2 vues de dessus) :
0 maïs (rangée cuite depuis le modèle 3D, tools/bake_impostors), 1 céréales (épis dorés), 2 feuillage bas (colza, soja),
3 tournesol, 4 céréales vues de dessus, 5 feuillage vu de dessus. Sorties : ../godot/assets/veg/crops_albedo.png, crops_normal.png."""
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi

S = 1024
rng = np.random.default_rng(4)


def cereal():
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    top = S - int(0.95 / 3 * S)
    for k in range(1400):
        x = rng.uniform(0, S); h = rng.uniform(0.75, 1.0) * (S - top)
        lean = rng.normal(0, 10)
        c = tuple(int(v) for v in np.array([196, 160, 82]) * rng.uniform(0.75, 1.1))
        d.line((x, S, x + lean, S - h), fill=c + (255,), width=3)
        # épi
        ex, ey = x + lean, S - h
        d.ellipse((ex - 5, ey - 22, ex + 5, ey + 4), fill=tuple(int(v * 1.05) for v in c) + (255,))
    return im


def leafy(flowers=False):
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    top = S - int((1.7 if flowers else 0.9) / 3 * S)
    for k in range(900 if not flowers else 500):
        x = rng.uniform(0, S); y = rng.uniform(top + 30, S)
        r = rng.uniform(10, 26)
        g = tuple(int(v) for v in np.array([62, 108, 40]) * rng.uniform(0.7, 1.2))
        d.ellipse((x - r, y - r * 0.6, x + r, y + r * 0.6), fill=g + (255,))
    if flowers:
        for k in range(46):
            x = rng.uniform(20, S - 20); y = rng.uniform(top, top + 120)
            d.line((x, y, x + rng.normal(0, 6), S), fill=(70, 100, 45, 255), width=6)
            r = rng.uniform(24, 34)
            d.ellipse((x - r, y - r, x + r, y + r), fill=(238, 190, 30, 255))
            d.ellipse((x - r * 0.45, y - r * 0.45, x + r * 0.45, y + r * 0.45), fill=(70, 45, 20, 255))
    else:
        for k in range(160):   # fleurs jaunes de colza éparses
            x = rng.uniform(0, S); y = rng.uniform(top, top + 60)
            d.ellipse((x - 5, y - 4, x + 5, y + 4), fill=(225, 205, 50, 255))
    return im


def top(kind):
    """Vue de dessus (nappe) : épis dorés serrés, ou feuillage avec fleurs de colza éparses."""
    im = Image.new("RGBA", (S, S), (0, 0, 0, 255)); d = ImageDraw.Draw(im)
    base = np.array([182, 150, 76]) if kind == "cereal" else np.array([58, 102, 38])
    a = (ndi.gaussian_filter(rng.random((S, S)), 6) - 0.5) * 0.6 + 1.0
    arr = np.clip(base[None, None, :] * a[..., None], 0, 255)
    im = Image.fromarray(np.dstack([arr, np.full((S, S), 255)]).astype(np.uint8), "RGBA"); d = ImageDraw.Draw(im)
    for k in range(9000 if kind == "cereal" else 2500):
        x, y = rng.uniform(0, S, 2)
        if kind == "cereal":
            c = tuple(int(v) for v in base * rng.uniform(0.8, 1.25))
            ang = rng.uniform(0, np.pi); L = rng.uniform(8, 16)
            d.line((x, y, x + np.cos(ang) * L, y + np.sin(ang) * L), fill=c + (255,), width=4)
        else:
            r = rng.uniform(8, 20); c = tuple(int(v) for v in base * rng.uniform(0.75, 1.3))
            d.ellipse((x - r, y - r * 0.7, x + r, y + r * 0.7), fill=c + (255,))
    if kind != "cereal":
        for k in range(500):
            x, y = rng.uniform(0, S, 2)
            d.ellipse((x - 4, y - 4, x + 4, y + 4), fill=(222, 202, 52, 255))
    return im


def main():
    rows_a, rows_n = [], []
    ma = Image.open("../godot/assets/veg/strip_mais_albedo.png").convert("RGBA").resize((S, S))
    mn = Image.open("../godot/assets/veg/strip_mais_normal.png").convert("RGBA").resize((S, S))
    rows_a.append(ma); rows_n.append(mn)
    flat = Image.new("RGBA", (S, S), (128, 128, 255, 255))
    for im in (cereal(), leafy(False), leafy(True), top("cereal"), top("leafy")):
        rows_a.append(im); rows_n.append(flat)
    A = np.vstack([np.asarray(r) for r in rows_a]).astype(np.float32)
    N = np.vstack([np.asarray(r) for r in rows_n]).astype(np.float32)
    # débord de couleur sous les pixels transparents
    m = A[..., 3] > 8
    _, (iy, ix) = ndi.distance_transform_edt(~m, return_indices=True)
    A[..., :3] = A[..., :3][iy, ix]; N[..., :3] = N[..., :3][iy, ix]
    N[..., 3] = A[..., 3]
    Image.fromarray(A.astype(np.uint8), "RGBA").save("../godot/assets/veg/crops_albedo.png")
    Image.fromarray(N.astype(np.uint8), "RGBA").save("../godot/assets/veg/crops_normal.png")
    prev = Image.new("RGBA", (S, 6 * S), (140, 170, 200, 255)); prev.alpha_composite(Image.fromarray(A.astype(np.uint8), "RGBA"))
    prev.convert("RGB").resize((256, 1536)).save("data/crops_preview.jpg")


if __name__ == "__main__":
    main()
