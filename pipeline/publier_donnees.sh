#!/bin/bash
# Publie les données générées (godot/world, terrain, assets générés…) sur la branche « donnees », utilisée par
# l'action GitHub qui construit l'APK. Index temporaire : rien n'est copié, seuls les fichiers modifiés partent.
# À lancer depuis la racine du dépôt après avoir relancé une étape de pipeline/.
set -e
cd "$(dirname "$0")/../godot"
export GIT_INDEX_FILE=$(mktemp -u)
git --work-tree=. add -f world terrain assets/terrain_tex assets/tex assets/sky.hdr* assets/car \
  assets/terrain_assets.tres* assets/bld assets/veg assets/fence assets/sfx assets/cockpit assets/props \
  models/goku_*.png*
T=$(git write-tree)
rm -f "$GIT_INDEX_FILE"
git fetch -q origin donnees || true
P=$(git rev-parse -q --verify origin/donnees || true)
if [ -n "$P" ] && [ "$(git rev-parse "$P^{tree}")" = "$T" ]; then
  echo "données inchangées"; exit 0
fi
C=$(git commit-tree "$T" ${P:+-p $P} -m "Données générées par pipeline/ ($(date +%F))")
git push origin "$C:refs/heads/donnees"
echo "branche donnees : $C"
