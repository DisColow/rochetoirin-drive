"""Fiches des bâtiments non résidentiels de Montcarra (une photo Street View chacun, 13/10/2026)."""
S = dict(skip=True)
FICHES = {
    0: S, 1: S, 8: S,
    2: dict(nom="Bureaux", mur="enduit#e8dcc0", toit="plat", h=(6.0, 6.0), o=["fen:6:1.0-2.2", "fen:6:3.8-5.0"]),
    3: dict(nom="Mairie", mur="enduit#efe6d4", toit="4pans:tuile", h=(3.5, 6.0), o=["fen:3", "pv:0.45", "mat:0.0-0.12:enduit#5a6a8a"]),
    4: dict(nom="École", mur="enduit#e4ccac", toit="2pans:tuile", h=(3.2, 5.0), o=["fen:2:1.0-2.2"]),
    5: dict(nom="École", mur="enduit#e4ccac", toit="4pans:tuile", h=(3.5, 6.0), o=["fen:4:1.0-2.2", "porte:0.3"]),
    6: dict(nom="École", mur="enduit#e4ccac", toit="2pans:tuile", h=(3.2, 5.0), o=["fen:2:1.0-2.2"]),
    7: dict(nom="Église", mur="pierre#b0a084", toit="2pans:tuile_brune", h=(8.0, 11.0), o=["ogive:3:3.0-6.0", "porte:0.5"]),
    9: dict(nom="Remise", ouvert=True, c_poteaux="#4a3a2a", toit="2pans:tuile", h=(2.4, 4.0)),
    10: dict(nom="Hangar à foin", ouvert=True, c_poteaux="#7a6a58", toit="2pans:tuile", h=(4.5, 7.0)),
    11: dict(nom="Hangar en bois", mur="bois#8a5a3a", toit="2pans:bac#b04a3a", h=(4.0, 6.0)),
}

FICHES[7] = S   # église : déjà un modèle dédié (landmarks.CHURCHES)
