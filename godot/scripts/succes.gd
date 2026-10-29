## Succès et statistiques (#133, initiative de la v6.86) : compteurs du jeu (distance, vitesse maximale, temps de jeu,
## explosions, décor cassé…) et succès débloqués d'après eux, chacun avec une prime au garage et un bandeau ; onglet
## « Succès » du menu Activités (menu_activites.gd). Sauvegarde user://succes.cfg (compteurs, succès obtenus).
## Compteurs : suivi de la voiture ici (distance, vitesse, nuit, à pied, communes, temps de jeu) ; noter() appelé par
## car.gd (explosion), casse.gd (décor, arbres), activities.gd (taxi, chasse, concurrents détruits), circulation.gd
## (voitures percutées), garage.gd (argent gagné), main.gd (éclairs) ; v6.95 : pluie, aube et journée du cycle suivies
## ici ; état déjà sauvegardé (médailles, voitures, carrière) relu par valeur().
## Essai : -- --drive-test --succes-test.
extends Node

const Voitures := preload("res://scripts/voitures.gd")
const Chargement := preload("res://scripts/chargement.gd")
const FICHIER := "user://succes.cfg"
const SUCCES := [
	{"id": "km1", "titre": "Premiers tours de roue", "texte": "Parcourir 1 km.", "stat": "km", "but": 1.0, "prime": 100},
	{"id": "km100", "titre": "Le tour du canton", "texte": "Parcourir 100 km.", "stat": "km", "but": 100.0, "prime": 500},
	{"id": "km1000", "titre": "Routier", "texte": "Parcourir 1 000 km.", "stat": "km", "but": 1000.0, "prime": 2000},
	{"id": "v200", "titre": "Plein pot", "texte": "Atteindre 200 km/h.", "stat": "vmax", "but": 200.0, "prime": 300},
	{"id": "v280", "titre": "Mur du son… presque", "texte": "Atteindre 280 km/h.", "stat": "vmax", "but": 280.0, "prime": 1000},
	{"id": "nuit10", "titre": "Couche-tard", "texte": "Rouler 10 km de nuit.", "stat": "km_nuit", "but": 10.0, "prime": 300},
	{"id": "orage", "titre": "Chasseur d'orages", "texte": "Rouler 5 km sous la pluie.", "stat": "km_pluie", "but": 5.0, "prime": 300},
	{"id": "eclairs", "titre": "Zeus", "texte": "Voir 20 éclairs.", "stat": "eclairs", "but": 20.0, "prime": 200},
	{"id": "aube", "titre": "Lève-tôt", "texte": "Rouler 2 km à l'aube (cycle jour et nuit).", "stat": "km_aube", "but": 2.0, "prime": 300},
	{"id": "journee", "titre": "Tour du cadran", "texte": "Jouer une journée entière du cycle jour et nuit.", "stat": "heures_cycle",
		"but": 24.0, "prime": 500},
	{"id": "pied1", "titre": "Promeneur", "texte": "Marcher 1 km à pied.", "stat": "km_pied", "but": 1.0, "prime": 200},
	{"id": "communes", "titre": "Explorateur", "texte": "Traverser 9 communes différentes.", "stat": "communes", "but": 9.0, "prime": 500},
	{"id": "boum1", "titre": "KA-BOOM", "texte": "Exploser contre un obstacle.", "stat": "explosions", "but": 1.0, "prime": 100},
	{"id": "boum25", "titre": "Artificier", "texte": "Exploser 25 fois.", "stat": "explosions", "but": 25.0, "prime": 600},
	{"id": "casse100", "titre": "Casseur", "texte": "Casser 100 éléments du décor.", "stat": "casse", "but": 100.0, "prime": 400},
	{"id": "arbres25", "titre": "Bûcheron", "texte": "Coucher 25 arbres.", "stat": "arbres", "but": 25.0, "prime": 300},
	{"id": "circ10", "titre": "Chauffard", "texte": "Percuter 10 voitures de la circulation.", "stat": "circulation", "but": 10.0, "prime": 300},
	{"id": "taxi1", "titre": "Taxi !", "texte": "Terminer une course de taxi.", "stat": "taxi", "but": 1.0, "prime": 100},
	{"id": "taxi50", "titre": "Chauffeur de confiance", "texte": "Terminer 50 courses de taxi.", "stat": "taxi", "but": 50.0, "prime": 1500},
	{"id": "taxi5e", "titre": "Cinq étoiles", "texte": "10 courses de taxi à 5 étoiles.", "stat": "taxi5", "but": 10.0, "prime": 600},
	{"id": "taxinuit", "titre": "Taxi de nuit", "texte": "5 courses de taxi au tarif de nuit.", "stat": "taxi_nuit", "but": 5.0, "prime": 400},
	{"id": "livreur1", "titre": "Livreur", "texte": "Finir une tournée de livraison de repas.", "stat": "tournees", "but": 1.0, "prime": 150},
	{"id": "livreur50", "titre": "Roi du bitume", "texte": "Livrer 50 repas.", "stat": "livraisons", "but": 50.0, "prime": 1000},
	{"id": "interpel1", "titre": "Force reste à la loi", "texte": "Interpeller un fuyard (activité Gendarme).", "stat": "interpellations", "but": 1.0, "prime": 150},
	{"id": "semes1", "titre": "Courant d'air", "texte": "Semer les gendarmes.", "stat": "semes", "but": 1.0, "prime": 200},
	{"id": "semes10", "titre": "Insaisissable", "texte": "Semer les gendarmes 10 fois.", "stat": "semes", "but": 10.0, "prime": 1000},
	{"id": "bus1", "titre": "Machiniste", "texte": "Terminer une ligne de bus.", "stat": "lignes_bus", "but": 1.0, "prime": 150},
	{"id": "bus100", "titre": "Ligne fidèle", "texte": "Transporter 100 voyageurs en bus.", "stat": "voyageurs", "but": 100.0, "prime": 800},
	{"id": "chasse10", "titre": "Détective", "texte": "Réussir 10 chasses au lieu.", "stat": "chasses", "but": 10.0, "prime": 600},
	{"id": "or1", "titre": "Médaillé", "texte": "Décrocher une médaille d'or.", "stat": "ors", "but": 1.0, "prime": 200},
	{"id": "or10", "titre": "Collectionneur d'or", "texte": "L'or sur 10 épreuves différentes.", "stat": "ors", "but": 10.0, "prime": 1500},
	{"id": "extreme", "titre": "Sans pitié", "texte": "L'or sur une épreuve en Extrême.", "stat": "ors_extreme", "but": 1.0, "prime": 1000},
	{"id": "detruits10", "titre": "Démolisseur", "texte": "Détruire 10 concurrents en course.", "stat": "concurrents", "but": 10.0, "prime": 600},
	{"id": "voitures3", "titre": "Garagiste", "texte": "Avoir 3 voitures au garage.", "stat": "voitures", "but": 3.0, "prime": 300},
	{"id": "voitures_tout", "titre": "Collection complète", "texte": "Avoir toutes les voitures du garage.", "stat": "voitures", "but": -1.0, "prime": 2000},
	{"id": "riche", "titre": "Riche", "texte": "Gagner 50 000 € au total.", "stat": "argent", "but": 50000.0, "prime": 1000},
	{"id": "chap1", "titre": "Le village vous salue", "texte": "Finir le chapitre 1 de la carrière.", "stat": "chapitres", "but": 1.0, "prime": 300},
	{"id": "champion", "titre": "Champion du Nord-Isère", "texte": "Finir la carrière.", "stat": "chapitres", "but": 4.0, "prime": 2000},
]
## Statistiques affichées dans l'onglet : [clé, libellé, unité]
const STATS := [["km", "Distance parcourue", "km"], ["km_nuit", "dont de nuit", "km"], ["km_pluie", "dont sous la pluie", "km"],
	["km_pied", "À pied", "km"], ["eclairs", "Éclairs vus", ""],
	["vmax", "Vitesse maximale", "km/h"], ["temps", "Temps de jeu", "temps"], ["communes", "Communes traversées", ""],
	["explosions", "Explosions", ""], ["casse", "Éléments du décor cassés", ""], ["arbres", "Arbres couchés", ""],
	["circulation", "Voitures de la circulation percutées", ""], ["taxi", "Courses de taxi", ""],
	["taxi5", "dont à 5 étoiles", ""], ["taxi_nuit", "dont au tarif de nuit", ""], ["lignes_bus", "Lignes de bus terminées", ""], ["semes", "Gendarmes semés", ""], ["livraisons", "Repas livrés", ""], ["arrestations", "Arrestations", ""], ["interpellations", "Fuyards interpellés", ""], ["voyageurs", "Voyageurs transportés en bus", ""], ["chasses", "Chasses au lieu réussies", ""], ["ors", "Épreuves en or", ""],
	["concurrents", "Concurrents détruits", ""], ["argent", "Argent gagné", "€"]]

