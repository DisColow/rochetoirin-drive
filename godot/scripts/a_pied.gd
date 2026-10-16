## À pied (issue #66) : on sort de la voiture arrêtée pour voir le monde comme un piéton, en vue à la première personne.
## Commandes (v6.54, #80) : au tactile, deux sticks virtuels comme les FPS sur téléphone (pouce gauche : marcher, à
## fond pour courir ; pouce droit : regarder), apparus là où l'on pose le pouce ; « SAUT » (disque au-dessus des sticks,
## Espace, bouton A). Clavier : ↑ ↓ marcher, ◀ ▶ tourner ; manette : sticks. Touche E / bouton Y, bouton « VOITURE » :
## retour dans la voiture d'où qu'on soit. Tête qui balance en marchant. Pendant ce temps la voiture est au frein de parking et ne lit
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
var _doigts := {}                 # doigt -> position (glisser pour regarder, souris)
var _sticks := {}                 # doigt -> [côté ("g" / "d"), centre, position]
var _calque: CanvasLayer
var _dessin: Control
var _pas := 0.0                   # phase du pas (balancement de la tête)
var _choc := 0.0                  # tête qui s'enfonce à la réception d'un saut
const SAUT := 4.3                 # m/s vers le haut
const RAYON := 110.0              # rayon des sticks virtuels (px)

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
	_calque = CanvasLayer.new(); _calque.layer = 1
	_dessin = Control.new(); _dessin.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dessin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dessin.draw.connect(_dessiner_sticks)
	_calque.add_child(_dessin)
	add_child(_calque)
	_sticks.clear()
	var hud = main.get_node("HUD")
	hud.gps.car = corps; hud.map.car = corps            # mini-carte et carte centrées sur le piéton
	main.get_node("HUD").toast("À pied : pouce gauche pour marcher, pouce droit pour regarder, SAUT pour sauter.", 4.0)

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
	if _calque:
		_calque.queue_free()
	_calque = null
	_sticks.clear()

## Après une téléportation par la carte (#80) : la voiture a été déplacée, le piéton la suit (à côté de la portière).
func rejoindre_voiture() -> void:
	if not actif or corps == null:
		return
	var car = main.car
	# la voiture, figée à pied, doit retomber sur le sol du point choisi avant d'être figée de nouveau
	car.freeze = false
	get_tree().create_timer(2.0).timeout.connect(func():
		if actif:
			car.linear_velocity = Vector3.ZERO; car.angular_velocity = Vector3.ZERO; car.freeze = true)
	var p: Vector3 = car.global_transform * Vector3(1.6, 0.0, 0.4)
	p.y = Relief.hauteur(p) + 0.1
	corps.global_position = p
	corps.velocity = Vector3.ZERO
	var f: Vector3 = car.global_transform.basis.z
	_yaw = atan2(f.x, f.z)
	_appliquer_regard()

## Stick virtuel d'un côté : vecteur (-1…1, -1…1), (0, 0) si aucun pouce.
func _stick(cote: String) -> Vector2:
	for k in _sticks:
		var st: Array = _sticks[k]
		if st[0] == cote:
			var d: Vector2 = (st[2] - st[1]) / RAYON
			return d.limit_length(1.0)
	return Vector2.ZERO

