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
	for s in [roads, buildings, fences, water, vegetation, crops, grass, poles, props, pools, shops, sport, rails, animaux, autoroute, birds, ciel, circulation, pietons]:
		if s and "target" in s:
			s.target = n
	if relief and "cible" in relief:
		relief.cible = n
	if terrain and "collision_target" in terrain:
		terrain.set("collision_target", n)
var garage: Node            # argent et pièces achetées (#43, garage.gd)
var carriere: Node          # mode carrière (#120, carriere.gd)
var succes: Node            # succès et statistiques (#133, succes.gd)
var nouveau_joueur := false # aucune partie sauvegardée au lancement : écran d'accueil (accueil.gd)
var tuning: Node            # pièces montées sur la voiture (tuning.gd)
var net: Node
var shops: Node3D
var sport: Node3D
var rails: Node3D           # voies ferrées et passages à niveau (#125, rails.gd)
var animaux: Node3D
var autoroute: Node3D
var circulation: Node3D       # voitures qui roulent (#132, circulation.gd)
var pietons: Node3D           # passants (v6.88, pietons.gd)
var klaxon: Node3D            # klaxon du joueur (v6.88, klaxon.gd)
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
	# premier lancement d'un nouveau joueur (jamais pendant les essais, lancés avec des options) : écran d'accueil
	var A := preload("res://scripts/accueil.gd")
	var args := OS.get_cmdline_user_args()
	if args.has("--accueil-test") or (nouveau_joueur and args.is_empty() and not A.deja_vu()):
		get_tree().create_timer(1.5).timeout.connect(A.montrer.bind(self))

func _ready() -> void:
	nouveau_joueur = not FileAccess.file_exists("user://garage.cfg") and not FileAccess.file_exists("user://carriere.cfg")
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
	eco_60 = bool(cfg.get_value("affichage", "eco_60", false))
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
	meteo_choix = clampi(int(cfg.get_value("affichage", "meteo", 0)), 0, VARIABLE)
	weather = meteo_choix if meteo_choix != VARIABLE else _meteo_depart()
	_meteo_de = weather
	_meteo_reste = _meteo_duree(weather)
	car.aide_voie = bool(cfg.get_value("conduite", "aide_voie", true))
	set_time(int(cfg.get_value("affichage", "heure", 0)), CYCLE_DEPART)
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
	rails = preload("res://scripts/rails.gd").new()          # voies ferrées (#125)
	rails.terrain = terrain
	add_child(rails)
	rails.target = car
	rails.update_now()
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
	await _etape("Circulation")
	circulation = preload("res://scripts/circulation.gd").new()
	circulation.main = self
	circulation.target = car
	circulation.set_densite(int(cfg.get_value("conduite", "circulation", 2)))
	circulation.set_niveau(int(Engine.get_meta("niveau_perf", 1)))
	add_child(circulation)
	pietons = preload("res://scripts/pietons.gd").new()
	pietons.main = self
	pietons.target = car
	pietons.set_densite(circulation.densite)
	pietons.set_niveau(circulation.niveau)
	add_child(pietons)
	klaxon = preload("res://scripts/klaxon.gd").new()
	klaxon.main = self
	add_child(klaxon)
	poles.set_night(_night)
	await _etape("Voiture, sons et radio")
	# gardien des limites de la carte
	guardian = preload("res://scripts/guardian.gd").new()
	guardian.car = car
	guardian.terrain = terrain
	guardian.actif = OS.get_cmdline_user_args().has("--void-test")      # soucoupe chargée seulement pour son essai
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
	_nuit_posee = -1.0                                   # tout est en place : lumière, nuit et météo redonnées à tous
	_lumiere()
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
	carriere = preload("res://scripts/carriere.gd").new()     # mode carrière (#120)
	carriere.name = "Carriere"
	carriere.main = self; carriere.act = activities; carriere.hud = hud; carriere.car = car
	add_child(carriere)
	succes = preload("res://scripts/succes.gd").new()         # succès et statistiques (#133)
	succes.name = "Succes"
	succes.main = self
	add_child(succes)
	var sv = preload("res://scripts/sauvegarde.gd").new()
	sv.name = "Sauvegarde"
	sv.car = car
	add_child(sv)
	# multijoueur sur le réseau local (v6.44)
	net = preload("res://scripts/net.gd").new()
	net.name = "Net"
	net.main = self; net.car = car; net.act = activities
	garage.voiture_changee.connect(net.voiture_changee)          # voiture des autres joueurs (#95)
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
	rails.update_now()
	if circulation:
		circulation.vider()
	if pietons:
		pietons.vider()
	animaux.update_now()
	autoroute.update_now()
	vegetation.update_now()
	grass.update_now()

