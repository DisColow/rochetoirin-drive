## Végétation : arbres réels (LiDAR HD) en tuiles de 256 m chargées au fil de la route.
##  - au loin : imposteurs (8 vues cuites) dans un MultiMesh par tuile, un seul appel de dessin par tuile ;
##  - près de la voiture : vrais modèles 3D (Sketchfab), ombres portées, troncs avec collisions ;
##  - densité réglable (Réglages) : part des arbres affichés, portée des imposteurs et des modèles 3D.
extends Node3D

const TILE := 256.0
const NEAR_MARGIN := 14.0     # avance possible de la caméra entre deux choix des modèles 3D (0,2 s)
const SPECIES := ["chene", "feuillu", "chene2", "bouleau", "peuplier", "epicea", "sapin", "pin"]
# niveaux de densité : part des arbres, portée des imposteurs (m), rayon des modèles 3D (m), nombre max de modèles 3D
const LEVELS := [
	{"name": "Faible", "frac": 0.3, "far": 700.0, "near": 45.0, "max_near": 50},
	{"name": "Moyenne", "frac": 0.55, "far": 1000.0, "near": 60.0, "max_near": 90},
	{"name": "Élevée", "frac": 0.8, "far": 1650.0, "near": 70.0, "max_near": 140},
	{"name": "Maximale", "frac": 1.0, "far": 2200.0, "near": 80.0, "max_near": 220},
]

var target: Node3D
var level := 2
var tiles := {}          # Vector2i -> chemin
var data := {}           # Vector2i -> PackedFloat32Array (8 valeurs par arbre)
var mmi := {}            # Vector2i -> MultiMeshInstance3D
var pending := []
var meshes := []         # Mesh par essence
var sizes := []          # taille de l'imposteur (en hauteurs d'arbre) par essence
var imp_mat: ShaderMaterial
var tree_mats := []      # matériaux des modèles 3D (relais avec les imposteurs)
var quad: QuadMesh
var pool := []           # MeshInstance3D réutilisés (modèles 3D proches)
var trunks: StaticBody3D
var trunk_shapes := []
var _t := 0.0
var _near_t := 0.0

func _ready() -> void:
	for f in DirAccess.get_files_at("res://world/veg"):
		if f.ends_with(".bin"):
			var p := f.trim_prefix("v_").trim_suffix(".bin").split("_")
			tiles[Vector2i(int(p[0]), int(p[1]))] = "res://world/veg/" + f
	var info: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/veg/impostors.json"))
	for n in SPECIES:
		var sc: PackedScene = load("res://assets/veg/%s.glb" % n)
		var mi: MeshInstance3D = sc.instantiate().find_children("*", "MeshInstance3D", true, false)[0]
		_wind_materials(mi.mesh)
		meshes.append(mi.mesh)
		sizes.append(float(info["size"][n]))
	imp_mat = ShaderMaterial.new()
	imp_mat.shader = preload("res://scripts/impostor.gdshader")
	preload("res://scripts/env.gd").add(imp_mat)
	preload("res://scripts/env.gd").fade(imp_mat, 0.0)
	imp_mat.set_shader_parameter("albedo_atlas", load("res://assets/veg/impostors_albedo.png"))
	imp_mat.set_shader_parameter("normal_atlas", load("res://assets/veg/impostors_normal.png"))
	quad = QuadMesh.new()
	quad.size = Vector2(1, 1)
	quad.material = imp_mat
	trunks = StaticBody3D.new()
	add_child(trunks)
	set_level(level)

## Matériaux des modèles 3D repris dans le shader « arbre » (vent, frémissement des feuilles, ombre des nuages).
func _wind_materials(mesh: Mesh) -> void:
	for i in mesh.get_surface_count():
		var m := mesh.surface_get_material(i) as StandardMaterial3D
		if m == null:
			continue
		var sm := ShaderMaterial.new()
		sm.shader = preload("res://scripts/tree.gdshader")
		preload("res://scripts/env.gd").add(sm)
		sm.set_shader_parameter("albedo_tex", m.albedo_texture)
		if m.normal_enabled and m.normal_texture:
			sm.set_shader_parameter("normal_tex", m.normal_texture)
			sm.set_shader_parameter("use_normal", true)
		sm.set_shader_parameter("leaf", m.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR or m.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_HASH)
		sm.set_shader_parameter("scissor", m.alpha_scissor_threshold)
		preload("res://scripts/env.gd").fade(sm, 0.0)
		tree_mats.append(sm)
		mesh.surface_set_material(i, sm)

func set_level(l: int) -> void:
	level = clampi(l, 0, LEVELS.size() - 1)
	var L: Dictionary = LEVELS[level]
	_set_cut(L.near)
	imp_mat.set_shader_parameter("far_cut", L.far)
	for k in mmi.keys():
		mmi[k].queue_free()
	mmi.clear()
	pending.clear()
	_t = 0.0
	_near_t = 0.0

func _d(k: Vector2i, c: Vector3) -> float:
	return Vector2((k.x + 0.5) * TILE - c.x, (k.y + 0.5) * TILE - c.z).length()

func update_now() -> void:
	if target == null:
		return
	for k in _wanted(target.global_position):
		if _d(k, target.global_position) < 500.0:
			_load(k)
	_near_t = 0.0
	_update_near()

