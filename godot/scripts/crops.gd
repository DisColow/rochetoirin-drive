## Champs cultivés en 3D (parcelles RPG 2024) : de près, des touffes façon GTA San Andreas (v6.50, issue #61 : un
## sprite par plant, jusqu'à 10 par m², faisait trop ramer) : deux plans croisés montrant chacun une bande de champ de
## LARGEUR m (plusieurs plants sur trois profondeurs : atlas touffes_albedo.png de pipeline/build_touffes.py), l'un le
## long des rangs, l'autre en travers, posés tous les PAS m sur un rang sur RANG_K ; 10 à 20 fois moins de plans. Sol de
## terre à sillons dessous ; fondu au loin, puis l'orthophoto (vue d'ensemble du champ).
## Cases de 32 m générées autour de la voiture sur un fil de calcul (une à la fois), plants plus clairsemés au loin
## (v6.45, issue #25). Un plant touché par la voiture éclate.
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
const RANGE := [80.0, 105.0, 130.0, 160.0]     # portée (v6.55 : bien plus loin, #81) des plants selon le réglage (Économie … Ultra)
# touffes (#61) : largeur d'une touffe (m, build_touffes.py), touffes sur un rang sur RANG_K, une tous les PAS m
const LARGEUR := 2.4
const RANG_K := [2, 4, 3, 2]
const PAS := [1.2, 1.4, 1.4, 1.2]

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
# construction des cases sur un fil de calcul (issue #25 : « ça rame dans une plantation ») : le fil principal ne lit
# que le relief (81 points par case) puis pose les maillages déjà calculés
# tâches WorkerThreadPool en cours (v6.56, #81 : trois en parallèle, une seule avant : avec la portée allongée, les
# cases lointaines n'avaient pas le temps d'apparaître) : [id, case, résultat rempli par le fil :
# {r: [buffer des plants, nombre, [[sommets du sol, custom]]]}]
const TACHES := 3
var _taches: Array = []
var _lod_t := 0.0

func _ready() -> void:
	mat = ShaderMaterial.new()
	mat.shader = preload("res://scripts/crops_plants.gdshader")
	preload("res://scripts/env.gd").add(mat)
	preload("res://scripts/env.gd").fade(mat, RANGE[level])
	mat.set_shader_parameter("plants_atlas", load("res://assets/veg/touffes_albedo.png"))
	mat_sol = ShaderMaterial.new()
	mat_sol.shader = preload("res://scripts/crops_sol.gdshader")
	preload("res://scripts/env.gd").add(mat_sol)
	preload("res://scripts/env.gd").phares_sur(mat_sol)
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

func _exit_tree() -> void:
	for tc in _taches:
		WorkerThreadPool.wait_for_task_completion(tc[0])
	_taches.clear()

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
	pending = todo.size()
	var poses := 0
	for tc in _taches.duplicate():
		if poses < 2 and WorkerThreadPool.is_task_completed(tc[0]):
			WorkerThreadPool.wait_for_task_completion(tc[0])
			_taches.erase(tc)
			if keep.has(tc[1]) and not cells.has(tc[1]):
				_poser(tc[1], tc[2].get("r", []))
				poses += 1
	# cases suivantes : les vides (sans champ) sont réglées tout de suite, jusqu'à 24 par image
	var en_cours := {}
	for tc in _taches:
		en_cours[tc[1]] = true
	var vues := 0
	for it in todo:
		if _taches.size() >= TACHES or vues >= 24:
			break
		if en_cours.has(it[1]):
			continue
		vues += 1
		_lancer(it[1])
	# densité selon la distance (instances mélangées à la construction : en afficher une partie = éclaircir
	# uniformément) ; pleine densité jusqu’à 25 m, 15 % au bord de la portée, où le fondu tramé prend le relais
	_lod_t -= dt
	if _lod_t <= 0.0:
		_lod_t = 0.2
		var cam := get_viewport().get_camera_3d()
		var o := cam.global_position if cam else c
		var rg: float = RANGE[level]
		for k in cells:
			var nd: Node3D = cells[k]
			if nd == null or not nd.has_meta("mm"):
				continue
			var mm: MultiMesh = nd.get_meta("mm")
			var dd := Vector2((k.x + 0.5) * CELL - o.x, (k.y + 0.5) * CELL - o.z).length() - CELL * 0.5
			var f := 1.0 - 0.85 * clampf((dd - 25.0) / (rg - 25.0), 0.0, 1.0)
			mm.visible_instance_count = maxi(1, int(mm.instance_count * f))
	if _t <= 0.0:
		_t = 0.5
		for k in cells.keys():
			if not keep.has(k):
				if cells[k]:
					cells[k].queue_free()
				cells.erase(k)

