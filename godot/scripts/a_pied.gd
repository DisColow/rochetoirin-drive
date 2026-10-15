## À pied (issue #66) : on sort de la voiture arrêtée pour voir le monde comme un piéton, en vue à la première personne.
## Commandes : les mêmes que la voiture (GAZ / ↑ avancer, FREIN / ↓ reculer, ◀ ▶ tourner), glisser le doigt sur l'écran
## (ou stick droit, souris) pour regarder, stick gauche pour marcher ; touche E / bouton Y : sortir, puis remonter
## (bouton « Monter » à moins de 3,5 m de la voiture). Pendant ce temps la voiture est au frein de parking et ne lit
## plus les commandes, et le monde (routes, bâtiments, relief, collisions…) se charge autour du piéton (main.suivre).
extends Node
const Relief := preload("res://scripts/relief.gd")

const MARCHE := 1.7               # m/s
const COURSE := 4.2               # GAZ tenu plus de 2 s : on court
const YEUX := 1.62
const PORTEE_MONTER := 3.5

var main: Node
var actif := false
var corps: CharacterBody3D
var cam: Camera3D
var _yaw := 0.0
var _pitch := 0.0
var _avance_t := 0.0
var _doigts := {}                 # doigt -> position (glisser pour regarder)

func _ready() -> void:
	if not InputMap.has_action("pied"):
		InputMap.add_action("pied", 0.5)
		var k := InputEventKey.new(); k.physical_keycode = KEY_E
		InputMap.action_add_event("pied", k)
		var j := InputEventJoypadButton.new(); j.button_index = JOY_BUTTON_Y
		InputMap.action_add_event("pied", j)

## Peut-on sortir maintenant ? (voiture presque arrêtée, aucune activité)
func peut_sortir() -> bool:
	var car = main.car
	var act = main.get("activities")
	return not actif and car.kmh() < 3.0 and (act == null or str(act.mode) == "")

func pres_de_la_voiture() -> bool:
	return actif and corps and corps.global_position.distance_to(main.car.global_position) < PORTEE_MONTER

func basculer() -> void:
	if actif:
		monter()                                       # d'où qu'on soit : retour direct dans la voiture
	elif peut_sortir():
		sortir()
	else:
		main.get_node("HUD").toast("Arrêtez-vous (et l'activité en cours) pour descendre.", 2.5)

func sortir() -> void:
	var car = main.car
	if main.cam_rig.mode == 1:
		main.cam_rig.set_mode(0)                    # vue cockpit refermée avant de descendre
	main.cam_rig.set_process(false)
	actif = true
	car.controle = false
	car.frein_parking = true
	# voiture immobilisée tout à fait (en pente, les freins de VehicleBody3D la laissaient glisser : v6.53)
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	car.freeze = true
	corps = CharacterBody3D.new()
	corps.name = "Pieton"
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new(); cap.radius = 0.3; cap.height = 1.75
	cs.shape = cap; cs.position.y = 0.875
	corps.add_child(cs)
	corps.floor_snap_length = 0.6
	corps.floor_max_angle = deg_to_rad(50.0)
	cam = Camera3D.new()
	cam.position.y = YEUX
	cam.fov = 72.0
	cam.far = 6000.0
	corps.add_child(cam)
	main.add_child(corps)
	# côté conducteur (gauche de la voiture : +x)
	var p: Vector3 = car.global_transform * Vector3(1.6, 0.0, 0.4)
	p.y = Relief.hauteur(p) + 0.05
	corps.global_position = p
	var f: Vector3 = car.global_transform.basis.z
	_yaw = atan2(f.x, f.z)
	_pitch = 0.0
	_appliquer_regard()
	cam.make_current()
	corps.add_collision_exception_with(car)          # on peut se tenir contre la voiture sans être éjecté
	main.suivre(corps)
	var hud = main.get_node("HUD")
	hud.gps.car = corps; hud.map.car = corps            # mini-carte et carte centrées sur le piéton
	main.get_node("HUD").toast("À pied : GAZ / FREIN pour marcher, ◀ ▶ pour tourner, glissez pour regarder.", 4.0)

func monter() -> void:
	var car = main.car
	actif = false
	car.freeze = false
	car.controle = true
	car.frein_parking = false
	var hud = main.get_node("HUD")
	hud.gps.car = car; hud.map.car = car
	main.suivre(car)
	main.cam_rig.set_process(true)
	main.cam_rig.cam.make_current()
	if corps:
		corps.queue_free()
	corps = null
	cam = null

func _appliquer_regard() -> void:
	corps.rotation.y = _yaw
	# la caméra regarde son -Z ; le piéton avance selon +Z : demi-tour, puis la tête lève ou baisse
	cam.rotation = Vector3(-_pitch, PI, 0.0)

func _process(_dt: float) -> void:
	if Input.is_action_just_pressed("pied") and not get_tree().paused and not preload("res://scripts/ui.gd").saisie_active():
		basculer()

func _physics_process(dt: float) -> void:
	if not actif or corps == null or get_tree().paused:
		return
	# regard : stick droit (manette)
	var rx := Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var ry := Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	if absf(rx) > 0.15:
		_yaw -= rx * 2.4 * dt
	if absf(ry) > 0.15:
		_pitch = clampf(_pitch - ry * 1.8 * dt, -1.3, 1.3)
	# marche : GAZ / FREIN (↑ ↓), stick gauche ; ◀ ▶ tournent
	var av := Input.get_action_strength("accelerer") - Input.get_action_strength("freiner")
	var lat := 0.0
	var ly := Input.get_joy_axis(0, JOY_AXIS_LEFT_Y)
	var lx := Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
	if absf(ly) > 0.2:
		av = -ly
	if absf(lx) > 0.2:
		lat = lx
	else:
		_yaw += (Input.get_action_strength("gauche") - Input.get_action_strength("droite")) * 2.0 * dt
	_appliquer_regard()
	_avance_t = _avance_t + dt if av > 0.5 else 0.0
	var vit := COURSE if _avance_t > 2.0 else MARCHE
	var b := corps.global_transform.basis
	var dir := (b.z * av + b.x * -lat)
	dir.y = 0.0
	if dir.length() > 1.0:
		dir = dir.normalized()
	var v := corps.velocity
	v.x = dir.x * vit; v.z = dir.z * vit
	v.y = 0.0 if corps.is_on_floor() else v.y - 9.81 * dt
	corps.velocity = v
	corps.move_and_slide()
	# jamais sous le relief (collisions du relief pas encore prêtes, trou) : remis dessus
	var h: float = Relief.hauteur(corps.global_position)
	if not is_nan(h) and corps.global_position.y < h - 0.3:
		corps.global_position.y = h + 0.05
		corps.velocity.y = 0.0

## Glisser le doigt (hors des boutons) ou la souris pour regarder autour de soi.
func _input(e: InputEvent) -> void:
	if not actif or cam == null:
		return
	var vs := get_viewport().get_visible_rect().size
	if e is InputEventScreenTouch:
		# zone des commandes (bas de l'écran) exclue
		if e.pressed and e.position.y < vs.y - 260.0:
			_doigts[e.index] = e.position
		elif not e.pressed:
			_doigts.erase(e.index)
	elif e is InputEventScreenDrag and _doigts.has(e.index):
		_yaw -= e.relative.x * 0.005
		_pitch = clampf(_pitch - e.relative.y * 0.004, -1.3, 1.3)
		_appliquer_regard()
	elif e is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_yaw -= e.relative.x * 0.004
		_pitch = clampf(_pitch - e.relative.y * 0.004, -1.3, 1.3)
		_appliquer_regard()
