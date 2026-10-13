"""Fiches des bâtiments non résidentiels de Sérézin-de-la-Tour (une photo Street View chacun, 13/10/2026)."""
S = dict(skip=True)
def B(nom, mur, toit="plat", h=(6.0, 6.0), o=(), **k):
    return dict(nom=nom, mur=mur, toit=toit, h=h, o=list(o), **k)
GRANGE = B("Grange", "bardage#3a4250", "4pans:tuile_brune", (4.0, 7.0), ["mat:0.0-0.25:beton#c8c4b8"])
SECHOIR = B("Séchoir", "bois#9a8a68", "2pans:fibro#9a9a92", (4.0, 5.5), soub=("beton#a8a49c", 1.4))
SOLAIRE = B("Stabulation", "bois#7a5a3a", "2pans:bac#2a3a5a", (3.5, 6.0), ["mat:0.0-0.2:beton#c8c4b8"])
FICHES = {
    1: S, 3: S, 7: S, 22: S, 25: S, 27: S, 29: S, 31: S, 39: S,
    0: B("Remise", "enduit#c8c4bc", "2pans:tuile", (3.0, 4.5)),
    2: B("Salle", "enduit#e4cc90", "2pans:tuile", (4.0, 5.5), ["fen:3"]),
    4: B("Grange", "enduit#ecebe6", "2pans:bac#9aa0a4", (5.0, 7.0), ["garage:1:#6a4a32"]),
    5: B("Grange", "beton#a8a8a4", "2pans:tuile", (5.0, 7.0), ["fen:3:1.2-2.2"]),
    6: B("Grange en pisé", "enduit#a88a68", "appentis:tuile", (3.0, 4.5)),
    8: B("Grange", "enduit#e8c890", "2pans:tuile", (5.0, 7.0), soub=("#d08a7a", 2.0)),
    9: GRANGE, 10: GRANGE, 11: GRANGE,
    12: B("Étable", "beton#c8c0b0", "2pans:bac#9a6a4a", (3.0, 4.5), ["fen:1:1.6-2.2"]),
    13: SECHOIR, 14: SECHOIR, 15: SECHOIR, 21: SECHOIR,
    16: B("Hangar", "bardage#7a8a9a", "2pans:fibro#9a9a92", (4.0, 5.0)),
    17: B("Bâtiment", "enduit#ecebe6", "2pans:tuile", (4.0, 5.5)),
    18: B("Grange", "enduit#c8c4b8", "2pans:tuile", (5.0, 7.0)),
    19: B("Grange", "enduit#c8b494", "2pans:tuile", (4.0, 6.0), ["garage:1:#7a5a3a"]),
    20: B("Grange en pisé", "enduit#c8a878", "2pans:tuile", (5.0, 7.0), ["fen:2:1.0-2.0"]),
    23: B("École", "enduit#ecebe6", "2pans:tuile", (6.0, 8.0), ["bande:4.0-6.0", "fen:3:1.0-2.4"]),
    24: B("Église", "enduit#d8ccb0", "2pans:tuile", (8.0, 11.0), ["porte:0.5"]),
    26: B("Mairie", "enduit#e8a890", "4pans:tuile_brune", (7.0, 9.0), ["fen:4:1.0-2.6", "fen:4:4.0-5.4", "ens:MAIRIE:#e8a890:#2a2a2a"]),
    28: B("École", "enduit#e8b0a0", "2pans:tuile", (7.0, 9.0), ["fen:5:1.0-2.4", "fen:5:4.0-5.4"]),
    30: B("École", "enduit#e8b0a0", "2pans:tuile", (6.0, 8.0), ["fen:3:3.6-4.8", "vitrine:0.2-0.8"]),
    32: SOLAIRE, 33: SOLAIRE, 34: SOLAIRE, 35: SOLAIRE,
    36: B("Grange", "beton#c8b898", "2pans:bac#8a8e92", (4.0, 6.0), ["porte:0.3"]),
    37: B("Atelier", "bardageh#5a5e64", "2pans:bac#5a5e64", (3.0, 4.0)),
    38: B("Hangar", "bois#6a5a42", "2pans:bac#8a4a3a", (3.5, 5.0)),
}
