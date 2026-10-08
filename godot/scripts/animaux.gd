## Animaux des prés et clôtures des pâtures (build_animaux.py, modèles blender_animaux.py) : tuiles de 256 m chargées
## au fil de la route, un MultiMesh par modèle et par tuile ; on ne traverse ni les bêtes ni les clôtures.
extends Node3D

const TILE := 256.0
const Cells := preload("res://scripts/cells.gd")
const VIEW := 450.0
const MODELS := ["vache", "mouton", "cheval", "cloture"]

var target: Node3D
var tiles := {}
var loaded := {}
var meshes := []
var _t := 0.0

func _ready() -> void:
	if not DirAccess.dir_exists_absolute("res://world/animaux"):
		return
	for f in DirAccess.get_files_at("res://world/animaux"):
		if f.ends_with(".bin"):
			var p := f.trim_prefix("a_").trim_suffix(".bin").split("_")
			tiles[Vector2i(int(p[0]), int(p[1]))] = "res://world/animaux/" + f
	var fence := StandardMaterial3D.new()
	fence.albedo_color = Color(0.38, 0.28, 0.18); fence.roughness = 0.9
	var wire := StandardMaterial3D.new()
	wire.albedo_color = Color(0.22, 0.22, 0.24); wire.metallic = 0.6; wire.roughness = 0.5
	for i in MODELS.size():
		var mi: MeshInstance3D = (load("res://assets/animaux/%s.glb" % MODELS[i]) as PackedScene).instantiate().find_children("*", "MeshInstance3D", true, false)[0]
		var mesh: Mesh = mi.mesh
		for s in mesh.get_surface_count():
			var nm := mesh.surface_get_material(s).resource_name if mesh.surface_get_material(s) else ""
			if i < 3:
				var sm := ShaderMaterial.new()
				sm.shader = preload("res://scripts/animal.gdshader")
				sm.set_shader_parameter("species", i)
				preload("res://scripts/env.gd").add(sm)
				mesh.surface_set_material(s, sm)
			else:
				mesh.surface_set_material(s, wire if nm == "fil" else fence)
		meshes.append(mesh)

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
	return out

func update_now() -> void:
	_t = 0.0
	if target:
		for k in _wanted(target.global_position):
			_add(k)

func _process(dt: float) -> void:
	if target == null:
		return
	_t -= dt
	if _t > 0.0:
		return
	_t = 0.5
	var ws := {}
	var n := 0
	for k in _wanted(target.global_position):
		ws[k] = true
		if not loaded.has(k) and n < 1:
			_add(k); n += 1
	for k in loaded.keys():
		if not ws.has(k):
			loaded[k].queue_free()
			loaded.erase(k)

func _add(k: Vector2i) -> void:
	if loaded.has(k):
		return
	var a := FileAccess.get_file_as_bytes(tiles[k])
	var cnt := a.decode_s32(0)
	var f := a.slice(4).to_float32_array()
	var root := Node3D.new()
	var body := StaticBody3D.new()
	root.add_child(body)
	var by := {}
	for i in cnt:
		var o := i * 17
		var m := int(f[o])
		var b := Basis(Vector3(f[o + 1], f[o + 2], f[o + 3]), Vector3(f[o + 4], f[o + 5], f[o + 6]), Vector3(f[o + 7], f[o + 8], f[o + 9]))
		var xf := Transform3D(b, Vector3(f[o + 10], f[o + 11], f[o + 12]))
		if not by.has(m):
			by[m] = []
		by[m].append([xf, Color(f[o + 13], f[o + 14], f[o + 15], f[o + 16])])
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		if m == 3:
			var L := b.x.length()
			bs.size = Vector3(L, 1.3, 0.12)
			cs.transform = Transform3D(Basis(Vector3.UP, atan2(-b.x.z, b.x.x)), xf * Vector3(0.5, 0.65, 0))
		else:
			bs.size = [Vector3(0.8, 1.4, 2.4), Vector3(0.6, 0.8, 1.1), Vector3(0.7, 1.6, 2.3)][m]
			cs.transform = xf * Transform3D(Basis.IDENTITY, Vector3(0, bs.size.y / 2, 0))
		cs.shape = bs
		body.add_child(cs)
	for m in by:
		Cells.add(root, meshes[m], by[m], 380.0 if m < 3 else 300.0, m < 3)
	add_child(root)
	loaded[k] = root