func _environment() -> void:
	# v6.70 (#122) : ciel de midi en deux images (haut à pleine définition, bas réduit) au lieu du panorama HDR de
	# 4096 × 2048 (45 Mo de mémoire vidéo) : pipeline/build_ciel_midi.py, scripts/ciel_midi.gdshader
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://scripts/ciel_midi.gdshader")
	mat.set_shader_parameter("photo_haut", load("res://assets/ciel/midi_haut.hdr"))
	mat.set_shader_parameter("photo_bas", load("res://assets/ciel/midi_bas.hdr"))
	mat.set_shader_parameter("gris", 0.0)
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
	# soleil : direction du point le plus lumineux de l'HDRI (cherché par build_ciel_midi.py, plus au démarrage : la
	# lecture de l'image entière depuis la carte graphique coûtait du temps et de la mémoire)
	var az := float(JSON.parse_string(FileAccess.get_file_as_string("res://assets/ciel/midi.json")).soleil_az)
	var sun := DirectionalLight3D.new()
	# u = 0,5 face à -Z dans Godot (centre du panorama) ; azimut en radians autour de Y
	sun.rotation = Vector3(deg_to_rad(-SUN_ELEV), (0.5 - az) * TAU + PI, 0)
	sun.light_energy = 1.6
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.shadow_enabled = true
	# ombres : 2 cascades (45 m nette, puis jusqu'à 480 m ; v6.64, #116 : portées × 1,5) fondues entre elles et au loin, pas d'apparition sèche
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 480.0
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
## Économie (#124, cible : TCL 40 R 5G, Mali-G57 à 2 cœurs, 720p) : pas d'ombres en temps réel (tache sous la voiture),
## image 3D à 60 % ajustée seule entre 50 et 80 % (res_auto), 30 img/s, physique à 60 pas par seconde (2 pas par image
## à 30 img/s : pas besoin d'interpolation), distances courtes cachées par la brume, phares et lampadaires factices.
const NIVEAUX := [
	# msaa, ombres (portée m, cascades, carte), seuil de détail (px), résolution 3D, distances, étalonnage
	{"msaa": Viewport.MSAA_DISABLED, "ombre": 0.0, "split": false, "carte": 1024, "lod": 8.0, "res": 0.6, "dist": 0.4, "post": false,
		"res_auto": true, "fps": 30, "physique": 60, "brume": 30.0},
	{"msaa": Viewport.MSAA_2X, "ombre": 220.0, "split": false, "carte": 2048, "lod": 3.0, "res": 0.9, "dist": 0.75, "post": true},
	{"msaa": Viewport.MSAA_4X, "ombre": 360.0, "split": true, "carte": 4096, "lod": 1.5, "res": 1.0, "dist": 1.0, "post": true},
	{"msaa": Viewport.MSAA_4X, "ombre": 480.0, "split": true, "carte": 4096, "lod": 1.0, "res": 1.0, "dist": 1.0, "post": true},
]
var _vues_base := {}

var eco_60 := false              # ⚙ > Performances : Économie à 60 img/s au lieu de 30 (#124)
func set_post(level: int) -> void:
	var N: Dictionary = NIVEAUX[clampi(level, 0, NIVEAUX.size() - 1)]
	var avant := int(Engine.get_meta("niveau_perf", -1))
	Engine.set_meta("niveau_perf", level)
	var vp := get_viewport()
	vp.msaa_3d = Viewport.MSAA_2X if safe_mode and N.msaa != Viewport.MSAA_DISABLED else N.msaa
	vp.mesh_lod_threshold = N.lod
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = N.res
	_res_auto = bool(N.get("res_auto", false))
	var tm = preload("res://scripts/env.gd").terrain_mat
	if tm:
		tm.set_shader_param("terre_labouree", 1.0 if level == 0 else 0.0)
	_res_t = 0.0
	Engine.max_fps = (60 if eco_60 else int(N.fps)) if N.has("fps") else 0
	Engine.physics_ticks_per_second = int(N.get("physique", 120))
	Engine.max_physics_steps_per_frame = 8 if Engine.physics_ticks_per_second >= 120 else 4
	if _sun:
		_sun.shadow_enabled = N.ombre > 0.0
	if circulation:
		circulation.set_niveau(level)
	if pietons:
		pietons.set_niveau(level)
	if _sun and N.ombre > 0.0:
		_sun.directional_shadow_max_distance = N.ombre
		_sun.directional_shadow_split_1 = 45.0 / N.ombre      # cascade nette toujours sur ~45 m
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
	# Économie : lampadaires et phares factices, nuit plus claire, brume (set_time relit le niveau)
	if avant != level and (avant == 0 or level == 0):
		if poles:
			poles.set_night(_night)
		if car and car.has_method("set_lights"):
			car.set_lights(car.lights_on)
		if _env:
			_lumiere()

