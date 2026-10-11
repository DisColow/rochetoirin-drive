---
id: rendu
titre: Rendu : tranches, ombres, lumière, ciel, herbe
tags: [rendu, opengl, ombres, aces, brouillard, herbe, performance]
sources: [render/Renderer.kt, render/Shaders.kt, render/ShadowMaps.kt, render/GrassRenderer.kt]
---
# Rendu

- **Tranches de profondeur** (précision du z-buffer) : [5000, 260000], [500, 6000], [36, 600], [0.1, 40] m ; le
  z-buffer est vidé entre tranches. Les tuiles sont filtrées par `inRange` + frustum.
- **Ombres** : `ShadowMaps.kt`, 2 cascades (45 m et 300 m), 2048², `sampler2DShadow` PCF, accrochage au texel.
  `sunShadow(p, n)` dans COMMON ; uniformes `uShadow0/1` (unités 6/7), `uShadowM0/1`, `uShadowP`.
  Programmes de profondeur : PROPS_DEPTH_FS, DEPTH_FS (voiture), TREE_DEPTH_FS, IMP_DEPTH_FS.
- **Couleur** : `grade()` = ACES ×0,86, saturation 0,97 ; `fogged()` brume (HAZE) ; ciel `SKY_FS` avec cumulus (uNoise, uTime).
- **Herbe 3D** : instanciée autour de la caméra (rayon 30 m, pas 0,42 m), hauteurs via texture R32F, densité par
  classe de sol, masque `grassmask.png`, vent.
- **AO du sol** : `groundao.png` (2 m) unité 8 pour terrain/route/herbe.
- **Option « graphismes élevés »** (pref `hiGfx`) : désactivée = pas d'ombres ni d'herbe.
- Unités de texture : 0 herbe/plaques, 1 bruit, 2 sol/panneaux, 3 feuilles, 6-7 ombres, 8 AO, 9-10 imposteurs.
- Validation visuelle sans téléphone : harnais WebGL (fiche harnais-webgl).
