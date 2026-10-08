"""Géométrie des autoroutes (appelé par build_roads.py), à la manière des jeux de conduite (Euro Truck Simulator) :

 - tracé : chaque chaussée est suivie de bout en bout (« chaîne » de voies OSM), densifiée tous les 3 m et lissée
   (rayons de plusieurs centaines de mètres au lieu des angles des polylignes OSM) ;
 - terre-plein central : les deux chaussées sont écartées si OSM les fait se chevaucher (3 m minimum entre les bords) ;
 - profil en long : lissage de Whittaker du relief (rayons verticaux de plusieurs km), les deux chaussées d'une même
   autoroute à la même altitude, déblais / remblais pris par le terrassement ; gabarit sous les ponts des autres routes
   et au-dessus des routes franchies ;
 - profil en travers : bande dérasée de gauche 1 m, voies de 3,5 m, bande d'arrêt d'urgence de 3 m ; largeur variable
   (biseau de 150 m quand le nombre de voies change) ;
 - bretelles : voie de décélération (biseau 80 m + voie parallèle 80 m) et d'accélération (voie parallèle 200 m +
   biseau 80 m) accolées à droite de la dernière voie (jamais à travers les voies) ; profil collé à celui de la
   chaussée tant qu'elles y sont accolées ; zébras au musoir.

Repère : x Est, z Sud ; pour une tangente T = (tx, tz), N = (-tz, tx) est à DROITE du sens de circulation.
"""
import math
from collections import defaultdict
import numpy as np
from scipy.ndimage import gaussian_filter1d
from scipy.spatial import cKDTree
import scipy.sparse as sp
import scipy.sparse.linalg as spl
from shapely.geometry import LineString
from shapely.strtree import STRtree

STEP = 3.0
LANE, BDG, BAU = 3.5, 1.0, 3.0           # voie, bande dérasée de gauche, bande d'arrêt d'urgence
LINK_L, LINK_R = 0.75, 1.75              # accotements revêtus d'une bretelle (gauche, droite)
MED_MIN = 3.0                            # terre-plein central minimal entre les bords revêtus (m)
DEC_PAR, DEC_TAP = 80.0, 80.0            # sortie : voie parallèle, biseau
ACC_PAR, ACC_TAP = 200.0, 80.0           # entrée
GMAX_LINK = 0.08
CLEAR = 6.4                              # dénivelé minimal chaussée -> tablier au-dessus (gabarit 5,3 m + tablier)
LAM_MW, LAM_LINK = 4.0e5, 4.0e3


def lanes_of(w, default):
    try:
        return max(1, int(str(w["tags"].get("lanes", default)).split(";")[0]))
    except ValueError:
        return default


def mw_width(n):
    return BDG + LANE * n + BAU


def link_width(n):
    return LINK_L + LANE * n + LINK_R


# ------------------------------------------------------------------------------------------------ outils
def frame(P):
    s = np.r_[0, np.cumsum(np.hypot(*np.diff(P, axis=0).T))]
    T = np.gradient(P, axis=0)
    T /= np.maximum(np.linalg.norm(T, axis=1, keepdims=True), 1e-9)
    R = np.c_[-T[:, 1], T[:, 0]]
    return s, T, R


def whittaker(g, wt, lam, fixed=None, soft=None):
    """min Σ wt (y-g)² + lam Σ (Δ²y)²  ; fixed : {indice: altitude} imposées ; soft : {indice: (altitude, poids)}."""
    n = len(g)
    wt = np.asarray(wt, float).copy(); g = np.asarray(g, float).copy()
    if fixed:
        for k, v in fixed.items():
            wt[k] = 1e6; g[k] = v
    if soft:
        for k, (v, p) in soft.items():
            g[k] = (g[k] * wt[k] + v * p) / (wt[k] + p); wt[k] += p
    if n < 4:
        return g
    if wt.sum() < 1e-9:
        wt[0] = wt[-1] = 1.0
    D = sp.diags([1.0, -2.0, 1.0], [0, 1, 2], shape=(n - 2, n))
    A = sp.diags(wt) + lam * (D.T @ D)
    return spl.spsolve(A.tocsc(), wt * g)


class Chain:
    """Chaussée continue : suite de voies OSM motorway bout à bout."""

    def __init__(self, ways):
        self.ways = ways

    def setup(self, P):
        self.P = P
        self.s, self.T, self.R = frame(P)
        self.tree = cKDTree(P)

    def at(self, s, arr):
        return np.interp(s, self.s, arr)

    def point(self, s, off):
        s = np.atleast_1d(np.asarray(s, float))
        P = np.c_[np.interp(s, self.s, self.P[:, 0]), np.interp(s, self.s, self.P[:, 1])]
        R = np.c_[np.interp(s, self.s, self.R[:, 0]), np.interp(s, self.s, self.R[:, 1])]
        R /= np.maximum(np.linalg.norm(R, axis=1, keepdims=True), 1e-9)
        return P + R * np.broadcast_to(np.asarray(off, float), s.shape)[:, None]

    def project(self, Q):
        """(abscisse, décalage à droite) des points Q sur l'axe."""
        Q = np.atleast_2d(Q)
        _, k = self.tree.query(Q)
        out_s, out_d = np.empty(len(Q)), np.empty(len(Q))
        for i, (q, kk) in enumerate(zip(Q, k)):
            best = None
            for a in (kk - 1, kk):
                if a < 0 or a + 1 >= len(self.P):
                    continue
                A, B = self.P[a], self.P[a + 1]
                v = B - A; L2 = max(float(v @ v), 1e-12)
                t = float(np.clip((q - A) @ v / L2, 0, 1))
                X = A + v * t
                dd = float(np.hypot(*(q - X)))
                if best is None or dd < best[0]:
                    Rr = np.array([-v[1], v[0]]) / math.sqrt(L2)
                    best = (dd, self.s[a] + t * (self.s[a + 1] - self.s[a]), float((q - X) @ Rr))
            out_s[i], out_d[i] = best[1], best[2]
        return out_s, out_d


