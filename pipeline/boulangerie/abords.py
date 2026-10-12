"""Abords de la boulangerie (v6.17) : d'après les photos Street View, rien entre la façade nord et la rue (une bande
d'herbe) ; build_fences.py y posait une haie de façade et un bout de grillage (limite de parcelle côté rue). Retire
de la tuile de clôtures les lignes dont tous les points sont dans cette bande. À relancer après build_fences.py.
Lancer depuis pipeline/ : python3 boulangerie/abords.py"""
import math, os
import numpy as np
from shapely.geometry import Point, Polygon

NE = (49.26, 409.80)
TH = math.atan2(0.450, 0.893)
W_ = (-math.cos(TH), -math.sin(TH)); N_ = (-math.sin(TH), math.cos(TH))
loc = lambda a, b: (NE[0] + a * W_[0] + b * N_[0], NE[1] + a * W_[1] + b * N_[1])
# bande entre la façade nord (et celle du restaurant, même parcelle côté rue) et le bord de la chaussée
BANDE = Polygon([loc(-1.0, 3.0), loc(16.0, 3.0), loc(16.0, -4.5), loc(-1.0, -4.5)])   # (jusque dans le bâtiment : la limite de parcelle le traversait)
F = "../godot/world/fences/f_0_1.bin"

a = np.fromfile(F, np.float32)
out, o, retire = [], 0, 0
while o + 16 <= len(a):
    n = int(a[o + 1]); rec = a[o:o + 16 + n * 3]
    P = rec[16:].reshape(n, 3)
    if all(BANDE.contains(Point(float(p[0]), float(p[2]))) for p in P):
        retire += 1
    else:
        out.append(rec)
    o += 16 + n * 3
np.concatenate(out).astype(np.float32).tofile(F)
print("abords de la boulangerie : %d lignes de clôture/haie retirées" % retire)
