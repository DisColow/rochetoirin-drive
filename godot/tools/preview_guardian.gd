## Aperçu du modèle du gardien : xvfb-run godot --path godot res://tools/preview_guardian.tscn -> user://gardien_*.png
extends Node3D

func _ready() -> void:
	var n: Node3D = load("res://models/goku.glb").instantiate()
	add_child(n)
	var ap: AnimationPlayer = n.find_children("*", "AnimationPlayer", true, false)[0]
	ap.play("Idle")
	await get_tree().process_frame
	var sk: Skeleton3D = n.find_children("*", "Skeleton3D", true, false)[0]
	var top := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("mixamorig_HeadTop_End_07"))
	var foot := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("mixamorig_LeftToe_End_059"))
	var hips := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("mixamorig_Hips_01"))
	print("tête ", top.origin, " pied ", foot.origin, " bassin ", hips.origin, " hauteur ", top.origin.y - foot.origin.y)
	var h: float = maxf(top.origin.y - foot.origin.y, 0.001)
	n.scale = Vector3.ONE * (1.8 / h)
	n.position.y = -foot.origin.y * (1.8 / h)
	var we := WorldEnvironment.new(); var env := Environment.new()
	env.background_mode = Environment.BG_COLOR; env.background_color = Color(0.6, 0.7, 0.8)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.ambient_light_color = Color(0.8, 0.8, 0.8)
	we.environment = env; add_child(we)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-45, -30, 0); add_child(sun)
	var cam := Camera3D.new(); add_child(cam); cam.make_current()
	var views := {"face": Vector3(0, 1.0, 3.2), "profil": Vector3(3.2, 1.0, 0.0), "dos": Vector3(0, 1.0, -3.2)}
	for k in views:
		var v := [k, views[k]]
		cam.global_position = v[1]
		cam.look_at(Vector3(0, 0.9, 0), Vector3.UP)
		for i in 8:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("user://gardien_%s.png" % v[0])
	get_tree().quit()
