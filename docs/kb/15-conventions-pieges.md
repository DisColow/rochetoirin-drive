---
id: conventions-pieges
titre: Conventions et pièges connus
tags: [conventions, pièges, axes, bugs, leçons]
sources: []
---
# Conventions

- Axes : x = Est, z = Sud, y = haut ; cap (yaw) 0 = Nord, horaire ; avant = (sin yaw, -cos yaw).
- Commentaires et textes en français. Style Kotlin compact, peu de commentaires, comme l'existant.
- Mesh.tri oriente les triangles selon la normale moyenne (pas besoin de soigner l'ordre).

# Pièges rencontrés

- Ne pas écraser `.gitignore` du dépôt en synchronisant (restaurer avec `git checkout .gitignore`).
- Trottoirs : sur-estimer l'emprise de l'enrobé laisse du terrain visible ; on la **sous-estime**.
- Maillages : segmentize trop fin = 100 Mo d'assets ; simplifier les contours (6 cm) et partager les sommets.
- Herbe fluo -> désaturer ; nuages invisibles -> étirer le fBm ; moiré de l'enrobé -> estomper par fwidth.
- Poly Haven : ajouter un User-Agent aux téléchargements (sinon 403). Modèles de 0,3 à 17 M de polygones :
  uniquement en imposteurs.
- `BitmapFactory` prémultiplie l'alpha : pour un alpha qui porte une donnée, décoder `inPremultiplied=false`
  et passer par `getPixels` + `glTexImage2D` (`Renderer.loadRgba`).
