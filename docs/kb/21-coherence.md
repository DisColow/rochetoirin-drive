---
id: coherence
titre: Règle d'or — la logique prime sur la donnée brute
tags: [cohérence, logique, placement, règles, validation, haies, trottoirs, piscines, taches, routes]
sources: [tools/check_coherence.py, tools/coherence.py]
---
# La logique prime sur la vérité absolue (demande explicite du propriétaire)

Les sources (OSM, orthophoto, cadastre, BD TOPO, Street View) sont imprécises de quelques mètres. Quand une donnée
mène à une scène illogique, on **corrige vers le plausible** plutôt que de la reproduire. Règles :

1. **Rien sur la chaussée ni sur les trottoirs** : arbres, haies, buissons, piscines, mobilier, voitures garées,
   clôtures. Emprise interdite = enrobé (`carriageway`) + trottoirs + 0,5 m.
2. **Clôtures, murets et haies continus et raccordés** : un seul style par façade de propriété, posé d'un bout à
   l'autre de la limite (ouvert uniquement au portail), angles fermés, pas de trous de 1 m entre tronçons, pas de
   superposition haie + grillage sur la même limite.
3. **Pas de routes qui se chevauchent** : les voies OSM doublons (service / chemin collé à une route) sont fusionnées
   ou supprimées.
4. **Pas de taches** : les petites plaques de sol (gravier, enrobé, béton) détectées sur l'orthophoto sont supprimées
   sauf allée reliant le portail à la maison ou cour accolée ; classes de sol lissées (pas d'îlots < 20 m²).
5. **Piscines seulement dans un jardin** : dans une parcelle habitée, à plus de 3 m d'une route et d'un bâtiment.
6. Vérifier après chaque génération : `python3 tools/check_coherence.py` doit rapporter **0** violation.

## Mise en œuvre (v0.11)

- `prepare_data.dedupe_and_cross` : doublons OSM supprimés (80 % dans la chaussée d'une voie plus importante),
  croisements sans nœud raccordés, segments > 12 m densifiés ; `separate_overlaps` écarte les nœuds propres à une voie
  (0,5 m entre bords, 3 m entre chaussées d'autoroute), hors carrefours et biseaux de bretelles.
- `prepare_street` écrit `data/surfaces.pkl` (chaussée, chaussée arrondie, trottoirs). Gardes : tout ce que posent
  `center`, `mobilier` et `prepare_quartier` passe par `guarded_add` / `guarded_coll` (rejeté si > 5 % des sommets sur
  la chaussée ou > 25 % sur un trottoir) ; petits objets et poteaux jamais sur la chaussée ; glissières coupées là où
  elles traverseraient l'autre chaussée.
- `prepare_decor` : arbres retirés à moins d'1 m de la chaussée ou d'un trottoir ; piscines seulement entièrement dans
  une parcelle habitée, à 3 m de la chaussée et 1,5 m des maisons ; cours (YARD) du bourg gardées seulement si
  >= 190 m², contour lissé.
- `prepare_quartier` : par limite, un seul type / décalage / essence ; limites côté rue reculées hors du trottoir (ou
  rognées) ; trous de 1 à 2 morceaux comblés ; morceaux contigus fusionnés en un seul tronçon (coupé au portail et
  quand le terrain varie de plus de 40 cm) ; limite avec une impasse / voie privée = côté rue ; haies tracées d'après la
  photo coupées hors chaussée / trottoir. Sols durs : allée droite portail -> maison + cours >= 60 m² collées à la
  maison (contours lissés) + accotements de la rue du Balcon ; plus aucune cellule pixelisée.
- `check_coherence.py` : arbres, obstacles, piscines, routes superposées, trous de clôture (journal `data/fences.json`).
  Exceptions logiques : croisement à niveau de deux axes sans nœud OSM (= carrefour) ; trou de clôture occupé par une
  annexe bâtie sur la limite (la clôture s'appuie sur ses murs).
- Surfaces plates sur terrain bombé : triangles subdivisés (`sidewalks.subdivide`, arêtes <= 2,5 m) sinon le sol perce
  au milieu (« anneau » de cour). Triangulation réparée (`make_valid`, repli Delaunay contraint).
- Piège outillage : ne jamais `pkill -f` / `pgrep -f` un motif qui figure dans sa propre commande (le shell se tue
  lui-même) ; lancer les régénérations via un script (`regen.sh`).
