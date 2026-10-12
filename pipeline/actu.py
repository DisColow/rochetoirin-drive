"""Actualité du jour pour les clients du taxi (issue #6, plan docs/plan_actualites.md) : lancé chaque matin par
.github/workflows/actu.yml.
  1. titres des dernières 72 h : Le Dauphiné Libéré (via Google Actualités : Bourgoin-Jallieu, Nord-Isère, Isère)
     et France Info (titres nationaux) ; pas de sport (choix de l'utilisateur) ; aucun sujet exclu ;
  2. météo du jour à Rochetoirin (Open-Meteo, sans clé) ;
  3. l'API Claude écrit des fils de conversation au format de godot/data/taxi.json (le client parle, trois réponses
     sur des tons différents, il enchaîne ; pas de réplique d'appréciation) ; clé ANTHROPIC_API_KEY (secret GitHub) ;
  4. contrôles (format, longueur, accords) ; si moins de 5 fils valides, on garde le paquet de la veille ;
  5. sortie : actu.json (publié par l'action sur la branche « actu », téléchargé par le jeu au lancement).
Lancer : python3 actu.py [--sortie actu.json] [--sans-ia : titres et météo seulement, pour essai]"""
import argparse, datetime as dt, email.utils, html, json, re, sys, urllib.parse, urllib.request
import xml.etree.ElementTree as ET

MODELE = "claude-opus-5-5"
FLUX_LOCAUX = [
    ("Le Dauphiné Libéré", "site:ledauphine.com Bourgoin-Jallieu"),
    ("Le Dauphiné Libéré", "site:ledauphine.com Nord-Isère"),
    ("Le Dauphiné Libéré", "site:ledauphine.com Isère"),
]
FLUX_NATIONAUX = [("France Info", "https://www.franceinfo.fr/titres.rss")]
SPORT = re.compile(r"\b(foot|football|rugby|basket|handball|tennis|cyclis|vélo|tour de france|ligue 1|ligue 2|top 14|"
                   r"match|championnat|coupe du monde|euro 20|JO |jeux olympiques|olympique|athlét|ski alpin|biathlon|"
                   r"formule 1|F1|moto ?gp|PSG|OL\b|OM\b|FCG|CSBJ|but[s]? |buteur|entraîneur|sélectionneur)", re.I)
METEO_CODES = {0: "grand soleil", 1: "plutôt dégagé", 2: "partiellement nuageux", 3: "couvert", 45: "brouillard",
               48: "brouillard givrant", 51: "bruine légère", 53: "bruine", 55: "forte bruine", 61: "pluie faible",
               63: "pluie", 65: "forte pluie", 66: "pluie verglaçante", 67: "pluie verglaçante", 71: "un peu de neige",
               73: "neige", 75: "forte neige", 77: "grésil", 80: "averses", 81: "averses", 82: "violentes averses",
               85: "averses de neige", 86: "fortes averses de neige", 95: "orages", 96: "orages et grêle", 99: "orages et grêle"}
UA = {"User-Agent": "Mozilla/5.0 (RochetoirinSimulator actu)"}


def lire(url, delai=40, essais=3):
    for i in range(essais):
        try:
            return urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=delai).read()
        except Exception:
            if i == essais - 1:
                raise


def titres(source, url, max_age_h=72):
    out = []
    try:
        racine = ET.fromstring(lire(url))
    except Exception as e:                      # une source en panne n'arrête pas le reste
        print("source indisponible :", source, url, e, file=sys.stderr)
        return out
    maintenant = dt.datetime.now(dt.timezone.utc)
    for it in racine.iter("item"):
        t = html.unescape((it.findtext("title") or "").strip())
        t = re.sub(r"\s+-\s+Le Dauphiné Libéré$", "", t)
        d = it.findtext("pubDate")
        try:
            quand = email.utils.parsedate_to_datetime(d) if d else maintenant
        except Exception:
            quand = maintenant
        if (maintenant - quand).total_seconds() > max_age_h * 3600 or not t or SPORT.search(t):
            continue
        desc = re.sub(r"<[^>]+>", " ", html.unescape(it.findtext("description") or ""))
        desc = re.sub(r"\s+", " ", desc).strip()
        out.append({"source": source, "titre": t, "resume": desc[:300] if source == "France Info" else "",
                    "date": quand.astimezone(dt.timezone(dt.timedelta(hours=2))).strftime("%Y-%m-%d %H:%M")})
    return out


def collecte():
    loc, nat, vus = [], [], set()
    for source, q in FLUX_LOCAUX:
        url = "https://news.google.com/rss/search?" + urllib.parse.urlencode({"q": q, "hl": "fr", "gl": "FR", "ceid": "FR:fr"})
        for t in titres(source, url):
            if t["titre"] not in vus:
                vus.add(t["titre"]); loc.append(t)
    for source, url in FLUX_NATIONAUX:
        for t in titres(source, url):
            if t["titre"] not in vus:
                vus.add(t["titre"]); nat.append(t)
    return loc[:45], nat[:35]


