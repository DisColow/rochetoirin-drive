"""Routes : profils en long réels (relief IGN 2 m, lissés comme une vraie route, cohérents aux carrefours),
terrain terrassé sous la chaussée, maillages de chaussée (enrobé / terre), trottoirs là où OSM les indique, ponts.

Entrées : data/osm.json, data/routes_plan.json (zone jouable, régions), data/dem/r_i_j.npy, data/dem/near.npy
Sorties : data/dem_carved/r_i_j.npy (hauteurs terrassées), data/roads.pkl (axes + profils pour la suite),
          ../godot/world/roads/t_<tx>_<tz>.glb (tuiles de 256 m : chaussée, trottoirs, bordures, ponts)
Repère : x Est, y altitude, z Sud (identique au jeu Godot).
"""
import json, math, os, pickle, sys
import numpy as np
from scipy.ndimage import gaussian_filter1d
from scipy.spatial import cKDTree
from shapely.geometry import LineString, Point, Polygon, box
from shapely.ops import unary_union
from shapely.prepared import prep
import shapely
import mapbox_earcut as earcut
from geo import to_local
from glb import write_glb

OUT_ROADS = "../godot/world/roads"
CARVED = "data/dem_carved"
REG = 1024.0
TILE = 256.0
os.makedirs(OUT_ROADS, exist_ok=True); os.makedirs(CARVED, exist_ok=True)

# classe : (largeur, sigma de lissage du profil en m, revêtu)
CLS = {"motorway": (11.0, 40, True), "trunk": (7.5, 30, True), "primary": (7.0, 25, True), "secondary": (6.5, 20, True),
       "tertiary": (6.0, 15, True), "motorway_link": (5.0, 20, True), "trunk_link": (5.0, 15, True),
       "primary_link": (5.0, 12, True), "secondary_link": (5.0, 12, True), "tertiary_link": (5.0, 10, True),
       "unclassified": (5.0, 10, True), "residential": (5.0, 8, True), "living_street": (4.5, 6, True),
       "pedestrian": (5.0, 6, True), "service": (3.5, 6, True), "track": (3.0, 5, False)}
UNPAVED = {"unpaved", "gravel", "dirt", "ground", "grass", "compacted", "fine_gravel", "earth", "mud", "sand", "grass_paver"}
SW_W, CURB_H = 1.6, 0.13


# ------------------------------------------------------------------------------------------------ relief
class DEM:
    def __init__(self):
        self.reg = {}
        for f in os.listdir("data/dem"):
            if f.startswith("r_"):
                i, j = map(int, f[2:-4].split("_"))
                self.reg[(i, j)] = np.load("data/dem/" + f)
        self.near = np.load("data/dem/near.npy")
        self.nm = json.load(open("data/dem/near.json"))

    def h(self, x, z):
        x = np.atleast_1d(np.asarray(x, float)); z = np.atleast_1d(np.asarray(z, float))
        out = np.empty(x.shape)
        i = np.floor(x / REG).astype(int); j = np.floor(z / REG).astype(int)
        done = np.zeros(x.shape, bool)
        for key in set(zip(i.tolist(), j.tolist())):
            if key not in self.reg:
                continue
            m = (i == key[0]) & (j == key[1])
            A = self.reg[key]
            gx = (x[m] - key[0] * REG) / 2.0; gz = (z[m] - key[1] * REG) / 2.0
            out[m] = bilinear(A, gx, gz, self._edge(key))
            done |= m
        if (~done).any():
            m = ~done
            gx = (x[m] - self.nm["x0"]) / self.nm["step"]; gz = (z[m] - self.nm["z0"]) / self.nm["step"]
            out[m] = bilinear(self.near, gx, gz)
        return out

    def _edge(self, key):
        """Voisins pour interpoler au bord de la région (dernière colonne/ligne)."""
        i, j = key
        return (self.reg.get((i + 1, j)), self.reg.get((i, j + 1)), self.reg.get((i + 1, j + 1)))


def bilinear(A, gx, gz, edge=None):
    H, W = A.shape
    if edge is not None:
        # tableau étendu d'une colonne / ligne avec les régions voisines (sinon répétition du bord)
        E = np.empty((H + 1, W + 1), A.dtype)
        E[:H, :W] = A
        r, d, rd = edge
        E[:H, W] = r[:, 0] if r is not None else A[:, -1]
        E[H, :W] = d[0, :] if d is not None else A[-1, :]
        E[H, W] = rd[0, 0] if rd is not None else E[H - 1, W]
        A = E; H, W = A.shape
    gx = np.clip(gx, 0, W - 1.001); gz = np.clip(gz, 0, H - 1.001)
    i0 = np.floor(gx).astype(int); j0 = np.floor(gz).astype(int)
    fx = gx - i0; fz = gz - j0
    return (A[j0, i0] * (1 - fx) * (1 - fz) + A[j0, i0 + 1] * fx * (1 - fz) + A[j0 + 1, i0] * (1 - fx) * fz
            + A[j0 + 1, i0 + 1] * fx * fz)


