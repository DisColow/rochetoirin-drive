## Clôtures, murets, haies et portails (build_fences.py) en tuiles de 256 m chargées au fil de la route.
## Les fichiers ne décrivent que les lignes et leurs réglages (quelques Mo) : les maillages sont construits ici, dans
## un fil de calcul (pas d'à-coup), puis ajoutés à la scène ; collisions près de la voiture.
## Enregistrement : en-tête de 16 flottants (type, n, couche, couche2, h0, h1, w, r, g, b, r2, g2, b2, graine, extra,
## drapeaux) puis n points (x, y, z).
extends Node3D

const TILE := 256.0
const VIEW := 520.0
const VIEW_CUT := 300.0
const COLL := 160.0
enum { HEDGE = 1, WALL, PANEL, POSTS, BOX, COLL_REC }
const F_CAPS := 1
const F_VFULL := 2
const F_CUT := 4
const F_TWO := 8
const F_FLAT := 16

var target: Node3D
var tiles := {}
var loaded := {}          # Vector2i -> Node3D
var tasks := {}           # Vector2i -> identifiant de tâche
var results := {}         # Vector2i -> [opaque, découpe, collisions] (écrit par le fil)
var bodies := {}
var colfaces := {}        # Vector2i -> PackedVector3Array
var lscale := PackedFloat32Array()
var mat: ShaderMaterial
var mat_cut: ShaderMaterial
var mutex := Mutex.new()
var _t := 0.0

func _ready() -> void:
	if not DirAccess.dir_exists_absolute("res://world/fences"):
		return
	for f in DirAccess.get_files_at("res://world/fences"):
		if not f.ends_with(".bin"):
			continue
		var p := f.trim_prefix("f_").trim_suffix(".bin").split("_")
		tiles[Vector2i(int(p[0]), int(p[1]))] = "res://world/fences/" + f
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://world/fences/meta.json"))
	for v in meta["scale"]:
		lscale.append(float(v))
	var alb = load("res://assets/fence/albedo.png")
	var nrm = load("res://assets/fence/normal.png")
	mat = ShaderMaterial.new()
	mat.shader = preload("res://scripts/fence.gdshader")
	preload("res://scripts/env.gd").add(mat)
	mat_cut = ShaderMaterial.new()
	mat_cut.shader = preload("res://scripts/fence_cut.gdshader")
	preload("res://scripts/env.gd").add(mat_cut)
	for m in [mat, mat_cut]:
		m.set_shader_parameter("albedo_tex", alb)
		m.set_shader_parameter("normal_tex", nrm)
	mat_cut.set_shader_parameter("cut", true)

func _exit_tree() -> void:
	for k in tasks:
		WorkerThreadPool.wait_for_task_completion(tasks[k])
	tasks.clear()

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

## Chargement immédiat autour de la voiture (départ, téléportation).
func update_now() -> void:
	if target == null:
		return
	for k in _wanted(target.global_position):
		if _d(k, target.global_position) < 400.0 and not loaded.has(k):
			if tasks.has(k):
				WorkerThreadPool.wait_for_task_completion(tasks[k])
				tasks.erase(k)
			else:
				_build(k, FileAccess.get_file_as_bytes(tiles[k]).to_float32_array())
			_finish(k)
	_collisions()

func _process(dt: float) -> void:
	if target == null:
		return
	# tuiles calculées : ajoutées à la scène (une par image)
	for k in tasks.keys():
		if WorkerThreadPool.is_task_completed(tasks[k]):
			WorkerThreadPool.wait_for_task_completion(tasks[k])
			tasks.erase(k)
			_finish(k)
			break
	_t -= dt
	if _t > 0:
		return
	_t = 0.25
	var want := _wanted(target.global_position)
	var ws := {}
	for k in want:
		ws[k] = true
	var started := 0
	for k in want:
		if not loaded.has(k) and not tasks.has(k) and started < 2 and tasks.size() < 3:
			var data := FileAccess.get_file_as_bytes(tiles[k]).to_float32_array()
			tasks[k] = WorkerThreadPool.add_task(_build.bind(k, data))
			started += 1
	for k in loaded.keys():
		if not ws.has(k):
			loaded[k].queue_free()
			loaded.erase(k)
			bodies.erase(k)
			colfaces.erase(k)
	_collisions()

