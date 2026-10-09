"""Carte des ambiances sonores -> ../godot/world/ambiance.bin + ambiance.json (lues par scripts/audio.gd).

Grille de 32 m sur la zone ; pour chaque case, quatre octets (0-255) : bâti (part du sol bâti dans un rayon de
~100 m : campagne -> village -> ville), bois (forêts et bois dans ~80 m : vent dans les arbres, oiseaux), eau
(proximité d'un ruisseau ou d'une rivière, 90 m), autoroute (proximité, 500 m). Le jeu lit la case sous la caméra
(interpolée) et dose les fonds sonores.
Points sonores (ambiance.json) : ruisseaux (un point tous les 20 m, largeur, permanent ou non) pour placer le bruit
de l'eau là où elle coule ; églises (cloches qui sonnent les heures) ; troupeaux de vaches (meuglements)."""
import json, math, pickle
import numpy as np
from scipy import ndimage as ndi
from shapely.geometry import Polygon, shape
from shapely.ops import transform
from shapely.prepared import prep
import geo
from build_vegetation import Carved
from build_buildings import load as load_buildings

CELL = 32.0
OUT = "../godot/world"


def local(g):
    return transform(lambda x, y, z=None: geo.to_local(x, y), g)


def raster(geoms, x0, z0, nx, nz, res):
    """Couverture (0/1) des polygones sur une grille fine de `res` m."""
    from PIL import Image, ImageDraw
    im = Image.new("L", (nx, nz))
    d = ImageDraw.Draw(im)
    for g in geoms:
        for p in getattr(g, "geoms", [g]):
            if p.geom_type != "Polygon" or p.is_empty:
                continue
            xy = [((x - x0) / res, (z - z0) / res) for x, z in p.exterior.coords]
            if len(xy) >= 3:
                d.polygon(xy, fill=255)
    return np.asarray(im, np.float32) / 255.0


def lines_raster(lines, x0, z0, nx, nz, res):
    from PIL import Image, ImageDraw
    im = Image.new("L", (nx, nz))
    d = ImageDraw.Draw(im)
    for P in lines:
        xy = [((x - x0) / res, (z - z0) / res) for x, z in P]
        if len(xy) >= 2:
            d.line(xy, fill=255, width=1)
    return np.asarray(im) > 0


