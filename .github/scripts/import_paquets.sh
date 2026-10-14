#!/bin/bash
# Import Godot par paquets (v6.45) : un import d'un seul tenant du monde complet dépasse la mémoire (code 137, ou
# serveur GitHub arrêté). Les gros dossiers sont sortis du projet puis remis par paquets de 700 fichiers, avec un import
# à chaque fois ; les fichiers déjà importés ne sont pas refaits. Ne pas utiliser .gdignore : leur retrait fait tout
# réimporter. À lancer depuis godot/.
H=${HORS:-/tmp/hors_import}
D="assets/voix assets/sur_mesure world/buildings world/veg world/roads world/fences world/crops world/poles world/animaux world/props world/water world/bord"
imp() { timeout 3000 godot --headless --import > /tmp/import_$1.log 2>&1; local c=$?; echo "import $1 : code $c"; [ $c -ne 0 ] && tail -5 /tmp/import_$1.log; }
rm -rf $H; mkdir -p $H
for d in $D; do
  [ -d $d ] || continue
  mkdir -p $H/$d
  find $d -maxdepth 1 -type f -exec mv -t $H/$d {} +
done
imp base
n=0
for d in $D; do
  [ -d $H/$d ] || continue
  while :; do
    lst=$(ls $H/$d | grep -v '\.import$\|\.uid$' | head -700)
    [ -z "$lst" ] && break
    for f in $lst; do
      mv $H/$d/$f $d/
      for x in import uid; do [ -f $H/$d/$f.$x ] && mv $H/$d/$f.$x $d/; done
    done
    n=$((n+1)); imp $n
  done
  find $H/$d -maxdepth 1 -type f -exec mv -t $d/ {} + 2>/dev/null
done
imp final
imp final2
