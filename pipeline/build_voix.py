"""Voix du taxi : chaque réplique de data/taxi.json enregistrée par synthèse vocale neuronale (Piper, hors ligne), puis
transformée par ffmpeg en talkie-walkie (version « D » choisie par l'utilisateur : bande 450-2600 Hz, compression forte,
saturation franche, grain numérique, souffle radio). Le jeu joue les fichiers tels quels, sans aucun effet ajouté
(v6.0 : les effets appliqués en jeu, décalage de hauteur compris, rendaient les voix incompréhensibles).
Répliques sans variable : enregistrées entières. Les 25 répliques à variables ({dest}…) : morceaux fixes + valeurs,
enchaînés en jeu.

Voix : les deux plus compréhensibles après effet D (mots reconnus par Vosk : Siwis 91 %, Gilles 89 % ; les voix MLS
56 à 79 %, écartées), déclinées en plusieurs hauteurs : passagères Siwis (CC BY 4.0), passagers et chauffeur Gilles
(CC0) ; chauffeur : UPMC « Pierre » (CC BY 4.0). Chaque fichier est ensuite normalisé (crête à -1 dBFS) : les voix
passent au-dessus du moteur et de la radio (v6.5).
Clé d'un fichier : md5 du texte (String.md5_text() en jeu).
Modèles : https://huggingface.co/rhasspy/piper-voices (fr_FR-siwis-medium, fr_FR-gilles-low, fr_FR-mls-medium), dans
data/voix_modeles/ (téléchargés ici s'ils manquent). Lancer avec le Python où piper-tts est installé :
  <venv>/bin/python build_voix.py
Sortie : ../godot/assets/voix/<voix>/<md5[:16]>.ogg + index.json {voix: {md5: durée}} ; reprend là où il s'est arrêté."""
import hashlib, io, json, os, re, subprocess, sys, urllib.request, wave
from multiprocessing import Pool

HERE = os.path.dirname(os.path.abspath(__file__))
TAXI = os.path.join(HERE, "..", "godot", "data", "taxi.json")
PLACES = os.path.join(HERE, "..", "godot", "world", "places.json")
COMMUNES = os.path.join(HERE, "data", "communes.json")
OUT = os.path.join(HERE, "..", "godot", "assets", "voix")
MOD = os.path.join(HERE, "data", "voix_modeles")
HF = "https://huggingface.co/rhasspy/piper-voices/resolve/main/fr/fr_FR/"
MODELES = {"fr_FR-siwis-medium": "siwis/medium/", "fr_FR-gilles-low": "gilles/low/", "fr_FR-upmc-medium": "upmc/medium/"}
VOIX = {  # nom : (modèle, locuteur, genre, hauteur) ; hauteur changée hors ligne (rubberband, timbre préservé)
    "f1": ("fr_FR-siwis-medium", None, "f", 1.0), "f2": ("fr_FR-siwis-medium", None, "f", 1.08),
    "f3": ("fr_FR-siwis-medium", None, "f", 0.9),
    "m1": ("fr_FR-gilles-low", None, "m", 1.0), "m2": ("fr_FR-gilles-low", None, "m", 1.1),
    "m3": ("fr_FR-gilles-low", None, "m", 0.92),
    "joueur": ("fr_FR-upmc-medium", 1, "m", 1.0),       # « Pierre » (96 % compris ; v6.5)
}
EFFET = ("highpass=f=450,lowpass=f=2600,acompressor=threshold=-24dB:ratio=8,volume=8dB,asoftclip=type=hard,"
         "acrusher=bits=10:mix=0.3")
VAR = re.compile(r"\{(prenom|age|metier|metier_detail|loisir|animal|famille|commune|dest|dest_commune)\}")


def accord(t, fem):
    t = re.sub(r"\{([^{}|]*)\|([^{}]*)\}", lambda m: m.group(2) if fem else m.group(1), t)
    return t.replace("{e}", "e" if fem else "")


def morceaux(t):
    """Texte (accords faits) -> la réplique entière si elle n'a pas de variable, sinon ses morceaux fixes (les valeurs
    des variables sont enregistrées à part)."""
    if not VAR.search(t):
        return [t.strip()]
    return [p.strip() for p in VAR.split(t)[::2] if p.strip()]


def parlable(t):
    return bool(re.search(r"\w", t))


def cle(t):
    return hashlib.md5(t.encode("utf-8")).hexdigest()


def collecte():
    d = json.load(open(TAXI))
    client, joueur = [], []
    for c in d["caracteres"]:
        client += c["bien"] + c["moyen"] + c["mal"] + sum(c["reponses"].values(), [])
    for q in d["questions"]:
        joueur += q["t"]
        client += q.get("fait", [])
    for fils in d["fils"].values():
        for fil in fils:
            for n in fil:
                client.append(n["dit"])
                for r in n["rep"].values():
                    if isinstance(r, dict):           # v6.12 : réponse + rebonds du client
                        joueur.append(r["t"])
                        client += [r["ok"], r["ko"]]
                    else:
                        joueur.append(r)
                if "silence" in n:
                    client += [n["silence"]["ok"], n["silence"]["ko"]]
    client += d["bonjour"] + sum(d["fin"].values(), []) + d["trop"] + d["derange"] + d["esquive"] + d["silence"]
    # valeurs des variables
    vals = {"f": set(), "m": set()}
    for g in "fm":
        vals[g] |= {m[g] for m in d["metiers"]}
        vals[g] |= {m["detail"] for m in d["metiers"]}
        vals[g] |= set(d["loisirs"]) | set(d["animaux"]) | set(d["familles"])
    lieux = {p["n"] for p in json.load(open(PLACES))} | {p["c"] for p in json.load(open(PLACES))}
    lieux |= set(json.load(open(COMMUNES)).keys())
    jobs = {}
    for v, (_, _, g, _) in VOIX.items():
        if v == "joueur":
            textes = {accord(t, False) for t in joueur}
            parts = {p for t in textes for p in morceaux(t)}
        else:
            parts = {p for t in client for p in morceaux(accord(t, g == "f"))} | vals[g] | lieux
        jobs[v] = sorted(p for p in parts if parlable(p))
    return jobs