func _wanted(c: Vector3) -> Array:
	var far: float = LEVELS[level].far
	var r := int(ceil(far / TILE)) + 1
	var kc := Vector2i(floori(c.x / TILE), floori(c.z / TILE))
	var out := []
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			var k := kc + Vector2i(dx, dz)
			if tiles.has(k) and _d(k, c) < far + TILE * 0.71:
				out.append(k)
	out.sort_custom(func(a, b): return _d(a, c) < _d(b, c))
	return out

func _load(k: Vector2i) -> void:
	if mmi.has(k):
		return
	if not data.has(k):
		data[k] = FileAccess.get_file_as_bytes(tiles[k]).to_float32_array()
	var a: PackedFloat32Array = data[k]
	var n := int(a.size() / 8 * float(LEVELS[level].frac))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = n
	var buf := PackedFloat32Array()
	buf.resize(n * 16)
	for i in n:
		var o := i * 8
		var sp := int(a[o + 5])
		var s: float = a[o + 3] * sizes[sp]
		var b := i * 16
		buf[b] = s; buf[b + 3] = a[o]
		buf[b + 5] = s; buf[b + 7] = a[o + 1] - 0.02 * s
		buf[b + 10] = s; buf[b + 11] = a[o + 2]
		buf[b + 12] = sp / 8.0; buf[b + 13] = a[o + 4] / TAU; buf[b + 14] = a[o + 7]
	mm.buffer = buf
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.extra_cull_margin = 40.0
	add_child(node)
	mmi[k] = node

func _process(dt: float) -> void:
	if target == null:
		return
	if pending.size() > 0:
		_load(pending.pop_front())
	_t -= dt
	if _t <= 0.0:
		_t = 0.5
		var want := _wanted(target.global_position)
		var ws := {}
		for k in want:
			ws[k] = true
			if not mmi.has(k) and not pending.has(k):
				pending.append(k)
		for k in mmi.keys():
			if not ws.has(k):
				mmi[k].queue_free()
				mmi.erase(k)
				data.erase(k)
	_near_t -= dt
	if _near_t <= 0.0:
		_near_t = 0.2
		_update_near()

## Distance du relais modèles 3D / imposteurs (fondu tramé sur ± 4 m autour).
func _set_cut(d: float) -> void:
	imp_mat.set_shader_parameter("near_cut", d)
	for m in tree_mats:
		m.set_shader_parameter("near_cut", d)

## Modèles 3D des arbres proches de la caméra (et troncs pour les collisions), pris dans un réservoir réutilisé.
## Choisis jusqu'au relais + 4 m + NEAR_MARGIN (la caméra avance entre deux mises à jour) ; si le plafond de modèles
## les tronque, le relais se rapproche d'autant : jamais de trou entre modèles 3D et imposteurs.
func _update_near() -> void:
	var cam := get_viewport().get_camera_3d()
	var c := cam.global_position if cam else target.global_position
	var L: Dictionary = LEVELS[level]
	var R: float = L.near + 4.0 + NEAR_MARGIN
	var r2: float = R * R
	var found := []
	var kc := Vector2i(floori(c.x / TILE), floori(c.z / TILE))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var k := kc + Vector2i(dx, dz)
			if not data.has(k):
				continue
			var a: PackedFloat32Array = data[k]
			var n := int(a.size() / 8 * float(L.frac))
			for i in n:
				var o := i * 8
				var ddx := a[o] - c.x
				var ddz := a[o + 2] - c.z
				var d := ddx * ddx + ddz * ddz
				if d < r2:
					found.append([d, a[o], a[o + 1], a[o + 2], a[o + 3], a[o + 4], int(a[o + 5]), a[o + 7]])
	found.sort_custom(func(p, q): return p[0] < q[0])
	if found.size() > int(L.max_near):
		found.resize(int(L.max_near))
		_set_cut(maxf(sqrt(found[-1][0]) - 4.0 - NEAR_MARGIN, 8.0))
	else:
		_set_cut(L.near)
	while pool.size() < found.size():
		var mi := MeshInstance3D.new()
		add_child(mi)
		pool.append(mi)
	var nt := 0
	for i in pool.size():
		var mi: MeshInstance3D = pool[i]
		if i >= found.size():
			mi.visible = false
			continue
		var t: Array = found[i]
		mi.visible = true
		if mi.mesh != meshes[t[6]]:
			mi.mesh = meshes[t[6]]
		mi.transform = Transform3D(Basis(Vector3.UP, t[5]).scaled(Vector3.ONE * t[4]), Vector3(t[1], t[2] - 0.05, t[3]))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if t[0] < 55.0 * 55.0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# tronc : collision pour les arbres de plus de 5 m à moins de 40 m
		if t[4] > 5.0 and t[0] < 1600.0:
			if nt >= trunk_shapes.size():
				var cs := CollisionShape3D.new()
				var cyl := CylinderShape3D.new()
				cs.shape = cyl
				trunks.add_child(cs)
				trunk_shapes.append(cs)
			var cs2: CollisionShape3D = trunk_shapes[nt]
			var rad := clampf(t[4] * 0.018, 0.15, 0.55)
			(cs2.shape as CylinderShape3D).radius = rad
			(cs2.shape as CylinderShape3D).height = 4.0
			cs2.position = Vector3(t[1], t[2] + 1.5, t[3])
			cs2.disabled = false
			nt += 1
	for j in range(nt, trunk_shapes.size()):
		trunk_shapes[j].disabled = true
