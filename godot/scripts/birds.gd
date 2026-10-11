## Vols d'oiseaux de temps en temps dans le ciel, devant la voiture (le jour seulement) : une petite bande qui traverse
## en battant des ailes et en planant, en ondulant comme un vrai vol ; un seul appel de dessin (MultiMesh).
extends Node3D

const N := 14

var target: Node3D
var terrain: Node
var day := true
var mm: MultiMesh
var mi: MultiMeshInstance3D
var _t := 3.0
var _life := 0.0
var _c := Vector3.ZERO
var _v := Vector3.ZERO
var _off := []
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	var q := QuadMesh.new()
	q.size = Vector2(1, 0.5)
	var m := ShaderMaterial.new()
	m.shader = preload("res://scripts/bird.gdshader")
	q.material = m
	mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = q
	mm.instance_count = N
	mm.visible_instance_count = 0
	mi = MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 400.0
	add_child(mi)
	for i in N:
		_off.append(Vector3(_rng.randf_range(-9, 9), _rng.randf_range(-3, 3), _rng.randf_range(-9, 9)))

func _ground(x: float, z: float) -> float:
	if terrain and terrain.data:
		var h: float = terrain.data.get_height(Vector3(x, 0, z))
		if is_finite(h):
			return h
	return target.global_position.y

func _spawn() -> void:
	var t := target.global_transform
	var fwd := Vector3(t.basis.z.x, 0, t.basis.z.z).normalized()
	var side := fwd.cross(Vector3.UP)
	var sg := 1.0 if _rng.randf() < 0.5 else -1.0
	# départ sur le côté, devant la voiture ; traversée du champ de vision
	_c = t.origin + fwd * _rng.randf_range(70, 160) + side * sg * _rng.randf_range(90, 140)
	_c.y = _ground(_c.x, _c.z) + _rng.randf_range(18, 45)
	_v = (-side * sg * 1.0 + fwd * _rng.randf_range(-0.3, 0.5)).normalized() * _rng.randf_range(9, 14)
	_life = 26.0
	var n := _rng.randi_range(5, N)
	mm.visible_instance_count = n
	for i in n:
		mm.set_instance_custom_data(i, Color(_rng.randf(), _rng.randf_range(9.0, 13.0), 0.0, 0.0))

func _process(dt: float) -> void:
	if target == null:
		return
	if _life <= 0.0:
		mm.visible_instance_count = 0
		if not day:
			return
		_t -= dt
		if _t <= 0.0:
			_t = _rng.randf_range(25.0, 70.0)
			_spawn()
		return
	_life -= dt
	_c += _v * dt
	var tm := Time.get_ticks_msec() / 1000.0
	var n := mm.visible_instance_count
	for i in n:
		var o: Vector3 = _off[i]
		var wob := Vector3(sin(tm * 0.7 + i), sin(tm * 1.1 + i * 2.0) * 0.5, cos(tm * 0.6 + i * 1.3)) * 1.5
		var p := _c + o + wob
		var s := 0.55 + (i % 3) * 0.08
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * s), p))
		var cd := mm.get_instance_custom_data(i)
		cd.b = 1.0 if fmod(tm * 0.25 + i * 0.37, 1.0) > 0.6 else 0.0      # alternance battements / plané
		mm.set_instance_custom_data(i, cd)
