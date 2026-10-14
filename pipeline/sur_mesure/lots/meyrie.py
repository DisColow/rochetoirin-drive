"""Fiches des bâtiments non résidentiels de Meyrié (une photo Street View chacun, 13/10/2026)."""
S = dict(skip=True)
def B(nom, mur, toit="plat", h=(6.0, 6.0), o=(), **k):
    return dict(nom=nom, mur=mur, toit=toit, h=h, o=list(o), **k)
SELF = B("Selfbeton", "bardage#d8c8a8", "2pans:bac#a8a8a4", (4.0, 5.0),
         brut={"extras": [{"t": "silo", "face": "N", "x": 0.3, "d": 2, "r": 1.6, "h": 12, "c": "#c82a2a"}]})
RESTO = B("Restaurant Traiteur", "bardage#ecebe8", "2pans:bac#a82a3a", (3.0, 4.0), ["bande:0.6-2.4", "ens:RESTAURANT TRAITEUR VIANDE:#a82a3a:#ffffff"])
MAIRIE = B("Mairie-école", "enduit#e8d4a8", "2pans:tuile", (5.0, 7.0), ["fen:3:3.0-4.0"])
FICHES = {
    7: S, 8: S, 12: S, 16: S, 17: S, 19: S, 27: S, 30: S, 31: S,
    0: B("Entrepôt", "bardage#a8acb0", "2pans:bac#a8acb0", (4.0, 5.0)),
    1: B("Atelier", "enduit#e8d8b8", "2pans:tuile", (5.0, 6.5), ["garage:2:#a82a2a", "ens:ATELIER:#ffffff:#2a2a2a"]),
    2: B("Metalcob", "bardage#d8d0b8", "2pans:bac#c8c8c4", (6.0, 7.5), ["ens:METALCOB:#2e3036:#ffffff"]),
    3: SELF, 4: SELF, 5: SELF,
    6: B("Usine ancienne", "pierre#a89070", "2pans:tuile", (10.0, 12.0), ["fen:5:1.0-2.4", "fen:5:4.0-5.4", "fen:5:7.0-8.4"]),
    9: B("Bureaux", "enduit#d8b898", h=(8.0, 8.0), o=["fen:6:1.0-2.4", "fen:6:4.0-5.4"]),
    10: B("Entrepôt", "bardage#a8acb0", h=(6.0, 6.0)),
    11: B("Entrepôt", "bardage#ecebe8", "2pans:bac#c8c8c4", (6.0, 7.5), ["garage:1:#ecebe8"]),
    13: B("Ateliers", "bardage#ecebe8", "2pans:bac#c8c8c4", (5.0, 6.5), ["garage:3:#ecebe8"]),
    14: RESTO, 15: RESTO,
    18: B("Salle", "enduit#e8c8a0", "2pans:tuile", (3.5, 5.0), ["pv:0.4"]),
    20: MAIRIE, 22: MAIRIE, 23: MAIRIE,
    21: B("École", "enduit#ecebe6", "4pans:tuile", (3.5, 5.0), ["fen:2:1.0-2.4"]),
    24: B("Salle", "enduit#e8b878", "2pans:bac#3a4250", (4.0, 6.0), ["fen:1:1.0-2.6"]),
    25: B("Salle", "enduit#e8b878", "2pans:bac#3a4250", (4.0, 6.0), ["fen:1:1.0-2.6"]),
    26: B("Église", "pierre#a89070", "2pans:tuile", (7.0, 10.0), ["ogive:2:3.0-5.0"],
          brut={"extras": [{"t": "clocher", "face": "O", "x": 0.5, "w": 3.5, "h": 18, "fleche": 6}]}),
    28: B("Pôle médical", "enduit#d8c0a0", "2pans:tuile", (4.0, 6.0), ["vitrine:0.1-0.4", "fen:3"]),
    29: B("Marc Rozier", "enduit#ecebe6", h=(4.0, 4.0), o=["fen:8:1.0-2.4", "porte:0.3", "ens:MARC ROZIER:#ecebe6:#2a2a2a"]),
    32: B("Salle des sports", "enduit#e8d0b0", "2pans:tuile", (4.0, 5.5), ["fen:3:1.4-2.2"]),
}
