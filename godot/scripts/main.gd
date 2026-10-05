## Monde : relief Terrain3D, routes en tuiles chargées au fil de la route, horizon courbe, ciel HDRI, soleil, voiture.
extends Node3D

const SUN_ELEV := 48.0          # ciel « kloofendal_48d » : soleil à 48° ; azimut mesuré sur l'image au démarrage

var terrain: Terrain3D
var car: VehicleBody3D
var roads: Node3D
var buildings: Node3D
var vegetation: Node3D
var crops: Node3D
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
	car.road_pts = FileAccess.get_file_as_bytes("res://world/teleport.bin").to_float32_array()
	add_child(car)
	car.place(Vector3(spawn.x, spawn.y + 0.6, spawn.z), float(spawn.heading))
	# essai : --drive-from=x,y,z,cap (départ de l'essai de conduite ailleurs qu'au point de départ)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--drive-from="):
			var v := a.trim_prefix("--drive-from=").split(",")
			car.place(Vector3(float(v[0]), float(v[1]), float(v[2])), float(v[3]))
	roads.target = car
	roads.update_now()
	buildings = preload("res://scripts/buildings.gd").new()
	add_child(buildings)
	buildings.target = car
	buildings.update_now()
	vegetation = preload("res://scripts/vegetation.gd").new()
	var cfg := ConfigFile.new()
	cfg.load("user://reglages.cfg")
	vegetation.level = int(cfg.get_value("affichage", "vegetation", 2))
	add_child(vegetation)
	vegetation.target = car
	vegetation.update_now()
	crops = preload("res://scripts/crops.gd").new()
	crops.level = vegetation.level
	crops.terrain = terrain
	add_child(crops)
	crops.target = car
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
	var cr = preload("res://scripts/crash_report.gd").new()
	cr.car = car; cr.hud = hud; cr.names = hud.names
	add_child(cr)

