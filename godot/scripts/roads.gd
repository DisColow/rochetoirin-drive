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
	# coussins berlinois : caoutchouc / enrobé rouge
	mats["cushion"] = _mat("asphalt", 0.5, Color(0.62, 0.2, 0.16))
	# peinture routière : blanc légèrement usé, posée au-dessus de l'enrobé
	var mk := StandardMaterial3D.new()
	mk.albedo_color = Color(0.86, 0.86, 0.84)
	mk.roughness = 0.6
	mk.albedo_texture = load("res://assets/tex/asphalt_albedo.jpg")
	mk.uv1_scale = Vector3(0.3, 0.3, 1)
	mk.albedo_texture_force_srgb = false
	mk.detail_enabled = false
	mk.render_priority = 1
	mk.cull_mode = BaseMaterial3D.CULL_DISABLED
	mats["marking"] = _paint(mk)
	var sg := StandardMaterial3D.new()
	sg.albedo_texture = load("res://assets/tex/signs_atlas.png")
	sg.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	sg.alpha_scissor_threshold = 0.5
	sg.roughness = 0.45
	sg.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mats["sign"] = sg
	var sc := sg.duplicate()
	sc.albedo_texture = load("res://assets/tex/signs_city.png")
	mats["sign_city"] = sc
	var back := StandardMaterial3D.new()
	back.albedo_color = Color(0.55, 0.56, 0.58); back.metallic = 0.7; back.roughness = 0.4
	mats["sign_back"] = back
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.62, 0.63, 0.65); metal.metallic = 0.8; metal.roughness = 0.35
	mats["metal"] = metal
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.08, 0.08, 0.09); dark.roughness = 0.5
	mats["metal_dark"] = dark
	var ls := preload("res://scripts/signal_light.gdshader")
	for i in 3:
		var m := ShaderMaterial.new()
		m.shader = ls
		m.set_shader_parameter("bulb", i)
		mats[["light_red", "light_amber", "light_green"][i]] = m

func _paint(m: StandardMaterial3D) -> StandardMaterial3D:
	# l'albédo de l'enrobé sert de grain : on le blanchit (peinture usée, granulats visibles)
	m.albedo_texture = null
	return m

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
		if mi.name.begins_with("detail"):
			mi.visibility_range_end = 450.0              # panneaux et marquages : inutiles au loin
			mi.visibility_range_end_margin = 30.0
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		else:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
				if mi.name.begins_with("detail"):
					continue
				var cs := CollisionShape3D.new()
				cs.shape = mi.mesh.create_trimesh_shape()
				sb.add_child(cs)
			loaded[k].add_child(sb)
			bodies[k] = sb
		elif not need and bodies.has(k):
			bodies[k].queue_free()
			bodies.erase(k)
