## Champs cultivés en 3D (parcelles RPG 2024), refaits en v6.39 (#142, issue #25 : « plante juste les sprites ») : de
## près, un sprite par plant (deux plans croisés, atlas des plants tools/bake_cultures.gd -- --seulement=plants) planté
## sur la grille du champ, sur un sol de terre à sillons ; fondu au loin, puis l'orthophoto (vue d'ensemble du champ).
## Cases de 32 m générées autour de la voiture (une par image au plus). Un plant touché par la voiture éclate.
extends Node3D
const Relief := preload("res://scripts/relief.gd")
const PerfMon := preload("res://scripts/perf_monitor.gd")

const TILE := 256.0
const CELL := 32.0
# par culture (maïs, céréales, colza, tournesol) : écartement des rangs, des pieds sur le rang (m), hauteur de la case
# du sprite (m, cf. bake_cultures.gd PLANTS)
const ROWS := [0.75, 0.32, 0.42, 0.75]
const STEP := [0.22, 0.30, 0.38, 0.34]
const HCASE := [3.0, 1.2, 1.4, 2.4]
const RANGE := [20.0, 35.0, 50.0, 60.0]        # portée des plants selon le réglage (Économie … Ultra)

var target: Node3D
var terrain: Node
var level := 2
var fields := {}          # tuile -> [[type, dir Vector2, PackedVector2Array, Rect2]]
var cells := {}           # case -> Node3D (ou null si vide)
var mat: ShaderMaterial   # plants
var mat_sol: ShaderMaterial
var cross: ArrayMesh
var _t := 0.0
var pending := 0         # cases encore à construire (essais : attendre que tout soit planté)
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	mat = ShaderMaterial.new()
	mat.shader = preload("res://scripts/crops_plants.gdshader")
	preload("res://scripts/env.gd").add(mat)
	preload("res://scripts/env.gd").fade(mat, RANGE[level])
	mat.set_shader_parameter("plants_atlas", load("res://assets/veg/plants_albedo.png"))
	mat_sol = ShaderMaterial.new()
	mat_sol.shader = preload("res://scripts/crops_sol.gdshader")
	preload("res://scripts/env.gd").add(mat_sol)
	preload("res://scripts/env.gd").fade(mat_sol, RANGE[level] + 15.0)
	mat_sol.set_shader_parameter("dirt", load("res://assets/tex/dirt_albedo.jpg"))
	# deux plans croisés de 1 × 1 (pied en 0), UV.y = 0 en haut
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ax in [Vector3(1, 0, 0), Vector3(0, 0, 1)]:
		var n := Vector3(-ax.z, 0, ax.x)
		var q := [[-0.5, 0.0, 0.0, 1.0], [0.5, 0.0, 1.0, 1.0], [0.5, 1.0, 1.0, 0.0], [-0.5, 1.0, 0.0, 0.0]]
		for i in [0, 1, 2, 0, 2, 3]:
			st.set_normal(n)
			st.set_uv(Vector2(q[i][2], q[i][3]))
			st.add_vertex(ax * q[i][0] + Vector3(0, q[i][1], 0))
	cross = st.commit()

func set_level(l: int) -> void:
	level = l
	if mat:
		mat.set_shader_parameter("fade_far", RANGE[level])
		mat_sol.set_shader_parameter("fade_far", RANGE[level] + 15.0)
	for k in cells.keys():
		if cells[k]:
			cells[k].queue_free()
	cells.clear()

func _tile_fields(k: Vector2i) -> Array:
	if fields.has(k):
		return fields[k]
	var out := []
	var path := "res://world/crops/c_%d_%d.bin" % [k.x, k.y]
	if FileAccess.file_exists(path):
		var sp := StreamPeerBuffer.new()
		sp.data_array = FileAccess.get_file_as_bytes(path)
		var n := sp.get_32()
		for i in n:
			var t := sp.get_32()
			var d := Vector2(sp.get_float(), sp.get_float())
			var m := sp.get_32()
			var pts := PackedVector2Array(); pts.resize(m)
			var r := Rect2()
			for j in m:
				pts[j] = Vector2(sp.get_float(), sp.get_float())
				r = Rect2(pts[j], Vector2.ZERO) if j == 0 else r.expand(pts[j])
			# sommets en double (fréquents dans les parcelles RPG) : intersect_polygons ne rendrait qu'un morceau du champ
			var net := PackedVector2Array()
			for q in pts:
				if net.is_empty() or q.distance_squared_to(net[net.size() - 1]) > 0.0025:
					net.append(q)
			if net.size() > 3 and net[0].distance_squared_to(net[net.size() - 1]) <= 0.0025:
				net.resize(net.size() - 1)
			if net.size() >= 3:
				out.append([t, d, net, r])
	fields[k] = out
	return out

