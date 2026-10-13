## Décor destructible (v6.9, issue #7) : panneaux de signalisation, lampadaires, clôtures (grillages, panneaux,
## poteaux ; pas les murets ni les haies) et petits arbres (moins de 9 m : les gros restent des obstacles) sont
## renversés quand la voiture les touche.
## - Détection avant le contact : boîte de la voiture (meta.json) élargie du rayon de l'objet ; candidats proches
##   relevés toutes les 0,2 s (panneaux : world/panneaux.bin de build_casse.py ; lampadaires : poles.pieds ;
##   arbres : vegetation.data ; clôtures : fences.lignes), testés à chaque pas de physique.
## - L'objet disparaît de son lot (exemplaire caché, ou sommets effacés par le shader : env_casse, uniform casse_pts) et
##   un débris physique part dans le sens du choc, roule, puis s'efface au bout de 15 s.
## - La voiture perd un peu de vitesse selon l'objet ; son du choc selon la matière ; poussière et éclats (dust.gd).
## Tout réapparaît quand la tuile est rechargée (on revient plus tard).
extends Node3D

const Env := preload("res://scripts/env.gd")
const PerfMon := preload("res://scripts/perf_monitor.gd")
const VIE := 15.0                 # durée de vie d'un débris (s)
const MAX_DEBRIS := 10
const ARBRE_MAX := 9.0            # hauteur maximale d'un arbre cassable (m)
const GRILLE := 16.0
# perte de vitesse (part), son, rayon de l'objet (m)
const KINDS := {
	"panneau": [0.06, "choc_leger_%d", 0.12],
	"lampadaire": [0.22, "choc_dur_%d", 0.18],
	"arbre": [0.14, "choc_bois_%d", 0.2],
	"cloture": [0.1, "choc_bois_%d", 0.1],
}

var main: Node
var car: VehicleBody3D
var poles: Node
var vegetation: Node
var fences: Node
var _hw := 0.95                   # demi-largeur, demi-longueur de la voiture
var _hl := 2.6
var _panneaux := {}               # case de 16 m -> Array de Vector4 (x, y du pied, z, hauteur)
var _arbres := {}                 # tuile -> [arbres affichés, {case de 16 m -> PackedInt32Array (indices cassables)}]
var _proches: Array = []          # [genre, données…] relevés toutes les 0,2 s
var _t := 0.0
var _casses: Array = []           # points déjà cassés (Vector3) : pas deux fois
var _pts: Array = []              # points effacés par le shader (Vector4), 16 au plus
var _debris: Array = []           # [RigidBody3D, âge]
var _pas := 0

func _ready() -> void:
	_preparer_reserve()
	var meta_p := "res://assets/car/meta.json"
	if FileAccess.file_exists(meta_p):
		var m = JSON.parse_string(FileAccess.get_file_as_string(meta_p))
		if m is Dictionary and m.has("box"):
			_hw = float(m.box[0]) * 0.5
			_hl = float(m.box[2]) * 0.5
	if FileAccess.file_exists("res://world/panneaux.bin"):
		var b := FileAccess.get_file_as_bytes("res://world/panneaux.bin")
		var n := b.decode_u32(0)
		for i in n:
			var o := 4 + i * 16
			var p := Vector4(b.decode_float(o), b.decode_float(o + 4), b.decode_float(o + 8), b.decode_float(o + 12))
			var k := Vector2i(floori(p.x / GRILLE), floori(p.z / GRILLE))
			if not _panneaux.has(k):
				_panneaux[k] = []
			_panneaux[k].append(p)
	if OS.get_cmdline_user_args().has("--casse-test"):
		essai.call_deferred()
	if OS.get_cmdline_user_args().has("--casse-debug"):
		print("[casse] panneaux : ", _panneaux.size(), " cases ; boîte voiture ", _hw, " × ", _hl)

func _physics_process(dt: float) -> void:
	var t0 := Time.get_ticks_usec()
	_pas_corps(dt)
	PerfMon.note("casse", Time.get_ticks_usec() - t0)

