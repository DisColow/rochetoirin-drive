"""Renault Espace I (1984-1988), d'après la photo de l'utilisateur (la voiture de son père) : modèle procédural.
Caisse « monocorps » : sections transversales lissées le long de la voiture (capot court et pentu, pare-brise très
incliné, toit plat, hayon vertical), carrosserie rouge foncé, tout le bas (boucliers, bas de caisse) beige doré,
calandre rouge à lamelles, phares carrés et clignotants orange, antibrouillards jaunes, jantes tôle à enjoliveurs.
Cotes réelles : longueur 4,25 m, largeur 1,77 m, hauteur 1,66 m, empattement 2,58 m, voies 1,47 m.
Sorties : ../godot/assets/car/{body,wheel}.glb + meta.json (repère : x à droite, y en haut, avant vers -z, origine au
sol au milieu de l'empattement ; matériaux nommés, remplacés dans car.gd)."""
import json, math, os
import numpy as np
from glb import write_glb

OUT = "../godot/assets/car"
WB = 2.58
TRACK = 1.47
R = 0.30                       # rayon de roue (185/70 R14 env.)
ZF, ZR = -2.16, 2.09           # bouclier avant, hayon
BELT = 1.05                    # ligne de ceinture (bas des vitres)
BEIGE_TOP = 0.55               # limite rouge / beige doré
ARCH_R = 0.36
ARCHES = (-WB / 2, WB / 2)


class Builder:
    def __init__(self):
        self.m = {}

    def tri(self, mat, a, b, c, n=None, uv=None):
        a, b, c = (np.asarray(v, np.float64) for v in (a, b, c))
        cr = np.cross(b - a, c - a)
        L = np.linalg.norm(cr)
        if L < 1e-9:
            return
        if n is not None and np.dot(cr, n) < 0:
            b, c = c, b; cr = -cr
        nn = cr / L
        d = self.m.setdefault(mat, dict(P=[], N=[], UV=[], C=[]))
        for v in (a, b, c):
            d["P"].append(v); d["N"].append(nn); d["UV"].append((v[0] + v[2], v[1]) if uv is None else uv); d["C"].append((1, 1, 1))

    def quad(self, mat, a, b, c, d, n=None, col=None):
        k0 = len(self.m.get(mat, {"P": []})["P"])
        self.tri(mat, a, b, c, n); self.tri(mat, a, c, d, n)
        if col is not None and mat in self.m:
            for i in range(k0, len(self.m[mat]["C"])):
                self.m[mat]["C"][i] = col

    def box(self, mat, c, s, col=None):
        """Pavé centré en c, demi-tailles s."""
        c = np.asarray(c, float); s = np.asarray(s, float)
        for ax in range(3):
            for sg in (-1, 1):
                n = np.zeros(3); n[ax] = sg
                u = np.zeros(3); u[(ax + 1) % 3] = s[(ax + 1) % 3]
                v = np.zeros(3); v[(ax + 2) % 3] = s[(ax + 2) % 3]
                f = c + n * s[ax]
                self.quad(mat, f - u - v, f + u - v, f + u + v, f - u + v, n, col)

    def prims(self, smooth=("paint", "beige", "glass")):
        out = []
        for mat, d in self.m.items():
            P = np.array(d["P"], np.float32); N = np.array(d["N"], np.float32)
            if mat in smooth:
                N = smooth_normals(P, N)
            out.append((mat, P, N, np.array(d["UV"], np.float32), np.arange(len(P), dtype=np.uint32),
                        np.array(d["C"], np.float32)))
        return out


def smooth_normals(P, N, max_angle=38.0):
    """Normales lissées entre faces voisines (même position) si l'angle est faible : carrosserie galbée, arêtes vives
    gardées (angle > max_angle)."""
    key = np.round(P / 0.002).astype(np.int64)
    _, inv = np.unique(key, axis=0, return_inverse=True)
    inv = inv.ravel()
    acc = np.zeros((inv.max() + 1, 3)); np.add.at(acc, inv, N)
    out = N.copy()
    cosm = math.cos(math.radians(max_angle))
    # moyenne restreinte : pour chaque sommet, somme des normales voisines proches de la sienne
    groups = {}
    for i, g in enumerate(inv):
        groups.setdefault(g, []).append(i)
    for idx in groups.values():
        if len(idx) < 2:
            continue
        Ng = N[idx]
        dots = Ng @ Ng.T
        for a, i in enumerate(idx):
            m = Ng[dots[a] > cosm].sum(0)
            out[i] = m / max(np.linalg.norm(m), 1e-9)
    return out.astype(np.float32)


