"""Fiches des bâtiments non résidentiels de Saint-Sorlin-de-Morestel (une photo Street View chacun, 13/10/2026)."""
S = dict(skip=True)
def B(nom, mur, toit="plat", h=(6.0, 6.0), o=(), **k):
    return dict(nom=nom, mur=mur, toit=toit, h=h, o=list(o), **k)
USINE = B("Usine de béton", "enduit#d8ccb4", "2pans:tuile", (5.0, 7.0), ["garage:1:#2a4aa0"],
          brut={"extras": [{"t": "silo", "face": "N", "x": 0.85, "d": 2.5, "r": 1.5, "h": 9, "c": "#d8d4cc"}]})
FICHES = {
    5: S, 9: S, 12: S, 14: S, 16: S, 21: S, 23: S,
    0: B("Grange", "enduit#c8c4b8", "2pans:tuile_brune", (5.0, 7.0), ["fenv:1:3.0-4.0"]),
    1: B("Grange", "enduit#d8d4cc", "2pans:tuile", (5.0, 7.0)),
    2: B("Tunnel", "bardage#2a8a7a", "berceau:bac#2a8a7a", (0.5, 3.0)),
    3: B("Stabulation", "bardage#8a8e92", "2pans:fibro#a8a8a0", (4.0, 6.0), ["garage:2:#5a5e62"]),
    4: B("Bâtiment", "enduit#ecebe6", "2pans:tuile", (3.5, 5.0), ["fen:1:1.6-2.6"]),
    6: B("Grange", "enduit#d8d4cc", "2pans:tuile", (5.0, 7.0)), 7: B("Grange", "enduit#d8d4cc", "2pans:tuile", (4.0, 5.5)),
    8: B("Ferme", "beton#c8c4bc", "2pans:bac#a83a2a", (3.5, 5.0), ["fen:1", "porte:0.4"]),
    10: B("Mairie", "enduit#e0c060", "2pans:tuile_brune", (7.0, 9.0), ["fen:3:1.0-2.4", "fen:3:4.0-5.4", "pv:0.3"]),
    11: B("Château d'eau", "pierre#d8ccb0", h=(8.0, 8.0)),
    13: B("Église", "pierre#d8ccb0", "2pans:tuile_brune", (7.0, 10.0), ["ogive:3:3.0-5.4", "porte:0.4"]),
    15: B("Grange", "enduit#b8b4a8", "2pans:tuile", (4.0, 6.5)),
    17: USINE, 19: USINE,
    18: B("Hangar", "beton#a8a8a4", "2pans:bac#8a8e92", (5.0, 6.5)),
    20: B("Usine", "enduit#ecebe6", "2pans:tuile", (5.0, 7.0), ["fen:4"]),
    22: B("Grange", "beton#a8a8a4", "2pans:bac#8a4a3a", (5.0, 8.0), ["garage:1:#8a8e92"]),
}
