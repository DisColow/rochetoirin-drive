"""Épreuves chronométrées (issue #59) : départs posés sur des lieux publics de la carte (mairies, églises, places,
châteaux, gares, parcs…), bien répartis, arrivée sur un autre lieu à 2,5-6 km par la route ; trois points de passage
sur l'itinéraire le plus rapide ; médailles d'après le temps de cet itinéraire (vitesses par type de voie) :
or 1,00 ×, argent 1,25 ×, bronze 1,6 ×. Sortie : ../godot/world/epreuves.json
[{id, nom, a: [x, z], etapes: [[x, z] × 3], b: [x, z], km, or, argent, bronze}].
Après build_roads.py et build_places.py.   python3 build_epreuves.py"""
import json, math, pickle
import networkx as nx
import numpy as np

KMH = dict(motorway=110, motorway_link=60, primary=80, primary_link=50, secondary=70, secondary_link=50, tertiary=60,
           tertiary_link=40, unclassified=45, residential=35, living_street=15, service=20, track=15)
GENRES = {"mairie", "culte", "place", "chateau", "gare", "parc", "culture", "sport", "poste"}
N = 14


def main():
    ways = pickle.load(open("data/roads.pkl", "rb"))["ways"]
    G = nx.Graph()
    pos = {}
    for w in ways:
        if w["cls"] not in KMH or "nodes" not in w or "idx" not in w:
            continue
        P = np.asarray(w["P"], float)
        ids, ix = w["nodes"], w["idx"]
        for k in range(len(ids) - 1):
            seg = P[int(ix[k]): int(ix[k + 1]) + 1]
            L = float(np.linalg.norm(np.diff(seg, axis=0), axis=1).sum()) if len(seg) > 1 else 0.0
            a, b = ids[k], ids[k + 1]
            pos[a] = (float(P[int(ix[k])][0]), float(P[int(ix[k])][1]))
            pos[b] = (float(P[int(ix[k + 1])][0]), float(P[int(ix[k + 1])][1]))
            G.add_edge(a, b, L=L, t=L / (KMH[w["cls"]] / 3.6))
    G = G.subgraph(max(nx.connected_components(G), key=len)).copy()
    ids = list(G.nodes); XY = np.array([pos[n] for n in ids])

    def proche(x, z):
        return ids[int(np.argmin(((XY - (x, z)) ** 2).sum(1)))]

    places = [p for p in json.load(open("../godot/world/places.json")) if p["k"] in GENRES]
    # départs bien répartis : le plus éloigné des départs déjà pris, à chaque tour
    choisis = [min(places, key=lambda p: p["x"] ** 2 + p["z"] ** 2)]
    while len(choisis) < N * 3 and len(choisis) < len(places):
        choisis.append(max(places, key=lambda p: min((p["x"] - q["x"]) ** 2 + (p["z"] - q["z"]) ** 2 for q in choisis)))
    out = []
    # v6.68 (#108) : les 14 épreuves d'origine (ids 0-13, records conservés), puis 12 sprints et 12 longues
    for (dmin, dmax, cible, nmax, genre) in ((2500, 6000, 4000, N, ""), (1200, 2500, 1800, N + 12, "Sprint : "),
                                            (6000, 10000, 8000, N + 24, "Longue : ")):
        for a in choisis:
            if len(out) >= nmax:
                break
            na = proche(a["x"], a["z"])
            dist = nx.single_source_dijkstra_path_length(G, na, cutoff=dmax, weight="L")
            cands = [p for p in places if p is not a and p["n"] != a["n"] and dmin <= dist.get(proche(p["x"], p["z"]), 0) <= dmax]
            if not cands:
                continue
            b = max(cands, key=lambda p: (p["k"] in ("mairie", "gare", "chateau", "culte"), -abs(dist[proche(p["x"], p["z"])] - cible)))
            nom = "%s%s → %s" % (genre, a["n"], b["n"])
            if any(o["nom"] == nom for o in out):
                continue
            path = nx.shortest_path(G, na, proche(b["x"], b["z"]), weight="t")
            t = sum(G[u][v]["t"] for u, v in zip(path[:-1], path[1:]))
            L = sum(G[u][v]["L"] for u, v in zip(path[:-1], path[1:]))
            cum = np.cumsum([0.0] + [G[u][v]["L"] for u, v in zip(path[:-1], path[1:])])
            etapes = [pos[path[int(np.searchsorted(cum, L * f))]] for f in (0.25, 0.5, 0.75)]
            out.append(dict(id=len(out), nom=nom, a=list(pos[na]), etapes=[list(e) for e in etapes],
                            b=list(pos[path[-1]]), km=round(L / 1000, 1), **{"or": round(t), "argent": round(t * 1.25), "bronze": round(t * 1.6)}))
            print("%-70s %.1f km  or %d:%02d" % (out[-1]["nom"][:70], L / 1000, t // 60, t % 60))
    json.dump(out, open("../godot/world/epreuves.json", "w"), ensure_ascii=False, indent=1)
    print(len(out), "épreuves")


if __name__ == "__main__":
    main()
