"""Rue du Balcon refaite d'après Street View (22 panoramas de juin 2022 et septembre 2014, tools/fetch_sv_street.py),
le cadastre (couloir public entre les parcelles) et l'orthophoto.

Constats (comparaison image par image, harnais WebGL aux mêmes caméras) :
- l'axe OSM est 2 à 3 m trop au nord : chaussée recalée sur la trace des caméras Street View de 2022 (partie est) et
  sur la limite cadastrale sud (partie ouest, panoramas de 2014 décalés), cf. AXE ;
- la rue se termine par une placette, d'où part au nord une courte impasse (3 portails) ; vers l'ouest, le couloir
  ne fait que 2,5 m : chemin piéton enrobé jusqu'à l'impasse du Balcon (pas de panorama : la voiture n'y passe pas) ;
- profil en travers : chaussée de 5 m ; caniveau central en béton dans la partie est (s < 100 m) ; trottoir à bordure
  côté sud ; côté nord, bande de gravier jusqu'aux murets (partie est) puis accotement enrobé (lotissement) ;
- clôtures relevées parcelle par parcelle (CLOTURES), lampadaires relevés (LAMPS).

Abscisse s : le long de AXE depuis le carrefour est. Côté +1 = nord (à droite en roulant vers l'ouest), -1 = sud.
"""
import numpy as np
from shapely.geometry import LineString, Point, Polygon, box
from shapely.ops import unary_union

NAME = "Rue du Balcon"
WIDTH = 5.0
# trace des caméras Street View (lissée, décalée de 0,7 m vers le sud)
AXE_SV = [[-261.1, 132.1], [-273.8, 124.0], [-283.9, 119.4], [-292.4, 113.8], [-300.6, 108.5], [-308.8, 103.2],
          [-317.1, 97.6], [-325.8, 91.7], [-334.6, 85.6], [-343.2, 79.7], [-351.7, 73.9], [-360.3, 68.3], [-369.0, 62.9],
          [-377.5, 57.6], [-385.4, 52.7], [-392.9, 48.1], [-403.5, 39.0]]
# axe retenu : trace SV pour la partie 2022 (s < 56 m) ; au-delà, les panoramas de 2014 sont décalés d'environ 2 m
# vers le sud (dérive GPS : le trottoir mordrait sur les parcelles) -> axe à 4,1 m de la limite cadastrale sud
# (trottoir 1,4 m + demi-chaussée 2,5 m + 0,2 m), raccord progressif entre s = 56 et 76 m
AXE = [[-261.1, 132.1], [-273.8, 124.0], [-283.9, 119.4], [-292.4, 113.8], [-300.6, 108.5], [-308.8, 103.2],
       [-316.6, 96.8], [-324.7, 90.1], [-333.4, 83.8], [-341.7, 77.6], [-350.1, 71.5], [-359.0, 66.2], [-367.8, 60.9],
       [-376.4, 55.8], [-384.4, 51.0], [-391.8, 46.6], [-402.2, 37.5]]
# impasse au nord de la placette (panoramas 2014 G5g_9Sh18R, yTnN0H_0Ed)
STUB = [[-402.2, 37.5], [-399.0, 29.0], [-393.5, 19.0]]
STUB_WIDTH = 4.5
PLACETTE = (-402.5, 37.5)
PLACETTE_R = 8.5
FOOTPATH_BOX = (-500.0, -16.0, -413.0, 40.0)      # partie étroite du couloir public : chemin piéton
SIDEWALK_SIDE = "left"                            # sens de AXE (est -> ouest) : gauche = sud
SIDEWALK_W = 1.4
GUTTER_END = 100.0                                # caniveau central en béton de s = 0 à s = 100 m
GRAVEL_END = 100.0                                # accotement nord en gravier, puis enrobé
# lampadaires relevés : (abscisse, côté)
LAMPS = [(4.0, -1), (38.0, -1), (73.0, -1), (108.0, 1), (150.0, 1)]

