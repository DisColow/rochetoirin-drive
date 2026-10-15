"""Aéronefs du ciel (issue #46, choix de Claude laissé par l'utilisateur, sans montgolfière) : modèles Sketchfab CC BY
-> ../godot/import/aeronefs/<nom>/ (glTF d'origine), convertis par blender_aeronefs.py. Crédits : data/aeronefs_credits.json."""
import io, json, os, sys, urllib.request, zipfile
MODELES = {
    "tourisme": "aa0f72aead044664a0555f047cb36262",   # Free Cessna 172 Replica (Low-Poly) — quadzii
    "ligne": "f06d488f08764e3ca26f2917d4053c69",      # Low Poly Airliner — maurogsw
    "helico": "5bbed2de9baa4a13a7faa72653b78b64",     # Low Poly Helicopter — antonmoek
    "planeur": "45ffefc38fcf4e76a9d0c2a4e76262ef",    # UNDERPOLY: Free Sailplane — underpolyproject
}
TOK = os.environ.get("SKETCHFAB_TOKEN", "")
H = {"Authorization": "Token " + TOK}
cred = {}
for nom, uid in MODELES.items():
    out = "../godot/import/aeronefs/" + nom
    info = json.loads(urllib.request.urlopen(urllib.request.Request("https://api.sketchfab.com/v3/models/" + uid, headers=H)).read())
    cred[nom] = dict(title=info["name"], author=info["user"]["username"], license=info["license"]["label"], url=info["viewerUrl"])
    if not os.path.isdir(out):
        if not TOK:
            sys.exit("SKETCHFAB_TOKEN absent")
        dl = json.loads(urllib.request.urlopen(urllib.request.Request(
            "https://api.sketchfab.com/v3/models/%s/download" % uid, headers=H)).read())
        z = zipfile.ZipFile(io.BytesIO(urllib.request.urlopen(dl["gltf"]["url"]).read()))
        os.makedirs(out); z.extractall(out)
    print(nom, cred[nom], sorted(os.listdir(out)))
json.dump(cred, open("data/aeronefs_credits.json", "w"), ensure_ascii=False, indent=1)
