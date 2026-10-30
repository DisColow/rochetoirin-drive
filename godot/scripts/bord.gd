## Bords de la carte façon Motocross Madness (v6.22, demande de l'utilisateur ; remplace la soucoupe du gardien,
## désactivée mais conservée) : talus de build_bord.py (world/bord/, tuiles de 256 m lues en arrière-plan) tout autour
## de la zone jouable ; on peut le grimper, avec du mal (il se raidit), et au-delà de RESSORT m hors de la carte la
## voiture est catapultée vers l'intérieur, très haut et en tournoyant (v6.46, issue #45). Collisions du talus : maillage
## (c'est une surface de roulage, comme le relief), seulement près de la voiture.
extends Node3D
const PerfMon := preload("res://scripts/perf_monitor.gd")

const TILE := 256.0
const VIEW := 1500.0
const COLL := 200.0
const RESSORT := 32.0          # m hors de la carte : début du ressort (#88 : 26 m avant ; 40 m en v6.55 n'était jamais atteint, même à 100 km/h)
const RAIDEUR := 7.0           # m/s² par mètre au-delà de RESSORT
const GRILLE := 64.0

var car: VehicleBody3D
var tiles := {}
var loaded := {}
var bodies := {}
var mat: ShaderMaterial
var _chargeur = preload("res://scripts/chargeur.gd").new()
var _t := 0.0
var _segs := {}                # case de 64 m -> Array de [a, b] (côtés de la limite proches)
var _zone := PackedVector2Array()
var _rebond_t := 0.0
# #157 : bord « cascade » façon Golden Sun 2 au lieu des collines (⚙ > Conduite > Bord de la carte)
const EAU := 14.0              # m : bande d'eau du bord (la voiture y est freinée)
const MUR := 2.0               # m avant la limite : la voiture est renvoyée vers l'intérieur
const RESTITUTION := 0.45
const FREIN_EAU := 0.9         # s⁻¹ : freinage horizontal dans l'eau
var cascade := false
var cascade_node: Node3D
var _dans_eau := false
var _embruns_t := 0.0

func _ready() -> void:
	name = "Bord"
	cascade_node = preload("res://scripts/cascade.gd").new()
	add_child(cascade_node)
	var cfg := ConfigFile.new()
	if cfg.load("user://reglages.cfg") == OK and bool(cfg.get_value("affichage", "bord_cascade", false)):
		set_cascade.call_deferred(true)
	mat = ShaderMaterial.new()
	mat.shader = preload("res://scripts/bord.gdshader")
	preload("res://scripts/env.gd").add(mat)
	if DirAccess.dir_exists_absolute("res://world/bord"):
		for f in DirAccess.get_files_at("res://world/bord"):
			f = f.trim_suffix(".import").trim_suffix(".remap")
			if f.ends_with(".glb"):
				var p := f.trim_prefix("bd_").trim_suffix(".glb").split("_")
				tiles[Vector2i(int(p[0]), int(p[1]))] = "res://world/bord/" + f
	if FileAccess.file_exists("res://world/zone.json"):
		var z: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://world/zone.json"))
		for q in z.pts:
			_zone.append(Vector2(q[0], q[1]))
		for i in _zone.size():
			var a := _zone[i]; var b := _zone[(i + 1) % _zone.size()]
			var n := int(ceil(a.distance_to(b) / (GRILLE * 0.5))) + 1
			for j in n + 1:
				var p := a.lerp(b, float(j) / n)
				for dx in range(-1, 2):
					for dz in range(-1, 2):
						var k := Vector2i(floori(p.x / GRILLE) + dx, floori(p.y / GRILLE) + dz)
						if not _segs.has(k):
							_segs[k] = []
						if _segs[k].is_empty() or _segs[k][-1] != i:
							_segs[k].append(i)

## Bord « cascade » (#157) ou collines : les tuiles du talus et leurs collisions sont libérées en mode cascade.
func set_cascade(on: bool) -> void:
	cascade = on
	cascade_node.set_actif(on)
	cascade = cascade_node.actif
	var m := get_parent()
	if m and m.get("poles"):
		m.poles.set_bout_monde(cascade)
	if cascade:
		for k in loaded:
			loaded[k].queue_free()
		loaded.clear(); bodies.clear()
		_chargeur.menage({})
	_t = 0.0

