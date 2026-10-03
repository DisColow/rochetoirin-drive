"""Quartier de la rue du Balcon (Rochetoirin) : clôtures, murets, haies, portails, gravier, parkings.

Sources (libres) :
  * cadastre IGN Parcellaire Express (data/cadastre_balcon.json, tools/fetch_cadastre.py) : limites de parcelles ;
  * orthophotographie IGN 20 cm (data/ortho_village.jpg) : présence et type de haie sur chaque limite,
    entrées des maisons, gravier / béton / enrobé au sol ;
  * vues Street View fournies (sept. 2014, 8 rue du Balcon) : style des clôtures côté rue — muret et
    clôture blanche à lisses entre piliers, portail blanc, entrée gravillonnée, place de parking bétonnée.

Règles :
  * limite couverte de végétation sur la photo  -> haie taillée continue (thuyas sombres ou lauriers clairs) ;
  * limite côté rue sans haie                   -> muret + clôture (lisses blanches, ou grillage rigide vert) ;
  * limite entre deux jardins sans haie         -> grillage vert sur poteaux ;
  * entrée détectée (gravier/enrobé jusqu'à la rue) -> portail entre deux piliers, boîte aux lettres.
"""
import json, math, os, pickle, struct, random
import numpy as np
from scipy import ndimage as ndi
from shapely.geometry import Polygon, LineString, Point, box
from shapely.ops import unary_union
from shapely.strtree import STRtree

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "data")
ZONE = (-600.0, -160.0, -180.0, 230.0)
(M_PLAIN, M_WALL, M_INDUS, M_TILES, M_METAL, M_FLAT, M_WATER, M_CHURCH, M_STEEL, M_CABLE, M_GLASS,
 M_STREAM, M_PAVE, M_CURB, M_GRASS, M_SIGN, M_LIGHT, M_RUBBLE, M_CREPI, M_HEDGE, M_GRAVEL, M_MESH) = range(22)

WHITE = (0.92, 0.91, 0.87)
CREAM = (0.86, 0.82, 0.72)            # piliers et murets enduits
CONCRETE = (0.70, 0.69, 0.65)         # murets en béton gris
WOOD = (0.42, 0.27, 0.16)
IRON = (0.08, 0.08, 0.09)
STONE = (0.5, 0.5, 0.5)               # neutre : la couleur vient du shader des moellons
ADDR12 = (-378.5, 32.2)               # 12 rue du Balcon (géocodeur IGN)
THUJA = (0.15, 0.27, 0.13)
LAUREL = (0.25, 0.38, 0.16)
GREEN_MESH = (0.12, 0.30, 0.18)


# clôtures, murets, haies, portails et sols : tout le bourg couvert par l'orthophoto (le style « rue du Balcon »
# des trottoirs, lampadaires et toits reste limité à ZONE)
FENCE_ZONE = (-660.0, -160.0, 420.0, 720.0)


def fence_poly():
    x0, z0, x1, z1 = FENCE_ZONE
    return box(x0, z0, x1, z1)


def zone_poly():
    x0, z0, x1, z1 = ZONE
    return box(x0, z0, x1, z1)


def in_zone(x, z):
    x0, z0, x1, z1 = ZONE
    return x0 <= x <= x1 and z0 <= z <= z1


