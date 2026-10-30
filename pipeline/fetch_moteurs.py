"""Sons de moteur propres à chaque voiture du garage (#153) : enregistrements libres de Wikimedia Commons
(CC BY / CC BY-SA, crédités dans ⚙ > Crédits) -> data/sons/moteurs/<clé>.wav (mono 44,1 kHz, non versionnés),
retravaillés par build_moteurs.py. Lancer depuis pipeline/.
CANDIDATS : clé -> (titre du fichier sur Commons, cylindres, description courte)."""
import json, os, subprocess, sys, time, urllib.parse, urllib.request

OUT = "data/sons/moteurs"
UA = {"User-Agent": "RochetoirinSimulator/1.0 (https://github.com/DisColow/rochetoirin-drive ; sons de moteur) python-urllib"}

CANDIDATS = {
    "2cv6": ("File:WWS CITROEN2CV6Charlestonengine.ogg", 2, "Citroën 2CV6 Charleston, bicylindre à plat"),
    "r5t2": ("File:Renault 5 Turbo 2 - engine and exhaust sound (YouTube 9yqNZjwGvCo).opus", 4, "Renault 5 Turbo 2"),
    "twingo": ("File:Renault Twingo (2002) - engine and exhaust sound (YouTube 1iwuiuqE2QY).opus", 4, "Renault Twingo (2002)"),
    "106r": ("File:Peugeot 106 Rallye - engine and exhaust sound (YouTube Z2iFd9mSyhE).opus", 4, "Peugeot 106 Rallye"),
    "cliors": ("File:Renault Clio IV RS Trophy - engine and exhaust sound (YouTube hNI zoxQ0qo).opus", 4, "Renault Clio IV RS Trophy"),
    "meganers": ("File:Renault Mégane RS - engine and exhaust sound (YouTube TplQIptv-ME).opus", 4, "Renault Mégane RS"),
    "rcz": ("File:Peugeot RCZ R - engine and exhaust sound (YouTube f2Y9uwyp8jw).opus", 4, "Peugeot RCZ R"),
    "toledo": ("File:Seat Toledo - engine and exhaust sound (YouTube zxgRsS4UvfM).opus", 4, "Seat Toledo"),
    "laguna": ("File:Renault Laguna II V6 - engine and exhaust sound (YouTube F9eJ7lo4Zno).opus", 6, "Renault Laguna II V6"),
    "omega": ("File:Opel Omega B 3.0 V6 - engine and exhaust sound (YouTube pK-1MhnSEuk).opus", 6, "Opel Omega B 3.0 V6"),
    "gt3_992": ("File:Porsche 911 GT3 (992) with Fi Exhaust - engine and exhaust sound (YouTube -ZK8A1PT-4k).opus", 6,
                "Porsche 911 GT3 (992)"),
    "gt3rs_991": ("File:Porsche 911 GT3 RS (991) - engine and exhaust sound (YouTube otznJ2rBoks).opus", 6,
                  "Porsche 911 GT3 RS (991)"),
    "mustang": ("File:Ford Mustang GT (S550) - engine and exhaust sound (YouTube 2ceiDjGgpI8).opus", 8, "Ford Mustang GT (S550)"),
    "bronco": ("File:Ford Bronco (1979) - engine and exhaust sound (YouTube h49p3ivoHYI).opus", 8, "Ford Bronco (1979)"),
    # BigSoundBank (Joseph Sardin, CC0) : « titre » = bsb:<numéro>
    "ess1l": ("bsb:966", 4, "moteur essence 1 litre (BigSoundBank)"),
    "dsl29": ("bsb:967", 4, "moteur diesel 2,9 litres (BigSoundBank)"),
    "man_sg220": ("File:WWS CityBusMANSG220engine.ogg", 6, "autobus MAN SG 220, diesel"),
}


def api(params):
    u = "https://commons.wikimedia.org/w/api.php?" + urllib.parse.urlencode(dict(params, format="json"))
    for k in range(6):
        try:
            return json.load(urllib.request.urlopen(urllib.request.Request(u, headers=UA), timeout=60))
        except Exception as e:
            print("nouvel essai", e); time.sleep(20 * 2 ** k)       # 429 : Commons demande de ralentir
    raise RuntimeError("Commons ne répond pas")


