## Effets des roues, façon Call of Duty 2 / grands jeux de rallye : grosses volutes de fumée et de poussière éclairées
## par le soleil (côté ombre plus sombre, contre-jour lumineux), qui gonflent, tournent lentement, se dissipent et
## s'adoucissent au contact du décor ; débris en volume qui volent, rebondissent et s'effacent.
##  - asphalte : fumée blanche épaisse quand ça glisse (dérapage, patinage, freinage bloqué) ;
##  - route mouillée : embruns gris derrière chaque roue ;
##  - terre, gravier : nuage de poussière beige + mottes et cailloux ;
##  - herbe : brins arrachés, mottes, voile de poussière légère.
## Rendu : deux MultiMesh seulement (nuages : shader scripts/fumee.gdshader, panneau face caméra calculé dans le
## shader, triés de l'arrière vers l'avant ; débris : petits volumes éclairés). Nombre de particules plafonné selon le
## niveau de performances (Engine meta « niveau_perf »). Surface : meta « surface » des routes (roads.gd), sinon herbe.
extends Node3D
const PerfMon := preload("res://scripts/perf_monitor.gd")

var car: VehicleBody3D
var roads: Node
var wet := 0.0

const MAX_NUAGES := [70, 120, 180, 240]
const MAX_DEBRIS := [120, 180, 240, 300]
# matière : teinte, taille de départ et de fin (m), durée (s), poussée vers le haut, opacité, débit (/s à fond)
const MATIERES := {
	"fumee": {"c": Color(0.93, 0.93, 0.94), "t0": 0.5, "t1": 3.8, "vie": 3.2, "monte": 0.45, "a": 0.6, "debit": 46.0},
	"poussiere": {"c": Color(0.78, 0.68, 0.53), "t0": 0.7, "t1": 4.6, "vie": 3.6, "monte": 0.18, "a": 0.55, "debit": 30.0},
	"voile": {"c": Color(0.62, 0.58, 0.45), "t0": 0.5, "t1": 2.4, "vie": 1.8, "monte": 0.12, "a": 0.25, "debit": 12.0},
	"eau": {"c": Color(0.82, 0.85, 0.88), "t0": 0.35, "t1": 2.2, "vie": 0.9, "monte": 0.05, "a": 0.42, "debit": 34.0},
}

var _mm_n: MultiMesh            # nuages
var _mm_d: MultiMesh            # débris
var _mat_n: ShaderMaterial
# nuages : tableaux parallèles (plus rapide qu'un tableau de dictionnaires)
var _np := PackedVector3Array(); var _nv := PackedVector3Array()
var _nage := PackedFloat32Array(); var _nvie := PackedFloat32Array()
var _nt0 := PackedFloat32Array(); var _nt1 := PackedFloat32Array()
var _nrot := PackedFloat32Array(); var _nrv := PackedFloat32Array()
var _nmonte := PackedFloat32Array(); var _na := PackedFloat32Array()
var _nc := PackedColorArray()
# débris
var _dp := PackedVector3Array(); var _dv := PackedVector3Array()
var _dage := PackedFloat32Array(); var _dsol := PackedFloat32Array()
var _dtaille := PackedVector3Array(); var _drot := PackedVector3Array(); var _drv := PackedVector3Array()
var _dc := PackedColorArray()
var _acc := {}                  # émission fractionnaire par roue et matière
var _demo := OS.get_cmdline_user_args().has("--fx-demo")

