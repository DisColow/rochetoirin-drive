## Relief de remplacement (v6.16, issue #11) : le jeu ne charge que les régions Terrain3D autour de la voiture ; au-delà,
## un maillage léger (scripts/relief.gd) prend leur place. Pour qu'on ne voie aucune différence quand une région se
## charge, son aspect est cuit à partir du vrai relief : vue de dessus orthographique du relief avec son propre shader
## (terrain.gdshader, `bake_mode`), qui sort l'albédo, la normale du monde, puis rugosité / AO / spéculaire.
## Sorties (res://world/relief/) : albedo.png, normale.png, matiere.png (PX m par pixel), hauteurs.bin (grille de
## PAS m : en-tête x0, z0, pas, largeur, hauteur, puis les hauteurs en float32, NaN hors des régions).
## xvfb-run godot --path godot res://tools/bake_relief.tscn   (rendu nécessaire : pas de --headless)
extends Node

const PX := 8.0            # m par pixel des textures
const PAS := 32.0          # m entre deux hauteurs
const TUILE := 4           # régions par côté de vue (4 km)
const REG := 1024.0

var vp: SubViewport
var cam: Camera3D
var terrain: Terrain3D

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var idx: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://import/terrain/index.json"))
	var i0 := 999; var i1 := -999; var j0 := 999; var j1 := -999
	for r in idx["regions"]:
		i0 = mini(i0, int(r[0])); i1 = maxi(i1, int(r[0])); j0 = mini(j0, int(r[1])); j1 = maxi(j1, int(r[1]))
	var nx := i1 - i0 + 1
	var nz := j1 - j0 + 1
	var x0 := i0 * REG
	var z0 := j0 * REG
	print("régions ", i0, "..", i1, " × ", j0, "..", j1)

	vp = SubViewport.new()
	var cote := int(TUILE * REG / PX)
	vp.size = Vector2i(cote, cote)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_DISABLED
	add_child(vp)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.BLACK
	env.ambient_light_energy = 0.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	we.environment = env
	vp.add_child(we)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = TUILE * REG
	cam.near = 10.0
	cam.far = 8000.0
	cam.rotation_degrees = Vector3(-90, 0, 0)
	vp.add_child(cam)
	cam.current = true

	# relief : mêmes réglages que main.gd
	terrain = Terrain3D.new()
	terrain.change_region_size(512)
	terrain.vertex_spacing = 2.0
	terrain.data_directory = "res://terrain"
	terrain.assets = load("res://assets/terrain_assets.tres")
	terrain.mesh_lods = 7
	terrain.mesh_size = 48
	var m := terrain.material
	m.world_background = Terrain3DMaterial.NONE
	m.show_checkered = false
	m.set_shader_param("blend_sharpness", 0.75)
	m.set_shader_param("macro_variation1", Color(0.86, 0.9, 0.74))
	m.set_shader_param("macro_variation2", Color(0.9, 0.86, 0.84))
	m.set_shader_param("macro_variation_slope", 0.4)
	m.set_shader_param("noise1_scale", 0.03)
	m.set_shader_param("noise2_scale", 0.09)
	m.set("shader_override", load("res://scripts/terrain.gdshader"))
	m.set("shader_override_enabled", true)
	vp.add_child(terrain)
	terrain.set_camera(cam)

	# hauteurs (grille de PAS m, NaN hors des régions)
	var hw := int(nx * REG / PAS) + 1
	var hh := int(nz * REG / PAS) + 1
	var hts := PackedFloat32Array()
	hts.resize(hw * hh)
	var n_ok := 0
	for b in hh:
		for a in hw:
			var p := Vector3(x0 + a * PAS, 0.0, z0 + b * PAS)
			var h := NAN
			# sur un bord de région, la région voisine peut manquer : on prend le côté qui existe
			for d in [Vector3.ZERO, Vector3(-0.5, 0, 0), Vector3(0, 0, -0.5), Vector3(-0.5, 0, -0.5)]:
				h = terrain.data.get_height(p + d)
				if not is_nan(h):
					break
			hts[b * hw + a] = h
			if not is_nan(h):
				n_ok += 1
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://world/relief"))
	var f := FileAccess.open("res://world/relief/hauteurs.bin", FileAccess.WRITE)
	f.store_float(x0); f.store_float(z0); f.store_float(PAS); f.store_32(hw); f.store_32(hh)
	f.store_buffer(hts.to_byte_array())
	f.close()
	print("hauteurs ", hw, " × ", hh, " (", n_ok, " points)")

	# vues de dessus
	var W := int(nx * REG / PX)
	var H := int(nz * REG / PX)
	var noms := ["", "albedo", "normale", "matiere"]
	for mode in [1, 2, 3]:
		m.set_shader_param("bake_mode", mode)
		var img := Image.create(W, H, false, Image.FORMAT_RGB8)
		for tz in range(0, nz, TUILE):
			for tx in range(0, nx, TUILE):
				var cx := x0 + (tx + TUILE * 0.5) * REG
				var cz := z0 + (tz + TUILE * 0.5) * REG
				cam.position = Vector3(cx, 4000.0, cz)
				for k in 4:
					await RenderingServer.frame_post_draw
				var vue := vp.get_texture().get_image()
				vue.convert(Image.FORMAT_RGB8)
				img.blit_rect(vue, Rect2i(Vector2i.ZERO, vue.get_size()), Vector2i(int(tx * REG / PX), int(tz * REG / PX)))
		if mode > 1:
			img.srgb_to_linear()      # données, pas des couleurs : la sortie de la vue est en sRGB
		img.save_png("res://world/relief/%s.png" % noms[mode])
		print(noms[mode], " ", W, " × ", H)
	get_tree().quit()
