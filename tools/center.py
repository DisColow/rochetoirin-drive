"""Centre du village de Rochetoirin, reproduit d'après Google Street View (avril 2023).

Uniquement le cœur du village (église, place, mairie, médiathèque, salle des fêtes,
boulangerie, restaurant, parking de la rue de Ravette, cimetière). Ailleurs, le décor
reste généré automatiquement depuis la BD TOPO.

Ce qui a été relevé sur les vues :
  * église Saint-Étienne néo-gothique en moellons bruns et dorés, encadrements en pierre de
    taille claire, contreforts, baies en arc brisé, transept, chevet polygonal à l'ouest,
    clocher carré latéral (nord) avec horloge et baies géminées, haute flèche octogonale en ardoise ;
  * place en gravier stabilisé devant l'église : platanes taillés en têtard, monument aux
    morts (obélisque blanc), voitures garées le long de l'église ;
  * médiathèque (pignon à oculus, porte cintrée en bois, enseigne violette, jardinet, boîte
    aux lettres jaune, boîte à livres) et mairie (crépi saumon, grandes baies à encadrements
    blancs, drapeaux) ;
  * salle des fêtes basse à pignon à redents ;
  * boulangerie-pâtisserie (maison crème à volets bruns, devanture bordeaux) et restaurant
    « Le Rochetoirin » (façade rouge, stores), local technique blanc en béton ;
  * parking de la rue de Ravette en enrobé avec îlots plantés et bordures ;
  * lampadaires crème à vasque verte (« champignons ») au lieu des lanternes génériques ;
  * cimetière ceint de murs gris, tombes en granit, cyprès ; conteneurs de tri.

Le module est appelé par prepare_decor.py (bâtiments, sol, arbres) et prepare_street.py
(mobilier, voitures, platanes, cimetière, lampadaires).
"""
import json, math, os, random
import numpy as np
import mapbox_earcut as earcut
import shapely
from shapely.geometry import Polygon, Point, LineString
from shapely.ops import polygonize, unary_union
from geo import to_local

HERE = os.path.dirname(os.path.abspath(__file__))
RAISED = []      # surfaces surélevées franchissables (polygone, hauteur(x, z)) -> physique (surf.bin)
DATA = os.path.join(HERE, "data")

(M_PLAIN, M_WALL, M_INDUS, M_TILES, M_METAL, M_FLAT, M_WATER, M_CHURCH, M_STEEL, M_CABLE, M_GLASS,
 M_STREAM, M_PAVE, M_CURB, M_GRASS, M_SIGN, M_LIGHT, M_RUBBLE, M_CREPI) = range(19)

# zone concernée (m, repère local) et centre (devant la mairie)
AREA = Polygon([(-20, 330), (200, 330), (200, 560), (-20, 560)])
CENTER = (90.0, 440.0)

# atlas des panneaux 8 × 8 cases de 128 px : lignes 4-5 réservées au centre
SIGN_BAKERY, SIGN_RESTO, SIGN_MAIRIE, SIGN_MEDIA = (0, 4, 2), (2, 4, 2), (4, 4, 2), (6, 4, 2)
SIGN_CLOCK, SIGN_LOGO_R, SIGN_PARKING, SIGN_NOENTRY = (0, 5, 1), (1, 5, 1), (2, 5, 1), (3, 5, 1)

rng = random.Random(1907)
terrain = None
Mesh = None


def setup(t, mesh_cls):
    global terrain, Mesh
    terrain, Mesh = t, mesh_cls


def sign_uv(cell):
    c, r, w = cell
    return c / 8.0, r / 8.0, (c + w) / 8.0, (r + 1) / 8.0


def H(x, z):
    return float(terrain.height(x, z))


def nrm(v):
    v = np.asarray(v, dtype=float)
    l = np.linalg.norm(v)
    return v / l if l > 1e-9 else np.array([0.0, 1.0, 0.0])


def in_area(x, z):
    return AREA.contains(Point(x, z))


# ----------------------------------------------------------------------------------- primitives
def poly3(m, pts, n, col, mat, uvs=None, extra=0.0):
    """Polygone plan (convexe ou non) en 3D ; uvs facultatives."""
    pts = [np.asarray(p, float) for p in pts]
    n = nrm(n)
    # triangulation dans le plan
    t1 = nrm(pts[1] - pts[0]); t2 = np.cross(n, t1)
    flat = np.array([[np.dot(p - pts[0], t1), np.dot(p - pts[0], t2)] for p in pts])
    tri = earcut.triangulate_float64(flat, np.array([len(flat)], dtype=np.uint32))
    ids = [m.vert(tuple(p), tuple(n), col, tuple(uvs[k]) if uvs is not None else (0, 0), mat, extra)
           for k, p in enumerate(pts)]
    for k in range(0, len(tri), 3):
        m.tri(ids[tri[k]], ids[tri[k + 1]], ids[tri[k + 2]])


def quad3(m, a, b, c, d, col, mat, uv=None, extra=0.0, n=None):
    a, b, c, d = (np.asarray(p, float) for p in (a, b, c, d))
    if n is None:
        n = nrm(np.cross(b - a, d - a))
    ids = [m.vert(tuple(p), tuple(n), col, uv[k] if uv else (0, 0), mat, extra) for k, p in enumerate((a, b, c, d))]
    m.quad(*ids)


def obox(m, c, ax, size, col, mat, extra=0.0, uvscale=True):
    """Boîte orientée : centre c (3D), axe horizontal ax (x,z), tailles (long, haut, large)."""
    ax = nrm([ax[0], 0, ax[1]]); bx = np.array([-ax[2], 0, ax[0]]); up = np.array([0, 1.0, 0])
    c = np.asarray(c, float)
    hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
    for n, (u, v), (su, sv) in ((ax, (bx, up), (hz, hy)), (-ax, (-bx, up), (hz, hy)), (bx, (-ax, up), (hx, hy)),
                                (-bx, (ax, up), (hx, hy)), (up, (ax, bx), (hx, hz)), (-up, (ax, -bx), (hx, hz))):
        d = {tuple(ax): hx, tuple(-ax): hx, tuple(bx): hz, tuple(-bx): hz, tuple(up): hy, tuple(-up): hy}[tuple(n)]
        o = c + n * d
        pts = [o - u * su - v * sv, o + u * su - v * sv, o + u * su + v * sv, o - u * su + v * sv]
        uv = [(-su, -sv), (su, -sv), (su, sv), (-su, sv)] if uvscale else None
        if uv:
            # coordonnées murales en mètres (horizontale, hauteur absolue relative au bas de la boîte)
            uv = [(float(np.dot(p, u)), float(p[1] - (c[1] - hy))) if abs(n[1]) < 0.5 else (float(p[0]), float(p[2])) for p in pts]
        quad3(m, *pts, col, mat, uv, extra, n=n)


def prism(m, x, y0, y1, z, r0, r1, sides, col, mat, rot=0.0, cap=True, extra=0.0):
    """Tronc de cône / prisme vertical à [sides] faces."""
    ring = []
    for k in range(sides + 1):
        a = rot + 2 * math.pi * k / sides
        ring.append((math.cos(a), math.sin(a), a))
    for k in range(sides):
        c0, s0, a0 = ring[k]; c1, s1, a1 = ring[k + 1]
        am = (a0 + a1) / 2
        n = (math.cos(am), (r0 - r1) / max(y1 - y0, 0.01), math.sin(am))
        pts = [(x + c0 * r0, y0, z + s0 * r0), (x + c1 * r0, y0, z + s1 * r0), (x + c1 * r1, y1, z + s1 * r1), (x + c0 * r1, y1, z + s0 * r1)]
        uv = [(a0 * r0, 0), (a1 * r0, 0), (a1 * r0, y1 - y0), (a0 * r0, y1 - y0)]
        quad3(m, *pts, col, mat, uv, extra, n=n)
    if cap and r1 > 0.01:
        poly3(m, [(x + c * r1, y1, z + s * r1) for c, s, _ in ring[:-1]], (0, 1, 0), col, mat, extra=extra)


def blob(m, c, r, col, mat, squash=1.0):
    """Petite boule à facettes (octaèdre subdivisé une fois)."""
    c = np.asarray(c, float)
    V = [np.array(v, float) for v in ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1))]
    F = [(0, 2, 4), (4, 2, 1), (1, 2, 5), (5, 2, 0), (0, 4, 3), (4, 1, 3), (1, 5, 3), (5, 0, 3)]
    tris = []
    for a, b, d in F:
        A, B, D = V[a], V[b], V[d]
        ab, bd, da = nrm(A + B), nrm(B + D), nrm(D + A)
        tris += [(A, ab, da), (ab, B, bd), (da, bd, D), (ab, bd, da)]
    for t in tris:
        ids = [m.vert(tuple(c + p * r * np.array([1, squash, 1])), tuple(p), col, (0, 0), mat) for p in t]
        m.tri(*ids)


class Frame:
    """Repère horizontal : P(u, w) = o + a·u + b·w (a, b unitaires orthogonaux)."""

    def __init__(self, o, a, b=None):
        self.o = np.asarray(o, float)
        self.a = nrm([a[0], 0, a[1]])[[0, 2]]
        self.b = np.asarray(b, float) / np.linalg.norm(b) if b is not None else np.array([-self.a[1], self.a[0]])

    def xz(self, u, w):
        return self.o + self.a * u + self.b * w

    def P(self, u, w, y):
        q = self.xz(u, w)
        return np.array([q[0], y, q[1]])

    def dir(self, du, dw):
        return self.a * du + self.b * dw

    @staticmethod
    def from_poly(pts, long_axis=True):
        r = Polygon(pts).minimum_rotated_rectangle
        c = list(r.exterior.coords)[:4]
        e0 = np.subtract(c[1], c[0]); e1 = np.subtract(c[3], c[0])
        if (np.linalg.norm(e0) < np.linalg.norm(e1)) == long_axis:
            e0, e1 = e1, e0
        f = Frame(c[0], e0, e1)
        return f, float(np.linalg.norm(e0)), float(np.linalg.norm(e1))


