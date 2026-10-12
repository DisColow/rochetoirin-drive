---
id: tests-build
titre: Tests, build et publication
tags: [tests, gradle, build, apk, robolectric]
sources: [app/src/test]
---
# Tests et build

- `./gradlew testDebugUnitTest` : `SimulationTest` (monde réel chargé depuis `src/main/assets` : chargement,
  accélération/freinage, pilote automatique de livraison, collisions bâtiment, **montée de trottoir**),
  `HudSnapshotTest` (rendu de l'interface en PNG dans `app/build/hud/`), `GamepadTest`.
- `./gradlew assembleRelease` -> `app/build/outputs/apk/release/app-release.apk` (~22 Mo).
- Pas d'émulateur utilisable dans le conteneur (pas de KVM) : rien n'est testé sur téléphone réel — le dire au propriétaire.
- `collisionWithHouse` part de x = 78 (un chêne réel de l'orthophoto gêne ailleurs).
