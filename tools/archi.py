"""Architecture des maisons du bourg relevée sur Street View (archi_bourg.json, une entrée par bâtiment BD TOPO).

Attributs : toit "2" (deux pans) / "4" (croupes) / "p" (plat), niv (niveaux), ss (garage en sous-sol, logement à l'étage),
gar (portes de garage côté rue), bal (balcon / terrasse à garde-corps), esc (escalier extérieur), auv (auvent, pergola,
préau), chem (cheminée), comb (combles habités : toit raide), solaire (panneaux), vieux (maison ancienne), pierre / pise
(murs en moellons / pisé), grange (bâtiment agricole), bois (bardage bois), cam (position de la caméra Street View :
la façade tournée vers elle est la façade sur rue).

Les maisons du bourg non relevées reçoivent la même répartition de toits (près d'une sur deux à deux pans).
"""
import json, math, os
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
_DATA = None

M_PLAIN, M_WALL, M_TILES, M_STEEL, M_GLASS, M_RUBBLE, M_CREPI = 0, 1, 3, 8, 10, 17, 18


def data():
    global _DATA
    if _DATA is None:
        p = os.path.join(HERE, "archi_bourg.json")
        _DATA = json.load(open(p)) if os.path.exists(p) else {}
    return _DATA


def street_edge(ring, cam):
    """Arête de l'anneau (CCW) la plus tournée vers la caméra / la rue : (a, b, normale extérieure, longueur)."""
    best, bs = None, -1e9
    n = len(ring)
    for k in range(n):
        a, b = np.array(ring[k], float), np.array(ring[(k + 1) % n], float)
        d = b - a; L = float(np.hypot(*d))
        if L < 2.0:
            continue
        nn = np.array([d[1], -d[0]]) / L
        mid = (a + b) / 2
        to = np.array(cam, float) - mid
        s = float(np.dot(nn, to / max(np.linalg.norm(to), 1e-6))) * min(L, 12.0)
        if s > bs:
            bs, best = s, (a, b, nn, L)
    return best


def plan(a, wall_top, gmin, roof_h, wcol, wallmat, rng):
    """Corrections de la maison d'après les attributs : (wall_top, roof_h, gable?, flat?, wcol, wallmat, floors)."""
    niv = int(a.get("niv", 1))
    wall_top = gmin + (3.0 if niv == 1 else 0.2 + 2.8 * niv)
    if a.get("comb"):
        wall_top += 0.6                     # surcroît des combles aménagés
    gable = a.get("toit") == "2"
    flat = a.get("toit") == "p"
    if a.get("pierre"):
        wallmat = M_RUBBLE; wcol = (0.70, 0.62, 0.50)
    elif a.get("pise"):
        wallmat = M_CREPI; wcol = (0.56, 0.45, 0.34)         # pisé : terre brune banchée
    elif a.get("bois"):
        wcol = (0.58, 0.42, 0.28)
    elif a.get("vieux"):
        wallmat = M_CREPI if rng.random() < 0.6 else wallmat
    if a.get("grange"):
        wallmat = M_RUBBLE if wallmat == M_RUBBLE else M_PLAIN
    return wall_top, roof_h, gable, flat, wcol, wallmat, niv


def roof_height(a, width):
    if a.get("comb"):
        return width * 0.42
    return width * (0.30 if a.get("toit") == "2" else 0.26)


