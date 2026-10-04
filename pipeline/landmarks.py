"""Bâtiments emblématiques (étape 4), modélisés d'après les photos Street View de référence (cache privé) :
 - églises : nef (avec bas-côtés), abside, clocher (flèche de pierre ou d'ardoise, toit en pavillon, clochetons),
   abat-son, horloge, portail, rosace, vitraux en plein cintre ou en ogive, croix ; position du clocher propre à
   chaque église (façade, chevet, côté) ;
 - chapelles à clocheton ;
 - mairies : bâtiment BD TOPO habillé (enduit et toit réels, volets battants, plaque, drapeaux français et européen) ;
 - châteaux du Marchil, de Thézieux et hôtel de ville de L'Isle-d'Abeau : tours rondes / tourelles, ardoise ;
 - tour du Pollet (ruine), monuments aux morts (obélisques), croix de chemin.
Emprises : OpenStreetMap (églises) ou BD TOPO (bâtiments habillés)."""
import json, math
import numpy as np
from shapely.geometry import Polygon, Point
from shapely.prepared import prep
import geo
from build_buildings import wall_edge, soffit, srgb, IDX, LAYERS, SCALE, obb_frame, tri_polygon

# ------------------------------------------------------------------------------------------------ réglages par monument
# tower : front (façade, au centre), front_in (derrière un fronton), back (au chevet), side_front, side_back, none
# spire : stone (flèche octogonale en pierre), slate (ardoise), pyramid (pavillon bas en tuiles), dome_low (pavillon
# très bas, ardoise) ; arch : round / pointed ; aisles : bas-côtés ; apse : round / none
CHURCHES = {
    "w64850603": dict(tower="side_front", spire="stone", T=6.0, Ht=27, Hs=17, Hn=14, aisles=True, apse="round",
                      arch="round", wall="pierre_claire", tint=(1.0, 0.95, 0.88), roof="tuile_ancienne", rose=True),
    "w70539437": dict(tower="back", spire="stone", T=5.0, Ht=21, Hs=13, Hn=11, aisles=False, apse="none",
                      arch="pointed", wall="pierre", tint=(1.12, 1.05, 0.92), roof="tuile_ancienne", triple=True),
    "w65382654": dict(tower="side_back", spire="stone", T=5.0, Ht=20, Hs=12, Hn=10, aisles=False, apse="round",
                      arch="round", wall="pierre", tint=(1.1, 1.03, 0.92), roof="tuile_grise", rose=False),
    "w74916998": dict(tower="front", spire="slate", T=5.4, Ht=22, Hs=14, Hn=11, aisles=True, apse="round",
                      arch="round", wall="pierre_claire", tint=(1.0, 0.97, 0.9), roof="tuile_ancienne", pinnacles=True),
    "w65330502": dict(tower="none", spire="slate", T=1.6, Ht=0, Hs=4.5, Hn=9, aisles=False, apse="none",
                      arch="pointed", wall="pierre", tint=(1.18, 1.14, 1.06), roof="tuile_ancienne", rose=True,
                      bellcote=True),
    "w422915711": dict(tower="side_back", spire="slate", T=4.4, Ht=18, Hs=9, Hn=9, aisles=False, apse="round",
                       arch="round", wall="pierre", tint=(1.0, 0.95, 0.86), roof="tuile_ancienne"),
    "w38497740": dict(tower="front_in", spire="dome_low", T=4.4, Ht=21, Hs=2.5, Hn=11, aisles=True, apse="round",
                      arch="round", wall="pierre_claire", tint=(1.05, 1.0, 0.9), roof="tuile_meca"),
    "w142617849": dict(tower="front", spire="pyramid", T=8.0, Ht=25, Hs=4.5, Hn=15, aisles=True, apse="round",
                       arch="round", wall="pierre", tint=(1.05, 0.98, 0.88), roof="tuile_ancienne"),
    # chapelles à clocheton
    "w258074410": dict(tower="none", spire="slate", T=1.2, Ht=0, Hs=3.0, Hn=5.5, aisles=False, apse="none",
                       arch="round", wall="pierre", tint=(1.05, 1.0, 0.92), roof="tuile_ancienne", bellcote=True),
    "w118471899": dict(tower="none", spire="slate", T=1.2, Ht=0, Hs=3.0, Hn=6.0, aisles=False, apse="round",
                       arch="round", wall="crepi", tint=(0.97, 0.94, 0.88), roof="tuile_meca", bellcote=True),
}
# mairies et autres bâtiments habillés (point ou polygone OSM -> bâtiment BD TOPO qui le contient)
DRESS = {
    "w70538450": dict(label="Mairie de Rochetoirin", wall="crepi", wtint=(0.98, 0.93, 0.84), modern=False,
                      shutters=(0.97, 0.97, 0.95), flags=True, plaque="plaque_mairie"),
    "n5617663286": dict(label="Mairie de Cessieu", wall="crepi", wtint=(0.97, 0.80, 0.68), roof="tuile_ancienne",
                        roof_tint=(0.85, 0.85, 0.85), hip=True, pitch=44, modern=False, shutters=(0.98, 0.98, 0.96),
                        flags=True, plaque="plaque_mairie", min_h=7.5),
    "n2329191935": dict(label="Mairie de Saint-Clair", wall="crepi", wtint=(0.99, 0.9, 0.86), modern=False,
                        shutters=(0.97, 0.97, 0.95), hip=True, flags=True, plaque="plaque_mairie"),
    "w218259048": dict(label="Mairie de Montcarra", wall="crepi", wtint=(0.97, 0.93, 0.85), hip=True,
                       flags=True, poles=True, plaque="plaque_mairie"),
    "w64851300": dict(label="Mairie de La Tour-du-Pin", wall="crepi", wtint=(0.95, 0.9, 0.8), flags=True,
                      plaque="plaque_mairie"),
    "w142617749": dict(label="Mairie de Saint-Chef", wall="pierre", modern=False, flags=True, plaque="plaque_mairie"),
    "w65331131": dict(label="Mairie de Saint-Jean-de-Soudain", wall="crepi", wtint=(0.97, 0.92, 0.82), hip=True,
                      modern=False, flags=True, plaque="plaque_mairie"),
    "w170225099": dict(label="Hôtel de ville (Four)", wall="crepi", wtint=(0.98, 0.95, 0.9), flags=True,
                       plaque="plaque_mairie"),
    "w120264872": dict(label="Hôtel de ville de L'Isle-d'Abeau", wall="pierre_claire", wtint=(1.12, 1.1, 1.05),
                       roof="ardoise", roof_tint=(0.75, 0.78, 0.82), hip=True, pitch=50, modern=False, min_h=10.0,
                       shutters=(0.95, 0.95, 0.93), flags=True, plaque="plaque_hdv", turret="round"),
    "w142617971": dict(label="Château du Marchil", wall="crepi_ancien", wtint=(1.08, 1.0, 0.9), roof="tuile_ancienne",
                       roof_tint=(0.8, 0.72, 0.68), hip=True, pitch=48, modern=False, shutters=(0.9, 0.88, 0.84),
                       turret="towers", min_h=11.0, kind="collectif"),
    "w142466149": dict(label="Château de Thézieux", wall="crepi", wtint=(0.98, 0.96, 0.92), roof="ardoise",
                       roof_tint=(0.7, 0.74, 0.8), hip=True, pitch=36, modern=False, shutters=(0.95, 0.95, 0.93),
                       turret="octo", min_h=12.5, kind="collectif"),
}
TOWER_RUIN = {"w142620707"}


