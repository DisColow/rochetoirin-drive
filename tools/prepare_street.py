"""Équipements de la route : trottoirs, marquages, panneaux, lampadaires, ralentisseurs,
passages à niveau, terre-pleins, caténaires.

À lancer APRÈS prepare_data.py puis prepare_decor.py.

Sources : OpenStreetMap (emplacements réels des stops, cédez-le-passage, passages piétons,
feux, ralentisseurs, passages à niveau, panneaux d'agglomération, limitations, ronds-points)
complétées par des règles quand la donnée manque (trottoirs et lampadaires en zone bâtie).

Sorties (assets) :
  street.bin   maillages (format props.bin) : trottoirs, bordures, panneaux, lampadaires, feux,
               barrières, îlots, glissières, caténaires
  decals.bin   marquages au sol et plateaux (format roads.bin)
  surf.bin     surélévations pour la physique (trottoirs, plateaux, dos d'âne), cm, tuiles de 32 m à 33 × 33 points (1 m)
  collide.bin  complété (poteaux, îlots, glissières)
  street.json  noms des communes pour les panneaux d'entrée
"""
import json, math, os, pickle, struct
import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import distance_transform_edt
from shapely.geometry import LineString, Polygon, Point, box
import shapely
import sidewalks as sw_mod
from shapely.ops import polygonize, unary_union
from geo import to_local
from prepare_data import Grid, X0, X1, Z0, Z1, CHUNK
from prepare_decor import Mesh, Chunks, read_grid, box_mesh, triangulate, norm, polys, load, loc, \
    M_PLAIN, M_STEEL, M_CABLE

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "data")
ASSETS = os.path.join(HERE, "..", "app", "src", "main", "assets")

M_PAVE, M_CURB, M_GRASS, M_SIGN, M_LIGHT = 12, 13, 14, 15, 16
# décalcomanies (styles du shader de route)
D_ZEBRA, D_STOP, D_GIVEWAY, D_RAMP, D_TABLE = 30.0, 31.0, 32.0, 33.0, 34.0

# atlas des panneaux : (colonne, ligne, largeur en cases) sur une grille 8 × 8 (lignes 4-5 : centre du village)
SIGN_STOP, SIGN_GIVEWAY, SIGN_PED, SIGN_BUMP, SIGN_LC, SIGN_CROSS, SIGN_BACK, SIGN_STRIPES = [(c, 0, 1) for c in range(8)]
SPEEDS = [30, 50, 70, 80, 90, 110, 130]
SIGN_LIGHT = (7, 1, 1)


def sign_uv(cell):
    c, r, w = cell
    return c / 8.0, r / 8.0, (c + w) / 8.0, (r + 1) / 8.0


