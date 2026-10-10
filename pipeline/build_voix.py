"""Voix du taxi : chaque réplique de data/taxi.json enregistrée par synthèse vocale neuronale (Piper, hors ligne),
pour une voix intelligible (l'effet talkie-walkie est ajouté en jeu par le bus « Voix »).

Voix (choisies avec choix_voix : taux de mots reconnus par Vosk après effet talkie-walkie, 90 à 95 %) :
  passagères : Siwis (CC BY 4.0), MLS 51 et 111 (Multilingual LibriSpeech, CC BY 4.0) ;
  passagers  : Gilles (CC0), MLS 87 et 84 ; chauffeur (le joueur) : MLS 78.
Les variables ({dest}, {metier}…) sont enregistrées à part et enchaînées en jeu : une réplique = morceaux de texte
fixes + valeurs. Clé d'un morceau : md5 du texte (String.md5_text() en jeu).
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
MODELES = {"fr_FR-siwis-medium": "siwis/medium/", "fr_FR-gilles-low": "gilles/low/", "fr_FR-mls-medium": "mls/medium/"}
VOIX = {  # nom : (modèle, locuteur, genre)
    "f1": ("fr_FR-siwis-medium", None, "f"), "f2": ("fr_FR-mls-medium", 51, "f"), "f3": ("fr_FR-mls-medium", 111, "f"),
    "m1": ("fr_FR-gilles-low", None, "m"), "m2": ("fr_FR-mls-medium", 87, "m"), "m3": ("fr_FR-mls-medium", 84, "m"),
    "joueur": ("fr_FR-mls-medium", 78, "m"),
}
VAR = re.compile(r"\{(prenom|age|metier|metier_detail|loisir|animal|famille|commune|dest|dest_commune)\}")


def accord(t, fem):
    t = re.sub(r"\{([^{}|]*)\|([^{}]*)\}", lambda m: m.group(2) if fem else m.group(1), t)
    return t.replace("{e}", "e" if fem else "")


def morceaux(t):
    """Texte (accords faits) -> morceaux fixes (les variables sont enregistrées à part)."""
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
                joueur += list(n["rep"].values())
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
    for v, (_, _, g) in VOIX.items():
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


_voices = {}


def rendu(job):
    from piper import PiperVoice, SynthesisConfig
    v, texte = job
    modele, spk, _ = VOIX[v]
    f = os.path.join(OUT, v, cle(texte)[:16] + ".ogg")
    if modele not in _voices:
        _voices[modele] = PiperVoice.load(os.path.join(MOD, modele + ".onnx"))
    b = io.BytesIO()
    w = wave.open(b, "wb")
    # un peu plus posé que par défaut : plus clair à travers le talkie-walkie
    _voices[modele].synthesize_wav(texte, w, SynthesisConfig(speaker_id=spk, length_scale=1.05))
    w.close()
    w = wave.open(io.BytesIO(b.getvalue()))
    dur = w.getnframes() / w.getframerate()
    # 16 kHz suffisent (bande passante du talkie-walkie : 3,2 kHz) ; silences de bord retirés ; Vorbis basse qualité
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", "-", "-af",
                    "silenceremove=start_periods=1:start_threshold=-45dB,areverse,"
                    "silenceremove=start_periods=1:start_threshold=-45dB,areverse,apad=pad_dur=0.04",
                    "-ar", "16000", "-ac", "1", "-c:a", "libvorbis", "-q:a", "0", f], input=b.getvalue(), check=True)
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
    main()
