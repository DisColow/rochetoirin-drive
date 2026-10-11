---
id: arborescence-code
titre: Organisation du code Kotlin
tags: [kotlin, architecture, modules, fichiers]
sources: [app/src/main/java/fr/rochetoirin/sim]
---
# Code Kotlin (`app/src/main/java/fr/rochetoirin/sim/`)

| Fichier | Rôle |
|---|---|
| `MainActivity.kt` | activité, préférences (`tilt`, `sound`, `hiGfx`, argent), capteur d'inclinaison, **manette** (dispatchKeyEvent / dispatchGenericMotionEvent) |
| `game/Game.kt` | boucle de jeu, `Input` (steer, throttle, brake, horn, orbit), livraisons, limites de vitesse, messages |
| `game/Gamepad.kt` | correspondance manette -> commandes (stick, gâchettes, A/B/Y/LB/RB) |
| `game/Gps.kt` | itinéraire (graphe routier) |
| `car/Vehicle.kt` | physique de l'Espace (moteur, boîte auto 5, adhérence, suspension, collisions, sol aux 4 roues) |
| `car/CarModel.kt` | maillage procédural de la voiture, dimensions (WHEELBASE, TRACK, WHEEL_R) |
| `world/World.kt` | chargement terrain/routes/carte, index spatial, `nearestRoad`, `groundHeight` |
| `world/Decor.kt` | props, arbres, obstacles (`collides`), surélévations `surf` (trottoirs) |
| `render/Renderer.kt` | GLSurfaceView.Renderer : tranches de profondeur, ombres, passes |
| `render/Shaders.kt` | tous les shaders GLSL (COMMON, TERRAIN, ROAD, PROPS, TREE, IMP, GRASS, SKY…) |
| `render/TreeRenderer.kt` | arbres procéduraux (3 LOD) + imposteurs |
| `render/GrassRenderer.kt`, `ShadowMaps.kt` | herbe 3D, ombres en cascades |
| `ui/HudView.kt` | interface : boutons ◀ ▶, pédales, D/R, GPS, panneaux (livraisons, carte, options) |
| `ui/MapPainter.kt` | mini-carte et grande carte |
| `audio/EngineSound.kt` | son moteur synthétisé, klaxon |
| `gl/Gl.kt`, `gl/Textures.kt` | utilitaires GL, textures procédurales (panneaux, feuilles, touffes) |
