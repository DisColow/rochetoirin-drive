## Monde : relief Terrain3D, routes en tuiles chargées au fil de la route, horizon courbe, ciel HDRI, soleil, voiture.
extends Node3D

const SUN_ELEV := 48.0          # ciel « kloofendal_48d » : soleil à 48° ; azimut mesuré sur l'image au démarrage

var terrain: Terrain3D
var car: VehicleBody3D
var roads: Node3D
var cam_rig: Node3D

func _ready() -> void:
	var skip := OS.get_environment("RS_SKIP")
	if not skip.contains("env"): _environment()
	if not skip.contains("terrain"): _terrain()
	if not skip.contains("far"): _far()
	roads = preload("res://scripts/roads.gd").new()
	add_child(roads)
	var spawn: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://world/spawn.json"))
	car = preload("res://scripts/car.gd").new()
	add_child(car)
	car.place(Vector3(spawn.x, spawn.y + 0.6, spawn.z), float(spawn.heading))
	roads.target = car
	roads.update_now()
	if "collision_target" in terrain:
		terrain.set("collision_target", car)
	cam_rig = preload("res://scripts/camera_rig.gd").new()
	cam_rig.target = car
	add_child(cam_rig)
	var hud = preload("res://scripts/hud.gd").new()
	hud.car = car
	hud.process_mode = Node.PROCESS_MODE_ALWAYS          # la carte reste utilisable jeu en pause
	add_child(hud)
	hud.teleport.connect(_teleport)

## Téléportation sans à-coup : routes de la destination chargées d'abord, voiture immobilisée le temps que
## les collisions du relief se créent autour d'elle.
func _teleport(p: Vector3, heading: float) -> void:
	car.freeze = true
	car.place(p, heading)
	cam_rig.snap()
	roads.update_now()
	await get_tree().create_timer(0.6).timeout
	car.freeze = false

func _environment() -> void:
	var sky_tex: Texture2D = load("res://assets/sky.hdr")
	var mat := PanoramaSkyMaterial.new()
	mat.panorama = sky_tex
	mat.energy_multiplier = 1.0
	var sky := Sky.new()
	sky.sky_material = mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.25
	env.glow_bloom = 0.02
	# perspective aérienne : brume légère qui prend la couleur du ciel (horizon bleuté des Alpes)
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_density = 0.000014
	env.fog_aerial_perspective = 0.85
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	# soleil : direction du point le plus lumineux de l'HDRI
	var img := sky_tex.get_image()
	var az := 0.0
	if img:
		var w := img.get_width(); var h := img.get_height()
		var best := 0.0
		for y in range(0, h / 2, 4):
			for x in range(0, w, 4):
				var c := img.get_pixel(x, y)
				var l := c.r + c.g + c.b
				if l > best:
					best = l; az = float(x) / w
	var sun := DirectionalLight3D.new()
	# u = 0,5 face à -Z dans Godot (centre du panorama) ; azimut en radians autour de Y
	sun.rotation = Vector3(deg_to_rad(-SUN_ELEV), (0.5 - az) * TAU + PI, 0)
	sun.light_energy = 1.6
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 220.0
	sun.shadow_blur = 1.2
	add_child(sun)

func _terrain() -> void:
	terrain = Terrain3D.new()
	terrain.change_region_size(512)
	terrain.vertex_spacing = 2.0
	terrain.data_directory = "res://terrain"
	terrain.assets = load("res://assets/terrain_assets.tres")
	terrain.mesh_lods = 7
	terrain.mesh_size = 48
	terrain.collision_radius = 96
	var m := terrain.material
	m.world_background = Terrain3DMaterial.NONE
	m.show_checkered = false
	terrain.material.set_shader_param("blend_sharpness", 0.75)
	add_child(terrain)
	terrain.set_camera(get_viewport().get_camera_3d())