def build_chains(ways):
    mw = [w for w in ways if w["cls"] == "motorway"]
    nxt = defaultdict(list); prv = defaultdict(list)
    for w in mw:
        nxt[w["nodes"][0]].append(w); prv[w["nodes"][-1]].append(w)
    seen = set(); chains = []
    for w in mw:
        if id(w) in seen:
            continue
        a = w; guard = 0
        while True:
            n0 = a["nodes"][0]
            if len(prv[n0]) != 1 or len(nxt[n0]) != 1 or id(prv[n0][0]) in seen or prv[n0][0] is w or guard > 1000:
                break
            a = prv[n0][0]; guard += 1
        seq = [a]; seen.add(id(a))
        while True:
            n1 = seq[-1]["nodes"][-1]
            if len(nxt[n1]) != 1 or len(prv[n1]) != 1 or id(nxt[n1][0]) in seen:
                break
            seq.append(nxt[n1][0]); seen.add(id(nxt[n1][0]))
        chains.append(Chain(seq))
    return chains


# ------------------------------------------------------------------------------------------------ tracé en plan
def align(N, ways):
    """Lisse les chaînes, écarte les chaussées qui se chevauchent, met à jour les nœuds (N) et prépare pour chaque voie
    d'autoroute : P_pre / idx_pre (polyligne à 3 m et rang des nœuds), hw_arr (demi-largeur), lanes_arr."""
    chains = build_chains(ways)
    for c in chains:
        P0, nd = [], []                  # sommets OSM de la chaîne ; nd[wi] = rangs (dans P0) des nœuds de la voie wi
        for wi, w in enumerate(c.ways):
            r = []
            for k, n in enumerate(w["nodes"]):
                if wi > 0 and k == 0:
                    r.append(len(P0) - 1); continue
                P0.append(N[n]); r.append(len(P0) - 1)
            nd.append(r)
        P0 = np.array(P0, float)
        dense, didx = [P0[0]], [0]
        for a, b in zip(P0[:-1], P0[1:]):
            L = float(np.hypot(*(b - a))); m = max(1, int(math.ceil(L / STEP)))
            for j in range(1, m + 1):
                dense.append(a + (b - a) * j / m)
            didx.append(len(dense) - 1)
        D = np.array(dense)
        s = np.r_[0, np.cumsum(np.hypot(*np.diff(D, axis=0).T))]
        # pas rigoureusement constant (le lissage et la régularisation du profil travaillent en indices)
        n = max(2, int(round(s[-1] / STEP)) + 1)
        su = np.linspace(0, s[-1], n)
        sn = s[didx]
        D = np.c_[np.interp(su, s, D[:, 0]), np.interp(su, s, D[:, 1])]
        s = su
        didx = list(np.clip(np.round(sn / max(su[1], 1e-6)).astype(int), 0, n - 1))
        for i in range(1, len(didx)):
            didx[i] = max(didx[i], didx[i - 1] + 1)
        if didx[-1] > n - 1:
            extra = didx[-1] - (n - 1)
            D = np.vstack([D, np.repeat(D[-1:], extra, 0) + np.arange(1, extra + 1)[:, None] * 0.01])
            s = np.r_[0, np.cumsum(np.hypot(*np.diff(D, axis=0).T))]
        sig = 30.0 / STEP
        S = np.c_[gaussian_filter1d(D[:, 0], sig, mode="nearest"), gaussian_filter1d(D[:, 1], sig, mode="nearest")]
        f = np.clip(np.exp(-(s / 40.0) ** 2) + np.exp(-((s[-1] - s) / 40.0) ** 2), 0, 1)[:, None]
        c.Psm = S * (1 - f) + D * f
        c.nd = [[didx[r] for r in rr] for rr in nd]
        hw = np.empty(len(D))
        for wi, w in enumerate(c.ways):
            a, b = c.nd[wi][0], c.nd[wi][-1]
            hw[a:b + 1] = mw_width(lanes_of(w, 2)) / 2
        c.lanes = np.round((hw * 2 - BDG - BAU) / LANE).astype(int)
        k = max(1, int(75 / STEP))
        c.hw = np.convolve(np.pad(hw, (k, k), mode="edge"), np.ones(2 * k + 1) / (2 * k + 1), mode="valid")
    # terre-plein central
    frames = [frame(c.Psm) for c in chains]
    allP = np.vstack([c.Psm for c in chains])
    own = np.concatenate([np.full(len(c.Psm), i) for i, c in enumerate(chains)])
    allT = np.vstack([f[1] for f in frames]); allH = np.concatenate([c.hw for c in chains])
    tree = cKDTree(allP)
    for ci, c in enumerate(chains):
        T, R = frames[ci][1], frames[ci][2]
        push = np.zeros(len(c.Psm)); twin = np.full(len(c.Psm), np.nan)
        for k, p in enumerate(c.Psm):
            best = None
            for j in tree.query_ball_point(p, 45.0):
                if own[j] == ci or allT[j] @ T[k] > -0.8:
                    continue
                lat = -float((allP[j] - p) @ R[k])        # > 0 : à gauche
                if lat > 0 and (best is None or lat < best[0]):
                    best = (lat, allH[j])
            if best:
                push[k] = max(0.0, (MED_MIN - (best[0] - c.hw[k] - best[1])) / 2)
                twin[k] = best[0]
        c.push = np.minimum(gaussian_filter1d(push, 40.0 / STEP, mode="nearest") * 1.25, 8.0)
        c.twin0 = twin
    for ci, c in enumerate(chains):
        c.setup(c.Psm + frames[ci][2] * c.push[:, None])
        c.twin = c.twin0 + 2 * c.push         # distance (à gauche) à l'axe de la chaussée opposée
    for c in chains:
        for wi, w in enumerate(c.ways):
            for k, n in enumerate(w["nodes"]):
                d = c.nd[wi][k]
                N[n] = (float(c.P[d, 0]), float(c.P[d, 1]))
            a, b = c.nd[wi][0], c.nd[wi][-1]
            w["P_pre"] = c.P[a:b + 1].copy()
            w["idx_pre"] = [d - a for d in c.nd[wi]]
            w["hw_arr"] = c.hw[a:b + 1].copy()
            w["lanes_arr"] = c.lanes[a:b + 1].copy()
            w["twin_arr"] = c.twin[a:b + 1].copy()
            w["chain_a"] = a
            w["chain"] = c
            w["w"] = float(c.hw[a:b + 1].max() * 2)
    return chains


