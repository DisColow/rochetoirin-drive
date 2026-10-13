"""Fiches des bâtiments non résidentiels de Vignieu (une photo Street View chacun, 13/10/2026)."""
S = dict(skip=True)
FICHES = {
    0: S, 1: S, 4: S, 6: S, 9: S, 12: S, 16: S,
    2: dict(nom="Garages", mur="enduit#e8c89a", toit="2pans:tuile", h=(3.0, 4.0), o=["garage:2:#ecebe8"]),
    3: dict(nom="Auberge", mur="enduit#ecebe6", toit="2pans:tuile_brune", h=(6.0, 8.0), o=["fen:3:1.0-2.2", "fen:3:3.4-4.6", "porte:0.4"]),
    5: dict(nom="Remise", mur="enduit#e8dcc0", toit="2pans:tuile", h=(2.6, 3.6), o=["garage:1:#7a5a3a"]),
    7: dict(nom="Maison de bourg", mur="enduit#d8c8a8", toit="4pans:tuile", h=(7.0, 9.0), o=["fenv:3:1.0-2.4", "fenv:3:3.8-5.0"]),
    8: dict(nom="Mairie-école", mur="enduit#ecebe6", toit="4pans:tuile_brune", h=(7.0, 9.0), o=["fen:5:1.0-2.4", "fen:5:3.8-5.0"]),
    10: dict(nom="Salle", mur="enduit#ecebe6", toit="2pans:tuile", h=(3.0, 4.5)),
    11: dict(nom="Bâtiment communal", mur="enduit#a8a8a4", toit="4pans:tuile_brune", h=(7.0, 9.5), o=["fen:4:1.0-2.4", "fen:4:4.0-5.4"]),
    13: dict(nom="Église", mur="pierre#a89a84", toit="2pans:tuile_brune", h=(8.0, 11.0), o=["ogive:3:3.0-6.0"],
             brut={"extras": [{"t": "clocher", "face": "N", "x": 0.5, "w": 3.5, "h": 18, "fleche": 6}]}),
    14: dict(nom="Ferme", mur="enduit#d8c8b0", toit="2pans:tuile", h=(4.0, 6.0), o=["garage:2:#a03a2a", "fen:2"]),
    15: dict(nom="Remise", mur="enduit#c8c0b0", toit="2pans:tuile", h=(3.0, 4.5)),
    17: dict(nom="Stabulation", mur="bois#6a4a32", toit="2pans:bac#7a5a40", h=(4.0, 6.5), o=["garage:2:#3a2a20"]),
    18: dict(nom="Remise", mur="enduit#e4d4b8", toit="2pans:tuile", h=(3.5, 5.0)),
    19: dict(nom="Atelier", mur="enduit#e4d4b8", toit="2pans:bac#ecebe8", h=(3.0, 4.0)),
    20: dict(nom="Commerce", mur="enduit#e8d8b8", toit="2pans:tuile", h=(5.0, 7.0), o=["mat:0.35-0.6:bois#8a3a2a", "garage:1:#6a6a6a", "fen:3:3.4-4.4"]),
    21: dict(nom="Hangar", mur="bardage#d8dce0", toit="2pans:bac#c8ccd0", h=(5.0, 6.5), soub=("beton#8a7a70", 2.4)),
}
