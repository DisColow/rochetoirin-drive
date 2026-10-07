"""Eau : surfaces hydrographiques (lacs, étangs, rivières larges) et tronçons (ruisseaux) de la BD TOPO.
Sorties : data/eau_surfaces.json, data/eau_troncons.json"""
from fetch_vegetation import wfs

if __name__ == "__main__":
    wfs("BDTOPO_V3:surface_hydrographique", "data/eau_surfaces.json")
    wfs("BDTOPO_V3:troncon_hydrographique", "data/eau_troncons.json")
