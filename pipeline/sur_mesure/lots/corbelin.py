"""Fiches des bâtiments non résidentiels de Corbelin et Morestel (une photo Street View chacun, 13/10/2026)."""
S = dict(skip=True)
def B(nom, mur, toit="plat", h=(6.0, 6.0), o=(), **k):
    return dict(nom=nom, mur=mur, toit=toit, h=h, o=list(o), **k)
FICHES = {
    3: S, 4: S,
    0: B("Usine", "bardage#d8d4c4", "2pans:bac#c8c4b8", (7.0, 8.5), ["vitrine:0.05-0.2", "garage:1:#2a2a2a"]),
    1: B("Usine", "beton#a8a8a4", h=(10.0, 10.0), o=["fen:5:3.0-4.4", "fen:5:6.4-7.8"]),
    2: B("Bâtiment", "enduit#ecebe6", "4pans:tuile_brune", (6.0, 9.0)),
}
