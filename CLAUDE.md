# Consignes du projet

- **Issues GitHub** : quand l'utilisateur demande de faire des choses, lire les issues ouvertes de
  `DisColow/rochetoirin-drive` (`curl -s https://api.github.com/repos/DisColow/rochetoirin-drive/issues?state=open`)
  et les ajouter à la liste des tâches ; poser des questions si une issue n'est pas claire.
- **Notification à la fin de chaque tour** : quand le travail est fini et que c'est à l'utilisateur d'écrire, lui
  envoyer une notification (outil PushNotification, message court en français : ce qui est prêt / ce qu'on attend de lui).
- Après chaque livraison (modification du jeu, nouvel APK), **mettre à jour ce dépôt systématiquement** :
  commit + push sur `main`, sans demander de confirmation (on peut revenir en arrière avec git).
- **L'APK est construit par GitHub Actions** (`.github/workflows/apk.yml`), jamais ici (ça consomme le temps de
  l'utilisateur) : à chaque push sur `godot` touchant `godot/`, l'action prend le projet + la branche `donnees`
  (fichiers générés par `pipeline/`), exporte, signe (secret `ANDROID_KEYSTORE`) et dépose
  `releases/RochetoirinSimulator-vX.Y.apk` (X.Y = `config/version` de `godot/project.godot`, à incrémenter avec
  `version/code` d'`export_presets.cfg` à chaque livraison). Après toute régénération de données :
  `pipeline/publier_donnees.sh` (n'envoie que les fichiers modifiés) **avant** de pousser le code. Mettre à jour le
  lien « Télécharger » du README ; captures et comparatifs dans `docs/apercus/`.
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
  Ordre : `routes_plan.py` (zone : couloirs et communes ; Rochetoirin, Saint-Chef et Bourgoin-Jallieu entières, d'après
  `data/communes.json` de `fetch_communes.py`), `fetch_dem.py` (relief : MNT LiDAR HD 1 m moyenné à 2 m ; jamais RGE ALTI brut, servi en marches d'escalier), `fetch_ortho.py`, `fetch_polyhaven.py`, `fetch_buildings.py` (bâtiments +
  ralentisseurs), `fetch_vegetation.py` (LiDAR HD MNH, zones de végétation, haies, RPG), `fetch_parking.py` (parkings OSM), `build_roads.py`
  (autoroutes : `autoroute_geom.py` — tracé, profil, terre-plein, voies auxiliaires, marquages ; parkings :
  `parking.py` — enrobé nivelé, places, marquage, `data/parkings.pkl` pour les clôtures et les voitures garées),
  `prepare_terrain.py`, `build_assets.py`, `build_espace.py` (voiture : Espace I procédural), `fetch_communes.py`, `build_map.py`, `fetch_landmarks.py`,
  `fetch_sv_landmarks.py` (cache Street View privé d'abord), `fetch_building_tex.py`, `build_bld_tex.py`,
  `build_buildings.py`, `build_gps.py`, `fetch_trees.py` (Sketchfab, SKETCHFAB_TOKEN), `fetch_cadastre.py`, `build_fence_tex.py`,
  `build_fences.py` (clôtures : relevé `clotures_bourg.json` ; contrôle « rien sur la route » doit donner 0),
  `fetch_water.py`, `build_water.py` (eau ; à lancer avant `prepare_terrain.py`, qui creuse le terrain dessous),
  `build_ground.py` (carte de l'herbe, après `prepare_terrain.py` ; les ombres douces du terrain viennent de son
  `ao_region`), `build_grass_tex.py`, `build_zone.py` (limite de la carte pour le gardien), `fetch_ufo.py` + `blender_ufo.py` (soucoupe du gardien),
  `build_sfx.py` (sons de synthèse), `fetch_power.py`, `build_poles.py` (pylônes, poteaux, fils, lampadaires), `build_cockpit.py` (vue cockpit en pixel art), `build_props.py`
  (voitures garées, poubelles, tracteurs ; après `build_fences.py`, qui fournit les portails ; voitures : modèles
  Sketchfab de `fetch_voitures.py` + `blender_voitures.py`, sans logo de vraie marque), `fetch_shops.py`,
  `fetch_sv_shops.py` (photos Street View des devantures, cache privé `streetview/shops`), `build_shops.py` (commerces
  d'après les fiches relevées à la main sur ces photos, `sources/shops_sv.txt`, sinon selon le métier ; marques parodiées ;
  enseignes sur trois pages d'atlas), `fetch_ortho_hd.py` (orthophoto 0,5 m) + `build_pools.py` (piscines des jardins ;
  avant `build_ground.py` et `build_props.py`), `fetch_sport.py`, `build_sport.py`, `fetch_animaux.py` + `blender_animaux_import.py` (vache, mouton, cheval : modèles Sketchfab CC BY, crédits dans ⚙), `build_animaux.py` (prés pâturés
  et clôtures), `fetch_autoroute.py`, `build_autoroute.py`, `build_haie_tex.py` (feuilles des touffes de haie),
  `build_car_sprite_ia.py` (voiture en sprite d'après la planche de l'utilisateur `sources/espace_sprites.jpg` ;
  l'ancien `build_car_sprite.py` + `blender_sprite.py` reste possible) ; sons enregistrés dans `pipeline/sources/` ;
  modèles Blender (module bpy dans un venv) : `blender_commerces.py`, `blender_sport.py`, `blender_animaux.py`,
  `blender_autoroute.py`, `blender_sprite.py` (384 vues de l'Espace, ~45 min), `blender_haies.py` (touffes),
  `blender_maisons.py` (kit de détails des maisons, posé par `build_buildings.py`) ; puis
  `godot --headless --import`, `godot --headless --script res://tools/prepare_trees.gd`, `godot --headless --import`,
  `xvfb-run godot --path godot res://tools/bake_impostors.tscn`, `impostor_bleed.py`, `build_crop_tex.py`,
  `build_vegetation.py`, `build_crops.py`, `godot --headless --import` et
  `godot --headless --script res://tools/import_terrain.gd`.
- Relief : shader Terrain3D remplacé par `godot/scripts/terrain.gdshader` (code généré par Terrain3D, récupéré avec
  `xvfb-run godot --path godot --script res://tools/dump_terrain_shader.gd`, + ombres des nuages et sol mouillé) ; à
  régénérer si on change les réglages du matériau du relief. Ambiance commune des shaders : `scripts/env.gdshaderinc`
  (paramètres `wind`, `clouds`, `wet` de chaque matériau, tenus à jour par `scripts/env.gd` : **jamais de paramètres
  globaux de shader**, ils faisaient planter le jeu au démarrage sur le téléphone, v3.1 à v3.3).
- **Portées d'affichage** : le fondu de visibilité de Godot (`VISIBILITY_RANGE_FADE_SELF`) ne marche pas en
  Compatibility et supprime la marge anti-clignotement : ne pas l'utiliser. Objets posés par lots :
  `scripts/cells.gd` (MultiMesh par cases de 64 m, matériaux effacés en fondu tramé jusqu'à la portée via
  `fade_far`/`env_fade_keep` d'`env.gdshaderinc`, position de caméra `env_cam` tenue à jour par `env.gd`).
- **Orientation des faces** : `glb.write_glb(..., fix_winding=True)` remet chaque triangle dans le sens de ses normales
  (tuiles de routes) ; contrôle : `python3 pipeline/check_winding.py godot/world/roads` doit donner 0 % partout.
- **Rien ne déborde sur la route** (arbres : couronne hors chaussée, champs arrêtés avant, bâtiments découpés).
- Essais : `-- --drive-test [--long] [--drive-from=x,y,z,cap] [--hard-steer] [--flip-test] [--reverse-test]`, `-- --mem-test`, captures
  `--shots=` (types : caméra, `map`, `tp`, `tap` = vrai toucher sur la carte, `cam` = vue de jeu + charge de rendu).
- Étapes validées une par une, **un APK à chaque étape** : 1 routes + relief + horizon, 2 signalisation et marquages,
  3 bâtiments génériques (modèles 3D réalistes, tailles réelles, variés), 4 bâtiments emblématiques, 5 végétation
  (densité réglable), 6 textures et finitions. Étape ajoutée, faite en v2.5 : clôtures, haies, murets et portails.
- **Releases GitHub** : à chaque nouvelle version, les actions créent la release « vX.Y » (notes = section « Nouveautés
  de la vX.Y » du README, `.github/scripts/notes_release.py`) et y joignent l'APK (`apk.yml`) puis les versions Windows
  et Steam Deck (`desktop.yml`, déclenchée par une modification de `godot/project.godot`, donc à chaque nouvelle version,
  ou à la demande) : écrire la section « Nouveautés » du README **avant** de pousser la version.
- L'APK (> 100 Mo) va aussi dans `releases/` via **Git LFS** (premier build de chaque version seulement) (`.gitattributes`) ; les GitHub Releases sont interdites à cette
  session. Lien : `https://github.com/DisColow/rochetoirin-drive/raw/godot/releases/<apk>`.
- Rendu Mobile (Vulkan) essayé en v2.8 : moins joli que Compatibility sur le téléphone de l'utilisateur, abandonné.
- Captures de contrôle : `xvfb-run godot --path godot -- --shots=<json>` ; essai de conduite : `-- --drive-test`.
- Gardien des limites (`scripts/guardian.gd`) : soucoupe volante « UFO » de sebslom (Sketchfab, CC BY 4.0 ;
  `fetch_ufo.py` + `blender_ufo.py` -> `assets/ufo/ufo.glb`), rayon tracteur qui ramène la voiture sur la route
  (`car.carried`) ; essai : `-- --drive-test --void-test [--snap]`. Crédits dans ⚙ > Crédits (`hud.gd`, `CREDITS`) : y ajouter toute nouvelle ressource sous licence.
- **Modèles 3D : toujours privilégier les modèles gratuits trouvables en ligne** (Sketchfab CC BY/CC0 via
  SKETCHFAB_TOKEN, Poly Haven, Kenney, Quaternius…, crédités dans ⚙ > Crédits) plutôt que de modéliser soi-même ; ne
  modéliser (Blender, procédural) qu'à défaut de modèle convenable.
- **Jeu sans friction** : rien ne doit gêner le joueur (démarrage direct, remise sur la route automatique, commandes
  souples, pas d'à-coups de chargement).