# clôtures côté rue, parcelle par parcelle (même vocabulaire que clotures_bourg.json ; « piquets » = grillage sur
# piquets bois ; « hmur » = hauteur du muret)
CLOTURES = {
    "383410000B1217": dict(front="haieT"),                                    # angle est, sud : thuyas
    "383410000B1212": dict(front="haieT"),
    "383410000B1633": dict(front="grillage", mur="gris", hmur=0.3),         # angle de la Sablière : pré clos
    "383410000B1637": dict(front="haieL", mur="gris", hmur=0.4),            # muret + laurier taillé bas
    "383410000B1632": dict(front="piquets", mur="gris", hmur=0.25),         # potager, friche en bord de rue
    "383410000B1640": dict(front="rien"),                                    # pré ouvert
    "383410000B1621": dict(front="muret", mur="gris", hmur=1.1, portail="plein_rouge"),
    "383410000B1727": dict(front="lisses", mur="blanc", grille="blanc", portail="barreaux_blanc"),
    "383410000B1728": dict(front="haieL", mur="blanc", hmur=0.5, grille="bois", portail="bois"),
    "383410000B1778": dict(front="haieL", mur="blanc", hmur=0.5, grille="bois", portail="plein_blanc"),
    "383410000B1725": dict(front="haieL", mur="blanc", hmur=0.4),           # 12 rue du Balcon
    "383410000B1724": dict(front="muret", mur="pierre", hmur=0.8, grille="noir", portail="fer"),
    "383410000B1716": dict(front="haieT", mur="gris", hmur=0.3),            # impasse du Balcon
    "383410000B1832": dict(front="grillage", mur="gris", hmur=0.15),
    "383410000B2188": dict(front="rien"),
    "383410000B1250": dict(front="rien"),
}
# style par défaut des parcelles non relevées du lotissement : haie de laurier sur muret blanc
DEFAULT = dict(front="haieL", mur="blanc", hmur=0.45)

_axis = None


def axis():
    global _axis
    if _axis is None:
        _axis = LineString(AXE)
    return _axis


def station(x, z):
    """(abscisse s, côté +1 nord / -1 sud, distance à l'axe)."""
    L = axis()
    p = Point(x, z)
    s = L.project(p)
    a = np.array(L.interpolate(max(0.0, s - 0.5)).coords[0]); b = np.array(L.interpolate(min(L.length, s + 0.5)).coords[0])
    d = b - a
    c = np.array(L.interpolate(s).coords[0])
    cross = d[0] * (z - c[1]) - d[1] * (x - c[0])
    return s, (1 if cross > 0 else -1), L.distance(p)


def at(s, off):
    """Point à l'abscisse s, décalé de off (positif = nord), et direction de l'axe."""
    L = axis()
    s = min(max(s, 0.0), L.length)
    a = np.array(L.interpolate(max(0.0, s - 0.5)).coords[0]); b = np.array(L.interpolate(min(L.length, s + 0.5)).coords[0])
    d = (b - a) / max(np.linalg.norm(b - a), 1e-6)
    left = np.array([d[1], -d[0]])                  # gauche du sens est -> ouest = sud
    c = np.array(L.interpolate(s).coords[0])
    return c - left * off, d


def apply_osm(nodes, ways, to_local=None):
    """Remplace le tracé OSM de la rue du Balcon par AXE (nœud du carrefour est conservé) et ajoute l'impasse nord."""
    target = [w for w in ways if w.get("name") == NAME and w["cls"] != "rail"]
    if not target:
        return ways
    w = max(target, key=lambda w_: len(w_["nodes"]))
    first = min(w["nodes"][:1] + w["nodes"][-1:], key=lambda n: np.hypot(nodes[n][0] - AXE[0][0], nodes[n][1] - AXE[0][1]))
    nid = [-7_700_000]

    def new(p):
        nid[0] -= 1
        nodes[nid[0]] = (float(p[0]), float(p[1]))
        return nid[0]

    ids = [first] + [new(p) for p in AXE[1:]]
    w["nodes"] = ids
    w["width"] = WIDTH
    w["tags"] = dict(w["tags"], sidewalk=SIDEWALK_SIDE)
    w["tags"]["sidewalk:width"] = str(SIDEWALK_W)
    for o in target:
        if o is not w:
            ways.remove(o)
    stub = dict(w)
    stub.update(id=w["id"] * 10 + 1, cls="residential", width=STUB_WIDTH, nodes=[ids[-1]] + [new(p) for p in STUB[1:]],
                tags=dict(highway="residential", name=NAME, sidewalk="no"))
    ways.append(stub)
    print("rue du Balcon : axe recalé d'après Street View (%d points) + impasse nord" % len(AXE))
    return ways


def public_corridor(parcels, bbox=(-560.0, -60.0, -240.0, 150.0)):
    """Couloir public (hors parcelles) autour de la rue."""
    pub = box(*bbox).difference(unary_union([p.buffer(0.05) for p in parcels]))
    parts = [g for g in getattr(pub, "geoms", [pub]) if g.geom_type == "Polygon"]
    hit = [g for g in parts if g.intersects(axis())]
    return unary_union(hit) if hit else None


