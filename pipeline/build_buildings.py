"""Bâtiments génériques : emprises et hauteurs réelles (IGN BD TOPO), textures photo (Poly Haven / ambientCG).

Pour chaque bâtiment :
 - murs sur l'emprise réelle (redressée à l'équerre quand elle l'est presque), pied enterré dans le relief ;
 - toit à deux ou quatre pans (hauteur de faîtage BD TOPO quand elle existe), y compris en L / T / U par
   recouvrement de rectangles ; toit-terrasse avec acrotère pour les grands bâtiments plats ;
 - couleur du toit d'après l'orthophoto, matériau des murs d'après la BD TOPO (pierre, crépi, bois, métal...) ;
 - fenêtres en retrait (tableaux, appuis), volets battants ou roulants, porte côté rue, porte de garage pour les
   annexes, vitrines pour les commerces, portes sectionnelles pour les bâtiments d'activité ;
 - pas d'ouverture sur les murs mitoyens.
Sortie : ../godot/world/buildings/b_tx_tz.glb (nœud « bld » : tout le visible, matériau unique « building » à tableau
de textures ; nœud « col » : prismes simples pour les collisions)."""
import hashlib, json, math, os, pickle, shutil
import numpy as np
import shapely
from shapely.geometry import shape, Polygon, MultiPolygon, Point
from shapely.ops import transform
from shapely.strtree import STRtree
from shapely.prepared import prep
from scipy.spatial import cKDTree
from PIL import Image

import geo
from build_roads import DEM, REG
from build_bld_tex import IDX, LAYERS
from glb import write_glb

OUT = "../godot/world/buildings"
# kit de détails Blender (blender_maisons.py) posé sur les ouvertures et les toits : enregistrements d'instances
KIT_MODELS = ["fenetre", "fenetre_vr", "volet", "porte", "garage", "marquise", "faitiere", "mitron", "antenne", "parabole"]
KID = {n: i for i, n in enumerate(KIT_MODELS)}
KIT = []
DOOR_TINTS = [((0.42, 0.16, 0.1), 3), ((0.2, 0.3, 0.45), 2), ((0.25, 0.35, 0.26), 2), ((0.9, 0.9, 0.88), 3),
              ((0.35, 0.35, 0.37), 2), ((0.55, 0.38, 0.22), 2)]


def kit(name, X, Y, Z, o, col=(1, 1, 1)):
    """Instance du kit : base (colonnes X, Y, Z) et origine (monde), couleur d'instance."""
    KIT.append((KID[name],) + tuple(float(v) for v in X) + tuple(float(v) for v in Y) + tuple(float(v) for v in Z)
               + (float(o[0]), float(o[1]), float(o[2])) + (float(col[0]), float(col[1]), float(col[2]), 1.0))


def kit_line(a, b, y_off=0.02):
    """Faîtières le long d'une arête de toit (a, b : points 3D), par mètres entiers."""
    a = np.asarray(a, float); b = np.asarray(b, float)
    v = b - a; L = float(np.linalg.norm(v))
    if L < 0.4:
        return
    n = max(1, int(round(L)))
    X = v / n
    up = np.array([0, 1.0, 0]); Y = up - X * (X @ up) / (X @ X); Y /= np.linalg.norm(Y)
    Z = np.cross(X, Y); Z /= np.linalg.norm(Z)
    for k in range(n):
        kit("faitiere", X, Y, Z, a + X * k + np.array([0, y_off, 0]))
TILE = 256.0
SCALE = {n: s for n, _, s in LAYERS}
GABLE_WIN = [False, None]
STAIRS = []                      # escaliers extérieurs posés (contrôle) : x, sol, z, normale du mur        # fenêtre de comble dans les pignons hauts (bâtiment en cours), teinte des volets


def _box(M, c, ax, ay, az, layer, tint):
    """Pavé centré en c, demi-axes ax, ay, az (vecteurs 3D orthogonaux)."""
    c = np.asarray(c, float); ax = np.asarray(ax, float); ay = np.asarray(ay, float); az = np.asarray(az, float)
    for a, b, n in ((ax, ay, az), (ay, ax, -az), (ay, az, ax), (az, ay, -ax), (az, ax, ay), (ax, az, -ay)):
        f = c + n
        pts = [f - a - b, f + a - b, f + a + b, f - a + b]
        M.poly(pts, [(0, 0), (1, 0), (1, 1), (0, 1)], layer, tint, n)


def ext_stairs(M, C, A, B, gnd, u0, nf):
    """Escalier extérieur droit le long du mur A -> B (vu de dehors) : une volée de 16 marches par étage (2,75 m) puis un
    palier de 1,4 m devant la porte, garde-corps métallique côté vide, collision comprise."""
    A = np.asarray(A, float); B = np.asarray(B, float)
    L = float(np.hypot(*(B - A))); d = (B - A) / L; n2 = np.array([d[1], -d[0]])
    D3 = np.array([d[0], 0, d[1]]); N3 = np.array([n2[0], 0, n2[1]]); UP = np.array([0.0, 1.0, 0.0])
    wid = 1.1; off = 0.05 + wid / 2
    conc = srgb((0.78, 0.77, 0.74)); rail = srgb((0.28, 0.29, 0.31))
    P = lambda u, y, o: np.array([A[0] + d[0] * u + n2[0] * o, y, A[1] + d[1] * u + n2[1] * o])
    u = u0
    for f in range(nf):
        y0 = gnd + f * 2.75
        for s in range(16):
            yc = y0 + (s + 1) * 2.75 / 16
            _box(M, P(u + s * 0.275 + 0.1375, yc - 0.04, off), D3 * 0.14, UP * 0.04, N3 * wid / 2, IDX["beton"], conc)
        # limon côté vide et palier
        _box(M, P(u + 2.2, y0 + 1.33, off + wid / 2), D3 * 2.25, UP * 0.15, N3 * 0.03, IDX["beton"], conc)
        ul = u + 16 * 0.275
        _box(M, P(ul + 0.7, y0 + 2.75 - 0.08, off), D3 * 0.7, UP * 0.08, N3 * wid / 2, IDX["beton"], conc)
        # poteau sous le palier
        _box(M, P(ul + 1.25, (gnd + y0 + 2.67) / 2, off + wid / 2 - 0.08), D3 * 0.06, UP * ((y0 + 2.67 - gnd) / 2), N3 * 0.06, IDX["beton"], conc)
        # garde-corps : main courante inclinée sur la volée, droite sur le palier, barreaux
        for t in np.linspace(0.0, 1.0, 9):
            yb = y0 + t * 2.75
            _box(M, P(u + t * 4.4, yb + 0.5, off + wid / 2 + 0.02), D3 * 0.012, UP * 0.5, N3 * 0.012, IDX["beton"], rail)
        a = P(u, y0 + 1.0, off + wid / 2 + 0.02); b = P(ul, y0 + 2.75 + 1.0, off + wid / 2 + 0.02)
        v = b - a
        _box(M, (a + b) / 2, v / 2, UP * 0.025, N3 * 0.025, IDX["beton"], rail)
        _box(M, P(ul + 0.7, y0 + 2.75 + 1.0, off + wid / 2 + 0.02), D3 * 0.7, UP * 0.025, N3 * 0.025, IDX["beton"], rail)
        _box(M, P(ul + 1.4, y0 + 2.75 + 0.5, off), D3 * 0.012, UP * 0.5, N3 * (wid / 2), IDX["beton"], rail)
        # collision : volée et palier
        q = [P(u, 0, 0.05), P(ul + 1.4, 0, 0.05), P(ul + 1.4, 0, off + wid / 2), P(u, 0, off + wid / 2)]
        V = np.array([[p[0], gnd - 0.3, p[2]] for p in q] + [[p[0], y0 + 2.75, p[2]] for p in q], np.float32)
        I = [0, 1, 5, 0, 5, 4, 1, 2, 6, 1, 6, 5, 2, 3, 7, 2, 7, 6, 3, 0, 4, 3, 4, 7, 4, 5, 6, 4, 6, 7]
        C.append((V, np.array(I, np.uint32)))
        u = ul + 1.4


