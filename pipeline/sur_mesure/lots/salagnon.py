"""Fiches des bâtiments non résidentiels de Salagnon (une photo Street View chacun, 13/10/2026)."""
S = dict(skip=True)
def B(nom, mur, toit="plat", h=(6.0, 6.0), o=(), **k):
    return dict(nom=nom, mur=mur, toit=toit, h=h, o=list(o), **k)
FICHES = {
    0: S, 6: S, 10: S,
    1: B("Grange", "enduit#e8e4dc", "2pans:tuile", (4.0, 6.0)),
    2: B("Grange", "enduit#d8d4cc", "2pans:tuile", (4.0, 6.0), ["garage:1:#7a6a58"]),
    3: B("Bar Le Relais", "enduit#ecebe6", "2pans:tuile", (6.0, 8.0), ["fen:2:3.6-4.6", "ens:BAR:#ecebe6:#c02a2a"],
         brut={"extras": [{"t": "store", "face": "NE", "x": [0.1, 0.5], "y": 2.6, "p": 1.4, "c": "#a82a2a"}]}),
    4: B("Église", "pierre#a89070", "2pans:tuile", (9.0, 13.0), ["ogive:1:2.6-6.0", "porte:0.5"]),
    5: B("École", "enduit#ecebe6", "2pans:tuile", (4.0, 6.0), ["fen:2:3.0-4.0"]),
    7: B("Salle des fêtes", "enduit#e8b878", "2pans:tuile", (4.0, 6.0), ["fen:4", "porte:0.5"]),
    8: B("Mairie", "enduit#ecdcc0", "4pans:tuile", (8.0, 10.0), ["fenv:4:1.0-2.4", "fenv:4:4.0-5.4"]),
    9: B("Bâtiment", "bardage#5a5e64", "2pans:bac#5a5e64", (4.0, 6.0), ["porte:0.6"]),
}
