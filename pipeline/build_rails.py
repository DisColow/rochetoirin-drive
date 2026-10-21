"""Voies ferrées (#125, demande de l'utilisateur : rails sur lesquels on roule sans partir en vrille, passages à
niveau aux barrières défonçables, pas de train). D'après OSM (fetch_rails.py : railway=rail, level_crossing).
- Chaque voie est rééchantillonnée tous les 2 m et posée sur le relief terrassé (Carved), profil lissé sur ~12 m,
  dessus du ballast 0,10 m au-dessus du sol (jamais sous le relief) ; dans la zone de jeu seulement ; ponts et tunnels sautés (le relief
  n'a pas leurs tabliers).
- Passages à niveau : sur la chaussée (rf : altitude de la route), rails noyés au ras de la route (drapeau 1, pas de
  ballast), rampe de 8 m de part et d'autre ; direction et largeur de la route relevées pour les barrières.
Sortie : ../godot/world/rails/rl_tx_tz.bin (tuiles de 256 m) :
  int32 n voies, puis par voie : int32 m points, m × 4 float32 (x, y du dessus du ballast, z, drapeau 0 ballast /
  1 noyé dans la route) ;
  int32 p passages, p × 8 float32 (x, y de la route, z, cap de la voie, cap de la route (rad), largeur de la route,
  barrières 0 aucune / 1 demi-barrières / 2 barrières pleines, écart entre voies extrêmes).
  OSM met un nœud de passage par voie (ligne à double voie : deux nœuds à ~4 m) : regroupés à moins de 12 m.
Lancer depuis pipeline/ (après build_roads.py) : python3 build_rails.py"""
import json, math, os, pickle, shutil, struct
from collections import defaultdict
import numpy as np
from shapely.geometry import LineString, Polygon, Point
import geo

OUT = "../godot/world/rails"
TILE = 256.0
PAS = 2.0
DESSUS = 0.10                 # dessus du ballast au-dessus du relief (m) : bosse douce (0,18 m : choc de 17 km/h)
RAMPE = 8.0                   # raccord du ballast à la chaussée d'un passage à niveau (m)
ROUTES = ("motorway", "motorway_link", "trunk", "trunk_link", "primary", "primary_link", "secondary", "secondary_link",
          "tertiary", "tertiary_link", "unclassified", "residential", "living_street", "service", "track")


def reechantillonner(P, pas):
    L = np.r_[0.0, np.cumsum(np.hypot(*np.diff(P, axis=0).T))]
    s = np.arange(0.0, L[-1] + 1e-6, pas)
    if L[-1] - s[-1] > 0.3:
        s = np.r_[s, L[-1]]
    return np.c_[np.interp(s, L, P[:, 0]), np.interp(s, L, P[:, 1])], s


