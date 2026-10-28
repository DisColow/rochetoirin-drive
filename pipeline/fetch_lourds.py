"""Véhicules lourds de la circulation (#136, choix de l'utilisateur : T5 et B1) : modèles Sketchfab CC BY (jeton dans
SKETCHFAB_TOKEN, jamais écrit) -> ../godot/import/lourds/<nom>/model.glb, convertis par blender_lourds.py.
Crédits : data/lourds_credits.json et ⚙ > Crédits."""
import json, os, sys, urllib.request

MODELS = {
    "tracteur": "201a2464cd4e4501b14f438ca7893cee",   # « Tractor With Trailer – Low Poly 3D Model » — KidBi-Gaming
    "bus": "14fe03d792914d51b6c6250b393c44fd",        # « Generic Town Bus » — own.guest
}
TOK = os.environ.get("SKETCHFAB_TOKEN", "")
OUT = "../godot/import/lourds"
H = {"Authorization": "Token " + TOK}


def main():
    creds = {}
    for name, uid in MODELS.items():
        info = json.loads(urllib.request.urlopen(urllib.request.Request("https://api.sketchfab.com/v3/models/" + uid, headers=H)).read())
        creds[name] = dict(title=info["name"], author=info["user"]["username"], license=info["license"]["label"],
                           url=info["viewerUrl"])
        f = os.path.join(OUT, name, "model.glb")
        if not os.path.isfile(f):
            if not TOK:
                sys.exit("SKETCHFAB_TOKEN absent")
            dl = json.loads(urllib.request.urlopen(urllib.request.Request(
                "https://api.sketchfab.com/v3/models/%s/download" % uid, headers=H)).read())
            os.makedirs(os.path.dirname(f), exist_ok=True)
            open(f, "wb").write(urllib.request.urlopen(dl["glb"]["url"]).read())
        print(name, creds[name]["title"], "—", creds[name]["author"], creds[name]["license"])
    json.dump(creds, open("data/lourds_credits.json", "w"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