# ------------------------------------------------------------------------------------------------ réseau
def width_of(t, cls):
    w = CLS[cls][0]
    if t.get("lanes"):
        try:
            n = int(str(t["lanes"]).split(";")[0])
            w = max(w, n * 3.3) if cls != "motorway" else n * 3.5 + 3.5
        except ValueError:
            pass
    if t.get("width"):
        try:
            w = max(2.5, min(16.0, float(str(t["width"]).replace("m", "").replace(",", ".").strip())))
        except ValueError:
            pass
    return w


def densify(P, step):
    out = [P[0]]
    for a, b in zip(P[:-1], P[1:]):
        L = float(np.hypot(*(b - a)))
        n = max(1, int(math.ceil(L / step)))
        for k in range(1, n + 1):
            out.append(a + (b - a) * k / n)
    return np.array(out)


def load_network():
    d = json.load(open("data/osm.json"))
    plan = json.load(open("data/routes_plan.json"))
    zone = Polygon(plan["zone"]).buffer(150)
    zp = prep(zone)
    N = {}
    for e in d["elements"]:
        if e["type"] == "node":
            x, z = to_local(e["lon"], e["lat"])
            N[e["id"]] = (float(x), float(z))
    ways = []
    for e in d["elements"]:
        t = e.get("tags", {})
        cls = t.get("highway")
        if e["type"] != "way" or cls not in CLS or t.get("area") == "yes" or t.get("tunnel") == "yes":
            continue
        # passage sous un bâtiment : gardé pour les bretelles (gares de péage sous leur auvent), pas dans le bourg
        if t.get("tunnel") == "building_passage" and cls not in ("motorway", "motorway_link"):
            continue
        if t.get("access") in ("private", "no") and cls == "track":
            continue
        pts = [N[n] for n in e["nodes"] if n in N]
        if len(pts) < 2:
            continue
        ls = LineString(pts)
        if not zp.intersects(ls):
            continue
        paved = CLS[cls][2]
        if t.get("surface") in UNPAVED:
            paved = False
        elif t.get("surface") in ("asphalt", "paved", "concrete", "paving_stones", "sett"):
            paved = True
        if cls == "track" and t.get("tracktype") == "grade1":
            paved = True
        sw = t.get("sidewalk") or t.get("sidewalk:both")
        sides = {"both": (1, 1), "left": (1, 0), "right": (0, 1)}.get(sw, (0, 0))
        if t.get("sidewalk:left") in ("yes", "separate") and t.get("sidewalk:left") == "yes":
            sides = (1, sides[1])
        if t.get("sidewalk:right") == "yes":
            sides = (sides[0], 1)
        ways.append(dict(id=e["id"], cls=cls, nodes=[n for n in e["nodes"] if n in N], tags=t, w=width_of(t, cls),
                         paved=paved, bridge=t.get("bridge") not in (None, "no"), layer=(int(t.get("layer", "0") or 0)
                         if str(t.get("layer", "0")).lstrip("-").isdigit() else 0) if t.get("tunnel") != "building_passage" else 0, sidewalk=sides,
                         oneway=t.get("oneway") in ("yes", "1") or t.get("junction") == "roundabout" or cls == "motorway"))
    node_tags = {e["id"]: e["tags"] for e in d["elements"] if e["type"] == "node" and e.get("tags")}
    towns = {}
    for e in d["elements"]:
        t = e.get("tags", {})
        if e["type"] == "node" and t.get("place") in ("town", "village", "city", "hamlet") and t.get("name"):
            towns[t["name"]] = np.array(N[e["id"]])
    return N, ways, zone, node_tags, towns


# ------------------------------------------------------------------------------------------------ profils
# rayon de courbure visé aux angles des tracés OSM (m), limité par la longueur des segments voisins
RADIUS = {"motorway": 300.0, "motorway_link": 60.0, "trunk": 150.0, "primary": 90.0, "secondary": 60.0,
          "tertiary": 40.0, "trunk_link": 40.0, "primary_link": 30.0, "secondary_link": 25.0, "tertiary_link": 20.0,
          "unclassified": 25.0, "residential": 12.0, "living_street": 8.0, "pedestrian": 8.0, "service": 8.0, "track": 15.0}


