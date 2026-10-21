## Voix du téléphone (v6.8) : synthèse vocale du système (DisplayServer.tts_*, moteur TTS d'Android, SAPI sous
## Windows, speech-dispatcher sous Linux) pour les répliques du taxi. Aucun fichier son : le texte est lu tel quel.
## - Voix françaises seulement ; voix « locales » préférées (les voix « réseau » échouent hors connexion).
## - Sexe de la voix : Android ne le donne pas -> table des voix connues (Google, Samsung, Windows) et mots du nom ;
##   à défaut, la hauteur fait la différence (plus grave pour un homme, plus aiguë pour une femme).
## - Choix forcé par le joueur dans ⚙ > Son (« Voix des femmes », « Voix des hommes »), mémorisé dans reglages.cfg.
## La fin de chaque réplique est suivie par taxi_talk.gd (rappel du système, état « parle », délai de secours).
extends RefCounted

# voix connues : code (dans le nom ou l'identifiant, en minuscules) -> sexe
const CONNUES := {
	"-fra-": "f", "-frb-": "m", "-frc-": "f", "-frd-": "m", "-fre-": "f", "-vlf-": "f",
	"smtf": "f", "smtm": "m", "hortense": "f", "julie": "f", "denise": "f", "eloise": "f", "paul": "m",
	"henri": "m", "claude": "m", "thomas": "m", "amelie": "f", "audrey": "f", "aurelie": "f", "nicolas": "m",
}

static var _voix: Array = []
static var _essai_ms := -99999

## Voix françaises du téléphone : [{id, nom, sexe ("f", "m" ou ""), locale}]. Le moteur d'Android démarre après le
## jeu : tant que la liste est vide, on la redemande (au plus toutes les 2 s).
static func voix() -> Array:
	if OS.get_cmdline_user_args().has("--sans-voix"):
		return _voix               # essais sous Linux : speech-dispatcher fige parfois le jeu en pleine partie (v6.74)
	if _voix.is_empty() and Time.get_ticks_msec() - _essai_ms > 2000:
		_essai_ms = Time.get_ticks_msec()
		if not DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
			return _voix
		var l := []
		for v in DisplayServer.tts_get_voices():
			var lang := str(v.get("language", "")).to_lower()
			if not lang.begins_with("fr"):
				continue
			var id := str(v.get("id", ""))
			var nom := str(v.get("name", id))
			var cle := (nom + " " + id).to_lower()
			l.append({"id": id, "nom": nom, "sexe": sexe(cle), "locale": not cle.contains("network"),
				"france": lang.contains("fr_fr") or lang.contains("fr-fr") or lang == "fr"})
		# France d'abord, puis voix locales
		l.sort_custom(func(a, b): return _cle_tri(a) < _cle_tri(b))
		_voix = l
		if not l.is_empty():
			print("[voix] %d voix françaises : " % l.size(), ", ".join(l.slice(0, 24).map(func(x): return "%s (%s)" % [x.nom, x.sexe if x.sexe != "" else "?"])))
	return _voix

static func _cle_tri(x: Dictionary) -> String:
	return ("0" if x.france else "1") + ("0" if x.locale else "1") + str(x.nom)

static func dispo() -> bool:
	return not voix().is_empty()

static func sexe(cle: String) -> String:
	if cle.contains("female") or cle.contains("femme"):
		return "f"
	if cle.contains("male") or cle.contains("homme"):
		return "m"
	for k in CONNUES:
		if cle.contains(k):
			return CONNUES[k]
	return ""

## Voix forcée par le joueur pour un sexe ("" = automatique).
static func reglage(s: String) -> String:
	var cfg := ConfigFile.new()
	cfg.load("user://reglages.cfg")
	return str(cfg.get_value("audio", "voix_" + s, ""))

static func regler(s: String, id: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load("user://reglages.cfg")
	cfg.set_value("audio", "voix_" + s, id)
	cfg.save("user://reglages.cfg")

## Voix d'une personne : {id, hauteur, debit}. graine : nombre propre à la personne (deux clients du même sexe ne
## parlent pas pareil : autre voix s'il y en a plusieurs, sinon hauteur et débit un peu différents).
static func choisir(s: String, graine: int) -> Dictionary:
	var l := voix()
	if l.is_empty():
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = graine
	var var_h := rng.randf_range(-0.06, 0.06)
	var debit := rng.randf_range(0.97, 1.08)
	var force := reglage(s)
	var v: Dictionary = {}
	if force != "":
		for x in l:
			if x.id == force:
				v = x
	if v.is_empty():
		var bons := l.filter(func(x): return x.sexe == s and x.locale)
		if bons.is_empty():
			bons = l.filter(func(x): return x.sexe == s)
		if not bons.is_empty():
			v = bons[graine % bons.size()]
	if v.is_empty():
		var locales := l.filter(func(x): return x.locale)
		v = (locales if not locales.is_empty() else l)[0]
	# hauteur : voix du bon sexe -> presque naturelle ; sinon on la décale nettement
	var h := 1.0
	if v.sexe != s:
		if v.sexe == "":
			h = 1.18 if s == "f" else 0.82
		else:
			h = 1.32 if s == "f" else 0.72
	return {"id": v.id, "hauteur": clampf(h + var_h, 0.5, 1.8), "debit": debit}

## Durée estimée (s) d'une réplique lue (≈ 13 caractères par seconde en français).
static func duree(t: String, debit: float) -> float:
	return t.length() / (13.0 * maxf(debit, 0.5)) + 0.3

## Texte nettoyé pour la lecture (guillemets et signes que certains moteurs prononcent).
static func propre(t: String) -> String:
	for c in ["«", "»", "*", "_", "\"", "(", ")"]:
		t = t.replace(c, " ")
	return t.replace("…", ".").strip_edges()

## Lit une phrase (sans interrompre la précédente : elle se termine d'abord). Renvoie l'identifiant de la réplique.
static var _n := 0
static func dire(t: String, choix: Dictionary, volume: float, couper := false) -> int:
	_n += 1
	DisplayServer.tts_speak(propre(t), str(choix.id), clampi(int(volume * 100.0), 0, 100),
		float(choix.hauteur), float(choix.debit), _n, couper)
	return _n
