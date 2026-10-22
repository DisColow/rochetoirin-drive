"""Réseau de la circulation (#132) : voies carrossables d'OSM (data/roads.pkl de build_roads.py), d'un carrefour à
l'autre, pour les voitures qui roulent toutes seules (godot/scripts/circulation.gd).

Routes retenues : autoroute et bretelles, nationales, départementales, routes de desserte, rues ; pas les voies de
service (parkings, allées privées), chemins de terre, rues piétonnes. Chaque arc va d'un carrefour (nœud OSM partagé
par deux routes, ou bout de route) au suivant ; tracé rééchantillonné à PAS m, altitude de la chaussée (`y` de
build_roads.py, ponts compris).

Feux tricolores (v6.87) : les arcs sont aussi coupés aux nœuds highway=traffic_signals ; pour chaque arc, le feu qui
règle l'arrivée à chacun de ses bouts : tête de feu placée comme furniture.signs (même voie, même sens, sinon une tête
de la même voie, sinon la première du nœud), phase = (17 cx + 31 cz) mod 60 avec (cx, cz) la case de 60 m de ses
ampoules, axe = |face.x| > |face.z| ; même calcul que scripts/signal_light.gdshader (cycle de 60 s).

world/trafic.bin (petit-boutiste) :
  int nn ; nn × (float x, float z)                         nœuds (carrefours)
  int na ; na × (int a, int b, int p0, int np, int fl, float v, float dl, int feu_b, int feu_a)
     feu_b : feu en arrivant en b dans le sens de l'arc, feu_a : en arrivant en a à contresens ; phase × 2 + axe,
     -1 : pas de feu
     fl : bit 0 sens unique (de a vers b), bits 4-7 nombre de voies dans le sens de marche (1 à 4), bits 8-11 classe
     v : vitesse autorisée (m/s ; maxspeed d'OSM, sinon selon la classe) ; dl : décalage du milieu de la voie de droite
     par rapport à l'axe (m, vers la droite du sens de marche ; 0 pour un sens unique à une voie)
  int np ; np × (float x, float y, float z)                points de l'axe
"""
import json, math, pickle, struct, collections
import numpy as np
import furniture

PAS = 6.0
CLASSES = ["motorway", "motorway_link", "primary", "primary_link", "secondary", "secondary_link", "tertiary",
           "tertiary_link", "unclassified", "residential", "living_street"]
DEFAUT = {"motorway": 130, "motorway_link": 70, "primary": 70, "primary_link": 50, "secondary": 70,
          "secondary_link": 50, "tertiary": 70, "tertiary_link": 50, "unclassified": 50, "residential": 50,
          "living_street": 20}


def vitesse(w):
    v = str(w["tags"].get("maxspeed", "")).strip()
    if v.isdigit() and 10 <= int(v) <= 130:
        return int(v)
    return DEFAUT[w["cls"]]


