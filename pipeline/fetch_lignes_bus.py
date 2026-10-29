"""Lignes de bus du réseau urbain Ruban (#149, OSM : relations route=bus, network=Ruban) pour l'activité « Ligne de bus »
(scripts/ligne_bus.gd) : pour chaque variante de ligne, ses arrêts dans l'ordre (membres « stop » des relations, sinon
« platform »), avec leur nom et leur position dans le repère du jeu (geo.to_local).
Sortie : ../godot/world/lignes_bus.json = [{ref, nom, arrets: [[x, z, nom], ...]}], arrêts consécutifs homonymes réunis.
Le jeu ne garde que les arrêts proches d'un arrêt de bus de la carte (pietons.arrets_bus) et longés par une voie.
python3 fetch_lignes_bus.py"""
import json, os, time, urllib.parse, urllib.request
import geo

ICI = os.path.dirname(os.path.abspath(__file__))
SORTIE = os.path.join(ICI, "..", "godot", "world", "lignes_bus.json")
BB = "45.51,5.165,45.67,5.53"
RESEAU = "Ruban"
q = """[out:json][timeout:300];relation["route"="bus"]["network"="%s"](%s);out body;>;out body qt;""" % (RESEAU, BB)
b = b""
for k in range(8):
    u = ("https://overpass-api.de/api/interpreter", "https://maps.mail.ru/osm/tools/overpass/api/interpreter")[k % 2]
    try:
        b = urllib.request.urlopen(urllib.request.Request(u, data=urllib.parse.urlencode(dict(data=q)).encode()), timeout=600).read()
        if b[:1] == b"{":
            break
    except Exception as e:
        print("nouvel essai", u, e)
        time.sleep(10 * (k + 1))
d = json.loads(b)
noeuds = {e["id"]: e for e in d["elements"] if e["type"] == "node"}
lignes = []
for r in d["elements"]:
    if r["type"] != "relation":
        continue
    t = r["tags"]
    membres = [m for m in r["members"] if m["type"] == "node" and m["ref"] in noeuds]
    arrets = [m for m in membres if m.get("role", "").startswith("stop")]
    if len(arrets) < 3:
        arrets = [m for m in membres if m.get("role", "").startswith("platform")]
    l = []
    for m in arrets:
        n = noeuds[m["ref"]]
        nom = n.get("tags", {}).get("name", "")
        x, z = geo.to_local(n["lon"], n["lat"])
        if l and l[-1][2] == nom and nom:
            continue
        l.append([round(float(x), 1), round(float(z), 1), nom])
    if len(l) >= 3:
        nom = t.get("name", "")
        if ":" in nom:
            nom = nom.split(":", 1)[1].strip()
        lignes.append({"ref": t.get("ref", ""), "nom": nom, "arrets": l})
lignes.sort(key=lambda a: (a["ref"].zfill(3), a["nom"]))
json.dump(lignes, open(SORTIE, "w"), ensure_ascii=False)
print(len(lignes), "lignes,", sum(len(a["arrets"]) for a in lignes), "arrêts ->", SORTIE)
