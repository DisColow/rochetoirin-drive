"""Trottoirs, angles de carrefour et îlots surélevés construits en 2D (polygones) puis maillés.

Principe : chaque côté de rue reçoit une bande de largeur constante, posée à cheval sur le bord de la chaussée ;
on fusionne toutes les bandes et on retranche l'emprise des chaussées (arrondie dans les angles de carrefour) et
les bâtiments. Les trottoirs se rejoignent ainsi sans trou aux carrefours et la bordure suit exactement
le bord de l'enrobé. Les angles arrondis entre deux chaussées sont comblés d'enrobé (« tablier » au format routes).

Bordures basses (10 cm) : la physique reçoit une surélévation interpolée sur 1 m, la voiture monte dessus.
"""
import numpy as np
import shapely
import mapbox_earcut as earcut
from scipy.spatial import cKDTree
from shapely.geometry import LineString, Point, Polygon, box
from shapely.geometry.polygon import orient
from shapely.ops import unary_union

CURB = 0.10            # hauteur de bordure (m)
SW_W = 1.6             # largeur des trottoirs (m)
CORNER_R = 3.0         # rayon des angles de trottoir aux carrefours (m)
CURB_COL = (0.74, 0.73, 0.70)
PAVE_COL = (0.56, 0.55, 0.53)
SKIRT_COL = (0.62, 0.61, 0.58)


def polys(g):
    if g is None or g.is_empty:
        return []
    if g.geom_type == "Polygon":
        return [g]
    return [q for q in getattr(g, "geoms", []) if q.geom_type == "Polygon" and not q.is_empty] + \
        [p for q in getattr(g, "geoms", []) if q.geom_type == "MultiPolygon" for p in q.geoms]


class RoadHeight:
    """Altitude de la chaussée la plus proche (pondération inverse des distances sur les rangées des rubans)."""

    def __init__(self, roads):
        pts, ys, st, hw = [], [], [], []
        for r in roads:
            if r.cls == "rail" or r.bridge:
                continue
            for c in range(3):
                pts.append(np.c_[r.VX[:, c], r.VZ[:, c]]); ys.append(r.VY[:, c])
                st.append(np.full(r.n, r.style)); hw.append(np.full(r.n, r.hw))
        self.t = cKDTree(np.vstack(pts))
        self.y = np.concatenate(ys); self.style = np.concatenate(st); self.hw = np.concatenate(hw)

    def __call__(self, x, z):
        q = np.c_[np.atleast_1d(x), np.atleast_1d(z)]
        d, i = self.t.query(q, k=4)
        w = 1.0 / np.maximum(d, 0.3) ** 2
        return (self.y[i] * w).sum(1) / w.sum(1)

    def nearest(self, x, z):
        _, i = self.t.query((x, z))
        return int(self.style[i]), float(self.hw[i])


def carriageway(roads, by_node, node_pos):
    """Emprise de l'enrobé (rubans + disques de carrefour, légèrement sous-estimée pour ne jamais laisser de jour)
    et emprise étendue aux angles arrondis des carrefours."""
    paved = [r for r in roads if r.cls != "rail" and not r.bridge]
    parts = [LineString(r.P).buffer(r.hw, quad_segs=4, cap_style="flat", join_style="round") for r in paved if r.n > 1]
    ends = {}
    for r in paved:
        ends.setdefault(r.part[0], []).append((r, r.P[0]))
        ends.setdefault(r.part[-1], []).append((r, r.P[-1]))
    nodes = []
    for nd, lst in ends.items():
        if len(by_node.get(nd, [])) >= 2:
            p = lst[0][1]
            parts.append(Point(p).buffer(min(r.hw for r, _ in lst) * 1.0, quad_segs=4))
            nodes.append(p)
    # nœuds intermédiaires partagés (carrefours en T sur une rue continue)
    for nd, lst in by_node.items():
        if len(lst) >= 2 and nd not in ends:
            r = roads[lst[0]]
            if r.cls != "rail" and not r.bridge and nd in node_pos:
                nodes.append(np.array(node_pos[nd]))
    carriage = unary_union(parts)
    # angles arrondis : fermeture morphologique locale autour de chaque carrefour
    ext_parts = []
    for p in nodes:
        win = Point(p).buffer(14.0, quad_segs=4)
        loc = carriage.intersection(box(p[0] - 22, p[1] - 22, p[0] + 22, p[1] + 22))
        if loc.is_empty:
            continue
        closed = loc.buffer(CORNER_R, quad_segs=4).buffer(-CORNER_R, quad_segs=4)
        ext_parts.append(closed.intersection(win))
    ext = unary_union([carriage] + ext_parts)
    return carriage, ext


