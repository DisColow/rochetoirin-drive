# Reprise du travail (tenu à jour à chaque étape)

Fichier lu en premier par toute nouvelle session (ou après une coupure : limite d'utilisation, conteneur
recyclé). Mis à jour et poussé après chaque livraison et chaque étape importante.

## État au 17/10/2026 (v6.64)
- Branche `godot`, worktree `rochetoirin-godot`. Tirer : `GIT_LFS_SKIP_SMUDGE=1 git pull --rebase origin godot`.
  Sauvegarde du travail en cours : `git push -f origin HEAD:refs/heads/zone-wip`.
- Données générées : branche `donnees` (`pipeline/publier_donnees.sh`). Après une régénération des bâtiments,
  remettre les `.import` publiés : `git fetch origin donnees` puis, pour chaque `world/buildings/*.import`,
  `git show FETCH_HEAD:world/buildings/<fichier>` (Godot donne sinon de nouveaux identifiants), puis réimporter.
- Captures : `--shots=<fichier.json>` (un CHEMIN de fichier, pas du JSON en ligne).
- Street View : **plafond de 9 000 images par mois** (`pipeline/sv_budget.py`, compteur `pipeline/sources/sv_depenses.json`).
- Réveil automatique de la session toutes les heures (routine « Reprise après limite d'utilisation », h+07).
- Pièges des essais : `pkill -f "[g]odot --path"` tue aussi le shell (motif présent dans la commande) : utiliser
  `pkill -x godot` ; les menus mettent le jeu en pause (`hud._show_drive(false)`) : un essai qui attend des images
  doit remettre `get_tree().paused = false` ; une étiquette `autowrap` dans une rangée (HBox) fausse la mise en page.
  Transcription d'un vocal : venv `scratchpad/fw` (faster-whisper, modèle « small », `language="fr"`).

## À faire (vocal du 17/10, issues #105 à #121 ; faits en v6.63 : #104 #105 #106 #107 #110 #111 #112 #119 #121)
- #108 plus d'épreuves ; #109 modèles de voitures à corriger (captures de chacune) ; #113 gare de La Tour-du-Pin sur
  mesure (photos du cache d'abord, annoncer les appels Street View) ; #114 fausses affiches de cinéma ; #115 terrains
  multisports (cages + paniers) ; #116 ombres plus loin ; #117 champs (fauchage plus large, blé en sprites, maïs en
  simple aplat) ; #118 herbe de bien plus loin ; #120 proposition de mode carrière (pas de développement).
- #105 : clôtures et murets font encore perdre ~6 km/h (casse.gd ne freine plus ; à chercher : boîtes voisines ?
  essai `--casse-test --casse-genres=cloture,muret --casse-debug`).

## v6.63 (17/10)
- #110 astuces sans fondu (`voile_demarrage.gd`) ; #111/#104 `radio.flash_permis()` (volume musique, `radio.taxi`
  tenu par `taxi_talk.gd`), essai `--flash-test` ; #105 plus de perte de vitesse dans `casse._casser`, corps de
  clôture retiré tout de suite (`fences.breche`) ; #106 `car._glisse_mur` (vitesses imposées le long du mur),
  essai `--mur-test [--mur-angle=°] [--mur-loin=m]` ; #121 `car.exploser()` + `champignon.gd` (déclenché par
  `audio.gd` : vitesse perdue d'un coup > 60 km/h contre dur/métal/bois) ; #107 numéros `Label3D` au-dessus des
  portes et `_itineraire` pendant la course ; #119/#112 `menu_activites.gd` (plein écran, onglets) +
  `carte_trace.gd` (carte du tracé par les routes) + `garage.records` (meilleurs temps) ; essai `--epreuves-menu-test`.

## v6.62 (16/10)
- #95 livré (voir la section « Voitures du garage » de CLAUDE.md) : 10 voitures, faux logos, Laguna peinte, cockpits,
  mini-carte sans GPS, voiture des autres joueurs. Essais `--voitures-test`, `--garage-voitures-test`.
- Idées de suite : cockpits encore plus détaillés (celui du pick-up reste le plus fin), son de moteur propre à
  chaque voiture (aujourd'hui : même enregistrement, plus aigu ou plus grave), Espace : quelques taches sombres
  de la simplification du modèle.

## v6.61 (16/10)
- #84 : sons 4B (bois) et 5B (verre) de la 2e série : `pipeline/compo_chocs.py` (composites, sources du scratchpad)
  -> `data/sons/compo_4_B.wav`, `compo_5_B.wav` -> `build_sons.py` (`bois_casse_0-2`, `verre_0-1`). Essai
  `--sons-test --sons-log` (journal `[son]`).
- #102 : logo détouré (`pipeline/sources/logo_detoure.png`, originaux à côté), icônes Android
  (`assets/logo/icone_192|avant|fond.png`), splash de boot, `scripts/ecran_titre.gd` (fond du boot et du voile,
  calé en haut). Nom du jeu inchangé (« Rochetoirin Simulator ») : question posée.
- #95 en cours : `fetch_voitures_joueur.py` (9 modèles, `godot/import/voitures/<id>`, `.gdignore`),
  `blender_voitures_joueur.py` -> `assets/voitures/<id>/`. Reste : faux logos, Laguna peinte, car.gd paramétré,
  garage achat/changement, cockpits pixel art par voiture, mini-carte sans GPS, voiture des autres joueurs (net.gd).
- Disque : penser à vider `~/.cache/speech-dispatcher` (500 Mo) et les captures.

## v6.60 (16/10)
- #103 : `camera_rig.gd` `CRANS` (5,3 / 7,6 / 10,5 m), `cran` ; cycle proche > moyen > loin > conducteur > capot.
  Essai `--crans-test`. #102 : images non reçues (échec d'envoi GitHub), redemandées, `pending`.

## v6.59 (16/10)
- #99 : `scripts/armes.gd` (caisses « ? » sur le tracé, une arme à la fois, bouton ARME / F / croix ↑ ; boule, onde,
  bouclier, tornade) ; net.gd : `armes_actives` envoyé avec la course, RPC `_subir`, `tir_vu`, `bouclier_vu` ;
  bouton de l'hôte « Courses à armes » (menu Multijoueur). Ids : réseau > 0, cibles d'essai < 0, 0 = personne.
  Essai sans réseau `--armes-test` (sur la ligne droite --drive-from=-8410.95,221,-7187.25,45.2). NON VÉRIFIÉ :
  vraie partie à deux appareils.
