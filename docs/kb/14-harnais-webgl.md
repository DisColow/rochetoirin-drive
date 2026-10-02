---
id: harnais-webgl
titre: Harnais WebGL de validation visuelle
tags: [webgl, playwright, captures, validation, chromium]
sources: [tools/apercu/]
---
# Harnais WebGL (`tools/apercu/`)

Reproduit le rendu du jeu dans Chromium (swiftshader) pour faire des captures sans téléphone :
`mkshaders.py` extrait les shaders de `Shaders.kt` vers `shadersrc.json` ; `world2.html` charge les assets
(copier `app/src/main/assets/*` dans le dossier servi) ; `worldshot2.js <dossier> '<json>'` produit des PNG.
Plan JSON : `{"name", "pos":[x,z] | "at": POI, "eye":[dx,dy,dz], "tgt":[dx,dy,dz], "fov", "nocar"}`.
Penser à mettre à jour le harnais quand on ajoute une passe de rendu (ex. imposteurs).