def surfaces(parcels, hard):
    """Sols de la rue d'après le relevé : [(polygone, nature)] avec nature 1 gravier, 2 béton, 3 enrobé.
    hard = chaussée + trottoirs (déjà maillés ailleurs)."""
    corr = public_corridor(parcels)
    if corr is None:
        return []
    out = []
    rest = corr.difference(hard.buffer(0.02))
    # placette + impasse nord : enrobé de limite à limite
    plac = corr.intersection(Point(PLACETTE).buffer(PLACETTE_R).union(LineString(STUB).buffer(4.0))
                             .union(box(-418.0, 15.0, -392.0, 50.0)))
    # chemin piéton (couloir étroit vers l'impasse du Balcon)
    foot = corr.intersection(box(*FOOTPATH_BOX))
    for g in (plac, foot):
        g = g.difference(hard.buffer(0.02))
        g = _clean(g, corr, hard)
        if not g.is_empty:
            out.append((g, 3))
    rest = rest.difference(plac).difference(foot)
    # accotements : côté nord gravier (est) / enrobé (lotissement) ; côté sud herbe (pas de surface)
    L = axis()
    north_e, north_w = [], []
    for s0 in np.arange(0.0, L.length, 4.0):
        s1 = min(L.length, s0 + 4.0)
        a0, _ = at(s0, 0.0); a1, _ = at(s1, 0.0)
        b0, _ = at(s0, 14.0); b1, _ = at(s1, 14.0)
        cell = Polygon([a0, a1, b1, b0])
        (north_e if s0 < GRAVEL_END else north_w).append(cell)
    ne = rest.intersection(unary_union(north_e)) if north_e else None
    nw = rest.intersection(unary_union(north_w)) if north_w else None
    if ne is not None and not ne.is_empty:
        out.append((_clean(ne, corr, hard), 1))
    if nw is not None and not nw.is_empty:
        out.append((_clean(nw, corr, hard), 3))
    return out


def _clean(g, corr, hard):
    """Pas de taches : fermeture morphologique (comble les jours entre bandes), trous < 6 m² bouchés, lanières et
    miettes < 2 m² supprimées ; on reste dans le couloir public, hors chaussée et trottoirs."""
    g = g.buffer(0.5, join_style=2).buffer(-0.5, join_style=2)
    parts = []
    for pg in getattr(g, "geoms", [g]):
        if pg.geom_type != "Polygon":
            continue
        pg = Polygon(pg.exterior, [h for h in pg.interiors if Polygon(h).area >= 6.0])
        parts.append(pg)
    g = unary_union(parts).intersection(corr).difference(hard.buffer(0.02))
    g = g.buffer(-0.3, join_style=2).buffer(0.3, join_style=2)
    return unary_union([pg for pg in getattr(g, "geoms", [g]) if pg.geom_type == "Polygon" and pg.area >= 2.0])


def gutter_quads():
    """Caniveau central : bande de béton de 0,45 m sur l'axe, de s = 0 à GUTTER_END. Liste de (p0, p1) le long de l'axe."""
    out = []
    for s0 in np.arange(6.0, GUTTER_END, 2.0):
        a, _ = at(s0, 0.0); b, _ = at(s0 + 2.0, 0.0)
        out.append((a, b))
    return out


def lamps():
    """[(x, z, dx, dz)] : pied au bord extérieur (trottoir au sud, accotement au nord), tête tournée vers la rue."""
    out = []
    for s, side in LAMPS:
        off = (WIDTH / 2 + SIDEWALK_W - 0.35) if side < 0 else (WIDTH / 2 + 1.0)
        p, d = at(s, off * side)
        q, _ = at(s, 0.0)
        v = (q - p) / max(np.linalg.norm(q - p), 1e-6)
        out.append((float(p[0]), float(p[1]), float(v[0]), float(v[1])))
    return out


def sv_cam_fix(cam, date):
    """Position corrigée d'une caméra Street View de 2014 (même décalage que l'axe) pour les comparaisons."""
    if not date or date >= "2020":
        return list(cam)
    L0 = LineString(AXE_SV)
    s = L0.project(Point(cam))
    a = np.array(L0.interpolate(s).coords[0])
    b = np.array(axis().interpolate(axis().project(Point(a))).coords[0])
    return [float(cam[0] + b[0] - a[0]), float(cam[1] + b[1] - a[1])]
