# Plan : des clients du taxi qui parlent de la vraie actualité

Statut : **en service depuis la v6.11** (12 octobre 2026). Choix de l'utilisateur (issue #6) : sources Le Dauphiné
Libéré + France Info, **pas de sport**, **aucun sujet exclu**, une conversation sur deux. Les voix sont celles du
téléphone (v6.8) : plus de fichiers son à fabriquer, le paquet ne contient que le texte.

## Pourquoi pas de génération en temps réel sur le téléphone

Générer dialogue **et** voix au moment où le client monte demanderait :

- une IA de génération de texte appelée depuis le téléphone : clé d'API dans l'APK (extractible par n'importe qui) ou
  serveur relais à héberger ;
- la synthèse vocale embarquée (extension sherpa-onnx compilée pour Android, ~30 Mo, APK complet) ;
- une connexion pendant la partie et quelques secondes d'attente par réplique.

Lourd, fragile et payant à chaque course. L'actualité change à l'échelle de la journée : on peut tout préparer
**une fois par jour, hors du téléphone**.

## Principe : l'« actu du jour » préparée chaque matin par GitHub Actions

### 1. Action programmée (chaque jour vers 6 h, `.github/workflows/actu.yml`)

1. **Sources** (flux RSS publics, titres et résumés seulement) :
   - national : France Info ;
   - local : Le Dauphiné Libéré (Isère, Nord-Isère, Bourgoin-Jallieu) ;
   - sport : un flux sport national.
2. **Météo réelle du jour** à Rochetoirin : Open-Meteo (gratuit, sans clé) — les clients commentent le temps qu'il
   fait vraiment.
3. **Écriture des dialogues** par l'API Claude (clé dans le secret GitHub `ANTHROPIC_API_KEY`, jamais dans l'APK) :
   12 à 15 fils de conversation au **format actuel** de `godot/data/taxi.json` (`fils` : le client lance le sujet
   avec ses mots, trois réponses sur des tons différents — chaleureux, drôle, curieux, sobre —, il enchaîne ; **pas de
   réplique d'appréciation** après nos réponses). Textes reformulés, jamais recopiés des articles. Chaque fil est
   marqué par caractère (râleur, nostalgique, farceur…) pour que la personnalité colore l'avis.
4. **Voix** : même chaîne que `pipeline/build_voix.py` (Piper, effet talkie « D », normalisation à -1 dBFS), pour
   les 6 voix de clients (f1-f3, m1-m3) et le chauffeur (UPMC « Pierre ») — environ 600 fichiers, 5 à 10 Mo.
5. **Contrôles avant publication** : format JSON validé, longueur des répliques, filtres de sujets ; en cas d'échec,
   le paquet de la veille reste en place.
6. **Publication** : paquet `actu-AAAA-MM-JJ.zip` (dialogues + voix + index) sur une branche dédiée `actu`, avec un
   `actu.json` qui indique le dernier paquet.

### 2. Dans le jeu

- Au lancement (`boot.gd` ou un script téléchargé à part, sans bloquer le jeu) : téléchargement du paquet du jour
  dans `user://actu/`.
- `taxi_talk.gd` : une conversation sur deux (réglable) pioche un fil d'actualité adapté au caractère et à la voix du
  client ; sinon, les sujets habituels (métier, famille, loisirs…).
- **Hors ligne** : dernier paquet reçu s'il a moins de 3 jours, sinon dialogues habituels seulement.
- Nouveau réglage possible : ⚙ > Taxi > « Actualité dans les conversations » (oui / non).

### 3. Garde-fous éditoriaux

- Pas de faits divers tragiques (morts, agressions, accidents graves), pas de sujets violemment clivants.
- Aucune personne privée nommée ; personnalités publiques seulement dans un registre neutre.
- Avis de passagers légers, variés, jamais haineux.

## Coût et charge

- API Claude : quelques centimes par jour.
- GitHub Actions : ~10 minutes par jour.
- Téléphone : aucun calcul, 5 à 10 Mo téléchargés par jour.

## À fournir par l'utilisateur au lancement

1. Le secret `ANTHROPIC_API_KEY` dans le dépôt (Settings > Secrets and variables > Actions).
2. Validation des sources (France Info + Le Dauphiné Libéré + sport ?), des sujets exclus, et de la part d'actualité
   dans les conversations (une sur deux ?).
