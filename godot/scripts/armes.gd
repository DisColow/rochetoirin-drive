## Courses à armes en multijoueur (#99, façon Mario Kart) : l'hôte active « armes » dans le menu Multijoueur ; pendant
## une course, des caisses « ? » sont posées sur le tracé (une rangée de trois à chaque étape et à mi-chemin) ; passer
## dessus donne une arme au hasard (une à la fois), tirée avec le bouton ARME (F au clavier, croix ↑ à la manette) :
##   - boule de feu : file tout droit devant (70 m/s, 2,5 s) ; la voiture touchée part en l'air en tournoyant ;
##   - onde de choc : repousse toutes les voitures à moins de 18 m ;
##   - bouclier : 6 s d'immunité (bulle visible par tous) ;
##   - tornade : soulève la voiture la plus proche devant soi (moins de 90 m) et la fait tourner sur elle-même.
## Chaque joueur pilote sa voiture : le tireur calcule le coup (positions reçues des autres) et envoie l'effet à la
## victime (net._subir), dont le jeu l'applique à sa voiture. Essai sans réseau : -- --armes-test.
extends Node3D

const TYPES := ["boule", "onde", "bouclier", "tornade"]
const NOMS := {"boule": "BOULE\nDE FEU", "onde": "ONDE", "bouclier": "BOUCLIER", "tornade": "TORNADE"}
const R_CAISSE := 3.2
const RECHARGE := 5.0                 # une caisse ramassée réapparaît après 5 s

var main: Node
var net: Node
var car: VehicleBody3D
var actif := false
var arme := ""                        # arme en main ("" : aucune)
var bouclier_t := 0.0
var _caisses: Array = []              # [Node3D, temps avant réapparition]
var _projs: Array = []                # [Node3D, vitesse, durée restante, mien]
var _effet_t := 0.0                   # tornade subie : temps restant
var _bouton: TouchScreenButton
var _label: Label
var _bulle: MeshInstance3D
var _mat_caisse: StandardMaterial3D

func _ready() -> void:
	if not InputMap.has_action("arme"):
		InputMap.add_action("arme", 0.5)
		var k := InputEventKey.new(); k.physical_keycode = KEY_F
		InputMap.action_add_event("arme", k)
		var j := InputEventJoypadButton.new(); j.button_index = JOY_BUTTON_DPAD_UP
		InputMap.action_add_event("arme", j)
	_mat_caisse = StandardMaterial3D.new()
	_mat_caisse.albedo_color = Color(1.0, 0.8, 0.15)
	_mat_caisse.emission_enabled = true; _mat_caisse.emission = Color(1.0, 0.6, 0.1); _mat_caisse.emission_energy_multiplier = 0.8
	var calque := CanvasLayer.new(); calque.layer = 5
	add_child(calque)
	_bouton = TouchScreenButton.new()
	_bouton.action = "arme"
	_bouton.passby_press = true
	var img := Image.create(150, 150, false, Image.FORMAT_RGBA8)
	for y in 150:
		for x in 150:
			var d := Vector2(x - 75, y - 75).length()
			if d < 74:
				img.set_pixel(x, y, Color(0.75, 0.15, 0.05, 0.7) if d < 70 else Color(1, 0.85, 0.3, 0.9))
	_bouton.texture_normal = ImageTexture.create_from_image(img)
	var sh := CircleShape2D.new(); sh.radius = 75
	_bouton.shape = sh; _bouton.shape_centered = true
	_label = Label.new()
	_label.size = Vector2(150, 150)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; _label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 22)
	_bouton.add_child(_label)
	_bouton.visible = false
	calque.add_child(_bouton)

## Début d'une course à armes : caisses sur le tracé (points de la course : positions 3D).
func demarrer(points: Array) -> void:
	arreter()
	actif = true
	for k in range(1, points.size()):
		var a: Vector3 = points[k - 1]; var b: Vector3 = points[k]
		for c in [a.lerp(b, 0.5), b]:
			var dir := (b - a); dir.y = 0.0
			dir = dir.normalized() if dir.length() > 0.1 else Vector3.FORWARD
			var lat := dir.cross(Vector3.UP)
			for o in [-3.5, 0.0, 3.5]:
				var p: Vector3 = c + lat * o
				p.y = preload("res://scripts/relief.gd").hauteur(p)
				_caisses.append([_caisse(p), 0.0])

