"""Géoréférencement commun : projection locale (mètres) centrée sur Rochetoirin.

Repère du jeu : x = Est, y = altitude, z = Sud (donc le Nord est vers -z).
"""
import math
import numpy as np

LAT0, LON0 = 45.5855, 5.4160          # centre du repère (près de la mairie)
M_PER_DEG_LAT = 111132.0
M_PER_DEG_LON = 111320.0 * math.cos(math.radians(LAT0))

# Zone jouable : grille fine (pas de 10 m)
INNER = dict(xmin=-2300.0, xmax=2300.0, zmin=-3100.0, zmax=3100.0, step=10.0)
# Horizon : grille grossière (pas de 60 m), 6 km autour
OUTER = dict(xmin=-8300.0, xmax=8300.0, zmin=-9100.0, zmax=9100.0, step=60.0)


def to_local(lon, lat):
    x = (np.asarray(lon) - LON0) * M_PER_DEG_LON
    z = -(np.asarray(lat) - LAT0) * M_PER_DEG_LAT
    return x, z


def to_lonlat(x, z):
    return LON0 + np.asarray(x) / M_PER_DEG_LON, LAT0 - np.asarray(z) / M_PER_DEG_LAT


def grid_shape(spec):
    nx = int(round((spec["xmax"] - spec["xmin"]) / spec["step"])) + 1
    nz = int(round((spec["zmax"] - spec["zmin"]) / spec["step"])) + 1
    return nx, nz


def grid_lonlat(spec):
    nx, nz = grid_shape(spec)
    xs = spec["xmin"] + np.arange(nx) * spec["step"]
    zs = spec["zmin"] + np.arange(nz) * spec["step"]
    X, Z = np.meshgrid(xs, zs)          # tableau [nz, nx]
    return to_lonlat(X, Z)

# Panorama : relief lointain (Chartreuse, Vercors, Belledonne, Bugey…), pas de 500 m sur ±75 km
PANO = dict(xmin=-75000.0, xmax=75000.0, zmin=-75000.0, zmax=75000.0, step=500.0)
