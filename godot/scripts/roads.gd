## Tuiles de routes (256 m) chargées en arrière-plan autour de la voiture ; collisions seulement près d'elle.
## Les surfaces portent le nom de leur matériau (asphalt, dirt, sidewalk, concrete, asphalt_bridge).
extends Node3D

const TILE := 256.0
const VIEW := 2200.0          # tuiles affichées jusqu'à cette distance
const COLL := 320.0           # collisions jusqu'à cette distance

var target: Node3D
var tiles := {}               # Vector2i -> chemin
var loaded := {}              # Vector2i -> Node3D
var pending := {}             # Vector2i -> chemin en cours de chargement
var bodies := {}              # Vector2i -> StaticBody3D
var mats := {}
var _t := 0.0

func _ready() -> void:
	for f in DirAccess.get_files_at("res://world/roads"):
		f = f.trim_suffix(".import").trim_suffix(".remap")
		if not f.ends_with(".glb"):
			continue
		var p := f.trim_prefix("t_").trim_suffix(".glb").split("_")
		tiles[Vector2i(int(p[0]), int(p[1]))] = "res://world/roads/" + f
	mats["asphalt"] = _mat("asphalt", 0.30, Color(0.82, 0.82, 0.82))
	mats["asphalt_bridge"] = mats["asphalt"]
	mats["dirt"] = _mat("dirt", 0.35, Color(1, 1, 1))
	mats["sidewalk"] = _mat("sidewalk", 0.5, Color(1, 1, 1))
	mats["concrete"] = _mat("concrete", 0.4, Color(0.92, 0.92, 0.9))

func _mat(name: String, scale: float, tint: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/tex/%s_albedo.jpg" % name)
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = load("res://assets/tex/%s_normal.jpg" % name)
	m.normal_scale = 1.0
	m.roughness_texture = load("res://assets/tex/%s_rough.jpg" % name)
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.uv1_scale = Vector3(scale, scale, 1.0)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m

func _key(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / TILE), floori(p.z / TILE))

func _wanted(center: Vector3) -> Array:
	var out := []
	var r := int(ceil(VIEW / TILE))
	var c := _key(center)
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			var k := c + Vector2i(dx, dz)
			if tiles.has(k) and Vector2((k.x + 0.5) * TILE - center.x, (k.y + 0.5) * TILE - center.z).length() < VIEW + TILE:
				out.append(k)
	return out

## Chargement immédiat (démarrage) des tuiles proches : pas de route manquante sous la voiture.
func update_now() -> void:
	if target == null:
		return
	for k in _wanted(target.global_position):
		if Vector2((k.x + 0.5) * TILE - target.global_position.x, (k.y + 0.5) * TILE - target.global_position.z).length() < 600.0:
			_add(k, load(tiles[k]))
	_update_collisions()

func _process(dt: float) -> void:
	if target == null:
		return
	# chargements étalés : deux tuiles par image au plus (pas d'à-coup)
	var n := 0
	for k in pending.keys():
		_add(k, load(pending[k]))
		pending.erase(k)
		n += 1
		if n >= 2:
			break
	_t -= dt
	if _t > 0:
		return
	_t = 0.25
	var want := _wanted(target.global_position)
	var ws := {}
	var c := target.global_position
	want.sort_custom(func(a, b): return Vector2((a.x + 0.5) * TILE - c.x, (a.y + 0.5) * TILE - c.z).length() < Vector2((b.x + 0.5) * TILE - c.x, (b.y + 0.5) * TILE - c.z).length())
	for k in want:
		ws[k] = true
		if not loaded.has(k) and not pending.has(k):
			pending[k] = tiles[k]
	for k in pending.keys():
		if not ws.has(k):
			pending.erase(k)
	for k in loaded.keys():
		if not ws.has(k):
			loaded[k].queue_free()
			loaded.erase(k)
			if bodies.has(k):
				bodies.erase(k)
	_update_collisions()

func _add(k: Vector2i, sc: PackedScene) -> void:
	if sc == null or loaded.has(k):
		return
	var n := sc.instantiate()
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = mi.mesh
		for s in mesh.get_surface_count():
			var mn := mesh.surface_get_material(s).resource_name if mesh.surface_get_material(s) else ""
			if mats.has(mn):
				mi.set_surface_override_material(s, mats[mn])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if mesh.get_surface_count() == 1 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(n)
	loaded[k] = n

func _update_collisions() -> void:
	var p := target.global_position
	for k in loaded.keys():
		var d := Vector2((k.x + 0.5) * TILE - p.x, (k.y + 0.5) * TILE - p.z).length()
		var need := d < COLL + TILE * 0.71
		if need and not bodies.has(k):
			var sb := StaticBody3D.new()
			for mi in loaded[k].find_children("*", "MeshInstance3D", true, false):
				var cs := CollisionShape3D.new()
				cs.shape = mi.mesh.create_trimesh_shape()
				sb.add_child(cs)
			loaded[k].add_child(sb)
			bodies[k] = sb
		elif not need and bodies.has(k):
			bodies[k].queue_free()
			bodies.erase(k)
