---
id: mobilier
titre: Mobilier et équipements du bourg (abribus, croix, terrains)
tags: [mobilier, abribus, arrêt de bus, croix, terrain, foot, tennis, boules, aire de jeux, osm]
sources: [tools/mobilier.py, tools/fetch_sv_points.py, tools/prepare_street.py]
---
# Mobilier du bourg (v0.8)

- Données : OSM (Overpass, miroir overpass.private.coffee si l'officiel coupe) -> `data/osm_bourg.json` (nœuds),
  `data/osm_bourg_ways.json` (contours des terrains, `out geom`). Vues Street View de chaque point :
  `fetch_sv_points.py points.json` -> `data/streetview/points/`.
- `mobilier.build` (appelé par prepare_street) : arrêts de bus (poteau bleu, zigzags jaunes au bord de chaussée,
  abribus bleu vitré à l'arrêt « Rochetoirin - Église »), croix de chemin en pierre sur socle, terrains de foot (buts,
  lignes), city-stade (sol vert, palissade bois + grillage, buts/paniers), boules (gravier + bordure bois), tennis
  (sol, lignes, filet, grillage vert), aire de jeux (balançoire, toboggan, jeux à ressort, dans la partie libre),
  table de pique-nique, borne de recharge, poteau d'incendie, panneaux d'information. Obstacles ajoutés à collide.bin.