class CarvedDEM(DEM):
    """Relief terrassé (celui affiché dans le jeu)."""
    def __init__(self):
        super().__init__()
        for k in list(self.reg):
            p = "data/dem_carved/r_%d_%d.npy" % k
            if os.path.exists(p):
                self.reg[k] = np.load(p)


def rnd(key, salt=""):
    """Aléa déterministe dans [0, 1) par bâtiment."""
    return int(hashlib.md5((key + salt).encode()).hexdigest()[:8], 16) / 2 ** 32


def pick(key, salt, items):
    r = rnd(key, salt); acc = 0.0; tot = sum(w for _, w in items)
    for v, w in items:
        acc += w / tot
        if r < acc:
            return v
    return items[-1][0]


def srgb(c):
    return np.array(c, np.float32)


# ------------------------------------------------------------------------------------------------ maillage
class Mesh:
    def __init__(self):
        self.P, self.N, self.UV, self.L, self.C, self.I = [], [], [], [], [], []
        self.n = 0

    def poly(self, pts, uv, layer, tint, normal=None):
        """Polygone convexe plan (éventail) ; orientation corrigée selon la normale voulue."""
        pts = np.asarray(pts, np.float32); uv = np.asarray(uv, np.float32)
        k = len(pts)
        if normal is None:
            normal = np.cross(pts[1] - pts[0], pts[2] - pts[0])
        normal = np.asarray(normal, np.float32)
        nl = np.linalg.norm(normal)
        if nl < 1e-9:
            return
        normal = normal / nl
        tri = []
        for j in range(1, k - 1):
            a, b, c = 0, j, j + 1
            if np.dot(np.cross(pts[b] - pts[a], pts[c] - pts[a]), normal) < 0:
                b, c = c, b
            tri += [a + self.n, b + self.n, c + self.n]
        self.P.append(pts); self.N.append(np.tile(normal, (k, 1))); self.UV.append(uv)
        self.L.append(np.tile([float(layer), 0.0], (k, 1))); self.C.append(np.tile(tint, (k, 1)))
        self.I += tri; self.n += k

    def tris(self, P, uv, I, layer, tint, normal_up=True):
        P = np.asarray(P, np.float32); I = np.asarray(I, np.uint32).reshape(-1, 3).copy()
        a, b, c = P[I[:, 0]], P[I[:, 1]], P[I[:, 2]]
        fl = np.cross(b - a, c - a)[:, 1] < 0
        if not normal_up:
            fl = ~fl
        I[fl] = I[fl][:, ::-1]
        nrm = np.tile([0, 1 if normal_up else -1, 0], (len(P), 1)).astype(np.float32)
        self.P.append(P); self.N.append(nrm); self.UV.append(np.asarray(uv, np.float32))
        self.L.append(np.tile([float(layer), 0.0], (len(P), 1))); self.C.append(np.tile(tint, (len(P), 1)))
        self.I += (I.ravel() + self.n).tolist(); self.n += len(P)

    def prim(self, mat):
        if not self.n:
            return None
        return (mat, np.vstack(self.P), np.vstack(self.N), np.vstack(self.UV), np.array(self.I, np.uint32),
                np.vstack(self.C), np.vstack(self.L))


def tri_polygon(poly):
    """Triangulation contrainte d'un polygone (sommets 2D, indices)."""
    import triangle as tr
    V, Sg = [], []
    holes = []
    for ring in [poly.exterior] + list(poly.interiors):
        C = np.asarray(ring.coords)[:-1]
        b = len(V); V.extend(C.tolist()); Sg.extend([(b + k, b + (k + 1) % len(C)) for k in range(len(C))])
    for h in poly.interiors:
        holes.append(Polygon(h).representative_point().coords[0])
    A = dict(vertices=np.array(V), segments=np.array(Sg))
    if holes:
        A["holes"] = np.array(holes)
    R = tr.triangulate(A, "pQ")
    return R["vertices"], R["triangles"].ravel()


# ------------------------------------------------------------------------------------------------ données
def load():
    plan = json.load(open("data/routes_plan.json"))
    zone = Polygon(plan["zone"])
    zp = prep(zone)
    feats = json.load(open("data/batiments.json"))["features"]
    out = []
    for f in feats:
        g = transform(lambda x, y, z=None: geo.to_local(x, y), shape(f["geometry"]))
        if not zp.intersects(g):
            continue
        g = g.buffer(0)
        if isinstance(g, MultiPolygon):
            g = max(g.geoms, key=lambda p: p.area)
        if g.is_empty or g.area < 6.0:
            continue
        out.append((f["properties"], g))
    return out


