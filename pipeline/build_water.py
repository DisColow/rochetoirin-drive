"""Eau : étangs, retenues, bassins, mares (surfaces BD TOPO) et rivières / ruisseaux permanents (tronçons BD TOPO).
 - plans d'eau : surface plane au niveau mesuré par le LiDAR (centile bas des altitudes intérieures) ;
 - cours d'eau : ruban (largeur selon la classe BD TOPO) dont l'altitude ne remonte jamais dans le sens du courant
   (minimum local de part et d'autre du tracé, puis minimum cumulé) ; rivières larges (surfaces « écoulement naturel »,
   canaux) : altitude prise sur le tracé du cours d'eau le plus proche ;
 - rien sur la route : l'eau s'arrête au bord des chaussées (sauf sous les ponts) ;
 - data/eau_carve.npz : points (x, z, altitude de l'eau) sur toute la surface en eau, pour creuser le terrain dessous
   (prepare_terrain.py).
Sortie : ../godot/world/water/w_tx_tz.glb (primitive « water » ; UV2 = sens du courant, nul pour les plans d'eau)."""
import json, math, os, pickle, shutil
import numpy as np
import shapely
from shapely.geometry import shape, LineString, Polygon, Point, box
from shapely.ops import transform, unary_union
from scipy.spatial import cKDTree
from scipy import ndimage as ndi
import geo
from build_vegetation import Carved
from build_buildings import tri_polygon
from build_fences import Local, lines_of, polys_of
from glb import write_glb

OUT = "../godot/world/water"
TILE = 256.0
WIDTH = {"Entre 0 et 5 m": 1.6, "Entre 5 et 15 m": 7.0, "Entre 15 et 50 m": 16.0}
SKIP_SURF = ("Marais", "Réservoir-bassin d'orage")


def local(g):
    return transform(lambda x, y, z=None: geo.to_local(x, y), g)


def low(dem, x, z, r=2.5):
    """Altitude minimale autour du point (fond du lit, même si le tracé est décalé de quelques mètres)."""
    best = dem.h(np.atleast_1d(x), np.atleast_1d(z))
    for dx, dz in ((r, 0), (-r, 0), (0, r), (0, -r), (r * 0.7, r * 0.7), (-r * 0.7, -r * 0.7), (r * 0.7, -r * 0.7), (-r * 0.7, r * 0.7)):
        best = np.minimum(best, dem.h(np.atleast_1d(x) + dx, np.atleast_1d(z) + dz))
    return best


