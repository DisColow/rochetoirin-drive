## Bâtiments en tuiles de 256 m chargées au fil de la route (deux par image au plus) ; collisions simples près de la voiture.
extends Node3D
const PerfMon := preload("res://scripts/perf_monitor.gd")

const TILE := 256.0
var VIEW := 1300.0
const COLL := 220.0

var target: Node3D
var tiles := {}
var loaded := {}
var _chargeur = preload("res://scripts/chargeur.gd").new()
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
	preload("res://scripts/env.gd").phares_sur(mat)
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
	_collisions(true)

func _process(dt: float) -> void:
	var t0_perf := Time.get_ticks_usec()
	_process_corps(dt)
	PerfMon.note("buildings", Time.get_ticks_usec() - t0_perf)

func _process_corps(dt: float) -> void:
	if target == null:
		return
	# tuiles lues en arrière-plan (scripts/chargeur.gd), posées une par image au plus (pas d'à-coup)
	if _tache >= 0 and WorkerThreadPool.is_task_completed(_tache):
		WorkerThreadPool.wait_for_task_completion(_tache)
		_tache = -1
		if pending.has(_tache_k) and _scenes.has(_tache_k) and not loaded.has(_tache_k):
			_add(_tache_k, _scenes[_tache_k], _tache_res)
			pending.erase(_tache_k)
		_scenes.erase(_tache_k)
		_tache_res = {}
	elif _tache < 0:
		for k in pending.keys():
			if loaded.has(k):
				pending.erase(k)
				continue
			var sc := _chargeur.pret(tiles[k]) as PackedScene
			if sc != null:
				if kit_meshes.is_empty():
					_add(k, sc)
					pending.erase(k)
				else:
					_scenes[k] = sc
					_tache_k = k
					var kk: Vector2i = k
					_tache = WorkerThreadPool.add_task(func(): _tache_res = _kit(kk))
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
	var vp := {}
	for k in pending:
		vp[tiles[k]] = true
	_chargeur.menage(vp)
	for k in loaded.keys():
		if not ws.has(k):
			loaded[k].queue_free()
			loaded.erase(k)
			bodies.erase(k)
	_collisions()

## Détails des maisons d'une tuile (k_*.bin) en tampons MultiMesh par [modèle, case de 48 m] : calcul pur, sur un fil
## de travail en roulant (#174 : fait sur le fil principal, la boucle sur des milliers de détails faisait des à-coups).
func _kit(k: Vector2i) -> Dictionary:
	var kf := "res://world/buildings/k_%d_%d.bin" % [k.x, k.y]
	var by := {}
	if not FileAccess.file_exists(kf):
		return by
	var a := FileAccess.get_file_as_bytes(kf)
	var cnt := a.decode_s32(0)
	var f := a.slice(4).to_float32_array()
	const CELLK := 48.0
	var listes := {}
	for i in cnt:
		var o := i * 17
		var m := int(f[o])
		var cx := floori(f[o + 10] / CELLK); var cz := floori(f[o + 12] / CELLK)
		var key := Vector3i(m, cx, cz)
		if not listes.has(key):
			listes[key] = PackedFloat32Array()
		var ox := (cx + 0.5) * CELLK; var oz := (cz + 0.5) * CELLK
		# base en colonnes (X, Y, Z) + origine (relative à la case) -> tampon MultiMesh (lignes) + couleur
		var l: PackedFloat32Array = listes[key]
		l.append_array(PackedFloat32Array([f[o + 1], f[o + 4], f[o + 7], f[o + 10] - ox, f[o + 2], f[o + 5], f[o + 8], f[o + 11],
			f[o + 3], f[o + 6], f[o + 9], f[o + 12] - oz, f[o + 13], f[o + 14], f[o + 15], 1.0]))
		listes[key] = l
	return listes

var _tache := -1                 # décodage des détails sur un fil de travail
var _tache_k := Vector2i.ZERO
var _tache_res := {}
var _scenes := {}                # Vector2i -> PackedScene lue, en attente de ses détails

func _exit_tree() -> void:
	if _tache >= 0:
		WorkerThreadPool.wait_for_task_completion(_tache)
		_tache = -1

func _add(k: Vector2i, sc: PackedScene = null, kit = null) -> void:
	if loaded.has(k):
		return
	if sc == null:
		sc = load(tiles[k])
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
	const CELLK := 48.0
	if not kit_meshes.is_empty():
		var by: Dictionary = kit if kit != null else _kit(k)
		for key in by:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.mesh = kit_meshes[key.x]
			var buf: PackedFloat32Array = by[key]
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

func _collisions(tout := false) -> void:
	var p := target.global_position
	for k in loaded.keys():
		var need := _d(k, p) < COLL + TILE * 0.71
		if need and not bodies.has(k):
			# collisions en boîtes (v6.19 : BoxShape3D seulement, plus de maillage concave) : c_tx_tz.bin de
			# build_buildings.py, 7 flottants par boîte (centre, demi-tailles, lacet)
			var sb := StaticBody3D.new()
			var cp: String = tiles[k].get_base_dir() + "/c_" + tiles[k].get_file().trim_prefix("b_").trim_suffix(".glb") + ".bin"
			var b := FileAccess.get_file_as_bytes(cp).to_float32_array() if FileAccess.file_exists(cp) else PackedFloat32Array()
			for i in range(0, b.size() - 6, 7):
				var cs := CollisionShape3D.new()
				var sh := BoxShape3D.new()
				sh.size = Vector3(b[i + 3], b[i + 4], b[i + 5]) * 2.0
				cs.shape = sh
				cs.transform = Transform3D(Basis(Vector3.UP, b[i + 6]), Vector3(b[i], b[i + 1], b[i + 2]))
				sb.add_child(cs)
			loaded[k].add_child(sb)
			bodies[k] = sb
			if not tout:
				return                   # une tuile par passage (0,25 s) : pas d'à-coup quand plusieurs arrivent (#174)
		elif not need and bodies.has(k):
			bodies[k].queue_free()
			bodies.erase(k)
