## Vie des villages (build_props.py) : voitures garées dans les cours (modèles gratuits Sketchfab, crédités dans ⚙),
## poubelles, tracteurs ; tuiles de 256 m chargées au
## fil de la route, un MultiMesh par modèle et par tuile (couleur de carrosserie par instance), collisions en boîtes.
extends Node3D
const PerfMon := preload("res://scripts/perf_monitor.gd")

const TILE := 256.0
const Cells := preload("res://scripts/cells.gd")
var VIEW := 520.0
const MODELS := {1: "car1", 2: "car2", 3: "car3", 4: "car4", 5: "tractor", 6: "bin"}
# boîtes de collision (largeur, hauteur, longueur) : voitures aux mesures de blender_voitures.py (rétros exclus)
const BOXES := {1: Vector3(1.66, 1.48, 3.75), 2: Vector3(1.75, 1.5, 4.05), 3: Vector3(1.76, 1.45, 4.45),
	4: Vector3(1.63, 1.6, 4.15), 5: Vector3(2.2, 2.7, 4.2), 6: Vector3(0.6, 1.05, 0.75)}

var target: Node3D
var tiles := {}
var loaded := {}
var meshes := {}
var _t := 0.0
# v6.22 (« collisions physiques sur les véhicules garés ») : près du joueur, chaque voiture garée (et tracteur)
# devient un corps rigide qu'on peut pousser, faire pivoter ou renverser ; loin de lui et immobile, elle redevient un
# exemplaire de son lot, à sa nouvelle place. MASSES : kg.
# poubelle (6) : 15 kg, envoyée valser sans ralentir la voiture (issue #41)
const MASSES := {1: 1100.0, 2: 1250.0, 3: 1400.0, 4: 1300.0, 5: 4500.0, 6: 15.0}
const R_ACTIF := 20.0
const R_RENDU := 45.0
var items := {}                       # tuile -> Array de {t, xf, col, cs, mm, i, rb}
var _ta := 0.0

func _ready() -> void:
	if not DirAccess.dir_exists_absolute("res://world/props"):
		return
	for f in DirAccess.get_files_at("res://world/props"):
		if f.ends_with(".bin"):
			var p := f.trim_prefix("pp_").trim_suffix(".bin").split("_")
			tiles[Vector2i(int(p[0]), int(p[1]))] = "res://world/props/" + f
	var paint := ShaderMaterial.new()
	paint.shader = preload("res://scripts/paint.gdshader")
	preload("res://scripts/env.gd").add(paint)
	preload("res://scripts/env.gd").phares_sur(paint)
	var mats := {
		"paint": paint,
		"glass": _m(Color(0.05, 0.06, 0.07), 0.05, 0.3),
		"plastic": _m(Color(0.06, 0.06, 0.065), 0.6),
		"rubber": _m(Color(0.03, 0.03, 0.035), 0.9),
		"hubcap": _m(Color(0.7, 0.71, 0.73), 0.35, 0.5),
		"rim": _m(Color(0.8, 0.72, 0.15), 0.5),
		"lamp": _m(Color(0.85, 0.88, 0.9), 0.1, 0.5),
		"tail": _m(Color(0.65, 0.04, 0.04), 0.25),
		"plate": _m(Color(0.92, 0.92, 0.9), 0.4),
		"lid": _m(Color(0.88, 0.72, 0.1), 0.6),
	}
	var fusion := ShaderMaterial.new()
	fusion.shader = preload("res://scripts/props.gdshader")
	preload("res://scripts/env.gd").add(fusion)
	preload("res://scripts/env.gd").phares_sur(fusion)
	for t in MODELS:
		var sc: PackedScene = load("res://assets/props/%s.glb" % MODELS[t])
		var mi: MeshInstance3D = sc.instantiate().find_children("*", "MeshInstance3D", true, false)[0]
		var mesh: Mesh = mi.mesh
		for s in mesh.get_surface_count():
			var m := mesh.surface_get_material(s)
			var nm := m.resource_name if m else ""
			if mats.has(nm):
				mesh.surface_set_material(s, mats[nm])
		meshes[t] = _fusionner(mesh, paint, fusion)

