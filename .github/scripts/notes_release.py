"""Notes de la release vX.Y (GitHub Releases) : section « Nouveautés de la vX.Y » du README et mode d'installation.
Usage : python3 .github/scripts/notes_release.py X.Y > notes.md"""
import sys

v = sys.argv[1]
lines = open("README.md", encoding="utf-8").read().splitlines()
out, on = [], False
for l in lines:
    if l.startswith("Nouveautés de la v%s" % v):
        on = True
        continue
    if on and (l.startswith("[v") or l.startswith("**[") or l.startswith("## ")):
        break
    if on:
        out.append(l)
body = "\n".join(out).strip() or "Nouvelle version."
print("""## Nouveautés de la v%(v)s

%(body)s

## Installer
- **Android** : `RochetoirinSimulator-v%(v)s.apk` (Android 8+).
- **Windows** : `RochetoirinSimulator-v%(v)s-windows.zip`, dézipper puis lancer `RochetoirinSimulator.exe`.
- **Steam Deck** : `RochetoirinSimulator-v%(v)s-steamdeck.tar.gz`, en mode Bureau extraire l'archive, Steam > Jeux >
  Ajouter un jeu non Steam > `RochetoirinSimulator.x86_64`, puis jouer en mode Jeu (voir `LISEZMOI.txt`).

Fichiers construits automatiquement par GitHub Actions : les versions PC arrivent environ une demi-heure après l'APK."""
      % dict(v=v, body=body))
