"""Génère le décor du jeu à partir des données IGN (BD TOPO, RPG) déjà téléchargées.

À lancer APRÈS prepare_data.py (il relit terrain.bin et map.json, et creuse les étangs).

Sorties (app/src/main/assets/) :
  landcover.png   occupation du sol, 4 m/pixel  (R = classe, G = orientation des rangs, B = aléa)
  landfar.png     occupation du sol lointaine, 25 m/pixel (forêts, eau, villes)
  props.bin       maillages : bâtiments, église, plans d'eau, ruisseaux, pylônes, câbles (tuiles de 320 m)
  trees.bin       arbres et haies (instances par tuile)
  collide.bin     emprises des bâtiments pour les collisions
  pano.bin        relief lointain (Alpes, Chartreuse, Vercors…) avec courbure terrestre
  terrain.bin     réécrit : fonds des étangs abaissés
"""
import json, math, os, struct, random
import numpy as np
from PIL import Image, ImageDraw
from shapely.geometry import shape, Polygon, MultiPolygon, LineString, Point, box
from shapely.ops import transform, polylabel, unary_union
from shapely import affinity
import mapbox_earcut as earcut
from geo import to_local, OUTER, PANO, grid_shape
from prepare_data import Grid, X0, X1, Z0, Z1, STEP, CHUNK, CHUNK_CELLS

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "data")
ASSETS = os.path.join(HERE, "..", "app", "src", "main", "assets")
rng = random.Random(38110)
CLIP = box(X0 + 45, Z0 + 45, X1 - 45, Z1 - 45)

# ----------------------------------------------------------------------------------- classes
MEADOW, PASTURE, MOWED, WHEAT, BARLEY, MAIZE, SUNFLOWER, RAPESEED, FALLOW, SOIL, FOREST, GARDEN, \
    YARD, GRAVEL, TURF, WATER, HEDGE, SOY = range(18)
RPG = {
    **dict.fromkeys(["PPH", "PRL", "SPH", "SPL", "BOR", "PPP", "SPM"], PASTURE),
    **dict.fromkeys(["PTR", "LUZ", "MLG", "TRE", "RGA", "FET", "MCR", "FSG", "PAT"], MOWED),
    **dict.fromkeys(["BTH", "BTP", "BDH", "BDP", "BTA", "TTH", "TTP", "EPE", "SGH", "SGP"], WHEAT),
    **dict.fromkeys(["ORH", "ORP", "AVH", "AVP", "MLC", "CHA"], BARLEY),
    **dict.fromkeys(["MIS", "MIE", "MID", "MPC"], MAIZE),
    "TRN": SUNFLOWER,
    **dict.fromkeys(["CZH", "CZP"], RAPESEED),
    **dict.fromkeys(["JAC", "SNE", "BFS", "BFP", "J5M", "J6P", "J6S"], FALLOW),
    **dict.fromkeys(["SOJ", "PEP", "FVL", "FEV", "PPO", "CPL", "LEC"], SOY),
}
LC_RES = 4.0


def loc(g):
    from shapely.validation import make_valid
    r = transform(lambda x, y, z=None: to_local(x, y), shape(g))
    return r if r.is_valid else make_valid(r)


def polys(g):
    if isinstance(g, Polygon):
        return [g]
    if isinstance(g, MultiPolygon):
        return list(g.geoms)
    if hasattr(g, "geoms"):
        return [p for x in g.geoms for p in polys(x)]
    return []


def load(name):
    """Objets d'une couche, sans doublons (la pagination WFS non triée peut en renvoyer)."""
    p = os.path.join(DATA, "wfs_%s.json" % name)
    if not os.path.exists(p):
        return []
    seen, out = set(), []
    for f in json.load(open(p))["features"]:
        key = f.get("id") or f["properties"].get("cleabs") or json.dumps(f["geometry"])[:200]
        if key in seen:
            continue
        seen.add(key)
        out.append(f)
    return out


def read_grid(path):
    b = open(path, "rb").read()
    _, nx, nz, x0, z0, st = struct.unpack("<4siifff", b[:24])
    return np.frombuffer(b[24:], "<f4").reshape(nz, nx).astype(np.float64), x0, z0, st


# ----------------------------------------------------------------------------------- maillage
class Mesh:
    """Sommets : pos3, normale3, couleur3, uv2, matériau(+graine), extra = 13 flottants."""
    N = 13

    def __init__(self):
        self.v = []
        self.i = []

    def vert(self, p, n, c, uv=(0, 0), mat=0.0, extra=0.0):
        self.v.append((p[0], p[1], p[2], n[0], n[1], n[2], c[0], c[1], c[2], uv[0], uv[1], mat, extra))
        return len(self.v) - 1

    def tri(self, a, b, c):
        """Triangle orienté (sens trigonométrique) selon la normale moyenne de ses sommets."""
        pa, pb, pc = (np.array(self.v[k][:3]) for k in (a, b, c))
        nn = np.array(self.v[a][3:6]) + np.array(self.v[b][3:6]) + np.array(self.v[c][3:6])
        if np.dot(np.cross(pb - pa, pc - pa), nn) < 0:
            b, c = c, b
        self.i += [a, b, c]

    def quad(self, a, b, c, d):
        self.tri(a, b, c)
        self.tri(a, c, d)


def norm(v):
    v = np.asarray(v, dtype=float)
    l = np.linalg.norm(v)
    return v / l if l > 1e-9 else np.array([0, 1.0, 0])


