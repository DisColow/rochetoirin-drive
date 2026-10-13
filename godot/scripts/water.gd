## Eau (build_water.py) : étangs, rivières, ruisseaux en tuiles de 256 m chargées au fil de la route.
extends Node3D
const PerfMon := preload("res://scripts/perf_monitor.gd")

const TILE := 256.0
const VIEW := 1500.0

var target: Node3D
var tiles := {}
var loaded := {}
var pending := {}
var mat: ShaderMaterial
var _chargeur = preload("res://scripts/chargeur.gd").new()   # v6.19 : tuiles lues en arrière-plan
var _t := 0.0

func _ready() -> void:
	if not DirAccess.dir_exists_absolute("res://world/water"):
		return
	for f in DirAccess.get_files_at("res://world/water"):
		f = f.trim_suffix(".import").trim_suffix(".remap")
		if not f.ends_with(".glb"):
			continue
		var p := f.trim_prefix("w_").trim_suffix(".glb").split("_")
		tiles[Vector2i(int(p[0]), int(p[1]))] = "res://world/water/" + f
	mat = ShaderMaterial.new()
	mat.shader = preload("res://scripts/water.gdshader")
	preload("res://scripts/env.gd").add(mat)

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

func _process(dt: float) -> void:
	var t0_perf := Time.get_ticks_usec()
	_process_corps(dt)
	PerfMon.note("water", Time.get_ticks_usec() - t0_perf)

func _process_corps(dt: float) -> void:
	if target == null:
		return
	# une tuile posée par image au plus, dès que sa lecture en arrière-plan est finie
	for k in pending.keys():
		var sc := _chargeur.pret(tiles[k]) as PackedScene
		if sc != null:
			_poser(k, sc)
			pending.erase(k)
			break
	_t -= dt
	if _t > 0:
		return
	_t = 0.5
	var ws := {}
	for k in _wanted(target.global_position):
		ws[k] = true
		if not loaded.has(k):
			pending[k] = true
	for k in pending.keys():
		if not ws.has(k):
			pending.erase(k)
	for k in loaded.keys():
		if not ws.has(k):
			loaded[k].queue_free()
			loaded.erase(k)
	var vp := {}
	for k in pending.keys():
		vp[tiles[k]] = true
	_chargeur.menage(vp)

## Pose immédiate (update_now, au démarrage et après une téléportation) : lecture directe.
func _add(k: Vector2i) -> void:
	if loaded.has(k):
		return
	_poser(k, load(tiles[k]))

func _poser(k: Vector2i, sc: PackedScene) -> void:
	if sc == null or loaded.has(k):
		return
	var n := sc.instantiate()
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = VIEW
		mi.visibility_range_end_margin = 100.0
	add_child(n)
	loaded[k] = n
