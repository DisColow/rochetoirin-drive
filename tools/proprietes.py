"""Propriétés redessinées à la main, une par une (rue du Balcon), d'après la photo aérienne IGN puis Street View.

Chaque propriété est décrite dans tools/proprietes/<id>.json (repère local, x Est, z Sud) :
  contour      limites réellement visibles (haies, murets, clôtures) — pas le cadastre ;
  batiments    maison BD TOPO (cleabs) redressée : toit, hauteur à l'égout, pente, couleurs, façades percées ;
  portails     portail entre deux piliers (+ portillon, boîte aux lettres) ;
  clotures     polylignes : muret_grillage, muret_haie, haie, grillage, muret ;
  sols         polygones : paves, gravier, beton, enrobe, terrasse ;
  arbres       position + essence (leyland, cypres, epicea, boule, fruitier, feuillu, laurier) ;
  objets       puits décoratif… ; voitures garées.
À l'intérieur du contour, le décor automatique (clôtures du cadastre, haies et arbres détectés sur la photo, cours,
piscines, portails, voitures) est supprimé : seule la description fait foi.
"""
import glob, json, math, os
import numpy as np
from shapely.geometry import LineString, Point, Polygon
from shapely.ops import unary_union

HERE = os.path.dirname(os.path.abspath(__file__))
_P = None
_Z = None

# matériaux (même numérotation que prepare_quartier)
(M_PLAIN, M_WALL, M_INDUS, M_TILES, M_METAL, M_FLAT, M_WATER, M_CHURCH, M_STEEL, M_CABLE, M_GLASS,
 M_STREAM, M_PAVE, M_CURB, M_GRASS, M_SIGN, M_LIGHT, M_RUBBLE, M_CREPI, M_HEDGE, M_GRAVEL, M_MESH) = range(22)
# types d'arbres (prepare_decor / Decor.kt) ; imposteurs : 6 + modèle + rayon / hauteur / 2
T_OAK, T_BUSH, T_POPLAR, T_CONIFER, T_FRUIT, T_SHRUB = range(6)
SOLS = {"paves": ((0.62, 0.61, 0.58), M_PAVE), "gravier": ((0.80, 0.76, 0.66), M_GRAVEL),
        "beton": ((0.70, 0.69, 0.66), M_PAVE), "enrobe": ((0.36, 0.36, 0.37), M_PAVE),
        "terrasse": ((0.80, 0.68, 0.60), M_PAVE)}


def all_():
    global _P
    if _P is None:
        _P = []
        for f in sorted(glob.glob(os.path.join(HERE, "proprietes", "*.json"))):
            d = json.load(open(f))
            d["poly"] = Polygon(d["contour"]).buffer(0)
            _P.append(d)
    return _P


def zone(margin=0.3):
    """Union des contours (élargis de margin) : le décor automatique s'arrête là."""
    global _Z
    if _Z is None:
        ps = [d["poly"].buffer(margin, join_style=2) for d in all_()]
        _Z = unary_union(ps) if ps else Polygon()
        import shapely
        shapely.prepare(_Z)
    return _Z


def contains(x, z):
    Z = zone()
    return not Z.is_empty and Z.contains(Point(x, z))


def parcelles(parcels):
    """idu des parcelles cadastrales couvertes par une propriété redessinée (> 40 % de leur aire ou > 150 m²)."""
    out = set()
    Z = zone(0.0)
    if Z.is_empty:
        return out
    for pid, p in parcels:
        if not p.intersects(Z):
            continue
        a = p.intersection(Z).area
        if a > 0.4 * p.area or a > 150:
            out.add(pid)
    return out


def batiment(cleabs):
    for d in all_():
        for b in d.get("batiments", []):
            if b.get("cleabs") == cleabs:
                return b
    return None


def arbres():
    """[(x, z, type, hauteur)] au format de prepare_decor.trees."""
    out = []
    for d in all_():
        for a in d.get("arbres", []):
            x, z = a["pos"]
            h = float(a["h"])
            t = a["type"]
            if t in MASSIFS:              # conifères denses : maillages (cf. massif), pas des arbres instanciés
                continue
            elif t == "fruitier":
                out.append((x, z, T_FRUIT, h))
            elif t == "laurier":
                r = float(a.get("r", 1.5))
                out.append((x, z, 6 + 4 + min(0.49, r / h / 2), h))
            else:                         # feuillu : modèle 3D (imposteur)
                r = float(a.get("r", h * 0.35))
                model = int(abs(hash((round(x), round(z)))) % 2)
                out.append((x, z, 6 + model + min(0.49, r / h / 2), h))
    return out


