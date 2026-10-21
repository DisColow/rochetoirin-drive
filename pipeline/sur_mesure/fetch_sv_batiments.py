"""Photos Street View des bâtiments non résidentiels de Rochetoirin (directive du 13/10 : méthode du restaurant pour
tous ; accord de l'utilisateur pour ≈ 3 à 4 $, plafond 5 $). Clé : variable GOOGLE_MAPS_API_KEY, jamais écrite.
Cache privé d'abord (SV_DIR, par défaut ../../rochetoirin-streetview/streetview/batiments) : rien n'est retéléchargé.
Pour chaque bâtiment : panorama extérieur le plus proche (métadonnées, gratuites) ; s'il est à plus de VISIBLE m de
l'emprise, le bâtiment est noté invisible (aucune photo payée). Sinon : vue cadrée sur le bâtiment depuis ce panorama
(champ ajusté à la largeur apparente), puis une deuxième vue depuis un panorama voisin le long de la route (autre angle),
et une troisième pour les grands bâtiments. 640 × 640 (champ vertical = horizontal, pour le calage).
Sortie : SV_DIR/<cleabs>_<k>.jpg + index.json {cleabs: {"vues": [{nom, pano, date, cam[x,z], heading, pitch, fov}],
"dist"} ou {"invisible": dist}}.
Lancer depuis pipeline/ : python3 sur_mesure/fetch_sv_batiments.py [lot] [commune] [--estimer] [--une] [--jusqua=19]
[--cleabs=BATIMENT…,BATIMENT…]\n(lot : commerces, industriels, agricoles, tous ; --estimer : métadonnées gratuites seulement, photos à prévoir)"""
import json, math, os, sys, time, urllib.parse
from shapely.geometry import shape, Point
from shapely.ops import transform
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import geo
from fetch_sv_landmarks import get

KEY = os.environ.get("GOOGLE_MAPS_API_KEY", "")
OUT = os.environ.get("SV_DIR", "../../rochetoirin-streetview/streetview/batiments")
API = "https://maps.googleapis.com/maps/api/streetview"
VISIBLE = 70.0          # m : au-delà, le bâtiment n'est pas assez visible depuis la route
PLAFOND = 700           # photos par lancement ; le plafond absolu (9 000 par mois) est tenu par sv_budget.py (get)
LOTS = {"commerces": ("Commercial et services", "Religieux"), "industriels": ("Industriel",), "agricoles": ("Agricole",)}


def batiments(commune="Rochetoirin"):
    """Bâtiments non résidentiels d'une commune (Rochetoirin par défaut) : [(cleabs, usage, polygone local)]."""
    R = shape(json.load(open("data/communes.json"))[commune])
    out = []
    for f in json.load(open("data/batiments.json"))["features"]:
        p = f["properties"]
        g = transform(lambda x, y, z=None: geo.to_local(x, y), shape(f["geometry"])).buffer(0)
        if g.geom_type == "MultiPolygon":
            g = max(g.geoms, key=lambda q: q.area)
        if g.is_empty or not R.contains(g.centroid):
            continue
        u1, u2 = p.get("usage_1") or "", p.get("usage_2") or ""
        if u1 in ("Résidentiel", "Annexe", "Indifférencié", "") and u2 in ("", "Résidentiel", "Annexe", "Indifférencié"):
            continue
        usage = u1 if u1 not in ("Résidentiel", "Annexe", "Indifférencié") else u2
        out.append((p["cleabs"], usage, g))
    return out


def meta(x, z, radius=50):
    lon, lat = geo.to_lonlat(x, z)
    m = get(API + "/metadata?" + urllib.parse.urlencode(dict(location="%f,%f" % (lat, lon), radius=radius,
                                                              source="outdoor", key=KEY)))
    if not m or m.get("status") != "OK":
        return None
    if "Google" not in (m.get("copyright") or ""):     # panorama de particulier (souvent en intérieur) : écarté
        return None
    cx, cz = geo.to_local(m["location"]["lng"], m["location"]["lat"])
    return dict(pano=m["pano_id"], date=m.get("date"), cam=[round(float(cx), 2), round(float(cz), 2)])


def cadrage(cam, g):
    """Cap (degrés, 0 = nord, 90 = est), champ et inclinaison pour voir tout le bâtiment depuis la caméra."""
    c = g.centroid
    cap = math.degrees(math.atan2(c.x - cam[0], -(c.y - cam[1]))) % 360
    angs = []
    for x, z in g.exterior.coords:
        a = math.degrees(math.atan2(x - cam[0], -(z - cam[1]))) - cap
        angs.append((a + 180) % 360 - 180)
    w = max(angs) - min(angs)
    cap = (cap + (max(angs) + min(angs)) / 2) % 360
    d = max(3.0, g.exterior.distance(Point(cam)))
    fov = max(45.0, min(110.0, w + 14))
    pitch = max(0.0, min(20.0, math.degrees(math.atan2(4.0, d)) * 0.8))
    return round(cap, 1), round(fov), round(pitch, 1)