func _ready() -> void:
	# nuages : quad 1 × 1, shader maison
	_mat_n = ShaderMaterial.new()
	_mat_n.shader = preload("res://scripts/fumee.gdshader")
	if ResourceLoader.exists("res://assets/fx/fumee.png"):
		_mat_n.set_shader_parameter("fumee_tex", load("res://assets/fx/fumee.png"))
	var q := QuadMesh.new(); q.size = Vector2(1, 1)
	_mm_n = MultiMesh.new()
	_mm_n.transform_format = MultiMesh.TRANSFORM_3D
	_mm_n.use_colors = true
	_mm_n.use_custom_data = true
	_mm_n.mesh = q
	_mm_n.instance_count = MAX_NUAGES[-1]
	_mm_n.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = _mm_n
	mi.material_override = _mat_n
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 16384.0          # positions mises à jour à la main : jamais écarté par erreur
	mi.sorting_offset = 2.0
	add_child(mi)
	# débris : petit caillou à facettes (mottes, cailloux) ; les brins d'herbe sont le même volume, très aplati
	var mat_d := StandardMaterial3D.new()
	mat_d.vertex_color_use_as_albedo = true
	mat_d.roughness = 0.95
	var roc := SphereMesh.new(); roc.radius = 0.5; roc.height = 0.8; roc.radial_segments = 6; roc.rings = 3
	roc.material = mat_d
	_mm_d = MultiMesh.new()
	_mm_d.transform_format = MultiMesh.TRANSFORM_3D
	_mm_d.use_colors = true
	_mm_d.mesh = roc
	_mm_d.instance_count = MAX_DEBRIS[-1]
	_mm_d.visible_instance_count = 0
	var md := MultiMeshInstance3D.new()
	md.multimesh = _mm_d
	md.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	md.extra_cull_margin = 16384.0
	add_child(md)

func _niveau() -> int:
	return clampi(int(Engine.get_meta("niveau_perf", 1)), 0, 3)

func _surface(w: VehicleWheel3D) -> String:
	var b := w.get_contact_body()
	if b == null:
		return "herbe"
	if b.has_meta("surface"):
		return "terre" if String(b.get_meta("surface")) == "dirt" else "asphalte"
	var n := b as Node
	while n:
		if n == roads:
			return "asphalte"
		n = n.get_parent()
	return "herbe"

# ---------------------------------------------------------------- émission
func _nuage(m: Dictionary, p: Vector3, v: Vector3, force: float) -> void:
	if _np.size() >= MAX_NUAGES[_niveau()]:
		return
	_np.append(p); _nv.append(v)
	_nage.append(0.0); _nvie.append(float(m.vie) * randf_range(0.8, 1.2))
	_nt0.append(float(m.t0) * randf_range(0.8, 1.2)); _nt1.append(float(m.t1) * randf_range(0.75, 1.25) * (0.6 + 0.4 * force))
	_nrot.append(randf() * TAU); _nrv.append(randf_range(-0.5, 0.5))
	_nmonte.append(float(m.monte)); _na.append(float(m.a) * (0.5 + 0.5 * force))
	var c: Color = m.c
	_nc.append(c.lerp(Color(c.r * 0.9, c.g * 0.9, c.b * 0.92), randf()))

func _debris(p: Vector3, v: Vector3, sol: float, taille: Vector3, c: Color) -> void:
	if _dp.size() >= MAX_DEBRIS[_niveau()]:
		return
	_dp.append(p); _dv.append(v); _dage.append(0.0); _dsol.append(sol)
	_dtaille.append(taille); _drot.append(Vector3(randf(), randf(), randf()) * TAU)
	_drv.append(Vector3(randf_range(-12, 12), randf_range(-12, 12), randf_range(-12, 12)))
	_dc.append(c)