## #124 étape 2 : un modèle sans texture (voitures 1 et 3 : 12 matériaux, tracteur 6, poubelle 3) devient une seule
## surface : un appel de dessin par case au lieu d'un par matériau, ombres comprises (au village, 346 appels pour les
## voitures garées). Couleur de chaque matériau dans UV (r, v) et UV2.x (b), UV2.y = métal × 10 (entier) + rugosité, ou
## −1 pour la carrosserie teintée par instance ; shader props.gdshader. (Pas la couleur des sommets : dans une MultiMesh
## sans couleur par exemplaire, le rendu Compatibility la multiplie par zéro, tout sortait noir.) Niveaux de détail refaits comme à l'import (ImporterMesh : ceux de
## l'import ne se relisent pas, mesh_get_surface les renvoie vides en 4.4). Modèle texturé ou d'une seule surface : inchangé.
func _fusionner(mesh: Mesh, paint: Material, fusion: Material) -> Mesh:
	if mesh.get_surface_count() < 2 or OS.get_environment("RS_SKIP").contains("fusion"):   # essais : avant / après
		return mesh
	var parts := []
	for s in mesh.get_surface_count():
		var m := mesh.surface_get_material(s)
		if m == paint:
			parts.append([s, Vector2(1, 1), Vector2(1, -1)])
		elif m is StandardMaterial3D and (m as StandardMaterial3D).albedo_texture == null:
			var sm := m as StandardMaterial3D
			parts.append([s, Vector2(sm.albedo_color.r, sm.albedo_color.g),
				Vector2(sm.albedo_color.b, roundf(sm.metallic * 10.0) + clampf(sm.roughness, 0.0, 0.99))])
		else:
			return mesh
	var P := PackedVector3Array()
	var N := PackedVector3Array()
	var U := PackedVector2Array()
	var U2 := PackedVector2Array()
	var I := PackedInt32Array()
	for pa in parts:
		var a := mesh.surface_get_arrays(pa[0])
		var base := P.size()
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		P.append_array(v)
		N.append_array(a[Mesh.ARRAY_NORMAL])
		for i in v.size():
			U.append(pa[1])
			U2.append(pa[2])
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		for i in idx:
			I.append(i + base)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = P
	arr[Mesh.ARRAY_NORMAL] = N
	arr[Mesh.ARRAY_TEX_UV] = U
	arr[Mesh.ARRAY_TEX_UV2] = U2
	arr[Mesh.ARRAY_INDEX] = I
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, fusion)
	im.generate_lods(25.0, 60.0, [])
	return im.get_mesh()

func _m(c: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c; m.roughness = rough; m.metallic = metal
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
			_add(k)

func _process(dt: float) -> void:
	var t0_perf := Time.get_ticks_usec()
	_process_corps(dt)
	PerfMon.note("props", Time.get_ticks_usec() - t0_perf)

func _process_corps(dt: float) -> void:
	if target == null:
		return
	_ta -= dt
	if _ta <= 0.0:
		_ta = 0.25
		_physique(target.global_position)
	_t -= dt
	if _t > 0.0:
		return
	_t = 0.5
	var ws := {}
	var n := 0
	for k in _wanted(target.global_position):
		ws[k] = true
		if not loaded.has(k) and n < 2:
			_add(k); n += 1
	for k in loaded.keys():
		if not ws.has(k):
			for it in items.get(k, []):
				if it.rb:
					it.rb.queue_free()
			items.erase(k)
			loaded[k].queue_free()
			loaded.erase(k)

func _add(k: Vector2i) -> void:
	if loaded.has(k):
		return
	var a := FileAccess.get_file_as_bytes(tiles[k])
	var cnt := a.decode_s32(0)
	var f := a.slice(4).to_float32_array()
	var root := Node3D.new()
	var body := StaticBody3D.new()
	root.add_child(body)
	var by := {}
	var its := []
	for i in cnt:
		var o := i * 8
		var t := int(f[o])
		var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(f[o + 4])), Vector3(f[o + 1], f[o + 2], f[o + 3]))
		if not by.has(t):
			by[t] = []
		by[t].append([xf, Color(f[o + 5], f[o + 6], f[o + 7])])
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = BOXES[t]
		cs.shape = bs
		cs.transform = xf * Transform3D(Basis.IDENTITY, Vector3(0, BOXES[t].y / 2, 0))
		body.add_child(cs)
		if MASSES.has(t):
			its.append({"t": t, "xf": xf, "col": Color(f[o + 5], f[o + 6], f[o + 7]), "cs": cs, "mm": null, "i": -1, "rb": null})
	var par_origine := {}
	for t in by:
		for mmi in Cells.add(root, meshes[t], by[t], 420.0 if t != 6 else 200.0, true):
			var org: PackedVector3Array = mmi.get_meta("origines")
			for j in org.size():
				par_origine[org[j]] = [mmi, j]
	for it in its:
		var r = par_origine.get((it.xf as Transform3D).origin)
		if r:
			it.mm = r[0]; it.i = r[1]
	add_child(root)
	loaded[k] = root
	items[k] = its

