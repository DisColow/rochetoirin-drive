## Modes d'essai et captures de contrôle du pipeline (issue #30 : sortis de main.gd, qui ne garde que le jeu).
## Script de la scène principale : il hérite du jeu (main.gd) et n'agit qu'avec les options de la ligne de commande
## (--shots=, --drive-test et ses variantes, --perf-breakdown, --mem-test…) ; sans option, le jeu est inchangé.
extends "res://scripts/main.gd"

var _bord_t0 := -1
var _bord_info := []        # essai --champ-bord : [point de la route, sens, côté du champ]

# ---------------------------------------------------------------- captures de contrôle (pipeline)
# godot --path godot -- --shots=res://shots.json : [{"name", "pos":[x,y,z], "look":[x,y,z], "fov"}] -> user://shots/
func _enter_tree() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			_shots.call_deferred(a.trim_prefix("--shots="))
		if a == "--vram":
			_vram_detail.call_deferred()

func _shots(path: String) -> void:
	while not Chargement.fini:                 # le monde se construit par étapes (v6.14)
		await get_tree().process_frame
	var list: Array = JSON.parse_string(FileAccess.get_file_as_string(path))
	set_process(false)
	cam_rig.set_process(false)
	car.freeze = true
	DirAccess.make_dir_recursive_absolute("user://shots")
	for s in list:
		if s.has("niveau"):
			perf_auto = false
			get_node("HUD").appliquer_niveau(int(s.niveau))
			for i in 30:
				await get_tree().process_frame
		if s.has("weather"):
			meteo_choix = int(s.weather)
			weather = int(s.weather)
			_meteo_de = weather
			_meteo_f = 1.0
			_wet_target = [0.0, 0.0, 1.0, 0.3][weather]
			_wet = _wet_target
		if s.has("time") or s.has("weather"):
			set_time(int(s.get("time", time_of_day)))
		if s.has("cam"):
			# vue de la caméra du jeu (0 poursuite, 1 conducteur, 2 capot) après un court trajet
			car.freeze = false
			set_process(true); cam_rig.set_process(true); roads.target = car; buildings.target = car; fences.target = car; water.target = car; poles.target = car; props.target = car; pools.target = car; shops.target = car; sport.target = car; animaux.target = car; autoroute.target = car; vegetation.target = car; crops.target = car; grass.target = car
			if s.has("voiture"):
				car.construire(String(s.voiture))           # voiture du garage (#122 : comparaison des textures)
				tuning.appliquer()
			if s.has("place"):
				# voiture posée ailleurs (x, y, z, cap) avant le court trajet
				car.place(Vector3(s.place[0], s.place[1], s.place[2]), float(s.place[3]))
				car.hold(0.5)
				for i in 120:
					await get_tree().physics_frame
			cam_rig.set_mode(int(s.cam))
			if s.has("cote"):
				# voiture à l'arrêt vue de côté, à hauteur des roues (contrôle du contact des roues avec le sol)
				for i in 120:
					await get_tree().physics_frame
				cam_rig.set_process(false)
				var cm := get_viewport().get_camera_3d()
				var c0: Vector3 = car.global_position + Vector3(0, 0.5, 0)
				cm.global_position = c0 + car.global_basis.x * float(s.cote)
				cm.look_at(c0, Vector3.UP)
				for i in 10:
					await get_tree().process_frame
				get_viewport().get_texture().get_image().save_png("user://shots/%s.png" % s.name)
				cam_rig.set_process(true)
				continue
			if s.has("sprite"):
				car.set_sprite_mode(bool(s.sprite))
			if s.has("side"):
				# décalage latéral (m, + à droite) : rouler hors de la route (effets des roues dans l'herbe)
				var pp: Vector3 = car.global_position - car.global_basis.x * float(s.side)
				car.place(pp + Vector3(0, 1.0, 0), rad_to_deg(PI - atan2(car.global_basis.z.x, car.global_basis.z.z)))
				car.hold(0.5)
			car.touch_throttle = 0.5
			car.touch_steer = float(s.get("steer", 0.0))
			for i in 240:
				await get_tree().physics_frame
			car.touch_throttle = 0.0
			get_viewport().get_texture().get_image().save_png("user://shots/%s.png" % s.name)
			var EnvP := preload("res://scripts/env.gd")
			print("  phares : factices=%s allumés=%s %s (%d matériaux, relief %s)" % [car._phares_factices, car.lights_on,
				str(EnvP.phares[0]), EnvP.phare_mats.size(), EnvP.terrain_mat != null])
			print("capture ", s.name, " : objets ", Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
				", appels de dessin ", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				", primitives ", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
			if s.has("haut"):
				# caméra relevée de « haut » degrés (ciel, nuages : #57) : capture <nom>_haut.png
				cam_rig.set_process(false)
				var ch := get_viewport().get_camera_3d()
				ch.rotate_object_local(Vector3.RIGHT, deg_to_rad(float(s.haut)))
				for i in 6:
					await get_tree().process_frame
				get_viewport().get_texture().get_image().save_png("user://shots/%s_haut.png" % s.name)
				cam_rig.set_process(true)
			# "views": [[lacet, tangage], …] (rad) : autres angles de caméra autour de la voiture arrêtée (sprite)
			if s.has("views"):
				car.freeze = true
				for k in (s.views as Array).size():
					cam_rig.yaw_off = float(s.views[k][0]); cam_rig.pitch_off = float(s.views[k][1])
					cam_rig._idle = -1e9
					for i in 6:
						await get_tree().process_frame
					get_viewport().get_texture().get_image().save_png("user://shots/%s_%d.png" % [s.name, k])
					print("capture ", s.name, "_", k)
				cam_rig._idle = 0.0; cam_rig.yaw_off = 0.0; cam_rig.pitch_off = 0.0
				car.freeze = false
				continue
			for n in [roads, buildings, fences, water, vegetation, crops, grass, terrain]:
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
			set_process(true); cam_rig.set_process(true); roads.target = car; buildings.target = car; fences.target = car; water.target = car; poles.target = car; props.target = car; pools.target = car; shops.target = car; sport.target = car; animaux.target = car; autoroute.target = car; vegetation.target = car; crops.target = car; grass.target = car
			var hud := get_node("HUD")
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
			var hud := get_node("HUD")
			hud._show_drive(false)
			hud.map.open()
			hud.map.zoom = 0.5
			hud.map._pick(hud.map.world_to_screen(Vector2(s.tp[0], s.tp[1])))
			car.freeze = false
			set_process(true); cam_rig.set_process(true); roads.target = car; buildings.target = car; fences.target = car; water.target = car; poles.target = car; props.target = car; pools.target = car; shops.target = car; sport.target = car; animaux.target = car; autoroute.target = car; vegetation.target = car; crops.target = car; grass.target = car
			for i in 240:
				await get_tree().physics_frame
			print("téléporté en ", car.global_position, " roues au sol ", car.wheels.filter(func(w): return w.is_in_contact()).size())
			get_viewport().get_texture().get_image().save_png("user://shots/%s.png" % s.name)
			print("capture ", s.name)
			continue
		if s.has("act"):
			await _act_shot(s)
			continue
		if s.get("reglages", false):          # menu ⚙ (défilement : "scroll" en pixels ; "bug" : zone de signalement ouverte)
			var hud := get_node("HUD")
			hud._open_settings()
			await get_tree().process_frame
			if s.get("bug", false):
				for b in hud.settings.find_children("*", "Button", true, false):
					if b.text == "Signaler un bug…":
						b.pressed.emit()
			for i in 6:
				await get_tree().process_frame
			hud.settings.get_child(0).scroll_vertical = int(s.get("scroll", 0))
			for i in 4:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png("user://shots/%s.png" % s.name)
			hud._fermer_reglages()
			print("capture ", s.name)
			continue
		if s.get("map", false):
			var hud := get_node("HUD")
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
		cam_rig.set_process(false)                 # (après une capture « tp », la caméra suivait encore la voiture)
		car.freeze = true
		var p := Vector3(s.pos[0], s.pos[1], s.pos[2])
		car.global_position = p + Vector3(0, -50, 0) if not s.get("car", false) else car.global_position
		roads.target = c
		buildings.target = c
		fences.target = c
		water.target = c
		poles.target = c
		props.target = c
		pools.target = c
		shops.target = c
		sport.target = c
		animaux.target = c
		autoroute.target = c
		vegetation.target = c
		crops.target = c
		grass.target = c
		c.global_position = p
		c.look_at(Vector3(s.look[0], s.look[1], s.look[2]), Vector3.UP)
		c.fov = s.get("fov", 62.0)
		get_node("HUD").visible = s.get("hud", true)          # "hud": false : image du monde seul (revues)
		terrain.set_camera(c)
		if not s.get("nuages", true):
			preload("res://scripts/env.gd").set_value("clouds", Vector4.ZERO)
		if relief:
			# "relief": rayon (m) du vrai relief chargé (comparaison avec le relief de remplacement au-delà)
			relief.cible = c
			relief.r_charge = float(s.get("relief", Relief.R_CHARGE))
			relief.r_garde = relief.r_charge + 800.0
			relief.r_lire = relief.r_garde
			relief.charger_autour(p, relief.r_charge)
		for i in 40:
			roads._process(0.3)
			buildings._process(0.3)
			fences._process(0.3)
			water._process(0.3)
			poles._process(0.3)
			props._process(0.3)
			shops._process(0.3)
			sport._process(0.3)
			animaux._process(0.3)
			autoroute._process(0.3)
			vegetation._process(0.3)
			crops._process(0.3)
			grass._process(0.3)
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("user://shots/%s.png" % s.name)
		print("capture ", s.name)
	get_tree().quit()

## Essai des activités (captures « act ») : menu, tracé posé sur la carte, course jouée (voiture déplacée de porte
## en porte), chasse au lieu (carte avec la zone, puis lieu atteint), taxi (client, prise en charge, dépôt).
func _act_shot(s: Dictionary) -> void:
	var a = activities
	var hud := get_node("HUD")
	var snap := func(n: String):
		for i in 8:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("user://shots/%s.png" % n)
		print("capture ", n)
	var run := func(frames: int):
		for i in frames:
			await get_tree().physics_frame
	car.freeze = false
	set_process(true); cam_rig.set_process(true); roads.target = car; buildings.target = car; fences.target = car; water.target = car; poles.target = car; props.target = car; pools.target = car; shops.target = car; sport.target = car; animaux.target = car; autoroute.target = car; vegetation.target = car; crops.target = car; grass.target = car
	get_tree().paused = false
	var c0 := Vector2(car.global_position.x, car.global_position.z)
	match s.act:
		"menu":
			a.open_menu()
			await snap.call(s.name)
			a._resume()
		"course":
			a._course_setup()
			for off in s.get("route", [[0, 0], [250, -150], [520, -40]]):
				a._on_pick(a._rp(a._nearest(c0 + Vector2(off[0], off[1]))))
			hud.map.center = c0 + Vector2(260, -80); hud.map.zoom = 1.6; hud.map.queue_redraw()
			await snap.call(s.name + "_trace")
			a._course_start()
			await run.call(150)
			await snap.call(s.name + "_depart")
			await run.call(400)
			print("course : phase ", a._phase, " prochain ", a._next, " t=", a._t)
			for k in range(1, a._route.size()):
				var i: int = a._route[k]
				car.place(Vector3(a.pts[i], a.pts[i + 2] + 0.3, a.pts[i + 1]), a.pts[i + 3])
				car.hold(0.3)
				await run.call(60)
				print("  porte ", k, " : phase ", a._phase, " prochain ", a._next, " temps ", a._t)
			await snap.call(s.name + "_arrivee")
		"chasse":
			var k := 0
			for j in a.places.size():
				if a.places[j].k == s.get("kind", "gare"):
					k = j; break
			a._hunt_place(k)
			a._hunt_begin()
			await run.call(240)
			hud._show_drive(false)
			hud.map.open()
			hud.map.zoom = 0.35
			hud.map.center = a.circle.c
			hud.map.queue_redraw()
			await snap.call(s.name + "_carte")
			hud.map._close()
			print("chasse : cible ", a._target, " ", a._target_name, " zone ", a.circle)
			var t: Vector2 = a._target
			var i: int = a._nearest(t)
			car.place(Vector3(a.pts[i], a.pts[i + 2] + 0.3, a.pts[i + 1]), a.pts[i + 3])
			car.hold(0.3)
			await run.call(90)
			print("  arrivé : phase ", a._phase, " temps ", a._t)
			await snap.call(s.name + "_trouve")
		"editeur":
			print("formules : ", editeur.match_formula("Sésame, ouvre-toi !"), " ", editeur.match_formula("sesame ouvre toi"),
				" ", editeur.match_formula("Hasta la vista baby"), " ", editeur.match_formula("bonjour"))
			editeur._on_formula("Sésame ouvre-toi", false)
			await run.call(200)
			var vs := get_viewport().get_visible_rect().size
			editeur._pick(Vector2(vs.x * float(s.get("tx", 0.3)), vs.y * float(s.get("ty", 0.45))))
			print("éditeur : ", editeur._sel)
			await snap.call(s.name)
			editeur._open_remark()
			await snap.call(s.name + "_remarque")
			editeur._on_formula("hasta la vista, baby", true)
			print("éditeur actif : ", editeur.active)
		"taxi":
			a._taxi_start()
			var cp: Vector2 = a._cl_pos
			var i: int = a._nearest(cp)
			# voiture arrêtée à 25 m du client, client dans le champ
			var h := deg_to_rad(a.pts[i + 3])
			var back := cp - Vector2(sin(h), -cos(h)) * 25.0
			var j: int = a._nearest(back)
			car.place(Vector3(a.pts[j], a.pts[j + 2] + 0.3, a.pts[j + 1]), a.pts[j + 3])
			car.hold(1.0)
			await run.call(200)
			print("taxi : client ", a._client.get_class(), " enfants ", a._client.get_child_count(), " en ", a._client.global_position)
			cam_rig.set_process(false)
			var cc: Camera3D = cam_rig.cam
			var cl: Vector3 = a._client.global_position
			cc.global_position = cl + a._client.global_transform.basis.z * 4.0 + Vector3(1.5, 1.6, 0)
			cc.look_at(cl + Vector3(0, 1.0, 0), Vector3.UP)
			await snap.call(s.name + "_client")
			cam_rig.set_process(true)
			car.place(Vector3(a.pts[i], a.pts[i + 2] + 0.3, a.pts[i + 1]), a.pts[i + 3])
			car.hold(1.5)
			await run.call(200)
			print("taxi : phase ", a._phase, " destination ", a._dest_name)
			await snap.call(s.name + "_course")
			# conversation : le client lance un fil, on répond deux fois, puis on lui pose une question
			var tk = a._talk
			tk._queue.clear(); tk._step = {}
			tk._start_fil("metier")
			for k in 2:
				var t0 := Time.get_ticks_msec()
				while Time.get_ticks_msec() - t0 < 240000:
					await get_tree().process_frame
					tk._shown = tk._full.length(); tk._say_end = 0; tk._hold = minf(tk._hold, 0.0)   # 1 image/s ici
					if tk._step.get("kind", "") == "choix" and tk._choices.get_child_count() > 0:
						break
				tk._wait = 999.0
				print("  état : étape ", tk._step, " file ", tk._queue.size(), " montré ", tk._shown, "/", tk._full.length(), " attente ", tk._hold, " fin ", tk._say_end - Time.get_ticks_msec(), " pause ", get_tree().paused, " riding ", tk.riding)
				print("taxi : ", tk.client.prenom, " (", tk.client.car.id, ", voix ", tk.client.voix, ") « ", tk._full, " » choix ", tk._choices.get_child_count())
				await snap.call(s.name + "_conversation%d" % k)
				tk._choices.get_child(0).emit_signal("pressed")
				await run.call(2)
				print("  joueur « ", tk._full, " » verdict ", tk._verdict.text, " humeur ", tk.client.sat, " voix en cours ", tk._player.playing, " morceaux ", tk._clips.size(), " son ", tk._player.stream.resource_path if tk._player.stream else "aucun")
				await snap.call(s.name + "_reponse%d" % k)
			var t1 := Time.get_ticks_msec()
			while Time.get_ticks_msec() - t1 < 240000:
				await get_tree().process_frame
				tk._shown = tk._full.length(); tk._say_end = 0; tk._hold = minf(tk._hold, 0.0)
				if tk._step.is_empty() and tk._queue.is_empty():
					break
			tk._fil = []; tk._since = 99.0
			tk._ask_menu()
			await run.call(2)
			tk._wait = 999.0
			await snap.call(s.name + "_questions")
			tk._choices.get_child(0).emit_signal("pressed")
			var t2 := Time.get_ticks_msec()
			while Time.get_ticks_msec() - t2 < 240000:
				await get_tree().process_frame
				if tk._step.get("who", "") != "client":
					tk._shown = tk._full.length(); tk._say_end = 0; tk._hold = minf(tk._hold, 0.0)
				if tk._step.get("who", "") == "client":
					tk._shown = tk._full.length()
					break
			print("  réponse à la question « ", tk._full, " » indice ", tk._hint.text)
			await snap.call(s.name + "_indice")
			var d: int = a._dest
			car.place(Vector3(a.pts[d], a.pts[d + 2] + 0.3, a.pts[d + 1]), a.pts[d + 3])
			car.hold(1.5)
			await run.call(200)
			print("  dépôt : phase ", a._phase, " courses ", a._rides, " total ", a._total)
			await snap.call(s.name + "_paye")
	a._stop()

# ---------------------------------------------------------------- essai : --perf-breakdown
## Voiture arrêtée : chaque système masqué à tour de rôle (triangles, appels de dessin, images/s gagnés), puis les
## réglages de rendu coûteux (ombres, anticrénelage, post-traitement, brouillard, lueur).
func _perf_breakdown() -> void:
	var fps := func(sec: float) -> float:
		var n := 0; var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < sec * 1000.0:
			await get_tree().process_frame
			n += 1
		return n / sec
	var mesure := func() -> Array:
		for i in 4:
			await get_tree().process_frame
		var f: float = await fps.call(3.0)
		return [Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), f]
	if OS.get_environment("NIVEAU") != "":                 # niveau de qualité imposé (#124 : Économie mesurée à part)
		perf_auto = false
		get_node("HUD").appliquer_niveau(int(OS.get_environment("NIVEAU")))
	await get_tree().create_timer(20.0).timeout
	car.freeze = true
	print("[répartition] niveau %d, position %s" % [int(Engine.get_meta("niveau_perf", -1)), str(car.global_position.round())])
	var ref: Array = await mesure.call()
	print("[répartition] référence : %.0fk triangles, %d appels, %.1f img/s" % ref)
	# enfants regroupés par système (nom du script, sinon nom sans numéro) : une mesure par groupe (#124)
	var groupes := {}
	for c in get_children():
		if not (c is Node3D) or c == car or not c.visible:
			continue
		var cle := String(c.name)
		if c.get_script() != null:
			cle = c.get_script().resource_path.get_file().get_basename()
		else:
			cle = cle.split("@", false)[0] if cle.begins_with("@") else cle.split("_")[0]
		if not groupes.has(cle):
			groupes[cle] = []
		groupes[cle].append(c)
	for cle in groupes:
		for c in groupes[cle]:
			c.visible = false
		var m: Array = await mesure.call()
		for c in groupes[cle]:
			c.visible = true
		if ref[1] - m[1] != 0 or ref[0] - m[0] >= 1.0:
			print("[répartition] %-18s %6.0fk triangles  %5d appels  %+5.1f img/s  (%d nœuds)" % [cle, ref[0] - m[0], ref[1] - m[1], m[2] - ref[2], groupes[cle].size()])
	# réglage coupé puis remis à son état d'avant (en Économie, ombres et anticrénelage sont déjà coupés : sautés)
	var vp := get_viewport()
	var essais := [
		["ombres", _sun.shadow_enabled, func(): _sun.shadow_enabled = false, func(): _sun.shadow_enabled = true],
		["anticrénelage", vp.msaa_3d != Viewport.MSAA_DISABLED, func(): vp.msaa_3d = Viewport.MSAA_DISABLED, func(): pass],
		["post-traitement", post != null and post.visible, func(): post.visible = false, func(): post.visible = true],
		["brouillard", _env.fog_enabled, func(): _env.fog_enabled = false, func(): _env.fog_enabled = true],
		["lueur", _env.glow_enabled, func(): _env.glow_enabled = false, func(): _env.glow_enabled = true],
	]
	var msaa0 := vp.msaa_3d
	for e in essais:
		if not e[1]:
			print("[répartition] %s : déjà coupé" % e[0])
			continue
		e[2].call()
		var m: Array = await mesure.call()
		e[3].call()
		vp.msaa_3d = msaa0
		print("[répartition] sans %-14s %6.0fk triangles  %5d appels  %+5.1f img/s" % [e[0], ref[0] - m[0], ref[1] - m[1], m[2] - ref[2]])
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
	if not has_meta("niv_fixe") and OS.get_environment("NIVEAU") != "" and Chargement.fini:
		set_meta("niv_fixe", true)
		# niveau de qualité imposé pour tous les essais de conduite (#124 : physique à 60 pas en Économie)
		perf_auto = false
		get_node("HUD").appliquer_niveau(int(OS.get_environment("NIVEAU")))
		print("niveau imposé %d : physique %d pas/s, %d img/s au plus" % [int(OS.get_environment("NIVEAU")),
			Engine.physics_ticks_per_second, Engine.max_fps])
	if OS.get_cmdline_user_args().has("--course-ia-test"):
		if t == 300:
			_course_ia_test()                  # commandes de la voiture : son pilote (concurrent.gd)
		return
	if OS.get_cmdline_user_args().has("--circulation-test"):
		if t == 300:
			_circulation_test()
		return
	if OS.get_cmdline_user_args().has("--pietons-test"):
		if t == 300:
			_pietons_test()
		return
	if OS.get_cmdline_user_args().has("--ligne-bus-test"):
		if t == 300:
			_ligne_bus_test()
		return
	if OS.get_cmdline_user_args().has("--gendarmes-test"):
		if t == 300:
			_gendarmes_test()
		return
	if OS.get_cmdline_user_args().has("--livreur-test"):
		if t == 300:
			_livreur_test()
		return
	if OS.get_cmdline_user_args().has("--helico-test"):
		if t == 300:
			_helico_test()
		return
	if OS.get_cmdline_user_args().has("--bus-test"):
		if t == 300:
			_bus_test()
		return
	if OS.get_cmdline_user_args().has("--lourds-test"):
		if t == 300:
			_lourds_test()
		return
	if OS.get_cmdline_user_args().has("--balade-test"):
		if t == 300:
			_balade_test()
		return
	if OS.get_cmdline_user_args().has("--lumiere-perf"):
		if t == 300:
			_lumiere_perf()
		return
	if OS.get_cmdline_user_args().has("--arc-test"):
		if t == 300:
			_arc_test()
		return
	if OS.get_cmdline_user_args().has("--orage-test"):
		if t == 300:
			_orage_test()
		return
	if OS.get_cmdline_user_args().has("--nuit-test"):
		if t == 300:
			_nuit_test()
		return
	if OS.get_cmdline_user_args().has("--cycle-test"):
		if t == 300:
			_cycle_test()
		return
	if OS.get_cmdline_user_args().has("--meteo-test"):
		if t == 300:
			_meteo_test()
		return
	if OS.get_cmdline_user_args().has("--succes-test"):
		if t == 300:
			_succes_test()
		return
	if OS.get_cmdline_user_args().has("--accueil-test"):
		if t == 300:
			while not Chargement.fini:
				await get_tree().process_frame
			for i in 240:
				await get_tree().process_frame
			DirAccess.make_dir_recursive_absolute("user://shots")
			get_viewport().get_texture().get_image().save_png("user://shots/accueil.png")
			print("  [accueil] capture faite")
			get_tree().quit()
		return
	var dur := 3000 if OS.get_cmdline_user_args().has("--long") else 1200
	car.touch_throttle = 1.0 if t < dur else 0.0
	car.touch_brake = 1.0 if t >= dur else 0.0
	var straight: bool = Array(OS.get_cmdline_user_args()).any(func(a): return a.begins_with("--drive-from="))
	car.touch_steer = 0.3 if (t > 600 and t < 800 and not straight) else 0.0
	if OS.get_cmdline_user_args().has("--roues-test") and t % 60 == 0:
		# enfoncement des roues : bas de la roue (centre - rayon) par rapport au point de contact (cm)
		var pe := []
		for w in car.wheels:
			if w.is_in_contact():
				pe.append("%.1f" % ((w.global_position.y - w.wheel_radius - w.get_contact_point().y) * 100.0))
		print("roues t=%.1f : %s cm (+ : au-dessus du sol)" % [t / 120.0, ", ".join(pe)])
	if OS.get_cmdline_user_args().has("--brake-test"):
		# essai de freinage : pleins gaz jusqu'à 100 km/h, puis frein à fond ; distance et décélération moyenne
		car.touch_steer = 0.0
		if not has_meta("bt_p0"):
			car.touch_throttle = 1.0; car.touch_brake = 0.0
			if car.kmh() >= 100.0 or t > 2400:
				set_meta("bt_p0", car.global_position); set_meta("bt_t0", t); set_meta("bt_v0", car.kmh())
				print("freinage depuis %.0f km/h" % car.kmh())
		else:
			car.touch_throttle = 0.0; car.touch_brake = 1.0
			if car.kmh() < 1.0:
				var d: float = car.global_position.distance_to(get_meta("bt_p0"))
				var tt: float = (t - int(get_meta("bt_t0"))) / float(Engine.physics_ticks_per_second)
				print("arrêt : %.1f m en %.2f s (décélération moyenne %.1f m/s²)" % [d, tt, float(get_meta("bt_v0")) / 3.6 / tt])
				get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--voie-test"):
		# aide au maintien dans la voie : sans toucher au volant après une embardée, la voiture regagne sa voie
		car.aide_voie = not OS.get_cmdline_user_args().has("--voie-off")
		car.touch_brake = 0.0
		car.touch_throttle = 1.0 if car.kmh() < 70.0 else 0.3
		car.touch_steer = 0.35 if t > 600 and t < 640 else 0.0       # coup de volant à gauche à 5 s
		if t % 60 == 0:
			print("  [voie] t=%.1f %d km/h écart %.2f m actif=%s pos=%s" % [t / 120.0, car.kmh(), car.voie.ecart, car.voie.actif, car.global_position.snapped(Vector3(0.1, 0.1, 0.1))])
		if t > 2400:
			get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--reverse-test"):
		# marche arrière depuis le départ (FREIN), puis GAZ en reculant : doit freiner puis repartir en avant
		car.touch_steer = 0.0
		car.touch_brake = 1.0 if t < 840 else 0.0
		car.touch_throttle = 1.0 if t >= 840 else 0.0
		if t % 30 == 0:
			print("  t=%.2f v=%.1f km/h (avant=%.2f) arrière=%s pos=%s" % [t / 120.0, car.kmh(), car.forward_speed(), car.reversing, car.global_position.snapped(Vector3(0.1, 0.1, 0.1))])
		if t > 1500:
			get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--champ-bord"):
		# vue de la route le long d'un champ (type --champ-type=N) : voiture posée sur un tronçon droit du graphe routier
		# bordé par ce champ sur 60 m, ~45 km/h ; captures user://shots/bord_N.png
		car.touch_steer = 0.0; car.touch_brake = 0.0
		if _bord_t0 < 0 and t >= 300 and crops.pending == 0:
			_bord_t0 = t                                   # champ entièrement planté autour de la voiture
		var tb := t - _bord_t0 + 300 if _bord_t0 >= 0 else 0
		car.touch_throttle = (1.0 if car.kmh() < 45.0 else 0.0) if tb > 420 else 0.0
		if t == 240:
			var ty := 0
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--champ-type="):
					ty = int(a.trim_prefix("--champ-type="))
			perf_auto = false                                  # sous xvfb le réglage automatique tomberait en Économie
			get_node("HUD").appliquer_niveau(int(OS.get_environment("NIVEAU")) if OS.get_environment("NIVEAU") != "" else 2)
			var it = preload("res://scripts/itineraire.gd").new()
			var c0 := Vector2(car.global_position.x, car.global_position.z)
			var best := Vector4(0, 0, 0, INF)
			for k in it.arc_p0.size():
				for j in range(it.arc_p0[k], it.arc_p0[k] + it.arc_np[k] - 1):
					var a0 := Vector2(it.px[j], it.pz[j])
					var a1 := Vector2(it.px[j + 1], it.pz[j + 1])
					if a0.distance_to(a1) < 2.0 or a0.distance_to(c0) > 2500.0 or a0.distance_to(c0) > best.w:
						continue
					var d := (a1 - a0).normalized()
					if crops.field_at(a0 + Vector2(-d.y, d.x) * 8.0) != ty and crops.field_at(a0 - Vector2(-d.y, d.x) * 8.0) != ty:
						continue
					for cote in [1.0, -1.0]:
						var n: Vector2 = Vector2(-d.y, d.x) * cote
						var plein := true
						for kk in range(0, 45, 5):
							if crops.field_at(a0 + d * kk + n * 8.0) != ty or crops.field_at(a0 + d * kk + n * 30.0) != ty:
								plein = false; break
						if plein:
							best = Vector4(a0.x, a0.y, atan2(d.x, -d.y), a0.distance_to(c0))
							_bord_info = [a0, d, n]
			if best.w == INF:
				print("  [bord] aucun champ de type %d le long d'une route" % ty); get_tree().quit()
			else:
				car.place(Vector3(best.x, Relief.hauteur(Vector3(best.x, 0, best.y)) + 1.0, best.y), rad_to_deg(best.z))
				car.hold(1.0)
				print("  [bord] type %d à %s" % [ty, Vector2(best.x, best.y)])
		# vues fixes face au champ, à 3, 20 et 100 m de sa bordure (hauteur d'yeux), avant de rouler
		if _bord_info.size() == 3 and tb >= 300 and tb < 420:
			var k := (tb - 300) / 40
			var dist: float = [3.0, 20.0, 100.0][k]
			var a0: Vector2 = _bord_info[0]; var d: Vector2 = _bord_info[1]; var n: Vector2 = _bord_info[2]
			var bord := a0 + d * 20.0 + n * 5.0                   # bordure du champ (environ)
			var cp := bord - n * 3.0                              # depuis le bord de la route
			var cible := bord + n * dist + d * (dist * 0.35)       # plants à 3, 20 ou 100 m dans le champ
			cam_rig.set_process(false)
			var cm := get_viewport().get_camera_3d()
			var yc: float = Relief.hauteur(Vector3(cp.x, 0, cp.y))
			var yt: float = Relief.hauteur(Vector3(cible.x, 0, cible.y))
			cm.global_position = Vector3(cp.x, (0.0 if is_nan(yc) else yc) + 1.7, cp.y)
			cm.look_at(Vector3(cible.x, (0.0 if is_nan(yt) else yt) + 0.6, cible.y), Vector3.UP)
			if (tb - 300) % 40 == 39:
				DirAccess.make_dir_recursive_absolute("user://shots")
				get_viewport().get_texture().get_image().save_png("user://shots/bord_vue%d.png" % int(dist))
			if tb == 419:
				cam_rig.set_process(true)
		if tb in [420 + 240, 420 + 420, 420 + 600]:
			DirAccess.make_dir_recursive_absolute("user://shots")
			get_viewport().get_texture().get_image().save_png("user://shots/bord_%d.png" % ((tb - 420) / 60))
		if tb > 420 + 620 or t > 30000:
			get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--champ-test"):
		# tiges fauchées (#131) : voiture posée dans un champ (70 m de culture devant elle) (le plus proche du départ, type --champ-type=N),
		# pleins gaz dedans ; captures user://shots/champ_N.png (vue de jeu)
		car.touch_steer = 0.0; car.touch_brake = 0.0
		car.touch_throttle = 1.0 if t > 360 else 0.0
		if t == 240:
			if OS.get_environment("NIVEAU") != "":         # niveau de qualité imposé (#81 : il ne l'était pas ici)
				perf_auto = false
				get_node("HUD").appliquer_niveau(int(OS.get_environment("NIVEAU")))
				print("  [champ] niveau %d, portée des plants %.0f m" % [crops.level, crops.RANGE[crops.level]])
			var ty := -1
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--champ-type="):
					ty = int(a.trim_prefix("--champ-type="))
			var c0 := Vector2(car.global_position.x, car.global_position.z)
			var trouve := false
			for r in range(30, 4000, 20):
				for k in 48:
					var ang := TAU * k / 48.0
					var d := Vector2(cos(ang), sin(ang))
					var q := c0 + d * r
					var f: int = crops.field_at(q)
					if f < 0 or (ty >= 0 and f != ty):
						continue
					var plein := true
					for kk in range(0, 70, 7):
						if crops.field_at(q + d * kk) != f:
							plein = false; break
					if plein:
						var p0 := q
						car.place(Vector3(p0.x, Relief.hauteur(Vector3(p0.x, 0, p0.y)) + 1.0, p0.y), rad_to_deg(atan2(d.x, -d.y)))
						car.hold(1.0)
						print("  [champ] type %d à %s, départ %s" % [f, q, p0])
						trouve = true
						break
				if trouve:
					break
			if not trouve:
				print("  [champ] aucun champ trouvé"); get_tree().quit()
		if t > 360 and t % 60 == 0:
			var loin := 0.0
			for k in crops.cells:
				if crops.cells[k]:
					loin = maxf(loin, Vector2((k.x + 0.5) * crops.CELL - car.global_position.x, (k.y + 0.5) * crops.CELL - car.global_position.z).length())
			print("  [champ] t=%.1f %d km/h morceaux %d, %d img/s, cases à construire %d, plans de plantes %d, case de plants la plus loin %.0f m, primitives %d" % [(t - 360) / 120.0, car.kmh(), dust._fp.size(), Engine.get_frames_per_second(), crops.pending, crops.instances_visibles(), loin, Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
		if t in [360 + 150, 360 + 200, 360 + 300, 360 + 420, 360 + 560]:
			DirAccess.make_dir_recursive_absolute("user://shots")
			get_viewport().get_texture().get_image().save_png("user://shots/champ_%d.png" % ((t - 360) / 60))
		if t > 360 + 600:
			get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--bord-test"):
		# bords façon Motocross Madness : posée à 50 m de la limite, pleins gaz vers l'extérieur pendant 20 s
		# (aide au maintien dans la voie coupée : elle ramenait la voiture sur la route, le bord n'était jamais atteint)
		car.aide_voie = false
		car.touch_steer = 0.0; car.touch_brake = 0.0
		car.touch_throttle = 1.0 if t > 240 else 0.0
		var bd: Node = get_node("Bord")
		if t == 240:
			var cp := Vector2(car.global_position.x, car.global_position.z)
			var nr: Array = guardian._nearest(cp)
			var q: Vector2 = nr[0]
			var out := (q - cp).normalized()
			var p := q - out * 50.0
			car.place(Vector3(p.x, Relief.hauteur(Vector3(p.x, 0, p.y)) + 1.0, p.y), rad_to_deg(atan2(out.x, -out.y)))
			car.hold(1.5)
		if t > 240 and t % 30 == 0:
			var h: Array = bd.hors_carte(car.global_position)
			print("  t=%.2f hors carte %.1f m, %.0f km/h, haut %.1f m %s" % [(t - 240) / 120.0, h[0], car.kmh(), car.global_position.y, car._touching() if car.kmh() < 20.0 else ""])
		if OS.get_cmdline_user_args().has("--snap") and t in [240 + 480, 240 + 840, 240 + 1200]:
			DirAccess.make_dir_recursive_absolute("user://shots")
			get_viewport().get_texture().get_image().save_png("user://shots/bord_%d.png" % ((t - 240) / 120))
		if t > 240 + 120 * 20:
			get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--pied-test"):
		# #66 : descendre, marcher 5 s, tourner, capture, revenir près de la voiture et remonter ; journal [pied]
		car.touch_steer = 0.0; car.touch_throttle = 0.0; car.touch_brake = 1.0
		var pd = pied
		if t == 300:
			print("  [pied] avant de descendre : %.1f km/h, activité « %s »" % [car.kmh(), activities.mode])
			car.linear_velocity = Vector3.ZERO
			pd.sortir()
			Input.action_press("accelerer", 1.0)
		if t == 300 + 480:
			Input.action_press("frein_main")
		if t == 300 + 482:
			Input.action_release("frein_main")
		if t > 300 + 480 and t < 300 + 560 and t % 10 == 0 and pd.corps:
			print("  [pied] saut t=%.2f hauteur au-dessus du sol %.2f m" % [(t - 300) / 120.0, pd.corps.global_position.y - Relief.hauteur(pd.corps.global_position)])
		if t == 300 + 600:
			Input.action_release("accelerer"); Input.action_press("gauche", 1.0)
		if t == 300 + 720:
			Input.action_release("gauche")
		if t in [300 + 360, 300 + 840]:
			DirAccess.make_dir_recursive_absolute("user://shots")
			get_viewport().get_texture().get_image().save_png("user://shots/pied_%d.png" % t)
		if t > 300 and t % 60 == 0 and pd.corps:
			print("  [pied] t=%.1f pos %s, %.1f m de la voiture, au sol %s, voiture %.1f km/h" % [(t - 300) / 120.0, pd.corps.global_position, pd.corps.global_position.distance_to(car.global_position), pd.corps.is_on_floor(), car.kmh()])
		if t == 300 + 760:
			var tp: Vector3 = car.global_position + Vector3(150, 0, 0)
			tp.y = Relief.hauteur(tp) + 1.0
			_teleport(tp, 0.0)
		if t == 300 + 880:
			print("  [pied] après la téléportation : piéton à %.1f m de la voiture" % pd.corps.global_position.distance_to(car.global_position))
		if t == 300 + 900:
			print("  [pied] voiture figée : ", car.freeze, " position ", car.global_position, " sol ", Relief.hauteur(car.global_position))
		if t == 300 + 960:
			pd.basculer()
			print("  [pied] remonté : ", not pd.actif, " voiture contrôlée ", car.controle)
		if t > 300 + 1020:
			get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--eau-test"):
		# #86 : la voiture posée à 18 m d'un plan d'eau fonce dedans ; elle doit couler puis revenir sur la route
		var wa = water
		car.touch_steer = 0.0; car.touch_brake = 0.0
		car.touch_throttle = 0.0
		if t == 300:
			var best := []
			for k in wa.plans:
				for kc in wa.plans[k]:
					var T: PackedVector3Array = wa.plans[k][kc]
					if best.is_empty() or T.size() > best[0].size():
						best = [T]
			if best.is_empty():
				print("  [eau] aucun plan d'eau chargé"); get_tree().quit(); return
			var T: PackedVector3Array = best[0]
			var c := (T[0] + T[1] + T[2]) / 3.0
			var ok := true
			var s0 := c + Vector3(0, 1.6, 0)
			car.place(s0, 0.0)
			print("  [eau] plan d'eau en %s (niveau %.2f), voiture lâchée au-dessus" % [c, wa.niveau_plan(c)])
			if not ok:
				print("  [eau] pas de départ trouvé"); get_tree().quit()
		if t > 300 and t % 30 == 0:
			var h: float = wa.niveau_plan(car.global_position)
			print("  [eau] t=%.2f pos %s eau %s noyade %.2f figée %s contrôle %s" % [(t - 300) / 120.0, car.global_position, "-" if is_nan(h) else "%.2f" % h, wa._noyade, car.freeze, car.controle])
		if t == 300 + 240:
			DirAccess.make_dir_recursive_absolute("user://shots")
			get_viewport().get_texture().get_image().save_png("user://shots/eau_%d.png" % t)
		if t > 300 + 1000:
			get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--gachettes-test"):
		# #91 : gâchette d'une manette Android qui plafonne à 0,82 : gaz puis marche arrière doivent être à fond
		car.touch_steer = 0.0; car.touch_throttle = 0.0; car.touch_brake = 0.0
		var etapes := [[300, 5, 0.82], [300 + 600, 5, 0.0], [300 + 600, 4, 0.82], [300 + 1500, 4, 0.0]]
		for e in etapes:
			if t == e[0]:
				var j := InputEventJoypadMotion.new(); j.device = 0; j.axis = e[1]; j.axis_value = e[2]
				Input.parse_input_event(j)
		if t == 300 + 300:
			var j := InputEventJoypadMotion.new(); j.device = 0; j.axis = 5; j.axis_value = 0.5
			Input.parse_input_event(j)
		if t == 300 + 360:
			print("  [gâchettes] gaz à mi-course (0,5 brut) : pédale %.2f" % car.thr_in)
			var j := InputEventJoypadMotion.new(); j.device = 0; j.axis = 5; j.axis_value = 0.82
			Input.parse_input_event(j)
		if t > 300 and t % 60 == 0:
			print("  [gâchettes] t=%.1f gaz %.2f frein %.2f, %.0f km/h%s" % [(t - 300) / 120.0, car.thr_in, car.brk_in, car.forward_speed() * 3.6, " (marche arrière)" if car.reversing else ""])
		if t > 300 + 1560:
			get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--ressort-test"):
		# #88 : voiture posée sur le talus à 30 m hors de la carte, lancée vers l'extérieur à 60 km/h ; le ressort doit
		# la catapulter au-delà de 40 m (journal [bord] catapulte + son « ressort »)
		car.aide_voie = false
		car.touch_steer = 0.0; car.touch_brake = 0.0; car.touch_throttle = 0.0
		var bd: Node = get_node("Bord")
		if t == 240:
			# un côté du contour de la carte proche de la voiture : milieu, normale vers l'extérieur
			var Z: PackedVector2Array = bd._zone
			var cp := Vector2(car.global_position.x, car.global_position.z)
			var bi := 0; var bdist := INF
			for k in Z.size():
				var a: Vector2 = Z[k]; var b: Vector2 = Z[(k + 1) % Z.size()]
				if a.distance_to(b) > 40.0 and cp.distance_to((a + b) * 0.5) < bdist:
					bdist = cp.distance_to((a + b) * 0.5); bi = k
			var a: Vector2 = Z[bi]; var b: Vector2 = Z[(bi + 1) % Z.size()]
			var m := (a + b) * 0.5
			var out := Vector2(b.y - a.y, a.x - b.x).normalized()
			if Geometry2D.is_point_in_polygon(m + out * 2.0, Z):
				out = -out
			var p := m - out * 60.0                                  # 60 m à l'intérieur, pleins gaz vers l'extérieur
			print("  [ressort] départ à 60 m dans la carte, côté %d (%.0f m de long) : %s" % [bi, a.distance_to(b), bd.hors_carte(Vector3(p.x, 0, p.y))[0]])
			var y := Relief.hauteur(Vector3(p.x, 0, p.y))
			car.place(Vector3(p.x, y + 1.0, p.y), rad_to_deg(atan2(out.x, -out.y)))
			car.hold(0.3)
		car.touch_throttle = 1.0 if t > 240 + 40 else 0.0
		if t > 240 + 480 and t % 15 == 0 and t < 240 + 1500:
			var h: Array = bd.hors_carte(car.global_position)
			print("  [ressort] t=%.2f hors carte %.1f m, %.0f km/h, haut %.1f m" % [(t - 240) / 120.0, h[0], car.kmh(), car.global_position.y])
		if t > 240 + 1500:
			get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--regard-test"):
		# #82 : à pied, stick droit poussé vers le haut pendant 0,5 s : de combien la caméra lève-t-elle (> 0) ?
		car.touch_steer = 0.0; car.touch_throttle = 0.0; car.touch_brake = 1.0
		if t == 300:
			car.linear_velocity = Vector3.ZERO
			pied.sortir()
		if t == 360:
			set_meta("x0", pied.cam.rotation.x)
			var j := InputEventJoypadMotion.new(); j.device = 0; j.axis = JOY_AXIS_RIGHT_Y; j.axis_value = -1.0
			Input.parse_input_event(j)
		if t == 420:
			var j := InputEventJoypadMotion.new(); j.device = 0; j.axis = JOY_AXIS_RIGHT_Y; j.axis_value = 0.0
			Input.parse_input_event(j)
			print("  [regard] stick droit vers le haut : caméra %+.2f rad (positif = regarde vers le haut)" % (pied.cam.rotation.x - float(get_meta("x0"))))
		if t > 440:
			get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--camera-test"):
		# #92 : pleins gaz en ligne droite ; distance caméra-voiture et hauteur de la caméra au-dessus de la voiture
		car.aide_voie = false
		car.touch_steer = 0.0; car.touch_brake = 0.0; car.touch_throttle = 1.0 if t > 300 else 0.0
		if t > 300 and t % 60 == 0:
			var cp: Vector3 = cam_rig.cam.global_position
			var d := Vector2(cp.x - car.global_position.x, cp.z - car.global_position.z).length()
			print("  [caméra] %3d km/h : caméra à %.1f m derrière, %.1f m au-dessus, champ %.0f°" % [car.kmh(), d, cp.y - car.global_position.y, cam_rig.cam.fov])
		if t == 300 + 480:
			DirAccess.make_dir_recursive_absolute("user://shots")
			get_viewport().get_texture().get_image().save_png("user://shots/camera_vite.png")
		if t > 300 + 600:
			get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--carte-test"):
		# #93 : la carte ne doit téléporter qu'au second toucher. Cas 1 : doigt resté « posé » dans la carte (zoom à
		# deux doigts interrompu), puis toucher de la mini-carte -> le doigt levé ne doit pas téléporter.
		# Cas 2 : toucher normal dans la carte ouverte -> téléportation.
		var mp = get_node("HUD").map
		if t == 300:
			set_meta("p0", car.global_position)
			mp.open()
			var a := InputEventScreenTouch.new(); a.index = 1; a.pressed = true; a.position = Vector2(500, 400)
			mp._gui_input(a)                                   # doigt posé...
			mp.visible = false                                 # ...et carte fermée sans qu'il soit levé
		if t == 330:
			mp.open()                                          # toucher de la mini-carte (appui)
			var r := InputEventScreenTouch.new(); r.index = 0; r.pressed = false; r.position = Vector2(700, 500)
			mp._gui_input(r)                                   # le même doigt se lève, sur la carte
		if t == 420:
			print("  [carte] cas 1 (doigt levé du toucher qui ouvre) : voiture déplacée de %.0f m, carte %s" % [car.global_position.distance_to(get_meta("p0")), "ouverte" if mp.visible else "fermée"])
			set_meta("p0", car.global_position)
			if not mp.visible:
				mp.open()
		if t == 460:
			var a := InputEventScreenTouch.new(); a.index = 0; a.pressed = true; a.position = Vector2(150, 120)
			mp._gui_input(a)
			var r := InputEventScreenTouch.new(); r.index = 0; r.pressed = false; r.position = Vector2(150, 120)
			mp._gui_input(r)
		if t == 560:
			print("  [carte] cas 2 (second toucher, dans la carte) : voiture déplacée de %.0f m" % car.global_position.distance_to(get_meta("p0")))
			get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--carriere-test"):
		_carriere_test(t)
		return
	if OS.get_cmdline_user_args().has("--carriere2-test"):
		_carriere2_test(t)
		return
	if OS.get_cmdline_user_args().has("--rails-test"):
		_rails_test(t)
		return
	if OS.get_cmdline_user_args().has("--defi-test"):
		# v7.11 (n compte les pas de physique) : défi du jour : défis des 7 jours qui viennent, défi réussi d'après son compteur, onglet Succès
		if not Chargement.fini:
			return
		var n: int = get_meta("defi_t", 0) + 1
		set_meta("defi_t", n)
		var su = succes
		if n == 30:
			var j: int = su.jour()
			print("  [défi] jeu en pause : %s" % str(get_tree().paused))
			print("  [défi] aujourd'hui (jour %d) : %s ; semaine : %s" % [j, su.defi().texte, ", ".join(range(7).map(func(k): return su.defi(j + k).texte))])
			su.defi_jour = j
			su.defi_base = su.valeur(String(su.defi().stat))
			su.defi_fait = false
			set_meta("argent0", garage.argent)
			su.noter(String(su.defi().stat), float(su.defi().but))
			print("  [défi] compteur « %s » augmenté de %s : progrès %s" % [su.defi().stat, str(su.defi().but), str(su.defi_progres())])
		if n == 200:
			print("  [défi] réussi %s, argent %+.2f € (prime %d €)" % [str(su.defi_fait), garage.argent - float(get_meta("argent0")), int(su.defi().prime)])
			activities.open_menu(7)
			get_tree().paused = false
		if n == 400:
			DirAccess.make_dir_recursive_absolute("user://shots")
			get_viewport().get_texture().get_image().save_png("user://shots/defi.png")
			print("  [défi] capture defi.png")
			get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--metiers-menu-test"):
		# v7.10 : onglet « Métiers » (taxi, bus, livreur) : tout tient à l'écran ?
		if not Chargement.fini:
			return
		var n: int = get_meta("metiers_t", 0) + 1
		set_meta("metiers_t", n)
		if n == 60:
			activities.open_menu(2)
			get_tree().paused = false
		if n == 120:
			DirAccess.make_dir_recursive_absolute("user://shots")
			get_viewport().get_texture().get_image().save_png("user://shots/metiers_menu.png")
			var bs: Array = activities._menu.find_children("*", "Button", true, false).filter(func(b): return b.is_visible_in_tree())
			var bas := 0.0
			for b in bs:
				bas = maxf(bas, (b as Control).get_global_rect().end.y)
			print("  [métiers] %d boutons, le plus bas finit à %.0f px sur %.0f" % [bs.size(), bas, get_viewport().get_visible_rect().size.y])
			get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--epreuves-menu-test"):
		# #101 : menu des épreuves -> la dernière de la liste (la plus loin) ; la voiture doit être sur sa ligne de départ
		var act = activities
		if t == 300:
			set_meta("p0", car.global_position)
			# #112 / #119 : menu plein écran, onglet Épreuves ; la plus loin de la liste, puis « Lancer »
			act.open_menu(0)
			var c0: Vector2 = act._car2()
			var loin: int = -1
			for e in act.epreuves:
				if loin < 0 or c0.distance_to(Vector2(e.a[0], e.a[1])) > c0.distance_to(Vector2(act.epreuves[loin].a[0], act.epreuves[loin].a[1])):
					loin = int(e.id)
			act._menu.choix = loin
			act.niveau_menu = 2                   # #127 : niveau Extrême choisi dans le menu
			act._menu._aller(0)
			set_meta("loin", loin)
			get_tree().paused = false             # le menu met le jeu en pause : l'essai continue de compter les images
		if t == 300 + 120:
			DirAccess.make_dir_recursive_absolute("user://shots")
			get_viewport().get_texture().get_image().save_png("user://shots/epreuves_menu.png")
			var bs: Array = act._menu.find_children("*", "Button", true, false)
			var cible: Button = null
			for b in bs:
				if b.text.begins_with("▶ Lancer"):
					cible = b
			var md: int = act._menu.find_children("*", "Control", true, false).filter(func(x): return x.get_class() == "Control" and x.has_method("_draw") and x.get("med") != null).size()
			print("  [épreuves] menu plein écran : %d boutons, %d médailles dessinées, fiche « %s », tracé %d points" % [bs.size(), md, act.epreuves[get_meta("loin")].nom, act._menu.find_children("*", "Control", true, false).filter(func(x): return x.get_script() == preload("res://scripts/carte_trace.gd"))[0]._trace.size()])
			cible.pressed.emit()
		if t == 300 + 300:
			DirAccess.make_dir_recursive_absolute("user://shots")
			get_viewport().get_texture().get_image().save_png("user://shots/epreuve_hud.png")
		if t == 300 + 360:
			var e: Dictionary = act.epreuves[act._epreuve] if act._epreuve >= 0 else {}
			var d := Vector2(car.global_position.x, car.global_position.z).distance_to(Vector2(e.a[0], e.a[1])) if not e.is_empty() else -1.0
			print("  [épreuves] activité « %s », épreuve %s, voiture déplacée de %.0f m, à %.0f m du départ" % [act.mode, e.get("nom", "?"), car.global_position.distance_to(get_meta("p0")), d])
			print("  [épreuves] #128 : %d concurrent(s) %s" % [act.concurrents.size(), act.concurrents.map(func(c): return "%s (%s, %.0f s, à %.0f m)" % [c.nom, c.modele,
				c.temps_cible, c.voiture.global_position.distance_to(car.global_position)])])
			if not e.is_empty():
				print("  [épreuves] niveau %s : or en %s (Normal : %s), prime de l'or %s" % [act.NIVEAUX_EP[act.niveau_ep][0],
					act._fmt(act.temps_medaille(e, "or", act.niveau_ep)), act._fmt(float(e["or"])), act._euros(act.prime_medaille(e, "or", act.niveau_ep))])
		if t == 300 + 1100:
			# #107 : course lancée : numéros au-dessus des colonnes, tracé GPS vers le prochain point
			var nums := []
			for b in act._beacons:
				if is_instance_valid(b):
					for l in b.find_children("*", "Label3D", false, false):
						nums.append(l.text)
			print("  [épreuves] phase %s, numéros affichés %s, tracé GPS %d points" % [act._phase, nums, act.route_gps.size()])
			get_viewport().get_texture().get_image().save_png("user://shots/epreuve_course.png")
			get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--garage-voitures-test"):
		# #95 : garage, onglet Voitures : essai de la GT3 (pas achetée), retour au pick-up en sortant ; puis achat de la
		# Twingo et volant pris ; captures garage_voitures_*.png
		car.touch_steer = 0.0; car.touch_throttle = 0.0; car.touch_brake = 1.0
		var act = activities
		if t >= 300:
			car.linear_velocity = Vector3.ZERO; car.freeze = true      # l'essai de conduite ne doit pas la faire rouler
		if t == 300:
			garage.voitures = ["ranger"]               # profil d'essai : seul le pick-up est à nous
			garage.conduire("ranger")
			garage.argent = 3000.0
			act._garage()
		var g = act._menu
		if t == 360:
			g.famille = "Voitures"; g._remplir()
			garage.voir("gt3"); g._maj()
			print("  [garage] essai : voiture affichée %s, conduite %s, bouton « %s »" % [car.voiture, garage.voiture, g._action.text])
		if t == 480:
			DirAccess.make_dir_recursive_absolute("user://shots")
			get_viewport().get_texture().get_image().save_png("user://shots/garage_voitures_essai.png")
		if t == 540:
			g.fermer()
			print("  [garage] sortie sans acheter : voiture %s, argent %.0f €" % [car.voiture, garage.argent])
		if t == 600:
			act._garage()
		if t == 660:
			g.famille = "Voitures"; g._remplir()
			garage.voir("twingo"); g._maj()
			g._acheter()
			print("  [garage] Tango achetée : voiture %s, conduite %s, argent %.0f €, voitures %s" % [car.voiture, garage.voiture, garage.argent, garage.voitures])
		if t == 780:
			DirAccess.make_dir_recursive_absolute("user://shots")
			get_viewport().get_texture().get_image().save_png("user://shots/garage_voitures_achat.png")
		if t == 840:
			g.fermer()
			print("  [garage] sortie : voiture %s (gardée dans user://garage.cfg : %s)" % [car.voiture, preload("res://scripts/voitures.gd").actuelle()])
			garage.voitures = ["ranger"]; garage.conduire("ranger")
			get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--voitures-test"):
		# #95 : chaque voiture du garage (achetée d'office), sur la longue ligne droite : 2,5 s pleins gaz (vitesse,
		# 4 roues au sol, garde au sol), puis capture de côté ; on revient au pick-up à la fin
		var V := preload("res://scripts/voitures.gd")
		var ids: Array = V.ordre().filter(func(i): return ResourceLoader.exists(String(V.CATALOGUE[i].dossier) + "/body.glb"))
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--voitures="):           # quelques voitures seulement, bus de service compris (#148)
				ids = Array(a.get_slice("=", 1).split(","))
		var k := (t - 300) / 560
		var u := (t - 300) % 560
		car.aide_voie = false
		car.touch_steer = 0.0
		if t < 300:
			return
		if k >= ids.size():
			garage.conduire("ranger")
			get_tree().quit()
			return
		var id: String = ids[k]
		if u == 0:
			if not has_meta("depart"):
				set_meta("depart", car.global_transform)
			if not garage.a_voiture(id):
				garage.voitures.append(id)
			garage.conduire(id)
			car.freeze = false
			car.global_transform = get_meta("depart")
			car.linear_velocity = Vector3.ZERO; car.angular_velocity = Vector3.ZERO
			cam_rig.set_process(true)
			cam_rig.set_mode(0)
		car.touch_throttle = 1.0 if u > 60 and u < 360 else 0.0
		car.touch_brake = 0.0 if u < 360 else 1.0
		if u == 360:
			var sol := 0
			for w in car.wheels:
				sol += 1 if (w as VehicleWheel3D).is_in_contact() else 0
			var q := PhysicsRayQueryParameters3D.create(car.global_position + Vector3(0, 3, 0), car.global_position - Vector3(0, 3, 0))
			q.exclude = [car.get_rid()]
			var hit := get_world_3d().direct_space_state.intersect_ray(q)
			var garde: float = car.global_position.y - (float(hit.position.y) if not hit.is_empty() else 0.0)
			print("  [voitures] %-24s 2,5 s pleins gaz : %3.0f km/h · roues au sol %d/4 · origine à %.2f m du sol · masse %.0f kg · %d ch" % [
				V.CATALOGUE[id].nom, car.kmh(), sol, garde, car.mass, roundi(car.puissance / 735.5)])
		if u == 380:
			car.linear_velocity = Vector3.ZERO; car.freeze = true
			var xf := car.global_transform
			cam_rig.set_process(false)
			cam_rig.cam.global_position = xf.origin + xf.basis.x * 6.5 + xf.basis.z * 1.5 + Vector3(0, 1.4, 0)
			cam_rig.cam.look_at(xf.origin + Vector3(0, 0.7, 0), Vector3.UP)
		if u == 460:
			DirAccess.make_dir_recursive_absolute("user://shots")
			get_viewport().get_texture().get_image().save_png("user://shots/voiture_%s.png" % id)
		if u == 470:
			cam_rig.set_process(true)
			cam_rig.set_mode(1)                          # vue conducteur : habitacle en pixel art de la voiture (#95)
		if u == 540:
			print("  [voitures] %-24s vue conducteur : écran GPS %s, mini-carte %s" % [V.CATALOGUE[id].nom, cockpit.a_gps(), get_node("HUD").gps.visible])
			get_viewport().get_texture().get_image().save_png("user://shots/cockpit_%s.png" % id)
		return
	if OS.get_cmdline_user_args().has("--argent-test") and t == 250:
		_argent_test()
	if OS.get_cmdline_user_args().has("--voitures-revue"):
		# commandes tenues par _voitures_revue (le pleins gaz par défaut des essais envoyait la voiture dans une haie)
		car.touch_throttle = _revue_gaz; car.touch_brake = _revue_frein; car.touch_steer = 0.0
		if not has_meta("depart0"):
			set_meta("depart0", car.global_transform)
		if t == 300:
			_voitures_revue()
		return
	if OS.get_cmdline_user_args().has("--boum-camera-test"):
		car.touch_steer = 0.0; car.touch_throttle = 0.0; car.touch_brake = 1.0
		if t == 300:
			_boum_camera_test()
		return
	if OS.get_cmdline_user_args().has("--virage-test"):
		car.touch_steer = 0.0; car.touch_throttle = 0.0; car.touch_brake = 1.0
		if t == 300:
			_virage_test()
		return
	if OS.get_cmdline_user_args().has("--explosion-test"):
		car.touch_steer = 0.0; car.touch_throttle = 0.0; car.touch_brake = 1.0
		if t == 300:
			_explosion_test()
		return
	if OS.get_cmdline_user_args().has("--mur-test"):
		# #106 : mur posé en travers devant la voiture (angle --mur-angle=°, 0 = de face) ; pleins gaz contre le mur :
		# déplacement le long du mur après 4 s
		car.touch_steer = 0.0; car.touch_brake = 0.0
		car.touch_throttle = 1.0 if t >= 240 else 0.0
		if t == 240:
			var ang := 0.0
			var loin: float = car.gabarit.z * 0.5 + 2.5
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--mur-angle="):
					ang = deg_to_rad(float(a.get_slice("=", 1)))
				if a.begins_with("--mur-loin="):              # #121 : élan pour arriver vite contre le mur
					loin = float(a.get_slice("=", 1))
			var fw := car.global_transform.basis.z
			fw.y = 0.0
			fw = fw.normalized()
			var mur := StaticBody3D.new()
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(40.0, 4.0, 1.0)
			cs.shape = bs
			mur.add_child(cs)
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = bs.size
			mi.mesh = bm
			mur.add_child(mi)
			add_child(mur)
			mur.global_position = car.global_position + fw * loin + Vector3.UP * 1.0
			mur.look_at(mur.global_position + fw.rotated(Vector3.UP, ang), Vector3.UP)
			set_meta("mur_p0", car.global_position)
			set_meta("mur_fw", fw)
			print("  [mur] mur à %.1f m devant, angle %.0f°" % [loin, rad_to_deg(ang)])
		if t > 240 and car.blown and not has_meta("boum_t"):
			set_meta("boum_t", t)
			print("  [mur] EXPLOSION à t=%.2f s (vitesse juste avant : %.0f km/h)" % [(t - 240) / 120.0, get_meta("v_avant", 0.0)])
		if t > 240 and not car.blown:
			set_meta("v_avant", car.kmh())
		if has_meta("boum_t") and t - int(get_meta("boum_t")) in [25, 70, 160]:
			DirAccess.make_dir_recursive_absolute("user://shots")
			get_viewport().get_texture().get_image().save_png("user://shots/boum_%d.png" % (t - int(get_meta("boum_t"))))
		if t > 240 and t % 60 == 0:
			var d: Vector3 = car.global_position - get_meta("mur_p0")
			var fw0: Vector3 = get_meta("mur_fw")
			print("  [mur] t=%.1f s : avancé %.1f m, latéral %.1f m, %.0f km/h, contact=%s explosée=%s cap %.0f° roues motrices %.0f N" % [(t - 240) / 120.0, d.dot(fw0), d.dot(fw0.cross(Vector3.UP)), car.kmh(), car.mur_contact, car.blown, rad_to_deg(car.global_transform.basis.z.signed_angle_to(fw0, Vector3.UP)), car.engine_force])
		if t == 240 + 120 * 7:
			DirAccess.make_dir_recursive_absolute("user://shots")
			get_viewport().get_texture().get_image().save_png("user://shots/mur.png")
			get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--flash-test"):
		# #111 / #104 : flash info autorisé selon le volume de la musique et la présence d'un client du taxi
		if t == 300:
			var AU := preload("res://scripts/audio.gd")
			var r = radio
			var l := []
			for cas in [[1.0, false], [0.0, false], [1.0, true]]:
				AU.volumes["musique"] = cas[0]
				r.taxi = cas[1]
				l.append("musique %.0f %%, client %s -> flash %s" % [cas[0] * 100.0, "oui" if cas[1] else "non", "lu" if r.flash_permis() else "PAS lu"])
			AU.volumes["musique"] = 1.0
			r.taxi = false
			print("  [flash] " + " ; ".join(l))
			get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--sons-test"):
		# #84 : choc contre du dur à 12,5 m/s (seuil du verre : 11) et bois cassé, appelés directement ; avec --sons-log
		car.touch_steer = 0.0; car.touch_throttle = 0.0; car.touch_brake = 1.0
		if t == 300:
			sound.impact("dur", 12.5, car.global_position)
		if t == 420:
			sound.impact("bois", 6.0, car.global_position, true)
		if t == 540:
			get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--crans-test"):
		# #103 : bouton caméra pressé 6 fois (ordre des vues), puis captures et distance caméra-voiture de chaque cran
		car.touch_steer = 0.0; car.touch_throttle = 0.0; car.touch_brake = 1.0
		if t == 300:
			car.linear_velocity = Vector3.ZERO; car.freeze = true
			var l := []
			for i in 6:
				cam_rig.cycle()
				l.append("mode %d cran %d" % [cam_rig.mode, cam_rig.cran])
			print("  [crans] bouton caméra ×6 : " + ", ".join(l))
			cam_rig.set_mode(0); cam_rig.cran = 0
		for k in 3:
			if t == 300 + 120 * (k + 1):
				DirAccess.make_dir_recursive_absolute("user://shots")
				get_viewport().get_texture().get_image().save_png("user://shots/cran_%d.png" % k)
				var d: Vector3 = cam_rig.cam.global_position - car.global_position
				print("  [crans] cran %d : caméra à %.1f m derrière, %.1f m au-dessus" % [k, Vector2(d.x, d.z).length(), d.y])
				cam_rig.cran = k + 1 if k < 2 else 0
		if t == 300 + 480:
			get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--armes-test"):
		# #99 sans réseau : caisses posées devant, ramassage en roulant ; puis boule, onde, tornade tirées sur une cible
		# d'essai (id -1) ; puis coups subis (vitesse avant/après) et bouclier (coup sans effet)
		var A = net.armes
		car.aide_voie = false
		car.touch_steer = 0.0
		var fwd := car.global_transform.basis.z
		if t == 300:
			var mc := MeshInstance3D.new()
			var bm := BoxMesh.new(); bm.size = Vector3(1.8, 1.4, 4.2); mc.mesh = bm
			var m := StandardMaterial3D.new(); m.albedo_color = Color(0.2, 0.4, 1.0); mc.material_override = m
			add_child(mc)
			mc.global_position = car.global_position + fwd * 200.0
			A.set_meta("cibles", {-1: mc})
			set_meta("cible", mc)
			set_meta("p0", car.global_position)
			A.demarrer([car.global_position + fwd * 10.0, car.global_position + fwd * 60.0])
			print("  [armes] %d caisses posées (rangées de 3 à 35 m et 60 m devant)" % A._caisses.size())
		if t >= 300 and t < 300 + 600:
			car.touch_throttle = 0.5; car.touch_brake = 0.0
			if A.arme != "" and not has_meta("ramasse"):
				set_meta("ramasse", true)
				print("  [armes] caisse ramassée à %.0f m du départ, %.0f km/h : arme « %s », bouton ARME visible %s" % [car.global_position.distance_to(get_meta("p0")), car.kmh(), A.arme, A._bouton.visible])
		if t == 300 + 90:
			DirAccess.make_dir_recursive_absolute("user://shots")
			get_viewport().get_texture().get_image().save_png("user://shots/armes_caisses.png")
		var cible: Node3D = get_meta("cible") if has_meta("cible") else null
		var tirs := {600: ["boule", 30.0], 720: ["onde", 10.0], 840: ["tornade", 50.0]}
		for dt0 in tirs:
			if t == 300 + dt0:
				car.touch_throttle = 0.0; car.touch_brake = 1.0
				car.linear_velocity = Vector3.ZERO; car.freeze = true
				cible.global_position = car.global_position + fwd * tirs[dt0][1]
				A.arme = tirs[dt0][0]
				A.tirer()
			if t == 300 + dt0 + 25 and tirs[dt0][0] == "boule":
				DirAccess.make_dir_recursive_absolute("user://shots")
				get_viewport().get_texture().get_image().save_png("user://shots/armes_boule.png")
			if t == 300 + dt0 + 100:
				print("  [armes] %s tirée sur une cible à %.0f m : touchée %s" % [tirs[dt0][0], tirs[dt0][1], A.has_meta("touche_" + tirs[dt0][0])])
		if t == 300 + 960:
			car.freeze = false
			A._effet_t = 0.0
			set_meta("v1", car.linear_velocity)
			A.subir("boule", fwd)
			print("  [armes] boule subie : vitesse %s -> %s, rotation %.1f rad/s" % [get_meta("v1").snapped(Vector3.ONE * 0.1), car.linear_velocity.snapped(Vector3.ONE * 0.1), car.angular_velocity.length()])
			set_meta("y1", car.global_position.y)
		if t == 300 + 1020:
			print("  [armes] 0,5 s après : %.1f m plus haut" % (car.global_position.y - get_meta("y1")))
		if t == 300 + 1080:
			car.linear_velocity = Vector3.ZERO; car.angular_velocity = Vector3.ZERO
			A.arme = "bouclier"; A.tirer()
			var v0 := car.linear_velocity
			A.subir("boule", fwd)
			print("  [armes] bouclier %.1f s : boule subie, vitesse %s -> %s (inchangée attendue)" % [A.bouclier_t, v0.snapped(Vector3.ONE * 0.1), car.linear_velocity.snapped(Vector3.ONE * 0.1)])
		if t == 300 + 1110:
			DirAccess.make_dir_recursive_absolute("user://shots")
			get_viewport().get_texture().get_image().save_png("user://shots/armes_bouclier.png")
		if t == 300 + 1140:
			A.arreter()
			print("  [armes] fin de course : %d caisses restantes, bouton visible %s" % [A._caisses.size(), A._bouton.visible])
			get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--nitro-test"):
		# #98 : nitro 2 monté ; 4 s pleins gaz, puis 4 s pleins gaz + nitro : vitesse gagnée, jauge, recharge
		car.aide_voie = false
		car.touch_steer = 0.0; car.touch_brake = 0.0; car.touch_throttle = 1.0 if t > 300 else 0.0
		if t == 300:
			car.nitro_niveau = 2; car.nitro_jauge = 1.0
		if t == 300 + 480:
			set_meta("v0", car.kmh())
			Input.action_press("nitro")
		if t == 300 + 600:
			DirAccess.make_dir_recursive_absolute("user://shots")
			get_viewport().get_texture().get_image().save_png("user://shots/nitro.png")
		if t == 300 + 960:
			Input.action_release("nitro")
			print("  [nitro] 4 s de nitro : %.0f -> %.0f km/h, jauge %.2f (vide en 5 s)" % [get_meta("v0"), car.kmh(), car.nitro_jauge])
			set_meta("j0", car.nitro_jauge)
		if t % 120 == 0 and t > 300 and t < 300 + 960:
			print("  [nitro] t=%.0f s %3.0f km/h jauge %.2f actif %s" % [(t - 300) / 120.0, car.kmh(), car.nitro_jauge, car.nitro_actif])
		if t == 300 + 1560:
			print("  [nitro] recharge en 5 s de route : %.2f -> %.2f" % [get_meta("j0"), car.nitro_jauge])
			get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--vinyles-test"):
		# #94 : trois des nouveaux vinyles vus de côté (couleur rouge)
		car.touch_steer = 0.0; car.touch_throttle = 0.0; car.touch_brake = 1.0
		var vs := [13, 19, 23]
		for k in vs.size():
			if t == 300 + k * 120:
				car.linear_velocity = Vector3.ZERO; car.freeze = true
				garage.monte["vinyle"] = vs[k]; garage.monte["couleur"] = 3
				tuning.appliquer()
				var xf := car.global_transform
				cam_rig.set_process(false)
				cam_rig.cam.global_position = xf.origin + xf.basis.x * 6.5 + Vector3(0, 1.3, 0)
				cam_rig.cam.look_at(xf.origin + Vector3(0, 0.9, 0), Vector3.UP)
			if t == 300 + k * 120 + 60:
				DirAccess.make_dir_recursive_absolute("user://shots")
				get_viewport().get_texture().get_image().save_png("user://shots/vinyle_%d.png" % vs[k])
		if t > 300 + 400:
			get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--garage-test"):
		# #94 : semi-slicks + autobloquant + allègement 2 + barres course + pare-buffle + galerie ; en roulant, l'adhérence
		# réelle des roues doit rester celle des pneus achetés (avant v6.58 : réécrite à 2,6 à chaque pas)
		car.aide_voie = false
		car.touch_steer = 0.0; car.touch_brake = 0.0; car.touch_throttle = 1.0 if t > 300 and t < 300 + 360 else 0.0
		if t == 300:
			for r in ["pneus", "differentiel", "allegement", "anti_roulis", "pare_buffle", "galerie", "phares"]:
				garage.monte[r] = {"pneus": 2, "differentiel": 1, "allegement": 2, "anti_roulis": 2, "pare_buffle": 1, "galerie": 1, "phares": 1}[r]
			tuning.appliquer()
		if t == 300 + 240:
			print("  [garage] en roulant à %.0f km/h : adhérence des roues %.2f (pneus semi-slicks 3,30 × autobloquant 1,08 = 3,56), masse %.0f kg, anti-roulis ×%.2f" % [car.kmh(), car.wheels[0].wheel_friction_slip, car.mass, car.anti_roulis])
		if t == 300 + 480:
			car.linear_velocity = Vector3.ZERO; car.freeze = true
			var xf := car.global_transform
			cam_rig.set_process(false)
			cam_rig.cam.global_position = xf.origin + xf.basis.z * 6.0 + xf.basis.x * 3.5 + Vector3(0, 1.8, 0)
			cam_rig.cam.look_at(xf.origin + Vector3(0, 1.0, 0), Vector3.UP)
		if t == 300 + 540:
			DirAccess.make_dir_recursive_absolute("user://shots")
			get_viewport().get_texture().get_image().save_png("user://shots/garage_options.png")
			get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--pedales-test"):
		# #64 et #65 : gâchette d'accélérateur restée à 18 % + frein (marche arrière attendue), puis frein à main lancé,
		# puis frein de parking (voiture immobile malgré les gaz à 40 %) ; journal [pédales]
		car.touch_steer = 0.0; car.touch_throttle = 0.0; car.touch_brake = 0.0
		if t == 300:
			Input.action_press("accelerer", 0.18); Input.action_press("freiner", 1.0)
		if t == 300 + 480:
			Input.action_release("freiner"); Input.action_press("accelerer", 1.0)
		if t == 300 + 960:
			Input.action_press("frein_main", 1.0)
		if t == 300 + 1200:
			Input.action_release("frein_main"); Input.action_release("accelerer")
			car.frein_parking = true
			Input.action_press("accelerer", 0.4)
		if t > 300 and t % 60 == 0:
			print("  [pédales] t=%.1f s vitesse %.1f km/h (avant %+.1f m/s) marche arrière %s frein à main %.1f parking %s" % [(t - 300) / 120.0, car.kmh(), car.forward_speed(), car.reversing, car.frein_main_in, car.frein_parking])
		if t > 300 + 1560:
			Input.action_release("accelerer")
			get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--pieton-test"):
		# clients MakeHuman (#55) : cinq piétons devant la voiture, deux immobiles, trois qui marchent ; captures
		car.touch_throttle = 0.0; car.touch_brake = 1.0
		if t == 300:
			var tr := car.global_transform
			for i in 5:
				var p: Node3D = load("res://assets/clients/mh_%d.glb" % (i * 2 + (1 if i == 4 else 0))).instantiate()
				p.set_script(preload("res://scripts/pieton.gd"))
				p.name = "Pieton%d" % i
				add_child(p)
				p.global_position = tr * Vector3(-3.0 + i * 1.5, 0.0, 6.0)
				p.global_position.y = Relief.hauteur(p.global_position)
				p.rotation.y = car.rotation.y + PI + (0.0 if i < 2 else PI / 2)
				p.vitesse = 0.0 if i < 2 else 1.4
				p.ivre = i == 4
		if t in [420, 470, 520]:
			cam_rig.set_process(false)
			var cm := get_viewport().get_camera_3d()
			cm.global_position = car.global_transform * Vector3(0.0, 1.6, 1.5)
			cm.look_at(car.global_transform * Vector3(0.0, 1.0, 6.0), Vector3.UP)
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute("user://shots")
			get_viewport().get_texture().get_image().save_png("user://shots/pieton_%d.png" % t)
		if t > 540:
			get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--taxi-test"):
		# courses de taxi enchaînées (#53) : la voiture est posée sur chaque cible ; journal [taxi]
		if t == 300:
			if OS.get_cmdline_user_args().has("--taxi-nuit"):
				set_time(3)                  # tarif de nuit (v6.93)
			activities._taxi_start()
		if t > 300 and t % 120 == 0:
			var ph: String = activities._phase
			var cible := Vector2.INF
			if ph == "attente":
				cible = activities._cl_pos
			elif ph == "course":
				cible = activities._rp(activities._dest if activities._arret < 0 else activities._arret)
			print("  [taxi] t=%d phase %s sorte %s arrêt %d (%.0f s) rappel %s courses %d compteur %.2f%s" % [t, ph, activities._sorte, activities._arret, activities._arret_t, not activities._rappel.is_empty(), activities._rides, activities._compteur.montant if activities._compteur else 0.0,
				" TARIF 2 (nuit)" if activities._compteur and activities._compteur.nuit else ""])
			if cible != Vector2.INF and _car2_dist(cible) > 12.0:
				var i: int = activities._nearest(cible)
				car.place(Vector3(cible.x, activities.pts[i + 2] + 1.0, cible.y), activities.pts[i + 3])
				car.hold(0.4)
		if t > 300 + 120 * 70 or activities._rides >= 4:
			if pietons:                      # v6.90 : clients déposés devenus passants (encore en scène ou non)
				var vus := 0
				for c in pietons.passants:
					if c.n.global_position.distance_to(car.global_position) < 40.0:
						vus += 1
				print("  [taxi] clients devenus passants : %d sur %d courses ; passants à moins de 40 m : %d" % [pietons.adoptes,
					activities._rides, vus])
			get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--garage-test"):
		# garage (#43) : écran ouvert, plusieurs préparations essayées tour à tour ; captures user://shots/garage_N.png
		car.touch_throttle = 0.0; car.touch_brake = 0.0; car.touch_steer = 0.0
		var essais := [{},
			{"couleur": 3, "finition": 1, "vinyle": 1, "neons": 1, "taxi": 1, "barre_led": 1, "prise_air": 1, "bas_caisse": 1, "aileron": 1, "echappement": 1, "jantes": 1, "suspension": 1},
			{"couleur": 5, "finition": 2, "vinyle": 3, "suspension": 2, "barre_led": 1, "aileron": 2, "jantes": 2},
			{"couleur": 8, "finition": 3, "vinyle": 5, "neons": 2, "aileron": 3, "jantes": 3, "echappement": 3},
			{"couleur": 11, "vinyle": 6, "suspension": 2, "aileron": 4, "jantes": 4},
			{"couleur": 1, "vinyle": 4, "vitres": 2, "neons": 5, "bas_caisse": 1, "aileron": 5, "jantes": 5},
			{"couleur": 9, "vinyle": 2, "finition": 1, "neons": 3, "echappement": 2}]
		if OS.get_cmdline_user_args().has("--jantes"):
			essais = [{"jantes": 0}, {"jantes": 1}, {"jantes": 2}, {"jantes": 3}, {"jantes": 4}, {"jantes": 5}, {"jantes": 2}]
		if t == 300:
			garage.argent = 5000.0
			activities._garage()
		var k := (t - 360) / 240
		if t >= 360 and (t - 360) % 240 == 0 and k < essais.size():
			garage.apercu = essais[k].duplicate()
			tuning.appliquer()
		if t >= 360 and (t - 360) % 240 == 200 and k < essais.size():
			DirAccess.make_dir_recursive_absolute("user://shots")
			if OS.get_cmdline_user_args().has("--jantes"):
				var cm: Camera3D = get_viewport().get_camera_3d()
				for cote in [1.0, -1.0]:
					cam_rig.set_process(false)
					var roue: Vector3 = car.global_transform * Vector3(0.89 * cote, 0.3, 1.68)
					cm.global_position = car.global_transform * Vector3(2.6 * cote, 0.7, 2.6)
					cm.look_at(roue, Vector3.UP)
					await RenderingServer.frame_post_draw
					get_viewport().get_texture().get_image().save_png("user://shots/jantes_%d_%s.png" % [k, "g" if cote > 0 else "d"])
				cam_rig.set_process(true)
			get_viewport().get_texture().get_image().save_png("user://shots/garage_%d.png" % k)
			print("  [garage] capture %d, %d km/h, argent %s" % [k, car.kmh(), garage.argent])
		if k >= essais.size():
			get_tree().quit()
		return
	if ciel and ciel.force != "":
		# aéronefs (#46, --ciel-test=<type>) : caméra posée près de la voiture, tournée vers l'appareil ;
		# captures user://shots/ciel_<type>_N.png toutes les 4 s, fin après 40 s
		car.touch_throttle = 0.0; car.touch_brake = 1.0
		if ciel._avion and not ciel.has_meta("rapproche"):
			# rapproché : l'appareil part tout près de son point de passage (l'essai sans écran est lent)
			ciel.set_meta("rapproche", true)
			if ciel._type != "planeur":
				ciel._p = ciel._proche - ciel._v.normalized() * (2500.0 if ciel._type == "ligne" else 150.0)
		if t > 360 and t % 240 == 0 and ciel._avion:
			var cam: Camera3D = get_node_or_null("CamCiel")
			if cam == null:
				cam = Camera3D.new(); cam.name = "CamCiel"; cam.far = 160000.0; add_child(cam)
			var o := car.global_position + Vector3(0, 45, 0)
			var a: Vector3 = ciel._avion.global_position
			var d := o.distance_to(a)
			cam.fov = clamp(rad_to_deg(2.0 * atan(40.0 / d)) * (6.0 if ciel._type == "ligne" else 1.0), 2.0, 70.0)
			cam.global_transform = Transform3D(Basis.looking_at(a - o, Vector3.UP), o)
			cam.current = true
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute("user://shots")
			get_viewport().get_texture().get_image().save_png("user://shots/ciel_%s_%d.png" % [ciel._type, (t - 360) / 240])
			print("  [ciel] capture à %.0f m, champ %.1f°" % [d, cam.fov])
		if t > 360 + 240 * 4:
			get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--void-test"):
		# essai du gardien : voiture posée sur le relief juste avant le bord de la carte, en roulant vers le vide
		# (la soucoupe doit attendre qu'elle tombe, puis la ramener sur une route)
		car.touch_throttle = 1.0 if t > 500 else 0.0
		if t == 240:
			var cp := Vector2(car.global_position.x, car.global_position.z)
			var nr: Array = guardian._nearest(cp)
			var q: Vector2 = nr[0]
			var out := (q - cp).normalized()
			var p := q
			var h := 0.0
			for k in 400:
				var hh: float = Relief.hauteur(Vector3(p.x, 0, p.y))
				if is_nan(hh):
					break
				h = hh
				p += out * 4.0
			p -= out * 40.0
			h = Relief.hauteur(Vector3(p.x, 0, p.y))
			if OS.get_cmdline_user_args().has("--void-drop"):
				# lâchée directement au-dessus du vide, loin de tout relief : la soucoupe doit surgir et la rattraper
				p = q
				for k in 600:
					if is_nan(Relief.hauteur(Vector3(p.x, 0, p.y))):
						break
					p += out * 50.0
				p += out * 300.0
				h = car.global_position.y + 10.0
			car.place(Vector3(p.x, h + 1.0, p.y), rad_to_deg(atan2(out.x, -out.y)))
			car.hold(2.0)                               # collisions du relief générées autour de la caméra
			if cam_rig and cam_rig.has_method("snap"):
				cam_rig.snap()
			print("posée avant le vide en ", car.global_position, " distance à la limite ", guardian._nearest(p)[1])
		if t > 240 + 120 * 40:
			get_tree().quit()
		if OS.get_cmdline_user_args().has("--snap") and t > 240 and t % 120 == 0:
			DirAccess.make_dir_recursive_absolute("user://shots")
			get_viewport().get_texture().get_image().save_png("user://shots/ovni_%02d.png" % ((t - 240) / 120))
		if t > 240 and t % 30 == 0:
			print("  t=%.2f état=%s pos=%s portée=%s" % [t / 120.0, guardian.state, car.global_position.snapped(Vector3.ONE), car.carried])
		return
	if OS.get_cmdline_user_args().has("--flip-test"):
		car.touch_throttle = 0.0; car.touch_brake = 0.0; car.touch_steer = 0.0
		if t == 240:
			var tr := car.global_transform
			car.global_transform = Transform3D(tr.basis.rotated(tr.basis.z, PI), tr.origin + tr.basis.x * 14.0 + Vector3(0, 1.5, 0))
			print("retournée en ", car.global_position)
		if t % 120 == 0 and t > 240:
			print("  t=%ds pos=%s haut=%.2f route=%s" % [t / 120, car.global_position.snapped(Vector3(0.1, 0.1, 0.1)), car.global_transform.basis.y.y, get_node("HUD").names.road_at(car.global_position)])
		return
	if OS.get_cmdline_user_args().has("--hard-steer"):
		car.touch_steer = (1.0 if t < 1000 else -1.0) if t > 840 and t < 1150 else 0.0
		if t % 30 == 0 and t > 800:
			print("  braquage t=%.2f v=%d km/h haut=%.2f roues=%d" % [t / 120.0, car.kmh(), car.global_transform.basis.y.y, car.wheels.filter(func(w): return w.is_in_contact()).size()])
	if not car.global_position.is_finite() or car.linear_velocity.length() > 80.0:
		print("ANOMALIE t=%d pos=%s v=%s" % [t, car.global_position, car.linear_velocity])
	if OS.get_cmdline_user_args().has("--snap") and t % 60 == 0:
		DirAccess.make_dir_recursive_absolute("user://shots")
		get_viewport().get_texture().get_image().save_png("user://shots/snap_%03d.png" % (t / 60))
		print("  snap %d gardien=%s éveil=%.2f portée=%s pos=%s" % [t / 60, guardian.state, guardian._charge, car.carried, car.global_position.snapped(Vector3.ONE)])
	if t % 120 == 0:
		print("t=%.0fs pos=%s v=%.0f km/h avant=%.1f roues au sol=%d" % [t / 120.0, car.global_position.snapped(Vector3(0.1, 0.1, 0.1)), car.kmh(), car.forward_speed(), car.wheels.filter(func(w): return w.is_in_contact()).size()])
		if sound:
			print("  son : ", sound.debug(), (" ; radio %s « %s » à %.0f s" % [radio.lcd_text(), radio.title, radio._player.get_playback_position()]) if radio and radio.station >= 0 else "")
	if t > dur + 600:
		get_tree().quit()

# ---------------------------------------------------------------- essai mémoire (pipeline) : --mem-test
# La voiture saute de point en point le long des routes (tout le réseau) ; mémoire et objets affichés.
var _mem_pts := PackedFloat32Array()
func _car2_dist(p: Vector2) -> float:
	return Vector2(car.global_position.x, car.global_position.z).distance_to(p)

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
		print("t=%ds mémoire %.0f Mo vidéo %.0f Mo (textures %.0f, tampons %.0f) objets %d nœuds %d ressources %d tuiles routes %d bâtiments %d" % [t / 120,
			Performance.get_monitor(Performance.MEMORY_STATIC) / 1e6, Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1e6,
			Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1e6, Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1e6,
			Performance.get_monitor(Performance.OBJECT_COUNT),
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
			roads.loaded.size(), buildings.loaded.size()])
	if t > 120 * 240:
		get_tree().quit()

# ---------------------------------------------------------------- essai : --vram (mémoire vidéo par famille, #122)
## Voiture posée au centre de Rochetoirin (ou --vram-at=x,y,z) ; 30 s plus tard : textures chargées groupées par
## dossier et les plus grosses, puis tampons (maillages et MultiMesh) de chaque système, lus dans le serveur de rendu.
func _vram_detail() -> void:
	while not Chargement.fini:
		await get_tree().process_frame
	var at := Vector3(92.8, 450.6, 419.5)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--vram-at="):
			var v := a.trim_prefix("--vram-at=").split(",")
			at = Vector3(float(v[0]), float(v[1]), float(v[2]))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--vram-voiture="):
			car.construire(a.trim_prefix("--vram-voiture="))      # voiture du garage conduite pendant la mesure
	car.place(at, 108.5)
	car.hold(1.0)
	var t0 := Time.get_ticks_msec()                        # temps réel : le rendu logiciel des essais tient ~1 image/s
	while Time.get_ticks_msec() - t0 < 40000:
		await get_tree().process_frame
	print("[vram] totale %.0f Mo : textures %.0f Mo, tampons %.0f Mo" % [Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1e6,
		Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1e6, Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1e6])
	var par := {}                  # système (script ou nom) -> [maillages vus, octets maillages, textures vues]
	var toutes := {}
	for c in get_children():
		if not (c is Node3D):
			continue
		var sc: String = c.get_script().resource_path.get_file() if c.get_script() else String(c.name).rstrip("0123456789_@")
		if not par.has(sc):
			par[sc] = [{}, 0, {}]
		var e: Array = par[sc]
		for n in c.find_children("*", "GeometryInstance3D", true, false) + ([c] if c is GeometryInstance3D else []):
			var mats := []
			if n.material_override:
				mats.append(n.material_override)
			var m: Mesh = n.mesh if n is MeshInstance3D else (n.multimesh.mesh if n is MultiMeshInstance3D and n.multimesh else null)
			if m:
				for k in m.get_surface_count():
					if m.surface_get_material(k):
						mats.append(m.surface_get_material(k))
			if n is MeshInstance3D:
				for k in n.get_surface_override_material_count():
					if n.get_surface_override_material(k):
						mats.append(n.get_surface_override_material(k))
			for mat in mats:
				for t in _textures_de(mat):
					e[2][t] = true
					toutes[t] = true
			if n is MultiMeshInstance3D and n.multimesh:
				var mm: MultiMesh = n.multimesh
				e[1] += mm.instance_count * (12 + (4 if mm.use_colors else 0) + (4 if mm.use_custom_data else 0)) * 4
			if m == null or e[0].has(m):
				continue
			e[0][m] = true
			for k in m.get_surface_count():
				var d: Dictionary = RenderingServer.mesh_get_surface(m.get_rid(), k)
				for cle in ["vertex_data", "attribute_data", "skin_data", "index_data"]:
					if d.has(cle):
						e[1] += (d[cle] as PackedByteArray).size()
				for l in d.get("lods", []):
					if l is Dictionary and l.has("index_data"):
						e[1] += (l.index_data as PackedByteArray).size()
	var res := []
	for sc in par:
		var e: Array = par[sc]
		var to := 0
		var noms := []
		for t in e[2]:
			var b := _octets_texture(t)
			to += b
			noms.append([b, String(t.resource_path).trim_prefix("res://")])
		noms.sort_custom(func(x, y): return x[0] > y[0])
		res.append([e[1] + to, sc, e[0].size(), e[1], to, noms.slice(0, 5)])
	res.sort_custom(func(x, y): return x[0] > y[0])
	for r in res:
		if r[0] < 100000:
			continue
		print("[vram] %-22s %6.1f Mo : maillages %5.1f Mo (%d), textures %5.1f Mo : %s" % [r[1], r[0] / 1e6, r[3] / 1e6, r[2], r[4] / 1e6,
			", ".join(r[5].map(func(x): return "%s %.1f" % [x[1].get_file(), x[0] / 1e6]))])
	var tt := 0
	for t in toutes:
		tt += _octets_texture(t)
	print("[vram] textures des objets 3D (sans doublons) : %.0f Mo" % (tt / 1e6))
	if terrain and terrain.get("data"):
		var nreg: int = terrain.data.get_region_locations().size()
		var rs: int = int(terrain.get("region_size"))
		print("[vram] relief Terrain3D : %d régions de %d² ; cartes hauteur + contrôle + couleur ≈ %.0f Mo" % [nreg, rs, nreg * rs * rs * (4 + 4 + 4 * 1.33) / 1e6])
	get_tree().quit()

## Textures d'un matériau (StandardMaterial3D ou ShaderMaterial).
func _textures_de(mat: Material) -> Array:
	var out := []
	if mat is ShaderMaterial and mat.shader:
		for u in mat.shader.get_shader_uniform_list():
			var v = mat.get_shader_parameter(u.name)
			if v is Texture:
				out.append(v)
	elif mat is BaseMaterial3D:
		for t in [mat.albedo_texture, mat.normal_texture, mat.emission_texture, mat.roughness_texture, mat.metallic_texture,
				mat.ao_texture, mat.orm_texture if mat is ORMMaterial3D else null]:
			if t:
				out.append(t)
	if mat and mat.next_pass:
		out.append_array(_textures_de(mat.next_pass))
	return out

## Mémoire vidéo estimée d'une texture : compressée (VRAM) 1 octet par pixel, sinon 4 ; + 1/3 avec les mipmaps.
func _octets_texture(t: Texture) -> int:
	var w := 0; var h := 0; var couches := 1
	if t is Texture2D:
		w = t.get_width(); h = t.get_height()
	elif t is TextureLayered:
		w = t.get_width(); h = t.get_height(); couches = t.get_layers()
	elif t is Texture3D:
		w = t.get_width(); h = t.get_height(); couches = t.get_depth()
	var bpp := 4.0
	var mip := false
	var imp := String(t.resource_path).get_slice("::", 0) + ".import"
	if t.resource_path != "" and FileAccess.file_exists(imp):
		var txt := FileAccess.get_file_as_string(imp)
		if txt.contains("compress/mode=2") or txt.contains("compress/mode=3") or txt.contains("compress/mode=4"):
			bpp = 1.0
		mip = txt.contains("mipmaps/generate=true")
	return int(w * h * couches * bpp * (1.33 if mip else 1.0))

## #127 : primes réelles du jeu (activities._epreuve_fin) pour un sprint et une longue épreuve aux trois niveaux :
## première médaille d'or, puis la même refaite ; course de taxi de 4 km en 6 min. Garage sauvegardé puis remis.
func _argent_test() -> void:
	var act = get_tree().get_nodes_in_group("activites")[0]
	var med0: Dictionary = garage.medailles.duplicate()
	var rec0: Dictionary = garage.records.duplicate()
	garage.medailles = {}
	garage.records = {}
	for id in [14, 27]:
		var e: Dictionary = act.epreuves[id]
		for niv in act.NIVEAUX_EP.size():
			act._epreuve = id
			act.niveau_ep = niv
			var t_or: float = act.temps_medaille(e, "or", niv)
			var r1: Array = act._epreuve_fin(t_or - 1.0)
			var r2: Array = act._epreuve_fin(t_or - 2.0)
			var r3: Array = act._epreuve_fin(act.temps_medaille(e, "bronze", niv) + 5.0)
			print("  [argent] %-40s %-9s or en %s : %s %d €, refaite %s %d €, trop lent : %d €" % [str(e.nom).left(40),
				act.NIVEAUX_EP[niv][0], act._fmt(t_or), r1[0], r1[1], r2[0], r2[1], r3[1]])
	act._epreuve = -1
	act.niveau_ep = 0
	garage.medailles = med0
	garage.records = rec0
	garage.sauver()
	var TM := preload("res://scripts/taximetre.gd")
	print("  [argent] taxi 4 km en 6 min (dont 1 min d'attente) : %.2f € au compteur (avant : %.2f €)" % [
		TM.PRISE + TM.PAR_KM * 4.0 + TM.PAR_MIN * 1.0, 3.5 + 1.6 * 4.0 + 0.6 * 1.0])

## #126 : revue des voitures du garage. Chacune posée au même endroit, roulée 1,5 s (suspensions en place), puis figée
## et photographiée sous 7 angles à midi (3/4 avant et arrière, profil, face, arrière, dessus, ras du sol), de nuit
## (phares) et en roulant derrière elle (caméra du jeu). Captures user://shots/revue_<id>_<angle>.png ;
## --revue-ids=a,b pour n'en faire que certaines. Lancer avec --drive-test --voitures-revue.
const REVUE_ANGLES := [   # nom, position de la caméra dans le repère de la voiture (x à gauche, z vers l'avant), visée
	["av", Vector3(4.6, 1.5, 5.2), 0.6], ["ar", Vector3(-4.6, 1.5, -5.2), 0.6], ["profil", Vector3(-7.0, 0.9, 0.0), 0.6],
	["face", Vector3(0.0, 0.9, 6.5), 0.6], ["dos", Vector3(0.0, 0.9, -6.5), 0.6], ["dessus", Vector3(0.0, 8.5, 0.6), 0.0],
	["ras", Vector3(3.2, 0.25, 3.6), 0.45]]
var _revue_gaz := 0.0
var _revue_frein := 1.0
func _voitures_revue() -> void:
	var V := preload("res://scripts/voitures.gd")
	var ids: Array = V.ordre().filter(func(i): return ResourceLoader.exists(String(V.CATALOGUE[i].dossier) + "/body.glb"))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--revue-ids="):
			ids = Array(a.get_slice("=", 1).split(","))
	perf_auto = false
	car.aide_voie = false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lod-seuil="):      # #130 : simplification des modèles forcée (seuil en pixels, Économie : 8)
			get_viewport().mesh_lod_threshold = float(a.get_slice("=", 1))
			print("  [revue] seuil des niveaux de détail : %.1f px" % get_viewport().mesh_lod_threshold)
	var depart: Transform3D = get_meta("depart0")
	DirAccess.make_dir_recursive_absolute("user://shots")
	for id in ids:
		if not garage.a_voiture(id):
			garage.voitures.append(id)
		garage.conduire(id)
		set_time(0)
		car.freeze = false
		car.global_transform = depart
		car.linear_velocity = Vector3.ZERO; car.angular_velocity = Vector3.ZERO
		cam_rig.set_process(true)
		cam_rig.set_mode(0)
		if car.blown:
			car.respawn_at(depart.origin, 0.0)
			car.global_transform = depart
		_revue_frein = 0.0; _revue_gaz = 0.35
		for i in 60:
			await get_tree().physics_frame
		_revue_gaz = 0.0
		for i in 30:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("user://shots/revue_%s_route.png" % id)
		_revue_frein = 1.0
		for i in 240:
			await get_tree().physics_frame
			if car.kmh() < 0.5:
				break
		# hauteur de l'origine de la caisse (= sol du modèle) au-dessus du sol, et centre des roues dans le repère de la
		# caisse comparé au rayon du modèle : une caisse posée juste a 0 cm et des roues à leur rayon (#126)
		var q := PhysicsRayQueryParameters3D.create(car.global_position + Vector3(0, 3, 0), car.global_position - Vector3(0, 3, 0))
		q.exclude = [car.get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		var garde: float = car.global_position.y - (float(hit.position.y) if not hit.is_empty() else 0.0)
		var cy := 0.0
		for w in car.wheels:
			cy += (car.global_transform.affine_inverse() * (w as Node3D).global_position).y / 4.0
		print("  [revue] %s : caisse à %.1f cm du sol, centre des roues à %.1f cm dans la caisse (rayon du modèle %.1f cm)" % [
			id, garde * 100.0, cy * 100.0, float(car._meta.get("radius", 0.0)) * 100.0])
		car.linear_velocity = Vector3.ZERO; car.angular_velocity = Vector3.ZERO
		car.freeze = true
		cam_rig.set_process(false)
		var xf := car.global_transform
		for ang in REVUE_ANGLES:
			var c: Camera3D = cam_rig.cam
			c.fov = 50.0
			c.global_position = xf * (ang[1] as Vector3)
			c.look_at(xf.origin + Vector3(0, ang[2], 0), Vector3.UP if ang[0] != "dessus" else xf.basis.z)
			for i in 3:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png("user://shots/revue_%s_%s.png" % [id, ang[0]])
		set_time(3)
		var c2: Camera3D = cam_rig.cam
		c2.global_position = xf * Vector3(3.8, 1.3, 6.5)
		c2.look_at(xf.origin + Vector3(0, 0.6, 0), Vector3.UP)
		for i in 5:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("user://shots/revue_%s_nuit.png" % id)
		print("  [revue] %s : %d captures" % [id, REVUE_ANGLES.size() + 2])
	set_time(0)
	garage.conduire("ranger")
	get_tree().quit()

## #129 : explosion en vue conducteur : la caméra doit passer en poursuite (plan large sur le champignon) le temps de
## l'explosion, sans volant 3D en l'air, puis revenir en vue conducteur. Captures user://shots/boum_cam_<n>.png.
func _boum_camera_test() -> void:
	DirAccess.make_dir_recursive_absolute("user://shots")
	cam_rig.set_mode(1)
	for i in 30:
		await get_tree().process_frame
	var vol: Node3D = car.get("_wheel_node")
	print("  [boum-cam] avant : vue %d, style %s, volant visible %s" % [cam_rig.mode, car.style_explosion, vol.visible if vol else "?"])
	get_viewport().get_texture().get_image().save_png("user://shots/boum_cam_0.png")
	car.exploser()
	var n := 1
	var t0 := Time.get_ticks_msec()
	for i in 400:
		await get_tree().process_frame
		if i in [3, 12, 24, 36]:
			print("  [boum-cam] pendant (image %d) : vue %d, voiture explosée %s, volant visible %s, caméra à %.1f m de la voiture, %.1f m au-dessus" % [
				i, cam_rig.mode, car.blown, vol.visible if vol else "?", cam_rig.cam.global_position.distance_to(car.global_position),
				cam_rig.cam.global_position.y - car.global_position.y])
			get_viewport().get_texture().get_image().save_png("user://shots/boum_cam_%d.png" % n)
			n += 1
		if not car.blown and i > 5:
			for j in 20:
				await get_tree().process_frame
			print("  [boum-cam] après : vue %d (attendu 1), volant visible %s (vue conducteur : caché), %.1f s" % [
				cam_rig.mode, vol.visible if vol else "?", (Time.get_ticks_msec() - t0) / 1000.0])
			get_viewport().get_texture().get_image().save_png("user://shots/boum_cam_%d.png" % n)
			break
	get_tree().quit()

## #128 : tenue de route en virage des voitures du garage pilotées par le jeu : sur un terrain plat (stade :
## --drive-from=185,447,495,90), vitesse tenue (--vitesses=20,35 km/h), braquage --braquage=1 ; virage établi :
## vitesse de lacet et accélération latérale (réglage de concurrent.a_lat). --fixed-fps 8.
func _virage_test() -> void:
	while not Chargement.fini:
		await get_tree().process_frame
	Engine.max_physics_steps_per_frame = 16
	var vits := [20.0, 35.0]
	var br := 1.0
	var mods := ["ranger", "p106", "clio", "r5", "p206", "p306", "gt3"]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--vitesses="):
			vits = Array(a.get_slice("=", 1).split(",")).map(func(x): return float(x))
		elif a.begins_with("--braquage="):
			br = float(a.get_slice("=", 1))
		elif a.begins_with("--modeles="):
			mods = Array(a.get_slice("=", 1).split(","))
	var p0 := car.global_position
	car.global_position = p0 + Vector3(0, 0, 60)          # la voiture du joueur à l'écart
	car.hold(9999.0)
	for m in mods:
		for vk: float in vits:
			var v := VehicleBody3D.new()
			v.set_script(preload("res://scripts/car.gd"))
			v.ia = true
			v.voiture = m
			add_child(v)
			v.place(p0 + Vector3(0, 0.3, 0), 90.0)
			v.hold(0.5)
			var mes := []
			for i in int(7.0 * Engine.physics_ticks_per_second):
				await get_tree().physics_frame
				var tt := float(i) / Engine.physics_ticks_per_second
				var vf: float = v.forward_speed()
				var e := vk / 3.6 - vf
				v.touch_throttle = clampf(e * 0.5 + 0.15, 0.0, 1.0) if e > 0.0 else 0.0
				v.touch_brake = clampf(-e * 0.3, 0.0, 1.0) if e < -0.5 else 0.0
				v.touch_steer = br if tt > 3.0 else 0.0
				if tt > 5.5:
					mes.append([vf, v.angular_velocity.y])
			var vm := 0.0
			var wm := 0.0
			for q in mes:
				vm += q[0] / mes.size(); wm += q[1] / mes.size()
			print("  [virage] %-7s visé %3d km/h : %4.1f km/h, lacet %.2f rad/s, rayon %5.1f m, latéral %.1f m/s², braquage %.2f rad" % [m, int(vk),
				vm * 3.6, wm, vm / maxf(absf(wm), 0.01), absf(vm * wm), v.steering])
			v.queue_free()
			await get_tree().physics_frame
	get_tree().quit()

## #128 : course contre 3 concurrents sur une épreuve (--ep=N, défaut 14 : départ au village ; --niv=0-2). La voiture
## du joueur est pilotée comme un concurrent (même pilote, temps visé --joueur=<s>, défaut : celui du concurrent du
## milieu, pour rouler avec eux) ; relevé toutes les 10 s (progression, vitesse, physique ou figé, place), explosion
## forcée d'un concurrent à 25 s (--sans-boum : non) pour voir son retour 4 s après, 30 m derrière ; arrivées et temps
## comparés aux temps visés. Captures user://shots/course_ia_<n>.png. Temps de jeu indépendant de la lenteur du rendu :
## lancer avec --fixed-fps 8 (15 pas de physique par image) : -- --drive-test --course-ia-test.
func _course_ia_test() -> void:
	var act = activities
	var id := 14
	var niv := 0
	var tj := -1.0
	var duree := 600.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--duree="):
			duree = float(a.get_slice("=", 1))
		elif a.begins_with("--ep="):
			id = int(a.get_slice("=", 1))
		elif a.begins_with("--niv="):
			niv = int(a.get_slice("=", 1))
		elif a.begins_with("--joueur="):
			tj = float(a.get_slice("=", 1))
		elif a.begins_with("--densite=") and circulation:
			circulation.set_densite(int(a.get_slice("=", 1)))
	DirAccess.make_dir_recursive_absolute("user://shots")
	var shot := func(n: String):
		get_viewport().get_texture().get_image().save_png("user://shots/course_ia_%s.png" % n)
	while not Chargement.fini:
		await get_tree().process_frame
	Engine.max_physics_steps_per_frame = 16
	act._epreuve_depart(id, niv, true)
	var e: Dictionary = act.epreuves[id]
	var cs: Array = act.concurrents.duplicate()
	var pj = preload("res://scripts/concurrent.gd").new()
	pj.main = self
	pj.voiture = car
	pj.nom = "joueur"
	pj.temps_cible = tj if tj > 0.0 else float(cs[1].temps_cible)
	var g0: Vector3 = act._grille[0]                  # tracé depuis la place de départ (comme les concurrents)
	var pts2 := [Vector2(g0.x, g0.z)]
	for i in range(1, act._route.size()):
		pts2.append(act._rp(act._route[i]))
	pj.points = pts2
	var aide: bool = car.aide_voie
	car.aide_voie = false                             # l'aide au maintien dans la voie contrarierait le pilote
	car.reversing = false
	pj.autres = cs[0].autres
	add_child(pj)
	print("  [course-ia] épreuve %d « %s », %s ; temps visés : %s ; joueur %.0f s" % [id, e.nom, act.NIVEAUX_EP[niv][0],
		", ".join(cs.map(func(c): return "%s (%s) %.0f s" % [c.nom, c.modele, c.temps_cible])), pj.temps_cible])
	for i in 24:
		await get_tree().physics_frame
	shot.call("0_grille")
	while act._phase == "depart":
		await get_tree().physics_frame
	pj.parti = true
	var fin := {}
	var bascules := {}
	var etat := {}
	var boum := not OS.get_cmdline_user_args().has("--sans-boum")
	var t_releve := 0.0
	var vu_boum := -1.0
	var boum_c = null
	var n_shot := 1
	var traces := {}                     # trajectoires (essai) : nom -> [[x, z, km/h, s, figé, volant, gaz, frein]…]
	var chemins := {}                    # tracés suivis : nom -> [[x, z]…] (relevés tant que les concurrents existent)
	var t_trace := 0.0
	var ev_par := {}                     # voitures de la circulation contournées, par concurrent
	while act._t < duree:
		await get_tree().physics_frame
		var tt: float = act._t
		if tt >= t_trace:
			t_trace += 0.25
			for c in cs + [pj]:
				if is_instance_valid(c) and c.pret and not chemins.has(c.nom):
					var lc := []
					for q: Vector2 in c._chemin:
						lc.append([snappedf(q.x, 0.1), snappedf(q.y, 0.1)])
					chemins[c.nom] = lc
				if is_instance_valid(c):
					var vv: VehicleBody3D = c.voiture
					if not traces.has(c.nom):
						traces[c.nom] = []
					traces[c.nom].append([snappedf(vv.global_position.x, 0.1), snappedf(vv.global_position.z, 0.1), int(vv.kmh()), int(c.s),
						c.fige, snappedf(vv.touch_steer, 0.01), snappedf(vv.touch_throttle, 0.01), snappedf(vv.touch_brake, 0.01)])
		for c in cs:
			if not is_instance_valid(c):
				continue
			ev_par[c.nom] = c.evites.size()
			if c.fige != etat.get(c.nom, false):
				bascules[c.nom] = bascules.get(c.nom, 0) + 1
				etat[c.nom] = c.fige
			if c.fini and not fin.has(c.nom):
				fin[c.nom] = c.t_arrivee
				print("  [course-ia] %s arrivé en %.1f s (visé %.0f s, %d explosion(s))" % [c.nom, c.t_arrivee, c.temps_cible, c.detruit])
		if boum and tt > 25.0 and vu_boum < 0.0:
			var c = cs[0]                                # le plus proche de la voiture du joueur (physique de préférence)
			for o in cs:
				if o.voiture.global_position.distance_to(car.global_position) < c.voiture.global_position.distance_to(car.global_position):
					c = o
			boum_c = c
			print("  [course-ia] explosion forcée de %s à %.0f m du départ (%s)" % [c.nom, c.s, "figé" if c.fige else "physique"])
			c.exploser()
			vu_boum = tt
		if vu_boum > 0.0 and tt > vu_boum + 0.6 and n_shot == 1:
			shot.call("1_boum")
			n_shot = 2
		if vu_boum > 0.0 and tt > vu_boum + 4.5 and n_shot == 2:
			var c = boum_c
			print("  [course-ia] retour de %s : %s, à %.0f m du départ, %.0f m de la voiture du joueur" % [c.nom,
				"revenu" if not c.voiture.blown else "TOUJOURS DÉTRUIT", c.s, c.voiture.global_position.distance_to(car.global_position)])
			shot.call("2_retour")
			n_shot = 3
		if tt >= t_releve:
			t_releve += 10.0
			var l := []
			for c in cs:
				l.append("%s %.0f/%.0f m %d km/h%s%s" % [c.nom, c.s, c.longueur, int(c.voiture.kmh()), " figé" if c.fige else "",
					" BOUM" if c.voiture.blown else ""])
			print("  [course-ia] t=%.0f s : joueur %.0f m %d km/h, %s / 4 ; %s" % [tt, pj.s, int(car.kmh()), act._rang(act._place()), " ; ".join(l)])
			if circulation:                  # circulation autour des pilotes lents (blocages)
				for c in cs + [pj]:
					var vv: VehicleBody3D = c.voiture
					if vv.kmh() > 5.0:
						continue
					var proches := []
					for tc in circulation.voitures:
						var d: float = (tc.pos as Vector3).distance_to(vv.global_position)
						if d < 25.0:
							proches.append("%.0f m %d km/h %s" % [d, int(float(tc.v) * 3.6), tc.leader])
					print("  [course-ia]   %s lent à (%.0f, %.0f) : %d voiture(s) de la circulation à 25 m : %s ; épaves %d" % [c.nom,
						vv.global_position.x, vv.global_position.z, proches.size(), ", ".join(proches), circulation.epaves.size()])
			if int(tt) == 10:
				shot.call("3_peloton")
		if act.mode != "course":
			print("  [course-ia] joueur arrivé en %.1f s (visé %.0f s)" % [tt, pj.temps_cible])
			shot.call("4_arrivee")
			break
	# les concurrents encore en course : jusqu'à leur retrait (8 s après l'arrivée du joueur)
	for i in 8 * Engine.physics_ticks_per_second:
		await get_tree().physics_frame
		for c in cs:
			if is_instance_valid(c) and c.fini and not fin.has(c.nom):
				fin[c.nom] = c.t_arrivee
				print("  [course-ia] %s arrivé en %.1f s (visé %.0f s, %d explosion(s))" % [c.nom, c.t_arrivee, c.temps_cible, c.detruit])
	var fj := FileAccess.open("user://course_ia.json", FileAccess.WRITE)
	fj.store_string(JSON.stringify({"traces": traces, "chemins": chemins}))
	fj.close()
	print("  [course-ia] bilan : %d/3 concurrents arrivés, passages physique <-> figé : %s, détruits payés : %d" % [fin.size(), bascules, act._detruits])
	if circulation:
		var ev := 0
		for k in ev_par:
			ev += int(ev_par[k])
		print("  [course-ia] circulation : %d voitures, %d contournées par les concurrents, %d devenues épaves" % [circulation.voitures.size(), ev, circulation.accidents])
	pj.queue_free()
	car.aide_voie = aide
	get_tree().quit()

## #129 : explosions candidates (et le champignon actuel pour comparer) photographiées aux mêmes instants, temps de
## l'effet réglé à la main (indépendant de la vitesse du rendu). Voiture cachée comme au moment de l'explosion, caméra
## fixe reculée selon la taille de l'effet. Captures user://shots/boum_<style>_<n>.png ; --explosion-styles=a,b,…
## pour n'en faire que certains. Lancer avec --drive-test --explosion-test.
const BOUM_INSTANTS := [0.1, 0.4, 0.9, 1.5, 2.1, 2.6]
const BOUM_VUES := {"avant": [14.0, 2.5], "film": [16.0, 3.0], "mini": [17.0, 6.5], "atomique": [32.0, 12.0, 14.0]}  # recul, visée, hauteur
var _boum_sens := 1.0            # caméra devant (1) ou derrière (-1) la voiture : --explosion-derriere
func _explosion_test() -> void:
	var styles := ["avant", "film", "mini", "atomique"]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--explosion-styles="):
			styles = a.get_slice("=", 1).split(",")
		if a == "--explosion-derriere":
			_boum_sens = -1.0
	car.linear_velocity = Vector3.ZERO
	car.freeze = true
	var xf := car.global_transform
	car.blow_up()
	cam_rig.set_process(false)
	get_node("HUD").visible = false
	DirAccess.make_dir_recursive_absolute("user://shots")
	var fw := xf.basis.z
	fw.y = 0.0
	fw = fw.normalized()
	var cote := fw.cross(Vector3.UP)
	for st in styles:
		var vue: Array = BOUM_VUES.get(st, [20.0, 5.0])
		var c: Camera3D = cam_rig.cam
		c.fov = 62.0
		c.global_position = xf.origin + fw * vue[0] * _boum_sens + cote * vue[0] * 0.35 + Vector3(0, vue[2] if vue.size() > 2 else 2.0 + vue[0] * 0.12, 0)
		c.look_at(xf.origin + Vector3(0, vue[1], 0), Vector3.UP)
		var fx: Node3D
		if st == "avant":
			fx = preload("res://scripts/champignon.gd").new()
			fx.set_process(false)
		else:
			fx = preload("res://scripts/explosion.gd").new()
			fx.style = st
			fx.auto = false
			fx.graine = 129
		fx.position = xf.origin - Vector3(0, 0.3, 0)
		add_child(fx)
		for n in BOUM_INSTANTS.size():
			var tt: float = BOUM_INSTANTS[n]
			if st == "avant":
				fx._t = tt
				if tt < fx.DUREE:
					fx._maj()
				fx.visible = tt < fx.DUREE
			else:
				fx.regler(tt)
				fx.visible = tt < fx.duree
			for i in 3:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png("user://shots/boum_%s_%d.png" % [st, n])
		print("  [explosion] %s : %d captures" % [st, BOUM_INSTANTS.size()])
		fx.queue_free()
		await get_tree().process_frame
	get_tree().quit()

# ---------------------------------------------------------------- essai : --carriere-test (#120)
## Les 4 missions du chapitre 1, étape par étape (chaque étape attend l'état du jeu, 900 pas au plus) : onglet Carrière,
## duel (bulle du rival, fantôme qui part au « Partez ! », arrivée simulée 5 s avant lui), livraison (voiture posée à
## chaque arrêt), taxi du maire (prise en charge, dépôt), premier chrono (arrivée simulée), message de fin à 100.
## Temps du jeu ×4 (à 1 image/s, les minuteries du jeu avancent sinon de 0,07 s par image). Captures
## user://shots/carriere_*.png, journal « [carrière] ». Lancer avec --drive-test --carriere-test.
func _carriere_test(t: int) -> void:
	var ca = carriere
	var act = activities
	car.touch_throttle = 0.0
	car.touch_steer = 0.0
	car.touch_brake = 1.0
	if t < 240:
		return
	var etape: int = get_meta("c_etape", 0)
	var t0: int = get_meta("c_t0", 240)
	var dt := t - t0
	var suite := func():
		set_meta("c_etape", etape + 1)
		set_meta("c_t0", t)
	var shot := func(n: String):
		DirAccess.make_dir_recursive_absolute("user://shots")
		get_viewport().get_texture().get_image().save_png("user://shots/carriere_%s.png" % n)
	var poser := func(i: int, vers: Vector2):
		var s: Array = act._start_at(i, vers)
		get_node("HUD").teleport.emit(s[0], s[1])
	if dt > 900:
		print("  [carrière] ÉCHEC : étape %d bloquée (phase carrière « %s », activité %s/%s)" % [etape, ca._phase, act.mode, act._phase])
		get_tree().quit()
		return
	match etape:
		0:
			Engine.time_scale = 4.0
			ca.effacer()
			act.open_menu(6)
			get_tree().paused = false
			suite.call()
		1:
			if dt >= 60:
				shot.call("menu")
				var bs: Array = act._menu.find_children("*", "Button", true, false) if act._menu else []
				print("  [carrière] onglet : %d boutons, réputation %d" % [bs.size(), int(ca.reps[0])])
				ca.lancer("duel", true)
				suite.call()
		2:
			if ca._bulle != null:
				shot.call("defi")
				var b: Array = ca._bulle.find_children("*", "Button", true, false)
				print("  [carrière] bulle du rival : %d réponses" % b.size())
				b[0].pressed.emit()
				suite.call()
		3:
			if act._phase == "course" and ca._rival != null and ca._rival.pret:
				var f = ca._rival
				print("  [carrière] duel lancé : tracé du rival %.0f m, temps visé %.1f s, rival à %.0f m de la voiture" % [f.longueur,
					f.temps_cible, f.voiture.global_position.distance_to(car.global_position)])
				suite.call()
		4:
			if dt >= 30:
				shot.call("rival")
				suite.call()
		5:
			if dt >= 240:
				var f = ca._rival
				print("  [carrière] course t=%.1f s : rival à %.0f m de la voiture, %.0f m parcourus, %s" % [act._t,
					f.voiture.global_position.distance_to(car.global_position), f.s, "sans physique (loin)" if f.fige else "physique"])
				shot.call("rival_loin")
				ca.epreuve_finie(0, f.temps_cible - 5.0, "or", "")
				act._stop()
				suite.call()
		6:
			if ca.faites.has("duel"):
				print("  [carrière] duel gagné : réputation %d, victoires %d" % [int(ca.reps[0]), int(ca.duel_bilan("kevin")[0])])
				ca.lancer("pain", true)
				set_meta("c_k", 0)
				suite.call()
		7:
			if ca._phase == "livre":
				print("  [carrière] livraison : commandes chargées, %d arrêts, limite %.0f s" % [ca._arrets.size(), ca._limite])
				shot.call("livraison")
				poser.call(int(ca._arrets[0].i), act._rp(int(ca._arrets[0].i)) + Vector2(50, 0))
				suite.call()
		8:
			var k: int = get_meta("c_k", 0)
			if ca.faites.has("pain"):
				print("  [carrière] livraison réussie : réputation %d, chocs %d, temps %.0f s" % [int(ca.reps[0]), ca._chocs, ca._t])
				suite.call()
			elif ca._phase == "livre" and ca._k > k:
				set_meta("c_k", ca._k)
				set_meta("c_t0", t)
				print("  [carrière] livré : %s" % ca._arrets[k].nom)
				poser.call(int(ca._arrets[ca._k].i), act._rp(int(ca._arrets[ca._k].i)) + Vector2(50, 0))
			elif ca._phase == "" and not ca.faites.has("pain") and dt > 30:
				print("  [carrière] ÉCHEC : livraison ratée (chocs %d)" % ca._chocs)
				get_tree().quit()
		9:
			if dt >= 60 and ca.reps[0] >= 50.0:
				ca.lancer("maire", true)
				suite.call()
		10:
			if dt >= 60 and not act.impose.is_empty():
				poser.call(int(act.impose.pick), act._rp(int(act.impose.dest)))
				suite.call()
		11:
			if act.mode == "taxi" and act._phase == "course":
				print("  [carrière] le maire est monté (%s) ; bulle : « %s »" % [act._cl_nom, act._talk._name.text])
				shot.call("maire")
				poser.call(int(act.impose.dest), Vector2.ZERO)
				suite.call()
		12:
			if ca.faites.has("maire"):
				print("  [carrière] maire déposé : réputation %d" % int(ca.reps[0]))
				ca.epreuve_finie(14, 200.0, "bronze", "")
				suite.call()
		13:
			if ca.fins_vues.has(0) and ca._bulle != null:
				suite.call()
		14:
			if dt >= 40:
				shot.call("message")
				print("  [carrière] fin : réputation %d, missions %s, message de fin %s\n%s" % [int(ca.reps[0]), str(ca.faites.keys()),
					ca.fins_vues.has(0), FileAccess.get_file_as_string("user://carriere.cfg")])
				get_tree().quit()

# ---------------------------------------------------------------- essai : --carriere2-test (#131)
## Chapitres 2 à 4, étape par étape (chaque étape attend l'état du jeu, 1 200 pas au plus) : message de fin du
## chapitre 1 (voiture offerte), onglet, œufs (voiture posée à chaque arrêt), colis perdu (posée près du lieu), chrono
## (arrivée simulée), mariée (prise en charge, dépôt), duel contre Sandrine (arrivée simulée), bébé (3 chocs simulés :
## raté ; puis réussi), train, service de nuit (3 vraies courses de taxi : voiture posée chez le client puis à
## destination), course de la ville (arrivée simulée 1re), duel contre Didier, les 5 manches du championnat (arrivées
## simulées ; Didier devant à la 2e), message de fin, rechargement de la sauvegarde. Temps du jeu ×4. Captures
## user://shots/carriere2_*.png, journal « [carrière2] ». Lancer avec --drive-test --carriere2-test --taxi-sorte=normale.
func _carriere2_test(t: int) -> void:
	var ca = carriere
	var act = activities
	car.touch_throttle = 0.0
	car.touch_steer = 0.0
	car.touch_brake = 1.0
	if t < 240:
		return
	var etape: int = get_meta("c_etape", 0)
	var t0: int = get_meta("c_t0", 240)
	var dt := t - t0
	var suite := func(n := -1):
		set_meta("c_etape", etape + 1 if n < 0 else n)
		set_meta("c_t0", t)
	var shot := func(n: String):
		DirAccess.make_dir_recursive_absolute("user://shots")
		get_viewport().get_texture().get_image().save_png("user://shots/carriere2_%s.png" % n)
	var poser := func(i: int, vers: Vector2):
		var s: Array = act._start_at(i, vers)
		get_node("HUD").teleport.emit(s[0], s[1])
	var dire := func(x: String): print("  [carrière2] " + x)
	var repondre := func(k: int) -> bool:          # touche la réponse k de la bulle ouverte
		if ca._bulle == null:
			return false
		var b: Array = ca._bulle.find_children("*", "Button", true, false)
		if b.size() <= k:
			return false
		b[k].pressed.emit()
		return true
	var bulle := func() -> String:
		if ca._bulle == null:
			return ""
		var l: Array = ca._bulle.find_children("*", "Label", true, false)
		return " | ".join(PackedStringArray(l.map(func(x): return x.text.replace("\n", " / "))))
	if dt > 1200:
		dire.call("ÉCHEC : étape %d bloquée (mission « %s », phase « %s », activité %s/%s)" % [etape, ca.en_cours, ca._phase, act.mode, act._phase])
		get_tree().quit()
		return
	var n: int = get_meta("c_manche", 1)
	match etape:
		0:
			Engine.time_scale = 4.0
			ca.effacer()
			ca.reps[0] = 100.0
			ca.commencee = true
			ca.sauver()
			set_meta("deuche", main_garage_a("deuche"))
			for nom in ca.lieux_des_missions():
				var nm: String = nom.get_slice("|", 0)
				var com: String = nom.get_slice("|", 1) if nom.contains("|") else ""
				var n_l: int = act.places.filter(func(p): return str(p.n) == nm and (com == "" or str(p.c) == com)).size()
				if n_l != 1:
					dire.call("ERREUR : lieu « %s » trouvé %d fois" % [nom, n_l])
			dire.call("lieux des missions contrôlés : %d" % ca.lieux_des_missions().size())
			ca._verifier_fins()
			suite.call()
		1:
			if ca.fins_vues.has(0) and ca._bulle != null and dt >= 20:
				dire.call("fin du chapitre 1 : %s" % bulle.call())
				dire.call("Deuche au garage : %s (avant : %s)" % [main_garage_a("deuche"), get_meta("deuche")])
				shot.call("fin1")
				repondre.call(0)
				act.open_menu(6)
				get_tree().paused = false
				suite.call()
		2:
			if dt >= 40:
				shot.call("menu2")
				var bs: Array = act._menu.find_children("*", "Button", true, false) if act._menu else []
				dire.call("onglet : chapitre affiché %d, %d boutons, chapitres ouverts %s" % [act._menu.chap_vu + 1, bs.size(),
					str([ca.ouvert(0), ca.ouvert(1), ca.ouvert(2), ca.ouvert(3)])])
				ca.lancer("oeufs", true)
				set_meta("c_k", 0)
				suite.call()
		3:
			if ca._phase == "livre":
				dire.call("œufs : chargement pris, %d arrêts, limite %.0f s" % [ca._arrets.size(), ca._limite])
				shot.call("oeufs")
				poser.call(int(ca._arrets[0].i), act._rp(int(ca._arrets[0].i)) + Vector2(50, 0))
				suite.call()
		4:
			var k: int = get_meta("c_k", 0)
			if ca.faites.has("oeufs"):
				dire.call("œufs livrés : réputation %d, chocs %d, temps %.0f s" % [int(ca.reps[1]), ca._chocs, ca._t])
				suite.call()
			elif ca._phase == "livre" and ca._k > k:
				set_meta("c_k", ca._k)
				set_meta("c_t0", t)
				dire.call("livré : %s" % ca._arrets[k].nom)
				poser.call(int(ca._arrets[ca._k].i), act._rp(int(ca._arrets[ca._k].i)) + Vector2(50, 0))
			elif ca._phase == "" and dt > 30:
				dire.call("ÉCHEC : œufs ratés (chocs %d)" % ca._chocs)
				get_tree().quit()
		5:
			if dt >= 40:
				ca.lancer("colis", true)
				suite.call()
		6:
			if act.mode == "chasse" and ca._phase == "chasse" and dt >= 20:
				var i: int = act._nearest(act._target)
				dire.call("colis : à trouver %s, limite %.0f s, route la plus proche à %.0f m (rayon %.0f m)" % [act._target_name,
					ca._limite, act._rp(i).distance_to(act._target), act._found_r])
				shot.call("colis")
				poser.call(i, act._target)
				suite.call()
		7:
			if ca.faites.has("colis"):
				dire.call("colis trouvé : réputation %d" % int(ca.reps[1]))
				ca.epreuve_finie(17, 100.0, "argent", "")
				suite.call()
			elif ca._phase == "" and dt > 60:
				dire.call("ÉCHEC : colis pas trouvé (voiture à %.0f m)" % act._car2().distance_to(act._target))
				get_tree().quit()
		8:
			if ca.faites.has("chrono2") and dt >= 20:
				dire.call("chrono de la Cassole : réputation %d" % int(ca.reps[1]))
				ca.lancer("mariee", true)
				suite.call()
		9, 19, 22, 25:
			if not act.impose.is_empty() and dt >= 40:
				poser.call(int(act.impose.pick), act._rp(int(act.impose.dest)))
				suite.call()
		10, 20, 23, 26:
			if act.mode == "taxi" and act._phase == "course":
				dire.call("%s : client monté (%s), bulle « %s », limite %.0f s" % [ca.en_cours, act._cl_nom, act._talk._name.text, float(act.impose.limite)])
				shot.call(ca.en_cours)
				if etape == 20:
					suite.call(40)                     # le bébé : 3 chocs d'abord
				else:
					poser.call(int(act.impose.dest), Vector2.ZERO)
					suite.call()
		11:
			if ca.faites.has("mariee"):
				dire.call("mariée déposée : réputation %d" % int(ca.reps[1]))
				ca.lancer("duel2", true)
				suite.call()
		12, 32:
			if ca._bulle != null:
				shot.call("defi_" + ca.en_cours)
				dire.call("défi : %s" % bulle.call())
				repondre.call(0)
				suite.call()
		13, 33:
			if act._phase == "course" and ca._rival != null and ca._rival.pret:
				var f = ca._rival
				dire.call("duel lancé : %s en %s, tracé %.0f m, temps visé %.1f s" % [f.nom, f.modele, f.longueur, f.temps_cible])
				suite.call()
		14, 34:
			if dt >= 30:
				shot.call("course_" + ca.en_cours)
				var f = ca._rival
				var m: Dictionary = ca.mission(ca.en_cours)
				dire.call("course t=%.1f s : %s à %.0f m, %.0f m parcourus" % [act._t, f.nom, f.voiture.global_position.distance_to(car.global_position), f.s])
				ca.epreuve_finie(int(m.epreuve), f.temps_cible - 5.0, "or", "")
				act._stop()
				suite.call()
		15, 35:
			var ch := 1 if etape == 15 else 2
			if ca.fins_vues.has(ch) and ca._bulle != null and dt >= 20:
				dire.call("fin du chapitre %d : réputation %d, duels %s ; %s" % [ch + 1, int(ca.reps[ch]), str(ca.duels), bulle.call()])
				dire.call("cadeau %s au garage : %s" % [ca.CHAPITRES[ch].cadeau, main_garage_a(String(ca.CHAPITRES[ch].cadeau))])
				shot.call("fin%d" % (ch + 1))
				repondre.call(0)
				if etape == 15:
					ca.lancer("bebe", true)
					suite.call(19)
				else:
					suite.call(50)
		40:
			# trois chocs simulés (saut de vitesse vu par la détection des chocs du taxi) : mission ratée
			if act.mode == "taxi" and dt % 150 == 75:
				act._prev_v = car.linear_velocity + Vector3(30.0, 0.0, 0.0)
				dire.call("choc simulé (%d)" % (act._shocks + 1))
			elif act.mode == "" and ca.en_cours == "" and not ca.faites.has("bebe"):
				dire.call("bébé : mission ratée après %d chocs (attendu : 3)" % act._shocks)
				suite.call()
		41:
			if dt >= 40:
				ca.lancer("bebe", true)
				suite.call(22)
		24:
			if ca.faites.has("bebe"):
				dire.call("bébé à l'hôpital : réputation %d" % int(ca.reps[2]))
				ca.lancer("train", true)
				suite.call()
		27:
			if ca.faites.has("train"):
				dire.call("train attrapé : réputation %d" % int(ca.reps[2]))
				ca.lancer("nuit", true)
				suite.call()
		28:
			if act.mode == "taxi" and act._phase == "attente" and time_of_day == 3 and dt >= 40:
				dire.call("service de nuit : heure %d, taxi lancé" % time_of_day)
				shot.call("nuit")
				suite.call()
		29:
			var cle := "%s:%s" % [act._phase, str(act._cl_pos)]
			if ca.faites.has("nuit"):
				dire.call("service de nuit réussi : %d courses, %d étoiles, réputation %d" % [ca._courses, ca._etoiles, int(ca.reps[2])])
				suite.call()
			elif ca.en_cours == "":
				dire.call("ÉCHEC : service de nuit raté (%d courses, %d étoiles)" % [ca._courses, ca._etoiles])
				get_tree().quit()
			elif cle != str(get_meta("c_pose", "")) and dt >= 30:
				if act._phase == "attente":
					set_meta("c_pose", cle)
					set_meta("c_t0", t)
					poser.call(act._nearest(act._cl_pos), act._cl_pos + Vector2(0, 40))
				elif act._phase == "course":
					set_meta("c_pose", cle)
					set_meta("c_t0", t)
					dire.call("course de nuit vers %s" % act._dest_name)
					poser.call(act._dest, Vector2.ZERO)
			elif dt >= 400 and act._phase == "attente":
				dire.call("voiture coincée loin du client (%.0f m, %d km/h) : montée forcée" % [act._car2().distance_to(act._cl_pos), int(car.kmh())])
				set_meta("c_t0", t)
				act._embarquer()
			elif dt >= 400 and act._phase == "course":
				dire.call("voiture coincée loin de la destination (%.0f m) : dépose forcée" % act._car2().distance_to(act._rp(act._dest)))
				set_meta("c_t0", t)
				act._taxi_drop()
		30:
			if dt >= 60:
				dire.call("après le service : heure %d" % time_of_day)
				ca.lancer("ville", true)
				suite.call()
		31:
			if act._phase == "course" and act.concurrents.size() == 3 and act.concurrents[0].pret and dt >= 30:
				shot.call("ville")
				dire.call("course de la ville : 3 concurrents, place affichée %d" % act._place())
				ca.epreuve_finie(24, 120.0, "or", "", 1)
				act._stop()
				ca.lancer("duel3", true)
				suite.call()
		50:
			if dt >= 20:
				ca.lancer("manche%d" % n, true)
				suite.call()
		51:
			if ca._bulle != null:
				dire.call("manche %d, défi : %s" % [n, bulle.call()])
				if n == 1:
					shot.call("defi_manche")
				repondre.call(0)
				suite.call()
		52:
			if act._phase == "course" and ca._concs.size() == 3 and ca._concs.values().all(func(c): return c.pret) and dt >= 20:
				var d := PackedStringArray()
				for c in ca._concs.values():
					d.append("%s (%s, %.0f s)" % [c.nom, c.modele, c.temps_cible])
				dire.call("manche %d lancée : %s" % [n, ", ".join(d)])
				if n == 1:
					shot.call("manche")
				if n == 2:
					ca._concs["didier"].fini = true
					ca._concs["didier"].t_arrivee = 50.0
				var m: Dictionary = ca.mission("manche%d" % n)
				ca.epreuve_finie(int(m.epreuve), 60.0, "or", "", 1)
				act._stop()
				suite.call()
		53:
			if ca._bulle != null and ca.faites.has("manche%d" % n):
				dire.call("manche %d finie : %s" % [n, bulle.call()])
				if n < 5:
					repondre.call(0)
					set_meta("c_manche", n + 1)
					suite.call(50)
				else:
					shot.call("manche5")
					suite.call()
		54:
			if ca.fins_vues.has(3) and ca._bulle != null and dt >= 20:
				dire.call("fin de la carrière : chapitre 4 %d, champion %s ; %s" % [int(ca.reps[3]), ca.carriere_finie(), bulle.call()])
				dire.call("cadeau gt3 au garage : %s" % main_garage_a("gt3"))
				shot.call("fin4")
				repondre.call(0)
				act.open_menu(6)
				get_tree().paused = false
				suite.call()
		55:
			if dt >= 40:
				shot.call("menu4")
				var avant: Array = ca.reps.duplicate()
				ca.charger()
				dire.call("sauvegarde relue : réputations %s -> %s, missions %d, championnat %s" % [str(avant), str(ca.reps), ca.faites.size(), str(ca.champ.points)])
				dire.call("FIN : tout est passé")
				get_tree().quit()

func main_garage_a(id: String) -> bool:
	return garage != null and garage.a_voiture(id)

# ---------------------------------------------------------------- essai : --circulation-test (#132)
## Circulation autour du joueur (lancer avec --fixed-fps 8 : temps de jeu indépendant de la lenteur du rendu ;
## --drive-from=<x,y,z,cap> : le lieu ; --densite=0-3, défaut 3) : relevé toutes les 10 s (voitures, vitesses, ce qui
## les arrête, plus petite distance entre deux voitures de même sens, hauteur par rapport à la route, coût par image) ;
## captures derrière une voiture qui roule ; voiture du joueur arrêtée devant une voiture qui arrive (elle doit
## s'arrêter derrière et klaxonner) ; voiture du joueur lancée contre une voiture qui arrive (elle doit devenir une
## épave). Captures user://shots/circulation_*.png, journal « [circulation] ».
func _circulation_test() -> void:
	var ci = circulation
	var dens := 3
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--densite="):
			dens = int(a.get_slice("=", 1))
	DirAccess.make_dir_recursive_absolute("user://shots")
	var shot := func(n: String):
		get_viewport().get_texture().get_image().save_png("user://shots/circulation_%s.png" % n)
	var dire := func(x: String): print("  [circulation] " + x)
	while not Chargement.fini:
		await get_tree().process_frame
	Engine.max_physics_steps_per_frame = 16
	ci.set_densite(dens)
	dire.call("réseau : %d carrefours, %d arcs ; niveau %d, densité %d : %d voitures voulues" % [ci._nx.size(), ci._a.size(),
		ci.niveau, ci.densite, ci.voulu()])
	var pas := func(n: int):
		for i in n:
			await get_tree().physics_frame
	var releve := func(tag: String):
		var vs := []
		var raisons := {}
		var dmin := INF
		var hmax := 0.0
		for c in ci.voitures:
			vs.append(float(c.v) * 3.6)
			raisons[String(c.leader)] = int(raisons.get(String(c.leader), 0)) + 1
			for o in ci.voitures:
				if o != c and (o.dir as Vector3).dot(c.dir) > 0.5:
					dmin = minf(dmin, (o.pos as Vector3).distance_to(c.pos))
		var moy := 0.0
		for v in vs:
			moy += v
		moy /= maxf(vs.size(), 1)
		var e = PerfMon._sys.get("circulation", [0, 0, 1])
		dire.call("%s : %d voitures, %.0f km/h en moyenne (%s), arrêtées %d, gênes %s, plus petite distance de même sens %.1f m, épaves %d, coût %.2f ms/pas (pire %.2f)" % [tag,
			ci.voitures.size(), moy, ", ".join(PackedStringArray(vs.map(func(x): return str(int(x))))), vs.filter(func(x): return x < 2.0).size(),
			str(raisons), dmin, ci.epaves.size(), float(e[0]) / maxf(float(e[2]), 1.0) / 1000.0, float(e[1]) / 1000.0])
	car.touch_throttle = 0.0
	car.touch_brake = 1.0
	car.touch_steer = 0.0
	car.aide_voie = false
	await pas.call(120)
	releve.call("départ")
	shot.call("0_depart")
	if OS.get_cmdline_user_args().has("--circulation-gros-plans"):
		await _circulation_gros_plans(ci, shot, dire, pas)
		get_tree().quit()
		return
	if OS.get_cmdline_user_args().has("--circulation-feux"):
		await _circulation_feux(ci, shot, dire, pas)
	if OS.get_cmdline_user_args().has("--circulation-depasse"):
		await _circulation_depasse(ci, shot, dire, pas)
	if OS.get_cmdline_user_args().has("--circulation-double"):
		await _circulation_double(ci, shot, dire)
	if OS.get_cmdline_user_args().has("--circulation-feux") or OS.get_cmdline_user_args().has("--circulation-depasse") \
			or OS.get_cmdline_user_args().has("--circulation-double"):
		releve.call("fin")
		dire.call("FIN")
		get_tree().quit()
		return
	for k in 3:
		await pas.call(600)
		releve.call("t+%d s" % ((k + 1) * 10))
	# derrière la voiture qui roule la plus proche : la voiture du joueur posée 14 m derrière, immobile, caméra de poursuite
	var c = null
	for o in ci.voitures:
		if float(o.v) > 5.0 and (c == null or (o.pos as Vector3).distance_to(car.global_position) < (c.pos as Vector3).distance_to(car.global_position)):
			c = o
	if c:
		for k in 4:
			var d: Vector3 = c.dir
			var p: Vector3 = (c.pos as Vector3) - d * (14.0 + float(c.v) * 0.5)
			car.place(p + Vector3(0, 0.3, 0), rad_to_deg(atan2(d.x, -d.z)))
			car.hold(0.3)
			cam_rig.snap()
			await pas.call(30)
			if not is_instance_valid(c.mi):
				break
			dire.call("suivie : %d km/h, voie %d, %.2f m au-dessus de l'axe de la route, gêne « %s »" % [int(float(c.v) * 3.6), int(c.voie), (c.pos as Vector3).y - ci._geo(int(c.voie), float(c.s), 0)[0].y, c.leader])
			shot.call("1_suivie_%d" % k)
			await pas.call(90)
	# blocage, de nuit : la voiture du joueur arrêtée sur la voie, 35 m devant une voiture qui arrive, tournée vers elle
	# (phares, clignotant si elle tourne au prochain carrefour)
	var heure: int = time_of_day
	set_time(3)
	c = null
	for o in ci.voitures:
		if float(o.v) > 6.0 and float(o.L) - float(o.s) > 60.0:
			c = o
			break
	if c:
		var g: Array = ci._geo(int(c.voie), float(c.s) + 35.0, int(c.rang))
		var t: Vector2 = g[1]
		car.place((g[0] as Vector3) + Vector3(0, 0.4, 0), rad_to_deg(atan2(-t.x, t.y)))
		car.hold(2.0)
		cam_rig.snap()
		var id := int(c.id)
		var v0 := float(c.v)
		var acc0: int = ci.accidents
		var vu = c
		car.touch_brake = 0.0                     # FREIN tenu à l'arrêt = marche arrière : voiture tenue à sa place
		for k in 16:
			car.hold(0.6)
			await pas.call(60)
			vu = null
			for o in ci.voitures:
				if int(o.id) == id:
					vu = o
			if vu == null:
				break
			var dj: Vector3 = car.global_position - (vu.pos as Vector3)
			var fv: Vector3 = vu.dir
			dire.call("  blocage +%.1f s : %d km/h, à %.1f m du joueur (devant %.1f, côté %.1f, haut %.1f), gêne « %s », freine %s" % [(k + 1) * 0.5,
				int(float(vu.v) * 3.6), dj.length(), dj.dot(fv), dj.dot(Vector3(-fv.z, 0.0, fv.x)), dj.y, vu.leader, vu.frein])
		if vu:
			var gap: float = (vu.pos as Vector3).distance_to(car.global_position) - 2.4 - ci.BOITES[int(vu.m)].z / 2.0
			car.touch_brake = 1.0
			dire.call("blocage : voiture %d arrivée à %.0f km/h, maintenant %.1f km/h, %.1f m derrière le joueur, gêne « %s », klaxon %s" % [id,
				v0 * 3.6, float(vu.v) * 3.6, gap, vu.leader, "oui" if float(vu.klaxon) > 0.0 else "non"])
			shot.call("2_blocage_nuit")
		else:
			dire.call("blocage : voiture %d disparue (accidents %d -> %d)" % [id, acc0, ci.accidents])
	set_time(heure)
	# choc : la voiture du joueur lancée de face contre une voiture qui arrive
	c = null
	for o in ci.voitures:
		if float(o.v) > 6.0 and float(o.L) - float(o.s) > 80.0:
			c = o
			break
	if c:
		var g: Array = ci._geo(int(c.voie), float(c.s) + 45.0, int(c.rang))
		var t: Vector2 = g[1]
		car.place((g[0] as Vector3) + Vector3(0, 0.4, 0), rad_to_deg(atan2(-t.x, t.y)))
		car.hold(0.2)
		var n_ep: int = ci.accidents
		car.touch_brake = 0.0
		car.touch_throttle = 1.0
		for i in 15 * 8 * 6:
			await get_tree().physics_frame
			if ci.accidents > n_ep:
				break
		await pas.call(30)
		cam_rig.snap()
		shot.call("3_choc")
		car.touch_throttle = 0.0
		car.touch_brake = 1.0
		dire.call("choc : accidents %d -> %d, voiture du joueur à %d km/h%s" % [n_ep, ci.accidents, int(car.kmh()),
			"" if ci.accidents > n_ep else " (ÉCHEC : pas d'épave)"])
		if ci.accidents > n_ep:
			var rb: RigidBody3D = ci.epaves[ci.epaves.size() - 1].rb
			await pas.call(240)
			dire.call("épave : %.1f m/s, inclinaison %.0f°" % [rb.linear_velocity.length(), rad_to_deg(rb.global_transform.basis.y.angle_to(Vector3.UP))])
			shot.call("4_epave")
	releve.call("fin")
	dire.call("FIN")
	get_tree().quit()

## Feux tricolores (#134) : 90 s d'observation ; chaque passage d'un carrefour à feu est noté avec l'état du feu à ce
## moment (au rouge à plus de 3 m/s : infraction) ; capture d'une voiture arrêtée au feu, caméra libre derrière elle.
func _circulation_feux(ci, shot: Callable, dire: Callable, pas: Callable) -> void:
	var avant := {}                      # voiture -> [voie, feu, état] au pas précédent
	var passages := 0
	var au_rouge := 0
	var arrets := 0
	var capture := false
	var cam := Camera3D.new()
	add_child(cam)
	var cam0 := get_viewport().get_camera_3d()
	for i in 15 * 8 * 90:
		await get_tree().physics_frame
		for c in ci.voitures:
			var k := int(c.voie) >> 1
			var feu: int = ci._feu_b[k] if int(c.voie) & 1 == 0 else ci._feu_a[k]
			var p = avant.get(int(c.id))
			if p != null and int(p[0]) != int(c.voie) and int(p[1]) >= 0:
				passages += 1
				if int(p[2]) == 2 and float(c.v) > 3.0:
					au_rouge += 1
					dire.call("au rouge : voiture %d à %d km/h" % [int(c.id), int(float(c.v) * 3.6)])
			avant[int(c.id)] = [int(c.voie), feu, ci._etat_feu(feu) if feu >= 0 and int(c.engage) != int(c.voie) else -1]
			if String(c.leader) == "feu" and float(c.v) < 0.3:
				arrets += 1
				if not capture and float(c.L) - float(c.s) < 12.0:
					capture = true
					var d: Vector3 = c.dir
					cam.global_position = (c.pos as Vector3) - d * 9.0 + Vector3(-d.z, 0.0, d.x) * 2.5 + Vector3.UP * 2.6
					cam.look_at((c.pos as Vector3) + d * 12.0 + Vector3.UP * 1.5)
					cam.current = true
					for f in 3:
						await get_tree().process_frame       # une vraie image avec la caméra libre (--fixed-fps)
					shot.call("feu_rouge")
					dire.call("capture : voiture %d arrêtée à %.1f m du carrefour, feu %d" % [int(c.id), float(c.L) - float(c.s), ci._etat_feu(feu)])
					cam0.current = true
		if i % (15 * 8 * 15) == 0:
			dire.call("feux t=%d s : %d passages de carrefours à feu, %d au rouge, %d pas d'arrêt au feu" % [i / 120, passages, au_rouge, arrets])
	dire.call("feux : %d passages de carrefours à feu, %d au rouge (à plus de 3 m/s), %d pas d'arrêt au feu" % [passages, au_rouge, arrets])
	cam.queue_free()

## Véhicule lent (v6.89) : la voiture du joueur roule à 30 km/h sur une route rapide à double sens, 35 m devant une
## voiture de la circulation ; relevé : voiture qui la double (écart, passage devant, retour dans sa voie), chocs.
func _circulation_double(ci, shot: Callable, dire: Callable) -> void:
	for essai in 6:
		var c = null
		for o in ci.voitures:
			var k := int(o.voie) >> 1
			if float(o.v) > 8.0 and not (ci._fl[k] & 1) and ci._v[k] >= ci.V_RAPIDE and float(o.L) - float(o.s) > 320.0 \
					and (c == null or (o.pos as Vector3).distance_to(car.global_position) < (c.pos as Vector3).distance_to(car.global_position)):
				c = o
		if c == null:
			dire.call("véhicule lent, essai %d : aucune voiture sur une route rapide assez longue" % (essai + 1))
			for i in 960:
				car.hold(0.5)
				await get_tree().physics_frame
			continue
		var voie := int(c.voie)
		var id := int(c.id)
		var sj: float = float(c.s) + 35.0
		var vj := 30.0 / 3.6
		var a0: int = ci.accidents
		var ecart_max := 0.0
		var devant := false
		var revenu := false
		var vu := false
		var cl_g := false
		var cl_d := false
		dire.call("véhicule lent, essai %d : voiture %d à %.0f km/h, route limitée à %.0f km/h, joueur 35 m devant à 30 km/h" % [
			essai + 1, id, float(c.v) * 3.6, ci._v[voie >> 1] * 3.6])
		for i in 45 * 120:
			sj += vj / 120.0
			if sj > float(c.L) - 20.0:
				break
			var g: Array = ci._geo(voie, sj, 0)
			var t: Vector2 = g[1]
			car.global_transform = Transform3D(Basis(Vector3.UP, PI - atan2(t.x, -t.y)), (g[0] as Vector3) + Vector3(0, 0.35, 0))
			car.linear_velocity = Vector3(t.x, 0, t.y) * vj
			await get_tree().physics_frame
			var o = null
			for x in ci.voitures:
				if int(x.id) == id:
					o = x
			if o == null or int(o.voie) != voie:
				break
			var e: float = ci._ecart(o, float(o.s))
			ecart_max = maxf(ecart_max, e)
			var dpo: Array = o.dep
			if dpo.size() >= 6 and float(o.s) < float(dpo[1]) and int(o.clign) == 1:
				cl_g = true
			if dpo.size() >= 6 and float(o.s) > float(dpo[2]) and int(o.clign) == 2:
				cl_d = true
			if e > 1.5 and float(o.s) > sj + 6.0:
				devant = true
			if devant and e < 0.05:
				revenu = true
				break
			if e > 1.5 and absf(float(o.s) - sj) < 3.0 and not vu:
				vu = true
				var cam := Camera3D.new()
				add_child(cam)
				var d: Vector3 = o.dir
				cam.global_position = car.global_position - d * 14.0 + Vector3(d.z, 0, -d.x) * 4.0 + Vector3.UP * 3.5
				cam.look_at(car.global_position + d * 4.0 + Vector3.UP)
				cam.current = true
				for f in 3:
					await get_tree().process_frame
				shot.call("double")
				cam.queue_free()
		dire.call("véhicule lent : écart maximal %.1f m, passée devant %s, revenue dans sa voie %s, chocs %d, clignotant à gauche en déboîtant %s, à droite en se rabattant %s" % [
			ecart_max, str(devant), str(revenu), ci.accidents - a0, str(cl_g), str(cl_d)])
		if revenu:
			break

## Dépassement (#134) : la voiture du joueur tenue arrêtée sur une voie à double sens, 30 m devant une voiture qui arrive ;
## relevé de la voiture : arrêt, klaxon, écart de dépassement, passage du joueur, retour dans sa voie.
func _circulation_depasse(ci, shot: Callable, dire: Callable, pas: Callable) -> void:
	for essai in 4:
		var c = null
		for o in ci.voitures:
			var k := int(o.voie) >> 1
			if float(o.v) > 4.0 and not (ci._fl[k] & 1) and float(o.L) - float(o.s) > 75.0 and (c == null
					or (o.pos as Vector3).distance_to(car.global_position) < (c.pos as Vector3).distance_to(car.global_position)):
				c = o
		dire.call("dépassement, essai %d : %s" % [essai + 1, "voiture %d choisie" % int(c.id) if c else "aucune voiture candidate"])
		if c == null:
			await pas.call(240)
			continue
		var g: Array = ci._geo(int(c.voie), float(c.s) + 30.0, int(c.rang))
		var t: Vector2 = g[1]
		car.touch_brake = 0.0
		car.place((g[0] as Vector3) + Vector3(0, 0.4, 0), rad_to_deg(atan2(t.x, -t.y)))
		cam_rig.snap()
		var id := int(c.id)
		var ecart_max := 0.0
		var klaxon := false
		var depasse := false
		var revenu := false
		for k in 40:
			car.hold(0.6)
			await pas.call(60)
			var vu = null
			for o in ci.voitures:
				if int(o.id) == id:
					vu = o
			if vu == null:
				dire.call("dépassement : voiture %d disparue (accidents %d)" % [id, ci.accidents])
				break
			var e: float = ci._ecart(vu, float(vu.s))
			ecart_max = maxf(ecart_max, e)
			if k % 2 == 0:
				dire.call("  dépassement +%d s : voiture %d à %d km/h, gêne « %s », attente %.1f s, écart %.1f m, dep %s" % [k / 2 + 1,
					id, int(float(vu.v) * 3.6), vu.leader, float(vu.attente), e, str(vu.dep)])
			klaxon = klaxon or float(vu.klaxon) > 0.0
			var devant: float = (car.global_position - (vu.pos as Vector3)).dot(vu.dir)
			if e > 1.0 and absf(devant) < 2.0 and not depasse:
				depasse = true
				shot.call("depasse")
			if depasse and devant < -8.0 and e < 0.2:
				revenu = true
				break
		car.touch_brake = 1.0
		dire.call("dépassement : écart maximal %.1f m, klaxon %s, à hauteur du joueur %s, revenu dans sa voie %s" % [ecart_max,
			klaxon, depasse, revenu])
		if revenu:
			return

## Gros plans d'une voiture de la circulation (--circulation-gros-plans) : caméra libre posée à côté d'elle, de jour
## (de préférence une voiture qui met son clignotant), puis devant elle de nuit (phares). Captures gros_plan_*.png.
func _circulation_gros_plans(ci, shot: Callable, dire: Callable, pas: Callable) -> void:
	var cam := Camera3D.new()
	cam.fov = 55.0
	add_child(cam)
	var cam0 := get_viewport().get_camera_3d()
	var heure: int = time_of_day
	for nuit in [false, true]:
		set_time(3 if nuit else heure)
		await pas.call(30)
		var c = null
		for o in ci.voitures:
			if float(o.v) > 3.0 and (c == null or int(o.clign) > int(c.clign) or (int(o.clign) == int(c.clign)
					and (o.pos as Vector3).distance_to(car.global_position) < (c.pos as Vector3).distance_to(car.global_position))):
				c = o
		if c == null:
			dire.call("gros plan : aucune voiture qui roule")
			continue
		cam.current = true
		for k in 4:
			if not is_instance_valid(c.mi):
				break
			var p: Vector3 = c.pos
			var d: Vector3 = c.dir
			var r := Vector3(-d.z, 0.0, d.x)
			cam.global_position = p + d * (10.0 if nuit else 2.0) + r * (2.5 if nuit else 5.5) + Vector3.UP * 1.3
			cam.look_at(p + Vector3.UP * 0.6)
			for f in 3:
				await get_tree().process_frame
			dire.call("gros plan %s %d : %d km/h, clignotant %d, freine %s, gêne « %s »" % ["nuit" if nuit else "jour", k,
				int(float(c.v) * 3.6), int(c.clign), c.frein, c.leader])
			shot.call("gros_plan_%s_%d" % ["nuit" if nuit else "jour", k])
			await pas.call(25)
	set_time(heure)
	cam0.current = true
	cam.queue_free()

# ---------------------------------------------------------------- essai : --succes-test (#133)
## Succès et statistiques : compteurs remis à zéro ; 20 s de vraie conduite plein gaz (distance, vitesse maximale,
## temps) ; argent gagné au garage (crochet) ; compteurs poussés pour débloquer des succès (primes, annonces une par
## une) ; onglet Succès (capture) ; sauvegarde relue. Lancer avec --fixed-fps 8 -- --drive-test --succes-test
## --drive-from=-8410.95,221,-7187.25,45.2 (longue ligne droite). Captures user://shots/succes_*.png.
func _succes_test() -> void:
	var su = succes
	var dire := func(x: String): print("  [succès] " + x)
	var shot := func(n: String):
		DirAccess.make_dir_recursive_absolute("user://shots")
		get_viewport().get_texture().get_image().save_png("user://shots/succes_%s.png" % n)
	while not Chargement.fini:
		await get_tree().process_frame
	Engine.max_physics_steps_per_frame = 16
	su.effacer()
	su.verifier()
	dire.call("au départ (état déjà sauvegardé : médailles, voitures, carrière) : %d succès %s" % [su.obtenus.size(), str(su.obtenus.keys())])
	var argent0: float = garage.argent
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://shots/ligne_bus.png"))
	if OS.get_cmdline_user_args().has("--succes-meteo"):
		# v6.95 : à l'aube du cycle, sous la pluie, compteurs juste sous le but
		set_time(CYCLE, 6.0)
		set_weather(2)
		su.stats["km_pluie"] = 4.9
		su.stats["km_aube"] = 1.9
		su.stats["heures_cycle"] = 23.8
		su.stats["eclairs"] = 19.0
		su.stats["taxi_nuit"] = 4.0
		await get_tree().process_frame
		dire.call("météo : pluie %.2f, heure %s" % [pluie, heure_texte()])
	car.touch_brake = 0.0
	car.touch_throttle = 1.0
	car.aide_voie = true
	var t0 := Time.get_ticks_msec()
	for i in 15 * 8 * 20:
		await get_tree().physics_frame
	car.touch_throttle = 0.0
	car.touch_brake = 1.0
	dire.call("après 20 s de conduite : %s, vitesse maximale %s, temps %s, communes %d" % [su.texte_stat("km", "km"),
		su.texte_stat("vmax", "km/h"), su.texte_stat("temps", "temps"), int(su.valeur("communes"))])
	var a0: float = su.valeur("argent")
	garage.gagner(1000.0)
	dire.call("argent gagné : %.0f -> %.0f (crochet du garage)" % [a0, su.valeur("argent")])
	su.noter("explosions")
	su.noter("taxi", 1.0)
	su.noter("km", 1.0)
	if OS.get_cmdline_user_args().has("--succes-meteo"):
		eclair(1.0)
		su.noter("taxi_nuit")
		dire.call("après 20 s à l'aube sous la pluie : sous la pluie %s, à l'aube %s, heures du cycle %.2f, éclairs %d, taxi de nuit %d" % [
			su.texte_stat("km_pluie", "km"), su.texte_stat("km_aube", "km"), su.valeur("heures_cycle"), int(su.valeur("eclairs")),
			int(su.valeur("taxi_nuit"))])
	for i in 30:
		await get_tree().process_frame
	su.verifier()
	dire.call("débloqués : %s ; argent du garage %.0f -> %.0f (primes comprises)" % [str(su.obtenus.keys()), argent0, garage.argent])
	# annonces une par une (3,5 s chacune)
	for i in 15 * 8 * 4:
		await get_tree().physics_frame
	shot.call("annonce")
	var toast = get_node("HUD").get("_toast")
	dire.call("annonces restantes : %d, bandeau affiché : %s" % [su._annonces.size(),
		(toast.visible and toast.find_children("*", "Label", true, false).any(func(l): return l.text.contains("Succès"))) if toast else false])
	activities.open_menu(7)
	get_tree().paused = false
	for i in 20:
		await get_tree().process_frame
	shot.call("onglet")
	var bs: Array = activities._menu.find_children("*", "Label", true, false) if activities._menu else []
	dire.call("onglet Succès : %d étiquettes" % bs.size())
	var avant: Dictionary = su.obtenus.duplicate()
	su.sauver()
	su.charger()
	dire.call("sauvegarde relue : %d succès (avant %d), km %.2f" % [su.obtenus.size(), avant.size(), su.valeur("km")])
	dire.call("FIN")
	get_tree().quit()

# ---------------------------------------------------------------- essai : --rails-test (#125)
## Voie ferrée en terrain plat (x -8624, z 1519, entre Bourgoin et La Tour-du-Pin) : la voiture roule 4 s le long de
## la voie sur le ballast, puis la traverse (5 s de plein gaz) ; puis elle fonce dans la barrière du passage à niveau
## de la route de x 4845, z 2883 (approche droite de 30 m) ; à chaque fois :
## roulis et tangage maximaux, rotation maximale, voiture retournée ou non. Captures user://shots/rails_*.png.
## Lancer avec --drive-test --rails-test --casse-debug.
func _rails_test(t: int) -> void:
	car.touch_steer = 0.0
	if t < 240:
		car.touch_throttle = 0.0; car.touch_brake = 1.0
		return
	var etape: int = get_meta("r_etape", 0)
	var t0: int = get_meta("r_t0", 240)
	var dt := t - t0
	var suite := func():
		set_meta("r_etape", etape + 1)
		set_meta("r_t0", t)
	var shot := func(n: String):
		DirAccess.make_dir_recursive_absolute("user://shots")
		get_viewport().get_texture().get_image().save_png("user://shots/rails_%s.png" % n)
	var poser := func(x: float, z: float, cap: float, sur_rails: float):
		var y: float = sur_rails if sur_rails > 0.0 else preload("res://scripts/relief.gd").hauteur(Vector3(x, 0, z))
		get_node("HUD").teleport.emit(Vector3(x, y + 1.0, z), cap)
	# stabilité : roulis / tangage (°), rotation (°/s), vitesse
	var b := car.global_transform.basis
	var roulis := rad_to_deg(asin(clampf(b.x.y, -1.0, 1.0)))
	var tangage := rad_to_deg(asin(clampf(b.z.y, -1.0, 1.0)))
	var st: Dictionary = get_meta("r_st", {"roulis": 0.0, "tangage": 0.0, "rot": 0.0, "v": 0.0})
	if etape in [2, 5, 8]:
		st.roulis = maxf(st.roulis, absf(roulis)); st.tangage = maxf(st.tangage, absf(tangage))
		st.rot = maxf(st.rot, rad_to_deg(car.angular_velocity.length())); st.v = maxf(st.v, car.kmh())
		set_meta("r_st", st)
	if etape == 5:                                  # traversée : stabilité à moins de 5 m de l'axe de la voie seulement
		var ax := Vector2(car.global_position.x + 8624.12, car.global_position.z - 1519.17).dot(Vector2(-0.831, 0.556))
		if absf(ax) < 5.0:
			var s2: Dictionary = get_meta("r_st2", {"roulis": 0.0, "tangage": 0.0, "rot": 0.0, "vmin": 999.0, "vmax": 0.0})
			s2.roulis = maxf(s2.roulis, absf(roulis)); s2.tangage = maxf(s2.tangage, absf(tangage))
			s2.rot = maxf(s2.rot, rad_to_deg(car.angular_velocity.length()))
			s2.vmin = minf(s2.vmin, car.kmh()); s2.vmax = maxf(s2.vmax, car.kmh())
			set_meta("r_st2", s2)
	if etape in [2, 5] and dt % 60 == 0:
		print("  [rails]    t=%.1f s : %.0f km/h à %s %s" % [dt / 120.0, car.kmh(), str(car.global_position.round()), car._touching() if car.kmh() < 15.0 else ""])
	var bilan := func(n: String):
		print("  [rails] %s : %.0f km/h au plus, roulis %.1f°, tangage %.1f°, rotation %.0f°/s au plus, retournée %s, à %s" % [n,
			st.v, st.roulis, st.tangage, st.rot, car.global_transform.basis.y.y < 0.3, str(car.global_position.round())])
		set_meta("r_st", {"roulis": 0.0, "tangage": 0.0, "rot": 0.0, "v": 0.0})
	match etape:
		0:
			poser.call(-8624.12, 1519.17, 146.2, 272.26)
			suite.call()
		1:
			car.touch_throttle = 0.0; car.touch_brake = 1.0
			if dt >= 300:
				shot.call("voie")
				var rl = rails
				print("  [rails] %d tuiles chargées, voiture à %.2f m au-dessus du dessus du ballast (272.26)" % [rl.loaded.size(), car.global_position.y - 272.26])
				set_meta("r_st", {"roulis": 0.0, "tangage": 0.0, "rot": 0.0, "v": 0.0})
				suite.call()
		2:
			car.touch_brake = 0.0; car.touch_throttle = 0.6
			if dt >= 480:
				bilan.call("le long de la voie, 4 s à 60 % des gaz")
				shot.call("voie_roule")
				suite.call()
		3:
			car.touch_throttle = 0.0; car.touch_brake = 1.0
			if dt >= 60:
				poser.call(-8612.5, 1511.4, 236.2, -1.0)            # 14 m avant l'axe de la voie
				suite.call()
		4:
			car.touch_throttle = 0.0; car.touch_brake = 1.0
			if dt >= 300:
				set_meta("r_st", {"roulis": 0.0, "tangage": 0.0, "rot": 0.0, "v": 0.0})
				suite.call()
		5:
			car.touch_brake = 0.0; car.touch_throttle = 1.0
			if dt == 300:
				shot.call("traverse_milieu")
			if dt >= 600:
				var e := Vector2(car.global_position.x + 8624.12, car.global_position.z - 1519.17)
				print("  [rails]    voiture à %.1f m au-delà de l'axe de la voie" % e.dot(Vector2(-0.831, 0.556)))
				var s2: Dictionary = get_meta("r_st2", {})
				if not s2.is_empty():
					print("  [rails] sur le ballast (axe ± 5 m) : %.0f à %.0f km/h, roulis %.1f°, tangage %.1f°, rotation %.0f°/s au plus" % [s2.vmin, s2.vmax,
						s2.roulis, s2.tangage, s2.rot])
				bilan.call("en travers de la voie, 5 s de plein gaz")
				shot.call("traverse")
				suite.call()
		6:
			car.touch_throttle = 0.0; car.touch_brake = 1.0
			if dt >= 60:
				poser.call(4864.97, 2905.77, 321.5, -1.0)          # voie de droite, 30 m avant le passage
				suite.call()
		7:
			car.touch_throttle = 0.0; car.touch_brake = 1.0
			if dt >= 300:
				shot.call("passage")
				var n := 0
				for k in rails.barrieres:
					n += rails.barrieres[k].size() / 2
				print("  [rails] passage à niveau : %d bras de barrière chargés" % n)
				set_meta("r_st", {"roulis": 0.0, "tangage": 0.0, "rot": 0.0, "v": 0.0})
				suite.call()
		8:
			car.touch_brake = 0.0; car.touch_throttle = 0.7
			var casses := 0
			for k in rails.barrieres:
				var ens: PackedVector3Array = rails.barrieres[k]
				for i in range(0, ens.size(), 2):
					if ens[i].y < -900.0:
						casses += 1
			if casses > 0 and not has_meta("r_casse"):
				set_meta("r_casse", t)
				print("  [rails] barrière défoncée à %.0f km/h" % car.kmh())
			if has_meta("r_casse") and t - int(get_meta("r_casse")) == 25:
				shot.call("casse")
			if dt >= 600 or (has_meta("r_casse") and t - int(get_meta("r_casse")) > 240):
				bilan.call("à travers le passage à niveau")
				print("  [rails] bras défoncés : %d" % casses)
				get_tree().quit()

## Hélicoptère des gendarmes (v7.12) : -- --drive-test --helico-test --drive-from=-10975,236,-1100,90. 3 étoiles, le
## joueur reste sur place : l'hélicoptère arrive (capture helico.png), le voit d'en haut ; puis il repart faire le plein.
func _helico_test() -> void:
	var gd = gendarmes
	var dire := func(x: String): print("  [hélico] " + x)
	DirAccess.make_dir_recursive_absolute("user://shots")
	while not Chargement.fini:
		await get_tree().process_frame
	Engine.max_physics_steps_per_frame = 16
	for k in 120:
		await get_tree().process_frame
	gd.infraction("explosion", car.global_position)
	gd._helico_t = 0.0
	var t := 0.0
	var cap := false
	while t < 40.0:
		car.frein_parking = true
		gd._renfort_t = 999.0                 # pas de renfort au sol : c'est l'hélicoptère qu'on regarde
		for g in gd.liste:
			if is_instance_valid(g):
				g.queue_free()
		gd.liste.clear()
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		var h = gd.helico
		if h == null or not is_instance_valid(h):
			continue
		var dh := Vector2(h.global_position.x - car.global_position.x, h.global_position.z - car.global_position.z).length()
		if fmod(t, 4.0) < get_physics_process_delta_time():
			dire.call("t %.0f s : hélicoptère à %.0f m (à l'horizontale), %.0f m au-dessus, voit le joueur %s, étoiles %d, %s" % [t, dh,
				h.global_position.y - car.global_position.y, str(h.voit(car.global_position)), gd.etoiles, gd._bandeau.text.replace("\n", " / ")])
		if not cap and dh < 90.0:
			cap = true
			var vue := Camera3D.new()
			add_child(vue)
			vue.global_position = h.global_position + Vector3(18, -10, 18)
			vue.look_at(h.global_position)
			vue.current = true
			for k in 3:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png("user://shots/helico.png")
			vue.queue_free()
			dire.call("capture helico.png")
			break
	dire.call("message radio : « %s »" % gd.message)
	if is_instance_valid(gd.helico):
		gd.helico.age = 999.0
		t = 0.0
		while t < 40.0 and is_instance_valid(gd.helico):
			car.frein_parking = true
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
		dire.call("parti faire le plein : %s après %.0f s ; message « %s »" % [str(not is_instance_valid(gd.helico)), t, gd.message])
	car.frein_parking = false
	print("  [hélico] FIN")
	get_tree().quit()

## Livreur de repas (#151) : -- --drive-test --livreur-test --drive-from=-10975,236,-1100,90. Trois livraisons,
## voiture posée sur la route au plus près du restaurant puis de l'adresse : 1) à l'heure ; 2) après deux chocs ;
## 3) en retard. Capture livreur.png à la première adresse.
func _livreur_test() -> void:
	var lv = livreur
	var dire := func(x: String): print("  [livreur] " + x)
	DirAccess.make_dir_recursive_absolute("user://shots")
	while not Chargement.fini:
		await get_tree().process_frame
	Engine.max_physics_steps_per_frame = 16
	for k in 120:
		await get_tree().process_frame
	if OS.get_cmdline_user_args().has("--livreur-nuit"):      # v7.10 : majoration de nuit
		set_time(3)
		for k in 30:
			await get_tree().process_frame
		dire.call("de nuit : tarif de nuit %s" % str(tarif_nuit()))
	var argent0: float = garage.argent
	dire.call("%d restaurants chargés" % lv.restos.size())
	activities._livreur_start()
	if not lv.actif:
		dire.call("ÉCHEC : tournée non démarrée")
		get_tree().quit()
		return
	var it = preload("res://scripts/itineraire.gd").new()
	var sur_route := func(q: Vector3) -> Vector3:
		var i: int = it.plus_proche(Vector2(q.x, q.z))
		var r := Vector3(it.nx[i], 0.0, it.nz[i])
		var h := Relief.hauteur(r)
		r.y = (h if is_finite(h) else car.global_position.y) + 0.6
		return r
	for k in lv.NB:
		dire.call("commande %d : %s (%s), à %.0f m" % [k + 1, lv.resto.nom, lv.resto_rue, Vector2(lv.resto.x - car.global_position.x, lv.resto.z - car.global_position.z).length()])
		var pr: Vector3 = lv.cible()
		await _teleport(pr + Vector3.UP * 0.6, 0.0)                     # point de la route devant le restaurant
		dire.call("  arrêt dans la rue à %.0f m du restaurant" % Vector2(pr.x - lv.resto.x, pr.z - lv.resto.z).length())
		var t := 0.0
		while lv.phase == "resto" and t < 10.0:
			car.frein_parking = true
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
		if lv.phase != "client":
			dire.call("ÉCHEC : commande %d non récupérée (phase %s, à %.0f m)" % [k + 1, lv.phase, car.global_position.distance_to(lv.cible())])
			break
		dire.call("  récupérée en %.1f s : livrer au %s, à %.0f m, délai %s" % [t, lv.adresse,
			Vector2(lv.dest.x - car.global_position.x, lv.dest.z - car.global_position.z).length(), lv._mmss(lv.delai)])
		if k == 1:                                  # deux chocs
			for c in 2:
				car.frein_parking = false
				car.linear_velocity = car.global_transform.basis.z * 8.0
				await get_tree().physics_frame
				car.linear_velocity = Vector3.ZERO
				var tc := 0.0
				while tc < 1.3:                       # au-delà du délai entre deux chocs comptés
					await get_tree().physics_frame
					tc += get_physics_process_delta_time()
			dire.call("  après deux chocs : repas %d %%" % int(lv.etat))
		if k == 2:
			lv.t = lv.delai + 15.0                    # en retard
		await _teleport(sur_route.call(lv.dest), 0.0)
		var n0: int = lv.n
		t = 0.0
		while lv.actif and lv.n == n0 and t < 10.0:
			car.frein_parking = true
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
			if k == 0 and t > 1.2 and t < 1.3:
				get_viewport().get_texture().get_image().save_png("user://shots/livreur.png")
		dire.call("  livraison %d : %s" % [k + 1, "faite" if lv.n > n0 or not lv.actif else "ÉCHEC (pas livrée : à %.1f m de l'adresse, %.1f km/h, repas %d %%)" % [
			Vector2(car.global_position.x - lv.dest.x, car.global_position.z - lv.dest.z).length(), car.kmh(), int(lv.etat)]])
	car.frein_parking = false
	dire.call("fin : actif %s, %d livrées, %d en retard, %d refusées, gain %.2f €, argent %+.2f €, statut « %s »" % [str(lv.actif),
		lv.livrees, lv.en_retard, lv.refusees, lv.gain, garage.argent - argent0, activities._status_l.text])
	print("  [livreur] FIN")
	get_tree().quit()

## Gendarmes (#150) : -- --drive-test --gendarmes-test --drive-from=-10975,236,-1100,90 (en ville). 1) patrouille
## posée 30 m derrière le joueur, qui accélère à fond sur sa voie : excès de vitesse vu, poursuite ; 2) le joueur
## s'arrête : le gendarme arrive (capture gendarmes.png), arrestation et amende ; 3) nouvelle infraction (gendarme
## embouti), le joueur est téléporté à 700 m : les gendarmes cherchent où il a été vu, semés au bout de 20 s.
func _gendarmes_test() -> void:
	var gd = gendarmes
	var ci = circulation
	var dire := func(x: String): print("  [gendarmes] " + x)
	DirAccess.make_dir_recursive_absolute("user://shots")
	while not Chargement.fini:
		await get_tree().process_frame
	Engine.max_physics_steps_per_frame = 16
	ci.set_densite(1)
	for k in 120:
		await get_tree().process_frame
	var nom_capture := "gendarmes"
	if OS.get_cmdline_user_args().has("--gendarmes-nuit"):      # de nuit : gyrophares et lueur bleue
		set_time(3)
		nom_capture = "gendarmes_nuit"
		for k in 60:
			await get_tree().process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://shots/%s.png" % nom_capture))
	var argent0: float = garage.argent
	var p0 := car.global_position
	dire.call("vitesse autorisée ici : %.0f km/h, permis : %s" % [ci.limite(p0), str(gd._permis())])
	# rue limitée à 50 km/h, la plus droite des longues voies à moins de 400 m (140 m droit devant)
	var voie := -1
	var meilleur := INF
	var c0 := Vector2i(floori(p0.x / ci.CASE), floori(p0.z / ci.CASE))
	for dx in range(-3, 4):
		for dz in range(-3, 4):
			for k: int in ci._grille.get(c0 + Vector2i(dx, dz), PackedInt32Array()):
				if ci._v[k] * 3.6 > 55.0 or ci._longueur(k << 1) < 170.0:
					continue
				var a: Vector3 = ci._geo(k << 1, 20.0, 0)[0]
				var b: Vector3 = ci._geo(k << 1, 160.0, 0)[0]
				var ecart := 140.0 - Vector2(b.x - a.x, b.z - a.z).length()      # sinueuse : plus courte à vol d'oiseau
				var sc := ecart * 10.0 + a.distance_to(p0) * 0.1
				if a.distance_to(p0) < 400.0 and sc < meilleur:
					meilleur = sc; voie = k << 1
	if voie < 0:
		dire.call("ÉCHEC : aucune longue rue à 50 km/h ici")
		get_tree().quit()
		return
	var sa := 30.0
	var gj: Array = ci._geo(voie, sa, 0)
	var gg: Array = ci._geo(voie, sa - 30.0, 0)
	await _teleport((gj[0] as Vector3) + Vector3.UP * 0.6, rad_to_deg(atan2(gj[1].x, -gj[1].y)))
	for k in 30:
		await get_tree().physics_frame
	var g = preload("res://scripts/gendarme.gd").new()
	g.main = self
	gd.add_child(g)
	gd.liste.append(g)
	g.poser(Vector2(gg[0].x, gg[0].z), Vector2(gj[0].x, gj[0].z))
	g._degeler()
	dire.call("voie %d (%.0f m), joueur à %.0f m de son début, patrouille 30 m derrière ; limite %.0f km/h" % [voie, ci._longueur(voie), sa, ci.limite(car.global_position)])
	# 1) pleins gaz sur la voie (volant : point de la voie 15 m devant)
	var t := 0.0
	var s := sa
	while t < 12.0 and gd.etoiles == 0:
		s = minf(s + maxf(car.forward_speed(), 3.0) * get_physics_process_delta_time(), ci._longueur(voie) - 1.0)
		var c: Array = ci._geo(voie, minf(s + 15.0, ci._longueur(voie) - 0.5), 0)
		var l: Vector3 = car.global_transform.affine_inverse() * (c[0] as Vector3)
		car.touch_steer = clampf(atan2(l.x, l.z) * 2.0, -1.0, 1.0)
		car.touch_throttle = 1.0
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if fmod(t, 1.0) < get_physics_process_delta_time():
			dire.call("  t %.0f s : %.0f km/h (limite %.0f), s %.0f m, gendarmes %d%s" % [t, car.kmh(), ci.limite(car.global_position), s,
				gd.liste.size(), (", le premier à %.0f m (%s%s)" % [gd.liste[0].voiture.global_position.distance_to(car.global_position),
				gd.liste[0].mode, ", en vue" if gd.liste[0].en_vue(gd.liste[0].voiture.global_position, car.global_position) else ", caché par " + gd.liste[0].obstacle]) if not gd.liste.is_empty() else ""])
	car.touch_throttle = 0.0
	car.touch_steer = 0.0
	if not is_instance_valid(g):
		g = gd.liste[0] if not gd.liste.is_empty() else null
	dire.call("après %.1f s : %.0f km/h, %d étoile(s), infraction « %s », gendarme %s à %.0f m" % [t, car.kmh(), gd.etoiles, gd.dernier,
		g.mode if g else "-", g.voiture.global_position.distance_to(car.global_position) if g else INF])
	if gd.etoiles == 0:
		dire.call("ÉCHEC : excès de vitesse non relevé")
	# 2) arrêt : le gendarme arrive, arrestation
	t = 0.0
	var cap := false
	var arr0: int = gd.arrestations
	while t < 45.0 and gd.arrestations == arr0:
		car.touch_brake = 1.0 if car.forward_speed() > 0.5 else 0.0     # à l'arrêt, le frein serait la marche arrière
		car.frein_parking = car.forward_speed() <= 0.5
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if not is_instance_valid(g) and not gd.liste.is_empty():
			g = gd.liste[0]
		var d: float = g.voiture.global_position.distance_to(car.global_position) if is_instance_valid(g) else INF
		if fmod(t, 2.0) < get_physics_process_delta_time():
			dire.call("  t %.0f s : gendarme à %.0f m, %.0f km/h, %s%s%s, étoiles %d, %s" % [t, d,
				g.voiture.kmh() if is_instance_valid(g) else 0.0, g.mode if is_instance_valid(g) else "-",
				" figé" if is_instance_valid(g) and g.fige else "", " direct" if is_instance_valid(g) and g.direct else "",
				gd.etoiles, gd._bandeau.text.replace("\n", " / ")])
		if not cap and d < 14.0:
			cap = true
						# caméra derrière le gendarme, dans l'axe de la rue, en hauteur
			var mil: Vector3 = (car.global_position + g.voiture.global_position) * 0.5
			var ax: Vector3 = (g.voiture.global_position - car.global_position).normalized()
			var vue := Camera3D.new()
			add_child(vue)
			vue.global_position = g.voiture.global_position + ax * 9.0 + Vector3.UP * 5.0
			vue.look_at(mil + Vector3.UP * 0.8)
			vue.current = true
			for k in 4:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png("user://shots/%s.png" % nom_capture)
			vue.queue_free()
			dire.call("capture %s.png (gendarme à %.0f m, lueur %.1f)" % [nom_capture, d, g._lueur.light_energy])
	car.touch_brake = 0.0
	car.frein_parking = false
	dire.call("message radio : « %s »" % gd.message)
	dire.call("arrestation : %s après %.0f s, argent %+.2f €" % [str(gd.arrestations > arr0), t, garage.argent - argent0])
	# 3) gendarme embouti, téléportation loin : semés
	for k in 60:
		await get_tree().physics_frame
	var g2 = null
	for x in gd.liste:
		if is_instance_valid(x) and not x.blown:
			g2 = x
	if g2 == null:
		gd._apparaitre("patrouille")
		g2 = gd.liste[gd.liste.size() - 1] if not gd.liste.is_empty() else null
	gd.infraction("gendarme", car.global_position)
	dire.call("gendarme embouti : %d étoile(s)" % gd.etoiles)
	var loin := car.global_position + Vector3(700, 0, 0)
	var h := Relief.hauteur(loin)
	await _teleport(Vector3(loin.x, (h if is_finite(h) else car.global_position.y) + 1.0, loin.z), 0.0)
	var sem0: int = gd.semes
	t = 0.0
	while t < 40.0 and gd.semes == sem0:
		car.touch_brake = 1.0 if car.forward_speed() > 0.5 else 0.0     # à l'arrêt, le frein serait la marche arrière
		car.frein_parking = car.forward_speed() <= 0.5
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if fmod(t, 4.0) < get_physics_process_delta_time():
			dire.call("  t %.0f s : %d gendarme(s), étoiles %d, %s" % [t, gd.liste.size(), gd.etoiles, gd._bandeau.text.replace("\n", " / ")])
	dire.call("message radio : « %s »" % gd.message)
	dire.call("semés : %s après %.0f s, argent %+.2f € depuis le début" % [str(gd.semes > sem0), t, garage.argent - argent0])
	# 4) à pied : on descend pendant une poursuite, elle continue ; le gendarme vient, arrestation
	for k in 30:
		await get_tree().physics_frame
	var pt: Array = ci._geo(voie, sa + 60.0, 0)
	await _teleport((pt[0] as Vector3) + Vector3.UP * 0.6, rad_to_deg(atan2(pt[1].x, -pt[1].y)))
	for k in 30:
		await get_tree().physics_frame
	var g3 = preload("res://scripts/gendarme.gd").new()
	g3.main = self
	gd.add_child(g3)
	gd.liste.append(g3)
	var pg: Array = ci._geo(voie, sa + 20.0, 0)
	g3.poser(Vector2(pg[0].x, pg[0].z), Vector2(pt[0].x, pt[0].z))
	g3._degeler()
	gd.infraction("gendarme", car.global_position)
	pied.sortir()
	var arr1: int = gd.arrestations
	t = 0.0
	while t < 40.0 and gd.arrestations == arr1:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if fmod(t, 3.0) < get_physics_process_delta_time():
			dire.call("  à pied, t %.0f s : à pied %s, étoiles %d, gendarme à %.0f m, %s" % [t, str(pied.actif), gd.etoiles,
				g3.voiture.global_position.distance_to(pied.corps.global_position) if is_instance_valid(g3) else INF, gd._bandeau.text.replace("\n", " / ")])
	dire.call("à pied : arrestation %s après %.0f s" % [str(gd.arrestations > arr1), t])
	# 5) barrage à 3 étoiles : joueur lancé sur la rue, deux voitures en travers 230 m devant
	pied.monter()
	for k in 30:
		await get_tree().physics_frame
	await _teleport((gj[0] as Vector3) + Vector3.UP * 0.6, rad_to_deg(atan2(gj[1].x, -gj[1].y)))
	for k in 30:
		await get_tree().physics_frame
	gd._infr_t = 0.0
	gd.infraction("explosion", car.global_position)
	car.linear_velocity = car.global_transform.basis.z * 16.0
	gd._barrage_t = 0.0
	var b0: int = gd.barrages
	gd._barrer(0.0, car, car.global_position)
	var bar: Array = gd.liste.filter(func(x): return is_instance_valid(x) and x.mode == "barrage")
	dire.call("barrage : %s, %d voiture(s), %d étoile(s)" % [str(gd.barrages > b0), bar.size(), gd.etoiles])
	if bar.size() == 2:
		var q: Vector3 = gd.dernier_barrage[0]
		var t2: Vector2 = gd.dernier_barrage[1]
		var route := Vector3(t2.x, 0.0, t2.y)
		for x in bar:
			var f: Vector3 = x.voiture.global_transform.basis.z
			dire.call("  voiture à %.0f m du joueur, %.1f m du milieu de la chaussée, en travers à %.0f° de la route" % [
				x.voiture.global_position.distance_to(car.global_position), Vector2(x.voiture.global_position.x - q.x, x.voiture.global_position.z - q.z).length(),
				rad_to_deg(acos(clampf(absf(f.dot(route)), 0.0, 1.0)))])
		# vue de la route en amont du barrage, puis le joueur arrive : les voitures se lancent
		var vue := Camera3D.new()
		add_child(vue)
		vue.global_position = q - route * 22.0 + Vector3.UP * 5.0
		vue.look_at(q + Vector3.UP * 0.8)
		vue.current = true
		var avant: Vector3 = q - route * 18.0
		var ha := Relief.hauteur(avant)
		await _teleport(Vector3(avant.x, (ha if is_finite(ha) else q.y) + 0.6, avant.z), rad_to_deg(atan2(route.x, -route.z)))
		vue.current = true
		for k in 24:
			car.frein_parking = true
			await get_tree().physics_frame
		get_viewport().get_texture().get_image().save_png("user://shots/gendarmes_barrage.png")
		vue.queue_free()
		dire.call("capture gendarmes_barrage.png ; modes après l'arrivée du joueur : %s" % ", ".join(bar.map(func(x): return x.mode if is_instance_valid(x) else "-")))
		dire.call("message radio : « %s »" % gd.message)
	car.frein_parking = false
	print("  [gendarmes] fin : arrestations %d, semés %d" % [gd.arrestations, gd.semes])
	get_tree().quit()

## Ligne de bus du joueur (#148) : -- --drive-test --ligne-bus-test --drive-from=-10975,236,-1100,90 (--fixed-fps 8
## conseillé) : Activités > « Prendre une ligne de bus » ; le bus accélère 6 s (vitesse relevée) ; puis, arrêt par
## arrêt : bus posé 40 m en amont sur la voie qui longe l'arrêt, conduit tout seul jusqu'à la porte au poteau
## (braquage vers la voie, freinage), portes, voyageurs ; capture au 2e arrêt ; au terminus : recette, voiture rendue.
const PORTE_BUS_Z := 3.9          # ligne_bus.gd PORTE.z : porte avant à 3,9 m devant le milieu du bus
const LB := preload("res://scripts/ligne_bus.gd")
func _ligne_bus_test() -> void:
	var lb = ligne_bus
	var ci = circulation
	var dire := func(x: String): print("  [ligne] " + x)
	DirAccess.make_dir_recursive_absolute("user://shots")
	while not Chargement.fini:
		await get_tree().process_frame
	Engine.max_physics_steps_per_frame = 16
	ci.set_densite(0)
	pietons.set_densite(2)
	for k in 120:
		await get_tree().process_frame
	var argent0: float = garage.argent
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://shots/ligne_bus.png"))
	dire.call("voiture avant : %s" % car.voiture)
	activities._bus_start()
	if not lb.actif:
		dire.call("ÉCHEC : ligne non démarrée")
		get_tree().quit()
		return
	dire.call("%s" % (lb.ligne if lb.ligne != "" else "ligne de proche en proche (secours)"))
	dire.call("ligne de %d arrêts : %s" % [lb.arrets.size(), ", ".join(range(lb.arrets.size()).map(func(k): return "%s (%s)" % [lb.noms[k], lb._mmss(lb.horaires[k])]))])
	dire.call("véhicule : %s, %.0f kg, gabarit %s, %d roues" % [car.voiture, car.mass, str(car.gabarit), car.wheels.size()])
	# accélération (ligne en pause : le premier arrêt n'est pas franchi pendant ce temps)
	activities.mode = ""
	var t := 0.0
	while t < 6.0:
		car.touch_throttle = 1.0
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	dire.call("pleins gaz 6 s : %.0f km/h" % car.kmh())
	car.touch_throttle = 0.0
	activities.mode = "bus"
	var cam := Camera3D.new()
	add_child(cam)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ligne-arret="):                # essai d'un seul arrêt (numéro de 1 à 6)
			lb.i = clampi(int(a.get_slice("=", 1)) - 1, 0, lb.arrets.size() - 1)
			lb._viser()
	var essais_arret := 0
	while lb.actif and essais_arret < 10:
		essais_arret += 1
		var k: int = lb.i
		var q: Vector3 = lb.arrets[k]
		var recul := 40.0
		var va: Array = ci.voie_arret(q, 0.0)            # voie la plus proche ; arrêt près de son début : posé plus près
		if not va.is_empty():
			recul = clampf(float(va[1]) - 2.0, 8.0, 40.0)
		if va.is_empty():
			dire.call("arrêt %d : aucune voie le long, sauté" % (k + 1))
			lb.i += 1
			if lb.i >= lb.arrets.size():
				lb._fin()
			else:
				lb._viser()
			continue
		var voie: int = va[0]
		var sa: float = va[1]
		var gq: Array = ci._geo(voie, sa, 0)
		dire.call("  arrêt %d : voie %d, à %.0f m de son début (longueur %.0f), recul %.0f, écart du poteau à la voie %.1f m" % [k + 1, voie, sa,
			ci._longueur(voie), recul, Vector2(q.x - gq[0].x, q.z - gq[0].z).length()])
		var g0: Array = ci._geo(voie, sa - recul, 0)
		var p0: Vector3 = g0[0]
		await _teleport(p0 + Vector3.UP * 0.6, rad_to_deg(atan2(g0[1].x, -g0[1].y)))
		for f in 30:
			await get_tree().physics_frame
		lb._peuple = -1                                  # repeuplé après la téléportation (pietons.vider)
		var t0: float = lb.t
		t = 0.0
		var fini := false
		if OS.get_cmdline_user_args().has("--ligne-libre"):   # personne à prendre ni à déposer : le bus passe
			lb._demande = false
			lb._attendent = 0
		var libre: bool = not lb._demande and lb._attendent == 0
		if libre:
			dire.call("arrêt %d %s : personne à prendre ni à déposer, le bus passe sans s'arrêter" % [k + 1, lb.noms[k]])
		while t < 60.0 and lb.actif and lb.i == k and lb.phase == "route":
			var s_vise := minf(sa + 16.0, ci._longueur(voie) - 0.5) if libre else sa - PORTE_BUS_Z
			var gc: Array = ci._geo(voie, s_vise, 0)
			var cible: Vector3 = gc[0]
			var fwd := car.global_transform.basis.z
			var vers := cible - car.global_position
			vers.y = 0.0
			var reste := vers.dot(Vector3(gc[1].x, 0.0, gc[1].y))
			var gp: Array = ci._geo(voie, minf(s_vise, sa - recul + t * 8.0 + 12.0), 0)
			var vise: Vector3 = (gp[0] as Vector3) - car.global_position
			car.touch_steer = clampf(fwd.cross(vise.normalized()).y * 2.5, -1.0, 1.0)
			var v := car.linear_velocity.length()
			if libre and car.kmh() < 28.0:
				car.touch_throttle = 1.0; car.touch_brake = 0.0
			elif reste > v * v / 6.0 + 1.0 and car.kmh() < 22.0:
				car.touch_throttle = 1.0 if car.kmh() < 8.0 else 0.6; car.touch_brake = 0.0
			elif car.kmh() > 2.0:
				car.touch_throttle = 0.0; car.touch_brake = 1.0
			else:
				car.touch_throttle = 0.0; car.touch_brake = 0.0
				car.hold(0.3)
			await get_tree().physics_frame
			var t_av := t
			t += get_physics_process_delta_time()
			if t >= 8.0 and t_av < 8.0 and reste > recul - PORTE_BUS_Z - 4.0:
				# bloqué depuis la pose : ce que touche la caisse, puis reposé plus près
				var q3 := PhysicsShapeQueryParameters3D.new()
				var bx := BoxShape3D.new()
				bx.size = Vector3(car.gabarit.x * 0.95, 1.4, car.gabarit.z * 0.95)
				q3.shape = bx
				q3.transform = car.global_transform.translated(Vector3.UP * 1.3)
				q3.exclude = [car.get_rid()]
				var touches := []
				for h in get_world_3d().direct_space_state.intersect_shape(q3, 8):
					var o: Object = h.collider
					touches.append("%s%s" % [o.name if o is Node else str(o), " (" + str((o as Node).get_meta("matiere")) + ")" if o is Node and (o as Node).has_meta("matiere") else ""])
				dire.call("  bloqué après 8 s (%.1f m parcourus) ; la caisse touche : %s" % [recul - PORTE_BUS_Z - reste, ", ".join(touches) if touches.size() > 0 else "rien"])
				var rs := []
				for w: VehicleWheel3D in car.wheels:
					rs.append("%s %s, force %.0f" % [w.name, ("au sol %.2f m sous l'axe" % (w.global_position.y - w.get_contact_point().y)) if w.is_in_contact() else "en l'air", w.engine_force])
				dire.call("  roues : %s ; vitesse %s, endormi %s, figé %s, tenu %.2f s, sol relief %.1f m (caisse %.1f m)" % ["; ".join(rs),
					str(car.linear_velocity.snapped(Vector3.ONE * 0.01)), car.sleeping, car.freeze, float(car.get("_hold_t")),
					Relief.hauteur(car.global_position) if relief else -1.0, car.global_position.y])
			if int(t / 10.0) != int(t_av / 10.0):
				dire.call("  t=%.0f s : %.1f km/h, reste %.1f m, gaz %.1f, frein %.1f, volant %.2f, position %s" % [t, car.kmh(), reste,
					car.touch_throttle, car.touch_brake, car.touch_steer, str(car.global_position.snapped(Vector3.ONE * 0.1))])
		car.touch_throttle = 0.0; car.touch_brake = 0.0; car.touch_steer = 0.0
		if lb.phase == "portes" and lb.i == k:
			var porte: Vector3 = car.global_transform * LB.PORTE
			var montent := 0
			for c in pietons.passants:
				if c.has("monte"):
					montent += 1
			dire.call("  attendaient (tirés) %d, arrêt demandé %s (sonnette %s) ; passants qui vont à la porte %d" % [lb._attendent, lb._demande,
				"entendue" if lb._sonne else "non", montent])
			dire.call("arrêt %d %s : portes ouvertes en %.1f s, porte à %.1f m du poteau ; %d à bord, recette %.2f €, primes %.2f €" % [
				k + 1, lb.noms[k], lb.t - t0, Vector2(porte.x - q.x, porte.z - q.z).length(), lb.voyageurs, lb.recette, lb.primes])
			if not FileAccess.file_exists("user://shots/ligne_bus.png") and k >= 1:
				var droite := -car.global_transform.basis.x
				cam.global_position = car.global_position + droite * 9.0 + car.global_transform.basis.z * 9.0 + Vector3.UP * 3.0
				cam.look_at(car.global_position + car.global_transform.basis.z * 3.5 + Vector3.UP * 1.2)
				cam.current = true
				for f in 24:
					await get_tree().process_frame
				get_viewport().get_texture().get_image().save_png("user://shots/ligne_bus.png")
				cam_rig.cam.current = true
				dire.call("capture ligne_bus.png")
			while lb.actif and lb.i == k:
				car.hold(0.3)
				await get_tree().physics_frame
			dire.call("  voyageurs montés : %d au total, %d à bord" % [lb.transportes, lb.voyageurs])
		elif libre and lb.i != k:
			dire.call("  arrêt %d desservi en passant (%.0f km/h), primes %.2f €" % [k + 1, car.kmh(), lb.primes])
		elif lb.actif:
			var porte2: Vector3 = car.global_transform * LB.PORTE
			dire.call("arrêt %d : portes NON ouvertes en 60 s (porte à %.1f m du poteau, %.0f km/h, phase %s)" % [k + 1,
				Vector2(porte2.x - q.x, porte2.z - q.z).length(), car.kmh(), lb.phase])
			lb.i += 1
			if lb.i >= lb.arrets.size():
				lb._fin()
			else:
				lb._viser()
	for f in 30:
		await get_tree().physics_frame
	dire.call("fin : ligne active %s, voiture %s, argent +%.2f €, statut « %s »" % [lb.actif, car.voiture,
		garage.argent - argent0, activities._status_l.text.replace("\n", " / ") if activities._status_l else ""])
	dire.call("succès : lignes %d, voyageurs %d" % [int(succes.valeur("lignes_bus")), int(succes.valeur("voyageurs"))])
	dire.call("FIN")
	get_tree().quit()

## Bus aux arrêts (v7.01) : -- --drive-test --bus-test --drive-from=-10975,236,-1100,90 (--fixed-fps 8 conseillé) : à
## Bourgoin ; deux passants posés à l'arrêt le plus proche et un bus 70 m en amont (circulation.bus_vers_arret) ; suivi
## du bus toutes les 4 s ; 90 s ; arrêts marqués, passants montés et descendus ; capture du premier bus à l'arrêt.
func _bus_test() -> void:
	var ci = circulation
	var dire := func(x: String): print("  [bus] " + x)
	DirAccess.make_dir_recursive_absolute("user://shots")
	while not Chargement.fini:
		await get_tree().process_frame
	Engine.max_physics_steps_per_frame = 16
	ci.set_densite(3)
	ci.lourds_x = 8.0
	ci.vider()
	pietons.set_densite(3)
	var cam := Camera3D.new()
	add_child(cam)
	var t := 0.0
	var log_t := 0.0
	var pris := false
	var pose := false
	var suivi := -1
	var suivi_t := 0.0
	var vise := Vector3.ZERO
	while t < 90.0:
		if not pose and t > 3.0 and pietons.ok:
			# un bus posé en amont de l'arrêt le plus proche de la voiture (les lignes réelles passent rarement par là)
			pose = true
			var bd := INF
			var arret := Vector3.ZERO
			for q: Vector3 in pietons.arrets_bus():
				if q.distance_to(car.global_position) < bd:
					bd = q.distance_to(car.global_position)
					arret = q
			dire.call("passants posés à l'arrêt : %d" % pietons.peupler_arret(arret, 2))
			suivi = ci.bus_vers_arret(arret)
			vise = arret
			dire.call("arrêt visé à %.0f m de la voiture %s : bus posé n° %d" % [bd, str(arret), suivi])
		if suivi >= 0 and t >= suivi_t:
			suivi_t += 4.0
			var trouve := false
			for c in ci.voitures:
				if int(c.id) == suivi:
					trouve = true
					var rel: Vector3 = vise - (c.pos as Vector3)
					var dir: Vector3 = c.dir
					dire.call("  t=%.0f s bus n° %d : %.0f km/h, arrêt devant %.1f m, côté %.1f m, arret_d %.1f, attente %.1f s, leader « %s »" % [t, suivi,
						float(c.v) * 3.6, rel.dot(dir), rel.dot(dir.cross(Vector3.UP).normalized()), float(c.arret_d), float(c.arret_t), str(c.leader)])
			if not trouve:
				dire.call("  t=%.0f s bus n° %d disparu" % [t, suivi])
				suivi = -1
		car.hold(0.5)
		await get_tree().process_frame
		t += get_process_delta_time()
		if not pris:
			for c in ci.voitures:
				if int(c.m) == 3 and float(c.arret_t) > 5.0 and float(c.arret_t) < 6.5:
					pris = true
					var dir: Vector3 = c.dir
					var droite := dir.cross(Vector3.UP).normalized()
					cam.global_position = (c.pos as Vector3) + droite * 10.0 + dir * 9.0 + Vector3.UP * 2.2
					cam.look_at((c.pos as Vector3) + droite * 2.0 + dir * 3.0 + Vector3.UP * 1.2)
					cam.current = true
					for i in 3:
						await get_tree().process_frame
					get_viewport().get_texture().get_image().save_png("user://shots/bus_arret.png")
					cam_rig.cam.current = true
					dire.call("bus à l'arrêt en gros plan (encore %.1f s d'attente)" % float(c.arret_t))
					break
		if t >= log_t:
			log_t += 20.0
			var bus: Array = ci.voitures.filter(func(c): return int(c.m) == 3)
			dire.call("t=%3.0f s : %d bus (%s) ; arrêts de bus connus %d, arrêts marqués %d ; passants montés %d, descendus %d" % [t, bus.size(),
				", ".join(bus.map(func(c): return "%.0f km/h%s" % [float(c.v) * 3.6, " à l'arrêt" if float(c.arret_t) > 0.0 else ""])),
				ci._arrets.size(), ci.arrets_faits, pietons.montes, pietons.descendus])
			for c in bus:
				var bd := INF
				var info := ""
				for q: Vector3 in ci._arrets:
					var d: float = q.distance_to(c.pos)
					if d < bd:
						bd = d
						var dir: Vector3 = c.dir
						info = "devant %.1f m, côté %.1f m" % [(q - (c.pos as Vector3)).dot(dir), (q - (c.pos as Vector3)).dot(dir.cross(Vector3.UP).normalized())]
				dire.call("  bus %d : arrêt le plus proche à %.0f m (%s), arret_d %.1f" % [int(c.id), bd, info, float(c.arret_d)])
	dire.call("FIN")
	get_tree().quit()

## Véhicules lourds (v6.99, #136) : -- --drive-test --lourds-test [--drive-from=…] (--fixed-fps 8 conseillé) : circulation
## dense, tracteurs et bus trois fois plus fréquents (--lourds-x=…) ; la voiture du joueur arrêtée ; relevé toutes les 10 s (tracteurs et
## bus en scène, leur vitesse la plus haute, voitures en train d'en doubler une) ; gros plan du premier de chaque genre
## qui roule à moins de 150 m ; 60 s.
func _lourds_test() -> void:
	var ci = circulation
	var dire := func(x: String): print("  [lourds] " + x)
	DirAccess.make_dir_recursive_absolute("user://shots")
	while not Chargement.fini:
		await get_tree().process_frame
	Engine.max_physics_steps_per_frame = 16
	ci.set_densite(3)
	ci.lourds_x = 3.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lourds-x="):
			ci.lourds_x = float(a.get_slice("=", 1))
	ci.vider()
	dire.call("modèles présents : %s" % str(ci._dispo))
	for m in [2, 3]:
		dire.call("%s : %d roues tournantes, rayons %s m, centres %s" % [ci.MODELES[m], ci._roues_g[m].size(),
			str(ci._roues_g[m].map(func(r): return snappedf(float(r[1]), 0.01))),
			str(ci._roues_g[m].map(func(r): return (r[0] as Vector3).snapped(Vector3.ONE * 0.1)))])
	var cam := Camera3D.new()
	add_child(cam)
	var vus := {}
	var vmax := {2: 0.0, 3: 0.0}
	var doubles := 0
	var t := 0.0
	var log_t := 0.0
	while t < 60.0:
		car.hold(0.5)
		await get_tree().process_frame
		t += get_process_delta_time()
		var n := {0: 0, 1: 0, 2: 0, 3: 0}
		for c in ci.voitures:
			var m := int(c.m)
			n[m] += 1
			if m >= 2 and t > 3.0:
				vmax[m] = maxf(vmax[m], float(c.v) * 3.6)
				if not vus.has(m) and t > 5.0 and (c.pos as Vector3).distance_to(car.global_position) < 150.0 and float(c.v) > 2.0:
					vus[m] = true
					var dir: Vector3 = c.dir
					var cote := dir.cross(Vector3.UP).normalized()
					cam.global_position = (c.pos as Vector3) + cote * 9.0 + dir * 6.0 + Vector3.UP * 2.6
					cam.look_at((c.pos as Vector3) + Vector3.UP * 1.3)
					cam.current = true
					for i in 3:
						await get_tree().process_frame
					get_viewport().get_texture().get_image().save_png("user://shots/lourd_%s.png" % ci.MODELES[m])
					var rg: Array = ci._roues_g[m][0] if not ci._roues_g[m].is_empty() else []
					if not rg.is_empty():
						dire.call("%s en gros plan à %.0f km/h : %.1f m parcourus, roue avant à %.0f° (%.1f tours)" % [ci.MODELES[m],
							float(c.v) * 3.6, float(c.dist), rad_to_deg(fmod(float(c.dist) / float(rg[1]), TAU)),
							float(c.dist) / float(rg[1]) / TAU])
					cam_rig.cam.current = true
			elif (c.dep as Array).size() > 0:
				doubles += 1
		if t >= log_t:
			log_t += 10.0
			dire.call("t=%2.0f s : %d voitures, %d tracteur(s), %d bus ; vitesse la plus haute : tracteur %.0f km/h, bus %.0f km/h ; voitures en dépassement (cumul d'images) %d" % [
				t, ci.voitures.size(), n[2], n[3], vmax[2], vmax[3], doubles])
	dire.call("gros plans : %s ; épaves %d" % [str(vus.keys().map(func(m): return ci.MODELES[m])), ci.epaves.size()])
	dire.call("FIN")
	get_tree().quit()

## Balade (v6.98) : -- --drive-test --balade-test [--duree=<s>] [--drive-from=…] (--fixed-fps 8 conseillé) : balade
## lancée comme depuis le menu ; relevé toutes les 15 s (lieu visé, vitesse, limitation de la route, plan) ; à la fin :
## lieux atteints, distance, vitesse moyenne, temps au-dessus de la limitation (+10 km/h), explosions, arrêts aux feux
## rouges (et passages au rouge : voiture à plus de 15 km/h sur le point d'arrêt d'un feu rouge), plans vus ;
## capture de chaque plan ; puis un toucher au milieu de l'écran rend la main. --balade-feu : le premier feu du trajet
## passe au rouge quand la voiture en est à 60 m (horloge des feux avancée) ; arrêt, attente et départ au vert relevés.
func _balade_test() -> void:
	var dire := func(x: String): print("  [balade] " + x)
	DirAccess.make_dir_recursive_absolute("user://shots")
	var duree := 240.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--duree="):
			duree = float(a.get_slice("=", 1))
	while not Chargement.fini:
		await get_tree().process_frame
	Engine.max_physics_steps_per_frame = 16
	var b = balade
	var hud_n = get_node("HUD")
	if OS.get_cmdline_user_args().has("--balade-feu"):
		# départ 150 m avant un feu de la circulation (arrivée d'arc à feu la plus proche, sur un arc assez long), arrivée
		# 250 m après le nœud, dans le prolongement
		var circ = circulation
		var meilleur := -1
		var md := INF
		for k in circ._a.size():
			if circ._feu_b[k] < 0 or circ._np[k] < 2:
				continue
			var n: int = circ._b[k]
			var pa: int = circ._p0[k]
			var lg := Vector2(circ._P[pa * 3], circ._P[pa * 3 + 2]).distance_to(Vector2(circ._nx[n], circ._nz[n]))
			var dn := Vector2(circ._nx[n], circ._nz[n]).distance_to(Vector2(car.global_position.x, car.global_position.z))
			if lg > 160.0 and dn < md:
				md = dn
				meilleur = k
		if meilleur >= 0:
			var n: int = circ._b[meilleur]
			var q := Vector2(circ._nx[n], circ._nz[n])
			var pa: int = circ._p0[meilleur]
			var depart := Vector2(circ._P[pa * 3], circ._P[pa * 3 + 2])
			var dir := (q - depart).normalized()
			var p0 := q - dir * 150.0
			var y := preload("res://scripts/relief.gd").hauteur(Vector3(p0.x, 0.0, p0.y))
			car.place(Vector3(p0.x, y + 1.0, p0.y), rad_to_deg(atan2(dir.x, -dir.y)))   # cap : 0 au nord (-Z), sens horaire
			car.hold(1.0)
			for i in 40:
				await get_tree().process_frame
			b.destination = q + dir * 250.0
			dire.call("feu d'essai : arc %d, nœud à (%.0f, %.0f), départ 150 m avant" % [meilleur, q.x, q.y])
	activities._balade_start()
	var t := 0.0
	var dist := 0.0
	var p_prec := car.global_position
	var au_dessus := 0.0
	var mesure := 0.0
	var vmax := 0.0
	var boums := 0
	var au_rouge := 0
	var blown := false
	var pris := {}
	var plan_prec := -1
	var plan_t0 := 0.0
	var log_t := 0.0
	var feu_force := []                     # --balade-feu : [point d'arrêt, code] du feu mis au rouge
	var feu_arret_t := -1.0
	var feu_d_min := INF
	var feu_vert_t := -1.0
	var feu_fin := false
	var Env := preload("res://scripts/env.gd")
	while t < duree and not feu_fin:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		t += dt
		var p := car.global_position
		if p.distance_to(p_prec) < 30.0:
			dist += p.distance_to(p_prec)
		p_prec = p
		var kmh := absf(car.forward_speed()) * 3.6
		vmax = maxf(vmax, kmh)
		var lim := int(hud_n.get("_limit"))
		if b._pilote_parti and lim > 0:
			mesure += dt
			if kmh > float(lim) + 10.0:
				au_dessus += dt
		for f in b._feux:
			var dfeu: float = b._pilote._s[int(f[0])] - b._pilote.s if is_instance_valid(b._pilote) else 99.0
			if absf(dfeu) < 1.0 and kmh > 15.0 and circulation._etat_feu(int(f[1])) == 2:
				au_rouge += 1
		if OS.get_cmdline_user_args().has("--balade-feu") and is_instance_valid(b._pilote) and b._pilote_parti:
			if feu_force.is_empty():
				for f in b._feux:
					var df: float = b._pilote._s[int(f[0])] - b._pilote.s
					if df > 40.0 and df < 60.0:
						feu_force = f
						# rouge pendant encore 29 s : phase du feu à 31 s de son cycle de 60 s
						var code: int = int(f[1])
						Env._t_feux = fposmod(31.0 - float(code >> 1) - (30.0 if code & 1 else 0.0), 600.0)
						dire.call("feu mis au rouge à %.0f m (état %d)" % [df, circulation._etat_feu(code)])
						break
			else:
				var dfo: float = b._pilote._s[int(feu_force[0])] - b._pilote.s
				var etat_f: int = circulation._etat_feu(int(feu_force[1]))
				if etat_f == 2 and dfo > -5.0 and feu_vert_t < 0.0:
					feu_d_min = minf(feu_d_min, dfo)
					if kmh < 3.0 and feu_arret_t < 0.0:
						feu_arret_t = t
						dire.call("arrêt au rouge à %.1f m du point d'arrêt" % dfo)
				elif feu_arret_t >= 0.0 and feu_vert_t < 0.0:
					feu_vert_t = t
				if feu_vert_t >= 0.0 and t - feu_vert_t > 6.0:
					dire.call("feu forcé : arrêté %.0f s au rouge, au plus près %.1f m du point d'arrêt ; 6 s après le vert : %.0f km/h, %.0f m après le point d'arrêt" % [
						feu_vert_t - feu_arret_t, feu_d_min, kmh, -dfo])
					feu_fin = true
		if car.blown and not blown:
			boums += 1
		blown = car.blown
		if b._plan != plan_prec:
			plan_prec = b._plan
			plan_t0 = t
		var nom_plan: String = b.PLANS[b._plan]
		if not pris.has(nom_plan) and t - plan_t0 > 2.0:
			pris[nom_plan] = true
			get_viewport().get_texture().get_image().save_png("user://shots/balade_%s.png" % nom_plan)
		if t >= log_t:
			log_t += 15.0
			var raison := ""
			if kmh < 3.0 and is_instance_valid(b._pilote) and b._pilote_parti:
				raison = " ; arrêt : %s, feu au rouge %s, profil %.1f m/s" % [b._pilote.suivie, str(b._arrete_feu),
					float(b._pilote._au(b._pilote.s + 4.0)[2])]
			if is_instance_valid(b._pilote):
				b._pilote.suivie = ""
			dire.call("t=%3.0f s : vers %s, %3.0f km/h (limitation %d), plan %s, lieux atteints %d, commandes %s%s" % [t, b.lieu,
				kmh, lim, nom_plan, b.lieux, "visibles" if hud_n.buttons[0].visible else "cachées", raison])
	dire.call("bilan sur %.0f s : %d lieu(x) atteint(s), %.2f km, %.0f km/h de moyenne, %.0f km/h au plus ; au-dessus de la limitation (+10 km/h) %.0f %% du temps ; %d explosion(s) ; plans vus : %s" % [
		t, b.lieux, dist / 1000.0, dist / t * 3.6, vmax, 100.0 * au_dessus / maxf(mesure, 0.01), boums, ", ".join(b.plans_vus.keys())])
	dire.call("feux tricolores sur les trajets : %d ; arrêts au rouge : %d ; passages au rouge : %d" % [b._feux.size(), b.arrets_feu, au_rouge])
	var ev := InputEventScreenTouch.new()
	ev.pressed = true
	ev.position = get_viewport().get_visible_rect().size * 0.5
	Input.parse_input_event(ev)
	for i in 8:
		await get_tree().process_frame
	dire.call("après un toucher au milieu de l'écran : balade active %s, activité « %s », caméra du jeu %s, commandes visibles %s" % [
		str(b.actif), activities.mode, str(cam_rig.cam.current), str(hud_n.buttons[0].visible)])
	dire.call("FIN")
	get_tree().quit()

## Coût de la lumière (v6.97) : -- --drive-test --lumiere-perf : durée moyenne de _lumiere() (appelée chaque seconde
## dans le cycle jour et nuit et pendant les fondus de la météo), sur un plateau (rien ne change) et pendant une
## transition ; nombre de matériaux de l'ambiance (Env.mats).
func _lumiere_perf() -> void:
	var dire := func(x: String): print("  [lumière] " + x)
	while not Chargement.fini:
		await get_tree().process_frame
	for i in 30:
		await get_tree().process_frame
	var Env := preload("res://scripts/env.gd")
	dire.call("matériaux de l'ambiance : %d" % Env.mats.size())
	for cas in [["plateau de midi (12 h)", 12.0, 0.0], ["transition (16 h -> 17 h)", 16.0, 1.0 / 200.0]]:
		set_time(CYCLE, float(cas[1]))
		var t0 := Time.get_ticks_usec()
		for i in 200:
			heure += float(cas[2])
			_cycle_situer()
			_lumiere()
		dire.call("%s : %.0f µs par mise à jour" % [cas[0], float(Time.get_ticks_usec() - t0) / 200.0])
	# horloge du cockpit (vue conducteur) dans le cycle : 21 h 37 puis 7 h 05
	cam_rig.set_mode(1)
	for hh in [21.0 + 37.0 / 60.0, 7.0 + 5.0 / 60.0]:
		set_time(CYCLE, hh)
		for i in 40:
			car.hold(0.5)
			await get_tree().process_frame
		var n := "%02dh%02d" % [int(hh), int(round(fmod(hh, 1.0) * 60.0))]
		get_viewport().get_texture().get_image().save_png("user://shots/cockpit_%s.png" % n)
		dire.call("cockpit à %s : pénombre %.2f (nuit du jeu %.2f)" % [heure_texte(), cockpit._night() if cockpit else -1.0, _night])
	cam_rig.set_mode(0)
	set_time(0)
	dire.call("FIN")
	get_tree().quit()

## Arc-en-ciel (v6.96) : -- --drive-test --arc-test [--drive-from=…] (--fixed-fps 8 conseillé) : fin d'une averse
## (pluie -> couvert, fondu de 20 s) en fin d'après-midi (soleil à 24°) puis à midi (48° : l'arc reste sous l'horizon) ;
## caméra tournée à l'opposé du soleil, levée de 20° ; pixels nettement colorés (écart de plus de 0,12 entre la plus forte
## et la plus faible composante) dans les deux tiers du haut, au plus fort de l'arc, avec et sans lui (même image, arc
## coupé quelques images) ; captures ; puis la circulation dans le brouillard.
func _arc_test() -> void:
	var dire := func(x: String): print("  [arc] " + x)
	var shot := func(n: String):
		get_viewport().get_texture().get_image().save_png("user://shots/arc_%s.png" % n)
	DirAccess.make_dir_recursive_absolute("user://shots")
	while not Chargement.fini:
		await get_tree().process_frame
	var images := func(n: int):
		for i in n:
			car.hold(0.5)
			await get_tree().process_frame
	var couleur := func() -> int:
		var im := get_viewport().get_texture().get_image()
		var n := 0
		for y in im.get_height() * 2 / 3:
			for x in im.get_width():
				var c := im.get_pixel(x, y)
				if maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b)) > 0.12:
					n += 1
		return n
	var hud_n = get_node("HUD")
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 80.0
	hud_n.visible = false
	for moment in [1, 0]:
		set_weather(2)
		set_time(moment)
		var vers_soleil: Vector3 = _sun.global_transform.basis.z
		var oppose := Vector3(-vers_soleil.x, 0.0, -vers_soleil.z).normalized()
		cam.global_position = car.global_position + Vector3.UP * 2.5
		cam.look_at(cam.global_position + oppose * cos(deg_to_rad(20.0)) + Vector3.UP * sin(deg_to_rad(20.0)))
		cam.current = true
		await images.call(30)
		meteo_vers(1, 20.0)
		var a_max := 0.0
		var avec := 0
		var sans := 0
		while _meteo_f < 1.0:
			await images.call(1)
			a_max = maxf(a_max, arc_en_ciel)
			if arc_en_ciel > 0.9 and avec == 0:
				await images.call(10)
				shot.call(TIMES[moment].to_lower().replace("è", "e").replace("-", "_"))
				avec = couleur.call()
				for m in [_sky_peint, _sky_day]:
					m.set_shader_parameter("arc", 0.0)
				await images.call(3)
				sans = couleur.call()
				for m in [_sky_peint, _sky_day]:
					m.set_shader_parameter("arc", arc_en_ciel)
		meteo_vitesse = 20.0                   # 3 min de jeu en 9 s
		await images.call(80)
		meteo_vitesse = 1.0
		dire.call("%s (soleil à %.0f°) : arc-en-ciel au plus %.2f ; pixels colorés au plus fort : %d avec l'arc, %d sans (même image) ; trois minutes après : arc %.2f" % [
			TIMES[moment], rad_to_deg(-_sun.rotation.x), a_max, avec, sans, arc_en_ciel])
	cam.current = false
	cam.queue_free()
	hud_n.visible = true
	# brouillard : circulation prudente comme sous la pluie
	for w in [0, 2, 3]:
		set_weather(w)
		await images.call(4)
		dire.call("%s : circulation, prudence %.2f (vitesse visée × %.2f)" % [WEATHERS[w], float(circulation._pluie),
			lerpf(1.0, circulation.PLUIE_V, float(circulation._pluie))])
	# vue de jeu : la route vers l'arc-en-ciel
	set_weather(2)
	set_time(1)
	await images.call(20)
	meteo_vers(1, 20.0)
	while arc_en_ciel < 0.95:
		await images.call(1)
	await images.call(10)
	shot.call("route")
	set_weather(0)
	set_time(0)
	dire.call("FIN")
	get_tree().quit()

## Orage et bulletin (v6.94) : -- --drive-test --orage-test [--drive-from=…] (--fixed-fps 8 conseillé) : textes du
## bulletin météo dans plusieurs situations et flash composé par la radio ; éclairs déclenchés par la boucle de pluie
## (position du son à chaque éclair, contre les coups de tonnerre relevés) ; lueur d'un éclair image par image (temps
## ralenti ×0,1), captures avant et pendant.
func _orage_test() -> void:
	var dire := func(x: String): print("  [orage] " + x)
	var shot := func(n: String):
		get_viewport().get_texture().get_image().save_png("user://shots/orage_%s.png" % n)
	DirAccess.make_dir_recursive_absolute("user://shots")
	while not Chargement.fini:
		await get_tree().process_frame
	var lum := func() -> float:
		var im := get_viewport().get_texture().get_image()
		im.resize(96, 54, Image.INTERPOLATE_BILINEAR)
		var t := 0.0
		for y in 54:
			for x in 96:
				t += im.get_pixel(x, y).get_luminance()
		return t / (96.0 * 54.0) * 255.0
	var images := func(n: int):
		for i in n:
			car.hold(0.5)
			await get_tree().process_frame
	# bulletin
	set_weather(0)
	set_time(0)
	dire.call("bulletin (midi, beau temps fixe) : " + bulletin_meteo())
	set_time(3)
	dire.call("bulletin (nuit, beau temps fixe) : " + bulletin_meteo())
	set_time(CYCLE, 14.1)
	set_weather(VARIABLE)
	for cas in [[0, 1, 200.0], [1, 2, 600.0], [2, 1, 1200.0], [3, 0, 100.0], [1, 0, 450.0]]:
		weather = int(cas[0])
		_meteo_de = weather
		_meteo_f = 1.0
		meteo_suivante = int(cas[1])
		_meteo_reste = float(cas[2])
		dire.call("bulletin (cycle, variable, %s puis %s dans %d s) : %s" % [WEATHERS[cas[0]], WEATHERS[cas[1]], int(cas[2]),
			bulletin_meteo()])
	if radio:
		radio.station = radio.stations.size() - 1
		radio._etape = 0
		radio._dernier_journal = Time.get_unix_time_from_system()
		radio._tune_infos()
		dire.call("radio, flash composé : « %s »" % radio.dernier_flash)
		radio.station = -1
		radio._player.stop()
	# météo variable : la prévision se réalise
	weather = 0
	_meteo_de = 0
	meteo_vers(0, 1.0)
	var prevu: int = meteo_suivante
	_meteo_reste = 0.5
	await images.call(30)
	dire.call("prévu : %s ; arrivé : %s" % [WEATHERS[prevu], WEATHERS[weather]])
	# éclairs déclenchés par la boucle de pluie
	set_weather(2)
	set_time(3)
	_wet = 1.0
	var vus := []
	var n0 := eclairs
	var att := 0
	while att < 900:
		att += 1
		await images.call(1)
		if eclairs > n0:
			vus.append("%.2f s" % rain.sound.get_playback_position())
			n0 = eclairs
		if att % 15 == 0:
			dire.call("pluie : son %s, position %.2f s, intensité %.2f" % [str(rain.sound.playing) if rain.sound else "absent",
				rain.sound.get_playback_position() if rain.sound else 0.0, rain.amount])
		if rain.sound and rain.sound.playing and rain.sound.get_playback_position() > 33.0:
			break
	dire.call("éclairs pendant les 33 premières secondes de la pluie : %d, aux positions du son %s (tonnerres à 15.3, 19.8, 22.35, 26.1, 30.85 s ; éclair 1 à 2,6 s avant)" % [
		vus.size(), ", ".join(vus)])
	# calage : la boucle de pluie parcourue à 30 images/s (deux tours), éclairs lancés et leur avance sur le tonnerre
	var vus2 := []
	var p0 := 0.0
	for i in 2 * 90 * 30:
		var p1 := fmod(float(i + 1) / 30.0, 90.0)
		for f in rain.eclairs_entre(p0, p1):
			vus2.append("%.2f s (force %.2f)" % [p1, f])
		p0 = p1
	dire.call("boucle de pluie à 30 images/s, deux tours : %d éclairs : %s" % [vus2.size(), ", ".join(vus2)])
	# lueur d'un éclair, image par image (temps ×0,1 : une image = 12,5 ms ; éclairs de la pluie coupés pendant la mesure)
	rain.main = null
	await images.call(20)
	var avant: float = lum.call()
	shot.call("avant")
	Engine.time_scale = 0.1
	await images.call(2)
	eclair(1.0)
	var courbe := []
	var pris := false
	for i in 48:
		await images.call(1)
		var l: float = lum.call()
		courbe.append("%.0f" % l)
		if not pris and _eclair_k > 0.8:
			pris = true
			shot.call("eclair")
	Engine.time_scale = 1.0
	rain.main = self
	dire.call("lueur d'un éclair (nuit, pluie), luminosité toutes les 12,5 ms : avant %.1f ; %s" % [avant, " ".join(courbe)])
	set_weather(0)
	set_time(0)
	dire.call("FIN")
	get_tree().quit()

## Nuit (v6.93) : -- --drive-test --nuit-test [--drive-from=…] (--fixed-fps 8 conseillé) : étoiles comptées (points
## lumineux du haut de l'image, caméra levée vers le ciel, interface cachée) de nuit par temps clair, par temps couvert,
## à midi et au crépuscule du cycle ; taximètre de jour et de nuit sur le même trajet ; tarif de nuit selon l'heure.
func _nuit_test() -> void:
	var dire := func(x: String): print("  [nuit] " + x)
	var shot := func(n: String):
		get_viewport().get_texture().get_image().save_png("user://shots/nuit_%s.png" % n)
	DirAccess.make_dir_recursive_absolute("user://shots")
	while not Chargement.fini:
		await get_tree().process_frame
	var images := func(n: int):
		for i in n:
			car.hold(0.5)
			await get_tree().process_frame
	# points lumineux : pixel clair nettement au-dessus de ses voisins à 2 pixels, dans les deux tiers du haut
	var etoiles_vues := func() -> int:
		var im := get_viewport().get_texture().get_image()
		var w := im.get_width()
		var h := im.get_height()
		var n := 0
		for y in range(2, h * 2 / 3):
			for x in range(2, w - 2):
				var l := im.get_pixel(x, y).get_luminance()
				if l < 0.22:
					continue
				var v := maxf(maxf(im.get_pixel(x - 2, y).get_luminance(), im.get_pixel(x + 2, y).get_luminance()),
					maxf(im.get_pixel(x, y - 2).get_luminance(), im.get_pixel(x, y + 2).get_luminance()))
				if l > v + 0.1:
					n += 1
		return n
	var hud_n = get_node("HUD")
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 70.0
	cam.global_position = car.global_position + Vector3.UP * 3.0
	cam.look_at(cam.global_position + Vector3(0.35, 0.8, -0.5))
	cam.current = true
	hud_n.visible = false
	set_weather(0)
	for cas in [["nuit claire", 3, 0, -1.0], ["nuit couverte", 3, 1, -1.0], ["midi", 0, 0, -1.0], ["cycle 19 h", CYCLE, 0, 19.0],
			["cycle 19 h 45", CYCLE, 0, 19.75], ["cycle 20 h 15", CYCLE, 0, 20.25], ["cycle 23 h", CYCLE, 0, 23.0]]:
		set_weather(int(cas[2]))
		set_time(int(cas[1]), float(cas[3]))
		await images.call(30)
		var n: int = etoiles_vues.call()
		dire.call("%s : %d étoiles vues" % [cas[0], n])
		if cas[0] == "nuit claire":
			shot.call("etoiles")
	set_weather(0)
	# vue de jeu, de nuit : la route sous les étoiles
	cam.current = false
	hud_n.visible = true
	set_time(3)
	await images.call(30)
	shot.call("route")
	cam.queue_free()
	# taximètre : 1 km à 72 km/h puis 1 min d'attente, de jour et de nuit
	var tx = preload("res://scripts/taximetre.gd").new()
	add_child(tx)
	for nuit in [false, true]:
		tx.nuit = nuit
		tx.demarrer()
		for i in 100:
			tx.compter(0.5, 10.0, 72.0)
		for i in 120:
			tx.compter(0.5, 0.0, 0.0)
		dire.call("taximètre %s : 1 km + 1 min d'attente = %.2f €" % ["TARIF 2 (nuit)" if nuit else "TARIF 1 (jour)", tx.montant])
	# nuit qui tombe pendant la course : 500 m de jour puis 500 m de nuit
	tx.nuit = false
	tx.demarrer()
	for i in 50:
		tx.compter(0.5, 10.0, 72.0)
	tx.nuit = true
	for i in 50:
		tx.compter(0.5, 10.0, 72.0)
	dire.call("taximètre, la nuit tombe à mi-course (1 km) : %.2f €" % tx.montant)
	tx.queue_free()
	var heures := []
	for hh in [6.5, 7.0, 12.0, 19.0, 19.5, 23.0, 3.0]:
		set_time(CYCLE, hh)
		heures.append("%s %s" % [heure_texte(), "nuit" if tarif_nuit() else "jour"])
	set_time(3)
	heures.append("réglage Nuit %s" % ("nuit" if tarif_nuit() else "jour"))
	set_time(2)
	heures.append("réglage Coucher %s" % ("nuit" if tarif_nuit() else "jour"))
	dire.call("tarif selon l'heure : " + ", ".join(heures))
	set_time(0)
	dire.call("FIN")
	get_tree().quit()

## Cycle jour et nuit (v6.92) : -- --drive-test --cycle-test [--drive-from=…] (--fixed-fps 8 conseillé) : moments fixes
## (lumière ambiante « ciel » à part nulle contre l'ancienne « couleur » : même image ?), puis une journée entière en
## accéléré, luminosité de l'image à chaque image (plus grand saut d'une image à l'autre contre le passage d'un moment
## fixe à l'autre), relevé et capture à chaque heure repère. Lancer avec RS_CLOUDS=0,1 (sans ombres de nuages : une
## ombre qui passe assombrit toute l'image). --cycle-sonde : réglages de la lumière à midi, fixe et dans le cycle.
func _cycle_test() -> void:
	var dire := func(x: String): print("  [cycle] " + x)
	var shot := func(n: String):
		get_viewport().get_texture().get_image().save_png("user://shots/cycle_%s.png" % n)
	DirAccess.make_dir_recursive_absolute("user://shots")
	while not Chargement.fini:
		await get_tree().process_frame
	var lum := func() -> float:
		var im := get_viewport().get_texture().get_image()
		im.resize(96, 54, Image.INTERPOLATE_BILINEAR)
		var t := 0.0
		for y in 54:
			for x in 96:
				var c := im.get_pixel(x, y)
				t += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
		return t / (96.0 * 54.0) * 255.0
	var images := func(n: int):
		for i in n:
			car.hold(0.5)
			await get_tree().process_frame
	set_weather(0)
	if OS.get_cmdline_user_args().has("--cycle-sonde"):
		cycle_pas = 1e9
		var sonde := func(n: String):
			await images.call(40)
			dire.call("%s : luminosité %.2f ; ambiance %d %.2f %.2f %s ; brume %.6f aérienne %.2f ; expo %.2f sat %.2f ; soleil %.2f %s %s ; ciel %s gris %s ; nuit %.3f ; nuages %s" % [
				n, lum.call(), _env.ambient_light_source, _env.ambient_light_energy, _env.ambient_light_sky_contribution,
				str(_env.ambient_light_color), _env.fog_density, _env.fog_aerial_perspective, _env.tonemap_exposure,
				_env.adjustment_saturation, _sun.light_energy, str(_sun.rotation), str(_sun.light_color),
				"photo" if _env.sky.sky_material == _sky_day else "peint", str(_sky_day.get_shader_parameter("gris")), _night,
				str(preload("res://scripts/env.gd").vals.get("clouds"))])
		set_time(0)
		await sonde.call("midi fixe")
		set_time(CYCLE, 12.0)
		await sonde.call("cycle 12 h direct")
		set_time(CYCLE, 9.0)
		await sonde.call("cycle 9 h")
		set_time(CYCLE, 12.0)
		await sonde.call("cycle 12 h après 9 h")
		set_time(0)
		await sonde.call("midi fixe après")
		dire.call("FIN")
		get_tree().quit()
		return
	# moments fixes : lumière ambiante « ciel » (part 0) contre « couleur » (jusqu'à la v6.91)
	var fixes := []
	for t in 4:
		set_time(t)
		await images.call(30)
		var l_ciel: float = lum.call()
		fixes.append(l_ciel)
		if t >= 2:
			_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			await images.call(4)
			var l_coul: float = lum.call()
			_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
			dire.call("%s : luminosité %.2f (ambiance « ciel », part 0) contre %.2f (« couleur », avant) : écart %.2f" % [
				TIMES[t], l_ciel, l_coul, absf(l_ciel - l_coul)])
		else:
			dire.call("%s : luminosité %.2f" % [TIMES[t], l_ciel])
	var saut_fixe := 0.0
	for t in 3:
		saut_fixe = maxf(saut_fixe, absf(float(fixes[t + 1]) - float(fixes[t])))
	dire.call("passage d'un moment fixe au suivant : saut jusqu'à %.1f d'un coup" % saut_fixe)
	# aube et crépuscule au rythme du jeu : une mise à jour par minute de jeu (ici une par image ; à ces heures la lumière
	# ambiante ne doit rien au ciel, dont les reflets se recalculent sur plusieurs images)
	for seg in [[5.0, 6.5, "aube (nuit -> lumière du coucher)"], [19.0, 20.5, "crépuscule (coucher -> nuit)"]]:
		set_time(CYCLE, float(seg[0]))
		cycle_pas = 0.0
		heure_vitesse = (1.0 / 60.0) / 0.125
		await images.call(3)
		var p0: float = lum.call()
		var debut := p0
		var s_max := 0.0
		while heure < float(seg[1]):
			await images.call(1)
			var l: float = lum.call()
			s_max = maxf(s_max, absf(l - p0))
			p0 = l
		dire.call("%s, une minute de jeu par image : luminosité %.1f -> %.1f, plus grand saut d'une image à l'autre %.2f" % [
			seg[2], debut, p0, s_max])
	if OS.get_cmdline_user_args().has("--cycle-lent"):
		cycle_pas = CYCLE_PAS
		heure_vitesse = 1.0 / 60.0
		set_time(0)
		dire.call("FIN")
		get_tree().quit()
		return
	# une journée en 720 images (2 min d'heure par image), lumière mise à jour toutes les 10 images (le jeu : chaque
	# seconde, soit une minute d'heure ; les reflets du ciel se recalculent en 8 images)
	set_time(CYCLE, 0.0)
	cycle_pas = 1.25
	heure_vitesse = 24.0 / (720.0 * 0.125)
	await images.call(2)
	var prec: float = lum.call()
	var saut := 0.0
	var saut_h := 0.0
	var vues := {}
	var pv_jour := 0
	var pv_nuit := 0
	for i in 720:
		await images.call(1)
		var l: float = lum.call()
		if absf(l - prec) > saut:
			saut = absf(l - prec)
			saut_h = heure
		prec = l
		var hh := int(floor(heure))
		if not vues.has(hh):
			vues[hh] = true
			if hh % 2 == 1 or hh in [6, 20]:
				dire.call("%s : moment %s -> %s (%.2f), soleil %.2f, nuit %.2f, ciel photo %.2f, phares %s, luminosité %.1f" % [
					heure_texte(), TIMES[_heure_de], TIMES[_heure_vers], _heure_f, _sun.light_energy, _night,
					0.0 if _env.sky.sky_material != _sky_day else 1.0 - float(_sky_day.get_shader_parameter("gris")),
					str(phares_allumes()), l])
			if hh in [6, 7, 9, 12, 17, 19, 20, 22]:
				shot.call("%02d" % hh)
			if hh == 12 and pietons:
				pv_jour = pietons.voulu()
			if hh == 23 and pietons:
				pv_nuit = pietons.voulu()
	dire.call("journée entière : plus grand saut d'une image à l'autre %.2f (vers %.1f h), contre %.1f d'un coup entre moments fixes" % [
		saut, saut_h, saut_fixe])
	dire.call("passants voulus : %d à midi, %d à 23 h" % [pv_jour, pv_nuit])
	cycle_pas = CYCLE_PAS
	heure_vitesse = 1.0 / 60.0
	set_time(0)
	dire.call("FIN")
	get_tree().quit()

## Météo variable (v6.91) : -- --drive-test --meteo-test [--drive-from=…] (--fixed-fps 8 conseillé) : à midi, fondus
## accélérés beau -> couvert -> pluie -> couvert -> brouillard -> beau, luminosité moyenne de l'image à chaque image (le
## plus grand saut d'une image à la suivante, contre le changement d'un coup d'avant la v6.91), captures au milieu et à
## la fin de chaque fondu ; passants et circulation sous la pluie ; enchaînement tiré par la météo variable (accéléré).
func _meteo_test() -> void:
	var dire := func(x: String): print("  [météo] " + x)
	var shot := func(n: String):
		get_viewport().get_texture().get_image().save_png("user://shots/meteo_%s.png" % n)
	DirAccess.make_dir_recursive_absolute("user://shots")
	while not Chargement.fini:
		await get_tree().process_frame
	var lum := func() -> float:
		var im := get_viewport().get_texture().get_image()
		im.resize(96, 54, Image.INTERPOLATE_BILINEAR)
		var t := 0.0
		for y in 54:
			for x in 96:
				var c := im.get_pixel(x, y)
				t += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
		return t / (96.0 * 54.0) * 255.0
	var images := func(n: int):
		for i in n:
			car.hold(0.5)
			await get_tree().process_frame
	var noms := ["beau", "couvert", "pluie", "brouillard"]
	set_time(0)
	set_weather(0)
	_wet = 0.0
	await images.call(60)
	var pv_beau: int = pietons.voulu() if pietons else 0
	if OS.get_cmdline_user_args().has("--meteo-court"):
		_meteo_variable(noms)
		return
	# avant : changement d'un coup (réglage fixe, comme jusqu'à la v6.90)
	var l0: float = lum.call()
	set_weather(1)
	await images.call(3)
	var l1: float = lum.call()
	dire.call("d'un coup (réglage fixe) : beau -> couvert, luminosité %.1f -> %.1f, saut de %.1f en une image" % [l0, l1,
		absf(l1 - l0)])
	set_weather(0)
	await images.call(30)
	for w in [1, 2, 1, 3, 0]:
		var de: int = weather
		meteo_vers(w, 24.0)
		var prec: float = lum.call()
		var debut := prec
		var saut := 0.0
		var nb := 0
		var mi := false
		var ciels := []
		while _meteo_f < 1.0:
			await images.call(1)
			var l: float = lum.call()
			saut = maxf(saut, absf(l - prec))
			prec = l
			nb += 1
			var ciel_vu := "peint"
			if _env.sky.sky_material == _sky_day:
				ciel_vu = "photo" if float(_sky_day.get_shader_parameter("gris")) <= 0.0 else "photo grisée"
			if not ciels.has(ciel_vu):
				ciels.append(ciel_vu)
			if not mi and _meteo_f >= 0.5:
				mi = true
				shot.call("%s_%s_mi" % [noms[de], noms[w]])
		await images.call(40)
		var fin: float = lum.call()
		shot.call(noms[w] + ("_2" if w == 1 and de == 2 else ""))
		dire.call(("fondu %s -> %s : %d images, luminosité %.1f -> %.1f, plus grand saut d'une image à l'autre %.2f (%.0f %% " +
			"de l'écart) ; ciel %s ; pluie %.2f (gouttes %.2f), sol mouillé %.2f, phares %s, brume %.5f") % [noms[de], noms[w], nb,
			debut, fin, saut, 100.0 * saut / maxf(absf(fin - debut), 0.01), " -> ".join(ciels), pluie, float(rain.amount), _wet,
			str(phares_meteo), _env.fog_density])
		if w == 2:
			dire.call("sous la pluie : passants voulus %d (beau temps : %d), circulation : pluie %.2f, phares %s, vitesse visée × %.2f" % [
				pietons.voulu() if pietons else 0, pv_beau, float(circulation._pluie) if circulation else 0.0,
				str(phares_meteo), lerpf(1.0, circulation.PLUIE_V, float(circulation._pluie)) if circulation else 1.0])
	_meteo_variable(noms)

## Météo variable : enchaînement tiré au hasard sur 20 h de jeu, par pas de 5 s (la vraie mécanique, _meteo_avancer,
## sans attendre les images).
func _meteo_variable(noms: Array) -> void:
	var dire := func(x: String): print("  [météo] " + x)
	meteo_vitesse = 1.0
	set_weather(VARIABLE)
	var suite := [noms[weather]]
	var duree := [0.0, 0.0, 0.0, 0.0]
	var actuel: int = weather
	for i in 14400:
		_meteo_avancer(5.0)
		duree[weather] += 5.0
		if weather != actuel:
			actuel = weather
			suite.append(noms[weather])
	var total: float = duree[0] + duree[1] + duree[2] + duree[3]
	dire.call("variable : %d changements en %.1f h de jeu : %s" % [suite.size() - 1, total / 3600.0, " > ".join(suite.slice(0, 24))])
	dire.call("variable : part du temps beau %.0f %%, couvert %.0f %%, pluie %.0f %%, brouillard %.0f %%" % [
		100.0 * duree[0] / total, 100.0 * duree[1] / total, 100.0 * duree[2] / total, 100.0 * duree[3] / total])
	meteo_vitesse = 1.0
	set_weather(0)
	dire.call("FIN")
	get_tree().quit()

## Passants (v6.88) : -- --drive-test --pietons-test [--drive-from=…] (--fixed-fps 8 conseillé) : passants en scène
## autour du joueur (lignes : trottoirs, rues piétonnes, bords de rue), capture d'un passant de près et de la rue, puis
## la voiture lancée à 40 km/h droit sur un passant (il doit s'écarter d'un bond), et une voiture qui le frôle de trop
## près (« pouf »). Coût par pas de physique.
func _pietons_test() -> void:
	var pi = pietons
	var dire := func(x: String): print("  [piétons] " + x)
	var shot := func(n: String):
		get_viewport().get_texture().get_image().save_png("user://shots/pietons_%s.png" % n)
	DirAccess.make_dir_recursive_absolute("user://shots")
	while not Chargement.fini:
		await get_tree().process_frame
	Engine.max_physics_steps_per_frame = 16
	if pi == null or not pi.ok:
		dire.call("ÉCHEC : pas de passants (world/pietons.bin ou modèles absents)")
		get_tree().quit()
		return
	pi.set_densite(3)
	dire.call("réseau : %d lignes ; niveau %d, densité %d : %d passants voulus" % [pi._p0.size(), pi.niveau, pi.densite, pi.voulu()])
	var arretes := {}                    # voitures de la circulation arrêtées devant un passant qui traverse
	var pas := func(n: int):
		for i in n:
			car.hold(0.5)
			await get_tree().physics_frame
			if circulation:
				for v in circulation.voitures:
					if String(v.leader) == "passant" and float(v.v) < 1.0:
						arretes[int(v.id)] = true
	var releve := func(tag: String):
		var genres := [0, 0, 0, 0, 0]
		var marche := 0
		var dmin := INF
		for c in pi.passants:
			genres[pi._genre[int(c.l)]] += 1
			if float(c.pause) <= 0.0:
				marche += 1
			dmin = minf(dmin, (c.n as Node3D).global_position.distance_to(car.global_position))
		var prets: int = pi._modeles.filter(func(m): return m[1] != null).size()
		var e = PerfMon._sys.get("pietons", [0, 0, 1])
		dire.call("%s : %d passants (trottoirs %d, rues piétonnes %d, bords de rue %d, passages piétons %d, arrêts de bus %d), %d en marche, le plus proche à %.0f m ; modèles chargés %d/%d ; traversées %d, voitures arrêtées pour un passant %d ; coût %.2f ms/pas (pire %.2f)" % [tag,
			pi.passants.size(), genres[0], genres[1], genres[2], genres[3], genres[4], marche, dmin, prets, pi._modeles.size(),
			pi.traversees, arretes.size(), float(e[0]) / maxf(float(e[2]), 1.0) / 1000.0, float(e[1]) / 1000.0])
	for k in 3 if OS.get_cmdline_user_args().has("--pietons-court") else 15:     # --pietons-court : 6 s seulement
		await pas.call(240)
		releve.call("t=%d s" % ((k + 1) * 2))
	# un passant de près : caméra libre devant lui
	var c = null
	for o in pi.passants:
		if float(o.pause) <= 0.0 and (c == null or (o.n as Node3D).global_position.distance_to(car.global_position) < (c.n as Node3D).global_position.distance_to(car.global_position)):
			c = o
	if c == null:
		dire.call("ÉCHEC : aucun passant en marche")
		get_tree().quit()
		return
	var cam := Camera3D.new()
	add_child(cam)
	var cam0 := get_viewport().get_camera_3d()
	var pp: Vector3 = (c.n as Node3D).global_position
	var dv: Vector3 = pi.tangente(int(c.l), float(c.s)) * float(c.sens)
	cam.global_position = pp + dv * 4.5 + Vector3(-dv.z, 0, dv.x) * 1.5 + Vector3.UP * 1.6
	cam.look_at(pp + Vector3.UP * 1.0)
	cam.current = true
	for f in 3:
		await get_tree().process_frame
	shot.call("pres")
	cam.global_position = pp + dv * 16.0 + Vector3(-dv.z, 0, dv.x) * 5.0 + Vector3.UP * 4.0
	cam.look_at(pp + Vector3.UP * 1.0)
	for f in 3:
		await get_tree().process_frame
	shot.call("rue")
	dire.call("captures : passant (ligne %d, genre %d) à (%.0f, %.0f)" % [int(c.l), pi._genre[int(c.l)], pp.x, pp.z])
	# voiture lancée droit sur un passant à 40 km/h
	for essai in 2:
		var cible = null
		for o in pi.passants:
			if (cible == null or (o.n as Node3D).global_position.distance_to(car.global_position) < (cible.n as Node3D).global_position.distance_to(car.global_position)):
				cible = o
		if cible == null:
			break
		var vise := 11.0
		var depart := 30.0 if essai == 0 else 4.0               # 2e essai : la voiture surgit à 4 m (trop près)
		var p0: Vector3 = (cible.n as Node3D).global_position
		var tg: Vector3 = pi.tangente(int(cible.l), float(cible.s))
		var dir := Vector3(-tg.z, 0, tg.x) if essai == 0 else tg          # en travers du trottoir, puis le long
		var espace := get_world_3d().direct_space_state
		for sg in [1.0, -1.0]:                       # côté d'où la voiture arrive sans traverser un mur
			var q0: Vector3 = p0 - dir * sg * depart + Vector3.UP
			var rq := PhysicsRayQueryParameters3D.create(q0, p0 + Vector3.UP)
			rq.exclude = [car.get_rid()]
			if espace.intersect_ray(rq).is_empty():
				dir *= sg
				break
		var b0: int = pi.bonds
		var f0: int = pi.poufs
		car.hold(0.0)
		car.place(p0 - dir * depart + Vector3(0, 0.6, 0), rad_to_deg(atan2(dir.x, -dir.z)))
		cam_rig.snap()
		cam0.current = true
		var dmin := INF
		var vu_bond := false
		for i in int(2.6 * 120):
			car.linear_velocity = Vector3(dir.x * vise, car.linear_velocity.y, dir.z * vise)
			await get_tree().physics_frame
			if not pi.passants.has(cible):
				break
			var q: Vector3 = (cible.n as Node3D).global_position
			var l: Vector3 = car.global_transform.affine_inverse() * q
			dmin = minf(dmin, Vector2(maxf(absf(l.x) - 1.0, 0.0), maxf(absf(l.z) - 2.4, 0.0)).length())
			if not vu_bond and pi.bonds > b0:
				vu_bond = true
				for f in 3:
					await get_tree().process_frame
				shot.call("bond_%d" % essai)
		car.linear_velocity = Vector3.ZERO
		dire.call("voiture sur un passant (%s) : bond %s, pouf %s, distance minimale à la carrosserie %.1f m" % [
			"de 30 m, en travers" if essai == 0 else "à 4 m, le long", str(pi.bonds > b0), str(pi.poufs > f0), dmin])
		await pas.call(240)
	# klaxon : voiture arrêtée à 12 m d'un passant en marche, tournée vers lui
	var cible_k = null
	for o in pi.passants:
		if float(o.pause) <= 0.0 and pi._genre[int(o.l)] != 3 and (cible_k == null or (o.n as Node3D).global_position.distance_to(car.global_position) < (cible_k.n as Node3D).global_position.distance_to(car.global_position)):
			cible_k = o
	if cible_k:
		var q0: Vector3 = (cible_k.n as Node3D).global_position
		var tg2: Vector3 = pi.tangente(int(cible_k.l), float(cible_k.s))
		var vers := Vector3(-tg2.z, 0, tg2.x)
		car.hold(0.0)
		car.place(q0 - vers * 12.0 + Vector3(0, 0.6, 0), rad_to_deg(atan2(vers.x, -vers.z)))
		cam_rig.snap()
		await pas.call(30)
		var s0: int = pi.sursauts
		var b0: int = pi.bonds
		klaxon.klaxonner()
		await pas.call(60)
		var q1: Vector3 = (cible_k.n as Node3D).global_position
		var regarde: Vector3 = (cible_k.n as Node3D).global_transform.basis.z
		var vers_auto: Vector3 = car.global_position - q1
		vers_auto.y = 0.0
		dire.call("klaxon : %d coup(s), %d passant(s) ont sursauté, %d bond(s) ; le passant visé : à l'arrêt %s, tourné vers la voiture %s (%.0f°), déplacé de %.1f m" % [
			klaxon.coups, pi.sursauts - s0, pi.bonds - b0, str(float(cible_k.pause) > 0.0 or float(cible_k.bond_t) > 0.0),
			str(rad_to_deg(regarde.angle_to(vers_auto.normalized())) < 30.0), rad_to_deg(regarde.angle_to(vers_auto.normalized())), q1.distance_to(q0)])
		for f in 3:
			await get_tree().process_frame
		shot.call("klaxon")
	# passage piéton : un passant posé au milieu d'un passage que va franchir une voiture de la circulation (20-50 m
	# devant elle) ; elle doit s'arrêter devant lui (meneur « passant »)
	if circulation and not pi.passants.is_empty():
		var choix = null
		for v in circulation.voitures:
			if float(v.v) < 3.0:
				continue
			var ch: PackedVector3Array = circulation._chemin(v)
			for k in pi._genre.size():
				if pi._genre[k] != 3:
					continue
				var m: Vector3 = pi.point(k, pi.longueur(k) * 0.5)
				if m.distance_to(v.pos) > 55.0 or m.distance_to(car.global_position) > 100.0:   # passants : 140 m au plus
					continue
				for i in ch.size():
					if i * 3 >= 20 and Vector2(ch[i].x - m.x, ch[i].z - m.z).length() < 2.0:
						choix = [v, k]
						break
				if choix:
					break
			if choix:
				break
		if choix == null:
			dire.call("passage piéton : aucune voiture de la circulation n'approche d'un passage piéton")
		else:
			var v = choix[0]
			var kp: int = choix[1]
			var pa = pi.passants[0]
			pa.l = kp; pa.s = pi.longueur(kp) * 0.5; pa.sens = 1; pa.traverse = -1; pa.pause = 8.0; pa.off = Vector3.ZERO
			pa.bond_t = 0.0
			var m: Vector3 = pi.point(kp, pi.longueur(kp) * 0.5)
			var d0: float = m.distance_to(v.pos)
			var dmin := INF
			var arret := false
			var meneur := ""
			for i in 8 * 120:
				car.hold(0.5)
				pa.pause = maxf(float(pa.pause), 1.0)
				await get_tree().physics_frame
				if not circulation.voitures.has(v):
					break
				dmin = minf(dmin, (v.pos as Vector3).distance_to((pa.n as Node3D).global_position))
				if float(v.v) < 0.3 and not arret:
					arret = true
					meneur = String(v.leader)
					cam.global_position = (v.pos as Vector3) - (v.dir as Vector3) * 8.0 + Vector3(-v.dir.z, 0, v.dir.x) * 3.0 + Vector3.UP * 2.8
					cam.look_at((pa.n as Node3D).global_position + Vector3.UP)
					cam.current = true
					for f in 3:
						await get_tree().process_frame
					shot.call("passage")
			pa.pause = 0.0
			dire.call("passage piéton : voiture %d à %.0f m, arrêtée %s (meneur %s), au plus près %.1f m du passant, passant toujours là %s" % [
				int(v.id), d0, str(arret), meneur, dmin, str(pi.passants.has(pa))])
	# explosion (v6.90) : à 15 m du passant le plus proche ; ceux à moins de 60 m doivent s'enfuir
	if not pi.passants.is_empty():
		var cible_e = pi.passants[0]
		for o in pi.passants:
			if (o.n as Node3D).global_position.distance_to(car.global_position) < (cible_e.n as Node3D).global_position.distance_to(car.global_position):
				cible_e = o
		var pe: Vector3 = (cible_e.n as Node3D).global_position + Vector3(15.0, 0.0, 0.0)
		var avant := {}
		for o in pi.passants:
			avant[o.n] = (o.n as Node3D).global_position
		var f0: int = pi.fuites
		var fx = preload("res://scripts/explosion.gd").new()
		fx.style = "mini"
		fx.position = pe
		add_child(fx)
		# vue d'au-dessus de la voiture (dans la rue), vers le passant : la boule de feu, puis ceux qui s'enfuient
		cam.global_position = car.global_position + Vector3.UP * 16.0
		cam.look_at((cible_e.n as Node3D).global_position.lerp(pe, 0.4))
		cam.current = true
		await pas.call(30)
		await get_tree().process_frame
		shot.call("fuite_0")
		await pas.call(150)
		await get_tree().process_frame
		shot.call("fuite_1")
		await pas.call(180)
		var eloignes := 0
		var proches := 0
		for o in pi.passants:
			if avant.has(o.n) and (avant[o.n] as Vector3).distance_to(pe) < 60.0:
				proches += 1
				if (o.n as Node3D).global_position.distance_to(pe) > (avant[o.n] as Vector3).distance_to(pe) + 4.0:
					eloignes += 1
		dire.call("explosion : %d passant(s) ont fui, %d sur %d à moins de 60 m se sont éloignés de plus de 4 m" % [pi.fuites - f0,
			eloignes, proches])
	releve.call("fin")
	cam.queue_free()
	dire.call("FIN")
	get_tree().quit()