## Type de culture sous un point (x, z), -1 hors des champs (trample.gd : la trace n'est peinte que dans les champs).
func field_at(p: Vector2) -> int:
	for f in _tile_fields(Vector2i(floori(p.x / TILE), floori(p.y / TILE))):
		if (f[3] as Rect2).grow(0.01).has_point(p) and Geometry2D.is_point_in_polygon(p, f[2]):
			return f[0]
	return -1

func _process(dt: float) -> void:
	var t0_perf := Time.get_ticks_usec()
	_process_corps(dt)
	PerfMon.note("crops", Time.get_ticks_usec() - t0_perf)

func _process_corps(dt: float) -> void:
	if target == null or terrain == null:
		return
	_t -= dt
	var c := target.global_position
	var rng_m: float = RANGE[level] + 15.0
	var kc := Vector2i(floori(c.x / CELL), floori(c.z / CELL))
	var r := int(ceil(rng_m / CELL))
	# cases à garder / à créer (deux créations par image au plus)
	var made := 0
	var keep := {}
	var todo := []
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			var k := kc + Vector2i(dx, dz)
			var cc := Vector2((k.x + 0.5) * CELL - c.x, (k.y + 0.5) * CELL - c.z)
			if cc.length() > rng_m + CELL * 0.71:
				continue
			keep[k] = true
			if not cells.has(k):
				todo.append([cc.length(), k])
	todo.sort_custom(func(a, b): return a[0] < b[0])
	pending = maxi(todo.size() - 1, 0)
	for it in todo:
		_build(it[1])
		made += 1
		if made >= 1:
			break
	if _t <= 0.0:
		_t = 0.5
		for k in cells.keys():
			if not keep.has(k):
				if cells[k]:
					cells[k].queue_free()
				cells.erase(k)

func _build(k: Vector2i) -> void:
	var x0 := k.x * CELL; var z0 := k.y * CELL
	var rect := Rect2(x0, z0, CELL, CELL)
	var cellpoly := PackedVector2Array([Vector2(x0, z0), Vector2(x0 + CELL, z0), Vector2(x0 + CELL, z0 + CELL), Vector2(x0, z0 + CELL)])
	var tk := Vector2i(floori(x0 / TILE), floori(z0 / TILE))
	var root := Node3D.new()
	_rng.seed = hash(k)
	var hg := PackedFloat32Array()            # relief de la case (grille de 4 m, interpolée pour chaque plant)
	for gz in 9:
		for gx in 9:
			var y: float = Relief.hauteur(Vector3(x0 + gx * 4.0, 0, z0 + gz * 4.0))
			hg.append(NAN if is_nan(y) else y)
	var buf := PackedFloat32Array()
	var count := 0
	for f in _tile_fields(tk):
		if not f[3].intersects(rect):
			continue
		var t: int = f[0]
		var part := _plants(f, t, cellpoly, hg, x0, z0)
		buf.append_array(part)
		count += part.size() / 16
		var sol := _sol(f, t, cellpoly)
		if sol:
			root.add_child(sol)
	if count > 0:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = cross
		mm.instance_count = count
		mm.buffer = buf
		var node := MultiMeshInstance3D.new()
		node.multimesh = mm
		node.material_override = mat
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(node)
	if root.get_child_count() == 0:
		root.free()
		cells[k] = null
		return
	add_child(root)
	cells[k] = root

func _h(hg: PackedFloat32Array, x0: float, z0: float, p: Vector2) -> float:
	var u := clampf((p.x - x0) / 4.0, 0.0, 7.999); var v := clampf((p.y - z0) / 4.0, 0.0, 7.999)
	var i := int(u); var j := int(v); var fu := u - i; var fv := v - j
	var a := hg[j * 9 + i]; var b := hg[j * 9 + i + 1]; var c := hg[j * 9 + 9 + i]; var d := hg[j * 9 + 9 + i + 1]
	return lerpf(lerpf(a, b, fu), lerpf(c, d, fu), fv)