class Chunks:
    """Répartit des objets (petits maillages) dans les tuiles de 320 m, en deux niveaux de détail."""

    def __init__(self):
        self.nCx = int(math.ceil((X1 - X0) / CHUNK)); self.nCz = int(math.ceil((Z1 - Z0) / CHUNK))
        self.data = {}

    def key(self, x, z):
        return (min(self.nCx - 1, max(0, int((x - X0) // CHUNK))), min(self.nCz - 1, max(0, int((z - Z0) // CHUNK))))

    def add(self, x, z, mesh, big):
        d = self.data.setdefault(self.key(x, z), ([], [], [], []))
        vs, ids = (d[0], d[1]) if big else (d[2], d[3])
        off = len(vs)
        vs.extend(mesh.v)
        ids.extend(j + off for j in mesh.i)

    def write(self, path, magic):
        out = bytearray(struct.pack("<4sfffii", magic, X0, Z0, CHUNK, self.nCx, self.nCz))
        out += struct.pack("<i", len(self.data))
        nv = 0
        for (cx, cz), (bv, bi, sv, si) in sorted(self.data.items()):
            verts = bv + sv
            idx = bi + [j + len(bv) for j in si]
            nv += len(verts)
            out += struct.pack("<iiiii", cx, cz, len(verts), len(idx), len(bi))
            out += np.asarray(verts, dtype="<f4").tobytes()
            out += np.asarray(idx, dtype="<u4").tobytes()
        open(path, "wb").write(out)
        return nv, len(out)


# ----------------------------------------------------------------------------------- couleurs
CREPI = [(0.86, 0.80, 0.67), (0.84, 0.70, 0.50), (0.86, 0.68, 0.56), (0.80, 0.74, 0.62), (0.89, 0.87, 0.82),
         (0.82, 0.76, 0.58), (0.78, 0.64, 0.50), (0.88, 0.82, 0.72)]
STONE = [(0.70, 0.64, 0.53), (0.66, 0.60, 0.50), (0.74, 0.68, 0.58)]
TILES = [(0.74, 0.38, 0.24), (0.68, 0.36, 0.25), (0.78, 0.44, 0.28), (0.62, 0.36, 0.28), (0.72, 0.42, 0.30)]
INDUS = [(0.62, 0.66, 0.70), (0.76, 0.74, 0.68), (0.85, 0.85, 0.83), (0.55, 0.58, 0.55), (0.70, 0.55, 0.42)]
M_PLAIN, M_WALL, M_INDUS_WALL, M_TILES, M_METAL, M_FLAT, M_WATER, M_CHURCH, M_STEEL, M_CABLE, M_GLASS, M_STREAM = range(12)


def jitter(c, a=0.04):
    return tuple(min(1, max(0, x + rng.uniform(-a, a))) for x in c)


def wall_color(mat_code, usage):
    if usage in ("Industriel", "Commercial et services", "Agricole") and rng.random() < 0.7:
        return jitter(rng.choice(INDUS), 0.03)
    d = (mat_code or "")[:1]
    if d == "1":
        return jitter(rng.choice(STONE))
    if d == "4":
        return jitter((0.62, 0.37, 0.28))
    if d == "6":
        return jitter((0.48, 0.35, 0.24))
    if d == "3":
        return jitter((0.74, 0.73, 0.70), 0.03)
    return jitter(rng.choice(CREPI), 0.03)


def roof_style(mat_code, usage, area):
    d = (mat_code or "")[:1]
    if d == "4" or (area > 1500 and usage != "Religieux"):
        return "flat"
    if d == "3" or (usage in ("Industriel", "Agricole", "Commercial et services") and area > 250):
        return "metal"
    if d == "2":
        return "slate"
    return "tiles"


# ----------------------------------------------------------------------------------- bâtiments
def inset_ring(ring, d):
    """Décale un anneau (CCW) vers l'intérieur de d par la méthode des bissectrices."""
    n = len(ring)
    out = []
    for k in range(n):
        p0 = np.array(ring[k - 1]); p1 = np.array(ring[k]); p2 = np.array(ring[(k + 1) % n])
        e0 = norm(np.append(p1 - p0, 0))[:2]; e1 = norm(np.append(p2 - p1, 0))[:2]
        n0 = np.array([-e0[1], e0[0]]); n1 = np.array([-e1[1], e1[0]])   # intérieur pour un anneau CCW
        b = n0 + n1
        lb = np.linalg.norm(b)
        if lb < 1e-6:
            b = n0; lb = 1.0
        b /= lb
        c = max(0.35, float(np.dot(b, n0)))
        out.append(tuple(p1 + b * d / c))
    return out


def triangulate(ring):
    a = np.asarray(ring, dtype=np.float64)
    if len(a) < 3:
        return []
    return list(earcut.triangulate_float64(a, np.array([len(a)], dtype=np.uint32)))


def building_mesh(poly, ground_min, wall_top, roof_h, style, wcol, rcol, wallmat, seed, floors, gable=False):
    m = Mesh()
    if gable:
        # maison rectangulaire à deux pans : on part du rectangle englobant minimal
        poly = poly.minimum_rotated_rectangle
    poly = poly.simplify(0.25)
    if poly.is_empty or not isinstance(poly, Polygon) or poly.area < 4:
        return None
    from shapely.geometry.polygon import orient
    poly = orient(poly, 1.0)
    ring = list(poly.exterior.coords)[:-1]
    n = len(ring)
    if n < 3:
        return None
    base = ground_min - 0.6
    # --- murs
    for k in range(n):
        a = ring[k]; b = ring[(k + 1) % n]
        dx, dz = b[0] - a[0], b[1] - a[1]
        L = math.hypot(dx, dz)
        if L < 0.05:
            continue
        nrm = (dz / L, 0.0, -dx / L)   # extérieur pour un anneau CCW (repère x Est, z Sud)
        ga = terrain.height(a[0], a[1]); gb = terrain.height(b[0], b[1])
        g = min(ga, gb)
        nwin = int(L // 3.3)
        half = nwin * 3.3 / 2 if (L > 2.8 and wallmat != M_PLAIN) else 0.0
        extra = floors * 1000 + half
        i0 = m.vert((a[0], base, a[1]), nrm, wcol, (-L / 2, base - g), wallmat + seed, extra)
        i1 = m.vert((b[0], base, b[1]), nrm, wcol, (L / 2, base - g), wallmat + seed, extra)
        i2 = m.vert((b[0], wall_top, b[1]), nrm, wcol, (L / 2, wall_top - g), wallmat + seed, extra)
        i3 = m.vert((a[0], wall_top, a[1]), nrm, wcol, (-L / 2, wall_top - g), wallmat + seed, extra)
        m.quad(i0, i1, i2, i3)
    # --- toit
    rmat = {"tiles": M_TILES, "slate": M_TILES, "metal": M_METAL, "flat": M_FLAT}[style]
    if gable and n == 4 and roof_h >= 0.2:
        gable_roof(m, ring, wall_top, roof_h, wcol, rcol, rmat + seed, wallmat + seed, floors)
        return m
    if style == "flat" or roof_h < 0.2:
        top = wall_top + 0.05
        # acrotère simple + toit plat
        ids = [m.vert((p[0], top, p[1]), (0, 1, 0), rcol, (p[0], p[1]), M_FLAT + seed) for p in ring]
        for t in range(0, len(tri := triangulate(ring)), 3):
            m.tri(ids[tri[t]], ids[tri[t + 2]], ids[tri[t + 1]])
        return m
    # avant-toit : anneau extérieur légèrement élargi et abaissé
    eave = inset_ring(ring, -0.45)
    # profondeur de l'arête : on cherche le plus grand retrait valide
    r_in = polylabel(poly, 0.2).distance(poly.exterior)
    d = r_in * 0.985
    inner = None
    while d > 0.3:
        cand = inset_ring(ring, d)
        cp = Polygon(cand)
        if cp.is_valid and cp.area > 0 and poly.buffer(0.01).contains(cp):
            inner = cand
            break
        d *= 0.8
    if inner is None:
        inner = inset_ring(ring, 0.3); d = 0.3
    slope = roof_h / max(d, 0.5)
    eave_y = wall_top - 0.45 * slope
    top_y = wall_top + roof_h * min(1.0, d / max(r_in, 0.5))
    for k in range(n):
        a = eave[k]; b = eave[(k + 1) % n]; c = inner[(k + 1) % n]; e = inner[k]
        pa = np.array([a[0], eave_y, a[1]]); pb = np.array([b[0], eave_y, b[1]])
        pc = np.array([c[0], top_y, c[1]]); pe = np.array([e[0], top_y, e[1]])
        nn = norm(np.cross(pb - pa, pe - pa))
        if nn[1] < 0:
            nn = -nn
        # uv : rangs de tuiles le long de la pente
        edge = norm(pb - pa)
        ids = []
        for p in (pa, pb, pc, pe):
            u = float(np.dot(p - pa, edge))
            v = float(np.linalg.norm((p - pa) - edge * np.dot(p - pa, edge)))
            ids.append(m.vert(p, nn, rcol, (u, v), rmat + seed))
        m.quad(*ids)
    # sous-face de l'avant-toit (sombre)
    for k in range(n):
        a = eave[k]; b = eave[(k + 1) % n]; c = ring[(k + 1) % n]; e = ring[k]
        ids = [m.vert((p[0], y, p[1]), (0, -1, 0), (0.25, 0.22, 0.2), (0, 0), M_PLAIN)
               for p, y in ((a, eave_y), (b, eave_y), (c, wall_top), (e, wall_top))]
        m.quad(ids[0], ids[3], ids[2], ids[1])
    # chapeau plat restant
    tri = triangulate(inner)
    if tri:
        ids = [m.vert((p[0], top_y, p[1]), (0, 1, 0), rcol, (p[0], p[1]), rmat + seed) for p in inner]
        for t in range(0, len(tri), 3):
            m.tri(ids[tri[t]], ids[tri[t + 2]], ids[tri[t + 1]])
    return m


def gable_roof(m, ring, wall_top, roof_h, wcol, rcol, rmat, wmat, floors):
    """Toit à deux pans débordant (lotissements du Bas-Dauphiné) : faîtage dans le grand axe,
    pignons enduits, large avant-toit sur consoles en bois."""
    P = [np.array(p, float) for p in ring]
    e = [np.linalg.norm(P[(k + 1) % 4] - P[k]) for k in range(4)]
    k0 = 0 if e[0] >= e[1] else 1                      # P[k0] -> P[k0+1] : grand côté
    A, B, C, D = P[k0], P[(k0 + 1) % 4], P[(k0 + 2) % 4], P[(k0 + 3) % 4]
    ax = (B - A) / np.linalg.norm(B - A); across = (D - A) / np.linalg.norm(D - A)
    W = np.linalg.norm(D - A)
    roof_h = min(roof_h, W * 0.45)
    ohs, ohg = 0.75, 0.6                                # débords en bas de pente et en pignon
    slope = roof_h / (W / 2)
    ridge_y = wall_top + roof_h
    eave_y = wall_top - ohs * slope
    M1, M2 = (A + D) / 2, (B + C) / 2                   # extrémités du faîtage
    E = lambda p, s: np.array([p[0], s, p[1]])
    under = (0.36, 0.27, 0.20)
    for side, (p0, p1) in enumerate(((A, B), (D, C))):
        out = -across if side == 0 else across
        q0 = p0 + out * ohs - ax * ohg; q1 = p1 + out * ohs + ax * ohg
        r0 = M1 - ax * ohg; r1 = M2 + ax * ohg
        pts = [E(q0, eave_y), E(q1, eave_y), E(r1, ridge_y), E(r0, ridge_y)]
        nn = norm(np.cross(pts[1] - pts[0], pts[3] - pts[0]))
        if nn[1] < 0:
            nn = -nn
        edge = norm(pts[1] - pts[0])
        up = nn * 0.16
        ids = []
        for p in pts:
            dd = p - pts[0]
            ids.append(m.vert(p + up, nn, rcol, (float(np.dot(dd, edge)), float(np.linalg.norm(dd - edge * np.dot(dd, edge)))), rmat))
        m.quad(*ids)
        ids = [m.vert(p, -nn, under, (0, 0), M_PLAIN) for p in pts]
        m.quad(*ids)
        # rives (planches) : bas de pente et pignons
        for a_, b_ in ((pts[0], pts[1]), (pts[1], pts[2]), (pts[3], pts[0])):
            ids = [m.vert(p, (0, 1, 0), under, (0, 0), M_PLAIN) for p in (a_, b_, b_ + up, a_ + up)]
            m.quad(*ids)
    # pignons enduits (triangles au-dessus des murs)
    for p0, p1 in ((A, D), (B, C)):
        mid = (p0 + p1) / 2
        v = mid - (A + C) / 2
        v = v / max(np.linalg.norm(v), 1e-6)
        nn = (float(v[0]), 0.0, float(v[1]))
        # uv.v élevé : pas de soubassement ni de fenêtres dans le triangle du pignon
        ids = [m.vert(E(p0, wall_top), nn, wcol, (0, 10.0), wmat, floors * 1000.0), m.vert(E(p1, wall_top), nn, wcol, (0, 10.0), wmat, floors * 1000.0),
               m.vert(E(mid, ridge_y), nn, wcol, (0, 10.0 + roof_h), wmat, floors * 1000.0)]
        m.tri(*ids)
        # consoles en bois sous l'avant-toit du pignon
        for t in (0.15, 0.5, 0.85):
            p = p0 + (p1 - p0) * t
            h = wall_top + roof_h * (1 - abs(t - 0.5) * 2) - 0.35
            dirv = ax if np.dot(mid - (A + C) / 2, ax) > 0 else -ax
            c = p + dirv * ohg / 2
            box_mesh(m, c[0], h, c[1], ohg, 0.14, 0.12, under, M_PLAIN, -math.atan2(dirv[1], dirv[0]))
    # chevrons apparents le long des bas de pente
    for p0, p1, out in ((A, B, -across), (D, C, across)):
        L = np.linalg.norm(p1 - p0)
        for k in range(1, int(L / 1.2)):
            p = p0 + (p1 - p0) * k / int(L / 1.2) + out * ohs / 2
            box_mesh(m, p[0], wall_top - ohs * slope / 2 - 0.05, p[1], ohs, 0.12, 0.08, under, M_PLAIN, -math.atan2(out[1], out[0]))


def box_mesh(m, cx, cy, cz, sx, sy, sz, col, mat, yaw=0.0, extra=0.0):
    c, s = math.cos(yaw), math.sin(yaw)
    def P(x, y, z):
        return (cx + x * c - z * s, cy + y, cz + x * s + z * c)
    def N(x, y, z):
        return (x * c - z * s, y, x * s + z * c)
    hx, hy, hz = sx / 2, sy / 2, sz / 2
    faces = [((1, 0, 0), [(hx, -hy, -hz), (hx, -hy, hz), (hx, hy, hz), (hx, hy, -hz)]),
             ((-1, 0, 0), [(-hx, -hy, hz), (-hx, -hy, -hz), (-hx, hy, -hz), (-hx, hy, hz)]),
             ((0, 0, 1), [(hx, -hy, hz), (-hx, -hy, hz), (-hx, hy, hz), (hx, hy, hz)]),
             ((0, 0, -1), [(-hx, -hy, -hz), (hx, -hy, -hz), (hx, hy, -hz), (-hx, hy, -hz)]),
             ((0, 1, 0), [(-hx, hy, -hz), (hx, hy, -hz), (hx, hy, hz), (-hx, hy, hz)]),
             ((0, -1, 0), [(-hx, -hy, hz), (hx, -hy, hz), (hx, -hy, -hz), (-hx, -hy, -hz)])]
    for n, pts in faces:
        ids = [m.vert(P(*p), N(*n), col, (p[0] + p[2], p[1] + hy), mat, extra) for p in pts]
        m.quad(*ids)


def church_extra(m, poly, ground, wall_top, top_alt, col):
    """Clocher carré + flèche à l'extrémité de la nef."""
    rect = poly.minimum_rotated_rectangle
    pts = list(rect.exterior.coords)[:4]
    e0 = np.subtract(pts[1], pts[0]); e1 = np.subtract(pts[2], pts[1])
    if np.linalg.norm(e0) < np.linalg.norm(e1):
        pts = pts[1:] + pts[:1]
        e0, e1 = e1, -e0
    L = np.linalg.norm(e0); W = np.linalg.norm(e1)
    ax = e0 / L
    yaw = math.atan2(ax[1], ax[0])
    side = min(W * 0.55, 7.0)
    c = np.mean(pts, axis=0) - ax * (L / 2 - side / 2)
    th = max(top_alt - 7.0, wall_top + 9.0)
    th = min(th, ground + 28.0)
    box_mesh(m, c[0], (ground - 1 + th) / 2, c[1], side, th - ground + 1, side, col, M_CHURCH, -yaw, extra=3000)
    # flèche
    tip = np.array([c[0], th + side * 1.2, c[1]])
    cs, sn = math.cos(-yaw), math.sin(-yaw)
    corners = []
    for sx, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
        x, z = sx * side / 2 * 1.05, sz * side / 2 * 1.05
        corners.append(np.array([c[0] + x * cs - z * sn, th, c[1] + x * sn + z * cs]))
    for k in range(4):
        a, b = corners[k], corners[(k + 1) % 4]
        nn = norm(np.cross(b - a, tip - a))
        if nn[1] < 0:
            nn = -nn
        ids = [m.vert(p, nn, (0.30, 0.32, 0.36), (0, 0), M_TILES + 0.5) for p in (a, b, tip)]
        m.tri(*ids)
    # croix
    box_mesh(m, tip[0], tip[1] + 0.8, tip[2], 0.12, 1.6, 0.12, (0.2, 0.2, 0.2), M_STEEL)
    box_mesh(m, tip[0], tip[1] + 1.1, tip[2], 0.7, 0.1, 0.1, (0.2, 0.2, 0.2), M_STEEL, -yaw)


def pool_mesh(poly, round_):
    """Piscine : bassin enterré à margelle blanche, ou piscine hors-sol ronde."""
    m = Mesh()
    ring = list(poly.exterior.coords)[:-1]
    xs, zs = np.array(ring).T
    hs = terrain.height(xs, zs)
    y = float(hs.max()) if not round_ else float(hs.min())
    water = (0.26, 0.66, 0.80)
    if round_:
        c = poly.centroid
        r = math.sqrt(poly.area / math.pi)
        n = 16
        pts = [(c.x + r * math.cos(2 * math.pi * k / n), c.y + r * math.sin(2 * math.pi * k / n)) for k in range(n)]
        for k in range(n):
            a, b = pts[k], pts[(k + 1) % n]
            nn = norm(((a[0] + b[0]) / 2 - c.x, 0, (a[1] + b[1]) / 2 - c.y))
            ids = [m.vert((p[0], yy, p[1]), nn, (0.55, 0.62, 0.66), (0, 0), M_STEEL) for p, yy in ((a, y - 0.2), (b, y - 0.2), (b, y + 1.15), (a, y + 1.15))]
            m.quad(*ids)
        ids = [m.vert((p[0], y + 1.05, p[1]), (0, 1, 0), water, (0, 0), M_GLASS) for p in pts]
        for k in range(1, n - 1):
            m.tri(ids[0], ids[k], ids[k + 1])
        return m
    from shapely.geometry.polygon import orient
    outer = orient(poly.buffer(0.5, join_style=2), 1.0)
    inner = orient(poly, 1.0)
    oc = list(outer.exterior.coords)[:-1]; ic = list(inner.exterior.coords)[:-1]
    top = y + 0.12
    ids = [m.vert((p[0], top, p[1]), (0, 1, 0), water, (0, 0), M_GLASS) for p in ic]
    for k in range(1, len(ids) - 1):
        m.tri(ids[0], ids[k], ids[k + 1])
    # margelle (plage blanche)
    for k in range(len(oc)):
        a, b = oc[k], oc[(k + 1) % len(oc)]
        pa = min(ic, key=lambda q: math.dist(q, a)); pb = min(ic, key=lambda q: math.dist(q, b))
        q = [m.vert((p[0], top + 0.03, p[1]), (0, 1, 0), (0.88, 0.86, 0.80), (0, 0), M_PLAIN) for p in (a, b, pb, pa)]
        m.quad(*q)
        nn = norm((b[1] - a[1], 0, -(b[0] - a[0])))
        q = [m.vert((p[0], yy, p[1]), nn, (0.80, 0.78, 0.72), (0, 0), M_PLAIN) for p, yy in ((a, float(hs.min()) - 0.3), (b, float(hs.min()) - 0.3), (b, top + 0.03), (a, top + 0.03))]
        m.quad(*q)
    return m


# ----------------------------------------------------------------------------------- pylônes
def pylon_mesh(m, x, y, z, yaw, h):
    col = (0.55, 0.57, 0.58)
    base_w = 4.5; top_w = 1.2
    for sx, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
        # jambes inclinées approximées par 4 tronçons
        for k in range(4):
            t0, t1 = k / 4, (k + 1) / 4
            w0 = base_w + (top_w - base_w) * t0; w1 = base_w + (top_w - base_w) * t1
            wm = (w0 + w1) / 2
            box_mesh(m, x + sx * wm / 2 * math.cos(yaw) - sz * wm / 2 * math.sin(yaw), y + h * (t0 + t1) / 2,
                     z + sx * wm / 2 * math.sin(yaw) + sz * wm / 2 * math.cos(yaw), 0.25, h / 4 + 0.1, 0.25, col, M_STEEL)
    # ceintures et traverses
    for t in (0.25, 0.5, 0.75):
        w = base_w + (top_w - base_w) * t
        box_mesh(m, x, y + h * t, z, w, 0.15, 0.15, col, M_STEEL, yaw)
        box_mesh(m, x, y + h * t, z, 0.15, 0.15, w, col, M_STEEL, yaw)
    arms = []
    for t, span in ((0.78, 7.0), (0.92, 5.5)):
        box_mesh(m, x, y + h * t, z, span, 0.35, 0.5, col, M_STEEL, yaw)
        for s in (-1, 1):
            arms.append((x + s * span / 2 * math.cos(yaw), y + h * t - 1.6, z + s * span / 2 * math.sin(yaw)))
            # isolateurs
            box_mesh(m, arms[-1][0], arms[-1][1] + 0.8, arms[-1][2], 0.18, 1.6, 0.18, (0.35, 0.45, 0.40), M_PLAIN)
    box_mesh(m, x, y + h + 1.0, z, 0.3, 2.0, 0.3, col, M_STEEL)
    return arms


def cable_mesh(m, p0, p1, sag):
    n = 12
    pts = []
    for k in range(n + 1):
        t = k / n
        p = np.array(p0) + (np.array(p1) - np.array(p0)) * t
        p[1] -= sag * 4 * t * (1 - t)
        pts.append(p)
    w = 0.035
    for k in range(n):
        a, b = pts[k], pts[k + 1]
        d = norm(b - a)
        side = norm(np.cross(d, [0, 1, 0])) * w
        up = norm(np.cross(side, d)) * w
        for off in (side, up):
            ids = [m.vert(p + o, (0, 1, 0), (0.15, 0.15, 0.16), (0, 0), M_CABLE) for p, o in
                   ((a, -off), (b, -off), (b, off), (a, off))]
            m.quad(*ids)


# ----------------------------------------------------------------------------------- main
def main():
    global terrain
    H, tx0, tz0, tst = read_grid(os.path.join(ASSETS, "terrain.bin"))
    terrain = Grid(H, tx0, tz0, tst)
    meta = json.load(open(os.path.join(ASSETS, "map.json")))
    nodes = meta["nodes"]
    import center
    center.setup(terrain, Mesh)

    W = int(round((X1 - X0) / LC_RES)); Hh = int(round((Z1 - Z0) / LC_RES))
    cls = Image.new("L", (W, Hh), MEADOW)
    ang = Image.new("L", (W, Hh), 0)
    rnd = Image.new("L", (W, Hh), 128)
    dc, da, dr = ImageDraw.Draw(cls), ImageDraw.Draw(ang), ImageDraw.Draw(rnd)

    def px(p):
        return [((x - X0) / LC_RES, (z - Z0) / LC_RES) for x, z in p]

    def fill(poly, c, a=None, r=None):
        for p in polys(poly):
            if p.area < 1:
                continue
            dc.polygon(px(p.exterior.coords), fill=c)
            if a is not None:
                da.polygon(px(p.exterior.coords), fill=a)
            if r is not None:
                dr.polygon(px(p.exterior.coords), fill=r)
            for hole in p.interiors:
                dc.polygon(px(hole.coords), fill=MEADOW)

    # masques à 1 m pour placer les arbres (routes, bâtiments, eau)
    MW, MH = int(X1 - X0), int(Z1 - Z0)
    block = Image.new("L", (MW, MH), 0)
    db = ImageDraw.Draw(block)

    def mpx(p):
        return [(x - X0, z - Z0) for x, z in p]

    for w in meta["ways"]:
        pts = [(nodes[i][0] - X0, nodes[i][1] - Z0) for i in w["nd"]]
        db.line(pts, fill=255, width=int(w["w"] + 4))
    # emprise de la voie ferrée (ballast + accotements) : ni arbres ni bâtiments
    rr = os.path.join(DATA, "road_rows.pkl")
    if os.path.exists(rr):
        import pickle
        for r in pickle.load(open(rr, "rb")):
            # tracé réellement affiché (lissé), pas le tracé simplifié du graphe
            extra = 8 if r["cls"] == "rail" else 6
            db.line([(x - X0, z - Z0) for x, z in r["P"]], fill=255, width=int(r["width"] + extra))
    road_mask = np.array(block) > 0

    # --- parcelles agricoles (RPG 2025)
    nfield = 0
    for f in load("rpg"):
        g = loc(f["geometry"]).intersection(CLIP)
        if g.is_empty:
            continue
        c = RPG.get(f["properties"].get("code_cultu"), MOWED)
        for p in polys(g):
            rect = p.minimum_rotated_rectangle
            cc = list(rect.exterior.coords)
            e0 = np.subtract(cc[1], cc[0]); e1 = np.subtract(cc[2], cc[1])
            e = e0 if np.linalg.norm(e0) > np.linalg.norm(e1) else e1
            a = (math.atan2(e[1], e[0]) % math.pi) / math.pi * 255
            fill(p.buffer(-1.5), c, int(a), rng.randint(0, 255))
            nfield += 1
    print(nfield, "parcelles")

    # --- bâtiments
    buildings = []
    for f in load("batiment"):
        pr = f["properties"]
        g = loc(f["geometry"])
        if not CLIP.contains(g.centroid):
            continue
        for p in polys(g):
            if p.area >= 6:
                buildings.append((p, pr))
    # dégager la chaussée : les bâtiments qui empiètent sur une route sont rognés (ou supprimés)
    from shapely.strtree import STRtree
    road_bufs = [LineString([nodes[i] for i in w["nd"]]).buffer(w["w"] / 2 + 0.6, cap_style=2) for w in meta["ways"]]
    rtree = STRtree(road_bufs)
    kept, clipped, dropped = [], 0, 0
    for p, pr in buildings:
        near = [road_bufs[j] for j in rtree.query(p) if road_bufs[j].intersects(p)]
        if near:
            q = p.difference(unary_union(near))
            if q.area < 0.6 * p.area or q.area < 8:
                dropped += 1
                continue
            parts = sorted(polys(q), key=lambda g: -g.area)
            p = parts[0]
            clipped += 1
        kept.append((p, pr))
    buildings = kept
    print(len(buildings), "bâtiments (", clipped, "rognés,", dropped, "supprimés sur la chaussée )")
    garden = Image.new("L", (W, Hh), 0); dg = ImageDraw.Draw(garden)
    yard = Image.new("L", (W, Hh), 0); dy = ImageDraw.Draw(yard)
    for p, pr in buildings:
        u = pr.get("usage_1")
        if (u == "Industriel" and p.area > 300) or (u == "Commercial et services" and p.area > 900):
            dy.polygon(px(p.buffer(9, join_style=2).exterior.coords), fill=255)
        elif u in ("Résidentiel", "Indifférencié", "Annexe") and p.area < 500:
            dg.polygon(px(p.buffer(13).exterior.coords), fill=255)
        db.polygon(mpx(p.buffer(1.5).exterior.coords), fill=255)
    cl = np.array(cls)
    cl[(np.array(garden) > 0) & (cl == MEADOW)] = GARDEN
    cl[(np.array(yard) > 0) & ((cl == MEADOW) | (cl == GARDEN))] = YARD
    # village de Rochetoirin : sol réel autour des maisons d'après l'orthophoto IGN
    village = None
    if os.path.exists(os.path.join(DATA, "ortho_village.jpg")):
        from prepare_village import Village
        village = Village()
        vr = village.rect()
        zone = unary_union([p.buffer(22) for p, pr in buildings if vr.contains(p.centroid)]).intersection(vr.buffer(-2))
    cls = Image.fromarray(cl); dc = ImageDraw.Draw(cls)

    # --- végétation
    forests, hedges_poly, poplars, orchards, landes = [], [], [], [], []
    for f in load("vegetation"):
        nat = f["properties"]["nature"]
        g = loc(f["geometry"]).intersection(CLIP)
        if g.is_empty:
            continue
        if nat == "Haie":
            fill(g, HEDGE); hedges_poly.append(g)
        elif nat == "Peupleraie":
            fill(g, FOREST); poplars.append(g)
        elif nat == "Verger":
            orchards.append(g)
        elif nat == "Lande ligneuse":
            fill(g, FALLOW); landes.append(g)
        else:
            fill(g, FOREST); forests.append((g, nat == "Forêt ouverte"))
    for f in load("cimetiere"):
        fill(loc(f["geometry"]).intersection(CLIP), GRAVEL)
    for f in load("sport"):
        g = loc(f["geometry"]).intersection(CLIP)
        nd = (f["properties"].get("nature_detaillee") or "") + (f["properties"].get("nature") or "")
        fill(g, TURF if ("foot" in nd.lower() or "rugby" in nd.lower() or "Grand" in nd) else GRAVEL)
    # centre du village : place en gravier, parkings en enrobé, square
    center.landcover(fill, YARD, GRAVEL, GARDEN)
    if village is not None:
        cl = np.array(cls)
        print(village.landcover(cl, X0, Z0, LC_RES, zone, GARDEN, YARD, MEADOW, FOREST), "cellules de sol d'après l'orthophoto")
        cls = Image.fromarray(cl); dc = ImageDraw.Draw(cls)

    # --- eau
    props = Chunks()
    ponds = []
    for f in load("surface_eau"):
        g = loc(f["geometry"]).intersection(CLIP)
        if g.is_empty:
            continue
        nat = f["properties"]["nature"]
        for p in polys(g):
            if p.area < 30:
                continue
            fill(p, WATER)
            db.polygon(mpx(p.exterior.coords), fill=255)
            ponds.append((p, nat != "Ecoulement naturel"))
    water_mesh(ponds, props)

    # ruisseaux (hors zones déjà couvertes par une surface d'eau)
    water_union = unary_union([p for p, _ in ponds]) if ponds else Polygon()
    nstream = 0
    for f in load("cours_eau"):
        pr = f["properties"]
        if pr.get("position_par_rapport_au_sol") not in (None, "0") or pr.get("fictif"):
            continue
        g = loc(f["geometry"]).intersection(CLIP)
        for line in ([g] if isinstance(g, LineString) else list(getattr(g, "geoms", []))):
            if not isinstance(line, LineString) or line.length < 10:
                continue
            if water_union.contains(line.interpolate(0.5, normalized=True)):
                continue
            width = 6.0 if "5 et 15" in (pr.get("classe_de_largeur") or "") else 2.2
            stream_mesh(line, width, road_mask, props)
            nstream += 1
    print(nstream, "ruisseaux")

    # --- maillages des bâtiments
    nb = 0
    nroof = 0
    quartier_zone = None
    if os.path.exists(os.path.join(DATA, "cadastre_balcon.json")):
        from prepare_quartier import in_zone as quartier_zone
    custom, roads_union = center.buildings(meta)
    for x, z, m, big in custom:
        props.add(x, z, m, big)
    print(len(custom), "modèles dédiés au centre du village")
    for p, pr in buildings:
        ov = center.override(p, pr)
        if ov == "skip":
            continue
        xs, zs = np.array(p.exterior.coords).T
        g = terrain.height(xs, zs)
        gmin, gmax = float(g.min()), float(g.max())
        usage = pr.get("usage_1") or "Indifférencié"
        nature = pr.get("nature") or ""
        h = pr.get("hauteur") or (2.6 if usage == "Annexe" else 6.0)
        if usage == "Annexe" or p.area < 25:
            h = min(h, 3.2)
        wall_top = max(gmin + h, gmax + 2.2)
        style = roof_style(pr.get("materiaux_de_la_toiture"), usage, p.area)
        roof_h = 0.0
        if pr.get("altitude_maximale_toit") and pr.get("altitude_minimale_sol"):
            roof_h = pr["altitude_maximale_toit"] - pr["altitude_minimale_sol"] - h
        r_in = polylabel(p, 0.5).distance(p.exterior)
        if style in ("tiles", "slate"):
            roof_h = min(max(roof_h, r_in * 0.62), r_in * 1.1, 6.0)
        elif style == "metal":
            roof_h = min(max(roof_h, r_in * 0.25), r_in * 0.4, 3.0)
        rcol = jitter(rng.choice(TILES), 0.03) if style == "tiles" else \
            (jitter((0.27, 0.29, 0.32), 0.02) if style == "slate" else
             (jitter(rng.choice([(0.58, 0.60, 0.60), (0.45, 0.30, 0.25), (0.35, 0.42, 0.38), (0.62, 0.62, 0.58)]), 0.02)
              if style == "metal" else jitter((0.50, 0.50, 0.48), 0.03)))
        wcol = wall_color(pr.get("materiaux_des_murs"), usage)
        wallmat = M_WALL
        if usage in ("Industriel", "Agricole") or (usage == "Commercial et services" and p.area > 300):
            wallmat = M_INDUS_WALL
        if usage == "Annexe" or h < 3.0:
            wallmat = M_PLAIN
        if nature == "Eglise" or usage == "Religieux":
            wallmat = M_CHURCH; wcol = jitter(STONE[0], 0.02); style = "tiles"
        if nature == "Serre":
            wallmat = M_GLASS; style = "metal"; wcol = (0.75, 0.82, 0.85); rcol = (0.80, 0.86, 0.88)
        seed = rng.random() * 0.98
        if ov:
            if "h" in ov:
                wall_top = max(gmin + ov["h"], gmax + 2.2)
            roof_h = ov.get("roof_h", roof_h)
            wcol = ov.get("wcol", wcol); rcol = ov.get("rcol", rcol); seed = ov.get("seed", seed)
            style = "tiles"
        if village is not None and not (ov and "rcol" in ov) and nature != "Eglise":
            rc = village.roof_color(p)
            if rc is not None:
                rcol = rc
                nroof += 1
        floors = max(1, int(round((wall_top - gmin) / 2.9)))
        gable = False
        if quartier_zone is not None and quartier_zone(p.centroid.x, p.centroid.y) and style == "tiles" \
                and usage in ("Résidentiel", "Indifférencié") and p.area > 40 and nature != "Eglise":
            mrr = p.minimum_rotated_rectangle
            if p.area / mrr.area > 0.85:
                # lotissement de la rue du Balcon (d'après Street View) : deux pans, enduit crème, volets bois
                gable = True
                roof_h = max(roof_h, 2.4)
                wcol = jitter(rng.choice([(0.90, 0.84, 0.70), (0.88, 0.80, 0.64), (0.91, 0.86, 0.74), (0.86, 0.78, 0.62)]), 0.02)
                seed = rng.choice([rng.uniform(0.0, 0.16), rng.uniform(0.84, 0.97)])     # volets bruns ou bordeaux
                if pr.get("hauteur") and pr["hauteur"] > 4.5:
                    wall_top = max(wall_top, gmin + 5.6)
                floors = max(1, int(round((wall_top - gmin) / 2.9)))
        # léger retrait : évite que deux murs mitoyens soient confondus (scintillement)
        pm = p.buffer(-0.12, join_style=2)
        if pm.is_empty or not isinstance(pm, Polygon):
            pm = p
        m = building_mesh(pm if not gable else p, gmin, wall_top, roof_h, style, wcol, rcol, wallmat, seed, floors, gable)
        if m is None:
            continue
        if nature == "Eglise":
            church_extra(m, p, gmin, wall_top, (pr.get("altitude_maximale_toit") or (gmin + 20)), wcol)
        if ov:
            center.dressed_extras(m, p, ov, gmin, wall_top, roads_union)
        c = p.centroid
        props.add(c.x, c.y, m, big=p.area > 60 or wall_top - gmin > 7)
        nb += 1
    print(nb, "bâtiments maillés,", nroof, "toits colorés d'après l'orthophoto")
    if village is not None:
        npool = 0
        for poly, round_ in village.pools():
            if any(p.intersects(poly) for p, _ in buildings if p.distance(poly) < 1):
                continue
            if center.in_area(poly.centroid.x, poly.centroid.y):
                continue      # centre : toits et bâches bleutés pris pour des piscines
            props.add(poly.centroid.x, poly.centroid.y, pool_mesh(poly, round_), big=False)
            npool += 1
        print(npool, "piscines")

    # --- pylônes et lignes électriques
    pylons = []
    for f in load("pylone"):
        x, z = to_local(*f["geometry"]["coordinates"][:2])
        if CLIP.contains(Point(float(x), float(z))):
            pylons.append((float(x), float(z)))
    nl = 0
    for f in load("ligne_electrique"):
        g = loc(f["geometry"])
        pts = [p for p in g.coords]
        # on accroche chaque sommet au pylône le plus proche
        chain = []
        for x, z in pts:
            if not pylons:
                break
            d = [math.hypot(x - a, z - b) for a, b in pylons]
            k = int(np.argmin(d))
            if d[k] < 25 and (not chain or chain[-1] != k):
                chain.append(k)
        arms_prev = None
        for idx, k in enumerate(chain):
            x, z = pylons[k]
            nxt = pylons[chain[min(idx + 1, len(chain) - 1)]]; prv = pylons[chain[max(idx - 1, 0)]]
            yaw = math.atan2(nxt[1] - prv[1], nxt[0] - prv[0]) + math.pi / 2
            y = terrain.height(x, z)
            m = Mesh()
            arms = pylon_mesh(m, x, y, z, yaw, 24.0)
            if arms_prev is not None:
                # ordonner les bras pour éviter les croisements
                for a in arms_prev:
                    b = min(arms, key=lambda q: math.hypot(q[0] - a[0] - (x - arms_prev[0][0]), q[2] - a[2] - (z - arms_prev[0][2])))
                    span = math.dist(a, b)
                    cable_mesh(m, a, b, span * span / 9000.0)
            props.add(x, z, m, big=True)
            arms_prev = arms
            nl += 1
    print(nl, "pylônes reliés")

    nv, size = props.write(os.path.join(ASSETS, "props.bin"), b"PRP1")
    print("décor : %d sommets, %.1f Mo" % (nv, size / 1e6))

    # --- écriture de l'occupation du sol
    Image.merge("RGB", (cls, ang, rnd)).save(os.path.join(ASSETS, "landcover.png"), optimize=True)
    water_carve(ponds, H, tx0, tz0, tst)

    # --- arbres
    blockm = np.array(block) > 0
    trees(forests, hedges_poly, poplars, orchards, landes, buildings, blockm, np.array(cls), center.tree_instances(), village)
    # --- collisions
    write_collisions(buildings)
    # --- lointain
    landfar()
    pano()


# ----------------------------------------------------------------------------------- eau
def water_mesh(ponds, props):
    for p, flat in ponds:
        ring = list(p.exterior.coords)[:-1]
        xs, zs = np.array(ring).T
        hb = terrain.height(xs, zs)
        tri = triangulate(ring)
        if not tri:
            continue
        m = Mesh()
        if flat:
            lvl = float(np.percentile(hb, 10)) + 0.05
            ids = [m.vert((x, lvl, z), (0, 1, 0), (0.2, 0.3, 0.3), (x, z), M_WATER) for x, z in ring]
        else:
            ids = [m.vert((x, h + 0.25, z), (0, 1, 0), (0.2, 0.3, 0.3), (x, z), M_WATER) for (x, z), h in zip(ring, hb)]
        for t in range(0, len(tri), 3):
            m.tri(ids[tri[t]], ids[tri[t + 2]], ids[tri[t + 1]])
        c = p.centroid
        props.add(c.x, c.y, m, big=True)


def water_carve(ponds, H, x0, z0, st):
    """Abaisse le fond des étangs pour que l'eau soit bien visible, puis réécrit terrain.bin."""
    nz, nx = H.shape
    xs = x0 + np.arange(nx) * st; zs = z0 + np.arange(nz) * st
    changed = 0
    for p, flat in ponds:
        if not flat:
            continue
        ring = np.array(p.exterior.coords)
        lvl = float(np.percentile(terrain.height(ring[:, 0], ring[:, 1]), 10)) + 0.05
        inner = p.buffer(-4)
        if inner.is_empty:
            continue
        mnx, mnz, mxx, mxz = inner.bounds
        for j in np.where((zs >= mnz) & (zs <= mxz))[0]:
            for i in np.where((xs >= mnx) & (xs <= mxx))[0]:
                if inner.contains(Point(xs[i], zs[j])) and H[j, i] > lvl - 1.0:
                    H[j, i] = lvl - 1.0
                    changed += 1
    path = os.path.join(ASSETS, "terrain.bin")
    head = open(path, "rb").read()[:24]
    open(path, "wb").write(head + H.astype("<f4").tobytes())
    print(changed, "points de terrain abaissés sous les étangs")


def stream_mesh(line, width, road_mask, props):
    L = line.length
    n = max(2, int(L / 4))
    pts = np.array([line.interpolate(t * L / n).coords[0] for t in range(n + 1)])
    T = np.gradient(pts, axis=0)
    T /= np.maximum(np.linalg.norm(T, axis=1, keepdims=True), 1e-6)
    N = np.stack([-T[:, 1], T[:, 0]], axis=1)
    hw = width / 2
    left = pts + N * hw; right = pts - N * hw
    hl = terrain.height(left[:, 0], left[:, 1]); hr = terrain.height(right[:, 0], right[:, 1])
    hc = terrain.height(pts[:, 0], pts[:, 1])
    y = np.maximum(np.maximum(hl, hr), hc) + 0.06
    # profil lissé et monotone vers l'aval (pas de cascade inversée)
    y = np.convolve(np.pad(y, 2, mode="edge"), np.ones(5) / 5, mode="valid")
    y = np.maximum(y, np.maximum(hl, hr) + 0.04)
    m = None
    for k in range(n):
        mid = (pts[k] + pts[k + 1]) / 2
        ix, iz = int(mid[0] - X0), int(mid[1] - Z0)
        if 0 <= iz < road_mask.shape[0] and 0 <= ix < road_mask.shape[1] and road_mask[iz, ix]:
            continue
        m = Mesh()
        ids = [m.vert((p[0], yy, p[1]), (0, 1, 0), (0.2, 0.3, 0.3), (s, lat), M_STREAM, hw)
               for p, yy, s, lat in ((left[k], y[k], k * 4.0, -hw), (right[k], y[k], k * 4.0, hw),
                                     (right[k + 1], y[k + 1], (k + 1) * 4.0, hw), (left[k + 1], y[k + 1], (k + 1) * 4.0, -hw))]
        m.quad(ids[0], ids[3], ids[2], ids[1])
        props.add(mid[0], mid[1], m, big=True)


# ----------------------------------------------------------------------------------- arbres
T_OAK, T_BUSH, T_POPLAR, T_CONIFER, T_FRUIT, T_SHRUB = range(6)


def trees(forests, hedges_poly, poplars, orchards, landes, buildings, block, cls, extra=(), village=None):
    import center
    inst = []

    def free(x, z):
        ix, iz = int(x - X0), int(z - Z0)
        return 0 <= iz < block.shape[0] and 0 <= ix < block.shape[1] and not block[iz, ix]

    def add(x, z, t, h):
        if village is not None and village.contains(x, z):
            return          # zone couverte par l'orthophoto : arbres réels ajoutés plus bas
        ci, cj = int((x - X0) / LC_RES), int((z - Z0) / LC_RES)
        if 0 <= cj < cls.shape[0] and 0 <= ci < cls.shape[1] and cls[cj, ci] in (YARD, GRAVEL) and center.in_area(x, z):
            return          # pas d'arbre au milieu d'un parking ou d'une place
        if free(x, z):
            inst.append((x, float(terrain.height(x, z)), z, h, t, rng.random()))

    def scatter(g, spacing, fn, jit=0.45):
        from shapely.prepared import prep
        for p in polys(g):
            pp = prep(p)
            mnx, mnz, mxx, mxz = p.bounds
            x = mnx + rng.random() * spacing
            while x < mxx:
                z = mnz + rng.random() * spacing
                while z < mxz:
                    xx = x + rng.uniform(-jit, jit) * spacing; zz = z + rng.uniform(-jit, jit) * spacing
                    if pp.contains(Point(xx, zz)):
                        fn(xx, zz)
                    z += spacing
                x += spacing

    if village is not None:
        hedge_near = lambda x, z, r: False
        if os.path.exists(os.path.join(DATA, "cadastre_balcon.json")):
            # quartier de la rue du Balcon : les haies sont modélisées en continu (prepare_street)
            from prepare_quartier import Quartier
            from shapely.strtree import STRtree
            hl = Quartier(village, terrain, [p for p, _ in buildings]).hedge_lines()
            if hl:
                ht = STRtree(hl)
                # les petits houppiers le long d'une limite font partie de la haie (déjà modélisée)
                from prepare_quartier import in_zone

                def hedge_near(x, z, r):
                    # dans le quartier, la végétation étroite est tracée en haies : seuls les houppiers larges restent des arbres
                    return in_zone(x, z) and r < 1.6
        real = village.trees(lambda x, z, r: not free(x, z) or hedge_near(x, z, r) or center.in_square(x, z))
        for x, z, t, h in real:
            inst.append((x, float(terrain.height(x, z)), z, h, t, rng.random()))
        print(len(real), "arbres, arbustes et haies d'après l'orthophoto")
    for x, z, t, h in extra:      # arbres placés à la main (centre du village), hors chaussée
        if free(x, z):
            inst.append((x, float(terrain.height(x, z)), z, h, t, rng.random()))
    for g, open_ in forests:
        scatter(g, 13.0 if open_ else 8.5,
                lambda x, z: add(x, z, T_CONIFER if rng.random() < 0.08 else T_OAK, rng.uniform(13, 23)))
    for g in poplars:
        rect = g.minimum_rotated_rectangle
        scatter(g, 7.0, lambda x, z: add(x, z, T_POPLAR, rng.uniform(20, 27)), jit=0.08)
    for g in orchards:
        scatter(g, 6.5, lambda x, z: add(x, z, T_FRUIT, rng.uniform(4, 6.5)), jit=0.1)
    for g in landes:
        scatter(g, 6.0, lambda x, z: add(x, z, T_SHRUB if rng.random() < 0.6 else T_BUSH, rng.uniform(2, 5)))
    for g in hedges_poly:
        scatter(g, 4.2, lambda x, z: add(x, z, T_OAK if rng.random() < 0.18 else (T_BUSH if rng.random() < 0.7 else T_SHRUB),
                                          rng.uniform(4, 9)))
    # haies linéaires
    for f in load("haie"):
        g = loc(f["geometry"]).intersection(CLIP)
        for line in ([g] if isinstance(g, LineString) else list(getattr(g, "geoms", []))):
            if not isinstance(line, LineString):
                continue
            L = line.length
            s = rng.uniform(0, 2)
            while s < L:
                p = line.interpolate(s)
                r = rng.random()
                if r < 0.16:
                    add(p.x + rng.uniform(-1, 1), p.y + rng.uniform(-1, 1), T_OAK, rng.uniform(10, 18))
                else:
                    add(p.x + rng.uniform(-0.7, 0.7), p.y + rng.uniform(-0.7, 0.7), T_BUSH if r < 0.75 else T_SHRUB, rng.uniform(3, 6))
                s += rng.uniform(2.8, 4.2)
    # jardins : arbres d'ornement autour des maisons
    for p, pr in buildings:
        if pr.get("usage_1") not in ("Résidentiel", "Indifférencié") or p.area > 400:
            continue
        c = p.centroid
        for _ in range(rng.choice([0, 1, 1, 2, 2, 3])):
            a = rng.uniform(0, 2 * math.pi); d = rng.uniform(8, 16)
            x, z = c.x + math.cos(a) * d, c.y + math.sin(a) * d
            r = rng.random()
            if r < 0.30:
                add(x, z, T_CONIFER, rng.uniform(6, 14))
            elif r < 0.55:
                add(x, z, T_FRUIT, rng.uniform(4, 7))
            elif r < 0.75:
                add(x, z, T_SHRUB, rng.uniform(1.5, 3))
            else:
                add(x, z, T_OAK, rng.uniform(8, 14))
    # arbres isolés dans les prés (bocage)
    hh, ww = cls.shape
    for _ in range(int((X1 - X0) * (Z1 - Z0) / 9000)):
        x = rng.uniform(X0 + 50, X1 - 50); z = rng.uniform(Z0 + 50, Z1 - 50)
        c = cls[int((z - Z0) / LC_RES), int((x - X0) / LC_RES)]
        if c in (PASTURE, MEADOW) and rng.random() < 0.5:
            add(x, z, T_OAK, rng.uniform(10, 19))

    print(len(inst), "arbres et arbustes")
    nCx = int(math.ceil((X1 - X0) / CHUNK)); nCz = int(math.ceil((Z1 - Z0) / CHUNK))
    buckets = {}
    for t in inst:
        k = (min(nCx - 1, int((t[0] - X0) // CHUNK)), min(nCz - 1, int((t[2] - Z0) // CHUNK)))
        buckets.setdefault(k, []).append(t)
    out = bytearray(struct.pack("<4sfffiii", b"TRE1", X0, Z0, CHUNK, nCx, nCz, len(buckets)))
    for (cx, cz), l in sorted(buckets.items()):
        out += struct.pack("<iii", cx, cz, len(l))
        out += np.asarray(l, dtype="<f4").tobytes()
    open(os.path.join(ASSETS, "trees.bin"), "wb").write(out)
    print("arbres : %.1f Mo" % (len(out) / 1e6))


def write_collisions(buildings):
    out = bytearray()
    n = 0
    for p, pr in buildings:
        q = p.simplify(0.3)
        if not isinstance(q, Polygon) or q.area < 6:
            continue
        ring = list(q.exterior.coords)[:-1]
        out += struct.pack("<i", len(ring)) + np.asarray(ring, dtype="<f4").tobytes()
        n += 1
    blob = struct.pack("<4si", b"COL1", n) + out
    open(os.path.join(ASSETS, "collide.bin"), "wb").write(blob)
    open(os.path.join(DATA, "collide_buildings.bin"), "wb").write(blob)   # copie de référence pour prepare_street
    print(n, "emprises de collision")


# ----------------------------------------------------------------------------------- lointain
def landfar():
    """Forêts, eau et zones bâties de l'anneau lointain (25 m/pixel)."""
    res = 25.0
    W = int((OUTER["xmax"] - OUTER["xmin"]) / res); Hh = int((OUTER["zmax"] - OUTER["zmin"]) / res)
    img = Image.new("L", (W, Hh), 0)
    d = ImageDraw.Draw(img)

    def px(p):
        return [((x - OUTER["xmin"]) / res, (z - OUTER["zmin"]) / res) for x, z in p]
    for f in load("batiment_far"):
        for p in polys(loc(f["geometry"])):
            d.polygon(px(p.buffer(12).exterior.coords), fill=3)
    for f in load("vegetation_far"):
        if f["properties"]["nature"] in ("Haie", "Verger", "Lande ligneuse"):
            continue
        for p in polys(loc(f["geometry"])):
            if p.area > 2000:
                d.polygon(px(p.exterior.coords), fill=1)
    for f in load("surface_eau_far"):
        for p in polys(loc(f["geometry"])):
            if p.area > 500:
                d.polygon(px(p.exterior.coords), fill=2)
    a = np.array(img) * 60
    Image.fromarray(a.astype(np.uint8)).save(os.path.join(ASSETS, "landfar.png"), optimize=True)
    print("landfar", img.size)


def pano():
    p = os.path.join(DATA, "elev_pano.npy")
    if not os.path.exists(p):
        print("pas de panorama"); return
    Hp = np.load(p).astype(np.float64)
    nx, nz = grid_shape(PANO)
    xs = PANO["xmin"] + np.arange(nx) * PANO["step"]; zs = PANO["zmin"] + np.arange(nz) * PANO["step"]
    X, Z = np.meshgrid(xs, zs)
    d2 = X ** 2 + Z ** 2
    Hp = Hp - d2 / (2 * 6371000 / (1 - 0.13))       # courbure terrestre + réfraction
    # sous l'anneau lointain : légèrement enterré pour éviter les chevauchements
    inside = (X > OUTER["xmin"] - 600) & (X < OUTER["xmax"] + 600) & (Z > OUTER["zmin"] - 600) & (Z < OUTER["zmax"] + 600)
    Hp[inside] -= 25
    with open(os.path.join(ASSETS, "pano.bin"), "wb") as f:
        f.write(struct.pack("<4siifff", b"TER1", nx, nz, PANO["xmin"], PANO["zmin"], PANO["step"]))
        f.write(Hp.astype("<f4").tobytes())
    print("panorama", nx, nz, "max %.0f m" % Hp.max())


if __name__ == "__main__":
    main()
