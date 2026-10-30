## Activité « Gendarme » (v7.13, #150 ; service en missions enchaînées v7.22, #161) : Activités > Métiers > « Prendre
## le service de gendarme » (activities._gendarme_start, mode « gendarme »). Le joueur prend la voiture de la
## Gendarmerette (voitures.gd « gendarme », habillée par gendarme.habiller : livrée, gyrophares, sirène), posée sur la
## route la plus proche ; à chaque mission, un ou plusieurs fuyards (gendarme.gd en mode « fuite », voitures ordinaires
## du garage) démarrent DEPART m devant et filent loin du joueur, plutôt devant lui.
## - Chaque choc contre un fuyard l'abîme (vitesse de rapprochement × PAR_MS %, choc_max % au plus) ; à 100 % il
##   s'arrête : interpellé. Détruit (KA-BOOM) : interpellé aussi, sa part de prime réduite de moitié. Coincé (arrêté à
##   moins de COINCE_D m de la Gendarmerette pendant COINCE_T s) : interpellé.
## - Mission réussie quand tous sont interpellés : médaille selon le temps (or : moitié du chrono, argent : trois
##   quarts, bronze : après), prime × PART_MEDAILLE ; la suivante (MISSIONS, de plus en plus dure) démarre après
##   PAUSE s. Échec (un fuyard à plus de PERDU m pendant PERDU_T s, ou chrono écoulé) : fin du service et bilan.
## Essais : --drive-test --gendarme-joueur-test (une mission), --gendarme-missions-test (enchaînement).
extends Node

const Gendarme := preload("res://scripts/gendarme.gd")
const Relief := preload("res://scripts/relief.gd")
const DEPART := 60.0
const PAR_MS := 6.0                 # % de dégâts par m/s de rapprochement
const CHOC_MIN := 3.0               # m/s
const ELAN := 20.0                  # m/s : vitesse des fuyards au départ (ils démarrent lancés)
const PERDU := 450.0
const PERDU_T := 12.0
const COINCE_D := 7.0                # fuyard immobilisé contre la Gendarmerette (m)…
const COINCE_T := 3.0                # … pendant ce temps (s) : interpellé
const PAUSE := 3.0                   # s entre deux missions (bilan de la mission)
const PART_MEDAILLE := {"or": 1.0, "argent": 0.6, "bronze": 0.35}
# #161 : missions de plus en plus dures : [modèles des fuyards, vitesse max (km/h), chrono (s), dégâts max par choc (%),
# prime de base (€)] ; au-delà de la dernière, elle revient en plus court et mieux payée
const MISSIONS := [
	[["twingo"], 100.0, 150.0, 40.0, 120.0],
	[["clio"], 110.0, 135.0, 40.0, 150.0],
	[["r5", "p106"], 110.0, 150.0, 35.0, 220.0],
	[["laguna"], 125.0, 120.0, 30.0, 220.0],
	[["p206", "p306"], 125.0, 140.0, 30.0, 300.0],
	[["gt3"], 140.0, 110.0, 25.0, 350.0],
	[["p306", "p206", "clio"], 130.0, 160.0, 25.0, 450.0],
]
static var enchainer := true         # essai --gendarme-joueur-test : une seule mission (comme avant #161)

var main: Node
var actif := false
var mission := 0                     # numéro de la mission en cours (1, 2…)
var fuyards: Array = []              # [{g: gendarme.gd, degats, coince_t, pris, detruit}]
var fuyard                           # premier fuyard pas encore interpellé (essais)
var degats := 0.0                    # ses dégâts
var t := 0.0                         # temps de la mission
var duree := 150.0
var interpelle := false              # dernière mission réussie
var reussies := 0
var gains := 0.0
var medailles := {"or": 0, "argent": 0, "bronze": 0}
var _p := {}                         # paramètres de la mission en cours
var _pause_t := 0.0                  # > 0 : bilan entre deux missions
var _perdu_t := 0.0
var _coince_t := 0.0
var _choc_cd := 0.0
var _gyro: Array = []
var _lueur: OmniLight3D
var _sirene: AudioStreamPlayer3D
var depart_dir := Vector3.FORWARD                 # sens de départ (essai : route jusqu'au fuyard)

func _act():
	return main.activities

