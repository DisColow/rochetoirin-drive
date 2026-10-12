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
    """Arête de l'anneau (CCW) la plus tournée vers la caméra / la rue : (a, b, normale extérieure, longueur, indice)."""
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
            bs, best = s, (a, b, nn, L, k)
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


def extras(m, poly, a, gmin, wall_top, roof_top, box_mesh, rng, gable_ring=None, ground=None, ouv=None, shut=None):
    """Éléments de façade sur rue et de toiture. ouv : ouvertures relevées (facades_ouvertures.json) posées sur
    l'arête de rue retenue par building_mesh (m.street), dont les fenêtres procédurales sont alors supprimées."""
    from shapely.geometry.polygon import orient
    ring = list(orient(gable_ring if gable_ring is not None else poly, 1.0).exterior.coords)[:-1]
    se = getattr(m, "street", None) or street_edge(ring, a.get("cam", poly.centroid.coords[0]))
    if se is None:
        return
    A, B, nn, L = se[:4]
    d = (B - A) / L
    yaw = math.atan2(d[1], d[0])
    out = nn * 0.06
    G = (lambda p: max(gmin, float(ground(p[0], p[1])))) if ground else (lambda p: gmin)
    doors = []
    used = 0.6                                         # abscisse libre le long de la façade
    # --- portes de garage (sectionnelles blanches ou bois), au rez-de-chaussée
    ng = int(a.get("gar", 0)) if ouv is None else 0
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
    if ouv is not None:
        P = [np.array(p, float) for p in ring]
        sides = sorted(float(np.linalg.norm(P[(k + 1) % len(P)] - P[k])) for k in range(len(P)))
        gable_end = gable_ring is not None and L < sides[-1] - 0.3
        doors, ent = openings(m, A, B, nn, L, ouv, gmin, wall_top, roof_top, gable_end, shut, G, box_mesh, rng, a)
        if ent is not None:
            entry = ent[0]
            if a.get("esc") and ent[1] >= 1:
                entry = max(0.3, ent[0] - 0.9 - 14 * 0.28)
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


# --- ouvertures de la façade sur rue relevées sur Street View -------------------------------------------------------
# Jetons (de gauche à droite, niveaux séparés par « | », rez-de-chaussée d'abord) :
#   V fenêtre à volets battants, R fenêtre à volet roulant, P porte-fenêtre à volets, B baie vitrée,
#   D porte d'entrée, G porte de garage, N porte de grange en planches, O petite fenêtre (jour), _ trumeau plein,
#   H porte de garage à deux battants en bois.
#   (largeur de l'ouverture, hauteur, allège, emprise sur la façade)
OPEN = {"V": (1.0, 1.25, 0.95, 2.3), "R": (1.2, 1.25, 0.95, 1.7), "P": (0.95, 2.15, 0.0, 2.2), "B": (2.4, 2.15, 0.0, 2.8),
        "D": (0.95, 2.15, 0.0, 1.6), "G": (2.5, 2.1, 0.0, 3.0), "N": (2.8, 2.6, 0.0, 3.4), "O": (0.6, 0.6, 1.45, 1.0),
        "H": (2.4, 2.0, 0.0, 3.0),
        "_": (0.0, 0.0, 0.0, 1.5)}
WHITE = (0.90, 0.90, 0.87)
ALU = (0.24, 0.25, 0.27)


def parse(spec):
    return [lvl.split() for lvl in spec.split("|")]


