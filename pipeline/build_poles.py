"""Poteaux, pylônes, fils et lampadaires -> ../godot/world/poles/p_tx_tz.bin (tuiles de 256 m).
 - lignes haute tension (OSM power=line) : pylônes à chaque support, 6 conducteurs ;
 - lignes basse / moyenne tension (power=minor_line) : poteaux bois ou béton, 3 fils ;
 - lampadaires : ceux d'OSM + un tous les 30 m d'un côté des rues de village (zones habitées), au-delà de la chaussée,
   du trottoir et de 0,6 m, jamais dans un bâtiment ni sur une clôture.
Rien sur la route : un support qui tomberait sur la chaussée (données décalées) est repoussé au bord, ou supprimé.
Format : int32 nombre de supports, puis (type, x, y, z, cap) float32 ; int32 nombre de fils, puis pour chacun
int32 n et n × (x, y, z). Types : 1 lampadaire, 2 poteau bois, 3 poteau béton, 4 pylône."""
import json, math, os, pickle, shutil
from collections import defaultdict
import numpy as np
import shapely
from shapely.geometry import LineString, Point, Polygon
from shapely.strtree import STRtree
import geo
from build_vegetation import Carved
from build_fences import Local
from build_ground import building_mask
from build_roads import REG

OUT = "../godot/world/poles"
TILE = 256.0
H_SUPPORT = {1: 6.0, 2: 8.5, 3: 9.5, 4: 28.0}   # hauteur d'accroche des fils (m)