## Défi du jour (v7.11) : un défi par jour du calendrier, tiré dans cette liste d'après la date (le même pour tous
## les joueurs ce jour-là) ; progrès = compteur du jour moins sa valeur au premier lancement du jour ; prime une fois.
const DEFIS := [
	{"stat": "livraisons", "but": 3.0, "texte": "Livrer 3 repas", "prime": 120},
	{"stat": "taxi", "but": 3.0, "texte": "Faire 3 courses de taxi", "prime": 120},
	{"stat": "lignes_bus", "but": 1.0, "texte": "Terminer une ligne de bus", "prime": 100},
	{"stat": "semes", "but": 1.0, "texte": "Semer les gendarmes", "prime": 150},
	{"stat": "km", "but": 25.0, "texte": "Rouler 25 km", "prime": 80},
	{"stat": "casse", "but": 40.0, "texte": "Casser 40 éléments du décor", "prime": 80},
	{"stat": "taxi5", "but": 1.0, "texte": "Réussir une course de taxi à 5 étoiles", "prime": 120},
	{"stat": "voyageurs", "but": 15.0, "texte": "Transporter 15 voyageurs en bus", "prime": 120},
	{"stat": "km_pied", "but": 1.0, "texte": "Marcher 1 km à pied", "prime": 60},
	{"stat": "concurrents", "but": 2.0, "texte": "Détruire 2 concurrents pendant une course", "prime": 100},
	{"stat": "km_nuit", "but": 10.0, "texte": "Rouler 10 km de nuit", "prime": 90},
	{"stat": "arbres", "but": 10.0, "texte": "Coucher 10 arbres", "prime": 70},
]

