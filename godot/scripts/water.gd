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
# plans d'eau où la voiture coule (v6.55, #86) : tuile -> {case de 8 m -> PackedVector3Array (triangles, 3 points)} ;
# les cours d'eau (UV2 = sens du courant, non nul) n'y sont pas : on les traverse
const CASE := 8.0
const COULE := 3.2                # durée de la noyade (s), puis retour sur la route
var plans := {}
var _noyade := -1.0               # temps depuis le plongeon (-1 : rien)
var _chk := 0.0
var _xf0: Transform3D

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
			plans.erase(k)
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
	plans[k] = _grille_plans(n)

## Triangles des plans d'eau d'une tuile posée, rangés par cases de CASE m.
func _grille_plans(n: Node) -> Dictionary:
	var g := {}
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var xf := mi.global_transform
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var V: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var U2 = arr[Mesh.ARRAY_TEX_UV2]
			var I = arr[Mesh.ARRAY_INDEX]
			var nt: int = (I.size() if I != null and I.size() > 0 else V.size()) / 3
			for t in nt:
				var ia: int = I[t * 3] if I != null and I.size() > 0 else t * 3
				var ib: int = I[t * 3 + 1] if I != null and I.size() > 0 else t * 3 + 1
				var ic: int = I[t * 3 + 2] if I != null and I.size() > 0 else t * 3 + 2
				if U2 != null and U2.size() > ic and (U2[ia].length_squared() > 1e-6 or U2[ib].length_squared() > 1e-6):
					continue                              # cours d'eau
				var a := xf * V[ia]; var b := xf * V[ib]; var c := xf * V[ic]
				for cx in range(floori(minf(a.x, minf(b.x, c.x)) / CASE), floori(maxf(a.x, maxf(b.x, c.x)) / CASE) + 1):
					for cz in range(floori(minf(a.z, minf(b.z, c.z)) / CASE), floori(maxf(a.z, maxf(b.z, c.z)) / CASE) + 1):
						var kc := Vector2i(cx, cz)
						if not g.has(kc):
							g[kc] = PackedVector3Array()
						g[kc].append_array([a, b, c])
	return g

## Altitude du plan d'eau sous p (NAN hors d'un plan d'eau).
func niveau_plan(p: Vector3) -> float:
	var g: Dictionary = plans.get(Vector2i(floori(p.x / TILE), floori(p.z / TILE)), {})
	var T: PackedVector3Array = g.get(Vector2i(floori(p.x / CASE), floori(p.z / CASE)), PackedVector3Array())
	for i in range(0, T.size() - 2, 3):
		var a := T[i]; var b := T[i + 1]; var c := T[i + 2]
		var v0 := Vector2(b.x - a.x, b.z - a.z); var v1 := Vector2(c.x - a.x, c.z - a.z)
		var v2 := Vector2(p.x - a.x, p.z - a.z)
		var den := v0.x * v1.y - v1.x * v0.y
		if absf(den) < 1e-8:
			continue
		var u := (v2.x * v1.y - v1.x * v2.y) / den
		var v := (v0.x * v2.y - v2.x * v0.y) / den
		if u >= -0.01 and v >= -0.01 and u + v <= 1.02:
			return a.y + u * (b.y - a.y) + v * (c.y - a.y)
	return NAN

## La voiture qui entre dans un plan d'eau coule (#86) : gerbe, plouf, moteur coupé, elle s'enfonce en piquant du nez,
## puis réapparaît sur la route la plus proche.
func _physics_process(dt: float) -> void:
	var m := get_parent()
	var car = m.get("car") if m else null
	if car == null:
		return
	if _noyade >= 0.0:
		_noyade += dt
		var k := _noyade / COULE
		var xf := _xf0
		xf.origin.y -= 2.8 * k * k + 0.4 * k
		xf.basis = xf.basis * Basis(Vector3.RIGHT, 0.35 * k)
		car.global_transform = xf
		if _noyade >= COULE:
			_noyade = -1.0
			car.freeze = false
			car.controle = true
			car.reset_to_road()
		return
	var pd = m.get("pied")
	if car.freeze or (pd and pd.get("actif")):
		return
	_chk -= dt
	if _chk > 0.0:
		return
	_chk = 0.1
	var p: Vector3 = car.global_position
	var h := niveau_plan(p)
	if is_nan(h) or p.y > h + 0.25:
		return
	if OS.get_cmdline_user_args().has("--eau-debug"):
		print("[eau] la voiture coule en %s (eau à %.2f m, voiture à %.2f m, %d km/h)" % [p, h, p.y, int(car.kmh())])
	_noyade = 0.0
	var v: Vector3 = car.linear_velocity
	_xf0 = car.global_transform
	_xf0.origin += Vector3(v.x, 0.0, v.z).limit_length(6.0) * 0.25      # elle glisse encore un peu
	car.controle = false
	car.freeze = true
	if m.get("sound") and m.sound.has_method("_one_shot"):
		m.sound._one_shot("plouf", p, 1.8, randf_range(0.9, 1.05), 30.0, 500.0)
	var D = m.get("dust")
	if D:
		var mat: Dictionary = D.MATIERES.get("eau", {})
		if not mat.is_empty():
			for i in 24:
				var q := Vector3(p.x + randf_range(-1.6, 1.6), h + 0.1, p.z + randf_range(-2.4, 2.4))
				D._nuage(mat, q, Vector3(v.x * 0.3 + randf_range(-2, 2), randf_range(3.0, 7.0), v.z * 0.3 + randf_range(-2, 2)), 1.0)
