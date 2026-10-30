"""Page d'écoute des sons de moteur (#153) : une ligne par voiture, le son actuel et les propositions, chacun joué sur le
même parcours (simulation d'audio.gd : ralenti, pleins gaz jusqu'à 100 km/h, pied levé, freinage).
Usage (depuis pipeline/) : python3 page_moteurs.py <dossier des mp3> <page.html> data/sons/moteurs/credits.json   (mp3 : <clé>.mp3 et actuel_<facteur>.mp3)"""
import base64, json, os, sys

# voiture du garage -> (nom en jeu, facteur du son actuel (fiche « moteur »), propositions)
VOITURES = [
    ("deuche", "Citrouille Deuche", 1.55, ["2cv6"]),
    ("r5", "Renaud Cinq", 1.35, ["r5t2", "106r"]),
    ("twingo", "Renaud Tango", 1.3, ["twingo", "106r"]),
    ("p106", "Pijo 106", 1.25, ["106r", "r5t2"]),
    ("clio", "Renaud Clia", 1.2, ["106r", "r5t2", "toledo"]),
    ("espace", "Renaud Espèce", 1.05, ["laguna", "toledo"]),
    ("p206", "Pijo 206", 1.2, ["106r", "r5t2", "toledo"]),
    ("laguna", "Renaud Lagune Break", 1.1, ["laguna", "omega"]),
    ("p306", "Pijo 306 Maxi et Gendarmerette", 1.4, ["r5t2", "106r"]),
    ("gt3", "Porc'Che 119 GT3 RS", 1.5, ["gt3_992", "gt3rs_991"]),
    ("ranger", "Fjord Rangeur Rapace", 1.0, ["mustang", "bronco"]),
    ("bus", "Autobus B1", 0.7, ["man_sg220", "dsl29"]),
]


def main(dossier, sortie, credits_path):
    credits = json.load(open(credits_path))
    sons = {}
    def son(nom):
        p = "%s/%s.mp3" % (dossier, nom)
        if not os.path.exists(p):
            return None
        if nom not in sons:
            sons[nom] = "data:audio/mpeg;base64," + base64.b64encode(open(p, "rb").read()).decode()
        return nom
    lignes = []
    for vid, nom, k, props in VOITURES:
        act = son("actuel_%s" % k)
        ch = [{"cle": "actuel", "son": act, "titre": "Son actuel", "desc": "4 cylindres de 106, transposé ×%s" % str(k).replace(".", ",")}]
        for i, c in enumerate(props):
            if son(c) and c in credits:
                ch.append({"cle": "ABC"[len(ch) - 1], "son": c, "titre": "Proposition " + "ABC"[len(ch) - 1],
                           "desc": credits[c]["desc"]})
        lignes.append({"id": vid, "nom": nom, "choix": ch})
    html = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "page_moteurs.html")).read()
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from build_moteurs import scenario
    sim, dt = scenario()
    k = 6
    html = html.replace("/*COURBE*/null", json.dumps({"t": [round(i * dt, 2) for i in range(0, len(sim), k)],
                                                     "rpm": [round(float(sim[i][0])) for i in range(0, len(sim), k)]}))
    html = html.replace("/*DONNEES*/null", json.dumps({"voitures": lignes, "sons": sons}, ensure_ascii=False))
    html = html.replace("<!--CREDITS-->", "".join(
        "<li>%s : « %s », %s, %s</li>" % (v["desc"], v["titre"], v["auteur"], v["licence"])
        for c, v in sorted(credits.items()) if c in sons))
    open(sortie, "w").write(html)
    print("%s : %.1f Mo, %d sons" % (sortie, os.path.getsize(sortie) / 1e6, len(sons)))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3])
