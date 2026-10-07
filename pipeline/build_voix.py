"""Voix du gardien (synthèse vocale Piper, voix française « tom », libre) -> ../godot/assets/sfx/kame.wav, ha.wav.
« Ka… mé… ha… mé… » pendant la charge, « HAAA ! » au tir ; voix un peu plus grave, compressée, avec un écho
(grand espace ouvert). Prérequis : piper-tts installé et le modèle fr_FR-tom-medium.onnx (variable PIPER_VOIX = dossier
du modèle, binaire PIPER = chemin de piper)."""
import os, subprocess, tempfile, wave
import numpy as np

OUT = "../godot/assets/sfx"
SR = 22050
VOIX = os.environ.get("PIPER_VOIX", ".")
PIPER = os.environ.get("PIPER", "piper")


def say(text, length):
    f = tempfile.mktemp(suffix=".wav")
    subprocess.run([PIPER, "--model", os.path.join(VOIX, "fr_FR-tom-medium.onnx"), "--length_scale", str(length),
                    "--output_file", f], input=text.encode(), check=True, capture_output=True)
    w = wave.open(f)
    x = np.frombuffer(w.readframes(w.getnframes()), "<i2").astype(np.float32) / 32768.0
    sr = w.getframerate()
    os.remove(f)
    return x, sr


def resample(x, sr_in, sr_out, pitch=1.0):
    """Change la cadence (et donc la hauteur : pitch < 1 = plus grave et plus lent)."""
    n = int(len(x) * sr_out / sr_in / pitch)
    t = np.linspace(0, len(x) - 1, n)
    return np.interp(t, np.arange(len(x)), x)


def fx(x, drive=1.0):
    x = np.tanh(x * 2.2 * drive) / np.tanh(2.2 * drive)               # compression et grain
    out = np.r_[x, np.zeros(int(SR * 1.2))]
    for d, g in ((0.11, 0.35), (0.23, 0.22), (0.41, 0.14), (0.67, 0.08)):  # échos
        k = int(SR * d)
        out[k:k + len(x)] += x * g
    return out / max(np.abs(out).max(), 1e-6) * 0.92


def save(name, x):
    with wave.open("%s/%s.wav" % (OUT, name), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype("<i2").tobytes())


def main():
    os.makedirs(OUT, exist_ok=True)
    x, sr = say("Kaa... méé... haa... méé...", 1.7)
    save("kame", fx(resample(x, sr, SR, 0.9)))
    x, sr = say("HAAAAAA !", 1.6)
    save("ha", fx(resample(x, sr, SR, 0.88), 1.8))
    print("voix : kame.wav, ha.wav")


if __name__ == "__main__":
    main()