# ------------------------------------------------------------------------------------------------ bretelles
def _ramp_path(start_way, exit_, links_from, links_to):
    """Suite de bretelles à partir de la chaussée (sens de la bretelle pour une sortie, sens inverse pour une entrée) :
    on suit la branche qui reste la plus proche de l'autoroute."""
    path = [start_way]; seen = {id(start_way)}
    L = start_way["s"][-1]
    while L < 450:
        w = path[-1]
        n = w["nodes"][-1] if exit_ else w["nodes"][0]
        cand = [v for v in (links_from[n] if exit_ else links_to[n]) if id(v) not in seen]
        if len(cand) != 1:
            break
        path.append(cand[0]); seen.add(id(cand[0])); L += cand[0]["s"][-1]
    return path


def ramps(ways, chains, N):
    """Voies d'accélération / de décélération. Modifie la géométrie des bretelles (w["P"], w["idx"]) et renvoie les
    nœuds déplacés {nœud: nouvelle position} (à propager aux autres voies). Remplit :
      chaîne : aux (voies auxiliaires), gores (polygones des zébras), rext (débord revêtu à droite au-delà de hw) ;
      bretelle : att_s / att_c (abscisse sur la chaîne des points accolés), noleft (pas de ligne de rive gauche)."""
    where = {}
    for c in chains:
        c.aux, c.gores = [], []
        c.rext = np.zeros(len(c.P))
        for wi, w in enumerate(c.ways):
            for k, n in enumerate(w["nodes"]):
                where.setdefault(n, (c, c.nd[wi][k]))
    links = [w for w in ways if w["cls"] == "motorway_link"]
    links_from = defaultdict(list); links_to = defaultdict(list)
    for l in links:
        l["w"] = link_width(lanes_of(l, 1))
        links_from[l["nodes"][0]].append(l); links_to[l["nodes"][-1]].append(l)
        l["att_s"] = np.full(len(l["P"]), np.nan)
        l["att_c"] = [None] * len(l["P"])
        l["noleft"] = np.zeros(len(l["P"]), bool)
        l["ext"] = [0, 0]
    moved = {}
    for l in links:
        for exit_ in (True, False):
            n = l["nodes"][0] if exit_ else l["nodes"][-1]
            if n in where:
                c, dj = where[n]
                if (exit_ and dj == len(c.P) - 1) or (not exit_ and dj == 0):
                    # bout de chaussée : la bretelle prolonge des voies (bifurcation / convergence)
                    sibl = links_from[n] if exit_ else links_to[n]
                    _fork(_ramp_path(l, exit_, links_from, links_to), exit_, c, dj, len(sibl), moved, N)
                else:
                    _ramp(_ramp_path(l, exit_, links_from, links_to), exit_, c, dj, moved, N, n)
    return links, moved


def _fork(path, exit_, c, dj, nsib, moved, N):
    """Bifurcation en bout de chaussée : chaque bretelle part du côté de la chaussée où elle va (bords alignés), puis
    rejoint son tracé OSM en 150 m."""
    P = np.vstack([w["P"] if exit_ else w["P"][::-1] for w in path])
    u = np.r_[0, np.cumsum(np.hypot(*np.diff(P, axis=0).T))]
    lw = path[0]["w"] / 2
    hw = float(c.hw[dj])
    if nsib < 2:
        off = 0.0
    else:
        k = int(np.searchsorted(u, min(60.0, u[-1] * 0.6)))
        _, dd = c.project(P[k:k + 1])
        off = (hw - lw) if dd[0] >= 0 else -(hw - lw)
    R = c.R[dj]
    t = np.clip(u / 150.0, 0, 1); f = 1 - t * t * (3 - 2 * t)
    newP = P + R[None, :] * (off * f)[:, None]
    off_i = 0
    for i, w in enumerate(path):
        n = len(w["P"])
        seg = newP[off_i:off_i + n]
        w["P"] = seg if exit_ else seg[::-1]
        off_i += n
        for j, nnode in enumerate(w["nodes"]):
            if i == 0 and ((exit_ and j == 0) or (not exit_ and j == len(w["nodes"]) - 1)):
                continue
            p = w["P"][w["idx"][j]]
            if np.hypot(*(p - np.asarray(N[nnode]))) > 0.05:
                moved[nnode] = (float(p[0]), float(p[1]))
    # profil : collé à la chaussée sur les premiers mètres
    w0 = path[0]
    s0 = np.r_[0, np.cumsum(np.hypot(*np.diff(w0["P"], axis=0).T))]
    for k in range(len(w0["P"])):
        uu = s0[k] if exit_ else s0[-1] - s0[k]
        if uu < 30.0:
            w0["att_s"][k] = c.s[dj]
            w0["att_c"][k] = c


