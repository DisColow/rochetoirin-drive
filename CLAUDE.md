# Consignes du projet

- **Issues GitHub** : quand l'utilisateur demande de faire des choses, lire les issues ouvertes de
  `DisColow/rochetoirin-drive` (`curl -s https://api.github.com/repos/DisColow/rochetoirin-drive/issues?state=open`)
  et les ajouter à la liste des tâches ; poser des questions si une issue n'est pas claire.
- **Issues « pour-toi »** : chaque fois que l'utilisateur a quelque chose à faire de son côté (mesure ou essai sur le
  téléphone, secret à ajouter, choix à valider, vidéo à envoyer…), créer une issue GitHub étiquetée `pour-toi`,
  assignée à `DisColow`, en français : contexte en deux lignes, étapes numérotées, ce qu'on attend en retour. Ne pas
  créer de doublon (vérifier les issues ouvertes). Ces issues ne sont pas des tâches pour Claude : les relire pour
  traiter les réponses de l'utilisateur, puis les refermer quand l'action est faite (en le disant dans un commentaire).
- **API Claude (payante, crédit de l'utilisateur) : uniquement pour l'actualité du jour** (`actu.yml`, ~0,40 $/jour).
  Tout autre usage (génération ponctuelle de textes, essais…) **demande l'accord explicite de l'utilisateur avant**,
  avec le coût estimé ; ne jamais changer de méthode en cours de route sans le lui redemander. Les textes du jeu
  s'écrivent par Claude Code directement (pas par l'API). Les rebonds du 12/10 (`taxi_rebonds.py`, ~4,50 $) ont été
  générés par l'API sans cet accord : erreur à ne pas reproduire ; l'action `taxi_rebonds.yml` est en lancement
  manuel seulement.
