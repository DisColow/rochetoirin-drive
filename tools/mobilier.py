"""Mobilier et équipements du bourg absents de la BD TOPO, d'après OpenStreetMap (data/osm_bourg*.json) et Street View
(data/streetview/points/) : arrêts de bus (abribus bleu vitré de l'Église, poteaux, zigzags jaunes), croix de chemin en
pierre, terrains (foot, city-stade, tennis, boules), aire de jeux, table de pique-nique, borne de recharge,
poteau d'incendie, panneaux d'information.

build(add, add_coll, roads, Mesh, H) -> compteurs ; add(x, z, mesh, big), add_coll(anneau 2D), H(x, z) altitude du sol.
"""
import json, math, os
import numpy as np
from shapely.geometry import Polygon, Point, LineString
from geo import to_local

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "data")
(M_PLAIN, M_WALL, M_INDUS, M_TILES, M_METAL, M_FLAT, M_WATER, M_CHURCH, M_STEEL, M_CABLE, M_GLASS,
 M_STREAM, M_PAVE, M_CURB, M_GRASS, M_SIGN, M_LIGHT, M_RUBBLE, M_CREPI, M_HEDGE, M_GRAVEL, M_MESH) = range(22)

WHITE = (0.92, 0.92, 0.90)
YELLOW = (0.95, 0.78, 0.10)
WOOD = (0.50, 0.36, 0.24)
STONE = (0.80, 0.77, 0.70)
BLUE = (0.10, 0.30, 0.62)
GREEN_FENCE = (0.16, 0.34, 0.20)


def nrm(v):
    v = np.asarray(v, float)
    return v / max(np.linalg.norm(v), 1e-9)


def ring_box(x, z, ax, L, W):
    a = nrm(ax); b = np.array([-a[1], a[0]])
    c = np.array([x, z], float)
    return np.array([c - a * L / 2 - b * W / 2, c + a * L / 2 - b * W / 2, c + a * L / 2 + b * W / 2, c - a * L / 2 + b * W / 2])


def nodes():
    p = os.path.join(DATA, "osm_bourg.json")
    if not os.path.exists(p):
        return []
    out = []
    for e in json.load(open(p))["elements"]:
        if e["type"] != "node" or not e.get("tags"):
            continue
        x, z = to_local(e["lon"], e["lat"])
        out.append((float(x), float(z), e["tags"]))
    return out


def ways():
    p = os.path.join(DATA, "osm_bourg_ways.json")
    if not os.path.exists(p):
        return []
    out = []
    try:
        for e in json.load(open(p))["elements"]:
            pts = [tuple(float(v) for v in to_local(g["lon"], g["lat"])) for g in e.get("geometry", [])]
            if len(pts) >= 4:
                out.append((Polygon(pts).buffer(0), e.get("tags", {})))
    except ValueError:
        return []
    return out


def road_dir(roads, x, z):
    """Direction de la route la plus proche, normale vers le point, distance au bord."""
    best = None
    for r in roads:
        if r.cls == "rail":
            continue
        k, d = r.row_near(x, z)
        if best is None or d - r.hw < best[0]:
            best = (d - r.hw, r, k)
    if best is None:
        return np.array([1.0, 0.0]), np.array([0.0, 1.0]), 99.0, None, 0
    _, r, k = best
    t = nrm(r.T[k]); p = r.P[k]
    n = np.array([-t[1], t[0]])
    if np.dot(n, np.array([x, z]) - p) < 0:
        n = -n
    return t, n, best[0], r, k


def frame(c, t, n):
    """Repère local : u le long de la route, v vers l'extérieur."""
    c = np.asarray(c, float)
    return lambda u, v: c + t * u + n * v


