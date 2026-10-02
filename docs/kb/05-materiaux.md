---
id: materiaux
titre: Matériaux des props (vMat)
tags: [shader, matériaux, props, PROPS_FS]
sources: [render/Shaders.kt, tools/prepare_decor.py, tools/center.py, tools/prepare_quartier.py]
---
# Matériaux (partie entière de `mat`, la fraction = graine/variante)

0 uni, 1 mur (fenêtres, volets : couleur volet = SHUT[int(graine*6)]), 2 mur industriel, 3 tuiles, 4 bac acier,
5 toit plat, 6 eau, 7 pierre d'église, 8 acier, 9 câble, 10 verre, 11 ruisseau, 12 pavé/trottoir, 13 bordure,
14 herbe, 15 panneau (atlas 1024², 8×8 cases), 16 lumière, 17 moellons, 18 crépi, 19 haie, 20 gravier,
21 clôture ajourée (vMat.y : 0 grillage, 1 barreaux, 2 lisses ; tramée au loin).

Volets SHUT : 0 bois brun, 1 blanc, 2 gris, 3 bleu-gris, 4 vert, 5 bordeaux. Graine pour un volet k : (k + 0.5) / 6.
`extra` des murs = étages * 1000 (+ décalages) ; voir `building_mesh` / `gable_roof` dans prepare_decor.py.
