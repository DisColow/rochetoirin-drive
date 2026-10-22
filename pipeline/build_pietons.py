"""Chemins des passants (v6.88, initiative de Claude) : où marchent les piétons de godot/scripts/pietons.gd.

D'après data/roads.pkl (build_roads.py) et la part de bâti de world/ambiance.bin (build_ambiance.py) :
- trottoirs d'OSM (sidewalk=*) : milieu du trottoir (axe décalé de w/2 + SW_W/2), sur la bordure (+ CURB_H) ;
- rues piétonnes (highway=pedestrian) : axe ;
- en ville, bord des rues sans trottoir (toutes sauf autoroutes, bretelles, voies de service et chemins ; limitées à
  50 km/h au plus) : BORD m hors de la chaussée, là où la part de bâti moyenne le long de la rue atteint BATI.
- passages piétons (nœuds highway=crossing dessinés par furniture.markings) d'une rue qui a des passants des deux
  côtés : ligne en travers de la chaussée, d'un côté à l'autre ; les lignes des côtés sont coupées à ses bouts.
- arrêts de bus (highway=bus_stop, panneau posé par furniture.signs) : petite ligne de 0,6 m face à la route, près du
  panneau ; le passant y attend sans bouger.
Chaque ligne est coupée là où elle passe sur une chaussée (carrefours, autres routes), morceaux de moins de MINI m
retirés ; bouts à moins de JOINT m réunis en nœuds (le passant continue sur une autre ligne, sinon fait demi-tour).
Poids d'apparition : part de bâti de la case (0-1) + 2 à moins de 80 m d'un lieu public (world/places.json).

world/pietons.bin (petit-boutiste) :
  int nl ; nl × (int p0, int np, int na, int nb, int genre, float poids)
     na, nb : nœud des deux bouts ; genre : 0 trottoir, 1 rue piétonne, 2 bord de rue, 3 passage piéton, 4 arrêt de bus
  int np ; np × (float x, float y, float z)
"""
import json, pickle, struct
import numpy as np
import shapely
from shapely.geometry import LineString, Point
from shapely.ops import unary_union

SW_W, CURB_H = 1.6, 0.13          # build_roads.py
BORD = 0.7
BATI = 150
MINI = 10.0
JOINT = 2.5
PAS = 3.0
TRAVERSEES = ("uncontrolled", "marked", "zebra", "traffic_signals", None)      # comme build_roads.py (zébras)
CHAUSSEES = ("motorway", "motorway_link", "primary", "primary_link", "secondary", "secondary_link", "tertiary",
             "tertiary_link", "unclassified", "residential", "living_street", "service", "track")