func arreter() -> void:
	actif = false
	arme = ""
	for c in _caisses:
		if is_instance_valid(c[0]):
			c[0].queue_free()
	_caisses.clear()
	_bouton.visible = false

func _caisse(p: Vector3) -> Node3D:
	var n := Node3D.new()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = Vector3(1.1, 1.1, 1.1)
	mi.mesh = bm; mi.material_override = _mat_caisse
	n.add_child(mi)
	# « ? » peint sur les quatre faces (au centre, il était caché par la caisse)
	for k in 4:
		var l := Label3D.new(); l.text = "?"; l.font_size = 140; l.outline_size = 0
		l.modulate = Color(0.25, 0.05, 0.0)
		l.rotation.y = k * PI / 2.0
		l.position = Vector3(sin(k * PI / 2.0), 0, cos(k * PI / 2.0)) * 0.56
		n.add_child(l)
	n.position = p + Vector3(0, 1.0, 0)
	add_child(n)
	return n

func _process(dt: float) -> void:
	if car == null:
		return
	# caisses : rotation, ramassage, réapparition
	for c in _caisses:
		var n: Node3D = c[0]
		n.rotate_y(dt * 1.6)
		if c[1] > 0.0:
			c[1] -= dt
			n.visible = c[1] <= 0.0
			continue
		if arme == "" and actif and n.global_position.distance_to(car.global_position + Vector3(0, 0.8, 0)) < R_CAISSE:
			arme = TYPES[randi() % TYPES.size()]
			c[1] = RECHARGE
			n.visible = false
			_son("teleport")
	_bouton.visible = actif and arme != ""
	if _bouton.visible:
		_label.text = NOMS[arme]
		var s := get_viewport().get_visible_rect().size
		_bouton.position = Vector2(s.x - 240 - 170, s.y - 260 - 60)
	if arme != "" and Input.is_action_just_pressed("arme") and not preload("res://scripts/ui.gd").saisie_active():
		tirer()
	# bouclier
	if bouclier_t > 0.0:
		bouclier_t -= dt
	_bulle_visible(bouclier_t > 0.0)
	# projectiles
	for pr in _projs.duplicate():
		var n: Node3D = pr[0]
		# avance par pas de 1 m au plus : une image lente ne doit pas faire traverser la cible
		var depl: Vector3 = pr[1] * dt
		var pas := maxi(1, ceili(depl.length()))
		var touche := 0
		for i in pas:
			n.global_position += depl / pas
			if pr[3]:
				touche = _auto_proche(n.global_position, 2.6)
				if touche != 0:
					break
		pr[2] -= dt
		if touche != 0 or pr[2] <= 0.0:
			if touche != 0:
				_frapper(touche, "boule", pr[1].normalized())
				_explosion(n.global_position)
			n.queue_free()
			_projs.erase(pr)
	# tornade subie : la voiture tourne sur elle-même en l'air
	if _effet_t > 0.0:
		_effet_t -= dt
		car.angular_velocity = Vector3(0, 9.0, 0)
		if car.global_position.y < preload("res://scripts/relief.gd").hauteur(car.global_position) + 4.0:
			car.linear_velocity.y = maxf(car.linear_velocity.y, 5.0)

## Tire l'arme en main.
func tirer() -> void:
	var a := arme
	arme = ""
	var fwd := car.global_transform.basis.z
	match a:
		"boule":
			var p := car.global_position + fwd * 3.2 + Vector3(0, 1.0, 0)
			var v := fwd * 70.0 + Vector3(car.linear_velocity.x, 0, car.linear_velocity.z)
			if net and net.en_ligne():
				net.tir_vu.rpc(p, v)                   # les autres voient passer la boule
			_boule(p, v, true)
			_son("soucoupe_depart")
		"onde":
			for id in _autos_proches(car.global_position, 18.0):
				_frapper(id, "onde", (_pos_auto(id) - car.global_position).normalized())
			_explosion(car.global_position + Vector3(0, 0.6, 0), 3.0)
			_son("coup_sourd")
		"bouclier":
			bouclier_t = 6.0
			if net and net.en_ligne():
				net.bouclier_vu.rpc(6.0)
		"tornade":
			var best := 0; var bd := 90.0                 # 0 : personne (ids réseau > 0, cibles d'essai < 0)
			for id in _ids():
				var d := _pos_auto(id) - car.global_position
				if d.length() < bd and d.dot(fwd) > 0.0:
					bd = d.length(); best = id
			if best != 0:
				_frapper(best, "tornade", fwd)
			_son("rayon")

