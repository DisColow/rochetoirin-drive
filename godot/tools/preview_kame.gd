## Aperçu des poses du gardien (charge, tir) : xvfb-run godot --path godot --script res://tools/preview_kame.gd
## -> user://kame_*.png
extends SceneTree

func _init() -> void:
	var root3 := Node3D.new()
	root.add_child.call_deferred(root3)
	await process_frame
	var we := WorldEnvironment.new(); var env := Environment.new()
	env.background_mode = Environment.BG_COLOR; env.background_color = Color(0.45, 0.62, 0.85)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.ambient_light_color = Color(0.7, 0.7, 0.75)
	env.glow_enabled = false
	we.environment = env; root3.add_child(we)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-40, -30, 0); root3.add_child(sun)
	var g = load("res://scripts/guardian.gd").new()
	root3.add_child(g)
	await process_frame
	g.set_process(false)
	print("iks ", g.iks.size())
	g.aura.visible = OS.get_environment("SANS_AURA") == ""
	var cam := Camera3D.new(); root3.add_child(cam); cam.make_current()
	var shots := [["charge_mi", 0.5, 0.0, Vector3(9, 6, 14)], ["charge", 1.0, 0.0, Vector3(9, 6, 14)],
		["charge_face", 1.0, 0.0, Vector3(0, 6, 16)], ["tir", 1.0, 1.0, Vector3(14, 7, 8)]]
	for s in shots:
		cam.global_position = s[3]
		cam.look_at(Vector3(0, 5, 0), Vector3.UP)
		for i in 20:
			g._pose(s[1], s[2])
			if s[2] > 0.0:
				g._place_beam(g.ball.global_position, g.ball.global_position + Vector3(0, -6, 60), 2.2)
				g.head.visible = true
				g.head.global_position = g.ball.global_position + Vector3(0, -6, 60)
				g.head.scale = Vector3.ONE * 3.0
			await process_frame
		root.get_texture().get_image().save_png("user://kame_%s.png" % s[0])
		print("capture ", s[0])
	quit()