def _ramp(path, exit_, c, dj, moved, N, node=None):
    # polyligne concaténée, orientée depuis l'autoroute
    segs = []
    for w in path:
        P = w["P"] if exit_ else w["P"][::-1]
        segs.append(P)
    P = np.vstack(segs)
    lw = path[0]["w"] / 2
    u = np.r_[0, np.cumsum(np.hypot(*np.diff(P, axis=0).T))]
    sj = float(c.s[dj])
    k30 = int(np.searchsorted(u, min(30.0, u[-1] * 0.5)))
    _, dd = c.project(P[k30:k30 + 1])
    if dd[0] < 0.5:                       # bretelle à gauche : laissée telle quelle
        print("  bretelle à gauche ou mal raccordée :", path[0]["id"], "sortie" if exit_ else "entrée", "d30=%.1f" % dd[0],
              "P", P[0].round())
        return
    hw = float(c.at(sj, c.hw))
    d_aux = hw - BAU + lw - LINK_L        # bord gauche de la voie de la bretelle sur le bord droit de la dernière voie
    kmax = int(np.searchsorted(u, min(u[-1], 450.0)))
    sm, dd = c.project(P[:kmax + 1])
    newP = P.copy()
    att = np.zeros(len(P), bool)
    stop = kmax + 1
    for k in range(kmax + 1):
        d = dd[k]
        du = u[k] - u[k - 1] if k > 0 else 0.0
        prog = (sm[k] - sm[k - 1]) * (1 if exit_ else -1) if k > 0 else 1.0
        if d > d_aux + 6.0 or (du > 0.5 and prog < 0.3 * du):
            stop = k; break
        x = (d - d_aux) / 1.5
        d2 = d_aux + 1.5 * (math.log1p(math.exp(x)) if x < 30 else x)
        if d > d_aux + 4.0:
            t = min(1.0, (d - d_aux - 4.0) / 2.0)
            d2 = d2 * (1 - t) + d * t
        newP[k] = c.point(sm[k], d2)[0]
    # voie parallèle + biseau, de l'autre côté du nœud
    par, tap = (DEC_PAR, DEC_TAP) if exit_ else (ACC_PAR, ACC_TAP)
    sgn = -1.0 if exit_ else 1.0
    d_start = hw - lw
    xs = np.arange(par + tap, 0.5, -STEP)
    se = sj + sgn * xs
    ok = (se >= 0) & (se <= c.s[-1])
    xs, se = xs[ok], se[ok]
    t = np.clip((xs - par) / tap, 0, 1); t = t * t * (3 - 2 * t)
    ext = c.point(se, d_aux + (d_start - d_aux) * t) if len(xs) else np.zeros((0, 2))
    full = np.vstack([ext, newP])
    ne = len(ext)
    smf, ddf = c.project(full)
    s_full = np.r_[0, np.cumsum(np.hypot(*np.diff(full, axis=0).T))]
    attached = (ddf - lw < hw + 0.3) & (np.arange(len(full)) < ne + stop)
    # fin de la partie accolée = début du terrain entre chaussée et bretelle
    k_at = ne
    while k_at < len(full) and attached[k_at]:
        k_at += 1
    att[:] = attached[ne:]
    sep = (ddf - lw + LINK_L > hw - BAU + 0.25)
    sep[:ne] = False
    k_sep = int(np.argmax(sep)) if sep.any() else len(full) - 1
    k_sep = min(k_sep, k_at)
    # zones de la chaîne
    s_lo = float(smf[0]); s_g0 = float(smf[k_sep]); s_g1 = float(smf[max(k_sep, k_at - 1)])
    c.aux.append((min(s_lo, s_g0), max(s_lo, s_g0), "sortie" if exit_ else "entrée", min(s_g0, s_g1), max(s_g0, s_g1),
                  path[0]["id"], node, sj))
    lo, hi = sorted((s_lo, float(smf[min(k_at, len(full) - 1)])))
    m = (c.s >= lo) & (c.s <= hi)
    if m.any():
        xs_, ys_ = smf[:k_at + 1], ddf[:k_at + 1] + lw
        o = np.argsort(xs_)
        c.rext[m] = np.maximum(c.rext[m], np.interp(c.s[m], xs_[o], ys_[o]) - c.hw[m])
    A, B = [], []
    for k in range(k_sep, min(k_at + 1, len(full))):
        A.append(c.point(smf[k], c.at(smf[k], c.hw) - BAU + 0.15)[0])
        r = _right(full, k)
        B.append(full[k] - r * (lw - LINK_L - 0.08))
    if len(A) >= 3:
        c.gores.append(np.vstack([np.array(A), np.array(B)[::-1]]))
    # retour dans chaque voie du chemin
    off = 0
    for i, w in enumerate(path):
        n = len(w["P"])
        seg = newP[off:off + n]; a_seg = att[off:off + n]
        sm_seg = smf[ne + off:ne + off + n]
        nol = np.zeros(n, bool)
        kk = np.arange(off, off + n) + ne
        nol[:] = kk < k_sep
        if i == 0:
            seg = np.vstack([ext, seg]); a_seg = np.r_[np.ones(ne, bool), a_seg]
            sm_seg = np.r_[smf[:ne], sm_seg]; nol = np.r_[np.ones(ne, bool), nol]
        if not exit_:
            seg = seg[::-1]; a_seg = a_seg[::-1]; sm_seg = sm_seg[::-1]; nol = nol[::-1]
        old_n = len(w["P"])
        w["P"] = seg
        add = len(seg) - old_n
        if add:
            # décale les rangs des nœuds (points ajoutés au début pour une sortie, à la fin pour une entrée)
            if exit_:
                w["idx"] = [k + add if j > 0 else add for j, k in enumerate(w["idx"])]
                w["ext"][0] = add
            else:
                w["ext"][1] = add
                w["idx"] = list(w["idx"][:-1]) + [len(seg) - 1 - add]
            w["att_s"] = np.r_[np.full(add, np.nan), w["att_s"]] if exit_ else np.r_[w["att_s"], np.full(add, np.nan)]
            w["att_c"] = ([None] * add + w["att_c"]) if exit_ else (w["att_c"] + [None] * add)
            w["noleft"] = np.r_[np.zeros(add, bool), w["noleft"]] if exit_ else np.r_[w["noleft"], np.zeros(add, bool)]
        for k in np.nonzero(a_seg)[0]:
            w["att_s"][k] = sm_seg[k]; w["att_c"][k] = c
        w["noleft"] |= nol
        off += n
        # nœuds intérieurs / de bout de chemin déplacés
        for j, nnode in enumerate(w["nodes"]):
            if (exit_ and j == 0 and i == 0) or (not exit_ and j == len(w["nodes"]) - 1 and i == 0):
                continue              # nœud sur l'autoroute : reste sur l'axe
            p = w["P"][w["idx"][j]]
            if np.hypot(*(p - np.asarray(N[nnode]))) > 0.05:
                moved[nnode] = (float(p[0]), float(p[1]))


def _right(P, k):
    a = P[max(0, k - 1)]; b = P[min(len(P) - 1, k + 1)]
    t = b - a; t = t / max(np.linalg.norm(t), 1e-9)
    return np.array([-t[1], t[0]])


def propagate(ways, moved, N):
    """Les autres voies raccordées à un nœud déplacé suivent en douceur (sur 40 m)."""
    for n, p in moved.items():
        old = np.asarray(N[n], float); new = np.asarray(p, float); dlt = new - old
        for w in ways:
            if n not in w["nodes"] or w.get("cls") == "motorway":
                continue
            k = w["idx"][w["nodes"].index(n)]
            if np.hypot(*(w["P"][k] - new)) < 0.05:
                continue
            s = np.r_[0, np.cumsum(np.hypot(*np.diff(w["P"], axis=0).T))]
            f = np.exp(-((s - s[k]) / 40.0) ** 2)
            w["P"] = w["P"] + dlt[None, :] * f[:, None]
        N[n] = (float(new[0]), float(new[1]))


