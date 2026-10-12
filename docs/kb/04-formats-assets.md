---
id: formats-assets
titre: Formats binaires des assets
tags: [format, binaire, props.bin, trees.bin, surf.bin, roads.bin]
sources: [tools/prepare_data.py, tools/prepare_decor.py, tools/prepare_street.py, world/Decor.kt]
---
# Formats (little-endian)

- **terrain.bin / far.bin / pano.bin** : `TER1`, nx, nz, x0, z0, pas, puis nx*nz float32 (altitudes).
- **roads.bin / decals.bin** : en-tête `<4sfffii` (magic, X0, Z0, CHUNK, nCx, nCz) + nb tuiles ; par tuile
  cx, cz, nv, ni puis sommets de **10 floats** : pos3, normale3, latéral, abscisse, demi-largeur, style.
  Style : 0..8 types de chaussée (6 chemin de terre, 7 voie ferrée), +10 = enrobé sans marquage (disques de carrefour,
  angles arrondis), 27+ passage à niveau, 30 zébra, 31 stop, 32 cédez, 33+ plateaux.
- **props.bin / street.bin** : même en-tête, par tuile cx, cz, nv, ni, nbig ; sommets de **13 floats** :
  pos3, normale3, couleur3, uv2, matériau, extra. Les `nbig` premiers indices = partie visible de loin.
- **trees.bin** : `TRE1`, X0, Z0, CHUNK, nCx, nCz, nb tuiles ; instances de **6 floats** : x, y, z, hauteur, type, aléa.
- **surf.bin** : `SRF1`, X0, Z0, 32, nb ; tuiles de 32 m à 33×33 octets = surélévation en cm (trottoirs, îlots,
  plateaux) ajoutée au sol physique, interpolée bilinéairement.
- **collide.bin** : anneaux 2D (bâtiments, murets, poteaux…) testés par `Decor.collides`.
- **map.json** : nœuds, voies (nom, classe, vitesse, sens unique), ponts, lieux (POI), départ, limites.
- Textures PNG : `landcover` (classes de sol), `grassmask` (2 m, 255 = pas d'herbe), `groundao` (2 m),
  `trees_imp_col/nrm.webp`, `hedge_leaves.png` (atlas des imposteurs).
