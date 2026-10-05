"""Clôtures, murets, haies et portails qui délimitent les propriétés ; haies champêtres du bocage.

Logique (la logique prime sur la donnée brute) :
 - parcelle habitée = parcelle cadastrale (< 5000 m²) qui contient une maison (BD TOPO résidentielle ou indifférenciée) ;
 - la parcelle est d'abord privée de l'emprise interdite (chaussée + trottoir + 0,5 m) : la limite côté rue se pose au
   bord de cette emprise si le cadastre (décalé de 1 à 3 m) mord sur la route -> rien ne déborde sur la route ;
 - chaque morceau de limite est classé : façade (le long d'une route), limite mitoyenne (deux parcelles habitées,
   posée une seule fois), fond (vers un champ, un bois...) ; le long d'une allée privée (driveway) : rien ;
 - un seul style par façade, d'un bout à l'autre (relevé Street View du bourg -> clotures_bourg.json, sinon haie /
   mur / grillage OSM ou BD TOPO tout proche, sinon tirage selon la répartition relevée dans le bourg) ;
 - pas de clôture dans un bâtiment (une annexe sur la limite sert de mur) ; haies et murs côté rue reculés dans la
   parcelle de leur demi-épaisseur ;
 - portail sur la façade face à la maison (ou au portail OSM), entre deux piliers ; pas de portail s'il y a déjà une
   allée qui entre dans la parcelle (ouverture entre deux piliers).
Haies champêtres : BD TOPO « haie » et OSM barrier=hedge hors des propriétés, hauteur d'après le LiDAR (MNH).
Sortie : ../godot/world/fences/f_tx_tz.bin (enregistrements compacts : lignes, piliers, vantaux ; maillages faits en jeu)."""
import hashlib, json, math, os, pickle, shutil, time
T0 = time.time()
_print = print
def print(*a, **k):
    _print("[%4.0fs]" % (time.time() - T0), *a, flush=True, **k)
from collections import Counter, defaultdict
import numpy as np
import shapely
from shapely.geometry import shape, LineString, MultiLineString, Polygon, MultiPolygon, Point
from shapely.ops import transform, unary_union, linemerge, substring
from shapely.strtree import STRtree
from shapely.prepared import prep
import geo
from build_roads import REG
from build_vegetation import Carved
from build_buildings import load as load_buildings
from build_fence_tex import IDX, SCALE

OUT = "../godot/world/fences"
TILE = 256.0
DRIVE = ("driveway", "parking_aisle")


def rnd(key, salt=""):
    return int(hashlib.md5((str(key) + salt).encode()).hexdigest()[:8], 16) / 2 ** 32


def pick(key, salt, items):
    r = rnd(key, salt); acc = 0.0; tot = sum(w for _, w in items)
    for v, w in items:
        acc += w / tot
        if r < acc:
            return v
    return items[-1][0]


def col(rgb, base=0.8):
    """Teinte de sommet (le shader l'élève au carré) pour obtenir la couleur voulue sur une texture neutre."""
    return np.sqrt(np.clip(np.array(rgb, np.float32) / 255.0 / base, 0, 1))


COLORS = {"vert": (38, 68, 48), "anthracite": (52, 56, 60), "gris": (120, 124, 124), "blanc": (228, 228, 222),
          "noir": (28, 28, 30), "beige": (200, 185, 160), "brun": (95, 70, 52), "galva": (150, 154, 150)}
WALL = {"creme": (225, 210, 182), "gris": (178, 176, 170), "blanc": (236, 233, 226), "rose": (226, 194, 174)}
# répartition relevée sur Street View dans le bourg (171 façades)
FRONT_MIX = [("haie_laurier", 45), ("rien", 26), ("haie_thuya", 20), ("occult", 17), ("muret_grille", 14),
             ("rigide", 13), ("muret_rigide", 12), ("mur", 10), ("muret", 5), ("lisses", 5), ("bois", 2),
             ("haie_photinia", 2)]
SURVEY = {"haieT": "haie_thuya", "haieL": "haie_laurier", "haieP": "haie_photinia", "muret": "muret",
          "muret_grille": "muret_grille", "muret_rigide": "muret_rigide", "mur": "mur", "occult": "occult",
          "lisses": "lisses", "bois": "bois", "grillage": "rigide", "rien": "rien"}
