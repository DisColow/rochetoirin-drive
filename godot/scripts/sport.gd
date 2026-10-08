## Terrains de sport (build_sport.py) : surfaces et tracés posés sur le relief, équipements faits avec Blender
## (blender_sport.py) : buts, poteaux de rugby, filets et grillages de tennis, paniers, mâts d'éclairage, bancs.
extends Node3D

const TILE := 256.0
const Cells := preload("res://scripts/cells.gd")
const VIEW := 650.0
const MODELS := ["but_foot", "poteaux_rugby", "filet_tennis", "panier_basket", "mat_eclairage", "grillage", "banc_touche"]
const COLL := {
	"but_foot": [[Vector3(-3.66, 1.22, 0), Vector3(0.15, 2.44, 0.15)], [Vector3(3.66, 1.22, 0), Vector3(0.15, 2.44, 0.15)]],
	"poteaux_rugby": [[Vector3(-2.8, 1.0, 0), Vector3(0.4, 2.0, 0.4)], [Vector3(2.8, 1.0, 0), Vector3(0.4, 2.0, 0.4)]],
	"panier_basket": [[Vector3(0, 1.6, -1.2), Vector3(0.2, 3.2, 0.2)]],
	"mat_eclairage": [[Vector3(0, 4.0, 0), Vector3(0.4, 8.0, 0.4)]],
	"grillage": [[Vector3(0, 1.5, 0), Vector3(3.0, 3.0, 0.08)]],
	"banc_touche": [[Vector3(0, 1.1, 0), Vector3(4.0, 2.2, 1.3)]],
}
const MATS := {
	"blanc": [0, Color(0.92, 0.92, 0.9), 0.35, 0.3], "filet": [7, Color(0.95, 0.95, 0.95), 0.8, 0.0, 0.1],
	"filet_noir": [7, Color(0.05, 0.05, 0.05), 0.8, 0.0, 0.05], "grillage": [7, Color(0.1, 0.3, 0.15), 0.6, 0.0, 0.06],
	"metal": [0, Color(0.5, 0.52, 0.55), 0.4, 0.7], "protection": [0, Color(0.1, 0.3, 0.7), 0.7, 0.0],
	"rouge": [0, Color(0.7, 0.1, 0.08), 0.5, 0.0], "orange": [0, Color(0.95, 0.4, 0.05), 0.4, 0.5],
	"projecteur": [5, Color(1, 1, 0.95), 0.3, 0.0, -1.0], "plexi": [0, Color(0.2, 0.35, 0.5), 0.1, 0.2],
}

var target: Node3D
var terrain: Node
var tiles := {}
var loaded := {}
var meshes := []
var pitch_mat: ShaderMaterial
var _t := 0.0

func _ready() -> void:
	if not DirAccess.dir_exists_absolute("res://world/sport"):
		return
	for f in DirAccess.get_files_at("res://world/sport"):
		if f.ends_with(".bin"):
			var p := f.trim_prefix("sp_").trim_suffix(".bin").split("_")
			tiles[Vector2i(int(p[0]), int(p[1]))] = "res://world/sport/" + f
	pitch_mat = ShaderMaterial.new()
	pitch_mat.shader = preload("res://scripts/pitch.gdshader")
	preload("res://scripts/env.gd").add(pitch_mat)
	var cache := {}
	for n in MODELS:
		var mi: MeshInstance3D = (load("res://assets/sport/%s.glb" % n) as PackedScene).instantiate().find_children("*", "MeshInstance3D", true, false)[0]
		var mesh: Mesh = mi.mesh
		for s in mesh.get_surface_count():
			var m := mesh.surface_get_material(s)
			var nm := m.resource_name if m else ""
			if not MATS.has(nm):
				continue
			if not cache.has(nm):
				var d: Array = MATS[nm]
				var sm := ShaderMaterial.new()
				sm.shader = preload("res://scripts/shop.gdshader")
				sm.set_shader_parameter("kind", d[0])
				sm.set_shader_parameter("albedo", d[1])
				sm.set_shader_parameter("rough", d[2])
				sm.set_shader_parameter("metal", d[3])
				if d.size() > 4:
					if d[0] == 7:
						sm.set_shader_parameter("grid", d[4])
					else:
						sm.set_shader_parameter("glow", Color(1.0, 0.95, 0.85))
				preload("res://scripts/env.gd").add(sm)
				cache[nm] = sm
			mesh.surface_set_material(s, cache[nm])
		meshes.append(mesh)

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