## Essais (#61) : instances de plantes affichées (toutes cases).
func instances_visibles() -> int:
	var n := 0
	for k in cells:
		if cells[k] and cells[k].has_meta("mm"):
			n += (cells[k].get_meta("mm") as MultiMesh).visible_instance_count
	return n

## Fil principal : relief de la case (grille de 4 m) et parcelles, puis calcul confié à un fil de calcul.
func _lancer(k: Vector2i) -> void:
	var x0 := k.x * CELL; var z0 := k.y * CELL
	var rect := Rect2(x0, z0, CELL, CELL)
	var tk := Vector2i(floori(x0 / TILE), floori(z0 / TILE))
	var fs := []
	for f in _tile_fields(tk):
		if f[3].intersects(rect):
			fs.append(f)
	if fs.is_empty():
		cells[k] = null
		return
	var hg := PackedFloat32Array()
	for gz in 9:
		for gx in 9:
			var y: float = Relief.hauteur(Vector3(x0 + gx * 4.0, 0, z0 + gz * 4.0))
			hg.append(NAN if is_nan(y) else y)
	var res := {}
	_taches.append([WorkerThreadPool.add_task(_calcul.bind(k, fs, hg, res), false, "cultures"), k, res])

## Fil de calcul : plants (mélangés pour le niveau de détail) et sol de terre de la case. Fonction statique : aucun
## accès au nœud ni à la scène depuis le fil ; le résultat va dans le dictionnaire « sortie » (lu après la fin).
static func _calcul(k: Vector2i, fs: Array, hg: PackedFloat32Array, sortie: Dictionary) -> void:
	var x0 := k.x * CELL; var z0 := k.y * CELL
	var cellpoly := PackedVector2Array([Vector2(x0, z0), Vector2(x0 + CELL, z0), Vector2(x0 + CELL, z0 + CELL), Vector2(x0, z0 + CELL)])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(k)
	var buf := PackedFloat32Array()
	var sols := []
	for f in fs:
		var t: int = f[0]
		buf.append_array(_plants(f, t, cellpoly, hg, x0, z0, rng))
		var v := _sol(f, cellpoly, hg, x0, z0)
		if not v.is_empty():
			var d: Vector2 = f[1]
			sols.append([v, Color(d.x, d.y, ROWS[t], 0.0)])
	var n := buf.size() / 16
	for i in range(n - 1, 0, -1):                 # mélange (Fisher-Yates) par blocs de 16 flottants
		var j := rng.randi_range(0, i)
		if j != i:
			for q in 16:
				var tmp := buf[i * 16 + q]
				buf[i * 16 + q] = buf[j * 16 + q]
				buf[j * 16 + q] = tmp
	sortie["r"] = [buf, n, sols]

## Fil principal : maillages de la case (plants : MultiMesh ; sol : un maillage par parcelle).
func _poser(k: Vector2i, res: Array) -> void:
	if res.is_empty():
		cells[k] = null
		return
	var root := Node3D.new()
	for sv in res[2]:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = sv[0]
		var nrm := PackedVector3Array()
		nrm.resize(sv[0].size())
		nrm.fill(Vector3.UP)
		arr[Mesh.ARRAY_NORMAL] = nrm
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = am
		mm.instance_count = 1
		mm.set_instance_transform(0, Transform3D.IDENTITY)
		mm.set_instance_custom_data(0, sv[1])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = mat_sol
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	var count: int = res[1]
	if count > 0 and level > 0:          # Économie (#124) : pas de plants, la terre à sillons seule
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = cross
		mm.instance_count = count
		mm.buffer = res[0]
		var node := MultiMeshInstance3D.new()
		node.multimesh = mm
		node.material_override = mat
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(node)
		root.set_meta("mm", mm)
	if root.get_child_count() == 0:
		root.free()
		cells[k] = null
		return
	add_child(root)
	cells[k] = root

