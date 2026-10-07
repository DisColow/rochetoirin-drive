## Caméra : poursuite souple derrière la voiture, ou vue conducteur (bouton caméra).
extends Node3D

var target: VehicleBody3D
var cam: Camera3D
var mode := 0                      # 0 poursuite, 1 conducteur, 2 capot
var _pos := Vector3.ZERO
var _look := Vector3.ZERO
var eye := Vector3(-0.39, 1.33, 0.10)
var cockpit: CanvasLayer          # habitacle en pixel art (vue conducteur)
var hud: CanvasLayer
var shake := 0.0                  # secousse (explosion), décroît toute seule
# regard au doigt : glisser sur l'écran (hors boutons) tourne la caméra ; elle revient en place quand on lâche
var yaw_off := 0.0
var pitch_off := 0.0
var _drag := {}
var _idle := 0.0

func _input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed and not (hud and hud.is_ui_point(e.position)):
			_drag[e.index] = true
		elif not e.pressed:
			_drag.erase(e.index)
	elif e is InputEventScreenDrag and _drag.has(e.index):
		var lim := 0.55 if mode != 0 else PI
		yaw_off = clampf(yaw_off - e.relative.x * 0.006, -lim, lim)
		pitch_off = clampf(pitch_off - e.relative.y * 0.004, -0.35 if mode != 0 else -0.25, 0.6 if mode == 0 else 0.35)
		_idle = 0.0

func _ready() -> void:
	cam = Camera3D.new()
	cam.near = 0.08
	cam.far = 160000.0
	cam.fov = 62.0
	add_child(cam)
	cam.make_current()
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/car/meta.json"))
	eye = Vector3(-meta.eye[0], meta.eye[1], -meta.eye[2])      # modèle tourné de 180°
	_pos = target.global_position + Vector3(0, 3, -7)

func snap() -> void:
	var t := target.global_transform
	var flat := Vector3(t.basis.z.x, 0, t.basis.z.z).normalized()
	_pos = t.origin - flat * 7.2 + Vector3(0, 2.6, 0)
	_look = t.origin + Vector3(0, 1.2, 0)

func cycle() -> void:
	set_mode((mode + 1) % 3)

func set_mode(m: int) -> void:
	mode = m
	if cockpit:
		cockpit.eye = eye
		cockpit.set_active(mode == 1)

func _process(dt: float) -> void:
	if Input.is_action_just_pressed("camera"):
		cycle()
	shake = move_toward(shake, 0.0, dt * 1.2)
	if _drag.is_empty():
		_idle += dt
		if _idle > 1.2:
			var k0 := 1.0 - exp(-dt * 2.5)
			yaw_off = lerpf(yaw_off, 0.0, k0)
			pitch_off = lerpf(pitch_off, 0.0, k0)
	if cockpit:
		cockpit.look_offset(yaw_off, pitch_off)
	var t := target.global_transform
	var fwd := t.basis.z
	if mode == 0:
		var flat := Vector3(fwd.x, 0, fwd.z).normalized().rotated(Vector3.UP, yaw_off)
		var want := t.origin - flat * 7.2 * cos(pitch_off) + Vector3(0, 2.6 + 7.2 * sin(pitch_off), 0)
		var k := 1.0 - exp(-dt * 5.0)
		_pos = _pos.lerp(want, k)
		_look = _look.lerp(t.origin + Vector3(0, 1.2, 0) + flat * 3.0, 1.0 - exp(-dt * 10.0)) if _look != Vector3.ZERO else t.origin
		cam.global_position = _pos
		cam.look_at(_look, Vector3.UP)
		cam.fov = lerpf(cam.fov, 62.0 + clampf(target.kmh() / 8.0, 0.0, 12.0), 1.0 - exp(-dt * 2.0))
	else:
		var p := t * (eye if mode == 1 else Vector3(0, 1.45, 1.2))
		cam.global_position = p
		# vue conducteur : regard un peu plongeant (la route apparaît au-dessus de la planche de bord en pixel art)
		var b := Basis.looking_at(fwd.rotated(t.basis.y, yaw_off), t.basis.y)
		b = b * Basis(Vector3.RIGHT, pitch_off)
		if mode == 1:
			b = b * Basis(Vector3.RIGHT, deg_to_rad(-7.0))
		cam.global_basis = b
		cam.fov = 68.0 if mode == 1 else 66.0
	if shake > 0.0:
		cam.global_position += Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * shake * 0.6
