## Piscines des jardins (build_pools.py, repérées sur l'orthophoto, gardées seulement dans les propriétés) :
## piscines enterrées (margelle en pierre claire, parois et fond carrelés de bleu, eau turquoise animée, muret de
## soutènement sur les terrains en pente) et piscines hors-sol rondes. Un maillage par tuile de 256 m, chargé au fil
## de la route ; collisions à hauteur de margelle.
extends Node3D

const TILE := 256.0
const VIEW := 380.0
const Cells := preload("res://scripts/cells.gd")
const COPING := 0.35          # largeur de la margelle
const DEPTH := 1.5            # profondeur du bassin

var target: Node3D
var tiles := {}               # Vector2i -> [piscines]
var loaded := {}
var _t := 0.0
var mat_stone: Material
var mat_tile: Material
var mat_water: ShaderMaterial
var mat_walls: Array = []

func _ready() -> void:
	if not FileAccess.file_exists("res://world/pools.json"):
		return
	for p in JSON.parse_string(FileAccess.get_file_as_string("res://world/pools.json")):
		var k := Vector2i(floori(float(p.x) / TILE), floori(float(p.z) / TILE))
		if not tiles.has(k):
			tiles[k] = []
		tiles[k].append(p)
	mat_stone = Cells.material(_m(Color(0.86, 0.83, 0.76), 0.85), VIEW)
	mat_tile = Cells.material(_m(Color(0.55, 0.82, 0.9), 0.3), VIEW)
	for c in [Color(0.42, 0.5, 0.58), Color(0.5, 0.36, 0.22), Color(0.85, 0.86, 0.86)]:
		mat_walls.append(Cells.material(_m(c, 0.6), VIEW))
	mat_water = ShaderMaterial.new()
	mat_water.shader = preload("res://scripts/pool_water.gdshader")
	preload("res://scripts/env.gd").add(mat_water)
	preload("res://scripts/env.gd").fade(mat_water, VIEW)

func _m(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c; m.roughness = rough
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

func _wanted(c: Vector3) -> Array:
	var out := []
	var r := int(ceil(VIEW / TILE))
	var kc := Vector2i(floori(c.x / TILE), floori(c.z / TILE))
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			var k := kc + Vector2i(dx, dz)
			if tiles.has(k) and Vector2((k.x + 0.5) * TILE - c.x, (k.y + 0.5) * TILE - c.z).length() < VIEW + TILE * 0.71:
				out.append(k)
	return out

func update_now() -> void:
	_t = 0.0
	if target:
		for k in _wanted(target.global_position):
			_add(k)

func _process(dt: float) -> void:
	if target == null or tiles.is_empty():
		return
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
			loaded[k].queue_free()
			loaded.erase(k)

# ---------------------------------------------------------------- géométrie
## Quadrilatère a, b, c, d (dans l'ordre du contour) ; normale tournée du côté de `hint`.
func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, hint: Vector3) -> void:
	var n := (b - a).cross(d - a).normalized()
	var vs := [a, b, c, a, c, d]
	if n.dot(hint) < 0.0:
		n = -n
		vs = [a, c, b, a, d, c]
	for v in vs:
		st.set_normal(n)
		st.set_uv(Vector2(v.x, v.z) * 0.5 + Vector2(v.y, v.y) * 0.5)
		st.add_vertex(v)

## Coins d'un rectangle centré en c (x, z), demi-côtés hu (le long de u) et hv, à l'altitude y (sens direct vu du dessus).
func _rect(c: Vector2, u: Vector2, hu: float, hv: float, y: float) -> Array:
	var v := Vector2(-u.y, u.x)
	var out := []
	for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var q: Vector2 = c + u * hu * s.x + v * hv * s.y
		out.append(Vector3(q.x, y, q.y))
	return out

func _sunken(stone: SurfaceTool, tile: SurfaceTool, water: SurfaceTool, p: Dictionary) -> void:
	var c := Vector2(float(p.x), float(p.z))
	var u := Vector2(cos(float(p.a)), sin(float(p.a)))
	var hu := float(p.L) / 2.0; var hv := float(p.W) / 2.0
	var y := float(p.y); var y0 := float(p.y0) - 0.15
	var inn := _rect(c, u, hu, hv, y)
	var out := _rect(c, u, hu + COPING, hv + COPING, y)
	var bot := _rect(c, u, hu, hv, y - DEPTH)
	var wat := _rect(c, u, hu, hv, y - 0.12)
	var skirt := _rect(c, u, hu + COPING, hv + COPING, y0)
	var cc := Vector3(c.x, 0, c.y)
	for k in 4:
		var k2 := (k + 1) % 4
		var mid: Vector3 = (out[k] + out[k2]) * 0.5
		var outw := Vector3(mid.x - cc.x, 0, mid.z - cc.z).normalized()
		# margelle (dessus), muret extérieur jusqu'au sol le plus bas, paroi carrelée du bassin
		_quad(stone, out[k], out[k2], inn[k2], inn[k], Vector3.UP)
		_quad(stone, skirt[k], skirt[k2], out[k2], out[k], outw)
		_quad(tile, inn[k], inn[k2], bot[k2], bot[k], -outw)
	_quad(tile, bot[0], bot[1], bot[2], bot[3], Vector3.UP)
	_quad(water, wat[0], wat[1], wat[2], wat[3], Vector3.UP)

