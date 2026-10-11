"""Limite de la carte (zone jouable de routes_plan.json, simplifiée à 4 m) -> ../godot/world/zone.json.
Au-delà, le gardien volant tire (guardian.gd)."""
import json
from shapely.geometry import Polygon

z = Polygon(json.load(open("data/routes_plan.json"))["zone"]).simplify(4.0)
pts = [[round(x, 1), round(y, 1)] for x, y in z.exterior.coords[:-1]]
json.dump({"pts": pts}, open("../godot/world/zone.json", "w"))
print(len(pts), "points de limite")