func _boule(p: Vector3, v: Vector3, mien: bool) -> void:
	var n := MeshInstance3D.new()
	var sm := SphereMesh.new(); sm.radius = 0.6; sm.height = 1.2
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.45, 0.05)
	m.emission_enabled = true; m.emission = Color(1.0, 0.35, 0.0); m.emission_energy_multiplier = 4.0
	sm.material = m
	n.mesh = sm
	var lum := OmniLight3D.new(); lum.light_color = Color(1.0, 0.5, 0.1); lum.light_energy = 3.0; lum.omni_range = 9.0
	n.add_child(lum)
	add_child(n)
	n.global_position = p
	_projs.append([n, v, 2.5, mien])

## Effet envoyé à un joueur (id réseau) ; -1, -2… : cibles d'essai locales (pas de réseau).
func _frapper(id: int, type: String, dir: Vector3) -> void:
	if net and net.en_ligne() and id > 0:
		net.subir_chez(id, type, dir)
	elif id < 0 and has_meta("cibles"):
		set_meta("touche_" + type, true)                # essai : le coup a bien trouvé sa cible

## Effet reçu (appelé par net.gd chez la victime).
func subir(type: String, dir: Vector3) -> void:
	if bouclier_t > 0.0:
		return
	var rnd := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
	match type:
		"boule":
			car.linear_velocity += Vector3.UP * 10.0 + dir * 7.0
			car.angular_velocity = rnd * 7.0
			_explosion(car.global_position + Vector3(0, 1, 0))
		"onde":
			car.linear_velocity += Vector3.UP * 5.0 + Vector3(dir.x, 0, dir.z).normalized() * 12.0
			car.angular_velocity = rnd * 4.0
		"tornade":
			_effet_t = 2.0
			car.linear_velocity += Vector3.UP * 8.0
	_son("coup_sourd")

func _bulle_visible(oui: bool) -> void:
	if oui and _bulle == null:
		_bulle = MeshInstance3D.new()
		var sm := SphereMesh.new(); sm.radius = 3.2; sm.height = 4.0
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.4, 0.8, 1.0)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH     # pas de transparence mélangée (performances.md)
		m.albedo_color.a = 0.35
		sm.material = m
		_bulle.mesh = sm
		car.add_child(_bulle)
		_bulle.position = Vector3(0, 1.0, 0)
	if _bulle:
		_bulle.visible = oui

func _explosion(p: Vector3, taille := 1.5) -> void:
	var D = main.get("dust") if main else null
	if D == null:
		return
	var mat: Dictionary = D.MATIERES.get("fumee", {})
	if mat.is_empty():
		return
	for i in 18:
		D._nuage(mat, p + Vector3(randf_range(-1, 1), randf_range(0, 1), randf_range(-1, 1)) * taille,
			Vector3(randf_range(-4, 4), randf_range(2, 7), randf_range(-4, 4)), 1.0)

func _son(n: String) -> void:
	var s = main.get("sound") if main else null
	if s and s.has_method("_one_shot"):
		s._one_shot(n, car.global_position, 1.2, 1.0, 30.0, 500.0)

# ---------------------------------------------------------------- autres voitures (réseau, ou cibles d'essai)
func _ids() -> Array:
	var l := []
	if net:
		l.append_array(net.autos.keys())
	if has_meta("cibles"):
		l.append_array((get_meta("cibles") as Dictionary).keys())
	return l

func _pos_auto(id: int) -> Vector3:
	if id < 0:
		return (get_meta("cibles")[id] as Node3D).global_position
	return (net.autos[id] as Node3D).global_position

func _autos_proches(p: Vector3, r: float) -> Array:
	var out := []
	for id in _ids():
		if _pos_auto(id).distance_to(p) < r:
			out.append(id)
	return out

func _auto_proche(p: Vector3, r: float) -> int:
	for id in _ids():
		if (_pos_auto(id) + Vector3(0, 1.0, 0)).distance_to(p) < r:
			return id
	return 0