# ------------------------------------------------------------------------------------------------ croisements
def crossings(ways):
    """Croisements dénivelés impliquant une autoroute ou une bretelle : [(haut, s_haut, bas, s_bas)]."""
    sel = [w for w in ways if len(w["P"]) > 1]
    ls = [LineString(w["P"]) for w in sel]
    tree = STRtree(ls)
    out = []
    for i, w in enumerate(sel):
        if w["cls"] not in ("motorway", "motorway_link"):
            continue
        for j in tree.query(ls[i]):
            o = sel[j]
            if o is w or (j < i and o["cls"] in ("motorway", "motorway_link")):
                continue
            if set(o["nodes"]) & set(w["nodes"]):
                continue
            x = ls[i].intersection(ls[j])
            if x.is_empty:
                continue
            pts = [x] if x.geom_type == "Point" else [g for g in getattr(x, "geoms", []) if g.geom_type == "Point"]
            for q in pts:
                sw, so = ls[i].project(q), ls[j].project(q)
                lw_ = (w["layer"] + (1 if w["bridge"] else 0)); lo_ = (o["layer"] + (1 if o["bridge"] else 0))
                if lw_ == lo_:
                    continue
                out.append((w, sw, o, so) if lw_ > lo_ else (o, so, w, sw))
    return out


def yat(w, s):
    return float(np.interp(s, w["s"], w["y"]))


# ------------------------------------------------------------------------------------------------ profil en long
def vertical(chains, dem, X):
    """Profils des chaussées : Whittaker (rayons de quelques km), jumelles à la même altitude, gabarits."""
    for c in chains:
        c.g = (dem.h(c.P[:, 0], c.P[:, 1]) * 2 + dem.h(*(c.P + c.R * (c.hw * 0.6)[:, None]).T)
               + dem.h(*(c.P - c.R * (c.hw * 0.6)[:, None]).T)) / 4
        br = np.zeros(len(c.P), bool)
        for wi, w in enumerate(c.ways):
            if w["bridge"]:
                br[c.nd[wi][0]:c.nd[wi][-1] + 1] = True
        c.bridge_mask = br
        c.wt = np.where(br, 0.0, 1.0)
        c.y = whittaker(c.g, c.wt, LAM_MW)
        c.tgt = c.g
        c.fixed = {}
    for it in range(2):
        allP = np.vstack([c.P for c in chains]); allY = np.concatenate([c.y for c in chains])
        own = np.concatenate([np.full(len(c.P), i) for i, c in enumerate(chains)])
        tree = cKDTree(allP)
        for ci, c in enumerate(chains):
            tgt = c.g.copy()
            ok = np.nonzero(np.isfinite(c.twin) & (c.twin < 45))[0]
            if len(ok):
                q = c.P[ok] - c.R[ok] * c.twin[ok, None]
                d, j = tree.query(q, k=6)
                for kk, dd, jj in zip(ok, d, j):
                    v = [allY[b] for a, b in zip(dd, jj) if own[b] != ci and a < 12]
                    if v:
                        tgt[kk] = 0.5 * (c.y[kk] + float(np.mean(v)))
            c.tgt = tgt
        for c in chains:
            c.y = whittaker(c.tgt, c.wt, LAM_MW)
    # gabarits avec les autres routes (leurs profils sont déjà calculés) : cibles douces sur ±60 m, renforcées
    # tant que le gabarit n'est pas atteint (la chaussée plonge ou monte en courbe douce, sans cassure)
    for c in chains:
        c.soft = {}
    for it in range(10):
        moved = False
        for c in chains:
            for (up, su, lo, sl) in X:
                if up["cls"] in ("motorway", "motorway_link") and lo["cls"] in ("motorway", "motorway_link"):
                    continue
                if up.get("chain") is c:
                    k = c.ways.index(up); s = c.s[c.nd[k][0]] + su; need = yat(lo, sl) + CLEAR + 0.15; sg = 1
                elif lo.get("chain") is c:
                    k = c.ways.index(lo); s = c.s[c.nd[k][0]] + sl; need = yat(up, su) - CLEAR - 0.15; sg = -1
                else:
                    continue
                kk = int(np.clip(np.searchsorted(c.s, s), 0, len(c.s) - 1))
                if (c.y[kk] - need) * sg < 0:
                    moved = True
                    for j in range(max(0, kk - 20), min(len(c.s), kk + 21)):
                        v, p = c.soft.get(j, (need, 0.0))
                        v = max(v, need) if sg > 0 else min(v, need)
                        c.soft[j] = (v, p + 20.0 * (1 + it))
        if not moved:
            break
        for c in chains:
            if c.soft:
                c.y = whittaker(c.tgt, c.wt, LAM_MW, soft=c.soft)
    for c in chains:
        for wi, w in enumerate(c.ways):
            a, b = c.nd[wi][0], c.nd[wi][-1]
            w["y"] = c.y[a:b + 1].copy()
            w["fixed_profile"] = True


def uniform(P, idx, step=STEP):
    """Rééchantillonne une polyligne à pas constant en gardant un point par nœud (rangs strictement croissants)."""
    s = np.r_[0, np.cumsum(np.hypot(*np.diff(P, axis=0).T))]
    if s[-1] < 1e-6:
        return P, idx
    n = max(2, int(round(s[-1] / step)) + 1)
    su = np.linspace(0, s[-1], n)
    Q = np.c_[np.interp(su, s, P[:, 0]), np.interp(su, s, P[:, 1])]
    k = list(np.clip(np.round(s[idx] / su[1]).astype(int), 0, n - 1))
    k[0] = 0; k[-1] = n - 1
    for i in range(1, len(k)):
        k[i] = max(k[i], k[i - 1] + 1)
    if k[-1] > n - 1:                       # nœuds très rapprochés : on garde les sommets d'origine
        return P, idx
    for i in range(len(k) - 2, 0, -1):
        k[i] = min(k[i], k[i + 1] - 1)
    for i, kk in enumerate(k):
        Q[kk] = P[idx[i]]
    return Q, k


