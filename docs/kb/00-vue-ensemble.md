---
id: vue-ensemble
titre: Vue d'ensemble du projet Rochetoirin Simulator
tags: [projet, android, objectif, zone]
sources: [README.md, CLAUDE.md]
---
# Vue d'ensemble

Jeu Android (Kotlin, OpenGL ES 3.0, minSdk 24, targetSdk 34) façon Euro Truck Simulator, en **Renault Espace IV rouge**,
centré sur **Rochetoirin (Isère, 38110)** : relief IGN, routes OpenStreetMap, bâtiments BD TOPO, orthophoto, cadastre,
Street View. Gameplay : livraisons (offres, chargement, trajet guidé par GPS, déchargement, paiement).

- Paquet : `fr.rochetoirin.sim` ; dépôt GitHub `DisColow/rochetoirin-drive` (branche `main`).
- Zone détaillée : bourg de Rochetoirin, quartier de la rue du Balcon (maison d'enfance du propriétaire au 12),
  La Tour-du-Pin / Saint-Jean-de-Soudain ; panorama lointain jusqu'aux Alpes.
- Les assets du jeu (`app/src/main/assets/`) sont **générés** par les scripts Python de `tools/`.
- Données brutes dans `tools/data/` : **non versionnées**, régénérables avec `tools/fetch_*`.
