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
			weather = int(s.weather)
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
	if OS.get_cmdline_user_args().has("--rails-test"):
		_rails_test(t)
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
			activities._taxi_start()
		if t > 300 and t % 120 == 0:
			var ph: String = activities._phase
			var cible := Vector2.INF
			if ph == "attente":
				cible = activities._cl_pos
			elif ph == "course":
				cible = activities._rp(activities._dest if activities._arret < 0 else activities._arret)
			print("  [taxi] t=%d phase %s sorte %s arrêt %d (%.0f s) rappel %s courses %d compteur %.2f" % [t, ph, activities._sorte, activities._arret, activities._arret_t, not activities._rappel.is_empty(), activities._rides, activities._compteur.montant if activities._compteur else 0.0])
			if cible != Vector2.INF and _car2_dist(cible) > 12.0:
				var i: int = activities._nearest(cible)
				car.place(Vector3(cible.x, activities.pts[i + 2] + 1.0, cible.y), activities.pts[i + 3])
				car.hold(0.4)
		if t > 300 + 120 * 70 or activities._rides >= 4:
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
			DirAccess.remove_absolute(ProjectSettings.globalize_path("user://carriere.cfg"))
			ca.rep = 0.0; ca.faites = {}; ca.message_vu = false; ca.commencee = false; ca.victoires = 0; ca.defaites = 0
			act.open_menu(6)
			get_tree().paused = false
			suite.call()
		1:
			if dt >= 60:
				shot.call("menu")
				var bs: Array = act._menu.find_children("*", "Button", true, false) if act._menu else []
				print("  [carrière] onglet : %d boutons, réputation %d" % [bs.size(), int(ca.rep)])
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
			if act._phase == "course" and ca._fantome != null and ca._fantome.pret:
				var f = ca._fantome
				print("  [carrière] duel lancé : tracé du rival %.0f m, temps visé %.1f s, fantôme à %.0f m de la voiture" % [f.longueur,
					f.temps_cible, f.global_position.distance_to(car.global_position)])
				suite.call()
		4:
			if dt >= 30:
				shot.call("fantome")
				suite.call()
		5:
			if dt >= 240:
				var f = ca._fantome
				print("  [carrière] course t=%.1f s : fantôme à %.0f m de la voiture (temps de passage %.1f s à 100 m)" % [act._t,
					f.global_position.distance_to(car.global_position), f.temps_a(100.0)])
				shot.call("fantome_loin")
				ca.epreuve_finie(0, f.temps_cible - 5.0, "or", "")
				act._stop()
				suite.call()
		6:
			if ca.faites.has("duel"):
				print("  [carrière] duel gagné : réputation %d, victoires %d" % [int(ca.rep), ca.victoires])
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
				print("  [carrière] livraison réussie : réputation %d, chocs %d, temps %.0f s" % [int(ca.rep), ca._chocs, ca._t])
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
			if dt >= 60 and ca.rep >= 50.0:
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
				print("  [carrière] maire déposé : réputation %d" % int(ca.rep))
				ca.epreuve_finie(14, 200.0, "bronze", "")
				suite.call()
		13:
			if ca.message_vu and ca._bulle != null:
				suite.call()
		14:
			if dt >= 40:
				shot.call("message")
				print("  [carrière] fin : réputation %d, missions %s, message de fin %s\n%s" % [int(ca.rep), str(ca.faites.keys()),
					ca.message_vu, FileAccess.get_file_as_string("user://carriere.cfg")])
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
