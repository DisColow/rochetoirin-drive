# Consignes du projet

- Après chaque livraison (modification du jeu, nouvel APK), **mettre à jour ce dépôt systématiquement** :
  commit + push sur `main`, sans demander de confirmation (on peut revenir en arrière avec git).
- Publier l'APK de release dans `releases/RochetoirinSimulator-vX.Y.apk` (version incrémentée) et mettre à jour
  le lien « Télécharger » du README. Les captures d'écran / comparatifs vont dans `docs/apercus/`.
- Avant de livrer : `./gradlew testDebugUnitTest` puis `./gradlew assembleRelease`.
- Les données brutes (`tools/data/`) ne sont pas versionnées : elles se régénèrent avec les scripts `tools/fetch_*`.
- **Quota Google Street View** : avant tout appel à l'API, récupérer le cache privé
  `DisColow/rochetoirin-streetview` (copier `streetview/` dans `tools/data/streetview/`) ; après tout nouveau
  téléchargement, y pousser les nouvelles images. Ce dépôt reste privé (images Google non redistribuables).
- **La logique prime sur la donnée brute** (cf. `docs/kb/21-coherence.md`) : rien sur les routes/trottoirs, clôtures et
  haies continues, pas de routes superposées, pas de taches ni de piscines absurdes. `python3 tools/check_coherence.py`
  doit rapporter 0 violation avant de livrer.

## Branche `godot` (refonte, depuis le 4 octobre 2026)

- Moteur **Godot 4.4.1** (`godot/`) + **Terrain3D 1.0.2**, rendu **Compatibility (OpenGL ES 3)** : le rendu Vulkan
  plante avec Terrain3D sur le Vulkan logiciel du conteneur, impossible à vérifier ; Compatibility est vérifiable ici.
- Données : `pipeline/` (Python) -> `godot/world`, `godot/terrain`, `godot/assets` (générés, non versionnés).
  Ordre : `routes_plan.py`, `fetch_dem.py`, `fetch_ortho.py`, `fetch_polyhaven.py`, `build_roads.py`,
  `prepare_terrain.py`, `build_assets.py`, `convert_car.py`, puis `godot --headless --import` et
  `godot --headless --script res://tools/import_terrain.gd`.
- Étapes validées une par une, **un APK à chaque étape** : 1 routes + relief + horizon, 2 signalisation et marquages,
  3 bâtiments génériques (modèles 3D réalistes, tailles réelles, variés), 4 bâtiments emblématiques, 5 végétation
  (densité réglable), 6 textures et finitions.
- L'APK (> 100 Mo) va dans `releases/` via **Git LFS** (`.gitattributes`) ; les GitHub Releases sont interdites à cette
  session. Lien : `https://github.com/DisColow/rochetoirin-drive/raw/godot/releases/<apk>`.
- Captures de contrôle : `xvfb-run godot --path godot -- --shots=<json>` ; essai de conduite : `-- --drive-test`.
- **Jeu sans friction** : rien ne doit gêner le joueur (démarrage direct, remise sur la route automatique, commandes
  souples, pas d'à-coups de chargement).