class Wall:
    """Façade plane : x vers la droite vu de l'extérieur, y vers le haut, d vers l'extérieur."""

    def __init__(self, left, right, y0, inside):
        left = np.asarray(left, float); right = np.asarray(right, float)
        r = right - left
        self.L = float(np.linalg.norm(r)); self.r = r / self.L
        self.n = np.array([-self.r[1], self.r[0]])
        if np.dot(self.n, np.asarray(inside) - (left + right) / 2) > 0:   # mauvais côté : on inverse
            left, right = right, left
            self.r = -self.r; self.n = -self.n
        self.o = left; self.y0 = y0

    def P(self, x, y, d=0.0):
        q = self.o + self.r * x + self.n * d
        return np.array([q[0], self.y0 + y, q[1]])

    def N(self):
        return (self.n[0], 0.0, self.n[1])

    def poly(self, m, pts, d, col, mat, extra=0.0):
        poly3(m, [self.P(x, y, d) for x, y in pts], self.N(), col, mat, [(x, y) for x, y in pts], extra)

    def rect(self, m, x0, x1, y0, y1, d, col, mat, extra=0.0):
        self.poly(m, [(x0, y0), (x1, y0), (x1, y1), (x0, y1)], d, col, mat, extra)

    def box(self, m, x0, x1, y0, y1, d0, d1, col, mat, extra=0.0):
        c = self.P((x0 + x1) / 2, (y0 + y1) / 2, (d0 + d1) / 2)
        obox(m, c, self.r, (x1 - x0, y1 - y0, d1 - d0), col, mat, extra)

    def sign(self, m, x, y, w, h, cell, d=0.06):
        u0, v0, u1, v1 = sign_uv(cell)
        pts = [self.P(x - w / 2, y - h / 2, d), self.P(x + w / 2, y - h / 2, d), self.P(x + w / 2, y + h / 2, d), self.P(x - w / 2, y + h / 2, d)]
        ids = [m.vert(tuple(p), self.N(), (1, 1, 1), uv, M_SIGN, 0.0) for p, uv in zip(pts, ((u0, v1), (u1, v1), (u1, v0), (u0, v0)))]
        m.quad(*ids)


def arch_pts(x, y0, w, h, kind="pointed", seg=6):
    """Contour d'une baie : rectangle surmonté d'un arc brisé (équilatéral) ou plein cintre."""
    l, r = x - w / 2, x + w / 2
    if kind == "pointed":
        ys = y0 + h - w * 0.866
        pts = [(l, y0), (r, y0), (r, ys)]
        for k in range(1, seg):
            a = math.radians(60 * k / seg)
            pts.append((l + w * math.cos(a), ys + w * math.sin(a)))
        pts.append((x, ys + w * 0.866))
        for k in range(seg - 1, 0, -1):
            a = math.radians(60 * k / seg)
            pts.append((r - w * math.cos(a), ys + w * math.sin(a)))
        pts.append((l, ys))
    elif kind == "round":
        ys = y0 + h - w / 2
        pts = [(l, y0), (r, y0)]
        for k in range(seg * 2 + 1):
            a = math.pi * k / (seg * 2)
            pts.append((x + w / 2 * math.cos(a), ys + w / 2 * math.sin(a)))
    else:
        pts = [(l, y0), (r, y0), (r, y0 + h), (l, y0 + h)]
    return pts


def circle_pts(x, y, r, n=12):
    return [(x + r * math.cos(2 * math.pi * k / n), y + r * math.sin(2 * math.pi * k / n)) for k in range(n)]


def grow(pts, cx, cy, s):
    """Agrandit un contour autour de son centre (encadrement)."""
    return [(cx + (x - cx) * (1 + s / max(abs(x - cx), 0.3)) if abs(x - cx) > 1e-6 else x,
             cy + (y - cy) * (1 + s / max(abs(y - cy), 0.3)) if abs(y - cy) > 1e-6 else y) for x, y in pts]


GLASS = (0.10, 0.12, 0.15)


def window(wall, m, x, y0, w, h, kind="rect", surround=None, sw=0.18, glass=GLASS, frame=None, shutters=None, sill=True,
           depth=0.0, smat=M_PLAIN):
    """Baie complète : vitrage, encadrement saillant, appui, menuiseries, volets."""
    pts = arch_pts(x, y0, w, h, kind)
    if surround is not None:
        cx, cy = x, y0 + h / 2
        outer = arch_pts(x, y0 - sw, w + 2 * sw, h + 2 * sw, kind)
        wall.poly(m, outer, 0.025 + depth, surround, smat, 3000.0)
    wall.poly(m, pts, 0.04 + depth, glass, M_GLASS)
    if frame is not None:
        # meneau et traverse
        wall.rect(m, x - 0.035, x + 0.035, y0, y0 + h * (0.82 if kind != "rect" else 1.0), 0.05 + depth, frame, M_PLAIN)
        if kind == "rect" and h > 1.1:
            wall.rect(m, x - w / 2, x + w / 2, y0 + h * 0.68, y0 + h * 0.68 + 0.06, 0.05 + depth, frame, M_PLAIN)
        for xx in (x - w / 2, x + w / 2 - 0.06):
            wall.rect(m, xx, xx + 0.06, y0, y0 + (h if kind == "rect" else h - w * 0.6), 0.05 + depth, frame, M_PLAIN)
        if kind == "rect":
            wall.rect(m, x - w / 2, x + w / 2, y0 + h - 0.06, y0 + h, 0.05 + depth, frame, M_PLAIN)
    if sill:
        wall.box(m, x - w / 2 - 0.08, x + w / 2 + 0.08, y0 - 0.08, y0, 0.0, 0.12 + depth, surround or (0.8, 0.8, 0.78), smat, 3000.0)
    if shutters is not None:
        for s in (-1, 1):
            xa = x + s * (w / 2 + 0.03); xb = xa + s * w / 2
            wall.rect(m, min(xa, xb), max(xa, xb), y0, y0 + h, 0.07 + depth, shutters, M_PLAIN)
            # écharpes en Z
            wall.rect(m, min(xa, xb), max(xa, xb), y0 + h * 0.2, y0 + h * 0.2 + 0.08, 0.09 + depth, [c * 0.8 for c in shutters], M_PLAIN)
            wall.rect(m, min(xa, xb), max(xa, xb), y0 + h * 0.78, y0 + h * 0.78 + 0.08, 0.09 + depth, [c * 0.8 for c in shutters], M_PLAIN)


def door(wall, m, x, w, h, col, kind="rect", surround=None, sw=0.2, y0=0.0, smat=M_PLAIN):
    if surround is not None:
        wall.poly(m, arch_pts(x, y0, w + 2 * sw, h + sw, kind), 0.025, surround, smat, 3000.0)
    wall.poly(m, arch_pts(x, y0, w, h, kind), 0.045, col, M_PLAIN)
    # panneaux / lames verticales
    dark = [c * 0.75 for c in col]
    n = max(2, int(w / 0.35))
    for k in range(1, n):
        xx = x - w / 2 + w * k / n
        wall.rect(m, xx - 0.02, xx + 0.02, y0 + 0.05, y0 + h - (w * 0.5 if kind != "rect" else 0.05), 0.05, dark, M_PLAIN)


# ----------------------------------------------------------------------------------- toitures
def gable_body(m, F, u0, u1, w0, w1, y0, eave, ridge, wall_col, wall_mat, roof_col, axis="u", oh=0.45,
               ends=(True, True), wall_extra=3000.0, gable_mat=None):
    """Volume rectangulaire à toit à deux pans (faîtage le long de u ou de w).
    Renvoie les murs {'u0','u1','w0','w1'} (objets Wall) pour y accrocher des détails."""
    cu, cw = (u0 + u1) / 2, (w0 + w1) / 2
    inside = F.xz(cu, cw)
    C = {k: F.xz(*k) for k in ((u0, w0), (u1, w0), (u1, w1), (u0, w1))}
    walls = {"w0": Wall(C[(u0, w0)], C[(u1, w0)], y0, inside), "w1": Wall(C[(u1, w1)], C[(u0, w1)], y0, inside),
             "u0": Wall(C[(u0, w1)], C[(u0, w0)], y0, inside), "u1": Wall(C[(u1, w0)], C[(u1, w1)], y0, inside)}
    gm = gable_mat if gable_mat is not None else wall_mat
    for k, wl in walls.items():
        wl.rect(m, 0, wl.L, -1.2, eave - y0, 0, wall_col, wall_mat, wall_extra)
    # pignons
    gable_walls = ("u0", "u1") if axis == "u" else ("w0", "w1")
    for idx, k in enumerate(gable_walls):
        if not ends[idx]:
            continue
        wl = walls[k]
        wl.poly(m, [(0, eave - y0), (wl.L, eave - y0), (wl.L / 2, ridge - y0)], 0, wall_col, gm, wall_extra)
    # pans
    if axis == "u":
        half = (w1 - w0) / 2
        slope = (ridge - eave) / half
        lo = eave - oh * slope
        sides = [((u0 - oh, w0 - oh), (u1 + oh, w0 - oh), (u1 + oh, cw), (u0 - oh, cw)),
                 ((u1 + oh, w1 + oh), (u0 - oh, w1 + oh), (u0 - oh, cw), (u1 + oh, cw))]
    else:
        half = (u1 - u0) / 2
        slope = (ridge - eave) / half
        lo = eave - oh * slope
        sides = [((u0 - oh, w1 + oh), (u0 - oh, w0 - oh), (cu, w0 - oh), (cu, w1 + oh)),
                 ((u1 + oh, w0 - oh), (u1 + oh, w1 + oh), (cu, w1 + oh), (cu, w0 - oh))]
    for s in sides:
        pts = [F.P(*s[0], lo), F.P(*s[1], lo), F.P(*s[2], ridge), F.P(*s[3], ridge)]
        roof_plane(m, pts, roof_col)
    return walls


def roof_plane(m, pts, col, mat=M_TILES, under=(0.30, 0.24, 0.20), thick=0.18):
    """Pan de toiture (quadrilatère ou triangle) : tuiles dessus, sous-face sombre, rive."""
    pts = [np.asarray(p, float) for p in pts]
    n = nrm(np.cross(pts[1] - pts[0], pts[-1] - pts[0]))
    if n[1] < 0:
        n = -n
    edge = nrm(pts[1] - pts[0])
    uv = []
    for p in pts:
        d = p - pts[0]
        uv.append((float(np.dot(d, edge)), float(np.linalg.norm(d - edge * np.dot(d, edge)))))
    up = n * thick
    poly3(m, [p + up for p in pts], n, col, mat + 0.37, uv)
    poly3(m, pts, -n, under, M_PLAIN)
    # chant de la rive basse
    quad3(m, pts[0], pts[1], pts[1] + up, pts[0] + up, under, M_PLAIN)


def ridge_cap(m, a, b, col, w=0.22):
    a = np.asarray(a, float); b = np.asarray(b, float)
    d = b - a
    obox(m, (a + b) / 2 + np.array([0, 0.16, 0]), (d[0], d[2]), (np.linalg.norm(d), 0.14, w), col, M_TILES + 0.37)


