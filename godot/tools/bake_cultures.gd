## Bandes et nappes des cultures d'après de vrais modèles 3D (#130, v6.37 : « toutes les cultures à la qualité du
## maïs ») : blé (Wheat — Yaroslav Karas, CC BY), colza (Rapeseed — ffish.asia / floraZia, CC0), tournesol
## (Sunflower — zvanstone, CC BY), préparés par tools/prepare_trees.gd -- --seulement=ble,ble2,colza,tournesol (hauteur 1 m)
## puis déplacés (glb + png) dans res://import/cultures/ (hors de l export : seulement pour la cuisson).
## Vues orthographiques de 3 m × 3 m, sans éclairage (albédo) puis normales, fond transparent, raccord horizontal
## (bandes) ou dans les deux sens (nappes vues de dessus) : chaque plant près d'un bord est aussi posé de l'autre côté.
## Blé vu de côté : « Realistic Wheat » (Graphetta, CC BY, ble2) ; vu de dessus : « Wheat — FREE » (ble).
## -- --seulement=strip_ble2,top_colza : ne cuit que ces rendus.
## Sorties : res://import/cultures/strip_<nom>_{albedo,normal}.png et top_<nom>_{albedo,normal}.png (1024 px), reprises
## par pipeline/build_crop_tex.py.
## xvfb-run godot --path . res://tools/bake_cultures.tscn   (rendu nécessaire : pas de --headless)
extends Node