var main: Node
var stats := {}                    # compteurs (float)
var defi_jour := -1                # jour du défi en cours (jours depuis 1970, heure locale)
var defi_base := 0.0               # valeur du compteur du défi au début du jour
var defi_fait := false
var _defi_dit := false             # défi annoncé une fois après le chargement
var obtenus := {}                  # succès -> date
var vus := {}                      # communes traversées
var _change := false
var _t_sauve := 0.0
var _t_verif := 0.0
var _t_commune := 0.0
var _annonces: Array = []          # succès à annoncer (un bandeau toutes les 3,5 s)
var _t_annonce := 0.0

func _ready() -> void:
	charger()

## v7.11 : compteurs sauvegardés aussi en quittant le jeu ou quand le téléphone le met en arrière-plan (sinon les
## 10 dernières secondes étaient perdues : repas livrés, ligne terminée juste avant de quitter…).
func _notification(what: int) -> void:
	if what in [NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT,
			NOTIFICATION_EXIT_TREE] and _change:
		sauver()

func charger() -> void:
	var c := ConfigFile.new()
	if c.load(FICHIER) != OK:
		return
	stats = c.get_value("succes", "stats", {})
	obtenus = c.get_value("succes", "obtenus", {})
	vus = c.get_value("succes", "communes", {})
	defi_jour = int(c.get_value("defi", "jour", -1))
	defi_base = float(c.get_value("defi", "base", 0.0))
	defi_fait = bool(c.get_value("defi", "fait", false))

