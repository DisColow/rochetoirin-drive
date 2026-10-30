"""Sons de moteur propres à chaque voiture du garage (#153), d'après les enregistrements de fetch_moteurs.py.
Lancer depuis pipeline/ :
  python3 build_moteurs.py <clé…>          boucles -> ../godot/assets/sfx/moteurs/<clé>/ + moteur.json
  python3 build_moteurs.py --ecoute <dossier> [clé…]
                                           simulation d'écoute (comme dans le jeu) de chaque clé et du son actuel
Méthode :
- fréquence d'allumage suivie dans tout l'enregistrement (cyl / 2 allumages par tour) : saillance harmonique (somme
  des harmoniques moins l'énergie entre elles, ce qui écarte l'octave du dessous et celle du dessus), puis chemin le
  plus continu (programmation dynamique) : un suivi image par image saute d'octave dès qu'un bruit passe ;
- PALIERS paliers de régime répartis (en échelle logarithmique) entre le ralenti et le haut du régime relevés ; pour
  chacun, l'extrait de 0,5 à 1,2 s le plus fort dont le régime reste à ± 12 % du palier ;
- chaque extrait est rééchantillonné à fréquence constante (suivi ci-dessus), bouclé sans couture, puis décliné en
  « charge » (accélérateur enfoncé) et « lache » (frein moteur), comme le moteur d'origine (build_sons.moteur)."""
import json, os, subprocess, sys
import numpy as np
from scipy.io import wavfile
from build_sons import SR, filt, make_loop, soft_sat

SRC = "data/sons/moteurs"
OUT = "../godot/assets/sfx/moteurs"
PALIERS = 4
# régime réel approximatif de chaque moteur enregistré (ralenti, rupteur, tr/min) : borne le suivi et cale son octave
REGIME = {"2cv6": (850, 5800), "r5t2": (900, 6500), "twingo": (750, 6000), "106r": (900, 7500), "cliors": (800, 6800),
          "meganers": (800, 6800), "rcz": (800, 6800), "toledo": (800, 6000), "laguna": (700, 6500),
          "omega": (700, 6200), "gt3_992": (900, 9000), "gt3rs_991": (900, 9000), "mustang": (700, 7000),
          "bronco": (650, 4500), "man_sg220": (600, 2300), "ess1l": (800, 6000),
          "dsl29": (750, 4200)}
HOP = 0.03
NB = 260                                   # cases de fréquence (échelle log)


def lire(cle):
    sr, x = wavfile.read("%s/%s.wav" % (SRC, cle))
    x = x.astype(np.float64) / 32768.0
    assert sr == SR
    return x - x.mean()


def suivre(x, cyl, rpm_min=450.0, rpm_max=9500.0, win=0.3):
    """Fréquence d'allumage (Hz) toutes les HOP s et confiance (0-1), par programmation dynamique."""
    fmin, fmax = rpm_min * cyl / 120.0, rpm_max * cyl / 120.0
    c = np.exp(np.linspace(np.log(fmin), np.log(fmax), NB))
    w = int(win * SR); h = int(HOP * SR); N = 1 << 17
    fr = np.fft.rfftfreq(N, 1.0 / SR)
    han = np.hanning(w)
    S, E = [], []
    for i in range(0, len(x) - w, h):
        seg = x[i:i + w]
        sp = np.abs(np.fft.rfft(seg * han, N))
        sp = sp / (np.median(sp[(fr > fmin) & (fr < fmax * 8)]) + 1e-12)
        sal = np.zeros(NB)
        for k in range(1, 9):
            sal += np.interp(c * k, fr, sp) / k ** 0.5
            sal -= 0.6 * np.interp(c * (k - 0.5), fr, sp) / k ** 0.5
        S.append(sal); E.append(np.sqrt(np.mean(seg ** 2)))
    S = np.array(S); E = np.array(E)
    S = S / (S.max(axis=1, keepdims=True) + 1e-12)
    # chemin : saillance cumulée moins une pénalité par case sautée (au plus SAUT cases entre deux images)
    SAUT, PEN = 5, 0.06
    T = len(S)
    acc = S[0].copy(); par = np.zeros((T, NB), dtype=np.int32)
    for t in range(1, T):
        best = np.full(NB, -1e9); arg = np.zeros(NB, dtype=np.int32)
        for d in range(-SAUT, SAUT + 1):
            sh = np.roll(acc, d) - PEN * abs(d)
            if d > 0:
                sh[:d] = -1e9
            elif d < 0:
                sh[d:] = -1e9
            m = sh > best
            best[m] = sh[m]; arg[m] = (np.arange(NB) - d)[m]
        acc = best + S[t]; par[t] = arg
    k = np.zeros(T, dtype=np.int32); k[-1] = int(np.argmax(acc))
    for t in range(T - 1, 0, -1):
        k[t - 1] = par[t, k[t]]
    f = c[k]
    conf = S[np.arange(T), k]
    t0 = (np.arange(T) * h + w / 2) / SR
    return t0, f, conf, E


