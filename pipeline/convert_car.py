"""Espace IV (car.bin de l'ancien moteur, déjà simplifié et coloré) -> godot/assets/car/{body,wheel}.glb + meta.json.
Repère : x à droite, y en haut, avant vers -z ; origine au sol au milieu de l'empattement."""
import json, os, struct
import numpy as np
from glb import write_glb
SRC = "/home/user/rochetoirin-truck/app/src/main/assets/car.bin"
OUT = "../godot/assets/car"; os.makedirs(OUT, exist_ok=True)
NAMES = ["paint", "glass", "plastic", "chrome", "rubber", "lamp", "tail", "plate_front", "plate_rear", "interior"]
b = open(SRC, "rb").read(); assert b[:4] == b"CAR1"; o = 4
blocks = []
for _ in range(3):
    nv, ni = struct.unpack_from("<ii", b, o); o += 8
    V = np.frombuffer(b, "<f4", nv * 12, o).reshape(nv, 12); o += nv * 48
    I = np.frombuffer(b, "<u4", ni, o); o += ni * 4
    blocks.append((V, I))
n = struct.unpack_from("<i", b, o)[0]; meta = np.frombuffer(b, "<f4", n, o + 4)
def prims(V, I, force=None):
    out = []
    mat = V[:, 9].astype(int)
    T = I.reshape(-1, 3)
    tm = mat[T[:, 0]] if force is None else np.full(len(T), force)
    for m in sorted(set(tm.tolist())):
        TT = T[tm == m]
        used = np.unique(TT); remap = -np.ones(len(V), int); remap[used] = np.arange(len(used))
        VV = V[used]
        out.append((NAMES[m], VV[:, 0:3], VV[:, 3:6], VV[:, 10:12], remap[TT].ravel(), VV[:, 6:9]))
    return out
body = prims(*blocks[0]) + prims(*blocks[1], force=1)
write_glb(OUT + "/body.glb", body, "body")
write_glb(OUT + "/wheel.glb", prims(*blocks[2]), "wheel")
Vw = blocks[2][0]
json.dump(dict(steer=meta[:3].tolist(), eye=meta[3:6].tolist(), wheelbase=2.80, track=1.56, radius=0.33,
               wheel_center=[float(Vw[:, 0].mean()), float(Vw[:, 1].mean()), float(Vw[:, 2].mean())]), open(OUT + "/meta.json", "w"))
print([p[0] for p in body], len(blocks[0][0]), "sommets")
