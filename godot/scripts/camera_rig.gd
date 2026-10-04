## Caméra : poursuite souple derrière la voiture, ou vue conducteur (bouton caméra).
extends Node3D

var target: VehicleBody3D
var cam: Camera3D
var mode := 0                      # 0 poursuite, 1 conducteur, 2 capot
var _pos := Vector3.ZERO
var _look := Vector3.ZERO
var eye := Vector3(-0.39, 1.33, 0.10)

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

func cycle() -> void:
	mode = (mode + 1) % 3

func _process(dt: float) -> void:
	if Input.is_action_just_pressed("camera"):
		cycle()
	var t := target.global_transform
	var fwd := t.basis.z
	if mode == 0:
		var flat := Vector3(fwd.x, 0, fwd.z).normalized()
		var want := t.origin - flat * 7.2 + Vector3(0, 2.6, 0)
		var k := 1.0 - exp(-dt * 5.0)
		_pos = _pos.lerp(want, k)
		_look = _look.lerp(t.origin + Vector3(0, 1.2, 0) + flat * 3.0, 1.0 - exp(-dt * 10.0)) if _look != Vector3.ZERO else t.origin
		cam.global_position = _pos
		cam.look_at(_look, Vector3.UP)
		cam.fov = lerpf(cam.fov, 62.0 + clampf(target.kmh() / 8.0, 0.0, 12.0), 1.0 - exp(-dt * 2.0))
	else:
		var p := t * (eye if mode == 1 else Vector3(0, 1.45, 1.2))
		cam.global_position = p
		cam.global_basis = Basis.looking_at(fwd, t.basis.y) if true else cam.global_basis
		cam.fov = 66.0
