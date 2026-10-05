"""Carte façon GPS (style de la première version du jeu) : fond sombre d'occupation du sol réelle + relief ombré,
routes et bâtiments en vecteurs (dessinés nets à tous les zooms par le jeu).
Sorties : ../godot/assets/tex/gps_bg.png (même emprise que world/map.json, 6 m/px), ../godot/world/gps_roads.bin,
../godot/world/gps_bld.bin
 gps_roads.bin : int32 n, puis par voie : int32 classe (0 autoroute … 6 chemin), int32 nb points, float32 xmin zmin xmax
 zmax, float32 (x, z) × nb ; voies triées des chemins aux autoroutes (ordre de dessin).
 gps_bld.bin : même format sans classe (emprises simplifiées)."""
import json, os, pickle, struct
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi
from shapely.geometry import LineString
import geo

M = json.load(open("../godot/world/map.json"))
X0, Z0, RES, W, H = M["x0"], M["z0"], M["res"], M["w"], M["h"]
REG = 1024.0


def px(coords):
    return [((x - X0) / RES, (z - Z0) / RES) for x, z in coords]


def raster(polys):
    im = Image.new("L", (W, H), 0); d = ImageDraw.Draw(im)
    for g in polys:
        for p in getattr(g, "geoms", [g]):
            if p.geom_type != "Polygon" or p.area < 30:
                continue
            d.polygon(px(p.exterior.coords), fill=255)
            for r in p.interiors:
                d.polygon(px(r.coords), fill=0)
    return np.asarray(im) > 0


def main():
    # relief : DEM des environs (25 m) rééchantillonné, régions à 2 m réduites par-dessus
    nm = json.load(open("data/dem/near.json")); near = np.load("data/dem/near.npy")
    xs = X0 + (np.arange(W) + 0.5) * RES; zs = Z0 + (np.arange(H) + 0.5) * RES
    gx = (xs - nm["x0"]) / nm["step"]; gz = (zs - nm["z0"]) / nm["step"]
    hgt = ndi.map_coordinates(near, np.meshgrid(gz, gx, indexing="ij"), order=1, mode="nearest")
    hgt = ndi.gaussian_filter(hgt, 5.0)          # relief des environs (25 m) : lissé, sinon stries
    # relief fin (régions à 2 m, réduites à 6 m) par-dessus
    for f in os.listdir("data/dem_carved"):
        if not f.startswith("r_"):
            continue
        i, j = map(int, f[2:-4].split("_"))
        a = np.load("data/dem_carved/" + f).astype(np.float32)
        k = 3
        a = a[:a.shape[0] // k * k, :a.shape[1] // k * k].reshape(a.shape[0] // k, k, a.shape[1] // k, k).mean(axis=(1, 3))
        x0p = int(round((i * REG - X0) / RES)); z0p = int(round((j * REG - Z0) / RES))
        h_, w_ = a.shape
        a0, a1 = max(0, z0p), min(H, z0p + h_); b0, b1 = max(0, x0p), min(W, x0p + w_)
        if a1 > a0 and b1 > b0:
            hgt[a0:a1, b0:b1] = a[a0 - z0p:a1 - z0p, b0 - x0p:b1 - x0p]
    hgt = ndi.gaussian_filter(hgt, 1.5)
    forest = np.zeros((H, W), bool)
    for f in os.listdir("data/mnh"):
        i, j = map(int, f[2:-4].split("_"))
        a = np.load("data/mnh/" + f).astype(np.float32) / 8
        # 6 m/px : part de couvert > 5 m
        k = int(RES)
        cov = (a[: 1024 // k * k, : 1024 // k * k] > 5).reshape(1024 // k, k, 1024 // k, k).mean(axis=(1, 3))
        x0p = int(round((i * REG - X0) / RES)); z0p = int(round((j * REG - Z0) / RES))
        h_, w_ = cov.shape
        a0, a1 = max(0, z0p), min(H, z0p + h_); b0, b1 = max(0, x0p), min(W, x0p + w_)
        if a1 > a0 and b1 > b0:
            forest[a0:a1, b0:b1] |= cov[a0 - z0p:a1 - z0p, b0 - x0p:b1 - x0p] > 0.5
    from prepare_terrain import landuse, arable_fields
    fo, farm, grass, resid = landuse()
    forest |= raster([fo]) & ~np.zeros_like(forest)
    fields = raster([arable_fields()])
    from build_buildings import load
    blds = [g for _, g in load()]
    bld = raster(blds)
    urban = ndi.binary_dilation(bld, iterations=3) | raster([resid])
    forest = ndi.binary_opening(forest, iterations=1)
    # palette sombre (GPS) : prairie, champs, forêt, zone bâtie
    col = np.zeros((H, W, 3), np.float32) + np.array([34, 50, 36])
    col[fields] = (66, 60, 38)
    col[urban] = (50, 53, 58)
    col[forest] = (20, 40, 25)
    col[bld] = (78, 82, 92)
    gy, gx_ = np.gradient(hgt, RES)
    shade = np.clip(1.0 + (-gx_ * 0.6 - gy * 0.8) * 1.2, 0.55, 1.45)
    col *= shade[..., None]
    out = Image.fromarray(np.clip(col, 0, 255).astype(np.uint8))
    out.save("../godot/assets/tex/gps_bg.png")
    # routes
    CL = {"motorway": 0, "motorway_link": 0, "trunk": 1, "trunk_link": 1, "primary": 1, "primary_link": 1, "secondary": 2,
          "secondary_link": 2, "tertiary": 3, "tertiary_link": 3, "unclassified": 4, "residential": 4, "living_street": 4,
          "service": 5, "pedestrian": 5, "track": 6}
    ways = pickle.load(open("data/roads.pkl", "rb"))["ways"]
    rows = []
    for w in ways:
        ls = LineString(w["P"]).simplify(1.0)
        P = np.asarray(ls.coords, np.float32)
        if len(P) < 2:
            continue
        rows.append((CL.get(w["cls"], 4), P))
    rows.sort(key=lambda r: -r[0])
    with open("../godot/world/gps_roads.bin", "wb") as f:
        f.write(struct.pack("<i", len(rows)))
        for c, P in rows:
            f.write(struct.pack("<ii4f", c, len(P), P[:, 0].min(), P[:, 1].min(), P[:, 0].max(), P[:, 1].max()))
            f.write(P.astype("<f4").tobytes())
    with open("../godot/world/gps_bld.bin", "wb") as f:
        polys = [g.simplify(0.8) for g in blds if g.area > 25]
        f.write(struct.pack("<i", len(polys)))
        for g in polys:
            P = np.asarray(g.exterior.coords, np.float32)[:-1]
            f.write(struct.pack("<i4f", len(P), *g.bounds))
            f.write(P.astype("<f4").tobytes())
    print("fond %dx%d, %d voies, %d bâtiments" % (W, H, len(rows), len(polys)))


if __name__ == "__main__":
    main()
