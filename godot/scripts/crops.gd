## Champs cultivés en 3D (parcelles RPG 2024) : rangs générés autour de la voiture, par cases de 32 m, en bandes de
## 3 m posées sur le relief (Terrain3D), orientés selon le grand côté du champ. Au-delà : texture du sol.
extends Node3D

const TILE := 256.0
const CELL := 32.0
const STRIP := 3.0
const SPACING := [0.85, 0.7, 0.6, 0.75]         # écartement des rangs (m) : maïs, céréales, feuillage, tournesol
const HEIGHT := [3.0, 1.0, 1.0, 1.9]           # hauteur des bandes (m)
const RANGE := [80.0, 110.0, 140.0, 170.0]     # selon la densité de végétation

var target: Node3D
var terrain: Node
var level := 2
var fields := {}          # tuile -> [[type, dir Vector2, PackedVector2Array, Rect2]]
var cells := {}           # case -> MultiMeshInstance3D (ou null si vide)
var mat: ShaderMaterial
var quad: QuadMesh
var _t := 0.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	mat = ShaderMaterial.new()
	mat.shader = preload("res://scripts/crops.gdshader")
	preload("res://scripts/env.gd").add(mat)
	preload("res://scripts/env.gd").fade(mat, RANGE[level])     # rangs effacés en fondu jusqu'à la portée
	mat.set_shader_parameter("albedo_atlas", load("res://assets/veg/crops_albedo.png"))
	mat.set_shader_parameter("normal_atlas", load("res://assets/veg/crops_normal.png"))
	quad = QuadMesh.new()
	quad.size = Vector2(1, 1)
	quad.center_offset = Vector3(0, 0.5, 0)
	quad.material = mat

func set_level(l: int) -> void:
	level = l
	if mat:
		mat.set_shader_parameter("fade_far", RANGE[level])
	for k in cells.keys():
		if cells[k]:
			cells[k].queue_free()
	cells.clear()

func _tile_fields(k: Vector2i) -> Array:
	if fields.has(k):
		return fields[k]
	var out := []
	var path := "res://world/crops/c_%d_%d.bin" % [k.x, k.y]
	if FileAccess.file_exists(path):
		var sp := StreamPeerBuffer.new()
		sp.data_array = FileAccess.get_file_as_bytes(path)
		var n := sp.get_32()
		for i in n:
			var t := sp.get_32()
			var d := Vector2(sp.get_float(), sp.get_float())
			var m := sp.get_32()
			var pts := PackedVector2Array(); pts.resize(m)
			var r := Rect2()
			for j in m:
				pts[j] = Vector2(sp.get_float(), sp.get_float())
				r = Rect2(pts[j], Vector2.ZERO) if j == 0 else r.expand(pts[j])
			out.append([t, d, pts, r])
	fields[k] = out
	return out

func _process(dt: float) -> void:
	if target == null or terrain == null:
		return
	_t -= dt
	var c := target.global_position
	var rng_m: float = RANGE[level]
	var kc := Vector2i(floori(c.x / CELL), floori(c.z / CELL))
	var r := int(ceil(rng_m / CELL))
	# cases à garder / à créer (deux créations par image au plus)
	var made := 0
	var keep := {}
	var todo := []
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			var k := kc + Vector2i(dx, dz)
			var cc := Vector2((k.x + 0.5) * CELL - c.x, (k.y + 0.5) * CELL - c.z)
			if cc.length() > rng_m + CELL * 0.71:
				continue
			keep[k] = true
			if not cells.has(k):
				todo.append([cc.length(), k])
	todo.sort_custom(func(a, b): return a[0] < b[0])
	for it in todo:
		_build(it[1])
		made += 1
		if made >= 2:
			break
	if _t <= 0.0:
		_t = 0.5
		for k in cells.keys():
			if not keep.has(k):
				if cells[k]:
					cells[k].queue_free()
				cells.erase(k)

func _build(k: Vector2i) -> void:
	var x0 := k.x * CELL; var z0 := k.y * CELL
	var rect := Rect2(x0, z0, CELL, CELL)
	var cellpoly := PackedVector2Array([Vector2(x0, z0), Vector2(x0 + CELL, z0), Vector2(x0 + CELL, z0 + CELL), Vector2(x0, z0 + CELL)])
	var tk := Vector2i(floori(x0 / TILE), floori(z0 / TILE))
	var buf := PackedFloat32Array()
	var count := 0
	_rng.seed = hash(k)
	for f in _tile_fields(tk):
		if not f[3].intersects(rect):
			continue
		var t: int = f[0]
		var part := _rows(f, t, f[1], SPACING[t] if t != 2 else 3.0, cellpoly)
		buf.append_array(part)
		count += part.size() / 16
	if count == 0:
		cells[k] = null
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = count
	mm.buffer = buf
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	cells[k] = node