const TAILLE := 3.0
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
uniform float sombre = 1.0;
void fragment() {
	vec4 c = texture(tex, UV) * col;
	if (use_alpha && c.a < 0.45) { discard; }
	ALBEDO = c.rgb * sombre;
}
"""

# nom, nombre de plants, hauteur min/max (m), profondeur de la bande (m)
const BANDES := [["ble2", 60, 0.85, 1.05, 0.6], ["colza", 22, 0.95, 1.25, 0.6], ["tournesol", 9, 1.6, 2.0, 0.25]]
const NAPPES := [["ble", 160, 0.85, 1.05], ["colza", 75, 0.95, 1.3]]

func _ready() -> void:
	_run.call_deferred()

func _poser(row: Node3D, src: PackedScene, x: float, z: float, y: float, h: float, rot: float, wrap_z: bool) -> void:
	var dx := [0.0]
	if x < -TAILLE * 0.5 + 0.8: dx.append(TAILLE)
	if x > TAILLE * 0.5 - 0.8: dx.append(-TAILLE)
	var dz := [0.0]
	if wrap_z:
		if z < -TAILLE * 0.5 + 0.8: dz.append(TAILLE)
		if z > TAILLE * 0.5 - 0.8: dz.append(-TAILLE)
	for a in dx:
		for b in dz:
			var m: Node3D = src.instantiate()
			m.transform = Transform3D(Basis(Vector3.UP, rot).scaled(Vector3.ONE * h), Vector3(x + a, y, z + b))
			row.add_child(m)

func _materiaux(row: Node3D, pass_i: int) -> void:
	var rng := RandomNumberGenerator.new(); rng.seed = 11
	for mi in row.find_children("*", "MeshInstance3D", true, false):
		var sombre := rng.randf_range(0.82, 1.0)
		for s in mi.mesh.get_surface_count():
			var srcm := mi.mesh.surface_get_material(s) as StandardMaterial3D
			if mi.has_meta("src_%d" % s):
				srcm = mi.get_meta("src_%d" % s)
			else:
				mi.set_meta("src_%d" % s, srcm)
			var sm := ShaderMaterial.new()
			sm.shader = Shader.new()
			sm.shader.code = ALBEDO_SHADER if pass_i == 0 else NORMAL_SHADER
			sm.set_shader_parameter("tex", srcm.albedo_texture if srcm else null)
			sm.set_shader_parameter("use_alpha", srcm != null and srcm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED)
			if pass_i == 0:
				if srcm:
					sm.set_shader_parameter("col", srcm.albedo_color)
				sm.set_shader_parameter("sombre", sombre)
			mi.set_surface_override_material(s, sm)

func _cuire(row: Node3D, nom: String) -> void:
	for pass_i in 2:
		_materiaux(row, pass_i)
		for i in 4:
			await get_tree().process_frame
		var img := vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		img.save_png("res://import/cultures/%s_%s.png" % [nom, "albedo" if pass_i == 0 else "normal"])

func _run() -> void:
	vp = SubViewport.new()
	vp.size = Vector2i(1024, 1024)
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
	cam.size = TAILLE
	cam.far = 50.0
	vp.add_child(cam)
	cam.make_current()
	# bandes vues de face (bas de l'image = pied des plants ; 3 m de haut comme la bande du maïs)
	var seuls := []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seulement="):
			seuls = a.trim_prefix("--seulement=").split(",")
	for b in BANDES:
		if not seuls.is_empty() and not ("strip_" + b[0]) in seuls:
			continue
		var src: PackedScene = load("res://import/cultures/%s.glb" % b[0])
		var row := Node3D.new(); vp.add_child(row)
		var rng := RandomNumberGenerator.new(); rng.seed = 7
		for k in int(b[1]):
			var x := -TAILLE * 0.5 + (k + rng.randf()) * TAILLE / float(b[1])
			_poser(row, src, x, rng.randf_range(-b[4], b[4]), 0.0, rng.randf_range(b[2], b[3]), rng.randf() * TAU, false)
		cam.global_position = Vector3(0, TAILLE * 0.5 - 0.02, 10)
		cam.look_at(Vector3(0, TAILLE * 0.5 - 0.02, 0), Vector3.UP)
		await _cuire(row, "strip_" + b[0])
		row.queue_free()
		await get_tree().process_frame
		print("bande ", b[0])
	# nappes vues de dessus (dessus du champ, raccord dans les deux sens)
	for b in NAPPES:
		if not seuls.is_empty() and not ("top_" + b[0]) in seuls:
			continue
		var src: PackedScene = load("res://import/cultures/%s.glb" % b[0])
		var row := Node3D.new(); vp.add_child(row)
		var rng := RandomNumberGenerator.new(); rng.seed = 9
		for k in int(b[1]):
			_poser(row, src, rng.randf_range(-TAILLE * 0.5, TAILLE * 0.5), rng.randf_range(-TAILLE * 0.5, TAILLE * 0.5),
				0.0, rng.randf_range(b[2], b[3]), rng.randf() * TAU, true)
		cam.global_position = Vector3(0, 10, 0)
		cam.look_at(Vector3(0, 0, 0), Vector3(0, 0, -1))
		await _cuire(row, "top_" + b[0])
		row.queue_free()
		await get_tree().process_frame
		print("nappe ", b[0])
	if "plants" in seuls:
		await _plants()
	get_tree().quit()

# Plants un par un (#142, issue #25 : « plante juste les sprites ») : 4 cultures × 8 variantes, vues de côté, chacune
# dans une case de 256 × 512 px (largeur = hauteur / 2) ; blé et colza en petites touffes (trop serrés pour un sprite
# par tige). Sortie : res://assets/veg/plants_{albedo,normal}.png (2048 × 2048), lue par crops.gd / crops_plants.gdshader.
# nom, échelle min/max du modèle, hauteur de la case (m), pieds par touffe, rayon de la touffe (m), orientation de base,
# écart d'orientation (rad) : blé (ble2, une rangée de tiges de 0,9 m) et colza (0,95 m de large) vus par la tranche
const PLANTS := [["res://assets/veg/mais.glb", 2.1, 2.6, 3.0, 1, 0.0, 0.0, TAU],
	["res://import/cultures/ble2.glb", 0.85, 1.05, 1.2, 2, 0.05, 0.0, 0.3],
	["res://import/cultures/colza.glb", 1.0, 1.25, 1.4, 1, 0.0, PI * 0.5, 0.3],
	["res://import/cultures/tournesol.glb", 1.6, 2.0, 2.4, 1, 0.0, 0.0, TAU]]

func _plants() -> void:
	vp.size = Vector2i(256, 512)
	var atlas := [Image.create(2048, 2048, false, Image.FORMAT_RGBA8), Image.create(2048, 2048, false, Image.FORMAT_RGBA8)]
	for ci in PLANTS.size():
		var b: Array = PLANTS[ci]
		var src: PackedScene = load(b[0])
		var hc: float = b[3]
		cam.size = hc
		cam.global_position = Vector3(0, hc * 0.5, 10)
		cam.look_at(Vector3(0, hc * 0.5, 0), Vector3.UP)
		for v in 8:
			var row := Node3D.new(); vp.add_child(row)
			var rng := RandomNumberGenerator.new(); rng.seed = 100 * ci + v
			for k in int(b[4]):
				var a := rng.randf() * TAU
				var r: float = sqrt(rng.randf()) * b[5]
				var m: Node3D = src.instantiate()
				var s := rng.randf_range(b[1], b[2])
				m.transform = Transform3D(Basis(Vector3.UP, b[6] + rng.randf_range(-0.5, 0.5) * b[7]).rotated(Vector3(cos(a), 0, sin(a)), rng.randf_range(-0.06, 0.06)).scaled(Vector3.ONE * s),
					Vector3(cos(a) * r, 0, sin(a) * r))
				row.add_child(m)
			for pass_i in 2:
				_materiaux(row, pass_i)
				for i in 4:
					await get_tree().process_frame
				var img := vp.get_texture().get_image()
				img.convert(Image.FORMAT_RGBA8)
				atlas[pass_i].blit_rect(img, Rect2i(0, 0, 256, 512), Vector2i(v * 256, ci * 512))
			row.queue_free()
			await get_tree().process_frame
		print("plants ", b[0])
	atlas[0].save_png("res://assets/veg/plants_albedo.png")
	atlas[1].save_png("res://assets/veg/plants_normal.png")