def link_profiles(links, X, mw_node_y=None):
    """Profils de toutes les bretelles résolus ensemble (moindres carrés creux) : relief lissé, courbure pénalisée y
    compris d'une bretelle à la suivante, altitudes égales aux nœuds communs, collées à la chaussée tant qu'elles y
    sont accolées, gabarits (cibles renforcées tant qu'ils ne sont pas atteints)."""
    links = [l for l in links if len(l["P"]) >= 2]
    off = {}; n = 0
    for l in links:
        off[id(l)] = n; n += len(l["P"])
    at = defaultdict(list)                     # nœud -> [(bretelle, rang)]
    for l in links:
        for k, nd in zip(l["idx"], l["nodes"]):
            at[nd].append((l, k))
    soft = defaultdict(float); soft_v = {}
    pair_soft = []
    for it in range(8):
        rows, cols, vals, rhs = [], [], [], []
        r = 0

        def row(entries, b):
            nonlocal r
            for j, v in entries:
                rows.append(r); cols.append(j); vals.append(v)
            rhs.append(b); r += 1
        for l in links:
            o = off[id(l)]; m = len(l["P"])
            g = l["ground"]
            wd = 0.0 if l["bridge"] else math.sqrt(0.3)
            for k in range(m):
                c = l["att_c"][k]
                if c is not None:
                    row([(o + k, 1e3)], 1e3 * float(np.interp(l["att_s"][k], c.s, c.y)))
                elif wd:
                    row([(o + k, wd)], wd * g[k])
                key = (id(l), k)
                if mw_node_y and k in l["idx"]:
                    nd = l["nodes"][l["idx"].index(k)]
                    if nd in mw_node_y and l["att_c"][k] is None:
                        row([(o + k, 1e3)], 1e3 * mw_node_y[nd])
                if key in soft_v:
                    p = math.sqrt(soft[key]); row([(o + k, p)], p * soft_v[key])
            sl = math.sqrt(LAM_LINK)
            for k in range(m - 2):
                row([(o + k, sl), (o + k + 1, -2 * sl), (o + k + 2, sl)], 0.0)
        for nd, lst in at.items():
            if len(lst) < 2:
                continue
            (l0, k0) = lst[0]
            for (l1, k1) in lst[1:]:
                row([(off[id(l0)] + k0, 100.0), (off[id(l1)] + k1, -100.0)], 0.0)
            # continuité de courbure d'une bretelle à la suivante (fin de l'une = début de l'autre)
            ends = [(l, k) for l, k in lst if k == len(l["P"]) - 1]; starts = [(l, k) for l, k in lst if k == 0]
            if len(ends) == 1 and len(starts) == 1 and len(ends[0][0]["P"]) > 1 and len(starts[0][0]["P"]) > 1:
                la, lb = ends[0][0], starts[0][0]
                sl = math.sqrt(LAM_LINK)
                row([(off[id(la)] + len(la["P"]) - 2, sl), (off[id(la)] + len(la["P"]) - 1, -2 * sl),
                     (off[id(lb)] + 1, sl)], 0.0)
        for (la, ka, lb, kb, p) in pair_soft:
            q = math.sqrt(p)
            row([(off[id(la)] + ka, q), (off[id(lb)] + kb, -q)], q * (CLEAR + 0.15))
        M = sp.csr_matrix((vals, (rows, cols)), shape=(r, n))
        y = spl.spsolve((M.T @ M).tocsc(), M.T @ np.array(rhs))
        for l in links:
            l["y"] = y[off[id(l)]:off[id(l)] + len(l["P"])]
        # gabarits
        bad = 0
        for (up, su, lo, sl_) in X:
            ul, ll = up["cls"] == "motorway_link", lo["cls"] == "motorway_link"
            if not (ul or ll):
                continue
            d = yat(up, su) - yat(lo, sl_)
            if d >= CLEAR - 0.05:
                continue
            bad += 1
            if ul and ll:
                ku = int(np.clip(np.searchsorted(up["s"], su), 0, len(up["s"]) - 1))
                kl = int(np.clip(np.searchsorted(lo["s"], sl_), 0, len(lo["s"]) - 1))
                pair_soft.append((up, ku, lo, kl, 50.0 * (1 + it)))
                continue
            l, s0, need, sg = (up, su, yat(lo, sl_) + CLEAR + 0.15, 1) if ul else (lo, sl_, yat(up, su) - CLEAR - 0.15, -1)
            kk = int(np.clip(np.searchsorted(l["s"], s0), 0, len(l["s"]) - 1))
            for j in range(max(0, kk - 8), min(len(l["s"]), kk + 9)):
                key = (id(l), j)
                soft_v[key] = max(soft_v.get(key, need), need) if sg > 0 else min(soft_v.get(key, need), need)
                soft[key] += 20.0 * (1 + it)
        if not bad:
            break
    for l in links:
        l["fixed_profile"] = True