- **Notification à la fin de chaque tour** : quand le travail est fini et que c'est à l'utilisateur d'écrire, lui
  envoyer une notification (outil PushNotification, message court en français : ce qui est prêt / ce qu'on attend de lui).
- Après chaque livraison (modification du jeu, nouvel APK), **mettre à jour ce dépôt systématiquement** :
  commit + push sur `main`, sans demander de confirmation (on peut revenir en arrière avec git).
- **L'APK est construit par GitHub Actions** (`.github/workflows/apk.yml`), jamais ici (ça consomme le temps de
  l'utilisateur) : à chaque push sur `godot` touchant `godot/`, l'action prend le projet + la branche `donnees`
  (fichiers générés par `pipeline/`), exporte, signe (secret `ANDROID_KEYSTORE`) et dépose
  `releases/RochetoirinSimulator-vX.Y.apk` (X.Y = `config/version` de `godot/project.godot`, à incrémenter avec
  `version/code` d'`export_presets.cfg` **à chaque livraison : APK complet à chaque version depuis la v6.13**). Après toute régénération de données :
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
  `prepare_terrain.py`, `build_assets.py`, `fetch_ranger.py` + `blender_ranger.py` (voiture du joueur depuis la v5.9 : Ford Ranger Raptor noir, benne ouverte depuis la v6.3 ; performances dans `car.gd` (Raptor « préparé » à la demande du joueur : 2 400 kg, 4x4, 300 kW aux roues, 0-100 en ~5 s, 230 km/h ; son V6 essence, boîte auto 10 rapports dans `audio.gd`) ; `meta.json` : empattement, voies, rayon, boîte de collision, phares ; l'ancien `build_espace.py` n'est plus utilisé), `fetch_communes.py`, `build_map.py`, `fetch_landmarks.py`,
  `fetch_sv_landmarks.py` (cache Street View privé d'abord), `fetch_building_tex.py`, `build_bld_tex.py`,
  `build_buildings.py`, `build_gps.py`, `fetch_trees.py` (Sketchfab, SKETCHFAB_TOKEN), `fetch_cadastre.py`, `build_fence_tex.py`,
  `build_fences.py` (clôtures : relevé `clotures_bourg.json` ; contrôle « rien sur la route » doit donner 0),
  `fetch_water.py`, `build_water.py` (eau ; à lancer avant `prepare_terrain.py`, qui creuse le terrain dessous),
  `build_ground.py` (carte de l'herbe, après `prepare_terrain.py` ; les ombres douces du terrain viennent de son
  `ao_region`), `build_grass_tex.py`, `build_zone.py` (limite de la carte pour le gardien), `fetch_ufo.py` + `blender_ufo.py` (soucoupe du gardien),
  `build_sfx.py` (sons de synthèse : pluie, bip), `build_ui.py` (interface pixel art, polices), `fetch_sons.py` + `build_sons.py` (sons d'après enregistrements réels : BigSoundBank / Joseph Sardin, CC0, et Kenney CC0 ; catalogue `SONS` de `build_sons.py`, boucles sans couture, Ogg), `build_ambiance.py` (carte sonore `world/ambiance.bin/json` : bâti, bois, eau, autoroute, points des ruisseaux, églises, troupeaux), `fetch_radio.py` (autoradio : Kevin MacLeod, CC BY 4.0), `fetch_power.py`, `build_poles.py` (pylônes, poteaux, fils, lampadaires ; modèle du lampadaire : `fetch_lampadaire.py` + `blender_lampadaire.py` -> `assets/props/lampadaire.glb`, « Street Lantern » CC BY 4.0, émission en mode multiplication pour n'allumer que les vitres), `build_cockpit.py` (vue cockpit en pixel art), `build_props.py`
  (voitures garées, poubelles, tracteurs ; après `build_fences.py`, qui fournit les portails ; voitures : modèles
  Sketchfab de `fetch_voitures.py` + `blender_voitures.py`, sans logo de vraie marque), `fetch_shops.py`, `fetch_cinemas.py` (cinémas OSM, posés par `build_shops.py` : marquise, affiches parodiques),
  `fetch_sv_shops.py` (photos Street View des devantures, cache privé `streetview/shops` ; structure des bâtiments relevée sur ces photos dans `sources/shops_bati.txt` — niveaux, toit, façade, volets — appliquée par `build_buildings.py`), `build_shops.py` (commerces
  d'après les fiches relevées à la main sur ces photos, `sources/shops_sv.txt`, sinon selon le métier ; marques parodiées ;
  enseignes sur trois pages d'atlas), `fetch_ortho_hd.py` (orthophoto 0,5 m) + `build_pools.py` (piscines des jardins ;
  avant `build_ground.py` et `build_props.py`), `fetch_sport.py`, `build_sport.py`, `fetch_animaux.py` + `blender_animaux_import.py` (vache, mouton, cheval : modèles Sketchfab CC BY, crédits dans ⚙), `build_animaux.py` (prés pâturés
  et clôtures), `fetch_autoroute.py`, `build_autoroute.py`, `build_haie_tex.py` (feuilles des touffes de haie),
  `blender_sprite.py` + `build_car_sprite.py` (option masquée depuis la v6.0 ; voiture en sprite pixel art : 384 vues rendues du modèle 3D de l'Espace, atlas sur deux pages, masques feux/vitres pour gouttes et essuie-glace arrière, ombre pixel art `ombre.png` ; l'ancien `build_car_sprite_ia.py` d'après la planche `sources/espace_sprites.jpg` n'est plus utilisé) ; sons enregistrés dans `pipeline/sources/` ;
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
- **Activités** (`scripts/activities.gd`, bouton ★ / touche T) : course (A, étapes, B posés sur la carte en mode
  choix `map.pick_mode`, portes lumineuses, chrono), chasse au lieu (même appareil ; lieu nommé, touché sur la carte
  ou au hasard ; zone `circle` qui rétrécit, dessinée par `map.gd` et `gps.gd` avec les repères `marks`), taxi
  (clients `assets/clients/` de `fetch_clients.py` + `blender_clients.py`, destinations `world/places.json` de
  `fetch_places.py` + `build_places.py` : lieux publics seulement). Essai : captures `{"act": "menu|course|chasse|taxi"}`. Pas de téléportation pendant une activité (`map.locked`, taxi compris) ; bouton « ■ Arrêter » dans le bandeau d'activité.
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
  `fetch_ufo.py` + `blender_ufo.py` -> `assets/ufo/ufo.glb`), invisible jusqu'à ce que la voiture tombe hors de la carte,
  rayon tracteur qui la ramène sur la route (`car.carried`), puis repart ; essai : `-- --drive-test --void-test --void-drop [--snap]`. Crédits dans ⚙ > Crédits (`hud.gd`, `CREDITS`) : y ajouter toute nouvelle ressource sous licence.
- **Éléments graphiques : modèles existants d'abord, au choix de l'utilisateur.** Pour tout élément graphique ajouté
  ou modifié (objets, mobilier, véhicules, personnages, végétation…) : 1) chercher d'abord des modèles 3D libres
  existants (Sketchfab CC BY/CC0 via SKETCHFAB_TOKEN, Poly Haven, Kenney, Quaternius, MakeHuman/MPFB…, crédités dans
  ⚙ > Crédits) ; 2) **proposer plusieurs candidats à l'utilisateur sur une planche JPEG** (même éclairage, échelle
  humaine) et attendre son choix ; 3) ne modéliser soi-même (Blender, procédural) qu'à défaut de modèle convenable.