def main():
    ways = pickle.load(open("data/roads.pkl", "rb"))["ways"]
    amb = json.load(open("../godot/world/ambiance.json"))
    bati = np.fromfile("../godot/world/ambiance.bin", np.uint8).reshape(amb["nz"], amb["nx"], 4)[:, :, 0]

    def part_bati(x, z):
        i = np.clip(((np.asarray(z) - amb["z0"]) // amb["cell"]).astype(int), 0, amb["nz"] - 1)
        j = np.clip(((np.asarray(x) - amb["x0"]) // amb["cell"]).astype(int), 0, amb["nx"] - 1)
        return bati[i, j]

    lieux = json.load(open("../godot/world/places.json"))
    lieux_xy = np.array([[p["x"], p["z"]] for p in lieux]) if lieux else np.zeros((0, 2))
    chaussee = unary_union([LineString(w["P"]).buffer(w["w"] / 2 + 0.15, cap_style="flat")
                            for w in ways if w["cls"] in CHAUSSEES and len(w["P"]) >= 2 and w["layer"] >= 0])
    shapely.prepare(chaussee)
    lignes = []                       # (genre, Nx3)
    node_tags = {e["id"]: e["tags"] for e in json.load(open("data/osm.json"))["elements"]
                 if e["type"] == "node" and e.get("tags", {}).get("highway") in ("crossing", "bus_stop")}
    par_noeud = {}
    for w in ways:
        for k, n in enumerate(w["nodes"]):
            if n in node_tags:
                par_noeud.setdefault(n, []).append((w, k))
    traversees = []                   # Nx3 (bouts sur les lignes des côtés)

    def ajouter(w, ls_axe, ligne, genre, dy):
        """Morceaux de `ligne` hors des chaussées, rééchantillonnés tous les PAS m, altitude de la route + dy."""
        reste = ligne.difference(chaussee) if genre != 1 else ligne
        S, Y = np.asarray(w["s"], float), np.asarray(w["y"], float)
        for g in getattr(reste, "geoms", [reste]):
            if g.geom_type != "LineString" or g.length < MINI:
                continue
            n = max(2, int(round(g.length / PAS)) + 1)
            pts = [g.interpolate(t) for t in np.linspace(0.0, g.length, n)]
            xz = np.array([[p.x, p.y] for p in pts])
            y = np.interp([ls_axe.project(p) for p in pts], S, Y) + dy
            lignes.append((genre, np.column_stack([xz[:, 0], y, xz[:, 1]])))

    for w in ways:
        if len(w["P"]) < 2 or w["layer"] < 0:
            continue
        P = np.asarray(w["P"], float)
        ls = LineString(P)
        if w["cls"] == "pedestrian":
            ajouter(w, ls, ls, 1, 0.0)
            continue
        if w["cls"] not in CHAUSSEES or w["cls"] in ("motorway", "motorway_link", "track", "service"):
            continue
        vmax = str(w["tags"].get("maxspeed", ""))
        en_ville = (not vmax.isdigit() or int(vmax) <= 50) and np.mean(part_bati(P[:, 0], P[:, 1])) >= BATI
        cotes = [None, None]
        for side, sg in ((0, 1), (1, -1)):
            if w["sidewalk"][side]:
                off, genre, dy = w["w"] / 2 + SW_W / 2, 0, CURB_H
            elif en_ville and not w["bridge"]:
                off, genre, dy = w["w"] / 2 + BORD, 2, 0.0
            else:
                continue
            cotes[side] = (off, dy)
            o = ls.offset_curve(sg * off, join_style="round")
            for g in getattr(o, "geoms", [o]):
                if not g.is_empty:
                    ajouter(w, ls, g, genre, dy)
        if cotes[0] and cotes[1] and w["paved"] and not w["bridge"]:
            S, Y = np.asarray(w["s"], float), np.asarray(w["y"], float)
            for k, n in enumerate(w["nodes"]):
                t = node_tags.get(n)
                if not t or t.get("highway") != "crossing" or t.get("crossing") not in TRAVERSEES:
                    continue
                s0 = float(S[w["idx"][k]])
                c = np.array([np.interp(s0, S, P[:, 0]), np.interp(s0, S, P[:, 1])])
                a = np.array([np.interp(s0 + 1.0, S, P[:, 0]), np.interp(s0 + 1.0, S, P[:, 1])]) - \
                    np.array([np.interp(s0 - 1.0, S, P[:, 0]), np.interp(s0 - 1.0, S, P[:, 1])])
                a /= max(np.linalg.norm(a), 1e-9)
                gauche = np.array([-a[1], a[0]])              # côté 0 (offset_curve positif)
                A = c + gauche * cotes[0][0]
                B = c - gauche * cotes[1][0]
                yc = float(np.interp(s0, S, Y))
                n_pts = max(3, int(round(np.linalg.norm(B - A) / PAS)) + 1)
                u = np.linspace(0.0, 1.0, n_pts)
                xz = A[None, :] + (B - A)[None, :] * u[:, None]
                y = np.full(n_pts, yc)
                y[0] += cotes[0][1]; y[-1] += cotes[1][1]
                traversees.append(np.column_stack([xz[:, 0], y, xz[:, 1]]))

    # arrêts de bus : comme furniture.signs (voie du nœud, de préférence une voie qui le traverse ; à droite du sens de
    # la voie, w/2 + trottoir + 0,8 m), le passant 1,5 m plus loin, un peu plus près de la route, tourné vers elle
    arrets = 0
    for n, t in node_tags.items():
        if t.get("highway") != "bus_stop" or n not in par_noeud:
            continue
        lst = [(w, k) for w, k in par_noeud[n] if not w["bridge"] and w["cls"] in CHAUSSEES]
        if not lst:
            continue
        w, k = min(lst, key=lambda wk: 0 if 0 < wk[1] < len(wk[0]["nodes"]) - 1 else 1)
        S, Y = np.asarray(w["s"], float), np.asarray(w["y"], float)
        P = np.asarray(w["P"], float)
        s0 = min(float(S[w["idx"][k]]) + 1.5, float(S[-1]))
        c = np.array([np.interp(s0, S, P[:, 0]), np.interp(s0, S, P[:, 1])])
        a = np.array([np.interp(s0 + 1.0, S, P[:, 0]), np.interp(s0 + 1.0, S, P[:, 1])]) - \
            np.array([np.interp(s0 - 1.0, S, P[:, 0]), np.interp(s0 - 1.0, S, P[:, 1])])
        a /= max(np.linalg.norm(a), 1e-9)
        droite = np.array([-a[1], a[0]])
        off = w["w"] / 2 + (SW_W if any(w["sidewalk"]) else 0.0) + 0.6
        A = c + droite * off
        B = A - droite * 0.6
        y = float(np.interp(s0, S, Y)) + (CURB_H if any(w["sidewalk"]) else 0.0)
        lignes.append((4, np.array([[A[0], y, A[1]], [B[0], y, B[1]]])))
        arrets += 1

    # passages piétons : les lignes des côtés coupées au point le plus proche de chaque bout (1,6 m au plus)
    from scipy.spatial import cKDTree
    idx = [(k, i) for k, (g, L) in enumerate(lignes) if g in (0, 2) for i in range(len(L))]
    arbre_p = cKDTree(np.array([[lignes[k][1][i][0], lignes[k][1][i][2]] for k, i in idx]))
    coupes = {}
    gardees = 0
    for T in traversees:
        bons = True
        for b in (0, -1):
            d, j = arbre_p.query([T[b][0], T[b][2]])
            if d > 1.6:
                bons = False
                break
        if not bons:
            continue
        for b in (0, -1):
            d, j = arbre_p.query([T[b][0], T[b][2]])
            k, i = idx[j]
            T[b] = lignes[k][1][i]
            coupes.setdefault(k, set()).add(i)
        u = np.linspace(0.0, 1.0, len(T))[1:-1, None]            # droite entre les deux bouts recalés
        T[1:-1, [0, 2]] = T[0, [0, 2]] + (T[-1, [0, 2]] - T[0, [0, 2]]) * u
        lignes.append((3, T))
        gardees += 1
    morceaux = []
    for k, (g, L) in enumerate(lignes):
        if k not in coupes:
            morceaux.append((g, L))
            continue
        bornes = [0] + sorted(i for i in coupes[k] if 0 < i < len(L) - 1) + [len(L) - 1]
        for i0, i1 in zip(bornes, bornes[1:]):
            if i1 > i0:
                morceaux.append((g, L[i0:i1 + 1]))
    lignes = morceaux

    # nœuds : bouts réunis à moins de JOINT m
    bouts = np.array([[l[1][k][0], l[1][k][2]] for l in lignes for k in (0, -1)])
    arbre = cKDTree(bouts)
    noeud = -np.ones(len(bouts), int)
    nn = 0
    for i in range(len(bouts)):
        if noeud[i] < 0:
            for j in arbre.query_ball_point(bouts[i], JOINT):
                if noeud[j] < 0:
                    noeud[j] = nn
            nn += 1
    pts, arcs = [], []
    for k, (genre, L) in enumerate(lignes):
        mil = L[len(L) // 2]
        poids = part_bati(mil[0], mil[2]) / 255.0
        if len(lieux_xy) and np.min(np.hypot(lieux_xy[:, 0] - mil[0], lieux_xy[:, 1] - mil[2])) < 80.0:
            poids += 2.0
        if genre == 4:
            poids = max(poids, 1.5)
        arcs.append((len(pts), len(L), int(noeud[2 * k]), int(noeud[2 * k + 1]), genre, float(poids)))
        pts.extend(map(tuple, L))
    with open("../godot/world/pietons.bin", "wb") as fh:
        fh.write(struct.pack("<i", len(arcs)))
        for a in arcs:
            fh.write(struct.pack("<iiiiif", *a))
        fh.write(struct.pack("<i", len(pts)))
        fh.write(np.asarray(pts, "<f4").tobytes())
    km = [sum(np.sum(np.hypot(*np.diff(L[:, [0, 2]], axis=0).T)) for g, L in lignes if g == k) / 1000 for k in range(3)]
    print("piétons : %d lignes, %d nœuds, %d points ; trottoirs %.1f km, rues piétonnes %.1f km, bords de rue %.1f km, "
          "%d passages piétons (sur %d possibles), %d arrêts de bus" % (len(arcs), nn, len(pts), *km, gardees, len(traversees),
                                                                       arrets))


if __name__ == "__main__":
    main()
