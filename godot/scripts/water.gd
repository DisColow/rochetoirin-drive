## Eau (build_water.py) : étangs, rivières, ruisseaux en tuiles de 256 m chargées au fil de la route.
extends Node3D
const PerfMon := preload("res://scripts/perf_monitor.gd")
const Relief := preload("res://scripts/relief.gd")

const TILE := 256.0
var VIEW := 1500.0          # × distance du niveau de performances (main.set_post, #174)

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
var plans := {}
# #187 : vraie physique de l'eau (façon Vice City). La voiture entre dans le plan d'eau avec son élan, flotte un
# moment, prend l'eau et coule en piquant du nez (poussée d'Archimède à chaque coin, frottement de l'eau), au fond d'un
# bassin profond ; noyée (toit sous l'eau) depuis NOYE_T s ou dans l'eau depuis MAX_T s : remise sur la route.
# Le relief n'est creusé que de 0,6 m sous l'eau (prepare_terrain.py) : pendant le bain, la voiture ne touche plus que
# le fond « bassin » (HeightMapShape3D de BASSIN m autour d'elle, sur sa propre couche de collision) : relief du jeu
# hors de l'eau, fond qui descend de PENTE m par m depuis la berge jusqu'à PROF m.
const COUCHE_BAIN := 1 << 12
const BASSIN := 64
const PROF := 4.5
const PENTE := 0.7
const FLOTTE := 1.12              # poussée au plongeon (× poids) : la voiture flotte
const PREND_EAU := 0.15           # poussée perdue par seconde (l'eau entre)
const NEZ := 0.72                 # part de poussée à l'avant (moteur : elle pique du nez)
const NOYE_T := 1.6
const MAX_T := 9.0
var _noyade := -1.0               # temps depuis le plongeon (-1 : rien)
var _chk := 0.0
var _fond: StaticBody3D
var _avant := {}                  # couches, amortissements de la voiture avant le bain
var _noye_t := 0.0
var _niveau := 0.0

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
	# #183 : couleur du ciel reflétée par l'eau (Fresnel du shader) = couleur de la brume du moment (heure, météo)
	var envi = get_parent().get("_env") if get_parent() else null
	if envi is Environment:
		var fc: Color = (envi as Environment).fog_light_color
		mat.set_shader_parameter("ciel", Vector3(fc.r, fc.g, fc.b))
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

## Entrée dans un plan d'eau (#86, #187) : gerbe, plouf, moteur noyé ; ensuite flottaison, puis la voiture coule.
func _physics_process(dt: float) -> void:
	var m := get_parent()
	var car = m.get("car") if m else null
	if car == null:
		return
	if _noyade >= 0.0:
		_bain(car, dt)
		return
	var pd = m.get("pied")
	if car.freeze or car.carried or (pd and pd.get("actif")):
		return
	_chk -= dt
	if _chk > 0.0:
		return
	_chk = 0.05
	var p: Vector3 = car.global_position
	var h := niveau_plan(p)
	if is_nan(h) or p.y > h + 0.4:
		return
	if OS.get_cmdline_user_args().has("--eau-debug"):
		print("[eau] la voiture plonge en %s (eau à %.2f m, voiture à %.2f m, %d km/h)" % [p, h, p.y, int(car.kmh())])
	_plonger(car, h)
	var v: Vector3 = car.linear_velocity
	if m.get("sound") and m.sound.has_method("_one_shot"):
		m.sound._one_shot("plouf", p, clampf(0.8 + v.length() / 10.0, 0.8, 2.0), randf_range(0.9, 1.05), 30.0, 500.0)
	var D = m.get("dust")
	if D:
		var mat: Dictionary = D.MATIERES.get("eau", {})
		if not mat.is_empty():
			for i in 24:
				var q := Vector3(p.x + randf_range(-1.6, 1.6), h + 0.1, p.z + randf_range(-2.4, 2.4))
				D._nuage(mat, q, Vector3(v.x * 0.3 + randf_range(-2, 2), randf_range(3.0, 7.0), v.z * 0.3 + randf_range(-2, 2)), 1.0)

