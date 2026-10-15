"""Pièces du garage (issue #43 : l'utilisateur a pris tous les modèles de la planche) : modèles Sketchfab CC BY
-> ../godot/import/garage/<code>/ (glTF d'origine), convertis par blender_garage.py. Crédits : data/garage_credits.json."""
import io, json, os, sys, urllib.request, zipfile
MODELES = {
    "S1": "5e118ed64b6b4cdb9b5a2931c06a0bc4", "S2": "d5ba2afc8faa496d95b64cb985b94a69", "S3": "61834dfc0ef444e8a41e10477dd5318c",
    "S4": "bdbc8cc1ab344e59beba76c76184a11a", "S5": "3c157328246140c0b8e1c106cb15ad7b",
    "E1": "af9ed6bfdfd448828921d3e067a373c4", "E2": "67879c173db6460bac6b1b67172cc460", "E3": "972169c2bf3f4686b5ee0ab843233c22",
    "E4": "a2f88d80c04f49dd9d13d2084c99c94f",
    "J1": "4e50d45e5ff04d00927a50c150e088c1", "J2": "3efc6a0cb9cc44d9adf24e226991a261", "J3": "68f53cc291724ccda5d0659824bb273f",
    "J4": "c5798e6b29d046c798c38647455dfab2", "J5": "e36860f9f8de4d8e8429cb07007142f2",
}
TOK = os.environ.get("SKETCHFAB_TOKEN", "")
H = {"Authorization": "Token " + TOK}
cred = json.load(open("data/garage_credits.json")) if os.path.exists("data/garage_credits.json") else {}
for code, uid in MODELES.items():
    out = "../godot/import/garage/" + code
    if code not in cred:
        info = json.loads(urllib.request.urlopen(urllib.request.Request("https://api.sketchfab.com/v3/models/" + uid, headers=H)).read())
        cred[code] = dict(title=info["name"], author=info["user"]["username"], license=info["license"]["label"], url=info["viewerUrl"])
    if not os.path.isdir(out):
        if not TOK:
            sys.exit("SKETCHFAB_TOKEN absent")
        dl = json.loads(urllib.request.urlopen(urllib.request.Request(
            "https://api.sketchfab.com/v3/models/%s/download" % uid, headers=H)).read())
        z = zipfile.ZipFile(io.BytesIO(urllib.request.urlopen(dl["gltf"]["url"]).read()))
        os.makedirs(out); z.extractall(out)
    print(code, cred[code]["title"], "|", cred[code]["license"], sorted(os.listdir(out)))
json.dump(cred, open("data/garage_credits.json", "w"), ensure_ascii=False, indent=1)
