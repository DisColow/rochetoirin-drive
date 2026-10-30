## Ambiance commune des matériaux du monde (vent, ombres des nuages, sol mouillé) : paramètres ordinaires de chaque
## matériau, tenus à jour ici. (Les paramètres globaux de shader de la v3.1 faisaient planter certains téléphones
## au démarrage.)
extends RefCounted

static var mats: Array = []
static var vals := {"wind": Vector4(0.8, 0.6, 0.55, 0.0), "clouds": Vector4.ZERO, "wet": 0.0}
static var terrain_mat: Object = null

static func add(m: ShaderMaterial) -> ShaderMaterial:
	mats.append(m)
	for k in vals:
		m.set_shader_parameter(k, vals[k])
	if bout_monde:
		_basculer(m, true)
	return m

## Bord « cascade » (#157) : les matériaux opaques sans discard (relief, routes, bâtiments, lointain) passent à leur
## variante « #define BOUT_MONDE » (le monde s'efface au-delà de la limite) ; en mode Collines, shaders d'origine.
const VARIANTES := ["res://scripts/terrain.gdshader", "res://scripts/asphalt.gdshader",
	"res://scripts/building.gdshader", "res://scripts/far.gdshader"]
static var bout_monde := false
static var _variantes := {}             # chemin du shader d'origine -> variante
static var _origines := {}              # variante -> shader d'origine

static func set_bout_monde(on: bool) -> void:
	bout_monde = on
	set_value("env_bout_monde", 1.0 if on else 0.0)
	for m in mats:
		_basculer(m, on)
	if terrain_mat:
		var sh = terrain_mat.get("shader_override")
		var neuf: Shader = _choisir(sh, on) if sh is Shader else null
		if neuf and neuf != sh:
			terrain_mat.set("shader_override", neuf)

static func _basculer(m: ShaderMaterial, on: bool) -> void:
	if m.shader:
		var neuf := _choisir(m.shader, on)
		if neuf != m.shader:
			m.shader = neuf

static func _choisir(sh: Shader, on: bool) -> Shader:
	if _origines.has(sh):
		return sh if on else _origines[sh]
	if not on or not sh.resource_path in VARIANTES:
		return sh
	if not _variantes.has(sh.resource_path):
		var v := Shader.new()
		var i := sh.code.find("\n", sh.code.find("shader_type"))
		v.code = sh.code.substr(0, i + 1) + "#define BOUT_MONDE\n" + sh.code.substr(i + 1)
		_variantes[sh.resource_path] = v
		_origines[v] = sh
	return _variantes[sh.resource_path]

## Matériau libéré (objet déchargé) : on l'oublie, sinon il garderait ses textures en mémoire (sur_mesure.gd).
static func remove(m: ShaderMaterial) -> void:
	mats.erase(m)

static func set_value(k: String, v) -> void:
	# valeur simple inchangée : rien à refaire (v6.97 : la lumière du cycle et de la météo est remise à jour chaque
	# seconde ; un matériau ajouté plus tard reçoit les valeurs par add()). Les tableaux, modifiés sur place, repartent.
	if (v is float or v is int or v is Vector4 or v is Color) and vals.has(k) and vals[k] == v:
		return
	vals[k] = v
	for m in mats:
		m.set_shader_parameter(k, v)
	if terrain_mat:
		terrain_mat.set_shader_param(k, v)

## Phares factices (réglage Économie, #124) : seuls le sol, les routes, les marquages et les bâtiments les reçoivent.
static var phare_mats: Array = []
static var phares := [Vector4.ZERO, Vector4(0, 0, 1, 45), Vector3(1.0, 0.93, 0.8)]

static func phares_sur(m: ShaderMaterial) -> ShaderMaterial:
	phare_mats.append(m)
	m.set_shader_parameter("env_phares", phares[0])
	m.set_shader_parameter("env_phares_dir", phares[1])
	m.set_shader_parameter("env_phares_coul", phares[2])
	return m

## Phares : p.xyz = milieu des phares, p.w = intensité (0 : éteints) ; d.xyz = axe, d.w = portée ; c = couleur.
static func set_phares(p: Vector4, d: Vector4, c: Vector3) -> void:
	if p.w <= 0.0 and phares[0].w <= 0.0:
		return
	phares = [p, d, c]
	for m in phare_mats:
		m.set_shader_parameter("env_phares", p)
		m.set_shader_parameter("env_phares_dir", d)
		m.set_shader_parameter("env_phares_coul", c)
	if terrain_mat:
		terrain_mat.set_shader_param("env_phares", p)
		terrain_mat.set_shader_param("env_phares_dir", d)
		terrain_mat.set_shader_param("env_phares_coul", c)

## Matériaux qui s'effacent au loin (fade_far) ou relaient d'autres modèles selon la distance : position de la caméra.
static var cam_mats: Array = []
static var cam := Vector3(1e6, 0.0, 1e6)

static func fade(m: ShaderMaterial, far: float) -> ShaderMaterial:
	m.set_shader_parameter("fade_far", far)
	m.set_shader_parameter("env_cam", cam)
	cam_mats.append(m)
	return m

static func set_cam(p: Vector3) -> void:
	if p.distance_squared_to(cam) < 0.04:
		return
	cam = p
	for m in cam_mats:
		m.set_shader_parameter("env_cam", p)

## Horloge des feux tricolores (s) : signal_light.gdshader (paramètre t_feux, roads.gd) et circulation.gd (#134).
## Temps de jeu (avancé par roads.gd à chaque image), pas l'heure réelle : les essais à --fixed-fps font tourner le jeu
## bien plus lentement que la montre, et les feux doivent suivre les voitures.
static var _t_feux := 0.0

static func avancer_feux(dt: float) -> void:
	_t_feux = fmod(_t_feux + dt, 600.0)

static func temps_feux() -> float:
	return _t_feux