## Début du bain : fond du bassin posé autour de la voiture, qui ne touche plus que lui ; moteur noyé.
func _plonger(car: VehicleBody3D, h: float) -> void:
	_noyade = 0.0
	_noye_t = 0.0
	_niveau = h
	var p := car.global_position
	var n := BASSIN + 1
	var x0 := floorf(p.x) - BASSIN * 0.5
	var z0 := floorf(p.z) - BASSIN * 0.5
	# cases dans l'eau, distance à la berge (chanfrein 3-4 en deux passes), hauteur du fond
	var dans := PackedByteArray(); dans.resize(n * n)
	var niv := PackedFloat32Array(); niv.resize(n * n)
	var dist := PackedFloat32Array(); dist.resize(n * n)
	for j in n:
		for i in n:
			var q := Vector3(x0 + i, p.y, z0 + j)
			var hq := niveau_plan(q)
			var k := j * n + i
			dans[k] = 0 if is_nan(hq) else 1
			niv[k] = h if is_nan(hq) else hq
			dist[k] = 1e6 if dans[k] else 0.0
	for j in n:
		for i in n:
			var k := j * n + i
			if dans[k] == 0:
				continue
			var d := dist[k]
			if i > 0: d = minf(d, dist[k - 1] + 1.0)
			if j > 0: d = minf(d, dist[k - n] + 1.0)
			if i > 0 and j > 0: d = minf(d, dist[k - n - 1] + 1.4)
			if i < n - 1 and j > 0: d = minf(d, dist[k - n + 1] + 1.4)
			dist[k] = d
	for j in range(n - 1, -1, -1):
		for i in range(n - 1, -1, -1):
			var k := j * n + i
			if dans[k] == 0:
				continue
			var d := dist[k]
			if i < n - 1: d = minf(d, dist[k + 1] + 1.0)
			if j < n - 1: d = minf(d, dist[k + n] + 1.0)
			if i < n - 1 and j < n - 1: d = minf(d, dist[k + n + 1] + 1.4)
			if i > 0 and j < n - 1: d = minf(d, dist[k + n - 1] + 1.4)
			dist[k] = d
	var H := PackedFloat32Array(); H.resize(n * n)
	var fond_min := INF
	for j in n:
		for i in n:
			var k := j * n + i
			var sol := Relief.hauteur(Vector3(x0 + i, 0.0, z0 + j))
			if dans[k]:
				# bord de la carte (pas de berge connue au-delà) : distance plafonnée par le bord de la grille
				var d := minf(dist[k], 1e3)
				H[k] = minf(sol, niv[k] - minf(0.6 + d * PENTE, PROF))
				fond_min = minf(fond_min, H[k])
			else:
				H[k] = sol
	var sh := HeightMapShape3D.new()
	sh.map_width = n
	sh.map_depth = n
	sh.map_data = H
	_fond = StaticBody3D.new()
	_fond.collision_layer = COUCHE_BAIN
	_fond.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = sh
	_fond.add_child(cs)
	add_child(_fond)
	_fond.global_position = Vector3(x0 + BASSIN * 0.5, 0.0, z0 + BASSIN * 0.5)
	_avant = {"couche": car.collision_layer, "masque": car.collision_mask, "ld": car.linear_damp, "ad": car.angular_damp}
	car.collision_layer = COUCHE_BAIN
	car.collision_mask = COUCHE_BAIN
	car.dans_eau = true
	if OS.get_cmdline_user_args().has("--eau-debug"):
		print("[eau] bassin : %d cases dans l'eau sur %d, fond le plus bas %.2f m sous l'eau" % [Array(dans).count(1), n * n, h - fond_min])

## Bain : poussée d'Archimède aux quatre coins (moins à l'avant), qui faiblit à mesure que l'eau entre ; l'eau freine.
func _bain(car: VehicleBody3D, dt: float) -> void:
	_noyade += dt
	if not is_instance_valid(_fond) or car.global_position.distance_to(_fond.global_position) > BASSIN * 0.6 or car.carried:
		_sortir(car, false)                    # téléportée, portée, ou sortie de la grille du bassin
		return
	var g: Vector3 = car.gabarit
	var hb := maxf(g.y, 1.2)
	var flotte := maxf(FLOTTE - PREND_EAU * _noyade, 0.0)
	var poids: float = car.mass * 9.8
	var sub_moy := 0.0
	for c: Vector2 in [Vector2(-0.5, 0.5), Vector2(0.5, 0.5), Vector2(-0.5, -0.5), Vector2(0.5, -0.5)]:
		var loc := Vector3(c.x * g.x * 0.8, 0.0, c.y * g.z * 0.8)
		var w := car.global_transform * loc
		var h := niveau_plan(w)
		if is_nan(h):
			h = _niveau
		var sub := clampf((h - (w.y - 0.25)) / hb, 0.0, 1.0)
		sub_moy += sub * 0.25
		var part := NEZ if c.y > 0.0 else 2.0 - NEZ
		car.apply_force(Vector3.UP * (poids * 0.25 * sub * flotte * part), w - car.global_position)
	# frottement de l'eau (amortissements du moteur physique : vitesse et rotation)
	car.linear_damp = 0.4 + 2.2 * sub_moy
	car.angular_damp = 0.8 + 3.0 * sub_moy
	# noyée : toit sous l'eau
	var toit := car.global_transform * Vector3(0.0, hb, 0.0)
	_noye_t = _noye_t + dt if toit.y < _niveau - 0.1 else 0.0
	if _noye_t > NOYE_T or _noyade > MAX_T:
		if OS.get_cmdline_user_args().has("--eau-debug"):
			print("[eau] noyée après %.1f s (voiture à %.2f m sous l'eau)" % [_noyade, _niveau - car.global_position.y])
		_sortir(car, true)

func _sortir(car: VehicleBody3D, remettre: bool) -> void:
	_noyade = -1.0
	if is_instance_valid(_fond):
		_fond.queue_free()
	_fond = null
	if not _avant.is_empty():
		car.collision_layer = _avant.couche
		car.collision_mask = _avant.masque
		car.linear_damp = _avant.ld
		car.angular_damp = _avant.ad
		_avant = {}
	car.dans_eau = false
	if remettre:
		car.reset_to_road("voiture tombée dans l'eau")