def modeles():
    os.makedirs(MOD, exist_ok=True)
    for m, sub in MODELES.items():
        for ext in (".onnx", ".onnx.json"):
            f = os.path.join(MOD, m + ext)
            if not os.path.exists(f):
                print("téléchargement", m + ext)
                urllib.request.urlretrieve(HF + sub + m + ext, f)


def normaliser(f):
    """Crête du fichier amenée à -1 dBFS (deux passes : mesure, puis gain), réencodé en Vorbis."""
    r = subprocess.run(["ffmpeg", "-hide_banner", "-i", f, "-af", "volumedetect", "-f", "null", "-"], capture_output=True, text=True)
    m = re.search(r"max_volume: (-?[\d.]+) dB", r.stderr)
    if not m:
        return
    gain = -1.0 - float(m.group(1))
    if abs(gain) < 0.5:
        return
    tmp = f + ".tmp.ogg"
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", f, "-af", "volume=%.2fdB" % gain, "-ar", "11025", "-ac", "1",
                    "-c:a", "libvorbis", "-q:a", "-1", tmp], check=True)
    os.replace(tmp, f)


_voices = {}


def rendu(job):
    from piper import PiperVoice, SynthesisConfig
    v, texte = job
    modele, spk, _, hauteur = VOIX[v]
    f = os.path.join(OUT, v, cle(texte)[:16] + ".ogg")
    if modele not in _voices:
        _voices[modele] = PiperVoice.load(os.path.join(MOD, modele + ".onnx"))
    b = io.BytesIO()
    w = wave.open(b, "wb")
    # un peu plus posé que par défaut : plus clair à travers le talkie-walkie
    _voices[modele].synthesize_wav(texte, w, SynthesisConfig(speaker_id=spk, length_scale=1.08))
    w.close()
    w = wave.open(io.BytesIO(b.getvalue()))
    dur = w.getnframes() / w.getframerate()
    # silences de bord retirés, effet talkie-walkie « D », souffle radio mêlé ; 11 kHz suffisent (bande coupée à
    # 2,6 kHz) ; Vorbis basse qualité
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", "-", "-f", "lavfi", "-i", "anoisesrc=c=pink:a=0.02:r=22050",
                    "-filter_complex",
                    "[0]silenceremove=start_periods=1:start_threshold=-45dB,areverse,"
                    "silenceremove=start_periods=1:start_threshold=-45dB,areverse,apad=pad_dur=0.06,"
                    + ("rubberband=pitch=%.2f:formant=preserved," % hauteur if hauteur != 1.0 else "") + EFFET + "[v];"
                    "[1]highpass=f=300,lowpass=f=3400[n];[v][n]amix=inputs=2:duration=first:weights=1 1[o]",
                    "-map", "[o]", "-ar", "11025", "-ac", "1", "-c:a", "libvorbis", "-q:a", "-1", f],
                   input=b.getvalue(), check=True)
    normaliser(f)
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", f],
                         capture_output=True, text=True).stdout.strip()
    return v, cle(texte), round(float(out or dur), 3)


def main():
    modeles()
    jobs = collecte()
    idx_f = os.path.join(OUT, "index.json")
    idx = json.load(open(idx_f)) if os.path.exists(idx_f) else {}
    todo = []
    for v, textes in jobs.items():
        os.makedirs(os.path.join(OUT, v), exist_ok=True)
        idx.setdefault(v, {})
        keep = {cle(t) for t in textes}
        for k in list(idx[v]):                     # répliques supprimées
            if k not in keep:
                del idx[v][k]
                p = os.path.join(OUT, v, k[:16] + ".ogg")
                if os.path.exists(p):
                    os.remove(p)
        todo += [(v, t) for t in textes if cle(t) not in idx[v]]
    print("à enregistrer :", len(todo), "sur", sum(len(t) for t in jobs.values()), flush=True)
    with Pool(int(sys.argv[1]) if len(sys.argv) > 1 else 4) as pool:
        for i, (v, k, dur) in enumerate(pool.imap_unordered(rendu, todo, chunksize=8)):
            idx[v][k] = dur
            if i % 200 == 0:
                print(i, "/", len(todo), flush=True)
                json.dump(idx, open(idx_f, "w"))
    json.dump(idx, open(idx_f, "w"))
    tot = sum(os.path.getsize(os.path.join(OUT, v, f)) for v in jobs for f in os.listdir(os.path.join(OUT, v)))
    print("fini :", sum(len(x) for x in idx.values()), "morceaux,", round(tot / 1e6, 1), "Mo")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--normaliser":
        # normalise les fichiers déjà enregistrés (sans les ré-synthétiser)
        fs = [os.path.join(OUT, v, f) for v in VOIX if os.path.isdir(os.path.join(OUT, v)) for f in os.listdir(os.path.join(OUT, v)) if f.endswith(".ogg")]
        with Pool(4) as pool:
            pool.map(normaliser, fs, chunksize=32)
        print("normalisés :", len(fs))
    else:
        main()
