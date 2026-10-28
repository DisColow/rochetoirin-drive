# Consignes du projet

- **RÈGLE ABSOLUE — Street View : jamais plus de 9 000 appels d'images par mois** (décision écrite de l'utilisateur,
  issue #13, 14/10/2026 ; remplace l'ancien plafond de 20 $ au total du 13/10). Aucune exception, aucun contournement :
  le compteur `pipeline/sources/sv_depenses.json` (versionné) compte chaque essai d'image par mois de facturation
  Google (heure du Pacifique) et `pipeline/sv_budget.py` arrête le programme avant tout dépassement (`PLAFOND_MOIS`) ;
  toute requête d'image Street View doit passer par `get()` de `fetch_sv_landmarks.py` (qui appelle
  `sv_budget.payer()`). Ne jamais modifier, relever ni remettre à zéro ce plafond ou ce compteur sans nouvelle décision
  écrite de l'utilisateur. Métadonnées (gratuites) non comptées. Avant chaque lot : annoncer à l'utilisateur le nombre
  d'appels prévu et le total du mois.

- **Reprise** : lire `docs/REPRISE.md` en début de session ; le tenir à jour et le pousser après chaque livraison
  et chaque étape importante (état, ce qui reste, pièges), pour qu'une autre session reprenne sans rien perdre
  (demande de l'utilisateur : la limite d'utilisation peut couper la session à tout moment, son pourcentage n'est
  pas visible depuis la session).
- **Issues GitHub** : quand l'utilisateur demande de faire des choses, lire les issues ouvertes de
  `DisColow/rochetoirin-drive` (`curl -s https://api.github.com/repos/DisColow/rochetoirin-drive/issues?state=open`)
  et les ajouter à la liste des tâches ; poser des questions si une issue n'est pas claire.
- **Issues « pour-toi »** : chaque fois que l'utilisateur a quelque chose à faire de son côté (mesure ou essai sur le
  téléphone, secret à ajouter, choix à valider, vidéo à envoyer…), créer une issue GitHub étiquetée `pour-toi`,
  assignée à `DisColow`, en français : contexte en deux lignes, étapes numérotées, ce qu'on attend en retour. Ne pas
  créer de doublon (vérifier les issues ouvertes). Ces issues ne sont pas des tâches pour Claude : les relire pour
  traiter les réponses de l'utilisateur, puis les refermer quand l'action est faite (en le disant dans un commentaire).
- **Étiquettes des issues** (demande du 14/10) : `pending` quand l'utilisateur doit donner une réponse ou une
  décision ; `à tester` quand il doit vérifier dans le jeu (livré). Elles remplacent `pour-toi`. Changer l'étiquette
  dès que l'état change (réponse reçue -> retirer `pending` ; livraison -> `à tester`).
- **Une issue GitHub par élément en cours ou à faire** (demande du 14/10) :
  - toute tâche en cours, à faire ou en attente a son issue (titre suivi du n° de tâche, état en tête du corps) ;
  - la créer dès qu'une nouvelle demande arrive ;
  - commenter à chaque avancée notable ;
  - à la livraison, si l'utilisateur doit vérifier le rendu dans le jeu, la laisser OUVERTE avec un commentaire
    « livré en vX.Y, à vérifier dans le jeu » : c'est lui qui la ferme ; sinon la fermer (version et résumé).
- **Jamais inactif** (demande du 14/10) : pendant que l'utilisateur teste ou qu'un build tourne, enchaîner sur
  les autres issues ouvertes (hors `pending` / `à tester`) au lieu d'attendre ; ne s'arrêter que s'il ne reste rien.