def _poly_of(e):
    if e["type"] == "node":
        x, z = geo.to_local(e["lon"], e["lat"])
        return Point(float(x), float(z))
    if e["type"] == "way" and "geometry" in e:
        g = e["geometry"]
        x, z = geo.to_local([p["lon"] for p in g], [p["lat"] for p in g])
        if len(g) >= 4:
            return Polygon(list(zip(x, z))).buffer(0)
        return Point(float(np.mean(x)), float(np.mean(z)))
    return None


class Frame:
    """Repère local d'un monument : s le long de l'axe (depuis la façade), t en travers ; y absolu."""
    def __init__(self, origin, ax):
        self.o = np.asarray(origin, float); self.ax = np.asarray(ax, float) / np.linalg.norm(ax)
        self.pe = np.array([-self.ax[1], self.ax[0]])

    def p2(self, s, t):
        return self.o + self.ax * s + self.pe * t

    def p3(self, s, t, y):
        q = self.p2(s, t)
        return (q[0], y, q[1])

    def n3(self, ds, dt, dy=0.0):
        q = self.ax * ds + self.pe * dt
        return np.array([q[0], dy, q[1]])


def _box(M, F, s0, s1, t0, t1, base, top, gnd, layer, tint, ops=None):
    """Murs d'un parallélépipède (coins dans le sens trigonométrique) ; ops : {côté: ouvertures} avec côtés
    'right' (t0), 'back' (s1), 'left' (t1), 'front' (s0) ; u mesuré depuis le premier coin de l'arête."""
    ops = ops or {}
    C = [F.p2(s0, t0), F.p2(s1, t0), F.p2(s1, t1), F.p2(s0, t1)]
    for k, side in enumerate(("right", "back", "left", "front")):
        wall_edge(M, C[k], C[(k + 1) % 4], base, top, gnd, layer, tint, ops.get(side, []), None, plinth=False)


def _col_box(C, F, s0, s1, t0, t1, y0, y1):
    P2 = [F.p2(s0, t0), F.p2(s1, t0), F.p2(s1, t1), F.p2(s0, t1)]
    P = np.array([(p[0], y0, p[1]) for p in P2] + [(p[0], y1, p[1]) for p in P2], np.float32)
    I = []
    for k in range(4):
        a, b = k, (k + 1) % 4
        I += [a, b, b + 4, a, b + 4, a + 4]
    I += [4, 5, 6, 4, 6, 7, 0, 2, 1, 0, 3, 2]
    C.append((P, np.array(I, np.uint32)))


def _col_prism(C, pts2, y0, y1):
    n = len(pts2)
    P = np.array([(p[0], y0, p[1]) for p in pts2] + [(p[0], y1, p[1]) for p in pts2], np.float32)
    I = []
    for k in range(n):
        a, b = k, (k + 1) % n
        I += [a, b, b + n, a, b + n, a + n]
    for k in range(1, n - 1):
        I += [n, n + k, n + k + 1]
    C.append((P, np.array(I, np.uint32)))


def _pyramid(M, base_pts3, apex, layer, tint, scale=2.0):
    """Faces d'une pyramide (base polygonale quelconque, sommet apex), normales vers l'extérieur."""
    B = [np.asarray(p, float) for p in base_pts3]
    c = np.mean(B, axis=0)
    apex = np.asarray(apex, float)
    for k in range(len(B)):
        a, b = B[k], B[(k + 1) % len(B)]
        nrm = np.cross(b - a, apex - a)
        out = (a + b) / 2 - c; out[1] = 0
        if np.dot(nrm, out) < 0:
            nrm = -nrm
        L = np.linalg.norm(b - a); hgt = np.linalg.norm(apex - (a + b) / 2)
        M.poly([a, b, apex], [(0, hgt / scale), (L / scale, hgt / scale), (L / 2 / scale, 0)], layer, tint, nrm)


