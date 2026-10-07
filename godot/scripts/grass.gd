## Végétation basse près de la voiture (touffes d'herbe, fleurs, fougères), d'après la carte du sol au mètre
## (build_ground.py : pelouse, pré, bas-côté, sous-bois ; rien sur les routes, trottoirs, bâtiments, clôtures, eau,
## champs). Cases de 12 m construites une par image autour de la caméra ; densité et portée selon le réglage.
extends Node3D

const REG := 1024.0
const CELL := 12.0
# par niveau de densité (Réglages) : portée (m), écartement des touffes (m)
const LEVELS := [[24.0, 0.95], [32.0, 0.78], [40.0, 0.66], [50.0, 0.58]]
# par catégorie : cases de la planche (avec poids), hauteur min / max (m), largeur relative, part des places occupées
const CAT := {
	1: [[0, 0, 0, 1], 0.2, 0.34, 1.8, 0.85],
	2: [[2, 2, 2, 3], 0.4, 0.75, 1.35, 0.95],
	3: [[4, 4, 5, 2], 0.45, 0.9, 1.25, 0.95],
	4: [[6, 6, 7, 7], 0.35, 0.75, 1.2, 0.5],
}

var target: Node3D
var terrain: Node
var level := 2
var maps := {}            # Vector2i région -> PackedByteArray (quartets)
var cells := {}           # Vector2i case -> MultiMeshInstance3D ou null
var mesh: ArrayMesh
var mat: ShaderMaterial
var _t := 0.0

func _ready() -> void:
	mat = ShaderMaterial.new()
	mat.shader = preload("res://scripts/grass.gdshader")
	mat.set_shader_parameter("atlas", load("res://assets/veg/grass_albedo.png"))
	# touffe : deux plans croisés de 1 × 1 m, base au sol
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for a in [0.0, PI / 2.0]:
		var d := Vector3(cos(a), 0, sin(a)) * 0.5
		var n := Vector3(-d.z, 0, d.x).normalized()
		var q := [-d, d, d + Vector3.UP, -d + Vector3.UP]
		var uv := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for k in [0, 1, 2, 0, 2, 3]:
			st.set_normal(n); st.set_uv(uv[k]); st.add_vertex(q[k])
	mesh = st.commit()
	mesh.surface_set_material(0, mat)
	set_level(level)

func set_level(l: int) -> void:
	level = clampi(l, 0, LEVELS.size() - 1)
	var r: float = LEVELS[level][0]
	mat.set_shader_parameter("fade_start", r - 10.0)
	mat.set_shader_parameter("fade_end", r)
	for k in cells.keys():
		if cells[k]:
			cells[k].queue_free()
	cells.clear()

func _map(k: Vector2i) -> PackedByteArray:
	if not maps.has(k):
		var p := "res://world/ground/g_%d_%d.bin" % [k.x, k.y]
		maps[k] = FileAccess.get_file_as_bytes(p) if FileAccess.file_exists(p) else PackedByteArray()
		if maps.size() > 6:
			for o in maps.keys():
				if o != k:
					maps.erase(o)
					break
	return maps[k]

func _cat(x: float, z: float) -> int:
	var k := Vector2i(floori(x / REG), floori(z / REG))
	var m := _map(k)
	if m.is_empty():
		return 0
	var xi := clampi(int(x - k.x * REG), 0, 1023)
	var zi := clampi(int(z - k.y * REG), 0, 1023)
	var b := m[zi * 512 + (xi >> 1)]
	return (b >> 4) & 15 if xi & 1 else b & 15

func update_now() -> void:
	_t = 0.0
	for i in 40:
		if not _step():
			break

func _process(dt: float) -> void:
	if target == null or terrain == null:
		return
	_step()

## Construit au plus une case manquante (la plus proche) et retire les cases trop lointaines ; faux s'il n'y a rien à faire.
func _step() -> bool:
	if target == null or terrain == null:
		return false
	var c := target.global_position
	var r: float = LEVELS[level][0]
	var kc := Vector2i(floori(c.x / CELL), floori(c.z / CELL))
	var n := int(ceil(r / CELL)) + 1
	var best := Vector2i.ZERO; var bd := INF
	for dx in range(-n, n + 1):
		for dz in range(-n, n + 1):
			var k := kc + Vector2i(dx, dz)
			if cells.has(k):
				continue
			var d := Vector2((k.x + 0.5) * CELL - c.x, (k.y + 0.5) * CELL - c.z).length()
			if d < r + CELL * 0.71 and d < bd:
				bd = d; best = k
	for k in cells.keys():
		var d := Vector2((k.x + 0.5) * CELL - c.x, (k.y + 0.5) * CELL - c.z).length()
		if d > r + CELL * 1.5:
			if cells[k]:
				cells[k].queue_free()
			cells.erase(k)
	if bd == INF:
		return false
	_build(best)
	return true

func _build(k: Vector2i) -> void:
	var sp: float = LEVELS[level][1]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(k)
	var buf := PackedFloat32Array()
	var cnt := 0
	var steps := int(CELL / sp)
	buf.resize(steps * steps * 16)
	for ix in steps:
		for iz in steps:
			var x := k.x * CELL + (ix + rng.randf()) * sp
			var z := k.y * CELL + (iz + rng.randf()) * sp
			var cat := _cat(x, z)
			if cat == 0 or not CAT.has(cat):
				continue
			var spec: Array = CAT[cat]
			if rng.randf() > float(spec[4]):
				continue
			var y: float = terrain.data.get_height(Vector3(x, 0, z))
			if is_nan(y):
				continue
			var cellv: int = spec[0][rng.randi() % 4]
			var h := rng.randf_range(spec[1], spec[2])
			var w := h * float(spec[3]) * rng.randf_range(0.8, 1.2)
			var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(w, h, w))
			var o := cnt * 16
			buf[o] = b.x.x; buf[o + 1] = b.y.x; buf[o + 2] = b.z.x; buf[o + 3] = x
			buf[o + 4] = b.x.y; buf[o + 5] = b.y.y; buf[o + 6] = b.z.y; buf[o + 7] = y - 0.03
			buf[o + 8] = b.x.z; buf[o + 9] = b.y.z; buf[o + 10] = b.z.z; buf[o + 11] = z
			buf[o + 12] = (cellv + 0.01) / 8.0; buf[o + 13] = rng.randf_range(0.82, 1.12); buf[o + 14] = rng.randf(); buf[o + 15] = 0.0
			cnt += 1
	if cnt == 0:
		cells[k] = null
		return
	buf.resize(cnt * 16)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = cnt
	mm.buffer = buf
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	cells[k] = mi
