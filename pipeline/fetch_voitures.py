"""Voitures garées : modèles gratuits Sketchfab (CC BY, voitures génériques sans logo de vraie marque ; jeton dans
SKETCHFAB_TOKEN, jamais écrit) -> ../godot/import/voitures/<nom>/ (glTF d'origine), convertis par
blender_voitures.py. Crédits : data/voitures_credits.json et ⚙ > Crédits."""
import io, json, os, sys, urllib.request, zipfile

MODELS = {
    "berline80": "af108d4773df4722a62420f65dd5b8fe",     # « Generic 80s european car » — henryviii
    "citadine": "ebe7c5e98a7448b5abb2eaf0cb22b766",      # « Low Poly Small car » — scailman
    "berline": "aeb2699532b4402e8b75ec8888b800b9",       # « Low-Poly Sedan car » — scailman
    "compacte": "a4c46087374a4a3e979092512f92c057",      # « Blue Sedan | Stylized Low Poly » — R3indeer
}
TOK = os.environ.get("SKETCHFAB_TOKEN", "")
OUT = "../godot/import/voitures"
H = {"Authorization": "Token " + TOK}


def main():
    creds = {}
    for name, uid in MODELS.items():
        info = json.loads(urllib.request.urlopen(urllib.request.Request("https://api.sketchfab.com/v3/models/" + uid, headers=H)).read())
        creds[name] = dict(title=info["name"], author=info["user"]["username"], license=info["license"]["label"],
                           url=info["viewerUrl"])
        d = os.path.join(OUT, name)
        if not os.path.isdir(d):
            if not TOK:
                sys.exit("SKETCHFAB_TOKEN absent")
            dl = json.loads(urllib.request.urlopen(urllib.request.Request(
                "https://api.sketchfab.com/v3/models/%s/download" % uid, headers=H)).read())
            z = zipfile.ZipFile(io.BytesIO(urllib.request.urlopen(dl["gltf"]["url"]).read()))
            os.makedirs(d)
            z.extractall(d)
        print(name, creds[name]["title"], "—", creds[name]["author"], creds[name]["license"])
    json.dump(creds, open("data/voitures_credits.json", "w"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
