## Équipements d'autoroute (build_autoroute.py, modèles blender_autoroute.py) : glissières, séparateurs en béton,
## clôtures, bornes d'appel d'urgence, panneaux bleus, potences de sortie, limitations de vitesse, absorbeurs de choc,
## balises à chevrons, gares de péage ; tuiles de 256 m chargées au fil de la route.
extends Node3D

const TILE := 256.0
const VIEW := 700.0
const MODELS := ["glissiere", "borne_sos", "panneau_bleu", "peage", "pile_peage", "chevron", "gba", "potence", "panneau_haut",
	"rond", "grillage", "absorbeur"]
# portée d'affichage par modèle (m)
const RANGE := {"glissiere": 320.0, "gba": 450.0, "grillage": 160.0, "borne_sos": 250.0, "rond": 450.0}
const MATS := {
	"galva": [0, Color(0.7, 0.72, 0.73), 0.42, 0.45], "orange": [0, Color(0.95, 0.42, 0.04), 0.4, 0.0],
	"beton": [0, Color(0.6, 0.6, 0.58), 0.85, 0.0], "sos": [0, Color(0.95, 0.95, 0.95), 0.4, 0.0],
	"noir": [0, Color(0.05, 0.05, 0.05), 0.5, 0.0], "dos": [0, Color(0.55, 0.57, 0.6), 0.4, 0.6],
	"panneau": [1, Color(1, 1, 1), 0.3, 0.0], "blanc": [0, Color(0.9, 0.9, 0.88), 0.45, 0.2],
	"bande": [0, Color(0.1, 0.25, 0.6), 0.4, 0.0], "cabine": [0, Color(0.85, 0.85, 0.82), 0.5, 0.2],
	"vitre": [6, Color(0.1, 0.15, 0.2), 0.05, 0.3], "ilot": [0, Color(0.95, 0.75, 0.1), 0.6, 0.0],
	"chevrons": [8, Color(1, 1, 1), 0.4, 0.0],
	"catadioptre": [5, Color(0.95, 0.55, 0.1), 0.3, 0.0, Color(0.9, 0.45, 0.05)],
	"gba": [0, Color(0.8, 0.79, 0.76), 0.9, 0.0],
	"vert": [0, Color(0.16, 0.3, 0.18), 0.6, 0.0], "treillis": [7, Color(0.35, 0.42, 0.36), 0.6, 0.0, Color(0, 0, 0), 0.05],
}

var target: Node3D
var tiles := {}
var loaded := {}
var meshes := []
var _t := 0.0

func _ready() -> void:
	if not DirAccess.dir_exists_absolute("res://world/autoroute"):
		return
	for f in DirAccess.get_files_at("res://world/autoroute"):
		if f.ends_with(".bin"):
			var p := f.trim_prefix("r_").trim_suffix(".bin").split("_")
			tiles[Vector2i(int(p[0]), int(p[1]))] = "res://world/autoroute/" + f
	var atlas: Texture2D = load("res://assets/autoroute/panneaux.png")
	var cache := {}
	for n in MODELS:
		var mi: MeshInstance3D = (load("res://assets/autoroute/%s.glb" % n) as PackedScene).instantiate().find_children("*", "MeshInstance3D", true, false)[0]
		var mesh: Mesh = mi.mesh
		for s in mesh.get_surface_count():
			var mt := mesh.surface_get_material(s)
			var nm := mt.resource_name if mt else ""
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
				sm.set_shader_parameter("atlas", atlas)
				if d.size() > 4:
					sm.set_shader_parameter("glow", d[4])
				if d.size() > 5:
					sm.set_shader_parameter("grid", d[5])
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
		if nm in ["peage", "grillage", "panneau_haut"]:
			continue
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		if nm == "glissiere" or nm == "gba":
			var L := b.x.length() * 4.0
			bs.size = Vector3(L, 0.8, 0.25 if nm == "glissiere" else 0.5)
			cs.transform = Transform3D(Basis(Vector3.UP, atan2(-b.x.z, b.x.x)), xf * Vector3(2.0, 0.4, 0))
		elif nm == "absorbeur":
			bs.size = Vector3(3.0, 0.9, 0.7)
			cs.transform = Transform3D(b.orthonormalized(), xf * Vector3(-1.5, 0.45, 0))
		elif nm == "potence":
			bs.size = Vector3(0.5, 7.6, 0.5)
			cs.transform = xf * Transform3D(Basis.IDENTITY, Vector3(0, 3.8, 0))
		else:
			bs.size = {"borne_sos": Vector3(0.5, 1.5, 0.4), "panneau_bleu": Vector3(1.0, 1.0, 0.3), "pile_peage": Vector3(1.6, 5.8, 2.6),
				"chevron": Vector3(0.2, 1.6, 0.2), "rond": Vector3(0.15, 2.3, 0.15)}[nm]
			if nm == "panneau_bleu":
				bs.size = Vector3(b.x.length() * 0.75, 2.5, 0.3)
				cs.transform = Transform3D(b.orthonormalized(), xf.origin + Vector3(0, -1.25, 0))
			else:
				cs.transform = xf * Transform3D(Basis.IDENTITY, Vector3(0, bs.size.y / 2, 0))
		cs.shape = bs
		body.add_child(cs)
	for m in by:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = meshes[m]
		mm.instance_count = by[m].size()
		for i in by[m].size():
			mm.set_instance_transform(i, by[m][i][0])
			mm.set_instance_custom_data(i, by[m][i][1])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if MODELS[m] in ["glissiere", "grillage", "gba"] else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mi.visibility_range_end = RANGE.get(MODELS[m], 700.0)
		root.add_child(mi)
	add_child(root)
	loaded[k] = root