- **Modèles d'après Street View : au pixel près.** Quand l'utilisateur demande de bâtir un modèle 3D d'après Street
  View, analyser le bâtiment avec précision sur les photos (plusieurs angles si possible) et le reproduire fidèlement
  dans le moindre détail : gabarit et proportions mesurés (largeur, profondeur, hauteur d'égout et de faîtage, pente et
  débords du toit), nombre, position, taille et forme exactes des ouvertures, menuiseries, volets, portes, balcons,
  cheminées, gouttières, enduit et couleurs relevés sur la photo, annexes et clôtures. Comparer ensuite une capture
  du jeu prise du même point de vue que la photo et corriger jusqu'à ce qu'elles se superposent. **Faire le tour du
  bâtiment** : récupérer un maximum de vues Street View (tous les panoramas proches, plusieurs caps et hauteurs) avant
  de relever quoi que ce soit ; l'architecture doit être strictement identique (formes, nombre et place des fenêtres
  et portes, annexes). Une issue n'est refermée qu'avec l'accord de l'utilisateur, comparatif photo/jeu à l'appui.
- **Viser les canons du genre** : à chaque demande, s'inspirer des meilleures références du genre (jeux de conduite,
  simulateurs, jeux en pixel art…) pour la qualité du résultat et l'ingéniosité des solutions, dans les limites du
  moteur graphique et du téléphone ; chercher l'astuce qui donne un rendu de grand jeu plutôt que la solution minimale.