SIDE_MIX = [("rigide", 35), ("losange", 20), ("haie_laurier", 15), ("haie_thuya", 15), ("rien", 15)]
BACK_MIX = [("losange", 35), ("haie_champetre", 25), ("rigide", 15), ("rien", 25)]
HEDGE_DIM = {"haie_thuya": (1.8, 2.3, 0.8), "haie_laurier": (1.6, 2.1, 1.0), "haie_photinia": (1.4, 1.8, 0.9),
         "haie_champetre": (1.6, 2.6, 1.5)}
# demi-épaisseur côté rue (recul dans la parcelle)
HALF = {"haie_thuya": 0.45, "haie_laurier": 0.55, "haie_photinia": 0.5, "haie_champetre": 0.8, "mur": 0.15,
        "muret": 0.15, "muret_grille": 0.15, "muret_rigide": 0.15}


def to_local_geom(g):
    return transform(lambda x, y, z=None: geo.to_local(x, y), g)


def lines_of(g):
    if g.is_empty:
        return []
    if g.geom_type == "LineString":
        return [g]
    if hasattr(g, "geoms"):
        out = []
        for p in g.geoms:
            out += lines_of(p)
        return out
    return []


def polys_of(g):
    if g.is_empty:
        return []
    if g.geom_type == "Polygon":
        return [g]
    if hasattr(g, "geoms"):
        return [p for q in g.geoms for p in polys_of(q)]
    return []


class Local:
    """Géométries indexées : opérations locales (jamais contre l'union de toute la carte, trop lente)."""
    def __init__(self, geoms):
        self.g = list(geoms); self.t = STRtree(self.g) if self.g else None

    def near(self, g, d):
        if self.t is None:
            return []
        return [self.g[i] for i in self.t.query(g, predicate="dwithin", distance=d)]

    def dist(self, g, cap=30.0):
        gs = self.near(g, cap)
        return min(x.distance(g) for x in gs) if gs else 1e9

    def cut(self, g, margin=0.0):
        gs = self.near(g, margin + 0.01)
        if not gs:
            return g
        u = unary_union(gs)
        return g.difference(u.buffer(margin) if margin > 0 else u)


# ------------------------------------------------------------------------------------------------ données
def load_parcels():
    seen, out = set(), []
    for f in sorted(os.listdir("data/cadastre")):
        for ft in json.load(open("data/cadastre/" + f))["features"]:
            pid = ft["properties"]["id"]
            if pid in seen or ft["geometry"] is None:
                continue
            seen.add(pid)
            g = to_local_geom(shape(ft["geometry"])).buffer(0)
            ps = polys_of(g)
            if not ps:
                continue
            out.append((pid, max(ps, key=lambda p: p.area)))
    return out


def load_osm():
    o = json.load(open("data/osm.json"))
    els = o["elements"] if isinstance(o, dict) else o
    nodes = {e["id"]: (e["lon"], e["lat"]) for e in els if e["type"] == "node" and "lon" in e}
    lines = defaultdict(list); gates = []
    for e in els:
        b = e.get("tags", {}).get("barrier")
        if not b:
            continue
        if e["type"] == "node" and b in ("gate", "swing_gate", "sliding_gate", "wicket_gate") and e["id"] in nodes:
            gates.append(geo.to_local(*nodes[e["id"]]))
        elif e["type"] == "way" and b in ("hedge", "wall", "fence"):
            pts = [nodes[n] for n in e["nodes"] if n in nodes]
            if len(pts) > 1:
                x, z = geo.to_local(np.array([p[0] for p in pts]), np.array([p[1] for p in pts]))
                needle = e["tags"].get("leaf_type") == "needleleaved"
                lines[b].append((LineString(np.c_[x, z]), needle))
    return lines, np.array(gates, np.float64).reshape(-1, 2)


# ------------------------------------------------------------------------------------------------ géométrie
# Enregistrements (float32) : en-tête de 16 valeurs puis n points (x, y, z). Le jeu construit les maillages
# (fences.gd, dans un fil de calcul) : quelques Mo au lieu de centaines de Mo de maillages.
# en-tête : type, n, couche, couche2, h0, h1, w, r, g, b, r2, g2, b2, graine, extra, drapeaux
R_HEDGE, R_WALL, R_PANEL, R_POSTS, R_BOX, R_COLL = 1, 2, 3, 4, 5, 6
F_CAPS, F_VFULL, F_CUT, F_TWO, F_FLAT = 1, 2, 4, 8, 16


