---
id: routes
titre: Routes : rubans, carrefours, doubles chaussées
tags: [routes, osm, carrefours, prepare_data, hauteur]
sources: [tools/prepare_data.py]
---
# Routes (`prepare_data.py`)

- Voies OSM découpées à la zone, densifiées (4 m), coins lissés ; largeur selon la classe et `lanes`.
- Rubans : 3 colonnes par rangée (VX/VY/VZ : bord gauche, axe, bord droit), soulevés au-dessus du terrain (CLEAR),
  terrain « creusé » sous la chaussée. Rangées sauvées dans `data/road_rows.pkl` pour les autres scripts.
- **Disques de carrefour** (style +10) aux extrémités partagées et dans les virages serrés.
- `merge_dual_carriageways` : fusion des chaussées séparées **seulement** pour les classes non résidentielles de même nom
  (sinon la mairie de La Tour-du-Pin devenait inaccessible).
- Harmonisation des hauteurs aux carrefours (pas de marche entre deux voies).
- Physique : `World.groundHeight` = terrain + 0,07 sur la chaussée + `surf` + tabliers de ponts.
