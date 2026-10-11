"""Ralentisseurs (OSM traffic_calming) : dos d'âne, ralentisseurs courts, plateaux surélevés, coussins berlinois.

Chaque ralentisseur est un relief posé sur la chaussée (avec collisions, il secoue la voiture) ; les marquages au sol
suivent ce relief grâce à `Calming.h(x, z)`, ajouté à l'altitude de la route. Rampes marquées de triangles blancs.
Dimensions : normes françaises (décret 94-447, guide CERTU) — dos d'âne 4 m × 10 cm, plateau rampes 1,5 m × 10 cm,
coussin 1,75 m × 3 m × 7 cm.
"""
import math
import numpy as np
from scipy.spatial import cKDTree
from furniture import _interp

CELL = 32.0
KINDS = {"hump", "bump", "table", "cushion"}


def _smooth(t):
    t = np.clip(t, 0.0, 1.0)
    return t * t * (3 - 2 * t)


class Calming:
    def __init__(self, ways, calm_json):
        """ways : voies (avec P, s, idx, nodes) ; calm_json : réponse Overpass traffic_calming."""
        self.f = []
        by_id = {w["id"]: w for w in ways}
        node_way = {}
        for w in ways:
            if w["bridge"]:
                continue
            for k, n in enumerate(w["nodes"]):
                node_way.setdefault(n, (w, w["s"][w["idx"][k]]))
        for e in calm_json["elements"]:
            kind = e.get("tags", {}).get("traffic_calming")
            if kind not in KINDS:
                continue
            if e["type"] == "node" and e["id"] in node_way:
                w, s = node_way[e["id"]]
                if kind == "table":
                    self._add(w, kind, s - 3.5, s + 3.5)
                else:
                    L = {"hump": 4.0, "bump": 1.0, "cushion": 3.0}[kind]
                    self._add(w, kind, s - L / 2, s + L / 2)
            elif e["type"] == "way" and e["id"] in by_id and kind == "table":
                w = by_id[e["id"]]
                s0, s1 = 0.0, float(w["s"][-1])
                if s1 < 5.0:
                    c = s1 / 2; s0, s1 = c - 2.5, c + 2.5
                self._add(w, kind, s0, s1)
        # index spatial : cellules -> ralentisseurs
        self.grid = {}
        for i, f in enumerate(self.f):
            mn = f["Q"].min(0) - f["hw"] - 1; mx = f["Q"].max(0) + f["hw"] + 1
            for cx in range(int(mn[0] // CELL), int(mx[0] // CELL) + 1):
                for cz in range(int(mn[1] // CELL), int(mx[1] // CELL) + 1):
                    self.grid.setdefault((cx, cz), []).append(i)

    def _add(self, w, kind, s0, s1):
        if not w["paved"] and kind != "table":
            return
        ss = np.arange(s0 - 0.6, s1 + 0.6 + 1e-6, 0.2)
        Q, T, N = [], [], []
        for s in ss:
            p, t, n = _interp(w, s)
            # au-delà des extrémités de la voie : prolongement en ligne droite
            if s < 0:
                p = p + t * s
            elif s > w["s"][-1]:
                p = p + t * (s - w["s"][-1])
            Q.append(p); T.append(t); N.append(n)
        Q = np.array(Q)
        self.f.append(dict(kind=kind, w=w, ss=ss, s0=s0, s1=s1, Q=Q, T=np.array(T), N=np.array(N),
                           hw=w["w"] / 2, two_way=not w["oneway"], tree=cKDTree(Q)))

    # profil (m) en fonction de l'abscisse u (le long) et du décalage v (en travers, + à droite)
    @staticmethod
    def profile(f, s, v):
        k = f["kind"]
        edge = _smooth((f["hw"] - np.abs(v)) / 0.35)                 # raccord en douceur au bord de chaussée
        if k == "hump":
            c = (f["s0"] + f["s1"]) / 2; u = (s - c) / 2.0
            return 0.10 * np.clip(1 - u * u, 0, 1) * edge
        if k == "bump":
            c = (f["s0"] + f["s1"]) / 2; u = (s - c) / 0.5
            return 0.07 * 0.5 * (1 + np.cos(np.pi * np.clip(u, -1, 1))) * edge
        if k == "table":
            up = _smooth((s - f["s0"]) / 1.5) * _smooth((f["s1"] - s) / 1.5)
            return 0.10 * up * edge
        if k == "cushion":
            c = (f["s0"] + f["s1"]) / 2
            lanes = (-f["hw"] / 2, f["hw"] / 2) if f["two_way"] else (0.0,)
            lon = _smooth((1.5 - np.abs(s - c)) / 0.6)
            h = 0.0
            for lc in lanes:
                h = np.maximum(h, _smooth((0.875 - np.abs(v - lc)) / 0.45))
            return 0.07 * lon * h
        return np.zeros_like(s)

    def _local(self, f, x, z):
        q = np.c_[x, z]
        d, i = f["tree"].query(q)
        rel = q - f["Q"][i]
        s = f["ss"][i] + np.einsum("ij,ij->i", rel, f["T"][i])
        v = np.einsum("ij,ij->i", rel, f["N"][i])
        return s, v

    def h(self, x, z):
        """Surélévation (m) due aux ralentisseurs aux points (x, z)."""
        x = np.atleast_1d(np.asarray(x, float)); z = np.atleast_1d(np.asarray(z, float))
        out = np.zeros(len(x))
        if not self.f:
            return out
        cx = np.floor(x / CELL).astype(int); cz = np.floor(z / CELL).astype(int)
        cand = set()
        for key in set(zip(cx.tolist(), cz.tolist())):
            cand.update(self.grid.get(key, ()))
        for i in cand:
            f = self.f[i]
            m = (np.abs(x - f["Q"][:, 0].mean()) < 60) & (np.abs(z - f["Q"][:, 1].mean()) < 60)
            if not m.any():
                continue
            s, v = self._local(f, x[m], z[m])
            inside = (s > f["ss"][0]) & (s < f["ss"][-1]) & (np.abs(v) < f["hw"])
            p = np.where(inside, self.profile(f, s, v), 0.0)
            out[m] = np.maximum(out[m], p)
        return out

    # ------------------------------------------------------------------------------------------ géométrie
    def build(self, tile_out, det_out, hroad):
        """Relief des ralentisseurs (tuile, avec collisions) et triangles blancs des rampes (détails)."""
        from build_roads import smooth_normals
        n = {}
        for f in self.f:
            n[f["kind"]] = n.get(f["kind"], 0) + 1
            hw = f["hw"]
            vs = np.linspace(-hw, hw, max(3, int(math.ceil(2 * hw / 0.35)) + 1))
            ss = f["ss"]
            S, V = np.meshgrid(ss, vs, indexing="ij")
            Q = f["Q"][:, None, :] + f["N"][:, None, :] * V[..., None]
            ns, nv = S.shape
            x = Q[..., 0].ravel(); z = Q[..., 1].ravel()
            y = hroad(x, z) + self.profile(f, S.ravel(), V.ravel()) + 0.012
            P = np.c_[x, y, z]
            I = []
            for a in range(ns - 1):
                for b in range(nv - 1):
                    i0 = a * nv + b; i1 = i0 + 1; i2 = i0 + nv + 1; i3 = i0 + nv
                    I += [i0, i2, i1, i0, i3, i2]
            I = np.array(I, np.uint32)
            # orientation vers le haut
            A, B, C = P[I[0::3]], P[I[1::3]], P[I[2::3]]
            if np.cross(B - A, C - A)[:, 1].mean() < 0:
                I = I.reshape(-1, 3)[:, ::-1].ravel()
            mat = "cushion" if f["kind"] == "cushion" else "asphalt"
            tile_out.add(mat, P, smooth_normals(P, I), np.c_[x, z], I, f["Q"][len(ss) // 2])
            # triangles blancs sur les rampes (dos d'âne et plateaux)
            if f["kind"] in ("hump", "table"):
                if f["kind"] == "hump":
                    c = (f["s0"] + f["s1"]) / 2; ramps = ((c - 2.0, c - 0.9), (c + 2.0, c + 0.9))
                else:
                    ramps = ((f["s0"], f["s0"] + 1.3), (f["s1"], f["s1"] - 1.3))
                nt = int((2 * hw - 0.4) // 1.0)
                for base, apex in ramps:
                    for j in range(nt):
                        vc = -hw + 0.2 + 0.5 + j * 1.0 + ((2 * hw - 0.4) - nt * 1.0) / 2
                        tri = [(base, vc - 0.25), (base, vc + 0.25), (apex, vc)]
                        pts = []
                        for s_, v_ in tri:
                            p, t, nn = _interp(f["w"], s_)
                            pts.append(p + nn * v_)
                        pts = np.array(pts)
                        yy = hroad(pts[:, 0], pts[:, 1]) + self.h(pts[:, 0], pts[:, 1]) + 0.03
                        P3 = np.c_[pts[:, 0], yy, pts[:, 1]]
                        I3 = [0, 1, 2] if np.cross(P3[1] - P3[0], P3[2] - P3[0])[1] > 0 else [0, 2, 1]
                        det_out.add("marking", P3, np.tile([0, 1, 0], (3, 1)), pts, I3, pts[0])
        return n
