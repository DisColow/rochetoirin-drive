## Monde : relief Terrain3D, routes en tuiles chargées au fil de la route, horizon courbe, ciel HDRI, soleil, voiture.
extends Node3D
const Relief := preload("res://scripts/relief.gd")
const PerfMon := preload("res://scripts/perf_monitor.gd")

const SUN_ELEV := 48.0          # ciel « kloofendal_48d » : soleil à 48° ; azimut mesuré sur l'image au démarrage

var terrain: Terrain3D
var relief: Node3D                 # régions du relief chargées autour de la voiture (relief.gd)
var car: VehicleBody3D
var roads: Node3D
var buildings: Node3D
var vegetation: Node3D
var crops: Node3D
var grass: Node3D
var guardian: Node3D
var poles: Node3D
var post: ColorRect
var fences: Node3D
var water: Node3D
var cam_rig: Node3D
var birds: Node3D
var ciel: Node3D            # aéronefs de passage (#46)
var props: Node3D
var pools: Node3D
var activities: CanvasLayer
var nav: Node                      # nav_physique.gd (#62)
var pied: Node                     # a_pied.gd (#66)

## Tout ce qui se charge et se calcule autour du joueur suit ce nœud : la voiture, ou le piéton quand on marche (#66).
func suivre(n: Node3D) -> void:
	for s in [roads, buildings, fences, water, vegetation, crops, grass, poles, props, pools, shops, sport, animaux, autoroute, birds, ciel]:
		if s and "target" in s:
			s.target = n
	if relief and "cible" in relief:
		relief.cible = n
	if terrain and "collision_target" in terrain:
		terrain.set("collision_target", n)
var garage: Node            # argent et pièces achetées (#43, garage.gd)
var tuning: Node            # pièces montées sur la voiture (tuning.gd)
var net: Node
var shops: Node3D
var sport: Node3D
var animaux: Node3D
var autoroute: Node3D
var dust: Node3D
var _trample: Node                 # cultures fauchées (trample.gd)
var rain: Node3D
var cockpit: CanvasLayer
var sound: Node                   # moteur sonore (scripts/audio.gd)
var radio: Node                   # autoradio (scripts/radio.gd)
var editeur: CanvasLayer          # éditeur de monde (scripts/editeur_monde.gd)
var perf: Node                     # mesure des performances (scripts/perf_monitor.gd)

## Mode sûr : si le démarrage précédent n'est pas allé jusqu'au bout (plantage pendant le chargement ou les
## premières images), on démarre sans le shader remplaçant du relief et avec moins d'anticrénelage.
const BOOT_FLAG := "user://demarrage.flag"
const Chargement := preload("res://scripts/chargement.gd")
var safe_mode := false

## Préchauffage des shaders : sur le téléphone, chaque matériau est compilé la première fois qu'il est dessiné (à-coup
## en pleine conduite). Pendant le voile de démarrage, un petit cube par matériau (simple, en lot MultiMesh, avec
## ombre) est dessiné devant la caméra, hors de vue derrière le voile : tout est compilé d'avance.

func _prechauffer() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var Env := preload("res://scripts/env.gd")
	var vus := {}
	var tenue := Node3D.new()
	cam.add_child(tenue)
	tenue.position = Vector3(0, 0, -3.0)
	var cube := BoxMesh.new(); cube.size = Vector3(0.05, 0.05, 0.05)
	var i := 0
	for m in Env.mats + Env.cam_mats:
		if m == null or vus.has(m):
			continue
		vus[m] = true
		var mi := MeshInstance3D.new()
		mi.mesh = cube; mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mi.position = Vector3((i % 20) * 0.06 - 0.6, (i / 20) * 0.06, 0)
		tenue.add_child(mi)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = cube; mm.instance_count = 1
		mm.set_instance_transform(0, Transform3D(Basis(), mi.position + Vector3(0, -0.5, 0)))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm; mmi.material_override = m
		tenue.add_child(mmi)
		i += 1
	for k in 3:
		await get_tree().process_frame
	tenue.queue_free()
	print("shaders préchauffés : ", i, " matériaux")

