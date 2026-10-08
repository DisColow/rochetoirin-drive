"""Équipements des autoroutes (après build_roads.py, qui fournit les chaussées, voies auxiliaires et musoirs) :

 - glissières de sécurité le long des bords réels (bande d'arrêt d'urgence, voies auxiliaires, bretelles), coupées
   aux musoirs, sur les ponts (parapets) et aux raccords avec les autres routes ;
 - terre-plein central : séparateur en béton (GBA) quand il est étroit, double glissière sinon ;
 - clôture grillagée d'emprise ;
 - signalisation de sortie à la française : présignalisation à 1 000 m et 500 m (panneaux bleus sur poteaux),
   potence au début de la voie de décélération (numéro, destinations, flèche), absorbeur de choc, balise à chevrons
   et panneau « SORTIE » au musoir ; limitation de vitesse rappelée après chaque entrée et tous les 5 km ;
 - bornes d'appel d'urgence (OSM), gares de péage (OSM).
Tout est posé hors des voies, du bon côté (N des voies = droite du sens de circulation).
Modèles : blender_autoroute.py. Sorties : ../godot/assets/autoroute/panneaux.png (atlas, cases 512 × 256),
../godot/world/autoroute/r_tx_tz.bin : int32 n, n × 17 float32 (modèle, base 3 × 3 colonnes, origine, 4 données)."""
import json, math, os, pickle, shutil
from collections import defaultdict
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy.spatial import cKDTree
from scipy.ndimage import maximum_filter1d


def dilate(m, r):
    """Masque booléen élargi de r échantillons de chaque côté."""
    return maximum_filter1d(np.asarray(m, np.uint8), 2 * r + 1, mode="nearest") > 0 if len(m) else np.asarray(m, bool)
import geo

OUT_A = "../godot/assets/autoroute"
OUT_W = "../godot/world/autoroute"
TILE = 256.0
MODELS = ["glissiere", "borne_sos", "panneau_bleu", "peage", "pile_peage", "chevron", "gba", "potence", "panneau_haut",
          "rond", "grillage", "absorbeur"]
MID = {n: i for i, n in enumerate(MODELS)}
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
BLUE = (16, 62, 140)
SPAN = 4.0                     # longueur des modèles de travée (glissière, GBA, grillage)