func _finish(k: Vector2i) -> void:
	mutex.lock()
	var r: Array = results.get(k, [])
	results.erase(k)
	mutex.unlock()
	if r.is_empty() or loaded.has(k):
		return
	var root := Node3D.new()
	for j in 2:
		var S: Dictionary = r[j]
		if S.v.size() == 0:
			continue
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = S.v; arr[Mesh.ARRAY_NORMAL] = S.n; arr[Mesh.ARRAY_TEX_UV] = S.uv
		arr[Mesh.ARRAY_TEX_UV2] = S.uv2; arr[Mesh.ARRAY_COLOR] = S.c; arr[Mesh.ARRAY_INDEX] = S.i
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.material_override = mat_cut if j == 1 else mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if j == 1 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mi.visibility_range_end = VIEW_CUT if j == 1 else VIEW
		mi.visibility_range_end_margin = 60.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		root.add_child(mi)
	add_child(root)
	loaded[k] = root
	colfaces[k] = r[2]

func _collisions() -> void:
	var p := target.global_position
	for k in loaded.keys():
		var need := _d(k, p) < COLL + TILE * 0.71
		if need and not bodies.has(k) and colfaces.has(k) and colfaces[k].size() > 0:
			var sb := StaticBody3D.new()
			var cs := CollisionShape3D.new()
			var sh := ConcavePolygonShape3D.new()
			sh.backface_collision = true
			sh.set_faces(colfaces[k])
			cs.shape = sh
			sb.add_child(cs)
			loaded[k].add_child(sb)
			bodies[k] = sb
		elif not need and bodies.has(k):
			bodies[k].queue_free()
			bodies.erase(k)

# ------------------------------------------------------------------------------------------------ construction (fil)
static func _surf() -> Dictionary:
	return {"v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array(), "uv2": PackedVector2Array(),
		"c": PackedColorArray(), "i": PackedInt32Array()}

## Sommet ; renvoie son indice.
static func _vx(S: Dictionary, p: Vector3, n: Vector3, uv: Vector2, layer: float, tint: Color) -> int:
	S.v.append(p); S.n.append(n); S.uv.append(uv); S.uv2.append(Vector2(layer, 0)); S.c.append(tint)
	return S.v.size() - 1

## Triangles du quadrilatère a b c d (indices), face avant du côté de n (Godot : sens horaire = face avant).
static func _quad(S: Dictionary, a: int, b: int, c: int, d: int, n: Vector3) -> void:
	var pa: Vector3 = S.v[a]
	var cr: Vector3 = (S.v[b] - pa).cross(S.v[c] - pa)
	if cr.length_squared() < 1e-12:
		cr = (S.v[c] - pa).cross(S.v[d] - pa)
	if cr.dot(n) > 0.0:
		S.i.append_array([a, c, b, a, d, c])
	else:
		S.i.append_array([a, b, c, a, c, d])

## Normales latérales en onglet et abscisses curvilignes d'une polyligne.
static func _frame(P: PackedVector3Array) -> Array:
	var n := P.size()
	var lat := PackedVector3Array(); lat.resize(n)
	var s := PackedFloat32Array(); s.resize(n)
	var t := PackedVector3Array(); t.resize(n - 1)
	for i in n - 1:
		var d := Vector3(P[i + 1].x - P[i].x, 0, P[i + 1].z - P[i].z)
		s[i + 1] = s[i] + d.length()
		t[i] = d.normalized() if d.length() > 1e-5 else Vector3(1, 0, 0)
	for i in n:
		var tv: Vector3
		if i == 0:
			tv = t[0]
		elif i == n - 1:
			tv = t[n - 2]
		else:
			tv = (t[i - 1] + t[i]).normalized()
			if tv.length() < 1e-4:
				tv = t[i]
		var nl := Vector3(-tv.z, 0, tv.x)
		var k := 1.0
		if i > 0 and i < n - 1:
			k = clampf(absf(Vector3(-t[i - 1].z, 0, t[i - 1].x).dot(nl)), 0.5, 1.0)
		lat[i] = nl / k
	return [lat, s]

