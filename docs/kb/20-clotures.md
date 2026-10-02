---
id: clotures-bourg
titre: Clôtures, murets, haies et portails du bourg
tags: [clôtures, murets, haies, portails, cadastre, street view, prepare_quartier]
sources: [tools/prepare_quartier.py, tools/clotures_bourg.json, tools/fetch_cadastre.py]
---
# Clôtures du bourg (v0.9)

- `fetch_cadastre.py` couvre tout le bourg (499 parcelles, WFS paginé). `prepare_quartier` : FENCE_ZONE (bourg entier)
  pour clôtures, haies, portails et sols ; ZONE (rue du Balcon) seulement pour caniveaux et accotements enrobés.
  Centre du village exclu (murs faits main dans center.py).
- Côté rue : limite à moins de 5 m de la chaussée, une seule parcelle habitée (l'autre peut être une voie ou un chemin).
- `clotures_bourg.json` : 171 façades relevées à la main sur Street View (clé = bâtiment BD TOPO) :
  front = haieT (thuyas) / haieL (lauriers) / haieP (photinias) / muret / muret_grille / muret_rigide / mur / occult
  (panneaux occultants) / lisses / bois / grillage / rien ; mur = creme / gris / blanc / rose / pierre ; grille = couleur ;
  portail = fer / bois / plein_blanc / plein_gris / barreaux_blanc. 154 parcelles reliées.
- Le relevé prime : façade « rien » sans clôture, haies vues d'avion supprimées le long des façades relevées sans haie.