class Out:
    def __init__(self):
        self.recs = []

    def rec(self, typ, P, Y, layer=0, layer2=0, h0=0.0, h1=0.0, w=0.0, tint=(1, 1, 1), tint2=(0, 0, 0), seed=0.0,
            extra=0.0, flags=0):
        P = np.asarray(P, np.float32).reshape(-1, 2); Y = np.asarray(Y, np.float32).reshape(-1)
        head = [typ, len(P), layer, layer2, h0, h1, w, *tint, *tint2, seed, extra, flags]
        self.recs.append(np.r_[np.array(head, np.float32), np.c_[P[:, 0], Y, P[:, 1]].ravel()].astype("<f4"))

    def bytes(self):
        return np.concatenate(self.recs).tobytes()


def build_line(o, P, Y, style, key, opts):
    """Pose une clôture de style donné le long de P (2D, échantillonné) sur le sol Y."""
    r = lambda s: rnd(key, s)
    CHECK.append((P[::2] if len(P) > 4 else P, HEDGE_DIM[style][2] * 0.5 * 1.1 if style.startswith("haie_") and not opts.get("w") else
                  (opts["w"] * 0.5 * 1.1 if style.startswith("haie_") else 0.15)))
    if style.startswith("haie_"):
        h0, h1, w = HEDGE_DIM[style]
        h = opts.get("h") or (h0 + (h1 - h0) * r("h"))
        w = opts.get("w") or w * (0.85 + 0.3 * r("w"))
        tint = np.array([0.92, 0.96, 0.9]) * (0.9 + 0.2 * r("t"))
        o.rec(R_HEDGE, P, Y, IDX[style], IDX["bord_" + style[5:]], 0.0, h, w, tint, seed=r("n") * 100)
        o.rec(R_COLL, P, Y, h1=min(h, 1.5))
        return
    if style in ("mur", "muret", "muret_grille", "muret_rigide"):
        wall = opts.get("mur") or pick(key, "mur", [("creme", 3), ("gris", 5), ("pierre", 1), ("blanc", 1), ("rose", 0.4)])
        lay, tint = (IDX["pierre"], col((200, 190, 175), 0.85)) if wall == "pierre" else (IDX["crepi"], col(WALL[wall], 0.86))
        hw = {"mur": 1.6 + 0.4 * r("h"), "muret": 0.6 + 0.3 * r("h"), "muret_grille": 0.5 + 0.2 * r("h"),
              "muret_rigide": 0.4 + 0.2 * r("h")}[style]
        o.rec(R_WALL, P, Y, lay, h0=-0.3, h1=hw, w=0.1, tint=tint, flags=F_CAPS)
        o.rec(R_WALL, P, Y, IDX["beton"], h0=hw - 0.01, h1=hw + 0.06, w=0.14, tint=col((190, 188, 182), 0.76), flags=F_CAPS)
        top = hw + 0.06
        if style == "muret_grille":
            gc = col(COLORS.get(opts.get("grille") or pick(key, "g", [("gris", 3), ("blanc", 2), ("noir", 2), ("vert", 2)]), COLORS["gris"]), 0.75)
            gh = 0.8 + 0.3 * r("gh")
            o.rec(R_PANEL, P, Y, IDX["grille"], h0=top, h1=top + gh, tint=gc, flags=F_VFULL | F_CUT)
            o.rec(R_POSTS, P, Y, IDX["metal"], h0=top, h1=gh, w=0.06, tint=gc, extra=2.5)
            top += gh
        elif style == "muret_rigide":
            gc = col(COLORS[pick(key, "g", [("vert", 3), ("anthracite", 3), ("gris", 1)])], 0.7)
            hp = 1.0 + 0.25 * r("gh")
            o.rec(R_PANEL, P, Y, IDX["grillage_rigide"], h0=top, h1=top + hp, tint=gc, flags=F_CUT)
            o.rec(R_POSTS, P, Y, IDX["metal"], h0=top, h1=hp, w=0.06, tint=gc, extra=2.5)
            top += hp
        o.rec(R_COLL, P, Y, h1=min(top, 1.5))
        return
    if style in ("rigide", "losange"):
        gc = col(COLORS[opts.get("couleur") or pick(key, "c", [("vert", 4), ("anthracite", 3), ("galva", 1 if style == "losange" else 0.2)])], 0.7)
        h = {"rigide": [1.23, 1.53, 1.73][int(r("h") * 3)], "losange": 1.0 + 0.5 * r("h")}[style]
        o.rec(R_PANEL, P, Y, IDX["grillage_" + style], h0=0.03, h1=h, tint=gc, flags=F_CUT)
        o.rec(R_POSTS, P, Y, IDX["metal"], h0=-0.2, h1=h + 0.25, w=0.06 if style == "rigide" else 0.045, tint=gc, extra=2.5)
        o.rec(R_COLL, P, Y, h1=h)
        return
    if style in ("occult", "bois"):
        if style == "occult":
            c = col(COLORS[pick(key, "c", [("anthracite", 4), ("gris", 2), ("brun", 1)])], 0.8); lay = IDX["occultant"]
        else:
            c = col((205, 190, 175), 0.67); lay = IDX["bois"]
        h = 1.6 + 0.3 * r("h")
        o.rec(R_PANEL, P, Y, lay, h0=0.03, h1=h, w=0.02, tint=c, flags=F_TWO)
        o.rec(R_POSTS, P, Y, IDX["metal"], h0=-0.2, h1=h + 0.25, w=0.09, tint=col(COLORS["anthracite"], 0.8), extra=1.8)
        o.rec(R_COLL, P, Y, h1=h)
        return
    if style == "lisses":
        c = col(COLORS["blanc"], 0.8)
        for hh in (0.35, 0.65, 0.95):
            o.rec(R_WALL, P, Y, IDX["metal"], h0=hh, h1=hh + 0.1, w=0.015, tint=c)
        o.rec(R_POSTS, P, Y, IDX["metal"], h0=-0.2, h1=1.3, w=0.1, tint=c, extra=2.0)
        o.rec(R_COLL, P, Y, h1=1.1)