class Atlas:
    W, CW, CH = 4096, 512, 256

    def __init__(self):
        self.img = Image.new("RGB", (self.W, self.W), BLUE)
        self.cells = {}

    def _cell(self, key, draw):
        if key in self.cells:
            return self.cells[key]
        i = len(self.cells)
        if i >= (self.W // self.CW) * (self.W // self.CH):
            return next(iter(self.cells.values()))
        cx, cy = (i % 8) * self.CW, (i // 8) * self.CH
        c = Image.new("RGB", (self.CW, self.CH), BLUE)
        draw(c, ImageDraw.Draw(c))
        self.img.paste(c, (cx, cy))
        r = (cx / self.W, cy / self.W, self.CW / self.W, self.CH / self.W)
        self.cells[key] = r
        return r

    @staticmethod
    def _fit(text, maxw, maxh, s=40):
        while s > 14:
            f = ImageFont.truetype(FONT, s)
            b = f.getbbox(text)
            if b[2] - b[0] <= maxw and b[3] - b[1] <= maxh:
                return f, b
            s -= 2
        f = ImageFont.truetype(FONT, 14)
        return f, f.getbbox(text)

    def _sortie_box(self, d, num, x, y):
        t = "SORTIE " + num if num else "SORTIE"
        ft, b = self._fit(t, 200, 40, 34)
        wbox = (b[2] - b[0]) + 30
        d.rounded_rectangle([x, y, x + wbox, y + 58], 10, fill=(255, 255, 255))
        d.text((x + 15 - b[0], y + 29 - (b[3] - b[1]) // 2 - b[1]), t, font=ft, fill=BLUE)
        return wbox

    @staticmethod
    def _arrow(d, x, y, s):
        """Flèche blanche oblique (vers le haut à droite) dans un carré s × s."""
        a = [(0.18, 0.92), (0.62, 0.48), (0.48, 0.34), (0.9, 0.12), (0.72, 0.56), (0.6, 0.44), (0.3, 1.0)]
        d.polygon([(x + px * s, y + py * s) for px, py in a], fill=(255, 255, 255))

    def _lines(self, d, lines, ys):
        hh = (self.CH - ys - 22) // max(1, len(lines))
        for k, ln in enumerate(lines):
            f, b = self._fit(ln, self.CW - 60, hh - 4)
            d.text((30, ys + k * hh + (hh - (b[3] - b[1])) // 2 - b[1]), ln, font=f, fill=(255, 255, 255))

    def panel(self, num, dests, dist):
        """Présignalisation : cartouche « SORTIE n », distance, destinations."""
        def draw(c, d):
            d.rounded_rectangle([6, 6, self.CW - 7, self.CH - 7], 18, outline=(255, 255, 255), width=6)
            self._sortie_box(d, num, 22, 18)
            fd = ImageFont.truetype(FONT, 34)
            b = fd.getbbox(dist)
            d.text((self.CW - 30 - (b[2] - b[0]), 26), dist, font=fd, fill=(255, 255, 255))
            self._lines(d, dests[:3], 92)
        return self._cell(("pre", num, tuple(dests), dist), draw)

    def potence(self, num, dests):
        """Panneau de la potence de sortie : « SORTIE n », flèche oblique à droite, destinations."""
        def draw(c, d):
            d.rounded_rectangle([6, 6, self.CW - 7, self.CH - 7], 18, outline=(255, 255, 255), width=6)
            self._sortie_box(d, num, 22, 18)
            self._arrow(d, self.CW - 112, 14, 86)
            self._lines(d, dests[:2], 108)
        return self._cell(("pot", num, tuple(dests)), draw)

    def musoir(self, num):
        """Petit panneau au musoir : « SORTIE n » + flèche."""
        def draw(c, d):
            d.rounded_rectangle([6, 6, self.CW - 7, self.CH - 7], 18, outline=(255, 255, 255), width=6)
            f, b = self._fit("SORTIE", 300, 80, 72)
            d.text((30 - b[0], 40 - b[1]), "SORTIE", font=f, fill=(255, 255, 255))
            if num:
                f2, b2 = self._fit(num, 300, 70, 64)
                d.text((30 - b2[0], 150 - b2[1]), num, font=f2, fill=(255, 255, 255))
            self._arrow(d, self.CW - 200, 40, 170)
        return self._cell(("mus", num), draw)

    def vitesse(self, v):
        """Limitation de vitesse (moitié gauche carrée de la case) : disque blanc, couronne rouge, chiffres noirs."""
        def draw(c, d):
            H = self.CH
            d.rectangle([0, 0, self.CW, H], fill=(150, 150, 150))
            d.ellipse([2, 2, H - 3, H - 3], fill=(200, 16, 30))
            d.ellipse([32, 32, H - 33, H - 33], fill=(250, 250, 250))
            f, b = self._fit(str(v), H - 84, H - 110, 110)
            d.text(((H - (b[2] - b[0])) // 2 - b[0], (H - (b[3] - b[1])) // 2 - b[1]), str(v), font=f, fill=(10, 10, 10))
        r = self._cell(("v", v), draw)
        return (r[0], r[1], self.CH / self.W, r[3])


def basis_facing(n, sx=1.0, sy=1.0):
    """Base d'un objet dont le +z regarde dans la direction n (plan), x = n tourné de -90°."""
    X = (n[1] * sx, 0.0, -n[0] * sx)
    return X + (0.0, sy, 0.0) + (n[0], 0.0, n[1])


def basis_span(pa, pb, ya, yb, toward):
    """Travée de pa à pb (modèle de 4 m), +z vers « toward » (normale plane) ; base directe."""
    t = pb - pa; L = float(np.hypot(*t)); t = t / max(L, 1e-6)
    z = np.array([-t[1], t[0]])
    if z @ toward < 0:                    # on parcourt la travée dans l'autre sens
        pa, pb, ya, yb = pb, pa, yb, ya
        t = -t; z = -z
    X = (t[0] * L / SPAN, (yb - ya) / SPAN, t[1] * L / SPAN)
    return X + (0.0, 1.0, 0.0) + (z[0], 0.0, z[1]), pa, ya


class Pave:
    """Points de chaussée de toutes les voies (pour ne rien poser sur une route)."""
    def __init__(self, ways):
        P, H, O = [], [], []
        for i, w in enumerate(ways):
            if len(w["P"]) < 2:
                continue
            s = w["s"]; ss = np.arange(0, s[-1] + 0.01, 2.0)
            P.append(np.c_[np.interp(ss, s, w["P"][:, 0]), np.interp(ss, s, w["P"][:, 1])])
            hw = np.interp(ss, s, w["hw_arr"]) if "hw_arr" in w else np.full(len(ss), w["w"] / 2)
            H.append(hw); O.append(np.full(len(ss), i))
        self.P = np.vstack(P); self.H = np.concatenate(H); self.O = np.concatenate(O)
        self.tree = cKDTree(self.P)

    def on_road(self, q, margin, skip=()):
        for j in self.tree.query_ball_point(q, 25.0):
            if self.O[j] in skip:
                continue
            if np.hypot(*(self.P[j] - q)) < self.H[j] + margin:
                return True
        return False


def main():
    import build_roads as BR
    os.makedirs(OUT_A, exist_ok=True)
    shutil.rmtree(OUT_W, ignore_errors=True); os.makedirs(OUT_W)
    D = pickle.load(open("data/roads.pkl", "rb"))
    ways, chains = D["ways"], D["chains"]
    widx = {id(w): i for i, w in enumerate(ways)}
    byid = {w["id"]: w for w in ways}
    rf = BR.road_height_fn(BR.samples(ways))
    hroad = lambda x, z: rf(x, z)[0]
    dem = BR.DEM()
    for k in list(dem.reg):
        p = "data/dem_carved/r_%d_%d.npy" % k
        if os.path.exists(p):
            dem.reg[k] = np.load(p)
    pave = Pave(ways)
    links = [w for w in ways if w["cls"] == "motorway_link" and len(w["P"]) > 1]
    osm = json.load(open("data/osm_autoroute.json"))["elements"]
    jref = {e["id"]: e["tags"].get("ref") for e in osm if e["type"] == "node" and e["tags"].get("highway") == "motorway_junction"}
    ldest = {}
    for e in osm:
        if e["type"] == "way" and e["tags"].get("highway") == "motorway_link":
            dest = e["tags"].get("destination") or e["tags"].get("destination:ref") or ""
            if dest:
                ldest[e["id"]] = dest
    atlas = Atlas()
    inst = []
    stats = defaultdict(int)

    def add(model, basis, o, y, data=(0, 0, 0, 0)):
        inst.append((MID[model],) + tuple(float(v) for v in basis) + (float(o[0]), float(y), float(o[1]))
                    + tuple(float(v) for v in data))
        stats[model] += 1

    def rail(P, R, offs, mask, model="glissiere", skip_ways=(), toward_sign=None):
        """Travées de 4 m le long de la polyligne P décalée de offs (à droite), là où mask est vrai."""
        Q = P + R * offs[:, None]
        sq = np.r_[0, np.cumsum(np.hypot(*np.diff(Q, axis=0).T))]
        k = 0; n = len(P)
        while k < n:
            if not mask[k]:
                k += 1; continue
            j = k
            while j + 1 < n and mask[j + 1]:
                j += 1
            a, b = sq[k], sq[j]
            x = a
            while x + 1.0 < b:
                x1 = min(x + SPAN, b)
                pa = np.array([np.interp(x, sq, Q[:, 0]), np.interp(x, sq, Q[:, 1])])
                pb = np.array([np.interp(x1, sq, Q[:, 0]), np.interp(x1, sq, Q[:, 1])])
                if pave.on_road((pa + pb) / 2, 0.25, skip_ways):
                    x = x1; continue
                ya = float(hroad(*pa)[0]) - 0.04; yb = float(hroad(*pb)[0]) - 0.04
                kk = int(np.clip(np.searchsorted(sq, (x + x1) / 2), 0, n - 1))
                toward = -R[kk] * np.sign(offs[kk]) if toward_sign is None else R[kk] * toward_sign
                B, o, y0 = basis_span(pa, pb, ya, yb, toward)
                add(model, B, o, y0)
                x = x1
            k = j + 1

    # ------------------------------------------------------------------ chaussées
    allP = np.vstack([c["P"] for c in chains])
    own = np.concatenate([np.full(len(c["P"]), i) for i, c in enumerate(chains)])
    start = np.r_[0, np.cumsum([len(c["P"]) for c in chains])]
    ctree = cKDTree(allP)
    for ci, c in enumerate(chains):
        P, R, s, hw = c["P"], c["R"], c["s"], c["hw"]
        n = len(P)
        cw = {widx[id(byid[i])] for i in c["ways"]}
        br = c["bridge"].copy()
        brd = dilate(br, 2)                                               # ponts : le parapet prend le relais
        nose = np.zeros(n, bool)
        for a in c["aux"]:
            lo, hi, kind, glo, ghi = a[:5]
            if kind == "sortie":
                nose |= (s > ghi - 3) & (s < ghi + 30)
            else:
                nose |= (s > glo - 30) & (s < glo + 3)
        rail(P, R, hw + c["rext"] + 0.75, ~brd & ~nose, skip_ways=cw)
        # terre-plein central
        tw = c["twin"]
        q = P - R * np.where(np.isfinite(tw), tw, 0)[:, None]
        d, j = ctree.query(q)
        ok = np.isfinite(tw) & (tw < 45) & (d < 6) & (own[j] != ci)
        twin_c = np.where(ok, own[j], -1)
        gba = ok & (tw - 2 * hw < 6.5)
        if gba.any():
            tws = cw | {widx[id(byid[i])] for cj in set(twin_c[gba].tolist()) for i in chains[cj]["ways"]}
            rail(P, R, -tw / 2, gba & (twin_c > ci) & ~brd, model="gba", skip_ways=tws, toward_sign=-1)
        rail(P, R, -(hw + 0.75), ~gba & ~brd, skip_ways=cw)
        # clôture d'emprise (côté extérieur), loin des échangeurs et des autres routes
        far = ~brd
        for a in c["aux"]:
            far &= ~((s > a[0] - 120) & (s < a[4] + 250))
        Q = P + R * (hw + c["rext"] + 12.0)[:, None]
        sq = np.r_[0, np.cumsum(np.hypot(*np.diff(Q, axis=0).T))]
        x = 0.0
        while x + SPAN < sq[-1]:
            kk = int(np.clip(np.searchsorted(sq, x + 2), 0, n - 1))
            if far[kk]:
                pa = np.array([np.interp(x, sq, Q[:, 0]), np.interp(x, sq, Q[:, 1])])
                pb = np.array([np.interp(x + SPAN, sq, Q[:, 0]), np.interp(x + SPAN, sq, Q[:, 1])])
                if not pave.on_road((pa + pb) / 2, 3.0):
                    ya, yb = float(dem.h(*pa)[0]), float(dem.h(*pb)[0])
                    B, o, y0 = basis_span(pa, pb, ya, yb, -R[kk])
                    add("grillage", B, o, y0 - 0.05)
            x += SPAN

        # limitations de vitesse : après chaque voie d'accélération, et tous les 5 km
        def speed_at(k):
            best = (1e9, 130)
            for i in c["ways"]:
                w = byid[i]
                dd = float(np.min(np.hypot(*(w["P"] - P[k]).T)))
                if dd < best[0]:
                    try:
                        v = int(str(w["tags"].get("maxspeed", "130")).split()[0])
                    except ValueError:
                        v = 130
                    best = (dd, v)
            return best[1]
        spots = [a[1] + 150 for a in c["aux"] if a[2] == "entrée"] + list(np.arange(2500, s[-1], 5000))
        for sv in spots:
            if sv >= s[-1] - 10 or any(a[0] - 60 < sv < a[4] + 60 for a in c["aux"]):
                continue
            k = int(np.searchsorted(s, sv))
            if brd[k]:
                continue
            p = P[k] + R[k] * (hw[k] + c["rext"][k] + 2.2)
            add("rond", basis_facing(-c["T"][k]), p, float(hroad(*p)[0]) - 0.05, atlas.vitesse(speed_at(k)))
        # sorties
        for a in c["aux"]:
            lo, hi, kind, glo, ghi, lid, node, sj = a
            if kind != "sortie":
                continue
            dests = [d_.strip() for d_ in ldest.get(lid, "").split(";") if d_.strip()]
            if not dests:
                l = byid.get(lid)
                dests = [l["tags"]["destination"]] if l and l["tags"].get("destination") else ["Toutes directions"]
            num = jref.get(node) or ""
            for dist in (1000.0, 500.0):
                sv = sj - dist
                if sv < 5:
                    continue
                k = int(np.searchsorted(s, sv))
                if brd[max(0, k - 3):k + 4].any():
                    k = int(np.searchsorted(s, sv - 40))
                p = P[k] + R[k] * (hw[k] + c["rext"][k] + 2.8)
                add("panneau_bleu", basis_facing(-c["T"][k], 4.6, 2.3), p, float(hroad(*p)[0]) + 2.5,
                    atlas.panel(num, dests, "%d m" % dist))
            # potence au début de la voie de décélération
            k = int(np.clip(np.searchsorted(s, lo), 0, n - 1))
            if not brd[max(0, k - 3):k + 4].any():
                p = P[k] + R[k] * (hw[k] + c["rext"][k] + 1.6)
                y = float(hroad(*p)[0])
                add("potence", basis_facing(-c["T"][k]), p, y - 0.05)
                pp = P[k] + R[k] * (hw[k] - 1.6) - c["T"][k] * 0.3
                add("panneau_haut", basis_facing(-c["T"][k], 4.2, 2.1), pp, y + 6.15, atlas.potence(num, dests))
            # musoir : absorbeur, balise à chevrons et panneau « SORTIE »
            k = int(np.searchsorted(s, ghi))
            if k < n and not brd[k]:
                T = c["T"][k]
                p = P[k] + R[k] * (hw[k] + 1.1) + T * 1.0
                X = (-T[0], 0.0, -T[1]); Z = (T[1], 0.0, -T[0])
                add("absorbeur", X + (0.0, 1.0, 0.0) + Z, p, float(hroad(*p)[0]) - 0.03)
                k2 = int(np.clip(np.searchsorted(s, ghi + 12), 0, n - 1))
                p2 = P[k2] + R[k2] * (hw[k2] + 1.6)
                if not pave.on_road(p2, 0.3):
                    add("chevron", basis_facing(-c["T"][k2]), p2, float(hroad(*p2)[0]) - 0.03)
                k3 = int(np.clip(np.searchsorted(s, ghi + 22), 0, n - 1))
                p3 = P[k3] + R[k3] * (hw[k3] + 2.0)
                if not pave.on_road(p3, 0.6):
                    add("panneau_bleu", basis_facing(-c["T"][k3], 2.2, 1.1), p3, float(hroad(*p3)[0]) + 1.6,
                        atlas.musoir(num))
    # ------------------------------------------------------------------ bretelles
    for l in links:
        P, R, s = l["P"], l["N"], l["s"]
        n = len(P); lw = l["w"] / 2
        me = {widx[id(l)]}
        att = np.isfinite(l["att_s"])
        near_att = dilate(att, 10)
        brd = np.full(n, bool(l["bridge"]))
        ends_ok = np.ones(n, bool)
        for k, nd in zip(l["idx"], l["nodes"]):
            others = [o for o in ways if o is not l and nd in o["nodes"]]
            if any(o["cls"] not in ("motorway", "motorway_link") for o in others):
                ends_ok &= np.abs(s - s[k]) > 25
        nl = dilate(l["noleft"], 10)
        rail(P, R, np.full(n, lw + 0.6), ~near_att & ~brd & ends_ok, skip_ways=me)
        rail(P, R, np.full(n, -(lw + 0.6)), ~near_att & ~brd & ends_ok & ~nl, skip_ways=me)
    # ------------------------------------------------------------------ bornes d'appel d'urgence
    for e in osm:
        if e["type"] != "node" or e["tags"].get("emergency") != "phone":
            continue
        x, z = geo.to_local(e["lon"], e["lat"])
        d, j = ctree.query([x, z])
        if d > 40:
            continue
        c = chains[own[j]]; k = j - start[own[j]]
        p = c["P"][k] + c["R"][k] * (c["hw"][k] + c["rext"][k] + 1.5)
        add("borne_sos", basis_facing(-c["R"][k]), p, float(hroad(*p)[0]) - 0.05)
    # ------------------------------------------------------------------ péages
    for e in osm:
        if e["tags"].get("barrier") != "toll_booth":
            continue
        if e["type"] == "node":
            x, z = geo.to_local(e["lon"], e["lat"])
        else:
            g = e.get("geometry") or []
            if not g:
                continue
            x, z = geo.to_local(np.mean([q["lon"] for q in g]), np.mean([q["lat"] for q in g]))
        best = None
        for w in ways:
            if w["cls"] not in ("motorway", "motorway_link") or len(w["P"]) < 2:
                continue
            dd = np.hypot(w["P"][:, 0] - x, w["P"][:, 1] - z)
            k = int(np.argmin(dd))
            if best is None or dd[k] < best[0]:
                best = (dd[k], w, k)
        if best is None or best[0] > 25:
            continue
        _, w, k = best
        T, R = w["T"][k], w["N"][k]
        hw = w["hw_arr"][k] if "hw_arr" in w else w["w"] / 2
        p = w["P"][k]; y = float(w["y"][k])
        add("peage", (T[0] * 8.0, 0.0, T[1] * 8.0, 0.0, 1.0, 0.0, R[0] * (hw + 2.0) / 4.5, 0.0, R[1] * (hw + 2.0) / 4.5), p, y)
        for sg in (1, -1):
            add("pile_peage", basis_facing(R * -sg), p + R * sg * (hw + 1.6), y)
    atlas.img.save(OUT_A + "/panneaux.png")
    T_ = defaultdict(list)
    for r in inst:
        T_[(int(math.floor(r[10] / TILE)), int(math.floor(r[12] / TILE)))].append(r)
    for (tx, tz), S in T_.items():
        open("%s/r_%d_%d.bin" % (OUT_W, tx, tz), "wb").write(np.int32(len(S)).tobytes() + np.array(S, "<f4").tobytes())
    print(dict(stats), len(T_), "tuiles,", len(atlas.cells), "panneaux différents")


if __name__ == "__main__":
    main()
