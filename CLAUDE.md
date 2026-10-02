# Consignes du projet

- Après chaque livraison (modification du jeu, nouvel APK), **mettre à jour ce dépôt systématiquement** :
  commit + push sur `main`, sans demander de confirmation (on peut revenir en arrière avec git).
- Publier l'APK de release dans `releases/RochetoirinSimulator-vX.Y.apk` (version incrémentée) et mettre à jour
  le lien « Télécharger » du README. Les captures d'écran / comparatifs vont dans `docs/apercus/`.
- Avant de livrer : `./gradlew testDebugUnitTest` puis `./gradlew assembleRelease`.
- Les données brutes (`tools/data/`) ne sont pas versionnées : elles se régénèrent avec les scripts `tools/fetch_*`.
