---
id: architecture-bourg
titre: Architecture des maisons du bourg relevée sur Street View
tags: [architecture, maisons, toits, garages, street view, archi, bourg]
sources: [tools/archi.py, tools/archi_bourg.json, tools/prepare_decor.py, tools/prepare_facades.py]
---
# Architecture (v0.7)

- `tools/archi_bourg.json` : 127 maisons annotées à la main d'après les 198 vues Street View (planches contact) :
  toit "2"/"4"/"p", niv, ss (garage en sous-sol), gar, bal, esc, auv, chem, comb, solaire, vieux, pierre, pise, grange, bois,
  cam (position de la caméra = côté rue).
- `archi.plan` : hauteur des murs par niveaux, toit à deux pans si emprise rectangulaire, matériau (moellons, pisé en crépi
  terre, bois). `archi.roof_height` : pente (combles = toit raide).
- `archi.extras` sur la façade tournée vers la caméra (`street_edge`) : portes de garage centrées (au sol local, maisons
  en pente), escalier extérieur, auvent (pan de tuiles, sur consoles au-dessus du garage ou sur poteaux), balcon à
  garde-corps, cheminée, panneaux solaires (pan sud des toits à deux pans).
- Maisons du bourg non relevées : ~45 % de toits à deux pans (répartition observée).
- Couleur des tuiles mesurée sur Street View (`prepare_facades.roof_color`, pixels chauds au-dessus de la façade), sinon
  orthophoto. Constat : maisons de plain-pied à croupes dans les lotissements, R+1 sur garage enterré, granges en pisé.