def main():
    from build_vegetation import Carved
    from build_roads import samples, road_height_fn
    shutil.rmtree(OUT, ignore_errors=True); os.makedirs(OUT)
    dem = Carved()
    zone = Polygon(json.load(open("data/routes_plan.json"))["zone"])
    ways = [w for w in pickle.load(open("data/roads.pkl", "rb"))["ways"] if len(w["P"]) > 1 and w["cls"] in ROUTES]
    rf = road_height_fn(samples(ways))
    d = json.load(open("data/osm_rails.json"))
    stats = defaultdict(int)
    # --- passages à niveau : point, route la plus proche (cap, largeur), barrières
    passages = []
    for e in d["elements"]:
        t = e.get("tags", {})
        if e["type"] != "node" or t.get("railway") != "level_crossing":
            continue
        x, z = geo.to_local(e["lon"], e["lat"])
        if not zone.contains(Point(x, z)):
            stats["passage hors zone"] += 1
            continue
        best = None
        for w in ways:
            P = np.asarray(w["P"])
            dd = np.hypot(P[:, 0] - x, P[:, 1] - z)
            k = int(np.argmin(dd))
            if dd[k] < 12.0 and (best is None or dd[k] < best[0]):
                k0, k1 = max(k - 1, 0), min(k + 1, len(P) - 1)
                best = (float(dd[k]), math.atan2(P[k1, 0] - P[k0, 0], -(P[k1, 1] - P[k0, 1])), float(w.get("w", 6.0)))
        if best is None:
            stats["passage sans route"] += 1
            continue
        bar = {"no": 0, "half": 1, "yes": 1, "full": 2, "double_half": 2, "gate": 2}.get(t.get("crossing:barrier", "half"), 1)
        y = float(rf(np.array([x]), np.array([z]))[0][0])
        passages.append([x, y, z, 0.0, best[1], min(max(best[2], 4.5), 12.0), bar])
    PA = np.array([[p[0], p[2]] for p in passages]) if passages else np.zeros((0, 2))
    # --- voies
    voies = []
    for e in d["elements"]:
        t = e.get("tags", {})
        if e["type"] != "way" or t.get("railway") not in ("rail", "light_rail") or "geometry" not in e:
            continue
        if t.get("bridge") in ("yes", "viaduct") or t.get("tunnel") in ("yes", "building_passage") or t.get("disused") == "yes":
            stats["pont ou tunnel"] += 1
            continue
        L = LineString([geo.to_local(g["lon"], g["lat"]) for g in e["geometry"]])
        I = L.intersection(zone)
        morceaux = [I] if I.geom_type == "LineString" else list(getattr(I, "geoms", []))
        for m in morceaux:
            if m.geom_type != "LineString" or m.length < 4.0:
                continue
            P, s = reechantillonner(np.asarray(m.coords), PAS)
            if len(P) < 2:
                continue
            h = dem.h(P[:, 0], P[:, 1])
            k = 7                                   # lissage sur ~12 m (relief à 2 m, bruit du LiDAR)
            hp = np.r_[np.full(k // 2, h[0]), h, np.full(k // 2, h[-1])]
            y = np.maximum(np.convolve(hp, np.ones(k) / k, mode="valid"), h) + DESSUS      # jamais sous le relief
            drap = np.zeros(len(P))
            # passages à niveau de cette voie : chaussée au ras, rampe autour
            if len(PA):
                for j, q in enumerate(PA):
                    dq = np.hypot(P[:, 0] - q[0], P[:, 1] - q[1])
                    i0 = int(np.argmin(dq))
                    if dq[i0] > 6.0:
                        continue
                    p = passages[j]
                    i1, i2 = max(i0 - 1, 0), min(i0 + 1, len(P) - 1)
                    p[3] = math.atan2(P[i2, 0] - P[i1, 0], -(P[i2, 1] - P[i1, 1]))
                    demi = p[5] / 2.0 / max(abs(math.sin(p[4] - p[3])), 0.4) + 1.0
                    ds = np.abs(s - s[i0])
                    noye = ds <= demi
                    yr = np.asarray(rf(P[:, 0], P[:, 1])[0]) + 0.015
                    y = np.where(noye, yr, y)
                    r = (ds > demi) & (ds < demi + RAMPE)
                    f = (ds[r] - demi) / RAMPE
                    y[r] = yr[r] * (1 - f) + y[r] * f
                    drap = np.where(noye, 1.0, drap)
                    stats["voies noyées"] += 1
            voies.append(np.c_[P[:, 0], y, P[:, 1], drap])
            stats["km de voie"] += m.length / 1000.0
    # --- tuiles : chaque segment dans la tuile de son milieu, morceaux consécutifs regroupés
    par_tuile = defaultdict(list)
    for V in voies:
        cour, kc = None, None
        for i in range(len(V) - 1):
            mx, mz = (V[i, 0] + V[i + 1, 0]) / 2, (V[i, 2] + V[i + 1, 2]) / 2
            k = (math.floor(mx / TILE), math.floor(mz / TILE))
            if k != kc:
                if cour is not None and len(cour) >= 2:
                    par_tuile[kc].append(np.array(cour))
                cour, kc = [V[i]], k
            cour.append(V[i + 1])
        if cour is not None and len(cour) >= 2:
            par_tuile[kc].append(np.array(cour))
    # un passage par croisement : nœuds à moins de 12 m regroupés (centre, écart entre les voies extrêmes)
    groupes = []
    for p in passages:
        for g in groupes:
            if math.hypot(g[0][0] - p[0], g[0][2] - p[2]) < 12.0:
                g.append(p)
                break
        else:
            groupes.append([p])
    fusion = []
    for g in groupes:
        G = np.array([[q[0], q[1], q[2]] for q in g])
        ecart = max((math.hypot(a[0] - b[0], a[2] - b[2]) for a in G for b in G), default=0.0)
        m = G.mean(axis=0)
        fusion.append([m[0], m[1], m[2], g[0][3], g[0][4], g[0][5], g[0][6], ecart])
    stats["passages (croisements)"] = len(fusion)
    pas_t = defaultdict(list)
    for p in fusion:
        pas_t[(math.floor(p[0] / TILE), math.floor(p[2] / TILE))].append(p)
    for k in set(par_tuile) | set(pas_t):
        b = bytearray(struct.pack("<i", len(par_tuile[k])))
        for V in par_tuile[k]:
            b += struct.pack("<i", len(V)) + V.astype("<f4").tobytes()
        b += struct.pack("<i", len(pas_t[k]))
        for p in pas_t[k]:
            b += struct.pack("<8f", *p)
        open(os.path.join(OUT, "rl_%d_%d.bin" % k), "wb").write(bytes(b))
    print("%d tuiles, %.1f km de voie, %d passages à niveau" % (len(set(par_tuile) | set(pas_t)), stats["km de voie"], len(passages)),
          {k: (round(v, 1) if isinstance(v, float) else v) for k, v in stats.items()})


if __name__ == "__main__":
    main()
