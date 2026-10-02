"""Transforme les données brutes (OSM + IGN) en fichiers prêts pour le jeu.

Entrées  : data/osm.json, data/pois.json, data/elev_inner.npy, data/elev_outer.npy
Sorties  : app/src/main/assets/
    terrain.bin  grille fine (10 m) déjà « terrassée » sous les routes
    far.bin      grille grossière (60 m) pour l'horizon
    roads.bin    maillages des routes, découpés en tuiles de 320 m
    map.json     graphe routier (GPS, minimap, noms de rues), ponts, lieux
"""
import json, math, os, struct, unicodedata
import numpy as np
from scipy.ndimage import gaussian_filter, map_coordinates
from geo import INNER, OUTER, grid_shape, to_local

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "data")
ASSETS = os.path.join(HERE, "..", "app", "src", "main", "assets")

# --- Zone fine recadrée pour s'aligner exactement sur la grille de 60 m -------------
STEP = 10.0
FAR_STEP = 60.0
X0, X1 = -2300.0, 2260.0
Z0, Z1 = -3100.0, 3080.0
CHUNK_CELLS = 32
CHUNK = CHUNK_CELLS * STEP
ROAD_MARGIN = 40.0          # les routes s'arrêtent avant le bord de la carte

# classe -> (largeur par défaut, vitesse par défaut, style de rendu, priorité d'affichage)
# styles : 0 autoroute, 1 nationale/départementale principale, 2 secondaire, 3 tertiaire,
#          4 route communale, 5 desserte, 6 chemin de terre, 8 béton (ponts)
CLASSES = {
    "motorway":       (10.5, 130, 0, 9),
    "trunk":          (8.0, 110, 1, 8),
    "primary":        (7.0, 80, 1, 8),
    "secondary":      (6.5, 80, 2, 7),
    "tertiary":       (6.0, 80, 3, 6),
    "motorway_link":  (5.0, 70, 0, 5),
    "trunk_link":     (5.0, 70, 1, 5),
    "primary_link":   (5.0, 50, 1, 5),
    "secondary_link": (5.0, 50, 2, 5),
    "tertiary_link":  (5.0, 50, 3, 5),
    "unclassified":   (5.0, 80, 4, 4),
    "residential":    (5.0, 50, 4, 4),
    "living_street":  (4.5, 20, 4, 4),
    "service":        (3.5, 30, 5, 3),
    "track":          (3.0, 30, 6, 1),
}
STYLE_CONCRETE = 8
DISC_FLAG = 10.0   # style + 10 : asphalte sans marquage (carrefours)


def load_inner():
    H = np.load(os.path.join(DATA, "elev_inner.npy")).astype(np.float64)
    i0 = int(round((X0 - INNER["xmin"]) / STEP)); i1 = int(round((X1 - INNER["xmin"]) / STEP)) + 1
    j0 = int(round((Z0 - INNER["zmin"]) / STEP)); j1 = int(round((Z1 - INNER["zmin"]) / STEP)) + 1
    return H[j0:j1, i0:i1].copy()


def load_outer():
    return np.load(os.path.join(DATA, "elev_outer.npy")).astype(np.float64)


class Grid:
    """Échantillonnage d'une grille avec EXACTEMENT la triangulation utilisée par le jeu
    (diagonale v00-v11)."""

    def __init__(self, H, x0, z0, step):
        self.H, self.x0, self.z0, self.step = H, x0, z0, step
        self.nz, self.nx = H.shape

    def height(self, x, z):
        x = np.asarray(x, dtype=np.float64); z = np.asarray(z, dtype=np.float64)
        gx = np.clip((x - self.x0) / self.step, 0, self.nx - 1.000001)
        gz = np.clip((z - self.z0) / self.step, 0, self.nz - 1.000001)
        i = np.floor(gx).astype(int); j = np.floor(gz).astype(int)
        fx = gx - i; fz = gz - j
        H = self.H
        h00 = H[j, i]; h10 = H[j, i + 1]; h01 = H[j + 1, i]; h11 = H[j + 1, i + 1]
        upper = fz >= fx
        a = h00 + (h11 - h01) * fx + (h01 - h00) * fz
        b = h00 + (h10 - h00) * fx + (h11 - h10) * fz
        return np.where(upper, a, b)

    def smooth(self, x, z):
        """Bilinéaire (pour des champs lissés)."""
        gx = (np.asarray(x) - self.x0) / self.step
        gz = (np.asarray(z) - self.z0) / self.step
        return map_coordinates(self.H, [np.atleast_1d(gz), np.atleast_1d(gx)], order=1, mode="nearest")

    def normal(self, x, z):
        e = self.step
        hx = (self.height(x + e, z) - self.height(x - e, z)) / (2 * e)
        hz = (self.height(x, z + e) - self.height(x, z - e)) / (2 * e)
        n = np.stack([-hx, np.ones_like(hx), -hz], axis=-1)
        return n / np.linalg.norm(n, axis=-1, keepdims=True)