static func _h(hg: PackedFloat32Array, x0: float, z0: float, p: Vector2) -> float:
	var u := clampf((p.x - x0) / 4.0, 0.0, 7.999); var v := clampf((p.y - z0) / 4.0, 0.0, 7.999)
	var i := int(u); var j := int(v); var fu := u - i; var fv := v - j
	var a := hg[j * 9 + i]; var b := hg[j * 9 + i + 1]; var c := hg[j * 9 + 9 + i]; var d := hg[j * 9 + 9 + i + 1]
	return lerpf(lerpf(a, b, fu), lerpf(c, d, fu), fv)

## Touffes d'une parcelle dans une case (#61) : sur un rang sur RANG_K[t] (grille commune à tout le champ), une touffe
## tous les PAS[t] m, un peu décalée ; deux plans de LARGEUR m, le long du rang et en travers ; données d'instance :
## culture, variante (0-3), teinte, hauteur de la case.
static func _plants(f: Array, t: int, cellpoly: PackedVector2Array, hg: PackedFloat32Array, x0: float, z0: float, rg: RandomNumberGenerator) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	var d: Vector2 = f[1]
	var nrm := Vector2(-d.y, d.x)
	var sp: float = ROWS[t] * RANG_K[t]; var st: float = PAS[t]; var hc: float = HCASE[t]
	var tmin := INF; var tmax := -INF; var smin := INF; var smax := -INF
	for p in cellpoly:
		tmin = minf(tmin, p.dot(nrm)); tmax = maxf(tmax, p.dot(nrm))
		smin = minf(smin, p.dot(d)); smax = maxf(smax, p.dot(d))
	for poly in Geometry2D.intersect_polygons(f[2], cellpoly):
		for kk in range(ceili(tmin / sp), floori(tmax / sp) + 1):
			var off := kk * sp
			var line := PackedVector2Array([nrm * off + d * (smin - 1.0), nrm * off + d * (smax + 1.0)])
			for seg in Geometry2D.intersect_polyline_with_polygon(line, poly):
				var a: Vector2 = seg[0]; var b: Vector2 = seg[seg.size() - 1]
				var s1 := maxf(a.dot(d), b.dot(d))
				# décalage d'un demi-pas un rang sur deux : pas d'alignement en damier vu de loin
				var s := ceilf(minf(a.dot(d), b.dot(d)) / st) * st + (st * 0.5 if kk % 2 != 0 else 0.0)
				while s <= s1:
					var q := nrm * off + d * s + nrm * rg.randf_range(-0.2, 0.2) * sp + d * rg.randf_range(-0.3, 0.3) * st
					s += st
					var y := _h(hg, x0, z0, q)
					if is_nan(y):
						continue
					var sc := hc * rg.randf_range(0.92, 1.06)
					var w := LARGEUR * sc / hc
					var ang := atan2(d.y, d.x) + rg.randf_range(-0.12, 0.12)
					var bx := Vector3(cos(ang), 0, sin(ang)) * w
					var bz := Vector3(-sin(ang), 0, cos(ang)) * w
					buf.append_array([bx.x, 0.0, bz.x, q.x, bx.y, sc, bz.y, y - 0.04, bx.z, 0.0, bz.z, q.y,
						float(t), float(rg.randi_range(0, 3)), rg.randf_range(0.72, 0.88), sc])
	return buf

## Sol de terre d'une parcelle dans une case : découpé au contour, posé sur le relief par carrés de 4 m (+3 cm ; hauteurs
## interpolées dans la grille de la case, sans relire le relief). Rend les sommets (triangles vus du dessus).
static func _sol(f: Array, cellpoly: PackedVector2Array, hg: PackedFloat32Array, x0: float, z0: float) -> PackedVector3Array:
	var out := PackedVector3Array()
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
						var y := _h(hg, x0, z0, v)
						hs.append(0.0 if is_nan(y) else y + 0.03)
					for i in range(1, piece.size() - 1):
						for j in [0, i, i + 1]:              # sens des faces vues du dessus (sinon normale retournée)
							var v: Vector2 = piece[j]
							out.append(Vector3(v.x, hs[j], v.y))
	return out