## Voile de démarrage (boot.gd) : effacé après les premières images du jeu et le préchauffage des shaders.
func _fermer_voile() -> void:
	Chargement.etape_suivante("Préparation des effets")
	for k in 2:
		await get_tree().process_frame
	await _prechauffer()
	for k in 2:
		await get_tree().process_frame
	Chargement.terminer()
	var v := get_tree().root.get_node_or_null("VoileDemarrage")
	if v and v.has_method("fermer"):
		v.fermer()

func _ready() -> void:
	safe_mode = FileAccess.file_exists(BOOT_FLAG)
	var bf := FileAccess.open(BOOT_FLAG, FileAccess.WRITE)
	if bf:
		bf.store_string(Time.get_datetime_string_from_system())
		bf.close()
	get_tree().create_timer(8.0).timeout.connect(func(): DirAccess.remove_absolute(BOOT_FLAG))
	RenderingServer.frame_pre_draw.connect(_env_cam)
	if safe_mode:
		print("mode sûr : le démarrage précédent a planté")
	# démarrage par étapes (v6.14) : une image est dessinée entre chaque étape, le voile affiche l'étape et la barre
	set_process(false)
	set_physics_process(false)
	Chargement.commencer()
	var skip := OS.get_environment("RS_SKIP")
	await _etape("Ciel et lumière")
	if not skip.contains("env"): _environment()
	await _etape("Relief")
	var spawn: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://world/spawn.json"))
	var depart := Vector3(spawn.x, spawn.y + 0.6, spawn.z)
	var cap_depart := float(spawn.heading)
	# partie sauvegardée (#51) : on repart de là où on s'était arrêté (pas pendant les essais)
	var sauv: Array = preload("res://scripts/sauvegarde.gd").lire()
	if not sauv.is_empty() and OS.get_cmdline_user_args().is_empty():
		depart = sauv[0]
		cap_depart = sauv[1]
	# essai : --drive-from=x,y,z,cap (départ de l'essai de conduite ailleurs qu'au point de départ)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--drive-from="):
			var v := a.trim_prefix("--drive-from=").split(",")
			depart = Vector3(float(v[0]), float(v[1]), float(v[2]))
			cap_depart = float(v[3])
	if not skip.contains("terrain"):
		# relief chargé autour du point de départ seulement (v6.16, relief.gd) ; le reste suit en arrière-plan
		_terrain()
		relief.charger_autour(depart)
	await _etape("Horizon")
	if not skip.contains("far"): _far()
	await _etape("Routes")
	roads = preload("res://scripts/roads.gd").new()
	add_child(roads)
	car = preload("res://scripts/car.gd").new()
	car.road_pts = FileAccess.get_file_as_bytes("res://world/teleport.bin").to_float32_array()
	add_child(car)
	car.place(depart, cap_depart)
	car.hold(600.0)                    # immobile pendant la suite du chargement (relâchée à la fin)
	if relief:
		relief.cible = car
	roads.target = car
	roads.update_now()
	await _etape("Bâtiments")
	buildings = preload("res://scripts/buildings.gd").new()
	add_child(buildings)
	buildings.target = car
	buildings.update_now()
	await _etape("Clôtures et haies")
	fences = preload("res://scripts/fences.gd").new()
	add_child(fences)
	fences.target = car
	fences.update_now()
	await _etape("Rivières et étangs")
	water = preload("res://scripts/water.gd").new()
	add_child(water)
	water.target = car
	water.update_now()
	await _etape("Arbres")
	vegetation = preload("res://scripts/vegetation.gd").new()
	var cfg := ConfigFile.new()
	cfg.load("user://reglages.cfg")
	perf_auto = bool(cfg.get_value("affichage", "perf_auto", true))
	vegetation.level = int(cfg.get_value("affichage", "vegetation", 1))    # défaut : Équilibré (puis automatique)
	add_child(vegetation)
	vegetation.target = car
	vegetation.update_now()
	await _etape("Champs et herbe")
	crops = preload("res://scripts/crops.gd").new()
	crops.level = vegetation.level
	crops.terrain = terrain
	add_child(crops)
	crops.target = car
	# cultures couchées au passage de la voiture
	var tr = preload("res://scripts/trample.gd").new()
	tr.car = car
	tr.crops = crops
	_trample = tr
	add_child(tr)
	if crops.get("mat"):
		tr.attacher(crops.mat)
		tr.attacher(crops.mat_sol)
	var env_ := preload("res://scripts/env.gd")
	if env_.terrain_mat and ResourceLoader.exists("res://assets/veg/crops_albedo.png"):
		tr.attacher_relief(env_.terrain_mat, load("res://assets/veg/crops_albedo.png"))
	grass = preload("res://scripts/grass.gd").new()
	grass.level = vegetation.level
	grass.terrain = terrain
	add_child(grass)
	grass.target = car
	weather = int(cfg.get_value("affichage", "meteo", 0))
	car.aide_voie = bool(cfg.get_value("conduite", "aide_voie", true))
	set_time(int(cfg.get_value("affichage", "heure", 0)))
	_wet = _wet_target                                    # au démarrage : sol déjà mouillé s'il pleut
	await _etape("Poteaux et lampadaires")
	poles = preload("res://scripts/poles.gd").new()
	add_child(poles)
	poles.target = car
	poles.update_now()
	await _etape("Voitures garées et mobilier")
	props = preload("res://scripts/props.gd").new()
	add_child(props)
	props.target = car
	props.update_now()
	pools = preload("res://scripts/pools.gd").new()
	add_child(pools)
	pools.target = car
	pools.update_now()
	await _etape("Commerces")
	shops = preload("res://scripts/shops.gd").new()
	add_child(shops)
	shops.target = car
	shops.update_now()
	add_child(preload("res://scripts/sur_mesure.gd").new())      # bâtiments refaits d'après Street View (boulangerie)
	await _etape("Terrains de sport")
	sport = preload("res://scripts/sport.gd").new()
	sport.terrain = terrain
	add_child(sport)
	sport.target = car
	sport.update_now()
	await _etape("Animaux")
	animaux = preload("res://scripts/animaux.gd").new()
	add_child(animaux)
	animaux.target = car
	animaux.update_now()
	await _etape("Autoroutes")
	autoroute = preload("res://scripts/autoroute.gd").new()
	add_child(autoroute)
	autoroute.target = car
	autoroute.update_now()
	poles.set_night(1.0 if time_of_day == 3 else (0.35 if time_of_day == 2 else 0.0))
	await _etape("Voiture, sons et radio")
	# gardien des limites de la carte
	guardian = preload("res://scripts/guardian.gd").new()
	guardian.car = car
	guardian.terrain = terrain
	add_child(guardian)
	# v6.22 : soucoupe désactivée (code conservé), remplacée par les bords façon Motocross Madness (bord.gd)
	guardian.process_mode = Node.PROCESS_MODE_DISABLED
	guardian.visible = false
	var bord := preload("res://scripts/bord.gd").new()
	bord.car = car
	add_child(bord)
	if "collision_target" in terrain:
		terrain.set("collision_target", car)
	# vie : oiseaux qui passent, poussière derrière les roues hors du bitume
	birds = preload("res://scripts/birds.gd").new()
	birds.target = car
	birds.terrain = terrain
	add_child(birds)
	ciel = preload("res://scripts/ciel.gd").new()
	ciel.target = car
	add_child(ciel)
	dust = preload("res://scripts/dust.gd").new()
	dust.car = car
	dust.roads = roads
	add_child(dust)
	if _trample:
		_trample.dust = dust
	_apply_ambience()
	cam_rig = preload("res://scripts/camera_rig.gd").new()
	cam_rig.target = car
	add_child(cam_rig)
	var ck = preload("res://scripts/cockpit.gd").new()
	ck.name = "Cockpit"
	ck.car = car
	ck.main = self
	add_child(ck)
	cam_rig.cockpit = ck
	cockpit = ck
	rain = preload("res://scripts/rain.gd").new()
	rain.cam_rig = cam_rig
	rain.car = car
	add_child(rain)
	sound = preload("res://scripts/audio.gd").new()
	sound.name = "Audio"
	sound.car = car
	sound.cam_rig = cam_rig
	sound.main = self
	add_child(sound)
	if _trample:
		_trample.audio = sound
	# décor destructible : panneaux, lampadaires, clôtures, petits arbres (casse.gd)
	var ca = preload("res://scripts/casse.gd").new()
	ca.name = "Casse"
	ca.main = self
	ca.car = car
	ca.poles = poles
	ca.vegetation = vegetation
	ca.fences = fences
	add_child(ca)
	radio = preload("res://scripts/radio.gd").new()
	radio.name = "Radio"
	radio.main = self
	radio.cam_rig = cam_rig
	add_child(radio)
	set_time(time_of_day)
	# étalonnage de l'image finale (calque 2D sous l'interface)
	var gl := CanvasLayer.new()
	gl.layer = -1
	post = ColorRect.new()
	post.set_anchors_preset(Control.PRESET_FULL_RECT)
	post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gm := ShaderMaterial.new()
	gm.shader = preload("res://scripts/grade.gdshader")
	post.material = gm
	gl.add_child(post)
	add_child(gl)
	post.visible = not OS.get_environment("RS_SKIP").contains("post")
	set_post(vegetation.level)
	await _etape("Interface")
	var hud = preload("res://scripts/hud.gd").new()
	hud.name = "HUD"
	hud.car = car
	if autoroute:
		autoroute.hud = hud
	hud.process_mode = Node.PROCESS_MODE_ALWAYS          # la carte reste utilisable jeu en pause
	add_child(hud)
	if cockpit:
		cockpit.ouvrir_carte.connect(hud._open_map)       # écran GPS de la planche de bord (#60)
	pied = preload("res://scripts/a_pied.gd").new()        # sortir de la voiture, à pied (#66)
	pied.main = self
	add_child(pied)
	nav = preload("res://scripts/nav_physique.gd").new()   # menus au clavier et à la manette (#62)
	nav.main = self
	add_child(nav)
	activities = preload("res://scripts/activities.gd").new()
	activities.main = self; activities.car = car; activities.hud = hud; activities.map = hud.map
	if radio:
		radio.hud = hud
	activities.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(activities)
	# garage (#43) : argent gagné aux activités, améliorations de la voiture
	garage = preload("res://scripts/garage.gd").new()
	garage.name = "Garage"
	add_child(garage)
	tuning = preload("res://scripts/tuning.gd").new()
	tuning.car = car; tuning.garage = garage; tuning.main = self; tuning.activities = activities
	add_child(tuning)
	var sv = preload("res://scripts/sauvegarde.gd").new()
	sv.name = "Sauvegarde"
	sv.car = car
	add_child(sv)
	# multijoueur sur le réseau local (v6.44)
	net = preload("res://scripts/net.gd").new()
	net.name = "Net"
	net.main = self; net.car = car; net.act = activities
	net.armes = preload("res://scripts/armes.gd").new()          # courses à armes (#99)
	net.armes.main = self; net.armes.net = net; net.armes.car = car
	add_child(net.armes)
	add_child(net)
	hud.teleport.connect(_teleport)
	cam_rig.hud = hud
	editeur = preload("res://scripts/editeur_monde.gd").new()
	editeur.main = self; editeur.hud = hud
	add_child(editeur)
	var cr = preload("res://scripts/crash_report.gd").new()
	cr.car = car; cr.hud = hud; cr.names = hud.names
	add_child(cr)
	perf = preload("res://scripts/perf_monitor.gd").new()
	perf.car = car; perf.names = hud.names
	add_child(perf)
	perf.releve_fini.connect(hud.releve_perf_fini)
	set_process(true)
	set_physics_process(true)
	car.hold(0.5)
	if OS.get_cmdline_user_args().has("--perf-breakdown") and has_method("_perf_breakdown"):
		call("_perf_breakdown")                      # essais.gd
	_fermer_voile()

