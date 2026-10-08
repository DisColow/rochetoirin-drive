## Tuiles de routes (256 m) chargées en arrière-plan autour de la voiture ; collisions seulement près d'elle.
## Les surfaces portent le nom de leur matériau (asphalt, dirt, sidewalk, concrete, asphalt_bridge).
extends Node3D

const TILE := 256.0
const VIEW := 1400.0          # tuiles affichées jusqu'à cette distance (au-delà : sol coloré)
const DETAIL := 450.0          # portée des panneaux et marquages
const Cells := preload("res://scripts/cells.gd")
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
	var am := ShaderMaterial.new()
	am.shader = preload("res://scripts/asphalt.gdshader")
	preload("res://scripts/env.gd").add(am)
	am.set_shader_parameter("albedo_tex", load("res://assets/tex/asphalt_albedo.jpg"))
	am.set_shader_parameter("normal_tex", load("res://assets/tex/asphalt_normal.jpg"))
	am.set_shader_parameter("rough_tex", load("res://assets/tex/asphalt_rough.jpg"))
	mats["asphalt"] = am
	mats["asphalt_bridge"] = mats["asphalt"]
	var amw: ShaderMaterial = am.duplicate()
	preload("res://scripts/env.gd").add(amw)
	amw.set_shader_parameter("motorway", true)
	amw.set_shader_parameter("tint", Color(0.5, 0.5, 0.52))
	mats["asphalt_mw"] = amw
	mats["asphalt_mw_bridge"] = amw
	mats["dirt"] = _mat("dirt", 0.35, Color(1, 1, 1))
	mats["sidewalk"] = _mat("sidewalk", 0.5, Color(1, 1, 1))
	mats["concrete"] = _mat("concrete", 0.4, Color(0.92, 0.92, 0.9))
	# coussins berlinois : caoutchouc / enrobé rouge
	mats["cushion"] = _mat("asphalt", 0.5, Color(0.62, 0.2, 0.16))
	# peinture routière : blanc légèrement usé, posée au-dessus de l'enrobé
	var mk := ShaderMaterial.new()
	mk.shader = preload("res://scripts/ground.gdshader")
	preload("res://scripts/env.gd").add(mk)
	mk.set_shader_parameter("textured", false)
	mk.set_shader_parameter("tint", Color(0.86, 0.86, 0.84))
	mk.set_shader_parameter("rough", 0.6)
	mk.render_priority = 1
	mats["marking"] = mk
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

func _mat(name: String, scale: float, tint: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://scripts/ground.gdshader")
	preload("res://scripts/env.gd").add(m)
	m.set_shader_parameter("albedo_tex", load("res://assets/tex/%s_albedo.jpg" % name))
	m.set_shader_parameter("normal_tex", load("res://assets/tex/%s_normal.jpg" % name))
	m.set_shader_parameter("rough_tex", load("res://assets/tex/%s_rough.jpg" % name))
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("uv_scale", scale)
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
			# panneaux et marquages : inutiles au loin, effacés par tramage jusqu'à 450 m (cells.gd), puis retirés
			for s in mesh.get_surface_count():
				var sm: Material = mi.get_surface_override_material(s)
				if sm == null:
					sm = mesh.surface_get_material(s)
				if sm:
					mi.set_surface_override_material(s, Cells.material(sm, DETAIL))
			mi.visibility_range_end = DETAIL + mesh.get_aabb().size.length() * 0.5 + 10.0
			mi.visibility_range_end_margin = 10.0
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