## Paramètres de la mission n (1, 2…).
static func parametres(n: int) -> Dictionary:
	var k := n - 1
	var tour := k / MISSIONS.size()                 # au-delà de la dernière : plus court, mieux payé
	var m: Array = MISSIONS[k % MISSIONS.size()]
	return {"modeles": m[0], "vmax": float(m[1]) / 3.6, "duree": float(m[2]) * pow(0.9, tour),
		"choc_max": float(m[3]), "base": float(m[4]) * (1.0 + 0.5 * tour)}

## Médaille d'une mission réussie en t s sur un chrono de d s.
static func medaille(t_: float, d: float) -> String:
	return "or" if t_ <= d * 0.5 else ("argent" if t_ <= d * 0.75 else "bronze")

func demarrer() -> bool:
	var car: VehicleBody3D = main.car
	var circ = main.get("circulation")
	if circ == null:
		return false
	var vp: Array = circ.voie_proche(car.global_position)     # route la plus proche
	var p0: Vector3 = vp[0]
	var d0: Vector3 = vp[1]
	if d0 == Vector3.ZERO:
		return false
	var r := _route_devant(p0, car.global_transform.basis.z)
	if r.is_empty():
		return false
	car.construire("gendarme")
	# prise de service : la Gendarmerette sur la route, dans le sens du fuyard (pas dans un parking ou contre un mur)
	if d0.dot(depart_dir) < 0.0:
		d0 = -d0
	var y := Relief.hauteur(p0)
	car.place(Vector3(p0.x, (p0.y if is_nan(y) else maxf(p0.y, y)) + 0.4, p0.z), rad_to_deg(atan2(d0.x, -d0.z)))
	car.hold(0.3)
	var h := Gendarme.habiller(car, Color(0.1, 0.17, 0.42))
	_gyro = h.gyro; _lueur = h.lueur; _sirene = h.sirene
	_sirene.volume_db = -8.0                      # la sienne : moins forte que celles des autres
	if _sirene.stream:
		_sirene.play()
	car.nitro_niveau = 0
	mission = 0; reussies = 0; gains = 0.0
	medailles = {"or": 0, "argent": 0, "bronze": 0}
	actif = true
	_mission_suivante(r)
	return true

## Route devant p dans le sens f (sinon dans une autre direction : voiture en travers, sur un parking…) : [point, dir].
func _route_devant(p: Vector3, f: Vector3) -> Array:
	var circ = main.get("circulation")
	for k: int in [0, 1, -1, 2, -2, 3, -3, 4]:          # devant d'abord
		depart_dir = f.rotated(Vector3.UP, k * PI / 4.0)
		var r: Array = circ.devant(p, depart_dir, DEPART, -0.7)     # tous les virages, pas de demi-tour
		if not r.is_empty():
			return r
	return []

## Mission suivante : ses fuyards partent DEPART m devant (r : [point, direction] de circulation.devant), à la queue
## leu leu (un toutes les 14 m) quand ils sont plusieurs.
func _mission_suivante(r: Array) -> void:
	for f in fuyards:
		if is_instance_valid(f.g):
			f.g.queue_free()
	fuyards.clear()
	mission += 1
	_p = parametres(mission)
	duree = _p.duree
	var circ = main.get("circulation")
	var q: Vector3 = r[0]
	var dir: Vector2 = r[1]
	for i in (_p.modeles as Array).size():
		var g := Gendarme.new()
		g.main = main
		g.livree = false
		g.modele = String(_p.modeles[i])
		g.mode = "fuite"
		g.vmax_fuite = _p.vmax
		add_child(g)
		var qi := q
		if i > 0:                                    # les suivants derrière le premier, sur la même route
			qi = q - Vector3(dir.x, 0.0, dir.y) * 14.0 * i
		g.poser(Vector2(qi.x, qi.z), Vector2(qi.x, qi.z) + dir * 10.0)
		var tr: PackedVector2Array = circ.trajet(qi, Vector3(dir.x, 0.0, dir.y), 350.0, -0.7, 0.5, 4.0, Gendarme.ISSUE)
		if tr.size() >= 10:
			g._prendre(tr)
			g._replan_t = 10.0
		g._degeler()                              # lancé à l'allure de son trajet…
		if g.voiture.linear_velocity.length() > ELAN:
			g.voiture.linear_velocity = g.voiture.linear_velocity.normalized() * ELAN     # … ELAN m/s au plus
		fuyards.append({"g": g, "degats": 0.0, "coince_t": 0.0, "pris": false, "detruit": false})
	fuyard = fuyards[0].g
	degats = 0.0; t = 0.0; interpelle = false; _perdu_t = 0.0; _coince_t = 0.0; _pause_t = 0.0

