## Essai du relief chargé autour de la voiture (relief.gd) : une cible parcourt la carte à 130 km/h (d'ouest en est
## puis retour) ; journal : régions ajoutées / libérées, durée de chaque mise à jour, mémoire.
## xvfb-run godot --path godot --script res://tools/essai_relief.gd   (ou --headless : sans le coût des textures)
extends SceneTree

func _initialize() -> void:
	var t := Terrain3D.new()
	t.change_region_size(512)
	t.vertex_spacing = 2.0
	t.assets = load("res://assets/terrain_assets.tres")
	root.add_child.call_deferred(t)
	await process_frame
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	t.set_camera(cam)
	var R := preload("res://scripts/relief.gd")
	var rel = R.new(t)
	root.add_child(rel)
	rel.cible = cam
	var m0 := Performance.get_monitor(Performance.MEMORY_STATIC)
	var a := Vector3(-12000, 500, -1500)
	var b := Vector3(4000, 500, -1500)
	cam.position = a
	var t0 := Time.get_ticks_msec()
	rel.charger_autour(a)
	print("départ : %d régions en %d ms" % [rel.charge.size(), Time.get_ticks_msec() - t0])
	var v := 36.0                      # m/s
	var pire := 0.0
	var n := 0
	for sens in [1, -1]:
		var de: Vector3 = a if sens == 1 else b
		var vers: Vector3 = b if sens == 1 else a
		var d := de.distance_to(vers)
		var s := 0.0
		while s < d:
			var t1 := Time.get_ticks_usec()
			cam.position = de.lerp(vers, s / d)
			await process_frame
			var ms := (Time.get_ticks_usec() - t1) / 1000.0
			pire = maxf(pire, ms)
			s += v * 0.1                   # 10 images par seconde de trajet simulé (accéléré)
			n += 1
			if not is_nan(R.hauteur(cam.position)) and is_nan(t.data.get_height(cam.position)) and rel.dispo.has(Vector2i(floor(cam.position.x / 1024), floor(cam.position.z / 1024))):
				print("MANQUE : pas de relief sous la cible en ", cam.position)
		print("trajet %d : %d régions chargées, mémoire +%d Mo, image la plus longue %.0f ms" % [sens, rel.charge.size(), (Performance.get_monitor(Performance.MEMORY_STATIC) - m0) / 1e6, pire])
	quit()
