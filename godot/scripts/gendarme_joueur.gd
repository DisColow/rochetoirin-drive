## Activité « Gendarme » (v7.13, #150, hypothèse 4 de l'issue) : Activités > Métiers > « Prendre le service de
## gendarme » (activities._gendarme_start, mode « gendarme »). Le joueur prend la voiture de la Gendarmerette
## (voitures.gd « gendarme », habillée par gendarme.habiller : livrée, gyrophares, sirène) ; un fuyard (gendarme.gd en
## mode « fuite », voiture ordinaire du garage) démarre DEPART m devant et file à l'opposé.
## - Chaque choc contre le fuyard l'abîme (vitesse de rapprochement × PAR_MS %) ; à 100 % il s'arrête : interpellé.
##   Détruit (KA-BOOM) : interpellé aussi, prime réduite.
## - Perdu : plus de PERDU m pendant PERDU_T s, ou plus de DUREE s.
## - Prime : BASE + TEMPS € par seconde d'avance sur DUREE.
## Essai : --drive-test --gendarme-joueur-test (essais.gd).
extends Node

const Gendarme := preload("res://scripts/gendarme.gd")
const DEPART := 60.0
const PAR_MS := 6.0                 # % de dégâts par m/s de rapprochement
const CHOC_MIN := 3.0               # m/s
const PERDU := 450.0
const PERDU_T := 12.0
const DUREE := 180.0
const BASE := 120.0
const TEMPS := 1.0
const MODELES := ["r5", "clio", "p206", "twingo"]

var main: Node
var actif := false
var fuyard                          # gendarme.gd
var degats := 0.0
var t := 0.0
var interpelle := false
var _perdu_t := 0.0
var _choc_cd := 0.0
var _rel_prec := 0.0
var _gyro: Array = []
var _lueur: OmniLight3D
var _sirene: AudioStreamPlayer3D

func _act():
	return main.activities

func demarrer() -> bool:
	var car: VehicleBody3D = main.car
	var circ = main.get("circulation")
	# route devant la voiture, sinon dans une autre direction (voiture en travers, sur un parking…)
	var r: Array = []
	var f: Vector3 = car.global_transform.basis.z
	var p0: Vector3 = circ.point_route(car.global_position) if circ else car.global_position     # route la plus proche
	for k in 8:
		if circ == null or not r.is_empty():
			break
		r = circ.devant(p0, f.rotated(Vector3.UP, k * PI / 4.0), DEPART, -0.7)     # tous les virages, pas de demi-tour
	if r.is_empty():
		return false
	car.construire("gendarme")
	var h := Gendarme.habiller(car, Color(0.1, 0.17, 0.42))
	_gyro = h.gyro; _lueur = h.lueur; _sirene = h.sirene
	_sirene.volume_db = -8.0                      # la sienne : moins forte que celles des autres
	if _sirene.stream:
		_sirene.play()
	car.nitro_niveau = 0
	fuyard = Gendarme.new()
	fuyard.main = main
	fuyard.livree = false
	fuyard.modele = MODELES[randi() % MODELES.size()]
	fuyard.mode = "fuite"
	add_child(fuyard)
	var q: Vector3 = r[0]
	var dir: Vector2 = r[1]
	fuyard.poser(Vector2(q.x, q.z), Vector2(q.x, q.z) + dir * 10.0)
	fuyard._degeler()
	degats = 0.0; t = 0.0; interpelle = false; _perdu_t = 0.0
	actif = true
	return true

func arreter() -> void:
	if not actif:
		return
	actif = false
	if is_instance_valid(fuyard):
		fuyard.queue_free()
	fuyard = null
	var g = main.get("garage")
	if g:
		g.vue_changee.emit(g.vue)                 # on reprend sa voiture (comme après la ligne de bus)
	else:
		main.car.construire(preload("res://scripts/voitures.gd").actuelle())
	main.car.global_position += Vector3.UP * 0.4

func process(dt: float) -> void:
	if not actif or not is_instance_valid(fuyard):
		return
	var act = _act()
	var car: VehicleBody3D = main.car
	t += dt
	Gendarme.clignoter(_gyro, _lueur, t, car.lights_on)
	var fv: Vector3 = fuyard.voiture.global_position
	act._itineraire(dt, Vector2(fv.x, fv.z))
	act.marks = [{p = Vector2(fv.x, fv.z), col = Color(1.0, 0.3, 0.25), txt = "!", gps = true}]
	var d := car.global_position.distance_to(fv)
	_perdu_t = _perdu_t + dt if d > PERDU else 0.0
	act._set_status("GENDARME · fuyard à %d m · dégâts %d %% · %s" % [int(d), int(degats), _mmss(DUREE - t)])
	if fuyard.blown and not interpelle:
		_fin(true, "Le fuyard est hors d'état de nuire… sa voiture aussi !")
	elif degats >= 100.0 and not interpelle:
		fuyard.mode = "arret"
		_fin(true, "Fuyard immobilisé et interpellé !")
	elif _perdu_t > PERDU_T or t > DUREE:
		_fin(false, "Le fuyard vous a semé…")

static func _mmss(s: float) -> String:
	var a := maxf(s, 0.0)
	return "%d:%02d" % [int(a) / 60, int(a) % 60]

func _fin(ok: bool, msg: String) -> void:
	interpelle = ok
	var act = _act()
	var prime := 0.0
	if ok:
		prime = BASE + TEMPS * maxf(DUREE - t, 0.0)
		if fuyard.blown:
			prime *= 0.5
		var g = main.get("garage")
		if g:
			g.gagner(prime)
		if main.get("succes"):
			main.succes.noter("interpellations")
	var bilan := "%s %s" % [msg, ("+%s (en %s)" % [act._euros(prime), _mmss(t)]) if ok else ""]
	print("[gendarme] fin : " + bilan)
	act._stop()
	act._set_status(bilan)
	act._status_t = 8.0
	main.get_node("HUD").toast(bilan, 5.0)

## Chocs contre le fuyard : dégâts selon la vitesse de rapprochement.
func _physics_process(dt: float) -> void:
	if not actif or not is_instance_valid(fuyard) or get_tree().paused or fuyard.blown:
		return
	_choc_cd -= dt
	var car: VehicleBody3D = main.car
	var n: Vector3 = (fuyard.voiture.global_position - car.global_position).normalized()
	# vitesse de rapprochement du pas d'avant : au moment où le contact est relevé, le choc a déjà freiné les deux voitures
	var r := _rel_prec
	_rel_prec = (car.linear_velocity - fuyard.voiture.linear_velocity).dot(n)
	if _choc_cd > 0.0 or not (car in fuyard.voiture.get_colliding_bodies()):      # contacts relevés par le fuyard
		return
	r = maxf(r, _rel_prec)
	if r < CHOC_MIN:
		return
	_choc_cd = 0.6
	degats = minf(degats + r * PAR_MS, 100.0)
	main.get_node("HUD").toast("Choc ! Fuyard abîmé à %d %%" % int(degats), 1.5)
	print("[gendarme] choc à %.1f m/s : dégâts %d %%" % [r, int(degats)])
