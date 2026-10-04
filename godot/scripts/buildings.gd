## Bâtiments en tuiles de 256 m chargées au fil de la route (deux par image au plus) ; collisions simples près de la voiture.
extends Node3D

const TILE := 256.0
const VIEW := 1700.0
const COLL := 220.0

var target: Node3D
var tiles := {}
var loaded := {}
var pending := {}
var bodies := {}
var mat: ShaderMaterial
var _t := 0.0

func _ready() -> void:
	for f in DirAccess.get_files_at("res://world/buildings"):
		f = f.trim_suffix(".import").trim_suffix(".remap")
		if not f.ends_with(".glb"):
			continue
		var p := f.trim_prefix("b_").trim_suffix(".glb").split("_")
		tiles[Vector2i(int(p[0]), int(p[1]))] = "res://world/buildings/" + f
	mat = ShaderMaterial.new()
	mat.shader = preload("res://scripts/building.gdshader")
	mat.set_shader_parameter("albedo_tex", load("res://assets/bld/albedo.png"))
	mat.set_shader_parameter("normal_tex", load("res://assets/bld/normal.png"))

func _d(k: Vector2i, c: Vector3) -> float:
	return Vector2((k.x + 0.5) * TILE - c.x, (k.y + 0.5) * TILE - c.z).length()

func _wanted(c: Vector3) -> Array:
	var out := []
	var r := int(ceil(VIEW / TILE))
	var kc := Vector2i(floori(c.x / TILE), floori(c.z / TILE))
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			var k := kc + Vector2i(dx, dz)
			if tiles.has(k) and _d(k, c) < VIEW + TILE * 0.71:
				out.append(k)
	out.sort_custom(func(a, b): return _d(a, c) < _d(b, c))
	return out

func update_now() -> void:
	if target == null:
		return
	for k in _wanted(target.global_position):
		if _d(k, target.global_position) < 600.0:
			_add(k)
	_collisions()

func _process(dt: float) -> void:
	if target == null:
		return
	var n := 0
	for k in pending.keys():
		_add(k)
		pending.erase(k)
		n += 1
		if n >= 2:
			break
	_t -= dt
	if _t > 0:
		return
	_t = 0.25
	var ws := {}
	for k in _wanted(target.global_position):
		ws[k] = true
		if not loaded.has(k) and not pending.has(k):
			pending[k] = true
	for k in pending.keys():
		if not ws.has(k):
			pending.erase(k)
	for k in loaded.keys():
		if not ws.has(k):
			loaded[k].queue_free()
			loaded.erase(k)
			bodies.erase(k)
	_collisions()

func _add(k: Vector2i) -> void:
	if loaded.has(k):
		return
	var sc: PackedScene = load(tiles[k])
	if sc == null:
		return
	var n := sc.instantiate()
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		if mi.name.begins_with("col"):
			mi.visible = false
			continue
		mi.material_override = mat
		mi.visibility_range_end = VIEW
		mi.visibility_range_end_margin = 100.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(n)
	loaded[k] = n

func _collisions() -> void:
	var p := target.global_position
	for k in loaded.keys():
		var need := _d(k, p) < COLL + TILE * 0.71
		if need and not bodies.has(k):
			var sb := StaticBody3D.new()
			for mi in loaded[k].find_children("col*", "MeshInstance3D", true, false):
				var cs := CollisionShape3D.new()
				cs.shape = mi.mesh.create_trimesh_shape()
				sb.add_child(cs)
			loaded[k].add_child(sb)
			bodies[k] = sb
		elif not need and bodies.has(k):
			bodies[k].queue_free()
			bodies.erase(k)