## Plants d'une parcelle dans une case : rangs parallèles à d (grille commune à tout le champ), un pied tous les
## STEP[t] m, un peu décalés ; données d'instance : culture, variante, teinte, hauteur de la case.
func _plants(f: Array, t: int, cellpoly: PackedVector2Array, hg: PackedFloat32Array, x0: float, z0: float) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	var d: Vector2 = f[1]
	var nrm := Vector2(-d.y, d.x)
	var sp: float = ROWS[t]; var st: float = STEP[t]; var hc: float = HCASE[t]
	var tmin := INF; var tmax := -INF; var smin := INF; var smax := -INF
	for p in cellpoly:
		tmin = minf(tmin, p.dot(nrm)); tmax = maxf(tmax, p.dot(nrm))
		smin = minf(smin, p.dot(d)); smax = maxf(smax, p.dot(d))
	var jit := 0.25 if t == 0 or t == 3 else 0.45          # céréales et colza : rangs moins nets (touffes)
	for poly in Geometry2D.intersect_polygons(f[2], cellpoly):
		for kk in range(ceili(tmin / sp), floori(tmax / sp) + 1):
			var off := kk * sp
			var line := PackedVector2Array([nrm * off + d * (smin - 1.0), nrm * off + d * (smax + 1.0)])
			for seg in Geometry2D.intersect_polyline_with_polygon(line, poly):
				var a: Vector2 = seg[0]; var b: Vector2 = seg[seg.size() - 1]
				var s1 := maxf(a.dot(d), b.dot(d))
				var s := ceilf(minf(a.dot(d), b.dot(d)) / st) * st
				while s <= s1:
					var q := nrm * off + d * s + nrm * _rng.randf_range(-jit, jit) * sp + d * _rng.randf_range(-0.3, 0.3) * st
					s += st
					var y := _h(hg, x0, z0, q)
					if is_nan(y):
						continue
					var sc := hc * _rng.randf_range(0.9, 1.08)
					var w := sc * 0.5
					var ang := _rng.randf() * TAU
					var bx := Vector3(cos(ang), 0, sin(ang)) * w
					var bz := Vector3(-sin(ang), 0, cos(ang)) * w
					buf.append_array([bx.x, 0.0, bz.x, q.x, bx.y, sc, bz.y, y - 0.04, bx.z, 0.0, bz.z, q.y,
						float(t), float(_rng.randi_range(0, 7)), _rng.randf_range(0.76, 0.94), sc])
	return buf

## Sol de terre d'une parcelle dans une case : découpé au contour, posé sur le relief par carrés de 4 m (+3 cm).
func _sol(f: Array, t: int, cellpoly: PackedVector2Array) -> MultiMeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 0
	var Q := 4.0
	for poly in Geometry2D.intersect_polygons(f[2], cellpoly):
		var r := Rect2(poly[0], Vector2.ZERO)
		for p in poly:
			r = r.expand(p)
		for gx in range(floori(r.position.x / Q), ceili(r.end.x / Q)):
			for gz in range(floori(r.position.y / Q), ceili(r.end.y / Q)):
				var sq := PackedVector2Array([Vector2(gx * Q, gz * Q), Vector2(gx * Q + Q, gz * Q), Vector2(gx * Q + Q, gz * Q + Q), Vector2(gx * Q, gz * Q + Q)])
				for piece in Geometry2D.intersect_polygons(sq, poly):
					if Geometry2D.is_polygon_clockwise(piece):
						piece.reverse()
					var hs := []
					for v in piece:
						var y: float = Relief.hauteur(Vector3(v.x, 0, v.y))
						hs.append(0.0 if is_nan(y) else y + 0.03)
					for i in range(1, piece.size() - 1):
						for j in [0, i, i + 1]:              # sens des faces vues du dessus (sinon normale retournée)
							var v: Vector2 = piece[j]
							st.set_normal(Vector3.UP)
							st.add_vertex(Vector3(v.x, hs[j], v.y))
							n += 1
	if n == 0:
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = st.commit()
	mm.instance_count = 1
	mm.set_instance_transform(0, Transform3D.IDENTITY)
	var d: Vector2 = f[1]
	mm.set_instance_custom_data(0, Color(d.x, d.y, ROWS[t], 0.0))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat_sol
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
