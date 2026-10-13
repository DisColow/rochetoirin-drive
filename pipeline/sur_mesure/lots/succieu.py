"""Fiches des bâtiments non résidentiels de Succieu (une photo Street View chacun, 13/10/2026)."""
S = dict(skip=True)
def B(nom, mur, toit="plat", h=(6.0, 6.0), o=(), **k):
    return dict(nom=nom, mur=mur, toit=toit, h=h, o=list(o), **k)
def O(nom="Hangar", c="#5a4a3a", toit="2pans:bac#8a8e92", h=(4.5, 6.0), **k):
    return dict(nom=nom, ouvert=True, c_poteaux=c, toit=toit, h=h, **k)
PISE = B("Grange en pisé", "enduit#c8a878", "2pans:tuile", (4.0, 6.0), soub=("pierre#a89a84", 0.8))
FERME = B("Ferme", "enduit#ecebe6", "2pans:bac#9a6a5a", (3.5, 5.0), ["garage:5:#5a3a2a"])
FICHES = {
    1: S, 3: S, 4: S, 7: S, 9: S, 10: S, 11: S, 13: S, 19: S, 26: S,
    0: PISE, 5: PISE, 6: PISE, 12: PISE, 14: PISE, 15: PISE,
    2: B("Grange", "beton#c8c0b0", "2pans:tuile", (5.0, 7.0), ["garage:1:#7a7e84"]),
    8: B("Hangar", "bardage#a86a4a", "berceau:bac#a86a4a", (1.0, 4.0)),
    16: B("Hangar", "bardage#c8ccd0", "2pans:bac#c8ccd0", (3.0, 4.0)),
    17: O(c="#a82a2a", toit="2pans:bac#a83a2a", h=(5.0, 6.0), pignons_clos=True),
    18: O(c="#a82a2a", toit="2pans:bac#5a5a5a", h=(5.0, 6.5), pignons_clos=True),
    20: B("Ferme", "enduit#e8dcc4", "2pans:tuile", (4.0, 6.0), ["garage:1:#c89a3a"]),
    21: FERME, 22: FERME, 23: FERME, 24: FERME,
    25: B("Usine", "enduit#d8d4cc", "2pans:tuile", (6.0, 7.5), ["fen:5:3.6-4.6"]),
}