# ------------------------------------------------------------------------------------------------ silhouette
def top(z):
    """Hauteur du dessus de caisse (bouclier, calandre, capot, pare-brise, toit) selon z."""
    pts = [(-2.16, 0.56), (-2.13, 0.58), (-2.115, 0.80), (-2.04, 0.86), (-1.44, 1.03), (-0.52, 1.60),
           (-0.30, 1.645), (1.80, 1.655), (2.02, 1.63), (2.09, 1.58)]
    zs, ys = zip(*pts)
    return float(np.interp(z, zs, ys))


def half_w(z):
    zs = [-2.16, -2.12, -2.0, -1.6, 1.8, 2.0, 2.09]
    ws = [0.82, 0.855, 0.875, 0.885, 0.885, 0.875, 0.86]
    return float(np.interp(z, zs, ws))


def bottom(z):
    return float(np.interp(z, [-2.16, -1.9, 1.85, 2.09], [0.26, 0.21, 0.21, 0.28]))


def profile(z):
    """Demi-section droite (x, y) du bas au milieu vers le haut au milieu."""
    yt, w, yb = top(z), half_w(z), bottom(z)
    s = float(np.clip((yt - 1.1) / 0.4, 0, 1))           # rentrée de caisse au-dessus de la ceinture
    lv = lambda y: min(y, yt - 0.03)
    low = [(w, lv(y)) for y in (0.33, 0.40, 0.47, BEIGE_TOP, 0.61, 0.67, 0.73)]     # fin : passages de roue ronds
    return [(0.0, yb), (w - 0.07, yb), (w, yb + 0.07)] + low + [(w, lv(0.80)), (w - 0.01, lv(BELT)),
            (w - 0.09 * s - 0.01, yt - 0.10 * s - 0.03), (w - 0.06 - 0.12 * s, yt), (0.0, yt)]


WSH = (-1.44, -0.52)          # pare-brise
PILLARS = [(-0.42, -0.30), (0.80, 0.90), (1.98, 2.10)]     # montants B, C, D


def side_mat(c, n, z):
    y = c[1]
    if n[1] < -0.9:
        return "plastic"                                     # dessous
    if y < BEIGE_TOP - 0.005:
        return "beige"
    if WSH[0] < z < WSH[1] and n[1] > 0.35:
        return "glass" if abs(c[0]) < half_w(z) - 0.06 else "plastic"   # pare-brise et montants A (fins)
    if abs(n[0]) > 0.5 and BELT + 0.02 < y < top(z) - 0.06 and z > WSH[0] + 0.05:
        if any(a <= z <= b for a, b in PILLARS):
            return "plastic"
        return "glass"
    return "paint"


def body(B):
    zs = sorted(set(np.round(np.r_[np.linspace(ZF, ZR, 200), [ZF, -2.13, -2.115, -2.04, -1.44, -0.52, -0.30, 1.8, 2.02, ZR],
                                   [p for ab in PILLARS for p in ab], list(WSH)], 4)))
    rings = []
    for z in zs:
        h = profile(z)
        ring = [(x, y) for x, y in h] + [(-x, y) for x, y in reversed(h[1:-1])]
        rings.append((z, ring))
    for (z0, r0), (z1, r1) in zip(rings[:-1], rings[1:]):
        k = len(r0)
        for j in range(k):
            a = (r0[j][0], r0[j][1], z0); b = (r0[(j + 1) % k][0], r0[(j + 1) % k][1], z0)
            c = (r1[(j + 1) % k][0], r1[(j + 1) % k][1], z1); d = (r1[j][0], r1[j][1], z1)
            cen = np.mean([a, b, c, d], axis=0)
            zm = cen[2]
            mid = np.array([0.0, (bottom(zm) + top(zm)) / 2, zm])
            out = cen - mid; out[2] = 0
            if np.linalg.norm(out) < 1e-6:
                continue
            # passages de roue : pas de tôle dans le cercle
            if abs(cen[0]) > 0.6 and any(math.hypot(zm - za, cen[1] - R) < ARCH_R for za in ARCHES):
                continue
            nrm = np.cross(np.subtract(b, a), np.subtract(d, a))
            if np.dot(nrm, out) < 0:
                nrm = -nrm
            nrm = nrm / max(np.linalg.norm(nrm), 1e-9)
            B.quad(side_mat(cen, nrm, zm), a, b, c, d, out)
    # faces avant (bouclier) et arrière (hayon) : bandes horizontales entre profils symétriques
    for z, sgn in ((zs[0], -1), (zs[-1], 1)):
        h = profile(z)
        for j in range(len(h) - 1):
            (xa, ya), (xb, yb_) = h[j], h[j + 1]
            if abs(yb_ - ya) < 1e-4 and j != 0:
                pass
            ym = (ya + yb_) / 2
            if sgn > 0:
                mat = "beige" if ym < BEIGE_TOP else ("glass" if 0.97 < ym < 1.50 else "paint")
            else:
                mat = "beige"
            B.quad(mat, (-xa, ya, z), (xa, ya, z), (xb, yb_, z), (-xb, yb_, z), (0, 0, sgn))
    # lunette arrière : vitre en bande sur toute la largeur, montants noirs sur les bords
    # (la face arrière est découpée en bandes au niveau des points du profil : on ajoute la vitre en applique)
    z = ZR + 0.003
    B.quad("glass", (-0.76, 0.98, z), (0.76, 0.98, z), (0.72, 1.50, z), (-0.72, 1.50, z), (0, 0, 1))
    # creux des passages de roue (noirs)
    for za in ARCHES:
        for sx in (-1, 1):
            w = half_w(za)
            n = 14
            for i in range(n):
                t0 = math.pi * i / n; t1 = math.pi * (i + 1) / n
                p0 = (za - ARCH_R * math.cos(t0), R + ARCH_R * math.sin(t0)); p1 = (za - ARCH_R * math.cos(t1), R + ARCH_R * math.sin(t1))
                xo, xi = sx * (w + 0.002), sx * (w - 0.26)
                B.quad("plastic", (xo, p0[1], p0[0]), (xi, p0[1], p0[0]), (xi, p1[1], p1[0]), (xo, p1[1], p1[0]),
                       (0, -(p0[1] - R), -(p0[0] - za)))
            # joue intérieure
            B.quad("plastic", (sx * (w - 0.26), R - 0.05, za - ARCH_R), (sx * (w - 0.26), R - 0.05, za + ARCH_R),
                   (sx * (w - 0.26), R + ARCH_R, za + ARCH_R), (sx * (w - 0.26), R + ARCH_R, za - ARCH_R), (sx, 0, 0))


