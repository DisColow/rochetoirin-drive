## Poteaux, pylônes, fils électriques et lampadaires (build_poles.py), en tuiles de 256 m chargées au fil de la route.
## Supports en MultiMesh (un appel de dessin par type et par tuile), fils en rubans fins qui pendent entre les supports ;
## la nuit, têtes de lampadaires lumineuses et vraies lumières sur les lampadaires les plus proches de la voiture.
extends Node3D

const TILE := 256.0
const Cells := preload("res://scripts/cells.gd")
const VIEW := 900.0
const LIGHTS := 6

var target: Node3D
var tiles := {}
var loaded := {}           # Vector2i -> Node3D
var lamps := {}            # Vector2i -> PackedVector3Array (têtes de lampadaires)
var meshes := {}           # type -> Mesh
var wire_mat: StandardMaterial3D
var head_mat: StandardMaterial3D
var night := 0.0
var pool := []
var _t := 0.0

func _ready() -> void:
	if not DirAccess.dir_exists_absolute("res://world/poles"):
		return
	for f in DirAccess.get_files_at("res://world/poles"):
		if f.ends_with(".bin"):
			var p := f.trim_prefix("p_").trim_suffix(".bin").split("_")
			tiles[Vector2i(int(p[0]), int(p[1]))] = "res://world/poles/" + f
	var grey := _m(Color(0.55, 0.56, 0.57), 0.5, 0.4)
	var wood := _m(Color(0.33, 0.24, 0.16), 0.9)
	var concrete := _m(Color(0.62, 0.61, 0.58), 0.85)
	var steel := _m(Color(0.5, 0.52, 0.53), 0.6, 0.6)
	head_mat = _m(Color(0.25, 0.26, 0.27), 0.5, 0.3)
	wire_mat = _m(Color(0.08, 0.08, 0.09), 0.6)
	wire_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	meshes[1] = _lamp(grey)
	meshes[2] = _pole(wood, 0.12, 0.1, 9.0)
	meshes[3] = _pole(concrete, 0.16, 0.1, 10.0)
	meshes[4] = _pylon(steel)
	for i in LIGHTS:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.78, 0.5)
		l.omni_range = 16.0
		l.light_energy = 2.2
		l.visible = false
		add_child(l)
		pool.append(l)

