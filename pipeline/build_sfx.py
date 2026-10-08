"""Sons de synthèse (aucun enregistrement repris) -> ../godot/assets/sfx/*.wav (mono 22 kHz, 16 bits)
 - charge.wav : bourdonnement d'énergie qui monte, en boucle (gardien qui charge son attaque)
 - vague.wav  : souffle de la vague d'énergie (grondement + sifflement descendant)
 - boum.wav   : explosion (choc grave + souffle bruité qui décroît)
 - pluie.wav  : pluie sur la carrosserie, en boucle (bruissement + gouttes)
 - soucoupe.wav : vrombissement de la soucoupe du gardien, en boucle (bourdon grave qui ondule + tintement aigu)
 - rayon.wav    : rayon tracteur, en boucle (accords scintillants qui montent, souffle)"""
import os, wave
import numpy as np

SR = 22050
OUT = "../godot/assets/sfx"
rng = np.random.default_rng(5)


def save(name, x):
    x = np.clip(x / max(np.abs(x).max(), 1e-6) * 0.9, -1, 1)
    with wave.open("%s/%s.wav" % (OUT, name), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x * 32767).astype("<i2").tobytes())


def lowpass(x, a):
    y = np.zeros_like(x); s = 0.0
    for i, v in enumerate(x):
        s += a * (v - s); y[i] = s
    return y


def main():
    os.makedirs(OUT, exist_ok=True)
    # charge : 4 s bouclables, fondamentale 90 Hz + harmoniques qui palpitent, sifflement aigu ondulant, crépitements
    T = 4.0; t = np.arange(int(SR * T)) / SR
    hum = sum(np.sin(2 * np.pi * 90 * k * t) / k for k in (1, 2, 3, 5)) * (0.75 + 0.25 * np.sin(2 * np.pi * 6 * t))
    whine = np.sin(2 * np.pi * (900 + 120 * np.sin(2 * np.pi * 0.5 * t)) * t) * 0.18
    crack = lowpass(rng.normal(0, 1, len(t)) * (rng.random(len(t)) < 0.004) * 8, 0.3)
    save("charge", hum * 0.6 + whine + crack * 0.4)
    # vague : 2,2 s, montée brève puis grondement soutenu et sifflement descendant
    T = 2.2; t = np.arange(int(SR * T)) / SR
    env = np.minimum(t / 0.08, 1) * np.exp(-np.maximum(t - 1.4, 0) * 4)
    rumble = lowpass(rng.normal(0, 1, len(t)), 0.05) * 6
    sweep = np.sin(2 * np.pi * np.cumsum(1400 * np.exp(-t * 0.9) + 200) / SR) * 0.35
    save("vague", (rumble + sweep + np.sin(2 * np.pi * 60 * t) * 0.5) * env)
    # boum : choc grave (55 Hz qui descend) + souffle bruité, 2,5 s
    T = 2.5; t = np.arange(int(SR * T)) / SR
    thump = np.sin(2 * np.pi * np.cumsum(70 * np.exp(-t * 2) + 30) / SR) * np.exp(-t * 3)
    blast = lowpass(rng.normal(0, 1, len(t)), 0.12) * np.exp(-t * 2.2) * 5
    crackle = lowpass(rng.normal(0, 1, len(t)) * (rng.random(len(t)) < 0.01) * 6, 0.4) * np.exp(-t * 1.2)
    save("boum", thump * 1.4 + blast + crackle)
    # pluie : 6 s bouclables (fondu enchaîné des bords) : bruissement filtré + gouttes qui claquent sur la tôle
    T = 6.0; n = int(SR * T); f = int(SR * 0.5)
    hiss = rng.normal(0, 1, n + f)
    hiss = hiss - lowpass(hiss, 0.02)                    # retire le grave : bruissement
    hiss = lowpass(hiss, 0.5) * 0.5
    ticks = np.zeros(n + f)
    for k in rng.integers(0, n + f - 400, 900):
        a = rng.uniform(0.2, 1.0)
        fr = rng.uniform(1800, 4200)
        tt = np.arange(300) / SR
        ticks[k:k + 300] += np.sin(2 * np.pi * fr * tt) * np.exp(-tt * 260) * a
    x = hiss + ticks * 0.6
    w = np.linspace(0, 1, f)
    x[:f] = x[:f] * w + x[n:n + f] * (1 - w)
    save("pluie", x[:n])
    pluie_orage()
    # bip de péage : deux notes courtes (ticket délivré / paiement accepté)
    t1 = np.arange(int(SR * 0.11)) / SR; t2 = np.arange(int(SR * 0.16)) / SR
    env = lambda tt: np.minimum(1, tt * 400) * np.minimum(1, (tt[-1] - tt) * 300)
    b = np.r_[np.sin(2 * np.pi * 1046 * t1) * env(t1), np.zeros(int(SR * 0.05)), np.sin(2 * np.pi * 1568 * t2) * env(t2)]
    save("bip", b * 0.5)
    soucoupe()
    print("sons :", os.listdir(OUT))