def affiner(x, t0, f, a, b, hop=0.01, win=0.12):
    """Suivi fin sur [a, b] : à ±6 % du suivi d'ensemble, peigne de 12 harmoniques, toutes les 10 ms (le suivi
    d'ensemble, lissé sur 0,3 s, ne suit pas un coup d'accélérateur)."""
    w = int(win * SR); N = 1 << 16
    fr = np.fft.rfftfreq(N, 1.0 / SR); han = np.hanning(w)
    T, F = [], []
    for tc in np.arange(a, b, hop):
        i = int(tc * SR) - w // 2
        if i < 0 or i + w > len(x):
            continue
        sp = np.abs(np.fft.rfft(x[i:i + w] * han, N))
        fc = float(np.interp(tc, t0, f))
        c = fc * np.linspace(0.94, 1.06, 241)
        v = sum(np.interp(c * k, fr, sp) for k in range(1, 13))
        T.append(tc); F.append(c[int(np.argmax(v))])
    F = np.array(F)
    if len(F) > 5:                                   # médiane glissante : écarte les sauts isolés
        F = np.array([np.median(F[max(0, i - 2):i + 3]) for i in range(len(F))])
    return np.array(T), F


def aplatir(x, t0, f, a, b):
    """Extrait [a, b] s rééchantillonné à fréquence d'allumage constante (moyenne de l'extrait), d'après le suivi fin."""
    t0, f = affiner(x, t0, f, a - 0.05, b + 0.05)
    i0, i1 = int(a * SR), int(b * SR)
    t = np.arange(i0, i1) / SR
    fi = np.interp(t, t0, f)
    fm = float(np.exp(np.mean(np.log(fi))))
    pos = i0 + np.cumsum(fm / fi)                    # trop aigu à cet instant (fi > fm) : lire plus lentement
    pos = pos[pos < i1 - 1]
    return np.interp(pos, np.arange(len(x)), x), fm