func _m(c: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c; m.roughness = rough; m.metallic = metal
	return m

# ---------------------------------------------------------------- maillages des supports (procéduraux)
func _bar(st: SurfaceTool, a: Vector3, b: Vector3, r: float) -> void:
	var ax := (b - a).normalized()
	var u := ax.cross(Vector3.UP if absf(ax.y) < 0.9 else Vector3.RIGHT).normalized() * r
	var v := ax.cross(u).normalized() * r
	var c := [u + v, u - v, -u - v, -u + v]
	for k in 4:
		var p0: Vector3 = c[k]; var p1: Vector3 = c[(k + 1) % 4]
		var n := (p0 + p1).normalized()
		for q in [a + p0, b + p0, b + p1, a + p0, b + p1, a + p1]:
			st.set_normal(n); st.add_vertex(q)

func _lamp(m: Material) -> Mesh:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_bar(st, Vector3(0, -0.3, 0), Vector3(0, 6.0, 0), 0.07)
	_bar(st, Vector3(0, 5.8, 0), Vector3(0, 6.1, -1.3), 0.04)        # crosse vers la rue (-Z local)
	var mesh := st.commit()
	mesh.surface_set_material(0, m)
	var st2 := SurfaceTool.new(); st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	_bar(st2, Vector3(0, 6.05, -1.15), Vector3(0, 6.05, -1.75), 0.12)  # tête
	st2.commit(mesh)
	mesh.surface_set_material(1, head_mat)
	return mesh

func _pole(m: Material, r0: float, r1: float, h: float) -> Mesh:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_bar(st, Vector3(0, -0.5, 0), Vector3(0, h, 0), (r0 + r1) / 2)
	_bar(st, Vector3(-0.9, h - 0.6, 0), Vector3(0.9, h - 0.6, 0), 0.05)    # traverse
	for x in [-0.7, 0.0, 0.7]:
		_bar(st, Vector3(x, h - 0.6, 0), Vector3(x, h - 0.45, 0), 0.03)     # isolateurs
	var mesh := st.commit()
	mesh.surface_set_material(0, m)
	return mesh

func _pylon(m: Material) -> Mesh:
	# pylône treillis : 4 montants qui se resserrent, entretoises en croix, deux consoles pour les conducteurs
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lv := [[0.0, 3.2], [8.0, 2.2], [16.0, 1.5], [22.0, 1.1], [30.0, 0.7]]
	for i in lv.size() - 1:
		var y0: float = lv[i][0]; var w0: float = lv[i][1]; var y1: float = lv[i + 1][0]; var w1: float = lv[i + 1][1]
		var c0 := [Vector3(w0, y0, w0), Vector3(-w0, y0, w0), Vector3(-w0, y0, -w0), Vector3(w0, y0, -w0)]
		var c1 := [Vector3(w1, y1, w1), Vector3(-w1, y1, w1), Vector3(-w1, y1, -w1), Vector3(w1, y1, -w1)]
		for k in 4:
			_bar(st, c0[k], c1[k], 0.12)
			_bar(st, c0[k], c1[(k + 1) % 4], 0.05)
			_bar(st, c0[(k + 1) % 4], c1[k], 0.05)
			_bar(st, c1[k], c1[(k + 1) % 4], 0.06)
	for y in [22.0, 27.0]:
		var w := 7.0 if y < 25.0 else 5.0
		_bar(st, Vector3(-w, y, 0.6), Vector3(w, y, 0.6), 0.1)
		_bar(st, Vector3(-w, y, -0.6), Vector3(w, y, -0.6), 0.1)
		_bar(st, Vector3(-w, y, 0), Vector3(-1.0, y + 2.0, 0), 0.06)
		_bar(st, Vector3(w, y, 0), Vector3(1.0, y + 2.0, 0), 0.06)
	var mesh := st.commit()
	mesh.surface_set_material(0, m)
	return mesh

# ---------------------------------------------------------------- tuiles
func _d(k: Vector2i, c: Vector3) -> float:
	return Vector2((k.x + 0.5) * TILE - c.x, (k.y + 0.5) * TILE - c.z).length()

func update_now() -> void:
	_t = 0.0
	if target:
		for k in _wanted(target.global_position):
			_add(k)

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

func _process(dt: float) -> void:
	if target == null:
		return
	_t -= dt
	if _t <= 0.0:
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
				lamps.erase(k)
		_night_lights()

func _add(k: Vector2i) -> void:
	if loaded.has(k):
		return
	var sp := StreamPeerBuffer.new()
	sp.data_array = FileAccess.get_file_as_bytes(tiles[k])
	var root := Node3D.new()
	var ns := sp.get_32()
	var by := {}
	var heads := PackedVector3Array()
	for i in ns:
		var t := int(sp.get_float()); var x := sp.get_float(); var y := sp.get_float(); var z := sp.get_float(); var cap := sp.get_float()
		var b := Basis(Vector3.UP, PI - deg_to_rad(cap))
		if not by.has(t):
			by[t] = []
		by[t].append(Transform3D(b, Vector3(x, y, z)))
		if t == 1:
			heads.append(Vector3(x, y + 5.9, z) + b * Vector3(0, 0, -1.45))
	for t in by:
		var l := []
		for xf in by[t]:
			l.append([xf])
		# par cases de 64 m (et non par tuile entière) ; matériaux d'origine (têtes de lampadaires allumées la nuit)
		Cells.add(root, meshes[t], l, VIEW if t == 4 else 450.0, t == 4, false)
	# fils : rubans fins croisés (visibles sous tous les angles)
	var nw := sp.get_32()
	if nw > 0:
		var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in nw:
			var n := sp.get_32()
			var prev := Vector3.ZERO
			for j in n:
				var p := Vector3(sp.get_float(), sp.get_float(), sp.get_float())
				if j > 0:
					var d := (p - prev).normalized()
					var side := d.cross(Vector3.UP).normalized() * 0.025
					var up := Vector3(0, 0.025, 0)
					for o in [side, up]:
						for q in [prev - o, p - o, p + o, prev - o, p + o, prev + o]:
							st.set_normal(Vector3.UP); st.add_vertex(q)
				prev = p
		var wm := st.commit()
		wm.surface_set_material(0, wire_mat)
		var wi := MeshInstance3D.new()
		wi.mesh = wm
		wi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wi.visibility_range_end = 500.0
		root.add_child(wi)
	add_child(root)
	loaded[k] = root
	lamps[k] = heads

## Nuit : têtes lumineuses et lumières réelles sur les lampadaires les plus proches de la voiture.
func set_night(n: float) -> void:
	night = n
	head_mat.emission_enabled = n > 0.0
	head_mat.emission = Color(1.0, 0.8, 0.5)
	head_mat.emission_energy_multiplier = 4.0 * n
	_night_lights()

func _night_lights() -> void:
	if target == null:
		return
	var c := target.global_position
	var best := []
	if night > 0.2:
		for k in lamps:
			for h: Vector3 in lamps[k]:
				var d := h.distance_squared_to(c)
				if d < 90.0 * 90.0:
					best.append([d, h])
		best.sort_custom(func(a, b): return a[0] < b[0])
	for i in pool.size():
		var l: OmniLight3D = pool[i]
		l.visible = i < best.size()
		if l.visible:
			l.global_position = best[i][1] - Vector3(0, 0.4, 0)
			l.light_energy = 2.2 * night