## Tiges fauchées par la voiture (trample.gd) : brins et feuilles de la couleur de la culture projetés en gerbe,
## plus un voile de poussière teinté. c = couleur principale, c2 = seconde couleur (épis, fleurs).
func eclats(p: Vector3, v: Vector3, sol: float, c: Color, c2: Color, n: int) -> void:
	for k in n:
		var dir := Vector3(randf_range(-1.0, 1.0), randf_range(0.9, 2.0), randf_range(-1.0, 1.0))
		var vit := v * randf_range(0.5, 1.05) + dir * randf_range(2.5, 7.0)
		var col := (c if randf() < 0.72 else c2).lerp(Color(0.3, 0.26, 0.14), randf() * 0.3)
		var taille := Vector3(0.05, randf_range(0.3, 0.8), 0.05) if randf() < 0.6 \
			else Vector3(randf_range(0.14, 0.26), 0.025, randf_range(0.08, 0.15))
		_debris(p + Vector3(randf_range(-0.8, 0.8), randf_range(0.1, 0.9), randf_range(-0.8, 0.8)), vit, sol, taille, col)
	if randf() < 0.5:
		var m := {"c": c.lerp(Color(0.8, 0.74, 0.58), 0.45), "t0": 0.6, "t1": 2.8, "vie": 1.5, "monte": 0.2, "a": 0.35}
		_nuage(m, p + Vector3(0, 0.4, 0), v * 0.25, 1.0)

func _emettre(i: int, mat: String, rate: float, dt: float, p: Vector3, v: Vector3, force: float) -> void:
	var key := i * 16 + MATIERES.keys().find(mat)
	var a: float = _acc.get(key, 0.0) + rate * dt
	while a >= 1.0:
		a -= 1.0
		var jitter := Vector3(randf_range(-0.25, 0.25), randf_range(0.0, 0.2), randf_range(-0.25, 0.25))
		_nuage(MATIERES[mat], p + jitter, v + jitter * 2.0, force)
	_acc[key] = a

func _process(_dt: float) -> void:
	var t0_perf := Time.get_ticks_usec()
	_process_corps(_dt)
	PerfMon.note("dust", Time.get_ticks_usec() - t0_perf)

func _process_corps(dt: float) -> void:
	if car == null or car.wheels.size() < 4:
		return
	dt = minf(dt, 0.05)
	var kmh: float = car.kmh()
	var fwd: Vector3 = car.global_basis.z * (1.0 if car.forward_speed() >= 0.0 else -1.0)
	var back := -fwd
	var lat: float = absf(car.linear_velocity.dot(car.global_basis.x))
	var cv: Vector3 = car.linear_velocity
	if _demo:
		# essai --fx-demo : chaque roue montre une matière, en continu
		for i in 4:
			var w: VehicleWheel3D = car.wheels[i]
			var sol := w.global_position - car.global_basis.y * w.wheel_radius
			var p := sol + back * 0.3 + Vector3(0, 0.25, 0)
			var v := back * 2.5 + Vector3(0, 0.6, 0)
			var mat: String = ["fumee", "poussiere", "eau", "voile"][i]
			_emettre(i, mat, MATIERES[mat].debit, dt, p, v, 1.0)
			if i >= 1 and randf() < dt * 20.0:
				_debris(sol, v + Vector3(randf_range(-1.2, 1.2), randf_range(2.5, 5.0), randf_range(-1.2, 1.2)), sol.y,
					Vector3(0.025, 0.14, 0.01) if i == 3 else Vector3.ONE * 0.07, Color(0.3, 0.5, 0.14) if i == 3 else Color(0.42, 0.33, 0.22))
		_animer(dt)
		return
	for i in 4:
		var w: VehicleWheel3D = car.wheels[i]
		if car.blown or not w.is_in_contact():
			continue
		var s := _surface(w)
		var slip := 1.0 - w.get_skidinfo()             # 0 adhérence … 1 glisse
		var spin: float = slip if w.use_as_traction else 0.0
		var force := clampf(kmh / 60.0 + spin * 1.2 + lat / 8.0, 0.0, 1.0)
		if kmh < 4.0 and spin < 0.3:
			continue
		var sol := w.global_position - car.global_basis.y * w.wheel_radius
		var p := sol + back * 0.3 + Vector3(0, 0.25, 0)
		# les nuages partent derrière la roue, entraînés un peu par la voiture, puis restent sur place
		var v := cv * 0.25 + back * (1.0 + kmh / 30.0) + Vector3(0, 0.6, 0)
		match s:
			"asphalte":
				if wet > 0.3 and kmh > 15.0:
					_emettre(i, "eau", MATIERES.eau.debit * clampf(kmh / 90.0, 0.2, 1.0) * wet, dt, p, v + Vector3(0, 0.6, 0), force)
				if slip > 0.3 or lat > 4.0:
					var g := clampf(maxf(slip, lat / 10.0), 0.0, 1.0)
					_emettre(i, "fumee", MATIERES.fumee.debit * g, dt, p, v * 0.5, g)
			"terre":
				if wet <= 0.3:
					_emettre(i, "poussiere", MATIERES.poussiere.debit * force, dt, p, v, force)
				if randf() < force * dt * 14.0:
					_debris(sol, v * 0.6 + Vector3(randf_range(-1, 1), randf_range(2, 4.5), randf_range(-1, 1)), sol.y,
						Vector3.ONE * randf_range(0.04, 0.09), [Color(0.42, 0.33, 0.22), Color(0.6, 0.58, 0.54)][randi() % 2])
			"herbe":
				_emettre(i, "voile", MATIERES.voile.debit * force, dt, p, v * 0.7, force)
				if randf() < force * dt * 22.0:
					var brin := randf() < 0.7
					_debris(sol, v * 0.6 + Vector3(randf_range(-1.2, 1.2), randf_range(2.5, 5.0), randf_range(-1.2, 1.2)), sol.y,
						Vector3(0.025, 0.14, 0.01) if brin else Vector3.ONE * randf_range(0.05, 0.1),
						Color(0.3, 0.5, 0.14).lerp(Color(0.45, 0.58, 0.2), randf()) if brin else Color(0.36, 0.27, 0.16))
	_animer(dt)