def _cross(M, x, y, z, ax, h=1.6, layer=None, tint=(0.25, 0.25, 0.27)):
    """Croix métallique au sommet (deux barres fines)."""
    layer = IDX["beton"] if layer is None else layer
    ax = np.asarray(ax, float) / np.linalg.norm(ax); pe = np.array([-ax[1], ax[0]])
    def bar(c, hx, hy, hz):
        P2 = [c[:2] + ax * hx + pe * hz, c[:2] - ax * hx + pe * hz, c[:2] - ax * hx - pe * hz, c[:2] + ax * hx - pe * hz]
        y0, y1 = c[2] - hy, c[2] + hy
        for k in range(4):
            a, b = P2[k], P2[(k + 1) % 4]
            n = np.array([(a + b)[0] / 2 - c[0], 0, (a + b)[1] / 2 - c[1]])
            M.poly([(a[0], y0, a[1]), (b[0], y0, b[1]), (b[0], y1, b[1]), (a[0], y1, a[1])],
                   [(0, 0), (0.1, 0), (0.1, 0.1), (0, 0.1)], layer, srgb(tint), n)
        M.poly([(p[0], y1, p[1]) for p in P2], [(0, 0), (0.1, 0), (0.1, 0.1), (0, 0.1)], layer, srgb(tint), (0, 1, 0))
    c = np.array([x, z, y + h / 2])
    bar(c, 0.05, h / 2, 0.05)
    bar(np.array([x, z, y + h * 0.68]), 0.05, 0.05, h * 0.3)


def _spire(M, F, sc, tc, half, ytop, Hs, kind, pinnacles=False, cross=True):
    """Couverture du clocher : flèche octogonale (pierre / ardoise), pavillon (tuiles) ou pavillon bas (ardoise)."""
    # chéneau / corniche : dalle au sommet de la maçonnerie
    sq = [F.p3(sc - half - 0.25, tc - half - 0.25, ytop), F.p3(sc + half + 0.25, tc - half - 0.25, ytop),
          F.p3(sc + half + 0.25, tc + half + 0.25, ytop), F.p3(sc - half - 0.25, tc + half + 0.25, ytop)]
    M.poly(sq, [(0, 0), (1, 0), (1, 1), (0, 1)], IDX["pierre_claire"], srgb((1, 1, 1)), (0, 1, 0))
    for k in range(4):
        a, b = np.array(sq[k]), np.array(sq[(k + 1) % 4])
        out = (a + b) / 2 - np.mean(sq, axis=0); out[1] = 0
        M.poly([a, b, b - (0, 0.35, 0), a - (0, 0.35, 0)], [(0, 0), (1, 0), (1, 0.1), (0, 0.1)], IDX["pierre_claire"],
               srgb((1, 1, 1)), out)
    apex_y = ytop + Hs
    if kind in ("stone", "slate"):
        r = half * 1.02
        oct3 = [F.p3(sc + r * math.cos(math.pi / 8 + k * math.pi / 4), tc + r * math.sin(math.pi / 8 + k * math.pi / 4), ytop)
                for k in range(8)]
        lay = IDX["pierre_taillee"] if kind == "stone" else IDX["ardoise"]
        tint = srgb((1.25, 1.2, 1.1)) if kind == "stone" else srgb((0.62, 0.66, 0.72))
        _pyramid(M, oct3, F.p3(sc, tc, apex_y), lay, tint)
    else:
        o = 0.35
        base = [F.p3(sc - half - o, tc - half - o, ytop - 0.2), F.p3(sc + half + o, tc - half - o, ytop - 0.2),
                F.p3(sc + half + o, tc + half + o, ytop - 0.2), F.p3(sc - half - o, tc + half + o, ytop - 0.2)]
        if kind == "pyramid":
            _pyramid(M, base, F.p3(sc, tc, apex_y), IDX["tuile_ancienne"], srgb((0.95, 0.9, 0.88)), 2.5)
        else:
            _pyramid(M, base, F.p3(sc, tc, apex_y), IDX["ardoise"], srgb((0.62, 0.66, 0.72)), 2.0)
    if pinnacles:
        for ds in (-1, 1):
            for dt in (-1, 1):
                cs, ct = sc + ds * (half - 0.3), tc + dt * (half - 0.3)
                b = [F.p3(cs - 0.35, ct - 0.35, ytop), F.p3(cs + 0.35, ct - 0.35, ytop), F.p3(cs + 0.35, ct + 0.35, ytop),
                     F.p3(cs - 0.35, ct + 0.35, ytop)]
                _pyramid(M, b, F.p3(cs, ct, ytop + 3.2), IDX["ardoise"], srgb((0.62, 0.66, 0.72)))
    if cross:
        q = F.p2(sc, tc)
        _cross(M, q[0], apex_y - 0.1, q[1], F.ax)


def _tower(M, C, F, s0, s1, t0, t1, base, gnd, Ht_abs, cfg, faces, portal_face=None):
    """Clocher : abat-son en haut de chaque face, horloge en dessous (faces visibles), portail éventuel."""
    T = s1 - s0
    wl = IDX[cfg["wall"]]; wt = srgb(cfg["tint"])
    arch = "portail_ogive" if cfg["arch"] == "pointed" else "portail_cintre"
    ops = {}
    for side in ("right", "back", "left", "front"):
        L = T
        o = []
        nb = 2 if L >= 5.5 else 1
        for j in range(nb):
            uc = L * (j + 1) / (nb + 1)
            o.append((uc - 0.55, uc + 0.55, Ht_abs - 3.4, Ht_abs - 0.9, IDX["abat_son"], 0.35))
        if side in faces and Ht_abs - gnd > 14:
            o.append((L / 2 - 0.95, L / 2 + 0.95, Ht_abs - 6.0, Ht_abs - 4.1, IDX["horloge"], 0.05))
        if side == portal_face:
            o.append((L / 2 - 1.3, L / 2 + 1.3, gnd + 0.05, gnd + 4.2, IDX[arch], 0.45))
        ops[side] = o
    _box(M, F, s0, s1, t0, t1, base, Ht_abs, gnd, wl, wt, ops)
    _col_box(C, F, s0, s1, t0, t1, base, Ht_abs)
    _spire(M, F, (s0 + s1) / 2, (t0 + t1) / 2, T / 2, Ht_abs, cfg["Hs"], cfg["spire"], cfg.get("pinnacles", False))