# ---------------------------------------------------------------------------------
# Lecture OSM
# ---------------------------------------------------------------------------------
def parse_osm():
    d = json.load(open(os.path.join(DATA, "osm.json")))
    nodes = {}
    for e in d["elements"]:
        if e["type"] == "node":
            x, z = to_local(e["lon"], e["lat"])
            nodes[e["id"]] = (float(x), float(z))
    ways = []
    for e in d["elements"]:
        if e["type"] != "way":
            continue
        t = e.get("tags", {})
        hw = t.get("highway")
        if hw not in CLASSES or t.get("tunnel") in ("yes", "building_passage"):
            continue
        if t.get("area") == "yes":
            continue
        width, speed, style, prio = CLASSES[hw]
        if t.get("lanes"):
            try:
                lanes = int(t["lanes"].split(";")[0])
                if hw == "motorway":
                    width = lanes * 3.5 + 3.5
                elif lanes >= 2:
                    width = max(width, lanes * 3.25)
                elif lanes == 1 and hw not in ("track", "service"):
                    width = min(width, 4.0)
            except ValueError:
                pass
        if t.get("width"):
            try:
                width = max(2.5, min(14.0, float(t["width"].replace("m", "").strip())))
            except ValueError:
                pass
        ms = t.get("maxspeed", "")
        if ms.isdigit():
            speed = int(ms)
        elif hw == "residential" or hw == "living_street":
            speed = 50
        oneway = t.get("oneway") in ("yes", "1") or hw in ("motorway", "motorway_link") or t.get("junction") == "roundabout"
        name = t.get("name") or (t.get("ref") and ("Autoroute " + t["ref"].replace(" ", "") if hw == "motorway" else t["ref"])) or ""
        ways.append(dict(id=e["id"], cls=hw, width=width, speed=speed, style=style, prio=prio,
                         oneway=oneway, name=name, bridge=t.get("bridge") not in (None, "no"),
                         nodes=[n for n in e["nodes"] if n in nodes], tags=t))
    # voies ferrées (ligne Lyon - Grenoble)
    p = os.path.join(DATA, "osm_street.json")
    if os.path.exists(p):
        ds = json.load(open(p))
        for e in ds["elements"]:
            if e["type"] == "node" and e["id"] not in nodes:
                x, z = to_local(e["lon"], e["lat"])
                nodes[e["id"]] = (float(x), float(z))
        for e in ds["elements"]:
            t = e.get("tags", {})
            if e["type"] != "way" or t.get("railway") not in ("rail", "light_rail") or t.get("tunnel") == "yes":
                continue
            if t.get("service") in ("yard", "siding", "spur"):
                continue
            try:
                tracks = int(t.get("tracks", "1"))
            except ValueError:
                tracks = 1
            ways.append(dict(id=e["id"], cls="rail", width=3.4 + (tracks - 1) * 4.0, speed=0, style=7, prio=10,
                             oneway=False, name="Voie ferrée", bridge=t.get("bridge") not in (None, "no"),
                             nodes=[n for n in e["nodes"] if n in nodes], tags=t))
    ways = merge_dual_carriageways(nodes, ways)
    return nodes, ways


# ---------------------------------------------------------------------------------
# Simplification : chaussées séparées rapprochées -> une seule route à double sens
# ---------------------------------------------------------------------------------
# (pas les rues résidentielles : en ville, deux sens uniques voisins forment souvent une boucle autour
#  d'un îlot, qu'il ne faut pas fusionner)
DUAL_CLASSES = {"trunk", "primary", "secondary", "tertiary", "unclassified",
                "trunk_link", "primary_link", "secondary_link", "tertiary_link"}
DUAL_DIST = 16.0       # écart maximal entre les axes des deux chaussées (m)