def meteo():
    try:
        d = json.loads(lire("https://api.open-meteo.com/v1/forecast?latitude=45.5826&longitude=5.4148&daily=weathercode,"
                            "temperature_2m_max,temperature_2m_min,precipitation_sum&timezone=Europe%2FParis&forecast_days=2"))
        j = d["daily"]
        f = lambda i: "%s, de %d à %d °C%s" % (METEO_CODES.get(int(j["weathercode"][i]), "temps variable"),
                                             round(j["temperature_2m_min"][i]), round(j["temperature_2m_max"][i]),
                                             ", %.0f mm de pluie" % j["precipitation_sum"][i] if j["precipitation_sum"][i] >= 1 else "")
        return "aujourd'hui : %s ; demain : %s" % (f(0), f(1))
    except Exception as e:
        print("météo indisponible :", e, file=sys.stderr)
        return ""


TONS = ["chaleureux", "drole", "curieux", "sobre"]
_TXT = {"type": "string"}
SCHEMA = {
    "type": "object",
    "properties": {
        "fils": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "sujet": _TXT,
                    "noeuds": {
                        "type": "array",
                        "items": {
                            "type": "object",
                            "properties": {
                                "dit": _TXT,
                                # réponse du joueur et rebonds du client (v6.12) : ok si le ton lui plaît, ko sinon
                                "rep": {"type": "object",
                                        "properties": {t: {"type": "object",
                                                           "properties": {"t": _TXT, "ok": _TXT, "ko": _TXT},
                                                           "required": ["t", "ok", "ko"], "additionalProperties": False}
                                                       for t in TONS},
                                        "required": TONS, "additionalProperties": False},
                                "silence": {"type": "object", "properties": {"ok": _TXT, "ko": _TXT},
                                            "required": ["ok", "ko"], "additionalProperties": False},
                            },
                            "required": ["dit", "rep", "silence"], "additionalProperties": False,
                        },
                    },
                },
                "required": ["sujet", "noeuds"], "additionalProperties": False,
            },
        }
    },
    "required": ["fils"], "additionalProperties": False,
}

CONSIGNES = """Tu écris des répliques pour « Rochetoirin Simulator », un jeu de conduite sur téléphone qui se passe à
Rochetoirin et autour de Bourgoin-Jallieu (Nord-Isère). Le joueur est chauffeur de taxi ; ses clients lui parlent de
l'actualité du jour, comme dans un vrai taxi. Les répliques sont lues à voix haute par la synthèse vocale du téléphone.

Écris des fils de conversation, chacun sur UN sujet d'actualité tiré de la liste fournie (ou de la météo du jour) :
- chaque fil a exactement 3 nœuds ; dans chaque nœud, « dit » est ce que dit le client, puis « rep » donne quatre
  réponses possibles du chauffeur, une par ton : chaleureux, drole, curieux, sobre ;
- pour chaque réponse du chauffeur (« t »), écris deux REBONDS du client, dits juste avant sa réplique suivante
  (dans la même bulle) : « ok » si ce ton lui plaît (il rebondit volontiers), « ko » s'il ne lui plaît pas (plus sec,
  plus court, mais toujours sur le fond) ; et pour le silence du chauffeur (« silence » : ok, ko) ; le rebond reprend
  ce que le chauffeur vient de dire (répond à sa question, renvoie sa blague, prolonge son idée), en 6 à 20 mots ; il
  ne JUGE JAMAIS la réponse (pas de « c'est gentil », « vous avez raison », « très drôle », « bonne question ») ;
- la réplique « dit » suivante doit aller après n'importe quel rebond (le client poursuit son idée) ; aux nœuds 1 et 2,
  le rebond ne pose pas de question et s'enchaîne avec le « dit » suivant ; au nœud 3, le rebond clôt le sujet ;
- le premier « dit » amène le sujet comme un vrai passager (« Vous avez vu, pour… ? », « Il paraît que… ») ;
- reformule toujours, ne recopie jamais un titre ; reste fidèle aux faits des titres, n'invente aucun détail
  factuel (chiffres, noms, lieux) qui n'y figure pas ; le client peut en revanche donner un avis personnel, nuancé,
  parfois bougon ou amusé, jamais haineux ni insultant envers qui que ce soit ;
- tous les sujets sont permis, sauf le sport (aucun fil sur le sport) ; parle des événements graves avec tact ;
  ne nomme pas de simples particuliers (victimes, prévenus) : « un habitant », « une jeune femme » ;
- français parlé, phrases courtes (« dit » : 25 mots au plus ; chaque réponse : 14 mots au plus), sans sigle obscur,
  sans abréviation, sans émoji, sans guillemets ni parenthèses ; dates relatives (« hier », « ce week-end ») ;
- le client peut être un homme ou une femme : quand un mot s'accorde avec lui, écris {masculin|féminin}, par exemple
  « je suis {inquiet|inquiète} », y compris dans les réponses du chauffeur qui s'adressent à lui (« vous êtes
  {frileux|frileuse} ») ; le chauffeur, lui, est un homme ; n'utilise aucune autre accolade ;
- varie les sujets : environ deux tiers de sujets locaux (Nord-Isère, Isère) et un tiers nationaux, plus un fil sur
  la météo du jour ; varie aussi les caractères des clients (râleur, nostalgique, farceur, inquiet, enthousiaste) ;
- « sujet » : quelques mots qui résument l'actualité (pour le journal du jeu, non lus).
Écris entre 12 et 15 fils."""


