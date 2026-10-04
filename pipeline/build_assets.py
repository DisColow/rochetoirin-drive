"""Textures et maillages de décor pour Godot.
 - textures Terrain3D (1024 px) : albedo + hauteur (RGBA), normale OpenGL + rugosité (RGBA) -> godot/assets/terrain_tex/
 - textures PBR des routes (1024 px) -> godot/assets/tex/<nom>_{albedo,normal,rough}.jpg
 - horizon : relief des environs (50 m) et lointain (500 m, ±75 km) texturé par l'orthophoto -> godot/world/far/*.glb
"""
import json, os, shutil
import numpy as np
from PIL import Image
from glb import write_glb

PH = "data/ph"
GT = "../godot/assets/terrain_tex"; GX = "../godot/assets/tex"; GF = "../godot/world/far"
for d in (GT, GX, GF):
    os.makedirs(d, exist_ok=True)
# Poly Haven (ph) ou ambientCG (acg:Nom), CC0
TERRAIN = ["acg:Grass005", "acg:Grass001", "forest_ground_04", "aerial_rocks_02", "acg:Ground037", "dry_ground_rocks"]
ROADS = {"asphalt": "asphalt_02", "dirt": "gravel_road", "sidewalk": "concrete_pavement", "concrete": "concrete"}
S = 1024


def im(p, mode):
    return Image.open(p).convert(mode).resize((S, S), Image.LANCZOS)


def terrain_textures():
    for k, t in enumerate(TERRAIN):
        if t.startswith("acg:"):
            t = t[4:]; b = "data/acg/%s/%s_2K-JPG_" % (t, t)
            a = im(b + "Color.jpg", "RGB"); h = im(b + "Displacement.jpg", "L")
            n = im(b + "NormalGL.jpg", "RGB"); r = im(b + "Roughness.jpg", "L")
        else:
            a = im("%s/%s/diff.jpg" % (PH, t), "RGB"); h = im("%s/%s/disp.jpg" % (PH, t), "L")
            n = im("%s/%s/nor_gl.jpg" % (PH, t), "RGB"); r = im("%s/%s/rough.jpg" % (PH, t), "L")
        if k == 4:                                    # chaume : moins éblouissant
            from PIL import ImageEnhance
            a = ImageEnhance.Brightness(a).enhance(0.78)
        Image.merge("RGBA", (*a.split(), h)).save("%s/%d_albedo_height.png" % (GT, k))
        Image.merge("RGBA", (*n.split(), r)).save("%s/%d_normal_rough.png" % (GT, k))


def road_textures():
    for name, t in ROADS.items():
        im("%s/%s/diff.jpg" % (PH, t), "RGB").save("%s/%s_albedo.jpg" % (GX, name), quality=92)
        im("%s/%s/nor_gl.jpg" % (PH, t), "RGB").save("%s/%s_normal.jpg" % (GX, name), quality=95)
        im("%s/%s/rough.jpg" % (PH, t), "L").save("%s/%s_rough.jpg" % (GX, name), quality=92)
    shutil.copy(PH + "/sky.hdr", "../godot/assets/sky.hdr")


def grid_mesh(A, x0, z0, step, skip, sink):
    """Maillage régulier ; quads dont les 4 coins sont dans skip(x, z) omis ; uv = coordonnées image 0-1."""
    H, W = A.shape
    xs = x0 + np.arange(W) * step; zs = z0 + np.arange(H) * step
    X, Z = np.meshgrid(xs, zs)
    P = np.c_[X.ravel(), A.ravel() - sink, Z.ravel()].astype(np.float32)
    UV = np.c_[(np.arange(W) / (W - 1))[None, :].repeat(H, 0).ravel(), (np.arange(H) / (H - 1))[:, None].repeat(W, 1).ravel()]
    gy, gx = np.gradient(A, step)
    Nn = np.c_[-gx.ravel(), np.ones(A.size), -gy.ravel()]; Nn /= np.linalg.norm(Nn, axis=1, keepdims=True)
    inside = skip(X, Z)
    q = np.arange(H - 1)[:, None] * W + np.arange(W - 1)[None, :]
    keep = ~(inside[:-1, :-1] & inside[1:, :-1] & inside[:-1, 1:] & inside[1:, 1:])
    q = q[keep]
    I = np.c_[q, q + W, q + 1, q + 1, q + W, q + W + 1].ravel().astype(np.uint32)
    return P, Nn.astype(np.float32), UV.astype(np.float32), I


def far():
    regs = set(tuple(r) for r in json.load(open("data/routes_plan.json"))["regions"])
    # environs à 50 m (sous-échantillonnage de la grille de 25 m), découpés en 4 × 4 morceaux
    nm = json.load(open("data/dem/near.json")); A = np.load("data/dem/near.npy")[::2, ::2]
    step = nm["step"] * 2

    def in_regions(X, Z, m=60.0):
        """Point à plus de m mètres du bord de l'ensemble des régions (pas de chaque région : sinon une bande de
        120 m subsiste le long de chaque frontière entre régions et ressort dans les vallons encaissés)."""
        def inside(x, z):
            key = np.floor(x / 1024).astype(int) * 100000 + np.floor(z / 1024).astype(int)
            return np.isin(key, [i * 100000 + j for i, j in regs])
        r = np.ones(X.shape, bool)
        for dx in (-m, 0, m):
            for dz in (-m, 0, m):
                r &= inside(X + dx, Z + dz)
        return r
    H, W = A.shape
    ci, cj = 4, 4
    for a in range(ci):
        for b in range(cj):
            i0, i1 = a * (W - 1) // ci, (a + 1) * (W - 1) // ci + 1
            j0, j1 = b * (H - 1) // cj, (b + 1) * (H - 1) // cj + 1
            sub = A[j0:j1, i0:i1]
            P, Nn, UV, I = grid_mesh(sub, nm["x0"] + i0 * step, nm["z0"] + j0 * step, step, in_regions, 1.5)
            # uv dans l'image complète des environs
            UV[:, 0] = (i0 + UV[:, 0] * (i1 - i0 - 1)) / (W - 1); UV[:, 1] = (j0 + UV[:, 1] * (j1 - j0 - 1)) / (H - 1)
            if len(I):
                write_glb("%s/near_%d_%d.glb" % (GF, a, b), [("far_near", P, Nn, UV, I)])
    Image.open("data/ortho/near.jpg").save("../godot/assets/tex/far_near.jpg", quality=90)
    # lointain : 500 m sur ±75 km, trou à l'emplacement des environs
    B = np.load("data/dem/pano.npy")
    x1, z1 = nm["x0"] + nm["w"] * nm["step"], nm["z0"] + nm["h"] * nm["step"]
    skip = lambda X, Z: (X > nm["x0"] + 1000) & (X < x1 - 1000) & (Z > nm["z0"] + 1000) & (Z < z1 - 1000)
    P, Nn, UV, I = grid_mesh(B, -75000, -75000, 500, skip, 8.0)
    write_glb("%s/pano.glb" % GF, [("far_pano", P, Nn, UV, I)])
    Image.open("data/ortho/pano.jpg").save("../godot/assets/tex/far_pano.jpg", quality=90)


if __name__ == "__main__":
    terrain_textures(); road_textures(); far()
    print("ok")
