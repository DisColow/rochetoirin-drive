#!/bin/bash
# Publie quelques fichiers générés sur la branche « donnees » SANS republier le reste de l'état local (contrairement à
# publier_donnees.sh, qui envoie tout world/, assets/… : risqué quand le conteneur n'a pas tout régénéré, ou a des
# .import refaits à la main). Part de l'arbre de « donnees » (arbres seulement, sans le contenu des fichiers) et ne
# remplace que les fichiers donnés, chemins relatifs à godot/ :
#   pipeline/publier_fichiers.sh world/trafic.bin assets/sfx/klaxon.ogg assets/sfx/klaxon.ogg.import
# (A_BLANC=1 : affiche seulement les différences avec « donnees »)
set -e
cd "$(dirname "$0")/../godot"
[ $# -gt 0 ] || { echo "usage : $0 <fichier relatif à godot/>…"; exit 1; }
git fetch -q --filter=blob:none --depth=1 origin donnees
P=$(git rev-parse FETCH_HEAD)

# remplace (ou ajoute) le blob $2 au chemin $3 dans l'arbre $1 ; affiche le nouvel arbre. --full-tree : sinon ls-tree
# ne liste que le sous-chemin du dossier courant (godot/) ; -z : noms accentués non échappés pour mktree.
remplacer() {
  local arbre=$1 blob=$2 chemin=$3
  local tete=${chemin%%/*}
  if [ "$tete" = "$chemin" ]; then
    { git ls-tree -z --full-tree "$arbre" | grep -z -v -P "\t\Q$chemin\E$" || true
      printf '100644 blob %s\t%s\0' "$blob" "$chemin"; } | git mktree -z --missing
  else
    local sous neuf
    sous=$(git ls-tree --full-tree "$arbre" "$tete" | awk '{print $3}')
    [ -n "$sous" ] || sous=$(printf '' | git mktree)
    neuf=$(remplacer "$sous" "$blob" "${chemin#*/}")
    { git ls-tree -z --full-tree "$arbre" | grep -z -v -P "\t\Q$tete\E$" || true
      printf '040000 tree %s\t%s\0' "$neuf" "$tete"; } | git mktree -z --missing
  fi
}

T=$(git rev-parse "$P^{tree}")
for f in "$@"; do
  [ -f "$f" ] || { echo "absent : $f"; exit 1; }
  B=$(git hash-object -w "$f")
  T=$(remplacer "$T" "$B" "$f")
  echo "$f -> $B"
done
if [ "$T" = "$(git rev-parse "$P^{tree}")" ]; then
  echo "données inchangées"; exit 0
fi
if [ -n "$A_BLANC" ]; then                     # essai : différences avec « donnees », rien n'est poussé
  git diff-tree -r --name-status "$P" "$T"; exit 0
fi
C=$(git commit-tree "$T" -p "$P" -m "Données : $* ($(date +%F))")
git push origin "$C:refs/heads/donnees"
echo "branche donnees : $C"