def bus_shelter(m, obox, quad3, F, t, n, y):
    """Abribus métallique bleu à parois vitrées (modèle de l'arrêt « Rochetoirin - Église »)."""
    yaw_ax = t
    L, D, Hh = 3.2, 1.5, 2.35
    for u in (-L / 2, L / 2):
        for v in (0.1, D):
            p = F(u, v)
            obox(m, (p[0], y + Hh / 2, p[1]), yaw_ax, (0.09, Hh, 0.09), BLUE, M_STEEL)
    # toit légèrement incliné vers l'arrière
    p = F(0, D / 2 + 0.05)
    obox(m, (p[0], y + Hh + 0.05, p[1]), yaw_ax, (L + 0.3, 0.08, D + 0.35), BLUE, M_STEEL)
    obox(m, (p[0], y + Hh + 0.11, p[1]), yaw_ax, (L + 0.2, 0.04, D + 0.25), (0.75, 0.80, 0.84), M_GLASS)
    # parois vitrées : fond et côtés
    E = lambda q, yy: (q[0], yy, q[1])
    glass = (0.70, 0.78, 0.82)
    a, b = F(-L / 2, D), F(L / 2, D)
    quad3(m, E(a, y + 0.15), E(b, y + 0.15), E(b, y + Hh - 0.05), E(a, y + Hh - 0.05), glass, M_GLASS)
    for u in (-L / 2, L / 2):
        a, b = F(u, 0.15), F(u, D)
        quad3(m, E(a, y + 0.15), E(b, y + 0.15), E(b, y + Hh - 0.05), E(a, y + Hh - 0.05), glass, M_GLASS)
    # banc et panneau d'affichage
    p = F(0, D - 0.3)
    obox(m, (p[0], y + 0.45, p[1]), yaw_ax, (L - 0.6, 0.06, 0.35), (0.62, 0.64, 0.66), M_STEEL)
    for u in (-L / 2 + 0.6, L / 2 - 0.6):
        q = F(u, D - 0.3)
        obox(m, (q[0], y + 0.22, q[1]), yaw_ax, (0.06, 0.44, 0.3), (0.40, 0.42, 0.44), M_STEEL)
    q = F(L / 2 - 0.5, D - 0.05)
    obox(m, (q[0], y + 1.35, q[1]), yaw_ax, (0.8, 1.2, 0.05), (0.93, 0.93, 0.90), M_PLAIN)


def bus_pole(m, obox, prism, x, z, y, t):
    prism(m, x, y, y + 2.6, z, 0.04, 0.04, 6, (0.60, 0.62, 0.63), M_STEEL)
    obox(m, (x, y + 2.35, z), t, (0.45, 0.45, 0.04), BLUE, M_PLAIN)
    obox(m, (x, y + 2.35, z), t, (0.30, 0.20, 0.06), WHITE, M_PLAIN)


def zigzag(m, quad3, r, k, side, y_of, length=14.0):
    """Zigzags jaunes de l'arrêt de bus le long du bord de chaussée."""
    s0 = float(r.s[k]) - length / 2
    lat = side * (r.hw - 0.25)
    n_z = 7
    pts = []
    for i in range(n_z * 2 + 1):
        s = s0 + length * i / (n_z * 2)
        l = lat - side * (0.0 if i % 2 == 0 else 1.2)
        q, _, _ = r.at(s, l)
        pts.append(q)
    for a, b in zip(pts[:-1], pts[1:]):
        d = nrm([b[0] - a[0], b[2] - a[2]]); w = np.array([-d[1], d[0]]) * 0.06
        ya, yb = a[1] + 0.03, b[1] + 0.03
        quad3(m, (a[0] - w[0], ya, a[2] - w[1]), (b[0] - w[0], yb, b[2] - w[1]), (b[0] + w[0], yb, b[2] + w[1]),
              (a[0] + w[0], ya, a[2] + w[1]), YELLOW, M_PLAIN, n=(0, 1, 0))


def stone_cross(m, obox, x, z, y, t):
    obox(m, (x, y + 0.3, z), t, (1.1, 0.6, 1.1), (0.72, 0.70, 0.64), M_RUBBLE)
    obox(m, (x, y + 0.9, z), t, (0.55, 0.6, 0.55), STONE, M_PLAIN)
    obox(m, (x, y + 2.0, z), t, (0.18, 1.6, 0.18), STONE, M_PLAIN)
    obox(m, (x, y + 2.35, z), t, (0.9, 0.16, 0.16), STONE, M_PLAIN)


def flat_poly(m, poly, y, col, mat, quad3=None, poly3=None, dy=0.03):
    from center import poly3 as p3
    pts = list(poly.exterior.coords)[:-1]
    p3(m, [(x, y + dy, z) for x, z in pts], (0, 1, 0), col, mat)


def line_box(m, obox, a, b, y, w, col, mat=M_PLAIN, h=0.02):
    a = np.asarray(a, float); b = np.asarray(b, float)
    L = float(np.linalg.norm(b - a))
    if L < 0.05:
        return
    c = (a + b) / 2
    obox(m, (c[0], y + h / 2 + 0.02, c[1]), b - a, (L, h, w), col, mat)


