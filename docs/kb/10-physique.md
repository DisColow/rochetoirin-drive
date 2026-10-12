---
id: physique
titre: Physique du véhicule et collisions
tags: [physique, vehicle, collisions, sol, boîte automatique]
sources: [car/Vehicle.kt, world/World.kt, world/Decor.kt]
---
# Physique (`Vehicle.update(dt, steer, throttle, brake)`)

- Moteur 2.0 16V (~140 ch, couple 191 N·m), convertisseur, boîte auto 5 rapports, marche arrière via `reverseSelected`.
- Direction : angle max décroissant avec la vitesse (0,62 / (1 + v/9)). Modèle bicyclette avec limite d'adhérence.
- Adhérence : route 0,98, chemin 0,75, hors route 0,62.
- Sol : hauteur aux 4 roues (`World.groundHeight`) -> tangage/roulis, suspension amortie, petits sauts.
- Collisions : boîte orientée 2,30 × 0,92 (demi-longueurs) contre `collide.bin` et troncs ; rebond à -20 % et `lastImpact`.
- Trottoirs/îlots : pas d'obstacle, montée par la surélévation `surf` interpolée sur 1 m.
