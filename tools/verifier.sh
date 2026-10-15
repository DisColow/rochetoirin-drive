#!/bin/bash
# Contrôle avant livraison (issue #30) : à lancer depuis la racine du dépôt, après l'import Godot.
#   tools/verifier.sh            vérification des scripts GDScript (rapide, ~2 min)
#   tools/verifier.sh --complet  + essais en jeu sans écran (xvfb, ~30 min) : casse, champ, captures de base
# Sortie : liste des erreurs ; code de retour 1 s'il y en a.
cd "$(dirname "$0")/../godot" || exit 1
J=$(mktemp -d)
ERR=0

echo "== scripts GDScript"
for f in scripts/*.gd tools/*.gd; do
  out=$(timeout 120 godot --headless --check-only --script "res://$f" 2>&1 | grep -E "SCRIPT ERROR|Parse Error|ERROR: .*\.gd")
  if [ -n "$out" ]; then
    echo "ERREUR $f"; echo "$out" | head -5; ERR=1
  fi
done

if [ "$1" = "--complet" ]; then
  essai() {   # nom, arguments du jeu
    local n=$1; shift
    pkill -9 -x speech-dispatch 2>/dev/null   # speech-dispatcher planté : il bloque Godot au démarrage (étape « Interface »)
    NIVEAU=1 timeout 1500 xvfb-run -a -s "-screen 0 960x540x24" godot --path . --resolution 960x540 -- "$@" > "$J/$n.log" 2>&1
    local c=$?
    local e
    e=$(grep -a -E "SCRIPT ERROR|Invalid (call|access|get|set)|Nonexistent function" -A2 "$J/$n.log" | head -12)
    if [ $c -ne 0 ] || [ -n "$e" ]; then
      echo "ERREUR essai $n (code $c)"; echo "$e"; ERR=1
    else
      echo "ok essai $n"
    fi
  }
  echo "== essais en jeu (journaux dans $J)"
  essai casse --drive-test --casse-test
  essai champ --drive-test --champ-test --champ-type=0
  essai conduite --drive-test
fi

[ $ERR -eq 0 ] && echo "== aucune erreur" || echo "== ERREURS : voir ci-dessus"
exit $ERR