## Résolution 3D ajustée toute seule (Économie, #124) : on ne peut mesurer que le retard (à 30 img/s plafonnées, une
## image en avance ne se voit pas) ; sous 28 img/s on baisse de 5 points (jusqu'à 50 %), et toutes les 6 s à 30 img/s
## on remonte de 5 points (jusqu'à 80 %), pas avant 20 s après une baisse.
var _res_auto := false
var _res_t := 0.0
var _res_baisse_t := 0.0
func _resolution_auto(dt: float) -> void:
	if not _res_auto or perf == null or get_tree().paused:
		return
	_res_t += dt
	_res_baisse_t += dt
	if _res_t < 2.0:
		return
	_res_t = 0.0
	var f: float = perf.get_fps_moyen(1)
	if f <= 0.0:
		return
	var vp := get_viewport()
	var cible := float(Engine.max_fps) if Engine.max_fps > 0 else 60.0
	if f < cible * 0.93 and vp.scaling_3d_scale > 0.5:
		vp.scaling_3d_scale = maxf(0.5, vp.scaling_3d_scale - 0.05)
		_res_baisse_t = 0.0
	elif f >= cible * 0.98 and vp.scaling_3d_scale < 0.8 and _res_baisse_t > 20.0 and int(Time.get_ticks_msec() / 2000) % 3 == 0:
		vp.scaling_3d_scale = minf(0.8, vp.scaling_3d_scale + 0.05)

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
const TIMES := ["Midi", "Après-midi", "Coucher", "Nuit", "Cycle"]
const CYCLE := 4
## Lumière de chaque moment : [hauteur du soleil (°), couleur, énergie, énergie du ciel, exposition, couleur du
## brouillard, densité, nuit].
const MOMENTS := [
	[48.0, Color(1.0, 0.96, 0.9), 1.45, 1.0, 1.0, Color(0.75, 0.82, 0.92), 0.000014, 0.0],
	[24.0, Color(1.0, 0.86, 0.66), 1.5, 0.9, 1.05, Color(0.85, 0.80, 0.70), 0.00002, 0.0],
	[9.0, Color(1.0, 0.62, 0.38), 1.8, 1.0, 1.1, Color(0.90, 0.62, 0.46), 0.00003, 0.35],
	[38.0, Color(0.55, 0.65, 1.0), 0.32, 1.0, 1.25, Color(0.05, 0.07, 0.12), 0.00003, 1.0],
]
## Cycle jour et nuit (v6.92, initiative de Claude) : une journée en 24 min (une heure de jeu par minute). Repères
## [heure, moment, décalage du soleil (°)] : nuit jusqu'à 5 h, aube (lumière du coucher, soleil de l'autre côté),
## matinée (lumière d'après-midi), midi de 10 h 30 à 14 h 30 (ciel photo), après-midi, coucher à 19 h, nuit dès 20 h 30.
## Entre deux repères, tout est mêlé ; du coucher à la nuit, le soleil cède la place à la lune dans la pénombre.
const CYCLE_REPERES := [[0.0, 3, 0.0], [5.0, 3, 0.0], [6.5, 2, -80.0], [8.0, 1, -45.0], [10.5, 0, 0.0], [14.5, 0, 0.0],
	[17.0, 1, 40.0], [19.0, 2, 80.0], [20.5, 3, 0.0], [24.0, 3, 0.0]]
