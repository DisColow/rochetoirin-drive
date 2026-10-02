---
id: arbres-imposteurs
titre: Arbres procéduraux et imposteurs de modèles 3D
tags: [arbres, imposteurs, poly haven, cc0, TreeRenderer, végétation]
sources: [render/TreeRenderer.kt, render/Shaders.kt, tools/prepare_village.py, tools/arbres/]
---
# Arbres

**Types** (trees.bin, champ type) : 0 chêne/feuillu, 1 buisson, 2 peuplier, 3 résineux, 4 fruitier, 5 arbuste ;
**6-13 imposteurs** : 6 + modèle (0 island_tree_01, 1 island_tree_02, 2 island_tree_03, 3 tree_small_02,
4-5 searsia_lucida a/e = arbustes et haies libres, 6-7 fir_tree_01 a/b = résineux) ;
la partie fractionnaire = (rayon du houppier / hauteur) / 2 (largeur du panneau).

- Procéduraux (`TREE_VS/FS`) : grappes de touffes (LUMPS_HI 9 / LUMPS_LO 5) + cartes de feuilles, tronc ;
  LOD < 130 m fin, < 380 m simplifié, puis panneau `BILLBOARD` jusqu'à 3,2 km.
- **Imposteurs** (bourg de Rochetoirin, feuillus vus sur l'orthophoto) : modèles Poly Haven CC0 photographiés
  sous 8 angles (`tools/arbres/bake.html` + `bake.js`, three.js dans Chromium headless) -> `assemble.py` ->
  atlas `trees_imp_col.webp` (couleur sRGB + couverture) et `trees_imp_nrm.webp` (normale modèle + profondeur),
  `trees_imp.json` (S, H, R par modèle). Shader `IMP_VS/FS` : panneau vertical face caméra, choix et fondu des deux
  vues voisines, normale tournée par le lacet aléatoire, éclairage soleil + ombres, profondeur pour l'auto-ombrage.
  Ombre portée : même panneau orienté vers le soleil (`uDirMode`=1).
- Atlas 2048² : 8 lignes (modèles) × 8 vues, cellules 256 px. Variante isolée d'un fichier : `modèle:nœud` (ex.
  `fir_tree_01:fir_tree_01_a_LOD0`), dossier `out/modèle__nœud`. Opacité des feuilles : cartes `*_alpha_1k.png`
  téléchargées à part par `dl.py` (`alpha.json`).
- **Haies taillées** (matériau 19) : texture `hedge_leaves.png` cuite par `hedge.js` (copies de searsia_lucida_a sur une
  grille périodique, raccord sans couture, 2,28 × 1,78 m), échantillonnée en uv métriques dans PROPS_FS.
- Collisions : `Decor` mappe 6-7 chêne, 8-9 fruitier, 10-11 buisson, 12-13 résineux.
- Régénérer : `python3 tools/arbres/dl.py <modèles>` puis `node bake.js <modèles>` puis `python3 assemble.py`
  (variable TREE_WORK = dossier de travail).
