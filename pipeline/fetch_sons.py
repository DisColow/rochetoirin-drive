"""Enregistrements sonores repris en ligne -> data/sons/ (bruts, non versionnés), retravaillés par build_sons.py.
Source principale : BigSoundBank / La Sonothèque de Joseph Sardin (https://bigsoundbank.com), licence CC0 (crédit
« Joseph SARDIN - BigSoundBank.com » dans ⚙ > Crédits). Le catalogue (numéros des sons) est dans build_sons.py."""
import os, sys, time, urllib.error, urllib.request

OUT = "data/sons"


def bsb(n):
    """Son n° n de BigSoundBank, dans la meilleure qualité disponible (FLAC, sinon WAV, sinon OGG)."""
    os.makedirs(OUT, exist_ok=True)
    for ext in ("flac", "wav", "ogg"):
        p = "%s/bsb_%04d.%s" % (OUT, n, ext)
        if os.path.exists(p) and os.path.getsize(p) > 1000:
            return p
    for ext, d in (("flac", "flac"), ("wav", "bwf-en"), ("wav", "wav"), ("ogg", "ogg")):
        u = "https://bigsoundbank.com/UPLOAD/%s/%04d.%s" % (d, n, ext)
        for k in range(3):
            try:
                b = urllib.request.urlopen(urllib.request.Request(u, headers={"User-Agent": "Mozilla/5.0"}), timeout=120).read()
                p = "%s/bsb_%04d.%s" % (OUT, n, ext)
                open(p, "wb").write(b)
                return p
            except urllib.error.HTTPError as e:
                if e.code == 404:
                    break
                print("nouvel essai", u, e); time.sleep(3 * (k + 1))
            except Exception as e:
                print("nouvel essai", u, e); time.sleep(3 * (k + 1))
    raise RuntimeError("son %d introuvable" % n)


def mixkit(n):
    """Son n° n de Mixkit (https://mixkit.co, licence libre « Mixkit Sound Effects Free License » : usage gratuit dans
    un jeu, sans attribution obligatoire ; crédit donné quand même dans ⚙ > Crédits), en WAV."""
    os.makedirs(OUT, exist_ok=True)
    p = "%s/mixkit_%d.wav" % (OUT, n)
    if os.path.exists(p) and os.path.getsize(p) > 1000:
        return p
    u = "https://assets.mixkit.co/active_storage/sfx/%d/%d.wav" % (n, n)
    for k in range(3):
        try:
            b = urllib.request.urlopen(urllib.request.Request(u, headers={"User-Agent": "Mozilla/5.0"}), timeout=120).read()
            open(p, "wb").write(b)
            return p
        except Exception as e:
            print("nouvel essai", u, e); time.sleep(3 * (k + 1))
    raise RuntimeError("son mixkit %d introuvable" % n)


def main():
    from build_sons import SONS
    ids = sorted({s["bsb"] for s in SONS.values() if "bsb" in s} | {int(a) for a in sys.argv[1:]})
    for n in ids:
        print(bsb(n))


if __name__ == "__main__":
    main()