GATES = []
CHECK = []          # (points 2D, demi-épaisseur) : contrôle « rien sur la route »


def gate(o, A, B, ya, yb, kind, key, pillar):
    """Portail entre A et B (2D) : deux piliers et deux vantaux fermés ; ou seulement des piliers (allée)."""
    GATES.append(dict(a=[round(float(A[0]), 1), round(float(A[1]), 1)], b=[round(float(B[0]), 1), round(float(B[1]), 1)], kind=kind))
    CHECK.append((np.array([A, B]), 0.3))
    d = B - A; L = np.linalg.norm(d); u = d / max(L, 1e-6)
    ph = 1.55 + 0.25 * rnd(key, "ph")
    pl, pt = pillar
    for p, y in ((A, ya), (B, yb)):
        o.rec(R_BOX, [p], [y], pl, h0=-0.3, h1=ph + 0.3, w=0.4, tint=pt, tint2=(u[0], u[1], 0), extra=0.4)
        o.rec(R_BOX, [p], [y], IDX["beton"], h0=ph, h1=0.07, w=0.48, tint=col((190, 188, 182), 0.76), tint2=(u[0], u[1], 0), extra=0.48)
    if kind is None:
        return
    a = A + u * 0.2; b = B - u * 0.2
    y0 = min(ya, yb)
    if kind in ("plein_blanc", "plein_gris", "bois", "lisses_blanc"):
        c = col({"plein_blanc": COLORS["blanc"], "plein_gris": COLORS["anthracite"], "bois": (150, 110, 80),
                 "lisses_blanc": COLORS["blanc"]}[kind], 0.85)
        lay = IDX["bois"] if kind == "bois" else IDX["portail_plein"]
        mid = (a + b) * 0.5
        for p0, p1 in ((a, mid), (mid, b)):
            o.rec(R_PANEL, [p0, p1], [y0, y0], lay, h0=0.05, h1=ph - 0.1, w=0.025, tint=c,
                  flags=F_TWO | F_FLAT | (F_VFULL if lay != IDX["bois"] else 0))
    else:
        c = col(COLORS["blanc"] if kind == "barreaux_blanc" else (COLORS["gris"] if kind == "ajoure_gris" else COLORS["noir"]), 0.75)
        o.rec(R_PANEL, [a, b], [y0, y0], IDX["grille"], h0=0.05, h1=ph - 0.1, tint=c, flags=F_CUT | F_VFULL | F_FLAT)
    o.rec(R_COLL, [A, B], [ya, yb], h1=1.4)


