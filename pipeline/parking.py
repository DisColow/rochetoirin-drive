"""Parkings (OSM amenity=parking, fetch_parking.py), pour build_roads.py :
 - emprises en enrobé (ou gravier), bâtiments et chaussées retirés, nivelées : altitude du relief lissé, raccordée
   progressivement à celle de la route d'accès (points de terrassement ajoutés à ceux des routes) ;
 - places de 2,5 × 5 m de part et d'autre des allées (service=parking_aisle), ou à défaut en rangées le long du bord
   côté route (et de part et d'autre d'allées tous les 16 m pour les parkings profonds), créneaux de 5,5 × 2,2 m pour
   les parkings en bord de rue trop étroits ; jamais sur une route, un bâtiment ou une autre place ;
 - marquage blanc entre les places.
Sortie complémentaire : data/parkings.pkl (emprises et places : clôtures, voitures garées, cohérence)."""
import json, math, pickle
import numpy as np
import shapely
from shapely.geometry import Polygon, LineString, shape, box
from shapely.ops import unary_union, transform
from shapely.strtree import STRtree
from scipy.spatial import cKDTree
from scipy import ndimage as ndi
from geo import to_local

STALL_W, STALL_D = 2.5, 5.0          # place en bataille
PAR_L, PAR_W = 5.5, 2.2              # place en créneau
AISLE_HALF = 3.0                     # demi-largeur d'allée de desserte
LINE_W = 0.12


def load(zone):
    d = json.load(open("data/osm_parking.json"))
    out = []
    for e in d["elements"]:
        t = e.get("tags", {})
        if t.get("amenity") != "parking" or e["type"] != "way" or "geometry" not in e:
            continue
        if t.get("parking") in ("underground", "multi-storey", "rooftop", "garage_boxes", "carports"):
            continue
        pts = [to_local(g["lon"], g["lat"]) for g in e["geometry"]]
        if len(pts) < 4:
            continue
        g = Polygon(pts).buffer(0)
        if g.is_empty or g.area < 25 or not zone.intersects(g):
            continue
        out.append(dict(id=e["id"], geom=g, tags=t, paved=t.get("surface") not in ("gravel", "compacted", "grass", "dirt",
                                                                                     "fine_gravel", "ground", "grass_paver", "unpaved")))
    return out


def buildings(zone):
    feats = json.load(open("data/batiments.json"))["features"]
    out = []
    for f in feats:
        g = transform(lambda x, y, z=None: to_local(x, y), shape(f["geometry"]))
        if zone.intersects(g):
            out.append(g.buffer(0))
    return out


