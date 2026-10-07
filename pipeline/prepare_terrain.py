"""Cartes Terrain3D par région (512 × 512, 2 m) : hauteur (terrassée), contrôle (texture de base / surcouche / mélange),
couleur (teinte issue de l'orthophoto, atténuée). Sorties : ../godot/import/terrain/r_i_j.{h,c}.raw, r_i_j.color.png

Textures (ordre des assets Terrain3D) :
 0 herbe tondue (leafy_grass)   1 prairie (grass_ground)   2 sous-bois (forest_ground_04)
 3 roche (aerial_rocks_02)      4 terre labourée (brown_mud_02)   5 accotement (gravillons gris dans l'herbe rase)
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


GREEN_CODES = {"LUZ", "MLG", "JAC", "TRE", "SPH", "SPL", "BOP", "PRL", "MLC", "J5M", "J6P", "J6S", "FAG", "VRC", "NOX", "VRG",
               "PFR", "CTG", "PEP", "SNE", "BFS", "BOR"}


def arable_fields():
    """Parcelles cultivées (RPG 2024, hors prairies, luzerne, jachères, vergers) : terre / chaume."""
    from shapely.geometry import shape
    from shapely.ops import transform, unary_union
    import geo
    out = []
    for f in json.load(open("data/rpg.json"))["features"]:
        c = f["properties"].get("code_cultu") or ""
        if c.startswith("P") or c in GREEN_CODES:
            continue
        g = transform(lambda x, y, z=None: geo.to_local(x, y), shape(f["geometry"])).buffer(0)
        if not g.is_empty:
            out.append(g)
    return unary_union(out)


def clean(mask, min_px):
    """Supprime les taches (composantes < min_px) et rebouche les trous de même taille : la texture dominante gagne."""
    lab, n = ndi.label(mask)
    if n:
        sizes = ndi.sum(mask, lab, np.arange(1, n + 1))
        mask = np.r_[False, sizes >= min_px][lab]
    inv = ~mask
    lab, n = ndi.label(inv)
    if n:
        sizes = ndi.sum(inv, lab, np.arange(1, n + 1))
        mask = mask | (np.r_[False, sizes < min_px][lab] & inv)
    return mask


def main():
    plan = json.load(open("data/routes_plan.json"))
    ways = pickle.load(open("data/roads.pkl", "rb"))["ways"]
    rf = road_height_fn(samples(ways))
    forest, farm, grass, resid = landuse()
    fields = arable_fields()
    for g in (forest, farm, grass, resid, fields):
        shapely.prepare(g)
    rng = np.random.default_rng(3)
    # eau (build_water.py) : terrain creusé sous les étangs et les cours d'eau, fond vaseux
    from scipy.spatial import cKDTree
    CV = np.load("data/eau_carve.npz")["pts"] if os.path.exists("data/eau_carve.npz") else np.zeros((0, 3))
    ctree = cKDTree(CV[:, :2]) if len(CV) else None
    for (i, j) in [tuple(r) for r in plan["regions"]]:
        H = np.load("data/dem_carved/r_%d_%d.npy" % (i, j)).astype(np.float32)
        xs = i * REG + np.arange(512) * 2.0; zs = j * REG + np.arange(512) * 2.0
        X, Z = np.meshgrid(xs, zs)
        wet = np.zeros(H.shape, bool)
        if ctree is not None:
            d, k = ctree.query(np.c_[X.ravel(), Z.ravel()], distance_upper_bound=1.3)
            hit = np.isfinite(d)
            if hit.any():
                _, sd0 = rf(X.ravel()[hit], Z.ravel()[hit])
                ok = sd0 > 0.8                                  # jamais sous une chaussée
                idx = np.nonzero(hit)[0][ok]
                Hf = H.ravel().copy()
                Hf[idx] = np.minimum(Hf[idx], CV[k[idx], 2] - 0.6)
                H = Hf.reshape(H.shape)
                wet.ravel()[idx] = True
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
        isfield = shapely.contains_xy(fields, X, Z)
        # une seule herbe par type de zone (pas de plaques aléatoires) : pelouse en zone habitée, prairie ailleurs
        base = np.ones(H.shape, np.uint32)
        base[clean(isres, 500)] = 0
        base[clean(isf, 500)] = 2
        base[wet] = 2
        # terre / chaume : champs cultivés réels (RPG) + grandes zones de sol nu sur la photo ; pas de taches
        # (< 2 000 m²) : elles prennent la texture dominante autour
        bare = ndi.gaussian_filter(((exg < 8) & (lum > 70)).astype(np.float32), 2.0) > 0.5
        soil = clean((isfield | clean(bare, 1500)) & ~isf, 500)
        over = np.full(H.shape, 4, np.uint32)
        blend = np.clip(ndi.gaussian_filter(soil.astype(np.float32), 1.2) * 1.4 - 0.2, 0, 1) * 255
        # roche sur les pentes fortes (prioritaire), en masses d'au moins 1 200 m²
        rockm = clean(slope > 30, 300)
        rock = np.where(rockm, np.clip((ndi.gaussian_filter(slope, 1.5) - 26) / 12, 0.35, 1), 0) * 255
        r_ = rock > blend
        over[r_] = 3; blend[r_] = rock[r_]
        # accotements gravillonnés le long des routes (0,8 m fondu)
        _, sd = rf(X.ravel(), Z.ravel())
        sd = sd.reshape(H.shape)
        sh = np.clip(1.0 - (sd - 0.2) / 1.0, 0, 1) * 200      # étroit et fondu : l'herbe reste visible
        s_ = sh > 50
        over[s_] = 5; blend[s_] = np.maximum(sh[s_], 0)
        angle = (rng.random(H.shape) * 16).astype(np.uint32)
        C = enc(base, over, blend.astype(np.uint32), angle)
        H.tofile("%s/r_%d_%d.h.raw" % (OUT, i, j))
        C.astype("<u4").tofile("%s/r_%d_%d.c.raw" % (OUT, i, j))
        # teinte : couleur de la photo ramenée autour de 0,8 (garde la nuance : vert tendre, blond, sombre en forêt)
        med = np.median(O.reshape(-1, 3), axis=0)
        Os = ndi.gaussian_filter(O, (6, 6, 0))                               # teinte lissée (12 m) : pas de taches
        tint = np.clip(Os / np.maximum(med, 1) * 0.78, 0.35, 1.0)
        tint = 0.65 * tint + 0.35 * 0.82                                       # atténuée : la texture fait le détail
        # ombres douces précalculées : pied des bâtiments, sous les arbres (build_ground.ao_region)
        from build_ground import ao_region
        tint = tint * ao_region(i, j)[..., None]
        img = np.dstack([tint, np.full(H.shape, 0.5)])
        Image.fromarray((img * 255).astype(np.uint8), "RGBA").save("%s/r_%d_%d.color.png" % (OUT, i, j))
    json.dump(dict(regions=plan["regions"], size=512, spacing=2.0), open(OUT + "/index.json", "w"))
    print(len(plan["regions"]), "régions préparées")


if __name__ == "__main__":
    main()