- À faire : #95 voitures (choix attendu) ; #84 sons (choix attendu) ; #96 logo/splash (images pas reçues).

## v6.58 (16/10)
- #94 : catalogue garage + allegement, anti_roulis, differentiel, phares, pare_buffle, galerie (tuning.gd) ; car.gd
  `adherence` (bug : wheel_friction_slip réécrit à 2,6 à chaque pas, pneus sans effet), `anti_roulis`, `set_phares`.
  Essai `--garage-test` (adhérence 3,56 en roulant, masse 2 100 kg). v6.57 : nitro (#98), 11 vinyles.
- À faire : #99 courses à armes (multijoueur, caisses « ? », boule de feu, onde de choc, bouclier, tornade/aimant) ;
  #95 voitures (planche envoyée, choix attendu ; Laguna : aucun modèle libre texturé) ; #84 sons (2e série en attente) ;
  #96 logo/splash (images pas reçues).

## v6.57 (16/10)
- #92 camera_rig : lissage dans le repère de la voiture (`_org`), hauteur 2,6 m, visée 4,5 m devant, champ +4° max ;
  essai `--camera-test` (avant 5,7 -> 11,6 m à 100 km/h ; après 5,3-6,4 m).
- #93 map.gd : `touches` vidé à l'ouverture, téléportation seulement pour un doigt posé dans la carte ouverte ;
  essai `--carte-test` (cas 1 : 3 536 m -> pas de téléportation).
- #96 astuces : `godot/data/astuces.json` (astuces + anecdotes), voile_demarrage.gd (7 s, fondu). Logo et splash
  screen de l'utilisateur : images jamais reçues (deux envois sans pièce jointe).
- Clé Sketchfab : `~/.config/rochetoirin/sketchfab_token` (hors dépôt, chargée par ~/.bashrc dans SKETCHFAB_TOKEN) ;
  conteneur seulement : pour les sessions neuves, elle doit être dans les réglages de l'environnement.
- En cours : #95 voitures à acheter (planche de modèles Sketchfab à proposer), #94 vinyles et améliorations.

## v6.56 (16/10) — preuves jointes aux tickets (nouvelle règle CLAUDE.md)
- Vérifs de la v6.55 : #81 essai champ ignorait NIVEAU (corrigé) ; plants : 3 constructions parallèles (TACHES),
  cases vides réglées par lots ; #88 RESSORT 40 m jamais atteint (39,3 m à 100 km/h) -> 32 m, essai `--ressort-test` ;
  #89 garde-corps coupés aussi sur les chemins de terre (chaussees_u) : 37 -> 0 positions sur une chaussée ;
  #85 essai `--casse-test --casse-genres=grillage_sport --drive-from=505,434,540,0` ; #82 essai `--regard-test`.
- Piège : `pgrep -f motif` dans une boucle d'attente se trouve lui-même (le motif est dans sa propre ligne de
  commande) : attendre par PID (`kill -0`).
- #91 car.gd `pedale()` : valeur brute de l'action, course pleine calée sur le plus grand enfoncement vu (≥ 0,8),
  zone morte 15 % ; marche arrière 0,75 × force jusqu'à 45 km/h. Essai `--drive-test --gachettes-test`
  (gâchette plafonnée à 0,82 -> pédale 1,00).
- #90 build_fences : propriétaires = usage « Résidentiel » seulement (ou « Indifférencié » relevé sur Street View) ;
  2700 tuiles, 0 point sur la route ; abords.py et build_props relancés.

## v6.55 (16/10) — retours vocaux du 16/10, issues #81 à #89
- #81 crops.RANGE [80,105,130,160], densité pleine jusqu'à 25 m puis 15 % au bord ; #82 a_pied : axe Y inversé.
- #83 build_fences : plus de morceau laissé ouvert le long d'une allée privée (place() retire l'emprise) ; abords.py
  relancé ; build_props relancé (aucune tuile changée). 446 tuiles de clôtures changées.
- #84 sons de chocs : page d'écoute https://claude.ai/artifact/2MaSpmQYWKaLWHu16f9Z1h ; choix « 2C » : tole_0-4 =
  metal_slam_01 (OpenGameArt CC0, data/sons/oga_metal_slam_01.ogg), le reste inchangé.
- #85 casse.gd : muret 2,5 m/s, piliers de portail (BOX, genre 3 « pilier ») ; grillages de sport (sport.grillages,
  sport.breche). Essai `--casse-test --casse-genres=muret,pilier --casse-vitesse=4.5`.
- #86 water.gd : plans d'eau (UV2 nul) rangés par cases de 8 m, niveau_plan(p) ; voiture sous niveau + 0,25 m ->
  plouf (Mixkit 1180), gerbe, figée, s'enfonce 3,2 s, reset_to_road. Essai `--drive-test --eau-test --eau-debug`.
- #87 boulangerie : poubelles déplacées à côté de l'escalier (a -1,2..-0,6). #88 bord.gd : RESSORT 40 m, son
  « ressort » (Mixkit 2894). #89 build_roads : _hors_chaussee() coupe les parapets des ponts dans leurs 15 premiers
  et derniers mètres là où ils entrent sur une chaussée (92 tuiles changées).