class Parkings:
    def __init__(self, ways, zone):
        self.lots = load(zone)
        blds = buildings(zone)
        bt = STRtree(blds)
        roads = [LineString(w["P"]).buffer(w["w"] / 2 + 0.2, cap_style="flat") for w in ways
                 if len(w["P"]) > 1 and w["tags"].get("service") != "parking_aisle" and not w["bridge"]]
        self.road_tree = STRtree(roads); self.roads = roads
        self.aisles = [w for w in ways if w["tags"].get("service") == "parking_aisle" and len(w["P"]) > 1]
        at = STRtree([LineString(w["P"]) for w in self.aisles]) if self.aisles else None
        for lot in self.lots:
            g = lot["geom"]
            hits = [blds[k] for k in bt.query(g) if blds[k].intersects(g)]
            if hits:
                g = g.difference(unary_union(hits).buffer(0.3))
            # les chaussées traversantes restent des chaussées (déjà revêtues) : l'emprise n'en garde que le reste
            rh = [roads[k] for k in self.road_tree.query(g) if roads[k].intersects(g)]
            lot["free"] = g.difference(unary_union(rh)) if rh else g
            lot["geom"] = g
            lot["aisles"] = [self.aisles[k] for k in (at.query(g) if at is not None else []) if LineString(self.aisles[k]["P"]).intersects(g)]
        self.lots = [l for l in self.lots if not l["geom"].is_empty and l["geom"].area > 20]
        self.bld_tree = bt; self.blds = blds
        self.stalls = []

    # ---------------------------------------------------------------- hauteur
    def samples(self, dem, rf):
        """Points de terrassement (x, z, y, demi-largeur) sur une grille de 2 m couvrant les emprises : relief lissé,
        raccordé à la route la plus proche sur 10 m."""
        out = []
        for lot in self.lots:
            g = lot["geom"]
            x0, z0, x1, z1 = g.bounds
            xs = np.arange(x0, x1 + 2, 2.0); zs = np.arange(z0, z1 + 2, 2.0)
            X, Z = np.meshgrid(xs, zs)
            inside = shapely.contains_xy(g.buffer(1.0), X, Z)
            if not inside.any():
                continue
            # relief lissé sur l'emprise (moyenne pondérée sur ~12 m)
            H = np.asarray(dem.h(X.ravel(), Z.ravel())).reshape(X.shape)
            m = inside.astype(float)
            Hs = ndi.gaussian_filter(H * m, 3.0) / np.maximum(ndi.gaussian_filter(m, 3.0), 1e-3)
            yr, sd = rf(X[inside], Z[inside])
            t = np.clip(sd / 10.0, 0, 1)
            t = t * t * (3 - 2 * t)
            y = np.where(sd < 1e8, yr + (Hs[inside] - yr) * t, Hs[inside])
            lot["grid"] = (xs, zs, inside, y)
            out.append(np.c_[X[inside], Z[inside], y, np.full(inside.sum(), 1.2)])
        return np.vstack(out) if out else np.zeros((0, 4))

    # ---------------------------------------------------------------- places
    def _ok(self, r, lot, placed):
        if not lot["geom"].buffer(-0.1).contains(r):
            return False
        if any(self.roads[k].intersects(r) for k in self.road_tree.query(r)):
            return False
        if any(self.blds[k].intersects(r) for k in self.bld_tree.query(r)):
            return False
        return not any(p.intersects(r) for p in placed)

    def _row(self, lot, A, B, side, placed, out, depth=STALL_D, width=STALL_W, offset=AISLE_HALF):
        """Places le long du segment A -> B (côté side = +1 droite / -1 gauche), à offset du segment."""
        d = B - A; L = float(np.hypot(*d))
        if L < width:
            return
        u = d / L; n = np.array([u[1], -u[0]]) * side
        k = 0.0
        while k + width <= L + 1e-6:
            p0 = A + u * k + n * offset
            c = [p0, p0 + u * width, p0 + u * width + n * depth, p0 + n * depth]
            r = Polygon(c)
            if self._ok(r.buffer(-0.05), lot, placed):
                placed.append(r); out.append(np.array(c))
            k += width

    def _directions(self, g):
        C = []
        for part in getattr(g, "geoms", [g]):
            E = np.asarray(part.exterior.coords)
            C += [(float(np.hypot(*(q - p))), q - p) for p, q in zip(E[:-1], E[1:])]
        C.sort(key=lambda t: -t[0])
        out = []
        for L, v in C[:6]:
            u = v / L
            for d in (u, np.array([-u[1], u[0]])):
                if all(abs(float(np.dot(d, o))) < 0.985 for o in out):
                    out.append(d)
        return out[:6]

    def _fill(self, lot, u, placed, rows):
        g = lot["geom"]
        n = np.array([u[1], -u[0]])
        E = np.vstack([np.asarray(p.exterior.coords) for p in getattr(g, "geoms", [g])])
        t = E @ u; o = E @ n
        tmin, tmax, omin, omax = t.min(), t.max(), o.min(), o.max()
        depth = omax - omin
        A0 = u * tmin; B0 = u * tmax
        # bord le plus proche d'une route : les places s'y appuient
        c = np.asarray(g.centroid.coords[0])
        def road_d(off):
            q = shapely.Point(*(c - n * (c @ n) + n * off))
            return min((self.roads[k].distance(q) for k in self.road_tree.query(q.buffer(40))), default=99)
        from_min = road_d(omin) <= road_d(omax)
        if depth >= STALL_D + 2 * AISLE_HALF:
            off = STALL_D + AISLE_HALF
            while off <= depth - AISLE_HALF + 0.01:
                oo = omin + off if from_min else omax - off
                for s_ in (1, -1):
                    self._row(lot, A0 + n * oo, B0 + n * oo, s_, placed, rows)
                off += 2 * (STALL_D + AISLE_HALF)
        else:
            oo = omin if from_min else omax
            side = 1 if from_min else -1          # vers l'intérieur : +n depuis omin ; _row tourne de -90° (u -> n·side)
            # _row : n_row = (u.y, -u.x) * side = n * side
            if depth >= STALL_D - 0.2:
                self._row(lot, A0 + n * oo, B0 + n * oo, side, placed, rows, offset=0.1)
            elif depth >= PAR_W - 0.1:
                self._row(lot, A0 + n * oo, B0 + n * oo, side, placed, rows, depth=PAR_W, width=PAR_L, offset=0.05)

    def build(self):
        for lot in self.lots:
            placed = []; rows = []
            if lot["aisles"]:
                for w in lot["aisles"]:
                    P = w["P"]
                    for a, b in zip(P[:-1], P[1:]):
                        for side in (1, -1):
                            self._row(lot, a, b, side, placed, rows)
            else:
                # sans allée cartographiée : rangées parallèles à l'un des grands bords de l'emprise (ou à leur
                # perpendiculaire) ; on garde l'orientation qui loge le plus de places
                best = []
                for u in self._directions(lot["geom"]):
                    trial_p, trial_r = [], []
                    self._fill(lot, u, trial_p, trial_r)
                    if len(trial_r) > len(best):
                        best = trial_r
                rows = best
            lot["stalls"] = rows
            self.stalls += rows
        return len(self.stalls)

    # ---------------------------------------------------------------- géométrie
    def surfaces(self):
        paved = [l["geom"] for l in self.lots if l["paved"]]
        unpaved = [l["geom"] for l in self.lots if not l["paved"]]
        return paved, unpaved

    def markings(self, out, hroad):
        """Traits blancs : côtés des places (sans doublon entre places voisines)."""
        seen = set(); n = 0
        for c in self.stalls:
            for a, b in ((c[0], c[3]), (c[1], c[2])):
                key = (round(a[0] * 4), round(a[1] * 4), round(b[0] * 4), round(b[1] * 4))
                if key in seen:
                    continue
                seen.add(key)
                _line(out, a, b, hroad); n += 1
        return n

    def save(self):
        pickle.dump(dict(lots=[dict(id=l["id"], geom=l["geom"], paved=l["paved"], stalls=l.get("stalls", [])) for l in self.lots]),
                    open("data/parkings.pkl", "wb"))


def _line(out, a, b, hroad):
    d = b - a; L = float(np.hypot(*d))
    if L < 0.2:
        return
    u = d / L; nrm = np.array([-u[1], u[0]]) * LINE_W / 2
    k = max(1, int(math.ceil(L / 1.5)))
    P = []
    for j in range(k + 1):
        q = a + d * j / k
        for s in (-1, 1):
            p = q + nrm * s
            P.append((p[0], float(hroad(p[0], p[1])[0]) + 0.025, p[1]))
    P = np.array(P, np.float32)
    I = []
    for j in range(k):
        i0 = 2 * j
        I += [i0, i0 + 1, i0 + 2, i0 + 1, i0 + 3, i0 + 2]          # même sens que les marquages des routes (vus du dessus)
    Nn = np.tile([0, 1, 0], (len(P), 1)).astype(np.float32)
    UV = np.zeros((len(P), 2), np.float32)
    out.add("marking", P, Nn, UV, np.array(I, np.uint32), (a + b) / 2)
