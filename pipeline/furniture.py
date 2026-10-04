"""Marquages au sol et signalisation (données OSM réelles uniquement) : géométrie par tuile.

Marquages (règles françaises) :
 - axe : tirets T1 (3 m / 10 m) sur les routes bidirectionnelles principales, ligne continue en courbe serrée et à
   l'approche des carrefours ; rives : tirets T2 (3 m / 3,5 m) sur les primaires / secondaires / nationales ;
 - autoroute et bretelles : rives continues, séparation de voies en tirets (39 m / 13 m) ;
 - lignes d'arrêt (STOP, feux), lignes « cédez le passage » (tirets 0,5 m), passages piétons en bandes.
Panneaux : nœuds OSM highway=stop / give_way / traffic_signals / bus_stop, traffic_sign=city_limit / maxspeed /
FR:C115 / C114 / FR:A15b, et changements de vitesse maximale entre deux voies (B14).
"""
import math
import numpy as np
from signs_atlas import uv_cell, uv_city, SPEEDS

MARK_W = 0.12
JUNC_GAP = 4.0


def _interp(w, s):
    """Point, tangente, normale (droite) de la voie w à l'abscisse s."""
    s = float(np.clip(s, 0, w["s"][-1]))
    k = int(np.clip(np.searchsorted(w["s"], s) - 1, 0, len(w["s"]) - 2))
    t = (s - w["s"][k]) / max(w["s"][k + 1] - w["s"][k], 1e-9)
    P = w["P"][k] + (w["P"][k + 1] - w["P"][k]) * t
    T = w["P"][k + 1] - w["P"][k]; T = T / max(np.linalg.norm(T), 1e-9)
    return P, T, np.array([-T[1], T[0]])


