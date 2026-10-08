## Commerces (build_shops.py, modèles blender_commerces.py) : devantures, enseignes parodiques, stores, croix de
## pharmacie, carottes de tabac, terrasses, supermarchés et stations-service. Tuiles de 256 m chargées au fil de la
## route, un MultiMesh par modèle et par tuile ; enseignes, intérieurs et croix éclairés la nuit.
extends Node3D

const TILE := 256.0
const Cells := preload("res://scripts/cells.gd")
const VIEW := 600.0
const MODELS := ["vitrine", "porte", "enseigne", "lampes", "banne", "croix", "carotte", "totem", "ombriere", "pompe",
	"abri_caddies", "terrasse", "auvent", "bandeau", "pilastre", "coffre_rideau", "porte_sectionnelle", "bardage"]
# collisions (boîtes locales : centre, taille) des objets posés au sol
const COLL := {
	"totem": [[Vector3(0, 2.9, 0), Vector3(2.0, 5.8, 0.8)]],
	"pompe": [[Vector3(0, 0.95, 0), Vector3(0.9, 1.9, 0.45)]],
	"ombriere": [[Vector3(-5, 2.6, -2), Vector3(0.4, 5.2, 0.4)], [Vector3(5, 2.6, -2), Vector3(0.4, 5.2, 0.4)],
		[Vector3(-5, 2.6, 2), Vector3(0.4, 5.2, 0.4)], [Vector3(5, 2.6, 2), Vector3(0.4, 5.2, 0.4)]],
	"abri_caddies": [[Vector3(0, 1.1, 0), Vector3(4.1, 2.2, 2.1)]],
}
# matériau Blender -> [kind, couleur, rugosité, métal, lueur]
const MATS := {
	"cadre": [3, Color(0.16, 0.17, 0.18), 0.4, 0.6], "socle": [0, Color(0.55, 0.53, 0.5), 0.8, 0.0],
	"verre": [6, Color(0.05, 0.06, 0.07), 0.05, 0.4], "interieur": [4, Color(0.75, 0.72, 0.65), 0.9, 0.0],
	"chrome": [0, Color(0.85, 0.86, 0.88), 0.15, 1.0], "caisson": [0, Color(0.12, 0.12, 0.13), 0.4, 0.3],
	"enseigne": [1, Color(1, 1, 1), 0.3, 0.0], "metal": [0, Color(0.35, 0.36, 0.38), 0.4, 0.6],
	"ampoule": [5, Color(1, 0.95, 0.85), 0.3, 0.0, Color(1.0, 0.85, 0.6)], "toile": [2, Color(0.8, 0.8, 0.8), 0.85, 0.0],
	"coffre": [0, Color(0.9, 0.9, 0.88), 0.4, 0.2], "croix": [5, Color(0.1, 0.75, 0.25), 0.3, 0.0, Color(0.1, 0.9, 0.3)],
	"carotte": [5, Color(0.8, 0.08, 0.06), 0.35, 0.0, Color(0.9, 0.12, 0.08)], "blanc": [0, Color(0.88, 0.88, 0.87), 0.45, 0.2],
	"bande": [3, Color(0.8, 0.1, 0.1), 0.4, 0.0], "ecran": [5, Color(0.1, 0.2, 0.15), 0.2, 0.0, Color(0.2, 0.5, 0.3)],
	"caoutchouc": [0, Color(0.03, 0.03, 0.03), 0.8, 0.0], "rotin": [0, Color(0.55, 0.38, 0.2), 0.8, 0.0],
}

var target: Node3D
var tiles := {}
var loaded := {}
var meshes := []
var _t := 0.0

func _ready() -> void:
	if not DirAccess.dir_exists_absolute("res://world/shops"):
		return
	for f in DirAccess.get_files_at("res://world/shops"):
		if f.ends_with(".bin"):
			var p := f.trim_prefix("s_").trim_suffix(".bin").split("_")
			tiles[Vector2i(int(p[0]), int(p[1]))] = "res://world/shops/" + f
	var atlas: Texture2D = load("res://assets/shops/enseignes.png")
	var atlas2: Texture2D = load("res://assets/shops/enseignes2.png") if ResourceLoader.exists("res://assets/shops/enseignes2.png") else atlas
	var atlas3: Texture2D = load("res://assets/shops/enseignes3.png") if ResourceLoader.exists("res://assets/shops/enseignes3.png") else atlas
	var cache := {}
	for n in MODELS:
		var sc: PackedScene = load("res://assets/shops/%s.glb" % n)
		var mi: MeshInstance3D = sc.instantiate().find_children("*", "MeshInstance3D", true, false)[0]
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
					sm.set_shader_parameter("glow", d[4])
				sm.set_shader_parameter("atlas", atlas)
				sm.set_shader_parameter("atlas2", atlas2)
				sm.set_shader_parameter("atlas3", atlas3)
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
		if not loaded.has(k) and n < 2:
			_add(k); n += 1
	for k in loaded.keys():
		if not ws.has(k):
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
	for i in cnt:
		var o := i * 17
		var m := int(f[o])
		var b := Basis(Vector3(f[o + 1], f[o + 2], f[o + 3]), Vector3(f[o + 4], f[o + 5], f[o + 6]), Vector3(f[o + 7], f[o + 8], f[o + 9]))
		var xf := Transform3D(b, Vector3(f[o + 10], f[o + 11], f[o + 12]))
		if not by.has(m):
			by[m] = []
		by[m].append([xf, Color(f[o + 13], f[o + 14], f[o + 15], f[o + 16])])
		var nm: String = MODELS[m]
		if COLL.has(nm):
			for c in COLL[nm]:
				var cs := CollisionShape3D.new()
				var bs := BoxShape3D.new()
				bs.size = c[1]
				cs.shape = bs
				cs.transform = xf * Transform3D(Basis.IDENTITY, c[0])
				body.add_child(cs)
	for m in by:
		var big: bool = MODELS[m] in ["totem", "ombriere", "enseigne", "auvent", "bardage", "porte_sectionnelle"]
		Cells.add(root, meshes[m], by[m], 550.0 if big else 300.0, big)
	add_child(root)
	loaded[k] = root
