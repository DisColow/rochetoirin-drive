## Imposteurs des arbres : 8 vues (tous les 45°) de chaque modèle normalisé (assets/veg/<nom>.glb), en couleur
## (albédo, sans éclairage) et en normales (repère de la vue), sur fond transparent.
## Sorties : res://assets/veg/impostors_albedo.png, impostors_normal.png (8 colonnes × N lignes de 256 px),
## impostors.json (ordre des lignes, taille de la vue en hauteurs d'arbre).
## xvfb-run godot --path . res://tools/bake_impostors.tscn   (rendu nécessaire : pas de --headless)
extends Node

const NAMES := ["chene", "feuillu", "chene2", "bouleau", "peuplier", "epicea", "sapin", "pin"]
const CELL := 256
const VIEWS := 8

var vp: SubViewport
var cam: Camera3D

const NORMAL_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform bool use_alpha = false;
void fragment() {
	float a = texture(tex, UV).a;
	if (use_alpha && a < 0.45) { discard; }
	vec3 n = normalize(NORMAL) * (FRONT_FACING ? 1.0 : -1.0);
	ALBEDO = n * 0.5 + 0.5;
}
"""
const ALBEDO_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform vec4 col : source_color = vec4(1.0);
uniform bool use_alpha = false;
void fragment() {
	vec4 c = texture(tex, UV) * col;
	if (use_alpha && c.a < 0.45) { discard; }
	ALBEDO = c.rgb;
}
"""

func _ready() -> void:
	_run.call_deferred()

func _bake_strip(_a: Image, _n: Image) -> void:
	vp.size = Vector2i(1024, 1024)
	cam.size = 3.0
	var row := Node3D.new()
	vp.add_child(row)
	var rng := RandomNumberGenerator.new(); rng.seed = 7
	var src: PackedScene = load("res://assets/veg/mais.glb")
	for k in 10:
		var m: Node3D = src.instantiate()
		var s := rng.randf_range(2.1, 2.6)
		m.transform = Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(-1.62 + k * 0.36 + rng.randf_range(-0.06, 0.06), 0, rng.randf_range(-0.15, 0.15)))
		row.add_child(m)
	var mis := row.find_children("*", "MeshInstance3D", true, false)
	for pass_i in 2:
		for mi in mis:
			for s in mi.mesh.get_surface_count():
				var srcm := mi.mesh.surface_get_material(s) as StandardMaterial3D
				var sm := ShaderMaterial.new()
				sm.shader = Shader.new()
				sm.shader.code = ALBEDO_SHADER if pass_i == 0 else NORMAL_SHADER
				sm.set_shader_parameter("tex", srcm.albedo_texture if srcm else null)
				sm.set_shader_parameter("use_alpha", srcm != null and srcm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED)
				if pass_i == 0 and srcm:
					sm.set_shader_parameter("col", srcm.albedo_color)
				mi.set_surface_override_material(s, sm)
		cam.global_position = Vector3(0, 1.48, 10)
		cam.look_at(Vector3(0, 1.48, 0), Vector3.UP)
		for i in 3:
			await get_tree().process_frame
		var img := vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		img.save_png("res://assets/veg/strip_mais_%s.png" % ("albedo" if pass_i == 0 else "normal"))
	row.queue_free()
	print("rangée de maïs")

func _run() -> void:
	vp = SubViewport.new()
	vp.size = Vector2i(CELL, CELL)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_4X
	add_child(vp)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.background_color = Color(0, 0, 0, 0)
	we.environment = env
	vp.add_child(we)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	vp.add_child(cam)
	cam.make_current()
	print("début")
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/veg/meta.json"))
	var alb := Image.create(CELL * VIEWS, CELL * NAMES.size(), false, Image.FORMAT_RGBA8)
	var nrm := Image.create(CELL * VIEWS, CELL * NAMES.size(), false, Image.FORMAT_RGBA8)
	var info := {"names": NAMES, "views": VIEWS, "cell": CELL, "size": {}}
	for row in NAMES.size():
		var n: String = NAMES[row]
		var tree: Node3D = load("res://assets/veg/%s.glb" % n).instantiate()
		vp.add_child(tree)
		var r: float = meta[n]["crown"]
		var size := maxf(1.04, 2.0 * r * 1.06)
		info["size"][n] = size
		cam.size = size
		var mis := tree.find_children("*", "MeshInstance3D", true, false)
		for pass_i in 2:
			for mi in mis:
				for s in mi.mesh.get_surface_count():
					var src := mi.mesh.surface_get_material(s) as StandardMaterial3D
					var sm := ShaderMaterial.new()
					sm.shader = Shader.new()
					sm.shader.code = ALBEDO_SHADER if pass_i == 0 else NORMAL_SHADER
					sm.set_shader_parameter("tex", src.albedo_texture if src else null)
					sm.set_shader_parameter("use_alpha", src != null and src.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED)
					if pass_i == 0 and src:
						sm.set_shader_parameter("col", src.albedo_color)
					mi.set_surface_override_material(s, sm)
			for v in VIEWS:
				var a := TAU * v / VIEWS
				# vue horizontale : l'arbre est vu depuis la route ; vue v = caméra à l'angle v × 45° autour de l'arbre
				var dir := Vector3(sin(a), 0.0, cos(a))
				cam.global_position = Vector3(0, size * 0.5 - 0.02, 0) + dir * 10.0
				cam.look_at(Vector3(0, size * 0.5 - 0.02, 0), Vector3.UP)
				await get_tree().process_frame
				await get_tree().process_frame
				await get_tree().process_frame
				var img := vp.get_texture().get_image()
				img.convert(Image.FORMAT_RGBA8)
				(alb if pass_i == 0 else nrm).blit_rect(img, Rect2i(0, 0, CELL, CELL), Vector2i(v * CELL, row * CELL))
		tree.queue_free()
		print("imposteur ", n, " taille ", snappedf(size, 0.01))
	# rangée de maïs (bande de 3 m de large × 3 m de haut, vue de côté) pour les champs
	await _bake_strip(alb, nrm)
	# (débord de couleur sous les pixels transparents : pipeline/impostor_bleed.py)
	alb.save_png("res://assets/veg/impostors_albedo.png")
	nrm.save_png("res://assets/veg/impostors_normal.png")
	var f := FileAccess.open("res://assets/veg/impostors.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(info, " "))
	f.close()
	get_tree().quit()