def _gable_roof(M, F, s0, s1, t0, t1, eave, pitch, layer, tint, wall_layer, wall_tint, gables=(True, True), o=0.45):
    tc = (t0 + t1) / 2; hw = (t1 - t0) / 2; tn = math.tan(pitch)
    ytop = eave + hw * tn
    sa, sb = s0 - (o if gables[0] else 0), s1 + (o if gables[1] else 0)
    sc_ = SCALE[LAYERS[layer][0]]
    L = math.hypot(hw + o, (hw + o) * tn)
    for sg in (-1, 1):
        te = tc + sg * (hw + o)
        q = [F.p3(sa, te, eave - o * tn), F.p3(sb, te, eave - o * tn), F.p3(sb, tc, ytop), F.p3(sa, tc, ytop)]
        nrm = F.n3(0, sg * tn, 1.0)
        M.poly(q, [(sa / sc_, L / sc_), (sb / sc_, L / sc_), (sb / sc_, 0), (sa / sc_, 0)], layer, tint, nrm)
        soffit(M, q, nrm)
    wsc = SCALE[LAYERS[wall_layer][0]]
    for s, ds, show in ((s0, -1, gables[0]), (s1, 1, gables[1])):
        M.poly([F.p3(s, t0, eave), F.p3(s, t1, eave), F.p3(s, tc, ytop)], [(0, 0), (2 * hw / wsc, 0), (hw / wsc, -hw * tn / wsc)],
               wall_layer, wall_tint, F.n3(ds, 0))
    return ytop


def _shed_roof(M, F, s0, s1, t_in, t_out, y_in, y_out, layer, tint, o=0.4):
    """Toit en appentis d'un bas-côté : du mur de la nef (t_in, y_in) vers l'extérieur (t_out, y_out)."""
    sg = 1 if t_out > t_in else -1
    slope = (y_in - y_out) / abs(t_out - t_in)
    to = t_out + sg * o; yo = y_out - o * slope
    q = [F.p3(s0 - o, t_in, y_in), F.p3(s1 + o, t_in, y_in), F.p3(s1 + o, to, yo), F.p3(s0 - o, to, yo)]
    nrm = F.n3(0, sg * slope, 1.0)
    sc_ = SCALE[LAYERS[layer][0]]
    w = math.hypot(abs(to - t_in), y_in - yo)
    M.poly(q, [(0, 0), ((s1 - s0 + 2 * o) / sc_, 0), ((s1 - s0 + 2 * o) / sc_, w / sc_), (0, w / sc_)], layer, tint, nrm)
    soffit(M, q, nrm)


def _apse(M, C, F, s_b, R, base, gnd, H, pitch, wl, wt, rl, rt, win_layer):
    """Abside semi-circulaire (8 pans) et sa demi-coupole de tuiles."""
    n = 8
    pts = [(s_b + R * math.cos(-math.pi / 2 + math.pi * k / n), R * math.sin(-math.pi / 2 + math.pi * k / n)) for k in range(n + 1)]
    for k in range(n):
        a, b = F.p2(*pts[k]), F.p2(*pts[k + 1])
        L = float(np.hypot(*(b - a)))
        ops = []
        if k in (2, 4, 5) and L > 1.6 and H > 6:
            ops = [(L / 2 - 0.5, L / 2 + 0.5, gnd + H * 0.38, gnd + H * 0.38 + 2.6, win_layer, 0.3)]
        wall_edge(M, a, b, base, gnd + H, gnd, wl, wt, ops, None, plinth=False)
    tn = math.tan(pitch); o = 0.4
    apex = F.p3(s_b, 0, gnd + H + R * tn)
    rim = [F.p3(s_b + (R + o) * math.cos(-math.pi / 2 + math.pi * k / n), (R + o) * math.sin(-math.pi / 2 + math.pi * k / n),
                gnd + H - o * tn) for k in range(n + 1)]
    for k in range(n):
        a, b = np.array(rim[k]), np.array(rim[k + 1])
        nrm = np.cross(b - a, np.array(apex) - a)
        if nrm[1] < 0:
            nrm = -nrm
        M.poly([a, b, apex], [(0, 1), (1, 1), (0.5, 0)], rl, rt, nrm)
        soffit(M, [a, b, apex], nrm)
    _col_prism(C, [F.p2(*p) for p in pts], base, gnd + H)


