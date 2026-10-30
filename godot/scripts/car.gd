## Renault Espace I (1984-1988, rouge foncé et bas beige doré, la voiture du père de l'utilisateur) : physique de véhicule à roues sur rayons, boîte automatique, direction adaptée à la vitesse.
## Sans friction : marche arrière comme dans les jeux (FREIN freine puis recule, GAZ en reculant freine puis avance), remise sur la route automatique (sortie de zone,
## chute, retournement ; plus au blocage depuis la v6.22), aides à la stabilité.
extends VehicleBody3D
const PerfMon := preload("res://scripts/perf_monitor.gd")

# Ford Ranger Raptor « préparé » (souhait du joueur : plus puissant que la série) : V6 3,0 l bi-turbo poussé à
# ~450 ch (300 kW aux roues), boîte auto 10 rapports, 4x4, 2 400 kg : 0 à 100 km/h en ~5 s, 230 km/h (débridé).
const MAX_KMH := 230.0
const POWER := 300000.0         # puissance aux roues (W)
const ENGINE := 15000.0         # force max (N) au démarrage, toutes roues (limitée par l'adhérence)
const DRAG := 0.98              # ½ ρ SCx : Cx 0,5 × 3,2 m² (gros pick-up)
const BRAKE := 46.0              # freins des roues ≈ 9,5 m/s² (100 à 0 km/h en ~40 m, comme le vrai)
const BRAKE_AIDE := 7.0          # v6.22 (« le frein n'est pas assez puissant ») : décélération ajoutée (m/s²) roues au
                                 # sol, façon jeu de conduite : ≈ 16 m/s² en tout, 100 à 0 km/h en ~25 m
const STEER_LOW := 0.55         # braquage max à l'arrêt (rad)
const STEER_HIGH := 0.08        # à 130 km/h

# performances réglées par le garage (#43, tuning.gd) : valeurs d'origine = constantes ci-dessus
var puissance := POWER
var force_max := ENGINE
var vmax := MAX_KMH
var freinage := 1.0              # multiplie BRAKE et BRAKE_AIDE
# nitro (#98) : niveau acheté au garage (0 : aucun) ; jauge 0 à 1, vidée en NITRO_DUREE s de boost, rechargée en
# roulant (lentement) et en dérapant (vite) ; poussée NITRO_ACC en plus du moteur, jusqu'à vmax + 50 km/h
const NITRO_DUREE := [0.0, 4.0, 5.0, 6.0]
const NITRO_ACC := [0.0, 6.0, 8.5, 11.0]
# réglés par le garage (tuning.gd, v6.58) : adhérence des pneus (avant, elle était réécrite à 2,6 à chaque pas : les
# pneus achetés n'avaient aucun effet), raideur des barres anti-roulis, couleur des phares
var adherence := 2.6
var anti_roulis := 1.0
var phare_couleur := Color(1.0, 0.93, 0.78)
var nitro_niveau := 0
var nitro_jauge := 1.0
var nitro_actif := false
var touch_nitro := 0.0
var tuning: Node                 # tuning.gd (peinture du garage)
var touch_throttle := 0.0
var touch_brake := 0.0
var touch_steer := 0.0
var touch_frein_main := 0.0       # bouton du frein à main (#64)
var frein_parking := false        # frein de parking (#64) : voiture immobilisée, moteur coupé
var controle := true              # false : le joueur est à pied (#66), la voiture ne lit plus les commandes
var ia := false                  # #128 : concurrent piloté par le jeu (concurrent.gd) : pédales et volant dans touch_*
                                 # seulement (ni clavier ni manette), pas d'aide à la voie, de nitro ni de remise auto
var frein_main_in := 0.0          # frein à main lu à ce pas (son, témoin)
var aide_voie := true            # aide au maintien dans la voie (v6.25, ⚙ > Conduite)
var voie = preload("res://scripts/voie.gd").new()
var steer_value := 0.0
var reversing := false
var thr_in := 0.0                # pédales lues à ce pas (moteur sonore)
var brk_in := 0.0
var safe := []                  # positions sûres récentes : [Transform3D]
var _safe_t := 0.0
var _stuck_t := 0.0
var _jam_t := 0.0
var _jam_ref := Vector3.ZERO
var _flip_t := 0.0
var wheels := []
var road_pts := PackedFloat32Array()
var _hold_t := 0.0
var _hold_xf := Transform3D()   # points de route (x, z, y, cap) pour la remise sur la route

func _ready() -> void:
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.22, 0)        # bas (moteur, plancher) : pas de basculement en virage
	# pas d'amortissement générique (0,1 par défaut dans le projet = 7 kN à 130 km/h) : traînée aérodynamique réelle
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp = 0.6
	continuous_cd = true
	# ombre douce de contact sous la caisse (le soleil seul laisse la voiture « flotter » quand il est haut)
	var gr := Gradient.new()
	gr.set_color(0, Color(0, 0, 0, 0.62)); gr.set_color(1, Color(0, 0, 0, 0.0))
	gr.add_point(0.55, Color(0, 0, 0, 0.45))
	var gt := GradientTexture2D.new()
	gt.gradient = gr; gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5); gt.fill_to = Vector2(0.5, 0.0); gt.width = 64; gt.height = 128
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR    # v6.19 : sans mélange (ALPHA_HASH absent en Compatibility)
	sm.albedo_texture = gt
	sm.render_priority = -1
	var blob := MeshInstance3D.new()
	blob.mesh = PlaneMesh.new(); blob.material_override = sm
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	blob.position = Vector3(0, 0.05, 0)
	add_child(blob)
	_blob = blob
	if ia:
		aide_voie = false
	construire(voiture if ia else preload("res://scripts/voitures.gd").actuelle())

## Voiture du joueur (#95) : caisse, roues, boîte de collision, volant et réglages de la voiture « id » du catalogue
## (voitures.gd) ; appelée au démarrage et quand on change de voiture au garage (l'ancienne est retirée).
var voiture := ""
var fiche := {}                          # entrée du catalogue
var gabarit := Vector3(2.0, 1.75, 5.4)   # largeur, hauteur, longueur : pièces du garage mises à l'échelle (tuning.gd)
var base_puissance := POWER              # d'origine, avant les améliorations du garage
var base_force := ENGINE
var base_vmax := MAX_KMH
var base_masse := 2400.0
var cx := DRAG
var n_motrices := 4.0                    # roues motrices (engine_force s'applique à chacune)
var k_frein := 1.0                       # freins des roues à l'échelle de la masse (réglés pour les 2 400 kg du pick-up)
var _cs: CollisionShape3D