## Rangs d'une parcelle dans une case : droites parallèles à d, espacées de sp ; bandes de 3 m sur le relief.
func _rows(f: Array, t: int, d: Vector2, sp: float, cellpoly: PackedVector2Array) -> PackedFloat32Array:
		var buf := PackedFloat32Array()
		var nrm := Vector2(-d.y, d.x)
		# rangs : droites parallèles à d, espacées de sp (grille commune à tout le champ)
		var tmin := INF; var tmax := -INF; var smin := INF; var smax := -INF
		for p in cellpoly:
			tmin = minf(tmin, p.dot(nrm)); tmax = maxf(tmax, p.dot(nrm))
			smin = minf(smin, p.dot(d)); smax = maxf(smax, p.dot(d))
		var clipped := Geometry2D.intersect_polygons(f[2], cellpoly)
		if t == 1 or t == 2:
			for poly in clipped:
				for e in poly.size():
					var a: Vector2 = poly[e]; var b: Vector2 = poly[(e + 1) % poly.size()]
					var mid := (a + b) * 0.5
					var x0 := cellpoly[0].x; var z0 := cellpoly[0].y
					# arête sur le bord de la case : intérieur du champ, pas de bordure
					if absf(a.x - b.x) < 0.01 and (absf(a.x - x0) < 0.01 or absf(a.x - x0 - 32.0) < 0.01):
						continue
					if absf(a.y - b.y) < 0.01 and (absf(a.y - z0) < 0.01 or absf(a.y - z0 - 32.0) < 0.01):
						continue
					var L := a.distance_to(b)
					var dd := (b - a) / maxf(L, 0.001)
					var nn := Vector2(-dd.y, dd.x)
					for j in int(ceil(L / STRIP)):
						var w := minf(STRIP, L - j * STRIP)
						var m := a + dd * (j * STRIP + w * 0.5)
						var y: float = terrain.data.get_height(Vector3(m.x, 0, m.y))
						if is_nan(y) or w < 0.3:
							continue
						var h: float = (0.95 if t == 1 else 0.85)
						buf.append_array([dd.x * w, 0.0, nn.x, m.x, 0.0, h, 0.0, y - 0.05, dd.y * w, 0.0, nn.y, m.y,
							t / 6.0, _rng.randf(), 1.0, h])
		for poly in clipped:
			for kk in range(ceili(tmin / sp), floori(tmax / sp) + 1):
				var off := kk * sp
				var line := PackedVector2Array([nrm * off + d * (smin - 1.0), nrm * off + d * (smax + 1.0)])
				for seg in Geometry2D.intersect_polyline_with_polygon(line, poly):
					var a: Vector2 = seg[0]; var b: Vector2 = seg[seg.size() - 1]
					var L := a.distance_to(b)
					var ns := int(ceil(L / STRIP))
					for j in ns:
						var w := minf(STRIP, L - j * STRIP)
						if w < 0.4:
							continue
						var m := a + (b - a).normalized() * (j * STRIP + w * 0.5)
						var y: float = terrain.data.get_height(Vector3(m.x, 0, m.y))
						if is_nan(y):
							continue
						# bande inclinée comme le terrain (pas de marches ni de trous sur les pentes)
						var dn := (b - a).normalized()
						var ya: float = terrain.data.get_height(Vector3(m.x - dn.x * w * 0.5, 0, m.y - dn.y * w * 0.5))
						var yb: float = terrain.data.get_height(Vector3(m.x + dn.x * w * 0.5, 0, m.y + dn.y * w * 0.5))
						var slope := 0.0 if is_nan(ya) or is_nan(yb) else (yb - ya) * signf(dn.dot(d))
						var h: float = HEIGHT[t] * _rng.randf_range(0.92, 1.06)
						if t == 2:
							# nappe horizontale (bande de 3 m × sp) à hauteur des épis / du feuillage
							var hh: float = (0.85 if t == 1 else 0.75) * _rng.randf_range(0.95, 1.05)
							# axes (rang, -travers, haut) : repère direct, la face visible regarde vers le haut
							var c0 := m + nrm * sp * 0.5
							buf.append_array([d.x * w, -nrm.x * sp, 0.0, c0.x, 0.0, 0.0, 1.0, y + hh, d.y * w, -nrm.y * sp, 0.0, c0.y,
								(t + 3) / 6.0, _rng.randf(), _rng.randf_range(0.9, 1.06), -1.0])
							continue
						# transformation : x = rang (largeur w), y = hauteur, z = travers (1 m)
						var bx := Vector3(d.x, 0, d.y) * w
						var bz := Vector3(nrm.x, 0, nrm.y)
						buf.append_array([bx.x, h * 0.0, bz.x, m.x, slope, h, bz.y, y - 0.05, bx.z, 0.0, bz.z, m.y,
							t / 6.0, _rng.randf() + (j * STRIP) / 3.0, _rng.randf_range(0.88, 1.08), h])
		return buf
