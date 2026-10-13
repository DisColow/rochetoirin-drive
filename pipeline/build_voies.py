"""Voies de circulation pour l'aide au maintien dans la voie (v6.25, scripts/voie.gd).
Même grille de 64 m que world/roadnames.json (build_map.py, à lancer avant). Sortie ../godot/world/voies.bin :
int32 début de chaque cellule (nx × nz + 1) puis float32 (x, z, dx, dz, demi-largeur, voies) des points d'axe tous
les 3 m, triés par cellule ; (dx, dz) = sens de numérisation OSM ; voies > 0 : sens unique à n voies, < 0 : double
sens à |n| voies (1 : voie unique, on suit l'axe).
Lancer depuis pipeline/ : python3 build_voies.py"""
import json, math, pickle
import numpy as np

CLASSES = {"motorway", "motorway_link", "trunk", "trunk_link", "primary", "primary_link", "secondary",
           "secondary_link", "tertiary", "tertiary_link", "unclassified", "residential", "living_street", "service"}
PAS = 3.0


def voies(w):
    t = w["tags"]
    n = str(t.get("lanes", "")).split(";")[0]
    oneway = bool(w.get("oneway")) or w["cls"] in ("motorway", "motorway_link")
    if n.isdigit() and int(n) > 0:
        n = int(n)
    else:
        n = 0
    if oneway:
        return max(1, n or (2 if w["cls"] == "motorway" else 1))
    if n == 0:
        n = 2 if w["w"] >= 4.8 else 1
    return -min(n, 4)


def main():
    meta = json.load(open("../godot/world/roadnames.json"))
    C, x0, z0, nx, nz = meta["cell"], meta["x0"], meta["z0"], meta["nx"], meta["nz"]
    ways = pickle.load(open("data/roads.pkl", "rb"))["ways"]
    rows = []
    for w in ways:
        if w["cls"] not in CLASSES or len(w["P"]) < 2 or (w["cls"] == "service" and w["w"] < 4.0):
            continue
        P, s = np.asarray(w["P"], float), np.asarray(w["s"], float)
        n = voies(w)
        for d in np.arange(0.0, s[-1] + 0.01, PAS):
            x = np.interp(d, s, P[:, 0]); z = np.interp(d, s, P[:, 1])
            a, b = max(0.0, d - 1.5), min(s[-1], d + 1.5)
            tx = np.interp(b, s, P[:, 0]) - np.interp(a, s, P[:, 0])
            tz = np.interp(b, s, P[:, 1]) - np.interp(a, s, P[:, 1])
            L = math.hypot(tx, tz)
            if L < 1e-3:
                continue
            rows.append((x, z, tx / L, tz / L, w["w"] / 2, n))
    R = np.array(rows)
    ix = ((R[:, 0] - x0) // C).astype(int); iz = ((R[:, 1] - z0) // C).astype(int)
    ok = (ix >= 0) & (iz >= 0) & (ix < nx) & (iz < nz)
    R, cell = R[ok], (iz * nx + ix)[ok]
    o = np.argsort(cell, kind="stable"); R, cell = R[o], cell[o]
    starts = np.searchsorted(cell, np.arange(nx * nz + 1)).astype("<i4")
    with open("../godot/world/voies.bin", "wb") as fh:
        fh.write(starts.tobytes()); fh.write(R.astype("<f4").tobytes())
    print("%d points de voie" % len(R))


if __name__ == "__main__":
    main()