func _build(k: Vector2i, a: PackedFloat32Array) -> void:
	var op := _surf()
	var cut := _surf()
	var col := PackedVector3Array()
	var o := 0
	while o + 16 <= a.size():
		var typ := int(a[o]); var n := int(a[o + 1])
		var layer := a[o + 2]; var layer2 := a[o + 3]
		var h0 := a[o + 4]; var h1 := a[o + 5]; var w := a[o + 6]
		var tint := Color(a[o + 7], a[o + 8], a[o + 9])
		var t2 := Vector3(a[o + 10], a[o + 11], a[o + 12])
		var seed := a[o + 13]; var extra := a[o + 14]; var flags := int(a[o + 15])
		var P := PackedVector3Array(); P.resize(n)
		for i in n:
			var q := o + 16 + i * 3
			P[i] = Vector3(a[q], a[q + 1], a[q + 2])
		o += 16 + n * 3
		match typ:
			HEDGE: _hedge(op, cut, P, layer, layer2, h1, w, tint, seed)
			WALL: _wall(op, P, layer, h0, h1, w, tint, flags & F_CAPS != 0)
			PANEL: _panel(cut if flags & F_CUT else op, P, layer, h0, h1, w, tint, flags)
			POSTS: _posts(op, P, layer, h0, h1, w, extra, tint)
			BOX: _box(op, P[0], Vector3(t2.x, 0, t2.y), w, extra, h0, h1, layer, tint)
			COLL_REC: _coll(col, P, h1)
	mutex.lock()
	results[k] = [op, cut, col]
	mutex.unlock()

func _hedge(S: Dictionary, C: Dictionary, P: PackedVector3Array, layer: float, bord: float, h: float, w: float, tint: Color, seed: float) -> void:
	var fr := _frame(P)
	var lat: PackedVector3Array = fr[0]; var s: PackedFloat32Array = fr[1]
	var sc := lscale[int(layer)]
	# profil : base plus étroite et enterrée, flancs bombés, sommet arrondi
	var prof := [Vector2(-0.42, -0.25), Vector2(-0.5, 0.35), Vector2(-0.5, 0.82), Vector2(-0.3, 1.0),
		Vector2(0.3, 1.0), Vector2(0.5, 0.82), Vector2(0.5, 0.35), Vector2(0.42, -0.25)]
	var np_ := prof.size()
	# normales du profil (lissées) et longueur développée (v)
	var pn := []
	var pv := PackedFloat32Array(); pv.resize(np_)
	for j in np_:
		var pa: Vector2 = prof[maxi(j - 1, 0)]; var pb: Vector2 = prof[mini(j + 1, np_ - 1)]
		var d := Vector2((pb.x - pa.x) * w, (pb.y - pa.y) * h)
		var nn := Vector2(d.y, -d.x).normalized()
		if nn.x * prof[j].x < 0.0 or (absf(prof[j].x) < 0.35 and nn.y < 0.0):
			nn = -nn
		pn.append(nn)
		if j > 0:
			pv[j] = pv[j - 1] + Vector2((prof[j].x - prof[j - 1].x) * w, (prof[j].y - prof[j - 1].y) * h).length()
	var kw := PackedFloat32Array(); var kh := PackedFloat32Array()
	kw.resize(P.size()); kh.resize(P.size())
	for i in P.size():
		var ph := s[i] * 0.9 + seed
		kw[i] = 1.0 + 0.07 * sin(ph) + 0.04 * sin(ph * 2.7 + 1.0)
		kh[i] = 1.0 + 0.05 * sin(ph * 0.6 + 2.0)
	var base: int = S.v.size()
	for i in P.size():
		for j in np_:
			var pr: Vector2 = prof[j]
			var nn: Vector2 = pn[j]
			var lv: Vector3 = lat[i]
			var p := P[i] + lv * (pr.x * w * kw[i]) + Vector3(0, pr.y * h * kh[i], 0)
			var nrm := (lv.normalized() * nn.x + Vector3(0, nn.y, 0)).normalized()
			_vx(S, p, nrm, Vector2(s[i] / sc, pv[j] / sc), layer, tint)
	for i in P.size() - 1:
		for j in np_ - 1:
			var a: int = base + i * np_ + j
			var outn: Vector3 = S.n[a] + S.n[a + 1] + S.n[a + np_]
			_quad(S, a, a + np_, a + np_ + 1, a + 1, outn)
	# bouts arrondis : éventail sur le profil
	for e in [0, P.size() - 1]:
		var tdir := Vector3(lat[e].z, 0, -lat[e].x).normalized() * (-1.0 if e == 0 else 1.0)
		var c0: int = S.v.size()
		var cen := P[e] + Vector3(0, h * 0.45, 0) + tdir * w * 0.25
		_vx(S, cen, tdir, Vector2(0.0, -h * 0.45 / sc), layer, tint)
		for j in np_:
			_vx(S, S.v[base + e * np_ + j], (tdir + S.n[base + e * np_ + j]).normalized(), Vector2(prof[j].x * w / sc, -prof[j].y * h / sc), layer, tint)
		for j in np_ - 1:
			var pa: Vector3 = S.v[c0 + 1 + j]
			var cr: Vector3 = (S.v[c0 + 2 + j] - pa).cross(cen - pa)
			if cr.dot(tdir) > 0.0:
				S.i.append_array([c0, c0 + 2 + j, c0 + 1 + j])
			else:
				S.i.append_array([c0, c0 + 1 + j, c0 + 2 + j])
	# bord feuillu découpé au sommet (silhouette irrégulière)
	var bsc := lscale[int(bord)]
	for off: float in [-0.22, 0.22]:
		var b0: int = C.v.size()
		for i in P.size():
			var lv: Vector3 = lat[i]
			var p := P[i] + lv * (off * w * kw[i])
			var top := h * kh[i]
			var nrm := lv.normalized() * signf(off)
			_vx(C, p + Vector3(0, top - 0.3, 0), nrm, Vector2(s[i] / bsc, 1.0), bord, tint)
			_vx(C, p + Vector3(0, top + 0.18, 0), nrm, Vector2(s[i] / bsc, 0.0), bord, tint)
		for i in P.size() - 1:
			var a: int = b0 + i * 2
			_quad(C, a, a + 2, a + 3, a + 1, C.n[a])