def main():
    shutil.rmtree(OUT, ignore_errors=True); os.makedirs(OUT)
    plan = json.load(open("data/routes_plan.json"))
    zone = Polygon(plan["zone"]).buffer(300)
    dem = Carved()
    ways = pickle.load(open("data/roads.pkl", "rb"))["ways"]
    ROAD = Local([LineString(w["P"]).buffer(w["w"] / 2 + 0.3) for w in ways if len(w["P"]) > 1 and not w["bridge"]])
    tiles = {}
    carve = []                                    # (x, z, y)

    def tile_of(x, z):
        k = (int(math.floor(x / TILE)), int(math.floor(z / TILE)))
        if k not in tiles:
            tiles[k] = dict(P=[], N=[], UV=[], UV2=[], I=[], n=0)
        return tiles[k]

    def add_tris(V, Y, T, flow=None):
        """Triangles (sommets 2D V, altitudes Y, indices T) répartis par tuile selon leur centre."""
        T = np.asarray(T).reshape(-1, 3)
        C = V[T].mean(1)
        for k in set(map(tuple, np.floor(C / TILE).astype(int))):
            sel = T[(np.floor(C / TILE).astype(int) == k).all(1)]
            used, inv = np.unique(sel.ravel(), return_inverse=True)
            t = tile_of((k[0] + 0.5) * TILE, (k[1] + 0.5) * TILE)
            P = np.c_[V[used, 0], Y[used], V[used, 1]]
            t["P"].append(P); t["N"].append(np.tile([0, 1, 0], (len(used), 1)))
            t["UV"].append(V[used] * 0.1)
            t["UV2"].append(flow[used] if flow is not None else np.zeros((len(used), 2)))
            # face vers le haut : sens horaire vu de dessus pour Godot (le glTF est retourné à l'import : CCW)
            I = inv.reshape(-1, 3) + t["n"]
            a, b, c = P[inv.reshape(-1, 3)[:, 0]], P[inv.reshape(-1, 3)[:, 1]], P[inv.reshape(-1, 3)[:, 2]]
            up = np.cross(b - a, c - a)[:, 1] < 0
            I[up] = I[up][:, ::-1]
            t["I"].append(I.ravel()); t["n"] += len(used)

    # ---- cours d'eau permanents : échantillons (x, z, y) le long du tracé, sens du courant
    streams = []
    for f in json.load(open("data/eau_troncons.json"))["features"]:
        p = f["properties"]
        if p.get("persistance") != "Permanent" or p.get("position_par_rapport_au_sol") != "0" or p.get("fictif"):
            continue
        g = local(shape(f["geometry"]))
        for l in lines_of(g):
            if not l.intersects(zone) or l.length < 5:
                continue
            C = np.asarray(shapely.segmentize(l, 2.0).coords)[:, :2]
            if p.get("sens_de_l_ecoulement") == "Sens inverse":
                C = C[::-1]
            y = low(dem, C[:, 0], C[:, 1])
            y = ndi.median_filter(y, size=5, mode="nearest")
            y = np.minimum.accumulate(y)                     # l'eau ne remonte jamais
            streams.append((C, y - 0.25, WIDTH.get(p.get("classe_de_largeur"), 1.8)))
    SP = np.vstack([np.c_[C, y] for C, y, _ in streams]) if streams else np.zeros((0, 3))
    stree = cKDTree(SP[:, :2]) if len(SP) else None
    print(len(streams), "tronçons de cours d'eau permanents")

    # ---- surfaces en eau
    surfaces = []
    nsurf = 0
    for f in json.load(open("data/eau_surfaces.json"))["features"]:
        p = f["properties"]
        if p.get("nature") in SKIP_SURF or p.get("position_par_rapport_au_sol") != "0":
            continue
        g = local(shape(f["geometry"])).buffer(0)
        if not g.intersects(zone):
            continue
        flowing = p.get("nature") in ("Ecoulement naturel", "Canal")
        for poly in polys_of(ROAD.cut(g)):
            if poly.area < 12:
                continue
            surfaces.append(poly)
            poly = shapely.segmentize(poly, 3.0)
            try:
                V, T = tri_polygon(poly) if not flowing or poly.area < 200 else _tri_fine(poly)
            except Exception:
                continue
            V = np.asarray(V, np.float64)
            if flowing and stree is not None:
                d, i = stree.query(V)
                Y = np.where(d < 40, SP[i, 2], low(dem, V[:, 0], V[:, 1]) - 0.2)
                fl = None
            else:
                # niveau : centile bas des altitudes intérieures (le LiDAR mesure la surface de l'eau)
                minx, minz, maxx, maxz = poly.bounds
                gx, gz = np.meshgrid(np.arange(minx, maxx, 2.0), np.arange(minz, maxz, 2.0))
                ins = shapely.contains_xy(poly, gx.ravel(), gz.ravel())
                hs = dem.h(gx.ravel()[ins], gz.ravel()[ins]) if ins.any() else dem.h(V[:, 0], V[:, 1])
                lev = float(np.percentile(hs, 20)) - 0.05
                Y = np.full(len(V), lev)
                fl = None
            add_tris(V, Y, T, fl)
            # points de creusement (grille de 1,5 m dans la surface)
            minx, minz, maxx, maxz = poly.bounds
            gx, gz = np.meshgrid(np.arange(minx, maxx + 1.5, 1.5), np.arange(minz, maxz + 1.5, 1.5))
            ins = shapely.contains_xy(poly.buffer(0.8), gx.ravel(), gz.ravel())
            if ins.any():
                px, pz = gx.ravel()[ins], gz.ravel()[ins]
                kd = cKDTree(V); _, j = kd.query(np.c_[px, pz])
                carve.append(np.c_[px, pz, Y[j]])
            nsurf += 1
    surf_u = unary_union(surfaces) if surfaces else Polygon()
    SURF = Local(surfaces)
    print(nsurf, "surfaces en eau")

    # ---- rubans des cours d'eau (hors des surfaces déjà en eau et hors des routes)
    nrib = 0
    for C, y, w in streams:
        l = LineString(C)
        cut = SURF.cut(l, 0.0)
        cut = ROAD.cut(cut, w / 2)
        for part in lines_of(cut):
            if part.length < 3:
                continue
            Q = np.asarray(shapely.segmentize(part, 2.0).coords)[:, :2]
            # altitude et sens repris du tracé complet
            kd = cKDTree(C); _, j = kd.query(Q)
            yq = y[j]
            if len(Q) < 2:
                continue
            d = np.gradient(Q, axis=0); d /= np.maximum(np.linalg.norm(d, axis=1, keepdims=True), 1e-6)
            nrm = np.c_[-d[:, 1], d[:, 0]]
            ww = w * (0.85 + 0.3 * (0.5 + 0.5 * np.sin(np.arange(len(Q)) * 0.37)))
            L = Q + nrm * (ww / 2)[:, None]; R = Q - nrm * (ww / 2)[:, None]
            V = np.vstack([L, R]); Y = np.r_[yq, yq]
            n = len(Q)
            T = []
            for i in range(n - 1):
                T += [i, i + 1, n + i, i + 1, n + i + 1, n + i]
            add_tris(V, Y, np.array(T), np.vstack([d, d]))
            # creusement : axe et bords
            for t in np.linspace(-0.5, 0.5, 5):
                P = Q + nrm * (ww * t * 1.3)[:, None]
                carve.append(np.c_[P, yq])
            nrib += 1
    print(nrib, "rubans de cours d'eau")

    for (tx, tz), t in tiles.items():
        if not t["n"]:
            continue
        prim = ("water", np.vstack(t["P"]), np.vstack(t["N"]), np.vstack(t["UV"]), np.concatenate(t["I"]).astype(np.uint32),
                None, np.vstack(t["UV2"]))
        write_glb("%s/w_%d_%d.glb" % (OUT, tx, tz), {"eau": [prim]})
    CV = np.vstack(carve) if carve else np.zeros((0, 3))
    np.savez_compressed("data/eau_carve.npz", pts=CV.astype(np.float32))
    print(len(tiles), "tuiles ;", len(CV), "points de creusement")


def _tri_fine(poly):
    """Triangulation avec points intérieurs (rivières larges en pente)."""
    import triangle as tr
    V, Sg = [], []
    for ring in [poly.exterior] + list(poly.interiors):
        C = np.asarray(ring.coords)[:-1]
        b = len(V); V.extend(C.tolist()); Sg.extend([(b + k, b + (k + 1) % len(C)) for k in range(len(C))])
    A = dict(vertices=np.array(V), segments=np.array(Sg))
    holes = [Polygon(h).representative_point().coords[0] for h in poly.interiors]
    if holes:
        A["holes"] = np.array(holes)
    R = tr.triangulate(A, "pqa40Q")
    return R["vertices"], R["triangles"].ravel()


if __name__ == "__main__":
    main()