- **Reprise automatique** (routine horaire « Reprise après limite d'utilisation », h+07) : terminer d'abord le travail
  en cours jusqu'à la livraison complète, puis enchaîner sur les issues ouvertes (sauf `pour-toi` / en attente).
  Si la session travaillait déjà quand le réveil arrive : ne rien écrire à l'utilisateur (demande du 14/10).
  S'il ne reste rien à faire (demande du 16/10) : REPRISE.md à jour et poussé, puis « Rien à reprendre : tu peux faire
  /clear (REPRISE.md est à jour). » en message et en notification ; l'utilisateur fait /clear (la session ne peut pas).
- **API Claude (payante, crédit de l'utilisateur) : uniquement pour l'actualité du jour** (`actu.yml`, ~0,40 $/jour).
  Tout autre usage (génération ponctuelle de textes, essais…) **demande l'accord explicite de l'utilisateur avant**,
  avec le coût estimé ; ne jamais changer de méthode en cours de route sans le lui redemander. Les textes du jeu
  s'écrivent par Claude Code directement (pas par l'API). Les rebonds du 12/10 (`taxi_rebonds.py`, ~4,50 $) ont été
  générés par l'API sans cet accord : erreur à ne pas reproduire ; l'action `taxi_rebonds.yml` est en lancement
  manuel seulement.
- **RÈGLE ABSOLUE — Preuve à chaque ticket livré** (demande du 16/10, après des livraisons non vérifiées) : le
  commentaire « livré en vX.Y » contient la preuve que ça marche (capture ou extrait du journal d'un essai qui
  exerce vraiment la correction : chiffres avant/après). Sans preuve : « NON VÉRIFIÉ : raison », et le message de
  livraison à l'utilisateur liste ces points. Un essai qui n'atteint pas la situation visée (ex. voiture qui
  n'arrive jamais au bord) ne compte pas comme preuve.
- **Hypothèses annoncées avant de coder** (16/10) : quand une donnée ou une demande est floue (usage « Indifférencié »
  de la BD TOPO, mot mal transcrit d'un vocal, cas limite), poser la question à l'utilisateur AVANT de livrer, pas
  après ; dire explicitement ce qui a été supposé.
- **Tri avant de proposer** (16/10) : avant de soumettre des choix (sons, modèles, textures), les comparer soi-même
  aux références du genre (« canons du genre ») et écarter les faibles ; ne proposer que ce qu'on défendrait.
- **Contrôle avant chaque livraison** (issue #30) : `tools/verifier.sh` (scripts GDScript, ~1 min) ; `--complet` ajoute
  les essais en jeu sans écran (casse, champ, conduite, ~30 min) après une modification du jeu. 0 erreur exigée.
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
- **Toujours tirer la branche sans les APK** : `GIT_LFS_SKIP_SMUDGE=1 git pull --rebase origin godot` (un `git pull`
  normal télécharge l'APK de 1,3 Go via Git LFS et remplit le disque de la session).
- Les données brutes (`tools/data/`) ne sont pas versionnées : elles se régénèrent avec les scripts `tools/fetch_*`.
- **Quota Google Street View** : avant tout appel à l'API, récupérer le cache privé
  `DisColow/rochetoirin-streetview` (copier `streetview/` dans `tools/data/streetview/`) ; après tout nouveau
  téléchargement, y pousser les nouvelles images. Ce dépôt reste privé (images Google non redistribuables).
- **Bâtiments : directives de l'utilisateur sur les aplats** (`docs/kb/aplats.md`, à lire avant de toucher un
  bâtiment) : façades strictement plates (ouvertures et détails muraux peints : texture + normal map), volume réservé
  aux structures extérieures, bâtiment reconnaissable plutôt qu'exact, corriger le volume existant par une fiche
  d'une ligne plutôt que modéliser.
- **La logique prime sur la donnée brute** (cf. `docs/kb/21-coherence.md`) : rien sur les routes/trottoirs, clôtures et
  haies continues, pas de routes superposées, pas de taches ni de piscines absurdes. (`tools/check_coherence.py` ne vaut
  que pour l'ancienne version du jeu : sur `godot`, contrôles propres à chaque script du pipeline, ex. « rien sur la
  route » de `build_fences.py` et `build_sport.py`.)

## Économie d'utilisation (demande du 14/10)
- Le suivi est dans les issues GitHub et docs/REPRISE.md : liste de tâches interne réduite aux tâches en cours.
- Captures d'écran seulement à la livraison ou sur demande ; sorties de commandes filtrées ; attentes en arrière-plan
  (pas de surveillance qui réveille à chaque étape) ; messages courts.
- Après chaque livraison, une session neuve (ou `/clear`) repart de REPRISE.md : bien moins coûteux qu'une longue
  conversation.

## Branche `godot` (refonte, depuis le 4 octobre 2026)

- Moteur **Godot 4.4.1** (`godot/`) + **Terrain3D 1.0.2**, rendu **Compatibility (OpenGL ES 3)** : le rendu Vulkan
  plante avec Terrain3D sur le Vulkan logiciel du conteneur, impossible à vérifier ; Compatibility est vérifiable ici.
- Données : `pipeline/` (Python) -> `godot/world`, `godot/terrain`, `godot/assets` (générés, non versionnés).
  Ordre : `routes_plan.py` (zone : couloirs et communes ; Rochetoirin, Saint-Chef, Bourgoin-Jallieu, Montcarra, Saint-Didier-de-la-Tour, La Chapelle-de-la-Tour et (v6.48) L'Isle-d'Abeau entières
  (v6.45), routes Montcarra / Chamont / Saint-Chef > Bourgoin-Jallieu et Montcarra > L'Isle-d'Abeau ; d'après
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
  `ao_region`), `build_grass_tex.py`, `build_zone.py` (limite de la carte pour le gardien), `build_epreuves.py` (épreuves chronométrées, après `build_places.py`), `build_nuages_tex.py` (nuages du ciel peint), `build_touffes.py` (touffes des champs façon San Andreas, après `bake_cultures.gd --seulement=plants` ; céréales : épis d'orge scannée CC0 de `blender_orge.py` devant le feuillage, v6.72, #117), `build_vinyles.py` + `fetch_garage.py` + `blender_garage.py` (garage), `blender_makehuman.py` (clients du taxi MakeHuman : MPFB 2 en extension Blender + pack « makehuman_system_assets » CC0, voir docs/REPRISE.md) puis `blender_animer_clients.py` (animations Quaternius transférées sur leur squelette, #77), `fetch_ufo.py` + `blender_ufo.py` (soucoupe du gardien),
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
  `build_vegetation.py`, `build_crops.py`, `godot --headless --import`,
  `godot --headless --script res://tools/import_terrain.gd`, puis
  `xvfb-run godot --path godot res://tools/bake_relief.tscn` (relief de remplacement `world/relief/`, à refaire après
  toute modification du relief ou de son shader) et `godot --headless --import`.
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
- **Argent** (v6.76, #127) : chaque épreuve en Normal / Difficile / Extrême (`activities.gd` `NIVEAUX_EP` : temps ×1 /
  0,9 / 0,82, primes ×1 / 2,5 / 6 ; or en Normal = 200 € + 45 €/km, argent 60 %, bronze 35 %, rejouer 25 %) ;
  médailles et records par niveau (`cle_ep(id, niv)`) ; taxi ×3, chasse 100 €. Essai `--drive-test --argent-test`.
- **Explosions** (v6.76, #129, `scripts/explosion.gd`) : **champignon atomique** (choix C de l'utilisateur, v6.80 ;
  styles « film » et « mini » gardés pour les essais, plus de choix dans ⚙) ; planches CC0 Unity Labs
  (`pipeline/fetch_explosions.py` -> `assets/fx/`). En vue conducteur ou capot, `camera_rig.gd` passe en poursuite
  le temps de l'explosion (`_mode_avant`) et recule en plan large (`_boum`, 30 m, 9 m de haut). Essais
  `--drive-test --explosion-test [--explosion-styles=a,b]`, `--drive-test --boum-camera-test`.
- **Mode carrière** (v6.74, #120 ; chapitres 2 à 4 en v6.84, #131, `scripts/carriere.gd`, onglet « Carrière » en tête
  du menu Activités) : scénario en 4 chapitres validé par l'utilisateur (carte jamais verrouillée hors mission, rivaux
  qui roulent vraiment : concurrent.gd). Tout est dans les données `CHAPITRES` (missions, intro, message de fin,
  voiture offerte `cadeau`) et `RIVAUX` (Kévin p106, Sandrine p206, Didier p306 : répliques, voix, allure au
  championnat). Genres de missions : livraison, taxi (`activities.impose` : client nommé, sexe/âge du modèle, `dit`,
  `chocs_max`), chrono, chasse (`activities.chasse_limite`, crochet `chasse_finie`), course (place à tenir), nuit
  (taxi de nuit, `main.set_time(3)` puis heure rendue), duel, manche (championnat du chapitre 4, `champ`, points
  `POINTS`). Lieux par nom de places.json, « nom|commune » s'il y a des homonymes (l'essai contrôle l'unicité).
  Réputation 0-100 par chapitre (`reps`), chapitre ouvert quand le précédent est à 100 ; ancienne sauvegarde du
  chapitre 1 relue. Progression dans `user://carriere.cfg`. Essais `-- --drive-test --carriere-test --sans-voix`
  (chapitre 1, ~20 min ici) et `-- --drive-test --carriere2-test --taxi-sorte=normale --sans-voix` (chapitres 2 à
  4, ~1 h 15 ici) ; `--sans-voix` : pas de synthèse vocale, speech-dispatcher fige le jeu sous Linux.
- **Circulation** (v6.85, #132, initiative de Claude, `scripts/circulation.gd` + `circulation.gdshader`) : voitures qui
  roulent toutes seules. Réseau `world/trafic.bin` de `pipeline/build_trafic.py` (après `build_roads.py` : voies
  carrossables d'OSM d'un carrefour à l'autre, sans service/chemins/piétons ; altitude de la chaussée, vitesse autorisée,
  sens unique, nombre de voies, décalage de la voie de droite). Modèles `assets/props/car1` et `car3` (habitacle
  retiré, roues à part qui tournent, une MultiMesh d'un exemplaire par voiture pour ses niveaux de détail), feux stop et
  phares dans le shader (UV2.y −2/−3, INSTANCE_CUSTOM.a). Conduite IDM (`IDM_*`), virages (`A_LAT`), réservation des
  carrefours (`_resa`), raccord lissé (`RACCORD`), klaxon (`assets/sfx/klaxon.ogg`, synthèse de `build_sfx.py`
  `klaxon()`) quand le joueur bloque. Nombre : `NOMBRE[niveau]` × `DENSITES[⚙ > Conduite > Circulation]`
  (`conduite/circulation` de reglages.cfg). Choc : `AnimatableBody3D` qui suit chaque voiture ; juste avant qu'une
  voiture pilotée la percute (`_chocs`), elle devient une épave `RigidBody3D` (meta « matiere » metal). `vider()` à la
  téléportation. Essai `--fixed-fps 8 -- --drive-test --circulation-test [--densite=0-3] [--drive-from=…]`.
  Obstacles : voitures de la circulation le long des voies (même voie devant, voie suivante) ; joueur, concurrents,
  piéton et épaves projetés sur le chemin (`_chemin`, un point tous les 3 m : en ligne droite, un obstacle à 30 m dans
  une rue qui tourne était manqué). Clignotants (UV2.y −4, côté d'après VERTEX.x) avant un virage de plus de 30°.
  **Piège des essais** : FREIN tenu à l'arrêt = marche arrière ; pour immobiliser la voiture du joueur, `car.hold()`.
  Publication des données : `pipeline/publier_fichiers.sh <fichiers>` (seulement ces fichiers sur `donnees`,
  `A_BLANC=1` pour voir les différences d'abord) plutôt que `publier_donnees.sh` quand le conteneur n'a pas tout.
  **Feux tricolores** (v6.87, #134) : arcs coupés aux nœuds `traffic_signals` ; pour chaque arrivée, phase et axe de la
  tête de feu calculés dans `build_trafic.py` comme `furniture.signs` la pose (champs `feu_b`/`feu_a` de trafic.bin,
  9 champs par arc ; l'ancien format à 7 champs reste lu, sans feux). `signal_light.gdshader` : phase =
  (17 cx + 31 cz) mod 60 (case de 60 m de l'ampoule), horloge `t_feux` donnée par roads.gd (`Env.temps_feux()`,
  temps de jeu avancé par roads.gd, pas l'heure réelle : à `--fixed-fps 8` le jeu tourne 30 fois moins vite que la
  montre) : **ne pas revenir à `TIME` ni à un hachage `fract(sin())`** (irreproductible côté jeu). Contrôle des têtes
  dessinées contre `build_trafic.py` : 198 ampoules sur 198 concordantes (v6.87). Arrêt à `ARRET_FEU` m du nœud,
  pas de réservation du carrefour pendant le rouge. **Dépassement** : obstacle immobile (épave, joueur, concurrent)
  après `ATTENTE` s : autre file d'un sens unique (raccord `dec`), sinon voie d'en face libre sur `DEGAGE` m
  (`dep` = [s0, s1, s2, s3, écart], `_ecart(c, s)` ajouté par `_pos`). **Véhicule lent** (v6.89) : sur une route
  rapide à double sens (`V_RAPIDE`), derrière un véhicule à moins de 65 % de la vitesse autorisée (joueur, autre voiture)
  depuis `LENT` s : `_doubler` (portion presque droite, voie d'en face libre sur toute la longueur du dépassement,
  voitures qui arrivent comprises ; `dep[5]` = vitesse du dépassement) ; pendant qu'elle déboîte, `_devant` ignore les
  voitures de sa voie. Essai `--circulation-test --circulation-double --drive-from=-8410.95,221,-7187.25,45.2`. **Véhicules lourds** (v6.99, #136,
  choix de l'utilisateur T5 et B1) : `pipeline/fetch_lourds.py` + `blender_lourds.py` (couleurs des textures regroupées
  en matériaux unis, roues regroupées par essieu et par côté en matériaux « roue_<n>_c<couleur> », allégés) -> `assets/props/lourd_tracteur.glb`, `lourd_bus.glb` ;
  `MODELES` 2 et 3 de `circulation.gd` (`_tirer_modele` : tracteur sur les routes à 65-95 km/h, bus à 50 km/h au plus ;
  `LOURD_CHANCE`, `LOURD_VMAX`, `LOURD_PITCH` ; modèle absent des données : jamais tiré ; v7.00 : une roue par groupe
  `roue_<n>`, `_roues_g` : centre, rayon, MultiMesh ; angle = `c.dist` / rayon). Essai `--lourds-test
  [--lourds-x=n]`. **Arrêts de bus** (v7.01) : `_arret_bus` (arrêts `pietons.arrets_bus()`, devant à moins de 40 m,
  à droite de -1,5 à 9 m) : le bus freine jusqu'à l'arrêt (leader « arrêt de bus »), attend `ARRET_BUS` s,
  `pietons.bus_a_l_arret` (passants qui attendent : vont à la porte et montent ; 1 ou 2 descendent) ; `bus_vers_arret`
  (essais) pose un bus en amont d'un arrêt. Essai `--bus-test`. Concurrents : `concurrent._piloter` évite aussi
  les voitures de la circulation (`evites` : voitures contournées). **Course contre des concurrents** : tracé dégagé
  sur `COURSE_MARGE` m (`_route_course`, d'après `concurrents[0]._chemin` : voitures et épaves retirées au départ,
  aucune apparition ensuite) et barré : une voiture ne s'engage plus sur une voie du tracé (`_sur_trace` : à 4,5 m et
  dans la même direction ; `_suite` rend -2, arrêt `BARRAGE` m avant le carrefour). Sans cela, en circulation dense,
  le peloton s'empilait sur les épaves dans les rues étroites (essai : bloqué à 150 m du départ, 13 épaves en 45 s ;
  après : 0 épave, 352 m en 40 s comme sans circulation). Essais `--circulation-feux`, `--circulation-depasse` (avec
  `--circulation-test`), `--course-ia-test --densite=3`.
- **Passants** (v6.88, #135, initiative de Claude, `scripts/pietons.gd`) : piétons qui marchent sur les trottoirs
  d'OSM, les rues piétonnes et, en ville (bâti de `world/ambiance.bin` ≥ `BATI`, rues à 50 km/h au plus), le bord des
  rues sans trottoir. Lignes `world/pietons.bin` de `pipeline/build_pietons.py` (après `build_roads.py` et
  `build_ambiance.py` : coupées sur les chaussées, bouts réunis en nœuds, poids selon le bâti et les lieux publics ;
  genres 0 trottoir, 1 rue piétonne, 2 bord de rue, 3 passage piéton, 4 arrêt de bus). Passages piétons (zébras de
  `furniture.markings` d'une rue qui a des passants des deux côtés) : le passant attend que rien n'arrive (`_libre`),
  puis traverse ; la circulation s'arrête devant lui (`sur_passage()` dans les obstacles de `circulation.gd`, meneur
  « passant », sans dépassement ni klaxon). Arrêts de bus (nœuds `bus_stop` sur une voie, comme le panneau de
  `furniture.signs`) : il attend sur place, face à la route.
  Modèles des clients du taxi (`assets/clients/mh_*.glb`, chargés en arrière-plan, animations de `pieton.gd` d'après
  `vitesse`) ; textures compressées depuis la v6.88 (`compress/mode=2`, normales `normal_map=1`). Nombre :
  `NOMBRE[niveau]` × `DENSITES[⚙ > Conduite > Circulation et passants]` (même réglage que la circulation), × `NUIT` la
  nuit ; réserve de passants cachés (pas de new/free en jeu). Voiture pilotée qui fonce sur un passant : bond de côté ;
  touché quand même : « pouf » (`activities._teleport_fx`), il disparaît (personne n'est blessé, aucun compteur).
  `vider()` à la téléportation. **Klaxon du joueur** (`scripts/klaxon.gd`, bouton KLAXON au-dessus des flèches, touche H,
  L3 : action `klaxon` de `nav_physique.TOUCHES`) : `klaxon.ogg` de la circulation, plus grave pour une voiture lourde ;
  `pietons.klaxon()` : les passants à 30 m se tournent vers la voiture, ceux devant elle s'écartent, ceux d'un passage
  piéton pressent le pas. v6.90 : client du taxi déposé -> `pietons.adopter(nœud, modèle)` (ligne à 25 m, sinon il
  s'éloigne et disparaît comme avant) ; explosion -> `pietons.panique(p)` (appelée par `explosion.gd`, fuite à 60 m).
  Essai `--fixed-fps 8 -- --drive-test --pietons-test [--pietons-court] --drive-from=-10461.9,241.5,-498.6,105`
  (centre de Bourgoin, 17 passages piétons à 100 m).
- **Heure et cycle jour et nuit** (`main.gd`, ⚙ > Heure de la journée) : Midi, Après-midi, Coucher, Nuit, ou **Cycle**
  (v6.92, #140, initiative de Claude : `heure_choix` = réglage, `time_of_day` = moment le plus proche, `heure` = heure
  du jeu, 24 min par journée, départ `CYCLE_DEPART`). Repères `CYCLE_REPERES` [heure, moment, décalage du soleil] ;
  entre deux repères, `_lumiere()` mêle deux moments `_moment(t, fm)` (`MOMENTS` : soleil, exposition, ambiance, brume,
  ciel), chacun déjà mêlé par la météo. Lumière ambiante toujours « ciel » (part 0 au coucher et la nuit = couleur
  seule, même image à 0,3 près). Du coucher à la nuit, le soleil devient la lune dans un creux d'énergie (`creux`).
  **Ciel** : ses reflets se recalculent sur ~8 images (mode INCREMENTAL) : mises à jour toutes les `CYCLE_PAS` s au
  plus, et rien n'est reposé s'il n'a pas changé (`_ciel_pose`), sinon la lumière ambiante reste celle d'un ciel
  d'avant (midi sombre). `heure_texte()` dans la pastille du HUD ; `phares_allumes()` (voiture, circulation) ; la
  carrière rend le cycle après le service de nuit (`set_time(choix, heure)`). Essai
  `--fixed-fps 8 -- --drive-test --cycle-test --drive-from=-8410.95,221,-7187.25,45.2`.
  **Étoiles** (v6.93, #141) : `etoile()` de `ciel_nuages.gdshaderinc` (grille de directions de 0,4°, une case sur ~70,
  1 à 2 px : plus petites, elles scintilleraient), dernier réglage `etoiles` du ciel peint (nuit claire seulement,
  mêlé au crépuscule), sous les nuages. **Tarif de nuit du taxi** : `main.tarif_nuit()` (réglage Nuit, 19 h 30 - 7 h
  dans le cycle) -> `taximetre.nuit` (« TARIF 2 », `PAR_KM_NUIT`, chaque mètre au tarif du moment). Essais `--nuit-test`
  (étoiles comptées, taximètre), `--taxi-test --taxi-nuit`.
  **Orage** (v6.94, #142) : la boucle `assets/sfx/pluie.ogg` contient des coups de tonnerre, relevés par analyse
  (énergie sous 200 Hz : `rain.gd` `TONNERRES` [début, force]) ; `rain.eclairs_entre(p0, p1)` lance `main.eclair(f)`
  1 à 2,6 s avant chacun (plus fort = plus près) : deux éclats (ciel `background_energy_multiplier`, ambiance, lune),
  plus discrets le jour. **Bulletin météo** : `main.bulletin_meteo()` ajouté au flash de Rochetoirin Info (`radio.gd`) ;
  en météo variable, `meteo_suivante` est tirée d'avance (la prévision se réalise). Essai `--orage-test` (textes, calage
  sur une boucle à 30 images/s, lueur image par image à temps ×0,1 ; ici le son avance en temps réel, pas le jeu).
  **Arc-en-ciel** (v6.96, #144) : `arc` de `ciel_nuages.gdshaderinc` (40,5-42,5° du point opposé au soleil, arc
  secondaire à 50,5-53,5°, sous l'horizon si le soleil dépasse 42°) ; `main._arc_avancer` : fin d'une averse (fondu
  depuis la pluie), de jour, une minute puis effacé. Brouillard : `main.brouillard`, circulation prudente comme sous la
  pluie. Essai `--arc-test` (pixels colorés avec et sans l'arc sur la même image).
  **Coût** (v6.97, #145) : `Env.set_value` ne renvoie plus une valeur simple inchangée aux matériaux (les tableaux,
  modifiés sur place, repartent toujours ; un matériau ajouté reçoit tout par `add()`) : `_lumiere()` 216 -> 22 µs
  (essai `--lumiere-perf`, 217 matériaux). Cockpit : horloge et pénombre suivent le cycle (`cockpit._cycle()`).
- **Météo** (`main.gd`, ⚙ > Météo) : Beau temps, Couvert, Pluie, Brouillard, ou **Variable** (v6.91, #139, initiative
  de Claude : `meteo_choix` = réglage, `weather` = temps qu'il fait ou qui arrive). Variable : durées `METEO_DUREES`,
  suites `METEO_SUITES`, fondu de `METEO_FONDU` s (`meteo_vers`, `_meteo_avancer`) où tous les réglages de
  `METEO_REGLAGES` sont mêlés (brume en échelle logarithmique), mis à jour `METEO_PAS` fois par fondu (le ciel qui
  change recalcule ses reflets : pas à chaque image). Ciel : le ciel photo de midi se couvre par `gris` de
  `ciel_midi.gdshader`, qui mêle le ciel peint de `ciel_nuages.gdshaderinc` (code commun avec `ciel_peint.gdshader`,
  mêmes réglages `_ciel_reglages`) : à la fin du fondu, `_sky_peint` le remplace sans saut. `main.pluie` (0-1) et
  `phares_meteo` : gouttes (`rain.gd`, premières gouttes en 4 s), pare-brise, sons (`audio.gd`), circulation
  (`PLUIE_V`, `PLUIE_T`, phares), passants (`PLUIE` : moins nombreux, pas pressé). Essai
  `--fixed-fps 8 -- --drive-test --meteo-test --drive-from=-8410.95,221,-7187.25,45.2` (luminosité image par image,
  captures `meteo_*.png`, enchaînement de la météo variable accéléré).
- **Balade** (v6.98, #146, initiative de Claude, `scripts/balade.gd`, Activités > Course libre > « Partir en balade »,
  `activities._balade_start`, mode « balade ») : pilote des concurrents (`concurrent.gd`) sur la voiture du joueur,
  `a_lat` 2,2, profil plafonné à la limitation de chaque route (`road_name.gd`, tous les 20 m : `_limiter`), lieux de
  `places.json` à 1,5-5 km l'un après l'autre ; plans de caméra `PLANS` (poursuite = caméra du jeu, bord de route avec
  vue dégagée vérifiée par un rayon, drone, roue, face, survol) de 7 à 12 s ; `hud.commandes_visibles(false)` cache les
  commandes de conduite sans mettre le jeu en pause ; un toucher hors de la rangée du haut, une touche ou un bouton de
  manette : `activities._stop()`. Feux rouges : `_relever_feux` (arrivées d'arcs de `trafic.bin` à feu, à moins de 7 m
  du trajet et dans son sens) puis `_feux_appliquer` (vitesse du profil nulle au point d'arrêt tant que c'est rouge) ;
  `concurrent.doubler = false` : suit la voiture de devant sans la doubler ni la pousser. Essai
  `--fixed-fps 8 -- --drive-test --balade-test [--duree=s] --drive-from=…`.
- **Ligne de bus** (v7.02, #148, initiative de Claude, `scripts/ligne_bus.gd`, Activités > Taxi > « Prendre une ligne de
  bus », `activities._bus_start`, mode « bus ») : le joueur prend le bus B1 (`voitures.gd` « bus », `service` : hors du
  garage, `ordre()` l'écarte ; modèle `blender_voitures_joueur.py bus` depuis `import/lourds/bus`, poste de conduite
  `eye`/`steer` posé à la main, cockpit `build_cockpits.py bus`) ; `NB_ARRETS` vrais arrêts enchaînés de proche en
  proche (`D_MIN`-`D_MAX` m, sans demi-tour), seulement ceux longés par une voie de la circulation
  (`circulation.voie_arret`) ; horaire par arrêt (`V_HORAIRE`, `ATTENTE`) ; porte avant `PORTE` à moins de `R_ARRET` m du
  poteau, bus arrêté -> portes (bus tenu immobile : frein de porte), `pietons.peupler_arret` à `PEUPLER` m (passants
  « garde » : hors du compte jusqu'à `R_GARDE`), `pietons.bus_a_l_arret(p, porte, nb_desc)` ; recette `TARIF` par
  voyageur, `PRIME_HEURE` à ± `ECART` s, `MALUS_CHOC` ; terminus : `garage.gagner`, succès `lignes_bus`/`voyageurs`,
  voiture rendue (`garage.vue_changee`). Caméra poursuite reculée d'après `car.gabarit.z` (`camera_rig.gd`). Essai
  `--fixed-fps 8 -- --drive-test --ligne-bus-test --drive-from=-10975,236,-1100,90` (bus posé en amont de chaque arrêt
  et conduit jusqu'au poteau, capture `ligne_bus.png`).
- **Succès et statistiques** (v6.86, #133, initiative de Claude, `scripts/succes.gd`, onglet « Succès » du menu
  Activités) : `SUCCES` (id, titre, texte, statistique, but, prime au garage) et `STATS` (affichage). Compteurs
  `noter(clé, n)` appelés par car.gd (explosion du joueur), casse.gd (décor, arbres), activities.gd (taxi, 5 étoiles,
  chasses, concurrents détruits), circulation.gd (voitures percutées par le joueur), garage.gd `gagner` (argent) ;
  distance, nuit, à pied, vitesse maximale, temps et communes suivis ici ; médailles, voitures et chapitres relus de
  leur sauvegarde (`valeur`). Annonces une par une (bandeau du HUD : `main.get_node("HUD")`, main n'a pas de variable
  `hud`). Sauvegarde `user://succes.cfg`. Essai `--fixed-fps 8 -- --drive-test --succes-test --drive-from=…`.
  v6.95 (#143) : succès de la météo et de la nuit (`km_pluie`, `eclairs` noté par `main.eclair`, `km_aube` et
  `heures_cycle` dans le cycle, `taxi_nuit` noté par `activities._taxi_drop`) ; essai `--succes-test --succes-meteo`.
- **Accueil** (v6.86, `scripts/accueil.gd`) : premier lancement d'un nouveau joueur (ni garage.cfg ni carriere.cfg au
  lancement), jamais avec des options de ligne de commande (essais) ; une fois (reglages.cfg accueil/vu). Capture
  `-- --drive-test --accueil-test`.
- **Concurrents** (#128, `scripts/concurrent.gd`, choix de l'utilisateur : 3 par course, un concurrent détruit revient
  4 s après, Kévin réel) : vraie voiture du garage (`car.gd` avec `ia = true` : commandes dans `touch_*` seulement, pas
  d'aide à la voie, de nitro, de volant 3D ni de remise automatique) pilotée par `concurrent.gd` : tracé `itineraire.gd`
  jambe par jambe, profil de vitesse (virages `a_lat`, accélération, freinage) mis à l'échelle du temps visé, horaire
  corrigé en route (`_allure`), poursuite d'un point devant (`_piloter`), décalage pour doubler (`autres`), KA-BOOM
  au-delà de `VITESSE_BOUM` perdus d'un coup en touchant quelque chose, retour `RETOUR` s après `RECUL` m derrière,
  remise sur le tracé si bloquée, retournée ou perdue ; à plus de `LOIN` m du joueur, figée (cinématique) et glissée
  sur le tracé (le relief n'a de collisions qu'à 96 m de la caméra). `activities.gd` : `CONCURRENTS` (modèles et temps
  visés par niveau), `avec_concurrents` (choix « Contre-la-montre / Course contre 3 voitures »), `ajouter_concurrent`
  (grille), `_place`, `BONUS_PLACE`, `concurrent_detruit` (prime), `_fin_concurrents`. Essai
  `--fixed-fps 8 -- --drive-test --course-ia-test [--ep=N] [--niv=0-2] [--joueur=<s>] [--sans-boum]` (la voiture du
  joueur pilotée par un `concurrent.gd` sans voiture propre ; `--fixed-fps` : temps de jeu indépendant de la lenteur
  du rendu ici, 15 pas de physique par image).
- **Voies ferrées** (v6.75, #125 : rouler dessus sans partir en vrille, passages à niveau aux barrières défonçables, pas
  de train) : `pipeline/fetch_rails.py` (OSM) + `build_rails.py` (après `build_roads.py` ; voies posées sur le relief
  terrassé, ponts et tunnels sautés, nœuds de passage d'une même route regroupés) -> `world/rails/rl_tx_tz.bin`, avant
  `build_ground.py` (pas d'herbe sur le ballast) ;
  `scripts/rails.gd` + `rails.gdshader` : ballast = collision en maillage (surface de roulage), rails sans collision,
  croix de Saint-André, feux qui clignotent, demi-barrières cassées par `casse.gd` (genre « barriere »). Essai
  `-- --drive-test --rails-test --casse-debug --sans-voix`.
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
  ou à la demande) : écrire la section « Nouveautés » du README **avant** de pousser la version. **Notes courtes et
  seulement celles de la version actuelle** (demande de l'utilisateur, 13/10) : remplacer la section précédente
  (elle reste dans sa release GitHub), 3 à 5 lignes, pas de détails techniques.
- L'APK (> 100 Mo) va aussi dans `releases/` via **Git LFS** (premier build de chaque version seulement) (`.gitattributes`) ; les GitHub Releases sont interdites à cette
  session. Lien : `https://github.com/DisColow/rochetoirin-drive/raw/godot/releases/<apk>`.
- Rendu Mobile (Vulkan) essayé en v2.8 : moins joli que Compatibility sur le téléphone de l'utilisateur, abandonné.
- Captures de contrôle : `xvfb-run godot --path godot -- --shots=<json>` ; essai de conduite : `-- --drive-test`.
- **Voitures du garage** (v6.62, #95, demande de l'utilisateur : modèles choisis sur planche, **noms et faux logos
  parodiés**, Laguna peinte par Claude, cockpit pixel art par voiture, mini-carte quand la voiture n'a pas de GPS) :
  - catalogue `scripts/voitures.gd` (nom parodié, prix, masse, puissance, vitesse, transmission, GPS, son du moteur,
    crédit) ; `garage.gd` : voitures achetées, voiture conduite, **améliorations propres à chaque voiture**
    (`pieces[id]`), onglet « Voitures » de `garage_ui.gd` (essai sur place, achat, prendre le volant) ;
  - `car.gd` `construire(id)` (caisse, roues, boîte, volant, physique ; force au démarrage d'après le rapport
    poids/puissance, roues motrices, freins à l'échelle de la masse) ; `tuning.gd` `lier()` et pièces du garage
    mises au gabarit de la voiture ; `net.gd` : chaque joueur voit la voiture des autres (`_ma_voiture`) ;
  - modèles : `fetch_voitures_joueur.py` (Sketchfab -> `godot/import/voitures/<id>`, `.gdignore`),
    `faux_logos.py` (emblèmes Renaud, Pijo, Citrouille, Porc'Che ; textures photo retouchées, originaux `*.orig.png`),
    `blender_voitures_joueur.py` (orientation, échelle réelle, roues par coins, matériaux du jeu, habitacle vidé,
    badges et lettrages en volume retirés, faux logos posés en décalcomanie) -> `assets/voitures/<id>/`, puis
    **`compresser_textures.py`** (v6.70 : les images extraites des glb s'importent sinon sans compression, jusqu'à
    80 Mo de mémoire vidéo pour la seule R5) ;
  - cockpits : `build_cockpits.py` (même procédé que `build_cockpit.py`) -> `assets/cockpit/<id>/`, chargés par
    `cockpit.gd` `charger(id)` ; `a_gps()` faux -> la mini-carte reste affichée (`hud.gd`) ;
  - essai : `-- --drive-test --voitures-test --drive-from=-8410.95,221,-7187.25,45.2` (vitesse après 2 s, roues au
    sol, captures `voiture_<id>.png` et `cockpit_<id>.png`).
  - **Import Godot** : `godot --headless --import` réimporte toutes les tuiles `t_*.glb` et sature la mémoire (14 Go,
    tué) ; pour importer seulement les nouveaux fichiers : `.gdignore` temporaire dans `world/` et `terrain/`.
- **Bords de la carte façon Motocross Madness** (v6.23, demande de l'utilisateur, `pipeline/build_bord.py` +
  `scripts/bord.gd`) :
  - Talus tout autour de la zone (`world/bord/`, tuiles de 256 m). Grille de 5 m dont la hauteur ne dépend que de
    la distance au bord : relief + 32 m × (d / 64)^2,2, puis un dos sous le relief. Aucun pli aux angles.
  - Collisions : maillage près de la voiture (surface de roulage, comme le relief).
  - Au-delà de 26 m hors de la carte, ressort vers l'intérieur et rebond si on insiste.
  - Les champs s'arrêtent au bord (`build_crops.py`).
  - Essai : `-- --drive-test --bord-test [--bord-debug] [--snap]`. À relancer après `build_zone.py`.
  - **Soucoupe du gardien désactivée** (choix de l'utilisateur, code conservé : `guardian.process_mode` désactivé
    dans `main.gd`).
- **Voitures garées physiques** (v6.23, `props.gd`, `_physique`) : à moins de 20 m du joueur, chaque voiture
  garée (et chaque tracteur) devient un `RigidBody3D` (`MASSES`) qu'on pousse ou renverse. Elle redevient un
  exemplaire de son lot, à sa nouvelle place, au-delà de 45 m quand elle est immobile.
- Ancien gardien des limites (`scripts/guardian.gd`, désactivé depuis la v6.23) : soucoupe volante « UFO » de sebslom (Sketchfab, CC BY 4.0 ;
  `fetch_ufo.py` + `blender_ufo.py` -> `assets/ufo/ufo.glb`), invisible jusqu'à ce que la voiture tombe hors de la carte,
  rayon tracteur qui la ramène sur la route (`car.carried`), puis repart ; essai : `-- --drive-test --void-test --void-drop [--snap]`. Crédits dans ⚙ > Crédits (`hud.gd`, `CREDITS`) : y ajouter toute nouvelle ressource sous licence.
- **Éléments graphiques : modèles existants d'abord, au choix de l'utilisateur.** Pour tout élément graphique ajouté
  ou modifié (objets, mobilier, véhicules, personnages, végétation…) : 1) chercher d'abord des modèles 3D libres
  existants (Sketchfab CC BY/CC0 via SKETCHFAB_TOKEN, Poly Haven, Kenney, Quaternius, MakeHuman/MPFB…, crédités dans
  ⚙ > Crédits) ; 2) **proposer plusieurs candidats à l'utilisateur sur une planche JPEG** (même éclairage, échelle
  humaine) et attendre son choix ; 3) ne modéliser soi-même (Blender, procédural) qu'à défaut de modèle convenable.
- **Bâtiments d'après Street View : reconnaissables, pas exacts** (directive du 12/10, remplace l'ancienne règle
  « au pixel près », jugée beaucoup trop longue sur la boulangerie) : partir du bâtiment déjà généré et le corriger
  (fiche d'une ligne : couleur, matériaux, toit, niveaux, volets, structures extérieures) ; façades en aplat
  (`docs/kb/aplats.md`) ; dimensions approximatives acceptées ; photos du cache d'abord, une ou deux suffisent.
  Comparatif photo/jeu pour validation ; une issue n'est refermée qu'avec l'accord de l'utilisateur.
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
- **Éditeur de monde : bâtiments refaits sur demande** : bâtiments refaits sur demande dans `pipeline/sources/bati_editeur.txt` (cleabs + relevé
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
  **Économie** (v6.76, #124, cible : TCL 40 R 5G, Mali-G57, 720p) : `NIVEAUX[0]` de `main.gd` (pas d'ombres, résolution
  3D auto 50-80 %, 30 img/s ou 60 avec `eco_60`, physique 60 pas/s, brume), ni arbres, ni herbe, ni plants (terre
  labourée), phares et lampadaires factices (`env_phares_lum` d'`env.gdshaderinc`, à ajouter à tout nouveau shader de
  sol ou de mur : `EMISSION += ALBEDO * env_phares_lum(wp)`). **Le frein des roues de Godot est une impulsion par pas
  de physique** : `car.gd` le met à l'échelle (`k_pas`) ; tout effet réglé par pas doit faire de même.
  **Essais en parallèle** : chacun son `XDG_DATA_HOME` (sinon `demarrage.flag` met l'autre en mode sûr).
  **Fusion des modèles** (v6.77, #124 étape 2) : `props.gd` et `shops.gd` `_fusionner` mettent tous les matériaux d'un
  modèle en une surface (un appel de dessin par case au lieu d'un par matériau) ; le matériau de chaque sommet passe
  dans UV/UV2 (`props.gdshader`, `shop.gdshader` « fusion ») — **jamais dans COLOR** : dans une MultiMesh sans couleur
  par exemplaire, Compatibility la multiplie par zéro (tout noir) ; niveaux de détail refaits par
  `ImporterMesh.generate_lods` (`RenderingServer.mesh_get_surface` ne rend pas ceux de l'import en 4.4). Petits objets
  sans ombre (clôtures, panneaux, enseignes, bornes). Essais avant/après : `RS_SKIP=fusion,ombres`.
  **Horizon lointain** (v6.78) : `pipeline/alleger_pano.py` simplifie `world/far/pano.glb` (173 000 -> 30 000
  triangles, erreur jugée en angle vu de la zone de jeu, silhouette à 2 px près) : à relancer après `build_assets.py`.
  **Import d'un seul fichier** : un `godot --headless --import` du projet ré-importe aussi les tuiles de bâtiments
  (13,8 Go, tué) ; importer le fichier dans un petit projet temporaire (même chemin `res://`, même `.import`) et copier
  son `.godot/imported/<fichier>-<hash>.scn/.md5` dans le projet.
  **`.import` manquants** (22/10 : 1 634 tuiles de routes depuis le 16/10, essais sans routes 3D, « No loader
  found ») : le jeu ne charge pas un modèle sans son `.import`, même si `.godot/imported` le contient. `verifier.sh` le
  signale ; les refaire d'après un `.import` voisin (nom du cache = `<fichier>-<md5 du chemin res://>.scn`, sans `uid`).
  **Niveaux de détail ratés** (v6.79, #130) : ceux que Godot fabrique à l'import déchirent les modèles faits de pièces
  séparées (la 2CV) ; ils apparaissent vite sur téléphone (petite résolution). Voitures du garage en pleine définition
  (`lod_bias`) ; contrôle : `--voitures-revue --lod-seuil=60 --resolution 800x360`.
- **Cultures fauchées** (v6.36, #131 : les tiges explosent en éclats de la couleur de la culture, `dust.eclats()`, couleurs `ECLATS` de `trample.gd` ; les bandes sont rasées à 10-20 cm dans la trace ; essai `-- --drive-test --champ-test [--champ-type=0-3]`, captures `user://shots/champ_N.png`). Ancien fonctionnement (v6.5, refait en v6.9 : issue #8, couchées à 90°) (`scripts/trample.gd`) : carte des passages
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
  la demande (`car.set_sprite_mode`). Contrôle : `-- --mem-test` (mémoire vidéo, textures, tampons) ; **`-- --vram
  [--vram-at=x,y,z] [--vram-voiture=id]`** (v6.70, #122) : mémoire vidéo par système (maillages et textures,
  relief Terrain3D). Relevé du 21/10 (Rochetoirin, Équilibré) : 615 Mo, dont relief ~130, bâtiments ~100, ciel
  45 (ramené à 18 : `build_ciel_midi.py`, `assets/ciel/`, `ciel_midi.gdshader`), horizon ~34, arbres 30,
  lampadaires 3 (sprites inutiles pour la mémoire). **Le gel persiste
  en v6.7 (issue #4)** : témoin de rendu depuis la v6.10 (`crash_report.gd` : vignette 4 × 4 px relue toutes les 5 s de
  temps réel ; deux échecs -> `[figé]` dans le journal, `user://fige.txt`, bandeau « Image figée » au lancement
  suivant avec rapport) ; essai : `-- --fige-test` (simule l'arrêt du rendu). Attendre un rapport avant de corriger.
- **Décor destructible** (v6.9, issue #7, `scripts/casse.gd`) : panneaux de signalisation (positions
  `world/panneaux.bin` relevées dans les tuiles de routes par `pipeline/build_casse.py`), lampadaires (`poles.pieds`,
  `poles.casser`), clôtures (grillages, panneaux, poteaux : `fences.lignes`, `fences.breche` ; **haies et murets aussi
  depuis la v6.24** : `fences.genres`, vitesse minimale `KINDS[…][3]`, sinon obstacles) et **petits arbres seulement** (moins de 9 m, `vegetation.casser` ; les gros restent des obstacles, choix de
  l'utilisateur). Détection avant contact (boîte de la voiture élargie), objet caché (exemplaire de MultiMesh : méta
  `origines` posée par `cells.gd`) ou effacé par le shader (`env_casse` d'`env.gdshaderinc`, uniform `casse_pts` : 16
  points, simple/fence), débris physique 15 s, poussière et éclats (`dust.gd`), son selon la matière, vitesse réduite
  selon l'objet. Tout réapparaît au rechargement de la tuile. Essai : `-- --casse-test [--casse-debug]` (captures
  `user://shots/casse_*.png`).
  **#123 (v6.81)** : débris persistants (figés au repos, rendus au-delà de `LOIN` 220 m, réserve de 32 corps ; le
  point effacé le plus loin part en premier) ; clôtures, grillages, haies, piliers et murets éclatent en 2-3 morceaux ;
  `COUCHES` (petits arbres, lampadaires, poteaux bois et béton : `poles.poteaux`, `poles.casser(p, t)`,
  `poles.couper_fils`) basculent et restent couchés. Gros arbres, pylônes, monuments et symboles religieux solides
  (choix de l'utilisateur). Essai : `--casse-genres=poteau,arbre,muret` (vue sur les morceaux `casse_<genre>_3.png`,
  débris restants après 20 s).
  **#123 (v6.82)** : objets posés par lots de `sport.gd` et `autoroute.gd` (`RENVERSABLES`, `objets[case]` = {nm, m, xf,
  cs, pts | a, b}, `casser_objet(o)` cache l'exemplaire et coupe ses boîtes) ; `casse.OBJETS` : comportement
  (« repousse », « couche », « segment » : travée de glissière ou de séparateur, défoncée seulement si la vitesse
  perpendiculaire dépasse le minimum), rayon, masse, matière. Détection des grands objets (banc de touche : 4 m) au
  point de leur boîte le plus proche de la voiture (`_pres`). Débris au modèle de l'objet (`_corps_objet`, posé un peu
  au-dessus de sa place). Essai : `--casse-genres=objet:glissiere,objet:gba,objet:borne_sos` (autoroute :
  `--drive-from=-11240,241,-1610,0`), `objet:banc_touche,objet:mat_eclairage,objet:but_foot` (stade :
  `--drive-from=150,447,500,0`).
- **Écran de chargement** (v6.14, `scripts/chargement.gd`) : `main._ready` construit le monde par **étapes nommées**
  (`await _etape("Routes")`…), une image dessinée entre chaque ; le voile (`voile_demarrage.gd`, posé aussi sur PC)
  affiche l'étape et une barre calée sur la durée de chaque étape mesurée au lancement précédent
  (`user://chargement.cfg`, défauts `DEFAUT`). Pendant le chargement : `set_process(false)`, voiture tenue
  (`car.hold`) ; les essais attendent `Chargement.fini`. Essai :
  `-- --capture-chargement` (captures `user://shots/chargement_N.png`). Toute nouvelle grosse initialisation :
  l'ajouter dans une étape (ou en créer une, avec sa durée par défaut).
- **Jeu sans friction** : rien ne doit gêner le joueur (démarrage direct, commandes souples, pas d'à-coups de
  chargement). **Plus de remise sur la route automatique quand la voiture est bloquée ou coincée** (demande de
  l'utilisateur, v6.22).
  - Restent : le bouton rouge (« replacer »), la voiture retournée, la chute hors du monde.
- **Conduite (v6.22)** :
  - Freinage façon jeu : freins des roues + `BRAKE_AIDE` (7 m/s² roues au sol), soit ≈ 16 m/s², 100 à 0 km/h en
    ~24 m. Essai : `-- --drive-test --brake-test --drive-from=-8410.95,221,-7187.25,45.2` (longue ligne droite).
  - Roues :
    - rayon physique 0,40 m (le modèle n'en fait que 0,267 m), axe abaissé d'autant ;
    - roue affichée à l'échelle (0,40 − 0,045) / 0,267, car la physique de Godot enfonce la roue de ~4,5 cm ;
    - essai `--roues-test` (enfoncement mesuré), capture `{"cam": 0, "place": [...], "cote": 4.5}` (vue de côté).
  - Fracas fort (`audio._fracas`, bus « Voiture ») quand un choc contre le décor arrête net la voiture.
  - Arbres cassables : seulement ceux affichés (`vegetation.visibles(k)`, densité réglable). Avant, des arbres
    non dessinés « surgissaient » cassés devant la voiture.
- **Itinéraire GPS du taxi** (v6.30, demande de l'utilisateur, `scripts/itineraire.gd`, données `world/graphe.bin`
  de `pipeline/build_itineraire.py`, d'après `data/roads.pkl`) : A* sur le graphe des voies carrossables (sens
  uniques respectés, chemins de terre pénalisés ×2,5), calculé sur un fil de travail ; recalculé si la cible change
  ou si la voiture s'écarte de plus de 35 m. Tracé bleu cerné de noir sur la mini-carte (`gps.gd`) et la carte
  (`map.gd`), `activities.route_gps`. Capture : `{"act": "taxi"}`.
- **Aide au maintien dans la voie** (v6.25, demande de l'utilisateur, `scripts/voie.gd`, données
  `world/voies.bin` de `pipeline/build_voies.py`, après `build_map.py`) :
  - quand le joueur lâche le volant (0,8 s), léger braquage vers le milieu de la voie de droite (double sens) ou
    de la voie la plus proche (sens unique à plusieurs voies) ; axe des routes étroites ;
  - rien sous 30 km/h, en marche arrière, aux carrefours, hors de la chaussée ou à contresens d'un sens unique ;
  - témoin (deux lignes de voie) sur le compteur ; réglage ⚙ > Conduite (`conduite/aide_voie`, actif par défaut).
  - v6.40 (« ultra puissante ») : poursuite d'un point au milieu de la voie 6-22 m devant, braquage jusqu'au
    maximum, dès 15 km/h, main rendue 0,35 s après le joueur.
  - Essai : `-- --drive-test --voie-test [--voie-off] --drive-from=-8410.95,221,-7187.25,45.2`.
- **Bâtiments non résidentiels refaits « comme la boulangerie »** (v6.26, demande du 13/10 : la méthode du
  restaurant était insuffisante) — `pipeline/sur_mesure/` :
  - `plan.py <id>` : vue en plan (orthophoto IGN 20 cm, cache `data/ortho_bat/`), emprise, grille en mètres du
    repère `cadre()` (u le long du grand côté) : on y découpe les **volumes** ;
  - `calage.py <id>` : fil de fer du relevé sur chaque photo (façades nommées, repère vert = x 0, grille au sol) ;
    `cams` corrige une caméra Google décalée ; `simplifier`, `decal`, `rot`, `echelle` recalent l'emprise ;
  - relevé à `volumes` (rectangles [u0, v0, u1, v1] en m, chacun sa hauteur, son toit, ses façades) ;
  - `batiment.py <id>` puis import Godot (nouvel atlas : `compress/mode=2` + mipmaps dans son `.import`, et `force_disable_compression=true` dans le `.glb.import`) ;
  - `comparatif.py <id…>` : captures du jeu depuis les caméras exactes des photos, planche photo | jeu.
  - Planches dans le cache privé (`streetview/planches/`), jamais dans le dépôt. Faits : mairie, atelier_kaki,
    église, salle des fêtes, salle du cimetière (liste à jour dans `docs/REPRISE.md`).
  - Options du relevé : `cams`, `sol: haut` (pente), `entourage` (encadrements), `remplace_bati_extra`, volumes
    tournés (`rot`), toits `sheds` (dents de scie), extra `charpente` (préau à ferme apparente), murs `bardageh`.
  - Shader `sur_mesure_une_face.gdshader` (entrées `une_face`) : triangles orientés, toits doublés dans le
    maillage ; en deux faces, les murs s'ombraient eux-mêmes (acné en anneaux). Boulangerie et restaurant : ancien
    shader à deux faces.
  - **Textures partagées (v6.38, solution A de l'issue #13, contre la limite de 2 Go de l'APK)** :
    `sur_mesure/bibliotheque.py` construit `godot/assets/sur_mesure/_bib.png` (12 matières neutres, 4 m par tuile,
    4 × 4 cases de 512 px). Murs et toits : UV = mètres / 4, UV2 = (case + 1, couleur RVB entière) ; le shader
    teinte la tuile (`tuile × couleur / 200`, sans passage en linéaire, sinon les murs sombres sont noirs). L'atlas
    du bâtiment ne garde que les « décalcomanies » (différence peinture / fond : ouvertures, chaînages…) posées à
    9 mm du mur, les panneaux (soubassements, bandes de matière) à 6 mm, les enseignes à 1,2 cm. Ombre d'égout
    faite dans le shader (`COLOR.a × 64` = hauteur d'égout). `SM_BIB=0` : ancien atlas complet.
    **Obligatoire** : `meshes/force_disable_compression=true` dans chaque `.glb.import` (sinon UV2 quantifié, murs
    de travers et couleurs fausses).
- **Bâtiments redressés hors de la chaussée** (v6.25) : le rectangle orienté qui remplace une emprise presque
  rectangulaire (`decompose`) regonflait l'emprise découpée au bord de la route (murs et collisions sur la
  chaussée, jusqu'à 450 m²) ; `rogner_routes` rogne ces rectangles côté route, sinon toit plat sur l'emprise réelle.
- **Relief chargé autour de la voiture** (v6.16, issue #11, `scripts/relief.gd`) : plus de `data_directory` (qui
  lisait les 173 régions d'un bloc : 765 Mo, 8 s) ; régions lues d'avance sur un fil (`R_LIRE` 2,6 km), mises dans
  Terrain3D à moins de `R_CHARGE` (1,8 km), libérées au-delà de `R_GARDE` (`remove_regionl` puis `save_region` vers
  un dossier vide : seul moyen de les sortir de la mémoire de Terrain3D 1.0.2) ; ajouts et retraits groupés en une
  seule `update_maps()` (Terrain3D refait alors toutes ses textures, ≈ 3 ms par région). Au démarrage et à la
  téléportation : régions à moins de 1,2 km chargées tout de suite (`charger_autour`). **Pas de popping** : ailleurs,
  relief de remplacement (`relief.gdshader`, maillage de 32 m) habillé de l'albédo, des normales et de la matière du
  vrai relief cuits par `tools/bake_relief.gd` (`bake_mode` de `terrain.gdshader`), effacé là où le vrai relief est
  chargé (masque 32 × 32), bordure de 32 m glissée dessous. Altitude du sol partout : `Relief.hauteur(p)` (vrai relief,
  sinon grille de secours `world/relief/hauteurs.bin`) — **ne plus appeler `terrain.data.get_height`**. Essais :
  `godot --path godot --script res://tools/essai_relief.gd -- --relief-debug` (trajet de 16 km, mémoire, durées),
  captures `{"relief": 99999}` (tout le vrai relief) contre `{"relief": 1800}`, `"nuages": false` pour comparer.
- **Bâtiments sur mesure** (v6.17, `scripts/sur_mesure.gd` + `sur_mesure.gdshader`, `world/sur_mesure.json`) : un
  modèle par bâtiment refait d'après Street View, façades « en aplat » (choix de l'utilisateur : ouvertures, volets,
  devanture, enseignes peintes dans un atlas avec leurs ombres ; en volume seulement toits, débords, annexes,
  escaliers, rampes, enseignes en drapeau…). Le bâtiment BD TOPO et la devanture remplacés (`remplace_bati`,
  `remplace_commerce`) sont sautés par `build_buildings.py` et `build_shops.py`. **Boulangerie de Rochetoirin**
  (`pipeline/boulangerie/` : `releve.md` = relevé, `calage.py` = fil de fer projeté sur les photos,
  `build_boulangerie.py` = atlas + modèle, `abords.py` = haie/grillage retirés devant la façade, à relancer après
  `build_fences.py`) ; photos dans le cache privé `streetview/boulangerie/` (index : position exacte de chaque
  caméra). Mesures par visée depuis plusieurs panoramas (position, cap, inclinaison, champ connus). Comparatif :
  captures `--shots` aux mêmes positions/caps que les photos, `--resolution 640x640` (champ vertical = horizontal).
  **Photos Google jamais dans ce dépôt** (planches photo/jeu : cache privé seulement). Régénérer les bâtiments
  refait toutes les tuiles : vérifier que seules celles du bâtiment changent (empreintes contre la branche
  `donnees`) et remettre les `.import` publiés (Godot leur donne de nouveaux identifiants).
- **Aplats partout** (v6.18, directive de l'utilisateur, `docs/kb/aplats.md`) : `build_buildings.py` ne fait plus
  aucune micro-géométrie (`wall_edge` : menuiserie au nu du mur, plus de tableaux, d'appuis saillants ni de kit 3D
  fenêtre/volet/porte/garage/marquise ; volets et appuis = quads collés à 1 cm ; fenêtres de comble idem) ;
  `build_bld_tex.py` peint l'ombre d'embrasure dans les couches fenêtre/porte/vitrine (`embrasure()`) ;
  `build_shops_plats.py` (après `blender_commerces.py`) remplace vitrine, porte, pilastre, coffre de rideau, porte
  sectionnelle, bardage, bandeau, caisson d'enseigne et affiche par des quads plats (une vitrine : 652 -> 14
  triangles). Le kit `assets/maisons` ne sert plus qu'aux faîtières, mitrons, antennes et paraboles.
- **Fiches rapides des bâtiments** (v6.18, `pipeline/sources/bati_fiches.txt`, `fiches_overrides` de
  `build_buildings.py`) : « cleabs niveaux toit façade volets [usage=… chainage=#rrggbb porche=tuile|verre h=…] ␣␣#
  commentaire », façade = code de `shops_bati.txt` ou `crepi#rrggbb`, volets = code ou `#rrggbb`. Depuis la v6.20, la méthode pour les bâtiments non résidentiels (directive du 13/10) n'est plus la fiche mais **celle du
  restaurant « Le Rochefestin »** : modèle sur mesure en aplats d'après Street View (voir `docs/kb/aplats.md`). La
  fiche ne sert plus que pour un bâtiment peu visible sur les photos.
- **Performances, 5 directives de l'utilisateur** (v6.19, `docs/kb/performances.md`, à respecter partout) :
  - tuiles lues en arrière-plan (`chargeur.gd`, désormais aussi pour l'eau) ;
  - pas d'occlusion possible en Compatibility ; LOD générés à l'import ;
  - MultiMesh pour le décor répété ; réserve de débris dans `casse.gd` (plus de `new`/`queue_free` en jeu) ;
  - un atlas et un shader par famille ; **aucune transparence mélangée** (tramage Bayer + `discard` ou `ALPHA_SCISSOR` ;
    `ALPHA_HASH_SCALE` des shaders maison ignoré en Compatibility ; vitres opaques) ; vitrines en Interior Mapping (`shop.gdshader`, kind 6) ;
  - collisions du décor en **BoxShape3D seulement** (bâtiments : `c_<tuile>.bin` produit par `boites()` dans
    `build_buildings.py` ; clôtures : une boîte par segment). Routes et relief exclus : c'est la surface de roulage.
- **Restaurant « Le Rochefestin »** (v6.20, `pipeline/boulangerie/build_restaurant.py`, relevé `releve_restaurant.md`) :
  - sur mesure comme la boulangerie, avec ses outils de peinture et de maillage et le même repère ;
  - photos du cache seulement ; seuls les titres sont lisibles ;
  - `sur_mesure.json` est maintenant **fusionné** : chaque script n'y met que sa propre entrée.
  - Après `build_shops.py`, publier **toutes** les tuiles `world/shops` avec les atlas d'enseignes. Retirer un commerce
    décale les cases des enseignes suivantes, donc remettre d'anciennes tuiles afficherait de mauvaises enseignes
    (erreur corrigée avant la livraison de la v6.20).
- **Bâtiments non résidentiels sur mesure** (v6.21, `pipeline/sur_mesure/`) :
  - `fetch_sv_batiments.py [commerces|industriels|agricoles]` : 2 à 3 photos par bâtiment visible depuis une route
    (moins de 70 m), dans le cache privé `streetview/batiments/` (index : caméra, cap, champ). Plafond de 700 photos ;
    1,73 $ dépensés pour les 138 bâtiments de Rochetoirin.
  - `releves/<id>.json` : un relevé par bâtiment, écrit en regardant les photos (format en tête de `batiment.py`) :
    - matière des murs, toit, hauteurs ;
    - ouvertures par façade, en fractions vues de dehors ;
    - enseignes au nom parodique, affichettes (seuls les titres lisibles), extras (auvents, stores, porches,
      silos, clocher, contreforts…), `ouvert` pour les abris sur poteaux.
  - `batiment.py [id…]` : le moteur.
    - Emprise du cadastre, sol du relief terrassé.
    - Murs peints dans un atlas de 1024 px, compressé à l'import.
    - Enseignes et affichettes en aplats haute définition, 1,2 cm devant le mur.
    - Toits par rectangles (`decompose`), sinon toit plat qui suit l'emprise.
    - Collisions en boîtes ; entrée dans `world/sur_mesure.json`.
  - 102 bâtiments faits : 20 commerces et services, l'église et la mairie, 62 industriels, 20 agricoles. Les 34 qui ne
    se voient d'aucune route gardent leur volume généré.
  - `sur_mesure.gd` les charge autour de la caméra (1,1 km, en arrière-plan) et les libère au-delà de 1,4 km ;
    `Env.remove` oublie leurs matériaux.
  - `build_shops.py` ne pose plus de devanture générique sur un bâtiment refait, ni de commerce OSM à moins de
    6 m de lui.