def details(B):
    zf = -2.125
    # joints de carrosserie (portes avant et arrière, hayon) : fines lignes sombres
    for sx in (-1, 1):
        for zj in (-1.42, -0.36, 0.84):
            w = half_w(zj) + 0.003
            B.box("plastic", (sx * w, (BEIGE_TOP + BELT) / 2 - 0.08, zj), (0.003, (BELT - BEIGE_TOP) / 2 + 0.2, 0.006))
        # monogramme « Espace » sur l'aile avant
        B.box("chrome", (sx * (half_w(-1.75) + 0.004), 0.78, -1.78), (0.003, 0.015, 0.09))
        # baguette de protection noire en haut du bas de caisse beige
        B.box("plastic", (sx * (half_w(0.0) + 0.006), BEIGE_TOP + 0.005, 0.0), (0.006, 0.012, 1.6))
    B.box("plastic", (0, 0.43, ZR + 0.003), (0.6, 0.004, 0.003))
    # bandeau caoutchouc noir sur le bouclier avant et arrière
    B.box("plastic", (0, BEIGE_TOP - 0.01, ZF - 0.004), (0.80, 0.014, 0.008))
    B.box("plastic", (0, BEIGE_TOP - 0.01, ZR + 0.006), (0.80, 0.014, 0.008))
    # calandre : fond noir, 5 lamelles rouges, losange Renault
    B.box("plastic", (0, 0.685, zf + 0.012), (0.43, 0.085, 0.006))
    for k in range(5):
        y = 0.615 + k * 0.034
        B.box("paint", (0, y, zf), (0.42, 0.010, 0.010))
    B.box("chrome", (0, 0.685, zf - 0.012), (0.035, 0.035, 0.006))
    # phares carrés et clignotants orange (enveloppants)
    for sx in (-1, 1):
        B.box("lamp", (sx * 0.585, 0.685, zf), (0.115, 0.085, 0.008))
        B.box("plastic", (sx * 0.585, 0.685, zf + 0.004), (0.125, 0.095, 0.006))
        B.box("orange", (sx * 0.76, 0.685, zf + 0.004), (0.06, 0.085, 0.01))
        B.box("orange", (sx * (half_w(-2.08) + 0.003), 0.685, -2.06), (0.006, 0.07, 0.05))
        # antibrouillards jaunes sous le bouclier
        B.box("fog", (sx * 0.55, 0.30, ZF - 0.008), (0.085, 0.03, 0.01))
        # rétroviseurs
        B.box("plastic", (sx * 0.935, 1.10, -1.30), (0.03, 0.05, 0.075))
        B.box("plastic", (sx * 0.90, 1.07, -1.32), (0.03, 0.014, 0.025))
        # poignées de portes
        for zh in (-0.62, 0.62):
            B.box("plastic", (sx * (0.888), 0.99, zh), (0.006, 0.015, 0.07))
        # feux arrière verticaux (rouge, orange en haut)
        B.box("tail", (sx * 0.74, 0.72, ZR + 0.008), (0.10, 0.14, 0.01))
        B.box("orange", (sx * 0.74, 0.90, ZR + 0.008), (0.10, 0.04, 0.01))
        # essuie-glace
        B.box("plastic", (sx * 0.30, 1.06, -1.40), (0.25, 0.008, 0.012))
    # plaques
    B.box("plate_front", (0, 0.43, ZF - 0.006), (0.26, 0.055, 0.004), col=(0.95, 0.95, 0.95))
    B.box("plate_rear", (0, 0.43, ZR + 0.006), (0.26, 0.055, 0.004), col=(0.95, 0.95, 0.95))
    # habitacle : plancher, planche de bord, 7 places (sièges gris-beige), cloison de coffre
    seat = (0.42, 0.40, 0.37); dark = (0.10, 0.10, 0.11)
    B.box("interior", (0, 0.36, 0.0), (0.84, 0.02, 1.95), col=dark)
    B.box("interior", (0, 0.93, -1.28), (0.84, 0.10, 0.18), col=dark)
    B.box("interior", (0, 1.03, -1.15), (0.80, 0.02, 0.10), col=dark)
    for zc, xs in ((-0.45, (-0.40, 0.40)), (0.45, (-0.55, 0.0, 0.55)), (1.35, (-0.40, 0.40))):
        for x in xs:
            B.box("interior", (x, 0.52, zc), (0.22, 0.07, 0.24), col=seat)
            B.box("interior", (x, 0.92, zc + 0.24), (0.22, 0.34, 0.05), col=seat)


