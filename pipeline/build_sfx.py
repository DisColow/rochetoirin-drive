"""Sons de synthèse -> ../godot/assets/sfx/*.wav (mono 22 kHz, 16 bits) ; les sons d'après enregistrements réels
(soucoupe, voiture, ambiances) sont faits par build_sons.py.
 - pluie.wav  : pluie sur la carrosserie, en boucle (bruissement + gouttes) ; pluie.ogg : d'après pluie_orage.mp3
 - bip.wav    : bip de péage et d'activités
 - klaxon.ogg : klaxon de voiture à deux tons (voitures de la circulation, #132)"""
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
    klaxon()
    print("sons :", os.listdir(OUT))


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


def klaxon():
    """Klaxon électrique à deux tons (≈ 410 et 510 Hz, comme les avertisseurs à disque des voitures européennes) :
    membrane qui vibre (onde riche en harmoniques, écrêtage doux), pavillon (résonance vers 2,4 kHz), attaque qui
    monte en hauteur sur 20 ms ; « tut-tuuut » (0,22 s, 0,1 s de silence, 0,5 s) -> klaxon.ogg."""
    import subprocess

    def coup(T):
        n = int(SR * T); t = np.arange(n) / SR
        x = np.zeros(n)
        for f0, a0 in ((410.0, 1.0), (512.0, 0.8)):
            f = f0 * (1.0 - 0.035 * np.exp(-t * 120))            # attaque un peu basse, se cale en 20 ms
            ph = 2 * np.pi * np.cumsum(f) / SR + rng.uniform(0, 6)
            for k in range(1, 12):
                fk = f0 * k
                if fk > 6000:
                    break
                res = 1.0 + 1.6 * np.exp(-((fk - 2400.0) / 700.0) ** 2)    # pavillon
                x += a0 * np.sin(k * ph) * res / k ** 0.75
        x = np.tanh(x * 0.9) + rng.normal(0, 0.015, n)
        env = np.minimum(1, t / 0.008) * np.minimum(1, (T - t) / 0.025)
        return x * env

    y = np.r_[coup(0.22), np.zeros(int(SR * 0.1)), coup(0.5)]
    save("_klaxon", y * 0.8)
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", OUT + "/_klaxon.wav", "-c:a", "libvorbis", "-q:a", "5",
                    OUT + "/klaxon.ogg"], check=True)
    os.remove(OUT + "/_klaxon.wav")


if __name__ == "__main__":
    main()
