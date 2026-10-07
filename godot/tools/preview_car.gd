## Aperçu de la voiture seule (4 vues) : xvfb-run godot --path godot res://tools/preview_car.tscn -> user://car_*.png
extends Node3D

func _ready() -> void:
	var car = preload("res://scripts/car.gd").new()
	car.freeze = true
	add_child(car)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.68, 0.74)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.82)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(30, 30)
	ground.mesh = pm
	var gm := StandardMaterial3D.new(); gm.albedo_color = Color(0.35, 0.35, 0.36)
	ground.material_override = gm
	add_child(ground)
	var cam := Camera3D.new()
	cam.fov = 40
	add_child(cam)
	cam.make_current()
	await get_tree().process_frame
	# avant de la voiture : +Z (Godot)
	var views := {"avant34": Vector3(3.6, 1.6, 5.2), "profil": Vector3(-7.5, 1.2, 0.2), "arriere34": Vector3(-3.8, 1.9, -5.0), "face": Vector3(0.0, 1.0, 7.5), "roue": Vector3(-2.6, 0.6, 2.4)}
	for n in views:
		cam.global_position = views[n]
		cam.look_at(Vector3(-0.7, 0.35, 1.29) if n == "roue" else Vector3(0, 0.8, 0), Vector3.UP)
		for i in 6:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("user://car_%s.png" % n)
		print("vue ", n)
	get_tree().quit()
