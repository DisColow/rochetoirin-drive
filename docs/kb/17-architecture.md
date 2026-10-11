---
id: architecture-bourg
titre: Architecture des maisons du bourg relevée sur Street View
tags: [architecture, maisons, toits, garages, fenêtres, volets, portes, ouvertures, façade, street view, archi, bourg]
sources: [tools/archi.py, tools/archi_bourg.json, tools/facades_ouvertures.json, tools/prepare_decor.py, tools/prepare_facades.py]
---
# Architecture (v0.7)

- `tools/archi_bourg.json` : 127 maisons annotées à la main d'après les 198 vues Street View (planches contact) :
  toit "2"/"4"/"p", niv, ss (garage en sous-sol), gar, bal, esc, auv, chem, comb, solaire, vieux, pierre, pise, grange, bois,
  cam (position de la caméra = côté rue).
- `archi.plan` : hauteur des murs par niveaux, toit à deux pans si emprise rectangulaire, matériau (moellons, pisé en crépi
  terre, bois). `archi.roof_height` : pente (combles = toit raide).
- `archi.extras` sur la façade tournée vers la caméra (`street_edge`) : portes de garage centrées (au sol local, maisons
  en pente), escalier extérieur, auvent (pan de tuiles, sur consoles au-dessus du garage ou sur poteaux), balcon à
  garde-corps, cheminée, panneaux solaires (pan sud des toits à deux pans).
- Maisons du bourg non relevées : ~45 % de toits à deux pans (répartition observée).
- Couleur des tuiles mesurée sur Street View (`prepare_facades.roof_color`, pixels chauds au-dessus de la façade), sinon
  orthophoto. Constat : maisons de plain-pied à croupes dans les lotissements, R+1 sur garage enterré, granges en pisé.

## Ouvertures de la façade sur rue (v0.12)

- `tools/facades_ouvertures.json` (clé cleabs) : relevé à la main des 129 maisons de `archi_bourg.json`, de gauche à
  droite vu de la rue, niveaux séparés par `|` (rez-de-chaussée d'abord ; pour une maison sur sous-sol, le
  rez-de-chaussée est le niveau des garages). Jetons : `V` fenêtre à volets battants, `R` volet roulant, `P`
  porte-fenêtre à volets, `B` baie vitrée alu, `D` porte d'entrée, `G` garage sectionnel, `N` porte de grange en
  planches, `O` petite fenêtre, `_` trumeau plein. Exemple : `"G V D | V V"`. Une façade `"_"` = pignon aveugle.
- `building_mesh(..., street=cam)` repère l'arête de rue (`archi.street_edge`, renvoie aussi l'indice) et y coupe les
  fenêtres procédurales du shader (halfZ = 0) ; les autres murs les gardent.
- `archi.openings` pose les ouvertures en relief (boîtes) : vitrage `M_GLASS`, dormant blanc (bois si maison
  ancienne, alu pour les baies), appui, volets ouverts couleur SHUT[] de la maison, coffre + tablier à moitié baissé,
  porte avec imposte vitrée et marche, garage à rainures, porte de grange à planches. Répartition « space-evenly »
  sur la longueur (emprises réduites jusqu'à 55 % si la façade est courte) ; étage dans le triangle du pignon si
  l'arête de rue est un pignon, sinon ignoré s'il dépasse le mur.
- Piège : l'anneau est CCW, donc vue de la rue l'arête A→B va de **droite à gauche** ; les jetons sont inversés.
- Les jetons `G`/`N` remplacent l'attribut `gar` ; l'auvent et l'escalier extérieur se calent sur ces portes / la
  porte `D`.
- Maison relevée sans teinte mesurée : murs « briques »/« bois » de la BD TOPO traités en enduit (rendu réel du bourg).
