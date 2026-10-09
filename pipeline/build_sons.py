"""Banque de sons du jeu d'après des enregistrements réels (fetch_sons.py -> data/sons/) -> ../godot/assets/sfx/*.ogg.

Chaque entrée de SONS : source (numéro BigSoundBank, CC0), extrait (t0, t1 en s), filtres (passe-haut / passe-bas en
Hz), boucle (fondu enchaîné de `xf` s entre la fin et le début : boucle sans couture), niveau visé (RMS en dBFS),
transposition (facteur de vitesse) et fondus d'entrée / de sortie pour les sons ponctuels. Mono 44,1 kHz, Ogg Vorbis.
Le jeu règle les boucles (stream.loop) lui-même."""
import os, subprocess
import numpy as np
from scipy.signal import butter, sosfiltfilt

from fetch_sons import bsb

SR = 44100
OUT = "../godot/assets/sfx"

K = "data/sons/kenney_impact/Audio/%s.ogg"          # Kenney « Impact Sounds » (CC0)
SONS = {
    # soucoupe du gardien : vrombissement tournant (boucle), passage en piqué, rayon tracteur
    "soucoupe": dict(bsb=2121, t0=0.5, t1=9.4, loop=True, xf=0.8, db=-16),
    "soucoupe_arrivee": dict(bsb=2122, t0=0.0, t1=6.0, db=-14, fo=0.6),
    "soucoupe_depart": dict(bsb=1972, t0=1.5, t1=10.5, db=-16, fi=0.3, fo=2.0, speed=1.15),
    "rayon": dict(bsb=2118, t0=0.3, t1=9.6, loop=True, xf=0.6, hp=180, lp=5000, db=-22, speed=0.75),
    # voiture : démarreur, roulement selon la surface, vent, crissement des pneus
    "demarreur": dict(bsb=966, t0=0.3, t1=5.0, db=-17, fo=1.2),
    "roule_asphalte": dict(bsb=1282, calme=10, loop=True, xf=1.0, speed=0.6, hp=60, lp=3500, db=-20),
    "roule_gravier": dict(bsb=1284, calme=8, loop=True, xf=1.0, speed=0.8, hp=80, db=-19),
    "roule_herbe": dict(bsb=1843, calme=6, loop=True, xf=1.0, speed=0.85, lp=2500, db=-21),
    "vent": dict(bsb=595, calme=20, loop=True, xf=2.0, hp=120, db=-20),
    "crissement": dict(bsb=2371, calme=2.0, loop=True, xf=0.4, hp=300, db=-17),
    "pluie_toit": dict(bsb=1293, calme=30, loop=True, xf=2.0, db=-22),
    # ambiances (fonds en boucle, fenêtre la plus régulière de l'enregistrement)
    "amb_jour": dict(bsb=97, calme=50, loop=True, xf=4.0, db=-24, q=3),
    "amb_jour2": dict(bsb=1911, calme=50, loop=True, xf=4.0, db=-24, q=3),
    "amb_soir": dict(bsb=1859, calme=50, loop=True, xf=4.0, db=-24, q=3),
    "amb_nuit": dict(bsb=1880, calme=50, loop=True, xf=4.0, db=-24, q=3),
    "amb_village": dict(bsb=1346, calme=50, loop=True, xf=4.0, db=-24, q=3),
    "amb_ville": dict(bsb=3188, calme=50, loop=True, xf=4.0, db=-23, q=3),
    "amb_bois": dict(bsb=904, calme=45, loop=True, xf=4.0, db=-25, q=3),
    "amb_autoroute": dict(bsb=122, calme=40, loop=True, xf=4.0, db=-22, q=3),
    "ruisseau": dict(bsb=864, calme=30, loop=True, xf=3.0, db=-20, q=3),
    "ruisseau2": dict(bsb=823, calme=30, loop=True, xf=3.0, db=-20, q=3),
    # sons ponctuels (oiseaux, animaux, cloche) : silences retirés
    **{"merle_%d" % i: dict(bsb=n, trim=True, db=-22) for i, n in enumerate((3476, 3483, 3485, 3486, 3487, 3490, 3494, 3498))},
    "rougegorge": dict(bsb=1670, trim=True, db=-23),
    **{"rossignol_%d" % i: dict(bsb=n, trim=True, db=-23) for i, n in enumerate((3086, 3087, 3088))},
    "chouette": dict(bsb=1764, trim=True, db=-22),
    "corneille": dict(bsb=956, trim=True, db=-22),
    **{"vache_%d" % i: dict(bsb=n, trim=True, db=-20) for i, n in enumerate((2382, 2383, 2384, 2385, 2386))},
    **{"chien_%d" % i: dict(bsb=n, trim=True, db=-21) for i, n in enumerate((2352, 2354, 2955))},
    "cloche": dict(bsb=3446, trim=True, trim_db=-50, db=-18),
    # chocs de la voiture selon ce qu'elle heurte
    **{"choc_dur_%d" % i: dict(file=K % ("impactMetal_heavy_%03d" % i), db=-12) for i in range(5)},
    **{"choc_moyen_%d" % i: dict(file=K % ("impactMetal_medium_%03d" % i), db=-14) for i in range(5)},
    **{"choc_leger_%d" % i: dict(file=K % ("impactMetal_light_%03d" % i), db=-16) for i in range(5)},
    **{"choc_bois_%d" % i: dict(file=K % ("impactWood_heavy_%03d" % i), db=-13) for i in range(5)},
    **{"choc_plastique_%d" % i: dict(file=K % ("impactPlate_medium_%03d" % i), db=-15) for i in range(5)},
    **{"choc_sol_%d" % i: dict(file=K % ("impactSoft_heavy_%03d" % i), db=-13, lp=900) for i in range(5)},
}


