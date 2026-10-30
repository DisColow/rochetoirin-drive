# Reprise du travail (tenu à jour à chaque étape)

Fichier lu en premier par toute nouvelle session (ou après une coupure : limite d'utilisation, conteneur
recyclé). Mis à jour et poussé après chaque livraison et chaque étape importante.

## État au 30/10/2026 (v6.84 #131 à v7.23 livrées)
- Branche `godot`, worktree `rochetoirin-godot`. Tirer : `GIT_LFS_SKIP_SMUDGE=1 git pull --rebase origin godot`.
  Sauvegarde du travail en cours : `GIT_LFS_SKIP_PUSH=1 git push origin HEAD:refs/heads/<branche neuve>` (ex. `v691` ;
  jamais de push forcé ; pousser `godot/` sur `godot` déclenche l'APK). Quota Git LFS dépassé : toujours
  `GIT_LFS_SKIP_PUSH=1` (les commits de code n'ont aucun objet LFS).
- **Objectif de l'utilisateur (22/10, /goal)** : « poursuivre sur ta lancée, compléter / améliorer / peaufiner / ajouter
  jusqu'à un produit fini de haute qualité ; prends des initiatives ». Initiatives choisies : carrière complète (#131,
  scénario déjà validé dans #120), puis circulation (#132), puis (idées) son de moteur propre à chaque voiture,
  piétons sur les trottoirs, feux tricolores respectés par la circulation.
- **v6.84 (#131, `à tester`)** : carrière en 4 chapitres (voir CLAUDE.md « Mode carrière »). Essai
  `--carriere2-test` (chapitres 2 à 4) : toutes les missions, le chemin « 3 chocs = raté », le service de nuit en vraies
  courses de taxi, les 5 manches et la fin. Piège trouvé : lieux homonymes (« Église de l'Assomption » existe aussi à
  Bourgoin) -> « nom|commune », contrôlé par l'essai. Corrigés en route : ligature « fi » de Pixelify Sans dessinée
  comme un « A » (`boot.gd` coupe `liga` de `assets/ui/pixel.ttf`), proposition d'épreuve restée affichée par-dessus
  une mission lancée par « Y aller » (`activities._fermer_offre`).
- **v6.85 (#132, `à tester`)** : circulation (voir CLAUDE.md « Circulation »). Essais `--circulation-test` (Bourgoin et
  autoroute : 13 voitures, aucune collision entre elles, arrêt à ~3 m derrière le joueur + klaxon, épave au choc,
  0,7-1,2 ms par pas ici) et `--circulation-gros-plans` (caméra libre : roues, clignotants, phares). Données publiées
  par `pipeline/publier_fichiers.sh` (trafic.bin, klaxon). Idées de suite : feux tricolores respectés (11 feux, cycle
  dans `signal_light.gdshader` : 60 s, phase selon la case de 60 m et l'axe), dépassement d'une voiture arrêtée,
  piétons sur les trottoirs, son de moteur propre à chaque voiture du garage.
- **v6.86 (#133, `à tester`)** : succès et statistiques (onglet « Succès », voir CLAUDE.md) et écran d'accueil du premier
  lancement (`accueil.gd`). Essais `--succes-test` (vraie conduite : 0,5 km, 164 km/h ; crochet de l'argent ; succès,
  primes, bandeau ; sauvegarde relue) et `--accueil-test`. Piège : `main` n'a pas de variable `hud` (variable locale
  de `_ready`) : `main.get_node("HUD")`.
- **v7.14 (#153)** : son de moteur propre à chaque voiture (voir CLAUDE.md « Son »), choix de l'utilisateur appliqué
  (même modèle sinon le plus proche). Boucles publiées sur `donnees` (8 jeux, `.import` faits dans un petit projet
  temporaire). Toledo préparé pour la Gendarmerette Focus (pas encore publié ni crédité).
- **v7.23** : rétroviseur ménagé en Économie (une image sur 8, coupé
  sous 24 img/s, promesse de l'hypothèse 3 de #163) ; carte d'activité et messages bornés en largeur (retour à la
  ligne avant le rétroviseur) ; essai `--gendarme-poursuite-test` (Gendarmerette conduite par le pilote des
  concurrents) : il ne rattrape pas le Twingo de la mission 1 (60-80 km/h, pilote prudent en virage) : pilote d'essai
  à améliorer avant de juger l'équilibre des missions. Toutes les issues ouvertes sont « à tester » (#124 attend le
  relevé du TCL).
- **v7.22 (#161)** : service de gendarme en missions (`gendarme_joueur.gd` : `MISSIONS`, `parametres(n)`, `medaille`,
  `fuyards` [{g, degats, coince_t, pris, detruit}], pause `PAUSE` s, `_fin_service`), vitesse par fuyard
  (`gendarme.vmax_fuite`), chrono en gros et coloré (`activities._set_status(t, coul, gros)`), succès « Gendarme
  d'élite » (stat `serie_gendarme`). Essai `--gendarme-missions-test`. Pièges : l'essai historique
  `--gendarme-joueur-test` (`enchainer` faux) ne fermait pas la consigne (corrigé) ; son pilote ne rattrape plus le
  fuyard (0-25 km/h derrière lui) ; `--gj-coince` : le fuyard lancé à 80 km/h contre la Gendarmerette arrêtée la fait
  exploser (règle #164) : scénario d'essai à revoir. Le fuyard coincé près du joueur ne se dégage plus tout seul.
- **v7.21 (#162, #163)** : carte d'activité en haut à gauche (`activities._set_status` : 1re ligne en gros
  `_status_g`, suite `_status_l`, texte complet `activities.statut` ; « Arrêter » dessous ; `bas_carte()`), messages
  (`hud.toast`) dessous, nom de la rue sous l'argent ; rétroviseur `retro.gd` (SubViewport 320 × 88, une image sur 4,
  220 m, retourné, masqué au poste de conduite ; ⚙ > Conduite). Essai `--hud-test` (coût mesuré ici : +3 % du temps
  d'image, rendu logiciel). #161 livrée en v7.22.
- **v7.20 (#164-#167)** : #164 `Car.juger` (règle de l'utilisateur : l'un à plus de 60 km/h, écart ≥ `ECART_BOUM`
  30 km/h, le plus lent explose ; vitesses d'avant le choc : `_vitesses` sur 3 pas ; voitures du joueur/IA, épaves de
  la circulation jugées dès `_accident`, voitures garées `props.exploser_garee`). Essai `--choc-vehicules-test`.
  #167 `circulation.NOMBRE` +50 %. #166 concurrents : meneur au temps de l'or en Normal, `A_ACC` 4. #165 matériaux
  opaques exportés en mélange alpha passés en découpe (`car._materials`), essai `--deuche-test`. En attente de
  réponse : hypothèses de #161 (missions de gendarmerie), #162 (HUD, maquette `docs/apercus/maquette_hud_162.jpg`),
  #163 (rétroviseur).
- **v7.19 (#158, #159, #160)** : gendarmerie. #158 : tout `garage.change` (gain d'argent) relançait
  `tuning.appliquer()` sur la voiture conduite, Gendarmerette comprise (peinture noire, jantes et enseigne de taxi
  du pick-up) : véhicules de service (`fiche.service`, aussi le bus) exclus du tuning (`tuning._service`). #160 :
  `hud.consigne(titre, texte, points, fin)` (jeu figé jusqu'à OK). #159 : `circulation.trajet(..., issue)` (sorties
  suivies d'au moins 250 m de route, `_portee`) et `gendarme._murs` (rayons avant gauche/droite/devant). Essai
  `--fuyard-test --drive-from=-10975,236,-1100,90 [--graine=N] [--fuite-ancienne]` (images issues : `body_html` de
  l'API REST donne des liens signés private-user-images qu'on télécharge sans jeton).
- **v7.18 (#157)** : bord « cascade » façon Golden Sun 2 (voir CLAUDE.md « Bords de la carte »). Données
  `world/zone_sdf.bin` et `world/cascade.bin` (publiées sur `donnees`). Essai `--cascade-test
  --drive-from=8040,410,3206,90` (bord plat près d'une route ; ailleurs la voiture peut reculer dans une pente).
  Pièges : arbres, bâtiments et herbe n'appellent pas `env_fade_keep` (test `env_hors_monde` ajouté à leur shader) ;
  lampadaires et fils en StandardMaterial3D (filtrés au chargement, `poles.set_bout_monde`). Disque de session plein
  pendant le travail : venv et fichiers de travail finis supprimés du brouillon.
- **v7.17 (#154)** : flèches d'itinéraire sur la route (`fleches_route.gd` + `.gdshader`, voir CLAUDE.md). Essai
  `--fleches-test --drive-from=-10975,236,-1100,90` (itinéraire calculé par l'essai : sans activité, rien ne remplace
  `activities.route_gps`). Pièges : chevrons à plat trop fins vus de la caméra (carré allongé à 4,2 m) ; sens du
  « Λ » : UV.y = 1 côté +Z du QuadMesh couché.
- **v7.16 (#155, #156)** : menu Activités qui défile (`menu_activites._colonne` dans un ScrollContainer, boutons en
  `MOUSE_FILTER_PASS`, bouton tenu neutralisé 0,3 s si on fait défiler ; essai `--menu-scroll-test`). Zone jouable
  `scripts/zone.gd` (`dedans(p, marge)`, `distance_bord`) ; `world/graphe_hors.bin` (`pipeline/build_graphe_hors.py`,
  publié sur `donnees`) : arcs à moins de 12 m de la limite évités par l'A*, nœuds en enclave jamais départ/arrivée ;
  livreur (adresses et restaurants à 60 m), arrêts Ruban (30 m), fuite du gendarme (`circulation.trajet` s'arrête),
  épreuve 5 (étape dans les collines retirée, temps réduits d'autant). Essai `--zone-test` (200 itinéraires près de
  la limite : 46 passaient dehors, 0 après). #157 livrée en v7.18.
- **v7.15 (#150)** : Focus de gendarmerie (choix A, règles 1-5 validées) pour les gendarmes et l'activité
  « Gendarme » ; son Toledo. Modèle `godot/import/voitures/gendarme/model.glb` (copié de la planche, Sketchfab uid
  0b2f13be68734710b620a87088b82ad3) ; conversion `blender_voitures_joueur.py -- gendarme` (toujours `--`, sinon toutes
  les voitures sont refaites ; restauration depuis `donnees` si besoin). Poste de conduite : celui de la 306.
- **v7.13 (#150)** : activité « Gendarme » (le joueur poursuit un fuyard et l'emboutit), chocs relevés sur la
  voiture IA (celle du joueur n'a pas de `contact_monitor`). Pièges trouvés : A* du GPS mauvais pour un fuyard
  (nœuds aux carrefours seulement -> demi-tour ; `circulation.trajet` à la place), voiture figée qui glissait à
  860 km/h (`_sg`), départ contre un mur à Bourgoin (voie OSM le long d'une façade ; essai sur la D522).
- **v7.12 (#150)** : hélicoptère des gendarmes à 3 étoiles, sous-titres des messages radio.
- **v7.11 (#152, `à tester`)** : défi du jour ; compteurs des succès sauvegardés en quittant (les 10 dernières
  secondes étaient perdues). Piège d'essai : les compteurs de `_physics_process` d'essais.gd comptent des pas de
  physique (~7 par image à `--fixed-fps 8`), pas des images.
- **v7.10 (#151)** : onglet « Métiers », majoration de nuit des livraisons, arrêt dans la rue devant le restaurant
  (un restaurant à 33 m du nœud routier le plus proche ne pouvait pas être servi).
- **v7.09 (#151, `à tester`)** : activité « Livreur de repas » (voir CLAUDE.md), `world/restos.json` publié sur
  `donnees`. Piège : `road_at` donne aussi « A 43 », « D 522 · Rue… », « Voie de service », « Chemin de terre »
  (filtrés pour les adresses).
- **v7.08 (#150)** : barrage de deux voitures en travers de la route à 3 étoiles (hypothèse 1 de l'issue) ; reste
  l'hypothèse 4 (activité « Gendarme ») en attente de l'avis de l'utilisateur.
- **v7.07 (#150)** : poursuite continuée à pied (descendre de voiture ne la termine plus), arrestation à pied ;
  astuces du chargement pour les nouveautés.
- **v7.06 (#150)** : message radio des patrouilles (« Avis à toutes les patrouilles… »), modèle des gendarmes
  préchargé. NON VÉRIFIÉ dans l'essai : la voix elle-même (pas de synthèse vocale dans le conteneur).
- **v7.05 (#150, `pending` : choix de la voiture A/B et des règles 1-5 attendus)** : gendarmes et courses-poursuites
  (voir CLAUDE.md « Gendarmes »), voiture provisoire = choix B (306 repeinte). Si l'utilisateur choisit A : importer
  « Ford Focus MK1 Gendarmerie » (szymonpasterczyk, CC BY, uid 0b2f13be68734710b620a87088b82ad3, normales
  personnalisées à effacer, modèle couché : rotation X 90°, ~79 000 triangles à réduire) comme voiture `service` du
  catalogue, inscriptions parodiques. Hypothèse 4 (activité « Gendarme » : jouer le gendarme) pas encore faite.
- **v7.04 (#149, `à tester`)** : vraies lignes Ruban (`world/lignes_bus.json` de `pipeline/fetch_lignes_bus.py`,
  publié sur `donnees` ; Overpass coupe souvent : relancer). Pièges : seuls 34 quais Ruban tombent sur un arrêt de la
  carte (la carte ne prend que les arrêts posés sur la chaussée) -> quais d'OSM ramenés au bord de la voie.
- **v7.03 (#148, `à tester`)** : sonnette « arrêt demandé », arrêts sans personne desservis en passant, arrêts brûlés
  pénalisés ; roues du bus en couleurs unies (`wheel.glb` republié sur `donnees`, `wheel_Image_1.jpg` retiré).
- **v7.02 (#148, `à tester`)** : ligne de bus du joueur (voir CLAUDE.md « Ligne de bus ») : bus jouable
  (`assets/voitures/bus`, publié sur `donnees`), cockpit `assets/cockpit/bus`, `ligne_bus.gd`. Essai `--ligne-bus-test
  [--ligne-arret=n]`. Pièges : arrêts sur voie de service inaccessibles (filtrés par `circulation.voie_arret`) ; bus
  calé dans les rues à 18 % avec la force d'une voiture (`force` du catalogue : 30 kN) ; `_teleport` vide les passants
  (repeupler après) ; disque presque plein (~500 Mo libres : nettoyer le bloc-notes avant un gros import).
- **v7.01 (#147, `à tester`)** : le bus s'arrête aux arrêts de bus (`circulation._arret_bus`, porte avant à hauteur :
  l'écart d'arrêt `IDM_S0` est ajouté), les passants qui attendent montent (il attend qu'ils aient marché jusqu'à la
  porte), 1 ou 2 descendent. Essai `--bus-test --drive-from=-10975,236,-1100,90` (bus posé en amont : les lignes
  aléatoires passent rarement devant un arrêt ; piège : une voiture ajoutée au-delà du quota est retirée aussitôt).
- **v7.00 (#136, `à tester`)** : roues des tracteurs (6 : avant, arrière, remorque) et des bus (4) qui tournent, chacune
  à son rayon (`blender_lourds.py` : matériaux « roue_<n>_c<couleur> » ; `circulation._roues_g`). Essai `--lourds-test`.
- **v6.99 (#136, `à tester`)** : tracteur T5 et bus B1 (choix de l'utilisateur) dans la circulation (voir CLAUDE.md
  « Véhicules lourds ») ; données publiées par `publier_fichiers.sh assets/props/lourd_*.glb(.import)`. Import d'un
  glb seul : petit projet temporaire (même chemin res://), puis copie du .import et de .godot/imported/<nom>-<md5>.*.
- **v6.98 (#146, `à tester`)** : mode Balade (`balade.gd`, voir CLAUDE.md « Balade ») : pilote des concurrents à allure
  de promenade (limitations relevées sur le trajet), lieux de places.json, six plans de caméra, un toucher rend la main.
  Arrêt aux feux rouges, sans doubler. Essai `--balade-test [--duree=s]` (lent ici : ~1 h pour 5 min de jeu en ville).
- **v6.97 (#145, `à tester`)** : `Env.set_value` saute les valeurs simples inchangées (`_lumiere()` 216 -> 22 µs,
  `--lumiere-perf`) ; horloge de l'autoradio et pénombre du cockpit dans le cycle.
- **v6.96 (#144, `à tester`)** : arc-en-ciel à la fin d'une averse (météo variable, soleil bas), circulation prudente
  dans le brouillard, ciel non reposé pendant un éclair. Essai `--arc-test`.
- **Piège (28/10)** : pousser pendant qu'un build tourne l'annule (`cancel-in-progress` d'`apk.yml` et `desktop.yml`) :
  la v6.94 n'a pas eu d'APK (la v6.95 la contient). Attendre la fin des builds avant de pousser (boucle sur
  `gh api repos/DisColow/rochetoirin-drive/actions/runs` jusqu'à ce qu'aucun ne soit en cours).
- **v6.95 (#143, `à tester`)** : cinq succès météo et nuit (`succes.gd` : orage, eclairs, aube, journee, taxinuit).
  Essai `--succes-test --succes-meteo` (aube du cycle sous la pluie, compteurs posés juste sous le but) : les cinq
  débloqués, primes versées, sauvegarde relue.
- **v6.94 (#142, `à tester`)** : orage (éclairs calés sur les coups de tonnerre de `pluie.ogg`, `rain.TONNERRES`) et
  bulletin météo de la radio (`main.bulletin_meteo`, prévision exacte par `meteo_suivante`). Essai `--orage-test` :
  6 éclairs par tour de boucle, 1 à 2,6 s avant le tonnerre ; lueur 30 -> 94, 36, 83, 30 en 0,35 s. **Piège** : à
  `--fixed-fps 8`, le son avance en temps réel (1 s par image ici) : tester le calage par `eclairs_entre`, pas en jeu.
- **v6.93 (#141, `à tester`)** : ciel étoilé (`etoile()` de `ciel_nuages.gdshaderinc`, réglage `etoiles` du ciel peint)
  et tarif de nuit du taxi (`main.tarif_nuit()`, `taximetre.nuit`, « TARIF 2 »). Essai `--nuit-test` : 121 étoiles par
  nuit claire, 0 par temps couvert ; taximètre 17,10 € de jour, 19,50 € de nuit (1 km + 1 min). `--taxi-test --taxi-nuit` :
  compteur en TARIF 2 pendant la course. Piège : `get_node("HUD")` est un CanvasLayer (pas un CanvasItem).
- **v6.92 (#140, `à tester`)** : cycle jour et nuit (⚙ > Heure > Cycle ; voir CLAUDE.md « Heure et cycle ») : journée de
  24 min, départ à 9 h, heure dans la pastille du HUD. `set_time`/`_apply_weather` remplacés par `_lumiere()` (deux
  moments `_moment()` mêlés, chacun mêlé par la météo). Essai `RS_CLOUDS=0,1 … --cycle-test` (moments fixes inchangés :
  midi 79,3 ; ambiance « ciel » à part 0 = « couleur » à 0,3 près ; journée entière en 720 images). **Piège** : une
  ombre de nuage qui passe assombrit toute l'image (midi à 58 au lieu de 79) : essais de luminosité sans ombres de
  nuages ; `--cycle-sonde` compare les réglages de la lumière. Les reflets du ciel se recalculent sur ~8 images :
  ne pas reposer le ciel à chaque image (`_ciel_pose`).
- **v6.91 (#139, `à tester`)** : météo variable (⚙ > Météo > Variable ; voir CLAUDE.md « Météo ») : fondus de 90 s
  (ciel photo de midi grisé puis ciel peint identique, brume, soleil, pluie, sol mouillé qui sèche en 60 s), circulation
  plus lente et phares allumés sous la pluie, passants moins nombreux (×0,4) et plus pressés. Essai `--meteo-test`
  (`--meteo-court` : seulement l'enchaînement, sur 20 h de jeu simulées) : saut de luminosité d'une image à l'autre
  0,42 au plus pendant le fondu beau -> couvert (3,4 d'un coup) ; répartition beau 52 %, couvert 34 %, pluie 11 %,
  brouillard 2 %.
- **v6.90 (#138, `à tester`)** : client du taxi déposé qui devient un passant (`pietons.adopter`), passants qui fuient
  les explosions (`pietons.panique`). Essais `--taxi-test` (« clients devenus passants : 2 sur 4 courses » : les autres
  destinations sans trottoir à 25 m) et `--pietons-test --pietons-court`.
- **v6.89 (#137, `à tester`)** : la circulation double les véhicules lents (`circulation._doubler`, voir CLAUDE.md
  « Véhicule lent »), clignotants pendant les dépassements, dérive latérale propre à chaque voiture (`derive`). Essai
  `--circulation-test --circulation-double --drive-from=-8410.95,221,-7187.25,45.2` (D 522, route à 70-80 km/h).
  Contrôle complet (`verifier.sh --complet`) passé sur la v6.88 : 0 erreur. **Piège** : ne pas modifier un script
  pendant un essai en cours (chaque essai charge les scripts à son démarrage ; un essai du contrôle complet a ainsi lu
  un script en cours d'écriture).
- **v6.88 (#135, `à tester`)** : passants (voir CLAUDE.md « Passants ») : `pipeline/build_pietons.py` ->
  `world/pietons.bin` (trottoirs d'OSM, rues piétonnes, bords des rues en ville, 981 passages piétons, 123 arrêts de
  bus), `scripts/pietons.gd` (clients du taxi, réserve de passants, traversées, bonds, « pouf »), klaxon du joueur
  (`scripts/klaxon.gd`, bouton, H, L3). Textures des clients compressées (76 `.import` publiés ; import local : petit
  projet temporaire, voir CLAUDE.md « Import d'un seul fichier »). Essai `--pietons-test` (centre de Bourgoin).
  **Suite proposée (#136, `pending`)** : tracteurs et bus dans la circulation, planche `docs/apercus/choix_vehicules.jpg`
  (modèles Sketchfab CC BY téléchargés dans le scratchpad, pas encore dans le dépôt) ; bus qui s'arrêtent aux arrêts où
  attendent les passants ; tracteurs lents sur les routes de campagne, dépassés par la circulation.
- **v6.87 (#134, `à tester`)** : feux tricolores respectés par la circulation, dépassement d'un obstacle immobile par la
  voie d'en face, concurrents qui évitent la circulation (voir CLAUDE.md « Circulation »). `trafic.bin` passe à 9 champs
  par arc (publié ; l'ancien format reste lu). Essais `--circulation-test --circulation-feux` (90 s de jeu : passages
  aux feux, aucun au rouge, capture caméra libre d'une voiture arrêtée) et `--circulation-depasse` (écart, klaxon,
  retour dans sa voie) ; `--course-ia-test --densite=3` compte les voitures contournées par les concurrents. Trouvé par
  cet essai : en circulation dense, le peloton s'empilait sur les épaves dans les rues étroites (bloqué à 150 m du
  départ ; sans circulation : 350 m en 40 s) -> tracé de la course dégagé et barré (`circulation._route_course`,
  `_sur_trace`) : 0 épave, 352 m en 40 s. Pièges :
  le shader des feux avait une phase `fract(sin())` irreproductible côté jeu et `TIME` (horloge du rendu) : remplacés
  par (17 cx + 31 cz) mod 60 et `Env.temps_feux()` (temps de jeu : à `--fixed-fps 8`, l'heure réelle défilait 30 fois
  trop vite pour les voitures) ; 198 têtes de feux dessinées sur 198 concordent avec `build_trafic.py` ; deux voitures
  qui se croisent à 2,5 m l'une de l'autre devenaient épaves (marge de choc ronde) : marges par axe. **Piège du
  conteneur** : `git worktree add` télécharge les APK par Git LFS et remplit le disque (le faire avec
  `GIT_LFS_SKIP_SMUDGE=1`, ou s'en passer).
- **v6.83 (#128, `à tester`)** : concurrents pilotés par le jeu (`scripts/concurrent.gd`, voir CLAUDE.md
  « Concurrents ») : course contre 3 voitures par défaut dans les épreuves, Kévin réel dans le duel de la carrière
  (`fantome.gd` retiré). Mesures : course complète en Extrême, concurrents à 1-3 s du temps visé, pilote à 0,8-1 m
  du tracé en moyenne ; explosion + retour 4 s après vérifiés ; essai `--carriere-test` complet (réputation 100).
  Réglages possibles si l'utilisateur trouve les concurrents trop forts ou trop lents : `activities.CONCURRENTS`
  (temps visés), `concurrent.a_lat` (virages), `LOIN`/`PRES` (physique coupée au loin).
  Leçons : l'essai de conduite générique (`--drive-test`) écrit `touch_*` à chaque pas avant les essais placés après
  lui dans `_physics_process` d'essais.gd (placer un essai qui pilote la voiture avant) ; `--fixed-fps 8` rend le
  temps de jeu indépendant de la lenteur du rendu ici.
- **Conteneur : 1 634 `.import` de tuiles de routes manquaient depuis le 16/10** (essais sans routes 3D, « No loader
  found ») ; refaits le 22/10 (voir CLAUDE.md « `.import` manquants ») ; `verifier.sh` le contrôle désormais.
- **#123 livré** (`à tester`) : v6.81 (débris persistants, éclats, arbres/lampadaires/poteaux couchés) et v6.82
  (`sport.gd`, `autoroute.gd` : `RENVERSABLES`, `objets`, `casser_objet` ; `casse.OBJETS` ; glissières et séparateurs
  défoncés de face seulement). Essais : `--casse-genres=objet:glissiere,objet:gba,…` (voir CLAUDE.md).
- **v6.80** (#129) : champignon atomique seul (plus de choix dans ⚙), caméra extérieure en plan large pendant
  l'explosion (`camera_rig.gd` `_mode_avant`, `_boum`). Essai `--boum-camera-test`.
- **v6.79** (#130) : les niveaux de détail faits à l'import déchirent les modèles en pièces séparées (2CV) ; voitures du
  garage toujours en pleine définition (`lod_bias = 64` dans `car._materials`, `fantome.gd`). Essai
  `--voitures-revue --lod-seuil=N` (seuil forcé, petite résolution : `--resolution 800x360`). À surveiller : d'autres
  modèles posés par lots (voitures garées, commerces) pourraient avoir le même défaut au loin.
- **v6.78** (#124 étape 2) : `pipeline/alleger_pano.py` -> `world/far/pano.glb` 173 000 -> 30 000 triangles (silhouette
  à 2 px près, 0,32 % des pixels changent au plus) ; Économie au village 1 004 k -> 718 k triangles. Données publiées.
  Le panorama complet d'origine : `scratchpad/pano_complet.glb` (non versionné) ou l'historique de la branche `donnees`.
- **#124 en attente (`pending`) : relevé de performances du TCL demandé (v6.78, Économie, village et Bourgoin)** avant la
  suite, qui demande de régénérer et réimporter ~1 600 tuiles de bâtiments (l'import complet sature la mémoire ici).
  Le relief cuit (`world/relief/albedo.png`, 3456 × 2176 sur toute la carte = 16 m/px) est trop grossier pour le sol
  proche : l'étape 3 « relief cuit » serait plutôt un shader de Terrain3D allégé (moins de couches) en Économie.
  Atlas des bâtiments sur mesure : minuscules (64 × 32 à 96 × 96 px, décalcomanies seulement) : un atlas commun par
  tuile est faisable dans `batiment.py`.
- **À FAIRE ENSUITE (#124, validé par l'utilisateur : étapes 2 et 3 « dans l'ordre », pas pressé ; ordre à revoir
  d'après le relevé)** :
  1. Étape 2, point 9 : bâtiments sur mesure regroupés par tuile (`sur_mesure.gd` : un modèle + un atlas par bâtiment,
     28 appels au village, 60 au centre de Bourgoin ; il faut un atlas commun par tuile ou un Texture2DArray).
  2. Étape 2, point 11 : villes lointaines simplifiées (bâtiments génériques `buildings.gd` : 121 appels et 553 000
     triangles au centre de Bourgoin ; au-delà de ~400 m, une version « blocs sans fenêtres » de chaque tuile, faite
     par `build_buildings.py`, à importer sans `godot --import` complet : voir « Import d'un seul fichier » de CLAUDE.md).
  3. Étape 3 : relief « cuit » en Économie (une texture au lieu du mélange de Terrain3D ; bâtiments sans relief de
     texture ni intérieurs de vitrines), à-coups des tuiles (routes posées en plusieurs images, rayon réduit en Économie).
  Mesures : `--perf-breakdown` (NIVEAU=0/1, `--drive-from=-10859.8,238.5,-920.6,0` pour Bourgoin), avant/après dans la
  même version par un interrupteur `RS_SKIP=…`. Repères v6.78 : village Équilibré 630 appels, Économie 405 appels /
  718 k triangles, Bourgoin Équilibré 694 appels / ~1,9 M triangles.
- **v6.77** (#124 étape 2, validée par l'utilisateur : « fait dans l'ordre ») : voitures garées, tracteurs, poubelles
  et commerces fusionnés en une surface par modèle (`_fusionner` de `props.gd` / `shops.gd`, voir CLAUDE.md),
  petits objets sans ombre. Village Équilibré 1 023 -> 630 appels, Économie 586 -> 405, Bourgoin 1 354 -> 694.
  **Reste de l'étape 2** : bâtiments sur mesure regroupés par tuile (un atlas par bâtiment : il faudra un
  Texture2DArray ou un atlas de tuile ; 28-60 appels), villes lointaines simplifiées (point 11), panorama allégé
  (`pano`, 173 k triangles). Puis étape 3 (relief cuit en Économie, à-coups des tuiles).
- **v6.76** : #124 étape 1 (vrai mode Économie), #127 argent (3 niveaux par épreuve), #126 revue des voitures, #129
  explosions (3 styles au choix dans ⚙ > Conduite, défaut « mini », **choix de l'utilisateur attendu**, `pending`).
  - #124 : `main.gd` `NIVEAUX[0]` (pas d'ombres, `res_auto` 50-80 %, 30 img/s ou `eco_60`, physique 60 pas/s, brume),
    arbres/herbe/plants coupés, terre labourée (`terrain.gdshader`), phares et lampadaires factices
    (`env.gdshaderinc` `env_phares_lum`, `env.gd` `set_phares`). **Freins des roues mis à l'échelle du pas de physique**
    (`car.gd` `k_pas` : le frein de Godot est une impulsion par pas ; à 60 pas/s, 100 -> 0 en 32,7 m au lieu de 23,5).
    Mesure Économie au village : 870 -> 586 appels, 1,36 M -> 1,04 M triangles. **Étape 2 à faire** (après retour de
    l'utilisateur sur le TCL) : voitures garées en un seul matériau (196 appels), bâtiments sur mesure et commerces
    regroupés par tuile, petits objets sans ombre, panorama de l'horizon allégé (173 k triangles).
  - #127 : `activities.gd` `NIVEAUX_EP`, `prime_medaille`, `cle_ep(id, niv)` (Normal = ancienne clé) ; menu
    (`menu_activites.gd`) : boutons de niveau ; taxi ×3 (`taximetre.gd`), chasse 100 €, course libre et carrière ×3.
    Essais `--drive-test --argent-test`, `--drive-test --epreuves-menu-test` (lance l'épreuve en Extrême).
  - #126 : essai `-- --drive-test --voitures-revue [--revue-ids=a,b]` (captures `revue_<id>_<angle>.png`, hauteur de caisse).
  - #129 : `scripts/explosion.gd` + `explosion.gdshader`, `pipeline/fetch_explosions.py` (planches CC0 Unity Labs ->
    `assets/fx/`, publiées sur `donnees`), essai `-- --drive-test --explosion-test [--explosion-styles=film,mini]`.
- (Au 22/10 matin ; depuis, #129, #128 et #123 ont reçu leurs réponses et sont livrés.) #124 : retour sur le
  téléphone attendu avant la suite de l'étape 2.
- **Piège des essais en parallèle** : deux Godot lancés ensemble partagent `user://` ; le fichier `demarrage.flag` de
  l'un met l'autre en **mode sûr** (shader du relief d'origine, sans phares factices ni ombres des nuages). Donner à
  chaque essai son dossier : `XDG_DATA_HOME=<dossier>` (copier les `.cfg` de `~/.local/share/godot/app_userdata/
  Rochetoirin Simulator/` dans `<dossier>/godot/app_userdata/Rochetoirin Simulator/`).
- v6.75 : voies ferrées (#125, `à tester`), v6.74 : carrière (#120, `à tester`).
- **`gh issue comment/edit` refusés ici (GraphQL)** : passer par l'API REST : `gh api repos/DisColow/rochetoirin-drive/issues/N/comments --input c.json` (`{"body": …}`), étiquettes `gh api -X POST …/issues/N/labels -f 'labels[]=à tester'`.
- Disque : ~1 Go libre. Les tuiles de routes (1 634) ne sont toujours pas importées ici : captures sans routes.
- Données générées : branche `donnees` (`pipeline/publier_donnees.sh`). `build_buildings.py` (25 min) EFFACE
  `world/buildings` (`.import` compris) : remettre les `.import` publiés d'un coup :
  `git fetch --filter=blob:none --depth=1 origin donnees` puis
  `GIT_INDEX_FILE=$(mktemp -u) git --work-tree=godot checkout FETCH_HEAD -- 'world/buildings/*.import'`.
  Comparer les empreintes (md5) avant/après : seules les tuiles du bâtiment doivent changer.
- **Import Godot ici** : beaucoup de fichiers n'ont jamais été importés dans ce conteneur (1 643 tuiles de routes sans
  `.import`, routes, eau, bâtiments de L'Isle-d'Abeau…) : un `godot --headless --import` complet les réimporte TOUS
  (4 768 fichiers, 12 Go de mémoire après 1 150 : tué). Import ciblé : sortir du projet (renommer hors de `godot/`)
  `world/roads`, `world/water`, `world/bord` et les `b_*.glb` inutiles, importer (1 min), tout remettre. Ne pas
  utiliser `.gdignore`.
- Captures : `--shots=<fichier.json>` (un CHEMIN de fichier, pas du JSON en ligne).
- Street View : **plafond de 9 000 images par mois** (`pipeline/sv_budget.py`, compteur `pipeline/sources/sv_depenses.json`).
- Réveil automatique de la session toutes les heures (routine « Reprise après limite d'utilisation », h+07).
- Pièges des essais : `pkill -f "[g]odot --path"` tue aussi le shell (motif présent dans la commande) : utiliser
  `pkill -x godot` ; les menus mettent le jeu en pause (`hud._show_drive(false)`) : un essai qui attend des images
  doit remettre `get_tree().paused = false` ; une étiquette `autowrap` dans une rangée (HBox) fausse la mise en page.
  Transcription d'un vocal : venv `scratchpad/fw` (faster-whisper, modèle « small », `language="fr"`).

## Vocal du 17/10 (issues #105 à #121) : tout est livré (`à tester`), sauf #120 (carrière, `pending`)

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
- (v6.73 : `--perf-breakdown` regroupé par système, utilisable ici en ~10 min ; voir v6.73.)

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

## v6.68 (21/10)
- #108 : build_epreuves.py : 14 d origine (ids 0-13 identiques, records gardés) + 12 sprints + 12 longues = 38. Aperçu v668.jpg (la capture du menu montre une ligne droite : tracé encore en calcul, le journal donne 1826 points).
- Reste : #109 (modèles de voitures), #113 (gare, Street View : annoncer le lot), #117 (champs).

## v6.69 (21/10)
- #109 : captures des 11 voitures (--voitures-test). Espace : trous (allègement par matériau) -> par_materiau 1.0 sur peinture/vitres, faces 90000 (89 k faces, lourd). 306 : roue du modèle = cylindre gris -> meta « roue_de »: « p206 » (car.gd met la roue empruntée au rayon). Aperçu v669.jpg.
- Piège : blender_voitures_joueur.py sans « -- » reconvertit toutes les voitures (sans dommage constaté).
- Reste : #113 (gare, Street View : annoncer le lot), #117 (champs).

## Proposition « tout en sprites, prêt pour la 2D » (21/10, #122, pending)
- Demande : tout ce qui peut l être en sprites, compatible avec un futur passage en 2D ; proposer et poser des questions AVANT de coder.
- Proposition postée (#122) : studio Blender unique (angles communs dont dessus 90° et iso 35°, même soleil, masques couleur/lumière, normales), sprites en panneaux face caméra maintenant, mêmes planches pour la 2D ; voiture du joueur photographiée dans le jeu au garage ; relief/routes/eau/bâtiments en 3D pour l instant. Planche docs/apercus/sprites_vues.jpg.
- Questions : 2D visée, style, ordre, bâtiments. Rien de codé en attendant les réponses.

## v6.70 (21/10) : mémoire vidéo (#122)
- Demande précisée : sprites pour panneaux, lampadaires, arbres « pour libérer de la mémoire vidéo ». Mesure d'abord
  (essai `--vram [--vram-at=x,y,z] [--vram-voiture=id]`, essais.gd) : 615 Mo au village (Équilibré, Ranger) ; relief ~130
  (Terrain3D 29 régions ≈ 101 + relief simplifié 30), bâtiments ~100, ciel 45, horizon ~34, arbres 30, sur mesure 21,
  clôtures 20 ; lampadaires 3 Mo, panneaux déjà plats (planches 11 Mo) -> sprites inutiles pour la mémoire.
- Choix de l'utilisateur : seulement les réglages sans perte visible (« Aucun » compromis, pas de sprites) :
  - voitures du garage : `compress/mode=2` (+ `normal_map=1`) via `pipeline/compresser_textures.py` (à relancer après
    `blender_voitures_joueur.py`) : R5 ~76 -> 16,9 Mo, 2CV -> 14,8 Mo (tools/mesure_texture.gd sur body.glb + wheel.glb) ;
  - ciel de midi : `pipeline/build_ciel_midi.py` (+ `rgbe.py`) -> `assets/ciel/midi_haut.hdr` (4096 × 1024),
    `midi_bas.hdr` (1024 × 256), `midi.json` (azimut du soleil) ; `scripts/ciel_midi.gdshader` ; `assets/sky.hdr`
    supprimé (build_assets.py appelle build_ciel_midi) : 45 -> 24 Mo mesurés à part (`tools/mesure_ciel.gd`) ;
  - soucoupe : `guardian.actif` faux (seulement avec `--void-test`) : −5,6 Mo ; vinyles chargés seulement si posés : −7,3 Mo ;
  - carte : impossible sans perte (une seule image de 17 Mo chargée, partagée avec la mini-carte) ; `assets/tex/map.jpg`,
    inutilisée, exclue de l'export (taille de l'APK seulement).
  - Mesures dans le jeu (bruit d'une mesure à l'autre ~±15 Mo) : Ranger 615 -> 598 Mo ; R5 682 -> 599 Mo.
- **Piège trouvé** : 1 643 tuiles de routes sur 2 930 n'ont pas de `.import`, ici comme sur la branche `donnees`, depuis
  le 16/10 (0 le 16/10 à 9 h, puis 1 266 -> 1 287). L'action GitHub les importe (import par paquets), donc l'APK a ses
  routes ; mais dans ce conteneur, les routes manquent sur ces tuiles (dont le village, t_0_0) : captures et essais
  sans routes à ces endroits. À réparer : import par paquets (`.github/scripts/import_paquets.sh`) puis publier.
- `tools/mesure_texture.gd` : mémoire vidéo d'une texture (écart du compteur avant/après chargement).

## v6.71 (21/10) : champs (#117, en partie)
- Maïs : `crops_plants.gdshader`, culture 0 = un seul plan parallèle à l'écran (droite de la caméra ramenée à
  l'horizontale), second plan de la croix effacé ; normale et `BACKLIGHT` calculés dans le fragment (sinon champ
  sombre à contre-jour). Fauchage : `trample.gd` pinceau ±6 px (4,9 m) au lieu de ±3 (2,6 m). Aperçu v671.jpg.
- Blé : planche `docs/apercus/ble_candidats.jpg` (A actuel, B orge scannée CC0 dense, C = B devant le feuillage de A),
  script `pipeline/candidats_ble.py` ; en attente du choix (#117 pending). Hypothèse annoncée : le blé deviendra aussi
  un plan face à l'écran, comme le maïs. Intégration du choix : ajouter le modèle à `fetch_trees.py`,
  `prepare_trees.gd`, `bake_cultures.gd` (BANDES), puis `build_crop_tex.py` / `build_touffes.py`.

## v6.72 (21/10) : blé (#117, « fais comme tu le sens » -> choix C)
- `pipeline/blender_orge.py` (venv bpy) : orge scannée ffish.asia / floraZia (CC0, `data/orge/`, téléchargée avec
  SKETCHFAB_TOKEN) -> `data/orge/touffe_ble_<v>.png` (2,4 × 1,2 m, 70 tiges/m, moins dense vers les bords, hauteurs
  0,72-1,08) ; `build_touffes.py` : céréales = feuillage actuel ×0,9 + épis devant -> `assets/veg/touffes_albedo.png`.
- Shader : céréales aussi en plan face à l'écran (v_plat pour cultures 0 et 1), contre-jour doré. Essais : en croix
  avec la texture dense (160 tiges/m) = bandes ; à plat avec un haut droit = « bottes de paille » ; retenu : contour
  irrégulier + plan unique. Aperçu v672.jpg (3 colonnes). Crédit ajouté (hud.gd).

## v6.73 (21/10) : gare de La Tour-du-Pin (#113)
- Photos : 3 vues Street View (compteur du mois 2 714 -> 2 717 / 9 000), `fetch_sv_batiments.py` : filtre
  `--cleabs=ID,ID`, plafond de 700 compté par lancement (avant : total payé, qui bloquait tout). Clé Google : variable
  `GOOGLE_MAPS_API_KEY` à mettre dans l'environnement de la session, jamais dans le dépôt. Photos poussées dans le cache
  privé (rochetoirin-streetview 6196a71).
- Relevé `sur_mesure/releves/gare_la_tour_du_pin.json` : aile basse u 0-27,6 (égout 4,7, 8 baies à encadrements de
  pierre, corniche) + corps à 3 niveaux u 27,6-40,3 (égout 10,6, faîtage 12,4 ; portes vitrées sous linteaux gris,
  « GARE DE LA TOUR DU PIN », logo parodié « SNIF », volets gris ouverts au 1er, clos au 2e, garde-corps). Caméras
  corrigées (`cams`, tangage −7,5 / −5,5 / cap −3 et −5) : les caméras Google semblent à ~1,8 m du sol. Couleurs des
  photos × 1,2 (× 1,3 donnait des murs presque blancs au soleil du jeu).
- `build_buildings.py` (seule `b_10_10` change) puis `build_shops.py` : l'ancien volume portait une devanture
  générique (usage « Commercial et services ») -> 64 tuiles `world/shops` + `enseignes2.png` republiées. 9 tuiles de
  routes autour de la gare importées ici (`.import` créés, publiés). Comparatif : `planches/cmp_gare_la_tour_du_pin.jpg`
  (cache privé) ; aperçu jeu `docs/apercus/v673.jpg`.
- #124 : `--perf-breakdown` regroupe les nœuds par système (nom du script) et prend `NIVEAU=0..3` ; marche ici
  (~10 min, nombres d'appels et de triangles justes, img/s sans valeur). Mesures et plan postés sur #124.
- #123 : questions postées (gros arbres, autoroute, pylônes et monuments, durée), étiquette `pending`.

## v6.74 (21/10) : mode carrière, chapitre 1 (#120)
- Validé par l'utilisateur (21/10, 14 h 59) : chapitre 1 seul, carte libre, rival en fantôme qui roule en même temps.
- `scripts/carriere.gd` (nœud « Carriere » de main) : réputation 0-100 (`user://carriere.cfg` : reputation, faites,
  message_vu, commencee, victoires, defaites), 4 missions (`MISSIONS`) : livraison « Le pain du matin » (boulangerie
  Chez Flonflon -> école, mairie de Saint-Jean-de-Soudain, Montbertaud ; 3 chocs = raté ; temps limite d'après les
  distances), taxi imposé « Monsieur le maire » (`activities.impose` : client, destination, temps limite ; pas
  d'arrêt ni de client suivant), « Premier chrono » (bronze à l'épreuve 14), « Le duel » (épreuve 0 contre Kévin
  Turbot, fantôme à 0,88 × le temps de l'or). Bonus/pertes du jeu libre seulement une fois la carrière commencée.
  Bulles (`_bulle_choix`) + voix du téléphone (`_dire`) ; message de fin à 100.
- `scripts/fantome.gd` : tracé itineraire.gd jambe par jambe, profil de vitesse (virages 6,5 m/s², accélération 3,
  freinage 6, 150 km/h), mis à l'échelle du temps cible ; horloge = `activities._t` ; Pijo 106 translucide
  (ALPHA_HASH), nom en Label3D, départ 2,4 m à gauche du joueur.
- Onglet « Carrière » (index 6, affiché en tête : `ORDRE` de menu_activites.gd). Crochets : activities (`_stop`,
  fin d'épreuve, `_epreuve_proche`, taxi), casse.gd (`decor_casse`), car.gd (`explosion`).
- Essai `--drive-test --carriere-test` (étapes déclenchées par l'état du jeu, `Engine.time_scale = 4` : à 1 img/s
  le temps du jeu n'avance que de 0,07 s par image). **Piège** : un speech-dispatcher resté d'un essai précédent
  bloque le démarrage suivant (« [étape] Interface » figé) : `pkill -9 -x speech-dispatch` avant et après.

## v6.75 (21/10) : voies ferrées (#125)
- `pipeline/fetch_rails.py` (OSM : railway=rail, level_crossing, platform -> `data/osm_rails.json`) ;
  `build_rails.py` -> `world/rails/rl_tx_tz.bin` : 39,8 km de voie, ponts et tunnels sautés (18 tronçons), voie
  rééchantillonnée à 2 m, dessus du ballast = max(relief lissé sur 12 m, relief) + 0,10 m ; passages à niveau :
  nœuds OSM (un par voie) regroupés à 12 m -> 5 croisements, rails noyés au ras de la route (`rf`), rampe de 8 m.
- `scripts/rails.gd` + `rails.gdshader` : ballast (dessus ±1,6 m, talus jusqu'à ±3,2 m, 14 cm plus bas),
  collision en maillage (ConcavePolygonShape3D, deux faces), rails sans collision ; passages : mât, croix de
  Saint-André, feux qui clignotent (2 matériaux partagés), demi-barrières (`barrieres`, `casser()`).
- casse.gd : genre « barriere » (segment pied -> bout, débris = le bras lui-même).
- Essai `--drive-test --rails-test --casse-debug --sans-voix` (~20 min) : le long de la voie (x -8624 z 1519),
  traversée (stabilité à ± 5 m de l'axe), barrière du passage de x 4845 z 2883 (approche droite de 30 m).
  Premier profil (18 cm, talus 0,8 m) : -17 km/h et 21° de tangage à la traversée ; adouci.
