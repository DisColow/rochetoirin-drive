## Voies ferrées (#125 : on roule dessus sans partir en vrille, passages à niveau aux barrières défonçables, pas de
## train). Tuiles world/rails/rl_tx_tz.bin de pipeline/build_rails.py, chargées autour du joueur comme sport.gd.
## - Ballast : bosse douce (dessus de 3,2 m à 0,10 m du sol, talus jusqu'à 6,4 m), seule partie qui porte la voiture (collision en
##   maillage, comme les routes : c'est une surface de roulage) ; traverses peintes par rails.gdshader.
## - Rails en volume, sans collision (aucune marche contre les roues) ; noyés au ras de la chaussée aux passages.
## - Passages à niveau : croix de Saint-André, feux rouges qui clignotent, demi-barrières baissées ; casse.gd les
##   défonce (genre « barriere », sans freiner la voiture) avec `barrieres` et `casser()`.
extends Node3D

const Relief := preload("res://scripts/relief.gd")
const PerfMon := preload("res://scripts/perf_monitor.gd")
const TILE := 256.0
const VIEW := 700.0
const DEMI := 1.6              # demi-largeur du dessus du ballast (m)
const PIED := 3.2              # demi-largeur au pied du talus : pente de ~5° (essai v6.75 : talus de 0,8 m = choc)
const BAS := 0.14              # pied du talus sous le dessus (4 cm sous le relief)
const ECART := 0.7175          # demi-écartement des rails (voie normale : 1,435 m)
const L_RAIL := 0.036          # demi-largeur d'un champignon de rail
const H_RAIL := 0.15

var target: Node3D
var terrain: Node
var tiles := {}
var loaded := {}
var barrieres := {}            # tuile -> PackedVector3Array : pied et bout de chaque bras (casse.gd)
var _bras := {}                # tuile -> Array des bras (MeshInstance3D), même ordre
var _mat: ShaderMaterial
var _m_mat: StandardMaterial3D
var _m_blanc: StandardMaterial3D
var _m_rouge: StandardMaterial3D
var _feux: Array = []          # deux feux rouges qui s'allument tour à tour
var _t := 0.0
var _clign := 0.0

func _ready() -> void:
	if not DirAccess.dir_exists_absolute("res://world/rails"):
		return
	for f in DirAccess.get_files_at("res://world/rails"):
		if f.ends_with(".bin"):
			var p := f.trim_prefix("rl_").trim_suffix(".bin").split("_")
			tiles[Vector2i(int(p[0]), int(p[1]))] = "res://world/rails/" + f
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://scripts/rails.gdshader")
	preload("res://scripts/env.gd").add(_mat)
	_m_mat = _std(Color(0.55, 0.56, 0.58), 0.5, 0.6)
	_m_blanc = _std(Color(0.93, 0.93, 0.92), 0.5, 0.0)
	_m_rouge = _std(Color(0.78, 0.07, 0.06), 0.45, 0.0)
	for i in 2:
		var m := _std(Color(0.25, 0.02, 0.02), 0.3, 0.0)
		m.emission_enabled = true
		m.emission = Color(1.0, 0.08, 0.04)
		_feux.append(m)