const CYCLE_DEPART := 9.0                    # heure au lancement du jeu
const CYCLE_HEURES := [12.5, 16.5, 19.0, 23.0]  # heure de chaque moment (passage d'un réglage fixe au cycle)
const CYCLE_PAS := 1.0                       # s entre deux mises à jour de la lumière (le ciel recalcule ses reflets)
var time_of_day := 0             # moment (0-3) ; dans le cycle, le plus proche
var heure_choix := 0             # réglage ⚙ > Heure (CYCLE : la journée passe)
var heure := CYCLE_DEPART        # heure du jeu dans le cycle
var heure_vitesse := 1.0 / 60.0  # heures de jeu par seconde (essais : plus vite)
var _heure_de := 0               # entre deux repères du cycle : de _heure_de vers _heure_vers, _heure_f de 0 à 1
var _heure_vers := 0
var _heure_f := 0.0
var _az_soleil := 0.0            # décalage du soleil (°)
var _heure_pas := 0.0
var cycle_pas := CYCLE_PAS       # essais : lumière mise à jour à chaque image
var _env: Environment
var _sun: DirectionalLight3D
var _sun_az := 0.0
var _sky_day: ShaderMaterial
var _sky_peint: ShaderMaterial          # ciel peint avec nuages (#57, ciel_peint.gdshader), heures sans photo

## Ciel peint : dégradé, soleil ou lune, plafond de nuages (couverture : seuil, plus haut = moins de nuages).
## Réglages `p` de _ciel_reglages : [haut, horizon, sol, énergie, couverture, clair, ombre, taille du soleil].
func _ciel_peint(p: Array) -> ShaderMaterial:
	if _sky_peint == null:
		_sky_peint = ShaderMaterial.new()
		_sky_peint.shader = preload("res://scripts/ciel_peint.gdshader")
	_ciel_regler(_sky_peint, p)
	return _sky_peint

const CIEL_CLES := ["haut", "horizon", "sol", "energie", "couverture", "clair", "ombre", "taille_soleil"]
var _ciel_vent := Vector2(randf(), randf())
func _ciel_regler(m: ShaderMaterial, p: Array) -> void:
	if m.get_shader_parameter("nuages") == null:
		m.set_shader_parameter("nuages", load("res://assets/fx/nuages.png"))
		m.set_shader_parameter("vent", _ciel_vent)
	for i in CIEL_CLES.size():
		m.set_shader_parameter(CIEL_CLES[i], p[i])

## Ciel du moment `t` par le temps `w` : vide pour le ciel photo (midi, beau temps), sinon réglages du ciel peint.
func _ciel_reglages(t: int, w: int) -> Array:
	if w == 0:
		if t == 0:
			return []
		if t < 3:
			# fin d'après-midi (bleu doux, horizon doré) ; coucher (bleu profond, horizon orangé), avec nuages
			var hz := Color(0.88, 0.80, 0.66) if t == 1 else Color(1.0, 0.56, 0.30)
			return [Color(0.26, 0.44, 0.75) if t == 1 else Color(0.14, 0.2, 0.42), hz, hz.darkened(0.6), float(MOMENTS[t][3]),
				0.56 if t == 1 else 0.6, Color(1.0, 0.95, 0.88) if t == 1 else Color(1.0, 0.68, 0.48),
				Color(0.5, 0.52, 0.6) if t == 1 else Color(0.35, 0.28, 0.38), 1.0]
		# nuit : ciel bleu nuit, clair de lune (le « soleil » devient la lune)
		return [Color(0.01, 0.015, 0.04), Color(0.05, 0.07, 0.13), Color(0.01, 0.01, 0.015), 1.0, 0.6,
			Color(0.1, 0.11, 0.16), Color(0.025, 0.03, 0.045), 0.6]
	# temps gris : ciel peint presque entièrement couvert de nuages gris (#57)
	var k: float = [1.0, 0.8, 0.45, 0.06][t]           # luminosité du ciel selon l'heure
	var top := Color(0.56, 0.6, 0.65) if w == 1 else (Color(0.4, 0.43, 0.47) if w == 2 else Color(0.72, 0.74, 0.76))
	var hor := Color(0.74, 0.76, 0.78) if w != 2 else Color(0.55, 0.57, 0.6)
	if t == 2:
		hor = hor.lerp(Color(0.85, 0.6, 0.45), 0.35)
	return [top * k, hor * k, Color(0.2, 0.21, 0.2) * k, 1.0, [0.6, 0.3, 0.12, 0.2][w], hor * k * 1.04, top * k * 0.72, 1.0]

