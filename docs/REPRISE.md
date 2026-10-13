# Reprise du travail (tenu à jour à chaque étape)

Fichier lu en premier par toute nouvelle session (ou après une coupure : limite d'utilisation, conteneur
recyclé). Mis à jour et poussé après chaque livraison et chaque étape importante.

## État au 13/10/2026 (v6.31)
- Branche `godot`, worktree `rochetoirin-godot`. Tirer : `GIT_LFS_SKIP_SMUDGE=1 git pull --rebase origin godot`.
- Données générées : branche `donnees` (`pipeline/publier_donnees.sh`). Après une régénération des bâtiments,
  remettre les `.import` publiés : `git fetch origin donnees` puis, pour chaque `world/buildings/*.import`,
  `git show FETCH_HEAD:world/buildings/<fichier>` (Godot donne sinon de nouveaux identifiants), puis réimporter.
- Captures : `--shots=<fichier.json>` (un CHEMIN de fichier, pas du JSON en ligne).
- Street View : **plafond absolu 20 $** (`pipeline/sv_budget.py`, compteur `pipeline/sources/sv_depenses.json` :
  247 photos = 1,73 $ au 13/10).
- Réveil automatique de la session toutes les 3 h (routine « Reprise après limite d'utilisation »).

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