def main():
    shutil.rmtree(OUT, ignore_errors=True); os.makedirs(OUT)
    plan = json.load(open("data/routes_plan.json"))
    zone = Polygon(plan["zone"])
    dem = Carved()
    ways = pickle.load(open("data/roads.pkl", "rb"))["ways"]
    road_z = Local([LineString(w["P"]).buffer(w["w"] / 2 + (1.6 if any(w["sidewalk"]) else 0.0) + 0.6)
                    for w in ways if len(w["P"]) > 1])
    d = json.load(open("data/osm_power.json"))
    supports = []          # (type, x, z, cap)
    wires = []             # [(x, y, z)]
    rng = np.random.default_rng(3)

    def out_of_road(x, z):
        """Repousse un point hors de l'emprise des routes (ou None si impossible)."""
        p = Point(x, z)
        near = road_z.near(p, 0.01)
        if not near:
            return x, z
        for g in near:
            if g.contains(p):
                b = g.exterior
                q = b.interpolate(b.project(p))
                v = np.array([q.x - x, q.y - z]); L = np.linalg.norm(v)
                if L > 4.0:
                    return None
                n = v / max(L, 1e-6)
                x, z = q.x + n[0] * 0.3, q.y + n[1] * 0.3
                p = Point(x, z)
        return (x, z) if not any(g.contains(p) for g in road_z.near(p, 0.01)) else None

    # lignes électriques
    for e in d["elements"]:
        if e["type"] != "way":
            continue
        pw = e["tags"].get("power")
        if pw not in ("line", "minor_line") or "geometry" not in e:
            continue
        lon = np.array([g["lon"] for g in e["geometry"]]); lat = np.array([g["lat"] for g in e["geometry"]])
        x, z = geo.to_local(lon, lat)
        P = np.c_[x, z]
        if not LineString(P).intersects(zone.buffer(400)):
            continue
        typ = 4 if pw == "line" else (2 if rng.random() < 0.6 else 3)
        # supports : sommets de la ligne ; portées trop longues coupées (poteaux tous les 45 m au plus en BT)
        pts = [P[0]]
        for a, b in zip(P[:-1], P[1:]):
            L = np.linalg.norm(b - a); m = int(L // (350 if typ == 4 else 45))
            for k in range(1, m + 1):
                pts.append(a + (b - a) * k / (m + 1))
            pts.append(b)
        sup = []
        for k, p in enumerate(pts):
            q = out_of_road(*p)
            if q is None:
                continue
            nb = pts[min(k + 1, len(pts) - 1)] - pts[max(k - 1, 0)]
            cap = math.degrees(math.atan2(nb[0], -nb[1]))
            sup.append((typ, q[0], q[1], cap))
        supports += sup
        # fils : entre supports consécutifs, chaînette (flèche ~2,5 % de la portée)
        offs = [-0.7, 0.0, 0.7] if typ != 4 else [-6.5, -4.5, -2.5, 2.5, 4.5, 6.5]
        hh = H_SUPPORT[typ]
        for (t1, x1, z1, c1), (t2, x2, z2, c2) in zip(sup[:-1], sup[1:]):
            L = math.hypot(x2 - x1, z2 - z1)
            if L < 3 or L > 600:
                continue
            y1 = float(dem.h(np.array([x1]), np.array([z1]))[0]) + hh
            y2 = float(dem.h(np.array([x2]), np.array([z2]))[0]) + hh
            dx, dz = (x2 - x1) / L, (z2 - z1) / L
            for o in offs:
                ox, oz = -dz * o, dx * o
                seg = []
                n = max(4, int(L / 12))
                for k in range(n + 1):
                    t = k / n
                    sag = 4 * 0.025 * L * t * (1 - t)
                    seg.append((x1 + (x2 - x1) * t + ox, y1 + (y2 - y1) * t - sag - (abs(o) > 3) * 0.0, z1 + (z2 - z1) * t + oz))
                wires.append(seg)
    nlines = len(supports)
    # lampadaires OSM
    for e in d["elements"]:
        if e["type"] == "node" and e["tags"].get("highway") == "street_lamp":
            x, z = geo.to_local(e["lon"], e["lat"])
            q = out_of_road(float(x), float(z))
            if q:
                supports.append((1, q[0], q[1], rng.random() * 360))
    # lampadaires de village : rues résidentielles dans les zones habitées
    from prepare_terrain import landuse
    _, _, _, resid = landuse()
    shapely.prepare(resid)
    bmasks = {}
    def in_building(x, z):
        i, j = int(math.floor(x / REG)), int(math.floor(z / REG))
        if (i, j) not in bmasks:
            try:
                bmasks[(i, j)] = building_mask(i, j)
            except Exception:
                bmasks[(i, j)] = None
        m = bmasks[(i, j)]
        if m is None:
            return False
        xi, zi = int(x - i * REG), int(z - j * REG)
        return bool(m[max(0, zi - 1):zi + 2, max(0, xi - 1):xi + 2].any())
    nvil = 0
    for w in ways:
        if w["cls"] not in ("residential", "living_street", "tertiary", "unclassified") or len(w["P"]) < 2:
            continue
        line = LineString(w["P"])
        if not line.intersects(zone):
            continue
        off = w["w"] / 2 + (1.6 if any(w["sidewalk"]) else 0.0) + 0.8
        side = 1 if (w["id"] % 2) else -1
        L = line.length
        for s in np.arange(12.0, L - 6.0, 30.0):
            p = line.interpolate(s)
            if not shapely.contains_xy(resid, p.x, p.y):
                continue
            a = np.asarray(line.interpolate(max(0, s - 1)).coords[0]); b = np.asarray(line.interpolate(min(L, s + 1)).coords[0])
            t = (b - a) / max(np.linalg.norm(b - a), 1e-6); n = np.array([-t[1], t[0]]) * side
            x, z = p.x + n[0] * off, p.y + n[1] * off
            if road_z.near(Point(x, z), 0.01) or in_building(x, z):
                continue
            cap = math.degrees(math.atan2(-n[0], n[1]))        # la crosse au-dessus de la chaussée
            supports.append((1, x, z, cap)); nvil += 1
    # écriture par tuile
    T = defaultdict(lambda: ([], []))
    for typ, x, z, cap in supports:
        y = float(dem.h(np.array([x]), np.array([z]))[0])
        T[(int(math.floor(x / TILE)), int(math.floor(z / TILE)))][0].append((typ, x, y, z, cap))
    for seg in wires:
        m = seg[len(seg) // 2]
        T[(int(math.floor(m[0] / TILE)), int(math.floor(m[2] / TILE)))][1].append(seg)
    for (tx, tz), (S, W) in T.items():
        b = bytearray()
        b += np.int32(len(S)).tobytes()
        if S:
            b += np.array(S, "<f4").tobytes()
        b += np.int32(len(W)).tobytes()
        for seg in W:
            b += np.int32(len(seg)).tobytes() + np.array(seg, "<f4").tobytes()
        open("%s/p_%d_%d.bin" % (OUT, tx, tz), "wb").write(bytes(b))
    print(nlines, "supports de lignes,", len(supports) - nlines - nvil, "lampadaires OSM,", nvil, "lampadaires de village,",
          len(wires), "fils,", len(T), "tuiles")


if __name__ == "__main__":
    main()
