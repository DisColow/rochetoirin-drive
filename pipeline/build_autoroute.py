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
          "rond", "grillage", "absorbeur", "barriere", "bras"]
MID = {n: i for i, n in enumerate(MODELS)}
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
BLUE = (16, 62, 140)
SPAN = 4.0                     # longueur des modèles de travée (glissière, GBA, grillage)


# villes annoncées sur les panneaux de confirmation : (nom, (lon, lat), grande ville)
_CITIES = [("Lyon", (4.8357, 45.7640), True), ("Chambéry", (5.9178, 45.5646), True), ("Grenoble", (5.7245, 45.1885), True),
           ("Genève", (6.1432, 46.2044), True), ("Bourgoin-Jallieu", (5.2733, 45.5865), False),
           ("La Tour-du-Pin", (5.4446, 45.5658), False), ("L'Isle-d'Abeau", (5.2290, 45.6196), False),
           ("Voiron", (5.5889, 45.3644), False), ("Aéroport St-Exupéry", (5.0811, 45.7256), False)]
CITIES = [(n, tuple(map(float, geo.to_local(lo, la))), m) for n, (lo, la), m in _CITIES]


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
            if num is not None:
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

    def bandeau(self, text):
        """Inscription blanche sur fond bleu (fronton de l'auvent de péage), dessinée deux fois plus large puis
        resserrée : affichée sur un panneau 4 fois plus large que haut, elle garde ses proportions."""
        def draw(c, d):
            big = Image.new("RGB", (self.CW * 2, self.CH), BLUE)
            dd = ImageDraw.Draw(big)
            f, b = self._fit(text, self.CW * 2 - 80, self.CH - 50, 200)
            dd.text(((self.CW * 2 - (b[2] - b[0])) // 2 - b[0], (self.CH - (b[3] - b[1])) // 2 - b[1]), text, font=f, fill=(255, 255, 255))
            c.paste(big.resize((self.CW, self.CH), Image.LANCZOS), (0, 0))
        return self._cell(("band", text), draw)

    def voie(self, kind):
        """Signal de voie de péage (moitié gauche carrée) : flèche verte au-dessus, mode de paiement dessous."""
        def draw(c, d):
            H = self.CH
            d.rectangle([0, 0, self.CW, H], fill=(20, 20, 24))
            d.rectangle([6, 6, H - 7, H - 7], outline=(230, 230, 230), width=4)
            # flèche verte (voie ouverte)
            g = (40, 220, 70)
            d.polygon([(H / 2 - 22, 24), (H / 2 + 22, 24), (H / 2 + 22, 66), (H / 2 + 44, 66), (H / 2, 108), (H / 2 - 44, 66),
                       (H / 2 - 22, 66)], fill=g)
            y0 = 124
            if kind == "t":
                d.ellipse([H / 2 - 56, y0, H / 2 + 56, y0 + 112], fill=(240, 120, 20))
                f, b = self._fit("t", 90, 100, 100)
                d.text((H / 2 - (b[2] - b[0]) / 2 - b[0], y0 + 56 - (b[3] - b[1]) / 2 - b[1]), "t", font=f, fill=(255, 255, 255))
            elif kind == "cb":
                d.rounded_rectangle([H / 2 - 70, y0 + 10, H / 2 + 70, y0 + 100], 10, fill=(30, 90, 190))
                d.rectangle([H / 2 - 70, y0 + 28, H / 2 + 70, y0 + 44], fill=(10, 10, 10))
                f, b = self._fit("CB", 80, 40, 40)
                d.text((H / 2 + 20 - b[0], y0 + 56 - b[1]), "CB", font=f, fill=(255, 255, 255))
            else:
                d.rectangle([H / 2 - 52, y0 + 6, H / 2 + 52, y0 + 104], fill=(245, 245, 240))
                for k in range(4):
                    d.line([(H / 2 - 38, y0 + 26 + k * 18), (H / 2 + 38, y0 + 26 + k * 18)], fill=(60, 60, 60), width=4)
        r = self._cell(("voie", kind), draw)
        return (r[0], r[1], self.CH / self.W, r[3])

    def confirmation(self, ref, dests):
        """Panneau de confirmation : cartouche rouge de l'autoroute, destinations et distances (km)."""
        def draw(c, d):
            d.rounded_rectangle([6, 6, self.CW - 7, self.CH - 7], 18, outline=(255, 255, 255), width=6)
            f, b = self._fit(ref, 150, 40, 36)
            wb = b[2] - b[0] + 30
            d.rounded_rectangle([24, 18, 24 + wb, 72], 8, fill=(200, 20, 30), outline=(255, 255, 255), width=3)
            d.text((24 + 15 - b[0], 45 - (b[3] - b[1]) // 2 - b[1]), ref, font=f, fill=(255, 255, 255))
            rows = dests[:3]
            hh = (self.CH - 90 - 18) // max(1, len(rows))
            for k, (name, km) in enumerate(rows):
                y = 88 + k * hh
                fk, bk = self._fit("%d" % km, 120, hh - 8, 40)
                d.text((self.CW - 30 - (bk[2] - bk[0]) - bk[0], y + (hh - (bk[3] - bk[1])) // 2 - bk[1]), "%d" % km, font=fk, fill=(255, 255, 255))
                fn, bn = self._fit(name, self.CW - 200, hh - 8, 40)
                d.text((30 - bn[0], y + (hh - (bn[3] - bn[1])) // 2 - bn[1]), name, font=fn, fill=(255, 255, 255))
        return self._cell(("conf", ref, tuple(dests)), draw)

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
            # musoir : la glissière s'interrompt sur la zone revêtue et repart de l'absorbeur (triangle avec celle
            # de la bretelle)
            if kind == "sortie":
                nose |= (s > ghi - 3) & (s < ghi + 1.5)
            else:
                nose |= (s > glo - 1.5) & (s < glo + 3)
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
        # panneaux de confirmation (destinations et distances) : après chaque entrée, et au début de la chaussée
        conf = [a[1] + 450 for a in c["aux"] if a[2] == "entrée"] + [700.0]
        done = []
        for sv in sorted(conf):
            if sv >= s[-1] - 200 or any(abs(sv - x) < 1500 for x in done):
                continue
            if any(a[0] - 120 < sv < a[4] + 120 for a in c["aux"]):
                continue
            k = int(np.searchsorted(s, sv))
            if brd[max(0, k - 5):k + 6].any():
                continue
            k2 = int(np.clip(np.searchsorted(s, sv + 2500), 0, n - 1))
            dv = P[k2] - P[k]; dv = dv / max(np.linalg.norm(dv), 1e-6)
            rows = []
            for name, (x_, z_), major in CITIES:
                v = np.array([x_, z_]) - P[k]; dist = float(np.linalg.norm(v))
                if dist < 3000 or (v / dist) @ dv < 0.55:
                    continue
                rows.append((dist * 1.2 / 1000.0, name, major))
            if not rows:
                continue
            rows.sort()
            pickd = [r for r in rows if not r[2]][:1] + [r for r in rows if r[2]][:2]
            pickd.sort()
            dests = [(r[1], max(1, int(round(r[0])))) for r in pickd]
            p = P[k] + R[k] * (hw[k] + c["rext"][k] + 3.2)
            if pave.on_road(p, 1.0):
                continue
            add("panneau_bleu", basis_facing(-c["T"][k], 4.4, 2.2), p, float(hroad(*p)[0]) + 2.4,
                atlas.confirmation(c["ref"] or "A 43", dests))
            stats["confirmation"] += 1
            done.append(sv)
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
        near_att_l = dilate(att, 1)            # côté autoroute : la glissière part du musoir
        brd = np.full(n, bool(l["bridge"]))
        ends_ok = np.ones(n, bool)
        for k, nd in zip(l["idx"], l["nodes"]):
            others = [o for o in ways if o is not l and nd in o["nodes"]]
            if any(o["cls"] not in ("motorway", "motorway_link") for o in others):
                ends_ok &= np.abs(s - s[k]) > 25
        nl = dilate(l["noleft"], 10)
        rail(P, R, np.full(n, lw + 0.6), ~near_att & ~brd & ends_ok, skip_ways=me)
        rail(P, R, np.full(n, -(lw + 0.6)), ~near_att_l & ~brd & ends_ok & ~nl, skip_ways=me)
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
    # gares élargies par build_roads.py (voies « plaza ») : auvent, îlots et cabines entre les voies, borne et bras de
    # barrière par voie (le bras est animé par autoroute.gd), liste des gares pour le ticket et le paiement
    import autoroute_geom as AG
    sites = []
    for w in ways:
        if not w.get("plaza"):
            continue
        tg = w["tags"]; n = int(tg["lanes"]); hp = w["w"] / 2; s0 = tg["toll_s0"]
        si = len(sites)
        k = int(np.clip(np.searchsorted(w["s"], s0), 0, len(w["s"]) - 1))
        T, R = w["T"][k], w["N"][k]; p = w["P"][k]
        y = float(w["y"][k])
        sites.append(dict(name=tg["name"], kind=tg["toll"], x=float(p[0]), z=float(p[1])))
        add("peage", (T[0] * 16.0, 0.0, T[1] * 16.0, 0.0, 1.0, 0.0, R[0] * (hp + 1.6) / 4.5, 0.0, R[1] * (hp + 1.6) / 4.5), p, y + 0.2)
        # inscription « PÉAGE » sur le fronton (face aux voitures qui arrivent)
        pf = p - T * 8.06
        add("panneau_haut", basis_facing(-T, 3.6, 0.9), pf, y + 0.2 + 6.88, atlas.bandeau("PÉAGE"))
        # signaux de voie sous le fronton : flèche verte + paiement (sortie : télépéage à gauche, CB ; entrée : ticket)
        for j in range(n):
            vc = -hp + 0.7 + j * (AG.PL_LANE + AG.PL_ISL) + AG.PL_LANE / 2
            kind = ("t" if j == 0 else "cb") if tg["toll"] == "pay" else ("t" if j == 0 else "ticket")
            q = p - T * 8.12 + R * vc
            add("panneau_haut", basis_facing(-T, 1.1, 1.1), q, y + 0.2 + 5.75, atlas.voie(kind))
        # présignalisation sur la bretelle : « PÉAGE » à 300 m et 120 m, limitation à 30 avant la gare
        bw = [o for o in ways if o["cls"] in ("motorway_link", "motorway") and len(o["P"]) > 1 and not o.get("plaza")]
        for dist, what in ((300.0, "pre"), (120.0, "pre"), (60.0, "v30")):
            qq = p - T * dist
            best = None
            for o in bw:
                dd = np.hypot(*(o["P"] - qq).T); kk = int(np.argmin(dd))
                if (best is None or dd[kk] < best[0]) and o["T"][kk] @ T > 0.5:
                    best = (dd[kk], o, kk)
            if best is None or best[0] > 40:
                continue
            _, o, kk = best
            ohw = o["hw_arr"][kk] if "hw_arr" in o else o["w"] / 2
            qs = o["P"][kk] + o["N"][kk] * (ohw + 2.0)
            if pave.on_road(qs, 0.5):
                continue
            if what == "pre":
                add("panneau_bleu", basis_facing(-o["T"][kk], 3.2, 1.6), qs, float(hroad(*qs)[0]) + 2.2,
                    atlas.panel(None, ["PÉAGE", tg["name"].replace("Péage de ", "")], "%d m" % dist))
            else:
                add("rond", basis_facing(-o["T"][kk]), qs, float(hroad(*qs)[0]) - 0.05, atlas.vitesse(30))
        L, I = AG.PL_LANE, AG.PL_ISL
        for j in range(n + 1):
            # îlots : entre les voies, et sur les deux bords de la gare
            v = -hp + 0.7 + j * (L + I) - I / 2
            v = max(v, -hp + 0.45) if j == 0 else (min(v, hp - 0.45) if j == n else v)
            q = p + R * v
            add("pile_peage", basis_facing(T), q, float(hroad(*q)[0]))
        for j in range(n):
            left = -hp + 0.7 + j * (L + I)                 # bord gauche de la voie j (automate côté conducteur)
            kb = int(np.clip(np.searchsorted(w["s"], s0 + 3.5), 0, len(w["s"]) - 1))
            Tb, Rb = w["T"][kb], w["N"][kb]
            q = w["P"][kb] + Rb * (left - 0.25)
            yb = float(hroad(*q)[0])
            B = (Rb[0], 0.0, Rb[1], 0.0, 1.0, 0.0, -Tb[0], 0.0, -Tb[1])
            add("barriere", B, q, yb)
            add("bras", B, q + Rb * 0.0, yb + 1.0, (si, 1.0 if tg["toll"] == "pay" else 0.0, j, 0))
    json.dump(sites, open(OUT_W + "/peages.json", "w"), ensure_ascii=False)
    stats["gares de péage"] = len(sites)
    atlas.img.save(OUT_A + "/panneaux.png")
    T_ = defaultdict(list)
    for r in inst:
        T_[(int(math.floor(r[10] / TILE)), int(math.floor(r[12] / TILE)))].append(r)
    for (tx, tz), S in T_.items():
        open("%s/r_%d_%d.bin" % (OUT_W, tx, tz), "wb").write(np.int32(len(S)).tobytes() + np.array(S, "<f4").tobytes())
    print(dict(stats), len(T_), "tuiles,", len(atlas.cells), "panneaux différents")


if __name__ == "__main__":
    main()