## Réglages du ciel peint mêlés ; un côté vide (ciel photo) prend ceux de l'autre.
func _ciel_melange(a: Array, b: Array, f: float) -> Array:
	if a.is_empty() or b.is_empty():
		return b if a.is_empty() else a
	var p := []
	for i in CIEL_CLES.size():
		p.append((a[i] as Color).lerp(b[i], f) if a[i] is Color else lerpf(float(a[i]), float(b[i]), f))
	return p

## Heure de la journée : un moment fixe (midi, fin d'après-midi dorée, coucher de soleil orangé, nuit bleutée : phares
## allumés, fenêtres éclairées) ou le cycle jour et nuit (`h` : heure où le reprendre, sinon celle du moment affiché).
func set_time(i: int, h := -1.0) -> void:
	var avant := heure_choix
	heure_choix = clampi(i, 0, TIMES.size() - 1)
	if heure_choix == CYCLE:
		if h >= 0.0:
			heure = h
		elif avant != CYCLE:
			heure = CYCLE_HEURES[time_of_day]
		_cycle_situer()
	else:
		time_of_day = heure_choix
		_heure_de = heure_choix
		_heure_vers = heure_choix
		_heure_f = 0.0
		_az_soleil = 0.0
	_lumiere()

## Cycle : repères qui encadrent l'heure, avancement entre les deux, moment le plus proche.
func _cycle_situer() -> void:
	heure = fposmod(heure, 24.0)
	for k in CYCLE_REPERES.size() - 1:
		var a: Array = CYCLE_REPERES[k]
		var b: Array = CYCLE_REPERES[k + 1]
		if heure >= float(a[0]) and heure < float(b[0]):
			_heure_de = int(a[1])
			_heure_vers = int(b[1])
			_heure_f = (heure - float(a[0])) / (float(b[0]) - float(a[0]))
			_az_soleil = lerpf(float(a[2]), float(b[2]), _heure_f)
			break
	time_of_day = _heure_vers if _heure_f >= 0.5 else _heure_de

## Cycle jour et nuit : l'heure avance ; lumière mise à jour toutes les CYCLE_PAS s.
func _cycle_avancer(dt: float) -> void:
	if heure_choix != CYCLE:
		return
	heure = fposmod(heure + dt * heure_vitesse, 24.0)
	_heure_pas -= dt
	if _heure_pas <= 0.0:
		_heure_pas = cycle_pas
		_cycle_situer()
		_lumiere()

## Heure du jeu en texte (« 14 h 05 »), dans le cycle seulement.
func heure_texte() -> String:
	if heure_choix != CYCLE:
		return ""
	var m := int(heure * 60.0) % 1440
	return "%d h %02d" % [m / 60, m % 60]

## Vent (direction fixe, force modérée) et ombres des nuages : le jour seulement (ciel à cumulus à midi, plus léger
## en fin d'après-midi ; pas de nuages découpés au coucher ni la nuit), effacées quand le ciel se couvre.
var wind_strength := 0.55
func _apply_ambience() -> void:
	preload("res://scripts/env.gd").set_value("wind", Vector4(0.8, 0.6, wind_strength, 0.0))
	var ombres := [0.45, 0.32, 0.0, 0.0]
	var force := lerpf(float(ombres[_heure_de]), float(ombres[_heure_vers]), _heure_f)
	var cl := Vector4(force * (1.0 - _gris), 0.0, 0.0, 0.0)
	if OS.get_environment("RS_CLOUDS") != "":                # essai : « force,seuil »
		var v := OS.get_environment("RS_CLOUDS").split(",")
		cl = Vector4(float(v[0]), float(v[1]), 0.0, 0.0)
	preload("res://scripts/env.gd").set_value("clouds", cl)
	# oiseaux et ciel animé (ciel.gd) : le jour, sauf sous la pluie et dans le brouillard
	var w := weather if _meteo_f >= 0.5 else _meteo_de
	if birds:
		birds.day = time_of_day < 3 and w < 2
	if ciel:
		ciel.day = time_of_day < 3 and w < 2

