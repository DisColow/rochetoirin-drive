---
id: regles-depot
titre: Règles du dépôt, livraison et sécurité
tags: [git, livraison, apk, release, sécurité, clé api]
sources: [CLAUDE.md]
---
# Règles de livraison

1. Après chaque livraison : **commit + push sur `main` sans demander** (le propriétaire préfère, git permet de revenir en arrière).
2. Avant de livrer : `./gradlew testDebugUnitTest` puis `./gradlew assembleRelease`.
3. APK publié dans `releases/RochetoirinSimulator-vX.Y.apk` (version incrémentée) ; mettre à jour le lien
   « Télécharger » du README. Captures et comparatifs dans `docs/apercus/`.
4. Ne jamais versionner `tools/data/` ni d'image Street View.
5. **Clé Google** : uniquement via la variable d'environnement `GOOGLE_MAPS_API_KEY`, jamais écrite dans un fichier du dépôt.
6. Copie de travail habituelle : `/home/user/rochetoirin-truck` (dev) synchronisée vers `/home/user/rochetoirin-drive` (dépôt).
   Synchroniser `app/src`, `tools` (sans `tools/data`, `__pycache__`), `docs`, puis `git add -A`.
7. Messages de commit en français, auteur assisté signalé par les lignes d'attribution demandées.
8. Cache Street View privé : `DisColow/rochetoirin-streetview` (220 images + index). Le restaurer avant d'appeler l'API Google (quota), y pousser toute nouvelle image. Ne jamais copier ces images dans le dépôt public.