class Out:
    """Accumulateur de primitives par tuile et par matériau : (positions, normales, uv, indices)."""
    def __init__(self, tile):
        self.tile = tile; self.d = {}

    def add(self, mat, P, Nn, UV, I, at):
        key = (int(at[0] // self.tile), int(at[1] // self.tile))
        g = self.d.setdefault(key, {}).setdefault(mat, [[], [], [], [], 0])
        g[0].append(np.asarray(P, np.float32)); g[1].append(np.asarray(Nn, np.float32))
        g[2].append(np.asarray(UV, np.float32)); g[3].append(np.asarray(I, np.uint32) + g[4]); g[4] += len(P)

    def prims(self, key):
        out = []
        for mat, g in self.d.get(key, {}).items():
            out.append((mat, np.vstack(g[0]), np.vstack(g[1]), np.vstack(g[2]), np.concatenate(g[3])))
        return out


# ------------------------------------------------------------------------------------------------ marquages
def _strip(out, w, hroad, s0, s1, off, width, mat="marking"):
    """Bande peinte le long de la voie entre s0 et s1, décalée de off (m, + à droite)."""
    if s1 - s0 < 0.2:
        return
    n = max(1, int(math.ceil((s1 - s0) / 1.5)))
    L, R = [], []
    for j in range(n + 1):
        P, T, Nn = _interp(w, s0 + (s1 - s0) * j / n)
        L.append(P + Nn * (off - width / 2)); R.append(P + Nn * (off + width / 2))
    Q = np.array(L + R)
    y = hroad(Q[:, 0], Q[:, 1]) + 0.025
    P3 = np.c_[Q[:, 0], y, Q[:, 1]]
    I = []
    for j in range(n):
        a, b, c, d = j, j + 1, n + 1 + j + 1, n + 1 + j
        I += [a, c, b, a, d, c]
    out.add(mat, P3, np.tile([0, 1, 0], (len(P3), 1)), np.c_[Q[:, 0], Q[:, 1]], I, Q[n // 2])


def _dashes(out, w, hroad, spans, off, width, on, offl, phase=0.0):
    for a, b in spans:
        s = a + phase
        while s < b:
            _strip(out, w, hroad, s, min(s + on, b), off, width)
            s += on + offl


def _curv_continuous(w):
    """Tronçons où l'axe doit être continu : courbe de rayon < 120 m (sur 20 m)."""
    T = np.arctan2(np.gradient(w["P"][:, 1]), np.gradient(w["P"][:, 0]))
    dT = np.abs((np.diff(np.unwrap(T))))
    ds = np.maximum(np.diff(w["s"]), 1e-6)
    curv = np.r_[dT / ds, 0]
    k = max(1, int(20 / 3))
    from scipy.ndimage import uniform_filter1d
    c = uniform_filter1d(curv, k, mode="nearest")
    return c > 1 / 120.0


def _subtract(spans, cut):
    out = []
    for a, b in spans:
        cur = [(a, b)]
        for c0, c1 in cut:
            nxt = []
            for x0, x1 in cur:
                if c1 <= x0 or c0 >= x1:
                    nxt.append((x0, x1))
                else:
                    if c0 > x0: nxt.append((x0, c0))
                    if c1 < x1: nxt.append((c1, x1))
            cur = nxt
        out += cur
    return out


def markings(out, ways, use, hroad, node_tags, crossing_ok):
    junc_s = {}
    for w in ways:
        cuts = []
        for k, n in enumerate(w["nodes"]):
            if use[n] >= 3 or (use[n] == 2 and 0 < k < len(w["nodes"]) - 1):
                s = w["s"][w["idx"][k]]
                cuts.append((s - w["w"] / 2 - JUNC_GAP, s + w["w"] / 2 + JUNC_GAP))
        w["cuts"] = cuts
    for w in ways:
        if not w["paved"] or w["cls"] in ("service", "track", "pedestrian", "living_street"):
            continue
        L = w["s"][-1]
        spans = _subtract([(0.0, L)], w["cuts"])
        hw = w["w"] / 2
        if w["cls"] == "motorway" or (w["oneway"] and w["cls"].endswith("_link")) or (w["oneway"] and w["cls"] == "trunk"):
            lanes = 2
            try:
                lanes = int(str(w["tags"].get("lanes", "2")).split(";")[0])
            except ValueError:
                pass
            if w["cls"].endswith("_link"):
                lanes = 1
            left = -hw + 0.5
            lane_w = 3.5 if w["cls"] == "motorway" else min(3.5, (w["w"] - 1.0) / lanes)
            for a, b in spans:
                _strip(out, w, hroad, a, b, left, 0.15)
                _strip(out, w, hroad, a, b, left + lanes * lane_w, 0.25 if w["cls"] == "motorway" else 0.15)
            for i in range(1, lanes):
                _dashes(out, w, hroad, spans, left + i * lane_w, 0.15, 39.0 if w["cls"] == "motorway" else 3.0,
                        13.0 if w["cls"] == "motorway" else 10.0)
            continue
        if w["oneway"]:
            continue
        main = w["cls"] in ("trunk", "primary", "secondary", "tertiary") or (w["cls"] == "unclassified" and w["w"] >= 5.5)
        if main and w["w"] >= 5.0:
            cont = _curv_continuous(w)
            # approche des carrefours : 15 m de ligne continue
            appr = np.zeros(len(w["s"]), bool)
            for c0, c1 in w["cuts"]:
                appr |= ((w["s"] > c0 - 15) & (w["s"] < c0)) | ((w["s"] > c1) & (w["s"] < c1 + 15))
            cont |= appr
            for a, b in spans:
                s = a
                while s < b:
                    k = int(np.clip(np.searchsorted(w["s"], s), 0, len(w["s"]) - 1))
                    if cont[k]:
                        e = s
                        while e < b and cont[int(np.clip(np.searchsorted(w["s"], e), 0, len(w["s"]) - 1))]:
                            e += 1.5
                        _strip(out, w, hroad, s, min(e, b), 0.0, MARK_W)
                        s = e
                    else:
                        _strip(out, w, hroad, s, min(s + 3.0, b), 0.0, MARK_W)
                        s += 13.0
        if w["cls"] in ("trunk", "primary", "secondary") and w["w"] >= 6.0:
            for sg in (1, -1):
                _dashes(out, w, hroad, spans, sg * (hw - 0.3), 0.15, 3.0, 3.5)
    # passages piétons, lignes d'arrêt et de cédez-le-passage
    n_cross = n_stop = 0
    for w in ways:
        if not w["paved"] or w["bridge"]:
            continue
        for k, n in enumerate(w["nodes"]):
            t = node_tags.get(n)
            if not t:
                continue
            s = w["s"][w["idx"][k]]
            hw = w["w"] / 2
            if t.get("highway") == "crossing" and t.get("crossing") in crossing_ok:
                o = -hw + 0.5
                while o < hw - 0.4:
                    _strip(out, w, hroad, s - 1.25, s + 1.25, o + 0.25, 0.5)
                    o += 1.0
                n_cross += 1
            elif t.get("highway") in ("stop", "give_way", "traffic_signals") and use[n] == 1 or \
                    (t.get("highway") in ("stop", "give_way") and use[n] >= 2):
                d = approach_dir(w, k, use, t)
                if d == 0:
                    continue
                se = s - d * 1.5 if use[n] >= 2 else s
                P, T, Nn = _interp(w, se)
                width = 0.5
                span = (0.0, hw - 0.2) if d > 0 else (-hw + 0.2, 0.0)
                if w["oneway"]:
                    span = (-hw + 0.2, hw - 0.2)
                _cross_line(out, P, T, Nn, span, width, hroad, dashed=t.get("highway") == "give_way")
                n_stop += 1
    return n_cross, n_stop


def _cross_line(out, P, T, Nn, span, width, hroad, dashed=False):
    a, b = span
    segs = [(a, b)] if not dashed else [(x, min(x + 0.5, b)) for x in np.arange(a, b, 1.0)]
    for x0, x1 in segs:
        Q = np.array([P + Nn * x0 - T * width / 2, P + Nn * x1 - T * width / 2, P + Nn * x1 + T * width / 2, P + Nn * x0 + T * width / 2])
        y = hroad(Q[:, 0], Q[:, 1]) + 0.03
        out.add("marking", np.c_[Q[:, 0], y, Q[:, 1]], np.tile([0, 1, 0], (4, 1)), Q, [0, 2, 1, 0, 3, 2], P)


def approach_dir(w, k, use, t=None):
    """+1 : la circulation concernée roule dans le sens de la voie ; -1 : sens inverse ; 0 : indéterminé."""
    d = (t or {}).get("direction")
    if d == "forward":
        return 1
    if d == "backward":
        return -1
    n = len(w["nodes"])
    if k == n - 1:
        return 1
    if k == 0:
        return -1
    s = w["s"][w["idx"][k]]
    fw = [w["s"][w["idx"][j]] - s for j in range(k + 1, n) if use[w["nodes"][j]] >= 2]
    bw = [s - w["s"][w["idx"][j]] for j in range(0, k) if use[w["nodes"][j]] >= 2]
    f = min(fw) if fw else 1e9; b = min(bw) if bw else 1e9
    if f == b == 1e9:
        return 1
    return 1 if f < b else -1


# ------------------------------------------------------------------------------------------------ panneaux
def _pole(out, x, z, y0, h, r=0.035, mat="metal"):
    n = 8; P, Nn, UV, I = [], [], [], []
    for j in range(n + 1):
        a = 2 * math.pi * j / n
        c, s = math.cos(a), math.sin(a)
        P += [(x + c * r, y0, z + s * r), (x + c * r, y0 + h, z + s * r)]
        Nn += [(c, 0, s), (c, 0, s)]; UV += [(j / n, 0), (j / n, h)]
    for j in range(n):
        a = 2 * j
        I += [a, a + 1, a + 3, a, a + 3, a + 2]
    out.add(mat, P, Nn, UV, I, (x, z))


def _panel(out, c, face, w, h, uv, mat, back=True):
    """Panneau plan centré en c (x, y, z), normale horizontale face (vers les usagers)."""
    f = np.array([face[0], 0, face[1]], float); f /= np.linalg.norm(f)
    r = np.array([-f[2], 0, f[0]])          # droite vue par l'usager qui regarde le panneau... (côté gauche du panneau)
    up = np.array([0, 1.0, 0])
    c = np.asarray(c, float) + f * 0.05
    u0, v0, du, dv = uv if len(uv) == 4 else (uv[0], uv[1], uv[2], uv[2])
    Q = [c - r * w / 2 - up * h / 2, c + r * w / 2 - up * h / 2, c + r * w / 2 + up * h / 2, c - r * w / 2 + up * h / 2]
    UV = [(u0 + du, v0 + dv), (u0, v0 + dv), (u0, v0), (u0 + du, v0)]
    out.add(mat, Q, [f] * 4, UV, [0, 2, 1, 0, 3, 2], (c[0], c[2]))
    if back:
        Qb = [q - f * 0.02 for q in Q]
        out.add("sign_back", Qb, [-f] * 4, [(0, 0)] * 4, [0, 1, 2, 0, 2, 3], (c[0], c[2]))


def _place(w, s, d, hw_extra):
    P, T, Nn = _interp(w, s)
    side = Nn * d                                    # droite du sens de circulation
    off = w["w"] / 2 + (1.6 if any(w["sidewalk"]) else 0.0) + hw_extra
    pos = P + side * off
    return pos, -T * d                               # face tournée vers les usagers qui arrivent


def signs(out, ways, use, hroad, node_tags, city_names, towns):
    stats = {}
    placed = []

    def put(kind, pos, face, w_=0.7, h=0.7, y_panel=2.0, uv=None, mat="sign", panels=None):
        if any(np.hypot(*(pos - q)) < 1.2 for q in placed[-400:]):
            return
        placed.append(pos)
        y0 = float(hroad(pos[0:1], pos[1:2])[0]) - 0.35
        _pole(out, pos[0], pos[1], y0, y_panel + 0.35 + h / 2 + 0.05)
        for (uvp, mp, ww, hh, yy, back) in (panels or [(uv or uv_cell(kind), mat, w_, h, y_panel, True)]):
            _panel(out, (pos[0], y0 + 0.35 + yy, pos[1]), face, ww, hh, uvp, mp, back)
        stats[kind] = stats.get(kind, 0) + 1

    by_node = {}
    for w in ways:
        for k, n in enumerate(w["nodes"]):
            by_node.setdefault(n, []).append((w, k))
    for n, t in node_tags.items():
        if n not in by_node:
            continue
        hwy = t.get("highway"); ts = str(t.get("traffic_sign", ""))
        lst = [(w, k) for w, k in by_node[n] if not w["bridge"]]
        if not lst:
            continue
        w, k = min(lst, key=lambda wk: 0 if 0 < wk[1] < len(wk[0]["nodes"]) - 1 else 1)
        s = w["s"][w["idx"][k]]
        if hwy in ("stop", "give_way"):
            if use[n] >= 2:                        # nœud du carrefour : panneau sur chaque voie qui n'est pas prioritaire
                cand = [(w2, k2) for w2, k2 in by_node[n] if w2["cls"] in ("residential", "unclassified", "service", "track", "living_street", "tertiary")]
                w, k = (cand or lst)[0]
                s = w["s"][w["idx"][k]]
            d = approach_dir(w, k, use, t)
            if d == 0:
                continue
            pos, face = _place(w, s - d * 2.0, d, 0.6)
            put("stop" if hwy == "stop" else "give_way", pos, face, 0.8, 0.8, 1.7)
        elif hwy == "traffic_signals":
            dirs = [approach_dir(w, k, use, t)] if use[n] == 1 else [1, -1]
            for w2, k2 in (lst if use[n] >= 2 else [(w, k)]):
                for d in ([approach_dir(w2, k2, use, t)] if use[n] >= 2 else dirs):
                    s2 = w2["s"][w2["idx"][k2]]
                    pos, face = _place(w2, s2 - d * 4.0, d, 0.5)
                    if any(np.hypot(*(pos - q)) < 1.2 for q in placed[-400:]):
                        continue
                    placed.append(pos)
                    y0 = float(hroad(pos[0:1], pos[1:2])[0]) - 0.35
                    _pole(out, pos[0], pos[1], y0, 3.3, r=0.06, mat="metal_dark")
                    _signal_head(out, pos, y0 + 0.35 + 2.55, face)
                    stats["feux"] = stats.get("feux", 0) + 1
        elif hwy == "bus_stop":
            d = 1
            pos, face = _place(w, s, d, 0.8)
            put("bus", pos, face, 0.55, 0.55, 2.1)
        elif ts == "city_limit" and t.get("name") in city_names:
            # entrée face aux usagers qui vont vers le centre de la commune, sortie au dos
            town = towns.get(t["name"])
            d = approach_dir(w, k, use, t)
            if town is not None and "direction" not in t:
                Pf, _, _ = _interp(w, s + 30); Pb, _, _ = _interp(w, s - 30)
                d = 1 if np.hypot(*(Pf - town)) < np.hypot(*(Pb - town)) else -1
            pos, face = _place(w, s, d, 0.8)
            put("city", pos, face, panels=[(uv_city(city_names, t["name"]), "sign_city", 1.4, 0.7, 2.0, False),
                                          (uv_city(city_names, t["name"], True), "sign_city", 1.4, 0.7, 2.0, False)][:1])
            # dos : sortie d'agglomération
            _panel(out, (pos[0], float(hroad(pos[0:1], pos[1:2])[0]) + 2.0, pos[1]), -face, 1.4, 0.7,
                   uv_city(city_names, t["name"], True), "sign_city", back=False)
        elif ts.startswith("FR:C115") or ts.startswith("FR:C114") or ts == "C114" or ts.startswith("FR:A15"):
            kind = "voie_verte" if "C115" in ts else ("fin_voie_verte" if "C114" in ts else "cerf")
            d = approach_dir(w, k, use, t)
            pos, face = _place(w, s, d, 0.6)
            put(kind, pos, face, 0.7, 0.7 if kind != "cerf" else 0.75, 2.0)
        elif ts == "maxspeed" or ts.startswith("FR:B14"):
            v = t.get("maxspeed") or w["tags"].get("maxspeed")
            if v and v.isdigit() and int(v) in SPEEDS:
                d = approach_dir(w, k, use, t)
                pos, face = _place(w, s, d, 0.6)
                put("b14_%s" % v, pos, face, 0.7, 0.7, 2.0)
    # changements de vitesse maximale entre deux voies qui se prolongent : B14 au début de la nouvelle limite
    for n, lst in by_node.items():
        if len(lst) != 2 or use[n] != 2:
            continue
        (a, ka), (b, kb) = lst
        va, vb = a["tags"].get("maxspeed"), b["tags"].get("maxspeed")
        if not (va and vb and va.isdigit() and vb.isdigit()) or va == vb:
            continue
        for (src, ks), (dst, kd), v in (((a, ka), (b, kb), vb), ((b, kb), (a, ka), va)):
            if int(v) not in SPEEDS or dst["bridge"]:
                continue
            # sens de circulation sur dst en s'éloignant du nœud
            d = 1 if kd == 0 else -1
            if dst["oneway"] and d == -1:
                continue
            s = dst["s"][dst["idx"][kd]] + d * 6.0
            pos, face = _place(dst, s, d, 0.6)
            put("b14_%s" % v, pos, face, 0.7, 0.7, 2.0)
    return stats


def _signal_head(out, pos, y, face):
    """Feu tricolore : caisson noir, trois feux (rouge, orange, vert) animés dans Godot (matériaux light_*)."""
    f = np.array([face[0], 0, face[1]], float); f /= np.linalg.norm(f)
    r = np.array([-f[2], 0, f[0]]); up = np.array([0, 1.0, 0])
    c = np.array([pos[0], y, pos[1]]) + f * 0.12
    # caisson (boîte)
    hx, hy, hz = 0.16, 0.48, 0.12
    corners = lambda sx, sy, sz: c + r * sx * hx + up * sy * hy + f * sz * hz
    faces = [(f, [(-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)]), (-f, [(1, -1, -1), (-1, -1, -1), (-1, 1, -1), (1, 1, -1)]),
             (r, [(1, -1, 1), (1, -1, -1), (1, 1, -1), (1, 1, 1)]), (-r, [(-1, -1, -1), (-1, -1, 1), (-1, 1, 1), (-1, 1, -1)]),
             (up, [(-1, 1, 1), (1, 1, 1), (1, 1, -1), (-1, 1, -1)])]
    for nrm, cs in faces:
        out.add("metal_dark", [corners(*q) for q in cs], [nrm] * 4, [(0, 0)] * 4, [0, 1, 2, 0, 2, 3], pos)
    for i, mat in enumerate(("light_red", "light_amber", "light_green")):
        cc = c + f * (hz + 0.005) + up * (0.30 - i * 0.30)
        m = 10; P = [cc]; Nn = [f]; UV = [(0.5, 0.5)]; I = []
        for j in range(m + 1):
            a = 2 * math.pi * j / m
            P.append(cc + r * math.cos(a) * 0.1 + up * math.sin(a) * 0.1); Nn.append(f); UV.append((0, 0))
        for j in range(1, m + 1):
            I += [0, j, j + 1]
        out.add(mat, P, Nn, UV, I, pos)