func _wall(S: Dictionary, P: PackedVector3Array, layer: float, h0: float, h1: float, w: float, tint: Color, caps: bool) -> void:
	var fr := _frame(P)
	var lat: PackedVector3Array = fr[0]; var s: PackedFloat32Array = fr[1]
	var sc := lscale[int(layer)]
	var up := Vector3.UP
	# trois faces : côté -, dessus, côté +
	var faces := [[-w, h0, -w, h1], [-w, h1, w, h1], [w, h1, w, h0]]
	for f in faces:
		var b0: int = S.v.size()
		for i in P.size():
			var lv: Vector3 = lat[i]
			var pa := P[i] + lv * float(f[0]) + up * float(f[1])
			var pb := P[i] + lv * float(f[2]) + up * float(f[3])
			var nrm: Vector3 = up if f[1] == f[3] else lv.normalized() * signf(float(f[0]))
			var v0 := 0.0 if f[1] == f[3] else -float(f[1]) / sc
			var v1 := 2.0 * w / sc if f[1] == f[3] else -float(f[3]) / sc
			_vx(S, pa, nrm, Vector2(s[i] / sc, v0), layer, tint)
			_vx(S, pb, nrm, Vector2(s[i] / sc, v1), layer, tint)
		for i in P.size() - 1:
			var a: int = b0 + i * 2
			_quad(S, a, a + 2, a + 3, a + 1, S.n[a])
	if caps:
		for e in [0, P.size() - 1]:
			var lv: Vector3 = lat[e]
			var tdir := Vector3(lv.z, 0, -lv.x).normalized() * (-1.0 if e == 0 else 1.0)
			var q := [P[e] - lv * w + up * h0, P[e] + lv * w + up * h0, P[e] + lv * w + up * h1, P[e] - lv * w + up * h1]
			var b0: int = S.v.size()
			for j in 4:
				_vx(S, q[j], tdir, Vector2((j % 3 != 0) as int * 2.0 * w / sc, -(h0 if j < 2 else h1) / sc), layer, tint)
			_quad(S, b0, b0 + 1, b0 + 2, b0 + 3, tdir)

