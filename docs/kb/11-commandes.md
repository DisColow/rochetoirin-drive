---
id: commandes
titre: Commandes tactiles, inclinaison et manette
tags: [commandes, hud, manette, gamepad, boutons, inclinaison]
sources: [ui/HudView.kt, game/Gamepad.kt, MainActivity.kt]
---
# Commandes (v0.6)

- **Écran** : boutons ◀ ▶ en bas à gauche (braquage en rampe 1,6/s, retour 4,5/s, courbe progressive) ; on peut
  glisser d'un bouton à l'autre ; klaxon (losange) au-dessus ; pédales analogiques à droite (plus haut = plus fort) ;
  sélecteur D/R ; glisser ailleurs = orbite caméra. Option inclinaison du téléphone.
- **Manette** : stick gauche (zone morte 0,12) ou croix = direction ; RT (AXIS_RTRIGGER/GAS) = gaz ; LT = frein ;
  A / B (ou croix haut/bas) = gaz/frein tout-ou-rien ; Y = D/R ; LB = klaxon ; RB / Select = caméra ; stick droit = orbite.
  Priorité : stick analogique > boutons ◀ ▶ / croix > inclinaison. Gaz/frein = max(écran, manette).
- Les menus (livraisons, carte, options) restent au doigt.
- Test : `GamepadTest`.