func arreter() -> void:
	if not actif:
		return
	actif = false
	for f in fuyards:
		if is_instance_valid(f.g):
			f.g.queue_free()
	fuyards.clear()
	fuyard = null
	var g = main.get("garage")
	if g:
		g.vue_changee.emit(g.vue)                 # on reprend sa voiture (comme après la ligne de bus)
	else:
		main.car.construire(preload("res://scripts/voitures.gd").actuelle())
	main.car.global_position += Vector3.UP * 0.4

func process(dt: float) -> void:
	if not actif:
		return
	var act = _act()
	var car: VehicleBody3D = main.car
	Gendarme.clignoter(_gyro, _lueur, t + _pause_t, car.lights_on)
	if _pause_t > 0.0:                               # bilan de la mission réussie, puis la suivante
		_pause_t -= dt
		if _pause_t <= 0.0:
			var r := _route_devant(car.global_position, car.global_transform.basis.z)
			if r.is_empty():
				_fin_service("Plus de route pour la mission suivante.")
				return
			_mission_suivante(r)
			main.get_node("HUD").toast("Mission %d : %s" % [mission, _annonce()], 4.0)
		return
	t += dt
	# fuyard suivi : le plus proche encore libre
	var libres := fuyards.filter(func(f): return not f.pris and is_instance_valid(f.g))
	if libres.is_empty():
		return
	libres.sort_custom(func(a, b): return car.global_position.distance_squared_to(a.g.voiture.global_position) < car.global_position.distance_squared_to(b.g.voiture.global_position))
	var cible: Dictionary = libres[0]
	fuyard = cible.g; degats = cible.degats
	var fv: Vector3 = cible.g.voiture.global_position
	act._itineraire(dt, Vector2(fv.x, fv.z))
	act.marks = fuyards.filter(func(f): return not f.pris and is_instance_valid(f.g)).map(func(f):
		var p: Vector3 = f.g.voiture.global_position
		return {p = Vector2(p.x, p.z), col = Color(1.0, 0.3, 0.25), txt = "!", gps = true})
	var dmax := 0.0
	for f in fuyards:
		if f.pris or not is_instance_valid(f.g):
			continue
		var d: float = car.global_position.distance_to(f.g.voiture.global_position)
		dmax = maxf(dmax, d)
		f.coince_t = f.coince_t + dt if d < COINCE_D and f.g.voiture.linear_velocity.length() < 1.5 else 0.0
		if f.g.blown:
			_prendre(f, "hors d'état de nuire… sa voiture aussi !", true)
		elif f.degats >= 100.0:
			_prendre(f, "immobilisé et interpellé !", false)
		elif f.coince_t > COINCE_T:
			_prendre(f, "coincé et interpellé !", false)
	_coince_t = cible.coince_t
	_perdu_t = _perdu_t + dt if dmax > PERDU else 0.0
	# carte d'activité (#162) : chrono en gros, coloré quand il presse (#161)
	var reste := duree - t
	var coul := Color.WHITE if reste > 30.0 else (Color(1.0, 0.62, 0.15) if reste > 10.0 or fmod(t, 0.5) < 0.25 else Color(1.0, 0.25, 0.2))
	var lignes := PackedStringArray()
	var n := 0
	for f in fuyards:
		n += 1
		var nom := "Fuyard %d" % n if fuyards.size() > 1 else "Fuyard"
		if f.pris:
			lignes.append("%s : interpellé" % nom)
		elif is_instance_valid(f.g):
			lignes.append("%s à %d m · dégâts %d %%" % [nom, int(car.global_position.distance_to(f.g.voiture.global_position)), int(f.degats)])
	act._set_status("%s   MISSION %d\n%s" % [_mmss(reste), mission, "\n".join(lignes)], coul, true)
	if fuyards.all(func(f): return f.pris):
		_mission_reussie()
	elif _perdu_t > PERDU_T:
		_fin_service("Un fuyard vous a semé…")
	elif t > duree:
		_fin_service("Temps écoulé : les fuyards courent toujours…")