def pyramid(m, base, apex, col, mat=M_TILES, extra=0.0):
    """Faces latérales d'une pyramide (base = polygone 3D)."""
    apex = np.asarray(apex, float)
    for k in range(len(base)):
        a = np.asarray(base[k], float); b = np.asarray(base[(k + 1) % len(base)], float)
        n = nrm(np.cross(b - a, apex - a))
        c = (a + b) / 2
        if np.dot(n, c - np.mean(base, axis=0)) < 0:
            n = -n
        L = np.linalg.norm(b - a)
        ids = [m.vert(tuple(p), tuple(n), col, uv, mat + 0.21, extra) for p, uv in
               ((a, (0, 0)), (b, (L, 0)), (apex, (L / 2, np.linalg.norm(apex - c))))]
        m.tri(*ids)


def cross(m, c, h, col=(0.18, 0.18, 0.19), ax=(1, 0)):
    obox(m, (c[0], c[1] + h / 2, c[2]), ax, (0.12, h, 0.12), col, M_STEEL)
    obox(m, (c[0], c[1] + h * 0.68, c[2]), ax, (h * 0.5, 0.11, 0.11), col, M_STEEL)


# ----------------------------------------------------------------------------------- église
RUBBLE = (0.5, 0.5, 0.5)            # teinte neutre : la couleur vient du shader des moellons
DRESS = (0.74, 0.65, 0.50)          # pierre de taille claire (encadrements, chaînages)
CH_ROOF = (0.56, 0.34, 0.26)
SLATE = (0.27, 0.29, 0.33)


def church():
    """Église Saint-Étienne. Repère : u le long de la nef (ouest → est), w vers le nord."""
    m = Mesh()
    a = np.array([31.5, 8.2]); a /= np.linalg.norm(a)
    F = Frame((102.2, 473.3), a, (a[1], -a[0]))
    foot = [F.xz(u, w) for u, w in ((0, -1.8), (15.6, -6.6), (31.8, -3.1), (31.8, 6.4), (15.7, 11.2), (3.8, 11.2), (0, 5.8))]
    g = min(H(x, z) for x, z in foot)
    y0 = g
    Y = lambda h: g + h

    # nef (3 travées), transept, chœur, chapelle sud, chevet polygonal
    nave = gable_body(m, F, 15.5, 31.8, -3.1, 6.4, y0, Y(9.0), Y(13.8), RUBBLE, M_RUBBLE, CH_ROOF, "u", ends=(False, True))
    tr = gable_body(m, F, 9.6, 15.5, -6.6, 11.2, y0, Y(9.0), Y(12.6), RUBBLE, M_RUBBLE, CH_ROOF, "w")
    choir = gable_body(m, F, 3.7, 9.6, -3.1, 6.4, y0, Y(8.0), Y(12.2), RUBBLE, M_RUBBLE, CH_ROOF, "u", ends=(False, False))
    gable_body(m, F, 3.6, 9.6, -6.6, -3.1, y0, Y(5.2), Y(6.8), RUBBLE, M_RUBBLE, CH_ROOF, "u", oh=0.3)
    ridge_cap(m, F.P(15.5, 1.65, Y(13.8)), F.P(32.2, 1.65, Y(13.8)), CH_ROOF)
    ridge_cap(m, F.P(12.55, -7.0, Y(12.6)), F.P(12.55, 11.6, Y(12.6)), CH_ROOF)
    # chevet : demi-octogone aplati
    cu, cw, R = 3.7, 1.65, 4.75
    ring = []
    for k in range(5):
        ang = math.pi / 2 + k * math.pi / 4
        ring.append((cu + math.cos(ang) * R * 3.7 / 4.75, cw + math.sin(ang) * R))
    inside = F.xz(cu + 1, cw)
    for k in range(4):
        wl = Wall(F.xz(*ring[k]), F.xz(*ring[k + 1]), y0, inside)
        wl.rect(m, 0, wl.L, -0.6, Y(8.0) - y0, 0, RUBBLE, M_RUBBLE)
        window(wl, m, wl.L / 2, Y(3.2) - y0, 0.8, 3.0, "pointed", DRESS, 0.2, smat=M_CHURCH)
        # contrefort d'angle
        if k > 0:
            wl.box(m, -0.35, 0.35, -0.5, Y(5.5) - y0, 0, 0.8, DRESS, M_CHURCH, 3000.0)
    oh = 0.45
    eave_ring = [F.P(cu + math.cos(math.pi / 2 + k * math.pi / 4) * (R + oh) * 3.7 / 4.75,
                     cw + math.sin(math.pi / 2 + k * math.pi / 4) * (R + oh), Y(8.0) - oh * 0.9) for k in range(5)]
    apex = F.P(cu, cw, Y(12.2))
    for k in range(4):
        roof_plane(m, [eave_ring[k], eave_ring[k + 1], apex], CH_ROOF)

    # contreforts et baies de la nef (nord w=6.4, sud w=-3.1)
    for side, wl in (("n", nave["w1"]), ("s", nave["w0"])):
        # position x le long du mur : le mur w1 va de u1 à u0 (vu de l'extérieur)
        def X(u):
            p = F.xz(u, 6.4 if side == "n" else -3.1)
            return float(np.dot(p - wl.o, wl.r))
        for u in (15.9, 21.0, 26.4, 31.4):
            x = X(u)
            wl.box(m, x - 0.45, x + 0.45, -0.5, Y(5.2) - y0, 0, 0.95, RUBBLE, M_RUBBLE)
            wl.box(m, x - 0.40, x + 0.40, Y(5.2) - y0, Y(7.6) - y0, 0, 0.55, RUBBLE, M_RUBBLE)
            wl.box(m, x - 0.5, x + 0.5, Y(5.1) - y0, Y(5.35) - y0, 0, 1.05, DRESS, M_CHURCH, 3000.0)
            wl.box(m, x - 0.45, x + 0.45, Y(7.5) - y0, Y(7.7) - y0, 0, 0.65, DRESS, M_CHURCH, 3000.0)
        for u in (18.45, 23.7, 28.9):
            window(wl, m, X(u), Y(3.9) - y0, 1.0, 3.5, "pointed", DRESS, 0.22, smat=M_CHURCH)
        # bandeau sous la corniche
        wl.box(m, 0, wl.L, Y(8.85) - y0, Y(9.05) - y0, 0, 0.12, DRESS, M_CHURCH, 3000.0)
        wl.box(m, 0, wl.L, -0.6, Y(0.7) - y0, 0, 0.1, RUBBLE, M_RUBBLE)

    # façade est : portail en arc brisé, oculus, croix de pignon
    fe = nave["u1"]
    xm = fe.L / 2
    fe.box(m, xm - 1.6, xm + 1.6, -0.5, Y(5.2) - y0, 0, 0.35, RUBBLE, M_RUBBLE)
    fe.poly(m, arch_pts(xm, Y(0) - y0, 3.0, 4.9, "pointed"), 0.36, DRESS, M_CHURCH, 3000.0)
    fe.poly(m, arch_pts(xm, Y(0) - y0, 2.4, 4.4, "pointed"), 0.38, (0.36, 0.33, 0.30), M_CHURCH, 3000.0)
    door(fe, m, xm, 1.8, 3.4, (0.33, 0.21, 0.14), "pointed", None, y0=Y(0) - y0 + 0.0)
    for x in (0.0, fe.L):
        fe.box(m, x - 0.5, x + 0.5, -0.5, Y(7.0) - y0, -0.3, 0.7, RUBBLE, M_RUBBLE)
    fe.poly(m, circle_pts(xm, Y(8.6) - y0, 1.25, 16), 0.03, DRESS, M_CHURCH, 3000.0)
    fe.poly(m, circle_pts(xm, Y(8.6) - y0, 0.95, 16), 0.05, GLASS, M_GLASS)
    for k in range(6):   # remplage de la rose
        a0 = math.pi * k / 6
        p = [(xm + math.cos(a0) * 0.95, Y(8.6) - y0 + math.sin(a0) * 0.95), (xm - math.cos(a0) * 0.95, Y(8.6) - y0 - math.sin(a0) * 0.95)]
        d = np.subtract(p[1], p[0]); nn = np.array([-d[1], d[0]]) / np.linalg.norm(d) * 0.04
        fe.poly(m, [tuple(p[0] - nn), tuple(p[1] - nn), tuple(p[1] + nn), tuple(p[0] + nn)], 0.06, DRESS, M_CHURCH, 3000.0)
    fe.box(m, xm - 0.15, xm + 0.15, Y(4.85) - y0, Y(4.95) - y0, 0, 0.5, DRESS, M_CHURCH, 3000.0)
    cross(m, F.P(32.0, 1.65, Y(13.8)), 1.6, DRESS)
    # pignon du transept : baies géminées nord et sud
    for k in ("w0", "w1"):
        wl = tr[k]
        for dx in (-0.65, 0.65):
            window(wl, m, wl.L / 2 + dx, Y(3.6) - y0, 0.75, 3.6, "pointed", DRESS, 0.18, smat=M_CHURCH)
        wl.poly(m, circle_pts(wl.L / 2, Y(9.4) - y0, 0.55, 12), 0.03, DRESS, M_CHURCH, 3000.0)
        wl.poly(m, circle_pts(wl.L / 2, Y(9.4) - y0, 0.38, 12), 0.05, GLASS, M_GLASS)
        for x in (0.0, wl.L):
            wl.box(m, x - 0.4, x + 0.4, -0.5, Y(6.0) - y0, -0.2, 0.6, RUBBLE, M_RUBBLE)
    cross(m, F.P(12.55, 11.4, Y(12.6)), 1.1, DRESS)
    cross(m, F.P(12.55, -6.8, Y(12.6)), 1.1, DRESS)
    # baies du chœur côté sud (au-dessus de la sacristie) et chapelle
    for u in (5.2, 8.0):
        wl = choir["w0"]
        x = float(np.dot(F.xz(u, -3.1) - wl.o, wl.r))
        window(wl, m, x, Y(5.6) - y0, 0.6, 2.0, "pointed", DRESS, 0.15, smat=M_CHURCH)

    # ------------------------------------------------------------ clocher (nord, entre chevet et transept)
    t0u, t1u, t0w, t1w = 4.0, 9.6, 5.7, 11.3
    top = Y(21.5)
    tc = (F.xz(t0u, t0w), F.xz(t1u, t0w), F.xz(t1u, t1w), F.xz(t0u, t1w))
    tin = F.xz((t0u + t1u) / 2, (t0w + t1w) / 2)
    tws = [Wall(tc[k], tc[(k + 1) % 4], y0, tin) for k in range(4)]
    for wl in tws:
        wl.rect(m, 0, wl.L, -0.6, top - y0, 0, RUBBLE, M_RUBBLE)
        L = wl.L
        # chaînages d'angle et contreforts
        for x in (0.0, L):
            wl.box(m, x - 0.55 if x > 0 else -0.05, x + 0.05 if x > 0 else 0.55, -0.5, Y(14.5) - y0, 0, 0.55, RUBBLE, M_RUBBLE)
            wl.box(m, x - 0.6 if x > 0 else 0.0, x if x > 0 else 0.6, Y(14.3) - y0, Y(14.6) - y0, 0, 0.62, DRESS, M_CHURCH, 3000.0)
        # cordons
        for h in (4.2, 9.6, 14.6):
            wl.box(m, 0, L, Y(h) - y0, Y(h + 0.22) - y0, 0, 0.14, DRESS, M_CHURCH, 3000.0)
        wl.box(m, -0.2, L + 0.2, top - y0 - 0.35, top - y0, 0, 0.3, DRESS, M_CHURCH, 3000.0)
        # meurtrières, baie du 1er niveau
        wl.poly(m, arch_pts(L / 2, Y(6.2) - y0, 0.35, 2.0, "pointed"), 0.04, GLASS, M_GLASS)
        wl.poly(m, arch_pts(L / 2, Y(6.0) - y0, 0.65, 2.4, "pointed"), 0.02, DRESS, M_CHURCH, 3000.0)
        window(wl, m, L / 2, Y(10.8) - y0, 0.6, 2.4, "pointed", DRESS, 0.15, smat=M_CHURCH)
        # beffroi : baies géminées à abat-sons
        for dx in (-0.55, 0.55):
            window(wl, m, L / 2 + dx, Y(15.6) - y0, 0.62, 3.2, "pointed", DRESS, 0.16, glass=(0.07, 0.07, 0.08), smat=M_CHURCH)
            for k in range(5):
                yy = Y(15.9) - y0 + k * 0.45
                wl.box(m, L / 2 + dx - 0.3, L / 2 + dx + 0.3, yy, yy + 0.06, 0.02, 0.12, (0.30, 0.27, 0.24), M_PLAIN)
        # horloge
        wl.poly(m, circle_pts(L / 2, Y(20.0) - y0, 0.75, 16), 0.03, DRESS, M_CHURCH, 3000.0)
        wl.sign(m, L / 2, Y(20.0) - y0, 1.2, 1.2, SIGN_CLOCK, 0.06)
    # flèche octogonale en ardoise
    cxz = tin
    rt = 2.75
    oct_ = [np.array([cxz[0] + math.cos(math.pi / 8 + k * math.pi / 4 + math.atan2(a[1], a[0])) * rt, top + 0.05,
                      cxz[1] + math.sin(math.pi / 8 + k * math.pi / 4 + math.atan2(a[1], a[0])) * rt]) for k in range(8)]
    tip = np.array([cxz[0], Y(38.0), cxz[1]])
    pyramid(m, oct_, tip, SLATE)
    # lucarnes de la flèche (une par face principale)
    for k in range(4):
        d = F.dir(*((1, 0), (0, 1), (-1, 0), (0, -1))[k])
        p = cxz + d * 2.3
        side = np.array([-d[1], d[0]])
        y = top + 1.2
        A = np.array([p[0] - side[0] * 0.6, y, p[1] - side[1] * 0.6]); B = np.array([p[0] + side[0] * 0.6, y, p[1] + side[1] * 0.6])
        T = np.array([p[0], y + 1.6, p[1]])
        n3 = (d[0], 0, d[1])
        poly3(m, [A + [d[0] * 0.3, 0, d[1] * 0.3], B + [d[0] * 0.3, 0, d[1] * 0.3], T + [d[0] * 0.3, 0, d[1] * 0.3]], n3, DRESS, M_CHURCH, extra=3000.0)
        poly3(m, [A + [d[0] * 0.32, 0.2, d[1] * 0.32] * np.array([1, 1, 1]), B + [d[0] * 0.32, 0.2, d[1] * 0.32], (A + B) / 2 + [d[0] * 0.32, 1.1, d[1] * 0.32]], n3, (0.08, 0.08, 0.09), M_PLAIN)
        back = np.array([cxz[0], y + 2.2, cxz[1]])
        for E in (A, B):
            nn = nrm(np.cross(T - E, back - E))
            if nn[1] < 0:
                nn = -nn
            poly3(m, [E + [d[0] * 0.35, 0, d[1] * 0.35], T + [d[0] * 0.35, 0.1, d[1] * 0.35], back], nn, SLATE, M_TILES + 0.21)
    # clochetons d'angle
    for k in range(4):
        q = tc[k] + (np.asarray(tin) - tc[k]) * 0.06
        obox(m, (q[0], top + 0.45, q[1]), a, (0.55, 0.9, 0.55), DRESS, M_CHURCH, 3000.0)
        b4 = [np.array([q[0] + dx, top + 0.9, q[1] + dz]) for dx, dz in ((-0.3, -0.3), (0.3, -0.3), (0.3, 0.3), (-0.3, 0.3))]
        pyramid(m, b4, (q[0], top + 2.4, q[1]), DRESS, M_CHURCH, 3000.0)
    cross(m, tip - [0, 0.2, 0], 2.2, (0.15, 0.15, 0.15))
    obox(m, tip + [0, 0.1, 0], a, (0.22, 0.22, 0.22), (0.62, 0.52, 0.25), M_STEEL)
    c = F.xz(16, 2)
    return [(c[0], c[1], m, True)]


