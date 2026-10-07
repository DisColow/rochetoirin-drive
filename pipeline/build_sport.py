"""Terrains de sport (OSM, fetch_sport.py) : surface et tracés dessinés en jeu sur un rectangle orienté qui épouse le
relief, équipements faits avec Blender (blender_sport.py) : buts, poteaux de rugby, filets et grillages de tennis,
paniers, mâts d'éclairage des terrains de foot, bancs de touche.
Rien sur la route : un terrain qui touche une chaussée est rogné à son rectangle intérieur, ou ignoré.
Sortie : ../godot/world/sport/sp_tx_tz.bin :
  int32 n terrains, n × 9 float32 (type, cx, cz, longueur, largeur, cap (rad), surface, éclairé, 0) ;
  int32 m objets, m × 17 float32 (modèle, base 3 × 3 colonnes, origine, 4 données) comme les commerces.
Types : 1 foot, 2 rugby, 3 tennis, 4 basket, 5 multisport / hand, 6 pétanque, 7 piste d'athlétisme.
Surfaces : 0 herbe, 1 synthétique, 2 terre battue, 3 résine (vert/bleu), 4 stabilisé, 5 tartan."""
import json, math, os, pickle, shutil
from collections import defaultdict
import numpy as np
from shapely.geometry import LineString, Polygon, Point
import geo
from build_fences import Local

OUT = "../godot/world/sport"
TILE = 256.0
MODELS = ["but_foot", "poteaux_rugby", "filet_tennis", "panier_basket", "mat_eclairage", "grillage", "banc_touche"]
MID = {n: i for i, n in enumerate(MODELS)}
SPORT = {"soccer": 1, "rugby_union": 2, "rugby_league": 2, "tennis": 3, "basketball": 4, "handball": 5, "multi": 5,
         "basketball;soccer": 5, "boules": 6, "petanque": 6, "athletics": 7}
SURF = {"grass": 0, "artificial_turf": 1, "clay": 2, "acrylic": 3, "asphalt": 3, "concrete": 3, "tartan": 5,
        "gravel": 4, "fine_gravel": 4, "compacted": 4, "dirt": 4, "sand": 4}


def xf(model, origin, ang, scale=(1, 1, 1), custom=(0, 0, 0, 0)):
    """Instance tournée de ang (rad) autour de la verticale : +x du modèle = largeur, +z = profondeur."""
    c, s = math.cos(ang), math.sin(ang)
    X = np.array([c, 0, -s]) * scale[0]; Y = np.array([0, 1.0, 0]) * scale[1]; Z = np.array([s, 0, c]) * scale[2]
    return (MID[model],) + tuple(X) + tuple(Y) + tuple(Z) + tuple(origin) + tuple(custom)


