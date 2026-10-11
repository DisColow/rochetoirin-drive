"""Radio de la voiture : stations à thème, musiques de Kevin MacLeod (incompetech.com, licence CC BY 4.0, crédits
dans ⚙ > Crédits et ../godot/assets/radio/radio.json) -> ../godot/assets/radio/*.ogg (mono 32 kHz : un autoradio
des années 80 n'en demande pas plus, et l'APK reste léger).
Choix : catalogue incompetech (pieces.json) filtré par genre et ambiance (pas de morceaux sombres ou inquiétants),
durée 1 min 45 à 4 min 30, six morceaux par station, tirage déterministe."""
import hashlib, json, os, subprocess, time, urllib.parse, urllib.request

OUT = "../godot/assets/radio"
RAW = "data/radio"
CAT = "https://incompetech.com/music/royalty-free/pieces.json"
MP3 = "https://incompetech.com/music/royalty-free/mp3-royaltyfree/%s"
BAD = {"Dark", "Eerie", "Unnerving", "Somber", "Suspenseful", "Aggressive", "Mysterious", "Intense"}
# station : (nom affiché, fréquence affichée, genres incompetech, ambiances voulues)
STATIONS = [
    ("Rochetoirin FM", "88.4", {"16", "18", "6"}, {"Bright", "Bouncy", "Driving", "Uplifting"}),
    ("Isère Jazz", "91.2", {"11", "3"}, {"Relaxed", "Grooving", "Calming"}),
    ("Dauphiné Classique", "95.7", {"4"}, {"Calming", "Relaxed", "Bright", "Grooving", "Uplifting"}),
    ("Radio Soleil", "99.1", {"8", "12", "21"}, {"Bouncy", "Grooving", "Bright"}),
    ("Bourgoin Électro", "104.6", {"7"}, {"Grooving", "Bright", "Driving", "Relaxed"}),
    ("Radio Rétro", "107.3", {"20"}, {"Bright", "Bouncy", "Humorous", "Grooving"}),
]
PER = 6


def secs(s):
    p = [int(x) for x in s.split(":")]
    return p[0] * 3600 + p[1] * 60 + p[2] if len(p) == 3 else p[0] * 60 + p[1]


def get(u):
    for k in range(4):
        try:
            return urllib.request.urlopen(urllib.request.Request(u, headers={"User-Agent": "Mozilla/5.0"}), timeout=180).read()
        except Exception as e:
            print("nouvel essai", u, e); time.sleep(3 * (k + 1))
    raise RuntimeError(u)


def main():
    import shutil
    shutil.rmtree(OUT, ignore_errors=True)
    os.makedirs(OUT, exist_ok=True); os.makedirs(RAW, exist_ok=True)
    pieces = json.loads(get(CAT))
    used = set()
    out = []
    for name, freq, genres, feels in STATIONS:
        cand = []
        for p in pieces:
            f = {x.strip() for x in (p.get("feel") or "").split(",") if x.strip()}
            if p.get("genre") not in genres or f & BAD or not (f & feels):
                continue
            d = secs(p.get("length") or "0:0")
            if not (105 <= d <= 270) or p["title"] in used or "Sting" in p["title"]:
                continue
            cand.append((hashlib.md5(p["title"].encode()).hexdigest(), p, d))
        cand.sort(key=lambda c: c[0])
        tracks = []
        for _, p, d in cand[:PER]:
            used.add(p["title"])
            fn = p["filename"]
            raw = os.path.join(RAW, fn)
            if not os.path.exists(raw):
                open(raw, "wb").write(get(MP3 % urllib.parse.quote(fn)))
            slug = "".join(c if c.isalnum() else "_" for c in p["title"].lower()).strip("_")
            ogg = "%s/%s.ogg" % (OUT, slug)
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", raw, "-ac", "1", "-ar", "32000", "-c:a", "libvorbis",
                            "-q:a", "2", ogg], check=True)
            tracks.append({"titre": p["title"], "fichier": slug, "duree": d})
            print("%-20s %s (%d s)" % (name, p["title"], d))
        out.append({"nom": name, "freq": freq, "morceaux": tracks})
    json.dump({"stations": out, "auteur": "Kevin MacLeod (incompetech.com)", "licence": "CC BY 4.0"},
              open(OUT + "/radio.json", "w"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
