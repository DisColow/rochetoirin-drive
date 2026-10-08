"""Soucoupe volante du gardien des limites (Sketchfab, CC BY ; jeton dans SKETCHFAB_TOKEN, jamais écrit)
-> ../godot/import/ufo/ (glTF d'origine), converti par blender_ufo.py. Crédit : data/ufo_credits.json et ⚙ > Crédits."""
import io, json, os, sys, urllib.request, zipfile
UID = "75655f43c4fc4c56ab60746caf7119fe"      # « UFO » — sebslom
TOK = os.environ.get("SKETCHFAB_TOKEN", "")
OUT = "../godot/import/ufo"
H = {"Authorization": "Token " + TOK}
info = json.loads(urllib.request.urlopen(urllib.request.Request("https://api.sketchfab.com/v3/models/" + UID, headers=H)).read())
cred = dict(title=info["name"], author=info["user"]["username"], license=info["license"]["label"], url=info["viewerUrl"])
if not os.path.isdir(OUT):
    if not TOK:
        sys.exit("SKETCHFAB_TOKEN absent")
    dl = json.loads(urllib.request.urlopen(urllib.request.Request(
        "https://api.sketchfab.com/v3/models/%s/download" % UID, headers=H)).read())
    z = zipfile.ZipFile(io.BytesIO(urllib.request.urlopen(dl["gltf"]["url"]).read()))
    os.makedirs(OUT); z.extractall(OUT)
json.dump(cred, open("data/ufo_credits.json", "w"), ensure_ascii=False, indent=1)
print(cred, sorted(os.listdir(OUT)))