func _h(x: float, z: float, fb: float) -> float:
	if terrain and terrain.data:
		var h: float = terrain.data.get_height(Vector3(x, 0, z))
		if not is_nan(h):
			return h
	return fb

## Surface d'un terrain : grille qui épouse le relief, un peu au-dessus du sol.
func _pitch_mesh(p: Array) -> ArrayMesh:
	var L: float = p[3]; var W: float = p[4]; var ang: float = p[5]
	var fwd := Vector2(sin(ang), cos(ang)); var side := Vector2(cos(ang), -sin(ang))
	var nl := maxi(2, ceili(L / 4.0)); var nw := maxi(2, ceili(W / 4.0))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := Vector2(p[1], p[2])
	var col := Color(float(p[0]) / 10.0, float(p[6]) / 10.0, float(p[7]), 0.0)
	var grid := []
	for i in nw + 1:
		var row := []
		for j in nl + 1:
			var u := -W * 0.5 + W * i / nw; var v := -L * 0.5 + L * j / nl
			var q := c + side * u + fwd * v
			row.append([Vector3(q.x, _h(q.x, q.y, 0.0) + 0.16, q.y), Vector2(u, v)])
		grid.append(row)
	for i in nw:
		for j in nl:
			for t in [[0, 0], [1, 0], [1, 1], [0, 0], [1, 1], [0, 1]]:
				var g: Array = grid[i + t[0]][j + t[1]]
				st.set_color(col); st.set_uv(g[1]); st.set_uv2(Vector2(L, W)); st.set_normal(Vector3.UP)
				st.add_vertex(g[0])
	st.generate_normals()
	return st.commit()

func _add(k: Vector2i) -> void:
	if loaded.has(k):
		return
	var a := FileAccess.get_file_as_bytes(tiles[k])
	var np := a.decode_s32(0)
	var f := a.slice(4, 4 + np * 36).to_float32_array()
	var root := Node3D.new()
	for i in np:
		var p := []
		for j in 9:
			p.append(f[i * 9 + j])
		var mi := MeshInstance3D.new()
		mi.mesh = _pitch_mesh(p)
		mi.material_override = pitch_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	var off := 4 + np * 36
	var ni := a.decode_s32(off)
	var g := a.slice(off + 4).to_float32_array()
	var body := StaticBody3D.new()
	root.add_child(body)
	var by := {}
	for i in ni:
		var o := i * 17
		var m := int(g[o])
		var b := Basis(Vector3(g[o + 1], g[o + 2], g[o + 3]), Vector3(g[o + 4], g[o + 5], g[o + 6]), Vector3(g[o + 7], g[o + 8], g[o + 9]))
		var xf := Transform3D(b, Vector3(g[o + 10], g[o + 11], g[o + 12]))
		if not by.has(m):
			by[m] = []
		by[m].append(xf)
		var nm: String = MODELS[m]
		if COLL.has(nm):
			for c in COLL[nm]:
				var cs := CollisionShape3D.new()
				var bs := BoxShape3D.new()
				bs.size = c[1] * Vector3(b.x.length(), 1.0, b.z.length()) if nm == "grillage" else c[1]
				cs.shape = bs
				cs.transform = Transform3D(b.orthonormalized(), xf.origin) * Transform3D(Basis.IDENTITY, c[0])
				body.add_child(cs)
	for m in by:
		var l := []
		for xf in by[m]:
			l.append([xf])
		Cells.add(root, meshes[m], l, 600.0 if MODELS[m] == "mat_eclairage" else 320.0, MODELS[m] == "mat_eclairage")
	add_child(root)
	loaded[k] = root
