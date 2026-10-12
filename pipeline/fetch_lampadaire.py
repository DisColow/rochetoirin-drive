"""Lampadaire : « Street Lantern » de Samuel Francis Johnson (Oneironauticus) (Sketchfab, CC BY 4.0 ; jeton dans
SKETCHFAB_TOKEN, jamais écrit) -> ../godot/import/lampadaire/ (glTF d'origine), converti par blender_lampadaire.py.
Choisi par l'utilisateur sur la planche docs/apercus/lampadaires_candidats.jpg (modèle C : une tige et une lanterne)."""
import io, json, os, sys, urllib.request, zipfile

UID = "b1bf5198ec564eecb50f319609c671c3"
OUT = "../godot/import/lampadaire"


def main():
    if os.path.isfile(os.path.join(OUT, "scene.gltf")):
        return
    tok = os.environ.get("SKETCHFAB_TOKEN", "")
    if not tok:
        sys.exit("SKETCHFAB_TOKEN absent")
    h = {"Authorization": "Token " + tok}
    dl = json.loads(urllib.request.urlopen(urllib.request.Request(
        "https://api.sketchfab.com/v3/models/%s/download" % UID, headers=h)).read())
    z = zipfile.ZipFile(io.BytesIO(urllib.request.urlopen(dl["gltf"]["url"]).read()))
    os.makedirs(OUT, exist_ok=True)
    z.extractall(OUT)


if __name__ == "__main__":
    main()