def openings(m, A, B, nn, L, spec, gmin, wall_top, roof_top, gable_end, shut, G, box_mesh, rng, a):
    """Ouvertures en relief sur l'arête A→B (normale nn) : vitrage (verre réfléchissant), dormant, appui, volets
    battants ouverts, coffres et tabliers de volets roulants, portes, portes de garage sectionnelles, portes de grange.
    Renvoie (portes de garage [(abscisse, sol)], (abscisse, niveau) de la porte d'entrée)."""
    d = (B - A) / L
    yaw = math.atan2(d[1], d[0])
    shut = shut or (0.42, 0.28, 0.18)
    old = bool(a.get("vieux") or a.get("pierre") or a.get("pise"))
    frame = (0.45, 0.32, 0.22) if old else WHITE
    door_col = (0.42, 0.28, 0.18) if old or rng.random() < 0.45 else (WHITE if rng.random() < 0.5 else (0.30, 0.32, 0.34))
    gar_col = (0.42, 0.28, 0.18) if old else (0.86, 0.86, 0.84) if rng.random() < 0.75 else (0.32, 0.34, 0.36)
    Gs = [G(A + d * t) for t in np.linspace(0.3, L - 0.3, 6)]
    gedge = max(Gs)
    garages, entry = [], None

    def put(t, y, w, h, dep, col, mat, off=0.0):
        c = A + d * t + nn * (dep / 2 + off)
        box_mesh(m, c[0], y + h / 2, c[1], w, h, dep, col, mat, yaw)

    for lvl, toks in enumerate(parse(spec)):
        if not toks:
            continue
        toks = toks[::-1]               # vue de la rue, l'arête A→B (anneau CCW) va de droite à gauche
        foot = np.array([OPEN.get(k, OPEN["_"])[3] for k in toks])
        s = min(1.0, max(0.55, (L - 0.5) / foot.sum()))
        gap = max(0.0, (L - foot.sum() * s) / (len(toks) + 1))
        t = gap
        for k in toks:
            w, h, sill, f = OPEN.get(k, OPEN["_"])
            tc = t + f * s / 2
            t += f * s + gap
            if k == "_":
                continue
            w *= min(1.0, s * 1.08)
            g0 = G(A + d * tc)
            if lvl == 0:
                y0 = g0 - (0.04 if sill == 0 else 0.0)
            else:
                y0 = max(gmin + 2.8 * lvl, gedge + 2.6 * lvl) + (0.0 if a.get("ss") else 0.15)
            yb, yt = y0 + sill, y0 + sill + h
            lim = wall_top - 0.15
            if gable_end and lvl >= 1:
                lim = wall_top + (roof_top - wall_top) * (1 - abs(tc - L / 2) / (L / 2)) - 0.45
            if yt + (0.25 if k in "RB" else 0.0) > lim:
                if lvl == 0 or sill == 0:
                    if lvl > 0:
                        continue
                    h = max(1.6, lim - yb - (0.25 if k in "RB" else 0.0))
                    yt = yb + h
                else:
                    drop = yt + (0.25 if k in "RB" else 0.0) - lim
                    if drop > 0.5:
                        continue
                    yb -= drop; yt -= drop
            if k in "VRPBO":
                fcol = ALU if k == "B" else frame
                put(tc, yb, w, h, 0.03, (0.10, 0.12, 0.14), M_GLASS)                     # vitrage
                for sx in (-1, 1):                                                       # dormant
                    put(tc + sx * (w / 2 - 0.035), yb, 0.07, h, 0.07, fcol, M_PLAIN)
                put(tc, yt - 0.07, w, 0.07, 0.07, fcol, M_PLAIN)
                put(tc, yb, w, 0.07, 0.07, fcol, M_PLAIN)
                if k in "VPB" and w > 0.7:                                               # meneau central
                    put(tc, yb, 0.06, h, 0.06, fcol, M_PLAIN)
                if sill > 0:                                                              # appui en saillie
                    put(tc, yb - 0.06, w + 0.2, 0.06, 0.16, (0.80, 0.79, 0.76), M_PLAIN)
                if k in "VP":                                                             # volets battants ouverts
                    for sx in (-1, 1):
                        cx = tc + sx * (w / 2 + w / 4 + 0.04)
                        put(cx, yb, w / 2, h, 0.04, shut, M_PLAIN)
                        for yy in (0.18, h - 0.28):                                      # barres
                            put(cx, yb + yy, w / 2 - 0.04, 0.1, 0.02, tuple(x * 0.8 for x in shut), M_PLAIN, 0.04)
                if k in "RB" or (k == "V" and not old and rng.random() < 0.3):            # coffre + tablier à moitié baissé
                    put(tc, yt, w + 0.08, 0.25, 0.10, WHITE if k != "B" else ALU, M_PLAIN)
                    if k != "V":
                        drop = h * (0.25 + 0.25 * rng.random())
                        put(tc, yt - drop, w - 0.06, drop, 0.05, (0.82, 0.82, 0.80) if k == "R" else ALU, M_PLAIN)
            elif k == "D":
                put(tc, yb, w, h, 0.06, door_col, M_PLAIN)
                put(tc, yb + h * 0.62, w * 0.5, h * 0.25, 0.07, (0.10, 0.12, 0.14), M_GLASS)    # imposte vitrée
                for sx in (-1, 1):
                    put(tc + sx * (w / 2 + 0.04), yb, 0.08, h + 0.08, 0.08, frame, M_PLAIN)
                put(tc, yb + h, w + 0.16, 0.08, 0.08, frame, M_PLAIN)
                put(tc + w * 0.36, yb + 1.0, 0.04, 0.04, 0.12, (0.75, 0.72, 0.62), M_STEEL)        # poignée
                put(tc, yb - 0.04, w + 0.4, 0.12, 0.45, (0.74, 0.73, 0.70), M_PLAIN)               # seuil / marche
                if entry is None or lvl < entry[1]:
                    entry = (tc, lvl)
            elif k == "G":
                put(tc, yb, w, h, 0.08, gar_col, M_PLAIN)
                for g in range(1, 4):                                                    # rainures
                    put(tc, yb + h * g / 4, w * 0.96, 0.03, 0.02, tuple(x * 0.8 for x in gar_col), M_PLAIN, 0.08)
                put(tc, yb + h, w + 0.3, 0.12, 0.1, WHITE, M_PLAIN)
                garages.append((tc, yb))
            elif k == "H":
                wood = (0.40, 0.25, 0.15)
                put(tc, yb, w, h, 0.07, wood, M_PLAIN)
                for j in range(1, int(w / 0.14)):                                         # lames verticales
                    put(tc - w / 2 + j * 0.14, yb, 0.02, h, 0.02, tuple(x * 0.78 for x in wood), M_PLAIN, 0.07)
                put(tc, yb, 0.04, h, 0.03, tuple(x * 0.6 for x in wood), M_PLAIN, 0.07)          # jointure des battants
                for yy in (0.3, h - 0.4):                                                 # pentures
                    for sx in (-1, 1):
                        put(tc + sx * w / 4, yb + yy, w / 2 - 0.2, 0.05, 0.02, (0.12, 0.12, 0.12), M_STEEL, 0.08)
                for sx in (-1, 1):
                    put(tc + sx * (w / 2 + 0.05), yb, 0.1, h + 0.1, 0.09, frame, M_PLAIN)
                put(tc, yb + h, w + 0.3, 0.12, 0.1, frame, M_PLAIN)
                garages.append((tc, yb))
            elif k == "N":
                wood = (0.40, 0.31, 0.22) if rng.random() < 0.5 else (0.48, 0.42, 0.34)
                put(tc, yb, w, h, 0.07, wood, M_PLAIN)
                for j in range(1, int(w / 0.16)):                                         # planches
                    put(tc - w / 2 + j * 0.16, yb, 0.025, h, 0.02, tuple(x * 0.75 for x in wood), M_PLAIN, 0.07)
                put(tc, yb, 0.05, h, 0.03, tuple(x * 0.7 for x in wood), M_PLAIN, 0.07)
                put(tc, yb + h, w + 0.2, 0.18, 0.12, (0.36, 0.27, 0.20), M_PLAIN)                # linteau bois
                garages.append((tc, yb))
    return garages, entry


def facades(m, ring, specs, gmin, wall_top, roof_top, box_mesh, rng, a, shut, ground, gable_ring=None):
    """Plusieurs façades percées (propriétés redessinées) : specs = [(arête de street_edge, jeton)]."""
    G = (lambda p: max(gmin, float(ground(p[0], p[1])))) if ground else (lambda p: gmin)
    P = [np.array(p, float) for p in ring]
    sides = sorted(float(np.linalg.norm(P[(k + 1) % len(P)] - P[k])) for k in range(len(P)))
    for se, spec in specs:
        A, B, nn, L = se[:4]
        gable_end = gable_ring is not None and L < sides[-1] - 0.3
        openings(m, A, B, nn, L, spec, gmin, wall_top, roof_top, gable_end, shut, G, box_mesh, rng, a)