def paliers(x, cyl, regime, nb=PALIERS):
    ral, rup = regime
    t0, f, conf, E = suivre(x, cyl, ral * 0.6, rup * 1.15)
    ok = (conf > 0.55) & (E > np.percentile(E, 30))
    # octave : le suivi peut tenir une harmonique (rapports justes, régime faux) -> bas du régime relevé calé sur le
    # ralenti, à l'octave près
    bas = np.percentile(f[ok] * 120.0 / cyl, 4)
    oct_ = 2.0 ** round(np.log2(ral / bas)) if abs(np.log2(ral / bas)) > 0.6 else 1.0
    f = f * oct_
    paliers.oct_ = oct_
    rpm = f * 120.0 / cyl
    lo, hi = np.percentile(rpm[ok], 4), np.percentile(rpm[ok], 96)
    print("  régime relevé %.0f-%.0f tr/min (octave × %g)" % (lo, hi, oct_))
    cibles = np.exp(np.linspace(np.log(lo * 1.03), np.log(hi * 0.95), nb))
    choix = []
    for r in cibles:
        best = None
        for tol, L in [(tol, L) for tol in (1.12, 1.2) for L in (int(1.2 / HOP), int(0.9 / HOP), int(0.6 / HOP))]:
            dans = ok & (np.abs(np.log(rpm / r)) < np.log(tol))
            for s in range(0, len(rpm) - L):
                if dans[s:s + L].all():
                    # fort, net et stable (régime le moins variable)
                    sc = E[s:s + L].mean() * conf[s:s + L].mean() / (0.02 + np.std(np.log(rpm[s:s + L])))
                    if best is None or sc > best[0]:
                        best = (sc, s, L)
            if best:
                break
        if best:
            _, s, L = best
            seg = (t0[s] - HOP / 2, t0[s + L - 1] + HOP / 2)
            r_seg = float(np.exp(np.mean(np.log(rpm[s:s + L]))))
            if choix and (seg in [a for a, _ in choix] or abs(np.log(r_seg / choix[-1][1])) < np.log(1.08)):
                continue                              # même extrait ou palier trop proche du précédent
            choix.append((seg, r_seg))
    return t0, f, [a for a, _ in choix]


def voir(cle, png):
    """Image de contrôle : spectrogramme (0-8 fois le haut du régime), fréquence suivie (et ses harmoniques 2 et 3),
    extraits retenus pour les paliers."""
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from scipy.signal import spectrogram
    cyl = __import__("fetch_moteurs").CANDIDATS[cle][1]
    x = filt(lire(cle), 18, None)
    t0, f, choix = paliers(x, cyl, REGIME[cle])
    oct_ = getattr(paliers, "oct_", 1.0)
    fmax = min(float(np.percentile(f / oct_, 98)) * 3.5, 1500.0)
    fr, t, S = spectrogram(x, SR, nperseg=int(0.3 * SR), noverlap=int(0.27 * SR), nfft=1 << 16)
    m = fr < fmax
    plt.figure(figsize=(16, 6))
    plt.pcolormesh(t, fr[m], 10 * np.log10(S[m] + 1e-14), shading="auto", cmap="magma",
                   vmin=np.percentile(10 * np.log10(S[m] + 1e-14), 40), vmax=np.percentile(10 * np.log10(S[m] + 1e-14), 99.7))
    for k, a in ((1, 1.0), (2, 0.5), (3, 0.35)):
        plt.plot(t0, f / oct_ * k, color="cyan", lw=0.8, alpha=a)
    for a, b in choix:
        plt.axvspan(a, b, color="lime", alpha=0.25)
    plt.title(cle); plt.ylim(0, fmax)
    plt.savefig(png, dpi=60, bbox_inches="tight")


def construire(cle, cyl, desc=""):
    x = filt(lire(cle), 18, None)
    t0, f, choix = paliers(x, cyl, REGIME[cle])
    d = "%s/%s" % (OUT, cle)
    os.makedirs(d, exist_ok=True)
    man = {"cylindres": cyl, "desc": desc, "paliers": []}
    from build_sons import write_ogg
    oct_ = paliers.oct_
    for n, (a, b) in enumerate(choix):
        y, fm = aplatir(x, t0, f / oct_, a, b)       # suivi fin sur la raie réellement suivie (avant calage d'octave)
        fm *= oct_
        y = make_loop(y, min(0.2, len(y) / SR * 0.15))
        rms = np.sqrt(np.mean(y ** 2)) + 1e-9
        on = soft_sat(y / rms * 0.18, 1.6)
        on = on + 0.35 * filt(on, None, 400)
        off = filt(y / rms * 0.18, None, 1100) * 0.55
        for kind, z in (("charge", on), ("lache", off)):
            write_ogg("moteurs/%s/p%d_%s" % (cle, n, kind), z, -15 if kind == "charge" else -21)
        man["paliers"].append({"nom": "p%d" % n, "f0": round(fm, 3), "rpm": round(fm * 120 / cyl)})
        print("%-10s palier %d : %5.0f tr/min (%.2f Hz), %.2f s pris à %.1f-%.1f s" % (cle, n, fm * 120 / cyl, fm, len(y) / SR, a, b))
    # plage de régime du jeu calée sur les paliers : transposition comme le moteur d'origine (× 0,65 au ralenti, × 1,9 au rupteur) ; seuls
    # les rapports de fréquence comptent, une erreur d'octave du calage est donc sans effet à l'oreille
    man["ralenti"] = round(man["paliers"][0]["rpm"] * 0.65)
    man["rupteur"] = round(man["paliers"][-1]["rpm"] * 1.9)
    json.dump(man, open(d + "/moteur.json", "w"), indent=1, ensure_ascii=False)
    return man


