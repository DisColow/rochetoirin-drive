"""Modèles 3D des animaux des prés (Sketchfab, CC-BY ; jeton dans SKETCHFAB_TOKEN, jamais écrit)
-> ../godot/import/animaux/<nom>/ (glTF d'origine), convertis par blender_animaux_import.py. Crédits : data/animaux_credits.json."""
import io, json, os, sys, urllib.request, zipfile
MODELS = {
    "vache": "99d333e3b4e4470a8d7d38436489c001",      # Cow — JosueBoisvert (pie rouge, type Montbéliarde)
    "mouton": "08b05ae799d947f1a68c49b2d661eb53",     # Sheep — kenchoo
    "cheval": "bc64f4ff7966474ca9bacd42fa73a754",     # Horse Rigged (Game Ready) — abhayexe
}
TOK = os.environ.get("SKETCHFAB_TOKEN", "")
OUT = "../godot/import/animaux"
credits = {}
for name, uid in MODELS.items():
    H = {"Authorization": "Token " + TOK}
    info = json.loads(urllib.request.urlopen(urllib.request.Request("https://api.sketchfab.com/v3/models/" + uid, headers=H)).read())
    credits[name] = dict(title=info["name"], author=info["user"]["username"], license=info["license"]["label"],
                         url=info["viewerUrl"])
    d = os.path.join(OUT, name)
    if os.path.isdir(d):
        continue
    if not TOK:
        sys.exit("SKETCHFAB_TOKEN absent")
    dl = json.loads(urllib.request.urlopen(urllib.request.Request(
        "https://api.sketchfab.com/v3/models/%s/download" % uid, headers=H)).read())
    z = zipfile.ZipFile(io.BytesIO(urllib.request.urlopen(dl["gltf"]["url"]).read()))
    os.makedirs(d); z.extractall(d)
    print(name, sorted(os.listdir(d)))
json.dump(credits, open("data/animaux_credits.json", "w"), ensure_ascii=False, indent=1)
print(json.dumps(credits, ensure_ascii=False, indent=1))