# conifères denses (Street View : masses de feuillage jusqu'au sol, aucun tronc visible)
# essence : (rayon / hauteur par défaut, couleur, profil)
MASSIFS = {"leyland": (0.30, (0.12, 0.23, 0.08), "leyland"), "cypres": (0.12, (0.11, 0.21, 0.08), "colonne"),
           "epicea": (0.33, (0.25, 0.34, 0.33), "cone"), "boule": (0.48, (0.17, 0.29, 0.12), "boule"),
           "thuya": (0.25, (0.15, 0.27, 0.12), "leyland")}


def _profil(kind, t):
    if kind == "colonne":                     # cyprès : colonne à pointe arrondie
        return max(0.0, (1 - t ** 3)) ** 0.5 * (0.85 + 0.15 * (1 - t))
    if kind == "cone":                        # épicéa : cône depuis le sol
        return max(0.0, 1.0 - t) * 0.95 + 0.05 * (t < 0.98)
    if kind == "boule":
        return max(0.0, 1 - (2 * t - 1) ** 2) ** 0.5 * 0.95 + 0.05
    # leyland : base pleine, plus large au quart, puis effilé et arrondi
    if t < 0.25:
        return 0.82 + 0.18 * t / 0.25
    return max(0.0, 1 - ((t - 0.25) / 0.75) ** 1.6) ** 0.8


def massif(m, x, y, z, h, r, col, kind, seed, mat):
    """Volume de feuillage dense (surface de révolution bosselée) ; matériau haie (texture de thuya)."""
    rs = np.random.RandomState(seed)
    ph = rs.uniform(0, 6.283, 6)
    nt, ny = 24, max(8, int(h / 0.45))
    P = np.zeros((ny + 1, nt, 3))
    lump = rs.uniform(-1, 1, (ny + 1, nt))                  # touffes : bruit lissé
    for _ in range(2):
        lump = 0.5 * lump + 0.125 * (np.roll(lump, 1, 1) + np.roll(lump, -1, 1) + np.roll(lump, 1, 0) + np.roll(lump, -1, 0))
    lump /= max(np.abs(lump).max(), 1e-6)
    sway = rs.uniform(-1, 1, 2) * r * 0.12                  # axe légèrement penché
    for j in range(ny + 1):
        t = j / ny
        yy = y - 0.25 + t * (h + 0.25)
        cx, cz = x + sway[0] * t, z + sway[1] * t
        for i in range(nt):
            th = 2 * math.pi * i / nt
            k = 1 + 0.14 * math.sin(3 * th + ph[0] + 9 * t) * math.sin(t * 7 + ph[1]) + 0.08 * math.sin(5 * th + ph[2] - 4 * t) \
                + 0.22 * lump[j, i] * (0.4 + 0.6 * min(1.0, t * 3))
            rr = r * _profil(kind, t) * max(0.3, k)
            P[j, i] = (cx + rr * math.cos(th), yy, cz + rr * math.sin(th))
    ids = np.zeros((ny + 1, nt), int)
    for j in range(ny + 1):
        for i in range(nt):
            a = P[min(ny, j + 1), i] - P[max(0, j - 1), i]
            b = P[j, (i + 1) % nt] - P[j, (i - 1) % nt]
            n = np.cross(a, b)
            if np.dot(n, P[j, i] - np.array([x, P[j, i][1], z])) < 0:
                n = -n
            if j == ny:
                n = np.array([0, 1.0, 0])
            n = n / max(np.linalg.norm(n), 1e-9)
            th = 2 * math.pi * i / nt
            ids[j, i] = m.vert(tuple(P[j, i]), tuple(n), col, (th * max(r, 0.5), P[j, i][1] - y), mat)
    for j in range(ny):
        for i in range(nt):
            m.quad(ids[j, i], ids[j, (i + 1) % nt], ids[j + 1, (i + 1) % nt], ids[j + 1, i])


def surfaces_dures():
    """Polygones des sols durs (pas d'herbe 3D dessus)."""
    return [Polygon(s["pts"]).buffer(0) for d in all_() for s in d.get("sols", [])]