func construire(id: String) -> void:
	var V := preload("res://scripts/voitures.gd")
	if not V.CATALOGUE.has(id):
		id = V.DEPART
	voiture = id
	fiche = V.CATALOGUE[id]
	var dossier := String(fiche.dossier)
	var ranger := id == "ranger"
	# l'ancienne voiture
	if _body:
		remove_child(_body); _body.queue_free(); _body = null
	for w in wheels:
		remove_child(w); w.queue_free()
	wheels.clear()
	if _cs:
		remove_child(_cs); _cs.queue_free()
	if _wheel_node:
		remove_child(_wheel_node); _wheel_node.queue_free(); _wheel_node = null
	for b in _beams:
		b.queue_free()
	_beams.clear()
	for q in _coronas:
		q.queue_free()
	_coronas.clear()
	_paint_mat = null; _lamp_mat = null; _tail_mat = null
	# fiche technique
	base_masse = float(fiche.masse)
	mass = base_masse
	base_puissance = float(fiche.kw) * 1000.0
	# force au démarrage (limite d'adhérence) d'après le rapport poids/puissance : 2 CV ≈ 2,5 m/s², GT3 ≈ 10 m/s²
	base_force = ENGINE if ranger else base_masse * (1.2 + 0.035 * base_puissance / base_masse)
	if fiche.has("force"):              # bus (#148) : première courte, monte les rues à 20 %
		base_force = float(fiche.force)
	n_motrices = 4.0 if String(fiche.traction) == "4x4" else 2.0
	k_frein = base_masse / 2400.0
	base_vmax = float(fiche.vmax)
	cx = float(fiche.cx)
	puissance = base_puissance; force_max = base_force; vmax = base_vmax
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dossier + "/meta.json"))
	_meta = meta
	if meta.has("dims"):
		gabarit = Vector3(float(meta.dims[1]), float(meta.dims[2]), float(meta.dims[0]))
	else:
		gabarit = Vector3(2.0, 1.75, 5.4)
	var body: Node3D = load(dossier + "/body.glb").instantiate()
	_body = body
	body.rotation.y = PI          # modèle : avant vers -Z ; véhicule Godot : avant vers +Z
	add_child(body)
	_materials(body)
	if meta.get("couleur") is Array and _paint_mat:
		_paint_mat.albedo_color = Color(float(meta.couleur[0]), float(meta.couleur[1]), float(meta.couleur[2]))
	_cs = CollisionShape3D.new()
	var box := BoxShape3D.new()
	var bx: Array = meta.get("box", [1.76, 1.15, 4.24])
	box.size = Vector3(bx[0], bx[1], bx[2])
	_cs.shape = box
	_cs.position = Vector3(0, float(meta.get("box_y", 0.95)), 0)
	add_child(_cs)
	var wb: float = meta.wheelbase; var tr: float = meta.track
	# v6.22 (« roues à moitié enfoncées ») : la roue du modèle du pick-up ne fait que 0,53 m de diamètre (vrai Raptor :
	# ~0,83 m) et la physique des roues de Godot la fait descendre de 4 à 8 cm sous le point de contact. Rayon physique
	# 0,40 m, axe abaissé d'autant (caisse à la même hauteur), roue affichée agrandie un peu moins que le rayon
	# physique : le bas du pneu touche juste le sol, le pneu remplit le passage de roue. Autres voitures (#95) : roue
	# du modèle à la bonne taille, rayon physique = rayon du modèle + 4,5 cm d'enfoncement.
	var r_mod: float = meta.radius
	var r := 0.40 if ranger else r_mod + 0.045
	var ech_roue := (r - 0.045) / r_mod
	var leger := base_masse / 2400.0
	var wheel_scene: PackedScene = load(dossier + "/wheel.glb")
	# #109 : roue empruntée à une autre voiture quand celle du modèle est ratée (meta « roue_de »), mise au même rayon
	var ech_autre := 1.0
	if meta.has("roue_de"):
		var autre := dossier.get_base_dir() + "/" + String(meta.roue_de)
		wheel_scene = load(autre + "/wheel.glb")
		ech_autre = r_mod / float(JSON.parse_string(FileAccess.get_file_as_string(autre + "/meta.json")).radius)
	var trac := String(fiche.traction)
	for i in 4:
		var front := i < 2
		var right := i % 2 == 0
		var w := VehicleWheel3D.new()
		# #126 : autres voitures +5 cm (mesuré : caisse à 4,5 cm au-dessus du sol du modèle, roues 5 cm trop bas dans
		# leurs passages de roue : toutes les voitures du garage paraissaient surélevées)
		w.position = Vector3((-1.0 if right else 1.0) * tr / 2, r_mod + (0.12 if ranger else 0.13) - (r - r_mod), (1.0 if front else -1.0) * wb / 2)
		w.wheel_radius = r
		w.suspension_travel = 0.24 if ranger else 0.16     # pick-up : suspensions Fox à grand débattement
		w.suspension_stiffness = 38.0 if ranger else 48.0
		w.suspension_max_force = 30000.0 * maxf(leger, 0.35)
		w.damping_compression = 0.9
		w.damping_relaxation = 1.4
		w.wheel_friction_slip = adherence
		w.wheel_roll_influence = 0.03
		w.use_as_steering = front
		w.use_as_traction = trac == "4x4" or (trac == "avant") == front
		var v: Node3D = wheel_scene.instantiate()
		_materials(v)
		v.rotation.y = 0.0 if right else PI
		v.scale = Vector3(1.1 if ranger else 1.0, ech_roue, ech_roue) * ech_autre
		w.add_child(v)
		add_child(w)
		wheels.append(w)
	for n in body.find_children("*", "MeshInstance3D", true, false):
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if not ia:
		_steering_wheel(meta)
	(_blob.mesh as PlaneMesh).size = Vector2(gabarit.x * 1.15, gabarit.z * 0.91)
	if tuning:
		tuning.lier()
	if lights_on:
		set_lights(true)                 # #126 : la nuit, la nouvelle voiture rallume ses phares
	# le sprite pixel art (option masquée depuis la v6.0) n'est construit qu'à la demande : ses 4 planches non
	# compressées occupaient ~170 Mo de mémoire vidéo pour rien (cause probable de l'image figée, v6.5)

## ---------------------------------------------------------------- voiture en sprite pixel art
## Atlas précalculé (blender_sprite.py + build_car_sprite.py) : la vue est choisie selon la direction de la caméra
## dans le repère de la voiture (32 angles × 4 hauteurs) et le braquage ; la caisse 3D ne fait plus que son ombre.
## Depuis la v4.0, le modèle 3D est de nouveau affiché par défaut (le sprite reste au choix dans les réglages).
var sprite_mode := false
var view_mode := 0                   # mode de caméra (0 poursuite) : le sprite ne sert qu'en vue extérieure
var _sprite: MeshInstance3D
var _sprite_mat: ShaderMaterial
var _sp := {}

var _pages := []                     # pages de l'atlas : [couleurs, feux]
var _page := -1
var _ai := -1                        # vue en cours (angle, hauteur, braquage) : hystérésis contre le papillotement
var _ei := -1
var _si := 1
var _blob_soft: Material
var _blob_px: Material
## Pluie qui tombe (main.gd) : gouttes sur les vitres du sprite, essuie-glace arrière.
var rain := 0.0
var _sprite_y := 0.0
var _prev_v := Vector3.ZERO
var _lat := 0.0                       # accélération latérale vue de la caméra (lissée)
var _sq := 0.0                        # ressort de l'écrasement (bosses, réceptions)
var _sq_v := 0.0
var _jolt := RandomNumberGenerator.new()

func _make_sprite() -> void:
	if not FileAccess.file_exists("res://assets/car/sprite.json"):
		sprite_mode = false
		return
	_sp = JSON.parse_string(FileAccess.get_file_as_string("res://assets/car/sprite.json"))
	var qm := QuadMesh.new()
	qm.size = Vector2(_sp.size[0], _sp.size[1])
	for pg in int(_sp.get("pages", 1)):
		var sfx := "" if pg == 0 else str(pg + 1)
		_pages.append([load("res://assets/car/sprite%s.png" % sfx), load("res://assets/car/sprite_feux%s.png" % sfx)])
	_sprite_mat = ShaderMaterial.new()
	_sprite_mat.shader = preload("res://scripts/car_sprite.gdshader")
	_sprite_mat.set_shader_parameter("grid", Vector2(_sp.cols, _sp.rows))
	_sprite_mat.set_shader_parameter("half_h", float(_sp.size[1]) * 0.5)
	if _sp.has("frame"):
		_sprite_mat.set_shader_parameter("frame", Vector2(_sp.frame[0], _sp.frame[1]))
	_set_page(0)
	preload("res://scripts/env.gd").add(_sprite_mat)
	_sprite = MeshInstance3D.new()
	_sprite.mesh = qm
	_sprite.material_override = _sprite_mat
	_sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sprite.extra_cull_margin = 6.0
	_sprite.position = Vector3(0, float(_sp.center_y), 0)
	add_child(_sprite)
	# ombre en pixel art (vue de dessus, bord tramé) à la place de l'ombre douce et de l'ombre portée de la caisse
	_blob_soft = _blob.material_override
	if ResourceLoader.exists("res://assets/car/ombre.png"):
		var om := StandardMaterial3D.new()
		om.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		om.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR    # v6.19 : bord net, sans mélange
		om.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		om.albedo_texture = load("res://assets/car/ombre.png")
		om.render_priority = -1
		_blob_px = om
	sprite_mode = false                      # v6.0 : sprite pixel art masqué, modèle 3D seulement
	_apply_sprite()