class Quartier:
    def __init__(self, village, terrain, buildings=None):
        from prepare_decor import loc, polys
        self.v = village
        self.terrain = terrain
        d = json.load(open(os.path.join(DATA, "cadastre_balcon.json")))
        self.parcels = []
        for f in d["features"]:
            for p in polys(loc(f["geometry"])):
                if p.area > 20:
                    self.parcels.append((f["properties"].get("idu") or f["properties"].get("numero"), p))
        if buildings is None:
            buildings = []
            cb = open(os.path.join(DATA, "collide_buildings.bin"), "rb").read()
            n = struct.unpack("<i", cb[4:8])[0]; p = 8
            for _ in range(n):
                k = struct.unpack("<i", cb[p:p + 4])[0]
                ring = np.frombuffer(cb[p + 4:p + 4 + k * 8], "<f4").reshape(-1, 2).astype(float); p += 4 + k * 8
                if len(ring) >= 3:
                    buildings.append(Polygon(ring).buffer(0))
        Z = fence_poly().buffer(30)
        self.buildings = [b for b in buildings if Z.intersects(b)]
        self.btree = STRtree(self.buildings) if self.buildings else None
        rows = pickle.load(open(os.path.join(DATA, "road_rows.pkl"), "rb"))
        rl = []
        for r in rows:
            if r["cls"] == "rail" or len(r["P"]) < 2:
                continue
            L = LineString(r["P"])
            if Z.intersects(L):
                rl.append(L.buffer(r["width"] / 2, cap_style=2))
        self.roads = unary_union(rl)
        # parcelle habitée : contient (le centre d') une maison
        self.res = {}
        for pid, p in self.parcels:
            self.res[pid] = any(p.contains(b.representative_point()) and b.area > 25 for b in self._near_b(p))
        self._masks()
        self._segments()

    def _near_b(self, g):
        if self.btree is None:
            return []
        return [self.buildings[i] for i in self.btree.query(g)]

    def H(self, x, z):
        return float(self.terrain.height(x, z))

    # ---------------------------------------------------------------- photo
    def _masks(self):
        v = self.v
        f = int(round(0.5 / v.res))
        h, w = v.img.shape[0] // f * f, v.img.shape[1] // f * f
        a = v.img[:h, :w].reshape(h // f, f, w // f, f, 3).mean(axis=(1, 3))
        R, G, B = a[..., 0], a[..., 1], a[..., 2]
        L = (R + G + B) / 3
        exg = 2 * G - R - B
        sat = a.max(axis=2) - a.min(axis=2)
        mu = ndi.uniform_filter(L, 3)
        sd = np.sqrt(np.maximum(ndi.uniform_filter(L * L, 3) - mu * mu, 0))
        self.c = 0.5
        self.hedge = (exg > 7) & (L < 135) & (sd > 5)
        self.dark = L < 78
        veg = exg > 7
        self.gravel = (~veg) & (L > 140) & (sat > 14) & (sat < 60) & (R >= G) & (G >= B - 4)
        self.concrete = (~veg) & (L > 135) & (sat <= 14)
        self.asphalt = (~veg) & (L > 70) & (L <= 135) & (sat < 16) & (sd < 10)
        for name in ("gravel", "concrete", "asphalt"):
            m = getattr(self, name)
            setattr(self, name, ndi.binary_opening(m, iterations=1))
        # haies = végétation étroite (< ~3 m de large) ; les houppiers larges restent des arbres
        tree = v.tree[:self.hedge.shape[0], :self.hedge.shape[1]]
        dist = ndi.distance_transform_edt(tree) * self.c
        crowns = ndi.binary_dilation(dist >= 1.6, iterations=3) & tree
        self.hedgem = ndi.binary_opening(tree & ~crowns, iterations=1)
        self.hdist = dist

    def _ij(self, x, z):
        return int((z - self.v.z0) / self.c), int((x - self.v.x0) / self.c)

    def frac(self, mask, pts):
        n = 0; s = 0
        for x, z in pts:
            j, i = self._ij(x, z)
            if 0 <= j < mask.shape[0] and 0 <= i < mask.shape[1]:
                n += 1; s += bool(mask[j, i])
        return s / n if n else 0.0

    # ---------------------------------------------------------------- limites
    def _segments(self):
        edges = {}
        for pid, p in self.parcels:
            cs = list(p.exterior.coords)
            for a, b in zip(cs[:-1], cs[1:]):
                if math.dist(a, b) < 0.3:
                    continue
                ka = (round(a[0], 1), round(a[1], 1)); kb = (round(b[0], 1), round(b[1], 1))
                key = (ka, kb) if ka < kb else (kb, ka)
                edges.setdefault(key, [a, b, []])[2].append(pid)
        # découpe en morceaux de ~2,5 m, puis harmonisation par limite (règle « la logique prime ») : un seul type,
        # un seul décalage et une seule essence par limite, posés d'un bout à l'autre sans trou
        self.pieces = []      # dict(a, b, kind, pids, street, dark, off, nrm, edge)
        zone = fence_poly()
        import center
        hard = self.roads
        sp = os.path.join(DATA, "surfaces.pkl")
        if os.path.exists(sp):
            S = pickle.load(open(sp, "rb"))
            hard = unary_union([hard, S["walk"], S["carriage"]])     # trottoirs et enrobé : rien dessus
        self.hard = hard
        veg = self.hedgem | self.v.tree[:self.hedgem.shape[0], :self.hedgem.shape[1]]
        for ei, ((ka, kb), (a, b, pids)) in enumerate(edges.items()):
            if not any(self.res.get(p) for p in pids):
                continue
            a = np.array(a, float); b = np.array(b, float)
            L = float(np.linalg.norm(b - a))
            d = (b - a) / L; nrm_ = np.array([-d[1], d[0]])
            mid0 = (a + b) / 2
            res_p = [p_ for p_ in pids if self.res.get(p_)]
            # côté rue : chaussée à moins de 5 m, ou parcelle voisine non bâtie qui porte la chaussée (impasse, voie privée)
            dr = self.roads.distance(Point(mid0))
            lane = any(not self.res.get(p_) and self.roads.intersects(dict(self.parcels)[p_]) for p_ in pids if p_ not in res_p)
            street = len(res_p) == 1 and (dr < 5.0 or (lane and dr < 14.0))
            if street:
                pids = res_p + [p_ for p_ in pids if p_ not in res_p]
                # limite côté rue : reculée dans la parcelle tant qu'elle mord sur la chaussée ou le trottoir
                par = dict(self.parcels)[pids[0]]
                inw = nrm_ if par.contains(Point(mid0 + nrm_ * 1.0)) else -nrm_
                for push in (0.0, 0.4, 0.8, 1.2, 1.6, 2.0, 2.5, 3.0):
                    seg = LineString([a + inw * push, b + inw * push])
                    if not hard.intersects(seg.buffer(0.35)):
                        break
                else:
                    # limite qui longe un trottoir de biais : on garde la plus longue partie dégagée (reculée d'1,2 m)
                    seg = LineString([a + inw * 1.2, b + inw * 1.2]).difference(hard.buffer(0.35))
                    parts = [g for g in getattr(seg, "geoms", [seg]) if g.geom_type == "LineString" and g.length > 1.0]
                    if not parts:
                        continue
                    seg = max(parts, key=lambda g: g.length)
                a, b = np.array(seg.coords[0]), np.array(seg.coords[-1])
                L = float(np.linalg.norm(b - a))
            n = max(1, int(round(L / 2.5)))
            raw = []
            for k in range(n):
                p0 = a + (b - a) * k / n; p1 = a + (b - a) * (k + 1) / n
                mid = (p0 + p1) / 2
                if not zone.contains(Point(mid)) or center.in_area(*mid):
                    raw.append(None); continue
                segk = LineString([p0, p1])
                if hard.intersects(segk.buffer(0.2)):
                    raw.append(None); continue
                if any(bd.intersects(segk.buffer(0.15)) for bd in self._near_b(segk)):
                    raw.append(None); continue      # mur de la maison en limite
                best, boff = 0.0, 0.0
                for off in (-2.0, -1.5, -1.0, -0.5, 0.0, 0.5, 1.0, 1.5, 2.0):
                    samples = [tuple(mid + d * t + nrm_ * (off + o)) for t in np.linspace(-1.0, 1.0, 5) for o in (-0.4, 0.0, 0.4)]
                    f_ = self.frac(veg, samples) - 0.02 * abs(off)
                    if f_ > best:
                        best, boff = f_, off
                samples = [tuple(mid + d * t + nrm_ * o) for t in np.linspace(-1.0, 1.0, 5) for o in (-0.4, 0.0, 0.4)]
                raw.append(dict(p0=p0, p1=p1, hed=best, off=boff, dark=self.frac(self.dark, samples) > 0.45))
            ok = [r for r in raw if r]
            if not ok:
                continue
            # un seul type pour toute la limite : haie si la majorité des morceaux est verte
            hedge = np.mean([r["hed"] > 0.3 for r in ok]) >= 0.5
            kind = "hedge" if hedge else ("front" if street else "mesh")
            offs = [r["off"] for r in ok if r["hed"] > 0.3]
            off = float(np.median(offs)) if (hedge and offs) else 0.0
            if hedge:
                # la haie décalée ne doit ni mordre sur le trottoir ni sortir de la parcelle de plus de 0,5 m
                for cand in (off, off * 0.5, 0.0):
                    lnh = LineString([a + nrm_ * cand, b + nrm_ * cand])
                    if not hard.intersects(lnh.buffer(0.55)):
                        off = cand; break
            dark = np.mean([r["dark"] for r in ok]) > 0.5
            # trous isolés d'un morceau (arbre, poteau détecté) comblés : la clôture reste continue
            # trous de 1 ou 2 morceaux entre deux tronçons : comblés tant qu'aucune maison ni chaussée ne s'y trouve
            for gap in (1, 2):
                for k in range(1, len(raw) - gap):
                    if raw[k - 1] and raw[k + gap] if k + gap < len(raw) else False:
                        if all(raw[k + g_] is None for g_ in range(gap)):
                            for g_ in range(gap):
                                kk = k + g_
                                p0 = a + (b - a) * kk / n; p1 = a + (b - a) * (kk + 1) / n
                                sg = LineString([p0, p1])
                                if not hard.intersects(sg.buffer(0.2)) and not any(bd.intersects(sg.buffer(0.15)) for bd in self._near_b(sg)):
                                    raw[kk] = dict(p0=p0, p1=p1)
            for r in raw:
                if r:
                    self.pieces.append(dict(a=tuple(r["p0"]), b=tuple(r["p1"]), kind=kind, pids=pids, street=street,
                                            dark=bool(dark), off=off, nrm=tuple(nrm_), edge=ei))

    def parcel_at(self, x, z):
        best = None
        for pid, p in self.parcels:
            d = p.distance(Point(x, z))
            if best is None or d < best[0]:
                best = (d, pid)
        return best[1] if best else None

    def hedge_lines(self):
        return [LineString([p["a"], p["b"]]) for p in self.pieces if p["kind"] == "hedge"]

    def hedge_polylines(self):
        """Haies continues : squelette des bandes de végétation étroites de la photo, dans les jardins.
        Renvoie [(points [(x, z)], largeur, sombre)]."""
        from skimage.morphology import skeletonize
        from shapely import vectorized
        m = self.hedgem.copy()
        H_, W_ = m.shape
        xs = self.v.x0 + (np.arange(W_) + 0.5) * self.c; zs = self.v.z0 + (np.arange(H_) + 0.5) * self.c
        x0, z0, x1, z1 = FENCE_ZONE
        i0, i1 = np.searchsorted(xs, x0), np.searchsorted(xs, x1); j0, j1 = np.searchsorted(zs, z0), np.searchsorted(zs, z1)
        sub = m[j0:j1, i0:i1]
        X, Z = np.meshgrid(xs[i0:i1], zs[j0:j1])
        homes = unary_union([p for pid, p in self.parcels if self.res.get(pid)]).buffer(2.0)
        forbid = self.roads.buffer(0.4)
        if self.buildings:
            forbid = forbid.union(unary_union(self.buildings).buffer(0.4))
        sub &= vectorized.contains(homes, X, Z) & ~vectorized.contains(forbid, X, Z)
        sub = ndi.binary_closing(sub, iterations=2)       # raccorde les trous de 1 m dans les haies
        sk = skeletonize(sub)
        hd = self.hdist[j0:j1, i0:i1]
        dk = self.dark[j0:j1, i0:i1]
        nb = [(-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)]
        pts = set(zip(*np.nonzero(sk)))
        deg = {p: sum((p[0] + a, p[1] + b) in pts for a, b in nb) for p in pts}
        seen_edges = set()
        out = []

        def walk(start, nxt):
            path = [start, nxt]
            seen_edges.add((start, nxt)); seen_edges.add((nxt, start))
            prev, cur = start, nxt
            while deg[cur] == 2:
                cand = [(cur[0] + a, cur[1] + b) for a, b in nb if (cur[0] + a, cur[1] + b) in pts and (cur[0] + a, cur[1] + b) != prev]
                cand = [c for c in cand if (cur, c) not in seen_edges]
                if not cand:
                    break
                prev, cur = cur, cand[0]
                seen_edges.add((prev, cur)); seen_edges.add((cur, prev))
                path.append(cur)
            return path

        starts = [p for p in pts if deg[p] != 2] + list(pts)
        for s in starts:
            for a, b in nb:
                n_ = (s[0] + a, s[1] + b)
                if n_ in pts and (s, n_) not in seen_edges:
                    path = walk(s, n_)
                    if len(path) < 4:
                        continue
                    coords = [(xs[i0 + i], zs[j0 + j]) for j, i in path]
                    ln = LineString(coords).simplify(0.5)
                    if ln.length < 2.0:
                        continue
                    w = float(np.clip(2.0 * np.median([hd[j, i] for j, i in path]) + 0.3, 0.7, 1.7))
                    dark = float(np.mean([dk[j, i] for j, i in path])) > 0.4
                    out.append((list(ln.coords), w, dark))
        return out

    def hedge_boxes(self):
        """Tronçons de haie taillée d'après la photo : (centre, axe, longueur, largeur, sombre)."""
        out = []
        m = self.hedgem
        x0, z0, x1, z1 = FENCE_ZONE
        zone = zone_poly()
        bunion = unary_union(self.buildings).buffer(0.4) if self.buildings else None
        roads = self.roads.buffer(0.3)
        homes = unary_union([p for pid, p in self.parcels if self.res.get(pid)]).buffer(2.0)
        from shapely.prepared import prep
        homes = prep(homes)
        for cz in np.arange(z0, z1, 2.0):
            for cx in np.arange(x0, x1, 2.0):
                j0, i0 = self._ij(cx - 1.5, cz - 1.5); j1, i1 = self._ij(cx + 1.5, cz + 1.5)
                if j0 < 0 or i0 < 0 or j1 >= m.shape[0] or i1 >= m.shape[1]:
                    continue
                w = m[j0:j1, i0:i1]
                js, is_ = np.nonzero(w)
                if len(js) * self.c * self.c < 1.4:
                    continue
                pts = np.stack([self.v.x0 + (i0 + is_ + 0.5) * self.c, self.v.z0 + (j0 + js + 0.5) * self.c], axis=1)
                c = pts.mean(axis=0)
                # ne garder que la cellule qui contient le centre (pas de doublons)
                if not (cx - 1.0 <= c[0] < cx + 1.0 and cz - 1.0 <= c[1] < cz + 1.0):
                    continue
                if not homes.contains(Point(c)) or roads.contains(Point(c)) or (bunion is not None and bunion.contains(Point(c))):
                    continue
                cov = np.cov((pts - c).T) if len(pts) > 2 else np.eye(2)
                ev, evec = np.linalg.eigh(cov)
                ax = evec[:, 1]
                elong = math.sqrt(max(ev[1], 1e-6) / max(ev[0], 1e-6))
                width = float(np.clip(2.0 * np.median(self.hdist[j0:j1, i0:i1][w]) + 0.3, 0.7, 1.6))
                length = 2.6 if elong > 1.6 else 1.8
                jj, ii = self._ij(*c)
                dark = bool(self.dark[max(0, jj - 2):jj + 3, max(0, ii - 2):ii + 3].mean() > 0.45)
                out.append((tuple(c), tuple(ax), length, width, dark))
        return out

    # ---------------------------------------------------------------- portails
    def gates(self):
        """Une entrée par parcelle habitée : sur la façade côté rue, là où gravier/béton/enrobé touche la limite."""
        out = []
        paved = self.gravel | self.concrete | self.asphalt
        front = {}
        for p in self.pieces:
            if p["street"]:
                front.setdefault(p["pids"][0], []).append(p)
        for pid, ps in front.items():
            if not self.res.get(pid):
                continue
            par = dict(self.parcels)[pid]
            best = None
            for p in ps:
                a, b = np.array(p["a"]), np.array(p["b"])
                mid = (a + b) / 2; d = (b - a) / np.linalg.norm(b - a); nn = np.array([-d[1], d[0]])
                if not par.contains(Point(mid + nn * 1.0)):
                    nn = -nn
                pts = [tuple(mid + d * t + nn * o) for t in np.linspace(-1.5, 1.5, 7) for o in np.linspace(0.5, 4.5, 6)]
                sc = self.frac(paved, pts) + 0.001 * min(math.dist(mid, ps[0]["a"]), math.dist(mid, ps[-1]["b"]))
                if best is None or sc > best[0]:
                    best = (sc, mid, d, nn, p)
            front_len = sum(math.dist(p["a"], p["b"]) for p in ps)
            if best and (best[0] > 0.35 or front_len >= 5.0):
                out.append(dict(pid=pid, mid=best[1], d=best[2], inward=best[3], piece=best[4]))
        return out


# ---------------------------------------------------------------------------------- maillages
def _box(m, obox, c, ax, size, col, mat, extra=0.0):
    obox(m, c, ax, size, col, mat, extra)


CAR_COLS = [(0.72, 0.73, 0.74), (0.30, 0.31, 0.33), (0.55, 0.56, 0.58), (0.85, 0.85, 0.83), (0.62, 0.10, 0.08), (0.15, 0.22, 0.40)]


def build(q, Mesh, obox, quad3, add, add_coll, parked_car=None):
    """Clôtures, haies, portails et sols du quartier."""
    rnd = random.Random(12)
    stats = {}
    q.paved_rects = []        # surfaces en dur (pour le masque de l'herbe 3D)
    q.paved_polys = []

    def count(k, n=1):
        stats[k] = stats.get(k, 0) + n

    home12 = q.parcel_at(*ADDR12)
    # clôtures côté rue relevées maison par maison sur Street View (clotures_bourg.json, clé = bâtiment BD TOPO)
    survey = {}
    sp = os.path.join(HERE, "clotures_bourg.json")
    if os.path.exists(sp):
        from prepare_decor import load, loc, polys
        sv = json.load(open(sp))
        for f in load("batiment"):
            a_ = sv.get(f["properties"]["cleabs"])
            if not a_:
                continue
            for bp in polys(loc(f["geometry"])):
                pid = q.parcel_at(*bp.representative_point().coords[0])
                if pid is not None:
                    survey[pid] = a_
    # rue du Balcon : relevé parcelle par parcelle (rue_balcon.CLOTURES), prioritaire ; parcelles bordant la rue non
    # relevées : style dominant du lotissement (haie de laurier sur muret blanc) plutôt qu'un tirage au hasard
    import rue_balcon
    for pid, p_ in q.parcels:
        if pid in rue_balcon.CLOTURES:
            survey[pid] = dict(rue_balcon.CLOTURES[pid])
        elif q.res.get(pid) and rue_balcon.axis().distance(p_) < rue_balcon.WIDTH / 2 + 6.0:
            survey[pid] = dict(rue_balcon.DEFAULT)
    count("parcelles relevées sur Street View", len(survey))
    WALLC = {"creme": CREAM, "gris": CONCRETE, "blanc": WHITE, "rose": (0.86, 0.68, 0.60), "pierre": None}
    GRILC = {"blanc": WHITE, "noir": IRON, "vert": (0.10, 0.30, 0.18), "gris": (0.30, 0.31, 0.32), "bois": WOOD,
             "beige": (0.80, 0.74, 0.62), "brande": (0.55, 0.45, 0.30), "grillage": GREEN_MESH}

    def style_of(pid):
        """Clôture côté rue : relevé Street View de la maison si disponible, sinon répartition de la rue du Balcon."""
        if pid in survey:
            return "sv"
        h = sum(ord(ch) * (k + 1) for k, ch in enumerate(str(pid))) % 20
        return "lisses" if h < 10 else ("bois" if h < 14 else ("rigide" if h < 18 else "fer"))

    def gate_of(pid):
        if pid == home12:
            return "plein_blanc"
        if pid in survey and survey[pid].get("portail"):
            g = survey[pid]["portail"]
            return {"plein_gris": "plein_gris", "ajoure_gris": "plein_gris", "lisses_blanc": "barreaux_blanc"}.get(g, g)
        h = sum(ord(ch) * (k + 2) for k, ch in enumerate(str(pid))) % 20
        return "plein_blanc" if h < 9 else ("fer" if h < 15 else ("bois" if h < 18 else "barreaux_blanc"))

    gates = q.gates()
    gate_zone = {}
    for g in gates:
        gate_zone.setdefault(g["pid"], []).append(g)

    def in_gate(pid_list, mid):
        for pid in pid_list:
            for g in gate_zone.get(pid, []):
                if abs(np.dot(np.subtract(mid, g["mid"]), g["d"])) < 2.0 and np.linalg.norm(np.subtract(mid, g["mid"])) < 2.6:
                    return True
        return False

    def front_sv(m, a, b, d, L, mid, y, sv, p):
        """Clôture côté rue d'après le relevé : muret (couleur), grille / panneaux rigides / occultants / lisses."""
        f = sv["front"]
        nn = np.array([-d[1], d[0]])
        wall = WALLC.get(sv.get("mur", ""), CREAM)
        stone = sv.get("mur") == "pierre"
        gcol = GRILC.get(sv.get("grille", ""), None)
        h_m = {"muret": 0.9, "muret_grille": 0.75, "muret_rigide": 0.6, "mur": 1.8, "occult": 0.5, "lisses": 0.6,
               "bois": 0.6, "grillage": 0.0, "piquets": 0.0}.get(f, 0.6)
        if f in ("grillage", "piquets") and sv.get("mur"):
            h_m = 0.3
        if f == "lisses" and not sv.get("mur"):
            h_m = 0.0
        if sv.get("hmur") is not None and (sv.get("mur") or h_m > 0):
            h_m = float(sv["hmur"])
        if h_m > 0:
            if stone:
                obox(m, (mid[0], y + h_m / 2 - 0.2, mid[1]), d, (L, h_m + 0.4, 0.3), STONE, M_RUBBLE)
            else:
                obox(m, (mid[0], y + h_m / 2 - 0.2, mid[1]), d, (L, h_m + 0.4, 0.2), wall or CREAM, M_CREPI)
            obox(m, (mid[0], y + h_m - 0.17, mid[1]), d, (L + 0.04, 0.05, 0.27), (0.78, 0.76, 0.72), M_CURB)
        top = y + h_m - 0.15
        p0 = np.array([a[0], top, a[1]]); p1 = np.array([b[0], top, b[1]])
        def panel(hh, col, pat, mat=M_MESH):
            quad3(m, p0, p1, p1 + [0, hh, 0], p0 + [0, hh, 0], col, mat, [(0, 0), (L, 0), (L, hh), (0, hh)], pat,
                  n=(nn[0], 0, nn[1]))
        if f == "muret_grille":
            panel(0.9, gcol or IRON, 1.0)
            obox(m, (mid[0], top + 0.92, mid[1]), d, (L, 0.04, 0.04), gcol or IRON, M_STEEL)
            for t in np.arange(0.0, L + 0.01, 2.5):          # piliers enduits
                pp = a + d * min(t, L)
                obox(m, (pp[0], q.H(*pp) + 0.6, pp[1]), d, (0.35, 1.7, 0.35), wall or CREAM, M_CREPI)
                obox(m, (pp[0], q.H(*pp) + 1.48, pp[1]), d, (0.42, 0.06, 0.42), (0.80, 0.78, 0.74), M_CURB)
        elif f in ("muret_rigide", "grillage"):
            panel(1.2 if f == "muret_rigide" else 1.5, gcol or GREEN_MESH, 0.0)
            for t in np.arange(0.0, L + 0.01, 2.5):
                pp = a + d * min(t, L)
                obox(m, (pp[0], top + 0.65, pp[1]), d, (0.05, 1.3, 0.05), gcol or GREEN_MESH, M_STEEL)
        elif f == "piquets":
            # grillage à moutons tendu sur piquets de bois (prés, potagers, friches)
            panel(1.1, (0.55, 0.56, 0.54), 0.0)
            for t in np.arange(0.0, L + 0.01, 2.5):
                pp = a + d * min(t, L)
                obox(m, (pp[0], top + 0.6, pp[1]), d, (0.09, 1.3, 0.09), (0.45, 0.36, 0.26), M_PLAIN)
        elif f == "muret" and gcol is not None:
            panel(0.9, gcol, 1.0)
            obox(m, (mid[0], top + 0.92, mid[1]), d, (L, 0.04, 0.04), gcol, M_STEEL)
        elif f == "occult":
            # panneaux occultants pleins (PVC, composite, brande) entre poteaux
            hh = 1.5
            col = gcol or (0.30, 0.31, 0.32)
            quad3(m, p0, p1, p1 + [0, hh, 0], p0 + [0, hh, 0], col, M_PLAIN, n=(nn[0], 0, nn[1]))
            quad3(m, p1, p0, p0 + [0, hh, 0], p1 + [0, hh, 0], col, M_PLAIN, n=(-nn[0], 0, -nn[1]))
            for t in np.arange(0.0, L + 0.01, 1.8):
                pp = a + d * min(t, L)
                obox(m, (pp[0], top + hh / 2, pp[1]), d, (0.08, hh + 0.05, 0.08), (0.22, 0.23, 0.24), M_STEEL)
        elif f == "lisses":
            col = gcol or WHITE
            for k in range(3):
                obox(m, (mid[0], top + 0.25 + k * 0.32, mid[1]), d, (L, 0.14, 0.04), col, M_PLAIN)
            for t in np.arange(0.0, L + 0.01, 2.0):
                pp = a + d * min(t, L)
                obox(m, (pp[0], top + 0.6, pp[1]), d, (0.1, 1.2, 0.1), col, M_PLAIN)
        elif f == "bois":
            for k in range(3):
                obox(m, (mid[0], top + 0.3 + k * 0.3, mid[1]), d, (L, 0.15, 0.04), WOOD, M_PLAIN)
            for t in np.arange(0.0, L + 0.01, 2.0):
                pp = a + d * min(t, L)
                obox(m, (pp[0], top + 0.6, pp[1]), d, (0.12, 1.2, 0.12), WOOD, M_PLAIN)
        elif f == "mur":
            obox(m, (mid[0], y + 1.75, mid[1]), d, (L + 0.06, 0.08, 0.3), (0.62, 0.42, 0.32), M_TILES + 0.2)

    hedge_segs = []
    parcels_d = dict(q.parcels)
    # façades relevées sans haie (muret, grille, clôture, ouverte) : les « haies » vues d'avion le long de ces façades
    # sont en réalité des arbustes ou des arbres derrière la clôture ; on ne les trace pas
    no_hedge = []
    for p in q.pieces:
        sv_ = survey.get(p["pids"][0]) if p["street"] else None
        if sv_ and sv_["front"] not in ("haieT", "haieL", "haieP"):
            no_hedge.append(LineString([p["a"], p["b"]]).buffer(3.0))
    no_hedge = unary_union(no_hedge) if no_hedge else None
    fence_log = []

    def flog(p, gate=False):
        a_, b_ = np.array(p["a"]), np.array(p["b"])
        dd = (b_ - a_) / max(np.linalg.norm(b_ - a_), 1e-9)
        if dd[0] < 0 or (dd[0] == 0 and dd[1] < 0):
            dd = -dd
        t0, t1 = sorted((float(np.dot(a_, dd)), float(np.dot(b_, dd))))
        fence_log.append(dict(line=str(p.get("edge")), t0=t0, t1=t1, b=[round(float(v), 1) for v in b_], gate=gate))

    # morceaux contigus d'une même limite fusionnés en un seul tronçon : haies et murets d'un seul tenant,
    # coupés seulement au portail
    runs = []
    for p in q.pieces:
        mid_p = (np.array(p["a"]) + np.array(p["b"])) / 2
        if p["street"] and in_gate(p["pids"], mid_p):
            flog(p, gate=True)
            runs.append(None)
            continue
        flog(p)
        r_ = runs[-1] if runs else None
        if r_ is not None and r_["edge"] == p["edge"] and math.dist(r_["b"], p["a"]) < 0.05 \
                and abs(q.H(*r_["a"]) - q.H(*p["b"])) < 0.4:
            r_["b"] = p["b"]
        else:
            runs.append(dict(p))
    for p in runs:
        if p is None:
            continue
        a, b = np.array(p["a"]), np.array(p["b"])
        L = float(np.linalg.norm(b - a)); d = (b - a) / L
        mid = (a + b) / 2
        ya, yb = q.H(*a), q.H(*b)
        y = min(ya, yb)
        m = Mesh()
        sv0 = survey.get(p["pids"][0]) if p["street"] else None
        if sv0 and p["kind"] == "hedge" and sv0["front"] not in ("haieT", "haieL", "haieP", "rien"):
            p = dict(p, kind="front")
        if sv0 and sv0["front"] == "rien":
            continue                                     # façade ouverte d'après Street View
        if p["kind"] == "hedge":
            # haie continue le long de la limite, à la position réelle mesurée sur la photo
            o = np.array(p["nrm"]) * p["off"]
            a_, b_ = a + o, b + o
            mid_ = (a_ + b_) / 2
            import vegetation
            hk = vegetation.hedge_kind(*mid)            # essence relevée sur Street View à proximité
            thuja = (hk == "T") if hk else (p["dark"] or (sum(map(ord, str(p["pids"]))) % 10) < 3)
            sv_ = survey.get(p["pids"][0]) if p["street"] else None
            if sv_ and sv_["front"] in ("haieT", "haieL", "haieP"):
                thuja = sv_["front"] == "haieT"
            elif sv_ and sv_["front"] != "rien":
                p = dict(p, kind="front")                # relevé : pas de haie sur cette façade
            elif sv_:
                continue                                 # façade ouverte (pelouse, cour)
            col = tuple(np.clip(np.array(THUJA if thuja else LAUREL) * (0.95 + 0.1 * ((sum(map(ord, str(p["pids"]))) % 7) / 7)), 0, 1))
            h = 2.0 if thuja else 1.7
            w = 1.0 if thuja else 0.9
            y2 = min(q.H(*a_), q.H(*b_))
            if p["street"]:
                # muret enduit à la limite, haie plantée juste derrière (cas le plus fréquent dans la rue)
                par = parcels_d[p["pids"][0]]
                inw = np.array([-d[1], d[0]])
                if not par.contains(Point(mid + inw * 1.0)):
                    inw = -inw
                mcol = CREAM if (sum(map(ord, str(p["pids"]))) % 3) else CONCRETE
                ym = min(q.H(*a), q.H(*b))
                if sv_ and sv_.get("mur"):
                    mcol = WALLC.get(sv_["mur"]) or CREAM
                if not sv_ or sv_.get("mur"):
                    mm_ = M_RUBBLE if sv_ and sv_.get("mur") == "pierre" else M_CREPI
                    hm = float(sv_.get("hmur", 0.6)) if sv_ else 0.6
                    obox(m, (mid[0], ym + (hm - 0.3) / 2, mid[1]), d, (L + 0.02, hm + 0.3, 0.2), STONE if mm_ == M_RUBBLE else mcol, mm_)
                    obox(m, (mid[0], ym + hm + 0.02, mid[1]), d, (L + 0.04, 0.05, 0.26), (0.78, 0.76, 0.72), M_CURB)
                    if sv_ and sv_.get("grille") == "bois":
                        # lisses en bois brun posées sur le muret, devant la haie (lotissement du Balcon)
                        for k_ in range(2):
                            obox(m, (mid[0], ym + hm + 0.3 + k_ * 0.32, mid[1]), d, (L, 0.13, 0.04), WOOD, M_PLAIN)
                        for t_ in np.arange(0.0, L + 0.01, 2.0):
                            pp_ = a + d * min(t_, L)
                            obox(m, (pp_[0], ym + hm + 0.4, pp_[1]), d, (0.09, 0.8, 0.09), WOOD, M_PLAIN)
                if sv_ and sv_.get("grille") == "grillage":
                    p0_ = np.array([a[0], ym, a[1]]); p1_ = np.array([b[0], ym, b[1]])
                    quad3(m, p0_, p1_, p1_ + [0, 1.5, 0], p0_ + [0, 1.5, 0], GREEN_MESH, M_MESH, [(0, 0), (L, 0), (L, 1.5), (0, 1.5)], 0.0)
                if np.dot(o, inw) < 0.45:
                    o = inw * 0.6
                    a_, b_ = a + o, b + o
                    mid_ = (a_ + b_) / 2
                if p["pids"][0] == home12:
                    col, h, w = THUJA, 2.1, 1.0         # thuyas taillés à ~2 m (Street View 2014)
            obox(m, (mid_[0], y2 + h / 2 - 0.25, mid_[1]), d, (L + 0.35, h + 0.5, w), col, M_HEDGE + (0.2 if thuja else 0.7))
            hedge_segs.append(LineString([a_, b_]))
            count("haies sur limites (m)", L)
            add(mid_[0], mid_[1], m, False)
            nn = np.array([-d[1], d[0]]) * w / 2
            add_coll(np.array([a_ - nn, b_ - nn, b_ + nn, a_ + nn]))
            continue
        elif p["kind"] == "front":
            st = style_of(p["pids"][0])
            if st == "sv" and sv0["front"] in ("haieT", "haieL", "haieP"):
                # haie relevée sur une limite que la photo aérienne ne montre pas verte : haie sur muret
                thuja = sv0["front"] == "haieT"
                mcol = WALLC.get(sv0.get("mur", ""), CREAM) or CREAM
                if sv0.get("mur"):
                    hm = float(sv0.get("hmur", 0.6))
                    obox(m, (mid[0], y + (hm - 0.3) / 2, mid[1]), d, (L + 0.02, hm + 0.3, 0.2), mcol, M_CREPI)
                    obox(m, (mid[0], y + hm + 0.02, mid[1]), d, (L + 0.04, 0.05, 0.26), (0.78, 0.76, 0.72), M_CURB)
                    if sv0.get("grille") == "bois":
                        for k_ in range(2):
                            obox(m, (mid[0], y + hm + 0.3 + k_ * 0.32, mid[1]), d, (L, 0.13, 0.04), WOOD, M_PLAIN)
                        for t_ in np.arange(0.0, L + 0.01, 2.0):
                            pp_ = a + d * min(t_, L)
                            obox(m, (pp_[0], y + hm + 0.4, pp_[1]), d, (0.09, 0.8, 0.09), WOOD, M_PLAIN)
                nn_ = np.array([-d[1], d[0]])
                par = parcels_d[p["pids"][0]]
                if not par.contains(Point(mid + nn_ * 1.0)):
                    nn_ = -nn_
                c_ = mid + nn_ * 0.6
                h, w = (2.0, 1.0) if thuja else (1.7, 0.9)
                col = THUJA if thuja else (LAUREL if sv0["front"] == "haieL" else (0.45, 0.25, 0.15))
                obox(m, (c_[0], y + h / 2 - 0.25, c_[1]), d, (L + 0.35, h + 0.5, w), col, M_HEDGE + (0.2 if thuja else 0.7))
                count("haies relevées sur Street View (m)", L)
            elif st == "sv":
                front_sv(m, a, b, d, L, mid, y, sv0, p)
                count("clôtures relevées sur Street View (m)", L)
            elif st == "lisses":
                # muret blanc + lisses horizontales entre piliers (cf. 8 rue du Balcon)
                obox(m, (mid[0], y + 0.15, mid[1]), d, (L, 0.9, 0.2), WHITE, M_CREPI)
                for t in (0.0, L):
                    pp = a + d * t
                    obox(m, (pp[0], q.H(*pp) + 0.65, pp[1]), d, (0.24, 1.7, 0.24), WHITE, M_CREPI)
                    obox(m, (pp[0], q.H(*pp) + 1.52, pp[1]), d, (0.3, 0.06, 0.3), (0.86, 0.85, 0.82), M_CURB)
                nn = np.array([-d[1], d[0]])
                p0 = np.array([a[0], y + 0.6, a[1]]); p1 = np.array([b[0], y + 0.6, b[1]])
                quad3(m, p0, p1, p1 + [0, 0.85, 0], p0 + [0, 0.85, 0], WHITE, M_MESH, [(0, 0), (L, 0), (L, 0.85), (0, 0.85)], 2.0,
                      n=(nn[0], 0, nn[1]))
                count("clôtures blanches à lisses (m)", L)
            elif st == "bois":
                # muret béton + lisses en bois brun (n° 9)
                obox(m, (mid[0], y + 0.15, mid[1]), d, (L, 0.9, 0.2), CONCRETE, M_CREPI)
                obox(m, (mid[0], y + 0.62, mid[1]), d, (L + 0.02, 0.05, 0.26), (0.78, 0.76, 0.72), M_CURB)
                for k in range(3):
                    obox(m, (mid[0], y + 0.85 + k * 0.28, mid[1]), d, (L, 0.16, 0.04), WOOD, M_PLAIN)
                obox(m, (a[0], y + 1.05, a[1]), d, (0.1, 0.9, 0.1), WOOD, M_PLAIN)
                count("murets + lisses bois (m)", L)
            elif st == "fer":
                # muret en pierres sèches + grille en fer forgé noire
                obox(m, (mid[0], y + 0.25, mid[1]), d, (L, 1.1, 0.35), STONE, M_RUBBLE)
                nn = np.array([-d[1], d[0]])
                p0 = np.array([a[0], y + 0.8, a[1]]); p1 = np.array([b[0], y + 0.8, b[1]])
                quad3(m, p0, p1, p1 + [0, 0.9, 0], p0 + [0, 0.9, 0], IRON, M_MESH, [(0, 0), (L, 0), (L, 0.9), (0, 0.9)], 1.0,
                      n=(nn[0], 0, nn[1]))
                obox(m, (mid[0], y + 1.68, mid[1]), d, (L, 0.04, 0.04), IRON, M_STEEL)
                count("murets en pierre + grilles (m)", L)
            else:
                # muret enduit + panneau rigide vert
                obox(m, (mid[0], y + 0.2, mid[1]), d, (L, 1.0, 0.22), (0.86, 0.80, 0.68), M_CREPI)
                obox(m, (mid[0], y + 0.73, mid[1]), d, (L + 0.02, 0.06, 0.3), (0.66, 0.65, 0.62), M_CURB)
                nn = np.array([-d[1], d[0]])
                p0 = np.array([a[0], y + 0.76, a[1]]); p1 = np.array([b[0], y + 0.76, b[1]])
                quad3(m, p0, p1, p1 + [0, 1.0, 0], p0 + [0, 1.0, 0], GREEN_MESH, M_MESH, [(0, 0), (L, 0), (L, 1.0), (0, 1.0)], 0.0,
                      n=(nn[0], 0, nn[1]))
                obox(m, (a[0], y + 1.0, a[1]), d, (0.06, 1.0, 0.06), GREEN_MESH, M_STEEL)
                count("murets + grillage rigide (m)", L)
        else:
            # grillage souple vert entre jardins
            nn = np.array([-d[1], d[0]])
            p0 = np.array([a[0], y, a[1]]); p1 = np.array([b[0], y, b[1]])
            quad3(m, p0 - [0, 0.1, 0], p1 - [0, 0.1, 0], p1 + [0, 1.4, 0], p0 + [0, 1.4, 0], GREEN_MESH, M_MESH,
                  [(0, -0.1), (L, -0.1), (L, 1.4), (0, 1.4)], 0.0, n=(nn[0], 0, nn[1]))
            obox(m, (a[0], y + 0.7, a[1]), d, (0.05, 1.6, 0.05), GREEN_MESH, M_STEEL)
            count("grillages (m)", L)
        add(mid[0], mid[1], m, False)
        nn = np.array([-d[1], d[0]]) * (0.45 if p["kind"] == "hedge" else 0.12)
        add_coll(np.array([a - nn, b - nn, b + nn, a + nn]))

    json.dump(dict(segments=fence_log), open(os.path.join(DATA, "fences.json"), "w"))
    # haies taillées continues, tracées d'après la photo
    tiles = {}
    hs_tree = STRtree(hedge_segs) if hedge_segs else None
    import shapely as _sh
    hard_b = q.hard.buffer(0.9)
    _sh.prepare(hard_b)
    for coords0, w, dark in q.hedge_polylines():
      # haie tracée d'après la photo : coupée là où elle mordrait sur la chaussée ou un trottoir
      lnc = LineString(coords0)
      g0 = lnc.difference(_sh.clip_by_rect(hard_b, *lnc.buffer(3).bounds)) if hard_b.intersects(lnc) else lnc
      for part in (getattr(g0, "geoms", [g0]) if not g0.is_empty else []):
        if part.geom_type != "LineString" or part.length < 2.0:
            continue
        coords = list(part.coords)
        ln = LineString(coords)
        if no_hedge is not None and ln.intersection(no_hedge).length > 0.4 * ln.length:
            continue
        if hs_tree is not None:
            # déjà couverte par une haie posée sur une limite de parcelle ?
            near = [hedge_segs[k] for k in hs_tree.query(ln.buffer(2.5))]
            if near and ln.buffer(2.5).intersection(unary_union(near)).length > 0.5 * ln.length:
                continue
        import vegetation
        hk = vegetation.hedge_kind(*coords[len(coords) // 2])
        thuja = (hk == "T") if hk else (dark or rnd.random() < 0.3)
        col = tuple(np.clip(np.array(THUJA if thuja else LAUREL) * rnd.uniform(0.9, 1.1), 0, 1))
        h = rnd.uniform(1.8, 2.2) if thuja else rnd.uniform(1.5, 1.9)
        mat = M_HEDGE + (rnd.uniform(0.0, 0.45) if thuja else rnd.uniform(0.5, 0.95))   # graine : < 0,48 thuya
        P = np.array(coords)
        # prolonge un peu les extrémités pour fermer les angles
        if len(P) >= 2:
            P[0] = P[0] - (P[1] - P[0]) / max(np.linalg.norm(P[1] - P[0]), 1e-6) * 0.3
            P[-1] = P[-1] + (P[-1] - P[-2]) / max(np.linalg.norm(P[-1] - P[-2]), 1e-6) * 0.3
        n = len(P)
        T = np.zeros_like(P)
        T[1:-1] = P[2:] - P[:-2]; T[0] = P[1] - P[0]; T[-1] = P[-1] - P[-2]
        T /= np.linalg.norm(T, axis=1, keepdims=True) + 1e-9
        N = np.stack([-T[:, 1], T[:, 0]], axis=1)
        ys = [q.H(*p) for p in P]
        key = (int(P[n // 2][0] // 48), int(P[n // 2][1] // 48))
        mm = tiles.setdefault(key, Mesh())
        L_ = [P[k] + N[k] * w / 2 for k in range(n)]; R_ = [P[k] - N[k] * w / 2 for k in range(n)]
        for k in range(n - 1):
            for side, S, sg in ((0, L_, 1), (1, R_, -1)):
                a3 = (S[k][0], ys[k] - 0.25, S[k][1]); b3 = (S[k + 1][0], ys[k + 1] - 0.25, S[k + 1][1])
                nn = (N[k][0] * sg, 0.0, N[k][1] * sg)
                ids = [mm.vert(p, nn, col, (0, 0), mat) for p in (a3, b3, (b3[0], ys[k + 1] + h, b3[2]), (a3[0], ys[k] + h, a3[2]))]
                mm.quad(*ids)
            # dessus légèrement bombé
            top = [(L_[k][0], ys[k] + h, L_[k][1]), (L_[k + 1][0], ys[k + 1] + h, L_[k + 1][1]),
                   (R_[k + 1][0], ys[k + 1] + h, R_[k + 1][1]), (R_[k][0], ys[k] + h, R_[k][1])]
            ids = [mm.vert(p, (0, 1, 0), col, (0, 0), mat) for p in top]
            mm.quad(*ids)
            a2, b2 = P[k], P[k + 1]
            nn2 = N[k] * w / 2
            add_coll(np.array([a2 - nn2, b2 - nn2, b2 + nn2, a2 + nn2]))
        for k, sg in ((0, -1), (n - 1, 1)):
            tt = (T[k][0] * sg, 0.0, T[k][1] * sg)
            ids = [mm.vert(p, tt, col, (0, 0), mat) for p in ((L_[k][0], ys[k] - 0.25, L_[k][1]), (R_[k][0], ys[k] - 0.25, R_[k][1]),
                                                                (R_[k][0], ys[k] + h, R_[k][1]), (L_[k][0], ys[k] + h, L_[k][1]))]
            mm.quad(*ids)
        count("haies hors limites (m)", float(LineString(coords).length))
    for (kx, kz), mm in tiles.items():
        add(kx * 48 + 24, kz * 48 + 24, mm, True)

    # portails et voitures dans les entrées
    for gi, g in enumerate(gates):
        mid, d, inw = np.array(g["mid"]), np.array(g["d"]), np.array(g["inward"])
        m = Mesh()
        y = q.H(*mid)
        kind = gate_of(g["pid"])
        stone = kind == "fer"
        for s in (-1, 1):
            pp = mid + d * s * 1.85
            yy = q.H(*pp)
            if stone:
                obox(m, (pp[0], yy + 0.75, pp[1]), d, (0.5, 1.9, 0.5), STONE, M_RUBBLE)
                obox(m, (pp[0], yy + 1.73, pp[1]), d, (0.6, 0.08, 0.6), (0.62, 0.60, 0.56), M_CURB)
            else:
                obox(m, (pp[0], yy + 0.7, pp[1]), d, (0.42, 1.8, 0.42), CREAM, M_CREPI)
                obox(m, (pp[0], yy + 1.63, pp[1]), d, (0.52, 0.08, 0.52), (0.82, 0.80, 0.76), M_CURB)
            c0 = mid + d * s * 0.02; c1 = mid + d * s * 1.63
            cm = (c0 + c1) / 2
            p0 = np.array([c0[0], y + 0.06, c0[1]]); p1 = np.array([c1[0], y + 0.06, c1[1]])
            if kind in ("plein_gris", "plein_rouge"):
                gc = (0.28, 0.29, 0.30) if kind == "plein_gris" else (0.55, 0.16, 0.14)
                quad3(m, p0, p1, p1 + [0, 1.5, 0], p0 + [0, 1.5, 0], gc, M_PLAIN, n=(inw[0], 0, inw[1]))
                quad3(m, p1, p0, p0 + [0, 1.5, 0], p1 + [0, 1.5, 0], gc, M_PLAIN, n=(-inw[0], 0, -inw[1]))
                for k in range(1, 5):
                    obox(m, (cm[0], y + 0.06 + k * 0.3, cm[1]), d, (1.61, 0.02, 0.07), tuple(c * 0.8 for c in gc), M_PLAIN)
            elif kind == "plein_blanc":
                # vantail plein en PVC blanc, haut légèrement cintré (12 rue du Balcon)
                top0, top1 = 1.45, 1.30
                quad3(m, p0, p1, p1 + [0, top1, 0], p0 + [0, top0, 0], WHITE, M_PLAIN, n=(inw[0], 0, inw[1]))
                for k in range(1, 6):
                    t = k / 6
                    pp2 = p0 + (p1 - p0) * t
                    hh = top0 + (top1 - top0) * t
                    obox(m, pp2 + np.array([0, hh / 2, 0]) - np.append(inw, 0)[[0, 2, 1]] * 0.0, d, (0.015, hh, 0.05), (0.84, 0.84, 0.82), M_PLAIN)
                obox(m, (cm[0], y + 0.7, cm[1]), d, (1.61, 0.04, 0.05), (0.86, 0.86, 0.84), M_PLAIN)
            else:
                col = {"fer": IRON, "bois": WOOD, "barreaux_blanc": WHITE}[kind]
                pat = 2.0 if kind == "bois" else 1.0
                quad3(m, p0, p1, p1 + [0, 1.42, 0], p0 + [0, 1.42, 0], col, M_MESH, [(0, 0), (1.61, 0), (1.61, 1.42), (0, 1.42)], pat,
                      n=(inw[0], 0, inw[1]))
                obox(m, (cm[0], y + 1.48, cm[1]), d, (1.61, 0.07, 0.05), col, M_STEEL)
                obox(m, (cm[0], y + 0.85, cm[1]), d, (1.61, 0.05, 0.04), col, M_STEEL)
        # boîte aux lettres sur le pilier côté rue
        pp = mid + d * 1.85 - inw * 0.29
        obox(m, (pp[0], q.H(*pp) + 1.1, pp[1]), d, (0.36, 0.42, 0.14), (0.85, 0.85, 0.82) if gi % 2 else (0.25, 0.27, 0.3), M_STEEL)
        add(mid[0], mid[1], m, False)
        a, b = mid - d * 2.05, mid + d * 2.05
        nn = inw * 0.15
        add_coll(np.array([a - nn, b - nn, b + nn, a + nn]))
        count("portails")
        # voiture garée dans l'entrée (une maison sur deux)
        if parked_car is not None and gi % 2 == 0:
            cpos = mid + inw * 5.0
            cm_, ring = parked_car(cpos[0], cpos[1], math.atan2(inw[1], inw[0]), CAR_COLS[gi % len(CAR_COLS)], 300 + gi)
            add(cpos[0], cpos[1], cm_, False)
            add_coll(np.array(ring))
            count("voitures dans les entrées")

    # caniveaux en béton le long de la chaussée (pas de trottoir dans le quartier ; ailleurs, les trottoirs les remplacent)
    rows = pickle.load(open(os.path.join(DATA, "road_rows.pkl"), "rb"))
    zone = zone_poly()
    for r in rows:
        if r["cls"] not in ("residential", "unclassified", "living_street", "tertiary") or len(r["P"]) < 2:
            continue
        if not zone.contains(Point(r["P"][len(r["P"]) // 2])):
            continue
        VX, VY, VZ = r["VX"], r["VY"], r["VZ"]
        hw = r["width"] / 2
        m = Mesh()
        if r.get("name") == rue_balcon.NAME:
            # rue du Balcon : caniveau central en béton (partie est), pas de caniveaux de rive (trottoir / accotements)
            if r["width"] < rue_balcon.WIDTH - 0.1:
                continue
            prev = None
            for k in range(len(VX)):
                if r["s"][k] > rue_balcon.GUTTER_END:
                    break
                c_ = np.array([VX[k, 1], VY[k, 1] + 0.02, VZ[k, 1]])
                e_ = np.array([VX[k, 2], VY[k, 2], VZ[k, 2]]) - np.array([VX[k, 0], VY[k, 0], VZ[k, 0]])
                e_ = e_ / max(np.linalg.norm(e_), 1e-6) * 0.22
                cur = (c_ - e_, c_ + e_)
                if prev is not None and r["s"][k] > 6.0:
                    ids = [m.vert(tuple(p_), (0, 1, 0), (0.52, 0.51, 0.49), (0, 0), M_PAVE) for p_ in (prev[0], cur[0], cur[1], prev[1])]
                    m.quad(*ids)
                prev = cur
            add(r["P"][len(r["P"]) // 2][0], r["P"][len(r["P"]) // 2][1], m, True, flat=True)
            count("caniveau central (m)", min(float(r["s"][-1]), rue_balcon.GUTTER_END))
            continue
        for col_ in (0, 2):
            prev = None
            for k in range(len(VX)):
                e = np.array([VX[k, col_], VY[k, col_] + 0.02, VZ[k, col_]])
                c_ = np.array([VX[k, 1], VY[k, 1] + 0.02, VZ[k, 1]])
                inner = e + (c_ - e) * (0.45 / max(hw, 0.5))
                if prev is not None:
                    ids = [m.vert(tuple(p_), (0, 1, 0), (0.74, 0.73, 0.70), (0, 0), M_PAVE) for p_ in (prev[0], e, inner, prev[1])]
                    m.quad(*ids)
                prev = (e, inner)
        add(r["P"][len(r["P"]) // 2][0], r["P"][len(r["P"]) // 2][1], m, True)
        count("caniveaux (m)", 2 * float(r["s"][-1]))

    # sols : gravier, béton, enrobé (cellules de 1 m regroupées par lignes)
    zone = fence_poly()
    res_parcels = [p for pid, p in q.parcels if q.res.get(pid)]
    allowed = unary_union(res_parcels).difference(unary_union(q.buildings).buffer(0.3)) if res_parcels else None
    if allowed is not None:
        from shapely import vectorized
        x0, z0, x1, z1 = FENCE_ZONE
        step = 1.0
        xs = np.arange(x0, x1, step) + step / 2; zs = np.arange(z0, z1, step) + step / 2
        X, Zg = np.meshgrid(xs, zs)
        ok = vectorized.contains(allowed, X, Zg) & ~vectorized.contains(q.roads.buffer(0.3), X, Zg)
        cls = np.zeros(X.shape, np.int8)
        for k, name in ((1, "gravel"), (2, "concrete"), (3, "asphalt")):
            msk = getattr(q, name)
            # 1 m = 2 × 2 pixels de 0,5 m : majorité
            J = ((Zg - q.v.z0) / q.c).astype(int); I = ((X - q.v.x0) / q.c).astype(int)
            J = np.clip(J, 0, msk.shape[0] - 2); I = np.clip(I, 0, msk.shape[1] - 2)
            frac = (msk[J, I].astype(float) + msk[J + 1, I] + msk[J, I + 1] + msk[J + 1, I + 1]) / 4
            cls[(frac >= 0.5) & ok & (cls == 0)] = k
        cls = ndi.median_filter(cls, size=3)
        cls[~ok] = 0
        # accotements : entre la chaussée et les clôtures, l'enrobé va jusqu'aux murets et portails
        parcels_all = unary_union([p for pid, p in q.parcels])
        homes = unary_union(res_parcels).buffer(0.2)
        verge = q.roads.buffer(6.0).intersection(homes.buffer(6.0)).difference(parcels_all).difference(q.roads.buffer(0.2))
        vmask = vectorized.contains(verge.intersection(zone_poly()), X, Zg)      # accotements enrobés : rue du Balcon
        # on ne garde que les plaques reliées à la rue ou à une maison (allées, cours, terrasses, parkings) :
        # l'herbe grillée claire au milieu d'un jardin n'est pas du gravier
        anchor = vectorized.contains(q.roads.buffer(1.5), X, Zg) | vectorized.contains(unary_union(q.buildings).buffer(1.5), X, Zg)
        # pas de taches : chaque nature de sol est lissée (ouverture + fermeture), les plaques de moins de 15 m² et
        # celles qui ne touchent ni la rue ni une maison disparaissent, une plaque prend une seule nature (majoritaire)
        sm = np.zeros_like(cls)
        for k in (1, 2, 3):
            mk = ndi.binary_closing(ndi.binary_opening(cls == k, iterations=1), iterations=2) & ok
            sm[(mk) & (sm == 0)] = k
        cls = sm
        lab, nl = ndi.label(cls > 0)
        if nl:
            touch = ndi.maximum(anchor, lab, index=np.arange(1, nl + 1))
            size = ndi.sum(np.ones_like(lab), lab, index=np.arange(1, nl + 1))
            keep = np.concatenate([[False], (np.asarray(touch) > 0) & (np.asarray(size) >= 15)])
            cls[~keep[lab]] = 0
            for c_ in range(1, nl + 1):
                if keep[c_]:
                    mm = lab == c_
                    cls[mm] = np.bincount(cls[mm], minlength=4)[1:].argmax() + 1
        # règle « la logique prime » : pas de plaques pixelisées. Sols durs = formes nettes :
        #   * une allée droite du portail à la maison (nature majoritaire sous l'allée sur la photo, gravier sinon) ;
        #   * une cour seulement si la photo montre une grande surface dure (>= 60 m²) collée à la maison,
        #     contour lissé ;
        #   * accotements enrobés de la rue du Balcon (polygone).
        from shapely.geometry import MultiPoint
        import sidewalks as swm
        cols = {1: (0.80, 0.75, 0.64), 2: (0.70, 0.69, 0.66), 3: (0.36, 0.36, 0.37)}
        mats = {1: M_GRAVEL, 2: M_PAVE, 3: M_PAVE}
        names = {1: "gravier (m²)", 2: "béton / dallage (m²)", 3: "enrobé (m²)"}
        surfaces = []                                   # (polygone, nature)
        blds = unary_union(q.buildings) if q.buildings else None

        def nature(poly):
            from shapely import vectorized as _v
            m_ = _v.contains(poly, X, Zg)
            vals = cls[m_]
            vals = vals[vals > 0]
            return int(np.bincount(vals, minlength=4)[1:].argmax() + 1) if len(vals) > 3 else 1

        for g in gates:
            mid, inw = np.array(g["mid"]), np.array(g["inward"])
            par = dict(q.parcels)[g["pid"]]
            # jusqu'à la maison la plus proche dans l'axe (25 m max), sinon 6 m
            L_ = 6.0
            for t in np.arange(1.0, 25.0, 0.5):
                if blds is not None and blds.distance(Point(mid + inw * t)) < 1.0:
                    L_ = max(3.0, t - 0.6); break
            d_ = np.array(g["d"])
            rect = Polygon([mid - d_ * 1.6, mid + d_ * 1.6, mid + d_ * 1.6 + inw * L_, mid - d_ * 1.6 + inw * L_])
            rect = rect.intersection(par.buffer(-0.1))
            if blds is not None:
                rect = rect.difference(blds.buffer(0.2))
            for pg in getattr(rect, "geoms", [rect]):
                if pg.geom_type == "Polygon" and pg.area > 4:
                    surfaces.append((pg, nature(pg)))
        lab, nl = ndi.label(cls > 0)
        if nl and blds is not None:
            for c_ in range(1, nl + 1):
                mm = lab == c_
                if mm.sum() * step * step < 60:
                    continue
                pts = np.c_[X[mm], Zg[mm]]
                g_ = MultiPoint(pts).buffer(0.75, quad_segs=2)
                g_ = g_.buffer(1.5).buffer(-1.5).simplify(0.6)
                if blds.distance(g_) > 1.5:
                    continue                          # surface dure isolée au milieu d'un jardin : pelouse grillée
                g_ = g_.intersection(allowed).difference(blds.buffer(0.2))
                for pg in getattr(g_, "geoms", [g_]):
                    # une cour est pleine et compacte : pas d'anneau autour d'une pelouse, pas de lanière
                    if pg.geom_type == "Polygon" and any(Polygon(h).area > 6 for h in pg.interiors):
                        continue
                    if pg.geom_type == "Polygon" and pg.area < 0.6 * pg.convex_hull.area:
                        continue
                    if pg.geom_type == "Polygon" and pg.area > 20:
                        k_ = int(np.bincount(cls[mm], minlength=4)[1:].argmax() + 1)
                        surfaces.append((pg, k_))
        verge_z = verge.intersection(zone_poly())
        # rue du Balcon : sols relevés sur Street View (gravier / enrobé côté nord, herbe côté sud, placette, chemin)
        bal = rue_balcon.surfaces([p_ for _, p_ in q.parcels], q.hard)
        excl = unary_union([g for g, _ in bal] + [rue_balcon.axis().buffer(12.0)])
        verge_z = verge_z.difference(excl)
        for g, k_ in bal:
            for pg in getattr(g, "geoms", [g]):
                if pg.geom_type == "Polygon" and pg.area > 1.0:
                    surfaces.append((pg.simplify(0.2), k_))
                    count("rue du Balcon : " + {1: "gravier", 2: "béton", 3: "enrobé"}[k_] + " (m²)", pg.area)
        for pg in getattr(verge_z, "geoms", [verge_z]):
            if pg.geom_type == "Polygon" and pg.area > 4:
                surfaces.append((pg.simplify(0.3), 3))
        # une seule couche : les surfaces se recouvrant sont fusionnées par nature (la plus « dure » l'emporte)
        done = None
        tiles = {}
        for pg, k in sorted(surfaces, key=lambda t: -t[1]):
            if done is not None:
                pg = pg.difference(done)
            if pg.is_empty:
                continue
            done = pg if done is None else done.union(pg)
            for part in getattr(pg, "geoms", [pg]):
                if part.geom_type != "Polygon" or part.area < 1.0:
                    continue
                v, tri = swm.tri_poly(part, 2.0)
                if len(tri) == 0:
                    continue
                v, tri = swm.subdivide(v, tri, 2.5)
                c = part.representative_point()
                key = (int((c.x - x0) // 64), int((c.y - z0) // 64))
                mm = tiles.setdefault(key, Mesh())
                ids = [mm.vert((float(x), q.H(x, z) + 0.035, float(z)), (0, 1, 0), cols[k], (float(x), float(z)), mats[k]) for x, z in v]
                for t in range(0, len(tri), 3):
                    mm.tri(ids[tri[t]], ids[tri[t + 1]], ids[tri[t + 2]])
                q.paved_polys.append(list(part.exterior.coords))
                count(names[k], part.area)
        for (kx, kz), mm in tiles.items():
            add(x0 + kx * 64 + 32, z0 + kz * 64 + 32, mm, True)
    return {k: int(v) for k, v in stats.items()}