def oriented(poly):
    """Rectangle orienté minimal : centre, axe long, longueur, largeur."""
    r = np.array(poly.minimum_rotated_rectangle.exterior.coords)[:4]
    e1, e2 = r[1] - r[0], r[2] - r[1]
    if np.linalg.norm(e1) < np.linalg.norm(e2):
        e1, e2 = e2, e1
    return r.mean(axis=0), nrm(e1), float(np.linalg.norm(e1)), float(np.linalg.norm(e2))


def goal(m, obox, c, ax, y, w=7.32, h=2.44, col=WHITE):
    b = np.array([-ax[1], ax[0]])
    for s in (-1, 1):
        p = c + b * s * w / 2
        obox(m, (p[0], y + h / 2, p[1]), ax, (0.12, h, 0.12), col, M_STEEL)
    obox(m, (c[0], y + h, c[1]), b, (w + 0.12, 0.12, 0.12), col, M_STEEL)
    # filet
    back = c - ax * 1.2
    obox(m, (back[0], y + h / 2, back[1]), b, (w, h, 0.02), (0.85, 0.85, 0.85), M_MESH, 0.0)


def fence_ring(m, obox, poly, H, h, col, kind=0.0, posts=2.5):
    """Clôture grillagée sur le pourtour (matériau ajouré)."""
    pts = list(poly.exterior.coords)
    for a, b in zip(pts[:-1], pts[1:]):
        a = np.array(a); b = np.array(b)
        L = float(np.linalg.norm(b - a))
        if L < 0.3:
            continue
        d = (b - a) / L
        n = max(1, int(L / 6))
        for k in range(n):
            p0 = a + d * L * k / n; p1 = a + d * L * (k + 1) / n
            c = (p0 + p1) / 2
            y = min(H(*p0), H(*p1))
            obox(m, (c[0], y + h / 2, c[1]), d, (L / n, h, 0.02), col, M_MESH + kind * 0.0, 0.0)
        for k in range(int(L / posts) + 1):
            p = a + d * min(L, k * posts)
            obox(m, (p[0], H(*p) + h / 2, p[1]), d, (0.06, h, 0.06), col, M_STEEL)