func _pas_corps(dt: float) -> void:
	if car == null:
		return
	_vieillir(dt)
	var v := car.linear_velocity
	_t -= dt
	if _t <= 0.0:
		_t = 0.2
		_relever()
	if v.length() < 1.2 or _proches.is_empty():
		return
	var inv := car.global_transform.affine_inverse()
	for it in _proches:
		match it[0]:
			"cloture":
				var a: Vector3 = it[1]; var b: Vector3 = it[2]
				var c := car.global_position
				var ab := Vector2(b.x - a.x, b.z - a.z)
				var tt := clampf(Vector2(c.x - a.x, c.z - a.z).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
				var q := a.lerp(b, tt)
				if _touche(inv, q, KINDS.cloture[2]) and not _deja(q, 2.2):
					_casser("cloture", q, it)
					return
			_:
				var p: Vector3 = it[1]
				if _touche(inv, p, KINDS[it[0]][2]) and not _deja(p, 0.5):
					_casser(it[0], p, it)
					return

func _touche(inv: Transform3D, p: Vector3, r: float) -> bool:
	var l := inv * p
	return absf(l.x) < _hw + r and absf(l.z) < _hl + r and l.y > -2.0 and l.y < 2.5

func _deja(p: Vector3, r: float) -> bool:
	for q in _casses:
		if Vector2(q.x - p.x, q.z - p.z).length() < r:
			return true
	return false

## Candidats à moins de 30 m de la voiture.
func _relever() -> void:
	_proches.clear()
	var c := car.global_position
	var R := 30.0
	var R2 := R * R
	var kc := Vector2i(floori(c.x / GRILLE), floori(c.z / GRILLE))
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			for p: Vector4 in _panneaux.get(kc + Vector2i(dx, dz), []):
				if Vector2(p.x - c.x, p.z - c.z).length_squared() < R2:
					_proches.append(["panneau", Vector3(p.x, p.y, p.z), p.w])
	var tiles := []
	for dx in [-R, R]:
		for dz in [-R, R]:
			var k := Vector2i(floori((c.x + dx) / 256.0), floori((c.z + dz) / 256.0))
			if not tiles.has(k):
				tiles.append(k)
	for k in tiles:
		if poles and poles.pieds.has(k):
			for p: Vector3 in poles.pieds[k]:
				if Vector2(p.x - c.x, p.z - c.z).length_squared() < R2:
					_proches.append(["lampadaire", p])
		if fences and fences.lignes.has(k):
			var L: PackedVector3Array = fences.lignes[k]
			var g: Dictionary = _grille_lignes(k)
			var vus := {}
			for gx in range(-2, 3):
				for gz in range(-2, 3):
					for i: int in g.get(kc + Vector2i(gx, gz), PackedInt32Array()):
						if vus.has(i):
							continue
						vus[i] = true
						_proches.append(["cloture", L[i], L[i + 1]])
		if vegetation and vegetation.data.has(k):
			var g: Dictionary = _grille_arbres(k)
			var a: PackedFloat32Array = vegetation.data[k]
			for gx in range(-2, 3):
				for gz in range(-2, 3):
					for i: int in g.get(kc + Vector2i(gx, gz), PackedInt32Array()):
						var o: int = i * 8
						var h: float = a[o + 3]
						if h <= 0.0 or h >= ARBRE_MAX:
							continue
						if Vector2(a[o] - c.x, a[o + 2] - c.z).length_squared() < R2:
							_proches.append(["arbre", Vector3(a[o], a[o + 1], a[o + 2]), k, i])

## Segments de clôtures cassables d'une tuile rangés par cases de 16 m (chaque case traversée par le segment).
var _lignes := {}
func _grille_lignes(k: Vector2i) -> Dictionary:
	var L: PackedVector3Array = fences.lignes[k]
	if _lignes.has(k) and _lignes[k][0] == L.size():
		return _lignes[k][1]
	for kk in _lignes.keys():
		if not fences.lignes.has(kk):
			_lignes.erase(kk)
	var g := {}
	for i in range(0, L.size() - 1, 2):
		var a := L[i]; var b := L[i + 1]
		var n := int(ceil(a.distance_to(b) / 6.0)) + 1
		for j in n + 1:
			var p := a.lerp(b, float(j) / n)
			var kk := Vector2i(floori(p.x / GRILLE), floori(p.z / GRILLE))
			if not g.has(kk):
				g[kk] = PackedInt32Array()
			var l: PackedInt32Array = g[kk]
			if l.is_empty() or l[-1] != i:
				l.append(i)
			g[kk] = l
	_lignes[k] = [L.size(), g]
	return g

## Arbres cassables d'une tuile rangés par cases de 16 m (fait une fois par tuile chargée).
func _grille_arbres(k: Vector2i) -> Dictionary:
	# seulement les arbres affichés (vegetation.visibles : densité réglable) ; refaite si le niveau change
	var nv: int = vegetation.visibles(k)
	if _arbres.has(k) and _arbres[k][0] == nv:
		return _arbres[k][1]
	for kk in _arbres.keys():
		if not vegetation.data.has(kk):
			_arbres.erase(kk)
	var g := {}
	var a: PackedFloat32Array = vegetation.data[k]
	for i in nv:
		var o: int = i * 8
		if a[o + 3] <= 0.0 or a[o + 3] >= ARBRE_MAX:
			continue
		var kk := Vector2i(floori(a[o] / GRILLE), floori(a[o + 2] / GRILLE))
		if not g.has(kk):
			g[kk] = PackedInt32Array()
		var l: PackedInt32Array = g[kk]
		l.append(i)
		g[kk] = l
	_arbres[k] = [nv, g]
	return g

# ---------------------------------------------------------------- casse
func _casser(genre: String, p: Vector3, it: Array) -> void:
	_casses.append(p)
	if _casses.size() > 200:
		_casses.pop_front()
	var v := car.linear_velocity
	var spd := v.length()
	var dir := v / maxf(spd, 0.01)
	var corps: RigidBody3D = null
	match genre:
		"panneau":
			var h: float = it[2]
			_effacer(Vector4(p.x, p.z, 0.75, p.y + 0.5))
			corps = _corps_panneau(h)
			corps.global_position = p + Vector3(0, h * 0.5 + 0.35, 0)
		"lampadaire":
			var m: Mesh = poles.casser(p)
			corps = _corps_modele(m, 4.05, 0.16, 140.0)
			corps.global_position = p + Vector3(0, 2.0, 0)
		"arbre":
			var r: Array = vegetation.casser(it[2], it[3])
			if r.is_empty():
				return
			var h: float = r[1]
			corps = _corps_modele(r[0], h, clampf(h * 0.018, 0.08, 0.16), 40.0 + h * 25.0, h)
			corps.global_position = p + Vector3(0, h * 0.5, 0)
			corps.rotation.y = r[2]
		"cloture":
			_effacer(Vector4(p.x, p.z, 1.7, p.y - 0.3))
			fences.breche(p, 1.9)
			corps = _corps_cloture()
			corps.global_position = p + Vector3(0, 0.7, 0)
	var k: Array = KINDS[genre]
	car.linear_velocity = v * (1.0 - float(k[0]) * clampf(spd / 12.0, 0.3, 1.0))
	if corps:
		car.add_collision_exception_with(corps)
		corps.linear_velocity = dir * spd * randf_range(0.75, 1.0) + Vector3(0, randf_range(1.5, 3.5), 0)
		corps.angular_velocity = dir.cross(Vector3.UP) * -randf_range(2.0, 4.0) + Vector3(0, randf_range(-1.5, 1.5), 0)
		_debris.append([corps, 0.0])
		while _debris.size() > MAX_DEBRIS:
			_rendre(_debris.pop_front()[0])
	if main and main.get("sound") and main.sound.has_method("_one_shot"):
		main.sound._one_shot(str(k[1]) % (randi() % 5), p + Vector3(0, 1, 0), clampf(spd / 10.0, 0.4, 1.0), randf_range(0.9, 1.1))
	if main and main.get("dust"):
		var D = main.dust
		var mat: Dictionary = D.MATIERES.get("poussiere", {})
		for i in 5:
			if not mat.is_empty():
				D._nuage(mat, p + Vector3(randf_range(-0.6, 0.6), randf_range(0.2, 1.0), randf_range(-0.6, 0.6)), dir * spd * 0.2 + Vector3(0, 0.5, 0), 0.8)
		var col := Color(0.35, 0.27, 0.18) if genre == "arbre" or genre == "cloture" else Color(0.55, 0.56, 0.58)
		for i in 8:
			D._debris(p + Vector3(randf_range(-0.4, 0.4), randf_range(0.3, 1.5), randf_range(-0.4, 0.4)),
				dir * spd * randf_range(0.3, 0.8) + Vector3(randf_range(-2, 2), randf_range(2, 5), randf_range(-2, 2)),
				p.y, Vector3(randf_range(0.04, 0.15), randf_range(0.02, 0.06), randf_range(0.04, 0.2)), col)
	if OS.get_cmdline_user_args().has("--casse-debug"):
		print("[casse] ", genre, " renversé en ", p, " à ", int(spd * 3.6), " km/h")

## Efface (shader) l'objet autour d'un point : x, z, rayon, hauteur au-dessus de laquelle tout disparaît.
func _effacer(c: Vector4) -> void:
	_pts.append(c)
	if _pts.size() > 16:
		_pts.pop_front()
	var arr := []
	for q in _pts:
		arr.append(q)
	while arr.size() < 16:
		arr.append(Vector4.ZERO)
	Env.set_value("casse_pts", arr)
	Env.set_value("casse_n", _pts.size())

# ---------------------------------------------------------------- réserve de débris (v6.19 : pas d'instanciation en jeu)
## Réserve préparée au démarrage : MAX_DEBRIS corps rigides, chacun avec 3 emplacements de maillage et une boîte de
## collision (BoxShape3D seulement) ; un débris est pris dans la réserve, habillé (maillages et boîte selon l'objet
## renversé), puis rendu (caché, figé, sans collision) à la fin de sa vie ou quand la réserve est pleine. Plus aucun
## new()/queue_free() pendant la conduite. Les maillages des panneaux et clôtures sont créés une seule fois.
var _reserve: Array = []           # RigidBody3D libres
var _mats := {}
var _mailles := {}

func _preparer_reserve() -> void:
	var m_metal := StandardMaterial3D.new(); m_metal.albedo_color = Color(0.62, 0.63, 0.65); m_metal.metallic = 0.8; m_metal.roughness = 0.35
	var m_rouge := StandardMaterial3D.new(); m_rouge.albedo_color = Color(0.85, 0.1, 0.1); m_rouge.roughness = 0.45
	var m_blanc := StandardMaterial3D.new(); m_blanc.albedo_color = Color(0.95, 0.95, 0.95); m_blanc.roughness = 0.45
	var m_grille := StandardMaterial3D.new(); m_grille.albedo_color = Color(0.22, 0.27, 0.22); m_grille.roughness = 0.6; m_grille.metallic = 0.4
	var face := CylinderMesh.new(); face.top_radius = 0.36; face.bottom_radius = 0.36; face.height = 0.03; face.radial_segments = 16; face.material = m_rouge
	var inner := CylinderMesh.new(); inner.top_radius = 0.27; inner.bottom_radius = 0.27; inner.height = 0.035; inner.radial_segments = 16; inner.material = m_blanc
	var poteau := BoxMesh.new(); poteau.size = Vector3(0.06, 1.4, 0.06); poteau.material = m_grille
	var grille := BoxMesh.new(); grille.size = Vector3(1.8, 1.1, 0.02); grille.material = m_grille
	_mats["metal"] = m_metal
	_mailles = {"face": face, "inner": inner, "poteau": poteau, "grille": grille, "mats": {}}
	for i in MAX_DEBRIS:
		var rb := RigidBody3D.new()
		rb.collision_layer = 1
		rb.collision_mask = 1
		rb.continuous_cd = true
		for k in 3:
			rb.add_child(MeshInstance3D.new())
		var cs := CollisionShape3D.new()
		cs.shape = BoxShape3D.new()
		rb.add_child(cs)
		add_child(rb)
		_rendre(rb)

func _rendre(rb: RigidBody3D) -> void:
	rb.freeze = true
	rb.visible = false
	(rb.get_child(3) as CollisionShape3D).disabled = true
	rb.global_position = Vector3(0, -1000, 0)
	if car and is_instance_valid(car):
		car.remove_collision_exception_with(rb)
	if not _reserve.has(rb):
		_reserve.append(rb)

func _prendre(masse: float, boite: Vector3) -> RigidBody3D:
	if _reserve.is_empty():
		var d: Array = _debris.pop_front()            # réserve vide : on reprend le plus vieux débris
		_rendre(d[0])
	var rb: RigidBody3D = _reserve.pop_back()
	rb.mass = masse
	for k in 3:
		var mi: MeshInstance3D = rb.get_child(k)
		mi.mesh = null; mi.transform = Transform3D.IDENTITY; mi.set_meta("e", 1.0)
	var cs: CollisionShape3D = rb.get_child(3)
	(cs.shape as BoxShape3D).size = boite
	cs.disabled = false
	rb.rotation = Vector3.ZERO
	rb.linear_velocity = Vector3.ZERO
	rb.angular_velocity = Vector3.ZERO
	rb.visible = true
	rb.freeze = false
	return rb

func _corps_modele(m: Mesh, h: float, r: float, masse: float, echelle := 1.0) -> RigidBody3D:
	var rb := _prendre(masse, Vector3(maxf(r, 0.1) * 2.0, h, maxf(r, 0.1) * 2.0))
	var mi: MeshInstance3D = rb.get_child(0)
	mi.mesh = m
	mi.scale = Vector3.ONE * echelle
	mi.set_meta("e", echelle)
	mi.position = Vector3(0, -h * 0.5, 0)
	return rb

func _corps_panneau(h: float) -> RigidBody3D:
	var rb := _prendre(25.0, Vector3(0.7, h, 0.12))
	var cle := "mat%d" % int(h * 10)
	if not _mailles.mats.has(cle):
		var cm := CylinderMesh.new(); cm.top_radius = 0.035; cm.bottom_radius = 0.035; cm.height = h; cm.radial_segments = 8
		cm.material = _mats.metal
		_mailles.mats[cle] = cm
	(rb.get_child(0) as MeshInstance3D).mesh = _mailles.mats[cle]
	var face: MeshInstance3D = rb.get_child(1)
	face.mesh = _mailles.face
	face.rotation = Vector3(PI * 0.5, 0, 0)
	face.position = Vector3(0, h * 0.5 - 0.35, 0.05)
	var inner: MeshInstance3D = rb.get_child(2)
	inner.mesh = _mailles.inner
	inner.rotation = face.rotation
	inner.position = face.position + Vector3(0, 0, 0.002)
	return rb

func _corps_cloture() -> RigidBody3D:
	var rb := _prendre(30.0, Vector3(1.9, 1.3, 0.1))
	for i in 3:
		var mi: MeshInstance3D = rb.get_child(i)
		mi.mesh = _mailles.poteau if i < 2 else _mailles.grille
		mi.position = Vector3(-0.9 + i * 1.8, 0, 0) if i < 2 else Vector3.ZERO
	return rb

## Débris : rétrécissent pendant la dernière seconde puis disparaissent.
func _vieillir(dt: float) -> void:
	for i in range(_debris.size() - 1, -1, -1):
		var d: Array = _debris[i]
		var rb: RigidBody3D = d[0]
		if not is_instance_valid(rb):
			_debris.remove_at(i)
			continue
		d[1] += dt
		if d[1] > VIE - 1.0:
			var s := clampf(VIE - d[1], 0.01, 1.0)
			for ch in rb.get_children():
				if ch is MeshInstance3D:
					ch.scale = Vector3.ONE * s * (ch.get_meta("e", 1.0) as float)
		if d[1] > VIE or rb.global_position.y < -500.0:
			_rendre(rb)
			_debris.remove_at(i)

# ---------------------------------------------------------------- essai : -- --casse-test
## Lance la voiture (vitesse imposée, 45 km/h) sur l'objet le plus proche de chaque genre et enregistre des captures
## dans user://shots/casse_<genre>_<n>.png ; le journal dit ce qui a été renversé.
func essai() -> void:
	while not preload("res://scripts/chargement.gd").fini:
		await get_tree().process_frame
	for i in 120:
		await get_tree().physics_frame
	DirAccess.make_dir_recursive_absolute("user://shots")
	var genres := ["panneau", "lampadaire", "arbre", "cloture"]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--casse-genres="):
			genres = Array(a.trim_prefix("--casse-genres=").split(","))
	for genre in genres:
		var c := car.global_position
		var best := Vector3.INF
		var bd := INF
		match genre:
			"panneau":
				for k in _panneaux:
					for p: Vector4 in _panneaux[k]:
						var d := Vector2(p.x - c.x, p.z - c.z).length()
						if d < bd and d > 3.0:
							bd = d; best = Vector3(p.x, p.y + 0.35, p.z)
			"lampadaire":
				for k in poles.pieds:
					for p: Vector3 in poles.pieds[k]:
						var d := Vector2(p.x - c.x, p.z - c.z).length()
						if d < bd and d > 3.0:
							bd = d; best = p
			"arbre":
				for k in vegetation.data:
					var a: PackedFloat32Array = vegetation.data[k]
					for i in vegetation.visibles(k):
						var o: int = i * 8
						if a[o + 3] > 3.0 and a[o + 3] < ARBRE_MAX:
							var d := Vector2(a[o] - c.x, a[o + 2] - c.z).length()
							if d < bd and d > 3.0:
								bd = d; best = Vector3(a[o], a[o + 1], a[o + 2])
			"cloture":
				for k in fences.lignes:
					var L: PackedVector3Array = fences.lignes[k]
					for i in range(0, L.size() - 1, 2):
						var m := (L[i] + L[i + 1]) * 0.5
						var d := Vector2(m.x - c.x, m.z - c.z).length()
						if d < bd and d > 3.0 and L[i].distance_to(L[i + 1]) > 3.0:
							bd = d; best = m
		if best == Vector3.INF:
			print("[casse] essai ", genre, " : aucun objet chargé")
			continue
		# élan court (3,6 m) depuis l'ouest : peu de chances de buter sur autre chose avant l'objet
		var f := Vector3(1, 0, 0)
		var start := best - f * (_hl + 1.0)
		start.y = best.y + 0.8
		car.place(start, 180.0 - rad_to_deg(atan2(f.x, f.z)))
		car.hold(0.3)
		for i in 40:
			await get_tree().physics_frame
		var n0 := _casses.size()
		for i in 60:
			car.linear_velocity = f * 12.5 + Vector3(0, car.linear_velocity.y, 0)
			await get_tree().physics_frame
		for i in 30:
			await get_tree().physics_frame
		var img_ok := DisplayServer.get_name() != "headless"
		if img_ok:
			get_viewport().get_texture().get_image().save_png("user://shots/casse_%s_1.png" % genre)
		var deb := ""
		if not _debris.is_empty() and is_instance_valid(_debris[-1][0]):
			deb = " ; débris en %s, %.1f m/s" % [_debris[-1][0].global_position, _debris[-1][0].linear_velocity.length()]
		print("[casse] essai ", genre, " en ", best, " : ", "renversé" if _casses.size() > n0 else "PAS renversé", ", voiture à ", int(car.kmh()), " km/h", deb)
		for i in 120:
			await get_tree().physics_frame
		if img_ok:
			get_viewport().get_texture().get_image().save_png("user://shots/casse_%s_2.png" % genre)
		if not _debris.is_empty() and is_instance_valid(_debris[-1][0]):
			print("[casse]    2 s plus tard : débris en ", _debris[-1][0].global_position, " (posé : ", _debris[-1][0].sleeping or _debris[-1][0].linear_velocity.length() < 0.5, ")")
	get_tree().quit()
