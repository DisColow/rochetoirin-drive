"""Fiches des bâtiments non résidentiels de La Bâtie-Montgascon (une photo Street View chacun, 13/10/2026)."""
S = dict(skip=True)
def B(nom, mur, toit="plat", h=(6.0, 6.0), o=(), **k):
    return dict(nom=nom, mur=mur, toit=toit, h=h, o=list(o), **k)
GARAGE = B("Garage Citron", "bardage#ecebe8", "2pans:tuile", (4.0, 6.0), ["garage:2:#3a3a3a", "ens:ATELIER:#c02a2a:#ffffff"], soub=("bardage#c02a2a", 3.6))
FICHES = {
    5: S, 6: S, 7: S, 8: S, 9: S, 12: S, 13: S, 14: S, 26: S, 33: S,
    0: B("Garage du Replat", "bardage#ecebe8", "2pans:bac#c8c8c4", (6.0, 8.0), ["vitrine:0.6-0.95", "porte:0.4", "ens:GARAGE DU REPLAT:#ffffff:#c02a2a"]),
    1: GARAGE, 2: GARAGE,
    3: B("Atelier", "enduit#a8a8a4", "2pans:tuile", (4.0, 6.0), ["garage:1:#ecebe8"]),
    4: B("Citron", "bardage#ecebe8", h=(4.0, 4.0), o=["vitrine:0.2-0.8", "ens:CITRON:#ffffff:#c02a2a"]),
    10: B("Bar de la Pattie", "pierre#b8a888", "2pans:tuile", (6.0, 8.0), ["vitrine:0.2-0.8", "fen:2:4.0-5.0", "ens:BAR DE LA PATTIE:#8a2a2a:#ffffff"], soub=("pierre#b8a888", 3.4)),
    11: B("Bureaux", "enduit#e8d8b0", h=(6.0, 6.0), o=["fen:8:1.0-2.4", "fen:8:4.0-5.4"]),
    15: B("Maison de bourg", "enduit#e8dcc8", "2pans:tuile", (6.0, 8.0), ["garage:2:#8a5a3a", "fen:4:3.8-5.0"]),
    16: B("Commerces", "enduit#e8c070", "2pans:tuile", (8.0, 10.0), ["vitrine:0.1-0.9", "fen:4:4.0-5.4", "fen:4:6.8-8.0"]),
    17: B("Commerces", "enduit#e8b080", "2pans:tuile", (7.0, 9.0), ["vitrine:0.1-0.5", "fen:3:4.0-5.4"]),
    18: B("Sundara", "enduit#e8c0a0", "2pans:tuile", (7.0, 9.0), ["vitrine:0.1-0.6", "fen:3:4.0-5.4", "ens:SUNDARA:#2a4a6a:#ffffff"]),
    19: B("Vival", "enduit#e8d8c4", "2pans:tuile", (6.0, 8.0), ["vitrine:0.1-0.6", "ens:VIVAL:#2a2a2a:#ffffff"]),
    20: B("Commerces", "enduit#e8e4dc", "2pans:tuile", (7.0, 9.0), ["vitrine:0.5-0.9", "garage:1:#ecebe8", "fenv:4:4.0-5.4"]),
    21: B("Tabac Presse", "enduit#ecebe6", "2pans:tuile", (8.0, 10.0), ["vitrine:0.2-0.8", "fen:4:4.0-5.4", "ens:TABAC PRESSE:#c02a2a:#ffffff"]),
    22: B("Boulangerie", "enduit#e8d098", "2pans:tuile", (7.0, 9.0), ["vitrine:0.2-0.7", "fen:3:4.0-5.4", "ens:BOULANGERIE PÂTISSERIE:#2a4a6a:#ffffff"]),
    23: B("Boutique", "pierre#c8b898", "2pans:tuile", (6.0, 8.0), ["vitrine:0.3-0.8", "fen:2:4.0-5.0"]),
    24: B("Maison de bourg", "enduit#d8d4cc", "2pans:tuile", (6.0, 8.0), ["fen:3:1.0-2.4", "fen:3:3.8-5.0"]),
    25: B("Ancien commerce", "enduit#ecdcc0", "2pans:tuile", (6.0, 8.0), ["vitrine:0.2-0.6", "fenv:3:4.0-5.4"]),
    27: B("Golden Villa", "enduit#ecebe6", "2pans:tuile", (7.0, 9.0), ["rideau:1", "fen:2:4.0-5.4", "ens:GOLDEN VILLA:#2e3036:#f0c020"]),
    28: B("L'Étal Batieland", "enduit#d8c8a8", "2pans:tuile", (8.0, 10.0), ["vitrine:0.3-0.7", "garage:1:#ecebe8", "fen:3:4.0-5.4"]),
    29: B("Bâtiment communal", "enduit#c8c0b0", "2pans:tuile", (6.0, 8.0), ["fen:5:1.0-3.0"]),
    30: B("Mairie", "enduit#ece4d4", "4pans:tuile", (10.0, 13.0), ["garage:4:#3a3a3a", "fen:4:5.0-6.4", "fen:4:7.6-8.8"]),
    31: B("Usine", "enduit#e8d0b0", h=(5.0, 5.0), o=["fen:5:3.0-4.4", "fen:5:0.6-2.0"]),
    32: B("Église", "pierre#ece8e0", "2pans:ardoise", (8.0, 12.0), ["ogive:3:3.0-6.0", "porte:0.5"],
          brut={"extras": [{"t": "clocher", "face": "N", "x": 0.2, "w": 4, "h": 26, "fleche": 10}]}),
}
