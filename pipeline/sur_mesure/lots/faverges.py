"""Fiches des bâtiments non résidentiels de Faverges-de-la-Tour (une photo Street View chacun, 13/10/2026)."""
S = dict(skip=True)
def B(nom, mur, toit="plat", h=(6.0, 6.0), o=(), **k):
    return dict(nom=nom, mur=mur, toit=toit, h=h, o=list(o), **k)
def O(nom="Hangar", c="#5a4a3a", toit="2pans:bac#8a8e92", h=(4.5, 6.0), **k):
    return dict(nom=nom, ouvert=True, c_poteaux=c, toit=toit, h=h, **k)
EGL = B("Église", "pierre#ece8e0", "2pans:tuile", (10.0, 14.0), ["ogive:4:3.0-7.0", "porte:0.5"],
        brut={"extras": [{"t": "clocher", "face": "N", "x": 0.5, "w": 5, "h": 24, "fleche": 2}]})
FICHES = {
    2: S, 3: S, 6: S, 8: S, 15: S, 18: S,
    0: B("Hangar", "bardage#a8b0a8", "2pans:bac#b04a3a", (5.0, 6.5), ["fen:5:1.6-2.2"]),
    1: B("Hangar", "bardage#a8b0a8", "2pans:bac#b04a3a", (5.0, 6.5)),
    4: O(toit="2pans:fibro#8a8a86", h=(4.0, 6.0)), 5: O(toit="2pans:fibro#8a8a86", h=(4.0, 6.0)),
    7: B("Atelier", "enduit#ecebe6", "2pans:tuile", (5.0, 7.0), ["fen:2:3.0-4.2"]),
    9: B("Usine", "bardage#ecebe8", h=(5.0, 5.0), o=["fen:5:1.2-2.2", "ens:FAVERGES INDUSTRIE:#ffffff:#2a5a9a"]),
    10: B("Bâtiment industriel", "enduit#a8a8a4", "2pans:tuile", (5.0, 7.0), ["ens:À LOUER:#ffffff:#c02a2a"]),
    11: B("Atelier", "bardage#a8acb0", "2pans:tuile", (6.0, 8.0), ["garage:1:#a8acb0"]),
    12: B("Usine", "enduit#ecebe6", h=(7.0, 7.0), o=["fen:3:1.0-2.4", "fen:3:4.0-5.4"]),
    13: B("Usine", "enduit#ecebe6", h=(7.0, 7.0), o=["fen:5:1.0-2.4", "fen:5:4.0-5.4", "ens:FRANTISSOR:#ecebe6:#2a2a2a"]),
    14: B("Négoce bois", "bois#7a6a5a", "2pans:bac#5a5e64", (4.0, 6.0)),
    16: B("Immeuble", "enduit#e8dcc8", "2pans:tuile", (8.0, 10.0), ["fen:4:1.0-2.4", "fen:4:4.0-5.4"]),
    17: B("Presbytère", "enduit#e8dcc8", "2pans:tuile", (6.0, 8.0), ["fen:4:1.0-2.4", "fen:4:4.0-5.4", "porte:0.55"]),
    19: B("Bâtiment", "enduit#ecdcd0", "2pans:tuile", (5.0, 7.0), ["porte:0.5", "fen:2:3.6-4.6"]),
    20: B("Tabac Presse", "enduit#e8dcc8", "4pans:tuile", (6.0, 8.0), ["vitrine:0.1-0.9", "fen:3:4.0-5.2"]),
    21: B("Mairie", "enduit#d8908a", "2pans:tuile", (6.0, 8.0), ["fen:3:1.0-2.4", "fen:3:4.0-5.4", "pv:0.4"]),
    22: B("Salle", "enduit#e8c8b0", "2pans:tuile", (4.0, 6.0), ["fen:3:1.0-2.2", "porte:0.4"]),
    23: B("Préau", "enduit#e8c8b0", "2pans:tuile_brune", (3.0, 5.0)),
    24: EGL, 25: EGL,
    26: B("Médiathèque", "bois#6a5a4a", h=(4.0, 4.0), o=["bande:0.6-2.6"]),
    27: B("Chapelle", "enduit#e8e4dc", "2pans:tuile", (4.0, 6.0), ["ogive:1:1.4-3.0", "porte:0.4"]),
}
