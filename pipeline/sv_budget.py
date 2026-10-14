"""RÈGLE ABSOLUE Street View (utilisateur ; 13/10/2026, plafond changé par l'utilisateur le 14/10/2026 dans l'issue
#13) : jamais plus de 9 000 appels d'images Street View par mois (le quota gratuit de Google est de 10 000 par mois ;
9 000 laisse une marge). Toute requête d'image (pas les métadonnées, gratuites) passe par payer() AVANT l'appel :
chaque essai est compté dans sources/sv_depenses.json (versionné), par mois de facturation Google (heure du
Pacifique), et le programme s'arrête net si l'appel ferait dépasser PLAFOND_MOIS. Ne jamais contourner, relever ni
remettre à zéro ce compteur sans une nouvelle décision écrite de l'utilisateur."""
import json, os, sys
from datetime import datetime
from zoneinfo import ZoneInfo

PLAFOND_MOIS = 9000
PRIX = 0.007            # prix public d'une image au-delà du quota gratuit (pour information)
F = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sources", "sv_depenses.json")


def mois():
    """Mois de facturation Google (les quotas mensuels repartent à minuit, heure du Pacifique)."""
    return datetime.now(ZoneInfo("America/Los_Angeles")).strftime("%Y-%m")


def etat():
    e = json.load(open(F)) if os.path.exists(F) else {"photos": 0}
    e.setdefault("mois", {})
    return e


def ce_mois():
    return etat()["mois"].get(mois(), 0)


def depense():
    """Coût au prix public de tout ce qui a été appelé depuis le début (information seulement)."""
    return etat()["photos"] * PRIX


def payer(n=1):
    e = etat()
    m = mois()
    deja = e["mois"].get(m, 0)
    if deja + n > PLAFOND_MOIS:
        sys.exit("PLAFOND STREET VIEW ATTEINT : %d appels ce mois-ci (%s), limite %d par mois — arrêt." % (deja, m, PLAFOND_MOIS))
    e["mois"][m] = deja + n
    e["photos"] += n
    json.dump(e, open(F, "w"), indent=1, ensure_ascii=False)