func _dessiner_sticks() -> void:
	for k in _sticks:
		var st: Array = _sticks[k]
		var c: Vector2 = st[1]
		var pt: Vector2 = c + ((st[2] - c) as Vector2).limit_length(RAYON)
		_dessin.draw_circle(c, RAYON, Color(0.05, 0.06, 0.07, 0.28))
		_dessin.draw_arc(c, RAYON, 0.0, TAU, 48, Color(1, 1, 1, 0.45), 3.0, true)
		_dessin.draw_circle(pt, 44.0, Color(1, 1, 1, 0.42))

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
	# regard : stick droit (manette) ; axe vertical inversé (#82 : pousser vers le haut baisse le regard)
	var rx := Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var ry := Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	if absf(rx) > 0.15:
		_yaw -= rx * 2.4 * dt
	if absf(ry) > 0.15:
		_pitch = clampf(_pitch + ry * 1.8 * dt, -1.3, 1.3)
	# sticks virtuels (#80) : droit = regard (vitesse selon l'écart), gauche = marche
	var sd := _stick("d")
	if sd != Vector2.ZERO:
		_yaw -= sd.x * absf(sd.x) * 3.0 * dt
		_pitch = clampf(_pitch + sd.y * absf(sd.y) * 2.0 * dt, -1.3, 1.3)
	var sg := _stick("g")
	# marche : GAZ / FREIN (↑ ↓), stick gauche ; ◀ ▶ tournent
	var av := Input.get_action_strength("accelerer") - Input.get_action_strength("freiner")
	var lat := 0.0
	if sg != Vector2.ZERO:
		av = -sg.y; lat = sg.x
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
	# course : GAZ tenu 2 s, ou stick gauche poussé à fond
	var vit := COURSE if (_avance_t > 2.0 or sg.length() > 0.92) else MARCHE
	var b := corps.global_transform.basis
	var dir := (b.z * av + b.x * -lat)
	dir.y = 0.0
	if dir.length() > 1.0:
		dir = dir.normalized()
	var v := corps.velocity
	v.x = dir.x * vit; v.z = dir.z * vit
	var au_sol := corps.is_on_floor()
	if au_sol:
		v.y = 0.0
		if Input.is_action_just_pressed("frein_main"):            # saut (#80) : Espace, bouton A, disque SAUT
			v.y = SAUT
	else:
		v.y -= 9.81 * dt
	var tombait := v.y
	corps.velocity = v
	corps.move_and_slide()
	if not au_sol and corps.is_on_floor() and tombait < -2.0:
		_choc = clampf(-tombait * 0.02, 0.0, 0.12)                # réception : la tête s'enfonce un peu
	# tête qui balance en marchant (#80) : monte et descend à chaque pas, roule légèrement d'un côté à l'autre
	var hv := Vector2(v.x, v.z).length()
	if corps.is_on_floor() and hv > 0.2:
		_pas += dt * hv * 3.6
	_choc = move_toward(_choc, 0.0, dt * 0.5)
	var amp := clampf(hv / COURSE, 0.0, 1.0)
	cam.position = Vector3(cos(_pas * 0.5) * 0.035 * amp, YEUX + absf(sin(_pas * 0.5)) * 0.06 * amp - 0.03 * amp - _choc, 0.0)
	cam.rotation.z = sin(_pas * 0.5) * 0.012 * amp
	# jamais sous le relief (collisions du relief pas encore prêtes, trou) : remis dessus
	var h: float = Relief.hauteur(corps.global_position)
	if not is_nan(h) and corps.global_position.y < h - 0.3:
		corps.global_position.y = h + 0.05
		corps.velocity.y = 0.0

## Un bouton de l'interface (P, VOITURE, menus du haut…) sous le doigt : pas de stick.
func _sur_bouton(p: Vector2) -> bool:
	for c in get_tree().get_nodes_in_group("ui_zone"):
		if c is Control and (c as Control).is_visible_in_tree() and (c as Control).get_global_rect().has_point(p):
			return true
	return false

## Sticks virtuels au tactile ; souris (bouton droit) pour regarder sur PC.
func _input(e: InputEvent) -> void:
	if not actif or cam == null:
		return
	var vs := get_viewport().get_visible_rect().size
	if e is InputEventScreenTouch:
		if e.pressed:
			# sticks : moitié gauche / droite de l'écran, sous la rangée du haut ; pas sur le disque SAUT
			var hud = main.get_node("HUD")
			var saut: Node2D = hud.get("b_frein_main")
			var sur_saut: bool = saut != null and saut.visible and e.position.distance_to(saut.position + Vector2(40, 40)) < 60.0
			if e.position.y > vs.y * 0.3 and not sur_saut and not _sur_bouton(e.position):
				var cote := "g" if e.position.x < vs.x * 0.5 else "d"
				for k in _sticks.keys():
					if _sticks[k][0] == cote:
						_sticks.erase(k)
				_sticks[e.index] = [cote, e.position, e.position]
		else:
			_sticks.erase(e.index)
		if _dessin:
			_dessin.queue_redraw()
	elif e is InputEventScreenDrag and _sticks.has(e.index):
		_sticks[e.index][2] = e.position
		if _dessin:
			_dessin.queue_redraw()
	elif e is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_yaw -= e.relative.x * 0.004
		_pitch = clampf(_pitch + e.relative.y * 0.004, -1.3, 1.3)
		_appliquer_regard()
