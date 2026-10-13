"""Fiches courtes -> relevés complets (v6.33, bâtiments non résidentiels des autres communes : Saint-Chef d'abord).
Une fiche par bâtiment visible, écrite en regardant ses photos (planches de 6 bâtiments) :
  "mur", "toit" ("2pans:tuile", "plat", "appentis:bac#…", "4pans:tuile_brune", "berceau:bac#…"),
  "h": (égout, faîtage), "ouvert"/"c_poteaux", "soub": ("matière#…" ou "#…", hauteur), "skip": True (volume généré gardé),
  "o": jetons d'ouvertures sur la face la plus vue des caméras (et "o2" sur la face opposée) :
    fen:n[:y0-y1]  fenêtres régulières (ogive:n:… fenêtres d'église) (0,9-2,2 m par défaut) ; fenv:n volets ouverts ; porte[:x] ; pv[:x] porte vitrée ;
    garage:n[:c] ; rideau:n ; vitrine:x0-x1 ; bande[:y0-y1] bande vitrée ; mat:x0-x1:matière (bande d'autre matière) ;
    ens:TEXTE:#fond:#texte enseigne (marque parodique) ; aff affichette.
Lancer depuis pipeline/ : python3 sur_mesure/lots/fiches.py <lot>   (écrit releves/<id>.json)"""
import json, os, sys
ICI = os.path.dirname(os.path.abspath(__file__))
REL = os.path.join(os.path.dirname(ICI), "releves")


def ops(jetons, eg):
    out = []
    for j in jetons:
        a = j.split(":")
        t = a[0]
        if t in ("fen", "fenv", "ogive"):
            n = int(a[1]); y = [float(v) for v in a[2].split("-")] if len(a) > 2 else [0.9, 2.2]
            o = {"t": {"fen": "fenetre", "fenv": "fenetre_volets", "ogive": "ogive"}[t], "x": [0.08, 0.92], "y": y, "n": n,
                 "l": min(1.6, 0.6 * 1.0 / max(n, 1) * 10)}
            out.append(o)
        elif t in ("porte", "pv"):
            x = float(a[1]) if len(a) > 1 else 0.5
            out.append({"t": "porte" if t == "porte" else "porte_vitree", "x": [x - 0.04, x + 0.04], "y": [0, 2.2]})
        elif t in ("garage", "rideau"):
            n = int(a[1]) if len(a) > 1 else 1
            o = {"t": "garage" if t == "garage" else "rideau", "x": [0.15, 0.85] if n > 1 else [0.4, 0.6],
                 "y": [0, min(4.2, eg - 0.6)], "n": n, "l": 3.6}
            if len(a) > 2:
                o["c"] = a[2]
            out.append(o)
        elif t == "vitrine":
            x0, x1 = (float(v) for v in a[1].split("-"))
            out.append({"t": "vitrine", "x": [x0, x1], "y": [0.3, 2.6]})
        elif t == "bande":
            y = [float(v) for v in a[1].split("-")] if len(a) > 1 else [1.0, 2.4]
            out.append({"t": "bande_vitree", "x": [0.05, 0.95], "y": y, "c": "#8a8e90"})
        elif t == "mat":
            x0, x1 = (float(v) for v in a[1].split("-"))
            out.append({"t": "matiere", "x": [x0, x1], "y": [0, eg], "mur": ":".join(a[2:])})
        elif t == "ens":
            y0 = max(2.6, eg - 1.4)
            out.append({"t": "enseigne", "x": [0.3, 0.7], "y": [y0, y0 + 0.9], "txt": a[1],
                        "c": a[2] if len(a) > 2 else "#ffffff", "tc": a[3] if len(a) > 3 else "#1a2a4a"})
        elif t == "aff":
            out.append({"t": "affiche", "x": [0.3, 0.38], "y": [1.4, 2.4]})
    return out


OPP = {"N": "S", "S": "N", "E": "O", "O": "E", "NE": "SO", "SO": "NE", "NO": "SE", "SE": "NO"}


def releve(e, F):
    eg, fa = F.get("h", (e["R"]["egout"], e["R"]["faitage"]))
    tt = F.get("toit", "2pans:tuile").split(":", 1)
    R = {"id": e["R"]["id"], "cleabs": e["cleabs"], "nom": F.get("nom", e["usage"]), "mur": F.get("mur", "enduit#e0d8c8"),
         "toit": {"type": tt[0], "matiere": tt[1] if len(tt) > 1 else "tuile", "debord": 0.0 if tt[0] in ("plat", "berceau") else 0.4},
         "egout": eg, "faitage": fa if tt[0] != "plat" else eg}
    if F.get("ouvert"):
        R["ouvert"] = True; R["c_poteaux"] = F.get("c_poteaux", "#8a8e92")
    if F.get("soub"):
        R["soubassement"], R["h_soub"] = F["soub"]
    faces = {}
    if F.get("o"):
        faces[e["vue"]] = ops(F["o"], eg)
    if F.get("o2"):
        faces[OPP.get(e["vue"], "N")] = ops(F["o2"], eg)
    if faces:
        R["faces"] = faces
    for k, v in F.get("brut", {}).items():              # champs du relevé donnés tels quels (extras…)
        R[k] = v
    for k in ("simplifier", "extras", "pignons_clos", "bardage_haut"):
        if k in F:
            R[k] = F[k]
    return R


if __name__ == "__main__":
    lot = sys.argv[1]
    liste = json.load(open(os.path.join(ICI, lot + "_liste.json")))
    sys.path.insert(0, ICI)
    FICHES = __import__(lot).FICHES
    n = 0
    for e in liste:
        F = FICHES.get(e["k"])
        p = os.path.join(REL, e["R"]["id"] + ".json")
        if F is None or F.get("skip"):
            if os.path.exists(p):
                os.remove(p)
            continue
        json.dump(releve(e, F), open(p, "w"), ensure_ascii=False, indent=1); n += 1
    print(n, "relevés écrits")
