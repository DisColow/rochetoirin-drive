## Aéronefs du ciel (issue #46), le jour seulement, un à la fois, de temps en temps :
##   - avion de tourisme et hélicoptère à basse altitude, avec le son de leur passage (enregistrement entier, lancé pour
##     que son maximum tombe au moment où l'appareil est au plus près : PIC) ;
##   - avion de ligne à 9-11 km d'altitude, à sa vraie taille, avec sa traînée de condensation (ruban tramé) ;
##   - planeur qui spirale dans une ascendance au-dessus du relief, puis repart en ligne droite (silencieux).
## Modèles : assets/aeronefs/*.glb (pipeline/fetch_aeronefs.py + blender_aeronefs.py), nez vers +Z ; pièces tournantes
## « rotor » (axe Y), « helice » (axe Z), « helice_q » (rotor de queue, axe X).
extends Node3D
const Relief := preload("res://scripts/relief.gd")
const PerfMon := preload("res://scripts/perf_monitor.gd")

# type : [modèle, vitesse m/s, altitude au-dessus du sol (min, max), son, instant du maximum dans le son (s), poids]
const TYPES := {
	"tourisme": ["res://assets/aeronefs/tourisme.glb", 55.0, Vector2(220, 420), "res://assets/sfx/avion_passage.ogg", 6.1, 4],
	"helico": ["res://assets/aeronefs/helico.glb", 48.0, Vector2(110, 220), "res://assets/sfx/helico_passage.ogg", 9.3, 3],
	"ligne": ["res://assets/aeronefs/ligne.glb", 230.0, Vector2(9000, 11000), "res://assets/sfx/ligne_passage.ogg", 7.5, 3],
	"planeur": ["res://assets/aeronefs/planeur.glb", 24.0, Vector2(300, 520), "", 0.0, 2],
}
const TRAINEE := 7000.0          # longueur de la traînée de l'avion de ligne (m)

var target: Node3D               # la voiture
var day := true
var force := ""                  # essai : type imposé (--ciel-test=<type>)

var _rng := RandomNumberGenerator.new()
var _t := 40.0                   # attente avant le prochain passage
var _type := ""
var _avion: Node3D
var _tournants := []             # [nœud, axe, vitesse rad/s]
var _son: AudioStreamPlayer3D
var _son_lance := false
var _p := Vector3.ZERO           # position et vitesse de l'appareil
var _v := Vector3.ZERO
var _vie := 0.0
var _proche := Vector3.ZERO      # point de passage au plus près (lignes droites)
var _vol_db := 0.0
# planeur : centre de l'ascendance, rayon, angle, temps de spirale restant
var _centre := Vector3.ZERO
var _rayon := 120.0
var _ang := 0.0
var _spirale := 0.0
var _trainee: MeshInstance3D
var _modeles := {}

func _ready() -> void:
	_rng.randomize()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ciel-test="):
			force = a.trim_prefix("--ciel-test=")
			_t = 2.0
	_son = AudioStreamPlayer3D.new()
	_son.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED   # l'enregistrement porte déjà son enveloppe
	_son.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	_son.bus = "Monde"
	add_child(_son)

func _process(dt: float) -> void:
	var t0_perf := Time.get_ticks_usec()
	_process_corps(dt)
	PerfMon.note("ciel", Time.get_ticks_usec() - t0_perf)

func _sol(p: Vector3) -> float:
	var h: float = Relief.hauteur(p)
	return h if is_finite(h) else target.global_position.y

func _process_corps(dt: float) -> void:
	if target == null:
		return
	if _avion == null:
		if not day and force == "":
			return
		_t -= dt
		if _t <= 0.0:
			_t = _rng.randf_range(70.0, 160.0)
			_lancer(force if force != "" else _tirer())
		return
	_vie -= dt
	if _type == "planeur" and _spirale > 0.0:
		_spirale -= dt
		_ang += TYPES.planeur[1] / _rayon * dt
		_centre.y += 1.2 * dt                                  # l'ascendance le fait monter
		var q: Vector3 = _centre + Vector3(cos(_ang), 0, sin(_ang)) * _rayon
		_v = (q - _p) / max(dt, 0.001)
		_p = q
		if _spirale <= 0.0:                                    # sortie de spirale : ligne droite
			_v = Vector3(-sin(_ang), 0, cos(_ang)) * TYPES.planeur[1]
	else:
		_p += _v * dt
	_poser()
	for r in _tournants:
		(r[0] as Node3D).rotate_object_local(r[1], r[2] * dt)
	# son : lancé quand le plus près arrive dans PIC secondes
	var info: Array = TYPES[_type]
	if not _son_lance and info[3] != "":
		var rel := _proche - _p
		var restant: float = rel.dot(_v.normalized()) / max(_v.length(), 1.0)
		if restant <= info[4]:
			_son_lance = true
			_son.stream = load(info[3])
			_son.volume_db = _vol_db
			_son.play(clamp(info[4] - restant, 0.0, 5.0))
	_son.global_position = _p
	if _trainee:
		_orienter_trainee()
	if _vie <= 0.0:
		_fin()

