"""Clients du taxi : « Low Poly Characters (PACK) » de micaelsampaio (Sketchfab, CC BY 4.0 ; jeton dans
SKETCHFAB_TOKEN, jamais écrit) -> ../godot/import/clients/, découpé par blender_clients.py. Crédit dans ⚙ > Crédits."""
import io, os, sys, json, urllib.request, zipfile
UID = "f1c8018af59643e0b009a6f018ed9fd9"
TOK = os.environ.get("SKETCHFAB_TOKEN", "")
OUT = "../godot/import/clients"
if not os.path.exists(os.path.join(OUT, "scene.gltf")):
    if not TOK:
        sys.exit("SKETCHFAB_TOKEN absent")
    H = {"Authorization": "Token " + TOK}
    dl = json.loads(urllib.request.urlopen(urllib.request.Request(
        "https://api.sketchfab.com/v3/models/%s/download" % UID, headers=H)).read())
    os.makedirs(OUT, exist_ok=True)
    zipfile.ZipFile(io.BytesIO(urllib.request.urlopen(dl["gltf"]["url"]).read())).extractall(OUT)
print(sorted(os.listdir(OUT)))
