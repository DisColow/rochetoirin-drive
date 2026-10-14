# Reprise du travail (tenu à jour à chaque étape)

Fichier lu en premier par toute nouvelle session (ou après une coupure : limite d'utilisation, conteneur
recyclé). Mis à jour et poussé après chaque livraison et chaque étape importante.

## État au 14/10/2026 (v6.41)
- Branche `godot`, worktree `rochetoirin-godot`. Tirer : `GIT_LFS_SKIP_SMUDGE=1 git pull --rebase origin godot`.
- Données générées : branche `donnees` (`pipeline/publier_donnees.sh`). Après une régénération des bâtiments,
  remettre les `.import` publiés : `git fetch origin donnees` puis, pour chaque `world/buildings/*.import`,
  `git show FETCH_HEAD:world/buildings/<fichier>` (Godot donne sinon de nouveaux identifiants), puis réimporter.
- Captures : `--shots=<fichier.json>` (un CHEMIN de fichier, pas du JSON en ligne).
- Street View : **plafond absolu 20 $** (`pipeline/sv_budget.py`, compteur `pipeline/sources/sv_depenses.json` :
  247 photos = 1,73 $ au 13/10).
- Réveil automatique de la session toutes les 3 h (routine « Reprise après limite d'utilisation »).

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
