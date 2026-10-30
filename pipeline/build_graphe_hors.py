"""Arcs du graphe routier (world/graphe.bin, build_itineraire.py) qui sortent de la zone jouable (world/zone.json,
build_zone.py) ou la frôlent à moins de MARGE m : l'itinéraire du GPS les évite (#156 : aucune activité ne doit faire
traverser les collines du bord). Puis les « enclaves » : nœuds que seuls des arcs évités relient au reste du réseau (dehors,
ou sur une route qui sort de la carte et y revient) ; ni départ, ni arrivée, ni adresse de livraison.
Sortie : ../godot/world/graphe_hors.bin (int32 : nombre d'arcs évités, leurs indices, nombre d'enclaves, leurs nœuds).
Lancer depuis pipeline/ après build_itineraire.py et build_zone.py : python3 build_graphe_hors.py"""
import json
import numpy as np
import shapely
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components
from shapely.geometry import Polygon

MARGE = 12.0

b = open("../godot/world/graphe.bin", "rb").read()
o = 0
nn = int(np.frombuffer(b, "<i4", 1, o)[0]); o += 4 + nn * 8
na = int(np.frombuffer(b, "<i4", 1, o)[0]); o += 4
arcs = np.frombuffer(b, "<i4", na * 6, o).reshape(na, 6); o += na * 24
npt = int(np.frombuffer(b, "<i4", 1, o)[0]); o += 4
pts = np.frombuffer(b, "<f4", npt * 2, o).reshape(npt, 2).astype(np.float64)

z = Polygon(json.load(open("../godot/world/zone.json"))["pts"]).buffer(-MARGE)
shapely.prepare(z)
dedans = shapely.contains_xy(z, pts[:, 0], pts[:, 1])
hors = [k for k in range(na) if not dedans[arcs[k, 4]:arcs[k, 4] + arcs[k, 5]].all()]
garde = np.ones(na, bool); garde[hors] = False
a, c = arcs[garde, 0], arcs[garde, 1]
_, comp = connected_components(coo_matrix((np.ones(len(a)), (a, c)), shape=(nn, nn)), directed=False)
principale = np.bincount(comp).argmax()
enclaves = np.nonzero(comp != principale)[0].tolist()
np.array([len(hors)] + hors + [len(enclaves)] + enclaves, "<i4").tofile("../godot/world/graphe_hors.bin")
print("%d arcs sur %d hors de la zone (marge %.0f m), %d points dehors sur %d ; %d nœuds en enclave"
      % (len(hors), na, MARGE, (~dedans).sum(), npt, len(enclaves)))