def build(add, add_coll, roads, Mesh, H):
    from center import obox, quad3, prism
    cnt = {}

    def count(k, n=1):
        cnt[k] = cnt.get(k, 0) + n

    # ---------------------------------------------------------------- arrêts de bus
    for x, z, t in nodes():
        if t.get("highway") != "bus_stop":
            continue
        tt, n, dist, r, k = road_dir(roads, x, z)
        if r is None:
            continue
        m = Mesh()
        # sur l'accotement, 1,2 m au-delà du bord de chaussée
        side = 1 if np.dot(r.N[k], n) > 0 else -1
        base = r.P[k] + n * (r.hw + 1.2)
        y = H(*base)
        if t.get("shelter") == "yes":
            F = lambda u, v, b=base: frame(b, tt, n)(u, v)
            bus_shelter(m, obox, quad3, F, tt, n, y)
            add_coll(ring_box(*(base + n * 0.8), tt, 3.4, 1.7))
            count("abribus")
        p = base + tt * 2.2
        bus_pole(m, obox, prism, p[0], p[1], H(*p), tt)
        add_coll(ring_box(p[0], p[1], tt, 0.2, 0.2))
        zigzag(m, quad3, r, k, side, H)
        add(base[0], base[1], m, False)
        count("arrêts de bus")
    # ---------------------------------------------------------------- croix de chemin
    for x, z, t in nodes():
        if t.get("historic") != "wayside_cross":
            continue
        tt, n, dist, r, k = road_dir(roads, x, z)
        if dist < 1.0 and r is not None:            # pas sur la chaussée
            x, z = r.P[k] + n * (r.hw + 1.5)
        m = Mesh()
        stone_cross(m, obox, x, z, H(x, z), tt)
        add(x, z, m, False)
        add_coll(ring_box(x, z, tt, 1.1, 1.1))
        count("croix de chemin")
    # ---------------------------------------------------------------- petits équipements
    for x, z, t in nodes():
        y = H(x, z)
        m = Mesh()
        if t.get("leisure") == "picnic_table":
            obox(m, (x, y + 0.75, z), (1, 0), (1.9, 0.06, 0.8), WOOD, M_PLAIN)
            for s in (-1, 1):
                obox(m, (x, y + 0.45, z + s * 0.65), (1, 0), (1.9, 0.05, 0.3), WOOD, M_PLAIN)
                obox(m, (x + s * 0.7, y + 0.37, z), (1, 0), (0.1, 0.74, 1.6), WOOD, M_PLAIN)
            add_coll(ring_box(x, z, (1, 0), 1.9, 1.6)); count("tables de pique-nique")
        elif t.get("amenity") == "charging_station":
            obox(m, (x, y + 0.7, z), (1, 0), (0.45, 1.4, 0.3), (0.94, 0.94, 0.92), M_PLAIN)
            obox(m, (x, y + 1.2, z + 0.16), (1, 0), (0.3, 0.25, 0.02), (0.10, 0.55, 0.30), M_LIGHT)
            add_coll(ring_box(x, z, (1, 0), 0.5, 0.4)); count("bornes de recharge")
        elif t.get("emergency") == "fire_hydrant":
            prism(m, x, y, y + 0.75, z, 0.11, 0.11, 8, (0.78, 0.08, 0.06), M_PLAIN)
            prism(m, x, y + 0.75, y + 0.85, z, 0.13, 0.05, 8, (0.78, 0.08, 0.06), M_PLAIN)
            add_coll(ring_box(x, z, (1, 0), 0.3, 0.3)); count("poteaux d'incendie")
        elif t.get("tourism") == "information":
            tt, n, dist, r, k = road_dir(roads, x, z)
            for s in (-0.6, 0.6):
                p = np.array([x, z]) + tt * s
                obox(m, (p[0], y + 1.0, p[1]), tt, (0.1, 2.0, 0.1), WOOD, M_PLAIN)
            obox(m, (x, y + 1.45, z), tt, (1.3, 0.9, 0.06), (0.30, 0.42, 0.30), M_PLAIN)
            obox(m, (x, y + 2.0, z), tt, (1.5, 0.08, 0.3), WOOD, M_PLAIN)
            add_coll(ring_box(x, z, tt, 1.4, 0.3)); count("panneaux d'information")
        else:
            continue
        add(x, z, m, False)
    # ---------------------------------------------------------------- terrains de sport et aire de jeux
    for poly, t in ways():
        if poly.is_empty or poly.geom_type != "Polygon":
            continue
        c, ax, L, W = oriented(poly)
        y = H(*c)
        m = Mesh()
        sport = t.get("sport", "")
        if t.get("leisure") == "pitch" and sport == "soccer":
            for s in (-1, 1):
                goal(m, obox, c + ax * s * (L / 2 - 1.5), -ax * s, y)
            b = np.array([-ax[1], ax[0]])
            corners = [c + ax * sx * (L / 2 - 1) + b * sz * (W / 2 - 1) for sx, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
            for a_, b_ in zip(corners, corners[1:] + corners[:1]):
                line_box(m, obox, a_, b_, y, 0.1, WHITE)
            line_box(m, obox, c - b * (W / 2 - 1), c + b * (W / 2 - 1), y, 0.1, WHITE)
            for s in (-1, 1):
                add_coll(ring_box(*(c + ax * s * (L / 2 - 1.5) + b * 3.66), ax, 0.2, 0.2))
                add_coll(ring_box(*(c + ax * s * (L / 2 - 1.5) - b * 3.66), ax, 0.2, 0.2))
            count("terrains de foot")
        elif t.get("leisure") == "pitch" and "basketball" in sport:
            # city-stade : sol en enrobé vert, palissade basse en bois + grillage haut, buts / paniers aux extrémités
            from center import poly3
            pts = list(poly.exterior.coords)[:-1]
            poly3(m, [(px, H(px, pz) + 0.04, pz) for px, pz in pts], (0, 1, 0), (0.22, 0.36, 0.28), M_FLAT)
            fence_ring(m, obox, poly, H, 1.0, WOOD)
            fence_ring(m, obox, poly.buffer(0.05), H, 3.2, (0.20, 0.22, 0.22))
            for s in (-1, 1):
                p = c + ax * s * (L / 2 - 0.6)
                goal(m, obox, p, -ax * s, y, w=3.0, h=2.0, col=(0.20, 0.22, 0.22))
                obox(m, (p[0], y + 3.05, p[1]), -ax * s, (0.05, 0.75, 1.0), WHITE, M_PLAIN)
            add_coll(np.array(poly.exterior.coords)[:-1])
            count("city-stade")
        elif t.get("leisure") == "pitch" and sport == "boules":
            from center import poly3
            pts = list(poly.exterior.coords)[:-1]
            poly3(m, [(px, H(px, pz) + 0.03, pz) for px, pz in pts], (0, 1, 0), (0.78, 0.72, 0.60), M_GRAVEL)
            for a_, b_ in zip(pts, pts[1:] + pts[:1]):
                line_box(m, obox, a_, b_, H(*a_), 0.12, WOOD, M_PLAIN, h=0.15)
            count("terrains de boules")
        elif t.get("leisure") == "pitch" and sport == "tennis":
            from center import poly3
            pts = list(poly.exterior.coords)[:-1]
            poly3(m, [(px, H(px, pz) + 0.04, pz) for px, pz in pts], (0, 1, 0), (0.30, 0.45, 0.32), M_FLAT)
            b = np.array([-ax[1], ax[0]])
            hl, hw = min(L / 2 - 3, 11.9), min(W / 2 - 2, 5.5)
            corners = [c + ax * sx * hl + b * sz * hw for sx, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
            for a_, b_ in zip(corners, corners[1:] + corners[:1]):
                line_box(m, obox, a_, b_, y + 0.02, 0.06, WHITE)
            obox(m, (c[0], y + 0.5, c[1]), b, (2 * hw + 1, 0.9, 0.03), (0.15, 0.15, 0.15), M_MESH)
            fence_ring(m, obox, poly, H, 3.0, GREEN_FENCE)
            count("courts de tennis")
        elif t.get("leisure") == "playground":
            fence_ring(m, obox, poly, H, 1.0, GREEN_FENCE)
            # jeux dans la partie libre (l'aire englobe souvent les terrains)
            from shapely.ops import unary_union
            others = unary_union([q.buffer(3) for q, tq in ways() if tq.get("leisure") == "pitch"] or [Point(0, 0).buffer(0.1)])
            free = poly.buffer(-3).difference(others)
            if not free.is_empty:
                big = max(getattr(free, "geoms", [free]), key=lambda g: g.area)
                c = np.array(big.representative_point().coords[0]); y = H(*c)
                L = W = min(12.0, math.sqrt(big.area))
            b = np.array([-ax[1], ax[0]])
            # balançoire, toboggan, jeux à ressort
            p = c - ax * L * 0.25
            for s in (-1, 1):
                q = p + b * s * 1.6
                obox(m, (q[0], y + 1.1, q[1]), b, (0.1, 2.2, 1.4), (0.45, 0.30, 0.20), M_PLAIN)
            obox(m, (p[0], y + 2.2, p[1]), b, (3.3, 0.12, 0.12), (0.45, 0.30, 0.20), M_PLAIN)
            for s in (-0.6, 0.6):
                q = p + b * s
                obox(m, (q[0], y + 0.45, q[1]), b, (0.45, 0.05, 0.2), (0.85, 0.20, 0.15), M_PLAIN)
            q = c + ax * L * 0.2
            obox(m, (q[0], y + 0.75, q[1]), ax, (1.2, 1.5, 1.2), (0.85, 0.65, 0.15), M_PLAIN)
            s0 = q + ax * 0.6; s1 = q + ax * 2.8
            quad3(m, (s0[0] - b[0] * 0.3, y + 1.5, s0[1] - b[1] * 0.3), (s0[0] + b[0] * 0.3, y + 1.5, s0[1] + b[1] * 0.3),
                  (s1[0] + b[0] * 0.3, y + 0.25, s1[1] + b[1] * 0.3), (s1[0] - b[0] * 0.3, y + 0.25, s1[1] - b[1] * 0.3),
                  (0.15, 0.45, 0.80), M_PLAIN)
            for k, col in enumerate(((0.9, 0.3, 0.2), (0.2, 0.6, 0.3))):
                q = c + b * (2.5 * (k * 2 - 1))
                prism(m, q[0], y, y + 0.5, q[1], 0.08, 0.08, 6, (0.5, 0.5, 0.5), M_STEEL)
                obox(m, (q[0], y + 0.7, q[1]), ax, (0.8, 0.35, 0.3), col, M_PLAIN)
            count("aires de jeux")
        else:
            continue
        add(float(c[0]), float(c[1]), m, False)
    return cnt
