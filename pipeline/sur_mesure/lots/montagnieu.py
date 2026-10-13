"""Fiches des bâtiments non résidentiels de Montagnieu (une photo Street View chacun, 13/10/2026)."""
S = dict(skip=True)
def B(nom, mur, toit="plat", h=(6.0, 6.0), o=(), **k):
    return dict(nom=nom, mur=mur, toit=toit, h=h, o=list(o), **k)
VERT = B("Hangar", "bardage#7a9a6a", "2pans:bac#8a8e92", (4.0, 5.5))
FICHES = {
    0: S,
    1: B("Écurie", "bois#a88a68", "2pans:bac#8a8e92", (3.0, 4.5), ["garage:1:#3a2a20"]),
    2: VERT, 3: VERT,
    4: B("Hangar", "bardage#7a9a6a", "2pans:bac#a8443a", (4.0, 5.5), ["garage:1:#2a2a2a"]),
    5: B("Garages", "bardage#8a8070", "2pans:bac#7a7068", (4.0, 5.0), ["garage:3:#5a3a2a"]),
}