# ------------------------------------------------------------------------------------------------ principal
def sample(line, step=2.0):
    g = shapely.segmentize(line, step)
    P = np.asarray(g.coords)[:, :2]
    keep = np.r_[True, np.linalg.norm(np.diff(P, axis=0), axis=1) > 0.05]
    return P[keep]


def chunks(line, maxlen=60.0):
    L = line.length
    if L <= maxlen:
        return [line]
    n = int(math.ceil(L / maxlen))
    return [substring(line, L * k / n, L * (k + 1) / n) for k in range(n)]


def main():
    shutil.rmtree(OUT, ignore_errors=True); os.makedirs(OUT)
    json.dump({"scale": [SCALE[n] for n in sorted(IDX, key=IDX.get)]}, open(OUT + "/meta.json", "w"))
    plan = json.load(open("data/routes_plan.json"))
    zone_play = Polygon(plan["zone"]).buffer(150)
    dem = Carved()
    # emprise interdite : chaussée + trottoir + 0,5 m (allées privées à part : on n'y longe rien)
    ways = pickle.load(open("data/roads.pkl", "rb"))["ways"]
    main_z, drive_z = [], []
    for w in ways:
        if len(w["P"]) < 2:
            continue
        b = LineString(w["P"]).buffer(w["w"] / 2 + (1.6 if any(w["sidewalk"]) else 0.0) + 0.5)
        (drive_z if w["tags"].get("service") in DRIVE else main_z).append(b)
    MAIN, DRV, ALL = Local(main_z), Local(drive_z), Local(main_z + drive_z)
    print("emprise des routes prête")
    # bâtiments
    blds = load_buildings()
    bpolys = [g for _, g in blds]
    btree = STRtree(bpolys)
    survey = json.load(open("clotures_bourg.json"))
    # parcelles habitées
    parcels = load_parcels()
    ptree = STRtree([g for _, g in parcels])
    owner = {}                      # index parcelle -> (bâtiment principal, propriétés)
    nres = Counter()
    for props, g in blds:
        if props.get("construction_legere"):
            continue
        u = props.get("usage_1"); u2 = props.get("usage_2")
        if not (u in ("Résidentiel", "Indifférencié") or u2 == "Résidentiel"):
            continue
        if not (30 <= g.area <= 600):
            continue
        rp = g.representative_point()
        for k in ptree.query(rp, predicate="within"):
            pa = parcels[k][1]
            if pa.area > 5000:
                continue
            nres[k] += 1
            if k not in owner or owner[k][0].area < g.area:
                owner[k] = (g, props)
    owner = {k: v for k, v in owner.items() if nres[k] <= 6 and parcels[k][1].intersects(zone_play)}
    print(len(parcels), "parcelles,", len(owner), "habitées")
    # parcelles privées de l'emprise des routes
    keys = sorted(owner)
    clipped = {}
    for k in keys:
        pc = ALL.cut(parcels[k][1])
        ps = [p for p in polys_of(pc) if p.area > 20]
        if ps:
            clipped[k] = MultiPolygon(ps) if len(ps) > 1 else ps[0]
    keys = sorted(clipped)
    ctree = STRtree([clipped[k] for k in keys])
    # morceaux de limite (noeuds aux croisements, limites mitoyennes fusionnées)
    edges = unary_union([LineString(p.exterior.coords) for k in keys for p in polys_of(clipped[k])])
    pieces = lines_of(edges)
    print(len(pieces), "morceaux de limite")
    osm_lines, osm_gates = load_osm()
    haies = [to_local_geom(shape(f["geometry"])) for f in json.load(open("data/haies.json"))["features"]]
    hedge_lines = haies + [l for l, _ in osm_lines["hedge"]]
    hedge_needle = [False] * len(haies) + [n for _, n in osm_lines["hedge"]]
    htree = STRtree(hedge_lines)
    wtree = STRtree([l for l, _ in osm_lines["wall"]]) if osm_lines["wall"] else None
    ftree = STRtree([l for l, _ in osm_lines["fence"]]) if osm_lines["fence"] else None
    used_hedge = set()

    def near(tree, g, d=2.5):
        if tree is None:
            return []
        return list(tree.query(g, predicate="dwithin", distance=d))

    def side_of(pt):
        for i in ctree.query(pt, predicate="within"):
            return keys[i]
        return None

    # classement des morceaux
    groups = defaultdict(list)          # (classe, propriétaire(s)) -> [lignes]
    for ln in pieces:
        if ln.length < 0.5:
            continue
        mid = ln.interpolate(0.5, normalized=True)
        a = np.asarray(ln.interpolate(max(0, ln.length * 0.5 - 0.2)).coords[0])
        b = np.asarray(ln.interpolate(min(ln.length, ln.length * 0.5 + 0.2)).coords[0])
        t = (b - a) / max(np.linalg.norm(b - a), 1e-6); n = np.array([-t[1], t[0]])
        m = np.asarray(mid.coords[0])
        L = side_of(Point(m + n * 0.3)); R = side_of(Point(m - n * 0.3))
        if L is None and R is None:
            continue
        dmain = MAIN.dist(mid); ddrive = DRV.dist(mid)
        if L is not None and R is not None and L != R:
            groups[("side", min(L, R), max(L, R))].append(ln)
        elif ddrive < 0.6 and ddrive <= dmain:
            continue                                   # le long d'une allée privée : rien
        elif dmain < 3.0:
            groups[("front", L if L is not None else R)].append(ln)
        else:
            groups[("back", L if L is not None else R)].append(ln)
    print(Counter(k[0] for k in groups))

    # style de chaque limite
    tiles = defaultdict(Out)
    stats = Counter()
    gate_count = 0
    front_lines = defaultdict(list)

    def place(lines, style, key, opts, inward_of=None):
        nonlocal stats
        if style == "rien":
            return []
        out = []
        for ln in lines:
            # pas dans les bâtiments (une annexe sur la limite fait office de mur)
            bs = [bpolys[i] for i in btree.query(ln.buffer(0.3))]
            if bs:
                ln = ln.difference(unary_union(bs).buffer(0.15))
            for l in lines_of(ln):
                # recul dans la parcelle (haies, murs côté rue)
                if inward_of is not None and style in HALF:
                    dd = HALF[style]
                    best = None
                    for sgn in (1, -1):
                        oc = l.offset_curve(dd * sgn, join_style=2)
                        for l2 in lines_of(oc):
                            if clipped[inward_of].distance(l2.interpolate(0.5, normalized=True)) < 0.02:
                                best = l2
                    l = best
                    if l is None:
                        continue
                # dernière garde : rien dans l'emprise des routes
                l = ALL.cut(l, HALF.get(style, 0.1))
                for l2 in lines_of(l):
                    if l2.length >= 0.8:
                        out.append(l2)
        return out

    def emit(lines, style, key, opts):
        for l in lines:
            for c in chunks(l):
                P = sample(c)
                if len(P) < 2:
                    continue
                Y = dem.h(P[:, 0], P[:, 1])
                m = P.mean(0)
                tk = (int(math.floor(m[0] / TILE)), int(math.floor(m[1] / TILE)))
                build_line(tiles[tk], P, Y, style, key, opts)
                stats[style] += c.length

    def hedge_near(lines):
        ids = set()
        for l in lines:
            for i in near(htree, l):
                if hedge_lines[i].distance(l.interpolate(0.5, normalized=True)) < 2.5:
                    ids.add(i)
        return ids

    for gi, (gk, lines) in enumerate(groups.items()):
        if gi % 3000 == 0:
            print("limites", gi, "/", len(groups))
        merged = lines_of(linemerge(lines)) if len(lines) > 1 else lines
        if gk[0] == "front":
            k = gk[1]
            g, props = owner[k]
            sv = survey.get(props.get("cleabs"))
            hn = hedge_near(merged)
            if sv:
                style = SURVEY.get(sv["front"], "rien"); opts = {"mur": sv.get("mur") if sv.get("mur") in WALL or sv.get("mur") == "pierre" else None,
                                                                "grille": sv.get("grille") if sv.get("grille") in COLORS else None}
                stats["relevé"] += 1
            elif hn:
                style = "haie_thuya" if any(hedge_needle[i] for i in hn) else pick(k, "hf", [("haie_laurier", 3), ("haie_thuya", 2)])
                opts = {}; used_hedge.update(hn)
            elif any(near(wtree, l) for l in merged):
                style = "mur"; opts = {}
            elif any(near(ftree, l) for l in merged):
                style = "rigide"; opts = {}
            else:
                style = pick(k, "front", FRONT_MIX); opts = {}
            fl = place(merged, style, k, opts, inward_of=k)
            front_lines[k] = (fl, style, sv)
        elif gk[0] == "side":
            k = (gk[1], gk[2])
            hn = hedge_near(merged)
            style = pick(str(k), "side", SIDE_MIX) if not hn else "haie_laurier"
            used_hedge.update(hn)
            emit(place(merged, style, k, {}), style, k, {})
        else:
            k = gk[1]
            hn = hedge_near(merged)
            style = pick(k, "back", BACK_MIX) if not hn else pick(k, "bh", [("haie_champetre", 2), ("haie_laurier", 1)])
            used_hedge.update(hn)
            emit(place(merged, style, ("b", k), {}), style, ("b", k), {})

    # façades + portails
    for k, (fl, style, sv) in front_lines.items():
        if not fl:
            continue
        g, props = owner[k]
        pillar_wall = (sv or {}).get("mur") or pick(k, "mur", [("creme", 3), ("gris", 5), ("pierre", 1), ("blanc", 1)])
        pillar = (IDX["pierre"], col((200, 190, 175), 0.85)) if pillar_wall == "pierre" else (IDX["crepi"], col(WALL.get(pillar_wall, WALL["gris"]), 0.86))
        has_drive = bool(DRV.near(parcels[k][1], 1.0))
        lines = sorted(fl, key=lambda l: -l.length)
        kind = None
        if style != "rien" and not has_drive and lines[0].length >= 6.0:
            ln = lines[0]
            # portail OSM sur cette façade, sinon face à la maison
            t = None
            if len(osm_gates):
                d = np.hypot(osm_gates[:, 0] - ln.centroid.x, osm_gates[:, 1] - ln.centroid.y)
                for gi in np.argsort(d)[:5]:
                    p = Point(osm_gates[gi])
                    if ln.distance(p) < 2.5:
                        t = ln.project(p); break
            wdt = 3.2 + 0.8 * (rnd(k, "pw") < 0.3)
            if t is None:
                # face à la maison, mais avec un passage libre derrière (5 m sans bâtiment, dans la parcelle)
                t0 = ln.project(g.centroid)
                best = None
                for tc in np.arange(wdt / 2 + 1.0, ln.length - wdt / 2 - 1.0 + 1e-6, 0.5):
                    p0 = np.asarray(ln.interpolate(tc).coords[0])
                    p1 = np.asarray(ln.interpolate(min(ln.length, tc + 0.3)).coords[0]) - np.asarray(ln.interpolate(max(0, tc - 0.3)).coords[0])
                    nn = np.array([-p1[1], p1[0]]) / max(np.linalg.norm(p1), 1e-6)
                    if clipped[k].distance(Point(p0 + nn * 1.0)) > clipped[k].distance(Point(p0 - nn * 1.0)):
                        nn = -nn
                    corridor = LineString([p0, p0 + nn * 5.0]).buffer(wdt / 2)
                    if any(bpolys[i].intersects(corridor) for i in btree.query(corridor)):
                        continue
                    sc_ = abs(tc - t0)
                    if best is None or sc_ < best[0]:
                        best = (sc_, tc)
                t = best[1] if best else None
            if t is not None:
                t = float(np.clip(t, wdt / 2 + 1.0, ln.length - wdt / 2 - 1.0))
        if style != "rien" and not has_drive and lines[0].length >= 6.0 and t is not None:
            gate_kind = (sv or {}).get("portail") or pick(k, "portail", [("fer", 3), ("barreaux_blanc", 2), ("plein_gris", 2), ("plein_blanc", 2), ("bois", 1), (None, 2)])
            A = np.asarray(ln.interpolate(t - wdt / 2).coords[0]); B = np.asarray(ln.interpolate(t + wdt / 2).coords[0])
            ya, yb = dem.h(np.array([A[0], B[0]]), np.array([A[1], B[1]]))
            tk = (int(math.floor(A[0] / TILE)), int(math.floor(A[1] / TILE)))
            if not style.startswith("haie_") or gate_kind:
                gate(tiles[tk], A, B, ya, yb, gate_kind, k, pillar)
            gate_count += 1
            rest = [substring(ln, 0, t - wdt / 2 - 0.2), substring(ln, t + wdt / 2 + 0.2, ln.length)]
            lines = [l for l in rest if l.length > 0.8] + lines[1:]
        emit(lines, style, k, {"mur": sv.get("mur") if sv and (sv.get("mur") in WALL or sv.get("mur") == "pierre") else None,
                               "grille": sv.get("grille") if sv and sv.get("grille") in COLORS else None})
    print("portails", gate_count)

    # haies champêtres : hors des propriétés, hors des routes, hauteur LiDAR
    mnh = {}
    def mnh_at(P):
        out = []
        for x, z in P:
            i, j = int(math.floor(x / REG)), int(math.floor(z / REG))
            if (i, j) not in mnh:
                p = "data/mnh/r_%d_%d.npy" % (i, j)
                mnh[(i, j)] = np.load(p) if os.path.exists(p) else None
            a = mnh[(i, j)]
            out.append(0.0 if a is None else a[int(z - j * REG) % 1024, int(x - i * REG) % 1024] / 8.0)
        return np.array(out)
    PROP = Local([clipped[k] for k in keys])
    nrural = 0
    for i, hl in enumerate(hedge_lines):
        if i in used_hedge or not zone_play.intersects(hl):
            continue
        l = hl
        l = PROP.cut(l, 1.0)
        l = ALL.cut(l, 0.9)
        # bâtiments
        for l2 in lines_of(l):
            if l2.length < 4:
                continue
            bs = [bpolys[b] for b in btree.query(l2.buffer(1.0))]
            if bs:
                l2 = l2.difference(unary_union(bs).buffer(1.0))
            for l3 in lines_of(l2):
                if l3.length < 4:
                    continue
                for c in chunks(l3):
                    P = sample(c, 2.5)
                    if len(P) < 2:
                        continue
                    hm = mnh_at(P[:: max(1, len(P) // 6)])
                    h = float(np.clip(np.median(hm) if len(hm) else 1.8, 1.4, 3.0))
                    Y = dem.h(P[:, 0], P[:, 1])
                    m = P.mean(0)
                    tk = (int(math.floor(m[0] / TILE)), int(math.floor(m[1] / TILE)))
                    style = "haie_thuya" if hedge_needle[i] else "haie_champetre"
                    build_line(tiles[tk], P, Y, style, ("r", i), {"h": h, "w": 1.4 + 0.6 * rnd(i, "w") if style == "haie_champetre" else None})
                    stats["champêtre"] += c.length
                    nrural += 1
    print("haies champêtres :", nrural, "tronçons")

    # contrôle : aucun point de clôture (épaisseur comprise) sur la chaussée ou le trottoir
    raw = Local([LineString(w["P"]).buffer(w["w"] / 2 + (1.6 if any(w["sidewalk"]) else 0.0))
                 for w in ways if len(w["P"]) > 1 and w["tags"].get("service") not in DRIVE])
    bad = 0; tot = 0
    for P, half in CHECK:
        for p in P:
            tot += 1
            if raw.near(Point(p), half - 0.02):
                bad += 1
    print("contrôle route : %d points sur %d dans l'emprise (chaussée + trottoir)" % (bad, tot))
    json.dump(GATES, open("data/fences_gates.json", "w"))
    # écriture
    nv = 0
    for (tx, tz), o in tiles.items():
        if o.recs:
            b = o.bytes(); nv += len(b)
            open("%s/f_%d_%d.bin" % (OUT, tx, tz), "wb").write(b)
    print(len(tiles), "tuiles, %.1f Mo" % (nv / 1e6))
    print({k: (round(v / 1000, 1) if isinstance(v, float) else v) for k, v in stats.items()}, "(km)")


if __name__ == "__main__":
    main()