def wheel():
    """Roue : pneu (caoutchouc), jante tôle et enjoliveur argenté à fentes ; axe x, face extérieure vers -x."""
    B = Builder()
    n = 28
    W = 0.185
    prof = [(0.20, -W / 2), (0.27, -W / 2), (0.295, -W / 2 + 0.03), (R, -0.03), (R, 0.03), (0.295, W / 2 - 0.03),
            (0.27, W / 2), (0.20, W / 2)]
    for i in range(n):
        a0 = 2 * math.pi * i / n; a1 = 2 * math.pi * (i + 1) / n
        for j in range(len(prof) - 1):
            (r0, x0), (r1, x1) = prof[j], prof[j + 1]
            p = lambda r, x, a: (x, r * math.cos(a), r * math.sin(a))
            mid = ((r0 + r1) / 2, (x0 + x1) / 2)
            out = np.array([mid[1] * 0.3, math.cos((a0 + a1) / 2) * mid[0], math.sin((a0 + a1) / 2) * mid[0]])
            B.quad("rubber", p(r0, x0, a0), p(r1, x1, a0), p(r1, x1, a1), p(r0, x0, a1), out)
        # enjoliveur (face extérieure, -x) : disque argenté légèrement bombé, 8 fentes sombres
        c0 = (-W / 2 - 0.012, 0.0, 0.0)
        e0 = (-W / 2 + 0.005, 0.20 * math.cos(a0), 0.20 * math.sin(a0)); e1 = (-W / 2 + 0.005, 0.20 * math.cos(a1), 0.20 * math.sin(a1))
        slot = i % 7 in (2, 3) and True
        B.tri("hubcap" if not slot else "plastic", c0, e0, e1, (-1, 0, 0))
        # face intérieure : jante sombre
        B.tri("plastic", (W / 2 - 0.01, 0, 0), (W / 2 - 0.01, 0.20 * math.cos(a0), 0.20 * math.sin(a0)),
              (W / 2 - 0.01, 0.20 * math.cos(a1), 0.20 * math.sin(a1)), (1, 0, 0))
    return B


def main():
    os.makedirs(OUT, exist_ok=True)
    B = Builder()
    body(B)
    details(B)
    write_glb(OUT + "/body.glb", B.prims(), "body")
    write_glb(OUT + "/wheel.glb", wheel().prims(), "wheel")
    json.dump(dict(steer=[-0.37, 1.00, -0.98], eye=[-0.37, 1.32, -0.42], wheelbase=WB, track=TRACK, radius=R,
                   wheel_center=[0.0, 0.0, 0.0], model="Renault Espace I (1984-1988)"), open(OUT + "/meta.json", "w"))
    print({k: len(v["P"]) // 3 for k, v in B.m.items()}, "triangles")


if __name__ == "__main__":
    main()
