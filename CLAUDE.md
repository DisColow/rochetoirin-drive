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
- **API Claude (payante, crédit de l'utilisateur) : uniquement pour l'actualité du jour** (`actu.yml`, ~0,40 $/jour).
  Tout autre usage (génération ponctuelle de textes, essais…) **demande l'accord explicite de l'utilisateur avant**,
  avec le coût estimé ; ne jamais changer de méthode en cours de route sans le lui redemander. Les textes du jeu
  s'écrivent par Claude Code directement (pas par l'API). Les rebonds du 12/10 (`taxi_rebonds.py`, ~4,50 $) ont été
  générés par l'API sans cet accord : erreur à ne pas reproduire ; l'action `taxi_rebonds.yml` est en lancement
  manuel seulement.
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
  `ao_region`), `build_grass_tex.py`, `build_zone.py` (limite de la carte pour le gardien), `build_epreuves.py` (épreuves chronométrées, après `build_places.py`), `build_nuages_tex.py` (nuages du ciel peint), `build_touffes.py` (touffes des champs façon San Andreas, après `bake_cultures.gd --seulement=plants`), `build_vinyles.py` + `fetch_garage.py` + `blender_garage.py` (garage), `blender_makehuman.py` (clients du taxi MakeHuman : MPFB 2 en extension Blender + pack « makehuman_system_assets » CC0, voir docs/REPRISE.md), `fetch_ufo.py` + `blender_ufo.py` (soucoupe du gardien),
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
  la demande (`car.set_sprite_mode`). Contrôle : `-- --mem-test` (mémoire vidéo, textures, tampons). **Le gel persiste
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