def tri_poly(poly, step=8.0):
    """Triangulation d'un polygone (avec trous) après densification des bords. Le polygone est d'abord réparé
    (contour auto-intersecté après simplification) ; si earcut ne couvre pas toute l'aire, triangulation de
    Delaunay contrainte (shapely)."""
    poly = shapely.make_valid(poly)
    if poly.geom_type != "Polygon":
        parts = [g for g in getattr(poly, "geoms", []) if g.geom_type == "Polygon"]
        if not parts:
            return np.zeros((0, 2)), []
        poly = max(parts, key=lambda g: g.area)
    v, t = _earcut(poly, step)
    if len(t):
        P = v[np.array(t).reshape(-1, 3)]
        area = 0.5 * np.abs((P[:, 1, 0] - P[:, 0, 0]) * (P[:, 2, 1] - P[:, 0, 1]) - (P[:, 2, 0] - P[:, 0, 0]) * (P[:, 1, 1] - P[:, 0, 1])).sum()
        if area > 0.95 * poly.area:
            return v, t
    tris = shapely.constrained_delaunay_triangles(shapely.segmentize(poly, step))
    verts, idx = [], []
    for tr in getattr(tris, "geoms", []):
        c = np.asarray(tr.exterior.coords)[:3]
        b0 = len(verts); verts.extend(map(tuple, c)); idx.extend([b0, b0 + 1, b0 + 2])
    return np.array(verts) if verts else np.zeros((0, 2)), idx


def subdivide(v, tri, maxlen=2.0):
    """Découpe les triangles jusqu'à ce qu'aucune arête ne dépasse maxlen (surfaces posées sur un terrain bombé :
    sans sommets intérieurs, le sol perce la surface au milieu)."""
    V = [tuple(p) for p in np.asarray(v)]
    cache = {}

    def mid(a, b):
        k = (min(a, b), max(a, b))
        if k not in cache:
            V.append(((V[a][0] + V[b][0]) / 2, (V[a][1] + V[b][1]) / 2)); cache[k] = len(V) - 1
        return cache[k]

    T = [tuple(tri[i:i + 3]) for i in range(0, len(tri), 3)]
    out = []
    while T:
        a, b, c = T.pop()
        la = np.hypot(*np.subtract(V[a], V[b])); lb = np.hypot(*np.subtract(V[b], V[c])); lc = np.hypot(*np.subtract(V[c], V[a]))
        m = max(la, lb, lc)
        if m <= maxlen:
            out.extend((a, b, c)); continue
        if m == la:
            d = mid(a, b); T += [(a, d, c), (d, b, c)]
        elif m == lb:
            d = mid(b, c); T += [(a, b, d), (a, d, c)]
        else:
            d = mid(c, a); T += [(a, b, d), (d, b, c)]
    return np.array(V), out


def _earcut(poly, step):
    poly = orient(shapely.segmentize(poly, step), 1.0)
    rings = [np.asarray(poly.exterior.coords)[:-1]] + [np.asarray(h.coords)[:-1] for h in poly.interiors]
    rings = [r for r in rings if len(r) >= 3]
    if not rings:
        return np.zeros((0, 2)), []
    verts = np.vstack(rings)
    ends = np.cumsum([len(r) for r in rings]).astype(np.uint32)
    return verts, list(earcut.triangulate_float64(verts.astype(np.float64), ends))