# ---------------------------------------------------------------- animation et rendu
func _animer(dt: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var env := preload("res://scripts/env.gd")
	var vent: Vector4 = env.vals.get("wind", Vector4.ZERO)
	var v_vent := Vector3(vent.x, 0.0, vent.y) * 0.8
	# nuages : montée, vent, freinage par l'air, gonflement ; suppression en fin de vie
	var i := 0
	while i < _np.size():
		_nage[i] += dt / _nvie[i]
		if _nage[i] >= 1.0:
			_suppr_nuage(i)
			continue
		var v := _nv[i]
		v = v.lerp(v_vent + Vector3(0, _nmonte[i], 0), 1.0 - exp(-dt * 1.6))
		_nv[i] = v
		_np[i] += v * dt
		_nrot[i] += _nrv[i] * dt
		i += 1
	# tri de l'arrière vers l'avant (transparence correcte)
	var cp := cam.global_position
	var ordre := range(_np.size())
	ordre.sort_custom(func(a, b): return _np[a].distance_squared_to(cp) > _np[b].distance_squared_to(cp))
	var buf := PackedFloat32Array()
	buf.resize(_mm_n.instance_count * 20)
	var k := 0
	for j in ordre:
		var age: float = _nage[j]
		var t := lerpf(_nt0[j], _nt1[j], 1.0 - pow(1.0 - age, 2.2))      # gonfle vite puis lentement
		var a := _na[j] * minf(1.0, age * 8.0) * (1.0 - age) * (1.0 - age * 0.3)
		var p := _np[j]
		var o := k * 20
		buf[o] = 1.0; buf[o + 3] = p.x
		buf[o + 5] = 1.0; buf[o + 7] = p.y
		buf[o + 10] = 1.0; buf[o + 11] = p.z
		var c := _nc[j]
		buf[o + 12] = c.r; buf[o + 13] = c.g; buf[o + 14] = c.b; buf[o + 15] = 1.0
		buf[o + 16] = t; buf[o + 17] = _nrot[j]; buf[o + 18] = age; buf[o + 19] = a
		k += 1
	_mm_n.buffer = buf
	_mm_n.visible_instance_count = k
	# lumière du moment (soleil de main.gd)
	var m := get_parent()
	if m and m.get("_sun"):
		var sun: DirectionalLight3D = m._sun
		_mat_n.set_shader_parameter("soleil_dir", sun.global_basis.z.normalized())
		var e := clampf(sun.light_energy, 0.0, 1.6)
		_mat_n.set_shader_parameter("soleil_coul", Vector3(sun.light_color.r, sun.light_color.g, sun.light_color.b) * e * 0.75)
		_mat_n.set_shader_parameter("ambiant", Vector3(0.45, 0.5, 0.58) * clampf(0.35 + e * 0.5, 0.25, 1.0))
	# débris : balistique, rebond au sol, puis effacement
	i = 0
	while i < _dp.size():
		_dage[i] += dt
		if _dage[i] > 1.6:
			_suppr_debris(i)
			continue
		var v := _dv[i] + Vector3(0, -9.8, 0) * dt
		v *= 1.0 - dt * 0.6
		var p := _dp[i] + v * dt
		if p.y < _dsol[i] and v.y < 0.0:
			p.y = _dsol[i]
			v = Vector3(v.x * 0.4, -v.y * 0.25, v.z * 0.4)
			_drv[i] *= 0.4
		_dv[i] = v; _dp[i] = p
		_drot[i] += _drv[i] * dt
		i += 1
	var bd := PackedFloat32Array()
	bd.resize(_mm_d.instance_count * 16)
	for j in _dp.size():
		var ech := 1.0 - clampf((_dage[j] - 1.2) / 0.4, 0.0, 1.0)
		var b := Basis.from_euler(_drot[j]).scaled(_dtaille[j] * ech)
		var o := j * 16
		var p := _dp[j]
		bd[o] = b.x.x; bd[o + 1] = b.y.x; bd[o + 2] = b.z.x; bd[o + 3] = p.x
		bd[o + 4] = b.x.y; bd[o + 5] = b.y.y; bd[o + 6] = b.z.y; bd[o + 7] = p.y
		bd[o + 8] = b.x.z; bd[o + 9] = b.y.z; bd[o + 10] = b.z.z; bd[o + 11] = p.z
		var c := _dc[j]
		bd[o + 12] = c.r; bd[o + 13] = c.g; bd[o + 14] = c.b; bd[o + 15] = 1.0
	_mm_d.buffer = bd
	_mm_d.visible_instance_count = _dp.size()

func _suppr_nuage(i: int) -> void:
	var l := _np.size() - 1
	if i != l:
		_np[i] = _np[l]; _nv[i] = _nv[l]; _nage[i] = _nage[l]; _nvie[i] = _nvie[l]
		_nt0[i] = _nt0[l]; _nt1[i] = _nt1[l]; _nrot[i] = _nrot[l]; _nrv[i] = _nrv[l]
		_nmonte[i] = _nmonte[l]; _na[i] = _na[l]; _nc[i] = _nc[l]
	# (les tableaux compacts sont des valeurs : chacun est raccourci explicitement)
	_np.resize(l); _nv.resize(l); _nage.resize(l); _nvie.resize(l); _nt0.resize(l); _nt1.resize(l)
	_nrot.resize(l); _nrv.resize(l); _nmonte.resize(l); _na.resize(l); _nc.resize(l)

func _suppr_debris(i: int) -> void:
	var l := _dp.size() - 1
	if i != l:
		_dp[i] = _dp[l]; _dv[i] = _dv[l]; _dage[i] = _dage[l]; _dsol[i] = _dsol[l]
		_dtaille[i] = _dtaille[l]; _drot[i] = _drot[l]; _drv[i] = _drv[l]; _dc[i] = _dc[l]
	_dp.resize(l); _dv.resize(l); _dage.resize(l); _dsol.resize(l)
	_dtaille.resize(l); _drot.resize(l); _drv.resize(l); _dc.resize(l)