func _set_page(pg: int) -> void:
	if pg == _page or pg >= _pages.size():
		return
	_page = pg
	_sprite_mat.set_shader_parameter("atlas", _pages[pg][0])
	_sprite_mat.set_shader_parameter("feux", _pages[pg][1])

func set_sprite_mode(on: bool) -> void:
	if on and _sprite == null:
		_make_sprite()
	sprite_mode = on and _sprite != null
	_apply_sprite()

func set_view_mode(m: int) -> void:
	view_mode = m
	_apply_sprite()

func _apply_sprite() -> void:
	if _sprite == null:
		return
	var on := sprite_mode and view_mode == 0 and not blown
	_sprite.visible = on
	# en sprite, la caisse 3D disparaît tout à fait (ombre comprise) : l'ombre est celle, en pixel art, du sol
	if not blown:
		_body.visible = not on
		for w in wheels:
			for n in w.get_children():
				if n is Node3D:
					n.visible = not on
	if _blob_px:
		_blob.material_override = _blob_px if on else _blob_soft
	if view_mode == 1:
		return                       # vue conducteur : set_cockpit gère la caisse
	for n in _body.find_children("*", "MeshInstance3D", true, false):
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if _wheel_node:
		if blown:
			_volant_avant = not on
		else:
			_wheel_node.visible = not on

func _process(_dt: float) -> void:
	var t0_perf := Time.get_ticks_usec()
	if _phares_factices:
		_maj_phares_factices()
	_process_corps(_dt)
	PerfMon.note("car", Time.get_ticks_usec() - t0_perf)

func _process_corps(_dt: float) -> void:
	if _sprite == null or not _sprite.visible:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	# hauteur du sprite prise sur le sol (points de contact des roues), pas sur la caisse suspendue : la voiture ne
	# monte ni ne descend à l'écran quand elle accélère ou freine
	var gy := 0.0
	var nc := 0
	for w in wheels:
		if w.is_in_contact():
			gy += w.get_contact_point().y
			nc += 1
	var want_y := gy / nc + float(_sp.center_y) if nc >= 3 else (global_basis * Vector3(0, float(_sp.center_y), 0) + global_position).y
	_sprite_y = want_y if absf(_sprite_y - want_y) > 1.5 else lerpf(_sprite_y, want_y, 0.25)
	_sprite.global_position = Vector3(global_position.x, _sprite_y, global_position.z)
	var c := _sprite.global_position
	# direction de la caméra dans le repère de la voiture réduit à son cap : le tangage (accélération, freinage) ne
	# change pas de vue, la caisse ne « plonge » pas ; le roulis est rendu en tournant le sprite
	var zh := Vector3(global_basis.z.x, 0.0, global_basis.z.z).normalized()
	var xh := Vector3.UP.cross(zh)
	var v := cam.global_position - c
	var rel := Vector3(v.dot(xh), v.y, v.dot(zh))
	var az := atan2(rel.x, -rel.z)
	var el := rad_to_deg(atan2(rel.y, Vector2(rel.x, rel.z).length()))
	var n_az := int(_sp.n_az)
	var fa := az / TAU * n_az
	if _ai < 0 or absf(wrapf(fa - _ai, -n_az * 0.5, n_az * 0.5)) > 0.62:
		_ai = posmod(int(round(fa)), n_az)
	var els: Array = _sp.els
	var best := 0
	for i in els.size():
		if absf(el - float(els[i])) < absf(el - float(els[best])):
			best = i
	if _ei < 0 or absf(el - float(els[best])) + 3.0 < absf(el - float(els[_ei])):
		_ei = best
	var n_st: int = (_sp.steers as Array).size()
	if n_st == 3:
		if steer_value > 0.16:
			_si = 2
		elif steer_value < -0.16:
			_si = 0
		elif absf(steer_value) < 0.08:
			_si = 1
	else:
		_si = 0
	var idx := (_ei * n_az + _ai) * n_st + _si
	var cols := int(_sp.cols)
	var per := cols * int(_sp.rows)
	_set_page(idx / per)
	var k := idx % per
	_sprite_mat.set_shader_parameter("cell", Vector2(k % cols, k / cols))
	var rb = (_sp.rear as Array)[idx] if _sp.has("rear") else null
	_sprite_mat.set_shader_parameter("rear", Vector4(rb[0], rb[1], rb[2] + 1, rb[3] + 1) if rb is Array else Vector4.ZERO)
	_sprite_mat.set_shader_parameter("rain", rain)
	# roulis / tangage de la caisse vus de la caméra
	var up_v := cam.global_basis.inverse() * global_basis.y
	_sprite_mat.set_shader_parameter("roll", atan2(up_v.x, up_v.y))
	_squash_stretch(cam, get_process_delta_time())
	_sprite_mat.set_shader_parameter("head", 1.0 if lights_on else 0.0)
	_sprite_mat.set_shader_parameter("tail", (0.8 if lights_on else 0.0) + (1.2 if brake > 1.0 else 0.0))

## Le sprite vit un peu (comme dans les jeux de course en pixel art) : il penche vers l'extérieur des virages selon
## l'accélération latérale vue de la caméra, s'écrase sur les bosses et à la réception d'un saut puis rebondit, et
## tressaute sur l'herbe et les chemins. Jamais d'effet de l'accélération en ligne droite (pas de « plongée »).
func _squash_stretch(cam: Camera3D, dt: float) -> void:
	if dt <= 0.0:
		return
	var v := linear_velocity
	var acc := (v - _prev_v) / dt
	_prev_v = v
	var lat_w := global_basis.x * acc.dot(global_basis.x)            # composante latérale (virage, dérapage)
	var target := clampf(-lat_w.dot(cam.global_basis.x) * 0.012, -0.16, 0.16)
	_lat = lerpf(_lat, target, 1.0 - exp(-dt * 6.0))
	# ressort vertical : choc de l'accélération verticale, plus des à-coups sur les surfaces irrégulières
	var kick := clampf(acc.y * 0.004, -0.25, 0.25)
	var rough := 0.0
	for w in wheels:
		if w.is_in_contact():
			var b: Node3D = w.get_contact_body()
			if b == null or not b.has_meta("surface") or String(b.get_meta("surface")) == "dirt":
				rough += 0.25
	var spd := clampf(kmh() / 60.0, 0.0, 1.0)
	_sq_v += (-140.0 * _sq - 9.0 * _sq_v) * dt + kick * 22.0 * dt + _jolt.randf_range(-1.0, 1.0) * rough * spd * 0.9
	_sq = clampf(_sq + _sq_v * dt, -0.12, 0.18)
	_sprite_mat.set_shader_parameter("shear", _lat)
	_sprite_mat.set_shader_parameter("squash", _sq)

var _wheel_node: Node3D
var _volant_avant := true            # visibilité du volant 3D avant l'explosion
var _wheel_rim: Node3D
var _blob: MeshInstance3D

