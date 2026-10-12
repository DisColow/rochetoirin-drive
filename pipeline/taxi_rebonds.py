"""Rebonds du client dans les conversations du taxi (v6.12, demande de l'utilisateur) : après notre réponse, le client
rebondit sur ce qu'on vient de lui dire, au début de sa réplique suivante (une seule bulle, une seule lecture), puis
enchaîne ; après la dernière réponse, son rebond clôt le fil. Jamais d'appréciation de notre réponse (« c'est
gentil », « très drôle ») : il reprend ce qu'on a dit, répond à la question, renvoie la balle.
Deux rebonds par réponse : « ok » si le ton plaît au client (goûts cachés de son caractère), « ko » sinon (plus sec,
plus froid, mais toujours sur le fond) ; deux rebonds pour le silence (on n'a pas répondu à temps).
Les répliques « dit » qui supposaient une réponse précise sont réécrites pour aller avec toutes.

Écrit une fois par l'API Claude (action .github/workflows/taxi_rebonds.yml, secret ANTHROPIC_API_KEY), relu, puis
versionné dans sources/taxi_fils.json, que taxi_dialogues.py reprend pour godot/data/taxi.json.
Lancer : python3 taxi_rebonds.py [--sortie sources/taxi_fils.json] [--verifier fichier.json]"""
import argparse, json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
TAXI = os.path.join(HERE, "..", "godot", "data", "taxi.json")
MODELE = "claude-opus-5-5"
TONS = ["chaleureux", "drole", "curieux", "sobre"]
VARS = {"prenom", "age", "metier", "metier_detail", "loisir", "animal", "famille", "commune", "dest", "dest_commune", "e"}

_TXT = {"type": "string"}
_REB = {"type": "object", "properties": {"ok": _TXT, "ko": _TXT}, "required": ["ok", "ko"], "additionalProperties": False}
SCHEMA = {
    "type": "object",
    "properties": {"fils": {"type": "array", "items": {
        "type": "object",
        "properties": {"noeuds": {"type": "array", "items": {
            "type": "object",
            "properties": {
                "dit": _TXT,
                "rep": {"type": "object", "properties": {t: {
                    "type": "object", "properties": {"t": _TXT, "ok": _TXT, "ko": _TXT},
                    "required": ["t", "ok", "ko"], "additionalProperties": False} for t in TONS},
                    "required": TONS, "additionalProperties": False},
                "silence": _REB,
            },
            "required": ["dit", "rep", "silence"], "additionalProperties": False}}},
        "required": ["noeuds"], "additionalProperties": False}}},
    "required": ["fils"], "additionalProperties": False,
}

CONSIGNES = """Tu écris les répliques d'un jeu de conduite sur téléphone, « Rochetoirin Simulator » (Nord-Isère). Le joueur
est chauffeur de taxi. Un client lance un sujet ; à chaque étape, le joueur choisit une réponse parmi quatre tons
(chaleureux, drole, curieux, sobre) ou se tait. Tout est lu à voix haute par la synthèse vocale du téléphone.

On te donne des fils de conversation existants : chaque fil a trois nœuds ; « dit » est la réplique du client,
« rep » les quatre réponses possibles du joueur. Le problème actuel : après la réponse du joueur, le client enchaîne
sur sa réplique suivante sans tenir compte de ce qu'on vient de lui dire. Tu ajoutes des REBONDS.

Pour chaque nœud et chaque réponse du joueur, écris deux rebonds du client :
- « ok » : la réponse lui a plu (le ton lui convient) : il rebondit volontiers, avec chaleur ou amusement ;
- « ko » : la réponse ne lui a pas plu (ce ton l'agace ou le laisse froid) : il rebondit plus sèchement, plus court,
  un peu fermé ou piqué, mais toujours sur le fond de ce qu'on a dit.
Et pour chaque nœud, deux rebonds au silence du joueur (« silence ») : « ok » pour un client que le silence ne gêne pas,
« ko » pour un client qui le prend mal.

Règles des rebonds :
1. Le rebond reprend ce que le joueur vient de dire : il répond à sa question, renvoie sa blague, prolonge son idée.
   Il ne JUGE JAMAIS la réponse : pas de « c'est gentil », « vous êtes drôle », « bonne question », « vous avez
   raison », « très drôle », « pas drôle ». Le client parle du sujet, pas de la réponse du joueur.
2. Nœuds 1 et 2 : le rebond est dit juste AVANT la réplique « dit » du nœud suivant, dans la même bulle. Il doit donc
   s'enchaîner naturellement avec elle, sans la répéter ni la contredire, et ne pas poser de question qui attendrait
   une réponse. Nœud 3 : le rebond est la dernière phrase du client sur ce sujet ; il clôt le fil (pas de question).
3. Court : 6 à 20 mots, une ou deux phrases, français parlé, sans guillemets ni parenthèses ni émoji.
4. Si une réplique « dit » des nœuds 2 ou 3 suppose une réponse précise du joueur (par exemple « Le secret, c'est… »
   qui répond à « C'est quoi votre secret ? »), réécris-la pour qu'elle aille après n'importe quelle réponse, et mets
   la réponse précise dans le rebond correspondant. Sinon, garde « dit » mot pour mot.
5. Ne change jamais les réponses du joueur : recopie-les à l'identique dans « t ».
6. Variables : garde telles quelles celles qui figurent dans le texte ({metier}, {loisir}, {dest}…) ; tu peux les
   réutiliser dans les rebonds, mais n'en invente pas d'autre. Le client peut être un homme ou une femme : pour un mot
   qui s'accorde avec lui, écris {masculin|féminin} (par exemple {content|contente}) ou {e} (petit{e}). Aucune autre
   accolade. Le joueur (chauffeur) est un homme.
7. Variété : pas deux rebonds qui commencent pareil dans un même fil ; évite les tics (« Ah », « Oh », « Bah » en
   début de chaque phrase).
Rends exactement les mêmes fils, dans le même ordre, avec trois nœuds chacun."""


