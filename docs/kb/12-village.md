---
id: village
titre: Bourg de Rochetoirin : orthophoto, centre, rue du Balcon, façades
tags: [rochetoirin, village, orthophoto, centre, rue du balcon, street view, façades]
sources: [tools/prepare_village.py, tools/center.py, tools/prepare_quartier.py, tools/prepare_facades.py]
---
# Bourg

- `prepare_village.Village` (orthophoto IGN 20 cm) : couleurs de toits, arbres réels (houppiers détectés, suppression des
  voisins), piscines, classes de sol (jardin, cour, prairie, forêt).
- `center.py` : centre fait main d'après Street View (avril 2023) : église Saint-Étienne, place, mairie-médiathèque,
  salle des fêtes, boulangerie, restaurant « Le Rochetoirin », parking rue de Ravette (îlots plantés), cimetière.
  `center.override(poly, props)` remplace un bâtiment (ou "skip").
- `prepare_quartier.py` (rue du Balcon) : parcelles cadastrales, haies sur limites, grillages, murets, clôtures,
  portails, caniveaux, gravier/béton/enrobé d'après l'orthophoto, voitures garées, lampadaires, toits à deux pans.
- `prepare_facades.py` : couleur réelle d'enduit et de volets par maison (`data/facades.json`) mesurée sur 198 vues
  Street View (projection de l'emprise BD TOPO dans l'image) ; ~100 maisons retenues après filtres qualité.