def main():
    shutil.rmtree(OUT, ignore_errors=True); os.makedirs(OUT)
    from build_vegetation import Carved
    dem = Carved()
    zone = Polygon(json.load(open("data/routes_plan.json"))["zone"])
    ways = [w for w in pickle.load(open("data/roads.pkl", "rb"))["ways"] if len(w["P"]) > 1]
    CARR = Local([LineString(w["P"]).buffer(w["w"] / 2 + 0.5) for w in ways if w["cls"] not in ("path", "footway", "track")])
    d = json.load(open("data/osm_sport.json"))
    pitches, inst = [], []
    stats = defaultdict(int)
    for e in d["elements"]:
        t = e.get("tags", {})
        if t.get("leisure") not in ("pitch", "track") or "geometry" not in e:
            continue
        pts = [geo.to_local(g["lon"], g["lat"]) for g in e["geometry"]]
        if len(pts) < 4:
            continue
        P = Polygon([(float(x), float(z)) for x, z in pts]).buffer(0)
        if P.is_empty or not zone.contains(P.centroid):
            continue
        if CARR.near(P, 0.0):
            P2 = P.buffer(-2.0)
            if P2.is_empty or CARR.near(P2, 0.0):
                stats["sur la route"] += 1
                continue
            P = P2
        sport = t.get("sport") or ""
        typ = SPORT.get(sport)
        if t.get("leisure") == "track":
            typ = 7 if "athletics" in sport else None
        if typ is None:
            typ = 1 if P.area > 3500 else (5 if P.area > 300 else None)
        if typ is None:
            continue
        r = P.minimum_rotated_rectangle
        c = np.asarray(r.exterior.coords)[:4]
        e1, e2 = c[1] - c[0], c[2] - c[1]
        L, W = np.linalg.norm(e1), np.linalg.norm(e2)
        ax = e1 / L
        if W > L:
            L, W = W, L; ax = e2 / np.linalg.norm(e2)
        if L < 8 or W < 5:
            continue
        cx, cz = r.centroid.x, r.centroid.y
        ang = math.atan2(ax[0], ax[1])                     # cap de la longueur (axe +z local)
        surf = SURF.get(t.get("surface", ""), {1: 0, 2: 0, 3: 3, 4: 3, 5: 3, 6: 4, 7: 5}[typ])
        if typ == 3 and t.get("surface") is None:
            surf = 2 if (hash(e["id"]) % 3 == 0) else 3
        lit = 1 if (t.get("lit") == "yes" or (typ in (1, 2) and L > 80)) else 0
        y = float(np.mean(dem.h(c[:, 0], c[:, 1])))
        pitches.append((typ, cx, cz, L, W, ang, surf, lit, 0.0))
        stats[typ] += 1
        fwd = np.array([math.sin(ang), math.cos(ang)]); side = np.array([math.cos(ang), -math.sin(ang)])

        def h(p):
            return float(dem.h(np.array([p[0]]), np.array([p[1]]))[0])
        cen = np.array([cx, cz])
        if typ in (1, 2, 5):
            for sg in (-1, 1):
                p = cen + fwd * sg * (L / 2 - (0.3 if typ != 5 else 0.5))
                model = "but_foot" if typ != 2 else "poteaux_rugby"
                sc = (1, 1, 1) if typ != 5 else (0.41, 0.82, 0.5)          # buts de hand / multisport : 3 × 2 m
                inst.append(xf(model, (p[0], h(p), p[1]), ang + (math.pi if sg > 0 else 0.0), sc))
            if typ == 5 and W >= 12:
                for sg in (-1, 1):
                    p = cen + fwd * sg * (L / 2 - 1.2)
                    inst.append(xf("panier_basket", (p[0], h(p), p[1]), ang + (math.pi if sg > 0 else 0.0)))
            if typ == 1 and L > 70:
                for sg in (-1, 1):
                    p = cen + side * (W / 2 + 4.0) + fwd * sg * 8.0
                    if not CARR.near(Point(p).buffer(2.5), 0.0):
                        inst.append(xf("banc_touche", (p[0], h(p), p[1]), ang - math.pi / 2))
            if lit:
                for sx in (-1, 1):
                    for sz in (-1, 1):
                        p = cen + side * sx * (W / 2 + 5.0) + fwd * sz * (L / 2 - 12.0)
                        if not CARR.near(Point(p).buffer(1.0), 0.0):
                            inst.append(xf("mat_eclairage", (p[0], h(p), p[1]), ang + (-math.pi / 2 if sx > 0 else math.pi / 2)))
        elif typ == 4:
            for sg in (-1, 1):
                p = cen + fwd * sg * (L / 2 - 1.2)
                inst.append(xf("panier_basket", (p[0], h(p), p[1]), ang + (math.pi if sg > 0 else 0.0)))
        elif typ == 3:
            inst.append(xf("filet_tennis", (cx, y, cz), ang, (W / 12.8 if W < 12.8 else 1.0, 1, 1)))
            # grillage tout autour (panneaux de 3 m), sauf s'il toucherait la chaussée
            for (a0, a1) in (((-1, -1), (1, -1)), ((1, -1), (1, 1)), ((1, 1), (-1, 1)), ((-1, 1), (-1, -1))):
                A = cen + side * a0[0] * W / 2 + fwd * a0[1] * L / 2
                B = cen + side * a1[0] * W / 2 + fwd * a1[1] * L / 2
                n = max(1, int(round(np.linalg.norm(B - A) / 3.0)))
                dv = (B - A) / n
                a = math.atan2(dv[1], -dv[0]) + math.pi / 2
                for k in range(n):
                    p = A + dv * (k + 0.5)
                    if CARR.near(Point(p), 0.6):
                        continue
                    inst.append(xf("grillage", (p[0], h(p), p[1]), math.atan2(-dv[1], dv[0]),
                                   (np.linalg.norm(dv) / 3.0, 1, 1)))
    T = defaultdict(lambda: ([], []))
    for p in pitches:
        T[(int(math.floor(p[1] / TILE)), int(math.floor(p[2] / TILE)))][0].append(p)
    for r in inst:
        T[(int(math.floor(r[10] / TILE)), int(math.floor(r[12] / TILE)))][1].append(r)
    for (tx, tz), (Ps, Is) in T.items():
        b = np.int32(len(Ps)).tobytes() + (np.array(Ps, "<f4").tobytes() if Ps else b"")
        b += np.int32(len(Is)).tobytes() + (np.array(Is, "<f4").tobytes() if Is else b"")
        open("%s/sp_%d_%d.bin" % (OUT, tx, tz), "wb").write(b)
    print(dict(stats), len(pitches), "terrains,", len(inst), "objets,", len(T), "tuiles")


if __name__ == "__main__":
    main()