## Distance signée à la limite (m, + hors de la carte) et direction vers l'intérieur ; [0, Vector2.ZERO] loin de la limite.
func hors_carte(p: Vector3) -> Array:
	var q := Vector2(p.x, p.z)
	var l: Array = _segs.get(Vector2i(floori(q.x / GRILLE), floori(q.y / GRILLE)), [])
	if l.is_empty():
		return [0.0, Vector2.ZERO]
	var best := 1e9
	var proj := q
	for i: int in l:
		var a := _zone[i]; var b := _zone[(i + 1) % _zone.size()]
		var ab := b - a
		var t := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
		var c := a + ab * t
		var d := q.distance_to(c)
		if d < best:
			best = d; proj = c
	var dedans := Geometry2D.is_point_in_polygon(q, _zone)
	var vers := (proj - q).normalized() if not dedans else (q - proj).normalized()
	return [-best if dedans else best, vers]

func _process(dt: float) -> void:
	var t0 := Time.get_ticks_usec()
	_suivre(dt)
	PerfMon.note("bord", Time.get_ticks_usec() - t0)

func _suivre(dt: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var c := cam.global_position
	if cascade:
		var hc: Array = hors_carte(c)
		cascade_node.son(-float(hc[0]) if hc[1] != Vector2.ZERO else 1e4)
		return
	_t -= dt
	if _t <= 0.0:
		_t = 0.5
		var voulus := {}
		var r := int(ceil(VIEW / TILE))
		var kc := Vector2i(floori(c.x / TILE), floori(c.z / TILE))
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				var k := kc + Vector2i(dx, dz)
				if tiles.has(k) and Vector2((k.x + 0.5) * TILE - c.x, (k.y + 0.5) * TILE - c.z).length() < VIEW + TILE * 0.71:
					voulus[k] = true
		for k in loaded.keys():
			if not voulus.has(k):
				loaded[k].queue_free(); loaded.erase(k); bodies.erase(k)
		var vp := {}
		for k in voulus:
			if not loaded.has(k):
				vp[tiles[k]] = true
		_chargeur.menage(vp)
		_collisions()
	for k in tiles:
		if loaded.has(k) or not tiles.has(k):
			continue
		if Vector2((k.x + 0.5) * TILE - c.x, (k.y + 0.5) * TILE - c.z).length() > VIEW + TILE * 0.71:
			continue
		var sc := _chargeur.pret(tiles[k]) as PackedScene
		if sc:
			var n := sc.instantiate()
			for mi in n.find_children("*", "MeshInstance3D", true, false):
				(mi as MeshInstance3D).material_override = mat
				(mi as MeshInstance3D).visibility_range_end = VIEW
			add_child(n)
			loaded[k] = n
			break

## Collisions du talus près de la voiture seulement.
func _collisions() -> void:
	if car == null:
		return
	var p := car.global_position
	for k in loaded:
		var near := Vector2((k.x + 0.5) * TILE - p.x, (k.y + 0.5) * TILE - p.z).length() < COLL + TILE * 0.71
		if near and not bodies.has(k):
			var sb := StaticBody3D.new()
			for mi in loaded[k].find_children("*", "MeshInstance3D", true, false):
				var cs := CollisionShape3D.new()
				var sh: ConcavePolygonShape3D = (mi as MeshInstance3D).mesh.create_trimesh_shape()
				sh.backface_collision = true
				cs.shape = sh
				sb.add_child(cs)
			loaded[k].add_child(sb)
			bodies[k] = sb
		elif not near and bodies.has(k):
			bodies[k].queue_free(); bodies.erase(k)

func _physics_process(dt: float) -> void:
	if car == null or _zone.is_empty() or car.carried:
		return
	if cascade:
		_physique_cascade(dt)
		return
	_rebond_t -= dt
	var h: Array = hors_carte(car.global_position)
	var d: float = h[0]
	if d <= RESSORT:
		return
	var vers: Vector2 = h[1]
	var v3 := Vector3(vers.x, 0.0, vers.y)
	var sortie := -car.linear_velocity.dot(v3)          # vitesse vers l'extérieur
	# ressort : force qui croît avec la distance, et rebond si on insiste (Motocross Madness)
	car.apply_central_force(v3 * car.mass * RAIDEUR * (d - RESSORT))
	# catapulte façon Motocross Madness (issue #45) : la voiture est renvoyée très haut et très loin vers l'intérieur
	# de la carte en tournoyant dans tous les sens ; plus elle arrive vite, plus elle vole
	if sortie > 1.0 and _rebond_t <= 0.0:
		var f := clampf(sortie / 15.0, 0.6, 2.0)
		car.linear_velocity = v3 * (24.0 + 14.0 * f) + Vector3.UP * (16.0 + 10.0 * f)
		car.angular_velocity = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * randf_range(5.0, 9.0) * f
		_rebond_t = 2.5
		var m := get_parent()
		if m and m.get("sound") and m.sound.has_method("_one_shot"):
			m.sound._one_shot("ressort", car.global_position, 1.6, randf_range(0.92, 1.08), 40.0, 800.0)   # « boing » (#88)
			m.sound._one_shot("soucoupe_depart", car.global_position, 0.5, 1.6, 20.0, 600.0)     # sifflement d'envol
		if OS.get_cmdline_user_args().has("--bord-debug"):
			print("[bord] catapulte à %.1f m hors de la carte, %.1f m/s vers l'extérieur" % [d, sortie])
	if d > 120.0:                                        # filet de sécurité (ne devrait pas arriver)
		car.reset_to_road()

## Bord « cascade » (#157) : freinée dans la bande d'eau (gerbes, plouf en y entrant), la voiture est renvoyée vers
## l'intérieur à MUR m de la limite (rebond amorti), jamais au-delà : le sol hors de la zone n'est plus dessiné.
func _physique_cascade(dt: float) -> void:
	var pd = get_parent().get("pied")
	if pd and pd.actif and pd.corps:                   # à pied (#66) : arrêté au même endroit que la voiture
		var hp: Array = hors_carte(pd.corps.global_position)
		var w: Vector2 = hp[1]
		if w != Vector2.ZERO and float(hp[0]) > -MUR:
			pd.corps.global_position += Vector3(w.x, 0.0, w.y) * (float(hp[0]) + MUR)
	var p := car.global_position
	var h: Array = hors_carte(p)
	var vers: Vector2 = h[1]
	if vers == Vector2.ZERO:
		_dans_eau = false
		if not Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), _zone):      # filet de sécurité
			car.reset_to_road()
		return
	var d: float = h[0]
	var v3 := Vector3(vers.x, 0.0, vers.y)
	var m := get_parent()
	if d > -EAU:
		var vh := car.linear_velocity
		vh.y = 0.0
		car.apply_central_force(-vh * car.mass * FREIN_EAU)
		if not _dans_eau and m and m.get("sound") and m.sound.has_method("_one_shot"):
			m.sound._one_shot("plouf", p, clampf(vh.length() / 12.0, 0.4, 1.6), randf_range(0.95, 1.1), 30.0, 400.0)
		_dans_eau = true
		_embruns_t -= dt
		var D = m.get("dust") if m else null
		if D and _embruns_t <= 0.0 and vh.length() > 2.0:
			_embruns_t = 0.08
			var mat: Dictionary = D.MATIERES.get("eau", {})
			if not mat.is_empty():
				for i in 2:
					var q := p + Vector3(randf_range(-1.2, 1.2), -0.4, randf_range(-1.2, 1.2))
					D._nuage(mat, q, Vector3(vh.x * 0.25, randf_range(2.0, 4.0) + vh.length() * 0.12, vh.z * 0.25), 0.8)
	else:
		_dans_eau = false
	if d > -MUR:
		var sortie := -car.linear_velocity.dot(v3)
		if sortie > 0.0:
			car.linear_velocity += v3 * sortie * (1.0 + RESTITUTION)
		if d > -MUR * 0.5:
			car.global_position += v3 * (d + MUR * 0.5)
		if OS.get_cmdline_user_args().has("--bord-debug"):
			print("[bord] cascade : renvoyée à %.1f m de la limite, %.1f m/s vers l'extérieur" % [-d, sortie])