## Volant (à la place mesurée sur le modèle), incliné de 62° et tourné avec la direction.
func _steering_wheel(meta: Dictionary) -> void:
	var p := Vector3(-float(meta.steer[0]), float(meta.steer[1]), -float(meta.steer[2]))
	_wheel_node = Node3D.new()
	add_child(_wheel_node)
	_wheel_node.position = p
	# colonne de direction : vers le conducteur (arrière, -Z) et vers le haut, à 28° de l'horizontale
	_wheel_node.basis = Basis(Vector3.RIGHT, deg_to_rad(28.0))
	_wheel_rim = Node3D.new()
	_wheel_node.add_child(_wheel_rim)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.06, 0.06, 0.065); mat.roughness = 0.55
	var ring := TorusMesh.new()
	ring.inner_radius = 0.165; ring.outer_radius = 0.2; ring.rings = 28; ring.ring_segments = 8
	var rim := MeshInstance3D.new(); rim.mesh = ring; rim.material_override = mat
	rim.rotation.x = PI / 2                         # anneau dans le plan xy (axe de rotation = z)
	_wheel_rim.add_child(rim)
	for a in [0.0, 2.2, -2.2]:
		var sp := BoxMesh.new(); sp.size = Vector3(0.17, 0.028, 0.02)
		var s := MeshInstance3D.new(); s.mesh = sp; s.material_override = mat
		s.rotation.z = a + PI / 2 if a != 0.0 else -PI / 2
		s.position = Vector3(cos(s.rotation.z), sin(s.rotation.z), 0) * 0.09
		_wheel_rim.add_child(s)
	var hub := CylinderMesh.new(); hub.top_radius = 0.06; hub.bottom_radius = 0.065; hub.height = 0.05
	var h := MeshInstance3D.new(); h.mesh = hub; h.material_override = mat; h.rotation.x = PI / 2
	_wheel_rim.add_child(h)
	var col := CylinderMesh.new(); col.top_radius = 0.035; col.bottom_radius = 0.045; col.height = 0.35
	var c := MeshInstance3D.new(); c.mesh = col; c.material_override = mat; c.rotation.x = PI / 2; c.position.z = 0.19
	_wheel_node.add_child(c)

func _materials(root: Node) -> void:
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.015, 0.015, 0.018)           # noir verni
	paint.metallic = 0.0; paint.roughness = 0.32
	paint.clearcoat_enabled = true; paint.clearcoat = 0.8; paint.clearcoat_roughness = 0.1
	var glass := StandardMaterial3D.new()
	# v6.19 : vitres opaques (verre fumé très sombre, reflets par metallic/roughness), pas de transparence
	glass.albedo_color = Color(0.035, 0.045, 0.055)
	glass.metallic = 0.6; glass.roughness = 0.04
	var chrome := StandardMaterial3D.new()
	chrome.albedo_color = Color(0.8, 0.8, 0.82); chrome.metallic = 1.0; chrome.roughness = 0.15
	var rubber := StandardMaterial3D.new()
	rubber.albedo_color = Color(0.03, 0.03, 0.035); rubber.roughness = 0.9
	var plastic := StandardMaterial3D.new()
	plastic.albedo_color = Color(0.05, 0.05, 0.055); plastic.roughness = 0.6
	var vcol := StandardMaterial3D.new()
	vcol.vertex_color_use_as_albedo = true; vcol.roughness = 0.5
	var lamp := StandardMaterial3D.new()
	lamp.albedo_color = Color(0.85, 0.88, 0.9); lamp.metallic = 0.5; lamp.roughness = 0.1
	var tail := StandardMaterial3D.new()
	tail.albedo_color = Color(0.7, 0.03, 0.03); tail.roughness = 0.2
	# faces intérieures (vue conducteur) : garnitures sombres au lieu de faces invisibles
	var inner := StandardMaterial3D.new()
	inner.albedo_color = Color(0.09, 0.09, 0.1); inner.roughness = 0.85
	inner.cull_mode = BaseMaterial3D.CULL_FRONT
	for m in [paint, plastic, chrome, rubber, lamp, tail, vcol]:
		m.next_pass = inner
	var beige := StandardMaterial3D.new()                    # boucliers et bas de caisse beige doré
	beige.albedo_color = Color(0.58, 0.50, 0.35); beige.metallic = 0.3; beige.roughness = 0.42
	var orange := StandardMaterial3D.new()
	orange.albedo_color = Color(0.95, 0.42, 0.04); orange.roughness = 0.2
	var fog := StandardMaterial3D.new()
	fog.albedo_color = Color(0.95, 0.78, 0.1); fog.roughness = 0.15
	for m in [beige, orange, fog]:
		m.next_pass = inner
	var cover := StandardMaterial3D.new()                    # couvercle de benne blanc
	cover.albedo_color = Color(0.86, 0.87, 0.87); cover.roughness = 0.35
	cover.next_pass = inner
	var hub := StandardMaterial3D.new()                      # enjoliveurs argentés
	hub.albedo_color = Color(0.72, 0.73, 0.75); hub.metallic = 0.45; hub.roughness = 0.35
	if _lamp_mat == null:
		_lamp_mat = lamp; _tail_mat = tail
	if _paint_mat == null:
		_paint_mat = paint
	var by_name := {"cover": cover, "hubcap": hub, "paint": paint, "beige": beige, "orange": orange, "fog": fog, "glass": glass, "chrome": chrome, "rubber": rubber, "plastic": plastic,
		"lamp": lamp, "tail": tail, "interior": vcol, "plate_front": vcol, "plate_rear": vcol}
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		# #130 : toujours en pleine définition. Les niveaux de détail faits à l'import déchirent les modèles en pièces
		# séparées (2CV « toute pétée » en Économie, image calculée en petite résolution) ; la voiture est toujours près
		mi.lod_bias = 64.0
		for s in mi.mesh.get_surface_count():
			var m: Material = mi.mesh.surface_get_material(s)
			var nm := m.resource_name if m else ""
			if by_name.has(nm):
				mi.set_surface_override_material(s, by_name[nm])

var _body: Node3D
var blown := false
## Portée par le rayon tracteur du gardien : position tenue par lui, plus de conduite ni de remise sur la route.
var carried := false

## Ombre de contact posée sur le sol (rayon vers le bas), estompée quand la voiture décolle.
func _place_blob() -> void:
	var o := global_position + global_basis.y * 1.0
	var q := PhysicsRayQueryParameters3D.create(o, o - Vector3(0, 3.0, 0))
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		_blob.visible = false
		return
	var gap := global_position.y - float(hit.position.y)
	_blob.visible = gap < 1.2
	_blob.global_position = Vector3(global_position.x, float(hit.position.y) + 0.04, global_position.z)
	# v6.19 : l'ombre rétrécit par seuil d'alpha (GeometryInstance3D.transparency forcerait le mélange)
	var mat_b := _blob.material_override as StandardMaterial3D
	if mat_b:
		mat_b.albedo_color.a = 1.0 - clampf(gap / 1.2, 0.0, 1.0)

## Vue cockpit (habitacle en pixel art) : la caisse 3D ne fait plus que porter son ombre, le volant 3D disparaît.
func set_cockpit(on: bool) -> void:
	for n in _body.find_children("*", "MeshInstance3D", true, false):
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if on else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if _wheel_node:
		if blown:
			_volant_avant = not on           # rendu à la réapparition (#129 : vue changée pendant l'explosion)
		else:
			_wheel_node.visible = not on
	if not on:
		_apply_sprite()