## Voitures garées physiques autour du joueur (voir MASSES).
func _physique(c: Vector3) -> void:
	var kc := Vector2i(floori(c.x / TILE), floori(c.z / TILE))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for it in items.get(kc + Vector2i(dx, dz), []):
				if it.mm == null:
					continue
				if it.rb == null:
					var o: Vector3 = (it.xf as Transform3D).origin
					if Vector2(o.x - c.x, o.z - c.z).length() < R_ACTIF:
						_activer(it)
				else:
					var rb: RigidBody3D = it.rb
					var o2 := rb.global_position
					if OS.get_cmdline_user_args().has("--props-debug") and rb.linear_velocity.length() > 0.2:
						print("[props] voiture garée en %s, %.1f m/s, contacts %s" % [o2.snapped(Vector3.ONE * 0.1), rb.linear_velocity.length(), rb.get_colliding_bodies()])
					if Vector2(o2.x - c.x, o2.z - c.z).length() > R_RENDU and rb.linear_velocity.length() < 0.3:
						_rendre(it)

func _activer(it: Dictionary) -> void:
	var t: int = it.t
	var rb := RigidBody3D.new()
	rb.set_meta("matiere", "plastique" if t == 6 else "metal")
	if t != 6:
		rb.set_meta("vehicule", true); rb.set_meta("garee", true); rb.set_meta("v_avant", 0.0)     # #164 : Car.juger
	rb.mass = MASSES[t]
	rb.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	rb.center_of_mass = Vector3(0, BOXES[t].y * 0.35, 0)
	rb.angular_damp = 1.5
	rb.linear_damp = 0.4
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = BOXES[t]
	cs.shape = bs
	cs.position = Vector3(0, BOXES[t].y / 2, 0)
	rb.add_child(cs)
	var mm := MultiMesh.new()                      # un seul exemplaire : même matériau, couleur par instance
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = meshes[t]
	mm.instance_count = 1
	mm.set_instance_transform(0, Transform3D.IDENTITY)
	mm.set_instance_custom_data(0, it.col)
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	rb.add_child(mi)
	add_child(rb)
	rb.global_transform = it.xf
	rb.sleeping = true
	rb.contact_monitor = OS.get_cmdline_user_args().has("--props-debug")
	rb.max_contacts_reported = 4
	if rb.contact_monitor:
		print("[props] voiture garée active en ", rb.global_position)
	(it.mm as MultiMeshInstance3D).multimesh.set_instance_transform(it.i, Transform3D(Basis.from_scale(Vector3.ONE * 0.001), (it.xf as Transform3D).origin - Vector3(0, 50, 0)))
	(it.cs as CollisionShape3D).disabled = true
	it.rb = rb

## #164 : voiture garée percutée à plus de 60 km/h (Car.juger) : KA-BOOM, elle disparaît (revient avec la tuile).
func exploser_garee(rb: Node) -> void:
	for k in items:
		for it in items[k]:
			if it.rb == rb:
				var p: Vector3 = (rb as Node3D).global_position
				var fx = preload("res://scripts/explosion.gd").new()
				fx.style = "atomique"
				fx.position = p - Vector3(0, 0.3, 0)
				get_parent().add_child(fx)
				var m := get_parent()
				if m.get("sound") and m.sound.has_method("boum"):
					m.sound.boum(p)
				rb.queue_free()
				it.rb = null
				it.mm = null                                # ni réactivée ni réaffichée tant que la tuile reste chargée
				return

func _rendre(it: Dictionary) -> void:
	var rb: RigidBody3D = it.rb
	var xf := rb.global_transform
	it.xf = xf
	(it.mm as MultiMeshInstance3D).multimesh.set_instance_transform(it.i, xf)
	var cs: CollisionShape3D = it.cs
	cs.transform = xf * Transform3D(Basis.IDENTITY, Vector3(0, BOXES[int(it.t)].y / 2, 0))
	cs.disabled = false
	rb.queue_free()
	it.rb = null