class Ortho:
    def __init__(self):
        self.cache = {}

    def mean(self, poly):
        """Couleur moyenne (0..1) de l'orthophoto à l'intérieur de l'emprise (rétrécie de 0,5 m)."""
        inner = poly.buffer(-0.6)
        if inner.is_empty:
            inner = poly
        mnx, mnz, mxx, mxz = inner.bounds
        xs = np.arange(mnx + 0.5, mxx, 1.0); zs = np.arange(mnz + 0.5, mxz, 1.0)
        if len(xs) == 0 or len(zs) == 0:
            c = inner.centroid; xs = np.array([c.x]); zs = np.array([c.y])
        X, Z = np.meshgrid(xs, zs); X = X.ravel(); Z = Z.ravel()
        m = shapely.contains_xy(inner, X, Z)
        if m.sum() == 0:
            c = inner.centroid; X = np.array([c.x]); Z = np.array([c.y])
        else:
            X, Z = X[m], Z[m]
        cols = []
        for x, z in zip(X[:400], Z[:400]):
            i, j = int(x // REG), int(z // REG)
            O = self.cache.get((i, j))
            if O is None:
                p = "data/ortho/r_%d_%d.jpg" % (i, j)
                O = np.asarray(Image.open(p)).astype(np.float32) / 255 if os.path.exists(p) else False
                self.cache[(i, j)] = O
            if O is False:
                continue
            px = int(np.clip((x - i * REG) / 2.0, 0, O.shape[1] - 1)); pz = int(np.clip((z - j * REG) / 2.0, 0, O.shape[0] - 1))
            cols.append(O[pz, px])
        return np.median(np.array(cols), 0) if cols else np.array([0.55, 0.35, 0.28])


# ------------------------------------------------------------------------------------------------ formes
def obb_frame(poly):
    """Rectangle orienté minimal : angle (rad) de son grand côté, centre."""
    r = poly.minimum_rotated_rectangle
    C = np.asarray(r.exterior.coords)[:4]
    e = [C[1] - C[0], C[2] - C[1]]
    L = [np.hypot(*v) for v in e]
    v = e[int(np.argmax(L))]
    a = math.atan2(v[1], v[0])
    c = r.centroid
    return a, np.array([c.x, c.y]), r


def rot(P, a, c):
    P = np.asarray(P, float)
    ca, sa = math.cos(a), math.sin(a)
    d = P - c
    return np.c_[c[0] + d[:, 0] * ca - d[:, 1] * sa, c[1] + d[:, 0] * sa + d[:, 1] * ca]


def _cluster(vals, tol=0.6):
    vals = np.sort(vals); out = [[vals[0]]]
    for v in vals[1:]:
        if v - out[-1][-1] <= tol:
            out[-1].append(v)
        else:
            out.append([v])
    return np.array([np.mean(g) for g in out])


def decompose(poly):
    """Footprint redressé et rectangles de toiture (dans le repère tourné) ; None si forme quelconque.
    Retourne (polygone redressé tourné, [rectangles (x0, z0, x1, z1)], angle, centre)."""
    a, c, r = obb_frame(poly)
    pr = Polygon(rot(np.asarray(poly.exterior.coords), -a, c))
    rr = Polygon(rot(np.asarray(r.exterior.coords), -a, c))
    fill = poly.area / max(r.area, 1e-6)
    if fill > 0.87:
        x0, z0, x1, z1 = rr.bounds
        return Polygon([(x0, z0), (x1, z0), (x1, z1), (x0, z1)]), [(x0, z0, x1, z1)], a, c
    C = np.asarray(pr.exterior.coords)
    E = np.diff(C, axis=0); L = np.hypot(E[:, 0], E[:, 1])
    ang = np.abs(np.degrees(np.arctan2(E[:, 1], E[:, 0]))) % 90
    axis = (np.minimum(ang, 90 - ang) < 12)
    if (L * axis).sum() < 0.9 * L.sum() or len(C) > 24:
        return None
    xs = _cluster(C[:, 0]); zs = _cluster(C[:, 1])
    snap = np.c_[xs[np.abs(C[:, 0][:, None] - xs[None]).argmin(1)], zs[np.abs(C[:, 1][:, None] - zs[None]).argmin(1)]]
    ps = Polygon(snap).buffer(0)
    if isinstance(ps, MultiPolygon) or ps.is_empty or abs(ps.area - pr.area) > 0.2 * pr.area:
        return None
    ps = shapely.simplify(ps, 0.05)
    nx, nz = len(xs) - 1, len(zs) - 1
    if nx < 1 or nz < 1:
        return None
    cx = (xs[:-1] + xs[1:]) / 2; cz = (zs[:-1] + zs[1:]) / 2
    F = np.array([[ps.contains(Point(x, z)) for x in cx] for z in cz])          # [nz, nx]
    covered = np.zeros_like(F)
    rects = []
    for _ in range(4):
        if (F & ~covered).sum() == 0:
            break
        best, bs = None, (-1, -1)
        for i0 in range(nx):
            for i1 in range(i0, nx):
                for j0 in range(nz):
                    for j1 in range(j0, nz):
                        blk = F[j0:j1 + 1, i0:i1 + 1]
                        if not blk.all():
                            break
                        new = (~covered[j0:j1 + 1, i0:i1 + 1]).sum()
                        area = (xs[i1 + 1] - xs[i0]) * (zs[j1 + 1] - zs[j0])
                        if (new, area) > bs:
                            bs = (new, area); best = (i0, i1, j0, j1)
        if best is None or bs[0] == 0:
            break
        i0, i1, j0, j1 = best
        covered[j0:j1 + 1, i0:i1 + 1] = True
        R = (xs[i0], zs[j0], xs[i1 + 1], zs[j1 + 1])
        if min(R[2] - R[0], R[3] - R[1]) >= 2.5:
            rects.append(R)
    if not rects:
        return None
    return ps, rects, a, c


# ------------------------------------------------------------------------------------------------ toits
def soffit(M, pts, nrm):
    """Dessous du pan (lambris bois) 12 cm plus bas : épaisseur du toit, visible sous les débords."""
    P = [(p[0], p[1] - 0.12, p[2]) for p in pts]
    uv = [(p[0] / 2.5, p[2] / 2.5) for p in pts]
    M.poly(P, uv, IDX["bardage_bois"], srgb((1.15, 1.1, 1.0)), -np.asarray(nrm, float))


ZINC = (0.80, 0.81, 0.82)


def gutter(M, a, b, nrm, ground):
    """Gouttière pendante le long de l'égout (a -> b) et descente d'eau jusqu'au sol à une extrémité."""
    a = np.asarray(a, float); b = np.asarray(b, float); n = np.asarray(nrm, float)
    n = n / max(np.linalg.norm(n), 1e-6)
    off = n * 0.07 + np.array([0, -0.12, 0])
    lay = IDX["beton"]
    p0, p1 = a + off, b + off
    # gouttière : demi-rond approché (fond + deux bords)
    for (dy, dn, w) in ((-0.05, 0.0, 0.07), (0.0, 0.06, 0.0), (0.0, -0.06, 0.0)):
        q0 = p0 + n * dn + np.array([0, dy, 0]); q1 = p1 + n * dn + np.array([0, dy, 0])
        if w:
            M.poly([q0 - n * w, q1 - n * w, q1 + n * w, q0 + n * w], [(0, 0), (1, 0), (1, 0.1), (0, 0.1)], lay, srgb(ZINC), (0, -1, 0))
        else:
            M.poly([q0, q1, q1 + np.array([0, -0.05, 0]), q0 + np.array([0, -0.05, 0])], [(0, 0), (1, 0), (1, 0.1), (0, 0.1)],
                   lay, srgb(ZINC), n if dn > 0 else -n)
    if ground is not None:
        d = (b - a) / max(np.linalg.norm(b - a), 1e-6)
        top = p0 + d * 0.25 - np.array([0, 0.05, 0])
        bot = np.array([top[0], ground + 0.1, top[2]])
        if top[1] - bot[1] > 1.0:
            w = 0.045
            for (u, nn) in ((d, d), (-d, -d), (n, n), (-n, -n)):
                side = np.cross(nn, [0, 1, 0]); side = side / max(np.linalg.norm(side), 1e-6) * w
                c0 = top + u * w; c1 = bot + u * w
                M.poly([c0 - side, c0 + side, c1 + side, c1 - side], [(0, 0), (0.1, 0), (0.1, 1), (0, 1)], lay, srgb(ZINC), nn)


def roof_rect(M, R, others, eave, pitch, kind, back, layer, tint, wall_layer, wall_tint, ov=0.35, ground=None):
    """Toit d'un rectangle (repère tourné) ; back(P) ramène au repère monde. kind : 'gable' | 'hip'."""
    x0, z0, x1, z1 = R
    along_x = (x1 - x0) >= (z1 - z0)
    # repère local du rectangle : s le long du faîtage, t en travers
    if along_x:
        s0, s1, t0, t1 = x0, x1, z0, z1
        P = lambda s, t, y: (s, t, y)
    else:
        s0, s1, t0, t1 = z0, z1, x0, x1
        P = lambda s, t, y: (t, s, y)
    tc = (t0 + t1) / 2; hw = (t1 - t0) / 2
    tn = math.tan(pitch)
    rise = hw * tn
    # extrémités intérieures (accolées à un autre rectangle) : prolongées jusqu'à l'axe du voisin, en pignon
    ends = []
    for side, s_end in ((0, s0), (1, s1)):
        probe = s_end - 0.3 if side == 0 else s_end + 0.3
        q = P(probe, tc, 0)
        inside = [o for o in others if o is not R and o[0] - 0.01 <= q[0] <= o[2] + 0.01 and o[1] - 0.01 <= q[1] <= o[3] + 0.01]
        if inside:
            o = inside[0]
            mid = ((o[0] + o[2]) / 2) if along_x else ((o[1] + o[3]) / 2)
            ends.append(("inner", mid))
        else:
            ends.append(("outer", s_end))
    sA = ends[0][1] if ends[0][0] == "inner" else s0
    sB = ends[1][1] if ends[1][0] == "inner" else s1
    hipA = kind == "hip" and ends[0][0] == "outer"
    hipB = kind == "hip" and ends[1][0] == "outer"
    oy = eave - ov * tn
    def W(s, t, y):
        p = P(s, t, y)
        q = back(np.array([[p[0], p[1]]]))[0]
        return (q[0], p[2], q[1])
    sa = sA - (ov if ends[0][0] == "outer" else 0.0)
    sb = sB + (ov if ends[1][0] == "outer" else 0.0)
    ra = sA + (hw if hipA else 0.0); rb = sB - (hw if hipB else 0.0)
    if ra > rb:
        ra = rb = (sA + sB) / 2
    ytop = eave + rise
    sc = SCALE[LAYERS[layer][0]]
    slope_len = math.hypot(hw + ov, rise + ov * tn)
    for sg in (-1, 1):
        te = tc + sg * (hw + ov)
        quad = [W(sa if not hipA else sa, te, oy), W(sb, te, oy), W(rb, tc, ytop), W(ra, tc, ytop)]
        if hipA:
            quad[0] = W(sA - ov, te, oy)
        if hipB:
            quad[1] = W(sB + ov, te, oy)
        # normale : vers le haut et vers l'extérieur
        p0 = np.array(quad[0]); p1 = np.array(quad[1]); p3 = np.array(quad[3])
        nrm = np.cross(p1 - p0, p3 - p0)
        if nrm[1] < 0:
            nrm = -nrm
        su = lambda s: s / sc
        uv = [(su(sa if not hipA else sA - ov), slope_len / sc), (su(sb if not hipB else sB + ov), slope_len / sc),
              (su(rb), 0.0), (su(ra), 0.0)]
        M.poly(quad, uv, layer, tint, nrm)
        soffit(M, quad, nrm)
    tiled = LAYERS[layer][0].startswith("tuile") and pitch > 0.15
    if tiled and rb - ra > 0.3:
        kit_line(W(ra, tc, ytop), W(rb, tc, ytop))
    for side, hip, s_e, s_r in ((0, hipA, sA, ra), (1, hipB, sB, rb)):
        sg = -1 if side == 0 else 1
        if hip and tiled:
            for tt in (-1, 1):
                kit_line(W(s_e + sg * ov, tc + tt * (hw + ov), oy), W(s_r, tc, ytop))
        if hip:
            tri = [W(s_e + sg * ov, tc - hw - ov, oy), W(s_e + sg * ov, tc + hw + ov, oy), W(s_r, tc, ytop)]
            p0, p1, p2 = map(np.array, tri)
            nrm = np.cross(p1 - p0, p2 - p0)
            if nrm[1] < 0:
                nrm = -nrm
            uv = [((-hw - ov) / sc, slope_len / sc), ((hw + ov) / sc, slope_len / sc), (0.0, 0.0)]
            M.poly(tri, uv, layer, tint, nrm)
            soffit(M, tri, nrm)
        else:
            # pignon (mur) et rive de toit
            s_w = s_e
            tri = [W(s_w, tc - hw, eave), W(s_w, tc + hw, eave), W(s_w, tc, ytop)]
            nrm = np.array(W(s_w + sg, tc, 0)) - np.array(W(s_w, tc, 0)); nrm[1] = 0
            wsc = SCALE[LAYERS[wall_layer][0]]
            M.poly(tri, [(-hw / wsc, 0), (hw / wsc, 0), (0, -rise / wsc)], wall_layer, wall_tint, nrm)
            if ends[side][0] == "outer" and GABLE_WIN[0] and rise >= 2.0 and hw >= 2.2:
                # fenêtre de comble au milieu du pignon (posée en applique : le pignon n'est pas percé)
                nn = nrm / max(np.linalg.norm(nrm), 1e-9)
                right = np.array([nn[2], 0.0, -nn[0]])
                c = np.array(W(s_w, tc, eave + 0.35)) + nn * 0.03
                kit("fenetre", right * 0.8, (0, 1.0, 0), nn, c - right * 0.4)
                M.poly([c - right * 0.45 + nn * 0.05, c + right * 0.45 + nn * 0.05, c + right * 0.45 - nn * 0.03, c - right * 0.45 - nn * 0.03],
                       [(0, 0), (1, 0), (1, 0.2), (0, 0.2)], IDX["beton"], srgb((0.95, 0.93, 0.88)), (0, 1, 0))
                if GABLE_WIN[1] is not None:
                    for sgn in (-1, 1):
                        kit("volet", right * 0.4, (0, 1.0, 0), nn, c + right * (0.4 if sgn > 0 else -0.8) + nn * 0.03, GABLE_WIN[1])
            if ends[side][0] == "outer":
                # épaisseur de rive (planche de rive)
                s_o = s_e + sg * ov
                for tt in (-1, 1):
                    a = W(s_o, tc + tt * (hw + ov), oy); b = W(s_o, tc, ytop)
                    a2 = (a[0], a[1] - 0.2, a[2]); b2 = (b[0], b[1] - 0.2, b[2])
                    M.poly([a, b, b2, a2], [(0, 0), (1, 0), (1, 0.1), (0, 0.1)], IDX["crepi"], srgb((0.85, 0.84, 0.8)), nrm)
    # bandeau d'égout (épaisseur du bord de toit le long des gouttières)
    for sg in (-1, 1):
        te = tc + sg * (hw + ov)
        a = W(sA - (ov if hipA or ends[0][0] == "outer" else 0), te, oy); b = W(sB + (ov if hipB or ends[1][0] == "outer" else 0), te, oy)
        nrm = np.array(W(0, te + sg, 0)) - np.array(W(0, te, 0)); nrm[1] = 0
        M.poly([a, b, (b[0], b[1] - 0.18, b[2]), (a[0], a[1] - 0.18, a[2])], [(0, 0), (1, 0), (1, 0.1), (0, 0.1)],
               IDX["crepi"], srgb((0.85, 0.84, 0.8)), nrm)
        if pitch > 0.12:
            gutter(M, a, b, nrm, ground)
    return ytop


def chimney(M, R, eave, pitch, back, key, layer, tint):
    """Souche de cheminée près du faîtage du rectangle principal."""
    x0, z0, x1, z1 = R
    along_x = (x1 - x0) >= (z1 - z0)
    s0, s1, t0, t1 = (x0, x1, z0, z1) if along_x else (z0, z1, x0, x1)
    hw = (t1 - t0) / 2; tc = (t0 + t1) / 2
    sc = s0 + (s1 - s0) * (0.3 + 0.4 * rnd(key, "cs"))
    tt = tc + (rnd(key, "ct") - 0.5) * hw * 0.6
    tn = math.tan(pitch)
    hlow = eave + tn * (hw - abs(tt - tc) - 0.45)
    htop = eave + tn * hw + 0.7 + 0.3 * rnd(key, "chh")
    a, b = 0.32, 0.25 + 0.15 * rnd(key, "cw")
    loc = [(sc - a, tt - b), (sc + a, tt - b), (sc + a, tt + b), (sc - a, tt + b)]
    if not along_x:
        loc = [(t, s_) for s_, t in loc]
    P = back(np.array(loc))
    c = P.mean(0)
    sc_ = SCALE[LAYERS[layer][0]]
    for k in range(4):
        p, q = P[k], P[(k + 1) % 4]
        n = np.array([p[0] + q[0] - 2 * c[0], 0, p[1] + q[1] - 2 * c[1]])
        L = np.hypot(*(q - p))
        M.poly([(p[0], hlow, p[1]), (q[0], hlow, q[1]), (q[0], htop, q[1]), (p[0], htop, p[1])],
               [(0, -hlow / sc_), (L / sc_, -hlow / sc_), (L / sc_, -htop / sc_), (0, -htop / sc_)], layer, tint, n)
    M.poly([(p[0], htop, p[1]) for p in P], [(0, 0), (0.2, 0), (0.2, 0.2), (0, 0.2)], IDX["beton"], srgb((0.6, 0.6, 0.58)), (0, 1, 0))
    ex = P[1] - P[0]; ex = ex / max(np.hypot(*ex), 1e-6)
    X = np.array([ex[0], 0, ex[1]]); Z = np.cross(X, [0, 1, 0])
    kit("mitron", X, (0, 1, 0), Z, (c[0], htop, c[1]))
    if rnd(key, "ant") < 0.45:
        a = rnd(key, "anta") * 6.283
        X = np.array([math.cos(a), 0, math.sin(a)]); Z = np.cross(X, [0, 1, 0])
        kit("antenne", X, (0, 1, 0), Z, (c[0] + ex[0] * 0.25, htop + 0.2, c[1] + ex[1] * 0.25))


# ------------------------------------------------------------------------------------------------ murs et ouvertures
KIT_DOOR = [(0.42, 0.16, 0.1), False]          # couleur de la porte d'entrée, marquise (réglés par build_one)


def wall_edge(M, A, B, base, top, gnd, layer, tint, openings, shutter_tint, plinth=True):
    """Mur plan de A à B (2D) entre base et top, percé des ouvertures [(u0, u1, v0, v1, couche, profondeur)].
    gnd : altitude du sol au pied du mur (haut du soubassement)."""
    A = np.asarray(A, float); B = np.asarray(B, float)
    L = float(np.hypot(*(B - A)))
    if L < 0.05:
        return
    d = (B - A) / L
    n2 = np.array([d[1], -d[0]])
    nrm = np.array([n2[0], 0.0, n2[1]])
    sc = SCALE[LAYERS[layer][0]]
    def W(u, y, off=0.0):
        p = A + d * u + n2 * off
        return (p[0], y, p[1])
    # découpage du mur autour des ouvertures (bandes horizontales)
    ys = sorted(set([base, top] + [o[2] for o in openings] + [o[3] for o in openings]))
    for ya, yb in zip(ys[:-1], ys[1:]):
        if yb - ya < 1e-3:
            continue
        holes = sorted([(o[0], o[1]) for o in openings if o[2] <= ya + 1e-4 and o[3] >= yb - 1e-4])
        u = 0.0
        for h0, h1 in holes + [(L, L)]:
            if h0 - u > 1e-3:
                M.poly([W(u, ya), W(h0, ya), W(h0, yb), W(u, yb)],
                       [(u / sc, -ya / sc), (h0 / sc, -ya / sc), (h0 / sc, -yb / sc), (u / sc, -yb / sc)], layer, tint, nrm)
            u = max(u, h1)
    for u0, u1, v0, v1, lay, dep in openings:
        # menuiserie en retrait et tableaux
        M.poly([W(u0, v0, -dep), W(u1, v0, -dep), W(u1, v1, -dep), W(u0, v1, -dep)],
               [(0.01, 0.99), (0.99, 0.99), (0.99, 0.01), (0.01, 0.01)], lay, srgb((1, 1, 1)), nrm)
        dv = np.array([d[0], 0, d[1]])
        M.poly([W(u0, v0), W(u0, v0, -dep), W(u0, v1, -dep), W(u0, v1)], [(0, 0), (dep / sc, 0), (dep / sc, 1 / sc), (0, 1 / sc)], layer, tint, dv)
        M.poly([W(u1, v0), W(u1, v0, -dep), W(u1, v1, -dep), W(u1, v1)], [(0, 0), (dep / sc, 0), (dep / sc, 1 / sc), (0, 1 / sc)], layer, tint, -dv)
        M.poly([W(u0, v1), W(u1, v1), W(u1, v1, -dep), W(u0, v1, -dep)], [(0, 0), (1 / sc, 0), (1 / sc, dep / sc), (0, dep / sc)], layer, tint, (0, -1, 0))
        # kit 3D (vu de dehors, x vers la droite = -d, origine au coin bas-gauche, au fond du tableau)
        mX = -np.array([d[0], 0, d[1]]); Zk = nrm / max(np.linalg.norm(nrm), 1e-9)
        wdt, hgt = u1 - u0, v1 - v0
        if lay == IDX["fenetre"] or lay == IDX["fenetre_volet_roulant"]:
            kit("fenetre" if lay == IDX["fenetre"] else "fenetre_vr", mX * wdt, (0, hgt, 0), Zk, W(u1, v0, -dep + 0.004))
        elif lay == IDX["porte"]:
            dc = KIT_DOOR[0]
            kit("porte", mX * wdt, (0, hgt, 0), Zk, W(u1, v0, -dep + 0.004), dc)
            if KIT_DOOR[1]:
                kit("marquise", mX * (wdt + 0.3), (0, 1, 0), Zk, W(u1 + 0.15, v1 + 0.12, 0.0))
        elif lay == IDX["porte_garage"] and wdt < 3.0:
            kit("garage", mX * wdt, (0, hgt, 0), Zk, W(u1, v0, -dep + 0.004))
        if lay in (IDX["fenetre"], IDX["fenetre_volet_roulant"]):
            if shutter_tint is not None and lay == IDX["fenetre"]:
                w2 = (u1 - u0) / 2
                for a_, b_ in ((u0 - w2, u0), (u1, u1 + w2)):
                    kit("volet", mX * (b_ - a_), (0, hgt, 0), Zk, W(b_, v0, 0.055), shutter_tint)
            # appui de fenêtre saillant
            M.poly([W(u0 - 0.05, v0, 0.06), W(u1 + 0.05, v0, 0.06), W(u1 + 0.05, v0, -dep), W(u0 - 0.05, v0, -dep)],
                   [(0, 0), (1, 0), (1, 0.2), (0, 0.2)], IDX["beton"], srgb((0.95, 0.93, 0.88)), (0, 1, 0))
            M.poly([W(u0 - 0.05, v0 - 0.06, 0.06), W(u1 + 0.05, v0 - 0.06, 0.06), W(u1 + 0.05, v0, 0.06), W(u0 - 0.05, v0, 0.06)],
                   [(0, 0), (1, 0), (1, 0.05), (0, 0.05)], IDX["beton"], srgb((0.95, 0.93, 0.88)), nrm)
            if shutter_tint is not None and lay == IDX["fenetre"]:
                w2 = (u1 - u0) / 2
                for a, b in ((u0 - w2, u0), (u1, u1 + w2)):
                    M.poly([W(a, v0, 0.04), W(b, v0, 0.04), W(b, v1, 0.04), W(a, v1, 0.04)],
                           [(0.02, 0.98), (0.98, 0.98), (0.98, 0.02), (0.02, 0.02)], IDX["volet"], shutter_tint, nrm)
        else:
            M.poly([W(u0, v0), W(u1, v0), W(u1, v0, -dep), W(u0, v0, -dep)], [(0, 0), (1, 0), (1, 0.1), (0, 0.1)], IDX["beton"],
                   srgb((0.7, 0.7, 0.68)), (0, 1, 0))
    if plinth and gnd - base > 0.05:
        # soubassement : même matière que le mur, un ton plus sombre, 25 cm au-dessus du sol (il paraissait noir)
        cuts = sorted([(o[0], o[1]) for o in openings if o[2] < gnd + 0.25])
        u = 0.0
        ptint = np.asarray(tint) * 0.86
        for h0, h1 in cuts + [(L, L)]:
            if h0 - u > 0.05:
                M.poly([W(u, base, 0.02), W(h0, base, 0.02), W(h0, gnd + 0.25, 0.02), W(u, gnd + 0.25, 0.02)],
                       [(u / sc, -base / sc), (h0 / sc, -base / sc), (h0 / sc, -(gnd + 0.25) / sc), (u / sc, -(gnd + 0.25) / sc)],
                       layer, ptint, nrm)
            u = max(u, h1)


# ------------------------------------------------------------------------------------------------ bâtiment
WALL_TINTS = [((0.97, 0.93, 0.86), 4), ((0.98, 0.92, 0.80), 3), ((0.98, 0.97, 0.94), 3), ((0.97, 0.90, 0.86), 2),
              ((0.92, 0.92, 0.90), 2), ((0.99, 0.94, 0.80), 2), ((0.96, 0.88, 0.80), 1), ((0.92, 0.89, 0.83), 2)]
SHUTTER_TINTS = [((0.62, 0.42, 0.28), 4), ((0.97, 0.97, 0.95), 3), ((0.80, 0.80, 0.78), 2), ((0.58, 0.68, 0.58), 2),
                 ((0.52, 0.62, 0.72), 2), ((0.60, 0.30, 0.28), 1), ((0.45, 0.52, 0.45), 1)]


def classify(p, poly):
    use = p.get("usage_1") or ""
    nat = p.get("nature") or ""
    A = poly.area
    H = p.get("hauteur")
    if nat.startswith("Industriel") or use in ("Industriel", "Agricole") or nat == "Serre":
        return "activite" if A > 60 else "annexe"
    if use == "Annexe" or (A < 22 and (H or 3) < 4):
        return "annexe"
    if use == "Commercial et services":
        return "commerce" if A < 1500 else "activite"
    if (H or 0) >= 10 or (A > 400 and use == "Résidentiel"):
        return "collectif"
    if A > 900:
        return "activite"
    return "maison"


def wall_material(p, kind, key):
    m = (p.get("materiaux_des_murs") or "") + "  "
    digits = set(m[:2]) - {"0", " "}
    if kind == "activite":
        if "6" in digits:
            return "bardage_bois"
        return pick(key, "wm", [("bardage_metal", 6), ("beton", 3), ("crepi", 2)])
    if "1" in digits or "2" in digits:
        return pick(key, "wm", [("pierre", 4), ("crepi_ancien", 4), ("pierre_taillee", 1), ("crepi", 1)])
    if "6" in digits:
        return "bardage_bois"
    if "7" in digits:
        return "bardage_metal"
    if "4" in digits:
        return pick(key, "wm", [("crepi", 6), ("brique", 3)])
    if digits & {"3", "5", "9"}:
        return pick(key, "wm", [("crepi", 9), ("crepi_ancien", 1)])
    if kind == "annexe":
        return pick(key, "wm", [("crepi", 4), ("bardage_bois", 3), ("pierre", 2), ("bardage_metal", 1)])
    return pick(key, "wm", [("crepi", 14), ("crepi_ancien", 3), ("pierre", 2), ("pierre_taillee", 1)])


def roof_material(ortho_rgb, kind, wall, key):
    """Couverture d'après l'orthophoto (peu saturée à 2 m : on compare rouge et bleu)."""
    r, g, b = ortho_rgb
    redness = r - b
    lum = (r + g + b) / 3
    var = 0.9 + 0.2 * rnd(key, "rv")
    if lum > 0.70 and kind in ("collectif", "commerce", "activite"):
        return "toit_plat", np.full(3, min(lum * 1.25, 1.2))
    if kind == "activite" and redness < 0.03:
        return "bardage_metal", np.clip(np.array([lum * 1.35] * 3) * np.array([1.0, 1.0, 1.02]), 0.3, 1.1)
    if redness < -0.008 or (lum < 0.33 and redness < 0.02):
        return "tuile_grise", np.full(3, np.clip(lum / 0.37, 0.55, 1.2) * var)
    old = wall in ("pierre", "crepi_ancien", "pierre_taillee")
    tex = pick(key, "rm", [("tuile_meca", 7), ("tuile_ancienne", 4)] + ([("tuile_mousse", 2)] if old else []))
    t = np.array([1.0, 0.97 + 0.06 * rnd(key, "rg"), 0.95 + 0.1 * rnd(key, "rb")]) * var * np.clip(lum / 0.5, 0.8, 1.2)
    return tex, t


def build_one(M, C, p, poly, dem, ortho, road_tree, road_pts, others_tree, others, my_i, ov=None):
    """Construit un bâtiment ; ov : réglages imposés (bâtiments emblématiques : mairies, châteaux) — wall, wtint, roof,
    roof_tint, hip, modern, shutters. Retourne un résumé (forme, hauteurs, côté rue) pour les ajouts éventuels."""
    ov = ov or {}
    key = p.get("cleabs") or str(my_i)
    kind = ov.get("kind") or classify(p, poly)
    poly = shapely.simplify(poly, 0.3)
    if poly.area < 6 or not poly.is_valid:
        return None
    poly = shapely.geometry.polygon.orient(poly, 1.0)
    H = p.get("hauteur")
    if not H or H <= 0:
        f = p.get("nombre_d_etages")
        H = (f * 2.8 + 0.6) if f else {"annexe": 2.6, "maison": 5.5, "collectif": 12.0, "commerce": 5.0, "activite": 6.5}[kind]
    H = float(np.clip(max(H, ov.get("min_h", 0.0)), 2.2, 45.0))
    rise_data = None
    if p.get("altitude_maximale_toit") and p.get("altitude_minimale_sol"):
        rise_data = float(p["altitude_maximale_toit"]) - float(p["altitude_minimale_sol"]) - H
    # sol
    ring = np.asarray(poly.exterior.coords)
    g = dem.h(ring[:, 0], ring[:, 1])
    gmin, gmax = float(g.min()), float(g.max())
    base = gmin - 0.6
    eave = max(gmin + H, gmax + (2.2 if kind == "annexe" else 2.6))
    wall = wall_material(p, kind, key)
    wl = IDX[wall]
    wtint = srgb(pick(key, "wt", WALL_TINTS)) if wall in ("crepi", "crepi_ancien") else srgb((1, 1, 1))
    if wall == "bardage_metal":
        wtint = srgb(pick(key, "wt", [((0.85, 0.86, 0.85), 4), ((0.62, 0.70, 0.66), 2), ((0.80, 0.74, 0.62), 2), ((0.55, 0.6, 0.68), 1)]))
    if wall == "bardage_bois":
        wtint = srgb(pick(key, "wt", [((1, 1, 1), 3), ((1.25, 1.2, 1.1), 2)]))
    if "wall" in ov:
        wall = ov["wall"]; wl = IDX[wall]
    if "wtint" in ov:
        wtint = srgb(ov["wtint"])
    rgb = ortho.mean(poly)
    rtex, rtint = roof_material(rgb, kind, wall, key)
    if "roof" in ov:
        rtex = ov["roof"]; rtint = np.array(ov.get("roof_tint", (1, 1, 1)))
    rl = IDX[rtex]; rtint = srgb(np.clip(rtint, 0.2, 1.5))
    # forme du toit
    dec = decompose(poly)
    flat = False
    A = poly.area
    if rtex == "toit_plat" or (rise_data is not None and rise_data < 0.4 and A > 60 and kind != "annexe" and "roof" not in ov):
        flat = True
    if dec is None and kind in ("activite", "collectif", "commerce") and "hip" not in ov:
        flat = True
    # commerces : toit-terrasse, sauf les bâtiments anciens (centres de bourg)
    if kind == "commerce" and wall not in ("pierre", "pierre_taillee", "crepi_ancien") and "roof" not in ov:
        flat = True
    if dec is None and not flat:
        # forme quelconque : rectangle orienté si l'emprise le remplit à peu près, sinon terrasse
        a, c, r = obb_frame(poly)
        if A / r.area > (0.5 if "hip" in ov else 0.72):
            rr = Polygon(rot(np.asarray(r.exterior.coords), -a, c))
            x0, z0, x1, z1 = rr.bounds
            dec = (Polygon([(x0, z0), (x1, z0), (x1, z1), (x0, z1)]), [(x0, z0, x1, z1)], a, c)
        else:
            flat = True
    if not flat:
        foot_r, rects, ang, cen = dec
        back = lambda P, ang=ang, cen=cen: rot(P, ang, cen)
        foot = Polygon(back(np.asarray(foot_r.exterior.coords)))
        foot = shapely.geometry.polygon.orient(foot, 1.0)
    else:
        foot = poly
    # murs
    ringw = np.asarray(foot.exterior.coords)
    gw = dem.h(ringw[:, 0], ringw[:, 1])
    top = eave + (0.6 if flat else 0.0)
    modern = ov.get("modern", wall in ("crepi", "brique", "beton") and rnd(key, "roll") < 0.6)
    if kind == "commerce" and wall not in ("pierre", "pierre_taillee", "crepi_ancien") and "modern" not in ov:
        modern = True                    # commerces récents : fenêtres sans volets battants
    sh_tint = None if modern else srgb(ov.get("shutters") or pick(key, "st", SHUTTER_TINTS))
    win_layer = IDX["fenetre_volet_roulant"] if modern else IDX["fenetre"]
    # côté rue : arête dont le milieu est le plus proche d'une route
    mids = (ringw[:-1] + ringw[1:]) / 2
    dists, _ = road_tree.query(mids)
    E = np.diff(ringw, axis=0); Ls = np.hypot(E[:, 0], E[:, 1])
    order = np.argsort(dists + np.where(Ls < 2.5, 1e3, 0))
    street = int(order[0])
    floors = max(1, int((eave - gmax - 0.2) / 2.75))
    KIT_DOOR[0] = pick(key, "door", DOOR_TINTS); KIT_DOOR[1] = rnd(key, "marq") < 0.35
    GABLE_WIN[0] = kind in ("maison", "collectif") and not modern or (kind == "maison" and rnd(key, "gw") < 0.5)
    GABLE_WIN[1] = sh_tint
    # immeubles : escalier extérieur le long du plus long mur libre (hors rue si possible) jusqu'aux étages
    stair = None
    if kind == "collectif" and floors >= 2 and "kind" not in ov:
        cand = []
        for k in range(len(ringw) - 1):
            n2 = np.array([E[k][1], -E[k][0]]) / max(Ls[k], 1e-6)
            mid = mids[k] + n2 * 0.7
            if any(others[j].contains(Point(mid)) for j in others_tree.query(Point(mid)) if j != my_i):
                continue
            if Ls[k] >= 7.0:
                cand.append((Ls[k] + (8.0 if k == street else 0.0), k))     # côté rue de préférence : visible
        if cand:
            k = max(cand)[1]
            nf = int(min(floors - 1, (Ls[k] - 1.0) // 5.8))
            if nf >= 1:
                u0 = (Ls[k] - nf * 5.8) / 2
                stair = (k, u0, u0 + nf * 5.8, nf)
    for k in range(len(ringw) - 1):
        Aa, Bb = ringw[k], ringw[k + 1]
        L = Ls[k]
        gnd = float(max(gw[k], gw[k + 1]))
        ops = []
        n2 = np.array([E[k][1], -E[k][0]]) / max(L, 1e-6)
        mid = mids[k] + n2 * 0.7
        mitoyen = any(others[j].contains(Point(mid)) for j in others_tree.query(Point(mid)) if j != my_i)
        if not mitoyen and L >= 2.0 and eave - gnd >= 2.2:
            if kind == "activite":
                if k == street and L >= 7:
                    nd = 1 if L < 20 else 2
                    for j in range(nd):
                        uc = L * (j + 1) / (nd + 1)
                        hh = min(4.2, eave - gnd - 0.6)
                        if hh > 2.4:
                            ops.append((uc - 2.0, uc + 2.0, gnd + 0.05, gnd + 0.05 + hh, IDX["porte_garage"], 0.12))
                if eave - gnd > 4.5 and L >= 6:
                    n = int(L // 6)
                    for j in range(n):
                        uc = (j + 0.5) * L / n
                        if any(o[0] - 0.8 < uc < o[1] + 0.8 for o in ops):
                            continue
                        ops.append((uc - 0.9, uc + 0.9, eave - 2.0, eave - 0.9, IDX["fenetre_volet_roulant"], 0.1))
            elif kind == "annexe":
                if k == street and L >= 3.0 and eave - gnd >= 2.3:
                    w = 2.4 if L >= 3.2 else L - 0.6
                    uc = L / 2
                    ops.append((uc - w / 2, uc + w / 2, gnd + 0.02, gnd + min(2.05, eave - gnd - 0.3), IDX["porte_garage"], 0.1))
            else:
                ww, wh, sp = (1.0, 1.3, 3.2) if kind == "maison" else (1.2, 1.45, 2.9)
                margin = 0.55 + (ww / 2 if sh_tint is not None else 0.25)
                n = int((L - 2 * margin + sp - ww) // sp)
                if n <= 0 and L >= ww + 2 * margin:
                    n = 1
                slots = [L / 2 + (j - (n - 1) / 2) * sp for j in range(max(n, 0))]
                door_slot = None
                if k == street and slots and kind in ("maison", "collectif"):
                    door_slot = min(range(len(slots)), key=lambda j: abs(slots[j] - L / 2) + rnd(key, "ds%d" % j) * 2)
                for f in range(floors + 1):
                    v0 = gnd + 0.9 + f * 2.75; whf = wh
                    if v0 + whf > eave - 0.25:
                        # étage sous un égout bas : fenêtre plus basse (allège à 0,55 m) plutôt que pas de fenêtre
                        v0 = gnd + f * 2.75 + 0.55; whf = 0.95
                        if f == 0 or v0 + whf > eave - 0.15 or v0 < gnd + f * 2.75 + 0.4:
                            break
                    for j, uc in enumerate(slots):
                        if f == 0 and kind == "commerce" and k == street:
                            ops.append((uc - 1.25, uc + 1.25, gnd + 0.08, gnd + 2.6, IDX["vitrine"], 0.08)); continue
                        if f == 0 and j == door_slot:
                            ops.append((uc - 0.47, uc + 0.47, gnd + 0.1, gnd + 2.25, IDX["porte"], 0.12)); continue
                        if f > 0 and kind == "commerce" and k == street and v0 < gnd + 2.8:
                            continue
                        if stair is not None and k == stair[0] and stair[1] - 0.4 < uc < stair[2] + 0.4:
                            continue                         # derrière l'escalier extérieur
                        ops.append((uc - ww / 2, uc + ww / 2, v0, v0 + whf, win_layer, 0.14))
                # commerce : vitrines au rez-de-chaussée ⇒ fenêtres d'étage au-dessus de 3 m
                if kind == "commerce" and k == street:
                    ops = [o for o in ops if not (o[4] == win_layer and o[2] < gnd + 2.8)]
        if stair is not None and k == stair[0]:
            for f in range(1, stair[3] + 1):
                ud = stair[1] + f * 5.8 - 0.65                  # porte au palier de l'étage f
                ops.append((ud - 0.47, ud + 0.47, gnd + f * 2.75 + 0.02, gnd + f * 2.75 + 2.17, IDX["porte"], 0.12))
        wall_edge(M, Aa, Bb, base, top, gnd, wl, wtint, ops, sh_tint)
        if stair is not None and k == stair[0]:
            ext_stairs(M, C, Aa, Bb, gnd, stair[1], stair[3])
            dd = (Bb - Aa) / L; nn = np.array([dd[1], -dd[0]])
            sc_ = Aa + dd * (stair[1] + stair[2]) / 2
            STAIRS.append([float(sc_[0]), float(gnd), float(sc_[1]), float(nn[0]), float(nn[1])])
        # antenne satellite sur un pignon ou une façade (une maison sur huit)
        if kind == "maison" and not mitoyen and k != street and L >= 4 and rnd(key, "dish%d" % k) < 0.06 and eave - gnd > 3.6:
            dd = (Bb - Aa) / L
            o = Aa + dd * (L * 0.82)
            kit("parabole", (-dd[0], 0, -dd[1]), (0, 1, 0), (n2[0], 0, n2[1]), (o[0], gnd + 3.0, o[1]))
    # toit
    if flat:
        inner = foot.buffer(-0.25, join_style="mitre")
        cap = inner if (not inner.is_empty and isinstance(inner, Polygon)) else foot
        V, T = tri_polygon(cap)
        sc = SCALE[LAYERS[IDX["toit_plat"]][0]]
        M.tris(np.c_[V[:, 0], np.full(len(V), eave + 0.45), V[:, 1]], V / sc, T, IDX["toit_plat"], srgb((1, 1, 1)))
        if cap is not foot:
            # acrotère : face intérieure et couvertine
            ci = np.asarray(cap.exterior.coords)
            for k in range(len(ci) - 1):
                a, b = ci[k], ci[k + 1]
                d = b - a; L = np.hypot(*d)
                if L < 0.05:
                    continue
                nrm = np.array([-d[1], 0, d[0]]) / L
                M.poly([(a[0], eave + 0.45, a[1]), (b[0], eave + 0.45, b[1]), (b[0], top, b[1]), (a[0], top, a[1])],
                       [(0, 0), (L / 3, 0), (L / 3, -0.05), (0, -0.05)], wl, wtint, nrm)
            ring_poly = foot.difference(cap)
            for part in getattr(ring_poly, "geoms", [ring_poly]):
                if part.geom_type == "Polygon" and part.area > 0.01:
                    V, T = tri_polygon(part)
                    M.tris(np.c_[V[:, 0], np.full(len(V), top), V[:, 1]], V / 3, T, IDX["beton"], srgb((0.8, 0.8, 0.78)))
        ytop = top
    else:
        # dalle au niveau de l'égout (bouche les éventuels trous entre rectangles)
        V, T = tri_polygon(foot)
        M.tris(np.c_[V[:, 0], np.full(len(V), eave - 0.02), V[:, 1]], V / 3, T, IDX["beton"], srgb((0.5, 0.5, 0.5)))
        foot_r, rects, ang, cen = dec
        main = max(rects, key=lambda R: (R[2] - R[0]) * (R[3] - R[1]))
        mw = min(main[2] - main[0], main[3] - main[1])
        if kind == "activite":
            pitch = math.radians(9)
        elif rise_data is not None and 0.8 < rise_data < mw * 0.75:
            pitch = math.atan(rise_data / (mw / 2))
        else:
            pitch = math.radians({"annexe": 22, "maison": 31, "collectif": 28, "commerce": 28}[kind] + rnd(key, "p") * 6 - 3)
        pitch = float(np.clip(pitch, math.radians(8), math.radians(45)))
        long_ratio = max(main[2] - main[0], main[3] - main[1]) / max(mw, 0.1)
        hip_p = {"maison": 0.55, "collectif": 0.5, "commerce": 0.3, "annexe": 0.1, "activite": 0.0}[kind]
        if wall in ("pierre", "pierre_taillee", "crepi_ancien"):
            hip_p *= 0.5
        rk = "hip" if (rnd(key, "hip") < hip_p and long_ratio < 2.6) else "gable"
        if "hip" in ov:
            rk = "hip" if ov["hip"] else "gable"
        if "pitch" in ov:
            pitch = math.radians(ov["pitch"])
        ytop = eave
        for R in rects:
            ytop = max(ytop, roof_rect(M, R, rects, eave, pitch, rk, lambda P: rot(P, ang, cen), rl, rtint, wl, wtint, ground=gmin))
        if kind in ("maison", "collectif") and rnd(key, "ch") < 0.75:
            chimney(M, main, eave, pitch, lambda P: rot(P, ang, cen), key, wl if wall != "bardage_bois" else IDX["crepi"], wtint)
    # collisions : prisme de l'emprise
    V, T = tri_polygon(foot)
    n = len(V)
    Pc = np.r_[np.c_[V[:, 0], np.full(n, base), V[:, 1]], np.c_[V[:, 0], np.full(n, ytop), V[:, 1]]]
    It = list(T + n)
    ring_i = []
    for k in range(len(ringw) - 1):
        a = np.argmin(np.hypot(V[:, 0] - ringw[k, 0], V[:, 1] - ringw[k, 1]))
        b = np.argmin(np.hypot(V[:, 0] - ringw[k + 1, 0], V[:, 1] - ringw[k + 1, 1]))
        It += [a, b, b + n, a, b + n, a + n]
    C.append((Pc, np.array(It, np.uint32)))
    return dict(kind=kind, foot=foot, eave=eave, ytop=ytop, base=base, gmin=gmin, gmax=gmax, street=street,
                ring=ringw, ground=gw, flat=flat, wall=wl, wtint=wtint)


def _col_prism(C, p, g, dem):
    """Collision de secours : prisme de l'emprise, du sol à la hauteur BD TOPO (8 m à défaut)."""
    try:
        foot = shapely.geometry.polygon.orient(shapely.simplify(g, 0.3), 1.0)
        V, T = tri_polygon(foot)
    except Exception:
        return
    ring = np.asarray(foot.exterior.coords)
    base = float(dem.h(ring[:, 0], ring[:, 1]).min()) - 0.5
    top = base + 0.5 + float(p.get("hauteur") or 8.0)
    n = len(V)
    Pc = np.r_[np.c_[V[:, 0], np.full(n, base), V[:, 1]], np.c_[V[:, 0], np.full(n, top), V[:, 1]]]
    It = list(np.asarray(T) + n)
    for k in range(len(ring) - 1):
        a = int(np.argmin(np.hypot(V[:, 0] - ring[k, 0], V[:, 1] - ring[k, 1])))
        b = int(np.argmin(np.hypot(V[:, 0] - ring[k + 1, 0], V[:, 1] - ring[k + 1, 1])))
        It += [a, b, b + n, a, b + n, a + n]
    C.append((Pc, np.array(It, np.uint32)))


def main():
    shutil.rmtree(OUT, ignore_errors=True); os.makedirs(OUT)
    dem = CarvedDEM()
    ortho = Ortho()
    blds = load()
    print(len(blds), "bâtiments dans la zone")
    lim = os.environ.get("BLD_BOX")
    if lim:
        x0, z0, x1, z1 = map(float, lim.split(","))
        blds = [(p, g) for p, g in blds if x0 < g.centroid.x < x1 and z0 < g.centroid.y < z1]
    ways = pickle.load(open("data/roads.pkl", "rb"))["ways"]
    rp = np.vstack([w["P"] for w in ways if w["cls"] not in ("track",)])
    road_tree = cKDTree(rp)
    # rien sur la chaussée : emprise découpée au bord de la route (décalage OSM / BD TOPO), supprimée si trop rognée
    from shapely.geometry import LineString
    from shapely.ops import unary_union
    rbuf = [LineString(w["P"]).buffer(w["w"] / 2 + 0.3, cap_style="flat") for w in ways if len(w["P"]) > 1 and not w["bridge"]]
    rtr = STRtree(rbuf)
    kept, cut, dropped = [], 0, 0
    for p, g in blds:
        hits = [rbuf[k] for k in rtr.query(g) if rbuf[k].intersects(g)]
        if hits:
            inter = g.intersection(unary_union(hits))
            if inter.area > 0.3:
                g2 = g.difference(unary_union(hits))
                parts = [q for q in getattr(g2, "geoms", [g2]) if q.geom_type == "Polygon"]
                g2 = max(parts, key=lambda q: q.area) if parts else None
                if g2 is None or g2.area < 0.6 * g.area or g2.area < 12:
                    dropped += 1
                    continue
                g = g2; cut += 1
        kept.append((p, g))
    blds = kept
    print("chaussées : %d bâtiments découpés, %d supprimés" % (cut, dropped))
    polys = [g for _, g in blds]
    tree = STRtree(polys)
    tiles = {}
    stats = {}
    # bâtiments emblématiques : modèles dédiés (remplacent les bâtiments BD TOPO recouverts) et habillages
    import landmarks
    LM = landmarks.Landmarks(polys, blds, road_tree, dem)
    for kind, n in LM.build(tiles, TILE, Mesh).items():
        stats["monument:" + kind] = n
    for i, (p, g) in enumerate(blds):
        c = g.centroid
        key = (int(c.x // TILE), int(c.y // TILE))
        M, C = tiles.setdefault(key, (Mesh(), []))
        nc = len(C)
        if i in LM.replaced:
            _col_prism(C, p, g, dem)
            continue
        nL = len(M.L)
        try:
            info = build_one(M, C, p, g, dem, ortho, road_tree, rp, tree, polys, i, LM.override.get(i))
            if info:
                # sol du bâtiment (UV2.y) : le shader assombrit le pied des murs (ombre douce)
                for a in M.L[nL:]:
                    a[:, 1] = info["gmin"]
            k = info["kind"] if info else None
            if info and i in LM.override:
                LM.extras(M, C, i, info)
                k = "habillé:" + LM.override[i].get("label", "?")
        except Exception as e:
            k = "erreur"
            if stats.get("erreur", 0) < 3:
                import traceback; traceback.print_exc()
        if len(C) == nc:
            _col_prism(C, p, g, dem)                 # aucun bâtiment sans collision
            stats["collision ajoutée"] = stats.get("collision ajoutée", 0) + 1
        stats[k] = stats.get(k, 0) + 1
        if i % 2000 == 0:
            print(i, stats)
    ntri = 0
    for (tx, tz), (M, C) in tiles.items():
        pr = M.prim("building")
        if pr is None:
            continue
        ntri += len(pr[4]) // 3
        Pc = []; Ic = []; off = 0
        for P, I in C:
            Pc.append(P); Ic.append(I + off); off += len(P)
        Pc = np.vstack(Pc).astype(np.float32); Ic = np.concatenate(Ic)
        col = ("collision", Pc, np.tile([0, 1, 0], (len(Pc), 1)), Pc[:, [0, 2]], Ic)
        write_glb("%s/b_%d_%d.glb" % (OUT, tx, tz), {"bld": [pr], "col": [col]})
    from collections import defaultdict
    KT = defaultdict(list)
    for r in KIT:
        KT[(int(math.floor(r[10] / TILE)), int(math.floor(r[12] / TILE)))].append(r)
    for (tx, tz), S in KT.items():
        open("%s/k_%d_%d.bin" % (OUT, tx, tz), "wb").write(np.int32(len(S)).tobytes() + np.array(S, "<f4").tobytes())
    print("kit :", {n: sum(1 for r in KIT if r[0] == i) for i, n in enumerate(KIT_MODELS)})
    json.dump(STAIRS, open("data/stairs.json", "w"))
    print("escaliers extérieurs :", len(STAIRS))
    print(len(tiles), "tuiles,", ntri, "triangles", stats)


if __name__ == "__main__":
    main()
