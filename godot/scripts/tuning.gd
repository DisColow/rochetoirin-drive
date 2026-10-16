## Améliorations montées sur la voiture du joueur (garage, issue #43 ; catalogue et argent : garage.gd).
##   - Technique : puissance et vitesse max (moteur), force au démarrage (boîte), hauteur et fermeté (suspension),
##     freinage, adhérence (pneus) : variables de car.gd et réglages des VehicleWheel3D.
##   - Peinture : couleur, finition et vinyles dans carrosserie.gdshader (surfaces « paint » de la caisse).
##   - Carrosserie : vitres, néons (lumière sous la caisse + tubes), pièces posées sur la caisse (formes simples faites
##     ici, ou modèles assets/garage/<rubrique>.glb s'ils existent), jantes (modèle de roue remplacé).
## Repère de la voiture : x à gauche, y en haut, z vers l'avant ; toit à y 1,70, capot de z 0,9 à 2,1, benne à l'arrière.
extends Node
const Garage := preload("res://scripts/garage.gd")

var car: VehicleBody3D
var garage: Node
var main: Node
var activities: Node                # enseigne TAXI allumée pendant une course de taxi

var _peinture: ShaderMaterial
var _verre: StandardMaterial3D
var _pieces := {}                   # rubrique -> Node3D posé sur la voiture
var _neon: OmniLight3D
var _neon_mat: StandardMaterial3D
var _taxi_mat: StandardMaterial3D
var _led_mat: StandardMaterial3D
var _roues_origine := []            # modèle de roue d'origine de chaque VehicleWheel3D
var _roues_y := []                  # hauteur d'origine des points d'attache des roues
var _mouille := 0.0
var _t := 0.0

# suspension : [décalage des roues (m ; négatif = caisse plus haute), raideur, débattement, amortissement]
const SUSP := [[0.0, 38.0, 0.24, 1.4], [0.07, 60.0, 0.15, 2.0], [-0.10, 34.0, 0.30, 1.3]]
const MOTEUR := [[1.0, 230.0], [1.15, 240.0], [1.3, 252.0], [1.5, 265.0]]   # [puissance ×, vitesse max]
const BOITE := [1.0, 1.12, 1.25]
const FREINS := [1.0, 1.15, 1.3]
const PNEUS := [2.6, 2.95, 3.3]
const JANTES_RETOURNEES := [3]
const DANS_LE_PNEU := 0.74            # diamètre de la nouvelle roue / diamètre extérieur du pneu d'origine
const VITRES := [Color(0.07, 0.085, 0.10), Color(0.035, 0.045, 0.055), Color(0.008, 0.008, 0.01)]

func _ready() -> void:
	car.set("tuning", self)
	_peinture = ShaderMaterial.new()
	_peinture.shader = preload("res://scripts/carrosserie.gdshader")
	_peinture.set_shader_parameter("vin_tex", load("res://assets/garage/vinyles.png"))
	_verre = StandardMaterial3D.new()
	_verre.metallic = 0.6; _verre.roughness = 0.04
	lier()
	garage.vue_changee.connect(func(id: String) -> void:
		car.construire(id)              # appelle lier()
		appliquer())
	garage.change.connect(appliquer)
	appliquer()

## Peinture du garage et vitres posées sur la caisse de la voiture conduite, roues d'origine retenues (jantes,
## suspension) ; refait quand on change de voiture (#95). Les pièces posées sont refaites à l'échelle de la voiture.
func lier() -> void:
	if _peinture == null:
		return                          # car.construire() au démarrage, avant le _ready de tuning
	var origine: Material = car.get("_paint_mat")
	if origine:
		_peinture.next_pass = origine.next_pass                # faces intérieures sombres (vue conducteur)
	var corps: Node3D = car.get("_body")
	var inv := car.global_transform.affine_inverse()
	_peint = false
	for mi in corps.find_children("*", "MeshInstance3D", true, false):
		var m3 := mi as MeshInstance3D
		var vers := inv * m3.global_transform
		for s in m3.mesh.get_surface_count():
			var nm := m3.mesh.surface_get_material(s).resource_name if m3.mesh.surface_get_material(s) else ""
			if m3.get_surface_override_material(s) == origine or nm == "paint":
				_peinture.set_shader_parameter("vers_voiture", Projection(vers))
				m3.set_surface_override_material(s, _peinture)
				_peint = true
			elif nm == "glass":
				m3.set_surface_override_material(s, _verre)
	_roues_origine.clear(); _roues_y.clear()
	for w in car.wheels:
		_roues_origine.append(w.get_child(0))
		_roues_y.append(w.position.y)
	for r in _pieces.keys():
		_pieces[r].queue_free()
	_pieces.clear()
	if _neon:
		_neon.queue_free(); _neon = null