# ---------------------------------------------------------------- météo (Réglages)
const WEATHERS := ["Beau temps", "Couvert", "Pluie", "Brouillard", "Variable"]
const VARIABLE := 4
## Météo variable (v6.91, initiative de Claude) : durée de chaque temps (s de jeu, min et max), temps qui peuvent
## suivre et leurs chances, durée du fondu de l'un à l'autre (le ciel se couvre, la pluie arrive, le sol se mouille).
## Environ la moitié du temps au beau, un tiers couvert, une averse sur dix (essai --meteo-test).
const METEO_DUREES := [[600.0, 1080.0], [180.0, 360.0], [180.0, 300.0], [120.0, 240.0]]
const METEO_SUITES := [[[1, 1.0]], [[0, 0.55], [2, 0.35], [3, 0.1]], [[1, 1.0]], [[1, 0.6], [0, 0.4]]]
const METEO_DEPART := [0.5, 0.3, 0.15, 0.05]       # temps au lancement du jeu
const METEO_FONDU := 90.0
const METEO_PAS := 90                              # mises à jour par fondu (le ciel change : reflets recalculés)
## Réglages de chaque temps (beau, couvert, pluie, brouillard), mêlés pendant un fondu : saturation, vent, sol mouillé,
## part de l'énergie du soleil, opacité des ombres, densité de la brume (beau temps : celle de l'heure), brume sur le
## ciel, ciel gris (plus d'ombres de nuages), pluie, phares allumés de jour.
const METEO_REGLAGES := {
	"sat": [1.08, 0.92, 0.86, 0.8], "vent": [0.55, 0.65, 0.9, 0.12], "mouille": [0.0, 0.0, 1.0, 0.3],
	"soleil": [1.0, 0.32, 0.2, 0.28], "ombre": [1.0, 0.45, 0.3, 0.35], "brume": [0.0, 0.00012, 0.0011, 0.011],
	"brume_ciel": [0.0, 0.0, 0.3, 0.85], "gris": [0.0, 1.0, 1.0, 1.0], "pluie": [0.0, 0.0, 1.0, 0.0],
	"phares": [0.0, 0.0, 1.0, 1.0]}
var weather := 0                 # temps qu'il fait (0-3) ; pendant un fondu, celui qui arrive
var meteo_choix := 0             # réglage ⚙ > Météo (VARIABLE : le temps change tout seul)
var meteo_vitesse := 1.0         # essais : le temps passe plus vite
var pluie := 0.0                 # 0-1, fondu compris : gouttes, sons, essuie-glaces, circulation, passants
var phares_meteo := false        # pluie ou brouillard : phares allumés en plein jour (voiture, circulation)
var _meteo_de := 0               # fondu de _meteo_de vers weather, _meteo_f de 0 à 1
var _meteo_f := 1.0
var _meteo_fondu := METEO_FONDU
var _meteo_reste := 0.0          # météo variable : temps avant le prochain changement
var _meteo_pas := 0.0
var _gris := 0.0
var _night := 0.0
var _nuit_posee := -1.0          # nuit déjà donnée aux bâtiments et aux lampadaires
var _ciel_pose := []             # ciel déjà posé (_lumiere)
var _wet := 0.0
var _wet_target := 0.0

func set_weather(i: int) -> void:
	meteo_choix = clampi(i, 0, WEATHERS.size() - 1)
	if meteo_choix == VARIABLE:
		_meteo_reste = _meteo_duree(weather)
	else:
		weather = meteo_choix
		_meteo_de = weather
		_meteo_f = 1.0
	_lumiere()

func _meteo_duree(w: int) -> float:
	return randf_range(float(METEO_DUREES[w][0]), float(METEO_DUREES[w][1]))

func _meteo_depart() -> int:
	var r := randf()
	for w in METEO_DEPART.size():
		r -= float(METEO_DEPART[w])
		if r <= 0.0:
			return w
	return 0

## Météo variable : le temps qui suit `w` (METEO_SUITES).
func _meteo_suivant(w: int) -> int:
	var r := randf()
	for s in METEO_SUITES[w]:
		r -= float(s[1])
		if r <= 0.0:
			return int(s[0])
	return int(METEO_SUITES[w][0][0])

## Fondu vers le temps `w` (météo variable ; essais).
func meteo_vers(w: int, duree := METEO_FONDU) -> void:
	_meteo_de = weather
	weather = w
	_meteo_f = 0.0
	_meteo_fondu = duree
	_meteo_pas = 0.0
	_meteo_reste = _meteo_duree(w)

