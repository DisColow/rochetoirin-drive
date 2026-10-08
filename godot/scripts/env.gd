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
	return m

static func set_value(k: String, v) -> void:
	vals[k] = v
	for m in mats:
		m.set_shader_parameter(k, v)
	if terrain_mat:
		terrain_mat.set_shader_param(k, v)

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