## Explosion (gardien des limites) : la voiture disparaît et s'immobilise jusqu'à sa réapparition.
func blow_up() -> void:
	blown = true
	_body.visible = false
	if _sprite:
		_sprite.visible = false
	_blob.visible = false
	for w in wheels:
		w.visible = false
	if _wheel_node:                      # #126 : le volant 3D restait suspendu en l'air pendant l'explosion
		_volant_avant = _wheel_node.visible
		_wheel_node.visible = false
	for q in _coronas:
		q.visible = false
	freeze = true

## #164 (règle de l'utilisateur) : choc entre deux véhicules (voitures du joueur et des IA, circulation, voitures
## garées) : explosion seulement si l'un roulait à plus de VITESSE_BOUM et que leurs vitesses (avant le choc)
## diffèrent d'au moins ECART_BOUM ; c'est alors le plus lent qui explose. Un choc n'est jugé qu'une fois (les deux
## voitures le voient).
const ECART_BOUM := 30.0            # km/h
var _vitesses := PackedFloat32Array([0.0, 0.0, 0.0])     # m/s aux trois derniers pas (la plus ancienne : avant le choc)
static var _chocs_vus := {}         # paire d'instances -> instant (s)

func vitesse_avant() -> float:
	return _vitesses[0]

static func est_vehicule(b: Object) -> bool:
	return b is VehicleBody3D or (b is Node and (b as Node).has_meta("vehicule"))

## Vitesse (km/h) d'un véhicule juste avant un choc : voiture (trois pas plus tôt), épave de la circulation (sa vitesse
## au moment de l'accident), voiture garée (0).
static func vitesse_de(b: Object) -> float:
	if b is VehicleBody3D and b.has_method("vitesse_avant"):
		return b.vitesse_avant() * 3.6
	if b is Node and (b as Node).has_meta("v_avant"):
		return float((b as Node).get_meta("v_avant")) * 3.6
	return (b as RigidBody3D).linear_velocity.length() * 3.6 if b is RigidBody3D else 0.0

## Juge le choc entre les véhicules a et b (km/h avant le choc : va, vb) ; fait exploser le plus lent, le renvoie (ou null).
static func juger(a: Object, va: float, b: Object, vb: float) -> Object:
	var ia := a.get_instance_id(); var ib := b.get_instance_id()
	var cle := "%d-%d" % [mini(ia, ib), maxi(ia, ib)]
	var now := Time.get_ticks_msec() / 1000.0
	if _chocs_vus.has(cle) and now - float(_chocs_vus[cle]) < 1.5:
		return null
	if _chocs_vus.size() > 64:
		_chocs_vus.clear()
	_chocs_vus[cle] = now
	if OS.get_cmdline_user_args().has("--choc-debug"):
		print("[choc] véhicules : %.0f et %.0f km/h" % [va, vb])
	if maxf(va, vb) < VITESSE_BOUM or absf(va - vb) < ECART_BOUM:
		return null
	var lent: Object = a if va < vb else b
	_faire_exploser(lent)
	return lent

static func _faire_exploser(v: Object) -> void:
	if not (v is Node) or not (v as Node).is_inside_tree():
		return
	var main: Node = (v as Node).get_tree().current_scene
	if v is VehicleBody3D and v.has_method("exploser"):
		if v.ia:
			(v as Node).set_meta("boum", true)          # son pilote (gendarme.gd, concurrent.gd) s'en charge
		else:
			if main and main.get("sound") and main.sound.has_method("boum"):
				main.sound.boum()
			v.exploser()
	elif (v as Node).has_meta("garee") and main and main.get("props"):
		main.props.exploser_garee(v)
	elif (v as Node).has_meta("epave") and main and main.get("circulation"):
		main.circulation.exploser_epave(v)

## #121 : choc contre un obstacle indestructible au-delà de VITESSE_BOUM (vitesse perdue d'un coup, détectée par
## audio.gd) : explosion (#129, explosion.gd : champignon atomique), puis la voiture revient sur la route.
const VITESSE_BOUM := 60.0          # km/h
var style_explosion := "atomique"    # #129 : champignon atomique (choix C de l'utilisateur) ; « film », « mini » : essais
func exploser() -> void:
	if blown or carried:
		return
	if get_parent().get("carriere"):
		get_parent().carriere.explosion()                # carrière (#120) : le KA-BOOM coûte de la réputation
	if not ia and get_parent().get("succes"):
		get_parent().succes.noter("explosions")          # succès (#133)
	var fx = preload("res://scripts/explosion.gd").new()
	fx.style = style_explosion
	fx.position = global_position - Vector3(0, 0.3, 0)       # avant add_child : _ready lit le sol sous ce point
	get_parent().add_child(fx)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	blow_up()
	await get_tree().create_timer(float(fx.duree) + 0.1).timeout
	respawn_at(Vector3.INF, 0.0)

## Réapparition après l'explosion (position et cap choisis par le gardien ; INF : route la plus proche).
func respawn_at(p: Vector3, heading_deg: float) -> void:
	freeze = false
	if p.is_finite():
		place(p, heading_deg)
	else:
		reset_to_road()
	hold(0.5)
	_body.visible = true
	_blob.visible = true
	for w in wheels:
		w.visible = true
	if _wheel_node:
		_wheel_node.visible = _volant_avant
	blown = false
	_maj_coronas(lights_on)
	_apply_sprite()

var _lamp_mat: StandardMaterial3D
var _paint_mat: StandardMaterial3D

## Pluie : carrosserie mouillée, plus brillante.
func set_wet(w: float) -> void:
	if _paint_mat:
		_paint_mat.roughness = lerpf(0.32, 0.08, w)
		_paint_mat.clearcoat_roughness = lerpf(0.1, 0.02, w)
	if tuning:
		tuning.mouille(w)
var _tail_mat: StandardMaterial3D
var _beams := []
var _meta := {}

## Phares (soir, nuit) : deux faisceaux, optiques et feux arrière lumineux. Réglage Économie (#124) : pas de vraies
## lampes, la lumière des phares est calculée par le sol, les routes et les murs (env.gdshaderinc, env_phares_lum).
var _phares_factices := false
var lights_on := false
func set_lights(on: bool) -> void:
	lights_on = on
	_phares_factices = on and int(Engine.get_meta("niveau_perf", 1)) == 0
	if not _phares_factices:
		preload("res://scripts/env.gd").set_phares(Vector4.ZERO, Vector4(0, 0, 1, 45), Vector3.ONE)
	if _beams.is_empty() and on and not _phares_factices:
		var bm := _phares_pos()
		for sx in [-bm.x, bm.x]:
			var s := SpotLight3D.new()
			s.position = Vector3(sx, bm.y, bm.z)
			s.rotation = Vector3(deg_to_rad(-4.0), PI, 0)        # vers l'avant (+Z) et un peu vers le bas
			s.spot_range = 45.0
			s.spot_angle = 28.0
			s.spot_attenuation = 0.8
			s.light_energy = 6.0
			s.light_color = phare_couleur
			s.shadow_enabled = false
			add_child(s)
			_beams.append(s)
	for s in _beams:
		s.visible = on and not _phares_factices
	_maj_coronas(on)
	if _lamp_mat:
		_lamp_mat.emission_enabled = on
		_lamp_mat.emission = Color(1.0, 0.95, 0.85)
		_lamp_mat.emission_energy_multiplier = 3.0
	if _tail_mat:
		_tail_mat.emission_enabled = on
		_tail_mat.emission = Color(0.9, 0.05, 0.03)
		_tail_mat.emission_energy_multiplier = 2.0