def merge_dual_carriageways(nodes, ways):
    """Hors autoroute, deux voies à sens unique parallèles et de sens opposés (route de Lyon, D16,
    boulevards de La Tour-du-Pin…) se chevauchaient, avec bordure de terre-plein et trottoirs au milieu.
    On garde une des deux, ramenée sur l'axe médian et passée à double sens ; les rues qui se
    raccordaient à la chaussée supprimée sont rebranchées sur la route conservée."""
    from shapely.geometry import LineString, Point
    from shapely.strtree import STRtree
    rb_nodes = {n for w in ways if w["tags"].get("junction") in ("roundabout", "circular") for n in w["nodes"]}
    cand = [w for w in ways if w["oneway"] and w["cls"] in DUAL_CLASSES and not w["bridge"]
            and w["tags"].get("junction") not in ("roundabout", "circular") and len(w["nodes"]) >= 2]
    if not cand:
        return ways
    lines = [LineString([nodes[n] for n in w["nodes"]]) for w in cand]
    tree = STRtree(lines)

    def tangent(line, d):
        a = line.interpolate(max(0.0, d - 1.0)); b = line.interpolate(min(line.length, d + 1.0))
        v = np.array([b.x - a.x, b.y - a.y]); l = np.linalg.norm(v)
        return v / l if l > 1e-9 else v

    def samples(line):
        n = max(2, int(line.length / 3.0) + 1)
        return [line.length * k / (n - 1) for k in range(n)]

    def opposite(i, d, allowed=None):
        """Chaussée opposée la plus proche au point d de la voie i : (indice, distance) ou None."""
        p = lines[i].interpolate(d); t = tangent(lines[i], d)
        best = None
        for j in tree.query(p.buffer(DUAL_DIST)):
            if j == i or (allowed is not None and j not in allowed):
                continue
            na, nb = cand[i]["name"], cand[j]["name"]
            if na and nb and na != nb:          # deux rues différentes
                continue
            dd = lines[j].distance(p)
            if dd > DUAL_DIST or dd < 0.5:
                continue
            if np.dot(tangent(lines[j], lines[j].project(p)), t) > -0.6:
                continue
            if best is None or dd < best[1]:
                best = (j, dd)
        return best

    cover = []
    for i, L in enumerate(lines):
        ss = samples(L)
        cover.append(sum(1 for d in ss if opposite(i, d)) / len(ss))
    paired = [i for i in range(len(cand)) if cover[i] >= 0.5]
    keep, drop = set(), set()
    for i in sorted(paired, key=lambda i: -lines[i].length):
        if i in keep or i in drop:
            continue
        keep.add(i)
        for d in samples(lines[i]):
            o = opposite(i, d)
            if o and o[0] not in keep:
                drop.add(o[0])
    # une chaussée n'est supprimée que si la route conservée la couvre presque entièrement
    changed = True
    while changed:
        changed = False
        for j in list(drop):
            ss = samples(lines[j])
            c = sum(1 for d in ss if opposite(j, d, keep)) / len(ss)
            if c < 0.75:
                drop.discard(j); changed = True
    keep = {i for i in keep if any(opposite(i, d, drop) for d in samples(lines[i]))}
    if not drop:
        return ways
    # routes conservées : nœuds ramenés au milieu des deux chaussées
    moved = {}
    for i in keep:
        w = cand[i]
        for n in w["nodes"]:
            if n in rb_nodes or n in moved:
                continue
            p = Point(nodes[n])
            best = None
            for j in drop:
                dd = lines[j].distance(p)
                if dd <= DUAL_DIST and (best is None or dd < best[1]):
                    best = (j, dd)
            if best:
                q = lines[best[0]].interpolate(lines[best[0]].project(p))
                moved[n] = ((p.x + q.x) / 2, (p.y + q.y) / 2)
        w_opp = np.mean([cand[j]["width"] for j in drop if lines[j].distance(lines[i]) < DUAL_DIST] or [w["width"]])
        w["width"] = float(min(14.0, w["width"] + w_opp))
        w["oneway"] = False
        w["tags"] = dict(w["tags"], oneway="no", dual_merged="yes")
    nodes.update(moved)
    kept_ways = [cand[i] for i in keep]
    drop_ids = {id(cand[j]) for j in drop}
    dropped_nodes = {n for j in drop for n in cand[j]["nodes"]}
    others = [w for w in ways if id(w) not in drop_ids]
    used_elsewhere = {n for w in others for n in w["nodes"]}
    # rues raccordées à une chaussée supprimée : le nœud est inséré sur la route conservée
    reattached = 0
    for n in sorted(dropped_nodes & used_elsewhere):
        if n in rb_nodes or any(n in w["nodes"] for w in kept_ways):
            continue
        p = Point(nodes[n])
        best = None
        for w in kept_ways:
            L = LineString([nodes[m] for m in w["nodes"]])
            dd = L.distance(p)
            if dd <= DUAL_DIST + 4 and (best is None or dd < best[1]):
                best = (w, dd, L)
        if not best:
            continue
        w, _, L = best
        q = L.interpolate(L.project(p))
        # segment où insérer
        k_best, e_best = 0, 1e9
        for k in range(len(w["nodes"]) - 1):
            e = LineString([nodes[w["nodes"][k]], nodes[w["nodes"][k + 1]]]).distance(q)
            if e < e_best:
                k_best, e_best = k, e
        nodes[n] = (q.x, q.y)
        a, b = nodes[w["nodes"][k_best]], nodes[w["nodes"][k_best + 1]]
        if math.dist(a, nodes[n]) < 0.5:
            alias = w["nodes"][k_best]
        elif math.dist(b, nodes[n]) < 0.5:
            alias = w["nodes"][k_best + 1]
        else:
            w["nodes"].insert(k_best + 1, n); alias = None
        if alias is not None:
            for o in others:
                o["nodes"] = [alias if m == n else m for m in o["nodes"]]
        reattached += 1
    for o in others:   # pas de doublons consécutifs après rebranchement
        o["nodes"] = [m for k, m in enumerate(o["nodes"]) if k == 0 or m != o["nodes"][k - 1]]
    print("chaussées séparées fusionnées : %d conservées à double sens, %d supprimées, %d raccords rebranchés"
          % (len(keep), len(drop), reattached))
    return [w for w in others if len(w["nodes"]) >= 2]