## Temps qui change tout seul (météo variable) et fondu en cours, à chaque image.
func _meteo_avancer(dt: float) -> void:
	if meteo_choix == VARIABLE and _meteo_f >= 1.0:
		_meteo_reste -= dt * meteo_vitesse
		if _meteo_reste <= 0.0:
			meteo_vers(_meteo_suivant(weather))
	if _meteo_f < 1.0:
		_meteo_f = minf(1.0, _meteo_f + dt * meteo_vitesse / _meteo_fondu)
		_meteo_pas -= dt * meteo_vitesse
		if _meteo_pas <= 0.0 or _meteo_f >= 1.0:
			_meteo_pas = _meteo_fondu / float(METEO_PAS)
			_lumiere()

## Réglage `cle` de METEO_REGLAGES au point du fondu.
func _meteo(cle: String, f: float) -> float:
	return lerpf(float(METEO_REGLAGES[cle][_meteo_de]), float(METEO_REGLAGES[cle][weather]), f)

## Lumière et ciel du moment `t` (0-3) par le temps qu'il fait, fondu de météo `fm` compris.
func _moment(t: int, fm: float) -> Dictionary:
	var P: Array = MOMENTS[t]
	var eco := int(Engine.get_meta("niveau_perf", 1)) == 0
	var d := {"elev": float(P[0]), "coul": P[1], "soleil": float(P[2]) * _meteo("soleil", fm), "expo": float(P[4]),
		"nuit": float(P[7])}
	# lumière ambiante : ciel le jour ; chaude au coucher, bleutée la nuit (sinon tout devient noir). Toujours « ciel »,
	# sa part à 0 au coucher et la nuit (= couleur seule) : un passage continu dans le cycle.
	if t < 2:
		# v6.28 : ciel seul = ombres gris-bleu (murs beiges gris à l'ombre) ; on y mêle la lumière renvoyée par le sol,
		# gris chaud, comme sur les photos (une façade à l'ombre garde sa couleur)
		d.amb = Color(0.80, 0.75, 0.68)
		d.amb_e = lerpf(1.5, 1.25, _meteo("gris", fm))
		d.amb_ciel = 0.4
	else:
		d.amb = Color(0.62, 0.50, 0.45) if t == 2 else Color(0.20, 0.25, 0.40)
		d.amb_e = 0.9 if t == 2 else 0.75
		d.amb_ciel = 0.0
		if eco and t == 3:
			# Économie : ni phares ni lampadaires réels -> nuit de clair de lune plus claire (#124)
			d.amb = Color(0.30, 0.36, 0.52)
			d.amb_e = 1.25
	# brume : celle du moment par beau temps ; mêlée en échelle logarithmique (elle s'épaissit régulièrement)
	var b0: float = float(P[6]) * (float(NIVEAUX[0].brume) if eco else 1.0)
	var ba: float = b0 if _meteo_de == 0 else float(METEO_REGLAGES.brume[_meteo_de])
	var bb: float = b0 if weather == 0 else float(METEO_REGLAGES.brume[weather])
	d.brume = exp(lerpf(log(maxf(ba, 1e-7)), log(maxf(bb, 1e-7)), fm))
	# ciel : part du ciel photo (midi par beau temps) et réglages du ciel peint
	var pa := _ciel_reglages(t, _meteo_de)
	var pb := _ciel_reglages(t, weather)
	d.photo = lerpf(1.0 if pa.is_empty() else 0.0, 1.0 if pb.is_empty() else 0.0, fm)
	d.ciel = _ciel_melange(pa, pb, fm)
	var ca: Color = P[5] if _meteo_de == 0 else pa[1]
	var cb: Color = P[5] if weather == 0 else pb[1]
	d.brume_coul = ca.lerp(cb, fm)
	return d

