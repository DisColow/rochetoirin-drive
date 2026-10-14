"""Fiches des bâtiments non résidentiels de La Tour-du-Pin (une photo Street View chacun, 13/10/2026)."""
S = dict(skip=True)
def B(nom, mur, toit="plat", h=(6.0, 6.0), o=(), **k):
    return dict(nom=nom, mur=mur, toit=toit, h=h, o=list(o), **k)
FICHES = {
    3: S, 6: S,
    0: B("Immeuble", "enduit#e8d8bc", "2pans:tuile", (9.0, 10.0), ["porte:0.25", "fen:4:1.0-2.4", "fen:5:4.0-5.4", "fen:5:7.0-8.4"]),
    1: B("Hôtel de France", "enduit#e8806a", "2pans:tuile", (14.0, 16.0), ["vitrine:0.1-0.9", "fen:5:4.0-5.4", "fen:5:7.0-8.4", "fen:5:10.0-11.4", "ens:HÔTEL DE FRANCE:#e8604a:#ffffff"]),
    2: B("Maison de bourg", "enduit#e8e2d4", "4pans:tuile", (7.0, 9.0), ["fen:2:1.0-2.4", "fen:2:4.0-5.4"]),
    4: B("Bâtiment public", "beton#d8ccb4", h=(7.0, 7.0), o=["fen:3:0.5-6.0", "porte:0.1"]),
    5: B("Bâtiment public", "beton#d8ccb4", h=(7.0, 7.0), o=["fen:3:0.5-6.0"]),
}
