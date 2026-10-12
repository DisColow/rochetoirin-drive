---
id: rue-balcon
titre: Rue du Balcon refaite d'après Street View (axe, profil, clôtures, lampadaires)
tags: [rue du balcon, street view, axe, cadastre, trottoir, caniveau, placette, clôtures, lampadaires, relevé, comparaison]
sources: [tools/rue_balcon.py, tools/fetch_sv_street.py, tools/prepare_data.py, tools/prepare_street.py, tools/prepare_quartier.py]
---
# Rue du Balcon (v0.13)

## Méthode (à réutiliser pour toute rue)
1. Cache privé Street View d'abord (règle quota). `python3 tools/fetch_sv_street.py "Rue du Balcon" "Impasse du Balcon"` :
   un panorama tous les ~10 m (dédoublonné par pano_id), 4 vues fov 90 (f/l/r/b, cap = sens de la rue) ->
   `data/streetview/rues/<pano>_<dir>.jpg` + `index.json` ; pousser ensuite dans le dépôt privé.
2. Rendre les mêmes caméras dans le harnais (`worldshot3.js` + `world3.html` en 800 × 600, vfov = 2·atan(0,75)).
   **Piège** : `world2.html` code en dur `<canvas width=2400 height=1080>` ET `const W=2400,H=1080` (viewport) ; changer
   les deux, sinon la capture ne montre qu'un coin de l'image et tout paraît décalé de plusieurs mètres.
3. Planches SV / jeu côte à côte ; plan (parcelles, couloir public, OSM, caméras) ; orthophoto recadrée.
4. Relevé par parcelle : vue latérale du panorama le plus proche avec l'emprise de la façade marquée.

## Constats
- Axe OSM 2 à 3 m trop au nord -> `AXE`. Partie est (panoramas 2022) : trace des caméras SV décalée de 0,7 m vers le
  sud (caniveau central). Partie ouest : les panoramas de **2014 sont décalés d'environ 2 m vers le sud** (dérive GPS :
  le trottoir mordait les parcelles, murets et portails sautaient) -> axe à 4,1 m de la limite cadastrale sud.
  Leçon : recouper toute position SV avec le cadastre ; `sv_cam_fix` corrige les caméras 2014 pour les comparaisons.
  `rue_balcon.apply_osm` remplace la voie dans `prepare_data.parse_osm` (nœud du carrefour est conservé).
- Placette au bout + impasse nord (3 portails) ; vers l'ouest couloir de 2,5 m = chemin piéton enrobé (aucun
  panorama : la voiture Google n'y passe pas) jusqu'à l'impasse du Balcon.
- Profil : chaussée 5 m, caniveau central béton (s < 100 m), trottoir 1,4 m côté sud (tag `sidewalk=left`,
  `sidewalk:width`), accotement nord gravier (s < 100) puis enrobé (lotissement), herbe côté sud.
- Lampadaires relevés (`LAMPS`, mât gris 6 m), le générateur automatique saute la rue.
- Clôtures (`CLOTURES`, clé = idu cadastral, prioritaire sur `clotures_bourg.json`) ; parcelles bâties non relevées en
  bordure : haie de laurier sur muret blanc (`DEFAULT`, style dominant) au lieu d'un tirage au hasard. Nouveautés :
  `piquets` (grillage sur piquets bois), `hmur` (hauteur du muret), lisses bois devant la haie (`grille: bois`),
  grille sur muret, portail `plein_rouge`.
- 2014 pour la moitié ouest (le passage 2022 s'arrête vers x = -310) : recouper avec l'orthophoto (plus récente).
- Caniveau central : maillage à plat sur l'enrobé, admis par `guarded_add(..., flat=True)` (la garde « rien sur la
  chaussée » le rejetait).
- Piscines : aucune entre la maison et la rue du Balcon (jardins de devant sans piscine sur SV) : une « piscine » plus
  proche de la rue que la maison de sa parcelle est une bâche ou un reflet (`prepare_decor`).