# ----------------------------------------------------------------------------------- bâtiments civils
CREPI_CREAM = (0.89, 0.83, 0.70)
CREPI_SALMON = (0.90, 0.75, 0.62)
TILE_RED = (0.66, 0.37, 0.26)
WHITE_SURR = (0.93, 0.92, 0.88)
WOOD = (0.40, 0.25, 0.15)


def front_wall(walls, roads_union):
    """Façade la plus proche d'une rue."""
    best, bd = None, 1e9
    for k, wl in walls.items():
        mid = wl.o + wl.r * wl.L / 2 + wl.n * 0.5
        d = roads_union.distance(Point(*mid))
        if d < bd:
            best, bd = k, d
    return best


def quoins(wl, m, top, col=WHITE_SURR):
    for x in (0.0, wl.L):
        for k in range(int(top / 0.6)):
            w = 0.45 if k % 2 == 0 else 0.28
            x0, x1 = (x, x + w) if x == 0.0 else (x - w, x)
            wl.box(m, x0, x1, k * 0.6, k * 0.6 + 0.56, 0, 0.03, col, M_CHURCH, 3000.0)


def mediatheque(roads_union):
    m = Mesh()
    F, L, W = Frame.from_poly([(84.5, 421.8), (97.5, 426.6), (94.7, 435.3), (81.8, 431.0)])
    pts = [F.xz(u, w) for u in (0, L) for w in (0, W)]
    g = min(H(x, z) for x, z in pts)
    y0 = g
    walls = gable_body(m, F, 0, L, 0, W, y0, g + 6.0, g + 9.4, CREPI_CREAM, M_CREPI, TILE_RED, "u", oh=0.6)
    ridge_cap(m, F.P(-0.6, W / 2, g + 9.4), F.P(L + 0.6, W / 2, g + 9.4), TILE_RED)
    # pignon côté route (le plus à l'est)
    ge = max(("u0", "u1"), key=lambda k: (walls[k].o + walls[k].r * walls[k].L / 2)[0])
    wl = walls[ge]
    x = wl.L / 2
    for k in ("u0", "u1", "w0", "w1"):
        quoins(walls[k], m, 6.6)
        walls[k].box(m, 0, walls[k].L, -0.5, 0.5, -0.0, 0.04, (0.72, 0.66, 0.56), M_CREPI)   # soubassement
    door(wl, m, x, 1.5, 2.9, (0.45, 0.28, 0.16), "round", (0.80, 0.74, 0.62), 0.25, y0=0.0, smat=M_CHURCH)
    wl.sign(m, x, 3.75, 2.8, 0.7, SIGN_MEDIA, 0.06)
    for dx in (-2.6, 2.6):
        window(wl, m, x + dx, 0.9, 1.0, 1.5, "rect", WHITE_SURR, 0.14, frame=(0.92, 0.92, 0.9))
        window(wl, m, x + dx, 4.0, 0.9, 1.3, "rect", WHITE_SURR, 0.14, frame=(0.92, 0.92, 0.9))
    wl.poly(m, circle_pts(x, 7.4, 0.62, 16), 0.03, WHITE_SURR, M_CHURCH, 3000.0)
    wl.poly(m, circle_pts(x, 7.4, 0.42, 16), 0.05, GLASS, M_GLASS)
    for k in ("w0", "w1"):
        wl2 = walls[k]
        for j in range(3):
            xx = wl2.L * (j + 0.5) / 3
            window(wl2, m, xx, 0.9, 1.0, 1.5, "rect", WHITE_SURR, 0.14, frame=(0.92, 0.92, 0.9))
            window(wl2, m, xx, 4.0, 0.9, 1.2, "rect", WHITE_SURR, 0.14, frame=(0.92, 0.92, 0.9))
    c = F.xz(L / 2, W / 2)
    return [(c[0], c[1], m, True)], (wl, F)


