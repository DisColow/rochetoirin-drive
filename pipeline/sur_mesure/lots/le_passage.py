"""Fiches des bâtiments non résidentiels du Passage (une photo Street View chacun, 13/10/2026)."""
S = dict(skip=True)
def B(nom, mur, toit="plat", h=(6.0, 6.0), o=(), **k):
    return dict(nom=nom, mur=mur, toit=toit, h=h, o=list(o), **k)
FICHES = {
    1: S, 3: S,
    0: dict(nom="Hangar", ouvert=True, c_poteaux="#7a7e84", toit="2pans:bac#8a8e92", h=(5.0, 6.5)),
    2: B("Atelier", "enduit#c8c4bc", "2pans:fibro#9a9a92", (4.0, 5.5), ["garage:1:#c8ccd0", "fen:2"]),
    4: B("Commerce", "enduit#ecebe6", "2pans:tuile", (6.0, 8.0), ["vitrine:0.1-0.8", "fen:4:4.0-5.0"]),
    5: B("Mairie", "enduit#ece4d0", "2pans:tuile", (7.0, 9.0), ["fen:3:1.0-2.4", "fen:3:4.0-5.4", "porte:0.5"]),
    6: B("Bâtiment communal", "enduit#ecdcc0", "2pans:tuile", (3.5, 5.0), ["fen:2", "porte:0.7"]),
    7: dict(nom="Hangar agricole", ouvert=True, c_poteaux="#5a4a3a", toit="2pans:bac#8a6a50", h=(4.0, 6.0), pignons_clos=True),
}