# ------------------------------------------------------------------------------------------------- construction
def build(Mesh, obox, quad3, add, add_coll, H, parked_car=None, prism=None):
    """Clôtures, haies, portails, sols, objets et voitures de toutes les propriétés. Renvoie des statistiques."""
    import sidewalks as swm
    stats = {}
    carr = None
    sp = os.path.join(HERE, "data", "surfaces.pkl")
    if os.path.exists(sp):
        import pickle
        S = pickle.load(open(sp, "rb"))
        carr = unary_union([S["carr_ext"], S["walk"]])

    def count(k, n=1):
        stats[k] = stats.get(k, 0) + n

    def seg_iter(pts, step=2.0):
        """Tronçons d'au plus step m : chaque panneau suit le terrain (murets en escalier dans les pentes)."""
        for a, b in zip(pts[:-1], pts[1:]):
            a, b = np.array(a, float), np.array(b, float)
            L = float(np.linalg.norm(b - a))
            if L <= 0.05:
                continue
            n = max(1, int(math.ceil(L / step)))
            for k in range(n):
                a_, b_ = a + (b - a) * k / n, a + (b - a) * (k + 1) / n
                yield a_, b_, L / n, (b - a) / L

    for d in all_():
        poly = d["poly"]

        def inward(a, b):
            """Normale horizontale pointant vers l'intérieur de la propriété."""
            dd = (b - a) / max(np.linalg.norm(b - a), 1e-9)
            n = np.array([-dd[1], dd[0]])
            mid = (a + b) / 2
            return n if poly.contains(Point(mid + n * 1.0)) or poly.distance(Point(mid + n * 1.0)) < poly.distance(Point(mid - n * 1.0)) else -n

        # ---------------------------------------------------------------- clôtures, murets, haies
        for c in d.get("clotures", []):
            kind = c["type"]
            for a, b, L, dd in seg_iter(c["pts"]):
                m = Mesh()
                mid = (a + b) / 2
                y = min(H(*a), H(*b))
                n_in = inward(a, b)
                hm = float(c.get("h_mur", 0.0)) if kind != "haie" else 0.0
                wcol = tuple(c.get("mur", (0.72, 0.71, 0.67)))
                if hm > 0:
                    # muret en béton (panneaux), enterré de 0,3 m, chaperon
                    obox(m, (mid[0], y + (hm - 0.3) / 2, mid[1]), dd, (L + 0.04, hm + 0.3, 0.18), wcol, M_CREPI)
                    obox(m, (mid[0], y + hm + 0.025, mid[1]), dd, (L + 0.06, 0.05, 0.22), tuple(v * 0.95 for v in wcol), M_CURB)
                    for t in np.arange(0.0, L + 0.01, 2.0):          # joints des panneaux
                        pp = a + dd * min(t, L)
                        obox(m, (pp[0], y + hm / 2 - 0.1, pp[1]), dd, (0.03, hm + 0.1, 0.20), tuple(v * 0.85 for v in wcol), M_PLAIN)
                top = y + hm
                if kind == "muret_grillage":
                    h = float(c.get("h", 1.1))
                    gcol = tuple(c.get("grillage", (0.42, 0.47, 0.42)))
                    p0 = np.array([a[0], top, a[1]]); p1 = np.array([b[0], top, b[1]])
                    quad3(m, p0, p1, p1 + [0, h, 0], p0 + [0, h, 0], gcol, M_MESH, [(0, 0), (L, 0), (L, h), (0, h)], 3.0,
                          n=(n_in[0], 0, n_in[1]))
                    for t in np.arange(0.0, L + 0.01, 2.5):          # poteaux béton
                        pp = a + dd * min(t, L)
                        obox(m, (pp[0], top + (h + 0.1) / 2, pp[1]), dd, (0.10, h + 0.1, 0.10), (0.74, 0.73, 0.70), M_PLAIN)
                    obox(m, (mid[0], top + h, mid[1]), dd, (L, 0.03, 0.03), gcol, M_STEEL)       # fil de tension
                    count("grillages sur muret (m)", L)
                elif kind == "muret_haie":
                    h = float(c.get("h", 1.0)); ep = float(c.get("ep", 0.8))
                    col = tuple(c.get("haie", (0.47, 0.55, 0.27)))
                    cc = mid + n_in * (ep / 2 - 0.05)
                    obox(m, (cc[0], top + h / 2 - 0.05, cc[1]), dd, (L + 0.1, h + 0.1, ep), col, M_HEDGE + 0.7)
                    count("haies sur muret (m)", L)
                    nn = n_in * ep
                    add_coll(np.array([a, b, b + nn, a + nn]))
                elif kind == "haie":
                    h = float(c.get("h", 2.0)); ep = float(c.get("ep", 1.2))
                    col = tuple(c.get("haie", (0.15, 0.27, 0.13)))
                    thuja = c.get("essence", "thuya") == "thuya"
                    cc = mid + n_in * (ep / 2)
                    obox(m, (cc[0], y + h / 2 - 0.2, cc[1]), dd, (L + ep * 0.6, h + 0.4, ep), col, M_HEDGE + (0.2 if thuja else 0.7))
                    count("haies (m)", L)
                    nn = n_in * ep
                    add_coll(np.array([a, b, b + nn, a + nn]))
                elif kind == "grillage":
                    h = float(c.get("h", 1.3))
                    gcol = tuple(c.get("grillage", (0.42, 0.47, 0.42)))
                    p0 = np.array([a[0], y - 0.05, a[1]]); p1 = np.array([b[0], y - 0.05, b[1]])
                    quad3(m, p0, p1, p1 + [0, h, 0], p0 + [0, h, 0], gcol, M_MESH, [(0, 0), (L, 0), (L, h), (0, h)], 3.0,
                          n=(n_in[0], 0, n_in[1]))
                    for t in np.arange(0.0, L + 0.01, 2.5):
                        pp = a + dd * min(t, L)
                        obox(m, (pp[0], y + h / 2, pp[1]), dd, (0.06, h + 0.1, 0.06), gcol, M_STEEL)
                    count("grillages (m)", L)
                else:
                    count("murets (m)", L)
                if kind != "muret_haie" and kind != "haie":
                    nn = n_in * 0.2
                    add_coll(np.array([a, b, b + nn, a + nn]))
                add(mid[0], mid[1], m, False)

        # ---------------------------------------------------------------- portails
        for g in d.get("portails", []):
            m = Mesh()
            a, b = np.array(g["a"], float), np.array(g["b"], float)
            W = float(np.linalg.norm(b - a)); dd = (b - a) / W
            n_in = inward(a, b)
            pc = tuple(g.get("piliers", (0.80, 0.73, 0.60))); hp = float(g.get("h_piliers", 1.75))
            gc = tuple(g.get("couleur", (0.15, 0.16, 0.17))); hg = float(g.get("h", 1.45))
            pil = [a, b]
            port = float(g.get("portillon", 0.0))
            if port > 0:
                pil.append(b + dd * (port + 0.45))
            for pp in pil:                                              # piliers en pierre reconstituée
                yy = H(*pp)
                obox(m, (pp[0], yy + hp / 2 - 0.2, pp[1]), dd, (0.45, hp + 0.4, 0.45), pc, M_RUBBLE)
                obox(m, (pp[0], yy + hp + 0.04, pp[1]), dd, (0.55, 0.08, 0.55), tuple(v * 0.92 for v in pc), M_CURB)
                add_coll(np.array([pp - dd * 0.23 - n_in * 0.23, pp + dd * 0.23 - n_in * 0.23, pp + dd * 0.23 + n_in * 0.23, pp - dd * 0.23 + n_in * 0.23]))

            def leaf(p0, p1):
                """Vantail : soubassement plein à deux bandes + barreaudage, montants et traverse."""
                L = float(np.linalg.norm(p1 - p0)); u = (p1 - p0) / max(L, 1e-6)
                c_ = (p0 + p1) / 2
                y0 = min(H(*p0), H(*p1)) + 0.06
                obox(m, (c_[0], y0 + 0.22, c_[1]), u, (L, 0.44, 0.04), gc, M_STEEL)
                obox(m, (c_[0], y0 + 0.24, c_[1]), u, (L * 0.96, 0.03, 0.05), tuple(v * 0.7 for v in gc), M_STEEL)
                q0 = np.array([p0[0], y0 + 0.44, p0[1]]); q1 = np.array([p1[0], y0 + 0.44, p1[1]])
                quad3(m, q0, q1, q1 + [0, hg - 0.44, 0], q0 + [0, hg - 0.44, 0], gc, M_MESH,
                      [(0, 0), (L, 0), (L, hg - 0.44), (0, hg - 0.44)], 1.0, n=(n_in[0], 0, n_in[1]))
                obox(m, (c_[0], y0 + hg, c_[1]), u, (L, 0.05, 0.05), gc, M_STEEL)
                obox(m, (c_[0], y0 + 0.9, c_[1]), u, (L, 0.04, 0.04), gc, M_STEEL)
                for pp in (p0, p1):
                    obox(m, (pp[0], y0 + hg / 2, pp[1]), u, (0.06, hg, 0.06), gc, M_STEEL)

            a_ = a + dd * 0.25; b_ = b - dd * 0.25
            mid = (a_ + b_) / 2
            leaf(a_, mid - dd * 0.01); leaf(mid + dd * 0.01, b_)
            if port > 0:
                leaf(b + dd * 0.25, b + dd * (port + 0.2))
            if g.get("boite"):                                          # boîte aux lettres sur le pilier droit, côté rue
                pp = b - n_in * 0.29
                obox(m, (pp[0], H(*pp) + 1.15, pp[1]), dd, (0.36, 0.40, 0.14), (0.22, 0.23, 0.25), M_STEEL)
            add(a[0], a[1], m, False)
            # vantaux fermés : obstacle
            nn = n_in * 0.1
            add_coll(np.array([a, b, b + nn, a + nn]))
            count("portails")

        # ---------------------------------------------------------------- sols
        tiles = Mesh()
        for s in d.get("sols", []):
            col, mat = SOLS.get(s["type"], SOLS["gravier"])
            pg = Polygon(s["pts"]).buffer(0)
            if s.get("hors_chaussee") and carr is not None:
                pg = pg.difference(carr.buffer(0.05))
                pg = max(getattr(pg, "geoms", [pg]), key=lambda g: g.area) if not pg.is_empty else pg
            if pg.is_empty:
                continue
            v, tri = swm.tri_poly(pg, 2.0)
            if len(tri) == 0:
                continue
            v, tri = swm.subdivide(v, tri, 1.5)
            ids = [tiles.vert((float(x), H(x, z) + 0.04, float(z)), (0, 1, 0), col, (float(x), float(z)), mat) for x, z in v]
            for t in range(0, len(tri), 3):
                tiles.tri(ids[tri[t]], ids[tri[t + 1]], ids[tri[t + 2]])
            if s["type"] == "paves":
                # bordure de pavés rouges côté portail (Street View)
                pass
            count("sols : " + s["type"] + " (m²)", pg.area)
        if tiles.v:
            c = d["poly"].centroid
            add(c.x, c.y, tiles, True)

        # ---------------------------------------------------------------- conifères denses
        for k, a in enumerate(d.get("arbres", [])):
            if a["type"] not in MASSIFS:
                continue
            ratio, col, kind = MASSIFS[a["type"]]
            x, z = a["pos"]; h = float(a["h"]); r = float(a.get("r", ratio * h))
            sd = int(abs(x * 7919 + z * 104729)) % 100000
            jit = 0.92 + 0.16 * ((sd % 97) / 97)
            mm = Mesh()
            massif(mm, x, H(x, z), z, h, r, tuple(c_ * jit for c_ in col), kind, sd, M_HEDGE + 0.2)
            add(x, z, mm, False)
            rc = min(r * 0.6, 1.2)
            add_coll(np.array([[x - rc, z - rc], [x + rc, z - rc], [x + rc, z + rc], [x - rc, z + rc]]))
            count("conifères denses")

        # ---------------------------------------------------------------- objets
        for o in d.get("objets", []):
            if o["type"] == "puits" and prism is not None:
                m = Mesh()
                x, z = o["pos"]; y = H(x, z)
                prism(m, x, y - 0.2, y + 0.65, z, 0.55, 0.55, 12, (0.72, 0.66, 0.56), M_RUBBLE)
                prism(m, x, y + 0.6, y + 0.66, z, 0.6, 0.6, 12, (0.64, 0.60, 0.54), M_CURB)
                for s_ in (-1, 1):
                    obox(m, (x + s_ * 0.45, y + 0.95, z), (1, 0), (0.08, 1.3, 0.08), (0.40, 0.27, 0.16), M_PLAIN)
                # petit toit à deux pans (tuiles)
                for s_ in (-1, 1):
                    a3 = np.array([x - 0.6, y + 1.55, z]); b3 = np.array([x + 0.6, y + 1.55, z])
                    quad3(m, a3, b3, b3 + [0, -0.3, s_ * 0.45], a3 + [0, -0.3, s_ * 0.45], (0.55, 0.32, 0.24), M_TILES + 0.3)
                add(x, z, m, False)
                add_coll(np.array([[x - 0.6, z - 0.6], [x + 0.6, z - 0.6], [x + 0.6, z + 0.6], [x - 0.6, z + 0.6]]))
                count("objets")

        # ---------------------------------------------------------------- voitures
        if parked_car is not None:
            for k, v in enumerate(d.get("voitures", [])):
                x, z = v["pos"]
                hdg = math.radians(v.get("cap", 0.0))
                yaw = math.atan2(-math.cos(hdg), math.sin(hdg))
                cm_, ring = parked_car(x, z, yaw, tuple(v.get("couleur", (0.85, 0.85, 0.85))), 900 + k)
                add(x, z, cm_, False)
                add_coll(np.array(ring))
                count("voitures")
    return stats
