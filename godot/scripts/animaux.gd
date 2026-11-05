## Animaux des prés et clôtures des pâtures (build_animaux.py, modèles blender_animaux.py) : tuiles de 256 m chargées
## au fil de la route, un MultiMesh par modèle et par tuile ; on ne traverse ni les bêtes ni les clôtures.
extends Node3D
const PerfMon := preload("res://scripts/perf_monitor.gd")

const TILE := 256.0
const Cells := preload("res://scripts/cells.gd")
const VIEW := 450.0
const MODELS := ["vache", "mouton", "cheval", "cloture", "piquet"]

var target: Node3D
var tiles := {}
var loaded := {}
var meshes := []
var _t := 0.0
# clôtures des prés défonçables (issue #27) : tuile -> {spans: [[p0, p1, origine, cassée]], grille: case 16 m ->
# indices, mis: MultiMeshInstance3D des travées}
const G := 16.0
var travees := {}

func _ready() -> void:
	if not DirAccess.dir_exists_absolute("res://world/animaux"):
		return
	for f in DirAccess.get_files_at("res://world/animaux"):
		if f.ends_with(".bin"):
			var p := f.trim_prefix("a_").trim_suffix(".bin").split("_")
			tiles[Vector2i(int(p[0]), int(p[1]))] = "res://world/animaux/" + f
	var fence := StandardMaterial3D.new()
	fence.albedo_color = Color(0.38, 0.28, 0.18); fence.roughness = 0.9
	var wire := StandardMaterial3D.new()
	wire.albedo_color = Color(0.52, 0.52, 0.54); wire.metallic = 0.5; wire.roughness = 0.45   # barbelé galvanisé
	for i in MODELS.size():
		var mi: MeshInstance3D = (load("res://assets/animaux/%s.glb" % MODELS[i]) as PackedScene).instantiate().find_children("*", "MeshInstance3D", true, false)[0]
		var mesh: Mesh = mi.mesh
		for s in mesh.get_surface_count():
			var nm := mesh.surface_get_material(s).resource_name if mesh.surface_get_material(s) else ""
			if i < 3:
				var sm := ShaderMaterial.new()
				sm.shader = preload("res://scripts/animal.gdshader")
				sm.set_shader_parameter("species", i)
				# modèles texturés (Sketchfab, blender_animaux_import.py) : texture de couleur d'origine
				var om := mesh.surface_get_material(s) as BaseMaterial3D
				if om and om.albedo_texture:
					sm.set_shader_parameter("albedo_tex", om.albedo_texture)
					sm.set_shader_parameter("textured", true)
				preload("res://scripts/env.gd").add(sm)
				mesh.surface_set_material(s, sm)
			else:
				mesh.surface_set_material(s, wire if nm == "fil" else fence)
		meshes.append(mesh)

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
	return out

func update_now() -> void:
	_t = 0.0
	if target:
		for k in _wanted(target.global_position):
			_add(k)

func _process(dt: float) -> void:
	var t0_perf := Time.get_ticks_usec()
	_process_corps(dt)
	PerfMon.note("animaux", Time.get_ticks_usec() - t0_perf)

func _process_corps(dt: float) -> void:
	if target == null:
		return
	_t -= dt
	if _t > 0.0:
		return
	_t = 0.5
	# #174 : tuile préparée sur un fil de travail (lecture, collisions, lots), posée ici quand elle est prête : la
	# préparation sur le fil principal faisait des à-coups (358 ms mesurés en balade)
	if _tache >= 0:
		if not WorkerThreadPool.is_task_completed(_tache):
			_t = 0.05
			return
		WorkerThreadPool.wait_for_task_completion(_tache)
		_tache = -1
		var lu: Array = _tache_res
		_tache_res = []
		var r: Array = _construire(lu) if not lu.is_empty() and not loaded.has(lu[0]) else []
		if not r.is_empty():
			add_child(r[1])
			loaded[r[0]] = r[1]
			if not (r[2] as Dictionary).is_empty():
				travees[r[0]] = r[2]
	var ws := {}
	for k in _wanted(target.global_position):
		ws[k] = true
		if not loaded.has(k) and _tache < 0:
			var kk: Vector2i = k
			_tache = WorkerThreadPool.add_task(func(): _tache_res = _lire(kk))
	for k in loaded.keys():
		if not ws.has(k):
			loaded[k].queue_free()
			loaded.erase(k)
			travees.erase(k)

var _tache := -1
var _tache_res: Array = []

func _exit_tree() -> void:
	if _tache >= 0:
		WorkerThreadPool.wait_for_task_completion(_tache)
		_tache = -1

func _add(k: Vector2i) -> void:
	if loaded.has(k):
		return
	var r := _preparer(k)
	add_child(r[1])
	loaded[k] = r[1]
	if not (r[2] as Dictionary).is_empty():
		travees[k] = r[2]

## Tuile k préparée hors de la scène (peut tourner sur un fil de travail) : [k, nœud racine, travées].
func _preparer(k: Vector2i) -> Array:
	return _construire(_lire(k))