# ---------------------------------------------------------------- écoute (simulation du jeu, audio.gd)
GEARS = [4.696, 2.985, 2.146, 1.769, 1.52, 1.275, 1.0, 0.854, 0.689, 0.636]
FINAL, WHEEL_R, IDLE, REDLINE = 3.73, 0.415, 750.0, 6500.0


def scenario(duree=16.0, dt=1 / 60):
    """Ralenti 2 s, pleins gaz jusqu'à 100 km/h (accélération selon le rapport), pied levé, freinage : régime simulé
    (boîte auto d'audio.gd) et charge, à chaque pas."""
    v, rpm, gear, shift, load = 0.0, IDLE, 0, 0.0, 0.0
    out = []
    t = 0.0
    phase = "ralenti"
    while t < duree:
        if phase == "ralenti" and t > 2.0:
            phase = "gaz"
        if phase == "gaz" and v * 3.6 >= 100:
            phase = "leve"; t_leve = t
        if phase == "leve" and t - t_leve > 3.0:
            phase = "frein"
        thr = 1.0 if phase == "gaz" else 0.0
        a = {"gaz": 4.2 if v < 15 else (3.0 if v < 22 else 2.2), "leve": -0.6, "frein": -5.0}.get(phase, 0.0)
        if shift > 0 and phase == "gaz":
            a *= 0.3
        v = max(0.0, v + a * dt)
        wrpm = v / (2 * np.pi * WHEEL_R) * 60 * FINAL
        up = 2000 + 4000 * thr; down = 1100 + 1500 * thr
        r = wrpm * GEARS[gear]
        if shift <= 0 and gear < len(GEARS) - 1 and r > up:
            gear += 1; shift = 0.28
        elif shift <= 0 and gear > 0 and r < down:
            gear -= 1; shift = 0.18
        r = wrpm * GEARS[gear]
        target = max(IDLE, r)
        if v < 5:
            target = max(target, IDLE + 1900 * thr)
        target = min(target, REDLINE)
        shift -= dt
        step = (9000 if target > rpm else 5000) * dt
        rpm = min(target, rpm + step) if target > rpm else max(target, rpm - step)
        pedal = thr
        k = dt * (6 if pedal > load else 3)
        load = min(0.0 if shift > 0 else pedal, load + k) if (0.0 if shift > 0 else pedal) > load else max(0.0 if shift > 0 else pedal, load - k)
        out.append((rpm, load))
        t += dt
    return np.array(out), dt


def ogg(path):
    p = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", path, "-f", "f32le", "-ac", "1", "-ar", str(SR), "-"],
                       capture_output=True, check=True)
    return np.frombuffer(p.stdout, dtype=np.float32).astype(np.float64)