def main():
    zone = Polygon(json.load(open("data/routes_plan.json"))["zone"])
    bx0, bz0, bx1, bz1 = zone.bounds
    x0 = math.floor((bx0 - 400) / CELL) * CELL; z0 = math.floor((bz0 - 400) / CELL) * CELL
    nx = int(math.ceil((bx1 + 400 - x0) / CELL)); nz = int(math.ceil((bz1 + 400 - z0) / CELL))
    F = 4                                           # grille fine : 8 m
    res = CELL / F
    fx, fz = nx * F, nz * F
    print("grille %d × %d cases de %d m" % (nx, nz, CELL))
    # bâti : part du sol couverte dans un disque de ~100 m
    bld = raster([g for _, g in load_buildings()], x0, z0, fx, fz, res)
    bati = ndi.uniform_filter(bld, size=int(200 / res))
    bati = np.clip((bati - 0.015) / 0.16, 0, 1)
    # bois
    veg = json.load(open("data/vegetation_zones.json"))["features"]
    woods = [local(shape(f["geometry"])) for f in veg
             if (f["properties"].get("nature") or "").startswith(("Bois", "Forêt", "Peupleraie", "Lande"))]
    bois = ndi.uniform_filter(raster(woods, x0, z0, fx, fz, res), size=int(160 / res))
    bois = np.clip(bois / 0.5, 0, 1)
    # eau : distance aux cours d'eau (ruisseaux intermittents un peu moins sonores)
    tr = json.load(open("data/eau_troncons.json"))["features"]
    streams, streams_i, pts = [], [], []
    for f in tr:
        p = f["properties"]
        if p.get("fictif") or p.get("position_par_rapport_au_sol") not in ("0", 0, None):
            continue
        g = local(shape(f["geometry"]))
        for ln in getattr(g, "geoms", [g]):
            P = [(c[0], c[1]) for c in ln.coords]
            (streams if p.get("persistance") == "Permanent" else streams_i).append(P)
            L = ln.length
            wid = {"Entre 0 et 5 m": 0, "Entre 5 et 15 m": 1, "Entre 15 et 50 m": 2}.get(p.get("classe_de_largeur"), 0)
            perm = 1 if p.get("persistance") == "Permanent" else 0
            if not perm:
                continue                                  # points sonores : cours d'eau permanents seulement
            for k in range(int(L // 20) + 1):
                q = ln.interpolate(min(k * 20.0, L))
                pts.append((q.x, q.y, wid, perm))
    eau = np.zeros((fz, fx), np.float32)
    for L_, k in ((streams, 1.0), (streams_i, 0.3)):          # fossés et ruisseaux intermittents : à peine audibles
        on = lines_raster(L_, x0, z0, fx, fz, res)
        if on.any():
            dist = ndi.distance_transform_edt(~on) * res
            eau = np.maximum(eau, k * np.clip(1 - dist / 90.0, 0, 1) ** 1.5)
    # autoroute
    ways = pickle.load(open("data/roads.pkl", "rb"))["ways"]
    mw = [[(float(a), float(b)) for a, b in np.asarray(w["P"])[:, :2]] for w in ways if w["cls"] in ("motorway", "trunk")]
    don = lines_raster(mw, x0, z0, fx, fz, res)
    dm = ndi.distance_transform_edt(~don) * res if don.any() else np.full((fz, fx), 1e9)
    auto = np.clip(1 - dm / 500.0, 0, 1) ** 2
    # vers la grille de 32 m (moyenne des 4 × 4 cases fines)
    def down(a):
        return a[:nz * F, :nx * F].reshape(nz, F, nx, F).mean(axis=(1, 3))
    G = np.stack([down(bati), down(bois), down(eau), down(auto)], axis=-1)
    G = np.clip(G * 255 + 0.5, 0, 255).astype(np.uint8)
    open(OUT + "/ambiance.bin", "wb").write(G.tobytes())
    # points : ruisseaux, églises, vaches
    dem = Carved()
    P = np.array(pts) if pts else np.zeros((0, 4))
    ys = dem.h(P[:, 0], P[:, 1]) if len(P) else []
    eaux = [[round(float(x), 1), round(float(y), 1), round(float(z), 1), int(w), int(pm)] for (x, z, w, pm), y in zip(P, ys)]
    lm = json.load(open("data/osm_landmarks.json"))["elements"]
    eglises = []
    zp = prep(zone.buffer(300))
    for e in lm:
        t = e.get("tags", {})
        if t.get("amenity") != "place_of_worship" and t.get("building") not in ("church", "chapel"):
            continue
        if "center" in e:
            lon, lat = e["center"]["lon"], e["center"]["lat"]
        elif "lon" in e:
            lon, lat = e["lon"], e["lat"]
        elif "geometry" in e:
            g = e["geometry"]; lon = sum(q["lon"] for q in g) / len(g); lat = sum(q["lat"] for q in g) / len(g)
        elif "bounds" in e:
            b = e["bounds"]; lon = (b["minlon"] + b["maxlon"]) / 2; lat = (b["minlat"] + b["maxlat"]) / 2
        else:
            continue
        x, z = (float(v) for v in geo.to_local(lon, lat))
        from shapely.geometry import Point
        if zp.contains(Point(x, z)):
            eglises.append([round(x, 1), round(float(dem.h(np.array([x]), np.array([z]))[0]) + 15, 1), round(z, 1),
                            1 if t.get("building") == "church" else 0])
    import glob
    vaches = {}
    for p in glob.glob(OUT + "/animaux/a_*.bin"):
        b = open(p, "rb").read()
        n = int(np.frombuffer(b[:4], np.int32)[0])
        R = np.frombuffer(b[4:], "<f4").reshape(n, 17)
        for r in R[R[:, 0] == 0]:
            vaches[(int(r[10] // 60), int(r[12] // 60))] = [round(float(r[10]), 1), round(float(r[11]) + 1, 1), round(float(r[12]), 1)]
    json.dump(dict(x0=x0, z0=z0, cell=CELL, nx=nx, nz=nz, eaux=eaux, eglises=eglises, vaches=list(vaches.values())),
              open(OUT + "/ambiance.json", "w"), separators=(",", ":"))
    print("ruisseaux : %d points ; églises : %d ; troupeaux : %d" % (len(eaux), len(eglises), len(vaches)))
    for i, n in enumerate(("bâti", "bois", "eau", "autoroute")):
        print("  %-9s moyenne %.2f  cases > 0,5 : %d" % (n, G[..., i].mean() / 255, (G[..., i] > 127).sum()))


if __name__ == "__main__":
    main()