def voies(w):
    """Nombre de voies dans chaque sens de marche."""
    try:
        n = int(str(w["tags"].get("lanes", "")).split(";")[0])
    except ValueError:
        n = 0
    if w["oneway"]:
        return max(1, min(4, n if n else (2 if w["cls"] == "motorway" else 1)))
    return max(1, min(3, n // 2 if n >= 2 else 1))


def reechantillonner(P, y, s, s0, s1):
    """Points de l'axe entre les abscisses s0 et s1 tous les PAS m environ (bouts compris)."""
    n = max(1, int(round((s1 - s0) / PAS)))
    t = np.linspace(s0, s1, n + 1)
    return np.stack([np.interp(t, s, P[:, 0]), np.interp(t, s, y), np.interp(t, s, P[:, 1])], 1)


def feux_par_approche(tous):
    """Têtes de feux comme furniture.signs : {(nœud, voie OSM, sens) : (phase, axe)} et {nœud : (phase, axe)}."""
    node_tags = {e["id"]: e["tags"] for e in json.load(open("data/osm.json"))["elements"]
                 if e["type"] == "node" and e.get("tags")}
    use, by_node = {}, {}
    for w in tous:
        for k, n in enumerate(w["nodes"]):
            use[n] = use.get(n, 0) + 1
            by_node.setdefault(n, []).append((w, k))
    tetes, premiere = {}, {}
    for n, t in node_tags.items():
        if t.get("highway") != "traffic_signals" or n not in by_node:
            continue
        lst = [(w, k) for w, k in by_node[n] if not w["bridge"]]
        if not lst:
            continue
        w, k = min(lst, key=lambda wk: 0 if 0 < wk[1] < len(wk[0]["nodes"]) - 1 else 1)
        dirs = [furniture.approach_dir(w, k, use, t)] if use[n] == 1 else [1, -1]
        for w2, k2 in (lst if use[n] >= 2 else [(w, k)]):
            for d in ([furniture.approach_dir(w2, k2, use, t)] if use[n] >= 2 else dirs):
                s2 = w2["s"][w2["idx"][k2]]
                pos, face = furniture._place(w2, s2 - d * 4.0, d, 0.5)
                f = np.asarray(face, float) / max(np.linalg.norm(face), 1e-9)
                ampoule = np.asarray(pos, float) + f * 0.245          # devant du caisson (_signal_head)
                cx, cz = math.floor(ampoule[0] / 60.0), math.floor(ampoule[1] / 60.0)
                ph = ((17 * cx + 31 * cz) % 60, 1 if abs(f[0]) > abs(f[1]) else 0)
                tetes[(n, w2["id"], d)] = ph
                premiere.setdefault(n, ph)
    return tetes, premiere


def feu(tetes, premiere, n, wid, d):
    ph = tetes.get((n, wid, d)) or tetes.get((n, wid, -d)) or premiere.get(n)
    return -1 if ph is None else ph[0] * 2 + ph[1]


def main():
    tous = pickle.load(open("data/roads.pkl", "rb"))["ways"]
    tetes, premiere = feux_par_approche(tous)
    ways = [w for w in tous if w["cls"] in CLASSES and len(w["P"]) >= 2 and w.get("paved", True)]
    usage = collections.Counter()
    for w in ways:
        for k, n in enumerate(w["nodes"]):
            usage[n] += 2 if k in (0, len(w["nodes"]) - 1) else 1
    nid, nodes, arcs, pts = {}, [], [], []

    def noeud(n, p):
        if n not in nid:
            nid[n] = len(nodes)
            nodes.append((float(p[0]), float(p[1])))
        return nid[n]

    for w in ways:
        P = np.asarray(w["P"], float); s = np.asarray(w["s"], float); y = np.asarray(w["y"], float)
        ids, ix = w["nodes"], [int(i) for i in w["idx"]]
        # carrefours de la route : bouts et nœuds partagés avec une autre route
        coupes = [k for k in range(len(ids)) if k in (0, len(ids) - 1) or usage[ids[k]] > 1 or ids[k] in premiere]
        fl = (1 if w["oneway"] else 0) | (voies(w) << 4) | (CLASSES.index(w["cls"]) << 8)
        v = vitesse(w) / 3.6
        demi = float(w["w"]) / 2.0
        nv = voies(w)
        # milieu de la voie la plus à droite : sens unique -> (nv - 1) demi-voies à droite de l'axe ;
        # double sens -> la moitié droite de la chaussée est partagée en nv voies
        if w["oneway"]:
            dl = demi * (nv - 1) / nv
        else:
            dl = demi - demi / (2 * nv)
        dl = float(min(dl, 5.5))
        for c0, c1 in zip(coupes, coupes[1:]):
            i0, i1 = ix[c0], ix[c1]
            if i1 <= i0 or s[i1] - s[i0] < 0.5:
                continue
            g = reechantillonner(P, y, s, s[i0], s[i1])
            a = noeud(ids[c0], P[i0]); b = noeud(ids[c1], P[i1])
            arcs.append((a, b, len(pts), len(g), fl, v, dl, feu(tetes, premiere, ids[c1], w["id"], 1),
                         feu(tetes, premiere, ids[c0], w["id"], -1)))
            pts.extend(map(tuple, g))
    with open("../godot/world/trafic.bin", "wb") as fh:
        fh.write(struct.pack("<i", len(nodes))); fh.write(np.asarray(nodes, "<f4").tobytes())
        fh.write(struct.pack("<i", len(arcs)))
        for a in arcs:
            fh.write(struct.pack("<iiiiiffii", *a))
        fh.write(struct.pack("<i", len(pts))); fh.write(np.asarray(pts, "<f4").tobytes())
    sortants = collections.Counter()
    for a, b, *_r, in arcs:
        sortants[a] += 1
        sortants[b] += 1
    impasses = sum(1 for n in range(len(nodes)) if sortants[n] == 1)
    print("trafic : %d carrefours (%d impasses), %d arcs, %d points, %d arrivées à un feu (%d nœuds), %.0f km d'axe" % (
        len(nodes), impasses, len(arcs), len(pts), sum((a[7] >= 0) + (a[8] >= 0) for a in arcs), len(premiere), sum(np.sum(np.hypot(*np.diff(np.asarray(pts[a[2]:a[2] + a[3]])[:, [0, 2]], axis=0).T)) for a in arcs) / 1000))


if __name__ == "__main__":
    main()