def mairie(roads_union):
    m = Mesh()
    F, L, W = Frame.from_poly([(69.7, 419.4), (84.4, 424.2), (81.4, 433.4), (66.6, 429.2)])
    pts = [F.xz(u, w) for u in (0, L) for w in (0, W)]
    g = min(H(x, z) for x, z in pts)
    y0 = g
    walls = gable_body(m, F, 0, L, 0, W, y0, g + 6.6, g + 9.8, CREPI_SALMON, M_CREPI, TILE_RED, "u", oh=0.55)
    ridge_cap(m, F.P(-0.55, W / 2, g + 9.8), F.P(L + 0.55, W / 2, g + 9.8), TILE_RED)
    fk = front_wall({k: walls[k] for k in ("w0", "w1")}, roads_union)
    wl = walls[fk]
    for k in walls:
        quoins(walls[k], m, 7.2)
        walls[k].box(m, 0, walls[k].L, -0.5, 0.5, 0, 0.04, (0.74, 0.64, 0.54), M_CREPI)
        walls[k].box(m, 0, walls[k].L, 3.25, 3.4, 0, 0.06, WHITE_SURR, M_CHURCH, 3000.0)   # bandeau d'étage
    x = wl.L / 2
    n = 5
    for j in range(n):
        xx = wl.L * (j + 0.5) / n
        if j == n // 2:
            door(wl, m, xx, 1.6, 2.8, WOOD, "rect", WHITE_SURR, 0.18, y0=0.0)
            # marquise vitrée triangulaire au-dessus de l'entrée
            wl.box(m, xx - 1.4, xx + 1.4, 2.95, 3.05, 0, 1.3, (0.30, 0.30, 0.32), M_STEEL)
            wl.box(m, xx - 1.3, xx + 1.3, 3.05, 3.12, 0.05, 1.25, (0.55, 0.70, 0.75), M_GLASS)
            wl.sign(m, xx, 6.25, 2.6, 0.62, SIGN_MAIRIE, 0.06)
        else:
            window(wl, m, xx, 0.8, 1.25, 2.0, "rect", WHITE_SURR, 0.18, frame=WOOD)
        window(wl, m, xx, 4.0, 1.15, 1.6, "rect", WHITE_SURR, 0.18, frame=WOOD)
    # drapeaux tricolore et européen sur hampes inclinées
    for s, kind in ((-1, "fr"), (1, "eu")):
        xx = x + s * 2.0
        base = wl.P(xx, 5.45, 0.1)
        d3 = np.array([wl.n[0], 0, wl.n[1]])
        tipp = base + d3 * 1.6 + np.array([0, 1.0, 0])
        q = tipp - base
        obox(m, (base + tipp) / 2, (q[0], q[2]), (np.linalg.norm(q), 0.04, 0.04), (0.85, 0.85, 0.85), M_STEEL)
        # le drapeau pend sous la hampe (plan vertical contenant la hampe)
        rr = np.array([wl.r[0], 0, wl.r[1]])
        cols = [(0.0, 0.20, 0.60), (0.95, 0.95, 0.95), (0.85, 0.10, 0.15)] if kind == "fr" else [(0.0, 0.20, 0.58)] * 3
        for k in range(3):
            a0 = base + q * (0.35 + 0.2 * k); a1 = base + q * (0.35 + 0.2 * (k + 1))
            quad3(m, a0, a1, a1 - [0, 0.85, 0], a0 - [0, 0.85, 0], cols[k], M_PLAIN, n=tuple(rr))
        if kind == "eu":
            mid = base + q * 0.65 - np.array([0, 0.42, 0])
            for k in range(12):
                ang = 2 * math.pi * k / 12
                p = mid + d3 * 0.25 * math.cos(ang) + np.array([0, 0.25 * math.sin(ang), 0]) + rr * 0.012
                obox(m, p, (d3[0], d3[2]), (0.05, 0.05, 0.05), (0.95, 0.85, 0.1), M_PLAIN)
    # pignons : oculus
    for k in ("u0", "u1"):
        w2 = walls[k]
        w2.poly(m, circle_pts(w2.L / 2, 7.9, 0.55, 16), 0.03, WHITE_SURR, M_CHURCH, 3000.0)
        w2.poly(m, circle_pts(w2.L / 2, 7.9, 0.38, 16), 0.05, GLASS, M_GLASS)
        for j in (0.3, 0.7):
            window(w2, m, w2.L * j, 0.8, 1.1, 1.8, "rect", WHITE_SURR, 0.18, frame=WOOD)
            window(w2, m, w2.L * j, 4.0, 1.0, 1.5, "rect", WHITE_SURR, 0.18, frame=WOOD)
    # façade arrière
    wb = walls["w1" if fk == "w0" else "w0"]
    for j in range(4):
        window(wb, m, wb.L * (j + 0.5) / 4, 0.8, 1.1, 1.7, "rect", WHITE_SURR, 0.16, frame=WOOD)
        window(wb, m, wb.L * (j + 0.5) / 4, 4.0, 1.0, 1.5, "rect", WHITE_SURR, 0.16, frame=WOOD)
    c = F.xz(L / 2, W / 2)
    return [(c[0], c[1], m, True)]


def stepped_gable(wl, m, eave, ridge, col, steps=4):
    """Pignon à redents dépassant de la toiture."""
    L = wl.L
    left = [(0.0, eave)]
    for k in range(steps):
        y = eave + (ridge - eave) * (k + 1) / steps + 0.45
        left += [(L / 2 * k / steps, y), (L / 2 * (k + 1) / steps, y)]
    right = [(L - x, y) for x, y in reversed(left)]
    outline = left + right[1:]
    for d in (-0.3, 0.0):
        wl.poly(m, outline, d, col, M_CREPI)
    for k in range(steps):
        x0 = L / 2 * k / steps; x1 = L / 2 * (k + 1) / steps
        y = eave + (ridge - eave) * (k + 1) / steps + 0.45
        for xa, xb in ((x0, x1), (L - x1, L - x0)):
            wl.box(m, xa - 0.05, xb + 0.05, y, y + 0.08, -0.36, 0.06, (0.62, 0.60, 0.56), M_CURB)


def salle_des_fetes(roads_union):
    m = Mesh()
    F, L, W = Frame.from_poly([(59.4, 441.2), (93.7, 446.1), (92.2, 469.9), (56.9, 466.7)])
    # w = 0 côté nord ?
    if F.xz(0, W)[1] < F.xz(0, 0)[1]:
        F = Frame(F.xz(0, W), F.a, -F.b)
    pts = [F.xz(u, w) for u in (0, L) for w in (0, W)]
    g = min(H(x, z) for x, z in pts)
    y0 = g
    wn = 10.5
    north = gable_body(m, F, 0, L, 0, wn, y0, g + 4.2, g + 7.2, CREPI_CREAM, M_CREPI, TILE_RED, "u", oh=0.4, ends=(False, False))
    hall = gable_body(m, F, 0.4, L - 0.4, wn, W, y0, g + 4.6, g + 6.6, (0.86, 0.82, 0.72), M_CREPI, (0.62, 0.36, 0.27), "u", oh=0.4)
    for k in ("u0", "u1"):
        stepped_gable(north[k], m, g + 4.2 - y0, g + 7.2 - y0, CREPI_CREAM)
    ridge_cap(m, F.P(-0.4, wn / 2, g + 7.2), F.P(L + 0.4, wn / 2, g + 7.2), TILE_RED)
    wf = north["w0"]
    for j in range(7):
        xx = wf.L * (j + 0.5) / 7
        if j in (2, 5):
            door(wf, m, xx, 1.8, 2.5, (0.50, 0.32, 0.18), "rect", WHITE_SURR, 0.15, y0=0.0)
        else:
            window(wf, m, xx, 1.0, 1.4, 1.4, "rect", WHITE_SURR, 0.14, frame=(0.92, 0.92, 0.9))
    ge = max(("u0", "u1"), key=lambda k: (north[k].o + north[k].r * north[k].L / 2)[0])
    wl = north[ge]
    door(wl, m, wl.L / 2, 1.7, 2.5, (0.50, 0.32, 0.18), "rect", WHITE_SURR, 0.15, y0=0.0)
    wl.box(m, wl.L / 2 - 1.3, wl.L / 2 + 1.3, 2.9, 3.05, 0, 1.2, (0.55, 0.32, 0.22), M_PLAIN)
    for dx in (-3.2, 3.2):
        window(wl, m, wl.L / 2 + dx, 1.0, 1.0, 1.3, "rect", WHITE_SURR, 0.14, frame=(0.92, 0.92, 0.9))
    for k in ("u0", "u1"):
        hw = hall[k]
        for j in range(3):
            window(hw, m, hw.L * (j + 0.5) / 3, 1.2, 1.6, 1.2, "rect", WHITE_SURR, 0.12, frame=(0.9, 0.9, 0.9))
    c = F.xz(L / 2, W / 2)
    return [(c[0], c[1], m, True)]


def cabin():
    """Local technique en béton blanc (devant la boulangerie)."""
    m = Mesh()
    F, L, W = Frame.from_poly([(61.3, 416.9), (66.4, 418.7), (65.4, 421.1), (60.4, 419.0)])
    g = min(H(*F.xz(u, w)) for u in (0, L) for w in (0, W))
    col = (0.86, 0.83, 0.74)
    obox(m, F.P(L / 2, W / 2, g + 1.1), F.a, (L, 2.8, W), col, M_CREPI)
    obox(m, F.P(L / 2, W / 2, g + 2.55), F.a, (L + 0.2, 0.12, W + 0.2), (0.62, 0.62, 0.6), M_CURB)
    inside = F.xz(L / 2, W / 2)
    for side in ((F.xz(0, 0), F.xz(L, 0)), (F.xz(L, W), F.xz(0, W))):
        wl = Wall(side[0], side[1], g, inside)
        for j, c in enumerate([(0.82, 0.78, 0.62), (0.82, 0.78, 0.62), (0.30, 0.22, 0.17)]):
            xx = wl.L * (j + 0.5) / 3
            wl.rect(m, xx - 0.55, xx + 0.55, 0.05, 2.1, 0.03, c, M_PLAIN)
    # antenne
    p = F.P(L * 0.8, W / 2, g + 2.6)
    obox(m, p + [0, 1.5, 0], F.a, (0.05, 3.0, 0.05), (0.6, 0.6, 0.6), M_STEEL)
    c = F.xz(L / 2, W / 2)
    return [(c[0], c[1], m, False)]


# ----------------------------------------------------------------------------------- bâtiments génériques habillés
# (centroïde approximatif, réglages) : la BD TOPO fournit l'emprise, on impose couleurs, hauteur, devanture
DRESSED = [
    ((41.0, 418.0), dict(name="boulangerie", wcol=(0.88, 0.81, 0.66), seed=0.05, h=8.2, roof_h=2.6, rcol=(0.62, 0.36, 0.27))),
    ((27.0, 416.0), dict(name="restaurant", wcol=(0.66, 0.22, 0.18), seed=0.21, h=6.2, roof_h=2.6, rcol=(0.60, 0.35, 0.27))),
    ((121.0, 410.0), dict(name="logements", wcol=(0.90, 0.85, 0.72), seed=0.55, rcol=(0.66, 0.38, 0.27))),
    ((150.0, 415.0), dict(name="logements", wcol=(0.90, 0.85, 0.72), seed=0.55, rcol=(0.66, 0.38, 0.27))),
]
CUSTOM = [(117.0, 475.0), (81.0, 427.0), (75.0, 456.0), (63.3, 419.0)]   # remplacés par un modèle dédié


def override(poly, pr):
    c = poly.centroid
    for cx, cz in CUSTOM:
        if math.hypot(c.x - cx, c.y - cz) < 6.0 and poly.area > 8:
            return "skip"
    for (cx, cz), d in DRESSED:
        if math.hypot(c.x - cx, c.y - cz) < 6.0:
            return d
    return None