def extras(m, poly, a, gmin, wall_top, roof_top, box_mesh, rng, gable_ring=None, ground=None):
    """Éléments de façade sur rue et de toiture."""
    from shapely.geometry.polygon import orient
    ring = list(orient(gable_ring if gable_ring is not None else poly, 1.0).exterior.coords)[:-1]
    se = street_edge(ring, a.get("cam", poly.centroid.coords[0]))
    if se is None:
        return
    A, B, nn, L = se
    d = (B - A) / L
    yaw = math.atan2(d[1], d[0])
    out = nn * 0.06
    G = (lambda p: max(gmin, float(ground(p[0], p[1])))) if ground else (lambda p: gmin)
    doors = []
    used = 0.6                                         # abscisse libre le long de la façade
    # --- portes de garage (sectionnelles blanches ou bois), au rez-de-chaussée
    ng = int(a.get("gar", 0))
    door_w = 3.2 if a.get("grange") else 2.5
    door_h = 2.9 if a.get("grange") else 2.1
    ng = min(ng, int((L - 1.0) // (door_w + 0.5)))
    if ng and not a.get("esc"):
        used = max(0.6, (L - ng * (door_w + 0.6)) / 2)          # groupe de portes centré sur la façade
    col = (0.86, 0.86, 0.84) if rng.random() < 0.6 and not a.get("grange") else (0.42, 0.28, 0.18)
    for k in range(ng):
        t = used + door_w / 2
        c = A + d * t + out
        g0 = G(c) - 0.05                                  # sol au droit de la porte (maisons en pente)
        box_mesh(m, c[0], g0 + door_h / 2, c[1], door_w, door_h, 0.08, col, M_PLAIN, yaw)
        for g in range(1, 4):                            # rainures des panneaux
            box_mesh(m, c[0] + nn[0] * 0.05, g0 + door_h * g / 4, c[1] + nn[1] * 0.05, door_w * 0.96, 0.03, 0.02,
                     tuple(x * 0.8 for x in col), M_PLAIN, yaw)
        box_mesh(m, c[0] + nn[0] * 0.03, g0 + door_h + 0.1, c[1] + nn[1] * 0.03, door_w + 0.3, 0.2, 0.1, (0.80, 0.79, 0.76), M_PLAIN, yaw)
        doors.append((t, g0))
        used += door_w + 0.6
    entry = used + 0.8                                   # porte d'entrée / escalier après les garages
    gs = G(A + d * min(entry, L - 0.5))
    floor1 = gs + (2.8 if a.get("ss") else 0.0)
    # --- escalier extérieur vers l'étage (maisons sur sous-sol)
    if a.get("esc") and floor1 > gmin + 1:
        steps = 14
        for s in range(steps):
            t = entry + s * 0.28
            if t > L - 0.5:
                break
            c = A + d * t + nn * 0.6
            h = (s + 1) * (floor1 - gs) / steps
            box_mesh(m, c[0], gs + h / 2, c[1], 0.3, h, 1.1, (0.74, 0.73, 0.70), M_PLAIN, yaw)
        entry += steps * 0.28 + 0.3
    # --- auvent / pergola / préau au-dessus de l'entrée
    if a.get("auv"):
        over_door = bool(doors) and (a.get("ss") or not a.get("esc"))
        w = 2.6 if not a.get("grange") else 4.0
        if over_door:                                   # petit toit en tuiles sur consoles au-dessus du garage
            t, base = doors[0][0], doors[0][1]
            w = door_w + 0.6
        else:
            t, base = min(max(entry, w / 2 + 0.3), L - w / 2 - 0.3), floor1
        y = base + (2.55 if over_door else 2.45)
        depth = 0.9 if over_door else 1.5
        # pan unique incliné vers l'avant (tuiles), sous-face et rive
        drop = 0.4
        E3 = lambda p, yy: (float(p[0]), float(yy), float(p[1]))
        b0, b1 = A + d * (t - w / 2), A + d * (t + w / 2)
        f0, f1 = b0 + nn * depth, b1 + nn * depth
        top = [E3(b0, y), E3(b1, y), E3(f1, y - drop), E3(f0, y - drop)]
        nrm = np.cross(np.subtract(top[1], top[0]), np.subtract(top[3], top[0])); nrm = nrm / np.linalg.norm(nrm)
        if nrm[1] < 0:
            nrm = -nrm
        uvs = [(0, 0), (w, 0), (w, depth), (0, depth)]
        m.quad(*[m.vert(p, tuple(nrm), (0.50, 0.30, 0.22), uv, M_TILES + 0.3) for p, uv in zip(top, uvs)])
        m.quad(*[m.vert((p[0], p[1] - 0.06, p[2]), tuple(-nrm), (0.36, 0.27, 0.20), (0, 0), M_PLAIN) for p in top])
        front = [E3(f0, y - drop - 0.12), E3(f1, y - drop - 0.12), E3(f1, y - drop), E3(f0, y - drop)]
        m.quad(*[m.vert(p, (float(nn[0]), 0.0, float(nn[1])), (0.36, 0.27, 0.20), (0, 0), M_PLAIN) for p in front])
        if over_door:
            for s in (-1, 1):
                p = A + d * (t + s * (w / 2 - 0.2)) + nn * 0.4
                box_mesh(m, p[0], y - 0.35, p[1], 0.12, 0.45, 0.6, (0.45, 0.31, 0.20), M_PLAIN, yaw)
        else:
            for s in (-1, 1):
                p = A + d * (t + s * (w / 2 - 0.15)) + nn * (depth - 0.1)
                box_mesh(m, p[0], (y + base) / 2, p[1], 0.14, y - base, 0.14, (0.45, 0.31, 0.20), M_PLAIN, yaw)
    # --- balcon ou terrasse à l'étage
    if a.get("bal") and wall_top - gmin > 4.5:
        w = min(4.0, L * 0.45)
        t = L - w / 2 - 0.5
        c = A + d * t + nn * 0.65
        y = gmin + 2.85
        box_mesh(m, c[0], y, c[1], w, 0.16, 1.3, (0.80, 0.79, 0.76), M_PLAIN, yaw)
        rail = (0.92, 0.92, 0.90) if rng.random() < 0.5 else (0.16, 0.17, 0.18)
        p = A + d * t + nn * 1.28
        box_mesh(m, p[0], y + 0.95, p[1], w, 0.06, 0.06, rail, M_STEEL, yaw)
        for k in range(int(w / 0.12)):
            q = A + d * (t - w / 2 + 0.06 + k * 0.12) + nn * 1.28
            box_mesh(m, q[0], y + 0.5, q[1], 0.025, 0.9, 0.025, rail, M_STEEL, yaw)
    # --- panneaux solaires sur le pan le plus au sud (toits à deux pans)
    if a.get("solaire") and gable_ring is not None:
        P = [np.array(p, float) for p in ring]
        e = [np.linalg.norm(P[(k + 1) % 4] - P[k]) for k in range(4)]
        k0 = 0 if e[0] >= e[1] else 1
        A2, B2, C2, D2 = P[k0], P[(k0 + 1) % 4], P[(k0 + 2) % 4], P[(k0 + 3) % 4]
        M1, M2 = (A2 + D2) / 2, (B2 + C2) / 2
        lo = (A2, B2) if (A2 - D2)[1] > 0 else (D2, C2)          # z vers le Sud
        E = lambda p, y: np.array([p[0], y, p[1]])
        pts = [E(lo[0], wall_top + 0.2), E(lo[1], wall_top + 0.2), E(M2, roof_top + 0.12), E(M1, roof_top + 0.12)]
        nrm = np.cross(pts[1] - pts[0], pts[3] - pts[0]); nrm = nrm / np.linalg.norm(nrm)
        if nrm[1] < 0:
            nrm = -nrm
        solar(m, pts, nrm, None)
    # --- cheminée (sous le faîtage, côté opposé à la rue)
    if a.get("chem"):
        c = np.array(poly.centroid.coords[0]) - nn * 0.8
        box_mesh(m, c[0], (wall_top + roof_top) / 2 + 0.6, c[1], 0.55, roof_top - wall_top + 0.6, 0.55,
                 (0.80, 0.78, 0.74), M_PLAIN, yaw)
        box_mesh(m, c[0], roof_top + 0.95, c[1], 0.7, 0.1, 0.7, (0.55, 0.40, 0.32), M_PLAIN, yaw)


def solar(m, pts, nn, rcol):
    """Panneaux photovoltaïques posés sur un pan (4 coins 3D du pan, normale)."""
    pa, pb, pc, pe = [np.asarray(p, float) for p in pts]
    u = pb - pa; v = pe - pa
    lift = np.asarray(nn) * 0.06
    q = [pa + u * 0.2 + v * 0.15 + lift, pa + u * 0.8 + v * 0.15 + lift, pa + u * 0.8 + v * 0.75 + lift, pa + u * 0.2 + v * 0.75 + lift]
    ids = [m.vert(tuple(p), tuple(nn), (0.10, 0.13, 0.20), (0, 0), M_GLASS) for p in q]
    m.quad(*ids)