def photo(v, chemin):
    img = get(API + "?" + urllib.parse.urlencode(dict(size="640x640", pano=v["pano"], heading=v["heading"],
                                                      pitch=v["pitch"], fov=v["fov"], key=KEY)), binary=True)
    if img and img[:2] == b"\xff\xd8":
        open(chemin, "wb").write(img)
        return True
    return False


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    lot = args[0] if args else "commerces"
    commune = args[1] if len(args) > 1 else "Rochetoirin"
    une = "--une" in sys.argv                          # une seule photo par bâtiment (v6.34 : couvrir plus de communes)
    arret = next((float(a.split("=")[1]) for a in sys.argv if a.startswith("--jusqua=")), None)   # $ au total
    estimer = "--estimer" in sys.argv                  # métadonnées seulement (gratuites) : photos à prévoir
    prevues = 0
    os.makedirs(OUT, exist_ok=True)
    idx_p = os.path.join(OUT, "index.json")
    index = json.load(open(idx_p)) if os.path.exists(idx_p) else {}
    payees = sum(len(v.get("vues", [])) for v in index.values())
    ce_lancement = 0
    faits = {c for v in json.load(open("../godot/world/sur_mesure.json")).values() for c in v.get("remplace_bati", [])}
    B = [b for b in batiments(commune) if (lot == "tous" or b[1] in LOTS[lot]) and b[0] not in faits]
    seuls = next((a.split("=", 1)[1].split(",") for a in sys.argv if a.startswith("--cleabs=")), None)
    if seuls:                                          # bâtiments choisis seulement (#113 : la gare de La Tour-du-Pin)
        B = [b for b in B if b[0] in seuls]
    todo = [b for b in B if b[0] not in index]
    print(len(B), "bâtiments (%s)," % lot, len(todo), "à photographier ; déjà payées :", payees)
    if todo and not KEY:
        sys.exit("GOOGLE_MAPS_API_KEY absente")
    for cl, usage, g in todo:
        c = g.centroid
        m1 = meta(c.x, c.y, 60)
        d1 = g.exterior.distance(Point(m1["cam"])) if m1 else 1e9
        if d1 > VISIBLE:
            if not estimer:
                index[cl] = {"invisible": round(d1, 1) if m1 else None, "usage": usage}
            continue
        vues = [m1]
        if estimer:
            prevues += 1 if une else (3 if g.area > 400 else 2)
            continue
        # panoramas voisins : 22 m de part et d'autre, perpendiculairement à la ligne de visée
        dx, dz = c.x - m1["cam"][0], c.y - m1["cam"][1]
        n = math.hypot(dx, dz) or 1.0
        tx, tz = -dz / n, dx / n
        voulus = 1 if une else (3 if g.area > 400 else 2)
        for s in (1, -1):
            if len(vues) >= voulus:
                break
            m = meta(m1["cam"][0] + tx * 22 * s, m1["cam"][1] + tz * 22 * s, 20)
            if m and all(m["pano"] != v["pano"] for v in vues) and g.exterior.distance(Point(m["cam"])) < VISIBLE:
                vues.append(m)
        ok = []
        for k, v in enumerate(vues):
            if ce_lancement >= PLAFOND and not une:
                print("plafond de photos atteint"); break
            if arret is not None:
                import sv_budget
                if sv_budget.depense() + 0.007 > arret:
                    print("arrêt demandé à %.2f $" % arret); json.dump(index, open(idx_p, "w"), indent=0); return
            v["heading"], v["fov"], v["pitch"] = cadrage(v["cam"], g)
            v["nom"] = "%s_%d" % (cl, k)
            if photo(v, os.path.join(OUT, v["nom"] + ".jpg")):
                ok.append(v); payees += 1; ce_lancement += 1
            time.sleep(0.05)
        index[cl] = {"vues": ok, "dist": round(d1, 1), "usage": usage}
        json.dump(index, open(idx_p, "w"), indent=0)
    if estimer:
        n_ = prevues
        print("estimation : au plus %d photos (%.2f $) ; aucune image payée" % (n_, n_ * 0.007))
        return
    json.dump(index, open(idx_p, "w"), indent=0)
    vis = [k for k in index if index[k].get("vues")]
    print("photos payées au total :", payees, "(%.2f $)" % (payees * 0.007), "; bâtiments photographiés :", len(vis),
          "; invisibles :", sum(1 for v in index.values() if "invisible" in v))


if __name__ == "__main__":
    main()