def url_fichier(titre):
    """Adresse du fichier sur upload.wikimedia.org (chemin d'après le MD5 du nom) : pas d'appel à l'API."""
    import hashlib
    nom = titre[5:].replace(" ", "_")
    h = hashlib.md5(nom.encode("utf-8")).hexdigest()
    return "https://upload.wikimedia.org/wikipedia/commons/%s/%s/%s" % (h[0], h[:2], urllib.parse.quote(nom))


def lire_url(url):
    """Téléchargement poli : un refus (429) attend tout ce que demande Retry-After (souvent 10 min : l'adresse de
    sortie du conteneur est partagée et limitée par Wikimedia)."""
    import urllib.error
    for k in range(30):
        try:
            return urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=300).read()
        except urllib.error.HTTPError as e:
            if e.code == 404:
                raise
            att = int(e.headers.get("Retry-After") or 60 * 2 ** min(k, 3)) + 5
            print("refus %d, nouvel essai dans %d s" % (e.code, att), flush=True); time.sleep(att)
        except Exception as e:
            print("nouvel essai", e, flush=True); time.sleep(60)
    raise RuntimeError("téléchargement impossible : " + url)


def info(titre):
    """URL, licence et auteur d'un fichier de Commons."""
    d = api({"action": "query", "prop": "imageinfo", "iiprop": "url|extmetadata", "titles": titre})
    p = next(iter(d["query"]["pages"].values()))
    ii = p["imageinfo"][0]; m = ii.get("extmetadata", {})
    import re
    auteur = re.sub("<[^>]+>", "", m.get("Artist", {}).get("value", "?")).strip()
    return ii["url"], m.get("LicenseShortName", {}).get("value", "?"), auteur


def main(cles):
    os.makedirs(OUT, exist_ok=True)
    cles = cles or list(CANDIDATS)
    for cle in cles:
        titre, cyl, desc = CANDIDATS[cle][:3]
        dst = "%s/%s.wav" % (OUT, cle)
        if os.path.exists(dst) and os.path.getsize(dst) > 10000:
            continue
        brut = "%s/%s.brut" % (OUT, cle)
        if titre.startswith("bsb:"):
            from fetch_sons import bsb
            brut = bsb(int(titre[4:]))
            subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", brut, "-ac", "1", "-ar", "44100", dst], check=True)
            print("%-10s %s" % (cle, desc), flush=True)
            continue
        open(brut, "wb").write(lire_url(url_fichier(titre)))
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", brut, "-ac", "1", "-ar", "44100", dst], check=True)
        os.remove(brut)
        print("%-10s %s" % (cle, desc), flush=True)
        time.sleep(30.0)                             # entre deux fichiers : rester discret
    # licences et auteurs (crédits) : une seule requête à l'API pour tous les fichiers
    old = json.load(open(OUT + "/credits.json")) if os.path.exists(OUT + "/credits.json") else {}
    for c in cles:
        if c not in old and CANDIDATS[c][0].startswith("bsb:"):
            old[c] = {"titre": "BigSoundBank n° " + CANDIDATS[c][0][4:], "licence": "CC0", "auteur": "Joseph SARDIN - BigSoundBank.com",
                      "cylindres": CANDIDATS[c][1], "desc": CANDIDATS[c][2]}
    manque = [c for c in cles if c not in old]
    if manque:
        import re
        d = api({"action": "query", "prop": "imageinfo", "iiprop": "extmetadata",
                 "titles": "|".join(CANDIDATS[c][0] for c in manque)})
        par_titre = {p["title"]: p for p in d["query"]["pages"].values()}
        norm = {n["from"]: n["to"] for n in d["query"].get("normalized", [])}
        for c in manque:
            p = par_titre.get(norm.get(CANDIDATS[c][0], CANDIDATS[c][0]), {})
            m = (p.get("imageinfo") or [{}])[0].get("extmetadata", {})
            old[c] = {"titre": CANDIDATS[c][0][5:], "licence": m.get("LicenseShortName", {}).get("value", "?"),
                      "auteur": re.sub("<[^>]+>", "", m.get("Artist", {}).get("value", "?")).strip(),
                      "cylindres": CANDIDATS[c][1], "desc": CANDIDATS[c][2]}
            print("%-10s %-12s %s" % (c, old[c]["licence"], old[c]["auteur"]))
    json.dump(old, open(OUT + "/credits.json", "w"), indent=1, ensure_ascii=False)


if __name__ == "__main__":
    main(sys.argv[1:])