def dressed_extras(m, poly, d, gmin, wall_top, roads_union):
    """Devantures : enseigne, vitrines, stores, sur la façade côté rue."""
    if d["name"] not in ("boulangerie", "restaurant"):
        return
    ring = list(poly.exterior.coords)[:-1]
    inside = (poly.centroid.x, poly.centroid.y)
    best = None
    for k in range(len(ring)):
        a, b = ring[k], ring[(k + 1) % len(ring)]
        L = math.dist(a, b)
        if L < 4.5:
            continue
        mid = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
        dd = roads_union.distance(Point(mid))
        if best is None or dd < best[0]:
            best = (dd, a, b)
    if best is None:
        return
    wl = Wall(best[1], best[2], gmin, inside)
    x = wl.L / 2
    if d["name"] == "boulangerie":
        bord = (0.42, 0.09, 0.14)
        w = min(wl.L - 0.8, 6.0)
        wl.box(m, x - w / 2, x + w / 2, -0.4, 3.3, 0, 0.18, bord, M_PLAIN)
        wl.box(m, x - w / 2 - 0.05, x + w / 2 + 0.05, 3.3, 3.42, 0, 0.26, (0.85, 0.72, 0.38), M_STEEL)
        wl.sign(m, x, 2.85, min(w - 0.3, 3.6), min(w - 0.3, 3.6) / 4, SIGN_BAKERY, 0.2)
        for dx in (-w / 4 - 0.2, w / 4 + 0.2):
            wl.rect(m, x + dx - w / 6, x + dx + w / 6, 0.5, 2.35, 0.2, (0.16, 0.14, 0.12), M_GLASS)
            wl.rect(m, x + dx - w / 6, x + dx + w / 6, 0.5, 0.62, 0.21, (0.85, 0.72, 0.38), M_STEEL)
        wl.rect(m, x - 0.5, x + 0.5, 0.0, 2.35, 0.2, (0.20, 0.17, 0.15), M_GLASS)
    else:
        red = (0.70, 0.20, 0.17)
        for j, xx in enumerate((wl.L * 0.25, wl.L * 0.6)):
            # stores bannes
            p0, p1 = wl.P(xx - 1.4, 2.9, 0.02), wl.P(xx + 1.4, 2.9, 0.02)
            q0, q1 = wl.P(xx - 1.4, 2.3, 1.2), wl.P(xx + 1.4, 2.3, 1.2)
            quad3(m, p0, p1, q1, q0, (0.62, 0.12, 0.12), M_PLAIN)
            quad3(m, q0, q1, q1 - [0, 0.25, 0], q0 - [0, 0.25, 0], (0.85, 0.82, 0.75), M_PLAIN)
            wl.rect(m, xx - 1.2, xx + 1.2, 0.5, 2.2, 0.03, (0.14, 0.12, 0.12), M_GLASS)
        wl.sign(m, wl.L * 0.42, 3.55, 3.2, 0.8, SIGN_RESTO, 0.08)
        wl.sign(m, wl.L * 0.85, 3.3, 0.8, 0.8, SIGN_LOGO_R, 0.08)
        # porte d'entrée sous le logo
        door(wl, m, wl.L * 0.85, 1.0, 2.2, (0.35, 0.18, 0.14), "rect", (0.90, 0.88, 0.82), 0.12)


def roads_union_from(meta):
    nodes = meta["nodes"]
    ls = []
    for w in meta["ways"]:
        pts = [nodes[i] for i in w["nd"]]
        if any(AREA.buffer(60).contains(Point(p)) for p in pts):
            ls.append(LineString(pts).buffer(w["w"] / 2))
    return unary_union(ls)


def buildings(meta):
    """Modèles dédiés (renvoie [(x, z, Mesh, big)])."""
    ru = roads_union_from(meta)
    out = []
    out += church()
    media, _ = mediatheque(ru)
    out += media
    out += mairie(ru)
    out += salle_des_fetes(ru)
    out += cabin()
    return out, ru


# ----------------------------------------------------------------------------------- sol
def osm():
    p = os.path.join(DATA, "center_osm.json")
    return json.load(open(p))["elements"] if os.path.exists(p) else []


def way_poly(e):
    x, z = to_local([q["lon"] for q in e["geometry"]], [q["lat"] for q in e["geometry"]])
    return [(float(a), float(b)) for a, b in zip(x, z)]


SQUARE_ID = 920110580       # place de l'église (gravier)
RAVETTE_ID = 224137384      # parking de la rue de Ravette


def landcover(fill, YARD, GRAVEL, GARDEN):
    for e in osm():
        t = e.get("tags", {})
        if e["type"] != "way" or "geometry" not in e:
            continue
        if t.get("amenity") == "parking":
            pts = way_poly(e)
            if len(pts) < 4:
                continue
            fill(Polygon(pts).buffer(5.0 if e['id'] == SQUARE_ID else 1.0), GRAVEL if e["id"] in (SQUARE_ID, 920110579, 920110584) else YARD)
        elif t.get("landuse") == "village_green":
            fill(Polygon(way_poly(e)), GARDEN)


_square = None


def in_square(x, z, margin=4.0):
    """Sur la place de l'église (les platanes y sont modélisés à la main)."""
    global _square
    if _square is None:
        _square = Polygon()
        for e in osm():
            if e["id"] == SQUARE_ID:
                _square = Polygon(way_poly(e)).buffer(margin)
    return _square.contains(Point(x, z))


def tree_instances():
    """(x, z, type, hauteur) pour trees.bin : cyprès du cimetière, jeunes arbres de la rue de l'Église."""
    T_OAK, T_BUSH, T_POPLAR, T_CONIFER, T_FRUIT, T_SHRUB = range(6)
    out = []
    # rangée de jeunes arbres dans la bande plantée à l'ouest de la rue de l'Église
    for k in range(7):
        z = 452 + k * 5.5
        out.append((143.5 - k * 0.15, z, T_FRUIT, 5.0 + (k % 3) * 0.6))
    # cyprès et thuyas du cimetière
    for x, z in ((99, 505), (124, 507), (98, 530), (125, 540), (110, 546)):
        out.append((x, z, T_CONIFER, 7.5))
    # saule et arbres d'ornement autour du parking de la rue de Ravette
    out += [(78, 380, T_OAK, 9.0), (115, 372, T_FRUIT, 5.0), (84, 410, T_FRUIT, 4.5), (110, 392, T_FRUIT, 4.8)]
    # massifs du jardin de la médiathèque
    for x, z in ((99, 431), (100, 435), (96, 437)):
        out.append((x, z, T_SHRUB, 1.4))
    return out


# ----------------------------------------------------------------------------------- mobilier (prepare_street)
def plane_tree(x, z, seed):
    """Platane taillé en têtard : tronc tacheté, charpentières courtes terminées par des moignons
    noueux, petites touffes de jeunes pousses."""
    r = random.Random(seed)
    m = Mesh()
    y = H(x, z)
    bark = (0.66, 0.63, 0.55)
    th = r.uniform(2.6, 3.3)
    prism(m, x, y - 0.2, y + th, z, 0.27, 0.22, 8, bark, M_CREPI, r.random())
    n = r.randint(5, 7)
    for k in range(n):
        a = 2 * math.pi * k / n + r.uniform(-0.3, 0.3)
        tilt = r.uniform(0.3, 0.75)
        L = r.uniform(0.9, 1.7)
        dx, dz = math.cos(a) * math.sin(tilt), math.sin(a) * math.sin(tilt)
        dy = math.cos(tilt)
        p0 = np.array([x, y + th - 0.15, z]); p1 = p0 + np.array([dx, dy, dz]) * L
        # charpentière trapue (prisme incliné : 5 faces)
        d = nrm(p1 - p0); s1 = nrm(np.cross(d, [0, 1, 0])); s2 = np.cross(s1, d)
        for j in range(5):
            a0, a1 = j * 2 * math.pi / 5, (j + 1) * 2 * math.pi / 5
            o0 = s1 * math.cos(a0) + s2 * math.sin(a0); o1 = s1 * math.cos(a1) + s2 * math.sin(a1)
            quad3(m, p0 + o0 * 0.15, p0 + o1 * 0.15, p1 + o1 * 0.12, p1 + o0 * 0.12, bark, M_CREPI,
                  [(0, 0), (0.3, 0), (0.3, L), (0, L)], n=tuple(nrm(o0 + o1)))
        # tête de chat (moignon noueux) et quelques jeunes pousses
        blob(m, p1 + d * 0.08, 0.24, (0.60, 0.57, 0.50), M_PLAIN, 1.25)
        if r.random() < 0.6:
            q = p1 + np.array([r.uniform(-0.2, 0.2), r.uniform(0.3, 0.5), r.uniform(-0.2, 0.2)])
            blob(m, q, r.uniform(0.2, 0.32), (0.50 + r.uniform(-0.05, 0.05), 0.62, 0.28), M_PLAIN, 0.9)
    return m, y