# ------------------------------------------------------------------------------------------------ marquages
def _poly_strip(out, hroad, P, R, s, s0, s1, off, width, step=1.5):
    """Bande peinte le long de la polyligne (P, R normale droite, s abscisses) entre s0 et s1 ; off : décalage à
    droite (scalaire ou tableau aligné sur P)."""
    if s1 - s0 < 0.2:
        return
    n = max(1, int(math.ceil((s1 - s0) / step)))
    ss = np.linspace(s0, s1, n + 1)
    Pc = np.c_[np.interp(ss, s, P[:, 0]), np.interp(ss, s, P[:, 1])]
    Rc = np.c_[np.interp(ss, s, R[:, 0]), np.interp(ss, s, R[:, 1])]
    Rc /= np.maximum(np.linalg.norm(Rc, axis=1, keepdims=True), 1e-9)
    o = np.interp(ss, s, off) if np.ndim(off) else np.full(len(ss), float(off))
    L = Pc + Rc * (o - width / 2)[:, None]; Rr = Pc + Rc * (o + width / 2)[:, None]
    Q = np.vstack([L, Rr])
    y = hroad(Q[:, 0], Q[:, 1]) + 0.025
    P3 = np.c_[Q[:, 0], y, Q[:, 1]]
    I = []
    for j in range(n):
        a, b, c, d = j, j + 1, n + 1 + j + 1, n + 1 + j
        I += [a, c, b, a, d, c]
    out.add("marking", P3, np.tile([0, 1, 0], (len(P3), 1)), Q, I, Q[n // 2])


def _spans_dashed(spans, on, off_, phase=0.0):
    out = []
    for a, b in spans:
        s = a + phase
        while s < b:
            out.append((s, min(s + on, b))); s += on + off_
    return out


def _mask_spans(s, m):
    """Tronçons [s0, s1] où le masque booléen m est vrai."""
    out = []; k = 0; n = len(m)
    while k < n:
        if m[k]:
            j = k
            while j + 1 < n and m[j + 1]:
                j += 1
            if j > k:
                out.append((float(s[k]), float(s[j])))
            k = j + 1
        else:
            k += 1
    return out


def _minus(spans, cuts):
    out = []
    for a, b in spans:
        cur = [(a, b)]
        for c0, c1 in cuts:
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


T1 = (3.0, 10.0)      # séparation des voies
T3 = (3.0, 1.33)      # voie d'insertion / de sortie
T4 = (39.0, 13.0)     # rive de la bande d'arrêt d'urgence (section courante)
U = 0.075             # unité de largeur sur autoroute


def markings(out, chains, ways, use, hroad):
    """Marquages des autoroutes et bretelles (règles françaises, u = 7,5 cm)."""
    import triangle as tr
    from shapely.geometry import Polygon, LineString as LS
    from shapely import affinity
    import mapbox_earcut as earcut
    n_gore = 0
    for c in chains:
        L = c.s[-1]
        full = [(0.0, L)]
        # rive gauche continue (3u)
        _poly_strip(out, hroad, c.P, c.R, c.s, 0, L, -c.hw + BDG, 3 * U)
        # séparation des voies (T1, 2u), là où la voie existe
        for i in range(1, int(c.lanes.max())):
            for a, b in _spans_dashed(_mask_spans(c.s, c.lanes > i), *T1):
                _poly_strip(out, hroad, c.P, c.R, c.s, a, b, -c.hw + BDG + LANE * i, 2 * U)
        # rive droite : T4 en section courante, T3 le long des voies auxiliaires, continue le long des zébras
        aux = [(a[0], a[1]) for a in c.aux]; gor = [(a[3], a[4]) for a in c.aux]
        base = _minus(full, aux + gor)
        off = c.hw - BAU
        for a, b in _spans_dashed(base, *T4):
            _poly_strip(out, hroad, c.P, c.R, c.s, a, b, off, 3 * U)
        for a, b in _spans_dashed(_minus(aux, gor), *T3):
            _poly_strip(out, hroad, c.P, c.R, c.s, a, b, off, 5 * U)
        for a, b in gor:
            _poly_strip(out, hroad, c.P, c.R, c.s, a, b, off, 3 * U)
        # zébras du musoir : bandes obliques à 45° tous les 4 m
        for G in c.gores:
            try:
                poly = Polygon(G).buffer(0)
            except Exception:
                continue
            if poly.is_empty or poly.area < 4:
                continue
            inner = poly.buffer(-0.25)
            if inner.is_empty:
                continue
            cx, cz = poly.centroid.x, poly.centroid.y
            k = int(np.argmin(np.hypot(c.P[:, 0] - cx, c.P[:, 1] - cz)))
            T = c.T[k]
            Dd = np.array([T[0] - T[1], T[1] + T[0]]) / math.sqrt(2)      # 45° vers la droite
            Nn = np.array([-Dd[1], Dd[0]])
            ext = max(poly.bounds[2] - poly.bounds[0], poly.bounds[3] - poly.bounds[1]) + 10
            for j in np.arange(-ext, ext, 4.0):
                o = np.array([cx, cz]) + Nn * j
                seg = LS([o - Dd * ext, o + Dd * ext]).intersection(inner)
                for g in getattr(seg, "geoms", [seg]):
                    if g.is_empty or g.geom_type != "LineString" or g.length < 0.3:
                        continue
                    bp = g.buffer(0.25, cap_style="flat")
                    for part in getattr(bp, "geoms", [bp]):
                        if part.geom_type != "Polygon":
                            continue
                        V = np.asarray(part.exterior.coords)[:-1]
                        I = earcut.triangulate_float64(V.astype(np.float64), np.array([len(V)], np.uint32))
                        if len(I) == 0:
                            continue
                        y = hroad(V[:, 0], V[:, 1]) + 0.026
                        P3 = np.c_[V[:, 0], y, V[:, 1]]
                        I = np.asarray(I, np.uint32).reshape(-1, 3)
                        a_, b_, c_ = P3[I[:, 0]], P3[I[:, 1]], P3[I[:, 2]]
                        flip = np.cross(b_ - a_, c_ - a_)[:, 1] < 0
                        I[flip] = I[flip][:, ::-1]
                        out.add("marking", P3, np.tile([0, 1, 0], (len(P3), 1)), V, I.ravel(), V[0])
            n_gore += 1
    # bretelles
    for w in ways:
        if w["cls"] != "motorway_link" or not w["paved"]:
            continue
        lw = w["w"] / 2; s = w["s"]; L = s[-1]
        cuts = []
        for k, n in zip(w["idx"], w["nodes"]):
            if use.get(n, 0) >= 2 and not (np.isfinite(w["att_s"][k]) if len(w["att_s"]) > k else False):
                others = [o for o in ways if o is not w and n in o["nodes"]]
                if any(o["cls"] not in ("motorway", "motorway_link") for o in others):
                    cuts.append((s[k] - lw - 5.0, s[k] + lw + 5.0))
                elif use.get(n, 0) >= 3:
                    cuts.append((s[k] - 2.0, s[k] + 2.0))
        left_ok = _minus(_mask_spans(s, ~w["noleft"]), cuts)
        right_ok = _minus([(0.0, L)], cuts)
        for a, b in left_ok:
            _poly_strip(out, hroad, w["P"], w["N"], s, a, b, -lw + LINK_L, 2 * U)
        for a, b in right_ok:
            _poly_strip(out, hroad, w["P"], w["N"], s, a, b, lw - LINK_R, 3 * U)
        n = lanes_of(w, 1)
        for i in range(1, n):
            for a, b in _spans_dashed(right_ok, *T1):
                _poly_strip(out, hroad, w["P"], w["N"], s, a, b, -lw + LINK_L + LANE * i, 2 * U)
    return n_gore


def export(chains):
    """Chaînes en dictionnaires simples (pour data/roads.pkl)."""
    return [dict(P=c.P, s=c.s, T=c.T, R=c.R, hw=c.hw, lanes=c.lanes, y=c.y, twin=c.twin, aux=c.aux, gores=c.gores,
                 rext=c.rext, bridge=c.bridge_mask, ways=[w["id"] for w in c.ways], ref=c.ways[0]["tags"].get("ref", ""))
            for c in chains]


# ------------------------------------------------------------------------------------------------ péages
PL_LANE, PL_ISL, PL_FLAT, PL_TAPER = 3.0, 1.3, 16.0, 34.0


def toll_plazas(ways):
    """Gares de péage (OSM barrier=toll_booth sur une bretelle ou une chaussée) : la route s'élargit en 2 voies
    (entrée : ticket) ou 3 voies (sortie : paiement) séparées par des îlots, sur ±16 m, raccordées en biseau sur 34 m.
    Chaque gare est une voie de plus (cls « service », tags toll / lanes / name) dont la largeur varie (hw_arr), qui
    suit le tracé et le profil de la bretelle."""
    import json, geo
    osm = json.load(open("data/osm_autoroute.json"))["elements"]
    cand = [w for w in ways if w["cls"] in ("motorway", "motorway_link") and len(w["P"]) > 1 and not w["bridge"]]
    nxt = defaultdict(list); prv = defaultdict(list)
    for w in cand:
        nxt[w["nodes"][0]].append(w); prv[w["nodes"][-1]].append(w)
    out = []
    for e in osm:
        if e["type"] != "node" or e["tags"].get("barrier") != "toll_booth":
            continue
        x, z = geo.to_local(e["lon"], e["lat"])
        best = None
        for w in cand:
            d = np.hypot(w["P"][:, 0] - x, w["P"][:, 1] - z)
            k = int(np.argmin(d))
            if best is None or d[k] < best[0]:
                best = (d[k], w, k)
        if best is None or best[0] > 15:
            continue
        _, w, k = best
        # polyligne prolongée de part et d'autre (voies qui se suivent) : ±60 m autour de la cabine
        P, Y = [w["P"]], [w["y"]]
        s0 = float(w["s"][k])
        def best(cs, ref, at_end):
            """Voie qui prolonge le mieux (moins de changement de cap)."""
            if not cs:
                return None
            return max(cs, key=lambda o: float(np.dot(o["T"][-1] if at_end else o["T"][0], ref)))
        a, L = w, 0.0
        while L < 60:
            c = best(prv.get(a["nodes"][0], []), a["T"][0], True)
            if c is None:
                break
            a = c; P.insert(0, a["P"][:-1]); Y.insert(0, a["y"][:-1]); s0 += a["s"][-1]; L += a["s"][-1]
        a, L = w, 0.0
        while L < 60:
            c = best(nxt.get(a["nodes"][-1], []), a["T"][-1], False)
            if c is None:
                break
            a = c; P.append(a["P"][1:]); Y.append(a["y"][1:]); L += a["s"][-1]
        P = np.vstack(P); Y = np.concatenate(Y)
        s = np.r_[0, np.cumsum(np.hypot(*np.diff(P, axis=0).T))]
        m = (s > s0 - PL_FLAT - PL_TAPER) & (s < s0 + PL_FLAT + PL_TAPER)
        if m.sum() < 4:
            continue
        P, Y, s = P[m], Y[m], s[m] - s0
        pay = w["cls"] == "motorway" or _is_exit(w, ways)
        n = 3 if pay else 2
        hp = (n * PL_LANE + (n - 1) * PL_ISL) / 2 + 0.7
        lw = w["w"] / 2
        t = np.clip((PL_FLAT + PL_TAPER - np.abs(s)) / PL_TAPER, 0, 1)
        t = t * t * (3 - 2 * t)
        hw = lw + (hp - lw) * t
        _, T, R = frame(P)
        out.append(dict(id=-(len(out) + 1), cls="service", nodes=[], idx=[], tags={
            "highway": "service", "name": "Péage de " + (e["tags"].get("name") or "l'autoroute"),
            "toll": "pay" if pay else "ticket", "lanes": str(n), "toll_s0": float(-s[0])},
            w=float(2 * hp), paved=True, bridge=False, layer=0, sidewalk=(0, 0), oneway=True,
            P=P, s=s - s[0], T=T, N=R, y=Y, ground=Y.copy(), hw_arr=hw, fixed_profile=True, plaza=True))
    return out


def _is_exit(w, ways):
    """Bretelle de sortie (paiement) ou d'entrée (ticket) : en aval de la cabine, la bretelle rejoint-elle d'abord le
    réseau local (sortie) ou l'autoroute (entrée) ? À défaut, même question vers l'amont."""
    at = defaultdict(list)
    for o in ways:
        for n in (o["nodes"][:1] + o["nodes"][-1:]) if o["nodes"] else []:
            at[n].append(o)
    def walk(start, down):
        seen, front, ev = {id(w)}, [(start, 0.0)], None
        while front:
            front.sort(key=lambda q: q[1])
            n, d = front.pop(0)
            if d > 2500:
                break
            for o in at.get(n, []):
                if id(o) in seen:
                    continue
                seen.add(id(o))
                if o["cls"] == "motorway":
                    return "autoroute"
                if not o["cls"].endswith("_link"):
                    return "local"
                front.append((o["nodes"][-1] if down else o["nodes"][0], d + o["s"][-1]))
        return None
    r = walk(w["nodes"][-1], True)
    if r:
        return r == "local"
    r = walk(w["nodes"][0], False)
    return r == "autoroute"


def plaza_markings(out, plazas, hroad):
    """Lignes continues dans l'axe des îlots (devant et derrière), ligne d'arrêt devant les barrières."""
    for w in plazas:
        n = int(w["tags"]["lanes"]); hp = w["w"] / 2; s0 = w["tags"]["toll_s0"]
        for j in range(n - 1):
            v = -hp + 0.7 + j * (PL_LANE + PL_ISL) + PL_LANE + PL_ISL / 2
            for a, b in ((s0 - 30, s0 - 8.5), (s0 + 8.5, s0 + 16)):
                _poly_strip(out, hroad, w["P"], w["N"], w["s"], max(a, 0), min(b, w["s"][-1]), v, 2 * U)
