---
id: proprietes
titre: Propriétés redessinées une par une (rue du Balcon) d'après la photo aérienne puis Street View
tags: [propriété, maison, rue du balcon, photo aérienne, orthophoto, ign, street view, contour, haie, portail, allée, validation]
sources: [tools/proprietes.py, tools/proprietes/*.json, tools/fetch_ortho_hd.py, tools/fetch_sv_views.py, tools/prepare_decor.py, tools/prepare_quartier.py, tools/archi.py]
---
# Propriétés redessinées (v0.14)

Demande : refaire la rue du Balcon **maison par maison**, d'après la **photo aérienne** (pas le cadastre), puis
Street View pour affiner ; **une maison à la fois, validée par l'utilisateur** avant la suivante.

## Sources
- `tools/fetch_ortho_hd.py` : IGN 2021 (été, ombres courtes : la plus lisible) et 2024 (soleil rasant : sert à
  confirmer murets et allées), rééchantillonnées à 10 cm -> `data/ortho_hd_<année>.jpg`. Les deux millésimes sont
  calés à 0,5 m près ; le contour BD TOPO des maisons colle au toit (à ~1 m) ; **le cadastre est décalé de 1,5 à 3 m**
  des limites réelles (murets, haies) : ne pas s'en servir pour les clôtures.
- Pas de vue satellite Google (clé limitée à Street View : 403).
- `tools/fetch_sv_views.py` : vues ciblées (maison, portail) depuis les panoramas connus (`rues/index.json`), cap
  calculé vers une cible, fov, tangage ; cache privé d'abord, pousser après.
- Adresses : api-adresse.data.gouv.fr (`N rue du balcon 38110 rochetoirin`) : 2, 5, 8, 9, 10, 11, 12, 13, 14, 15, 16
  (pairs au nord).

## Relevé
Planche `gridcrop.py` (grille 1 m / 5 m en coordonnées locales) sur 2021 et 2024, superposition cadastre / BD TOPO ;
lecture des positions au mètre. Hauteurs et distances sur Street View : élévation angulaire depuis la caméra (2,5 m).
Ex. n° 2 : le pied du pignon est 1,9 m sous la rue (descente de garage), invisible sur le terrain du jeu (maille 10 m).

## Format `tools/proprietes/<id>.json`
`contour` (limites visibles), `batiments` (cleabs, toit, egout au-dessus du sol le plus haut, pente, couleurs mur /
tuile / volets, `facades` = [{cam, spec}] avec les jetons d'`archi.openings`, dont `H` = porte de garage à deux
battants en bois), `portails` (a, b, type, couleur, piliers, portillon, boîte), `clotures` (muret_grillage,
muret_haie, haie, grillage, muret), `sols` (paves, gravier, beton, enrobe, terrasse), `arbres` (leyland, cypres,
epicea, boule, fruitier, feuillu, laurier), `objets` (puits), `voitures`.

## Intégration
- `proprietes.zone()` : dans le contour, plus rien d'automatique (morceaux de clôture du cadastre, haies tracées
  d'après la photo, portails, voitures, cours, piscines, arbres détectés ou semés) ; sol = jardin.
- Maison : `prepare_decor` applique la description (hauteur, pente, couleurs, plusieurs façades percées, fenêtres
  procédurales coupées sur ces façades : `building_mesh(street=[cams])`).
- `proprietes.build` (appelé en fin de `prepare_quartier.build`) : clôtures, portails, sols (maillages drapés),
  puits, voitures, obstacles ; sols durs ajoutés au masque de l'herbe 3D.
- Contrôle : `propcmp.sh <id> <préfixe des vues> cx cz demi-largeur` (scratchpad) -> planche aérienne IGN / jeu et
  planche Street View / jeu.