## Position des phares (x = demi-écart, y = hauteur, z = avant) d'après meta.json. #126 : pour quatre voitures du garage
## (Clia, Deuche, Espèce, Porc'Che : z = 3,8 / 2,6 / 4,8 / -17 m), blender_voitures_joueur.py a mesuré l'avant sur une
## pièce qui dépasse : faisceaux devant la voiture dans le vide, ou derrière elle. Hors du nez de la caisse, on
## prend le bout de la caisse (dims[0] = longueur).
func _phares_pos() -> Vector3:
	var bm: Array = _meta.get("beams", [0.585, 0.69, 2.2])
	var z := float(bm[2])
	var dims: Array = _meta.get("dims", [])
	if dims.size() >= 1:
		var demi := float(dims[0]) * 0.5
		if z < demi * 0.75 or z > demi * 1.15:
			z = demi - 0.12
	return Vector3(float(bm[0]), float(bm[1]), z)

## #126 : halos des phares et des feux arrière (« coronas », comme GTA) : la plupart des voitures du garage ont leurs
## optiques peintes dans une texture, donc rien ne s'allumait la nuit. Disque lumineux face à la caméra, posé au nez et à
## l'arrière de la caisse, visible seulement du côté où l'optique regarde.
var _coronas: Array = []
const CORONA_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, skip_vertex_transform;
uniform vec3 coul : source_color = vec3(1.0, 0.95, 0.82);
uniform float taille = 0.5;
uniform float sens = 1.0;          // +1 : optique vers l'avant de la voiture, -1 : vers l'arrière
varying float v_face;
void vertex() {
	vec3 c = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 axe = normalize((MODELVIEW_MATRIX * vec4(0.0, 0.0, sens, 0.0)).xyz);
	v_face = smoothstep(0.05, 0.5, dot(axe, normalize(-c)));
	c += normalize(-c) * 0.12;      // un peu vers la caméra : pas coupé par le bord de la caisse
	VERTEX = c + vec3(VERTEX.xy * taille, 0.0);
}
void fragment() {
	float k = pow(clamp(1.0 - length(UV - 0.5) * 2.0, 0.0, 1.0), 1.6) * v_face;
	ALBEDO = coul * (0.7 + 1.6 * k);
	const float BAYER[16] = { 0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0 };
	if (k <= (BAYER[int(mod(FRAGCOORD.x, 4.0)) + int(mod(FRAGCOORD.y, 4.0)) * 4] + 0.5) / 16.0) {
		discard;
	}
}
"""
func _maj_coronas(on: bool) -> void:
	if on and _coronas.is_empty() and _body:
		var bm := _phares_pos()
		var dims: Array = _meta.get("dims", [])
		var bx: Array = _meta.get("box", [1.76, 1.15, 4.24])
		var arr := -(float(dims[0]) * 0.5 - 0.1) if dims.size() >= 1 else -float(bx[2]) * 0.5
		var sh := Shader.new()
		sh.code = CORONA_SHADER
		for f in [[bm.z, Color(1.0, 0.95, 0.82), 0.55, 1.0], [arr, Color(1.0, 0.1, 0.06), 0.34, -1.0]]:
			var m := ShaderMaterial.new()
			m.shader = sh
			m.set_shader_parameter("coul", f[1])
			m.set_shader_parameter("taille", f[2])
			m.set_shader_parameter("sens", f[3])
			var qm := QuadMesh.new()
			qm.material = m
			for sx in [-bm.x, bm.x]:
				var q := MeshInstance3D.new()
				q.mesh = qm
				q.position = Vector3(sx, bm.y, f[0])
				q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(q)
				_coronas.append(q)
	for q in _coronas:
		q.visible = on and not blown

func _maj_phares_factices() -> void:
	var bm := _phares_pos()
	var p := global_transform * Vector3(0.0, bm.y, bm.z)
	var d := (global_basis * Vector3(0.0, -0.07, 1.0)).normalized()
	var on := visible and not blown
	preload("res://scripts/env.gd").set_phares(Vector4(p.x, p.y, p.z, 1.7 if on else 0.0), Vector4(d.x, d.y, d.z, 45.0),
		Vector3(phare_couleur.r, phare_couleur.g, phare_couleur.b))

func place(p: Vector3, heading_deg: float) -> void:
	# cap : 0 = Nord (-Z), sens horaire ; l'avant du véhicule est +Z
	var b := Basis(Vector3.UP, PI - deg_to_rad(heading_deg))
	global_transform = Transform3D(b, p)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	safe = [global_transform]

## Maintient la voiture immobile à sa place (téléportation : le temps que le décor et les collisions se chargent).
func hold(t: float) -> void:
	_hold_t = t
	_hold_xf = global_transform

func kmh() -> float:
	return linear_velocity.length() * 3.6

func forward_speed() -> float:
	return linear_velocity.dot(global_transform.basis.z)

func _physics_process(dt: float) -> void:
	if blown:
		return
	_vitesses[0] = _vitesses[1]; _vitesses[1] = _vitesses[2]; _vitesses[2] = linear_velocity.length()
	if contact_monitor and not ia:
		for b in get_colliding_bodies():                 # #164 : choc avec un autre véhicule
			if est_vehicule(b) and juger(self, vitesse_avant() * 3.6, b, vitesse_de(b)) == self:
				return
	if carried:
		_place_blob()
		return
	_place_blob()
	if _hold_t > 0.0:
		_hold_t -= dt
		global_transform = _hold_xf
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		return
	# gâchettes de manette : zone morte de 15 % (#65 : une gâchette d'accélérateur qui ne revient pas tout à fait à
	# zéro empêchait la marche arrière)
	var thr := clampf((0.0 if ia else pedale("accelerer")) + touch_throttle, 0.0, 1.0)
	var brk := clampf((0.0 if ia else pedale("freiner")) + touch_brake, 0.0, 1.0)
	if not ia and Input.is_action_just_pressed("frein_parking") and not preload("res://scripts/ui.gd").saisie_active():
		frein_parking = not frein_parking
	if frein_parking and thr > 0.5 and absf(forward_speed()) < 0.3:
		frein_parking = false                       # on accélère franchement : le frein de parking se desserre
	var fm := clampf((0.0 if ia else Input.get_action_strength("frein_main")) + touch_frein_main, 0.0, 1.0)
	frein_main_in = fm
	var st := clampf((0.0 if ia else Input.get_action_strength("gauche") - Input.get_action_strength("droite")) + touch_steer, -1.0, 1.0)
	if not controle:
		thr = 0.0; brk = 0.0; st = 0.0; fm = 0.0
		frein_parking = true
	thr_in = thr; brk_in = brk
	var v := forward_speed()
	# sens de marche « jeu » : la pédale opposée au mouvement freine, puis la voiture repart dans l'autre sens dès
	# qu'elle est presque arrêtée (pas besoin d'attendre l'arrêt complet)
	# pédale dominante (#65) : l'autre peut rester un peu enfoncée sans bloquer le changement de sens
	if brk > 0.1 and brk > thr + 0.15 and v < 0.6:
		reversing = true
	elif thr > 0.1 and thr > brk + 0.15 and v > -0.6:
		reversing = false
	if aide_voie and not reversing:
		st = clampf(st + voie.correction(global_position, global_transform.basis.z, v, st, dt), -1.0, 1.0)
	else:
		voie.actif = false
	var k := clampf(absf(v) * 3.6 / 130.0, 0.0, 1.0)
	var max_steer := lerpf(STEER_LOW, STEER_HIGH, sqrt(k))
	# direction progressive, retour au centre plus rapide
	var target := st * max_steer
	var rate := 2.2 if absf(target) > absf(steer_value) else 3.5
	steer_value = move_toward(steer_value, target, rate * dt)
	steering = steer_value
	if _wheel_rim:
		_wheel_rim.rotation.z = -steer_value * 8.0          # démultiplication : ~ 1 tour de volant pour 0,55 rad
	var spd := absf(v) * 3.6
	if reversing:
		if thr > 0.1 and thr > brk:
			# en reculant, GAZ freine (puis repart en avant, voir plus haut)
			engine_force = 0.0
			brake = BRAKE * k_frein * freinage * thr
		else:
			# (v6.56, #91 : 25 km/h et demi-force avant, on reculait trop lentement)
			engine_force = -force_max * 0.75 / n_motrices * brk if spd < 45.0 else 0.0
			brake = 0.0
	else:
		# boîte auto : force limitée par la puissance (F = P / v), coupée à la vitesse max
		# (engine_force s'applique à chacune des roues motrices : 4 sur le pick-up, 2 sur les tractions et propulsions)
		var f := thr * minf(force_max, puissance / maxf(absf(v), 1.0)) / n_motrices
		if spd > vmax:
			f = 0.0
		engine_force = f if brk < 0.1 or thr > brk else 0.0
		brake = BRAKE * k_frein * freinage * brk + (2.0 if thr < 0.05 and spd < 3.0 and brk < 0.1 else 0.0)
	_nitro(dt, thr, v, spd)
	_glisse_mur(thr, brk, v, st)
	# frein à main (#64) : roues arrière bloquées et moins d'adhérence derrière (dérapage), moteur débrayé ; frein de
	# parking : toutes les roues bloquées, moteur coupé
	for w in wheels:
		var arriere: bool = not w.use_as_steering
		w.wheel_friction_slip = adherence * (0.42 if arriere and fm > 0.3 else 1.0)
	if fm > 0.3 or frein_parking:
		engine_force = 0.0
		if frein_parking:
			brake = BRAKE * k_frein * 2.0
		else:
			for w in wheels:
				w.brake = BRAKE * k_frein * 1.6 * fm if not w.use_as_steering else w.brake
	# le frein des roues de Godot est une impulsion par pas de physique (non multipliée par la durée du pas) : réglé à
	# 120 pas/s, il freinait deux fois moins à 60 pas/s (Économie, #124 : 100 à 0 km/h en 32,7 m au lieu de 23,5 m)
	var k_pas := 120.0 / float(Engine.physics_ticks_per_second)
	if k_pas != 1.0:
		for w in wheels:
			w.brake *= k_pas
	# aide au freinage (pédale opposée au sens de marche), seulement roues au sol
	var pedale := thr if reversing else brk
	if pedale > 0.1 and linear_velocity.length() > 0.5 and wheels.any(func(w): return w.is_in_contact()):
		var vh := linear_velocity - Vector3.UP * linear_velocity.y
		if (not reversing and v > 0.3) or (reversing and v < -0.3):
			apply_central_force(-vh.normalized() * mass * BRAKE_AIDE * freinage * pedale)
	# frein moteur léger et aide à la stabilité en virage (anti-dérive latérale)
	if thr < 0.05 and not reversing:
		apply_central_force(-linear_velocity * 25.0)
	# traînée aérodynamique et résistance au roulement (pneus tout-terrain BFGoodrich KO2)
	apply_central_force(-linear_velocity * linear_velocity.length() * cx)
	if linear_velocity.length() > 0.5:
		apply_central_force(-linear_velocity.normalized() * mass * 9.81 * 0.015)
	var side := global_transform.basis.x
	var lat := linear_velocity.dot(side)
	apply_central_force(-side * lat * mass * 0.6 * 0.5 * 0.05)    # (0,5 = dt × 60 à 120 pas/s : même effet à 60 pas/s)
	_anti_roll()
	if not ia:
		_recovery(dt)

## #106 : accélérer contre un mur ne laisse plus la voiture plantée : elle pivote pour longer le mur et glisse vers la
## gauche ou la droite (côté où le nez est déjà tourné, sinon côté du volant, sinon au hasard, gardé tant qu'on pousse).
var _mur_cote := 0.0
var mur_contact := false             # essais : un mur est devant la voiture et elle glisse
func _glisse_mur(thr: float, brk: float, v: float, st: float) -> void:
	var pousse := brk if reversing else thr
	mur_contact = false
	if pousse < 0.3 or absf(v) > 3.0 or not controle:
		_mur_cote = 0.0
		return
	var sens := -1.0 if reversing else 1.0
	var fwd := global_transform.basis.z * sens
	fwd.y = 0.0
	fwd = fwd.normalized()
	var side := global_transform.basis.x
	side.y = 0.0
	side = side.normalized()
	var ss := get_world_3d().direct_space_state
	var n := Vector3.ZERO
	for dx: float in [0.0, -0.4, 0.4]:
		var o := global_position + Vector3.UP * 0.55 + side * dx * gabarit.x
		var q := PhysicsRayQueryParameters3D.create(o, o + fwd * (gabarit.z * 0.5 + 0.6))
		q.exclude = [get_rid()]
		var h := ss.intersect_ray(q)
		if not h.is_empty() and absf((h.normal as Vector3).y) < 0.6:
			n += h.normal
	n.y = 0.0
	if n.length() < 0.1:
		_mur_cote = 0.0
		return
	n = n.normalized()
	var t := n.cross(Vector3.UP)                       # le long du mur
	if _mur_cote == 0.0:
		var a := fwd.dot(t)
		if absf(a) > 0.12:
			_mur_cote = signf(a)
		elif absf(st) > 0.1:
			_mur_cote = signf(t.dot(side) * st * sens)   # volant à gauche : vers la gauche de la voiture
		else:
			_mur_cote = 1.0 if randf() < 0.5 else -1.0
	t *= _mur_cote
	mur_contact = true
	# le nez tourne pour longer le mur et la caisse glisse le long du mur en s'en décollant un peu ; vitesses imposées
	# (des forces ne suffisaient pas : la caisse plaquée par le moteur restait collée au mur par frottement), moteur
	# réduit pour ne plus la plaquer
	var ang := fwd.signed_angle_to(t, Vector3.UP)
	var av := angular_velocity
	av.y = move_toward(av.y, clampf(ang * 2.0, -1.4, 1.4) * pousse, 0.15)
	angular_velocity = av
	var lv := linear_velocity
	lv += t * (move_toward(lv.dot(t), 3.5 * pousse, 0.12) - lv.dot(t))
	lv += n * (move_toward(lv.dot(n), 0.6, 0.12) - lv.dot(n))
	linear_velocity = lv
	engine_force *= 0.3

## Pédale d'une gâchette ou d'une touche, 0 à 1 (v6.56, #91) : beaucoup de manettes sur Android plafonnent leurs
## gâchettes vers 0,8 à 0,95 ; la course pleine est donc calée sur le plus grand enfoncement déjà vu (au moins
## 0,8), après une zone morte de 15 %. Valeur brute de l'action (sans la zone morte de Godot, qui s'ajoutait à la
## nôtre).
static var _course := {"accelerer": 0.8, "freiner": 0.8}
static func pedale(action: String) -> float:
	var x := Input.get_action_raw_strength(action)
	if x > _course[action]:
		_course[action] = minf(x, 1.0)
	var plein: float = _course[action]
	return clampf((x - 0.15) / maxf(plein - 0.15 - 0.03, 0.1), 0.0, 1.0)

## Aide à la stabilité : ramène doucement la caisse à plat autour de son axe longitudinal (roulis), sans toucher au
## tangage (montées, descentes) ; plus ferme en l'air pour retomber sur les roues après un saut.
func _anti_roll() -> void:
	var fwd := global_transform.basis.z
	var up := global_transform.basis.y
	var on_ground := wheels.any(func(w): return w.is_in_contact())
	# angle de roulis : inclinaison de l'axe vertical de la caisse dans le plan perpendiculaire à l'avant
	var ref := (Vector3.UP - fwd * Vector3.UP.dot(fwd)).normalized()
	var roll := up.signed_angle_to(ref, fwd)
	var k := (9000.0 if on_ground else 14000.0) * anti_roulis
	var d := 2500.0
	apply_torque(fwd * (roll * k - angular_velocity.dot(fwd) * d))
	if not on_ground:
		# en l'air : le tangage est aussi amorti pour atterrir à plat
		var right := global_transform.basis.x
		apply_torque(-right * angular_velocity.dot(right) * 1500.0)

func _recovery(dt: float) -> void:
	var p := global_position
	var up := global_transform.basis.y.y
	_safe_t -= dt
	var on_ground := false
	for w in wheels:
		if w.is_in_contact():
			on_ground = true
	if _safe_t <= 0.0 and on_ground and up > 0.85 and kmh() > 3.0:
		_safe_t = 1.0
		safe.append(global_transform)
		if safe.size() > 12:
			safe.pop_front()
	# état aberrant (moteur physique) : remise immédiate
	if not global_transform.origin.is_finite() or not linear_velocity.is_finite() or linear_velocity.length() > 110.0:
		reset_to_road()
		return
	# retourné ou sur le flanc plus de 1,2 s (presque à l'arrêt)
	_flip_t = _flip_t + dt if (up < 0.5 and kmh() < 25.0) else 0.0
	# v6.22 (demande de l'utilisateur) : plus de remise sur la route automatique quand la voiture est bloquée ou
	# coincée à l'arrêt ; il reste le bouton rouge (« replacer »), la voiture retournée et la chute hors du monde
	if p.y < -50.0 or _flip_t > 1.2 or (Input.is_action_just_pressed("replacer") and not preload("res://scripts/ui.gd").saisie_active()):
		reset_to_road()

## Objets du décor qui touchent la carrosserie (diagnostic d'une voiture coincée).
func _touching() -> Array:
	var q := PhysicsShapeQueryParameters3D.new()
	var b := BoxShape3D.new()
	var bx: Array = _meta.get("box", [1.76, 1.15, 4.24])
	b.size = Vector3(bx[0], bx[1], bx[2]) + Vector3(0.4, 0.2, 0.4)
	q.shape = b
	q.transform = global_transform * Transform3D(Basis(), Vector3(0, float(_meta.get("box_y", 0.95)), 0))
	q.exclude = [get_rid()]
	var out := []
	for r in get_world_3d().direct_space_state.intersect_shape(q, 8):
		var c: Object = r.collider
		if c is Node:
			var n := c as Node
			var gp := n.get_parent()
			if gp and not gp.get_script() and gp.get_parent() and gp.get_parent().get_script():
				gp = gp.get_parent()
			var sc: String = (gp.get_script().resource_path.get_file() + ":") if gp and gp.get_script() else ""
			out.append("%s%s/%s%s" % [sc, gp.name if gp else "", n.name, (" " + str(n.get_meta("surface"))) if n.has_meta("surface") else ""])
	return out

## Remise sur la route la plus proche, dans le sens de la voie le plus proche de celui de la voiture.
func reset_to_road() -> void:
	if carried:
		return
	var p := global_position
	if not p.is_finite():
		p = safe[-1].origin if safe.size() > 0 else Vector3.ZERO
	# sens de la marche (#74) : celui où la voiture allait (vitesse), sinon l'avant de la caisse, sinon le dernier
	# cap sûr ; marche arrière : l'avant de la caisse
	var fwd := global_transform.basis.z
	var vh := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	if vh.length() > 3.0 and vh.is_finite() and not reversing:
		fwd = vh
	elif not (fwd.is_finite() and Vector2(fwd.x, fwd.z).length() > 0.2) and safe.size() > 0:
		fwd = safe[-1].basis.z
	var yaw_ok := fwd.is_finite() and Vector2(fwd.x, fwd.z).length() > 0.2
	var best := -1
	var bd := 1e18
	for i in range(0, road_pts.size(), 4):
		var dx := road_pts[i] - p.x
		var dz := road_pts[i + 1] - p.z
		var d := dx * dx + dz * dz
		if d > bd:
			continue
		if yaw_ok:
			# cap du point (0 = Nord = -Z, sens horaire) -> direction ; sens opposé pénalisé de 60 m (#74 : toujours
			# dans le sens de la marche, sauf si la route dans ce sens est bien plus loin : pas de raccourci)
			var h := deg_to_rad(road_pts[i + 3])
			if Vector2(sin(h), -cos(h)).dot(Vector2(fwd.x, fwd.z).normalized()) < 0.3:
				d += 3600.0
		if d < bd:
			bd = d; best = i
	if best >= 0:
		place(Vector3(road_pts[best], road_pts[best + 2] + 0.3, road_pts[best + 1]), road_pts[best + 3])
	else:
		var t: Transform3D = safe[max(0, safe.size() - 3)] if safe.size() > 0 else global_transform
		global_transform = Transform3D(Basis(Vector3.UP, t.basis.get_euler().y), t.origin + Vector3(0, 0.8, 0))
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
	_flip_t = 0.0; _stuck_t = 0.0; _jam_t = 0.0; _jam_ref = global_position

## Nitro (#98) : poussée vers l'avant tant qu'on tient le bouton et qu'il reste de la jauge.
func _nitro(dt: float, thr: float, v: float, spd: float) -> void:
	if nitro_niveau <= 0 or not controle:
		nitro_actif = false
		return
	var veut := (not ia and Input.is_action_pressed("nitro") and not preload("res://scripts/ui.gd").saisie_active()) or touch_nitro > 0.5
	nitro_actif = veut and nitro_jauge > 0.0 and not reversing and v > -0.5 and spd < vmax + 50.0 \
		and wheels.any(func(w): return w.is_in_contact())
	_flamme_nitro()
	if nitro_actif:
		nitro_jauge = maxf(0.0, nitro_jauge - dt / NITRO_DUREE[nitro_niveau])
		apply_central_force(global_transform.basis.z * mass * NITRO_ACC[nitro_niveau])
	elif not veut:
		var lat := absf(linear_velocity.dot(global_transform.basis.x))
		var rech := 0.03 if spd > 30.0 else 0.0           # en roulant : ~33 s pour une jauge pleine
		if lat > 3.0 and spd > 25.0:
			rech += 0.18                                    # en dérapant : ~5 s
		nitro_jauge = minf(1.0, nitro_jauge + rech * dt)

## Flamme bleue à l'arrière pendant le nitro (cône émissif qui vacille).
var _flamme: MeshInstance3D
func _flamme_nitro() -> void:
	if _flamme == null:
		_flamme = MeshInstance3D.new()
		var cm := CylinderMesh.new(); cm.top_radius = 0.0; cm.bottom_radius = 0.16; cm.height = 0.9
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.45, 0.75, 1.0)
		m.emission_enabled = true; m.emission = Color(0.4, 0.7, 1.0); m.emission_energy_multiplier = 3.0
		cm.material = m
		_flamme.mesh = cm
		_flamme.rotation = Vector3(-PI / 2, 0, 0)            # pointe vers l'arrière (-Z)
		_flamme.position = Vector3(0.55, 0.42, -2.95)
		_flamme.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_flamme)
	_flamme.visible = nitro_actif
	if nitro_actif:
		var k := randf_range(0.8, 1.3)
		_flamme.scale = Vector3(1.0, k, 1.0)

## Couleur des phares (garage, v6.58) : appliquée aussi aux faisceaux déjà allumés.
func set_phares(c: Color) -> void:
	phare_couleur = c
	for b in _beams:
		if is_instance_valid(b):
			b.light_color = c
