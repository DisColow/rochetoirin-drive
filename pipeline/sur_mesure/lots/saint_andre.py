"""Fiches des bâtiments non résidentiels de Saint-André-le-Gaz (une photo Street View chacun, 13/10/2026)."""
S = dict(skip=True)
def B(nom, mur, toit="plat", h=(6.0, 6.0), o=(), **k):
    return dict(nom=nom, mur=mur, toit=toit, h=h, o=list(o), **k)
ROSE = B("Usine", "enduit#d8b4a0", "2pans:bac#a85a4a", (5.0, 6.5), ["porte:0.85"])
BLANC = B("Usine", "bardage#ecebe8", "2pans:bac#ecebe8", (5.0, 6.5), ["fen:5:1.4-2.4"], soub=("beton#c8c4bc", 0.6))
SILO = B("Coopérative", "bardage#d8d4c4", "2pans:bac#a8a8a4", (4.0, 5.0),
         brut={"extras": [{"t": "silo", "face": "N", "x": 0.5, "d": 3, "r": 2.6, "h": 13, "c": "#a8acb0"},
                          {"t": "silo", "face": "N", "x": 0.85, "d": 3, "r": 2.6, "h": 13, "c": "#a8acb0"}]})
FICHES = {
    0: S, 3: S, 4: S, 13: S, 14: S, 16: S, 17: S, 21: S, 29: S, 30: S, 32: S, 33: S, 34: S, 35: S,
    1: B("Poulailler", "beton#c8c4bc", "2pans:fibro#9a9a92", (2.5, 3.5)),
    2: B("Poulailler", "beton#c8c4bc", "2pans:fibro#9a9a92", (2.5, 3.5)),
    5: ROSE, 7: ROSE,
    6: BLANC, 8: BLANC, 9: BLANC,
    10: B("Bâtiment", "enduit#ecebe6", "2pans:tuile", (7.0, 9.0), ["fen:2:1.0-2.4", "fen:2:4.0-5.4"]),
    11: B("Ferme", "enduit#c8b8a0", "2pans:tuile", (5.0, 7.0), ["fen:3:3.6-4.6"]),
    12: B("Hangar", "bois#8a6a4a", "2pans:tuile", (3.0, 5.0)),
    15: B("Château d'eau industriel", "enduit#e8e0d0", h=(17.0, 17.0)),
    18: B("Immeuble", "enduit#e8c0a8", "2pans:tuile", (8.0, 10.0), ["fenv:2:1.0-2.4", "fenv:2:4.0-5.4"]),
    19: B("Commerces", "enduit#f0c080", "2pans:tuile", (10.0, 12.0), ["vitrine:0.1-0.9", "fen:5:4.4-5.8", "fen:5:7.2-8.4", "ens:GEMINA:#2a5a8a:#ffffff"]),
    20: B("Le Millésime", "brique#b87a5a", "2pans:tuile", (8.0, 10.0), ["fen:4:1.0-2.4", "fen:4:4.0-5.4"],
          brut={"extras": [{"t": "store", "face": "NE", "x": [0.0, 0.3], "y": 2.6, "p": 1.4, "c": "#a82a2a"}]}),
    22: B("Entrepôt", "bardage#ecebe8", "2pans:bac#c8c8c4", (5.0, 6.5)),
    23: B("Entrepôt", "bardage#ecebe8", "2pans:bac#c8c8c4", (5.0, 6.5)),
    24: B("Boucherie Rôtisserie", "pierre#c8b090", "2pans:tuile", (8.0, 10.0), ["garage:2:#a82a3a", "fenv:3:4.0-5.4", "ens:BOUCHERIE:#ffffff:#2a2a2a"]),
    25: B("Le Millésime", "enduit#ecebe6", "2pans:tuile", (7.0, 9.0), ["vitrine:0.1-0.4", "garage:1:#3a3a3a", "ens:LE MILLÉSIME:#2e3036:#ffffff"]),
    26: B("Tabac", "bois#a87a4a", "2pans:tuile", (8.0, 10.0), ["rideau:1", "fen:2:4.0-5.4", "ens:TABAC:#c02a2a:#ffffff"]),
    27: SILO, 28: SILO,
    31: B("Usine", "bardage#4a8a3a", h=(5.0, 5.0), o=["fen:8:1.2-2.4"]),
    36: B("Négoce matériel", "bardage#ecebe8", "2pans:bac#c8c8c4", (5.0, 6.5), ["garage:2:#ecebe8"]),
}
