"""Voiture du joueur : « Ford Ranger Raptor 2019 » de David_Holiday (Sketchfab, CC BY 4.0 ; jeton dans SKETCHFAB_TOKEN,
jamais écrit) -> ../godot/import/ranger/ (glTF d'origine), converti par blender_ranger.py."""
import io, json, os, sys, urllib.request, zipfile

UID = "7dcc4fb472ab4e7eb8ae19ad036e2bf9"
OUT = "../godot/import/ranger"


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