func sauver() -> void:
	var c := ConfigFile.new()
	c.set_value("succes", "stats", stats)
	c.set_value("succes", "obtenus", obtenus)
	c.set_value("succes", "communes", vus)
	c.set_value("defi", "jour", defi_jour)
	c.set_value("defi", "base", defi_base)
	c.set_value("defi", "fait", defi_fait)
	c.save(FICHIER)
	_change = false

## Remet tout à zéro (essais).
func effacer() -> void:
	stats = {}; obtenus = {}; vus = {}; _annonces = []
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FICHIER))

## Un événement du jeu : compteur augmenté de n.
func noter(cle: String, n := 1.0) -> void:
	stats[cle] = float(stats.get(cle, 0.0)) + n
	_change = true

## Valeur d'une statistique (compteurs, ou état sauvegardé ailleurs : médailles, voitures, carrière).
func valeur(cle: String) -> float:
	var g = main.get("garage") if main else null
	match cle:
		"communes":
			return float(vus.size())
		"ors", "ors_extreme":
			var n := 0
			if g:
				for k in g.medailles:
					if str(g.medailles[k]) == "or" and ((cle == "ors" and not str(k).contains(":")) or (cle == "ors_extreme" and str(k).ends_with(":2"))):
						n += 1
			return float(n)
		"voitures":
			return float(g.voitures.size()) if g else 0.0
		"chapitres":
			var ca = main.get("carriere") if main else null
			var n := 0
			if ca:
				for k in ca.CHAPITRES.size():
					if ca.fini(k):
						n += 1
			return float(n)
	return float(stats.get(cle, 0.0))

func but(s: Dictionary) -> float:
	return float(Voitures.CATALOGUE.size()) if float(s.but) < 0.0 else float(s.but)

func obtenu(id: String) -> bool:
	return obtenus.has(id)

# ================================================================ suivi
func _physics_process(dt: float) -> void:
	if main == null or get_tree().paused:
		return
	var car: VehicleBody3D = main.get("car")
	if car == null:
		return
	var pied = main.get("pied")
	var a_pied: bool = pied != null and bool(pied.get("actif"))
	stats["temps"] = float(stats.get("temps", 0.0)) + dt
	_change = true
	var cycle := int(main.get("heure_choix")) == 4
	if cycle:
		noter("heures_cycle", dt * float(main.get("heure_vitesse")))
	if a_pied:
		var pv = pied.get("velocity")
		if pv is Vector3:
			noter("km_pied", Vector2(pv.x, pv.z).length() * dt / 1000.0)
	elif not car.carried and not car.blown:
		var v := car.linear_velocity.length()
		if v > 0.5 and v < 120.0:                      # au-delà : téléportation ou rebond, pas de la conduite
			noter("km", v * dt / 1000.0)
			if int(main.get("time_of_day")) == 3:
				noter("km_nuit", v * dt / 1000.0)
			if float(main.get("pluie")) > 0.5:
				noter("km_pluie", v * dt / 1000.0)
			if cycle and float(main.get("heure")) >= 5.0 and float(main.get("heure")) < 7.5:
				noter("km_aube", v * dt / 1000.0)
			if v * 3.6 > float(stats.get("vmax", 0.0)):
				stats["vmax"] = v * 3.6