## Lumière, ciel et temps qu'il fait : le moment de la journée (deux moments mêlés dans le cycle) par la météo (deux
## temps mêlés pendant un fondu). Ciel gris uniforme, soleil voilé (ombres pâles), brume plus ou moins dense, vent, sol
## mouillé, pluie, essuie-glaces ; phares allumés la nuit, sous la pluie et dans le brouillard. Le ciel photo de midi
## se couvre ou se change en ciel de l'après-midi par `gris` (ciel_midi.gdshader), puis cède la place au ciel peint,
## identique à ce moment-là. Du coucher à la nuit (et de la nuit à l'aube), le soleil devient la lune dans la pénombre.
func _lumiere() -> void:
	if _env == null:
		return
	var fm := smoothstep(0.0, 1.0, _meteo_f)
	var a := _moment(_heure_de, fm)
	var b := a if _heure_vers == _heure_de else _moment(_heure_vers, fm)
	var f := _heure_f
	var creux := sin(PI * f) if (_heure_de == 3) != (_heure_vers == 3) else 0.0
	_sun.rotation = Vector3(deg_to_rad(-lerpf(a.elev, b.elev, f)), _sun_az + deg_to_rad(_az_soleil), 0)
	_sun.light_color = (a.coul as Color).lerp(b.coul, f)
	_sun.light_energy = lerpf(a.soleil, b.soleil, f) * (1.0 - 0.92 * creux)
	_sun.shadow_opacity = _meteo("ombre", fm)
	_env.tonemap_exposure = lerpf(a.expo, b.expo, f)
	_env.adjustment_saturation = _meteo("sat", fm)
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.ambient_light_color = (a.amb as Color).lerp(b.amb, f)
	_env.ambient_light_energy = lerpf(a.amb_e, b.amb_e, f)
	_env.ambient_light_sky_contribution = lerpf(a.amb_ciel, b.amb_ciel, f)
	_env.fog_density = exp(lerpf(log(a.brume), log(b.brume), f))
	_env.fog_sky_affect = _meteo("brume_ciel", fm)
	var photo := lerpf(a.photo, b.photo, f)
	_env.fog_aerial_perspective = 0.85 * photo
	_env.fog_light_color = (a.brume_coul as Color).lerp(b.brume_coul, f)
	# ciel : ses reflets se recalculent sur plusieurs images (Sky.PROCESS_MODE_AUTOMATIC -> INCREMENTAL, le shader
	# lit LIGHT0) : ne rien toucher s'il n'a pas changé (sinon la lumière ambiante reste celle d'un ciel d'avant)
	var p := _ciel_melange(a.ciel, b.ciel, f)
	var etat_ciel := [photo, p, _sun.rotation, _sun.light_energy]
	if etat_ciel != _ciel_pose:
		_ciel_pose = etat_ciel
		if photo >= 1.0 or p.is_empty():
			_sky_day.set_shader_parameter("gris", 0.0)
			_env.sky.sky_material = _sky_day
		elif photo <= 0.0:
			_env.sky.sky_material = _ciel_peint(p)
		else:
			_ciel_regler(_sky_day, p)
			_sky_day.set_shader_parameter("gris", 1.0 - photo)
			_env.sky.sky_material = _sky_day
	# nuit : fenêtres éclairées, lampadaires
	_night = lerpf(a.nuit, b.nuit, f)
	if absf(_night - _nuit_posee) > 0.004:
		_nuit_posee = _night
		preload("res://scripts/env.gd").set_value("night", _night)
		if buildings and buildings.mat:
			buildings.mat.set_shader_parameter("night", _night)
			buildings.set_kit_night(_night)
		if poles:
			poles.set_night(_night)
	# temps qu'il fait
	_gris = _meteo("gris", fm)
	pluie = _meteo("pluie", fm)
	phares_meteo = _meteo("phares", fm) > 0.5
	wind_strength = _meteo("vent", fm)
	_wet_target = _meteo("mouille", fm)
	preload("res://scripts/env.gd").set_value("wet", _wet)
	if car and car.has_method("set_wet"):
		car.set_wet(_wet)
	if rain:
		rain.on = pluie > 0.5
		rain.set_night(_night)
	if cockpit:
		cockpit.rain = pluie
	if car and "rain" in car:
		car.rain = pluie
	_apply_ambience()
	if car and car.has_method("set_lights"):
		car.set_lights(phares_allumes())

## Phares allumés : la nuit, au coucher, sous la pluie et dans le brouillard (voiture du joueur, circulation).
func phares_allumes() -> bool:
	return _night > 0.2 or phares_meteo

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
	_resolution_auto(_dt)
	_meteo_avancer(_dt)
	_cycle_avancer(_dt)
	# sol qui se mouille peu à peu sous la pluie et sèche après
	if absf(_wet - _wet_target) > 0.001:
		_wet = move_toward(_wet, _wet_target, _dt / (6.0 if _wet_target > _wet else 60.0))
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
