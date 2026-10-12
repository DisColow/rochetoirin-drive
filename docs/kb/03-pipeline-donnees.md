---
id: pipeline-donnees
titre: Pipeline de génération des données (tools/)
tags: [python, pipeline, génération, assets, ordre]
sources: [tools/]
---
# Pipeline (`tools/`, Python 3 : numpy, shapely 2, pillow, scipy, mapbox-earcut)

Ordre :
1. `fetch_osm.sh` (Overpass, bbox 45.552,5.383,45.618,5.445), `fetch_elevation.py` (RGE ALTI), `fetch_decor.py`
   (BD TOPO + RPG via WFS), `fetch_ortho.py` (orthophoto 20 cm du bourg), `fetch_cadastre.py` (rue du Balcon),
   facultatif `fetch_streetview.py` (clé `GOOGLE_MAPS_API_KEY`) puis `prepare_facades.py`.
2. `prepare_data.py` -> `terrain.bin`, `far.bin`, `roads.bin`, `map.json`, `data/road_rows.pkl` (rangées des rubans).
3. `prepare_decor.py` -> `landcover.png`, `landfar.png`, `props.bin`, `trees.bin`, `collide.bin`, `pano.bin`
   (appelle `center.py`, `prepare_village.py`, lit `data/facades.json`).
4. `prepare_street.py` -> `street.bin`, `decals.bin`, `surf.bin`, `street.json`, `grassmask.png`, `groundao.png`
   (+ obstacles ajoutés à `collide.bin`) ; appelle `sidewalks.py`, `center.furniture`, `prepare_quartier.build`.
5. Arbres en imposteurs (une fois) : `tools/arbres/` (voir fiche arbres-imposteurs).

Durées : prepare_decor ~3 min, prepare_street ~2 min. Repère local : x = Est, z = Sud (m), y = altitude.
Modules d'appui : `geo.py` (to_local / to_lonlat), `center.py` (centre du village fait main),
`prepare_village.py` (analyse orthophoto), `prepare_quartier.py` (rue du Balcon), `sidewalks.py` (trottoirs).
