"""Radars (#182, choix de l'utilisateur du 07/11) : modèles Sketchfab CC BY -> ../godot/import/radars/<id>/ (glTF
d'origine), convertis par blender_radars.py. Clé Sketchfab : secret réseau de l'environnement cloud (le proxy l'ajoute
aux appels vers api.sketchfab.com), sinon SKETCHFAB_TOKEN."""
import io, json, os, sys, urllib.request, zipfile

MODELES = {
    "radar_mobile": ("0d274b384f55481494acdba43d9a3e4c", "Portable Speed Camera", "rxf10240"),   # A
    "radar_fixe": ("82b93e76b73a46be9ec78c440f9a15be", "Speed Camera UK", "ThomasRedfern12"),     # D
}
OUT = "../godot/import/radars"


def main():
    h = {"Authorization": "Token " + os.environ.get("SKETCHFAB_TOKEN", "secret-du-proxy")}
    for k, (uid, nom, auteur) in MODELES.items():
        d = os.path.join(OUT, k)
        if os.path.isfile(os.path.join(d, "scene.gltf")):
            continue
        dl = json.loads(urllib.request.urlopen(urllib.request.Request(
            "https://api.sketchfab.com/v3/models/%s/download" % uid, headers=h)).read())
        z = zipfile.ZipFile(io.BytesIO(urllib.request.urlopen(dl["gltf"]["url"]).read()))
        os.makedirs(d, exist_ok=True)
        z.extractall(d)
        print(k, nom, auteur, "ok")
    open(os.path.join(OUT, ".gdignore"), "w").close()


if __name__ == "__main__":
    main()