func _process(dt: float) -> void:
	_t_commune -= dt
	var hud = main.get_node_or_null("HUD") if main else null
	if _t_commune <= 0.0 and hud and hud.get("names") and main.get("car"):
		_t_commune = 2.0
		var com: String = hud.names.commune_at(main.car.global_position)
		if com != "" and not vus.has(com):
			vus[com] = true
			_change = true
	_t_verif -= dt
	if _t_verif <= 0.0:
		_t_verif = 1.0
		verifier()
		if not _defi_dit and Chargement.fini and hud and defi_jour == jour():
			_defi_dit = true
			if not defi_fait:
				var d := defi()
				hud.toast("Défi du jour : %s  ·  +%d €\n(Activités > Succès)" % [d.texte, int(d.prime)], 5.0)
	_t_annonce -= dt
	if _t_annonce <= 0.0 and not _annonces.is_empty() and not get_tree().paused:
		_t_annonce = 3.5
		_annoncer(_annonces.pop_front())
	_t_sauve -= dt
	if _t_sauve <= 0.0 and _change:
		_t_sauve = 10.0
		sauver()

## Jour du calendrier (heure locale) : jours depuis le 1er janvier 1970.
static func jour() -> int:
	var tz: Dictionary = Time.get_time_zone_from_system()
	return int(floor((Time.get_unix_time_from_system() + float(tz.get("bias", 0)) * 60.0) / 86400.0))

## Défi du jour j : mélange fixe de la liste (deux jours de suite n'ont pas le même défi).
static func defi(j := -1) -> Dictionary:
	if j < 0:
		j = jour()
	return DEFIS[(j * 5 + 3) % DEFIS.size()]

## Progrès du défi en cours (0 si un autre jour a commencé : il est remis en place par verifier).
func defi_progres() -> float:
	var d := defi()
	return clampf(valeur(String(d.stat)) - defi_base, 0.0, float(d.but)) if defi_jour == jour() else 0.0

func _verifier_defi() -> void:
	var j := jour()
	var d := defi(j)
	if j != defi_jour:                       # nouveau jour : nouveau défi, compté à partir de maintenant
		defi_jour = j
		defi_base = valeur(String(d.stat))
		defi_fait = false
		_change = true
		return
	if defi_fait or valeur(String(d.stat)) - defi_base < float(d.but):
		return
	defi_fait = true
	_change = true
	var g = main.get("garage") if main else null
	if g:
		g.gagner(float(d.prime))
	_annonces.append({"titre": "Défi du jour réussi", "texte": String(d.texte), "prime": d.prime})
	print("[succès] défi du jour : ", d.texte)

## Succès atteints : notés, prime au garage, annonce.
func verifier() -> void:
	_verifier_defi()
	for s in SUCCES:
		if obtenus.has(s.id) or valeur(String(s.stat)) < but(s):
			continue
		obtenus[s.id] = Time.get_date_string_from_system()
		_change = true
		var g = main.get("garage") if main else null
		if g:
			g.gagner(float(s.prime))
		_annonces.append(s)
		print("[succès] ", s.titre)
	if _change and not _annonces.is_empty():
		sauver()

func _annoncer(s: Dictionary) -> void:
	var hud = main.get_node_or_null("HUD") if main else null
	if hud:
		hud.toast("★ Succès : %s\n%s  ·  +%d €" % [s.titre, s.texte, int(s.prime)], 4.0)
	var act = main.get("activities") if main else null
	if act and act.get("_bip"):
		act._bip.play()

## Texte d'une statistique pour l'onglet.
func texte_stat(cle: String, unite: String) -> String:
	var v := valeur(cle)
	match unite:
		"km":
			return ("%.1f km" % v).replace(".", ",")
		"km/h":
			return "%d km/h" % int(v)
		"temps":
			var m := int(v / 60.0)
			return "%d h %02d min" % [m / 60, m % 60]
		"€":
			return ("%d €" % int(v))
	return str(int(v))
