"""Fiches des bâtiments non résidentiels de Sermérieu (une photo Street View chacun, 13/10/2026)."""
S = dict(skip=True)
def B(nom, mur, toit="plat", h=(6.0, 6.0), o=(), **k):
    return dict(nom=nom, mur=mur, toit=toit, h=h, o=list(o), **k)
FICHES = {
    0: B("Tunnel", "bardage#4a6a8a", "berceau:bac#4a6a8a", (0.5, 3.0)),
    1: B("École", "enduit#e8d0a8", "2pans:tuile", (5.0, 7.0), ["fen:6:1.0-2.4", "mat:0.4-0.6:bois#a86a3a"]),
    2: B("Garage AD", "bardage#a8acb0", h=(5.0, 5.0), o=["vitrine:0.6-0.95", "fen:2:2.0-3.0", "ens:AD AUTO:#ffffff:#c02a2a"]),
    3: B("Entrepôt", "bardage#a8acb0", h=(5.0, 5.0)),
    4: B("Usine", "bardage#ecebe8", h=(6.0, 6.0), o=["fen:3:1.0-2.4", "mat:0.0-0.05:bardage#4a9a3a"]),
    5: B("Grange en pisé", "enduit#c8a878", "2pans:tuile", (5.0, 6.5), ["fen:1:3.4-4.2"]),
}
