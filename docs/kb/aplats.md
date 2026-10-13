# Directives de l'utilisateur : bâtiments en aplat (12 octobre 2026)

À appliquer à tout bâtiment, généré ou refait d'après Street View.

## Façades strictement plates
- **Aucune micro-géométrie** sur les murs : portes, fenêtres, volets, appuis, rebords, encadrements, pilastres,
  coffres de rideau, bandeaux, caissons d'enseigne… ne sont **jamais** modélisés en 3D (pas de retrait, pas de saillie,
  pas de tableaux). Ils sont **peints** : texture (albédo) + normal map, avec l'ombre de l'embrasure peinte
  (`build_bld_tex.py`, `embrasure()`), à la manière des anciens GTA.
- Un détail rapporté sur le mur (volet, appui, enseigne, affiche) est un **aplat** : un quad collé au mur (1 à 2 cm
  devant, sans épaisseur), jamais une boîte.

## Ce qui reste en volume
- Seulement les **structures extérieures** qui dépassent franchement : toits, débords et rives, petits pignons,
  cheminées, annexes, auvents et porches, marquises, stores bannes, escaliers extérieurs, rampes et rambardes,
  enseignes en drapeau, lampes, pompes, terrasses, mobilier.

## Fidélité : reconnaissable, pas exact
- Le but est qu'on **reconnaisse le bâtiment**, point. Dimensions approximatives acceptées.
- **Bâtiments non résidentiels : méthode du restaurant « Le Rochefestin »** (directive du 13/10, v6.20 ; remplace
  la fiche d'une ligne) :
  - Une ou deux photos Street View par bâtiment : le cache d'abord. Les photos payantes demandent l'accord de
    l'utilisateur, avec le coût estimé.
  - Relevé rapide (`releve_*.md`), sur l'emprise du cadastre :
    - volumes et travées ;
    - bon nombre de fenêtres et de portes, à leur place ;
    - devanture et enseigne, avec un **nom parodique** ;
    - couleurs et matériaux ;
    - éléments extérieurs (porches, auvents, marches, poubelles, appliques…) ;
    - affichettes.
  - Modèle sur mesure à la manière de `pipeline/boulangerie/build_restaurant.py` :
    - façades en aplat peintes dans un atlas ;
    - volume seulement pour les structures extérieures ;
    - **seuls les titres lisibles**, le reste en gribouillis ;
    - collisions en boîtes ;
    - entrée dans `world/sur_mesure.json`, qui remplace le bâtiment BD TOPO et la devanture générique.
  - Une seule passe de correction, d'après une planche photo/jeu prise sous les mêmes angles. Cette planche reste
    dans le cache privé.
  - Reconnaissable, pas exact : pas de relevé au centimètre, la boulangerie de la v6.17 avait été jugée trop longue.
- Fiche d'une ligne (`pipeline/sources/bati_fiches.txt`) : seulement pour un bâtiment qu'on ne voit pas assez sur les
  photos pour la méthode complète.