def accolades_ok(s):
    for m in re.finditer(r"\{([^{}]*)\}", s):
        g = m.group(1)
        if g in VARS or g.count("|") == 1:
            continue
        return False
    return s.count("{") == s.count("}")


def propre(s, maxi):
    s = re.sub(r"\s+", " ", str(s)).strip().replace("«", "").replace("»", "").replace("\"", "")
    return s if s and len(s) <= maxi and accolades_ok(s) else None


def valider(orig, neuf, sujet):
    """Fils réécrits -> fils validés (ou None si irrécupérable). Les réponses du joueur restent celles d'origine."""
    if len(neuf) != len(orig):
        print("%s : %d fils au lieu de %d" % (sujet, len(neuf), len(orig)), file=sys.stderr)
        return None
    out = []
    for fo, fn in zip(orig, neuf):
        noeuds = fn.get("noeuds", [])
        if len(noeuds) != len(fo):
            return None
        fil = []
        for no, nn in zip(fo, noeuds):
            dit = propre(nn.get("dit", ""), 240)
            if dit is None:
                return None
            rep = {}
            for t in TONS:
                r = nn["rep"][t]
                ok, ko = propre(r.get("ok", ""), 170), propre(r.get("ko", ""), 170)
                if ok is None or ko is None:
                    print("%s : rebond refusé : %r / %r" % (sujet, r.get("ok"), r.get("ko")), file=sys.stderr)
                    return None
                rep[t] = {"t": no["rep"][t] if isinstance(no["rep"][t], str) else no["rep"][t]["t"], "ok": ok, "ko": ko}
            si = nn.get("silence", {})
            sok, sko = propre(si.get("ok", ""), 170), propre(si.get("ko", ""), 170)
            if sok is None or sko is None:
                return None
            fil.append({"dit": dit, "rep": rep, "silence": {"ok": sok, "ko": sko}})
        out.append(fil)
    return out


def ecrire(client, sujet, fils):
    entree = [{"noeuds": [{"dit": n["dit"], "rep": {t: (n["rep"][t] if isinstance(n["rep"][t], str) else n["rep"][t]["t"])
                                                       for t in TONS}} for n in f]} for f in fils]
    with client.beta.messages.stream(
        model=MODELE,
        max_tokens=48000,
        betas=["server-side-fallback-2026-07-01"],
        fallbacks="default",
        system=CONSIGNES,
        output_config={"effort": "high", "format": {"type": "json_schema", "schema": SCHEMA}},
        messages=[{"role": "user", "content": "Sujet : %s\n\n%s" % (sujet, json.dumps({"fils": entree}, ensure_ascii=False, indent=1))}],
    ) as flux:
        rep = flux.get_final_message()
    if rep.stop_reason in ("refusal", "max_tokens"):
        raise RuntimeError("%s : arrêt %s" % (sujet, rep.stop_reason))
    print("%s : entrée %d, sortie %d jetons" % (sujet, rep.usage.input_tokens, rep.usage.output_tokens), file=sys.stderr)
    return json.loads(next(b.text for b in rep.content if b.type == "text"))["fils"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sortie", default=os.path.join(HERE, "sources", "taxi_fils.json"))
    ap.add_argument("--verifier")
    a = ap.parse_args()
    fils = json.load(open(TAXI))["fils"]
    if a.verifier:
        d = json.load(open(a.verifier))
        bad = [s for s in fils if s not in d or valider(fils[s], [{"noeuds": f} for f in d[s]], s) is None]
        print("sujets invalides :", bad or "aucun")
        return
    import anthropic
    client = anthropic.Anthropic()
    out = {}
    for sujet, liste in fils.items():
        for essai in range(3):
            try:
                v = valider(liste, ecrire(client, sujet, liste), sujet)
            except Exception as e:
                print("%s : essai %d : %s" % (sujet, essai + 1, e), file=sys.stderr)
                v = None
            if v:
                out[sujet] = v
                break
        if sujet not in out:
            sys.exit("%s : échec après 3 essais" % sujet)
    os.makedirs(os.path.dirname(a.sortie), exist_ok=True)
    with open(a.sortie, "w", encoding="utf-8") as fo:
        json.dump(out, fo, ensure_ascii=False, indent=1)
    print("%d sujets, %d fils -> %s" % (len(out), sum(len(v) for v in out.values()), a.sortie), file=sys.stderr)


if __name__ == "__main__":
    main()