def round_polyline(P0, keep, R, step=3.0):
    """Remplace chaque sommet intérieur (hors carrefours) par un arc de cercle tangent aux deux segments.
    Renvoie la polyligne densifiée (pas de 3 m) et l'indice de chaque sommet OSM dans celle-ci."""
    n = len(P0)
    # points de contrôle : (point, est_un_sommet_osm_conservé)
    ctrl = [(P0[0], 0)]
    for k in range(1, n - 1):
        a, b, c = P0[k - 1], P0[k], P0[k + 1]
        u = b - a; v = c - b
        lu, lv = np.linalg.norm(u), np.linalg.norm(v)
        if keep[k] or lu < 1e-6 or lv < 1e-6:
            ctrl.append((b, k)); continue
        u /= lu; v /= lv
        cosang = float(np.clip(np.dot(u, v), -1, 1))
        th = math.acos(cosang)                       # angle de déviation
        if th < math.radians(2):
            ctrl.append((b, k)); continue
        t = R * math.tan(th / 2)
        t = min(t, 0.48 * lu, 0.48 * lv)              # le segment voisin doit garder de la place
        r = t / math.tan(th / 2)
        p1 = b - u * t; p2 = b + v * t
        # centre de l'arc
        sgn = 1.0 if (u[0] * v[1] - u[1] * v[0]) > 0 else -1.0
        nrm = np.array([-u[1], u[0]]) * sgn
        cen = p1 + nrm * r
        a1 = math.atan2(p1[1] - cen[1], p1[0] - cen[0]); a2 = math.atan2(p2[1] - cen[1], p2[0] - cen[0])
        da = (a2 - a1 + math.pi) % (2 * math.pi) - math.pi
        m = max(2, int(math.ceil(abs(da) * r / step)))
        for j in range(m + 1):
            aa = a1 + da * j / m
            ctrl.append((cen + r * np.array([math.cos(aa), math.sin(aa)]), k if j == m // 2 else -1))
    ctrl.append((P0[-1], n - 1))
    P, idx = [ctrl[0][0]], {0: 0}
    for (a, _), (b, kb) in zip(ctrl[:-1], ctrl[1:]):
        L = float(np.hypot(*(b - a))); m = max(1, int(math.ceil(L / step)))
        for j in range(1, m + 1):
            P.append(a + (b - a) * j / m)
        if kb >= 0:
            idx[kb] = len(P) - 1
    return np.array(P), [idx.get(k, 0) for k in range(n)]


def _frame(w, dem):
    P = w["P"]
    s = np.r_[0, np.cumsum(np.hypot(*np.diff(P, axis=0).T))]
    T = np.gradient(P, axis=0); T /= np.maximum(np.linalg.norm(T, axis=1, keepdims=True), 1e-9)
    Nn = np.c_[-T[:, 1], T[:, 0]]
    w.update(s=s, T=T, N=Nn)
    if dem is not None:
        hw = w["w"] / 2
        w["ground"] = (dem.h(P[:, 0], P[:, 1]) * 2 + dem.h(*(P + Nn * hw * 0.7).T) + dem.h(*(P - Nn * hw * 0.7).T)) / 4


def _shared(ways, use, rank):
    """Cohérence aux nœuds partagés : altitude de la voie la plus prioritaire (autoroute > bretelle > autres), sinon
    moyenne ; correction répartie linéairement entre nœuds, jamais sur les profils imposés (autoroutes, bretelles)."""
    for it in range(4):
        acc = {}
        for w in ways:
            if w["bridge"] and not w.get("fixed_profile"):
                continue
            for k, n in zip(w["idx"], w["nodes"]):
                if use[n] > 1:
                    acc.setdefault(n, []).append((rank(w), w["y"][k]))
        target = {}
        for n, v in acc.items():
            r = max(a for a, _ in v)
            target[n] = float(np.mean([y for a, y in v if a == r]))
        for w in ways:
            if w["bridge"] or w.get("fixed_profile"):
                continue
            ks, cs = [], []
            for k, n in zip(w["idx"], w["nodes"]):
                if n in target:
                    ks.append(k); cs.append(target[n] - w["y"][k])
            if ks:
                w["y"] = w["y"] + np.interp(np.arange(len(w["y"])), ks, cs)


def _bridges(ways):
    """Ponts des routes ordinaires : droite (légère courbe) entre les extrémités raccordées."""
    for w in ways:
        if not w["bridge"] or w.get("fixed_profile"):
            continue
        ends = []
        for k in (0, -1):
            n = w["nodes"][k]
            v = [o["y"][o["idx"][o["nodes"].index(n)]] for o in ways if o is not w and (not o["bridge"] or o.get("fixed_profile"))
                 and n in o["nodes"]]
            ends.append(float(np.mean(v)) if v else float(w["ground"][k]))
        t = w["s"] / max(w["s"][-1], 1e-6)
        w["y"] = ends[0] + (ends[1] - ends[0]) * t + 0.4 * np.sin(np.pi * t) * min(1.0, w["s"][-1] / 60)


def profiles(N, ways, dem):
    """Profil en long de chaque voie : relief moyen sous la chaussée, lissé ; altitudes communes aux nœuds partagés.
    Autoroutes et bretelles : géométrie dédiée (autoroute_geom.py)."""
    import autoroute_geom as AG
    chains = AG.align(N, ways)
    use = {}
    for w in ways:
        for n in w["nodes"]:
            use[n] = use.get(n, 0) + 1
    for w in ways:
        if "P_pre" in w:
            w["P"], w["idx"] = w.pop("P_pre"), w.pop("idx_pre")
        else:
            P0 = np.array([N[n] for n in w["nodes"]])
            keep = [k == 0 or k == len(P0) - 1 or use[n] > 1 for k, n in enumerate(w["nodes"])]
            w["P"], w["idx"] = round_polyline(P0, keep, RADIUS.get(w["cls"], 12.0))
        _frame(w, None)
    for w in ways:
        if w["cls"] == "motorway_link":
            w["P"], w["idx"] = AG.uniform(w["P"], w["idx"])
            _frame(w, None)
    links, moved = AG.ramps(ways, chains, N)
    AG.propagate(ways, moved, N)
    for w in ways:
        _frame(w, dem)
        if w.get("fixed_profile"):
            continue
        sig = CLS[w["cls"]][1] / 3.0                           # échantillons de 3 m
        w["y"] = gaussian_filter1d(w["ground"], sig, mode="nearest") if len(w["ground"]) > 3 else w["ground"].copy()
    rank = lambda w: 2 if w["cls"] == "motorway" else 1 if w["cls"] == "motorway_link" else 0
    others = [w for w in ways if w["cls"] not in ("motorway", "motorway_link")]
    _shared(others, use, rank); _bridges(others)
    X = AG.crossings(ways)
    AG.vertical(chains, dem, X)
    mw_node_y = {n: float(w["y"][k]) for w in ways if w["cls"] == "motorway" for k, n in zip(w["idx"], w["nodes"])}
    AG.link_profiles(links, X, mw_node_y)
    _shared(ways, use, rank); _bridges(ways)
    # contrôle des gabarits
    bad = [(u["cls"], l["cls"], AG.yat(u, su) - AG.yat(l, sl)) for u, su, l, sl in X if AG.yat(u, su) - AG.yat(l, sl) < AG.CLEAR - 0.3]
    print("croisements dénivelés :", len(X), "; gabarit insuffisant :", len(bad), bad[:8])
    for c in chains:
        g = np.abs(np.diff(c.y)) / np.maximum(np.diff(c.s), 1e-6)
        print("chaussée %6.0f m : pente max %.1f %%, déblai/remblai max %.1f / %.1f m" % (
            c.s[-1], g.max() * 100, (c.g - c.y)[~c.bridge_mask].max() if (~c.bridge_mask).any() else 0,
            (c.y - c.g)[~c.bridge_mask].max() if (~c.bridge_mask).any() else 0))
    return ways, chains


# ------------------------------------------------------------------------------------------------ échantillons
def samples(ways, step=1.0, accot=True):
    """Points d'axe denses (x, z, y, demi-largeur portée par le terrassement) hors ponts."""
    out = []
    for w in ways:
        if w["bridge"]:
            continue
        L = w["s"][-1]
        ss = np.arange(0, L + 0.01, step)
        x = np.interp(ss, w["s"], w["P"][:, 0]); z = np.interp(ss, w["s"], w["P"][:, 1]); y = np.interp(ss, w["s"], w["y"])
        if "hw_arr" in w:          # autoroute : largeur variable + accotement de 2,5 m (berme avant le talus)
            hw = np.interp(ss, w["s"], w["hw_arr"]) + (2.5 if accot else 0.0)
        else:
            hw = np.full(len(ss), w["w"] / 2 + (SW_W if any(w["sidewalk"]) else 0.0) + (1.5 if w["cls"] == "motorway_link" and accot else 0.0))
        out.append(np.c_[x, z, y, hw])
    return np.vstack(out)


def road_height_fn(S):
    tree = cKDTree(S[:, :2])
    hwmax = S[:, 3].max()

    def f(x, z):
        """(altitude de la route la plus proche au sens du bord, distance signée au bord)."""
        q = np.c_[np.atleast_1d(x), np.atleast_1d(z)]
        d, i = tree.query(q, k=8, distance_upper_bound=hwmax + 40)
        ok = np.isfinite(d)
        ii = np.where(ok, i, 0)
        sd = np.where(ok, d - S[ii, 3], 1e9)
        k = np.argmin(sd, axis=1)
        r = np.arange(len(q))
        return S[ii[r, k], 2], sd[r, k]
    return f


# ------------------------------------------------------------------------------------------------ terrassement
def carve(dem, rf, regions):
    for (i, j) in regions:
        A = dem.reg[(i, j)].copy()
        xs = i * REG + np.arange(512) * 2.0; zs = j * REG + np.arange(512) * 2.0
        X, Z = np.meshgrid(xs, zs)
        y, sd = rf(X.ravel(), Z.ravel())
        y = y.reshape(A.shape); sd = sd.reshape(A.shape)
        inner = 1.0
        target = y - 0.10
        # talus : pente d'environ 2/3 (déblai / remblai), au moins 9 m de raccord
        from scipy.ndimage import gaussian_filter
        dif = gaussian_filter(np.where(sd < 1e8, np.abs(A - target), 0.0), 5.0)      # lissé (10 m) : talus réguliers
        B = np.clip(1.5 * dif, 9.0, 38.0)
        t = np.clip((sd - inner) / B, 0, 1)
        t = t * t * (3 - 2 * t)
        Ac = np.where(sd < 1e8, target + (A - target) * t, A)
        np.save("%s/r_%d_%d.npy" % (CARVED, i, j), Ac.astype(np.float32))


# ------------------------------------------------------------------------------------------------ maillages
def tri_poly(poly):
    poly = shapely.geometry.polygon.orient(poly, 1.0)
    rings = [np.asarray(poly.exterior.coords)[:-1]] + [np.asarray(h.coords)[:-1] for h in poly.interiors]
    rings = [r for r in rings if len(r) >= 3]
    if not rings:
        return np.zeros((0, 2)), np.zeros(0, np.uint32)
    V = np.vstack(rings)
    ends = np.cumsum([len(r) for r in rings]).astype(np.uint32)
    return V, np.asarray(earcut.triangulate_float64(V.astype(np.float64), ends), np.uint32)


def subdivide(V, T, maxlen):
    V = [tuple(p) for p in V]; cache = {}
    def mid(a, b):
        k = (min(a, b), max(a, b))
        if k not in cache:
            V.append(((V[a][0] + V[b][0]) / 2, (V[a][1] + V[b][1]) / 2)); cache[k] = len(V) - 1
        return cache[k]
    stack = [tuple(T[k:k + 3]) for k in range(0, len(T), 3)]; out = []
    while stack:
        a, b, c = stack.pop()
        la = math.dist(V[a], V[b]); lb = math.dist(V[b], V[c]); lc = math.dist(V[c], V[a]); m = max(la, lb, lc)
        if m <= maxlen:
            out += [a, b, c]; continue
        if m == la:
            d = mid(a, b); stack += [(a, d, c), (d, b, c)]
        elif m == lb:
            d = mid(b, c); stack += [(a, b, d), (a, d, c)]
        else:
            d = mid(c, a); stack += [(a, b, d), (d, b, c)]
    return np.array(V), np.array(out, np.uint32)


class MeshB:
    def __init__(self):
        self.p, self.n, self.uv, self.i = [], [], [], []
        self.nv = 0

    def add(self, P, Nrm, UV, I):
        self.p.append(np.asarray(P, np.float32)); self.n.append(np.asarray(Nrm, np.float32))
        self.uv.append(np.asarray(UV, np.float32)); self.i.append(np.asarray(I, np.uint32) + self.nv)
        self.nv += len(P)

    def empty(self):
        return self.nv == 0

    def arrays(self):
        return np.vstack(self.p), np.vstack(self.n), np.vstack(self.uv), np.concatenate(self.i)


def smooth_normals(P, I):
    Nn = np.zeros_like(P)
    a, b, c = P[I[0::3]], P[I[1::3]], P[I[2::3]]
    fn = np.cross(b - a, c - a)
    for k in range(3):
        np.add.at(Nn, I[k::3], fn)
    Nn /= np.maximum(np.linalg.norm(Nn, axis=1, keepdims=True), 1e-9)
    Nn[Nn[:, 1] < 0] *= -1
    return Nn


def surface(mb, poly, hfun, lift, maxlen=2.5):
    """Triangulation de qualité (Shewchuk) : angles >= 25°, aire <= maxlen² / 1,5 ; suit le profil de la route."""
    import triangle as tr
    for part in getattr(poly, "geoms", [poly]):
        if part.geom_type != "Polygon" or part.area < 0.5:
            continue
        part = shapely.segmentize(shapely.set_precision(part, 0.005), maxlen)
        if part.is_empty or part.geom_type != "Polygon":
            continue
        # sommets dédoublonnés (Triangle plante sur des sommets confondus ou des segments nuls)
        V, Sg, holes, vid = [], [], [], {}
        for ring in [part.exterior] + list(part.interiors):
            C = np.asarray(ring.coords)[:-1]
            if len(C) < 3:
                continue
            ids = []
            for p in C:
                key = (round(p[0] * 200), round(p[1] * 200))
                if key not in vid:
                    vid[key] = len(V); V.append(p.tolist())
                if not ids or ids[-1] != vid[key]:
                    ids.append(vid[key])
            if len(ids) > 1 and ids[0] == ids[-1]:
                ids.pop()
            if len(ids) < 3:
                continue
            Sg.extend([(ids[k], ids[(k + 1) % len(ids)]) for k in range(len(ids))])
        if len(V) < 3 or len(Sg) < 3:
            continue
        for h in part.interiors:
            hp = Polygon(h)
            if hp.area > 0.01:
                holes.append(hp.representative_point().coords[0])
        A = dict(vertices=np.array(V), segments=np.array(Sg))
        if holes:
            A["holes"] = np.array(holes)
        try:
            R = tr.triangulate(A, "pq25a%.2fQ" % (maxlen * maxlen / 1.5))
        except Exception:
            continue
        if "triangles" not in R:
            continue
        V2 = R["vertices"]; T = R["triangles"].astype(np.uint32).ravel()
        y = hfun(V2[:, 0], V2[:, 1]) + lift
        P = np.c_[V2[:, 0], y, V2[:, 1]]
        a, b, c = P[T[0::3]], P[T[1::3]], P[T[2::3]]
        up = np.cross(b - a, c - a)[:, 1] < 0
        T = T.reshape(-1, 3); T[up] = T[up][:, ::-1]; T = T.ravel()
        mb.add(P, smooth_normals(P, T), V2, T)


def walls(mb, ring_pts, y_top, y_bot, uvs=1.0):
    """Faces verticales le long d'une polyligne (bordures, rives de pont)."""
    R = np.asarray(ring_pts)
    for k in range(len(R) - 1):
        a, b = R[k], R[k + 1]
        L = float(np.hypot(*(b - a)))
        if L < 1e-3:
            continue
        n = np.array([b[1] - a[1], 0, -(b[0] - a[0])]) / L
        P = [(a[0], y_bot[k], a[1]), (b[0], y_bot[k + 1], b[1]), (b[0], y_top[k + 1], b[1]), (a[0], y_top[k], a[1])]
        mb.add(P, [n] * 4, [(0, 0), (L * uvs, 0), (L * uvs, 1), (0, 1)], [0, 1, 2, 0, 2, 3])


def main():
    import shutil
    shutil.rmtree(OUT_ROADS, ignore_errors=True); os.makedirs(OUT_ROADS)
    dem = DEM()
    N, ways, zone, node_tags, towns = load_network()
    print(len(ways), "voies dans la zone")
    ways, chains = profiles(N, ways, dem)
    import autoroute_geom as AG
    plazas = AG.toll_plazas(ways)
    ways += plazas
    print("gares de péage :", [(p["tags"]["name"], p["tags"]["toll"]) for p in plazas])
    S = samples(ways)
    # parkings : emprises nivelées (points de terrassement en plus de ceux des routes), places, marquage
    import parking
    PK = parking.Parkings(ways, zone)
    Sp = PK.samples(dem, road_height_fn(S))
    print("parkings :", len(PK.lots), "emprises,", len(Sp), "points de nivellement")
    S = np.vstack([S, Sp])
    rf = road_height_fn(S)
    regions = [tuple(r) for r in json.load(open("data/routes_plan.json"))["regions"]]
    carve(dem, rf, regions)
    print("terrassement :", len(regions), "régions")
    import autoroute_geom as AG
    pickle.dump(dict(ways=[{k: v for k, v in w.items() if k not in ("chain", "att_c")} for w in ways],
                     chains=AG.export(chains)), open("data/roads.pkl", "wb"))

    # emprises
    paved, unpaved, walk, decks, paved_mw = [], [], [], [], []
    for w in ways:
        ls = LineString(w["P"])
        if "hw_arr" in w:
            g = _band(w, -w["hw_arr"], w["hw_arr"])
            if w["bridge"]:
                decks.append((w, g)); continue
            paved.append(g); paved_mw.append(g)
            # terre-plein central étroit : revêtu jusqu'à l'axe (séparateur en béton posé par build_autoroute.py)
            for g2 in median_strips(w):
                paved.append(g2); paved_mw.append(g2)
            continue
        g = ls.buffer(w["w"] / 2, cap_style="flat" if not w["bridge"] else "flat", join_style="round", quad_segs=4)
        if w["bridge"]:
            decks.append((w, g)); continue
        (paved if w["paved"] else unpaved).append(ls.buffer(w["w"] / 2, cap_style="round", join_style="round", quad_segs=4))
        if w["cls"] == "motorway_link":
            paved_mw.append(paved[-1])
        for side, sg in ((0, 1), (1, -1)):
            if w["sidewalk"][side]:
                off = ls.offset_curve(sg * (w["w"] / 2 + SW_W / 2), join_style="round")
                if not off.is_empty:
                    walk.append(off.buffer(SW_W / 2, cap_style="flat", join_style="round", quad_segs=3))
    pk_paved, pk_unpaved = PK.surfaces()
    paved += pk_paved; unpaved += pk_unpaved
    Zc = zone.buffer(50)
    paved = [g.intersection(Zc) for g in paved]; unpaved = [g.intersection(Zc) for g in unpaved]
    walk = [g.intersection(Zc) for g in walk]
    decks = [(w, g.intersection(Zc)) for w, g in decks if g.intersects(Zc)]
    paved_u = unary_union(paved)
    mw_u = unary_union([g.intersection(Zc) for g in paved_mw]) if paved_mw else Polygon()
    other_u = paved_u.difference(mw_u)
    unpaved_u = unary_union(unpaved).difference(paved_u) if unpaved else Polygon()
    walk_u = unary_union(walk).difference(paved_u).difference(unpaved_u.buffer(0.01)) if walk else Polygon()
    shapely.prepare(paved_u); shapely.prepare(walk_u)
    hroad = lambda x, z: rf(x, z)[0]
    # marquages et panneaux (données OSM réelles)
    import furniture, signs_atlas
    use = {}
    for w in ways:
        for n in w["nodes"]:
            use[n] = use.get(n, 0) + 1
    city = [t.get("name") for t in node_tags.values() if t.get("traffic_sign") == "city_limit" and t.get("name")]
    city_names = signs_atlas.build(city)
    det = furniture.Out(TILE)
    ways_m = [w for w in ways if not w["bridge"]]
    import calming
    calm = calming.Calming(ways, json.load(open("data/osm_calming.json")))
    hroad_b = lambda x, z: hroad(x, z) + calm.h(x, z)
    bumps = furniture.Out(TILE)
    print("ralentisseurs :", calm.build(bumps, det, hroad))
    nc, ns = furniture.markings(det, [w for w in ways_m if w["cls"] not in ("motorway", "motorway_link")], use, hroad_b,
                                node_tags, {"uncontrolled", "marked", "zebra", "traffic_signals", None})
    import autoroute_geom as AG
    print("autoroutes : %d zébras" % AG.markings(det, chains, ways, use, hroad_b))
    AG.plaza_markings(det, [w for w in ways if w.get("plaza")], hroad_b)
    st = furniture.signs(det, ways, use, hroad_b, node_tags, city_names, towns)
    print("parkings : %d places, %d traits" % (PK.build(), PK.markings(det, hroad_b)))
    PK.save()
    print("marquages : %d passages piétons, %d lignes d'arrêt ; panneaux :" % (nc, ns), st)
    tiles = set()
    mnx, mnz, mxx, mxz = unary_union([paved_u, unpaved_u]).bounds
    for tx in range(int(mnx // TILE), int(mxx // TILE) + 1):
        for tz in range(int(mnz // TILE), int(mxz // TILE) + 1):
            if Zc.intersects(box(tx * TILE, tz * TILE, (tx + 1) * TILE, (tz + 1) * TILE)):
                tiles.add((tx, tz))
    ntri = 0
    for tx, tz in sorted(tiles):
        bb = (tx * TILE, tz * TILE, (tx + 1) * TILE, (tz + 1) * TILE)
        groups = {}
        for name, geom, lift in (("asphalt", other_u, 0.0), ("asphalt_mw", mw_u, 0.0), ("dirt", unpaved_u, 0.0),
                                 ("sidewalk", walk_u, CURB_H)):
            if geom.is_empty:
                continue
            g = shapely.clip_by_rect(geom, *bb)
            if g.is_empty:
                continue
            mb = MeshB()
            surface(mb, g, hroad, lift)
            if name == "sidewalk":
                # bordure : face verticale côté chaussée
                for part in getattr(g, "geoms", [g]):
                    if part.geom_type != "Polygon":
                        continue
                    for ring in [part.exterior] + list(part.interiors):
                        C = np.asarray(ring.coords)
                        C = densify(C, 2.0)
                        y = hroad(C[:, 0], C[:, 1])
                        walls(mb, C, y + CURB_H, y - 0.15)
            if not mb.empty():
                groups[name] = mb
        # ponts de la tuile
        mbd = MeshB(); mbp = MeshB(); mbdm = MeshB()
        for w, g in decks:
            if not g.intersects(box(*bb)):
                continue
            mid = w["P"][len(w["P"]) // 2]
            if not (bb[0] <= mid[0] < bb[2] and bb[1] <= mid[1] < bb[3]):
                continue
            yb = lambda x, z, w=w: _yb(w, x, z)
            surface(mbdm if w["cls"] in ("motorway", "motorway_link") else mbd, g, yb, 0.0, maxlen=3.0)
            for sg in (1, -1):
                E = w["P"] + w["N"] * sg * (w["hw_arr"][:, None] if "hw_arr" in w else w["w"] / 2)
                y = w["y"]
                walls(mbp, E, y + 1.0, y - 0.9)                     # parapets et rive du tablier
                walls(mbp, E[::-1], (y + 1.0)[::-1], (y - 0.9)[::-1])
            # piles tous les 25 m si le tablier est haut
            for k in range(0, len(w["P"]), 8):
                gnd = float(dem.h(*w["P"][k])[0])
                if w["y"][k] - gnd > 3 and rf(*w["P"][k])[1][0] > 1.0:       # jamais sur une chaussée
                    c = w["P"][k]; r = 0.6
                    sq = np.array([[c[0] - r, c[1] - r], [c[0] + r, c[1] - r], [c[0] + r, c[1] + r], [c[0] - r, c[1] + r], [c[0] - r, c[1] - r]])
                    walls(mbp, sq, np.full(5, w["y"][k] - 0.9), np.full(5, gnd - 1.0))
        if not mbd.empty():
            groups["asphalt_bridge"] = mbd
        if not mbdm.empty():
            groups["asphalt_mw_bridge"] = mbdm
        if not mbp.empty():
            groups["concrete"] = mbp
        dprims = det.prims((tx, tz))
        bprims = bumps.prims((tx, tz))
        if groups or dprims or bprims:
            prims = list(bprims)
            for name, mb in groups.items():
                P, Nn, UV, I = mb.arrays()
                prims.append((name, P, Nn, UV, I)); ntri += len(I) // 3
            # le relief des ralentisseurs rejoint l'enrobé de même nom (une seule surface par matériau)
            merged = {}
            for name, P, Nn, UV, I in prims:
                if name in merged:
                    m = merged[name]; I = I + len(m[0])
                    merged[name] = (np.vstack([m[0], P]), np.vstack([m[1], Nn]), np.vstack([m[2], UV]), np.concatenate([m[3], I]))
                else:
                    merged[name] = (P, Nn, UV, I)
            prims = [(k,) + v for k, v in merged.items()]
            G = {}
            if prims:
                G["tile"] = prims
            if dprims:
                G["detail"] = dprims
            write_glb("%s/t_%d_%d.glb" % (OUT_ROADS, tx, tz), G, fix_winding=True)
    print(len(tiles), "tuiles de routes,", ntri, "triangles")


def median_strips(w):
    """Terre-plein central étroit (< 6,5 m) d'une chaussée d'autoroute : polygones revêtus de son bord gauche à l'axe
    du terre-plein."""
    tw = w.get("twin_arr")
    out = []
    if tw is None:
        return out
    m = np.isfinite(tw) & (tw - 2 * w["hw_arr"] < 6.5) & (tw / 2 > w["hw_arr"] + 0.2)
    k = 0
    while k < len(m):
        if not m[k]:
            k += 1; continue
        j = k
        while j + 1 < len(m) and m[j + 1]:
            j += 1
        if j - k >= 2:
            sl = slice(k, j + 1)
            out.append(_band(w, -tw[sl] / 2 - 0.05, -w["hw_arr"][sl] + 0.05, sl))
        k = j + 1
    return out


def _band(w, lo, hi, sl=slice(None)):
    """Polygone entre les décalages lo et hi (à droite, tableaux alignés sur la polyligne de w)."""
    P = w["P"][sl]; Nn = w["N"][sl]
    A = P + Nn * np.asarray(lo)[:, None]; B = P + Nn * np.asarray(hi)[:, None]
    g = Polygon(np.vstack([A, B[::-1]]))
    return g if g.is_valid else g.buffer(0)


def _yb(w, x, z):
    ls = LineString(w["P"])
    s = np.array([ls.project(Point(a, b)) for a, b in zip(np.atleast_1d(x), np.atleast_1d(z))])
    return np.interp(s, w["s"], w["y"])


if __name__ == "__main__":
    main()
