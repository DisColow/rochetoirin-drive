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
- **Réutiliser le bâtiment déjà généré** (volume BD TOPO) et le corriger par une **fiche d'une ligne**
  (`pipeline/sources/bati_fiches.txt`) : couleur de l'enduit, matériaux, toit, niveaux, volets, chaînages, porche…
  Pas de modèle sur mesure ni de relevé au centimètre (la boulangerie de la v6.17 a été jugée beaucoup trop longue).
- Méthode rapide pour les bâtiments non résidentiels : regarder 1 ou 2 photos (cache Street View d'abord), écrire la
  fiche, passer au suivant. Les photos Street View payantes demandent l'accord de l'utilisateur avec le coût estimé.
