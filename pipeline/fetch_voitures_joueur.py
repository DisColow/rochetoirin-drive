"""Voitures du joueur à acheter au garage (#95, choix de l'utilisateur du 16/10) : modèles Sketchfab CC BY 4.0
(jeton dans SKETCHFAB_TOKEN, jamais écrit) -> ../godot/import/voitures/<id>/ (glTF d'origine), convertis par
blender_voitures_joueur.py. Noms et logos parodiés dans le jeu (pas de vraie marque)."""
import io, json, os, sys, urllib.request, zipfile

MODELES = {
    "espace": ("b8e7c65711134fca865f635ccddafcf5", "2008 Renault Espace", "tonielpro520"),    # modèle du début du jeu
    "deuche": ("abdb2d11268b405c90b117e0992693ee", "[FREE] 2CV Charleston 1986", "pagesm"),
    "clio": ("e3bbb96f7a61412086868ea3b136de2c", "1997 Renault Clio Mk.2", "ImperialBlue3D"),
    "laguna": ("89db7cd5a6c34e3ebee16f53293aba63", "Renault Laguna Estate 2001", "szymonpasterczyk"),
    "p206": ("513b76a9909049f49327c0b83bc5b56b", "2000 Peugeot 206", "tonielpro520"),
    "p106": ("ee99130773fd4cdfb31507ed1db11a62", "1996 Peugeot 106", "zairiqzairiqpixarcarsbfdi"),
    "p306": ("d5823d8aede14edcadcf0ccee7403528", "Lowpoly Peugeot 306 Maxi", "anxietybot"),
    "r5": ("8e1b46fcc3144809b3aec69028eb1811", "Renault 5 V2", "41iveR"),
    "gt3": ("c08b312e73754d0db8ab1e266eca8a28", "Porsche 911 GT3 RS (991.1) '16", "Car2022"),
    "twingo": ("a96fb412e30f450c864f74e2124ac2de", "Renault Twingo", "brentonmckey"),
}
OUT = "../godot/import/voitures"


def main(seuls=None):
    tok = os.environ.get("SKETCHFAB_TOKEN", "")
    if not tok:
        sys.exit("SKETCHFAB_TOKEN absent")
    h = {"Authorization": "Token " + tok}
    for k, (uid, nom, auteur) in MODELES.items():
        if seuls and k not in seuls:
            continue
        d = os.path.join(OUT, k)
        if os.path.isfile(os.path.join(d, "scene.gltf")):
            continue
        dl = json.loads(urllib.request.urlopen(urllib.request.Request(
            "https://api.sketchfab.com/v3/models/%s/download" % uid, headers=h)).read())
        z = zipfile.ZipFile(io.BytesIO(urllib.request.urlopen(dl["gltf"]["url"]).read()))
        os.makedirs(d, exist_ok=True)
        z.extractall(d)
        print(k, nom, auteur, "ok")


if __name__ == "__main__":
    main(sys.argv[1:])