## Téléportation sans à-coup : appliquée une fois le jeu repris (un déplacement fait pendant la pause est annulé par
## le moteur physique), routes et bâtiments de la destination chargés d'abord, voiture maintenue immobile 0,6 s.
func _teleport(p: Vector3, heading: float) -> void:
	await get_tree().process_frame
	await get_tree().physics_frame
	car.place(p, heading)
	car.hold(0.6)
	cam_rig.snap()
	roads.update_now()
	buildings.update_now()
	vegetation.update_now()

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
	# ombres : 2 cascades (40 m nette, puis jusqu'à 320 m) fondues entre elles et au loin, pas d'apparition sèche
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 320.0
	sun.directional_shadow_split_1 = 0.14
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_fade_start = 0.7
	sun.shadow_bias = 0.08
	sun.shadow_normal_bias = 1.6
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
		if s.has("cam"):
			# vue de la caméra du jeu (0 poursuite, 1 conducteur, 2 capot) après un court trajet
			car.freeze = false
			set_process(true); cam_rig.set_process(true); roads.target = car; buildings.target = car; vegetation.target = car; crops.target = car
			cam_rig.mode = int(s.cam)
			car.touch_throttle = 0.5
			for i in 240:
				await get_tree().physics_frame
			car.touch_throttle = 0.0
			get_viewport().get_texture().get_image().save_png("user://shots/%s.png" % s.name)
			print("capture ", s.name, " : objets ", Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
				", appels de dessin ", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				", primitives ", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
			for n in [roads, buildings, vegetation, crops, terrain]:
				if n == null:
					continue
				n.visible = false
				for i in 4:
					await get_tree().process_frame
				print("   sans ", n.name, " : appels ", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
					", primitives ", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
				n.visible = true
			continue
			continue
		if s.get("tap", false):
			# téléportation par un vrai toucher : bouton CARTE puis toucher sur la carte (chemin complet des entrées)
			car.freeze = false
			set_process(true); cam_rig.set_process(true); roads.target = car; buildings.target = car; vegetation.target = car; crops.target = car
			var hud := find_children("*", "CanvasLayer", false, false)[0]
			var before := car.global_position
			Input.action_press("carte")
			await get_tree().process_frame
			Input.action_release("carte")
			for i in 5:
				await get_tree().process_frame
			print("carte ouverte : ", hud.map.visible, " pause : ", get_tree().paused)
			hud.map.zoom = 0.5
			hud.map.center = Vector2(s.tap[0], s.tap[1])
			await get_tree().process_frame
			var sp: Vector2 = get_viewport().get_final_transform() * (hud.map.world_to_screen(Vector2(s.tap[0], s.tap[1])) + hud.map.global_position)
			var ev := InputEventScreenTouch.new(); ev.index = 0; ev.position = sp; ev.pressed = true
			Input.parse_input_event(ev)
			await get_tree().process_frame
			var ev2 := InputEventScreenTouch.new(); ev2.index = 0; ev2.position = sp; ev2.pressed = false
			Input.parse_input_event(ev2)
			for i in 360:
				await get_tree().physics_frame
			print("toucher en ", sp, " : avant ", before.snapped(Vector3.ONE), " après ", car.global_position.snapped(Vector3.ONE),
				" carte visible ", hud.map.visible, " pause ", get_tree().paused)
			get_viewport().get_texture().get_image().save_png("user://shots/%s.png" % s.name)
			continue
		if s.get("tp", false):
			var hud := find_children("*", "CanvasLayer", false, false)[0]
			hud._show_drive(false)
			hud.map.open()
			hud.map.zoom = 0.5
			hud.map._pick(hud.map.world_to_screen(Vector2(s.tp[0], s.tp[1])))
			car.freeze = false
			set_process(true); cam_rig.set_process(true); roads.target = car; buildings.target = car; vegetation.target = car; crops.target = car
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
		buildings.target = c
		vegetation.target = c
		crops.target = c
		c.global_position = p
		c.look_at(Vector3(s.look[0], s.look[1], s.look[2]), Vector3.UP)
		c.fov = s.get("fov", 62.0)
		terrain.set_camera(c)
		for i in 40:
			roads._process(0.3)
			buildings._process(0.3)
			vegetation._process(0.3)
			crops._process(0.3)
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("user://shots/%s.png" % s.name)
		print("capture ", s.name)
	get_tree().quit()

# ---------------------------------------------------------------- essai de conduite (pipeline) : --drive-test
func _physics_process(_dt: float) -> void:
	if OS.get_cmdline_user_args().has("--mem-test"):
		_mem_test()
		return
	if not OS.get_cmdline_user_args().has("--drive-test"):
		return
	var t := Engine.get_physics_frames()
	if t == 1:
		print("départ ", car.global_position)
	var dur := 3000 if OS.get_cmdline_user_args().has("--long") else 1200
	car.touch_throttle = 1.0 if t < dur else 0.0
	car.touch_brake = 1.0 if t >= dur else 0.0
	var straight: bool = Array(OS.get_cmdline_user_args()).any(func(a): return a.begins_with("--drive-from="))
	car.touch_steer = 0.3 if (t > 600 and t < 800 and not straight) else 0.0
	if OS.get_cmdline_user_args().has("--flip-test"):
		car.touch_throttle = 0.0; car.touch_brake = 0.0; car.touch_steer = 0.0
		if t == 240:
			var tr := car.global_transform
			car.global_transform = Transform3D(tr.basis.rotated(tr.basis.z, PI), tr.origin + tr.basis.x * 14.0 + Vector3(0, 1.5, 0))
			print("retournée en ", car.global_position)
		if t % 120 == 0 and t > 240:
			print("  t=%ds pos=%s haut=%.2f route=%s" % [t / 120, car.global_position.snapped(Vector3(0.1, 0.1, 0.1)), car.global_transform.basis.y.y, find_children("*", "CanvasLayer", false, false)[0].names.road_at(car.global_position)])
		return
	if OS.get_cmdline_user_args().has("--hard-steer"):
		car.touch_steer = (1.0 if t < 1000 else -1.0) if t > 840 and t < 1150 else 0.0
		if t % 30 == 0 and t > 800:
			print("  braquage t=%.2f v=%d km/h haut=%.2f roues=%d" % [t / 120.0, car.kmh(), car.global_transform.basis.y.y, car.wheels.filter(func(w): return w.is_in_contact()).size()])
	if not car.global_position.is_finite() or car.linear_velocity.length() > 80.0:
		print("ANOMALIE t=%d pos=%s v=%s" % [t, car.global_position, car.linear_velocity])
	if t % 120 == 0:
		print("t=%.0fs pos=%s v=%.0f km/h avant=%.1f roues au sol=%d" % [t / 120.0, car.global_position.snapped(Vector3(0.1, 0.1, 0.1)), car.kmh(), car.forward_speed(), car.wheels.filter(func(w): return w.is_in_contact()).size()])
	if t > dur + 600:
		get_tree().quit()

# ---------------------------------------------------------------- essai mémoire (pipeline) : --mem-test
# La voiture saute de point en point le long des routes (tout le réseau) ; mémoire et objets affichés.
var _mem_pts := PackedFloat32Array()
func _mem_test() -> void:
	var t := Engine.get_physics_frames()
	if _mem_pts.is_empty():
		_mem_pts = FileAccess.get_file_as_bytes("res://world/teleport.bin").to_float32_array()
	if t % 30 == 0:
		var i := (t / 30 * 997 * 4) % _mem_pts.size()
		i -= i % 4
		car.freeze = true
		car.place(Vector3(_mem_pts[i], _mem_pts[i + 2], _mem_pts[i + 1]), _mem_pts[i + 3])
	if t % 600 == 0:
		print("t=%ds mémoire %.0f Mo objets %d nœuds %d ressources %d tuiles routes %d bâtiments %d" % [t / 120,
			Performance.get_monitor(Performance.MEMORY_STATIC) / 1e6, Performance.get_monitor(Performance.OBJECT_COUNT),
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
			roads.loaded.size(), buildings.loaded.size()])
	if t > 120 * 240:
		get_tree().quit()