## Étape suivante du démarrage : affichée par le voile, puis une image est dessinée avant de continuer.
func _etape(nom: String) -> void:
	Chargement.etape_suivante(nom)
	print("[étape] ", nom, " ", Time.get_ticks_msec())
	await get_tree().process_frame

## Téléportation sans à-coup : appliquée une fois le jeu repris (un déplacement fait pendant la pause est annulé par
## le moteur physique), routes et bâtiments de la destination chargés d'abord, voiture maintenue immobile 0,6 s.
func _teleport(p: Vector3, heading: float) -> void:
	await get_tree().process_frame
	await get_tree().physics_frame
	if relief:
		relief.charger_autour(p)
	car.place(p, heading)
	car.hold(0.6)
	if pied and pied.actif:              # à pied : la voiture ET le piéton vont au point choisi (#80)
		pied.rejoindre_voiture()
	cam_rig.snap()
	roads.update_now()
	buildings.update_now()
	fences.update_now()
	water.update_now()
	poles.update_now()
	props.update_now()
	pools.update_now()
	shops.update_now()
	sport.update_now()
	animaux.update_now()
	autoroute.update_now()
	vegetation.update_now()
	grass.update_now()

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
	env.adjustment_contrast = 1.06
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	_env = env
	_sky_day = mat
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
	_sun = sun
	_sun_az = sun.rotation.y