## Pièces du garage dessinées pour le pick-up (repère du Raptor) : ramenées au gabarit des autres voitures.
func _echelle() -> Vector3:
	var g: Vector3 = car.get("gabarit")
	return Vector3(g.x / 2.0, g.y / 1.75, g.z / 5.4)

var _peint := false                 # la voiture a une carrosserie « paint » (sinon, peinture d'origine texturée)

func _process(dt: float) -> void:
	_t -= dt
	if _t > 0.0:
		return
	_t = 0.5
	if _taxi_mat:
		var allume: bool = activities != null and String(activities.get("mode")) == "taxi"
		_taxi_mat.emission_energy_multiplier = 2.2 if allume else 0.0
	if _led_mat:
		var b: Array = car.get("_beams")
		_led_mat.emission_energy_multiplier = 4.0 if (not b.is_empty() and b[0].visible) else 0.0

## Pluie : peinture plus brillante (car.set_wet).
func mouille(w: float) -> void:
	_mouille = w
	_finition()

func appliquer() -> void:
	# technique
	var mo: Array = MOTEUR[garage.choix("moteur")]
	car.puissance = car.base_puissance * float(mo[0])
	car.vmax = car.base_vmax * float(mo[1]) / 230.0
	car.force_max = car.base_force * BOITE[garage.choix("boite")]
	car.freinage = FREINS[garage.choix("freins")]
	car.nitro_niveau = garage.choix("nitro")
	var su: Array = SUSP[garage.choix("suspension")]
	for i in car.wheels.size():
		var w: VehicleWheel3D = car.wheels[i]
		w.position.y = _roues_y[i] + float(su[0])
		w.suspension_stiffness = su[1]
		w.suspension_travel = su[2]
		w.damping_relaxation = su[3]
		w.wheel_friction_slip = PNEUS[garage.choix("pneus")]
	car.adherence = PNEUS[garage.choix("pneus")] * (1.08 if garage.choix("differentiel") > 0 else 1.0)
	car.mass = car.base_masse * [1.0, 0.9375, 0.875][garage.choix("allegement")]
	car.anti_roulis = [1.0, 1.35, 1.7][garage.choix("anti_roulis")]
	car.set_phares([Color(1.0, 0.93, 0.78), Color(0.75, 0.88, 1.0), Color(1.0, 0.82, 0.35), Color(0.75, 0.5, 1.0)][garage.choix("phares")])
	# peinture et vitres
	_peinture.set_shader_parameter("couleur", couleur())
	var vi: int = garage.choix("vinyle")
	_peinture.set_shader_parameter("vinyle", vi)
	var clair: bool = couleur().get_luminance() > 0.45
	_peinture.set_shader_parameter("vin_col", Color(0.05, 0.05, 0.06) if clair else Color(0.95, 0.95, 0.95))
	_finition()
	_verre.albedo_color = VITRES[garage.choix("vitres")]
	# néons
	_neons(garage.choix("neons"))
	# pièces
	_poser("taxi", garage.choix("taxi"), _faire_taxi)
	_poser("barre_led", garage.choix("barre_led"), _faire_led)
	_poser("prise_air", garage.choix("prise_air"), _faire_prise)
	_poser("bas_caisse", garage.choix("bas_caisse"), _faire_jupes)
	_poser("aileron", garage.choix("aileron"), _faire_aileron)
	_poser("echappement", garage.choix("echappement"), _faire_echappement)
	_poser("pare_buffle", garage.choix("pare_buffle"), _faire_pare_buffle)
	_poser("galerie", garage.choix("galerie"), _faire_galerie)
	_jantes(garage.choix("jantes"))
	var audio = main.get("sound") if main else null
	if audio and "echappement" in audio:
		audio.echappement = garage.choix("echappement") > 0