def inside(x, z, m=0.0):
    return X0 + m <= x <= X1 - m and Z0 + m <= z <= Z1 - m


def clip_way(way, nodes):
    """Découpe une voie en morceaux entièrement dans la zone jouable."""
    parts, cur = [], []
    for n in way["nodes"]:
        x, z = nodes[n]
        if inside(x, z, ROAD_MARGIN):
            cur.append(n)
        else:
            if len(cur) >= 2:
                parts.append(cur)
            cur = []
    if len(cur) >= 2:
        parts.append(cur)
    return parts


def densify(pts, max_seg=4.0):
    out = [pts[0]]
    for a, b in zip(pts[:-1], pts[1:]):
        d = math.dist(a, b)
        n = max(1, int(math.ceil(d / max_seg)))
        for k in range(1, n + 1):
            t = k / n
            out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    return np.array(out)


def smooth_corners(P, iters=2):
    """Arrondit légèrement les angles des polylignes OSM (Chaikin conservant les extrémités)."""
    for _ in range(iters):
        if len(P) < 3:
            return P
        Q = [P[0]]
        for a, b in zip(P[:-1], P[1:]):
            Q.append(0.75 * a + 0.25 * b)
            Q.append(0.25 * a + 0.75 * b)
        Q.append(P[-1])
        P = np.array(Q)
    return P