func _std(c: Color, r: float, me: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c; m.roughness = r; m.metallic = me
	return m

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
			if not loaded.has(k):
				_add(k)

func _process(dt: float) -> void:
	var t0_perf := Time.get_ticks_usec()
	_process_corps(dt)
	PerfMon.note("rails", Time.get_ticks_usec() - t0_perf)

func _process_corps(dt: float) -> void:
	_clign += dt                             # feux des passages à niveau : 1 s chacun
	var on := int(_clign) % 2
	for i in 2:
		_feux[i].emission_energy_multiplier = 3.0 if i == on else 0.0
	if target == null:
		return
	_t -= dt
	if _t > 0.0:
		return
	_t = 0.5
	var ws := {}
	var n := 0
	for k in _wanted(target.global_position):
		ws[k] = true
		if not loaded.has(k) and n < 1:
			_add(k); n += 1
	for k in loaded.keys():
		if not ws.has(k):
			loaded[k].queue_free()
			loaded.erase(k)
			barrieres.erase(k)
			_bras.erase(k)

# ================================================================ construction d'une tuile
func _add(k: Vector2i) -> void:
	var f := FileAccess.open(tiles[k], FileAccess.READ)
	if f == null:
		return
	var root := Node3D.new()
	var V := PackedVector3Array(); var N := PackedVector3Array(); var U := PackedVector2Array(); var C := PackedColorArray()
	var I := PackedInt32Array()
	var faces := PackedVector3Array()          # collision : dessus et talus du ballast
	var nv := f.get_32()
	for v in nv:
		var m := f.get_32()
		var raw := f.get_buffer(m * 16).to_float32_array()
		_voie(raw, m, V, N, U, C, I, faces)
	barrieres[k] = PackedVector3Array()
	_bras[k] = []
	var np_ := f.get_32()
	for p in np_:
		var q := f.get_buffer(32).to_float32_array()
		_passage(root, k, q)
	if not V.is_empty():
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = V; a[Mesh.ARRAY_NORMAL] = N; a[Mesh.ARRAY_TEX_UV] = U; a[Mesh.ARRAY_COLOR] = C
		a[Mesh.ARRAY_INDEX] = I
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		var mi := MeshInstance3D.new()
		mi.mesh = am
		mi.material_override = _mat
		root.add_child(mi)
	if not faces.is_empty():
		var sb := StaticBody3D.new()
		sb.set_meta("surface", "dirt")                       # roulement : gravier (audio.gd)
		var cs := CollisionShape3D.new()
		var sh := ConcavePolygonShape3D.new()
		sh.backface_collision = true
		sh.set_faces(faces)
		cs.shape = sh
		sb.add_child(cs)
		root.add_child(sb)
	add_child(root)
	loaded[k] = root

## Une voie : ballast (là où elle n'est pas noyée dans une chaussée) et deux rails.
func _voie(raw: PackedFloat32Array, m: int, V: PackedVector3Array, N: PackedVector3Array, U: PackedVector2Array,
		C: PackedColorArray, I: PackedInt32Array, faces: PackedVector3Array) -> void:
	var P := PackedVector3Array(); var F := PackedFloat32Array(); var S := PackedFloat32Array(); var D := PackedVector3Array()
	for i in m:
		P.append(Vector3(raw[i * 4], raw[i * 4 + 1], raw[i * 4 + 2]))
		F.append(raw[i * 4 + 3])
	var s := 0.0
	for i in m:
		if i > 0:
			s += Vector2(P[i].x - P[i - 1].x, P[i].z - P[i - 1].z).length()
		S.append(s)
		var a := P[maxi(i - 1, 0)]; var b := P[mini(i + 1, m - 1)]
		var d := Vector3(b.x - a.x, 0, b.z - a.z).normalized()
		D.append(Vector3(-d.z, 0, d.x))                      # à droite de la voie
	var ballast := func(i: int, o: float, dy: float) -> Vector3:
		return P[i] + D[i] * o + Vector3(0, dy, 0)
	for i in m - 1:
		var noye := F[i] > 0.5 or F[i + 1] > 0.5
		if not noye:
			# talus gauche, dessus, talus droit : 4 points par profil
			var prof := [[-PIED, -BAS], [-DEMI, 0.0], [DEMI, 0.0], [PIED, -BAS]]
			for j in 3:
				var q := [ballast.call(i, prof[j][0], prof[j][1]), ballast.call(i, prof[j + 1][0], prof[j + 1][1]),
					ballast.call(i + 1, prof[j + 1][0], prof[j + 1][1]), ballast.call(i + 1, prof[j][0], prof[j][1])]
				var uv := [Vector2(prof[j][0], S[i]), Vector2(prof[j + 1][0], S[i]), Vector2(prof[j + 1][0], S[i + 1]), Vector2(prof[j][0], S[i + 1])]
				_quad(q, uv, Color(0, 0, 0), V, N, U, C, I)
				faces.append_array(PackedVector3Array([q[0], q[2], q[1], q[0], q[3], q[2]]))
		# rails : dessus (et flancs hors des passages)
		for cote: float in [-1.0, 1.0]:
			var h := 0.0 if noye else H_RAIL
			var o: float = cote * ECART
			var t0: Vector3 = ballast.call(i, o - L_RAIL, h); var t1: Vector3 = ballast.call(i, o + L_RAIL, h)
			var t2: Vector3 = ballast.call(i + 1, o + L_RAIL, h); var t3: Vector3 = ballast.call(i + 1, o - L_RAIL, h)
			_quad([t0, t1, t2, t3], [Vector2(o, S[i]), Vector2(o, S[i]), Vector2(o, S[i + 1]), Vector2(o, S[i + 1])], Color(1, 1, 0), V, N, U, C, I)
			if not noye:
				for e: float in [-L_RAIL, L_RAIL]:
					var b0: Vector3 = ballast.call(i, o + e, 0.0); var b1: Vector3 = ballast.call(i + 1, o + e, 0.0)
					var h0: Vector3 = ballast.call(i, o + e, H_RAIL); var h1: Vector3 = ballast.call(i + 1, o + e, H_RAIL)
					var q := [b0, h0, h1, b1] if e < 0.0 else [h0, b0, b1, h1]
					_quad(q, [Vector2(o, S[i]), Vector2(o, S[i]), Vector2(o, S[i + 1]), Vector2(o, S[i + 1])], Color(1, 0, 0), V, N, U, C, I)

## Quadrilatère (q0 q1 q2 q3), normale calculée, deux triangles tournés vers le haut ou vers l'extérieur.
func _quad(q: Array, uv: Array, col: Color, V: PackedVector3Array, N: PackedVector3Array, U: PackedVector2Array,
		C: PackedColorArray, I: PackedInt32Array) -> void:
	var n: Vector3 = (q[2] - q[0]).cross(q[1] - q[0]).normalized()
	if n.y < 0.0 and absf(n.y) > 0.3:
		n = -n
	var b := V.size()
	for k in 4:
		V.append(q[k]); N.append(n); U.append(uv[k]); C.append(col)
	# sens des triangles : face avant vers n (Godot : face avant = sens horaire vu de devant)
	var n0: Vector3 = (q[1] - q[0]).cross(q[2] - q[0])
	if n0.dot(n) >= 0.0:
		I.append_array(PackedInt32Array([b, b + 2, b + 1, b, b + 3, b + 2]))
	else:
		I.append_array(PackedInt32Array([b, b + 1, b + 2, b, b + 2, b + 3]))

# ================================================================ passages à niveau
## q : x, y de la chaussée, z, cap de la voie, cap de la route (rad), largeur de la route, barrières (0, 1, 2),
## écart entre les voies extrêmes (ligne à double voie).
func _passage(root: Node3D, k: Vector2i, q: PackedFloat32Array) -> void:
	var c := Vector2(q[0], q[2])
	var ra := q[4]
	var r := Vector2(sin(ra), -cos(ra))                 # sens de la route
	var droite := Vector2(cos(ra), sin(ra))
	var sin_a := maxf(absf(sin(q[4] - q[3])), 0.4)
	var dist := (4.6 + q[7] * 0.5) / sin_a               # du milieu des voies à la barrière, le long de la route
	var larg := q[5]
	for sens in [1.0, -1.0]:
		var av: Vector2 = r * sens
		var dr: Vector2 = droite * sens
		var pied := c - av * dist + dr * (larg / 2.0 + 0.6)
		var y := Relief.hauteur(Vector3(pied.x, 0, pied.y))
		if is_nan(y):
			y = q[1]
		var cap := atan2(av.x, av.y)                     # rotation.y : +Z du nœud vers le sens de circulation
		var mat := Node3D.new()
		mat.position = Vector3(pied.x, y, pied.y)
		mat.rotation.y = cap
		root.add_child(mat)
		_boite(mat, Vector3(0.12, 3.3, 0.12), Vector3(0, 1.65, 0), _m_mat)
		# croix de Saint-André (blanche bordée de rouge), face au conducteur qui arrive (-Z)
		for a in [PI / 4.0, -PI / 4.0]:
			var x := _boite(mat, Vector3(1.25, 0.2, 0.03), Vector3(0, 2.85, -0.09), _m_rouge)
			x.rotation.z = a
			var x2 := _boite(mat, Vector3(1.15, 0.12, 0.03), Vector3(0, 2.85, -0.11), _m_blanc)
			x2.rotation.z = a
		# deux feux rouges qui clignotent tour à tour
		_boite(mat, Vector3(0.75, 0.32, 0.06), Vector3(0, 2.1, -0.08), _std(Color(0.05, 0.05, 0.05), 0.6, 0.0))
		for i in 2:
			var feu := MeshInstance3D.new()
			var sp := SphereMesh.new(); sp.radius = 0.11; sp.height = 0.12; sp.radial_segments = 12; sp.rings = 4
			feu.mesh = sp
			feu.material_override = _feux[i]
			feu.position = Vector3(-0.2 + 0.4 * i, 2.1, -0.14)
			mat.add_child(feu)
		if q[6] < 0.5:
			continue
		# bras de barrière baissé en travers de la voie de droite (ou de toute la route : barrières pleines)
		var lb := (larg / 2.0 + 0.4) if q[6] < 1.5 else larg + 0.6
		var bras := MeshInstance3D.new()
		var bm := BoxMesh.new(); bm.size = Vector3(lb, 0.1, 0.1)
		var m := StandardMaterial3D.new()
		m.albedo_texture = _rayures()
		m.uv1_scale = Vector3(lb / 0.8, 1, 1)
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		m.roughness = 0.5
		bm.material = m
		bras.mesh = bm
		bras.position = Vector3(lb / 2.0 + 0.08, 1.0, 0.0)   # +X du mât = gauche du conducteur : vers l'axe de la route
		mat.add_child(bras)
		var bout := pied - dr * (lb + 0.1)
		var ens: PackedVector3Array = barrieres[k]
		ens.append(Vector3(pied.x, y, pied.y)); ens.append(Vector3(bout.x, y, bout.y))
		barrieres[k] = ens
		_bras[k].append(bras)

func _boite(p: Node3D, taille: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new(); b.size = taille
	mi.mesh = b
	mi.material_override = m
	mi.position = pos
	p.add_child(mi)
	return mi

var _tex_rayures: ImageTexture
func _rayures() -> ImageTexture:
	if _tex_rayures == null:
		var im := Image.create(2, 1, false, Image.FORMAT_RGB8)
		im.set_pixel(0, 0, Color(0.85, 0.06, 0.05)); im.set_pixel(1, 0, Color(0.95, 0.95, 0.95))
		_tex_rayures = ImageTexture.create_from_image(im)
	return _tex_rayures

## Bras de barrière touché par la voiture (casse.gd) : caché et retiré de la liste ; renvoie son maillage (débris),
## sa longueur et sa position, ou [] s'il n'y en a plus là.
func casser(p: Vector3) -> Array:
	var kc := Vector2i(floori(p.x / TILE), floori(p.z / TILE))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var k := kc + Vector2i(dx, dz)
			if not barrieres.has(k):
				continue
			var ens: PackedVector3Array = barrieres[k]
			for i in range(0, ens.size() - 1, 2):
				var a := Vector2(ens[i].x, ens[i].z); var b := Vector2(ens[i + 1].x, ens[i + 1].z)
				var q := Geometry2D.get_closest_point_to_segment(Vector2(p.x, p.z), a, b)
				if q.distance_to(Vector2(p.x, p.z)) < 3.0:
					var bras: MeshInstance3D = _bras[k][i / 2]
					bras.visible = false
					# segment retiré (remplacé par un point hors d'atteinte : les indices des autres bras ne bougent pas)
					ens[i] = Vector3(0, -1000, 0); ens[i + 1] = Vector3(0, -1000, 0)
					barrieres[k] = ens
					return [bras.mesh, (bras.mesh as BoxMesh).size.x, bras.global_transform]
	return []