def soucoupe():
    # 4 s bouclables : les fréquences sont des multiples de 1/4 Hz, les modulations aussi (raccord sans clic)
    T = 4.0; t = np.arange(int(SR * T)) / SR
    wob = np.sin(2 * np.pi * 1.5 * t)
    hum = sum(np.sin(2 * np.pi * 55 * k * t + 0.6 * k * wob) / k for k in (1, 2, 3, 4, 6))
    ring = np.sin(2 * np.pi * 660 * t + 3 * np.sin(2 * np.pi * 0.5 * t)) * 0.12 * (0.6 + 0.4 * np.sin(2 * np.pi * 0.25 * t))
    save("soucoupe", hum * (0.8 + 0.2 * np.sin(2 * np.pi * 3 * t)) + ring)
    # rayon : arpèges scintillants (thérémine) qui montent en boucle, sur un souffle doux
    T = 4.0; n = int(SR * T); t = np.arange(n) / SR
    x = np.zeros(n)
    for k, f0 in enumerate((440, 554, 659, 880)):
        ph = 2 * np.pi * np.cumsum(f0 * (1 + 0.5 * ((t * 2 + k * 0.25) % 1))) / SR
        x += np.sin(ph) * (0.5 + 0.5 * np.sin(2 * np.pi * (2 * t + k * 0.25))) * 0.25
    vib = np.sin(2 * np.pi * 7 * t)
    x += np.sin(2 * np.pi * 220 * t + 2 * vib) * 0.3
    air = rng.normal(0, 1, n); air = lowpass(air - lowpass(air, 0.05), 0.4) * 0.25
    f = int(SR * 0.3); w = np.linspace(0, 1, f)
    x[:f] = x[:f] * w + x[-f:] * (1 - w)
    save("rayon", x + air)


def pluie_orage(src="sources/pluie_orage.mp3", T=90.0, F=6.0):
    """Pluie et orage enregistrés (« Rain and thunder », Premankur Adhikary, Pixabay) : 90 s bouclables (fondu
    enchaîné de 6 s), en Ogg Vorbis -> pluie.ogg (préférée par rain.gd au son de synthèse)."""
    import subprocess, tempfile
    if not os.path.exists(src):
        return
    tmp = tempfile.mktemp(suffix=".wav")
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", src, "-t", str(T + F), "-ac", "2", "-ar", "44100", tmp], check=True)
    import wave
    w = wave.open(tmp); a = np.frombuffer(w.readframes(w.getnframes()), "<i2").reshape(-1, 2).astype(np.float32); w.close()
    n = int(44100 * T); f = int(44100 * F)
    k = np.linspace(0, 1, f)[:, None]
    a[:f] = a[:f] * k + a[n:n + f] * (1 - k)
    a = a[:n]
    w = wave.open(tmp, "wb"); w.setnchannels(2); w.setsampwidth(2); w.setframerate(44100)
    w.writeframes(np.clip(a, -32768, 32767).astype("<i2").tobytes()); w.close()
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", tmp, "-c:a", "libvorbis", "-q:a", "4", OUT + "/pluie.ogg"], check=True)
    os.remove(tmp)


if __name__ == "__main__":
    main()