def rendre(boucles, freq, sim, dt):
    """boucles : [(f0, charge, lache)] ; freq(rpm) -> fréquence d'allumage voulue. Fondu des deux boucles qui
    encadrent la fréquence (puissance constante en log), transposition par lecture à vitesse variable."""
    boucles = sorted(boucles, key=lambda b: b[0])
    n = len(sim)
    spf = int(round(dt * SR))
    tot = np.zeros(n * spf)
    ph = [[0.0, 0.0] for _ in boucles]
    for s, (rpm, load) in enumerate(sim):
        f = freq(rpm)
        g = np.zeros(len(boucles))
        if f <= boucles[0][0]:
            g[0] = 1
        elif f >= boucles[-1][0]:
            g[-1] = 1
        else:
            for i in range(len(boucles) - 1):
                if boucles[i][0] <= f < boucles[i + 1][0]:
                    w = np.log(f / boucles[i][0]) / np.log(boucles[i + 1][0] / boucles[i][0])
                    g[i] = np.cos(w * np.pi / 2); g[i + 1] = np.sin(w * np.pi / 2)
        master = 0.55 + 0.45 * np.clip((rpm - IDLE) / (REDLINE - IDLE), 0, 1)
        seg = np.zeros(spf)
        for i, (f0, on, off) in enumerate(boucles):
            if g[i] <= 0:
                continue
            ps = np.clip(f / f0, 0.35, 2.6)
            for j, (buf, vol) in enumerate(((on, g[i] * master * (0.3 + 0.7 * load)), (off, g[i] * master * (1 - load) * 0.9))):
                idx = ph[i][j] + ps * np.arange(spf)
                seg += vol * np.interp(idx % len(buf), np.arange(len(buf)), buf)
                ph[i][j] = (ph[i][j] + ps * spf) % len(buf)
        tot[s * spf:(s + 1) * spf] = seg
    return tot / (np.abs(tot).max() + 1e-9) * 0.8


def plage(man):
    """Régime simulé du jeu (IDLE-REDLINE) -> régime réel du moteur enregistré (ralenti-rupteur)."""
    lo, hi = float(man["ralenti"]), float(man["rupteur"])
    return lambda rpm: lo + (rpm - IDLE) / (REDLINE - IDLE) * (hi - lo)


def ecoute(dossier, cles, actuel=True):
    os.makedirs(dossier, exist_ok=True)
    sim, dt = scenario()
    for cle in cles:
        man = json.load(open("%s/%s/moteur.json" % (OUT, cle)))
        b = [(p["f0"], ogg("%s/%s/%s_charge.ogg" % (OUT, cle, p["nom"])), ogg("%s/%s/%s_lache.ogg" % (OUT, cle, p["nom"])))
             for p in man["paliers"]]
        cyl = man["cylindres"]; vers = plage(man)
        y = rendre(b, lambda r: vers(r) * cyl / 120.0, sim, dt)
        ecrire(dossier, cle, y)
    if actuel:
        man = json.load(open("../godot/assets/sfx/moteur.json"))
        b = [(m["f0"], ogg("../godot/assets/sfx/moteur_%s_charge.ogg" % m["nom"]), ogg("../godot/assets/sfx/moteur_%s_lache.ogg" % m["nom"])) for m in man]
        for nom, k in (("actuel_1.0", 1.0), ("actuel_1.25", 1.25), ("actuel_1.55", 1.55)):
            ecrire(dossier, nom, rendre(b, lambda r, k=k: r / 30.0 * k, sim, dt))


def ecrire(dossier, nom, y):
    pcm = (np.clip(y, -1, 1) * 32767).astype(np.int16)
    wavfile.write("%s/%s.wav" % (dossier, nom), SR, pcm)
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", "%s/%s.wav" % (dossier, nom), "-b:a", "128k",
                    "%s/%s.mp3" % (dossier, nom)], check=True)
    os.remove("%s/%s.wav" % (dossier, nom))
    print("écoute", nom)


def main(args):
    from fetch_moteurs import CANDIDATS
    if args and args[0] == "--voir":
        for cle in args[2:]:
            voir(cle, "%s/voir_%s.png" % (args[1], cle))
        return
    if args and args[0] == "--ecoute":
        ecoute(args[1], args[2:] or [c for c in CANDIDATS if os.path.exists("%s/%s/moteur.json" % (OUT, c))])
        return
    for cle in args or [c for c in CANDIDATS if os.path.exists("%s/%s.wav" % (SRC, c))]:
        construire(cle, CANDIDATS[cle][1], CANDIDATS[cle][2])


if __name__ == "__main__":
    main(sys.argv[1:])