## Couleur de la carrosserie : choix du garage ; « d'origine » (choix 0) = teinte du modèle (#95), noir pour le pick-up.
func couleur() -> Color:
	var i: int = garage.choix("couleur")
	var m: Dictionary = car.get("_meta")
	if i == 0 and m.get("couleur") is Array:
		return Color(float(m.couleur[0]), float(m.couleur[1]), float(m.couleur[2]))
	return Garage.COULEURS[i]

func _finition() -> void:
	var f: int = garage.choix("finition")
	# [métal, rugosité, vernis, rugosité du vernis, nacre]
	var p: Array = [[0.0, 0.32, 0.8, 0.1, 0.0], [0.35, 0.28, 0.9, 0.06, 1.0], [0.0, 0.62, 0.0, 0.5, 0.0], [1.0, 0.06, 0.3, 0.05, 0.0]][f]
	_peinture.set_shader_parameter("metal", p[0])
	_peinture.set_shader_parameter("rugosite", lerpf(p[1], minf(p[1], 0.08), _mouille))
	_peinture.set_shader_parameter("vernis", p[2])
	_peinture.set_shader_parameter("vernis_rug", lerpf(p[3], 0.02, _mouille))
	_peinture.set_shader_parameter("nacre", p[4])
	if f == 3:   # chromé : la couleur teinte le reflet
		_peinture.set_shader_parameter("couleur", couleur().lerp(Color(0.85, 0.86, 0.88), 0.55))

# ---------------------------------------------------------------- néons
func _neons(i: int) -> void:
	if i == 0:
		if _neon:
			_neon.queue_free(); _neon = null
		if _pieces.has("neons"):
			_pieces.neons.queue_free(); _pieces.erase("neons")
		return
	var col: Color = Garage.NEONS[i]
	if _neon == null:
		_neon = OmniLight3D.new()
		_neon.position = Vector3(0, 0.02, 0)
		_neon.omni_range = 3.4
		_neon.omni_attenuation = 1.2
		_neon.light_energy = 2.2
		_neon.shadow_enabled = false
		car.add_child(_neon)
		_neon_mat = StandardMaterial3D.new()
		_neon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var n := Node3D.new()
		for sx in [-0.86, 0.86]:
			var c := CylinderMesh.new(); c.top_radius = 0.018; c.bottom_radius = 0.018; c.height = 2.3; c.radial_segments = 6
			var mi := MeshInstance3D.new(); mi.mesh = c; mi.material_override = _neon_mat
			mi.rotation.x = PI / 2; mi.position = Vector3(sx, 0.12, -0.1)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			n.add_child(mi)
		n.scale = _echelle()
		car.add_child(n)
		_pieces["neons"] = n
	_neon.light_color = col
	_neon_mat.albedo_color = col.lerp(Color.WHITE, 0.3)

