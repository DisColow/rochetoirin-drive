"""Fiches des bâtiments non résidentiels de Dolomieu (une photo Street View chacun, 13/10/2026)."""
S = dict(skip=True)
def B(nom, mur, toit="plat", h=(6.0, 6.0), o=(), **k):
    return dict(nom=nom, mur=mur, toit=toit, h=h, o=list(o), **k)
def O(nom="Hangar", c="#5a4a3a", toit="2pans:bac#8a8e92", h=(4.5, 6.0), **k):
    return dict(nom=nom, ouvert=True, c_poteaux=c, toit=toit, h=h, **k)
ECOLE = B("École", "enduit#ece8dc", "2pans:tuile_brune", (4.0, 6.0), ["fen:2:1.0-2.4"], soub=("#2a7a6a", 0.2))
FERME = O("Hangar", c="#6a5a42", toit="2pans:fibro#9a9a92", h=(3.5, 5.0))
MAIRIE = B("Mairie", "enduit#ecebe4", "4pans:tuile", (8.0, 10.0), ["fen:3:1.0-2.6", "fen:3:4.0-5.4", "pv:0.5"])
FICHES = {
    0: S, 3: S, 4: S, 5: S, 6: S, 7: S, 15: S, 16: S, 36: S, 38: S, 42: S,
    1: B("Atelier", "bardage#a8acb0", "2pans:bac#8a8e92", (3.5, 5.0), ["garage:1:#a8acb0", "fen:1"]),
    2: B("Bâtiment", "enduit#ecd8c0", "2pans:tuile", (4.0, 5.5), ["fen:4"]),
    8: B("Garage", "enduit#ece8dc", "2pans:fibro#a8a8a0", (5.0, 6.5), ["garage:1:#3a3a3a", "ens:GARAGE:#1a3a8a:#ffffff"]),
    9: B("Atelier", "enduit#d8d0c0", "2pans:tuile", (3.5, 5.0), ["fen:1:1.2-2.4"]),
    10: FERME, 11: FERME, 13: FERME,
    12: B("Grange", "pierre#b8a888", "2pans:tuile", (4.0, 7.0), soub=("pierre#b8a888", 4.0)),
    14: B("Grange", "pierre#b8a888", "2pans:tuile", (3.0, 5.0)),
    17: B("Usine ancienne", "enduit#ece4d0", "2pans:tuile", (4.0, 5.5), ["fen:4:1.0-3.0"]),
    18: B("Bâtiment", "enduit#b8b0a4", "2pans:tuile", (5.0, 7.0)),
    19: B("École", "enduit#e8b060", "plat", (4.0, 4.0), ["fen:8:0.8-2.6", "mat:0.0-0.05:enduit#c02a2a"]),
    20: B("Église", "pierre#a89070", "2pans:tuile_brune", (10.0, 14.0), ["ogive:3:3.0-7.0", "porte:0.5"],
          brut={"extras": [{"t": "clocher", "face": "O", "x": 0.5, "w": 5, "h": 30, "fleche": 10}]}),
    21: ECOLE, 22: ECOLE, 23: ECOLE, 24: ECOLE, 25: ECOLE, 26: ECOLE, 27: ECOLE, 29: ECOLE,
    28: B("Église", "pierre#a89070", "2pans:tuile_brune", (8.0, 12.0), ["ogive:2:3.0-6.0"]),
    30: MAIRIE, 31: MAIRIE, 32: MAIRIE, 33: MAIRIE,
    34: B("Institut de beauté", "enduit#b8945a", "2pans:tuile", (7.0, 9.0), ["vitrine:0.05-0.6", "fen:3:4.0-5.4"]),
    35: B("Vival", "enduit#e0a090", "2pans:tuile", (8.0, 10.0), ["vitrine:0.1-0.5", "fenv:2:4.0-5.4", "fenv:2:6.6-7.6"]),
    37: B("Remise", "enduit#e8d8b8", "2pans:tuile", (3.0, 5.0), ["garage:2:#ecebe8"]),
    39: B("Ramstor", "bardage#3a6aa0", "2pans:bac#3a6aa0", (6.0, 8.0), ["fen:4:3.6-4.8", "fen:4:1.0-2.2", "ens:RAMSTOR:#f0c020:#1a1a1a"], soub=("enduit#ecebe6", 3.0)),
    40: B("Ramstor", "bardage#3a6aa0", "2pans:bac#3a6aa0", (6.0, 8.0), ["fen:4:3.6-4.8", "fen:4:1.0-2.2"], soub=("enduit#ecebe6", 3.0)),
    41: B("Hangar", "bardage#8a8e84", "2pans:bac#8a8e84", (5.0, 6.5), soub=("beton#c8c4bc", 1.4)),
    43: B("Atelier", "beton#a8a49c", "2pans:tuile", (4.0, 6.0), ["garage:1:#ecebe8", "fen:2:3.6-4.4"]),
    44: B("Atelier", "bardage#c8ccd2", "2pans:bac#c8ccd2", (5.0, 6.5), ["garage:1:#c8ccd2", "porte:0.6", "fen:1:1.0-2.0"]),
    46: S, 53: S, 54: S, 56: S, 60: S, 61: S, 64: S, 65: S, 66: S, 67: S, 74: S,
    45: B("Usine", "bardage#d8dcdc", h=(7.0, 7.0), o=["fen:4:1.2-2.4", "mat:0.0-0.15:bardage#2a4a8a"]),
    47: B("Chapelle", "enduit#e0d0b8", "2pans:tuile", (6.0, 8.0), ["porte:0.5", "ogive:2:3.8-5.6"]),
    48: B("Bâtiment", "enduit#b8b4a8", "4pans:tuile", (7.0, 9.0), ["fenv:3:1.0-2.4", "fenv:3:4.0-5.4"]),
    49: B("Église", "pierre#a89070", "2pans:tuile_brune", (6.0, 9.0), ["ogive:5:2.4-5.0", "porte:0.55"]),
    50: B("Immeuble", "enduit#ece4d4", "2pans:tuile", (9.0, 11.0), ["fenv:3:1.0-2.4", "fenv:3:4.0-5.4", "fenv:3:6.8-8.0"]),
    51: B("Immeuble", "enduit#a8a8a4", "2pans:tuile", (7.0, 9.0), ["fen:4:1.0-2.4", "fen:4:4.0-5.4"]),
    52: B("Boulangerie Pâtisserie", "enduit#e8d0b0", "2pans:tuile", (6.0, 7.0), ["vitrine:0.2-0.8", "fen:2:4.0-5.0", "ens:BOULANGERIE PÂTISSERIE:#a86a3a:#ffffff"]),
    55: B("Centre technique", "bardage#c8ccd0", "2pans:bac#c8ccd0", (5.0, 6.0), ["garage:3:#ecebe8"]),
    57: B("Vilest", "bardage#ecebe8", h=(5.0, 5.0), o=["fen:3:1.0-2.2", "ens:VILEST:#ffffff:#1a4aa0"]),
    58: B("Maison de bourg", "enduit#d8b878", "2pans:tuile", (7.0, 8.5), ["fenv:2:4.0-5.4", "fenv:1:1.0-2.4", "porte:0.4"]),
    59: B("Café-restaurant", "enduit#e8d0b8", "2pans:tuile", (7.0, 8.5), ["fen:3:4.0-5.4", "garage:3:#6a3a2a"]),
    62: B("Grange", "bois#7a6a5a", "2pans:fibro#9a9a92", (2.6, 4.0)),
    63: B("Immeuble", "enduit#c8c0b0", "2pans:tuile", (9.0, 11.0), ["fen:3:1.0-2.4", "fen:3:4.0-5.4", "fen:3:7.0-8.2"]),
    68: B("Boucherie Charcuterie", "enduit#d8ccb4", "2pans:tuile", (7.0, 9.0), ["vitrine:0.1-0.8", "fenv:3:4.0-5.4", "ens:BOUCHERIE CHARCUTERIE:#ece0c8:#8a2a2a"]),
    69: B("Color'Style", "enduit#c8c4b8", "2pans:tuile", (6.0, 8.0), ["vitrine:0.1-0.9", "fenv:2:4.0-5.4", "ens:COLOR'STYLE:#8a2a6a:#ffffff"]),
    70: B("Vestiaires", "enduit#ece8dc", "2pans:tuile", (3.5, 5.0), ["porte:0.3", "porte:0.7"]),
    71: B("Gymnase", "bardage#d8dcd8", "berceau:bac#5a8a6a", (3.0, 7.0)),
    72: B("Salle", "bardage#8a2a2a", "plat", (5.0, 5.0), ["bande:0.6-2.6"]),
    73: B("Maison de bourg", "enduit#ecebe6", "2pans:tuile", (8.0, 10.0), ["fenv:2:4.0-5.4", "fenv:1:6.8-8.0"]),
}