func _annonce() -> String:
	var n: int = (_p.modeles as Array).size()
	return ("%d fuyards" % n if n > 1 else "un fuyard") + " à %d km/h au plus, %s" % [int(_p.vmax * 3.6), _mmss(duree)]

func _prendre(f: Dictionary, msg: String, detruit: bool) -> void:
	f.pris = true
	f.detruit = detruit
	if is_instance_valid(f.g) and not detruit:
		f.g.mode = "arret"
	if main.get("succes"):
		main.succes.noter("interpellations")
	var nom := "Fuyard %d" % (fuyards.find(f) + 1) if fuyards.size() > 1 else "Fuyard"
	main.get_node("HUD").toast("%s %s" % [nom, msg], 3.0)
	print("[gendarme] %s %s" % [nom, msg])

func _mission_reussie() -> void:
	interpelle = true
	var m := medaille(t, duree)
	var prime: float = _p.base * float(PART_MEDAILLE[m])
	var part := prime / maxf(fuyards.size(), 1)
	for f in fuyards:
		if f.detruit:
			prime -= part * 0.5                  # KA-BOOM : sa part réduite de moitié
	var g = main.get("garage")
	if g:
		g.gagner(prime)
	gains += prime
	reussies += 1
	medailles[m] = int(medailles[m]) + 1
	var su = main.get("succes")
	if su:                                       # meilleure série de missions d'un même service (succès « Gendarme d'élite »)
		su.stats["serie_gendarme"] = maxf(float(su.stats.get("serie_gendarme", 0.0)), float(reussies))
		su._change = true
	var act = _act()
	var bilan := "Mission %d réussie en %s : %s, +%s" % [mission, _mmss(t), m.to_upper(), act._euros(prime)]
	print("[gendarme] " + bilan)
	main.get_node("HUD").toast(bilan, PAUSE + 1.0)
	act._set_status("%s\nmission suivante dans %d s" % [bilan, int(PAUSE)])
	if not enchainer:
		_fin_service("")
		return
	_pause_t = PAUSE

## Fin du service : bilan (missions réussies, médailles, gains) dans la carte d'activité et un message.
func _fin_service(msg: String) -> void:
	var act = _act()
	var bilan := "%sService terminé : %d mission(s) réussie(s) (or %d, argent %d, bronze %d), +%s" % [
		(msg + " ") if msg != "" else "", reussies, medailles.or, medailles.argent, medailles.bronze, act._euros(gains)]
	print("[gendarme] fin : " + bilan)
	act._stop()
	act._set_status(bilan)
	act._status_t = 10.0
	main.get_node("HUD").toast(bilan, 6.0)

static func _mmss(s: float) -> String:
	var a := maxf(s, 0.0)
	return "%d:%02d" % [int(a) / 60, int(a) % 60]

## Chocs contre les fuyards : dégâts selon la vitesse de rapprochement.
func _physics_process(dt: float) -> void:
	if not actif or get_tree().paused or _pause_t > 0.0:
		return
	_choc_cd -= dt
	var car: VehicleBody3D = main.car
	for f in fuyards:
		if f.pris or not is_instance_valid(f.g) or f.g.blown:
			continue
		var fv: VehicleBody3D = f.g.voiture
		var nrm: Vector3 = (fv.global_position - car.global_position).normalized()
		# vitesse de rapprochement du pas d'avant : au moment où le contact est relevé, le choc a déjà freiné les deux voitures
		var r: float = f.get("rel", 0.0)
		f.rel = (car.linear_velocity - fv.linear_velocity).dot(nrm)
		if _choc_cd > 0.0 or not (car in fv.get_colliding_bodies()):      # contacts relevés par le fuyard
			continue
		r = maxf(r, f.rel)
		if r < CHOC_MIN:
			continue
		_choc_cd = 0.6
		f.degats = minf(f.degats + minf(r * PAR_MS, float(_p.choc_max)), 100.0)
		main.get_node("HUD").toast("Choc ! Fuyard abîmé à %d %%" % int(f.degats), 1.5)
		print("[gendarme] choc à %.1f m/s : dégâts %d %%" % [r, int(f.degats)])
