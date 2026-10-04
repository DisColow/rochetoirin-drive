"""Cartes Terrain3D par région (512 × 512, 2 m) : hauteur (terrassée), contrôle (texture de base / surcouche / mélange),
couleur (teinte issue de l'orthophoto, atténuée). Sorties : ../godot/import/terrain/r_i_j.{h,c}.raw, r_i_j.color.png

Textures (ordre des assets Terrain3D) :
 0 herbe tondue (leafy_grass)   1 prairie (grass_ground)   2 sous-bois (forest_ground_04)
 3 roche (aerial_rocks_02)      4 terre labourée (brown_mud_02)   5 accotement gravillonné (dry_ground_rocks)
"""
import json, os, pickle
import numpy as np
from PIL import Image
from scipy import ndimage as ndi
from shapely.geometry import Polygon, shape
from shapely.ops import unary_union
import shapely
from geo import to_local
from build_roads import samples, road_height_fn

OUT = "../godot/import/terrain"; os.makedirs(OUT, exist_ok=True)
REG = 1024.0


def landuse():
    d = json.load(open("data/osm.json"))
    N = {e["id"]: to_local(e["lon"], e["lat"]) for e in d["elements"] if e["type"] == "node"}
    W = {e["id"]: e for e in d["elements"] if e["type"] == "way"}
    forest, farm, grass, resid = [], [], [], []
    def poly(nodes):
        pts = [tuple(map(float, N[n])) for n in nodes if n in N]
        return Polygon(pts).buffer(0) if len(pts) >= 4 else None
    for e in d["elements"]:
        t = e.get("tags", {})
        lu = t.get("landuse") or t.get("natural")
        if lu is None:
            continue
        ps = []
        if e["type"] == "way" and e["nodes"][0] == e["nodes"][-1]:
            ps = [poly(e["nodes"])]
        elif e["type"] == "relation":
            for m in e.get("members", []):
                if m["type"] == "way" and m.get("role") == "outer" and m["ref"] in W and W[m["ref"]]["nodes"][0] == W[m["ref"]]["nodes"][-1]:
                    ps.append(poly(W[m["ref"]]["nodes"]))
        ps = [p for p in ps if p is not None and not p.is_empty]
        if lu in ("forest", "wood"):
            forest += ps
        elif lu in ("farmland", "orchard", "vineyard"):
            farm += ps
        elif lu in ("meadow", "grassland", "grass", "village_green", "recreation_ground"):
            grass += ps
        elif lu in ("residential", "commercial", "industrial", "retail"):
            resid += ps
    U = lambda l: unary_union(l) if l else Polygon()
    return U(forest), U(farm), U(grass), U(resid)


def enc(base, over, blend, angle):
    return ((base.astype(np.uint32) & 0x1F) << 27) | ((over.astype(np.uint32) & 0x1F) << 22) | \
           ((blend.astype(np.uint32) & 0xFF) << 14) | ((angle.astype(np.uint32) & 0xF) << 10)


def main():
    plan = json.load(open("data/routes_plan.json"))
    ways = pickle.load(open("data/roads.pkl", "rb"))["ways"]
    rf = road_height_fn(samples(ways))
    forest, farm, grass, resid = landuse()
    for g in (forest, farm, grass, resid):
        shapely.prepare(g)
    rng = np.random.default_rng(3)
    for (i, j) in [tuple(r) for r in plan["regions"]]:
        H = np.load("data/dem_carved/r_%d_%d.npy" % (i, j)).astype(np.float32)
        xs = i * REG + np.arange(512) * 2.0; zs = j * REG + np.arange(512) * 2.0
        X, Z = np.meshgrid(xs, zs)
        # pente
        gy, gx = np.gradient(H, 2.0)
        slope = np.degrees(np.arctan(np.hypot(gx, gy)))
        # orthophoto : vert / sol nu
        O = np.asarray(Image.open("data/ortho/r_%d_%d.jpg" % (i, j))).astype(np.float32)
        Ob = ndi.gaussian_filter(O, (2, 2, 0))
        R_, G_, B_ = Ob[..., 0], Ob[..., 1], Ob[..., 2]
        exg = 2 * G_ - R_ - B_
        lum = Ob.mean(axis=2)
        isf = shapely.contains_xy(forest, X, Z)
        isfarm = shapely.contains_xy(farm, X, Z)
        isres = shapely.contains_xy(resid, X, Z)
        noise = ndi.gaussian_filter(rng.random(H.shape), 6)
        noise = (noise - noise.min()) / max(np.ptp(noise), 1e-6)
        base = np.where(noise > 0.5, 1, 0).astype(np.uint32)                 # gazon / prairie
        base[isres] = 0
        base[isf] = 2
        # champs (chaume, terre) en surcouche fondue : probabilité lissée, pas de bords en escalier
        soilp = ndi.gaussian_filter(((exg < 8) & (lum > 70)).astype(np.float32), 2.0)
        soilp[isf] = 0.0
        over = np.full(H.shape, 4, np.uint32)
        blend = np.clip((soilp - 0.25) / 0.5, 0, 1) * 255
        # roche sur les pentes fortes (prioritaire)
        rock = np.clip((slope - 28) / 14, 0, 1) * 255
        r_ = rock > blend
        over[r_] = 3; blend[r_] = rock[r_]
        # accotements gravillonnés le long des routes (0,8 m fondu)
        _, sd = rf(X.ravel(), Z.ravel())
        sd = sd.reshape(H.shape)
        sh = np.clip(1.0 - (sd - 0.3) / 1.2, 0, 1) * 255
        s_ = sh > 40
        over[s_] = 5; blend[s_] = np.maximum(sh[s_], 0)
        angle = (rng.random(H.shape) * 16).astype(np.uint32)
        C = enc(base, over, blend.astype(np.uint32), angle)
        H.tofile("%s/r_%d_%d.h.raw" % (OUT, i, j))
        C.astype("<u4").tofile("%s/r_%d_%d.c.raw" % (OUT, i, j))
        # teinte : couleur de la photo ramenée autour de 0,8 (garde la nuance : vert tendre, blond, sombre en forêt)
        med = np.median(O.reshape(-1, 3), axis=0)
        tint = np.clip(Ob / np.maximum(med, 1) * 0.78, 0.35, 1.0)
        tint = 0.65 * tint + 0.35 * 0.82                                       # atténuée : la texture fait le détail
        img = np.dstack([tint, np.full(H.shape, 0.5)])
        Image.fromarray((img * 255).astype(np.uint8), "RGBA").save("%s/r_%d_%d.color.png" % (OUT, i, j))
    json.dump(dict(regions=plan["regions"], size=512, spacing=2.0), open(OUT + "/index.json", "w"))
    print(len(plan["regions"]), "régions préparées")


if __name__ == "__main__":
    main()
