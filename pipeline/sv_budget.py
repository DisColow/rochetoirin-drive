"""RÈGLE ABSOLUE (utilisateur, 13/10/2026) : jamais plus de 20 $ de photos Street View payantes, au total.
Toute requête d'image Street View (pas les métadonnées, gratuites) passe par payer() AVANT l'appel : chaque essai est
compté au prix fort (0,007 $) dans sources/sv_depenses.json (versionné), et le programme s'arrête net si l'appel
ferait dépasser PLAFOND_USD. Ne jamais contourner, relever ni remettre à zéro ce compteur."""
import json, os, sys

PLAFOND_USD = 20.0
PRIX = 0.007
F = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sources", "sv_depenses.json")


def etat():
    return json.load(open(F)) if os.path.exists(F) else {"photos": 0}


def depense():
    return etat()["photos"] * PRIX


def payer(n=1):
    e = etat()
    if (e["photos"] + n) * PRIX > PLAFOND_USD + 1e-9:
        sys.exit("PLAFOND STREET VIEW ATTEINT : %.2f $ dépensés, limite absolue %.0f $ — arrêt." % (e["photos"] * PRIX, PLAFOND_USD))
    e["photos"] += n
    json.dump(e, open(F, "w"), indent=1)