## Étalonnage et netteté : désactivés au niveau Faible (téléphones modestes).
## Niveau de performances (Réglages > Performances, 0 Économie … 3 Maximale) : en plus de la végétation, de l'herbe et
## des cultures (réglées par hud.gd), il règle ici les ombres, l'anticrénelage, la simplification des objets lointains,
## la résolution 3D, les distances d'affichage et l'étalonnage. Mesures : essai --perf-breakdown (les ombres pèsent un
## tiers des triangles ; l'anticrénelage 4× coûte cher sur les petites puces).
const NIVEAUX := [
	# msaa, ombres (portée m, cascades, carte), seuil de détail (px), résolution 3D, distances, étalonnage
	{"msaa": Viewport.MSAA_DISABLED, "ombre": 90.0, "split": false, "carte": 2048, "lod": 6.0, "res": 0.8, "dist": 0.55, "post": false},
	{"msaa": Viewport.MSAA_2X, "ombre": 150.0, "split": false, "carte": 2048, "lod": 3.0, "res": 0.9, "dist": 0.75, "post": true},
	{"msaa": Viewport.MSAA_4X, "ombre": 240.0, "split": true, "carte": 4096, "lod": 1.5, "res": 1.0, "dist": 1.0, "post": true},
	{"msaa": Viewport.MSAA_4X, "ombre": 320.0, "split": true, "carte": 4096, "lod": 1.0, "res": 1.0, "dist": 1.0, "post": true},
]
var _vues_base := {}

