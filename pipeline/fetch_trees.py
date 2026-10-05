"""Modèles 3D de végétation (Sketchfab, CC-BY ; jeton dans SKETCHFAB_TOKEN, jamais écrit) -> ../godot/import/trees/<nom>/
(importés par Godot, convertis par tools/prepare_trees.gd). Crédits : data/trees_credits.json."""
import io, json, os, sys, urllib.request, zipfile
MODELS = {
    "chene": "3dc59560f2d24345bdbe65c44636453b",      # Oak tree — massive-graphisme
    "feuillu": "d989c0f801d847b9a74992ec4ddcfdfc",    # Realistic Tree — danielpetrov
    "chene2": "6468dd4d3eb240ef902b9057d9913606",     # Oak tree — evolveduk
    "bouleau": "aa842dffd9654d33b8b91170ce83c172",    # Birch tree — evolveduk
    "peuplier": "ec7c1d301bbc43dca5fe5f0650148d13",   # Poplar tree — evseevdaniil0011
    "epicea": "7a5db417827244d98827459bce0cc944",     # Spruce tree — intice184
    "sapin": "0965de5def1342cd8b8b1a0fa5643e27",      # Fir tree — intice184
    "pin": "d45218a3fab349e5b1de040f29e7b6f9",        # Pine Tree — evolveduk
    "mais": "5fd3b104d8104519b061469c365d4974",       # Maize Corn Plant — gilles.schaeck
}
TOK = os.environ.get("SKETCHFAB_TOKEN", "")
OUT = "../godot/import/trees"
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
json.dump(credits, open("data/trees_credits.json", "w"), ensure_ascii=False, indent=1)
