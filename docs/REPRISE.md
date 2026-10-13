# Reprise du travail (tenu à jour à chaque étape)

Fichier lu en premier par toute nouvelle session (ou après une coupure : limite d'utilisation, conteneur
recyclé). Mis à jour et poussé après chaque livraison et chaque étape importante.

## État au 13/10/2026 (v6.25)
- Branche `godot`, worktree `rochetoirin-godot`. Tirer : `GIT_LFS_SKIP_SMUDGE=1 git pull --rebase origin godot`.
- Données générées : branche `donnees` (`pipeline/publier_donnees.sh`). Après une régénération des bâtiments,
  remettre les `.import` publiés : `git fetch origin donnees` puis, pour chaque `world/buildings/*.import`,
  `git show FETCH_HEAD:world/buildings/<fichier>` (Godot donne sinon de nouveaux identifiants), puis réimporter.
- Captures : `--shots=<fichier.json>` (un CHEMIN de fichier, pas du JSON en ligne).
- Street View : **plafond absolu 20 $** (`pipeline/sv_budget.py`, compteur `pipeline/sources/sv_depenses.json` :
  247 photos = 1,73 $ au 13/10).
- Réveil automatique de la session toutes les 3 h (routine « Reprise après limite d'utilisation »).

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