## Livré : v6.53 (16/10 nuit, correctif) et v6.54 — issue #80 (mode piéton)
- v6.53 : bouton VOITURE (remonte d'où qu'on soit), voiture figée (freeze) à pied, gps/map suivent le piéton.
- v6.54 : a_pied.gd sticks virtuels (moitié gauche/droite du bas de l'écran, hors boutons), saut sur l'action
  « frein_main » (bouton SAUT), balancement de tête + tassement à la réception ; main._teleport -> pied.rejoindre_voiture()
  (dégèle la voiture 2 s pour qu'elle retombe) ; crops.RANGE [35,60,85,110] et éclaircissement jusqu'à 25 % au bord.
- Attention : un push sur godot annule le build APK en cours (concurrence apk.yml) : attendre la fin avant de pousser.

## Livré : v6.52 (16/10) : balises des épreuves (#78), saisie (#79, nav_physique ignore les touches quand un LineEdit/TextEdit a le focus ; UI.saisie_active() bloque les raccourcis)

## Livré : v6.51 (15/10 nuit), APK 1 574 Mo — tickets #66 à #77
- #66 à pied : `scripts/a_pied.gd` (CharacterBody3D, caméra 1re personne retournée de 180°, `main.suivre(n)` fait
  suivre le chargement du monde, `car.controle`) ; action « pied » (E / Y), caméra déplacée sur le clic du stick droit.
  Essai `--drive-test --pied-test`.
- #67 radio : journal +9 dB et filtre moins sourd (`radio._en_journal`), titres lus à plein volume.
- #68 feux tricolores : mâts « metal_dark » relevés par `build_casse.py`, ampoules effacées (`signal_light.gdshader`).
- #69 croix des réglages : bande du haut réservée (`content_margin_top` 92), `hud._fermer_reglages`.
- #70 GPS cockpit ignoré quand un menu est ouvert. #74 points de téléportation dans les deux sens (`build_map.py`)
  + sens de la marche d'après la vitesse (`car.reset_to_road`). #75 part « temps » du pourboire (bonus, sans chrono).
- #71 : fils filtrés par âge et métier (`taxi_talk.FIL_AGE`, `_fil_possible`), réponses génériques seulement sobres et
  hors questions / sujets tristes ; accords de genre corrigés dans les sources. #72 : `taxi_talk._bourre`, débit 0,78,
  caractère tiré à l'apparition (`choisir_caractere`), `pieton.ivre`.
- #73 : plus de « rien » dans les tirages de `build_fences.py` (façade relevée « rien » -> muret) ; régénérer
  fences + `boulangerie/abords.py` + props + `build_casse.py`.
- #76 : grillage d'autoroute cassable (`autoroute.grillages`, genre « grillage » de `casse.gd`).
- #77 : animations Quaternius (UAL 1 et 2, CC0, opengameart) -> `pipeline/data/anim/`, `blender_animer_clients.py`
  (transfert par rotations monde, bras réalignés T -> A) ; `pieton.gd` joue marche / titube / attente_0-3.

## Livré : v6.49 (15/10 soir), APK 1 564 Mo — #53 (suite) et #55
- #53 : `activities.gd` : sortes de course `normale` / `arret` (on attend le client à un lieu en chemin, compteur au
  tarif d'attente, `ARRETS`) / `retour` (on revient le chercher après la course suivante, même client et même
  modèle, il raconte : `RETOURS`, `_rappel`) ; plus de retard dans la note (`_stars` = chocs) ; réponses génériques
  par ton (`taxi_talk.GENERIQUES`, 35 %, sans rebond). Essai : `--drive-test --taxi-test [--taxi-sorte=arret|retour]`.
- #55 : clients MakeHuman `assets/clients/mh_0-9.glb` + `mh.json` (`pipeline/blender_makehuman.py`). Installation :
  venv bpy ; `git clone --depth 1 https://github.com/makehumancommunity/mpfb2` ; lien
  `~/.config/blender/5.0/extensions/user_default/mpfb` -> `mpfb2/src/mpfb` ; pack
  `https://files2.makehumancommunity.org/asset_packs/makehuman_system_assets/makehuman_system_assets_cc0.zip`
  décompressé, sous-dossiers liés dans `~/.config/blender/5.0/extensions/.user/user_default/mpfb/data/`.
  Marche procédurale `pieton.gd` (os du squelette game_engine, `cible` + signal `arrive`), téléportation
  `activities._teleport_fx` + son `teleport` (BSB 572). Essai : `--drive-test --pieton-test`.

## Livré : v6.48 (15/10 après-midi)
- Zone #50 : commune de L'Isle-d'Abeau entière + route Montcarra > L'Isle-d'Abeau (par 45,6356 N 5,2426 E) ;
  228 régions, 189 km². BB des fetch_*.py : 45,51-45,67 / 5,165-5,53 (bande ouest téléchargée seule puis fusionnée).
  Après régénération : `.import` publiés remis depuis `donnees` (`git ls-tree -r` DEPUIS LA RACINE du dépôt, puis
  `git cat-file blob` en parallèle), import par paquets, `import_terrain.gd`, `bake_relief`, import.
- Épreuves (#59) : `build_epreuves.py` -> `world/epreuves.json` (14 épreuves entre lieux publics, médailles d'après le
  temps de l'itinéraire le plus rapide) ; `activities.gd` (`reperes_epreuves`, `_epreuve_proche`, `_epreuve_fin`),
  médailles dans `garage.medailles` ; drapeaux sur la carte et le GPS. Argent sous le compteur (`hud.argent_panel`).
- Radio #56 : station « Rochetoirin Info » ajoutée par `radio.gd`, contenus de `radio_infos.gd` (flash 20 Minutes ou
  RTL en MP3 — Radio France est en AAC, illisible par Godot —, titres franceinfo + Dauphiné lus par la voix du téléphone).
- Nuages #57 : `ciel_peint.gdshader` (heures 1-3 et temps couvert ; midi = HDRI), texture `assets/fx/nuages.png`
  (`build_nuages_tex.py`) ; pas de TIME (le ciel se recalcule entièrement quand il change).
