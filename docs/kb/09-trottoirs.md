---
id: trottoirs
titre: Trottoirs, angles de carrefour, îlots (sidewalks.py)
tags: [trottoirs, bordures, carrefours, îlots, franchissable, sidewalks]
sources: [tools/sidewalks.py, tools/prepare_street.py, tools/center.py]
---
# Trottoirs (v0.6)

- Chaque côté de rue éligible (classes résidentielles à primaires, zone bâtie ou tag OSM `sidewalk`, pas dans le
  quartier de la rue du Balcon) reçoit une bande de **1,6 m** posée à cheval sur le bord de chaussée.
- Union des bandes **moins** l'emprise de l'enrobé `carriageway()` (rubans + disques, légèrement sous-estimée pour ne
  jamais laisser de jour) **arrondie** aux carrefours (fermeture morphologique R = 3 m) **moins** les bâtiments ;
  ouverture/fermeture 0,3 m pour supprimer les lanières ; simplification 6 cm.
- Maillage `raised_mesh` : dessus triangulé (earcut, pas 8 m), bordure côté chaussée + bande claire de 16 cm,
  retombée vers le terrain côté jardins ; découpé par tuiles CHUNK.
- Angles arrondis entre chaussée réelle et emprise arrondie : **enrobé** en décalcomanie (style route +10).
- **Bordures basses 10 cm, aucune collision** ; physique via `surf_shape` (hauteur réelle - terrain, en cm).
  Îlots de rond-point et du parking de la rue de Ravette : même principe (seul le massif central des ronds-points bloque).
- Test : `SimulationTest.climbsSidewalk`.