def church(M, C, cfg, poly, dem, road_tree, key):
    """Église (ou chapelle) sur son emprise OSM : axe = grand côté du rectangle orienté, façade côté route."""
    a, c, r = obb_frame(poly)
    ax = np.array([math.cos(a), math.sin(a)])
    Cr = np.asarray(r.exterior.coords)[:4]
    L = max(np.hypot(*(Cr[1] - Cr[0])), np.hypot(*(Cr[2] - Cr[1])))
    W = min(np.hypot(*(Cr[1] - Cr[0])), np.hypot(*(Cr[2] - Cr[1])))
    c = np.array([c[0], c[1]])
    e1, e2 = c - ax * L / 2, c + ax * L / 2
    d1, _ = road_tree.query(e1); d2, _ = road_tree.query(e2)
    if d2 < d1:                         # façade = extrémité la plus proche d'une route
        ax = -ax
    if cfg.get("flip"):
        ax = -ax
    F = Frame(c - ax * L / 2, ax)
    ring = np.asarray(poly.exterior.coords)
    g = dem.h(ring[:, 0], ring[:, 1])
    gnd = float(g.min()); base = gnd - 1.0
    wl = IDX[cfg["wall"]]; wt = srgb(cfg["tint"])
    rl = IDX[cfg["roof"]]; rt = srgb((0.95, 0.92, 0.9))
    win = IDX["vitrail_ogive"] if cfg["arch"] == "pointed" else IDX["vitrail_cintre"]
    portal = IDX["portail_ogive"] if cfg["arch"] == "pointed" else IDX["portail_cintre"]
    T, Hn = cfg["T"], cfg["Hn"]
    pitch = math.radians(40)
    tw = cfg["tower"]
    # répartition le long de l'axe
    side_tower = tw.startswith("side")
    Wn = W - (T - 0.6 if side_tower else 0.0)
    Wn = max(Wn, 5.0)
    t_n0, t_n1 = -Wn / 2, Wn / 2
    if side_tower:                       # nef décalée, clocher accolé sur le côté gauche (t > 0)
        t_n0, t_n1 = -W / 2, -W / 2 + Wn
    R = min(Wn * (0.32 if cfg["aisles"] else 0.42), 4.5) if cfg["apse"] == "round" else 0.0
    s_n0 = 0.0; s_n1 = L - R
    if tw == "front":
        s_n0 = T * 0.6
    elif tw == "back":
        s_n1 = L - T * 0.6
    elif tw == "front_in":
        s_n0 = 0.0
    # nef (et bas-côtés)
    Wc = Wn * 0.56 if cfg["aisles"] else Wn
    tc0 = (t_n0 + t_n1) / 2 - Wc / 2; tc1 = tc0 + Wc
    nave_len = s_n1 - s_n0
    nwin = max(1, int((nave_len - 3.0) // 4.6))
    def side_ops(L_, y0, h, w=1.3):
        return [(L_ * (j + 0.5) / nwin - w / 2, L_ * (j + 0.5) / nwin + w / 2, y0, y0 + h, win, 0.35) for j in range(nwin)]
    front_ops = []
    if tw not in ("front",):
        front_ops.append((Wc / 2 - 1.4, Wc / 2 + 1.4, gnd + 0.05, gnd + 4.4, portal, 0.5))
        if cfg.get("rose"):
            front_ops.append((Wc / 2 - 1.6, Wc / 2 + 1.6, gnd + 5.4, gnd + 8.6, IDX["rosace"], 0.4))
        elif cfg.get("triple"):
            for dx in (-1.3, 0, 1.3):
                front_ops.append((Wc / 2 + dx - 0.45, Wc / 2 + dx + 0.45, gnd + 5.2, gnd + 8.6, IDX["vitrail_ogive"], 0.35))
        elif Hn > 8:
            front_ops.append((Wc / 2 - 0.6, Wc / 2 + 0.6, gnd + 5.4, gnd + 8.2, win, 0.35))
    if tw == "front_in":                 # façade à fronton : portail central, clocher en retrait derrière
        pass
    eave = gnd + Hn
    clere = gnd + Hn * 0.62 if cfg["aisles"] else gnd + min(3.2, Hn * 0.35)
    wh = min(3.4, Hn * 0.33) if not cfg["aisles"] else min(2.6, Hn * 0.25)
    _box(M, F, s_n0, s_n1, tc0, tc1, base, eave, gnd, wl, wt,
         {"right": side_ops(nave_len, clere, wh), "left": side_ops(nave_len, clere, wh), "front": front_ops})
    _col_box(C, F, s_n0, s_n1, tc0, tc1, base, eave)
    ridge = _gable_roof(M, F, s_n0, s_n1, tc0, tc1, eave, pitch, rl, rt, wl, wt,
                        gables=(tw != "front", not (tw == "back")))
    if cfg["aisles"]:
        Ha = Hn * 0.52
        for t_in, t_out in ((tc0, t_n0), (tc1, t_n1)):
            if abs(t_out - t_in) < 1.0:
                continue
            ta, tb = min(t_in, t_out), max(t_in, t_out)
            side = "right" if t_out < t_in else "left"
            _box(M, F, s_n0 + 0.3, s_n1 - 0.3, ta, tb, base, gnd + Ha, gnd, wl, wt,
                 {side: side_ops(nave_len - 0.6, gnd + Ha * 0.32, min(2.8, Ha * 0.45))})
            _col_box(C, F, s_n0 + 0.3, s_n1 - 0.3, ta, tb, base, gnd + Ha)
            _shed_roof(M, F, s_n0 + 0.3, s_n1 - 0.3, t_in, t_out, gnd + Ha + abs(t_out - t_in) * 0.36, gnd + Ha, rl, rt)
    if R > 0:
        _apse(M, C, F, s_n1, R, base, gnd, Hn * 0.82, pitch, wl, wt, rl, rt, win)
    # clocher
    if tw != "none":
        Ht = gnd + cfg["Ht"]
        if tw == "front":
            s0, s1, t0, t1 = 0.0, T, (tc0 + tc1) / 2 - T / 2, (tc0 + tc1) / 2 + T / 2
            faces, pf = ("front", "right", "left"), "front"
        elif tw == "front_in":
            s0, s1 = 1.2, 1.2 + T
            t0, t1 = (tc0 + tc1) / 2 - T / 2, (tc0 + tc1) / 2 + T / 2
            faces, pf = ("front", "right", "left"), None
        elif tw == "back":
            s0, s1, t0, t1 = L - T, L, (tc0 + tc1) / 2 - T / 2, (tc0 + tc1) / 2 + T / 2
            faces, pf = ("back", "right", "left"), None
        elif tw == "side_front":
            s0, s1, t0, t1 = 0.0, T, t_n1 - 0.6, t_n1 - 0.6 + T
            faces, pf = ("front", "left"), "front"
        else:                            # side_back : contre le chœur
            s0, s1 = max(0.0, s_n1 - T - 1.0), max(T, s_n1 - 1.0)
            t0, t1 = t_n1 - 0.6, t_n1 - 0.6 + T
            faces, pf = ("left", "back", "front"), None
        _tower(M, C, F, s0, s1, t0, t1, base, gnd, Ht, cfg, faces, pf)
    if cfg.get("bellcote"):              # clocheton sur le pignon de façade
        b = cfg["T"]
        tcn = (tc0 + tc1) / 2
        s0 = s_n0 + 0.3
        y0 = eave
        ytop = ridge + 1.8
        _box(M, F, s0, s0 + b, tcn - b / 2, tcn + b / 2, y0, ytop, y0, wl, wt,
             {sd: [(b / 2 - 0.3, b / 2 + 0.3, ytop - 1.5, ytop - 0.3, IDX["abat_son"], 0.2)] for sd in ("front", "right", "left", "back")})
        r = b / 2 + 0.1
        base4 = [F.p3(s0 + b / 2 + dx * r, tcn + dt * r, ytop) for dx, dt in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
        _pyramid(M, base4, F.p3(s0 + b / 2, tcn, ytop + cfg["Hs"]), IDX["ardoise"], srgb((0.62, 0.66, 0.72)))
        q = F.p2(s0 + b / 2, tcn)
        _cross(M, q[0], ytop + cfg["Hs"] - 0.1, q[1], F.ax, 1.1)
    # croix au faîte du pignon de façade si pas de clocher en façade
    if tw not in ("front", "front_in") and not cfg.get("bellcote"):
        q = F.p2(s_n0, (tc0 + tc1) / 2)
        _cross(M, q[0], ridge, q[1], F.ax, 1.3, IDX["pierre_claire"], (1.0, 0.97, 0.9))
    return "église" if cfg["Hn"] > 7 else "chapelle"


# ------------------------------------------------------------------------------------------------ petits monuments
def round_tower(M, C, center, radius, base, top, layer, tint, roof=None, roof_h=0.0, n=14, ruin=False, key=0,
                windows=0, gnd=None):
    """Tour ronde (n pans) ; toit conique (roof = couche) ou sommet ruiné irrégulier."""
    gnd = base if gnd is None else gnd
    cx, cz = center
    rng = np.random.default_rng(key)
    pts = [(cx + radius * math.cos(2 * math.pi * k / n), cz + radius * math.sin(2 * math.pi * k / n)) for k in range(n + 1)]
    tops = [top - (rng.random() * 2.5 if ruin else 0.0) for _ in range(n)]
    for k in range(n):
        a, b = np.array(pts[k]), np.array(pts[k + 1])
        L = float(np.hypot(*(b - a)))
        ops = []
        if windows and k % max(1, n // windows) == 0 and top - gnd > 5:
            ops = [(L / 2 - 0.35, L / 2 + 0.35, gnd + (top - gnd) * 0.55, gnd + (top - gnd) * 0.55 + 1.2, IDX["fenetre"], 0.3)]
        wall_edge(M, a, b, base, tops[k], gnd, layer, tint, ops, srgb((0.9, 0.88, 0.84)) if ops else None, plinth=False)
        if ruin:
            # parement intérieur et arase du mur (1,2 m d'épaisseur)
            ia = np.array([cx, cz]) + (a - (cx, cz)) * (radius - 1.2) / radius
            ib = np.array([cx, cz]) + (b - (cx, cz)) * (radius - 1.2) / radius
            wall_edge(M, ib, ia, base, tops[k], gnd, layer, tint, [], None, plinth=False)
            M.poly([(a[0], tops[k], a[1]), (b[0], tops[k], b[1]), (ib[0], tops[k], ib[1]), (ia[0], tops[k], ia[1])],
                   [(0, 0), (0.5, 0), (0.5, 0.5), (0, 0.5)], layer, tint, (0, 1, 0))
    if roof is not None:
        o = 0.35
        rim = [(cx + (radius + o) * math.cos(2 * math.pi * k / n), top - 0.25, cz + (radius + o) * math.sin(2 * math.pi * k / n))
               for k in range(n)]
        _pyramid(M, rim, (cx, top + roof_h, cz), roof[0], roof[1], 1.5)
        for k in range(n):
            a, b = np.array(rim[k]), np.array(rim[(k + 1) % n])
            nr = np.cross(b - a, np.array((cx, top + roof_h, cz)) - a)
            soffit(M, [a, b, (cx, top + roof_h, cz)], nr if nr[1] > 0 else -nr)
    _col_prism(C, pts[:-1], base, top + roof_h * 0.5)


def obelisk(M, C, x, z, gnd, h=4.5):
    """Monument aux morts : socle à degrés, stèle effilée, pyramidion."""
    lay = IDX["pierre_claire"]; tint = srgb((1.25, 1.22, 1.15))
    F = Frame((x, z), (1.0, 0.0))
    for w, y0, y1 in ((1.9, gnd - 0.5, gnd + 0.3), (1.4, gnd + 0.3, gnd + 1.2)):
        _box(M, F, -w / 2, w / 2, -w / 2, w / 2, y0, y1, y0, lay, tint)
        M.poly([F.p3(-w / 2, -w / 2, y1), F.p3(w / 2, -w / 2, y1), F.p3(w / 2, w / 2, y1), F.p3(-w / 2, w / 2, y1)],
               [(0, 0), (1, 0), (1, 1), (0, 1)], lay, tint, (0, 1, 0))
    yb, yt = gnd + 1.2, gnd + h
    b0, b1 = 0.45, 0.3
    corners = lambda r, y: [F.p3(-r, -r, y), F.p3(r, -r, y), F.p3(r, r, y), F.p3(-r, r, y)]
    lo, hi = corners(b0, yb), corners(b1, yt)
    cen = np.array([x, (yb + yt) / 2, z])
    for k in range(4):
        q = [lo[k], lo[(k + 1) % 4], hi[(k + 1) % 4], hi[k]]
        out = (np.array(q[0]) + np.array(q[1])) / 2 - cen; out[1] = 0.05
        M.poly(q, [(0, 1), (1, 1), (1, 0), (0, 0)], lay, tint, out)
    _pyramid(M, hi, (x, yt + 0.5, z), lay, tint, 1.0)
    _col_box(C, F, -0.95, 0.95, -0.95, 0.95, gnd - 0.5, yt)


def wayside_cross(M, C, x, z, gnd):
    """Croix de chemin : socle de pierre et croix en fer forgé."""
    F = Frame((x, z), (1.0, 0.0))
    lay = IDX["pierre_claire"]; tint = srgb((1.15, 1.12, 1.05))
    _box(M, F, -0.45, 0.45, -0.45, 0.45, gnd - 0.4, gnd + 1.1, gnd, lay, tint)
    M.poly([F.p3(-0.45, -0.45, gnd + 1.1), F.p3(0.45, -0.45, gnd + 1.1), F.p3(0.45, 0.45, gnd + 1.1), F.p3(-0.45, 0.45, gnd + 1.1)],
           [(0, 0), (1, 0), (1, 1), (0, 1)], lay, tint, (0, 1, 0))
    _cross(M, x, gnd + 1.1, z, (1.0, 0.0), 2.2, IDX["beton"], (0.12, 0.12, 0.13))
    _col_box(C, F, -0.45, 0.45, -0.45, 0.45, gnd - 0.4, gnd + 3.2)


def flag(M, root, out, y, kind_layer):
    """Drapeau sur hampe inclinée à 45° hors de la façade (deux faces)."""
    root = np.asarray(root, float); out = np.asarray(out, float) / np.linalg.norm(out)
    tip = root + out * 1.5
    pole_top = (tip[0], y + 1.5, tip[1])
    pole_bot = (root[0], y, root[1])
    pe = np.array([-out[1], out[0]])
    # hampe : fine poutre carrée
    P0 = np.array(pole_bot); P1 = np.array(pole_top)
    d = P1 - P0
    side = np.array([pe[0], 0, pe[1]]) * 0.03
    upn = np.cross(d, side); upn = upn / np.linalg.norm(upn) * 0.03
    for v, w in ((side, upn), (upn, -side), (-side, -upn), (-upn, side)):
        M.poly([P0 + v, P1 + v, P1 + w, P0 + w], [(0, 0), (1, 0), (1, 0.1), (0, 0.1)], IDX["beton"], srgb((0.85, 0.85, 0.85)),
               (v + w))
    # étoffe pendante (1,4 × 0,95 m) accrochée sous l'extrémité de la hampe
    tipw = np.array(pole_top)
    q = [tipw, tipw - np.array([out[0], 0, out[1]]) * 1.0 + (0, -0.05, 0),
         tipw - np.array([out[0], 0, out[1]]) * 1.0 + (0, -1.0, 0), tipw + (0, -0.95, 0)]
    nrm = np.array([pe[0], 0, pe[1]])
    uv = [(1, 0), (0, 0), (0, 1), (1, 1)]
    M.poly(q, uv, kind_layer, srgb((1, 1, 1)), nrm)
    M.poly(q[::-1], uv[::-1], kind_layer, srgb((1, 1, 1)), -nrm)


def flag_pole(M, C, x, z, gnd, layer, h=7.0):
    F = Frame((x, z), (1.0, 0.0))
    _box(M, F, -0.05, 0.05, -0.05, 0.05, gnd - 0.3, gnd + h, gnd, IDX["beton"], srgb((0.9, 0.9, 0.9)))
    nrm = np.array([0, 0, 1.0])
    q = [(x + 0.05, gnd + h - 0.1, z), (x + 1.55, gnd + h - 0.1, z), (x + 1.55, gnd + h - 1.1, z), (x + 0.05, gnd + h - 1.1, z)]
    uv = [(0, 0), (1, 0), (1, 1), (0, 1)]
    M.poly(q, uv, layer, srgb((1, 1, 1)), nrm)
    M.poly(q[::-1], uv[::-1], layer, srgb((1, 1, 1)), -nrm)


# ------------------------------------------------------------------------------------------------ ensemble
class Landmarks:
    def __init__(self, polys, blds, road_tree, dem):
        self.dem = dem; self.road_tree = road_tree
        self.polys = polys
        self.replaced = set()            # indices BD TOPO remplacés par un modèle dédié
        self.override = {}               # indice BD TOPO -> réglages d'habillage
        self.items = []                  # (type, géométrie, réglages, clé)
        zone = prep(Polygon(json.load(open("data/routes_plan.json"))["zone"]))
        from shapely.strtree import STRtree
        tree = STRtree(polys)
        for e in json.load(open("data/osm_landmarks.json"))["elements"]:
            key = "%s%d" % (e["type"][0], e["id"])
            g = _poly_of(e)
            if g is None or g.is_empty or not zone.contains(g.centroid):
                continue
            t = e.get("tags", {})
            if key in CHURCHES and isinstance(g, Polygon):
                for j in tree.query(g):
                    inter = polys[j].intersection(g).area
                    if inter > 0.35 * polys[j].area:
                        self.replaced.add(int(j))
                self.items.append(("church", g, CHURCHES[key], key))
            elif key in DRESS:
                # bâtiment BD TOPO qui contient le point (ou recouvre le plus le polygone)
                best, ba = None, 0.0
                probe = g if isinstance(g, Polygon) else g.buffer(6)
                for j in tree.query(probe):
                    a = polys[j].intersection(probe).area
                    if a > ba:
                        best, ba = int(j), a
                if best is not None:
                    self.override[best] = dict(DRESS[key])
            elif key in TOWER_RUIN:
                for j in tree.query(g):
                    if polys[j].intersection(g).area > 0.3 * polys[j].area:
                        self.replaced.add(int(j))
                self.items.append(("ruin", g, {}, key))
            elif t.get("historic") == "memorial" and (t.get("memorial") in (None, "war_memorial", "obelisk", "stele")):
                if t.get("memorial") == "plaque" or "Plaque" in t.get("name", ""):
                    continue
                self.items.append(("obelisk", g.centroid, {}, key))
            elif t.get("historic") == "wayside_cross":
                self.items.append(("cross", g.centroid, {}, key))

    def build(self, tiles, TILE, Mesh):
        stats = {}
        for kind, g, cfg, key in self.items:
            c = g.centroid
            tk = (int(c.x // TILE), int(c.y // TILE))
            M, C = tiles.setdefault(tk, (Mesh(), []))
            gnd = float(self.dem.h(c.x, c.y)[0])
            if kind == "church":
                k = church(M, C, cfg, g, self.dem, self.road_tree, key)
            elif kind == "ruin":
                r = math.sqrt(g.area / math.pi)
                round_tower(M, C, (c.x, c.y), r, gnd - 1.5, gnd + 8.0, IDX["pierre"], srgb((1.05, 1.0, 0.92)), ruin=True, key=7)
                k = "ruine"
            elif kind == "obelisk":
                obelisk(M, C, c.x, c.y, gnd); k = "monument aux morts"
            else:
                wayside_cross(M, C, c.x, c.y, gnd); k = "croix"
            stats[k] = stats.get(k, 0) + 1
        return stats

    def extras(self, M, C, i, info):
        """Habillage après construction du bâtiment : plaque, drapeaux, mâts, tourelles."""
        ov = self.override[i]
        ring = info["ring"]; k = info["street"]
        A, B = np.asarray(ring[k]), np.asarray(ring[k + 1])
        L = float(np.hypot(*(B - A)))
        d = (B - A) / max(L, 1e-6); out = np.array([d[1], -d[0]])
        gnd = float(max(info["ground"][k], info["ground"][k + 1]))
        mid = (A + B) / 2
        nrm = np.array([out[0], 0, out[1]])
        if ov.get("plaque"):
            w = 2.6 if ov["plaque"] == "plaque_mairie" else 3.6
            y0 = min(gnd + 2.55, info["eave"] - 0.9)
            p = [mid - d * w / 2 + out * 0.04, mid + d * w / 2 + out * 0.04]
            M.poly([(p[0][0], y0, p[0][1]), (p[1][0], y0, p[1][1]), (p[1][0], y0 + 0.6, p[1][1]), (p[0][0], y0 + 0.6, p[0][1])],
                   [(0, 1), (1, 1), (1, 0), (0, 0)], IDX[ov["plaque"]], srgb((1, 1, 1)), nrm)
        if ov.get("flags"):
            y = min(gnd + 3.6, info["eave"] - 1.6)
            for sg, lay in ((-1, "drapeau_fr"), (1, "drapeau_eu")):
                root = mid + d * sg * min(2.2, L / 2 - 0.5) + out * 0.05
                flag(M, root, out + np.array([0, 0]) * 0, y, IDX[lay])
        if ov.get("poles"):
            for j, lay in enumerate(("drapeau_fr", "drapeau_eu", "drapeau_fr")):
                p = mid + out * 9.0 + d * (j - 1) * 2.4
                flag_pole(M, C, p[0], p[1], float(self.dem.h(p[0], p[1])[0]), IDX[lay])
        t = ov.get("turret")
        if t:
            foot = info["foot"]
            ringf = np.asarray(foot.exterior.coords)[:-1]
            # coins du côté rue
            ca, cb = A, B
            if t == "towers":
                for corner in (ca, cb):
                    round_tower(M, C, corner + out * 0.6, 2.7, info["base"], info["eave"] + 1.2, info["wall"],
                                info["wtint"], (IDX["tuile_ancienne"], srgb((0.8, 0.72, 0.68))), 6.5, n=16, key=3,
                                windows=4, gnd=gnd)
            elif t == "octo":
                round_tower(M, C, cb + out * 0.4 + d * 0.4, 2.1, info["base"], info["eave"] + 2.5, info["wall"], info["wtint"],
                            (IDX["ardoise"], srgb((0.7, 0.74, 0.8))), 4.5, n=8, key=4, windows=3, gnd=gnd)
            else:
                round_tower(M, C, ca + out * 0.3, 1.9, info["base"], info["eave"] + 2.0, info["wall"], info["wtint"],
                            (IDX["ardoise"], srgb((0.75, 0.78, 0.82))), 4.5, n=14, key=5, windows=3, gnd=gnd)