- Interface : rangée du haut repliable (`hud.replier`, repliée en activité), plus de bouton carte (#58 ; carte
  bornée `map._borner`), icône activités = drapeau + clé (`build_ui.py`), GPS cockpit -> carte (`cockpit.ouvrir_carte`,
  mini-carte cachée en cockpit, #60), compteur taxi 150 px de haut à (24, 136) (#52).
- #54 : 6 vinyles de plus (10 bandes dans `vinyles.png`) ; jantes : le pneu à crampons fait partie de la CAISSE du
  Raptor, la nouvelle roue est réduite (`DANS_LE_PNEU` 0,74) ; J3 retournée (`JANTES_RETOURNEES`).
- #53 (partie) : réponses du taxi au 2e doigt (`taxi_talk._input`). Reste : courses avec attente / retour plus tard,
  réponses qui varient. #55 (personnages MakeHuman qui marchent) : à faire.
- Essais : `--garage-test [--jantes]`, captures `{"haut": degrés}` (caméra relevée, ciel).
- **Quota Git LFS du dépôt dépassé** (v6.48) : l'étape « Dépôt de l'APK dans releases/ » d'`apk.yml` échoue (rendue
  non bloquante) ; l'APK est publié dans la release GitHub. Pousser la branche de travail SANS LFS :
  `git push --no-verify -f origin HEAD:refs/heads/zone-wip` (sinon l'APK de 1,5 Go repart à chaque fois).

## Livré : v6.47 (15/10 midi), APK 1 486 Mo — garage, ciel, sauvegarde ; en cours : v6.48 = zone L'Isle-d'Abeau (#50)
- Garage (#43, tout d'un coup, payé avec l'argent du jeu) : `garage.gd` (catalogue `CATALOGUE`, argent et pièces dans
  `user://garage.cfg`, `apercu` = essai non acheté), `tuning.gd` (effets : variables `puissance`, `force_max`, `vmax`,
  `freinage` de car.gd, roues, `carrosserie.gdshader` = couleur/finition/vinyles dans le repère de la voiture,
  vitres, néons, pièces), `garage_ui.gd` (menu ★ > Garage, voiture arrêtée ; `camera_rig.vitrine`), primes dans
  `activities.gd` (taxi = course + pourboire, course = 2 €/100 m + 15 € record, chasse = 25 €). Modèles : tous ceux
  de la planche (`fetch_garage.py` + `blender_garage.py` -> `assets/garage/aileron_1-5`, `echappement_1-4`,
  `jantes_1-5`, calés dans le repère de la voiture) ; prise d'air, enseigne TAXI, barre de LED, jupes : formes simples
  dans `tuning.gd`. Vinyles : `build_vinyles.py` -> `assets/garage/vinyles.png`. Échappement : `audio.echappement`.
  Essai : `--drive-test --garage-test` (captures `garage_N.png`).
- Ciel (#46, choix laissé à Claude, sans montgolfière) : `ciel.gd` + `trainee.gdshader`, modèles `fetch_aeronefs.py`
  + `blender_aeronefs.py` (A3 Cessna 172, B1 avion de ligne, H2 hélicoptère, P1 planeur), sons `avion_passage`,
  `helico_passage`, `ligne_passage` (build_sons.py). Essai : `--drive-test --ciel-test=<type>`.
- Sauvegarde (#51) : `sauvegarde.gd` (position et cap, `user://partie.cfg`, toutes les 30 s et en quittant).
- #48 saisie : la fenêtre de `UI.ouvrir_saisie` doit être `PROCESS_MODE_ALWAYS` (les menus mettent le jeu en pause
  via `hud._show_drive(false)`) ; « Valider » en haut. #49 : `itineraire.restant()` + flèche dessinée après le tracé.
- #47 : `vegetation._exit_tree` attend la tâche du fil de travail (plus de plantage à la fermeture).
- Défilement au doigt commun : `defilement.gd` (réglages et garage).
- Issues à tester : #43, #46, #47, #48, #49, #51.
- `publier_donnees.sh` : récupère la branche `donnees` sans le contenu des fichiers (`--filter=blob:none --depth=1`) ;
  un `git fetch` complet (plus de 1,8 Go) remplissait le disque de la session.
- #50 en cours : `routes_plan.py` modifié (228 régions, 189 km²) ; BB des fetch_*.py mis sur la bande ouest
  45,51-45,67 / 5,165-5,19 (à remettre à 5,165-5,53 après fusion) ; anciens fichiers dans
  `scratchpad/zone650/old/`, fusion par `scratchpad/zone650/merge.py <ancien> <bande> <sortie>` (à recréer si
  perdu : ajout des features/éléments d'identifiant inconnu).
- #50 (v6.48) : route Montcarra -> (45.6356, 5.2426) -> impasse des Glycines (45.6265, 5.2181) + commune de
  L'Isle-d'Abeau entière (~+10 km²) ; BB des fetch à étendre à l'ouest (5,17°) ; procédure par bande comme en v6.45.

## Livré : v6.46 (15/10 matin), APK 1 477 Mo
- Issues à tester : #27, #31-#42, #44, #45 ; en attente de l'utilisateur : #43 (tuning), #46 (planche du ciel) ; #47 :
  plantage à la fermeture sur PC (essai « champ »), cause non trouvée (pas le code v6.46 : scripts v6.45 aussi).
- Essais en jeu : tuer `speech-dispatcher` planté (`pkill -9 -x speech-dispatch`, jamais `pkill -f`), sinon Godot
  se bloque à l'étape « Interface ».
- Zone sans trous (`routes_plan.py` : `Polygon(Z.exterior)`) : 215 régions, ~178 km² (issue #33 : routes sans relief).
- Ponts OSM de moins de 10 m = chaussée ordinaire (`build_roads.py`, issues #31/#32 : tablier en béton et parapets
  au milieu des carrefours). Clôtures : rien dans un disque autour de chaque carrefour (`build_fences.py`).
- Clôtures des prés défonçables (`animaux.gd`, issue #27/#41) ; poubelles physiques de 15 kg (`props.gd`).
- Sons des chocs contre les murs (#40) : `coup_sourd` (Mixkit 1704), `froisse_0/1` (Mixkit 1616), `eboulis` (1703),
  tôle plus grave ; troncs = bois, bêtes = sol ; journal `--choc-debug`.
- Taximètre (`taximetre.gd`, #44), catapulte du bord (`bord.gd`, #45), saisie tactile `UI.saisie_tactile` (#39),
  défilement des réglages (`hud._input`, #38), interrupteur de l'aide à la voie (#37), noms de la carte (#36), zoom
  du GPS du cockpit (#34).
- Taxi (#42) : caractères `ivre`, `colere`, `vip` (champ `sujets` : fils propres, abordés d'abord, réservés) ;
  fils `pipeline/sources/taxi_fils_v646_source.py` -> `taxi_fils_v646.json`, fusionnés par `taxi_dialogues.py`.
- En attente du choix de l'utilisateur : #46 (planche des objets volants), #43 (plan du tuning).

## Livré : v6.45 (14/10 au soir), APK 1 466 Mo
- Issues à tester : #15, #16 (zone), #25, #8 (plantations), #28 (chocs), #29 (GPS du cockpit) ; #30 fermée.
- Actions GitHub : import par paquets (`.github/scripts/import_paquets.sh`) + 12 Go d'échange : obligatoire depuis
  la zone agrandie (le serveur s'arrêtait). Un push qui ne touche que `.github/scripts/` ne relance rien :
  `gh api -X POST repos/DisColow/rochetoirin-drive/actions/workflows/apk.yml/dispatches -f ref=godot`.
- Prochaine étape : rien en cours ; attendre les retours (étiquettes « à tester »), sinon issues ouvertes.

## Fait en v6.45 : zone agrandie (#118, #128 ; issues #15, #16) et plantations (issues #25, #8)
- Zone (`pipeline/routes_plan.py`) : communes entières Montcarra, Saint-Didier-de-la-Tour, La Chapelle-de-la-Tour ;
  routes Montcarra / Chamont / Saint-Chef > Bourgoin-Jallieu (couloirs de 450 m) ; 209 régions, ~149 km².
- Emprise des téléchargements (BB des fetch_*.py) étendue au sud : 45,51° (Saint-Didier). Ajout fait sur la seule
  bande 45,51-45,53 puis fusion par identifiant avec les données existantes (pas de re-téléchargement complet, pour
  ne rien changer ailleurs). `data/dem/pano.npy` n'existe plus : `build_assets.py` garde alors `far/pano.glb`.
- Overpass : overpass-api.de répond 406 au proxy, maps.mail.ru souvent 504 : relancer jusqu'à réussite.
- Plantations (issue #25, « ça rame ») : `crops.gd` calcule les cases sur un fil (WorkerThreadPool : plants + sol,
  hauteurs lues dans la grille de 4 m de la case, plus d'appel au relief par sommet), instances mélangées puis
  `visible_instance_count` selon la distance (100 % de près, 40 % au bord de la portée).
- Plants écrasés (issue #8) : `dust.eclats_plants` = morceaux découpés dans l'atlas des plants
  (`eclats_plants.gdshader`), qui tournoient, planent et se posent ; `audio.feuillage()` : froissement
  (BigSoundBank 1811-1815, Miscanthus) et tiges cassées (1299, 1300) pour maïs et tournesol.

- Chocs (issue #28) : `audio.impact(matière, force, pos, casse)` superpose des couches (objet, tôle du Raptor, tôle
  lourde > 8 m/s, verre et débris > 11 m/s) ; matière = méta `matiere` de la boîte touchée (clôtures : par tronçon,
  `fences.MATIERES`), du corps (voitures garées actives, autoroute, joueurs distants), sinon d'après le chemin du nœud ;
  raclement en boucle contre métal ou dur ; `casse.gd` appelle `impact(..., true)`. Sons : BigSoundBank (tôle 1771-1776,
  barrières 2358-2360, grille 683, pierres 1022, poubelle 1266) et Mixkit (`fetch_sons.mixkit` : verre 1551/759,
  débris 1562, métal 2980/833, bois 2182, effondrement 2958, canette 389).
- GPS du cockpit (issue #29) : `gps.gd` avec `mini = true` dans l'écran central (`cockpit.gd`, `meta.screen_map`
  ou [314, 31, 48, 47]), taille fixée à la main (pas d'ancres dans le SubViewport).
- Import Godot qui manque de mémoire (code 137) : ne PAS utiliser `.gdignore` (tout est réimporté à leur retrait) ;
  sortir les fichiers du projet et les remettre par paquets de 700 avec un import à chaque fois.

## Fait en v6.44 : multijoueur jusqu'à 4 (#139, issue #20)
- `scripts/net.gd` (nœud « Net » de main) : ENet port 47601, annonces UDP 47602 (diffusion), état des voitures
  20 Hz (unreliable_ordered), voitures distantes = body.glb + roues + AnimatableBody3D (collision), Label3D du nom,
  couleur par rang ; course : `lancer_course` (hôte) -> `activities.course_reseau(route, rang)` (départ 9 m × rang
  derrière) ; arrivées et gains du taxi partagés (toasts de classement). Menu : Activités > Multijoueur.
- Essai local : hôte `-- --net-host`, invité `-- --drive-test --net-join=127.0.0.1` (lignes « [net] » toutes les 2 s).
- Android : permissions access_network_state, access_wifi_state, change_wifi_multicast_state. Sans « multicast
  lock » certains téléphones ne reçoivent pas les annonces : l'adresse de l'hôte est affichée pour la taper.

## Fait en v6.43 : cockpit du Ford Ranger Raptor (#133, issue #17)
- `pipeline/build_cockpit.py` : dash() / top() / wheel() redessinés (rampes black, orange, magnesium, screen) en
  gardant les repères de meta.json (compteurs, écran = LCD, voyants, PRND, rétro). Ancienne version (Espace I) :
  scratchpad build_cockpit_espace.py.

## Fait en v6.42 : clôtures des pâtures (#135, issue #18)
- `build_animaux.py` : pré = parcelle RPG privée de l'emprise des routes (ROAD.cut) ; clôture = contour intérieur
  (0,7 m) sans coupure aux routes ; bêtes dans le pré. Limites de propriétés : inchangées (rue du Balcon relevée
  maison par maison d'après Street View : certaines façades sont réellement ouvertes).

## Fait en v6.41 : terrains de sport (#136, issue #19)
- `build_sport.py` : 9e valeur d'un terrain = hauteur aplanie (max du relief sous le terrain + 1 m de marge,
  + 5 cm) ; équipements sur le terrain posés à cette hauteur ; buts sur la ligne de but (L/2 - 1, les tracés sont à
  1 m du bord) ; paniers à 1,2 m de la ligne de fond.
- `sport.gd` : surface plane à H + talus (UV2 < 0, herbe naturelle dans pitch.gdshader) jusqu'au relief, collision
  en trimesh (on roule dessus). Captures : --shots (sport_shots.json dans le scratchpad).

## Fait en v6.40 : aide au maintien dans la voie ultra puissante (#143, issue #26)
- `scripts/voie.gd` : poursuite d'un point au milieu de la voie, 6 à 22 m devant (0,55 s × vitesse) ; K_VISEE 2,4,
  braquage jusqu'au maximum, dès 15 km/h, main rendue 0,35 s après le joueur. Essai `--voie-test` : écart de 1,5 m
  rattrapé en ~1,5 s, 0,00 m tenu jusqu'à 110 km/h.
- Livraison attendue après le build v6.39 (concurrence `apk` : un push annule le build en cours).

## Fait en v6.39 : plantations en sprites individuels (#142, issue #25)
- `tools/bake_cultures.tscn -- --seulement=plants` -> `assets/veg/plants_albedo.png` (4 cultures × 8 variantes,
  cases 256 × 512 ; blé ble2 et colza vus par la tranche). `crops.gd` : un plant = 2 plans croisés
  (`crops_plants.gdshader`), grille ROWS/STEP par culture, portée RANGE [20, 35, 50, 60] m + fondu large ; sol de
  terre à sillons (`crops_sol.gdshader`, dirt_albedo) ; plants touchés par la voiture : supprimés (éclats de dust.gd).
- Parcelles : sommets en double retirés au chargement.
- Essai `-- --drive-test --champ-bord --champ-type=N` : force le niveau Beau (sous xvfb le réglage auto tombe en
  Économie = 20 m), attend `crops.pending == 0`, vues `bord_vue{3,20,100}.png` + en roulant `bord_{4,7,10}.png`.
- Livré pour vérification par l'utilisateur dans le jeu (issue #25 laissée ouverte).

## Fait en v6.38 : textures partagées des bâtiments (solution A, issues #13 et #22)
- `pipeline/sur_mesure/bibliotheque.py` -> `godot/assets/sur_mesure/_bib.png` ; `batiment.py` (mode `SM_BIB=1` par
  défaut) : atlas réduit aux décalcomanies (9 mm), panneaux (6 mm), enseignes (1,2 cm). `assets/sur_mesure` :
  388 Mo -> 68 Mo. Shader : teinte = tuile × couleur / 200 (pas de pow 2,2 : murs sombres noirs sinon).
- `.glb.import` : `meshes/force_disable_compression=true` obligatoire (UV2 = couleur entière).
- **Import Godot de tous les modèles : tué par manque de mémoire (> 14 Go)** -> importer par lots de 450 (mettre les
  autres .glb + .import de côté dans le scratchpad, importer, remettre).
- Mode d'essai `-- --drive-test --champ-bord --champ-type=N` (voiture sur une route bordée d'un champ, captures
  `user://shots/bord_N.png`).
- Plantations (#25, tâche #142) : validées par l'utilisateur (un sprite par plant de près, fondu, amalgame de
  loin ; les plants ÉCLATENT, ne se couchent pas ; sol en terre). Étape suivante : champ d'essai par culture,
  captures depuis la route à 3, 20 et 100 m, à envoyer à l'utilisateur avant de généraliser.
- Règles du 14/10 : une issue GitHub par élément en cours ou à faire ; issue laissée ouverte si le rendu est à
  vérifier ; routine de reprise horaire (h+07) : finir le travail en cours puis les issues.

## Fait en v6.37 : #130 (cultures à la qualité du maïs)
- Modèles Sketchfab (fetch_trees.py : ble, ble2, colza, tournesol) -> prepare_trees.gd `-- --seulement=…` -> déplacés
  dans `godot/import/cultures/` (hors export) -> `tools/bake_cultures.tscn` (bandes et nappes 3 m, `--seulement=`)
  -> `pipeline/build_crop_tex.py` (normales des bandes penchées vers le haut, sinon rangs noirs au soleil).
- `crops.gd` : rangs aussi dans le blé (0,8 m) et le colza (1,2 m), nappe abaissée sous les épis ; niveau Économie :
  nappe seule. Coût processeur des champs ~×2 (2,6 -> 5,1 ms en moyenne au chargement des cases).
- Street View : plafond de 9 000 appels par mois (issue #13) ; solution A (textures partagées) à faire, à condition
  de ne pas changer visiblement le rendu (commerces toujours fidèles à leur photo).

## Fait en v6.36 : #131 (cultures qui explosent)
- `dust.eclats()` (brins + feuilles + voile teinté), appelée par `trample.gd` pour chaque pixel fraîchement fauché
  (couleurs `ECLATS` par type de culture) ; bandes rasées à 10-20 cm dans `crops.gdshader` ; débris plafonnés
  120-300 selon le niveau. Essai : `-- --drive-test --champ-test [--champ-type=0-3]`.
- #118 et #128 (agrandir la zone) : bloqués par la taille de l'APK (1,84 Go / 2 Go) ; question posée à l'utilisateur.

## En cours : tout le #126 (demande « Fais tout le 126 », 13/10)
- **Photos terminées : compteur à 19,00 $ (2 714 photos). PLUS AUCUNE photo Street View ne peut être achetée.**
- Par commune : `python3 sur_mesure/lots/planches.py <lot> <commune> <préfixe>` (liste + planches 3×3 dans le
  scratchpad rev/), fiches dans `sur_mesure/lots/<lot>.py` (aides B()/D()/IC(), S = skip), `fiches.py <lot>`,
  `batiment.py <ids>` (atlas réduit : `densite` 12 px/m, tailles 256-1024).
- Modèles faits, tuiles régénérées : v6.34 (21 communes, sc à niv) et v6.35 (btm, sal, lpa, sag, mey, cor, mor,
  epa, bgj, ltp : 506). 1 755 bâtiments BD TOPO remplacés au total.
- Piège : ne pas doubler une église de `landmarks.CHURCHES` ; contrôle = emprise du cleabs qui recouvre à plus de
  35 % un polygone OSM d'église (sjs_67, mtc_7, ces_38, scl_56 retirés en v6.35).
- **Taille de l'APK : limite GitHub 2 Go par fichier** (v6.35 refusée à ~2,05 Go). Atlas sur mesure des lots
  plafonnés à l'import : `process/size_limit=512` dans le `.import` de tout atlas de lot > 512 px (fait pour les
  340 concernés, publié sur `donnees`). À refaire pour chaque nouvel atlas de lot (avec mode 2 + mipmaps).
  L'alpha des atlas est un masque (vitres, lumières) : ne pas le retirer.
- Méthode gratuite (1 722 bâtiments sans photo) : en attente de l'accord de l'utilisateur (gain faible, APK lourd,
  enseignes « d'après le métier » perdues).
- Puis méthode gratuite (orthophoto + BD TOPO) pour les bâtiments sans photo.

## Fait en v6.33 : Saint-Chef (#126)
- Photos Street View de Saint-Chef payées (accord de l'utilisateur) : compteur 605 photos = 4,24 $ / 20 $.
  Cache privé poussé (rochetoirin-streetview 818ea7c).
- `fetch_sv_batiments.py [lot] [commune] [--estimer]` : commune au choix, `--estimer` = métadonnées gratuites seulement.
- Fiches courtes : `sur_mesure/lots/saint_chef.py` (FICHES par indice, « skip » = volume généré gardé) +
  `saint_chef_liste.json` ; `python3 sur_mesure/lots/fiches.py saint_chef` écrit `releves/sc_<k>.json` (123).
  Jetons d'ouvertures en tête de `fiches.py`. Planches de revue : script scratchpad sc_prep.py (6 bâtiments/planche).
- Après de nouveaux modèles : `build_buildings.py` (18 min) puis `build_shops.py`, remettre les `.import` publiés,
  patcher les nouveaux atlas (mode 2), import. Ne pas doubler une église qui a déjà un modèle dédié
  (`landmarks.CHURCHES`) : abbatiale sc_116 retirée.
- Moteur : briques/pierres groupées si l'atlas est serré (plus d'échec « atlas trop petit »).
- Disque : venv Blender `bl` du scratchpad supprimé : `python3 -m venv bl && bl/bin/pip install bpy` si besoin.
- Suite de #126 : commune suivante (Saint-Clair-de-la-Tour 165, Saint-Savin 160, Saint-Didier 134…) : estimer
  (`--estimer`), annoncer la dépense, attendre l'accord.

## Fait en v6.32
- École : emprise trop découpée = toit plat ; refaite en 2 volumes (`volumes`, le principal tourné de -9°) à
  toits 4 pans, fenêtres par volume. Préau : `ouvert`. Nouvel atlas ecole_1.png : `.import` patché (mode 2).
- Pierrin : bâtiment caché par le stock sur toutes les photos, volume gardé tel quel (rien à gagner).
- Reste de #141 : pavillon_porche (BD TOPO récent, absent de la photo 2026 ?) puis #126 (bâtiments restants).

## Fait en v6.31
- Agricoles (20) revus par comparatif groupé. Moteur : toit `berceau` (tunnel), `soubassement` en matière
  (`beton#…` : parpaings peints), abris `ouvert` avec `pignons_clos` et `bardage_haut`. Relevés corrigés :
  fumiere (c'est un hangar gris foncé de 5 m), stabulation_bois_6/7/15 (appentis, la 7 fermée), stabulation_a/b,
  ferme_bois (bois sur parpaings), ferme_pise, ferme_parpaing (face E en pisé), hangar_ferme_9/10/11 (gris foncé).
- Planches où la caméra vise une maison voisine (hangar_ferme_9/10/11, fumiere vue 1) : bâtiment peu visible.
- Script utile : faces vues par les caméras (scratchpad faces_cam.py ; importer calage depuis sur_mesure/, pas
  celui de boulangerie/ qui porte le même nom).
- Reste de #141 : école, pavillon_porche, pierrin ; stabulation_bois_15 (emprise complexe, toit en morceaux).

## Fait en v6.30
- #132 fait : itinéraire GPS (itineraire.gd, build_itineraire.py -> world/graphe.bin à publier).
- Industriels lot 3 (35-62) revus : teintes de crépi/bardage trop claires corrigées (garage_anthracite,
  hangar_tole, locaux gris, maison_crepi, maison_maitre, materiaux_fournitures, tribal, petit_local_gris),
  toit `sheds` pour usine_sheds. Reste : agricoles (20), puis école, pavillon_porche, pierrin.
- Piège : speech-dispatcher planté = Godot bloqué au démarrage (taxi_talk / synthèse vocale) : comparatif.py le tue
  avant chaque lancement ; à la main : `kill -9` des PID speech-dispatcher et sd_*.
- Piège : `pkill -f motif` tue aussi le shell dont la ligne de commande contient le motif (code 144) : tuer par PID.

## Fait en v6.29
- Lumière de jour : soleil 1,45, ambiance 1,5 (ciel 40 % + gris chaud). Vitres moins miroir (shader), dégradé de
  vitrage plus sombre. Bardage `bardageh` (nervures horizontales).
- Industriels revus (comparatif groupé) : lots 1-2 (34 premiers de la liste) faits. Reste : industriels 35-62,
  agricoles (20), puis école / pavillon_porche / pierrin.
- Repère : le jeu est « plein soleil », les photos souvent voilées : un mur au soleil ressort plus clair, normal.

## Fait en v6.28
- Lumière ambiante de jour : ciel + gris chaud (main.gd, `ambient_light_sky_contribution` 0,55) : murs à l'ombre
  beiges et non plus gris-bleu.
- Moteur : extra `charpente` (préau ouvert à ferme apparente), fermes automatiques des abris `ouvert` à 2 pans,
  volumes tournés (`rot`), `poutre()`.
- Comparatif groupé de 15 commerces/services : bons = ferme_rigolo, rsm_cabosse, techni_vert, hangar_rose,
  grange_bois, ateliers_est/sud ; retouchés = mecano_plus, salle_baies, grand_porche.
- À revoir : `pavillon_porche` (BD TOPO récent, absent de la photo 2026 devant le préau ?), école (photos à
  80 m : peut-être de nouvelles photos plus proches, à annoncer avec la dépense), pierrin (caché par le stock).
- Suite #141 : bâtiments industriels (62) et agricoles (20) par lots : comparatif groupé, puis corrections.

## Fait en v6.27
- Refaits : église (3 volumes, caméras Google corrigées de ~6 m via `cams`), salle des fêtes, salle du cimetière
  (`"sol": "haut"` : pente), mairie (encadrements `entourage`, annexe absorbée `remplace_bati_extra`).
- Leçon : lire les hauteurs sur le comparatif (pied / corniche), pas sur le calage seul ; si le modèle paraît trop
  grand ou petit sur toutes les vues, corriger la caméra (`cams`), pas les dimensions.
- École : ailes en biais, il faudra des volumes tournés (à ajouter au moteur : "rot" par volume).

## Fait en v6.26
- Églises (landmarks.py `hors_chaussee`) décalées hors de la route : #125 terminé.
- #141 en cours : outils plan.py / calage.py / comparatif.py, relevés à volumes ; faits : mairie, atelier_kaki.
  Suite : église, école, salle des fêtes, puis les autres commerces/services, puis industriels et agricoles.
  Une itération = relevé -> batiment.py -> import Godot -> comparatif.py (≈ 10 min de calcul).
- Acné d'ombre des bâtiments sur mesure corrigée (shader une face).

## Fait en v6.25
- Aide au maintien dans la voie (`scripts/voie.gd`, `world/voies.bin` de `pipeline/build_voies.py`).
- Taxi : lieu de prise en charge annoncé (`activities.gd`, `_cl_nom`).
- Bâtiments redressés rognés côté route (`build_buildings.py`, `rogner_routes`) : 838 -> 359 boîtes qui touchent
  la chaussée, pire cas 456 -> 61 m². Restent : églises de Montcarra (-1675, -2991) et vers (1091, 1403), posées sur
  l'emprise OSM par `landmarks.py` (non rognées).
- Notes de version condensées (version actuelle seulement).

## Ordre de travail convenu (« celles qui gênent la conduite d'abord », puis enchaîner sans demander)
1. #125 fin : églises de landmarks.py qui touchent la route.
2. #141 refaire TOUS les bâtiments non résidentiels avec la méthode complète de la boulangerie
   (`pipeline/boulangerie/` : relevé, calage multi-panoramas, comparatif photo/jeu) — la méthode du restaurant
   (`pipeline/sur_mesure/batiment.py`) a été jugée insuffisante. Annoncer la dépense Street View avant chaque lot.
3. #126 modéliser tous les bâtiments restants.
4. #132 GPS taxi, #130/#131 cultures, #135 clôtures pâtures, #136 terrains de sport, #133 cockpit Raptor,
   #118/#128 nouvelles zones, #139 multijoueur.


## v6.64 (21/10)
- #118 herbe : portées doublées (grass.gd LEVELS 90/120/150/190 m, 3e bande > 70 m écartement ×4) ; #116 ombres : NIVEAUX ombre 140/220/360/480 m, cascade nette 45 m (split_1 = 45/portée). Aperçu docs/apercus/v664.jpg.
- Reste : #105 (clôtures/murets freinent encore), #108, #109, #113, #114, #115, #117, #120.
- Piège : --perf-breakdown trop lent ici (1 img/s, timeout) : mesure inutilisable.

## v6.65 (21/10)
- #105 : fences.breche retire les tronçons par distance au segment (avant : par sommets, un long tronçon touché au milieu restait : 45 -> 0 km/h ; après : 45 -> 39, reste = objet de jardin poussé). colgenres = genres alignés sur colfaces. Essai casse : arrivée perpendiculaire au tronçon ; car._touching donne le script du parent.
- Piège : disque plein (allocation ~40 Go) : nettoyer scratchpad (bl = venv Blender 1 Go, fw = whisper).
- Reste : #108, #109, #113, #114, #115, #117, #120.

## v6.66 (21/10)
- #115 : build_sport.py : multisport > 60 m -> foot ; pas de paniers sur multisport herbe/synthétique ; paniers des city-stades au-dessus des buts (L/2 + 0,2). 132 -> 114 paniers. Aperçu docs/apercus/v666.jpg. Données publiées (donnees).
- #120 : proposition de carrière postée, étiquette pending.
- Reste : #108, #109, #113, #114, #117.

## v6.67 (21/10)
- #114 : FILMS de build_shops.py = 10 parodies (motifs dino et requin ajoutés), titres de 4 lignes en plus petit. Toutes les tuiles shops + atlas d enseignes republiés. Aperçus v667_affiches.jpg, v667_cinema.jpg.
- Reste : #108 (courses), #109 (modèles de voitures), #113 (gare, Street View : annoncer le lot), #117 (champs).