func set_post(level: int) -> void:
	var N: Dictionary = NIVEAUX[clampi(level, 0, NIVEAUX.size() - 1)]
	Engine.set_meta("niveau_perf", level)
	var vp := get_viewport()
	vp.msaa_3d = Viewport.MSAA_2X if safe_mode and N.msaa != Viewport.MSAA_DISABLED else N.msaa
	vp.mesh_lod_threshold = N.lod
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = N.res
	if _sun:
		_sun.directional_shadow_max_distance = N.ombre
		_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if N.split else DirectionalLight3D.SHADOW_ORTHOGONAL
		RenderingServer.directional_shadow_atlas_set_size(N.carte, true)
	# distances d'affichage des objets posés par tuiles (valeurs de base gardées au premier appel)
	for sysn in ["buildings", "props", "fences", "poles", "shops"]:
		var sy = get(sysn)
		if sy == null:
			continue
		for prop in ["VIEW", "VIEW_CUT", "TOUFFE_VIEW"]:
			if sy.get(prop) == null:
				continue
			var key: String = sysn + "." + prop
			if not _vues_base.has(key):
				_vues_base[key] = float(sy.get(prop))
			sy.set(prop, _vues_base[key] * N.dist)
	if fences and fences.get("mat"):
		var Env := preload("res://scripts/env.gd")
		Env.fade(fences.mat, fences.VIEW)
		if fences.get("mat_cut"):
			Env.fade(fences.mat_cut, fences.VIEW_CUT)
	if post:
		post.visible = N.post and not OS.get_environment("RS_SKIP").contains("post")

## Niveau automatique : on part d'Équilibré ; toutes les 30 s, d'après les images/s mesurées (perf_monitor.gd), on
## descend d'un cran sous 24 img/s, on remonte (jusqu'à Élevée) au-dessus de 50 img/s.
var perf_auto := false
var _auto_t := 0.0

