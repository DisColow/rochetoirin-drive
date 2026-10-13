"""Fiches des bâtiments non résidentiels de Vasselin (une photo Street View chacun, 13/10/2026)."""
S = dict(skip=True)
FICHES = {
    9: S,
    0: dict(nom="Mairie", mur="enduit#e4c890", toit="plat", h=(6.0, 6.0),
            o=["pv:0.15", "fen:3:3.4-4.4", "mat:0.4-0.95:bardage#c02a2a"]),
    1: dict(nom="Église", mur="pierre#a8a090", toit="2pans:tuile_brune", h=(6.0, 9.0), o=["porte:0.5"]),
    2: dict(nom="Bâtiment communal", mur="enduit#ece4d4", toit="2pans:tuile_brune", h=(5.0, 6.5), o=["fen:2"]),
    3: dict(nom="Mairie ancienne", mur="enduit#e8dcc8", toit="4pans:tuile", h=(8.0, 10.0),
            o=["fenv:4:3.8-5.0", "porte:0.4", "fen:2:1.0-2.2"]),
    4: dict(nom="Atelier", mur="enduit#d8d4cc", toit="sheds:tuile", h=(4.0, 6.5), o=["garage:2:#8a8e90"]),
    5: dict(nom="Bâtiment", mur="enduit#ecebe6", toit="2pans:tuile", h=(4.0, 5.5), o=["fen:3"]),
    6: dict(nom="Hangar", mur="bardage#ecebe8", toit="2pans:bac#b04a3a", h=(4.0, 5.5)),
    7: dict(nom="Hangar", mur="bardage#ecebe8", toit="plat", h=(5.0, 5.0)),
    8: dict(nom="Tunnel", mur="bardage#1a6a5a", toit="berceau:bac#1a6a5a", h=(0.5, 3.0)),
    10: dict(nom="Tunnel", mur="bardage#3a4a50", toit="berceau:bac#3a4a50", h=(0.4, 2.8)),
}
