"""Fiches des bâtiments non résidentiels des Éparres (une photo Street View chacun, 13/10/2026)."""
S = dict(skip=True)
def B(nom, mur, toit="plat", h=(6.0, 6.0), o=(), **k):
    return dict(nom=nom, mur=mur, toit=toit, h=h, o=list(o), **k)
GRANGE = B("Grange", "beton#c8c4bc", "2pans:tuile", (5.0, 7.0))
USINE = B("Usine", "bardage#ecebe8", "2pans:fibro#a8a8a0", (7.0, 9.0), ["fen:2:1.2-2.2"])
FICHES = {
    0: S, 1: S, 3: S, 4: S, 6: S, 16: S, 20: S, 27: S, 33: S, 34: S, 35: S, 36: S, 37: S, 43: S, 44: S, 45: S, 46: S,
    2: dict(nom="Grange", mur="enduit#ecebe6", toit="2pans:tuile", h=(5.0, 7.5), ouvert=False, o=[]),
    5: GRANGE, 7: GRANGE, 9: GRANGE,
    8: dict(nom="Stabulation", ouvert=True, c_poteaux="#5a6a7a", toit="2pans:bac#8a8e92", h=(4.0, 6.0), pignons_clos=True),
    10: B("Grange en pisé", "enduit#c8a878", "2pans:tuile", (4.0, 6.0), ["fen:2:2.0-3.0"], soub=("pierre#9a8a78", 1.2)),
    11: B("Garages", "beton#c8c4bc", "2pans:tuile", (3.0, 4.5), ["garage:2:#a8643a"]),
    12: B("Garages", "beton#c8c4bc", "2pans:tuile", (2.6, 3.6), ["garage:2:#a8643a"]),
    13: B("Grange", "bois#a8987a", "2pans:tuile", (4.0, 6.0), ["garage:2:#a83a2a"]),
    14: B("Hangar", "bardage#a8acb0", "2pans:bac#a8acb0", (3.0, 4.0), ["garage:1:#3a3a3a"]),
    15: B("Menuiserie", "bois#8a6a4a", "2pans:tuile", (5.0, 7.0), ["garage:2:#8a5a3a"]),
    17: B("Mairie", "enduit#ecdcc4", "2pans:tuile", (6.0, 8.0), ["fen:5:1.0-2.4", "fen:5:4.0-5.4", "pv:0.5"]),
    18: B("Église", "pierre#b8a888", "2pans:tuile", (8.0, 11.0), ["porte:0.5", "fen:1:5.0-6.0"], soub=("brique#a85a3a", 0.0)),
    19: B("La Ferme de la Grangière", "bois#8a6a4a", "2pans:tuile", (5.0, 7.0), ["vitrine:0.5-0.8", "porte:0.3", "ens:LA FERME DE LA GRANGIÈRE:#ffffff:#2a5a3a"]),
    21: B("Adour Chauffage", "enduit#a8a8a4", "2pans:tuile", (4.0, 6.0), ["vitrine:0.3-0.7", "ens:CHAUFFAGE:#ffffff:#2a6ab0"]),
    22: B("Maison de bourg", "enduit#e8dcc4", "2pans:tuile", (8.0, 10.0), ["fen:3:1.0-2.4", "fen:3:4.0-5.4", "fen:3:6.8-8.0"]),
    23: B("École", "enduit#ecebe6", "2pans:tuile", (6.0, 8.0), ["fen:4:1.0-2.4", "fen:4:4.0-5.4"]),
    24: B("Bâtiment communal", "enduit#ecebe6", "2pans:tuile", (7.0, 9.0), ["garage:3:#a8acb0", "fenv:4:4.0-5.4"]),
    25: B("Coiffure", "enduit#e8c890", "2pans:tuile", (6.0, 8.0), ["vitrine:0.1-0.9", "fenv:1:4.0-5.4"]),
    26: B("Usine", "enduit#e8dcc4", "2pans:tuile", (6.0, 8.0), ["fenv:3:3.6-4.8"]),
    28: B("Garage", "enduit#ecebe6", "2pans:bac#a8a8a4", (6.0, 8.0), ["garage:1:#c8c8c4"]),
    29: B("Grange", "pierre#a89070", "2pans:tuile", (4.0, 5.5), ["fen:2:2.0-3.0"]),
    30: USINE, 31: B("Atelier", "bardageh#4a4e56", "2pans:bac#4a4e56", (4.0, 5.0)),
    32: B("Usine", "pierre#a89070", "2pans:tuile", (3.0, 4.0)),
    38: USINE, 39: USINE, 40: USINE, 41: USINE, 42: USINE,
    47: B("Dimopur", "bardage#ecebe8", h=(8.0, 8.0), o=["garage:2:#7a7e84", "ens:DIMOPUR:#ffffff:#2a2a2a"]),
    48: B("Usine", "bardage#d8c8a0", "2pans:bac#a85a3a", (5.0, 6.5)),
}