func _perf_auto(dt: float) -> void:
	if not perf_auto or perf == null or get_tree().paused:
		return
	_auto_t += dt
	if _auto_t < 30.0:
		return
	_auto_t = 0.0
	var f: float = perf.get_fps_moyen(4)
	if f <= 0.0:
		return
	var l: int = vegetation.level
	if f < 24.0 and l > 0:
		get_node("HUD").appliquer_niveau(l - 1)
		print("[perf] niveau automatique : %.0f img/s -> %d" % [f, l - 1])
	elif f > 50.0 and l < 2:
		get_node("HUD").appliquer_niveau(l + 1)
		print("[perf] niveau automatique : %.0f img/s -> %d" % [f, l + 1])

# ---------------------------------------------------------------- heure de la journée (Réglages)
const TIMES := ["Midi", "Après-midi", "Coucher", "Nuit"]
var time_of_day := 0
var _env: Environment
var _sun: DirectionalLight3D
var _sun_az := 0.0
var _sky_day: Material
var _sky_peint: ShaderMaterial          # ciel peint avec nuages (#57, ciel_peint.gdshader), heures sans photo

## Ciel peint : dégradé, soleil ou lune, plafond de nuages (couverture : seuil, plus haut = moins de nuages).
func _ciel_peint(haut: Color, horizon: Color, sol: Color, energie: float, couverture: float, clair: Color, ombre: Color,
		soleil := 1.0) -> ShaderMaterial:
	if _sky_peint == null:
		_sky_peint = ShaderMaterial.new()
		_sky_peint.shader = preload("res://scripts/ciel_peint.gdshader")
		_sky_peint.set_shader_parameter("nuages", load("res://assets/fx/nuages.png"))
		_sky_peint.set_shader_parameter("vent", Vector2(randf(), randf()))
	for k in [["haut", haut], ["horizon", horizon], ["sol", sol], ["energie", energie], ["couverture", couverture],
			["clair", clair], ["ombre", ombre], ["taille_soleil", soleil]]:
		_sky_peint.set_shader_parameter(k[0], k[1])
	return _sky_peint

## Lumière selon l'heure : midi (ciel photo à cumulus), fin d'après-midi dorée, coucher de soleil orangé, nuit bleutée
## (phares allumés, fenêtres éclairées). Le soleil garde son azimut ; seuls hauteur, couleur et ciel changent.
func set_time(i: int) -> void:
	time_of_day = clampi(i, 0, TIMES.size() - 1)
	if _env == null:
		return
	# [hauteur du soleil (°), couleur, énergie, énergie du ciel, exposition, couleur du brouillard, densité, nuit]
	var P: Array = [
		[48.0, Color(1.0, 0.96, 0.9), 1.45, 1.0, 1.0, Color(0.75, 0.82, 0.92), 0.000014, 0.0],
		[24.0, Color(1.0, 0.86, 0.66), 1.5, 0.9, 1.05, Color(0.85, 0.80, 0.70), 0.00002, 0.0],
		[9.0, Color(1.0, 0.62, 0.38), 1.8, 1.0, 1.1, Color(0.90, 0.62, 0.46), 0.00003, 0.35],
		[38.0, Color(0.55, 0.65, 1.0), 0.32, 1.0, 1.25, Color(0.05, 0.07, 0.12), 0.00003, 1.0],
	][time_of_day]
	_sun.rotation = Vector3(deg_to_rad(-float(P[0])), _sun_az, 0)
	_sun.light_color = P[1]
	_sun.light_energy = P[2]
	if time_of_day == 0:
		_env.sky.sky_material = _sky_day
		_env.fog_aerial_perspective = 0.85
	elif time_of_day < 3:
		# ciel peint : fin d'après-midi (bleu doux, horizon doré) ; coucher (bleu profond, horizon orangé), avec nuages
		var hz := Color(0.88, 0.80, 0.66) if time_of_day == 1 else Color(1.0, 0.56, 0.30)
		_env.sky.sky_material = _ciel_peint(Color(0.26, 0.44, 0.75) if time_of_day == 1 else Color(0.14, 0.2, 0.42), hz,
			hz.darkened(0.6), P[3], 0.56 if time_of_day == 1 else 0.6,
			Color(1.0, 0.95, 0.88) if time_of_day == 1 else Color(1.0, 0.68, 0.48),
			Color(0.5, 0.52, 0.6) if time_of_day == 1 else Color(0.35, 0.28, 0.38))
		_env.fog_aerial_perspective = 0.0
		_env.fog_light_color = P[5]
	else:
		# nuit : ciel bleu nuit, clair de lune (le « soleil » devient la lune)
		_env.sky.sky_material = _ciel_peint(Color(0.01, 0.015, 0.04), Color(0.05, 0.07, 0.13), Color(0.01, 0.01, 0.015), 1.0,
			0.6, Color(0.1, 0.11, 0.16), Color(0.025, 0.03, 0.045), 0.6)
		_env.fog_aerial_perspective = 0.0
		_env.fog_light_color = P[5]
	_env.tonemap_exposure = P[4]
	_env.fog_density = P[6]
	# lumière ambiante : ciel le jour ; chaude au coucher, bleutée la nuit (sinon tout devient noir)
	if time_of_day < 2:
		# v6.28 : ciel seul = ombres gris-bleu (murs beiges gris à l'ombre) ; on y mêle la lumière renvoyée par le sol,
		# gris chaud, comme sur les photos (une façade à l'ombre garde sa couleur)
		_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		_env.ambient_light_color = Color(0.80, 0.75, 0.68)
		_env.ambient_light_sky_contribution = 0.4
		_env.ambient_light_energy = 1.5
	else:
		_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		_env.ambient_light_sky_contribution = 1.0
		_env.ambient_light_color = Color(0.62, 0.50, 0.45) if time_of_day == 2 else Color(0.20, 0.25, 0.40)
		_env.ambient_light_energy = 0.9 if time_of_day == 2 else 0.75
	var night: float = P[7]
	preload("res://scripts/env.gd").set_value("night", night)
	_apply_ambience()
	if buildings and buildings.mat:
		buildings.mat.set_shader_parameter("night", night)
		buildings.set_kit_night(night)
	if poles:
		poles.set_night(night)
	_night = night
	_apply_weather()