def raised_mesh(m, poly, top, base, edge_kind, top_col, top_mat, curb_mat, step=8.0, band=0.16):
    """Surface surélevée : dessus triangulé, faces verticales sur le pourtour, dessus de bordure clair.
    top(x, z) / base(x, z, kind) : altitudes ; edge_kind(milieux) -> 0 pas de face (coupure de tuile),
    1 bordure côté chaussée, 2 retombée vers le terrain."""
    v, tri = tri_poly(poly, step)
    if len(tri) == 0:
        return
    ys = top(v[:, 0], v[:, 1])
    ids = [m.vert((float(x), float(y), float(z)), (0, 1, 0), top_col, (float(x), float(z)), top_mat) for (x, z), y in zip(v, ys)]
    for k in range(0, len(tri), 3):
        m.tri(ids[tri[k]], ids[tri[k + 1]], ids[tri[k + 2]])
    p = orient(shapely.segmentize(poly, step), 1.0)
    for ring in [p.exterior] + list(p.interiors):
        c = np.asarray(ring.coords)[:-1]
        nP = len(c)
        if nP < 3:
            continue
        a, b = c, np.roll(c, -1, axis=0)
        kinds = edge_kind((a + b) / 2)
        d = b - a
        L = np.maximum(np.hypot(d[:, 0], d[:, 1]), 1e-6)
        en = np.c_[d[:, 1] / L, -d[:, 0] / L]              # normale extérieure de chaque arête (anneau CCW, trous CW)
        yt = top(c[:, 0], c[:, 1])
        cache = {}

        def vtx(j, kind, edge):
            # sommets partagés entre arêtes voisines de même nature (normale moyenne)
            key = (j, kind)
            if key not in cache:
                prev = (j - 1) % nP
                nn = en[edge]
                if kinds[prev] == kind and edge == j:
                    nn = en[prev] + en[j]
                elif (j - 1) % nP == edge and kinds[j % nP] == kind:
                    nn = en[edge] + en[j % nP]
                nn = nn / max(np.hypot(*nn), 1e-6)
                n3 = (float(nn[0]), 0.0, float(nn[1]))
                col = CURB_COL if kind == 1 else SKIRT_COL
                x, z = c[j]
                lo = m.vert((x, base(x, z, kind), z), n3, col, (0, 0), curb_mat)
                hi = m.vert((x, float(yt[j]), z), n3, col, (0, 0), curb_mat)
                bd = None
                if kind == 1 and band > 0:
                    bd = (m.vert((x, float(yt[j]) + 0.006, z), (0, 1, 0), CURB_COL, (0, 0), curb_mat),
                          m.vert((x - nn[0] * band, float(yt[j]) + 0.006, z - nn[1] * band), (0, 1, 0), CURB_COL, (0, 0), curb_mat))
                cache[key] = (lo, hi, bd)
            return cache[key]

        for k in range(nP):
            if kinds[k] == 0 or L[k] < 1e-3:
                continue
            k2 = (k + 1) % nP
            A, B = vtx(k, kinds[k], k), vtx(k2, kinds[k], k)
            m.quad(A[0], B[0], B[1], A[1])
            if A[2] is not None:
                m.quad(A[2][0], B[2][0], B[2][1], A[2][1])


def surf_shape(surf, poly, height, X0, Z0):
    """Surélévation physique (cm, grille de 1 m par tuiles de 32 m) : height(x, z) en mètres sur le polygone."""
    mnx, mnz, mxx, mxz = poly.bounds
    for tx in range(int((mnx - X0) // 32), int((mxx - X0) // 32) + 1):
        for tz in range(int((mnz - Z0) // 32), int((mxz - Z0) // 32) + 1):
            gx = X0 + tx * 32 + np.arange(33); gz = Z0 + tz * 32 + np.arange(33)
            Xg, Zg = np.meshgrid(gx, gz)
            inside = shapely.contains_xy(poly, Xg, Zg)
            if not inside.any():
                continue
            h = np.zeros(Xg.shape)
            h[inside] = height(Xg[inside], Zg[inside])
            cm = np.clip(np.round(h * 100), 0, 255).astype(np.uint8)
            t = surf.setdefault((tx, tz), np.zeros((33, 33), np.uint8))
            np.maximum(t, cm, out=t)