- **Son** (`scripts/audio.gd`) : bus « Voiture » et « Monde » (passe-bas : vue conducteur étouffée), moteur à boucles
  par régime (`assets/sfx/moteur.json` : fréquence d'allumage de chaque boucle ; régime = boîte 5 vitesses simulée),
  roulement selon `meta « surface »` des corps de collision des routes (`roads.gd`, un corps par matériau), ambiances
  d'après `world/ambiance.bin`, sons ponctuels positionnés ; autoradio `scripts/radio.gd` (bus « Radio »). Essai :
  `-- --drive-test [--radio]` affiche régime, rapport, surface et ambiances dans le journal.
- **Interface** (`pipeline/build_ui.py` -> `assets/ui/`, thème du projet `assets/ui/theme.tres`, aide `scripts/ui.gd`) :
  planche de bord des années 80 en pixel art (boutons poussoirs avec témoin, bouton rouge « feux de détresse » pour la
  remise sur la route, cadres et touches des menus, police Pixelify Sans, afficheur LCD DSEG7 du compteur). Les
  commandes de conduite (◀ ▶ FREIN GAZ) restent des disques translucides. Toute nouvelle fenêtre : `UI.panel()`.
- **Taxi : conversations** (`scripts/taxi_talk.gd`, textes `data/taxi.json` générés par `pipeline/taxi_dialogues.py`,
  versionnés) : caractères aux goûts cachés, fils de trois échanges (le client parle, on répond sur un ton —
  chaleureux, drôle, curieux, sobre, ou silence —, puis il enchaîne : **pas de réplique d'appréciation** après notre réponse, demande de l'utilisateur, v6.6 ; son humeur évolue en silence).
  **Rebonds** (v6.12, demande de l'utilisateur) : le client rebondit sur ce qu'on vient de dire (répond à la question,
  renvoie la blague) **sans jamais juger la réponse**, au début de sa réplique suivante (même bulle, même lecture,
  séparateur `SEP` « ¦ ») ; au dernier nœud, le rebond clôt le fil. Deux rebonds par réponse : `ok` si le ton plaît
  au client (goût > 0), `ko` sinon (plus sec, toujours sur le fond), et `silence: {ok, ko}`. Format :
  `rep[ton] = {t, ok, ko}` (l'ancien format texte reste lu). Écrits par l'API Claude (`pipeline/taxi_rebonds.py`,
  action `taxi_rebonds.yml` -> branche `rebonds`), relus, versionnés dans `pipeline/sources/taxi_fils.json`, repris
  par `taxi_dialogues.py` ; l'actualité du matin (`actu.py`) les écrit aussi. **Plus de voix enregistrées** (choix de
  l'utilisateur, v6.12) : voix du téléphone, sinon texte seul. Jauge d'humeur (plus d'indicateurs ♥ / • / ✗ depuis la v6.2), indices
  (allure du client, préférences apprises en lui posant des questions avec le bouton « bulle »), pourboire selon la
  satisfaction. **Voix du téléphone** (depuis la v6.8, demande de l'utilisateur, `scripts/voix_tel.gd`) : synthèse
  vocale du système (`DisplayServer.tts_*`, réglage `audio/general/text_to_speech` déjà actif) ; voix française
  d'homme ou de femme selon le client (table `CONNUES` des voix Google/Samsung/Windows + mots du nom ; sinon hauteur
  décalée), hauteur et débit propres à chaque client (`graine`), voix forcées dans ⚙ > Son (`voix_f`, `voix_m`). La
  réplique suivante attend la fin de la lecture (`_tts_busy` : rappel « fin », état « parle » retombé, durée estimée,
  filet de sécurité) : **le dialogue ne doit jamais pouvoir rester bloqué**. Pas d'effet talkie (le son ne passe pas
  par Godot). Sous Linux, un speech-dispatcher planté bloque Godot au démarrage (essais : tuer `speech-dispatcher`).
  **Voix enregistrées** (secours quand l'appareil n'a aucune voix française ; depuis la v6.2) : chaque réplique enregistrée par `pipeline/build_voix.py` (Piper hors ligne,
  voix Siwis et Gilles en plusieurs hauteurs ; répliques entières, sauf les 25 à variables : morceaux + valeurs), **effet talkie-walkie appliqué
  par ffmpeg dans les fichiers** (version « D » choisie par l'utilisateur : bande 450-2600 Hz, compression, saturation,
  grain, souffle), joués tels quels par le bus « Voix » sans aucun effet ni décalage de hauteur (en v6.0, ces effets
  en jeu rendaient les voix incompréhensibles ; en v6.1, synthèse vocale du système, abandonnée). Le dialogue n'avance
  qu'à la fin réelle du son (`_voice_busy()`). Toute nouvelle réplique : relancer `taxi_dialogues.py` puis
  `build_voix.py` (incrémental, venv avec piper-tts), puis `publier_donnees.sh`. La radio baisse quand quelqu'un parle.
- **Actualité du taxi** (v6.11, issue #6, `docs/plan_actualites.md`) : action `.github/workflows/actu.yml` chaque matin
  (6 h 50 à Paris, et à chaque modification de `pipeline/actu.py`) : titres des dernières 72 h (Le Dauphiné Libéré via
  Google Actualités — son flux RSS direct ne répond pas —, France Info), **pas de sport, aucun sujet exclu** (choix de
  l'utilisateur), météo Open-Meteo ; API Claude (`claude-opus-5-5`, sortie JSON contrainte par schéma, repli serveur
  `fallbacks: "default"`, secret `ANTHROPIC_API_KEY`) ; contrôles (3 nœuds, longueurs, accords `{masculin|féminin}`
  seulement) ; `actu.json` publié sur la branche `actu`. Jeu : `taxi_talk.gd` le télécharge au lancement
  (`user://actu.json`, valable 3 jours), **une conversation sur deux** sur l'actualité (`ACTU_PART`). Essai local :
  `python3 pipeline/actu.py --sans-ia` (titres et météo seulement).
- **Éditeur de monde** (`scripts/editeur_monde.gd`) : « Sésame, ouvre-toi » / « Hasta la vista, baby » dans le champ
  « Formule magique » (appui long sur le nom de la rue, F2, ou ⚙) ; on touche un objet, puis « Générer depuis Street
  View » ou une remarque -> issue GitHub pré-remplie (étiquette `editeur-monde` : position, GPS, objet, caméra, lien
  Street View, capture `--shots`). **Traiter ces issues comme des demandes de l'utilisateur.** Essai : capture
  `{"act": "editeur"}`.
- **Particules en Compatibility** : les matériaux « billboard » (y compris `BILLBOARD_PARTICLES`) et la transparence
  alpha ignorent la position, la taille et la couleur de chaque particule (CPUParticles3D), et `color_ramp` écrase la
  teinte : utiliser des maillages en volume (cubes, sphères basses), la transparence tramée `ALPHA_HASH` et
  `scale_amount_curve` pour le fondu. **Effets des roues depuis la v6.5** (`scripts/dust.gd` + `scripts/fumee.gdshader`,
  texture `assets/fx/fumee.png` de `pipeline/build_fumee_tex.py`) : système maison en MultiMesh (pas de CPUParticles) —
  panneau face caméra calculé dans le shader (`skip_vertex_transform`), taille/rotation/âge/opacité dans
  `INSTANCE_CUSTOM`, teinte dans `COLOR`, éclairage par le soleil d'après la normale de la texture, tri arrière→avant
  en GDScript, débris en volume avec rebond. **Ne pas utiliser `hint_depth_texture`** (soft particles) : tout le rendu
  3D devient noir en Compatibility. Essai visuel : `-- --fx-demo` (chaque roue émet une matière en continu).
- **Mises à jour incrémentales : DÉSACTIVÉES depuis la v6.13** (demande de l'utilisateur : impossible de tester ;
  `MAJ := false` dans `boot.gd`, étape « paquet » retirée d'`apk.yml`, catalogue de la branche `maj` vidé ; chaque
  version = APK complet, `version/code` + `config/version` montés à chaque livraison). Ancien fonctionnement, pour
  mémoire (depuis la v5.5) : `scenes/boot.tscn` (`scripts/boot.gd`, jamais mis à jour lui-même)
  écran de démarrage (depuis la v5.8) : lit le catalogue `raw.githubusercontent.com/…/maj/catalogue.json` (branche
  `maj`), télécharge le paquet de la base de l'APK installé avec barre de progression (bouton « Jouer sans attendre »),
  charge `user://maj/maj-X.Y.pck` puis lance `main.tscn` ; `scripts/maj.gd` ne fait plus que valider après 40 s
  (et télécharge en arrière-plan pour les APK d'avant la v5.8). Essai sur PC : `MAJ_ESSAI_BASE=<code> godot --path godot`. `apk.yml` : le premier build d'un `version/code` exporte la base (`--export-pack`, release `base-CODE`) ; les
  suivants exportent un paquet cumulatif (`--export-patch --patches base.pck`) joint à la release `vX.Y` et inscrit
  au catalogue. (Ancienne règle, caduque : ne changer `version/code` que si un APK complet était nécessaire (moteur Godot, permissions Android,
  `boot.gd`, réglages du projet).)
- **Éditeur de monde** : bâtiments refaits sur demande dans `pipeline/sources/bati_editeur.txt` (cleabs + relevé
  Street View, photos dans le cache privé `streetview/editeur/`), appliqués par `build_buildings.py`.
- **Performances** : `scripts/perf_monitor.gd` (images/s mesurées en temps réel — le delta de Godot est plafonné
  quand le jeu rame —, 1 % bas, à-coups > 50 ms, appels de dessin, coût de chaque système : chaque `_process` est
  enveloppé et chronométré par `PerfMon.note()` ; `[perf]` dans le journal ; relevé de 3 min depuis ⚙ envoyé en ticket
  GitHub « Performances »). Les temps `Performance.TIME_PROCESS` et `viewport_get_measured_render_time_*` sont faux en
  Compatibility : ne pas s'y fier. Réglage ⚙ > Performances (Économie, Équilibré, Élevée, Maximale, Auto ; `NIVEAUX` de
  `main.gd` : anticrénelage, ombres, seuil de détail `mesh_lod_threshold`, résolution 3D, distances d'affichage `VIEW`
  des systèmes, étalonnage ; végétation/herbe/cultures par leurs `LEVELS`) ; Auto = Équilibré puis ajusté toutes les
  30 s d'après les images/s. Tuiles des routes et bâtiments lues en arrière-plan (`scripts/chargeur.gd`), végétation
  préparée sur un fil de travail, shaders préchauffés sous le voile de démarrage (`_prechauffer`). Essai
  `--perf-breakdown` : coût de chaque système et réglage (ombres ≈ 1/3 des triangles) ; captures `{"niveau": 0-3}`.
- **Cultures écrasées** (v6.5, refait en v6.9 : issue #8, couchées à 90°) (`scripts/trample.gd`) : carte des passages
  de 96 m qui suit la voiture (256 px, R/V = sens, B = écrasement, A = ligne de l'atlas des cultures + 1 sur 8), peinte
  **seulement dans les champs** (`crops.field_at`), lue par `crops.gdshader` (`trample_tex`, `trample_zone`) au sommet
  ET au centre de chaque bande : les bandes basculent à plat autour de leur pied, perpendiculairement à la bande ; le
  dessus des céréales (nappe en carrés de 4 m : une trace passe entre ses sommets) est **découpé au pixel** dans la
  trace, et le relief (`terrain.gdshader` : `trample_tex`, `crops_albedo`) y dessine les tiges couchées dans le sens
  de la marche.
  Essais : `--trample-debug` (journal), `--trample-all` (tout couché) ; captures `{"cam": 0, "place": [x, y, z, cap]}`.
- **Mémoire vidéo** (image figée sur le téléphone : la 3D cesse d'être dessinée quand la mémoire vidéo sature, l'écran
  alterne alors entre les deux dernières images) : **toute texture de plus de 4 Mo doit être importée compressée**
  (`compress/mode=2`, sauf pixel art de `assets/ui` et `assets/cockpit`) ; le sprite de la voiture n'est chargé qu'à
  la demande (`car.set_sprite_mode`). Contrôle : `-- --mem-test` (mémoire vidéo, textures, tampons). **Le gel persiste
  en v6.7 (issue #4)** : témoin de rendu depuis la v6.10 (`crash_report.gd` : vignette 4 × 4 px relue toutes les 5 s de
  temps réel ; deux échecs -> `[figé]` dans le journal, `user://fige.txt`, bandeau « Image figée » au lancement
  suivant avec rapport) ; essai : `-- --fige-test` (simule l'arrêt du rendu). Attendre un rapport avant de corriger.
- **Décor destructible** (v6.9, issue #7, `scripts/casse.gd`) : panneaux de signalisation (positions
  `world/panneaux.bin` relevées dans les tuiles de routes par `pipeline/build_casse.py`), lampadaires (`poles.pieds`,
  `poles.casser`), clôtures (grillages, panneaux, poteaux : `fences.lignes`, `fences.breche` ; **pas les murets ni les
  haies**) et **petits arbres seulement** (moins de 9 m, `vegetation.casser` ; les gros restent des obstacles, choix de
  l'utilisateur). Détection avant contact (boîte de la voiture élargie), objet caché (exemplaire de MultiMesh : méta
  `origines` posée par `cells.gd`) ou effacé par le shader (`env_casse` d'`env.gdshaderinc`, uniform `casse_pts` : 16
  points, simple/fence), débris physique 15 s, poussière et éclats (`dust.gd`), son selon la matière, vitesse réduite
  selon l'objet. Tout réapparaît au rechargement de la tuile. Essai : `-- --casse-test [--casse-debug]` (captures
  `user://shots/casse_*.png`).
- **Jeu sans friction** : rien ne doit gêner le joueur (démarrage direct, remise sur la route automatique, commandes
  souples, pas d'à-coups de chargement). Voiture coincée (gaz ou frein enfoncé, moins de 1,5 m parcouru en 3 s, même
  si la vitesse calculée reste élevée en vibrant contre un obstacle) : remise sur la route automatique (`car.gd`).