## Vent (direction fixe, force modérée) et ombres des nuages : le jour seulement (ciel à cumulus à midi, plus léger
## en fin d'après-midi ; pas de nuages découpés au coucher ni la nuit).
var wind_strength := 0.55
func _apply_ambience() -> void:
	preload("res://scripts/env.gd").set_value("wind", Vector4(0.8, 0.6, wind_strength, 0.0))
	var cl := Vector4([0.45, 0.32, 0.0, 0.0][time_of_day], 0.0, 0.0, 0.0)
	if OS.get_environment("RS_CLOUDS") != "":                # essai : « force,seuil »
		var v := OS.get_environment("RS_CLOUDS").split(",")
		cl = Vector4(float(v[0]), float(v[1]), 0.0, 0.0)
	preload("res://scripts/env.gd").set_value("clouds", cl)
	if birds:
		birds.day = time_of_day < 3
	if ciel:
		ciel.day = time_of_day < 3

# ---------------------------------------------------------------- météo (Réglages)
const WEATHERS := ["Beau temps", "Couvert", "Pluie", "Brouillard"]
var weather := 0
var _night := 0.0
var _wet := 0.0
var _wet_target := 0.0

func set_weather(i: int) -> void:
	weather = clampi(i, 0, WEATHERS.size() - 1)
	set_time(time_of_day)