def load_file(p):
    b = subprocess.run(["ffmpeg", "-v", "error", "-i", p, "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"],
                       capture_output=True, check=True).stdout
    return np.frombuffer(b, np.float32).astype(np.float64)


def load(n):
    return load_file(bsb(n))


load_any = load


def write_ogg(name, x, db=-18, q=4):
    """Niveau : RMS visé (dBFS), crête limitée en douceur à -1 dBFS ; mono Ogg Vorbis."""
    rms = np.sqrt(np.mean(x ** 2)) + 1e-12
    x = x * 10 ** (db / 20) / rms
    if np.abs(x).max() > 0.89:
        x = 0.89 * np.tanh(x / 0.89)
    p = "%s/%s.ogg" % (OUT, name)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "1", "-i", "-",
                    "-c:a", "libvorbis", "-q:a", str(q), p], input=x.astype(np.float32).tobytes(), check=True)
    return p


def filt(x, hp=None, lp=None):
    if hp:
        x = sosfiltfilt(butter(4, hp, "highpass", fs=SR, output="sos"), x)
    if lp:
        x = sosfiltfilt(butter(4, lp, "lowpass", fs=SR, output="sos"), x)
    return x


def resample(x, speed):
    """Transposition par rééchantillonnage (speed > 1 : plus aigu et plus court)."""
    n = int(len(x) / speed)
    return np.interp(np.arange(n) * speed, np.arange(len(x)), x)


def make_loop(x, xf):
    """Boucle sans couture : les `xf` dernières secondes sont fondues (puissance constante) dans le début."""
    k = int(xf * SR)
    a = np.linspace(0, np.pi / 2, k)
    head = x[:k] * np.sin(a) + x[-k:] * np.cos(a)
    return np.concatenate([head, x[k:-k]])