# ---------------------------------------------------------------------------------
def main():
    H = load_inner()
    nz, nx = H.shape
    print("grille fine", nx, "x", nz, "alt", H.min(), H.max())
    Hfar = load_outer()
    far = Grid(Hfar, OUTER["xmin"], OUTER["zmin"], FAR_STEP)

    # 1) Raccord du bord de la grille fine avec la grille grossière (pas de fissure),
    #    avec un fondu sur 150 m.
    xs = X0 + np.arange(nx) * STEP
    zs = Z0 + np.arange(nz) * STEP
    XX, ZZ = np.meshgrid(xs, zs)
    Hfar_at = far.height(XX, ZZ)
    edge_d = np.minimum.reduce([XX - X0, X1 - XX, ZZ - Z0, Z1 - ZZ])
    w = np.clip(edge_d / 150.0, 0, 1)
    w = w * w * (3 - 2 * w)
    H = Hfar_at * (1 - w) + H * w

    # Champ lissé utilisé pour le profil en long des routes
    Hs = gaussian_filter(H, sigma=1.3)
    smooth_grid = Grid(Hs, X0, Z0, STEP)

    nodes, ways = parse_osm()
    roads = []
    for wdef in ways:
        for part in clip_way(wdef, nodes):
            pts = np.array([nodes[n] for n in part])
            if not wdef["bridge"]:
                pts = smooth_corners(pts, 2)
            P = densify(list(map(tuple, pts)), 4.0)
            seg = np.linalg.norm(np.diff(P, axis=0), axis=1)
            if seg.sum() < 3:
                continue
            r = dict(wdef); r["P"] = P; r["part"] = part
            r["s"] = np.concatenate([[0], np.cumsum(seg)])
            roads.append(r)
    print(len(roads), "tronçons de route")

    # 2) Profil en long des routes
    for r in roads:
        P = r["P"]
        h = smooth_grid.smooth(P[:, 0], P[:, 1])
        if r["bridge"]:
            h = np.linspace(h[0], h[-1], len(h))   # tablier rectiligne entre les culées
        r["h"] = h

    # 3) Terrassement : le terrain épouse la route sur sa largeur + 14 m, puis fondu sur 22 m
    FLAT, BLEND = 14.5, 22.0
    best = np.full(H.shape, np.inf)
    hroad = np.zeros(H.shape)
    for r in roads:
        if r["bridge"]:
            continue
        P, h, hw = r["P"], r["h"], r["width"] / 2
        R = hw + FLAT + BLEND
        for k in range(len(P) - 1):
            ax, az = P[k]; bx, bz = P[k + 1]
            i0 = max(0, int((min(ax, bx) - R - X0) // STEP)); i1 = min(nx - 1, int((max(ax, bx) + R - X0) // STEP) + 1)
            j0 = max(0, int((min(az, bz) - R - Z0) // STEP)); j1 = min(nz - 1, int((max(az, bz) + R - Z0) // STEP) + 1)
            if i1 < i0 or j1 < j0:
                continue
            gx = XX[j0:j1 + 1, i0:i1 + 1]; gz = ZZ[j0:j1 + 1, i0:i1 + 1]
            dx, dz = bx - ax, bz - az
            L2 = dx * dx + dz * dz
            t = np.clip(((gx - ax) * dx + (gz - az) * dz) / L2, 0, 1)
            d = np.hypot(gx - (ax + t * dx), gz - (az + t * dz)) - hw
            hh = h[k] + (h[k + 1] - h[k]) * t
            sub = best[j0:j1 + 1, i0:i1 + 1]
            m = d < sub
            sub[m] = d[m]
            hroad[j0:j1 + 1, i0:i1 + 1][m] = hh[m]
    wt = np.clip((best - FLAT) / BLEND, 0, 1)
    wt = wt * wt * (3 - 2 * wt)
    carved = np.where(np.isfinite(best), hroad * (1 - wt) + H * wt, H)
    # le bord doit rester identique à la grille grossière
    border = (edge_d < 1)
    carved[border] = Hfar_at[border]
    terrain = Grid(carved, X0, Z0, STEP)
    print("terrassement : max déplacement %.1f m" % np.abs(carved - H).max())

    # 4) Maillage des routes ----------------------------------------------------------
    nCx = int(math.ceil((nx - 1) / CHUNK_CELLS)); nCz = int(math.ceil((nz - 1) / CHUNK_CELLS))
    chunks = {}   # (cx,cz) -> dict(prio -> [verts list, indices list])

    def chunk_of(x, z):
        return (min(nCx - 1, max(0, int((x - X0) // CHUNK))), min(nCz - 1, max(0, int((z - Z0) // CHUNK))))

    def bucket(c, prio):
        return chunks.setdefault(c, {}).setdefault(prio, ([], []))

    CLEAR = 0.07

    def lift(xs_, zs_, ys_):
        """Garantit que la route reste au-dessus du terrain (avec marge)."""
        return np.maximum(ys_, terrain.height(xs_, zs_) + CLEAR)

    # passages à niveau : rails noyés dans l'enrobé
    lc_pts = []
    p = os.path.join(DATA, "osm_street.json")
    if os.path.exists(p):
        for e in json.load(open(p))["elements"]:
            if e["type"] == "node" and e.get("tags", {}).get("railway") == "level_crossing":
                lc_pts.append(to_local(e["lon"], e["lat"]))
    lc_pts = np.array(lc_pts, dtype=float).reshape(-1, 2)

    junction_count = {}
    for r in [r for r in roads if r["cls"] != "rail"]:
        for n in (r["part"][0], r["part"][-1]):
            junction_count[n] = junction_count.get(n, 0) + 1
        for n in r["part"][1:-1]:
            junction_count[n] = junction_count.get(n, 0) + 2

    discs = {}   # nœud -> (rayon, style, prio, hauteur)
    for r in roads:
        P, h, hw = r["P"], r["h"], r["width"] / 2
        n = len(P)
        T = np.zeros_like(P)
        T[1:-1] = P[2:] - P[:-2]; T[0] = P[1] - P[0]; T[-1] = P[-1] - P[-2]
        T /= np.linalg.norm(T, axis=1, keepdims=True)
        N = np.stack([-T[:, 1], T[:, 0]], axis=1)            # normale (gauche quand on regarde vers +T... x=E,z=S)
        # facteur d'onglet
        miter = np.ones(n)
        for k in range(1, n - 1):
            a = P[k] - P[k - 1]; b = P[k + 1] - P[k]
            a /= np.linalg.norm(a); b /= np.linalg.norm(b)
            na = np.array([-a[1], a[0]])
            miter[k] = 1.0 / max(0.55, float(np.dot(na, N[k])))
        lat = np.array([-1.0, 0.0, 1.0])
        VX = P[:, 0:1] + N[:, 0:1] * lat * hw * miter[:, None]
        VZ = P[:, 1:2] + N[:, 1:2] * lat * hw * miter[:, None]
        base = r["h"][:, None] + np.zeros((1, 3))
        if r["bridge"]:
            VY = base + 0.10
            VY[[0, -1]] = lift(VX[[0, -1]], VZ[[0, -1]], VY[[0, -1]])
        else:
            VY = lift(VX, VZ, base + CLEAR)
            # contrôle entre les sommets
            for _ in range(3):
                bad = False
                for f in (0.25, 0.5, 0.75):
                    mx = VX[:-1] + (VX[1:] - VX[:-1]) * f
                    mz = VZ[:-1] + (VZ[1:] - VZ[:-1]) * f
                    my = VY[:-1] + (VY[1:] - VY[:-1]) * f
                    deficit = terrain.height(mx, mz) + 0.03 - my
                    m = deficit > 0
                    if m.any():
                        bad = True
                        add = np.where(m, deficit + 0.02, 0)
                        VY[:-1] += add; VY[1:] += add
                if not bad:
                    break
        r["_geo"] = (n, T, N, miter, lat, VX, VZ, VY)

    # raccords : aux nœuds partagés, toutes les extrémités prennent la hauteur la plus haute,
    # avec un fondu sur ~16 m (évite les marches entre deux tronçons rehaussés différemment)
    ends = {}
    for r in roads:
        if r["cls"] == "rail" or r["bridge"]:
            continue
        n_ = r["_geo"][0]
        for node, kk in ((r["part"][0], 0), (r["part"][-1], n_ - 1)):
            ends.setdefault(node, []).append((r, kk))
        # nœuds intermédiaires partagés (carrefours en T)
        for node in r["part"][1:-1]:
            if junction_count.get(node, 0) > 2:
                kk = int(np.argmin(np.hypot(r["P"][:, 0] - nodes[node][0], r["P"][:, 1] - nodes[node][1])))
                ends.setdefault(node, []).append((r, kk))
    for node, lst in ends.items():
        if len(lst) < 2:
            continue
        target = max(float(r["_geo"][7][kk, 1]) for r, kk in lst)
        for r, kk in lst:
            VY = r["_geo"][7]
            delta = target - float(VY[kk, 1])
            if delta <= 0.005:
                continue
            s_ = r["s"]
            dist = np.abs(s_ - s_[kk])
            f = np.clip(1.0 - dist / 16.0, 0.0, 1.0)
            f = f * f * (3 - 2 * f)
            VY += (delta * f)[:, None]

    for r in roads:
        P, h, hw = r["P"], r["h"], r["width"] / 2
        n, T, N, miter, lat, VX, VZ, VY = r.pop("_geo")
        r["deck"] = VY[:, 1]
        nrm = terrain.normal(P[:, 0], P[:, 1]) if not r["bridge"] else np.tile([0.0, 1.0, 0.0], (n, 1))
        style = float(r["style"])
        if r["oneway"] and r["cls"] != "motorway" and style < 3:
            style = 3.0 if r["width"] < 6 else style
        row_style = np.full(n, style)
        if r["cls"] == "rail" and len(lc_pts):
            dmin = np.min(np.hypot(P[:, None, 0] - lc_pts[None, :, 0], P[:, None, 1] - lc_pts[None, :, 1]), axis=1)
            row_style[dmin < 6.5] = 27.0
        r["VX"], r["VY"], r["VZ"], r["N"] = VX, VY, VZ, N
        rowmap = {}
        for k in range(n - 1):
            mid = (P[k] + P[k + 1]) / 2
            c = chunk_of(*mid)
            verts, idx = bucket(c, r["prio"])
            for kk in (k, k + 1):
                if (c, kk) not in rowmap:
                    rowmap[(c, kk)] = len(verts) // 10
                    for j in range(3):
                        verts.extend([VX[kk, j], VY[kk, j], VZ[kk, j], *nrm[kk], lat[j] * hw, r["s"][kk], hw, row_style[kk]])
            a = rowmap[(c, k)]; b = rowmap[(c, k + 1)]
            for j in range(2):
                idx.extend([a + j, b + j, a + j + 1, a + j + 1, b + j, b + j + 1])
            if r["bridge"]:
                # parapets et flancs en béton
                for side in (0, 2):
                    sgn = -1 if side == 0 else 1
                    p0 = (VX[k, side], VY[k, side], VZ[k, side]); p1 = (VX[k + 1, side], VY[k + 1, side], VZ[k + 1, side])
                    nx_, nz_ = N[k] * sgn
                    base_i = len(verts) // 10
                    for (px, py, pz) in (p0, p1):
                        verts.extend([px, py - 1.2, pz, nx_, 0, nz_, 0, 0, 1, STYLE_CONCRETE])
                        verts.extend([px, py + 0.9, pz, nx_, 0, nz_, 0, 0, 1, STYLE_CONCRETE])
                    idx.extend([base_i, base_i + 2, base_i + 1, base_i + 1, base_i + 2, base_i + 3])
        if r["cls"] == "rail":
            continue
        # disques de raccordement aux extrémités
        for end, kk in ((r["part"][0], 0), (r["part"][-1], n - 1)):
            if junction_count.get(end, 0) >= 2:
                cur = discs.get(end)
                cand = (hw, r["style"], r["prio"], float(VY[kk, 1]), P[kk])
                if cur is None or cand[2] > cur[2] or (cand[2] == cur[2] and cand[0] > cur[0]):
                    discs[end] = cand
        # disques dans les virages serrés
        for k in range(1, n - 1):
            if miter[k] > 1.25 and not r["bridge"]:
                key = ("v", id(r), k)
                discs[key] = (hw, r["style"], r["prio"], float(VY[k, 1]), P[k])

    SEG = 14
    for key, (hw, style, prio, y, p) in discs.items():
        c = chunk_of(*p)
        # les disques se dessinent juste avant les rubans de même priorité
        verts, idx = bucket(c, prio - 0.5)
        ang = np.linspace(0, 2 * math.pi, SEG, endpoint=False)
        rx = p[0] + np.cos(ang) * hw * 1.02; rz = p[1] + np.sin(ang) * hw * 1.02
        ry = lift(rx, rz, np.full(SEG, y))
        cy = max(y, float(terrain.height(p[0], p[1])) + CLEAR)
        b = len(verts) // 10
        verts.extend([p[0], cy, p[1], 0, 1, 0, 0, 0, hw, style + DISC_FLAG])
        for j in range(SEG):
            verts.extend([rx[j], ry[j], rz[j], 0, 1, 0, 0, 0, hw, style + DISC_FLAG])
        for j in range(SEG):
            idx.extend([b, b + 1 + (j + 1) % SEG, b + 1 + j])

    out = bytearray()
    out += struct.pack("<4sfffii", b"RDS1", X0, Z0, CHUNK, nCx, nCz)
    out += struct.pack("<i", len(chunks))
    nv_tot = 0
    for (cx, cz), groups in sorted(chunks.items()):
        verts, idx = [], []
        for prio in sorted(groups):
            v, i = groups[prio]
            off = len(verts) // 10
            verts.extend(v); idx.extend(j + off for j in i)
        nv_tot += len(verts) // 10
        out += struct.pack("<iiii", cx, cz, len(verts) // 10, len(idx))
        out += np.asarray(verts, dtype="<f4").tobytes()
        out += np.asarray(idx, dtype="<u4").tobytes()
    os.makedirs(ASSETS, exist_ok=True)
    open(os.path.join(ASSETS, "roads.bin"), "wb").write(out)
    print("routes : %d sommets, %d tuiles, %.1f Mo" % (nv_tot, len(chunks), len(out) / 1e6))

    # 5) Terrain -------------------------------------------------------------------
    with open(os.path.join(ASSETS, "terrain.bin"), "wb") as f:
        f.write(struct.pack("<4siifff", b"TER1", nx, nz, X0, Z0, STEP))
        f.write(carved.astype("<f4").tobytes())
    fz_, fx_ = Hfar.shape
    with open(os.path.join(ASSETS, "far.bin"), "wb") as f:
        f.write(struct.pack("<4siifff", b"TER1", fx_, fz_, OUTER["xmin"], OUTER["zmin"], FAR_STEP))
        f.write(Hfar.astype("<f4").tobytes())

    # 6) Graphe routier, ponts, lieux ---------------------------------------------
    used = {}
    node_list = []
    gways = []
    import pickle
    pickle.dump([dict(id=r["id"], cls=r["cls"], style=r["style"], oneway=r["oneway"], bridge=r["bridge"], tags=r["tags"],
                      width=r["width"], part=r["part"], P=r["P"], s=r["s"], VX=r["VX"], VY=r["VY"], VZ=r["VZ"], N=r["N"],
                      name=r["name"], speed=r["speed"]) for r in roads], open(os.path.join(DATA, "road_rows.pkl"), "wb"))
    roads = [r for r in roads if r["cls"] != "rail"]
    for r in roads:
        ids = []
        for n in r["part"]:
            if n not in used:
                used[n] = len(node_list)
                node_list.append(nodes[n])
            ids.append(used[n])
        gways.append(dict(c=r["style"], k=r["cls"], o=1 if r["oneway"] else 0, n=r["name"], s=r["speed"],
                          w=round(r["width"], 1), b=1 if r["bridge"] else 0, nd=ids))
    bridges = []
    for r in roads:
        if r["bridge"]:
            bridges.append(dict(hw=r["width"] / 2, p=[[round(float(x), 2), round(float(y), 2), round(float(z), 2)]
                                                      for (x, z), y in zip(r["P"], r["deck"])]))

    pois = build_pois(node_list, gways)
    start = next(p for p in pois if p["name"] == "Mairie de Rochetoirin")
    meta = dict(nodes=[[round(x, 1), round(z, 1)] for x, z in node_list], ways=gways, bridges=bridges,
                pois=pois, start=start, bounds=[X0, Z0, X1, Z1])
    json.dump(meta, open(os.path.join(ASSETS, "map.json"), "w"), ensure_ascii=False, separators=(",", ":"))
    print("graphe : %d nœuds, %d voies, %d ponts, %d lieux" % (len(node_list), len(gways), len(bridges), len(pois)))


# Lieux de livraison -----------------------------------------------------------------
KINDS = {
    "townhall": "Mairie", "place_of_worship": "Église", "school": "École", "community_centre": "Salle",
    "bakery": "Boulangerie", "butcher": "Boucherie", "restaurant": "Restaurant", "supermarket": "Supermarché",
    "garden_centre": "Jardinerie", "fuel": "Station", "car": "Garage", "car_repair": "Garage",
    "sports_centre": "Sport", "pitch": "Sport", "doityourself": "Bricolage", "recycling": "Déchèterie",
    "library": "Bibliothèque", "fire_station": "Pompiers", "pharmacy": "Pharmacie", "veterinary": "Vétérinaire",
    "locality": "Lieu-dit", "hamlet": "Hameau", "village": "Village", "studio": "Radio",
}
NAMES_OVERRIDE = {"fire_station": "Caserne des pompiers"}


def build_pois(node_list, gways):
    d = json.load(open(os.path.join(DATA, "pois.json")))
    # nœuds accessibles en voiture (hors chemins de terre), pour l'accrochage
    drivable = set()
    for w in gways:
        if w["k"] not in ("track",):
            drivable.update(w["nd"])
    ids = np.array(sorted(drivable))
    pts = np.array([node_list[i] for i in ids])
    seen = set(); out = []
    for e in d["elements"]:
        t = e.get("tags", {}); c = e.get("center", e)
        kind = next((t[k] for k in ("place", "amenity", "shop", "leisure", "craft", "office") if k in t), None)
        if kind not in KINDS:
            continue
        name = t.get("name") or NAMES_OVERRIDE.get(kind)
        if not name or name.lower().startswith(("conteneur", "section")):
            continue
        key = unicodedata.normalize("NFD", name.lower()).encode("ascii", "ignore")
        if key in seen:
            continue
        x, z = to_local(c["lon"], c["lat"]); x, z = float(x), float(z)
        if not inside(x, z, 120):
            continue
        dd = np.hypot(pts[:, 0] - x, pts[:, 1] - z)
        k = int(np.argmin(dd))
        if dd[k] > 150:
            continue
        seen.add(key)
        out.append(dict(name=name, kind=KINDS[kind], node=int(ids[k]),
                        x=round(float(pts[k, 0]), 1), z=round(float(pts[k, 1]), 1)))
    return out


if __name__ == "__main__":
    main()
