---
id: voiture-modele
titre: Modèle 3D de la voiture (Espace IV Sketchfab)
tags: [voiture, espace, modèle 3d, sketchfab, car.bin, import, cc-by]
sources: [tools/import_car.py, car/CarModel.kt, render/Renderer.kt]
---
# Voiture (v0.9)

- Modèle « 2008 Renault Espace » de tonielpro520 (Sketchfab, **CC-BY-4.0**, crédit obligatoire dans le README).
  Téléchargement : `SKETCHFAB_TOKEN=… python3 tools/import_car.py --download` (jeton jamais écrit dans le dépôt),
  puis `python3 tools/import_car.py` -> `assets/car.bin`.
- Conversion : sommets fusionnés par position (le glTF est en triangles isolés), simplification quadrique
  (`fast-simplification`, caisse 25 %, roues 6 %), normales lissées sauf arêtes vives > 35° (`smooth_shade`),
  mise à l'échelle sur l'empattement (2,80 m ; longueur obtenue 4,66 m), repère du jeu (avant -z, droite +x).
- Matériaux : argent -> peinture rouge (pièces argent dans les passages de roue -> jantes), auto_11 -> vitres,
  chrome2 avant -> phares, rouges -> feux AR (effet freinage), intérieur assombri, volant du modèle retiré
  (volant animé du jeu placé à sa position, œil du conducteur 55 cm derrière), plaques « 4127 XR 38 » ajoutées.
- `car.bin` : 'CAR1', blocs caisse / vitres / roue (nv, ni, 12 floats par sommet, indices u32), puis 6 floats
  (centre du volant, œil). `CarModel.load` ; repli sur le modèle procédural si absent.
- ~110 k sommets de caisse + 4 × 14 k pour les roues.