def calm_window(x, dur, step=0.5):
    """Début (s) de la fenêtre de `dur` s la plus régulière : pas de bruit de manipulation, de voiture qui passe… (on
    minimise le rapport entre la sonie maximale sur 0,5 s et la sonie médiane de la fenêtre)."""
    h = int(0.5 * SR)
    e = np.sqrt(np.convolve(x ** 2, np.ones(h) / h, "valid")[::h // 2] + 1e-12)
    n = int(dur / 0.25)
    best, bi = None, 0
    for i in range(0, max(1, len(e) - n), max(1, int(step / 0.25))):
        w = e[i:i + n]
        sc = np.max(w) / np.median(w)
        if best is None or sc < best:
            best, bi = sc, i
    return bi * 0.25


def trim(x, thr_db=-40, pad=0.08):
    """Retire les silences du début et de la fin (seuil relatif à la crête)."""
    h = int(0.01 * SR)
    e = np.sqrt(np.convolve(x ** 2, np.ones(h) / h, "same"))
    on = np.where(e > e.max() * 10 ** (thr_db / 20))[0]
    if len(on) == 0:
        return x
    a = max(0, on[0] - int(pad * SR)); b = min(len(x), on[-1] + int(pad * SR))
    return x[a:b]


def render(name, s):
    x = load(s["bsb"]) if "bsb" in s else load_file(s["file"])
    if "calme" in s:
        t0 = calm_window(x, s["calme"])
        x = x[int(t0 * SR): int((t0 + s["calme"]) * SR)]
    else:
        x = x[int(s.get("t0", 0) * SR): int(s["t1"] * SR) if "t1" in s else None]
    if s.get("trim"):
        x = trim(x, s.get("trim_db", -40))
    x = filt(x - x.mean(), s.get("hp"), s.get("lp"))
    if s.get("speed", 1.0) != 1.0:
        x = resample(x, s["speed"])
    if s.get("loop"):
        x = make_loop(x, s.get("xf", 0.5))
    else:
        for key, sl in (("fi", slice(None)), ("fo", slice(None, None, -1))):
            if s.get(key):
                k = int(s[key] * SR)
                env = np.ones(len(x)); env[:k] = np.sin(np.linspace(0, np.pi / 2, k)) ** 2
                x = x * env[sl]
    return write_ogg(name, x, s.get("db", -18), s.get("q", 4)), len(x) / SR


# ---------------------------------------------------------------- moteur
# Moteur de l'Espace : Peugeot 106 essence 4 cylindres (BigSoundBank n° 872, « démarrage difficile » : le ralenti
# accéléré du moteur froid donne des paliers de régime stables). Fréquence d'allumage d'un 4 cylindres = tr/min / 30.
# Chaque palier devient une boucle sans couture à fréquence aplatie ; le jeu fond les deux boucles qui encadrent le
# régime voulu et les transpose (pitch_scale = f_voulue / f_boucle). Deux versions : « charge » (accélérateur
# enfoncé : plus présente, légèrement saturée) et « lache » (frein moteur : plus sourde et plus douce).
MOTEUR = [("ralenti", 32.0, 44.0, 40.28), ("bas", 23.0, 25.8, 83.56), ("moyen", 14.6, 18.7, 95.44),
          ("haut", 20.0, 21.5, 109.24)]


def f0_track(x, f, hop=0.05, win=0.4):
    """Fréquence d'allumage au fil du temps (peigne harmonique fin autour de f)."""
    w = int(win * SR); h = int(hop * SR); N = 1 << 17
    fr = np.fft.rfftfreq(N, 1 / SR)
    c = np.arange(f * 0.94, f * 1.06, 0.04)
    T, F = [], []
    for i in range(0, len(x) - w, h):
        sp = np.abs(np.fft.rfft(x[i:i + w] * np.hanning(w), N))
        v = sum(np.interp(c * k, fr, sp) for k in range(1, 9))
        T.append((i + w / 2) / SR); F.append(c[int(np.argmax(v))])
    return np.array(T), np.array(F)


def flatten_pitch(x, f):
    """Rééchantillonnage à vitesse variable : la fréquence d'allumage devient constante (égale à sa moyenne)."""
    T, F = f0_track(x, f)
    fm = F.mean()
    t = np.arange(len(x)) / SR
    rate = np.interp(t, T, F / fm)                      # > 1 : l'extrait est trop aigu à cet instant -> lire plus vite
    pos = np.cumsum(rate)
    pos = pos[pos < len(x) - 1]
    return np.interp(pos, np.arange(len(x)), x), fm


def soft_sat(x, drive):
    return np.tanh(x * drive) / np.tanh(drive)


def moteur():
    import json
    man = []
    src = load_any(872)
    for name, t0, t1, fguess in MOTEUR:
        x = src[int(t0 * SR): int(t1 * SR)]
        x = filt(x - x.mean(), 22, None)
        x, fm = flatten_pitch(x, fguess)
        x = make_loop(x, min(0.25, len(x) / SR * 0.15))
        rms = np.sqrt(np.mean(x ** 2))
        on = soft_sat(x / rms * 0.18, 1.6)
        on = on + 0.35 * filt(on, None, 400)               # un peu plus de corps dans le grave
        off = filt(x, None, 1100) * 0.55
        for kind, y in (("charge", on), ("lache", off)):
            write_ogg("moteur_%s_%s" % (name, kind), y, -15 if kind == "charge" else -21)
        man.append({"nom": name, "f0": round(float(fm), 3), "rpm": round(float(fm) * 30)})
        print("moteur %-8s f0 %.2f Hz  (%d tr/min)  %.2f s" % (name, fm, fm * 30, len(x) / SR))
    json.dump(man, open(OUT + "/moteur.json", "w"), indent=1)


def main(only=None):
    os.makedirs(OUT, exist_ok=True)
    if not only or "moteur" in only:
        moteur()
    for name, s in SONS.items():
        if only and name not in only:
            continue
        p, d = render(name, s)
        print("%-22s %5.1f s  %s" % (name, d, p))


if __name__ == "__main__":
    import sys
    main(sys.argv[1:] or None)
