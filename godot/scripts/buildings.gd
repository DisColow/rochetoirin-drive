## Bâtiments en tuiles de 256 m chargées au fil de la route (deux par image au plus) ; collisions simples près de la voiture.
extends Node3D

const TILE := 256.0
const VIEW := 1300.0
const COLL := 220.0

var target: Node3D
var tiles := {}
var loaded := {}
var pending := {}
var bodies := {}
var mat: ShaderMaterial
var _t := 0.0
# kit de détails Blender (blender_maisons.py) posé par build_buildings.py : k_tx_tz.bin, affiché près de la caméra
const KIT_MODELS := ["fenetre", "fenetre_vr", "volet", "porte", "garage", "marquise", "faitiere", "mitron", "antenne", "parabole"]
const KIT_FADE := 210.0        # détails des maisons : effacés en fondu jusqu'à cette distance (m)
const KIT_MATS := {  # surface : [type, couleur, rugosité, métal]
	"menuiserie": [0, Color(0.92, 0.92, 0.9), 0.45, 0.0], "vitrage": [2, Color(0.1, 0.12, 0.14), 0.05, 0.3],
	"couleur": [1, Color(1, 1, 1), 0.6, 0.0], "fer": [0, Color(0.08, 0.08, 0.09), 0.4, 0.5],
	"alu": [0, Color(0.75, 0.76, 0.78), 0.3, 0.6], "terre_cuite": [0, Color(0.62, 0.32, 0.2), 0.75, 0.0],
	"beton_kit": [0, Color(0.66, 0.65, 0.62), 0.85, 0.0], "blanc_kit": [0, Color(0.93, 0.93, 0.91), 0.5, 0.0]}
var kit_meshes := []
var kit_mats := []

func _ready() -> void:
	for f in DirAccess.get_files_at("res://world/buildings"):
		f = f.trim_suffix(".import").trim_suffix(".remap")
		if not f.ends_with(".glb"):
			continue
		var p := f.trim_prefix("b_").trim_suffix(".glb").split("_")
		tiles[Vector2i(int(p[0]), int(p[1]))] = "res://world/buildings/" + f
	mat = ShaderMaterial.new()
	mat.shader = preload("res://scripts/building.gdshader")
	preload("res://scripts/env.gd").add(mat)
	mat.set_shader_parameter("albedo_tex", load("res://assets/bld/albedo.png"))
	mat.set_shader_parameter("normal_tex", load("res://assets/bld/normal.png"))
	if ResourceLoader.exists("res://assets/maisons/fenetre.glb"):
		var cache := {}
		for n in KIT_MODELS:
			var sc: Node = (load("res://assets/maisons/%s.glb" % n) as PackedScene).instantiate()
			var mesh: Mesh = (sc.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh
			sc.free()
			for s in mesh.get_surface_count():
				var mt := mesh.surface_get_material(s)
				var nm := mt.resource_name if mt else ""
				if not KIT_MATS.has(nm):
					continue
				if not cache.has(nm):
					var d: Array = KIT_MATS[nm]
					var sm := ShaderMaterial.new()
					sm.shader = preload("res://scripts/maison_kit.gdshader")
					sm.set_shader_parameter("kind", d[0]); sm.set_shader_parameter("albedo", d[1])
					sm.set_shader_parameter("rough", d[2]); sm.set_shader_parameter("metal", d[3])
					preload("res://scripts/env.gd").add(sm)
					preload("res://scripts/env.gd").fade(sm, KIT_FADE)
					kit_mats.append(sm)
					cache[nm] = sm
				mesh.surface_set_material(s, cache[nm])
			kit_meshes.append(mesh)

## Nuit : fenêtres du kit éclairées comme celles des façades.
func set_kit_night(v: float) -> void:
	for m in kit_mats:
		m.set_shader_parameter("night", v)

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
	var kf := "res://world/buildings/k_%d_%d.bin" % [k.x, k.y]
	if not kit_meshes.is_empty() and FileAccess.file_exists(kf):
		var a := FileAccess.get_file_as_bytes(kf)
		var cnt := a.decode_s32(0)
		var f := a.slice(4).to_float32_array()
		var by := {}
		const CELLK := 48.0
		for i in cnt:
			var o := i * 17
			var m := int(f[o])
			var cx := floori(f[o + 10] / CELLK); var cz := floori(f[o + 12] / CELLK)
			var key := Vector3i(m, cx, cz)
			if not by.has(key):
				by[key] = []
			var ox := (cx + 0.5) * CELLK; var oz := (cz + 0.5) * CELLK
			# base en colonnes (X, Y, Z) + origine (relative à la case) -> tampon MultiMesh (lignes) + couleur
			(by[key] as Array).append_array([f[o + 1], f[o + 4], f[o + 7], f[o + 10] - ox, f[o + 2], f[o + 5], f[o + 8], f[o + 11],
				f[o + 3], f[o + 6], f[o + 9], f[o + 12] - oz, f[o + 13], f[o + 14], f[o + 15], 1.0])
		for key in by:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.mesh = kit_meshes[key.x]
			var buf := PackedFloat32Array(by[key])
			mm.instance_count = buf.size() / 16
			mm.buffer = buf
			var mi := MultiMeshInstance3D.new()
			mi.multimesh = mm
			mi.position = Vector3((key.y + 0.5) * CELLK, 0, (key.z + 0.5) * CELLK)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			# détails effacés par tramage jusqu'à KIT_FADE (maison_kit.gdshader), case retirée une fois invisible
			mi.visibility_range_end = KIT_FADE + CELLK * 0.75 + 6.0
			mi.visibility_range_end_margin = 10.0
			n.add_child(mi)
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
				var sh: ConcavePolygonShape3D = mi.mesh.create_trimesh_shape()
				sh.backface_collision = true            # murs sans épaisseur : on bute dessus des deux côtés
				cs.shape = sh
				sb.add_child(cs)
			loaded[k].add_child(sb)
			bodies[k] = sb
		elif not need and bodies.has(k):
			bodies[k].queue_free()
			bodies.erase(k)