func _tirer() -> String:
	var tot := 0
	for k in TYPES:
		tot += TYPES[k][5]
	var r := _rng.randi_range(1, tot)
	for k in TYPES:
		r -= TYPES[k][5]
		if r <= 0:
			return k
	return "tourisme"

func _lancer(type: String) -> void:
	if not TYPES.has(type):
		return
	_type = type
	var info: Array = TYPES[type]
	if not _modeles.has(type):
		_modeles[type] = load(info[0])
	_avion = (_modeles[type] as PackedScene).instantiate()
	add_child(_avion)
	_tournants.clear()
	for n in _avion.find_children("*", "Node3D", true, false):
		if n.name.begins_with("rotor"):
			_tournants.append([n, Vector3.UP, 38.0])
		elif n.name.begins_with("helice_q"):
			_tournants.append([n, Vector3.RIGHT, 70.0])
		elif n.name.begins_with("helice"):
			_tournants.append([n, Vector3.BACK, 60.0])
	for n in _avion.find_children("*", "GeometryInstance3D", true, false):
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(n as GeometryInstance3D).extra_cull_margin = 50.0
	var car := target.global_position
	var fwd := target.global_transform.basis.z                 # la voiture regarde vers +Z (comme les modèles)
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var cote := fwd.cross(Vector3.UP)
	var sg := 1.0 if _rng.randf() < 0.5 else -1.0
	var vit: float = info[1]
	var alt: float = _rng.randf_range(info[2].x, info[2].y)
	if type == "planeur":
		_centre = car + fwd * _rng.randf_range(350, 700) + cote * sg * _rng.randf_range(0, 300)
		_centre.y = _sol(_centre) + alt
		_rayon = _rng.randf_range(90, 150)
		_ang = _rng.randf() * TAU
		_spirale = _rng.randf_range(70.0, 110.0)
		_p = _centre + Vector3(cos(_ang), 0, sin(_ang)) * _rayon
		_vie = _spirale + 60.0
		_proche = _p
	else:
		# ligne droite qui passe devant la voiture, d'un côté à l'autre, plus ou moins en biais
		var dirv := (cote * -sg + fwd * _rng.randf_range(-0.6, 0.6)).normalized()
		var ecart := _rng.randf_range(60, 400) if type != "ligne" else _rng.randf_range(0, 6000)
		_proche = car + fwd * _rng.randf_range(80, 500) + dirv.cross(Vector3.UP) * ecart * sg
		_proche.y = _sol(_proche) + alt
		var demi := 1600.0 if type != "ligne" else 30000.0
		_p = _proche - dirv * demi
		_v = dirv * vit
		_vie = 2.0 * demi / vit
		var d := (_proche - car).length()
		_vol_db = clamp(-20.0 * log(d / 180.0) / log(10.0), -26.0, 3.0) if type != "ligne" else -4.0
	_son_lance = false
	if type == "ligne":
		_trainee = _faire_trainee()
		add_child(_trainee)
	_poser()
	print("  [ciel] %s à %.0f m d'altitude, au plus près %.0f m" % [type, alt, (_proche - car).length()])

func _poser() -> void:
	var dir := _v.normalized() if _v.length() > 0.1 else Vector3.FORWARD
	var b := Basis.looking_at(-dir, Vector3.UP)                # nez des modèles vers +Z
	if _type == "planeur" and _spirale > 0.0:
		b = b * Basis(Vector3.BACK, deg_to_rad(-25.0))         # inclinaison vers le centre du virage
	elif _type == "helico":
		b = b * Basis(Vector3.RIGHT, deg_to_rad(8.0))          # nez baissé en vol d'avancement
	_avion.global_transform = Transform3D(b, _p)

func _faire_trainee() -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var m := ShaderMaterial.new()
	m.shader = preload("res://scripts/trainee.gdshader")
	q.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = TRAINEE
	return mi

## Ruban de la traînée : de l'arrière de l'avion vers l'arrière, tourné vers la caméra autour de son axe.
func _orienter_trainee() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var axe := -_v.normalized()
	var debut := _p + axe * 40.0
	var centre := debut + axe * TRAINEE * 0.5
	var vers := (cam.global_position - centre).normalized()
	var large := axe.cross(vers).normalized()
	var face := large.cross(axe).normalized()
	# quad : x = axe (longueur), y = largeur
	_trainee.global_transform = Transform3D(Basis(axe * TRAINEE, large * 60.0, face), centre)

func _fin() -> void:
	_avion.queue_free()
	_avion = null
	if _trainee:
		_trainee.queue_free()
		_trainee = null
	_son.stop()
	if force != "":
		_t = 3.0