## Ciel gris uniforme, soleil voilé (ombres pâles), brume plus ou moins dense, vent, sol mouillé, pluie, essuie-glaces ;
## phares allumés la nuit, sous la pluie et dans le brouillard.
func _apply_weather() -> void:
	if _env == null:
		return
	var w := weather
	_env.adjustment_saturation = [1.08, 0.92, 0.86, 0.8][w]
	wind_strength = [0.55, 0.65, 0.9, 0.12][w]
	_wet_target = [0.0, 0.0, 1.0, 0.3][w]
	if w > 0:
		var k: float = [1.0, 0.8, 0.45, 0.06][time_of_day]           # luminosité du ciel selon l'heure
		var top := Color(0.56, 0.6, 0.65) if w == 1 else (Color(0.4, 0.43, 0.47) if w == 2 else Color(0.72, 0.74, 0.76))
		var hor := Color(0.74, 0.76, 0.78) if w != 2 else Color(0.55, 0.57, 0.6)
		if time_of_day == 2:
			hor = hor.lerp(Color(0.85, 0.6, 0.45), 0.35)
		# temps couvert : ciel peint presque entièrement couvert de nuages gris (#57)
		_env.sky.sky_material = _ciel_peint(top * k, hor * k, Color(0.2, 0.21, 0.2) * k, 1.0, [0.6, 0.3, 0.12, 0.2][w],
			hor * k * 1.04, top * k * 0.72)
		_sun.light_energy *= [1.0, 0.32, 0.2, 0.28][w]
		_sun.shadow_opacity = [1.0, 0.45, 0.3, 0.35][w]
		_env.fog_aerial_perspective = 0.0
		_env.fog_light_color = hor * k
		_env.fog_density = [0.0, 0.00012, 0.0011, 0.011][w]
		_env.fog_sky_affect = [0.0, 0.0, 0.3, 0.85][w]
		if time_of_day < 2:
			_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
			_env.ambient_light_energy = 1.25
	else:
		_sun.shadow_opacity = 1.0
		_env.fog_sky_affect = 0.0
	preload("res://scripts/env.gd").set_value("wet", _wet)
	if car and car.has_method("set_wet"):
		car.set_wet(_wet)
	if rain:
		rain.on = w == 2
		rain.set_night(_night)
	if cockpit:
		cockpit.rain = 1.0 if w == 2 else 0.0
	if car and "rain" in car:
		car.rain = 1.0 if w == 2 else 0.0
	_apply_ambience()
	if birds:
		birds.day = time_of_day < 3 and w < 2
	if ciel:
		ciel.day = time_of_day < 3 and w < 2
	if w > 0:
		preload("res://scripts/env.gd").set_value("clouds", Vector4.ZERO)
	if car and car.has_method("set_lights"):
		car.set_lights(_night > 0.2 or w >= 2)

func _terrain() -> void:
	terrain = Terrain3D.new()
	terrain.change_region_size(512)
	terrain.vertex_spacing = 2.0
	terrain.assets = load("res://assets/terrain_assets.tres")
	terrain.mesh_lods = 7
	terrain.mesh_size = 48
	terrain.collision_radius = 96
	var m := terrain.material
	m.world_background = Terrain3DMaterial.NONE
	m.show_checkered = false
	terrain.material.set_shader_param("blend_sharpness", 0.75)
	# variation à grande échelle (prés moins uniformes : zones plus jaunes, plus sombres, sur 100 à 400 m)
	m.set_shader_param("macro_variation1", Color(0.86, 0.9, 0.74))
	m.set_shader_param("macro_variation2", Color(0.9, 0.86, 0.84))
	m.set_shader_param("macro_variation_slope", 0.4)
	m.set_shader_param("noise1_scale", 0.03)
	m.set_shader_param("noise2_scale", 0.09)
	# shader du relief remplacé (même code + ombres des nuages et sol mouillé), sauf en mode sûr
	if not safe_mode:
		m.set("shader_override", load("res://scripts/terrain.gdshader"))
		m.set("shader_override_enabled", true)
		preload("res://scripts/env.gd").terrain_mat = m
	add_child(terrain)
	terrain.set_camera(get_viewport().get_camera_3d())
	relief = Relief.new(terrain)
	add_child(relief)

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
	var t0_perf := Time.get_ticks_usec()
	_process_corps(_dt)
	PerfMon.note("main", Time.get_ticks_usec() - t0_perf)

func _process_corps(_dt: float) -> void:
	_perf_auto(_dt)
	# sol qui se mouille peu à peu sous la pluie et sèche après
	if absf(_wet - _wet_target) > 0.001:
		_wet = move_toward(_wet, _wet_target, _dt / (6.0 if _wet_target > _wet else 25.0))
		preload("res://scripts/env.gd").set_value("wet", _wet)
		if dust:
			dust.wet = _wet
		car.set_wet(_wet)
	if terrain and get_viewport().get_camera_3d() and terrain.get_camera() != get_viewport().get_camera_3d():
		terrain.set_camera(get_viewport().get_camera_3d())

## Position de la caméra pour les fondus au loin des matériaux (env.gd), à chaque image, captures comprises.
func _env_cam() -> void:
	var c := get_viewport().get_camera_3d()
	if c:
		preload("res://scripts/env.gd").set_cam(c.global_position)