func _far() -> void:
	var sh := preload("res://scripts/far.gdshader")
	for f in DirAccess.get_files_at("res://world/far"):
		if not (f.ends_with(".glb") or f.ends_with(".glb.import")):
			continue
		f = f.trim_suffix(".import")
		var sc: PackedScene = load("res://world/far/" + f)
		var n := sc.instantiate()
		var tex: Texture2D = load("res://assets/tex/far_pano.jpg" if f.begins_with("pano") else "res://assets/tex/far_near.jpg")
		var mat := ShaderMaterial.new()
		mat.shader = sh
		mat.set_shader_parameter("tex", tex)
		for mi in n.find_children("*", "MeshInstance3D", true, false):
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.extra_cull_margin = 2000.0
		add_child(n)

func _process(_dt: float) -> void:
	if terrain and get_viewport().get_camera_3d() and terrain.get_camera() != get_viewport().get_camera_3d():
		terrain.set_camera(get_viewport().get_camera_3d())

# ---------------------------------------------------------------- captures de contrôle (pipeline)
# godot --path godot -- --shots=res://shots.json : [{"name", "pos":[x,y,z], "look":[x,y,z], "fov"}] -> user://shots/
func _enter_tree() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			_shots.call_deferred(a.trim_prefix("--shots="))

func _shots(path: String) -> void:
	var list: Array = JSON.parse_string(FileAccess.get_file_as_string(path))
	set_process(false)
	cam_rig.set_process(false)
	car.freeze = true
	DirAccess.make_dir_recursive_absolute("user://shots")
	for s in list:
		if s.get("tp", false):
			var hud := find_children("*", "CanvasLayer", false, false)[0]
			hud._show_drive(false)
			hud.map.open()
			hud.map.zoom = 0.5
			hud.map._pick(hud.map.world_to_screen(Vector2(s.tp[0], s.tp[1])))
			car.freeze = false
			set_process(true); cam_rig.set_process(true); roads.target = car
			for i in 240:
				await get_tree().physics_frame
			print("téléporté en ", car.global_position, " roues au sol ", car.wheels.filter(func(w): return w.is_in_contact()).size())
			get_viewport().get_texture().get_image().save_png("user://shots/%s.png" % s.name)
			print("capture ", s.name)
			continue
		if s.get("map", false):
			var hud := find_children("*", "CanvasLayer", false, false)[0]
			hud._show_drive(false)
			get_tree().paused = false
			hud.map.open()
			hud.map.zoom = s.get("zoom", 0.6)
			for i in 10:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png("user://shots/%s.png" % s.name)
			hud.map._close()
			print("capture ", s.name)
			continue
		var c: Camera3D = cam_rig.cam
		var p := Vector3(s.pos[0], s.pos[1], s.pos[2])
		car.global_position = p + Vector3(0, -50, 0) if not s.get("car", false) else car.global_position
		roads.target = c
		c.global_position = p
		c.look_at(Vector3(s.look[0], s.look[1], s.look[2]), Vector3.UP)
		c.fov = s.get("fov", 62.0)
		terrain.set_camera(c)
		for i in 40:
			roads._process(0.3)
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("user://shots/%s.png" % s.name)
		print("capture ", s.name)
	get_tree().quit()

# ---------------------------------------------------------------- essai de conduite (pipeline) : --drive-test
func _physics_process(_dt: float) -> void:
	if not OS.get_cmdline_user_args().has("--drive-test"):
		return
	var t := Engine.get_physics_frames()
	if t == 1:
		print("départ ", car.global_position)
	car.touch_throttle = 1.0 if t < 1200 else 0.0
	car.touch_brake = 1.0 if t >= 1200 else 0.0
	car.touch_steer = 0.3 if (t > 600 and t < 800) else 0.0
	if t % 120 == 0:
		print("t=%.0fs pos=%s v=%.0f km/h avant=%.1f roues au sol=%d" % [t / 120.0, car.global_position.snapped(Vector3(0.1, 0.1, 0.1)), car.kmh(), car.forward_speed(), car.wheels.filter(func(w): return w.is_in_contact()).size()])
	if t > 1800:
		get_tree().quit()