def generer(loc, nat, met, jour):
    import anthropic                            # dans l'action seulement (pip install anthropic)
    client = anthropic.Anthropic()              # ANTHROPIC_API_KEY
    lignes = ["Date : %s." % jour, "Météo à Rochetoirin : %s." % (met or "inconnue"), "", "Actualité locale :"]
    lignes += ["- [%s] %s" % (t["date"], t["titre"]) for t in loc]
    lignes += ["", "Actualité nationale :"]
    lignes += ["- [%s] %s%s" % (t["date"], t["titre"], (" — " + t["resume"]) if t["resume"] else "") for t in nat]
    with client.beta.messages.stream(
        model=MODELE,
        max_tokens=64000,
        betas=["server-side-fallback-2026-07-01"],
        fallbacks="default",                    # repli serveur si un modèle décline (aucun sujet n'est exclu)
        system=CONSIGNES,
        output_config={"effort": "medium", "format": {"type": "json_schema", "schema": SCHEMA}},
        messages=[{"role": "user", "content": "\n".join(lignes)}],
    ) as flux:
        rep = flux.get_final_message()
    if rep.stop_reason == "refusal":
        raise RuntimeError("refus du modèle : %s" % getattr(rep, "stop_details", None))
    if rep.stop_reason == "max_tokens":
        raise RuntimeError("réponse tronquée (max_tokens)")
    texte = next(b.text for b in rep.content if b.type == "text")
    print("jetons : entrée %d, sortie %d" % (rep.usage.input_tokens, rep.usage.output_tokens), file=sys.stderr)
    return json.loads(texte)["fils"]


ACCOLADE = re.compile(r"\{[^{}]*\}")


def propre(s, maxi):
    s = re.sub(r"\s+", " ", str(s)).strip().replace("«", "").replace("»", "").replace("\"", "")
    # seules les accolades d'accord {masculin|féminin} sont permises (une autre accolade : réplique rejetée)
    if any(m.group(0).count("|") != 1 for m in ACCOLADE.finditer(s)):
        return None
    if len(s) > maxi or not s or s.count("{") != s.count("}"):
        return None
    return s


def valider(fils):
    out = []
    for f in fils:
        noeuds = []
        for n in f.get("noeuds", [])[:3]:
            dit = propre(n.get("dit", ""), 220)
            rep, ok = {}, dit is not None and not SPORT.search(dit or "")
            for t in TONS:
                r = n.get("rep", {}).get(t, {})
                v = {"t": propre(r.get("t", ""), 110), "ok": propre(r.get("ok", ""), 170), "ko": propre(r.get("ko", ""), 170)}
                ok = ok and None not in v.values()
                rep[t] = v
            si = n.get("silence", {})
            sil = {"ok": propre(si.get("ok", ""), 170), "ko": propre(si.get("ko", ""), 170)}
            if not ok or None in sil.values():
                noeuds = []
                break
            noeuds.append({"dit": dit, "rep": rep, "silence": sil})
        if len(noeuds) == 3:
            out.append({"sujet": propre(f.get("sujet", ""), 120) or "", "noeuds": noeuds})
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sortie", default="actu.json")
    ap.add_argument("--sans-ia", action="store_true")
    a = ap.parse_args()
    jour = dt.date.today().isoformat()
    loc, nat = collecte()
    met = meteo()
    print("titres : %d locaux, %d nationaux ; météo : %s" % (len(loc), len(nat), met), file=sys.stderr)
    if a.sans_ia:
        print(json.dumps({"locaux": loc[:10], "nationaux": nat[:10], "meteo": met}, ensure_ascii=False, indent=1))
        return
    if len(loc) + len(nat) < 5:
        sys.exit("trop peu de titres : paquet de la veille conservé")
    fils = valider(generer(loc, nat, met, jour))
    if len(fils) < 5:
        sys.exit("seulement %d fils valides : paquet de la veille conservé" % len(fils))
    paquet = {"version": 1, "date": jour, "genere": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
              "meteo": met, "modele": MODELE, "sujets": [f["sujet"] for f in fils], "fils": [f["noeuds"] for f in fils]}
    with open(a.sortie, "w", encoding="utf-8") as fo:
        json.dump(paquet, fo, ensure_ascii=False, indent=1)
    print("%d fils écrits dans %s" % (len(fils), a.sortie), file=sys.stderr)


if __name__ == "__main__":
    main()