def parked_car(x, z, yaw, col, seed):
    """Voiture garée (volume simplifié)."""
    r = random.Random(seed)
    m = Mesh()
    y = H(x, z)
    ax = (math.cos(yaw), math.sin(yaw)); a3 = np.array([ax[0], 0, ax[1]]); b3 = np.array([-ax[1], 0, ax[0]])
    L = r.uniform(3.9, 4.5); W = 1.76
    c = np.array([x, y, z])
    obox(m, c + [0, 0.62, 0], ax, (L, 0.62, W), col, M_STEEL)
    obox(m, c + a3 * (L / 2 - 0.25) + [0, 0.55, 0], ax, (0.5, 0.45, W - 0.06), col, M_STEEL)
    # habitacle
    k = r.choice([0.45, 0.6, 0.75])   # berline, break, monospace
    roof_len = L * (0.38 + 0.2 * k)
    base_y = y + 0.93
    top_y = y + 1.38 + 0.15 * k
    fr = c + a3 * (L * 0.18); rr = c - a3 * (L * 0.36 - 0.1 * k)
    pts_side = []
    for s in (-1, 1):
        bb = b3 * (W / 2 - 0.05) * s
        A = fr + a3 * 0.6 + bb + [0, base_y - y, 0]; B = rr - a3 * 0.1 + bb + [0, base_y - y, 0]
        C = rr + a3 * 0.15 + bb * 0.92 + [0, top_y - y, 0]; D = rr + a3 * (0.15 + roof_len) + bb * 0.92 + [0, top_y - y, 0]
        pts_side.append((A, B, C, D))
        poly3(m, [A, B, C, D], tuple(b3 * s), (0.12, 0.14, 0.17), M_GLASS)
    (A0, B0, C0, D0), (A1, B1, C1, D1) = pts_side
    quad3(m, A0, A1, D1, D0, (0.12, 0.14, 0.17), M_GLASS)        # pare-brise
    quad3(m, B0, B1, C1, C0, (0.12, 0.14, 0.17), M_GLASS)        # lunette
    quad3(m, C0, C1, D1, D0, col, M_STEEL, n=(0, 1, 0))           # pavillon
    for sx in (-1, 1):
        for sz in (-1, 1):
            p = c + a3 * sx * (L / 2 - 0.75) + b3 * sz * (W / 2 - 0.12) + [0, 0.32, 0]
            obox(m, p, ax, (0.62, 0.62, 0.22), (0.08, 0.08, 0.08), M_PLAIN)
    for s in (-1, 1):   # feux
        obox(m, c + a3 * (L / 2 + 0.01) + b3 * s * 0.6 + [0, 0.75, 0], ax, (0.04, 0.12, 0.3), (0.9, 0.9, 0.85), M_PLAIN)
        obox(m, c - a3 * (L / 2 + 0.01) + b3 * s * 0.6 + [0, 0.8, 0], ax, (0.04, 0.14, 0.26), (0.65, 0.05, 0.05), M_PLAIN)
    ring = [tuple(c[[0, 2]] + np.array(ax) * sx * L / 2 + np.array([-ax[1], ax[0]]) * sz * W / 2)
            for sx, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    return m, ring


CAR_COLS = [(0.72, 0.73, 0.74), (0.55, 0.56, 0.58), (0.20, 0.22, 0.26), (0.88, 0.88, 0.86), (0.12, 0.25, 0.55),
            (0.30, 0.31, 0.33), (0.68, 0.70, 0.72), (0.45, 0.10, 0.10), (0.78, 0.78, 0.76)]


def champignon(x, z, double=False):
    """Lampadaire crème à vasque verte (style du centre)."""
    m = Mesh()
    y = H(x, z)
    cream, green = (0.88, 0.86, 0.78), (0.16, 0.27, 0.21)
    prism(m, x, y - 0.2, y + 0.6, z, 0.11, 0.09, 8, cream, M_STEEL)
    prism(m, x, y + 0.6, y + 4.6, z, 0.065, 0.05, 8, cream, M_STEEL)
    heads = [(x, z, y + 4.6)] if not double else []
    if double:
        for s in (-1, 1):
            hx = x + s * 0.65
            obox(m, (x + s * 0.33, y + 4.55, z), (1, 0), (0.66, 0.06, 0.06), cream, M_STEEL)
            heads.append((hx, z, y + 4.5))
    for hx, hz, hy in heads:
        prism(m, hx, hy, hy + 0.08, hz, 0.06, 0.06, 6, cream, M_STEEL)
        # vasque (cône inversé) + chapeau
        prism(m, hx, hy - 0.05, hy + 0.12, hz, 0.12, 0.36, 10, green, M_STEEL, cap=False)
        prism(m, hx, hy + 0.12, hy + 0.26, hz, 0.38, 0.10, 10, green, M_STEEL)
        poly3(m, [(hx + 0.13 * math.cos(a), hy - 0.04, hz + 0.13 * math.sin(a)) for a in np.linspace(0, 2 * math.pi, 10, endpoint=False)],
              (0, -1, 0), (0.95, 0.92, 0.80), M_LIGHT)
        prism(m, hx, hy + 0.26, hy + 0.4, hz, 0.03, 0.01, 6, green, M_STEEL)
    return m


def memorial(x, z):
    m = Mesh()
    y = H(x, z)
    st = (0.90, 0.89, 0.85)
    prism(m, x, y - 0.3, y + 0.25, z, 2.0, 2.0, 4, (0.70, 0.70, 0.68), M_CURB, math.pi / 4)
    prism(m, x, y + 0.25, y + 0.55, z, 1.45, 1.45, 4, st, M_CHURCH, math.pi / 4, extra=3000.0)
    prism(m, x, y + 0.55, y + 1.6, z, 0.95, 0.95, 4, st, M_CHURCH, math.pi / 4, extra=3000.0)
    prism(m, x, y + 1.6, y + 1.8, z, 1.05, 1.05, 4, st, M_CHURCH, math.pi / 4, extra=3000.0)
    prism(m, x, y + 1.8, y + 6.4, z, 0.62, 0.36, 4, st, M_CHURCH, math.pi / 4, extra=3000.0)
    pyramid(m, [(x + 0.36 * math.cos(math.pi / 4 + k * math.pi / 2), y + 6.4, z + 0.36 * math.sin(math.pi / 4 + k * math.pi / 2)) for k in range(4)],
            (x, y + 7.0, z), st, M_CHURCH, 3000.0)
    # plaque et palmes
    for k in range(4):
        a = k * math.pi / 2
        d = np.array([math.cos(a), math.sin(a)])
        obox(m, (x + d[0] * 0.66, y + 1.1, z + d[1] * 0.66), (-d[1], d[0]), (0.8, 0.6, 0.03), (0.22, 0.22, 0.24), M_STEEL)
    # chaînes et bornes autour
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        px, pz = x + 2.6 * math.cos(a), z + 2.6 * math.sin(a)
        prism(m, px, y - 0.1, y + 0.7, pz, 0.09, 0.09, 6, (0.25, 0.26, 0.27), M_STEEL)
    for k in range(4):
        a0 = math.pi / 4 + k * math.pi / 2; a1 = a0 + math.pi / 2
        p0 = np.array([x + 2.6 * math.cos(a0), y + 0.62, z + 2.6 * math.sin(a0)])
        p1 = np.array([x + 2.6 * math.cos(a1), y + 0.62, z + 2.6 * math.sin(a1)])
        for j in range(6):
            t0, t1 = j / 6, (j + 1) / 6
            q0 = p0 + (p1 - p0) * t0 - [0, 0.25 * math.sin(math.pi * t0), 0]
            q1 = p0 + (p1 - p0) * t1 - [0, 0.25 * math.sin(math.pi * t1), 0]
            d = q1 - q0
            obox(m, (q0 + q1) / 2, (d[0], d[2]), (np.linalg.norm(d), 0.03, 0.03), (0.15, 0.15, 0.15), M_STEEL)
    return m


def cemetery_parts():
    """Murs (segments) et tombes du cimetière."""
    for e in osm():
        if e.get("tags", {}).get("landuse") == "cemetery":
            return way_poly(e)
    return None


def furniture(add, add_coll, roads_union=None):
    """Mobilier du centre. add(x, z, mesh, big) ; add_coll(anneau)."""
    def ring_box(x, z, ax, L, W):
        a = np.array(ax) / np.linalg.norm(ax); b = np.array([-a[1], a[0]])
        return np.array([[x, z] + a * sx * L / 2 + b * sz * W / 2 for sx, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1))])

    stats = {}

    def count(k):
        stats[k] = stats.get(k, 0) + 1

    # --- platanes en têtard autour de la place de l'église
    planes = []
    sq = None
    for e in osm():
        if e["id"] == SQUARE_ID:
            sq = Polygon(way_poly(e))
    if sq is not None:
        ring = sq.exterior
        L = ring.length
        s = 2.0
        while s < L:
            p = ring.interpolate(s)
            c = sq.centroid
            # légèrement à l'intérieur de la place
            d = np.array([c.x - p.x, c.y - p.y]); d /= np.linalg.norm(d)
            q = (p.x + d[0] * 1.6, p.y + d[1] * 1.6)
            # pas devant l'église (côté sud : les voitures s'y garent)
            if q[1] < 458 or q[0] > 140:
                planes.append(q)
            s += 8.5
        planes += [(118.0, 452.0), (130.0, 455.0)]
    for k, (x, z) in enumerate(planes):
        if math.hypot(x - 124.7, z - 447.2) < 4:
            continue
        if roads_union is not None and roads_union.buffer(0.8).contains(Point(x, z)):
            continue
        m, y = plane_tree(x, z, k + 11)
        add(x, z, m, True)
        add_coll(ring_box(x, z, (1, 0), 0.5, 0.5))
        count("platanes")
    # --- monument aux morts
    add(124.7, 447.2, memorial(124.7, 447.2), True)
    add_coll(ring_box(124.7, 447.2, (1, 0), 2.8, 2.8))
    # --- voitures garées : le long de l'église (place), parking de la rue de Ravette, salle des fêtes
    cars = []
    a = np.array([31.5, 8.2]); a /= np.linalg.norm(a)
    nb = np.array([a[1], -a[0]])          # vers le nord
    for k in range(6):
        p = np.array([102.2, 473.3]) + a * (17.5 + k * 2.6) + nb * 9.6
        cars.append((p[0], p[1], math.atan2(nb[1], nb[0]), k))
    rav = None
    for e in osm():
        if e["id"] == RAVETTE_ID:
            rav = Polygon(way_poly(e))
    faces = []
    if rav is not None and roads_union is not None:
        # une allée en boucle laisse un trou dans l'union des chaussées : c'est l'îlot
        faces = [f for f in (Polygon(i) for b in getattr(roads_union, "geoms", [roads_union]) for i in b.interiors)
                 if rav.buffer(4).contains(f.centroid) and 15 < f.area < 900]
    if rav is not None:
        # rangées perpendiculaires au grand côté du parking
        F, L, W = Frame.from_poly(list(rav.exterior.coords)[:-1])
        for j, u in enumerate(np.arange(3.0, L - 2.0, 2.55)):
            for w in (2.7, W - 2.7):
                q = F.xz(u, w)
                if rng.random() < 0.55 and rav.buffer(-1.0).contains(Point(q)) and \
                        (roads_union is None or roads_union.distance(Point(q)) > 1.6) and \
                        not any(f.buffer(1.4).contains(Point(q)) for f in faces):
                    yaw = math.atan2(F.b[1], F.b[0])
                    cars.append((q[0], q[1], yaw, 100 + j * 2 + (w > 3)))
    for k, (u, w) in enumerate(((52, 452), (52, 455), (52, 466), (52, 469))):
        cars.append((u, w, 0.0, 200 + k))
    for x, z, yaw, sd in cars:
        if roads_union is not None and roads_union.distance(Point(x, z)) < 1.2:
            continue
        col = CAR_COLS[(sd * 7) % len(CAR_COLS)]
        m, ring = parked_car(x, z, yaw, col, sd)
        add(x, z, m, False)
        add_coll(np.array(ring))
        count("voitures garées")
    # --- îlots plantés du parking de la rue de Ravette (faces fermées des allées)
    if faces:
        for f in faces:
            g = f.buffer(-0.4)
            if g.is_empty or not isinstance(g, Polygon):
                continue
            m = Mesh()
            import sidewalks as swm
            g = g.simplify(0.05)
            gb = g.boundary
            top = lambda x, z: np.atleast_1d(np.vectorize(H)(x, z)) + swm.CURB + 0.07
            kind = lambda mids: np.where(shapely.distance(gb, shapely.points(mids)) < 0.03, 1, 0)
            base = lambda x, z, k: H(x, z) - 0.04
            # bordure continue (10 cm au-dessus de l'enrobé, franchissable) + terre végétalisée
            swm.raised_mesh(m, g, top, base, kind, (0.34, 0.42, 0.20), M_GRASS, M_CURB, step=3.0, band=0.15)
            RAISED.append((g, lambda x, z: np.full(np.shape(x), swm.CURB + 0.07)))
            # arbustes bas
            rr = random.Random(int(f.area))
            inner = g.buffer(-0.6)
            if not inner.is_empty:
                mnx, mnz, mxx, mxz = inner.bounds
                for _ in range(int(f.area / 6)):
                    q = (rr.uniform(mnx, mxx), rr.uniform(mnz, mxz))
                    if inner.contains(Point(q)):
                        blob(m, (q[0], H(*q) + 0.4, q[1]), rr.uniform(0.35, 0.6), (0.24 + rr.uniform(-0.04, 0.04), 0.38, 0.15), M_PLAIN, 0.7)
            add(f.centroid.x, f.centroid.y, m, True)
            count("îlots plantés")
    # --- cimetière : murs gris avec chaperon, portail, tombes
    cem = cemetery_parts()
    if cem is not None:
        cp = Polygon(cem)
        if not cp.exterior.is_ccw:
            cp = Polygon(cem[::-1])
        pts = list(cp.exterior.coords)[:-1]
        wall_col = (0.72, 0.71, 0.68)
        for k in range(len(pts)):
            a_, b_ = np.array(pts[k]), np.array(pts[(k + 1) % len(pts)])
            d = b_ - a_; L = np.linalg.norm(d); d /= L
            # portail : ouverture au milieu du côté nord (face au parking)
            gaps = []
            if abs(d[1]) < 0.4 and (a_[1] + b_[1]) / 2 < cp.centroid.y:
                gaps = [(L / 2 - 1.8, L / 2 + 1.8)]
            segs = [(0.0, gaps[0][0]), (gaps[0][1], L)] if gaps else [(0.0, L)]
            m = Mesh()
            for s0, s1 in segs:
                n = max(1, int((s1 - s0) / 6))
                for j in range(n):
                    t0 = s0 + (s1 - s0) * j / n; t1 = s0 + (s1 - s0) * (j + 1) / n
                    p0 = a_ + d * t0; p1 = a_ + d * t1
                    mid = (p0 + p1) / 2
                    y = min(H(*p0), H(*p1))
                    obox(m, (mid[0], y + 0.6, mid[1]), d, (t1 - t0 + 0.2, 2.6, 0.25), wall_col, M_CREPI)
                    obox(m, (mid[0], y + 1.95, mid[1]), d, (t1 - t0 + 0.2, 0.12, 0.42), (0.60, 0.60, 0.58), M_CURB)
                    q = np.array([[*(p0 + np.array([-d[1], d[0]]) * 0.15)], [*(p1 + np.array([-d[1], d[0]]) * 0.15)],
                                  [*(p1 - np.array([-d[1], d[0]]) * 0.15)], [*(p0 - np.array([-d[1], d[0]]) * 0.15)]])
                    add_coll(q)
            for g0, g1 in gaps:
                for t in (g0, g1):
                    p = a_ + d * t
                    y = H(*p)
                    obox(m, (p[0], y + 1.1, p[1]), d, (0.5, 2.6, 0.5), (0.80, 0.79, 0.75), M_CHURCH, 3000.0)
                    add_coll(ring_box(p[0], p[1], d, 0.5, 0.5))
                # grille entrouverte
                p = a_ + d * g0
                obox(m, (p[0] + d[0] * 1.0, H(*p) + 0.9, p[1] + d[1] * 1.0), d, (1.7, 1.6, 0.04), (0.12, 0.14, 0.13), M_STEEL)
            add(float(a_[0] + d[0] * L / 2), float(a_[1] + d[1] * L / 2), m, True)
        # tombes en rangées
        F, L, W = Frame.from_poly(pts)
        m = Mesh()
        inner = cp.buffer(-1.6)
        rr = random.Random(5)
        granite = [(0.22, 0.22, 0.23), (0.45, 0.44, 0.43), (0.60, 0.50, 0.48), (0.35, 0.34, 0.36), (0.70, 0.69, 0.66)]
        nt = 0
        for i, u in enumerate(np.arange(1.5, L - 1.0, 1.55)):
            for j, w in enumerate(np.arange(1.5, W - 1.0, 3.0)):
                if j % 4 == 2:          # allée
                    continue
                q = F.xz(u, w)
                if not inner.contains(Point(q)) or rr.random() < 0.12:
                    continue
                col = rr.choice(granite)
                y = H(*q)
                obox(m, (q[0], y + 0.18, q[1]), F.b, (2.1, 0.45, 0.95), col, M_STEEL)
                hp = F.xz(u, w + 1.0)
                hh = rr.uniform(0.6, 1.1)
                if rr.random() < 0.25:
                    obox(m, (hp[0], y + 0.3 + hh * 0.6, hp[1]), F.a, (0.1, hh * 1.2, 0.1), col, M_STEEL)
                    obox(m, (hp[0], y + 0.3 + hh * 0.9, hp[1]), F.a, (0.6, 0.1, 0.1), col, M_STEEL)
                else:
                    obox(m, (hp[0], y + 0.3 + hh / 2, hp[1]), F.a, (0.85, hh, 0.12), col, M_STEEL)
                if rr.random() < 0.35:
                    blob(m, (q[0], y + 0.5, q[1]), 0.18, rr.choice([(0.8, 0.3, 0.4), (0.9, 0.85, 0.3), (0.85, 0.85, 0.9)]), M_PLAIN)
                nt += 1
        c = cp.centroid
        add(c.x, c.y, m, False)
        stats["tombes"] = nt
    # --- conteneurs de tri (verre, papier, emballages)
    for k, col in enumerate([(0.18, 0.42, 0.22), (0.20, 0.35, 0.62), (0.80, 0.70, 0.15)]):
        x, z = 88.0 + k * 1.9, 486.5
        m = Mesh()
        y = H(x, z)
        obox(m, (x, y + 0.85, z), (1, 0), (1.6, 1.7, 1.6), col, M_STEEL)
        prism(m, x, y + 1.7, y + 1.95, z, 0.75, 0.4, 8, col, M_STEEL, math.pi / 8)
        add(x, z, m, False)
        add_coll(ring_box(x, z, (1, 0), 1.6, 1.6))
    # --- boîte aux lettres jaune et boîte à livres devant la médiathèque
    m = Mesh()
    x, z = 103.5, 428.8
    y = H(x, z)
    obox(m, (x, y + 0.6, z), (1, 0), (0.08, 1.2, 0.08), (0.3, 0.3, 0.3), M_STEEL)
    obox(m, (x, y + 1.25, z), (1, 0.3), (0.42, 0.5, 0.32), (0.96, 0.80, 0.08), M_STEEL)
    obox(m, (x, y + 1.52, z), (1, 0.3), (0.46, 0.05, 0.36), (0.30, 0.42, 0.75), M_STEEL)
    x, z = 98.7, 428.0
    obox(m, (x, y + 0.5, z), (1, 0.3), (0.1, 1.0, 0.1), (0.35, 0.25, 0.16), M_PLAIN)
    obox(m, (x, y + 1.35, z), (1, 0.3), (0.9, 0.8, 0.45), (0.55, 0.38, 0.22), M_PLAIN)
    obox(m, (x, y + 1.37, z + 0.0), (1, 0.3), (0.75, 0.62, 0.47), (0.15, 0.17, 0.2), M_GLASS)
    add(x, z, m, False)
    add_coll(ring_box(103.5, 428.8, (1, 0), 0.5, 0.5))
    # --- muret et grille du jardin de la médiathèque (côté route)
    m = Mesh()
    p0, p1 = np.array([97.5, 427.2]), np.array([94.6, 436.6])
    d = p1 - p0; L = np.linalg.norm(d); d /= L
    n_ = np.array([d[1], -d[0]])
    if n_[0] < 0:
        n_ = -n_
    q0 = p0 + n_ * 4.0; q1 = p1 + n_ * 4.0
    for j in range(3):
        a_ = q0 + (q1 - q0) * j / 3; b_ = q0 + (q1 - q0) * (j + 1) / 3
        mid = (a_ + b_) / 2
        y = H(*mid)
        obox(m, (mid[0], y + 0.25, mid[1]), d, (L / 3, 0.7, 0.3), (0.82, 0.76, 0.62), M_CREPI)
        obox(m, (mid[0], y + 0.63, mid[1]), d, (L / 3, 0.06, 0.36), (0.68, 0.66, 0.62), M_CURB)
        for t in np.linspace(0, 1, 12):
            pp = a_ + (b_ - a_) * t
            obox(m, (pp[0], y + 0.95, pp[1]), d, (0.025, 0.6, 0.025), (0.13, 0.15, 0.14), M_STEEL)
        obox(m, (mid[0], y + 1.22, mid[1]), d, (L / 3, 0.04, 0.04), (0.13, 0.15, 0.14), M_STEEL)
        add_coll(np.array([a_ - n_ * 0.2, b_ - n_ * 0.2, b_ + n_ * 0.2, a_ + n_ * 0.2]))
    add(float(q0[0]), float(q0[1]), m, False)
    # --- bornes et barrières le long de la place
    if sq is not None:
        m = Mesh()
        ring = sq.exterior
        for s in np.arange(0, ring.length, 3.0):
            p = ring.interpolate(s)
            if roads_union is not None and roads_union.distance(p) > 3.5:
                continue
            if roads_union is not None and roads_union.contains(p):
                continue
            y = H(p.x, p.y)
            prism(m, p.x, y - 0.1, y + 0.75, p.y, 0.09, 0.08, 8, (0.32, 0.34, 0.33), M_STEEL)
            add_coll(ring_box(p.x, p.y, (1, 0), 0.2, 0.2))
        add(sq.centroid.x, sq.centroid.y, m, False)
    return stats


def lamp_style(x, z):
    """Lampadaires « champignon » dans le centre, double tête autour de la place."""
    if math.hypot(x - CENTER[0], z - CENTER[1]) > 330:
        return None
    return "double" if math.hypot(x - 125, z - 450) < 45 else "single"
