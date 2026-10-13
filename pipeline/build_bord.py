"""Bords de la carte façon Motocross Madness (v6.22, demande de l'utilisateur) : un talus tout autour de la zone
jouable (world/zone.json, build_zone.py), qui se raidit à mesure qu'on s'éloigne (on peut le grimper, avec du mal) ;
au-delà de 26 m hors de la carte, bord.gd renvoie la voiture vers l'intérieur comme un ressort (la soucoupe du
gardien est désactivée).
Surface continue (pas de plis aux angles de la limite) : grille régulière de PAS m dont la hauteur ne dépend que de
la distance d au bord de la zone : relief terrassé (CarvedDEM) + HAUT × (d / PROF)^2,2 jusqu'à PROF m, puis un dos qui
redescend sous le relief (le talus ne laisse jamais voir le vide). Côté carte (d < 0) : juste sous le relief.
Sorties : ../godot/world/bord/bd_<tx>_<tz>.glb (tuiles de 256 m, matériau « bord ») ; rien n'est versionné.
Lancer depuis pipeline/ après build_zone.py : python3 build_bord.py"""
import json, math, os, shutil
import numpy as np
import shapely
from shapely.geometry import Polygon, box
from glb import write_glb
from build_buildings import CarvedDEM

OUT = "../godot/world/bord"
TILE = 256.0
PROF, HAUT, DOS = 64.0, 32.0, 84.0
PAS = 5.0


def hauteur(d):
    h = np.where(d <= 0.0, -0.6, HAUT * (np.clip(d, 0, PROF) / PROF) ** 2.2)
    return np.where(d > PROF, HAUT - (d - PROF) * 3.0, h)


def main():
    shutil.rmtree(OUT, ignore_errors=True); os.makedirs(OUT)
    dem = CarvedDEM()
    z = Polygon(json.load(open("../godot/world/zone.json"))["pts"])
    bande = z.buffer(DOS).difference(z.buffer(-8.0))
    bd = z.exterior
    x0, z0, x1, z1 = bande.bounds
    n = 0
    for tx in range(int(math.floor(x0 / TILE)), int(math.floor(x1 / TILE)) + 1):
        for tz in range(int(math.floor(z0 / TILE)), int(math.floor(z1 / TILE)) + 1):
            tb = box(tx * TILE, tz * TILE, (tx + 1) * TILE, (tz + 1) * TILE)
            if not tb.intersects(bande):
                continue
            xs = np.arange(tx * TILE, (tx + 1) * TILE + 0.01, PAS)
            zs = np.arange(tz * TILE, (tz + 1) * TILE + 0.01, PAS)
            X, Zg = np.meshgrid(xs, zs)
            pts = shapely.points(X.ravel(), Zg.ravel())
            d = shapely.distance(pts, bd)
            dedans = shapely.contains(z, pts)
            d = np.where(dedans, -d, d).reshape(X.shape)
            keep = (d > -8.0) & (d < DOS)
            # cellules dont un coin est dans la bande
            cell = keep[:-1, :-1] | keep[1:, :-1] | keep[:-1, 1:] | keep[1:, 1:]
            if not cell.any():
                continue
            g = dem.h(X.ravel(), Zg.ravel()).reshape(X.shape)
            ok = np.isfinite(g)
            if not ok.all():                       # au-delà du relief connu : hauteur du voisin connu le plus proche
                from scipy.ndimage import distance_transform_edt
                if not ok.any():
                    continue
                _, (iy, ix) = distance_transform_edt(~ok, return_indices=True)
                g = g[iy, ix]
            Y = g + hauteur(d)
            ny, nx = X.shape
            idx = np.arange(ny * nx).reshape(ny, nx)
            a = idx[:-1, :-1][cell]; b = idx[:-1, 1:][cell]; c = idx[1:, :-1][cell]; e = idx[1:, 1:][cell]
            tri = np.c_[a, c, b, b, c, e].reshape(-1, 3)
            used = np.unique(tri)
            remap = -np.ones(ny * nx, np.int64); remap[used] = np.arange(len(used))
            V = np.c_[X.ravel(), Y.ravel(), Zg.ravel()][used].astype(np.float32)
            I = remap[tri].astype(np.uint32)
            Nv = np.zeros_like(V)
            fn = np.cross(V[I[:, 1]] - V[I[:, 0]], V[I[:, 2]] - V[I[:, 0]])
            for k in range(3):
                np.add.at(Nv, I[:, k], fn)
            Nv /= np.linalg.norm(Nv, axis=1)[:, None] + 1e-9
            if np.mean(Nv[:, 1]) < 0:
                Nv = -Nv; I = I[:, ::-1].copy()
            UV = np.c_[np.zeros(len(used)), np.clip(d.ravel()[used] / PROF, -0.2, 1.4)].astype(np.float32)
            write_glb(os.path.join(OUT, "bd_%d_%d.glb" % (tx, tz)), [("bord", V, Nv.astype(np.float32), UV, I.ravel())])
            n += 1
    print(n, "tuiles de talus")


if __name__ == "__main__":
    main()