## Lecture et calculs d'une tuile (fil de travail possible : ni nœud ni ressource partagée) :
## [k, objets par modèle, boîtes [taille, transform], travées, grille].
func _lire(k: Vector2i) -> Array:
	var a := FileAccess.get_file_as_bytes(tiles[k])
	var cnt := a.decode_s32(0)
	var f := a.slice(4).to_float32_array()
	var by := {}
	var spans := []
	var grille := {}
	var boites := []
	for i in cnt:
		var o := i * 17
		var m := int(f[o])
		var b := Basis(Vector3(f[o + 1], f[o + 2], f[o + 3]), Vector3(f[o + 4], f[o + 5], f[o + 6]), Vector3(f[o + 7], f[o + 8], f[o + 9]))
		var xf := Transform3D(b, Vector3(f[o + 10], f[o + 11], f[o + 12]))
		if not by.has(m):
			by[m] = []
		by[m].append([xf, Color(f[o + 13], f[o + 14], f[o + 15], f[o + 16])])
		if m == 4:
			continue                     # piquet
		if m == 3:
			# travée de clôture : défonçable, sans collision (issue #27) ; repérée sur une grille de 16 m
			var p0 := Vector2(xf.origin.x, xf.origin.z)
			var p1 := p0 + Vector2(b.x.x, b.x.z)
			var tr := [p0, p1, xf.origin, false]
			var ix := spans.size()
			spans.append(tr)
			var lo := Vector2i(floori(minf(p0.x, p1.x) / G) - 1, floori(minf(p0.y, p1.y) / G) - 1)
			var hi := Vector2i(floori(maxf(p0.x, p1.x) / G) + 1, floori(maxf(p0.y, p1.y) / G) + 1)
			for gx in range(lo.x, hi.x + 1):
				for gz in range(lo.y, hi.y + 1):
					var gk := Vector2i(gx, gz)
					if not grille.has(gk):
						grille[gk] = PackedInt32Array()
					grille[gk].append(ix)
			continue
		var sz: Vector3 = [Vector3(0.8, 1.4, 2.4), Vector3(0.6, 0.8, 1.1), Vector3(0.7, 1.6, 2.3)][m]
		boites.append([sz, xf * Transform3D(Basis.IDENTITY, Vector3(0, sz.y / 2, 0))])
	return [k, by, boites, spans, grille]

## Nœuds d'une tuile lue (fil principal) : [k, nœud racine, travées].
func _construire(r: Array) -> Array:
	var k: Vector2i = r[0]
	var by: Dictionary = r[1]
	var root := Node3D.new()
	var body := StaticBody3D.new()
	body.set_meta("matiere", "sol")                 # bêtes : choc sourd (audio.gd)
	root.add_child(body)
	for bx in r[2]:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = bx[0]
		cs.transform = bx[1]
		cs.shape = bs
		body.add_child(cs)
	var mis3 := []
	for m in by:
		var mis := Cells.add(root, meshes[m], by[m], 380.0 if m < 3 else 300.0, m < 3)
		if m == 3:
			mis3 = mis
	var spans: Array = r[3]
	return [k, root, {"spans": spans, "grille": r[4], "mis": mis3} if not spans.is_empty() else {}]

## Clôtures des prés défonçables (issue #27, demande de l'utilisateur) : la voiture qui touche une travée (devant ou
## milieu de la caisse à moins de 1,2 m du fil) l'arrache : travée cachée, éclats de bois, craquement de branche
## arrachée (audio.impact « bois », casse), et presque pas de perte de vitesse (3 %).
func _physics_process(_dt: float) -> void:
	var car := target as VehicleBody3D
	if car == null or travees.is_empty():
		return
	var v := car.linear_velocity
	if v.length() < 1.5:
		return
	var c3 := car.global_position
	var f3 := car.global_basis.z
	var pts := [Vector2(c3.x, c3.z), Vector2(c3.x + f3.x * 2.2, c3.z + f3.z * 2.2)]
	var kt := Vector2i(floori(c3.x / TILE), floori(c3.z / TILE))
	var gk := Vector2i(floori(c3.x / G), floori(c3.z / G))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var T: Dictionary = travees.get(kt + Vector2i(dx, dz), {})
			if T.is_empty():
				continue
			for i in T.grille.get(gk, PackedInt32Array()):
				var tr: Array = T.spans[i]
				if tr[3]:
					continue
				for q in pts:
					if q.distance_to(Geometry2D.get_closest_point_to_segment(q, tr[0], tr[1])) < 1.2:
						_arracher(T, tr, car)
						break

func _arracher(T: Dictionary, tr: Array, car: VehicleBody3D) -> void:
	tr[3] = true
	print("[clôture du pré] arrachée en %s à %d km/h" % [tr[2], int(car.kmh())])
	var org: Vector3 = tr[2]
	for mi in T.mis:
		var o: PackedVector3Array = mi.get_meta("origines", PackedVector3Array())
		var i := o.find(org)
		if i >= 0:
			mi.multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * 0.001), org - Vector3(0, 50, 0)))
			break
	var spd := car.linear_velocity.length()
	car.linear_velocity *= 0.97
	var m := get_parent()
	var mid := Vector3((tr[0].x + tr[1].x) * 0.5, org.y + 0.7, (tr[0].y + tr[1].y) * 0.5)
	if m and m.get("sound") and m.sound.has_method("impact"):
		m.sound.impact("bois", maxf(spd, 5.0), mid, true)
	if m and m.get("dust") and m.dust.has_method("eclats"):
		m.dust.eclats(mid, car.linear_velocity, org.y, Color(0.38, 0.28, 0.18), Color(0.52, 0.52, 0.54), 10)
