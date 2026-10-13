"""Graphe routier pour l'itinéraire du GPS (v6.30, taxi : chemin le plus court vers le client puis la destination).
Nœuds = nœuds OSM des voies carrossables (croisements et points de forme), arcs = tronçons entre deux nœuds
consécutifs d'une voie, avec leur longueur, leur sens unique éventuel et leur géométrie (points de l'axe).
Sortie ../godot/world/graphe.bin (petit-boutiste) :
 int32 nn, float32 (x, z) × nn ;
 int32 na, puis par arc : int32 a, int32 b, float32 longueur, int32 drapeaux (1 = sens unique a -> b,
 2 = chemin de terre), int32 début, int32 nombre de points (dans le tableau de points) ;
 int32 np, float32 (x, z) × np.
Lancer depuis pipeline/ : python3 build_itineraire.py"""
import pickle, struct
import numpy as np

EXCLUS = {"footway", "path", "cycleway", "steps", "pedestrian", "bridleway", "corridor", "platform", "construction"}


def main():
    ways = pickle.load(open("data/roads.pkl", "rb"))["ways"]
    nid = {}                       # nœud OSM -> indice
    nodes = []
    arcs = []
    pts = []
    for w in ways:
        if w["cls"] in EXCLUS or len(w["P"]) < 2 or "nodes" not in w or "idx" not in w:
            continue
        P = np.asarray(w["P"], float); s = np.asarray(w["s"], float)
        ow = bool(w.get("oneway"))
        fl = (1 if ow else 0) | (2 if w["cls"] == "track" else 0)
        ids, ix = w["nodes"], w["idx"]
        for k in range(len(ids) - 1):
            i0, i1 = int(ix[k]), int(ix[k + 1])
            if i1 <= i0:
                continue
            ab = []
            for j, (n, i) in enumerate(((ids[k], i0), (ids[k + 1], i1))):
                if n not in nid:
                    nid[n] = len(nodes); nodes.append((P[i, 0], P[i, 1]))
                ab.append(nid[n])
            g = P[i0:i1 + 1]
            arcs.append((ab[0], ab[1], float(s[i1] - s[i0]), fl, len(pts), len(g)))
            pts.extend(map(tuple, g))
    with open("../godot/world/graphe.bin", "wb") as fh:
        fh.write(struct.pack("<i", len(nodes))); fh.write(np.asarray(nodes, "<f4").tobytes())
        fh.write(struct.pack("<i", len(arcs)))
        for a in arcs:
            fh.write(struct.pack("<iifiii", *a))
        fh.write(struct.pack("<i", len(pts))); fh.write(np.asarray(pts, "<f4").tobytes())
    print("%d nœuds, %d arcs, %d points" % (len(nodes), len(arcs), len(pts)))


if __name__ == "__main__":
    main()
