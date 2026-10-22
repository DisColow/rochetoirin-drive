## Progression réelle du démarrage (v6.14, demande de l'utilisateur : l'écran restait figé à 3-4 %). main.gd construit
## le monde par étapes nommées (« Routes… », « Bâtiments… ») avec une image dessinée entre chaque ; le voile de
## démarrage (voile_demarrage.gd) affiche l'étape et une barre qui avance selon la durée de chaque étape, mesurée au
## lancement précédent sur cet appareil (user://chargement.cfg), sinon selon des durées par défaut.
extends RefCounted

const FICHIER := "user://chargement.cfg"
const DEPART := 0.04              # part de la barre prise par la lecture de la scène (écran de boot.gd)
# durées par défaut (s), relevées sur PC ; remplacées par celles de l'appareil dès le deuxième lancement
const DEFAUT := {
	"Ciel et lumière": 0.3, "Relief": 1.0, "Horizon": 0.5, "Routes": 2.5, "Bâtiments": 3.0,
	"Clôtures et haies": 1.5, "Rivières et étangs": 0.3, "Arbres": 2.0, "Champs et herbe": 1.0,
	"Poteaux et lampadaires": 0.6, "Voitures garées et mobilier": 0.8, "Commerces": 0.8, "Terrains de sport": 0.4,
	"Animaux": 0.5, "Autoroutes": 0.8, "Circulation": 0.4, "Voiture, sons et radio": 1.0, "Interface": 0.8,
	"Préparation des effets": 2.0,
}

static var etape := ""             # étape en cours (affichée : « Routes… »)
static var debut := 0.0            # part de la barre au début de l'étape en cours (0 … 1)
static var fin := 0.0              # part de la barre à la fin de l'étape en cours
static var duree := 1.0            # durée attendue de l'étape en cours (s)
static var t0 := 0                 # début de l'étape en cours (ms)
static var fini := false
static var _durees := {}           # attendues (appareil ou défaut)
static var _mesures := {}          # mesurées pendant ce lancement
static var _total := 0.0
static var _fait := 0.0

static func commencer() -> void:
	fini = false
	_mesures = {}
	_durees = DEFAUT.duplicate()
	var cfg := ConfigFile.new()
	if cfg.load(FICHIER) == OK:
		for k in _durees:
			_durees[k] = clampf(float(cfg.get_value("durees", k, _durees[k])), 0.05, 120.0)
	_total = 0.0
	for k in _durees:
		_total += float(_durees[k])
	_fait = 0.0
	etape = ""
	debut = DEPART
	fin = DEPART

## Passe à l'étape suivante (la précédente est finie et chronométrée).
static func etape_suivante(nom: String) -> void:
	_clore()
	etape = nom
	_sous = -1.0
	duree = float(_durees.get(nom, 1.0))
	debut = DEPART + (1.0 - DEPART) * _fait / _total
	fin = DEPART + (1.0 - DEPART) * minf(_fait + duree, _total) / _total
	t0 = Time.get_ticks_msec()

static func _clore() -> void:
	if etape == "":
		return
	_mesures[etape] = (Time.get_ticks_msec() - t0) / 1000.0
	_fait += float(_durees.get(etape, 1.0))

## Avancement connu à l'intérieur de l'étape en cours (0 … 1) : la barre s'y cale (pour une étape découpée en morceaux).
static var _sous := -1.0
static func sous_progres(k: float) -> void:
	_sous = clampf(k, 0.0, 1.0)

## Fin du démarrage : durées de cet appareil gardées pour le prochain lancement.
static func terminer() -> void:
	_clore()
	etape = ""
	fini = true
	var cfg := ConfigFile.new()
	for k in _mesures:
		cfg.set_value("durees", k, _mesures[k])
	cfg.save(FICHIER)
	print("[chargement] durées (s) : ", _mesures)

## Part de la barre à afficher : la barre avance dans l'étape en cours au rythme de sa durée attendue, sans dépasser
## 95 % de l'étape (elle n'atteint la fin de l'étape que lorsque celle-ci est vraiment finie).
static func progres() -> float:
	if fini:
		return 1.0
	if etape == "":
		return debut
	var k := clampf((Time.get_ticks_msec() - t0) / 1000.0 / maxf(duree, 0.05), 0.0, 0.95)
	if _sous >= 0.0:
		k = maxf(k * 0.5, _sous * 0.9)      # avancement réel de l'étape (90 % : le reste après la lecture)
	return lerpf(debut, fin, k)