func _panel(S: Dictionary, P: PackedVector3Array, layer: float, h0: float, h1: float, w: float, tint: Color, flags: int) -> void:
	var fr := _frame(P)
	var lat: PackedVector3Array = fr[0]; var s: PackedFloat32Array = fr[1]
	var sc := lscale[int(layer)]
	var vfull := flags & F_VFULL != 0
	var ymin := INF
	if flags & F_FLAT:
		for p in P:
			ymin = minf(ymin, p.y)
	var sides := [1.0, -1.0] if flags & F_TWO else [0.0]
	for sd in sides:
		var b0: int = S.v.size()
		for i in P.size():
			var lv: Vector3 = lat[i]
			var p := P[i] + lv * (w * float(sd))
			if flags & F_FLAT:
				p.y = ymin
			var nrm := lv.normalized() * (float(sd) if sd != 0.0 else 1.0)
			var u := s[i] / sc if not vfull or flags & F_FLAT == 0 else s[i] / maxf(s[P.size() - 1], 0.01)
			_vx(S, p + Vector3(0, h0, 0), nrm, Vector2(u, 1.0 if vfull else -h0 / sc), layer, tint)
			_vx(S, p + Vector3(0, h1, 0), nrm, Vector2(u, 0.0 if vfull else -h1 / sc), layer, tint)
		for i in P.size() - 1:
			var a: int = b0 + i * 2
			_quad(S, a, a + 2, a + 3, a + 1, S.n[a])

func _posts(S: Dictionary, P: PackedVector3Array, layer: float, h0: float, h: float, size: float, every: float, tint: Color) -> void:
	var fr := _frame(P)
	var s: PackedFloat32Array = fr[1]
	var total := s[P.size() - 1]
	var cnt := maxi(1, roundi(total / every))
	var i := 0
	for k in cnt + 1:
		var t := total * k / cnt
		while i < P.size() - 2 and s[i + 1] < t:
			i += 1
		var f := clampf((t - s[i]) / maxf(s[i + 1] - s[i], 1e-5), 0.0, 1.0)
		var p := P[i].lerp(P[i + 1], f)
		var d := (P[i + 1] - P[i]); d.y = 0
		_box(S, p, d.normalized(), size, size, h0, h, layer, tint)

func _box(S: Dictionary, c: Vector3, dir: Vector3, w: float, dd: float, y0: float, h: float, layer: float, tint: Color) -> void:
	if dir.length() < 1e-4:
		dir = Vector3(1, 0, 0)
	dir = dir.normalized()
	var u := dir * w * 0.5
	var v := Vector3(-dir.z, 0, dir.x) * dd * 0.5
	var base := c + Vector3(0, y0, 0)
	var up := Vector3(0, h, 0)
	var sc := lscale[int(layer)]
	for f in [[-u - v, u - v, -v], [u - v, u + v, u], [u + v, -u + v, v], [-u + v, -u - v, -u]]:
		var pa: Vector3 = base + f[0]; var pb: Vector3 = base + f[1]
		var nrm: Vector3 = (f[2] as Vector3).normalized()
		var L := pa.distance_to(pb) / sc
		var b0: int = S.v.size()
		_vx(S, pa, nrm, Vector2(0, h / sc), layer, tint)
		_vx(S, pb, nrm, Vector2(L, h / sc), layer, tint)
		_vx(S, pb + up, nrm, Vector2(L, 0), layer, tint)
		_vx(S, pa + up, nrm, Vector2(0, 0), layer, tint)
		_quad(S, b0, b0 + 1, b0 + 2, b0 + 3, nrm)
	var b1: int = S.v.size()
	var q := [-u - v, u - v, u + v, -u + v]
	for j in 4:
		_vx(S, base + up + q[j], Vector3.UP, Vector2((j == 1 or j == 2) as int * w / sc, (j >= 2) as int * dd / sc), layer, tint)
	_quad(S, b1, b1 + 1, b1 + 2, b1 + 3, Vector3.UP)

static func _coll(col: PackedVector3Array, P: PackedVector3Array, h: float) -> void:
	for i in P.size() - 1:
		var a := P[i] - Vector3(0, 0.3, 0); var b := P[i + 1] - Vector3(0, 0.3, 0)
		var a2 := P[i] + Vector3(0, h, 0); var b2 := P[i + 1] + Vector3(0, h, 0)
		col.append_array([a, b, b2, a, b2, a2])