# ---------------------------------------------------------------- pièces
func _poser(r: String, n_choix: int, faire: Callable) -> void:
	# modèle n° n_choix (assets/garage/<rubrique>_<n>.glb, déjà calé dans le repère de la voiture) ou forme simple
	if _pieces.has(r) and int(_pieces[r].get_meta("choix", -1)) != n_choix:
		_pieces[r].queue_free()
		_pieces.erase(r)
	if n_choix > 0 and not _pieces.has(r):
		var n: Node3D
		var f := "res://assets/garage/%s_%d.glb" % [r, n_choix]
		if ResourceLoader.exists(f):
			n = load(f).instantiate()
		else:
			n = faire.call()
		n.set_meta("choix", n_choix)
		n.scale = _echelle()
		for g in n.find_children("*", "GeometryInstance3D", true, false):
			(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		car.add_child(n)
		_pieces[r] = n
	if _pieces.has(r) and r in ["prise_air", "bas_caisse", "aileron"]:
		var col: Color = couleur()
		for mi in _pieces[r].find_children("*", "MeshInstance3D", true, false):
			if mi.has_meta("peinte"):
				(mi.material_override as StandardMaterial3D).albedo_color = col

func _boite(p: Node3D, taille: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new(); b.size = taille
	var mi := MeshInstance3D.new(); mi.mesh = b; mi.material_override = mat
	mi.position = pos; mi.rotation = rot
	p.add_child(mi)
	return mi

func _mat(c: Color, rug := 0.35, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c; m.roughness = rug; m.metallic = metal
	return m

func _peinte(p: Node3D, taille: Vector3, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var m := _mat(couleur(), 0.3)
	m.clearcoat_enabled = true; m.clearcoat = 0.8
	var mi := _boite(p, taille, pos, m, rot)
	mi.set_meta("peinte", true)
	return mi

## Enseigne TAXI sur le toit : caisson jaune, lettres noires sur les deux faces, allumée pendant les courses.
func _faire_taxi() -> Node3D:
	var n := Node3D.new()
	_taxi_mat = _mat(Color(1.0, 0.82, 0.1), 0.3)
	_taxi_mat.emission_enabled = true
	_taxi_mat.emission = Color(1.0, 0.8, 0.2)
	_taxi_mat.emission_energy_multiplier = 0.0
	_boite(n, Vector3(0.66, 0.2, 0.26), Vector3(0, 1.83, -0.3), _taxi_mat)
	_boite(n, Vector3(0.7, 0.03, 0.3), Vector3(0, 1.72, -0.3), _mat(Color(0.05, 0.05, 0.05), 0.6))
	for sz in [1.0, -1.0]:
		var l := Label3D.new()
		l.text = "TAXI"
		l.font_size = 64
		l.pixel_size = 0.0022
		l.modulate = Color(0.05, 0.05, 0.05)
		l.outline_size = 0
		l.alpha_cut = Label3D.ALPHA_CUT_DISCARD
		l.position = Vector3(0, 1.83, -0.3 + sz * 0.132)
		l.rotation.y = 0.0 if sz > 0 else PI
		n.add_child(l)
	return n

## Barre de LED au-dessus du pare-brise, allumée avec les phares.
func _faire_led() -> Node3D:
	var n := Node3D.new()
	_led_mat = _mat(Color(0.9, 0.95, 1.0), 0.1)
	_led_mat.emission_enabled = true
	_led_mat.emission = Color(0.95, 0.97, 1.0)
	_boite(n, Vector3(1.32, 0.09, 0.1), Vector3(0, 1.78, 0.22), _mat(Color(0.03, 0.03, 0.035), 0.5, 0.3))
	for k in 12:
		_boite(n, Vector3(0.07, 0.05, 0.01), Vector3(-0.6 + k * 1.2 / 11.0, 1.78, 0.275), _led_mat)
	for sx in [-0.62, 0.62]:
		_boite(n, Vector3(0.04, 0.1, 0.06), Vector3(sx, 1.72, 0.2), _mat(Color(0.03, 0.03, 0.035), 0.5))
	return n

## Prise d'air posée sur le capot (pente du capot ~17°), ouverture noire à l'avant.
func _faire_prise() -> Node3D:
	var n := Node3D.new()
	var rot := Vector3(deg_to_rad(17.0), 0, 0)
	_peinte(n, Vector3(0.62, 0.1, 0.72), Vector3(0, 1.36, 1.42), rot)
	_boite(n, Vector3(0.5, 0.06, 0.02), Vector3(0, 1.39, 1.79), _mat(Color(0.01, 0.01, 0.01), 0.9), rot)
	return n

## Jupes latérales entre les roues, couleur de la carrosserie.
func _faire_jupes() -> Node3D:
	var n := Node3D.new()
	for sx in [-1.0, 1.0]:
		_peinte(n, Vector3(0.08, 0.17, 2.34), Vector3(sx * 0.98, 0.33, -0.02))
	return n

## Aileron (en attendant le modèle choisi) : plan porteur sur deux montants au bout de la benne.
func _faire_aileron() -> Node3D:
	var n := Node3D.new()
	_peinte(n, Vector3(1.72, 0.035, 0.32), Vector3(0, 1.6, -2.6), Vector3(deg_to_rad(-8.0), 0, 0))
	for sx in [-0.6, 0.6]:
		_boite(n, Vector3(0.05, 0.32, 0.16), Vector3(sx, 1.42, -2.62), _mat(Color(0.03, 0.03, 0.035), 0.5))
	for sx in [-0.87, 0.87]:
		_peinte(n, Vector3(0.02, 0.14, 0.36), Vector3(sx, 1.62, -2.6))
	return n

## Échappement sport (en attendant le modèle choisi) : double sortie chromée sous le pare-chocs arrière.
func _faire_echappement() -> Node3D:
	var n := Node3D.new()
	var chrome := _mat(Color(0.85, 0.85, 0.87), 0.12, 1.0)
	for sx in [-0.62, -0.46, 0.46, 0.62]:
		var c := CylinderMesh.new(); c.top_radius = 0.055; c.bottom_radius = 0.05; c.height = 0.22; c.radial_segments = 12
		var mi := MeshInstance3D.new(); mi.mesh = c; mi.material_override = chrome
		mi.rotation.x = PI / 2; mi.position = Vector3(sx, 0.2, -2.78)
		n.add_child(mi)
		var f := CylinderMesh.new(); f.top_radius = 0.045; f.bottom_radius = 0.045; f.height = 0.01
		var fi := MeshInstance3D.new(); fi.mesh = f; fi.material_override = _mat(Color(0.01, 0.01, 0.01), 0.9)
		fi.rotation.x = PI / 2; fi.position = Vector3(sx, 0.2, -2.895)
		n.add_child(fi)
	return n

## Pare-buffle tubulaire noir devant la calandre (v6.58).
func _faire_pare_buffle() -> Node3D:
	var n := Node3D.new()
	var noir := _mat(Color(0.03, 0.03, 0.035), 0.4, 0.6)
	for sx in [-0.42, 0.42]:
		_boite(n, Vector3(0.07, 0.75, 0.07), Vector3(sx, 0.75, 2.66), noir)
	_boite(n, Vector3(1.0, 0.07, 0.07), Vector3(0, 1.12, 2.68), noir)
	_boite(n, Vector3(1.6, 0.08, 0.08), Vector3(0, 0.55, 2.7), noir)
	for sx in [-0.78, 0.78]:
		_boite(n, Vector3(0.07, 0.3, 0.07), Vector3(sx, 0.62, 2.62), noir, Vector3(0, 0, sx * 0.4))
	return n

## Galerie de toit : cadre et barreaux en aluminium noir sur le pavillon (v6.58).
func _faire_galerie() -> Node3D:
	var n := Node3D.new()
	var noir := _mat(Color(0.05, 0.05, 0.055), 0.45, 0.5)
	for sx in [-0.66, 0.66]:
		_boite(n, Vector3(0.05, 0.05, 1.45), Vector3(sx, 1.8, -0.15), noir)
		for sz in [-0.8, 0.5]:
			_boite(n, Vector3(0.05, 0.1, 0.05), Vector3(sx, 1.76, sz), noir)
	for k in 5:
		_boite(n, Vector3(1.32, 0.035, 0.04), Vector3(0, 1.82, -0.8 + k * 0.32), noir)
	return n

## Jantes : modèle de roue remplacé (assets/garage/jantes_<n>.glb : roue complète, axe x, diamètre 1 m).
func _jantes(n_choix: int) -> void:
	var f := "res://assets/garage/jantes_%d.glb" % n_choix
	var dispo := n_choix > 0 and ResourceLoader.exists(f)
	for i in car.wheels.size():
		var w: VehicleWheel3D = car.wheels[i]
		var orig: Node3D = _roues_origine[i]
		var neuve := w.get_node_or_null("Jantes")
		if neuve and int(neuve.get_meta("choix", -1)) != n_choix:
			w.remove_child(neuve)
			neuve.queue_free()
			neuve = null
		# tout ce qui n'est pas la nouvelle roue est caché (#54 : le pneu d'origine restait autour de la jante)
		for c in w.get_children():
			if c is Node3D and c.name != "Jantes":
				(c as Node3D).visible = not dispo
		if dispo and neuve == null:
			neuve = load(f).instantiate()
			neuve.name = "Jantes"
			neuve.set_meta("choix", n_choix)
			# le pneu à crampons fait partie de la caisse du Raptor : la nouvelle roue se loge dedans (#54)
			neuve.scale = Vector3.ONE * 2.0 * (w.wheel_radius - 0.045) * DANS_LE_PNEU
			# face extérieure de la jante vers l'extérieur ; la n° 3 est livrée retournée (étrier côté face)
			neuve.rotation.y = (0.0 if i % 2 == 0 else PI) + (PI if n_choix in JANTES_RETOURNEES else 0.0)
			w.add_child(neuve)
