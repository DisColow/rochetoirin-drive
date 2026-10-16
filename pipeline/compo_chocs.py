"""Chocs « jeu vidéo » (#84, 2e série) : couches superposées, compressées. Le jeu garde 4_B (bois) et 5_B (verre),
choisis par l'utilisateur le 16/10 -> data/sons/compo_4_B.wav, compo_5_B.wav (repris par build_sons.py). Sources :
Kenney Impact Sounds, OpenGameArt (packs CC0 cités dans ⚙ > Crédits), Mixkit, téléchargées dans le dossier S."""
import subprocess, sys, os, glob
S = "/tmp/claude-0/-home-user/2cff0bea-6915-5af5-9412-60b47b93c8bd/scratchpad"
OUT = S + "/sons_page2/sons"
os.makedirs(OUT, exist_ok=True)
def F(pat):
    r = sorted(glob.glob(S + "/**/" + pat, recursive=True)) + sorted(glob.glob("/home/user/rochetoirin-godot/pipeline/data/sons/" + pat))
    r = [x for x in r if "sons_page" not in x and "ogg_vorbis" not in x]
    if not r: sys.exit("introuvable " + pat)
    return r[0]
THUMP = "thump"   # coup sourd synthétique (sinus qui plonge de 90 à 40 Hz)
def mix(name, layers, dur=2.2, sub=0.0):
    ins, fl = [], []
    for i, (src, t0, db, extra) in enumerate(layers):
        if src == THUMP:
            ins += ["-f", "lavfi", "-t", "0.6", "-i", "aevalsrc='sin(2*PI*(90*t-42*t*t))*exp(-t*7)':s=44100"]
        else:
            ins += ["-i", src]
        f = "[%d:a]aformat=sample_rates=44100:channel_layouts=mono" % i
        if extra: f += "," + extra
        f += ",volume=%.1fdB,adelay=%d" % (db, int(t0 * 1000))
        fl.append(f + "[l%d]" % i)
    n = len(layers)
    master = "".join("[l%d]" % i for i in range(n)) + "amix=inputs=%d:normalize=0:duration=longest," % n + \
        "equalizer=f=70:t=q:w=1:g=%.1f," % (4 + sub) + "acompressor=threshold=-20dB:ratio=6:attack=2:release=150:makeup=4," + \
        "asoftclip=type=tanh," + "atrim=0:%.2f,afade=t=out:st=%.2f:d=0.35," % (dur, dur - 0.35) + "loudnorm=I=-11:TP=-1"
    cmd = ["ffmpeg", "-v", "error", "-y"] + ins + ["-filter_complex", ";".join(fl) + ";" + master, "-ac", "1", "/home/user/rochetoirin-godot/pipeline/data/sons/" + name + ".wav"]
    subprocess.run(cmd, check=True)
K = lambda n: F("Audio/%s.ogg" % n)
C = {
 # 1 gros choc
 "1_A": [(THUMP, 0, 0, ""), (K("impactPunch_heavy_000"), 0, -2, ""), (F("qubodup-crash.ogg"), 0.0, 0, ""), (F("bfh1_glass_falling_02.ogg"), 0.12, -8, "")],
 "1_B": [(F("qubodup-BangShort.ogg"), 0, -2, "lowpass=f=500"), (F("mixkit_2980.wav"), 0.0, 0, ""), (F("bfh1_metal_falling_01.ogg"), 0.15, -6, "")],
 "1_C": [(THUMP, 0, 0, ""), (F("impactcrunch04.mp3.flac"), -0.0, 0, "atrim=start=0.2,asetpts=PTS-STARTPTS"), (K("impactMetal_heavy_002"), 0, -2, ""), (F("bfh1_glass_breaking_02.ogg"), 0.05, -7, "")],
 "1_D": [(F("Chunky%20Explosion.mp3"), 0, -3, "lowpass=f=350,atrim=0:1.5"), (F("qubodup-crash.ogg"), 0, 0, "asetrate=44100*0.85,aresample=44100"), (K("impactPunch_heavy_002"), 0, -1, "")],
 # 2 tôle (choc moyen)
 "2_A": [(THUMP, 0, -5, ""), (F("metal_slam_01.ogg"), 0, 0, ""), (K("impactPunch_medium_000"), 0, -4, "")],
 "2_B": [(F("impactcrunch03.mp3.flac"), 0, 0, "atrim=start=0.1,asetpts=PTS-STARTPTS"), (K("impactMetal_medium_001"), 0, -1, ""), (K("impactPunch_medium_002"), 0, -4, "")],
 "2_C": [(F("qubodup-crash.ogg"), 0, 0, "asetrate=44100*1.2,aresample=44100,atrim=0:0.9"), (K("impactPunch_medium_001"), 0, -3, "")],
 "2_D": [(THUMP, 0, -4, ""), (K("impactPlate_heavy_001"), 0, 0, ""), (K("impactMetal_medium_003"), 0.01, -2, "")],
 # 3 poteau, glissière
 "3_A": [(THUMP, 0, -3, ""), (K("impactMetal_heavy_000"), 0, 0, ""), (K("impactBell_heavy_001"), 0, -10, "lowpass=f=2500")],
 "3_B": [(F("mixkit_2980.wav"), 0, 0, "atrim=0:1.0"), (K("impactPunch_heavy_001"), 0, -3, "")],
 "3_C": [(THUMP, 0, -3, ""), (F("metal_hit_01.ogg"), 0, 0, ""), (F("bfh1_metal_hit_04.ogg"), 0.0, -3, "")],
 # 4 bois
 "4_A": [(THUMP, 0, -3, ""), (F("bfh1_wood_breaking_01.ogg"), 0, 0, ""), (K("impactWood_heavy_001"), 0, -2, "")],
 "4_B": [(F("wood_breaking_01.ogg"), 0, 0, ""), (F("impactcrunch01.mp3.flac"), 0, -2, "atrim=start=0.15,asetpts=PTS-STARTPTS"), (K("impactPunch_heavy_003"), 0, -5, "")],
 "4_C": [(K("impactPlank_medium_002"), 0, 0, ""), (F("bfh1_wood_breaking_03.ogg"), 0.02, -1, ""), (F("bfh1_wood_falling_01.ogg"), 0.25, -7, "")],
 # 5 verre
 "5_A": [(THUMP, 0, -6, ""), (K("impactGlass_heavy_000"), 0, 0, ""), (F("bfh1_glass_breaking_02.ogg"), 0.03, -2, "")],
 "5_B": [(F("mixkit_759.wav"), 0, 0, ""), (F("bfh1_glass_falling_03.ogg"), 0.3, -6, "")],
 "5_C": [(K("impactGlass_heavy_003"), 0, 0, ""), (F("glass_breaking.wav"), 0.02, -3, ""), (K("impactPunch_medium_003"), 0, -6, "")],
}
for k, l in C.items():
    if k in ('4_B', '5_B'): mix('compo_' + k, l)
    print(k)
