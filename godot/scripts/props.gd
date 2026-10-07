## Vie des villages (build_props.py) : voitures garées dans les cours, poubelles, tracteurs ; tuiles de 256 m chargées au
## fil de la route, un MultiMesh par modèle et par tuile (couleur de carrosserie par instance), collisions en boîtes.
extends Node3D

const TILE := 256.0
const VIEW := 520.0
const MODELS := {1: "car1", 2: "car2", 3: "car3", 4: "car4", 5: "tractor", 6: "bin"}
const BOXES := {1: Vector3(1.62, 1.4, 3.72), 2: Vector3(1.7, 1.43, 4.1), 3: Vector3(1.75, 1.46, 4.6),
	4: Vector3(1.68, 1.8, 4.0), 5: Vector3(2.2, 2.7, 4.2), 6: Vector3(0.6, 1.05, 0.75)}

var target: Node3D
var tiles := {}
var loaded := {}
var meshes := {}
var _t := 0.0

func _ready() -> void:
	if not DirAccess.dir_exists_absolute("res://world/props"):
		return
	for f in DirAccess.get_files_at("res://world/props"):
		if f.ends_with(".bin"):
			var p := f.trim_prefix("pp_").trim_suffix(".bin").split("_")
			tiles[Vector2i(int(p[0]), int(p[1]))] = "res://world/props/" + f
	var paint := ShaderMaterial.new()
	paint.shader = preload("res://scripts/paint.gdshader")
	var mats := {
		"paint": paint,
		"glass": _m(Color(0.05, 0.06, 0.07), 0.05, 0.3),
		"plastic": _m(Color(0.06, 0.06, 0.065), 0.6),
		"rubber": _m(Color(0.03, 0.03, 0.035), 0.9),
		"hubcap": _m(Color(0.7, 0.71, 0.73), 0.35, 0.5),
		"rim": _m(Color(0.8, 0.72, 0.15), 0.5),
		"lamp": _m(Color(0.85, 0.88, 0.9), 0.1, 0.5),
		"tail": _m(Color(0.65, 0.04, 0.04), 0.25),
		"plate": _m(Color(0.92, 0.92, 0.9), 0.4),
		"lid": _m(Color(0.88, 0.72, 0.1), 0.6),
	}
	for t in MODELS:
		var sc: PackedScene = load("res://assets/props/%s.glb" % MODELS[t])
		var mi: MeshInstance3D = sc.instantiate().find_children("*", "MeshInstance3D", true, false)[0]
		var mesh: Mesh = mi.mesh
		for s in mesh.get_surface_count():
			var m := mesh.surface_get_material(s)
			var nm := m.resource_name if m else ""
			if mats.has(nm):
				mesh.surface_set_material(s, mats[nm])
		meshes[t] = mesh

func _m(c: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c; m.roughness = rough; m.metallic = metal
	return m

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
		if not loaded.has(k) and n < 2:
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
		var o := i * 8
		var t := int(f[o])
		var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(f[o + 4])), Vector3(f[o + 1], f[o + 2], f[o + 3]))
		if not by.has(t):
			by[t] = []
		by[t].append([xf, Color(f[o + 5], f[o + 6], f[o + 7])])
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = BOXES[t]
		cs.shape = bs
		cs.transform = xf * Transform3D(Basis.IDENTITY, Vector3(0, BOXES[t].y / 2, 0))
		body.add_child(cs)
	for t in by:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = meshes[t]
		mm.instance_count = by[t].size()
		for i in by[t].size():
			mm.set_instance_transform(i, by[t][i][0])
			mm.set_instance_custom_data(i, by[t][i][1])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mi.visibility_range_end = 420.0 if t != 6 else 160.0
		root.add_child(mi)
	add_child(root)
	loaded[k] = root