func _round(wall: SurfaceTool, water: SurfaceTool, p: Dictionary) -> void:
	var c := Vector2(float(p.x), float(p.z))
	var r := (float(p.L) + float(p.W)) / 4.0
	var y0 := float(p.y0) - 0.1
	var y1 := float(p.y0) + 1.2
	var n := 24
	for k in n:
		var a0 := TAU * k / n; var a1 := TAU * (k + 1) / n
		var p0 := c + Vector2(cos(a0), sin(a0)) * r; var p1 := c + Vector2(cos(a1), sin(a1)) * r
		var q0 := c + Vector2(cos(a0), sin(a0)) * (r - 0.12); var q1 := c + Vector2(cos(a1), sin(a1)) * (r - 0.12)
		var outw := Vector3(cos((a0 + a1) / 2), 0, sin((a0 + a1) / 2))
		_quad(wall, Vector3(p1.x, y0, p1.y), Vector3(p0.x, y0, p0.y), Vector3(p0.x, y1, p0.y), Vector3(p1.x, y1, p1.y), outw)
		_quad(wall, Vector3(p1.x, y1, p1.y), Vector3(p0.x, y1, p0.y), Vector3(q0.x, y1, q0.y), Vector3(q1.x, y1, q1.y), Vector3.UP)
		_quad(wall, Vector3(q1.x, y1, q1.y), Vector3(q0.x, y1, q0.y), Vector3(q0.x, y0 + 0.3, q0.y), Vector3(q1.x, y0 + 0.3, q1.y), -outw)
		var w := y1 - 0.15
		water.set_normal(Vector3.UP)
		for v in [Vector3(c.x, w, c.y), Vector3(q1.x, w, q1.y), Vector3(q0.x, w, q0.y)]:
			water.set_uv(Vector2(v.x, v.z))
			water.add_vertex(v)

func _add(k: Vector2i) -> void:
	if loaded.has(k):
		return
	var root := Node3D.new()
	var body := StaticBody3D.new()
	root.add_child(body)
	var stone := SurfaceTool.new(); stone.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tile := SurfaceTool.new(); tile.begin(Mesh.PRIMITIVE_TRIANGLES)
	var water := SurfaceTool.new(); water.begin(Mesh.PRIMITIVE_TRIANGLES)
	var walls := []
	for w in 3:
		var s := SurfaceTool.new(); s.begin(Mesh.PRIMITIVE_TRIANGLES); walls.append(s)
	var nw := [0, 0, 0]
	var ns := 0
	for p in tiles[k]:
		var cs := CollisionShape3D.new()
		if p.round:
			var wi := int(abs(float(p.x) * 7.0 + float(p.z) * 3.0)) % 3
			_round(walls[wi], water, p)
			nw[wi] += 1
			var cy := CylinderShape3D.new()
			cy.radius = (float(p.L) + float(p.W)) / 4.0
			cy.height = 1.4
			cs.shape = cy
			cs.position = Vector3(float(p.x), float(p.y0) + 0.6, float(p.z))
		else:
			_sunken(stone, tile, water, p)
			ns += 1
			var bx := BoxShape3D.new()
			var h := float(p.y) - float(p.y0) + 0.3
			bx.size = Vector3(float(p.L) + 2 * COPING, h, float(p.W) + 2 * COPING)
			cs.shape = bx
			cs.transform = Transform3D(Basis(Vector3.UP, -float(p.a)), Vector3(float(p.x), float(p.y) - h / 2.0, float(p.z)))
		body.add_child(cs)
	var mesh := ArrayMesh.new()
	if ns > 0:
		stone.commit(mesh); mesh.surface_set_material(mesh.get_surface_count() - 1, mat_stone)
		tile.commit(mesh); mesh.surface_set_material(mesh.get_surface_count() - 1, mat_tile)
	for w in 3:
		if nw[w] > 0:
			walls[w].commit(mesh); mesh.surface_set_material(mesh.get_surface_count() - 1, mat_walls[w])
	water.commit(mesh); mesh.surface_set_material(mesh.get_surface_count() - 1, mat_water)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = VIEW + TILE
	root.add_child(mi)
	add_child(root)
	loaded[k] = root