def entry_cell(i, exit_):
    slot = i * 2 + exit_
    return ((slot % 4) * 2, 2 + slot // 4, 2)


class Road:
    def __init__(self, d):
        self.__dict__.update(d)
        self.hw = self.width / 2
        self.n = len(self.P)
        T = np.zeros_like(self.P)
        T[1:-1] = self.P[2:] - self.P[:-2]; T[0] = self.P[1] - self.P[0]; T[-1] = self.P[-1] - self.P[-2]
        self.T = T / np.maximum(np.linalg.norm(T, axis=1, keepdims=True), 1e-9)

    def row_near(self, x, z):
        d = np.hypot(self.P[:, 0] - x, self.P[:, 1] - z)
        k = int(np.argmin(d))
        return k, float(d[k])

    def at(self, s, lat):
        """Point de la chaussée à l'abscisse s et au décalage latéral lat (m), avec son altitude."""
        s = min(max(s, 0.0), float(self.s[-1]))
        k = int(np.searchsorted(self.s, s) - 1)
        k = min(max(k, 0), self.n - 2)
        f = (s - self.s[k]) / max(self.s[k + 1] - self.s[k], 1e-6)
        P = self.P[k] + (self.P[k + 1] - self.P[k]) * f
        N = self.N[k] + (self.N[k + 1] - self.N[k]) * f
        N = N / max(np.linalg.norm(N), 1e-9)
        T = self.T[k] + (self.T[k + 1] - self.T[k]) * f
        T = T / max(np.linalg.norm(T), 1e-9)
        t = np.clip(lat / max(self.hw, 0.1), -1, 1)
        ys = self.VY[k] + (self.VY[k + 1] - self.VY[k]) * f      # 3 colonnes : -hw, 0, +hw
        y = ys[1] + (ys[2] - ys[1]) * t if t >= 0 else ys[1] + (ys[0] - ys[1]) * (-t)
        p = P + N * lat
        return np.array([p[0], y, p[1]]), N, T


def main():
    global terrain
    H, tx0, tz0, tst = read_grid(os.path.join(ASSETS, "terrain.bin"))
    terrain = Grid(H, tx0, tz0, tst)
    import center
    center.setup(terrain, Mesh)
    import prepare_quartier as quartier_mod
    roads = [Road(d) for d in pickle.load(open(os.path.join(DATA, "road_rows.pkl"), "rb"))]
    by_node = {}
    for i, r in enumerate(roads):
        for n in r.part:
            by_node.setdefault(n, []).append(i)
    osm = json.load(open(os.path.join(DATA, "osm.json")))
    street = json.load(open(os.path.join(DATA, "osm_street.json")))
    node_tags, node_pos = {}, {}
    for e in osm["elements"] + street["elements"]:
        if e["type"] == "node":
            x, z = to_local(e["lon"], e["lat"])
            node_pos[e["id"]] = (float(x), float(z))
            if e.get("tags"):
                node_tags[e["id"]] = e["tags"]

    # ---------------------------------------------------------------- rasters d'aide (1 m)
    MW, MH = int(X1 - X0), int(Z1 - Z0)
    bimg = Image.new("L", (MW, MH), 0); db = ImageDraw.Draw(bimg)
    built = Image.new("L", (MW // 4, MH // 4), 0); dbu = ImageDraw.Draw(built)
    cb = open(os.path.join(DATA, "collide_buildings.bin"), "rb").read()   # bâtiments seuls (écrit par prepare_decor)
    nb = struct.unpack("<i", cb[4:8])[0]; p = 8
    rings = []
    for _ in range(nb):
        k = struct.unpack("<i", cb[p:p + 4])[0]
        ring = np.frombuffer(cb[p + 4:p + 4 + k * 8], "<f4").reshape(-1, 2).astype(float); p += 4 + k * 8
        rings.append(ring)
        db.polygon([(x - X0, z - Z0) for x, z in ring], fill=255)
        c = ring.mean(axis=0)
        dbu.ellipse([(c[0] - X0) / 4 - 9, (c[1] - Z0) / 4 - 9, (c[0] - X0) / 4 + 9, (c[1] - Z0) / 4 + 9], fill=255)
    bdist = distance_transform_edt(np.array(bimg) == 0)       # distance au bâtiment le plus proche (m)
    # zone bâtie : au moins quelques maisons dans un rayon de ~36 m
    builtm = np.array(built) > 0
    rimg = Image.new("I", (MW, MH), 0); dr = ImageDraw.Draw(rimg)
    for i, r in enumerate(roads):
        if r.cls == "rail":
            continue
        L = [(x - X0, z - Z0) for x, z in r.P]
        dr.line(L, fill=i + 1, width=max(2, int(round(r.width))))
    rid = np.array(rimg)

    def px(x, z):
        return int(min(MW - 1, max(0, x - X0))), int(min(MH - 1, max(0, z - Z0)))

    def bd(x, z):
        i, j = px(x, z); return float(bdist[j, i])

    def is_built(x, z):
        i, j = px(x, z); return bool(builtm[min(j // 4, builtm.shape[0] - 1), min(i // 4, builtm.shape[1] - 1)])

    def other_road(x, z, own):
        i, j = px(x, z); v = int(rid[j, i]); return v != 0 and v != own + 1

    props = Chunks()
    _ROAD_IN = [None]            # chaussée rétrécie (préparée) une fois les trottoirs construits
    decals = {}      # tuile -> (verts, idx) au format routes (10 flottants)
    surf = {}        # tuile (32 m) -> tableau 64 × 64 de cm
    extra_coll = []  # nouveaux obstacles (anneaux)

    def decal_quad(r, s0, s1, lat0, lat1, style, nseg=1, hfun=None, along_fn=None):
        """Bande de chaussée entre s0..s1 et lat0..lat1 (au format routes), éventuellement surélevée."""
        mid, _, _ = r.at((s0 + s1) / 2, (lat0 + lat1) / 2)
        key = (min(props.nCx - 1, max(0, int((mid[0] - X0) // CHUNK))), min(props.nCz - 1, max(0, int((mid[2] - Z0) // CHUNK))))
        verts, idx = decals.setdefault(key, ([], []))
        base = len(verts) // 10
        hw_attr = max(abs(lat0), abs(lat1), 0.5) if style == D_ZEBRA else r.hw
        for a in range(nseg + 1):
            s = s0 + (s1 - s0) * a / nseg
            along = along_fn(s) if along_fn else s - s0
            for lat in (lat0, lat1):
                q, N, T = r.at(s, lat)
                y = q[1] + 0.012 + (hfun(s) if hfun else 0.0)
                verts.extend([q[0], y, q[2], 0, 1, 0, lat, along, hw_attr, style])
        for a in range(nseg):
            i0 = base + a * 2
            idx.extend([i0, i0 + 2, i0 + 1, i0 + 1, i0 + 2, i0 + 3])

    def surf_poly(pts, cm):
        """Ajoute une surélévation (polygone, en cm) dans la grille physique."""
        xs = [q[0] for q in pts]; zs = [q[1] for q in pts]
        for tx in range(int((min(xs) - X0) // 32), int((max(xs) - X0) // 32) + 1):
            for tz in range(int((min(zs) - Z0) // 32), int((max(zs) - Z0) // 32) + 1):
                img = Image.new("L", (33, 33), 0)
                ImageDraw.Draw(img).polygon([((x - X0 - tx * 32), (z - Z0 - tz * 32)) for x, z in pts], fill=int(cm))
                a = np.array(img)
                if a.any():
                    t = surf.setdefault((tx, tz), np.zeros((33, 33), np.uint8))
                    np.maximum(t, a, out=t)

    def pole_coll(x, z, r=0.15):
        if _ROAD_IN[0] is not None and _ROAD_IN[0].contains(Point(x, z)):
            return
        extra_coll.append(np.array([[x - r, z - r], [x + r, z - r], [x + r, z + r], [x - r, z + r]]))

    def plate(m, center, normal, w, h, cell, shape_back=True):
        """Panneau double face : recto texturé, verso gris (même découpe)."""
        u0, v0, u1, v1 = sign_uv(cell)
        nx, nz = normal
        rx, rz = -nz, nx          # vecteur « droite » du panneau vu de face
        cx, cy, cz = center
        corners = [(-w / 2, -h / 2, u1 if False else u0, v1), (w / 2, -h / 2, u1, v1), (w / 2, h / 2, u1, v0), (-w / 2, h / 2, u0, v0)]
        for face, off in ((0, 0.012), (1, -0.012)):
            ids = []
            for a, b, u, v in corners:
                # vu de face (normale vers l'observateur), la droite du panneau est -r
                px_ = cx - rx * a + nx * off; pz_ = cz - rz * a + nz * off
                ids.append(m.vert((px_, cy + b, pz_), (nx if face == 0 else -nx, 0, nz if face == 0 else -nz), (1, 1, 1), (u, v),
                                  M_SIGN, 1.0 if face == 1 else 0.0))
            if face == 0:
                m.quad(ids[0], ids[1], ids[2], ids[3])
            else:
                m.quad(ids[0], ids[3], ids[2], ids[1])

    def sign_post(x, z, facing, cells, size=0.8, height=2.0):
        """Poteau + un ou plusieurs panneaux empilés. [facing] = normale tournée vers les conducteurs."""
        m = Mesh()
        y = float(terrain.height(x, z))
        top = y + height + size * (len(cells) - 1) * 1.05
        pole(m, x, y - 0.2, top + size / 2, z, 0.07, (0.55, 0.56, 0.58), M_STEEL)
        for k, cell in enumerate(cells):
            w = size * (2.0 if cell[2] == 2 else 1.0)
            plate(m, (x + facing[0] * 0.05, top - k * size * 1.05, z + facing[1] * 0.05), facing, w, size, cell)
        props.add(x, z, m, big=False)
        pole_coll(x, z)

    def right_of(a):
        return np.array([-a[1], a[0]])

    stats = {}

    def count(k):
        stats[k] = stats.get(k, 0) + 1

    def count_n(k, n):
        stats[k] = stats.get(k, 0) + n

    # ---------------------------------------------------------------- trottoirs
    SIDEWALK_CLS = {"residential", "living_street", "tertiary", "secondary", "primary", "unclassified",
                    "tertiary_link", "secondary_link", "primary_link"}
    sidewalk_side = {}   # (road, side) -> tableau des largeurs par rangée (0 = pas de trottoir)
    carriage, carr_ext = sw_mod.carriageway(roads, by_node, node_pos)
    rh = sw_mod.RoadHeight(roads)
    strips, walk_pieces = [], []
    for i, r in enumerate(roads):
        if r.cls not in SIDEWALK_CLS or r.bridge or r.tags.get("junction") == "roundabout":
            continue
        tag = r.tags.get("sidewalk") or r.tags.get("sidewalk:both")
        if tag is None and quartier_mod.in_zone(*r.P[len(r.P) // 2]):
            continue        # rue du Balcon et alentours : pas de trottoir (chaussée, caniveau, entrées privées)
        sides = {}
        for sg, name in ((1, "right"), (-1, "left")):
            forced = tag in ("both", name) or r.tags.get("sidewalk:" + name) == "yes"
            denied = tag in ("no", "none", "separate") or (tag in ("left", "right") and tag != name)
            sides[sg] = "yes" if forced else ("no" if denied else "auto")
        for sg in (1, -1):
            if sides[sg] == "no":
                continue
            col = 2 if sg > 0 else 0
            on = np.zeros(r.n, bool)
            for k in range(r.n):
                ex, ez = r.VX[k, col], r.VZ[k, col]
                if sides[sg] == "auto" and not is_built(ex, ez):
                    continue
                d = r.N[k] * sg
                if bd(ex + d[0] * 0.3, ez + d[1] * 0.3) < 0.9:
                    continue
                on[k] = True
            # supprimer les tronçons isolés trop courts, combler les petits trous
            run = 0
            for k in range(r.n + 1):
                if k < r.n and not on[k]:
                    run += 1
                else:
                    if 0 < run < 3 and k - run > 0 and k < r.n:
                        on[k - run:k] = True
                    run = 0
            run = 0
            for k in range(r.n + 1):
                if k < r.n and on[k]:
                    run += 1
                else:
                    if 0 < run < 4:
                        on[k - run:k] = False
                    run = 0
            if not on.any():
                continue
            sidewalk_side[(i, sg)] = np.where(on, sw_mod.SW_W, 0.0)
            k = 0
            while k < r.n:
                if not on[k]:
                    k += 1
                    continue
                k1 = k
                while k1 + 1 < r.n and on[k1 + 1]:
                    k1 += 1
                a0, a1 = max(0, k - 1) if k > 0 else 0, min(r.n - 1, k1 + 1)
                inner = r.P[a0:a1 + 1] + r.N[a0:a1 + 1] * sg * (r.hw - 0.4)
                outer = r.P[a0:a1 + 1] + r.N[a0:a1 + 1] * sg * (r.hw + sw_mod.SW_W)
                if len(inner) >= 2:
                    pg = Polygon(np.vstack([inner, outer[::-1]])).buffer(0)
                    strips.append(pg)
                count("trottoirs (tronçons)")
                k = k1 + 1

    # assemblage : bandes fusionnées, moins les chaussées (angles arrondis) et les bâtiments
    bld_union = unary_union([Polygon(rg).buffer(0.15, join_style=2) for rg in rings if len(rg) >= 3])
    walk = unary_union(strips).difference(carr_ext).difference(bld_union)
    walk = walk.buffer(-0.3, join_style=2).buffer(0.3, join_style=2)        # pas de lanières < 0,6 m
    walk = walk.buffer(0.25).buffer(-0.25).difference(carr_ext).difference(bld_union)
    walk = unary_union([q for q in sw_mod.polys(walk) if q.area > 2.5]).simplify(0.06)
    print("trottoirs :", shapely.get_num_coordinates(walk), "sommets de contour")
    walk_pieces.extend(sw_mod.polys(walk))
    pickle.dump(dict(carriage=carriage, carr_ext=carr_ext, walk=walk), open(os.path.join(DATA, "surfaces.pkl"), "wb"))
    import shapely as _sh0
    _ROAD_IN[0] = carriage.buffer(-0.1)
    _sh0.prepare(_ROAD_IN[0])
    _raw_add = props.add

    def _small_guard(x, z, m, big=False):
        if not big and m.v:
            xz = np.array([(v[0], v[2]) for v in m.v])
            if np.ptp(xz[:, 0]) < 2.5 and np.ptp(xz[:, 1]) < 2.5 and _ROAD_IN[0].contains(Point(xz[:, 0].mean(), xz[:, 1].mean())):
                return                                   # panneau / poteau / lampadaire tombé sur la chaussée
        _raw_add(x, z, m, big)
    props.add = _small_guard
    walk_b = walk.boundary

    def sw_top(x, z):
        return np.maximum(rh(x, z) + sw_mod.CURB, terrain.height(np.asarray(x), np.asarray(z)) + 0.04)

    def sw_kind(mids):
        pts = shapely.points(mids)
        on_edge = shapely.distance(walk_b, pts) < 0.03
        near_road = shapely.distance(carr_ext, pts) < 0.08
        return np.where(~on_edge, 0, np.where(near_road, 1, 2))

    def sw_base(x, z, kind):
        if kind == 1:
            return float(rh(x, z)[0]) - 0.03
        return float(min(terrain.height(x, z), sw_top(x, z)[0])) - 0.3

    nsw = 0.0
    for cx in range(props.nCx):
        for cz in range(props.nCz):
            cb = box(X0 + cx * CHUNK, Z0 + cz * CHUNK, X0 + (cx + 1) * CHUNK, Z0 + (cz + 1) * CHUNK)
            if not walk.bounds or not cb.intersects(walk):
                continue
            part = walk.intersection(cb)
            for q in sw_mod.polys(part):
                m = Mesh()
                sw_mod.raised_mesh(m, q, sw_top, sw_base, sw_kind, sw_mod.PAVE_COL, M_PAVE, M_CURB)
                if m.i:
                    c = q.representative_point()
                    props.add(c.x, c.y, m, big=True)
                    nsw += q.area
    for q in walk_pieces:
        sw_mod.surf_shape(surf, q, lambda x, z: sw_top(x, z) - terrain.height(x, z), X0, Z0)
    count_n("trottoirs (m²)", int(nsw))

    # tablier d'enrobé dans les angles arrondis des carrefours (au format routes, sans marquage)
    apron = carr_ext.difference(carriage)
    napr = 0.0
    for q in sw_mod.polys(apron):
        if q.area < 0.3:
            continue
        v, tri = sw_mod.tri_poly(q, 3.0)
        if len(tri) == 0:
            continue
        c = q.representative_point()
        style, hw_ = rh.nearest(c.x, c.y)
        if style >= 6:
            continue          # chemins de terre, voies ferrées
        ys = np.maximum(rh(v[:, 0], v[:, 1]), terrain.height(v[:, 0], v[:, 1]) + 0.03) + 0.006
        key = (min(props.nCx - 1, max(0, int((c.x - X0) // CHUNK))), min(props.nCz - 1, max(0, int((c.y - Z0) // CHUNK))))
        verts, idx = decals.setdefault(key, ([], []))
        base = len(verts) // 10
        for (x, z), y in zip(v, ys):
            verts.extend([float(x), float(y), float(z), 0, 1, 0, 0, 0, hw_, style + 10])
        for k in range(0, len(tri), 3):
            idx.extend([base + tri[k], base + tri[k + 2], base + tri[k + 1]])
        napr += q.area
    count_n("angles de carrefour en enrobé (m²)", int(napr))

    # ---------------------------------------------------------------- lampadaires
    lamps = []

    def lamp_ok(x, z):
        return all((x - a) ** 2 + (z - b) ** 2 > 18 ** 2 for a, b in lamps[-300:])

    for i, r in enumerate(roads):
        if r.cls in ("motorway", "motorway_link", "track", "rail", "service") or r.bridge:
            continue
        s = 12.0
        side = 1
        while s < r.s[-1] - 6:
            q, N, T = r.at(s, 0)
            if is_built(q[0], q[2]):
                sw = sidewalk_side.get((i, side))
                k, _ = r.row_near(q[0], q[2])
                off = r.hw + ((sw[k] - 0.35) if sw is not None and sw[k] > 0 else 0.9)
                x, z = q[0] + N[0] * side * off, q[2] + N[1] * side * off
                if bd(x, z) > 0.6 and not other_road(x, z, i) and lamp_ok(x, z):
                    style = center.lamp_style(x, z)
                    if quartier_mod.in_zone(x, z):
                        props.add(x, z, quartier_lamp(x, float(terrain.height(x, z)), z, -N[0] * side, -N[1] * side), False)
                    elif style:
                        props.add(x, z, center.champignon(x, z, style == "double"), False)
                    else:
                        lamp_mesh(x, float(terrain.height(x, z)), z, -N[0] * side, -N[1] * side, False, props)
                    pole_coll(x, z)
                    lamps.append((x, z))
                    count("lampadaires")
                if r.width >= 6.0:
                    side = -side
            s += 38.0
    for nid, t in node_tags.items():
        if t.get("highway") == "street_lamp" and nid in node_pos:
            x, z = node_pos[nid]
            if X0 + 50 < x < X1 - 50 and Z0 + 50 < z < Z1 - 50 and lamp_ok(x, z):
                if center.lamp_style(x, z):
                    props.add(x, z, center.champignon(x, z, center.lamp_style(x, z) == "double"), False)
                else:
                    lamp_mesh(x, float(terrain.height(x, z)), z, 1, 0, False, props)
                pole_coll(x, z)
                count("lampadaires")

    # ---------------------------------------------------------------- éléments ponctuels OSM
    def road_of(nid, x, z):
        best = None
        for i in by_node.get(nid, []):
            r = roads[i]
            if r.cls == "rail":
                continue
            k, d = r.row_near(x, z)
            if best is None or d < best[2]:
                best = (i, k, d)
        if best is None:
            # nœud proche mais pas sur la voie (passages à niveau, panneaux)
            for i, r in enumerate(roads):
                if r.cls == "rail":
                    continue
                k, d = r.row_near(x, z)
                if d < 9 and (best is None or d < best[2]):
                    best = (i, k, d)
        return best

    def approach_dir(r, nid, k, tags):
        d = tags.get("direction")
        if d in ("forward", "backward"):
            return 1 if d == "forward" else -1
        if nid in r.part:
            idx = r.part.index(nid)
            return 1 if idx >= len(r.part) / 2 else -1
        return 1 if k >= r.n / 2 else -1

    def side_offset(i, sg_right, k):
        sw = sidewalk_side.get((i, sg_right))
        return roads[i].hw + (sw[k] if sw is not None and sw[k] > 0 else 0) + 0.7

    for nid, t in node_tags.items():
        if nid not in node_pos:
            continue
        x, z = node_pos[nid]
        if not (X0 + 60 < x < X1 - 60 and Z0 + 60 < z < Z1 - 60):
            continue
        hwy = t.get("highway"); calm = t.get("traffic_calming"); rail = t.get("railway"); ts = t.get("traffic_sign", "")
        if not (hwy in ("stop", "give_way", "crossing", "traffic_signals") or calm or rail == "level_crossing"
                or ts.startswith("city_limit") or "maxspeed" in ts or ts.startswith("FR:B14")):
            continue
        hit = road_of(nid, x, z)
        if hit is None:
            continue
        i, k, _ = hit
        r = roads[i]
        s = float(r.s[k])
        T = r.T[k]
        if hwy in ("stop", "give_way"):
            sg = approach_dir(r, nid, k, t)
            a = T * sg
            rt = right_of(a)
            lat_sign = 1 if np.dot(rt, r.N[k]) > 0 else -1
            lat0, lat1 = (0.0, lat_sign * (r.hw - 0.2)) if not r.oneway else (-(r.hw - 0.2), r.hw - 0.2)
            width = 0.5 if hwy == "stop" else 0.5
            decal_quad(r, s - width / 2, s + width / 2, min(lat0, lat1), max(lat0, lat1), D_STOP if hwy == "stop" else D_GIVEWAY)
            off = side_offset(i, lat_sign, k)
            q, N, _ = r.at(s - sg * 1.5, 0)
            sign_post(q[0] + rt[0] * off, q[2] + rt[1] * off, (-a[0], -a[1]), [SIGN_STOP if hwy == "stop" else SIGN_GIVEWAY],
                      size=0.8 if hwy == "stop" else 0.9)
            count("stops" if hwy == "stop" else "cédez-le-passage")
        elif hwy == "crossing" or (hwy == "traffic_signals" and t.get("crossing")):
            if t.get("crossing") in ("unmarked", "no", "informal") or r.cls in ("track", "service"):
                continue
            decal_quad(r, s - 2.0, s + 2.0, -r.hw, r.hw, D_ZEBRA)
            if r.cls in ("primary", "secondary", "tertiary"):
                for sg in (1, -1):
                    a = T * sg; rt = right_of(a)
                    lat_sign = 1 if np.dot(rt, r.N[k]) > 0 else -1
                    off = side_offset(i, lat_sign, k)
                    q, _, _ = r.at(s - sg * 2.5, 0)
                    sign_post(q[0] + rt[0] * off, q[2] + rt[1] * off, (-a[0], -a[1]), [SIGN_PED], size=0.7)
            count("passages piétons")
        if hwy == "traffic_signals":
            for sg in (1, -1):
                a = T * sg; rt = right_of(a)
                lat_sign = 1 if np.dot(rt, r.N[k]) > 0 else -1
                q, _, _ = r.at(s - sg * 4.0, 0)
                off = side_offset(i, lat_sign, k)
                traffic_light(q[0] + rt[0] * off, q[2] + rt[1] * off, (-a[0], -a[1]), props)
                pole_coll(q[0] + rt[0] * off, q[2] + rt[1] * off)
                if not r.oneway or sg == 1:
                    lo, hi = sorted((0.0, lat_sign * (r.hw - 0.2)))
                    decal_quad(r, s - sg * 3.0 - 0.25, s - sg * 3.0 + 0.25, lo, hi, D_STOP)
            count("feux tricolores")
        if calm in ("table", "bump", "hump"):
            if r.cls in ("motorway", "track"):
                continue
            L = 8.0 if calm == "table" else 4.0
            ramp = 1.6 if calm == "table" else 2.0
            hgt = 0.10

            def hf(ss, s=s, L=L, ramp=ramp):
                u = abs(ss - s)
                if calm == "table":
                    return hgt if u < L / 2 - ramp else max(0.0, hgt * (L / 2 - u) / ramp)
                return hgt * 0.5 * (1 + math.cos(math.pi * min(u / (L / 2), 1.0)))
            if calm == "table":
                decal_quad(r, s - L / 2, s - L / 2 + ramp, -r.hw, r.hw, D_RAMP, nseg=4, hfun=hf, along_fn=lambda ss, s0=s - L / 2: (ss - s0) / ramp)
                decal_quad(r, s - L / 2 + ramp, s + L / 2 - ramp, -r.hw, r.hw, D_TABLE, nseg=2, hfun=hf)
                decal_quad(r, s + L / 2 - ramp, s + L / 2, -r.hw, r.hw, D_RAMP, nseg=4, hfun=hf, along_fn=lambda ss, s1=s + L / 2: (s1 - ss) / ramp)
            else:
                decal_quad(r, s - L / 2, s, -r.hw, r.hw, D_RAMP, nseg=6, hfun=hf, along_fn=lambda ss, s0=s - L / 2: (ss - s0) / (L / 2))
                decal_quad(r, s, s + L / 2, -r.hw, r.hw, D_RAMP, nseg=6, hfun=hf, along_fn=lambda ss, s1=s + L / 2: (s1 - ss) / (L / 2))
            # physique : bandes de 0,5 m
            ss = s - L / 2
            while ss < s + L / 2:
                h = hf(ss + 0.25)
                if h > 0.005:
                    a1, _, _ = r.at(ss, -r.hw); a2, _, _ = r.at(ss, r.hw); b1, _, _ = r.at(ss + 0.5, -r.hw); b2, _, _ = r.at(ss + 0.5, r.hw)
                    surf_poly([(a1[0], a1[2]), (a2[0], a2[2]), (b2[0], b2[2]), (b1[0], b1[2])], h * 100)
                ss += 0.5
            for sg in (1, -1):
                if r.s[-1] > 60:
                    a = T * sg; rt = right_of(a)
                    lat_sign = 1 if np.dot(rt, r.N[k]) > 0 else -1
                    sa = s - sg * 25
                    if 0 < sa < r.s[-1]:
                        q, _, _ = r.at(sa, 0)
                        off = side_offset(i, lat_sign, min(r.n - 1, max(0, k - sg * 6)))
                        sign_post(q[0] + rt[0] * off, q[2] + rt[1] * off, (-a[0], -a[1]), [SIGN_BUMP], size=0.9)
            count("ralentisseurs")
        if rail == "level_crossing":
            rail_hw = 2.0
            for rr in roads:
                if rr.cls == "rail":
                    kk, dd = rr.row_near(x, z)
                    if dd < 10:
                        rail_hw = rr.hw
            for sg in (1, -1):
                a = T * sg; rt = right_of(a)
                lat_sign = 1 if np.dot(rt, r.N[k]) > 0 else -1
                q, _, _ = r.at(s - sg * (rail_hw + 3.0), 0)
                off = r.hw + 0.9
                level_crossing_post(q[0] + rt[0] * off, q[2] + rt[1] * off, (-a[0], -a[1]), rt, r.hw, props)
                pole_coll(q[0] + rt[0] * off, q[2] + rt[1] * off, 0.25)
                sa = s - sg * 110
                if 0 < sa < r.s[-1]:
                    q, _, _ = r.at(sa, 0)
                    sign_post(q[0] + rt[0] * (r.hw + 1.0), q[2] + rt[1] * (r.hw + 1.0), (-a[0], -a[1]), [SIGN_LC], size=0.9)
            count("passages à niveau")
        if ts.startswith("city_limit"):
            pass   # traité plus bas (besoin des noms)
        if "maxspeed" in ts or ts.startswith("FR:B14"):
            v = t.get("maxspeed") or "".join(ch for ch in ts.split("[")[-1] if ch.isdigit())
            try:
                v = int(v)
            except ValueError:
                continue
            cell = (SPEEDS.index(min(SPEEDS, key=lambda q: abs(q - v))), 1, 1)
            dirs = [1 if t.get("direction") == "forward" else -1] if t.get("direction") in ("forward", "backward") else [1, -1]
            for sg in dirs:
                a = T * sg; rt = right_of(a)
                lat_sign = 1 if np.dot(rt, r.N[k]) > 0 else -1
                off = side_offset(i, lat_sign, k)
                sign_post(x + rt[0] * off, z + rt[1] * off, (-a[0], -a[1]), [cell], size=0.75)
            count("limitations")

    # panneaux d'entrée d'agglomération
    places = {}
    for f in json.load(open(os.path.join(DATA, "pois.json")))["elements"]:
        tg = f.get("tags", {})
        if tg.get("place") in ("village", "town", "hamlet") and tg.get("name"):
            c = f.get("center", f)
            places[tg["name"]] = tuple(map(float, to_local(c["lon"], c["lat"])))
    names = []
    for nid, t in node_tags.items():
        if not t.get("traffic_sign", "").startswith("city_limit") or nid not in node_pos:
            continue
        name = t.get("name")
        if not name:
            continue
        x, z = node_pos[nid]
        if not (X0 + 60 < x < X1 - 60 and Z0 + 60 < z < Z1 - 60):
            continue
        hit = road_of(nid, x, z)
        if hit is None:
            continue
        if name not in names:
            if len(names) >= 4:
                continue
            names.append(name)
        ni = names.index(name)
        i, k, _ = hit
        r = roads[i]
        cpos = places.get(name)
        T = r.T[k]
        a_in = T if cpos is None or np.dot(np.subtract(cpos, r.P[k]), T) > 0 else -T   # vers le centre du village
        rt = right_of(a_in)
        lat_sign = 1 if np.dot(rt, r.N[k]) > 0 else -1
        off = side_offset(i, lat_sign, k) + 0.3
        px_, pz_ = r.P[k][0] + rt[0] * off, r.P[k][1] + rt[1] * off
        m = Mesh()
        y = float(terrain.height(px_, pz_))
        for dx in (-0.55, 0.55):
            qx, qz = px_ + (-a_in[1]) * dx * 0 + rt[0] * dx, pz_ + rt[1] * dx
            box_mesh(m, qx, y + 1.25, qz, 0.07, 2.5, 0.07, (0.55, 0.56, 0.58), M_STEEL)
        u0, v0, u1, v1 = sign_uv(entry_cell(ni, 0))
        e0, e1, e2, e3 = sign_uv(entry_cell(ni, 1))
        # recto « entrée » vers l'extérieur, verso « sortie » vers le village
        for face, (nn, uu) in enumerate((((-a_in[0], -a_in[1]), (u0, v0, u1, v1)), ((a_in[0], a_in[1]), (e0, e1, e2, e3)))):
            nx, nz = nn
            rx, rz = -nz, nx
            off2 = 0.012
            ids = []
            for aa, bb, u, v in ((-0.8, -0.4, uu[0], uu[3]), (0.8, -0.4, uu[2], uu[3]), (0.8, 0.4, uu[2], uu[1]), (-0.8, 0.4, uu[0], uu[1])):
                ids.append(m.vert((px_ - rx * aa + nx * off2, y + 2.3 + bb, pz_ - rz * aa + nz * off2), (nx, 0, nz), (1, 1, 1), (u, v), M_SIGN, 0.0))
            m.quad(*ids)
        props.add(px_, pz_, m, big=False)
        pole_coll(px_, pz_, 0.6)
        count("panneaux d'agglomération")

    # ---------------------------------------------------------------- terre-pleins
    # îlots centraux des ronds-points
    rings_l = [LineString(r.P) for r in roads if r.tags.get("junction") == "roundabout"]
    rb_hw = {id(LineString(r.P)): r.hw for r in roads}
    hw_by_line = [r.hw for r in roads if r.tags.get("junction") == "roundabout"]
    if rings_l:
        merged = unary_union(rings_l)
        for poly in polygonize(merged):
            hwm = max(hw_by_line) if hw_by_line else 3.0
            isl = poly.buffer(-(hwm + 0.3))
            for q in polys(isl):
                if q.area < 6:
                    continue
                extra_coll.append(island_mesh(q, props, surf))
                count("îlots de rond-point")
    # chaussées séparées : terre-plein (glissière sur l'autoroute, bordure ailleurs)
    import shapely as _shp
    carr_in = carriage.buffer(-0.2)
    _shp.prepare(carr_in)
    oneways = [i for i, r in enumerate(roads) if r.oneway and r.cls in ("motorway", "trunk", "primary", "secondary", "tertiary")
               and r.tags.get("junction") != "roundabout"]
    for i in oneways:
        r = roads[i]
        for k0 in range(0, r.n - 1, 3):
            mid = r.P[k0]
            opp = False
            for j in oneways:
                if j == i:
                    continue
                kk, dd = roads[j].row_near(*mid)
                # vrai terre-plein seulement : il faut un espace entre les deux chaussées
                gap_ok = (4 < dd < 32) if r.cls == "motorway" else (dd - r.hw - roads[j].hw > 1.5 and dd < 40)
                if gap_ok and np.dot(roads[j].T[kk], r.T[k0]) < -0.7:
                    # la chaussée opposée doit être à gauche
                    if np.dot(roads[j].P[kk] - mid, -r.N[k0]) > 0:
                        opp = True
                        break
            if not opp:
                continue
            k1 = min(r.n - 1, k0 + 3)
            if r.cls == "motorway":
                guardrail(r, float(r.s[k0]), float(r.s[k1]), props, extra_coll, carr_in)
            else:
                median_curb(r, float(r.s[k0]), float(r.s[k1]), props, surf_poly)
        count("terre-pleins (tronçons)")

    # ---------------------------------------------------------------- caténaires
    for r in roads:
        if r.cls != "rail" or r.tags.get("electrified") not in ("contact_line", "yes"):
            continue
        s = 20.0
        prev = None
        while s < r.s[-1] - 10:
            q, N, T = r.at(s, 0)
            side = 1
            mx, mz = q[0] + N[0] * (r.hw + 1.4), q[2] + N[1] * (r.hw + 1.4)
            m = Mesh()
            y = float(terrain.height(mx, mz))
            box_mesh(m, mx, y + 3.9, mz, 0.3, 7.8, 0.3, (0.45, 0.47, 0.48), M_STEEL)
            ax = math.atan2(N[1], N[0])
            span = r.hw + 1.6
            box_mesh(m, (mx + q[0]) / 2 - N[0] * 0.2, y + 7.2, (mz + q[2]) / 2 - N[1] * 0.2, span, 0.12, 0.12, (0.45, 0.47, 0.48), M_STEEL, -ax)
            wires = []
            tracks = max(1, int(round((2 * r.hw - 3.4) / 4.0)) + 1)
            for kk in range(tracks):
                c = (kk - (tracks - 1) / 2) * 4.0
                wires.append((q[0] + N[0] * c, q[1] + 5.6, q[2] + N[1] * c))
                box_mesh(m, wires[-1][0], q[1] + 6.4, wires[-1][2], 0.05, 1.6, 0.05, (0.3, 0.3, 0.3), M_STEEL)
            if prev:
                for a_, b_ in zip(prev, wires):
                    _cable(m, a_, b_)
            props.add(mx, mz, m, big=False)
            pole_coll(mx, mz, 0.25)
            prev = wires
            s += 55.0
        count("caténaires")

    # ---------------------------------------------------------------- centre du village (d'après Street View)
    meta = json.load(open(os.path.join(ASSETS, "map.json")))
    # règle « la logique prime » : rien de ce qui suit (mobilier, centre, quartier) ne mord sur la chaussée,
    # ni (sauf poteaux) sur les trottoirs
    import shapely as _sh
    road_in = carriage.buffer(-0.15)
    _sh.prepare(road_in); _sh.prepare(walk)
    rejected = {"maillages": 0, "obstacles": 0}

    def _foot(xz):
        from shapely.geometry import MultiPoint
        return MultiPoint(xz).convex_hull if len(xz) >= 3 else Point(xz[0]).buffer(0.1)

    def _ov(big, g):
        if not big.intersects(g):
            return 0.0
        return _sh.clip_by_rect(big, *g.bounds).intersection(g).area

    def _bad(g, small_ok):
        if g.is_empty:
            return False
        if _ov(road_in, g) > 0.05 * g.area + 0.02:
            return True
        return (not small_ok) and _ov(walk, g) > 0.25 * g.area

    def guarded_add(x, z, m, big=False):
        # part des sommets posés sur la chaussée / le trottoir (une enveloppe convexe pénaliserait les haies en L)
        xz = np.array([(v[0], v[2]) for v in m.v])
        if len(xz):
            on_r = _sh.contains_xy(road_in, xz[:, 0], xz[:, 1]).mean()
            small = (np.ptp(xz[:, 0]) * np.ptp(xz[:, 1])) < 0.8
            on_w = 0.0 if small else _sh.contains_xy(walk, xz[:, 0], xz[:, 1]).mean()
            if on_r > 0.05 or on_w > 0.25:
                rejected["maillages"] += 1
                return
        props.add(x, z, m, big)

    def guarded_coll(ring):
        g = Polygon(ring).buffer(0)
        if _bad(g, g.area < 0.6):
            rejected["obstacles"] += 1
            return
        extra_coll.append(ring)
    for k, v in center.furniture(guarded_add, guarded_coll, center.roads_union_from(meta)).items():
        stats["centre : " + k] = v
    import mobilier
    for k, v in mobilier.build(guarded_add, guarded_coll, roads, Mesh, lambda x, z: float(terrain.height(x, z))).items():
        stats["bourg : " + k] = v
    for q, hfun in center.RAISED:
        sw_mod.surf_shape(surf, q, hfun, X0, Z0)

    # ---------------------------------------------------------------- quartier de la rue du Balcon
    if os.path.exists(os.path.join(DATA, "cadastre_balcon.json")) and os.path.exists(os.path.join(DATA, "ortho_village.jpg")):
        from prepare_village import Village
        q = quartier_mod.Quartier(Village(), terrain)
        for k, v in quartier_mod.build(q, Mesh, center.obox, center.quad3, guarded_add, guarded_coll, center.parked_car).items():
            stats["rue du Balcon : " + k] = v

    paved_rects = []
    paved_polys = []
    if os.path.exists(os.path.join(DATA, "cadastre_balcon.json")) and os.path.exists(os.path.join(DATA, "ortho_village.jpg")):
        paved_rects = getattr(q, "paved_rects", [])
        paved_polys = getattr(q, "paved_polys", [])
    # ---------------------------------------------------------------- masque de l'herbe 3D (2 m / pixel)
    # 255 = pas d'herbe : chaussées (+ marge), trottoirs, voies ferrées, bâtiments, obstacles, surfaces du quartier
    GM = 2.0
    gm = Image.new("L", (int((X1 - X0) / GM), int((Z1 - Z0) / GM)), 0)
    dg = ImageDraw.Draw(gm)
    gpx = lambda x, z: ((x - X0) / GM, (z - Z0) / GM)
    for i, r in enumerate(roads):
        extra = 3.0 if r.cls == "rail" else 1.2
        sw = max([float(np.max(sidewalk_side[(i, sg)])) for sg in (1, -1) if (i, sg) in sidewalk_side] or [0.0])
        dg.line([gpx(x, z) for x, z in r.P], fill=255, width=max(1, int(round((r.width + 2 * (extra + sw)) / GM))))
    for ring in rings + extra_coll:
        if len(ring) >= 3:
            dg.polygon([gpx(x, z) for x, z in ring], fill=255, outline=255)
    for q in walk_pieces:
        dg.polygon([gpx(x, z) for x, z in q.buffer(0.5).exterior.coords], fill=255, outline=255)
    for xa, za, xb, zb in paved_rects:
        dg.rectangle([gpx(xa, za), gpx(xb, zb)], fill=255)
    for ring in (paved_polys if "paved_polys" in dir() else []):
        if len(ring) >= 3:
            dg.polygon([gpx(x, z) for x, z in ring], fill=255)
    gm.save(os.path.join(ASSETS, "grassmask.png"), optimize=True)

    # ---------------------------------------------------------------- occlusion ambiante du sol (2 m / pixel)
    # assombrit le sol au pied des murs et sous les houppiers (les objets « reposent » sur le terrain)
    write_ground_ao(rings, extra_coll)

    # ---------------------------------------------------------------- écriture
    nv, size = props.write(os.path.join(ASSETS, "street.bin"), b"PRP1")
    out = bytearray(struct.pack("<4sfffii", b"RDS1", X0, Z0, CHUNK, props.nCx, props.nCz))
    out += struct.pack("<i", len(decals))
    for (cx, cz), (v, idx) in sorted(decals.items()):
        out += struct.pack("<iiii", cx, cz, len(v) // 10, len(idx))
        out += np.asarray(v, dtype="<f4").tobytes() + np.asarray(idx, dtype="<u4").tobytes()
    open(os.path.join(ASSETS, "decals.bin"), "wb").write(out)
    s_out = bytearray(struct.pack("<4sfffi", b"SRF1", X0, Z0, 32.0, len(surf)))
    for (tx, tz), a in sorted(surf.items()):
        s_out += struct.pack("<ii", tx, tz) + a.astype(np.uint8).tobytes()
    open(os.path.join(ASSETS, "surf.bin"), "wb").write(s_out)
    # collisions : bâtiments existants + nouveaux obstacles
    all_rings = rings + extra_coll
    c_out = bytearray(struct.pack("<4si", b"COL1", len(all_rings)))
    for ring in all_rings:
        c_out += struct.pack("<i", len(ring)) + np.asarray(ring, dtype="<f4").tobytes()
    open(os.path.join(ASSETS, "collide.bin"), "wb").write(c_out)
    json.dump({"signs": names}, open(os.path.join(ASSETS, "street.json"), "w"), ensure_ascii=False)
    for k, v in stats.items():
        print("%5d %s" % (v, k))
    print("équipements : %d sommets (%.1f Mo), %d tuiles de marquage, %d tuiles physiques, %d obstacles ajoutés"
          % (nv, size / 1e6, len(decals), len(surf), len(extra_coll)))


# ------------------------------------------------------------------------------------ occlusion du sol
def write_ground_ao(rings, extra_coll):
    from scipy.ndimage import gaussian_filter
    R = 1.0
    W, Hh = int((X1 - X0) / R), int((Z1 - Z0) / R)
    occ = Image.new("L", (W, Hh), 0)
    do = ImageDraw.Draw(occ)
    for ring in rings:
        if len(ring) >= 3:
            do.polygon([((x - X0) / R, (z - Z0) / R) for x, z in ring], fill=255)
    d = distance_transform_edt(np.array(occ) == 0) * R
    ao = 1.0 - 0.42 * np.exp(-d / 1.6)
    ao[np.array(occ) > 0] = 0.6
    # houppiers : ombre douce sous l'arbre (rayon relatif à la hauteur, cf. TREE_PARAMS du shader)
    crown = np.zeros((Hh, W), np.float32)
    TPR = [0.36, 0.52, 0.12, 0.24, 0.44, 0.60]
    b = open(os.path.join(ASSETS, "trees.bin"), "rb").read()
    nb = struct.unpack("<i", b[24:28])[0]; p = 28
    for _ in range(nb):
        cx, cz, n = struct.unpack("<iii", b[p:p + 12]); p += 12
        a = np.frombuffer(b[p:p + n * 24], "<f4").reshape(n, 6); p += n * 24
        for x, y, z, h, t, r in a:
            rad = max(0.8, TPR[int(t + 0.5) % 6] * h)
            i0, j0 = int((x - X0) / R), int((z - Z0) / R)
            k = int(rad / R) + 1
            if i0 - k < 0 or j0 - k < 0 or i0 + k >= W or j0 + k >= Hh:
                continue
            yy, xx = np.mgrid[-k:k + 1, -k:k + 1]
            f = np.clip(1.0 - np.sqrt(xx * xx + yy * yy) * R / rad, 0, 1) * min(1.0, h / 8.0)
            sub = crown[j0 - k:j0 + k + 1, i0 - k:i0 + k + 1]
            np.maximum(sub, f, out=sub)
    ao *= 1.0 - 0.38 * gaussian_filter(crown, 1.0)
    ao = gaussian_filter(ao, 0.8)
    # 2 m / pixel
    ao2 = ao[:Hh // 2 * 2, :W // 2 * 2].reshape(Hh // 2, 2, W // 2, 2).mean(axis=(1, 3))
    Image.fromarray(np.clip(ao2 * 255, 0, 255).astype(np.uint8)).save(os.path.join(ASSETS, "groundao.png"), optimize=True)
    print("occlusion du sol :", ao2.shape, "%.0f%% assombri" % (100 * (ao2 < 0.9).mean()))


# ------------------------------------------------------------------------------------ maillages
def pole(m, x, y0, y1, z, w, col, mat):
    """Poteau vertical léger (4 faces + dessus)."""
    h = w / 2
    for nx, nz, ax, az in ((1, 0, 0, 1), (-1, 0, 0, -1), (0, 1, -1, 0), (0, -1, 1, 0)):
        cx, cz = x + nx * h, z + nz * h
        ids = [m.vert((cx - ax * h, y0, cz - az * h), (nx, 0, nz), col, (0, 0), mat), m.vert((cx + ax * h, y0, cz + az * h), (nx, 0, nz), col, (0, 0), mat),
               m.vert((cx + ax * h, y1, cz + az * h), (nx, 0, nz), col, (0, 0), mat), m.vert((cx - ax * h, y1, cz - az * h), (nx, 0, nz), col, (0, 0), mat)]
        m.quad(*ids)


def quartier_lamp(x, y, z, dx, dz):
    """Lampadaire de lotissement (rue du Balcon) : mât gris de 6 m, petite tête inclinée vers la rue."""
    m = Mesh()
    col = (0.62, 0.63, 0.64)
    pole(m, x, y - 0.2, y + 6.0, z, 0.1, col, M_STEEL)
    ax = math.atan2(dz, dx)
    box_mesh(m, x + dx * 0.25, y + 6.05, z + dz * 0.25, 0.65, 0.14, 0.24, (0.35, 0.36, 0.38), M_STEEL, -ax)
    c, s_ = math.cos(ax), math.sin(ax)
    lx, lz, ly = x + dx * 0.3, z + dz * 0.3, y + 5.97
    ids = [m.vert((lx + a * c - b * s_, ly, lz + a * s_ + b * c), (0, -1, 0), (0.92, 0.90, 0.80), (0, 0), M_LIGHT)
           for a, b in ((-0.22, -0.09), (0.22, -0.09), (0.22, 0.09), (-0.22, 0.09))]
    m.quad(*ids)
    return m


def lamp_mesh(x, y, z, dx, dz, classic, props):
    m = Mesh()
    if classic:
        # lanterne de style ancien (centre du village)
        col = (0.13, 0.20, 0.16)
        box_mesh(m, x, y + 0.3, z, 0.32, 0.6, 0.32, col, M_STEEL)
        pole(m, x, y + 0.3, y + 3.95, z, 0.11, col, M_STEEL)
        box_mesh(m, x, y + 4.0, z, 0.36, 0.08, 0.36, col, M_STEEL)
        pole(m, x, y + 4.05, y + 4.65, z, 0.30, (0.85, 0.82, 0.65), M_LIGHT)
        box_mesh(m, x, y + 4.72, z, 0.44, 0.14, 0.44, col, M_STEEL)
        box_mesh(m, x, y + 4.85, z, 0.12, 0.15, 0.12, col, M_STEEL)
    else:
        col = (0.60, 0.62, 0.63)
        h = 7.0
        pole(m, x, y - 0.2, y + h, z, 0.13, col, M_STEEL)
        ax = math.atan2(dz, dx)
        box_mesh(m, x + dx * 0.7, y + h - 0.05, z + dz * 0.7, 1.4, 0.08, 0.08, col, M_STEEL, -ax)
        box_mesh(m, x + dx * 1.45, y + h - 0.12, z + dz * 1.45, 0.65, 0.12, 0.28, col, M_STEEL, -ax)
        lx, lz, ly = x + dx * 1.45, z + dz * 1.45, y + h - 0.185
        c, s_ = math.cos(ax), math.sin(ax)
        ids = [m.vert((lx + a * c - b * s_, ly, lz + a * s_ + b * c), (0, -1, 0), (0.88, 0.86, 0.75), (0, 0), M_LIGHT)
               for a, b in ((-0.25, -0.1), (0.25, -0.1), (0.25, 0.1), (-0.25, 0.1))]
        m.quad(*ids)
    props.add(x, z, m, big=False)


def traffic_light(x, z, facing, props):
    m = Mesh()
    y = float(terrain.height(x, z))
    box_mesh(m, x, y + 1.6, z, 0.12, 3.2, 0.12, (0.25, 0.26, 0.27), M_STEEL)
    nx, nz = facing
    u0, v0, u1, v1 = sign_uv(SIGN_LIGHT)
    cx, cy, cz = x + nx * 0.12, y + 3.0, z + nz * 0.12
    rx, rz = -nz, nx
    ids = [m.vert((cx - rx * a, cy + b, cz - rz * a), (nx, 0, nz), (1, 1, 1), (u, v), M_SIGN, 0.0)
           for a, b, u, v in ((-0.25, -0.5, u0, v1), (0.25, -0.5, u1, v1), (0.25, 0.5, u1, v0), (-0.25, 0.5, u0, v0))]
    m.quad(*ids)
    box_mesh(m, x + nx * 0.02, y + 3.0, z + nz * 0.02, 0.3, 1.05, 0.2, (0.12, 0.12, 0.13), M_PLAIN)
    props.add(x, z, m, big=False)


def level_crossing_post(x, z, facing, right, road_hw, props):
    """Croix de Saint-André, feux rouges clignotants et demi-barrière (relevée)."""
    m = Mesh()
    y = float(terrain.height(x, z))
    nx, nz = facing
    box_mesh(m, x, y + 1.9, z, 0.14, 3.8, 0.14, (0.92, 0.92, 0.9), M_STEEL)
    for k in range(4):
        box_mesh(m, x, y + 0.35 + k * 0.9, z, 0.16, 0.45, 0.16, (0.75, 0.08, 0.08), M_PLAIN)
    # croix
    rx, rz = -nz, nx
    u0, v0, u1, v1 = sign_uv(SIGN_CROSS)
    cx, cy, cz = x + nx * 0.1, y + 3.3, z + nz * 0.1
    for face, sgn in ((0, 1), (1, -1)):
        ids = [m.vert((cx - rx * a + nx * 0.01 * sgn, cy + b, cz - rz * a + nz * 0.01 * sgn), (nx * sgn, 0, nz * sgn), (1, 1, 1), (u, v), M_SIGN, float(face))
               for a, b, u, v in ((-0.7, -0.7, u0, v1), (0.7, -0.7, u1, v1), (0.7, 0.7, u1, v0), (-0.7, 0.7, u0, v0))]
        m.quad(*ids) if face == 0 else m.quad(ids[0], ids[3], ids[2], ids[1])
    # feux
    for s in (-0.35, 0.35):
        box_mesh(m, x - rx * s + nx * 0.15, y + 2.35, z - rz * s + nz * 0.15, 0.3, 0.3, 0.12, (0.1, 0.1, 0.1), M_PLAIN)
        box_mesh(m, x - rx * s + nx * 0.22, y + 2.35, z - rz * s + nz * 0.22, 0.2, 0.2, 0.02, (0.6, 0.05, 0.05), M_PLAIN)
    # boîtier et barrière relevée (rayée rouge et blanc)
    box_mesh(m, x - right[0] * 0.5, y + 0.6, z - right[1] * 0.5, 0.5, 1.2, 0.5, (0.85, 0.85, 0.82), M_STEEL)
    L = road_hw + 0.4
    u0, v0, u1, v1 = sign_uv(SIGN_STRIPES)
    bx, bz = x - right[0] * 0.5, z - right[1] * 0.5
    for face, (fnx, fnz) in enumerate(((nx, nz), (-nx, -nz))):
        ids = [m.vert((bx + fnx * 0.05 - rx * 0.0 + (-rx) * w_, y + 1.2 + hh, bz + fnz * 0.05 + (-rz) * w_), (fnx, 0, fnz), (1, 1, 1), (u, v), M_SIGN, 0.0)
               for w_, hh, u, v in ((-0.05, 0.0, u0, v1), (0.05, 0.0, u0, v0), (0.05, L, u1, v0), (-0.05, L, u1, v1))]
        m.quad(*ids) if face == 0 else m.quad(ids[0], ids[3], ids[2], ids[1])
    props.add(x, z, m, big=False)


def island_mesh(q, props, surf):
    """Îlot central engazonné avec bordure basse franchissable ; petit massif central (obstacle)."""
    m = Mesh()
    q = q.simplify(0.05)
    qb = q.boundary
    top = lambda x, z: terrain.height(np.asarray(x), np.asarray(z)) + 0.07 + sw_mod.CURB + 0.02
    kind = lambda mids: np.where(shapely.distance(qb, shapely.points(mids)) < 0.03, 1, 0)
    base = lambda x, z, k: float(terrain.height(x, z)) - 0.05
    sw_mod.raised_mesh(m, q, top, base, kind, (0.30, 0.46, 0.17), M_GRASS, M_CURB, step=3.0, band=0.2)
    sw_mod.surf_shape(surf, q, lambda x, z: np.full(np.shape(x), 0.07 + sw_mod.CURB + 0.02), X0, Z0)
    c = q.centroid
    yc = float(terrain.height(c.x, c.y))
    s = min(2.5, math.sqrt(q.area) * 0.3)
    box_mesh(m, c.x, yc + 0.45, c.y, s, 0.5, s, (0.55, 0.50, 0.42), M_CURB)
    props.add(c.x, c.y, m, big=True)
    return np.array([[c.x - s / 2, c.y - s / 2], [c.x + s / 2, c.y - s / 2], [c.x + s / 2, c.y + s / 2], [c.x - s / 2, c.y + s / 2]])


def guardrail(r, s0, s1, props, coll, carriage=None):
    """Glissière de sécurité métallique sur le bord gauche (terre-plein central de l'autoroute)."""
    m = Mesh()
    lat = -(r.hw + 0.7)
    s = s0
    pts = []
    while s <= s1 + 0.01:
        q, N, T = r.at(s, lat)
        if carriage is not None and carriage.contains(Point(q[0], q[2])):
            break                                    # glissière qui tomberait sur l'autre chaussée : on s'arrête
        pts.append(q)
        pole(m, q[0], q[1] - 0.1, q[1] + 0.8, q[2], 0.1, (0.6, 0.62, 0.63), M_STEEL)
        s += 4.0
    for a, b in zip(pts[:-1], pts[1:]):
        mid_ = (a + b) / 2
        if carriage is not None and carriage.contains(Point(mid_[0], mid_[2])):
            continue                                 # tronçon de glissière qui traverserait l'autre chaussée
        d = norm(b - a)
        side = norm(np.cross(d, [0, 1, 0]))
        for hh in (0.55, 0.75):
            ids = [m.vert(p + np.array([0, hh, 0]), side, (0.70, 0.72, 0.74), (0, 0), M_STEEL) for p in (a, b)] + \
                  [m.vert(p + np.array([0, hh + 0.12, 0]), side, (0.70, 0.72, 0.74), (0, 0), M_STEEL) for p in (b, a)]
            m.quad(*ids)
        coll.append(np.array([[a[0] - side[0] * 0.15, a[2] - side[2] * 0.15], [b[0] - side[0] * 0.15, b[2] - side[2] * 0.15],
                              [b[0] + side[0] * 0.15, b[2] + side[2] * 0.15], [a[0] + side[0] * 0.15, a[2] + side[2] * 0.15]]))
    if pts:
        props.add(pts[0][0], pts[0][2], m, big=True)


def median_curb(r, s0, s1, props, surf_poly):
    """Bordure du terre-plein sur le bord gauche d'une chaussée séparée."""
    m = Mesh()
    s = s0
    prev = None
    while s <= s1 + 0.01:
        a, N, T = r.at(s, -r.hw)
        b, _, _ = r.at(s, -r.hw - 0.3)
        cur = (a, b)
        if prev:
            (a0, b0), (a1, b1) = prev, cur
            up = np.array([0, 0.12, 0])
            ids = [m.vert(p, (0, 1, 0), (0.75, 0.74, 0.71), (0, 0), M_CURB) for p in (a0 + up, a1 + up, b1 + up, b0 + up)]
            m.quad(*ids)
            nn = (N[0], 0, N[1])
            ids = [m.vert(p, nn, (0.72, 0.71, 0.68), (0, 0), M_CURB) for p in (a0, a1, a1 + up, a0 + up)]
            m.quad(*ids)
            surf_poly([(a0[0], a0[2]), (a1[0], a1[2]), (b1[0], b1[2]), (b0[0], b0[2])], 12)
        prev = cur
        s += 4.0
    if prev:
        props.add(prev[0][0], prev[0][2], m, big=True)


def _cable(m, a, b):
    a = np.array(a); b = np.array(b)
    d = norm(b - a)
    side = norm(np.cross(d, [0, 1, 0])) * 0.02
    up = np.array([0, 0.02, 0])
    for off in (side, up):
        ids = [m.vert(p + o, (0, 1, 0), (0.25, 0.22, 0.18), (0, 0), M_CABLE) for p, o in ((a, -off), (b, -off), (b, off), (a, off))]
        m.quad(*ids)


if __name__ == "__main__":
    main()
