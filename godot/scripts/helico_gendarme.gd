## Hélicoptère de la Gendarmerette (v7.12, #150) : à 3 étoiles, l'hélicoptère du ciel (assets/aeronefs/helico.glb,
## comme ciel.gd : rotors qui tournent) arrive de loin, puis tourne au-dessus du joueur (rayon RAYON m, ALT m au-dessus
## du sol, VMAX m/s au plus : un joueur plus rapide le distance) ; il le voit à moins de VUE m (gendarmes.gd : vu) ;
## projecteur la nuit ; repart faire le plein au bout de DUREE s (ou quand la poursuite finit) et s'éloigne en montant.
extends Node3D

const Relief := preload("res://scripts/relief.gd")
const ALT := 75.0
const RAYON := 45.0
const VMAX := 40.0                  # m/s (144 km/h)
const VUE := 350.0
const DUREE := 75.0

var main: Node
var depart := false                 # repart (plein, fin de la poursuite)
var age := 0.0
var _v := Vector3.ZERO
var _ang := 0.0
var _modele: Node3D
var _tournants := []
var _phare: SpotLight3D
var _son: AudioStreamPlayer3D

func _ready() -> void:
	var sc: PackedScene = load("res://assets/aeronefs/helico.glb")
	_modele = sc.instantiate()
	add_child(_modele)
	for n in _modele.find_children("*", "Node3D", true, false):
		if n.name.begins_with("rotor"):
			_tournants.append([n, Vector3.UP, 38.0])
		elif n.name.begins_with("helice_q"):
			_tournants.append([n, Vector3.RIGHT, 70.0])
	for n in _modele.find_children("*", "GeometryInstance3D", true, false):
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# livrée bleue de la gendarmerie (même teinte que les voitures, gendarme.gd)
	var sh := Shader.new()
	sh.code = preload("res://scripts/gendarme.gd").TEINTE
	for n in _modele.find_children("*", "MeshInstance3D", true, false):
		var m3 := n as MeshInstance3D
		for k in m3.mesh.get_surface_count():
			var m := m3.get_active_material(k) as BaseMaterial3D
			if m and m.albedo_texture:
				var t := ShaderMaterial.new()
				t.shader = sh
				t.set_shader_parameter("tex", m.albedo_texture)
				t.set_shader_parameter("teinte", Color(0.12, 0.2, 0.5))
				m3.set_surface_override_material(k, t)
	_phare = SpotLight3D.new()
	_phare.light_color = Color(1.0, 0.97, 0.9)
	_phare.spot_range = 160.0
	_phare.spot_angle = 9.0
	_phare.light_energy = 0.0
	_phare.shadow_enabled = false
	add_child(_phare)
	_son = AudioStreamPlayer3D.new()
	if ResourceLoader.exists("res://assets/sfx/helico_passage.ogg"):
		var st: AudioStream = (load("res://assets/sfx/helico_passage.ogg") as AudioStream).duplicate()
		if st is AudioStreamOggVorbis:
			(st as AudioStreamOggVorbis).loop = true
		_son.stream = st
	_son.bus = "Monde"
	_son.unit_size = 40.0
	_son.max_distance = 900.0
	_son.volume_db = -4.0
	add_child(_son)
	_son.play(4.0)

## Arrivée à `d` m du joueur, du côté opposé à sa direction (il arrive derrière lui).
func poser(p: Vector3, dir: Vector3, d := 600.0) -> void:
	var a := -Vector2(dir.x, dir.z).normalized()
	if a.length() < 0.5:
		a = Vector2(1, 0)
	var q := p + Vector3(a.x, 0.0, a.y) * d
	var h := Relief.hauteur(q)
	global_position = Vector3(q.x, (h if is_finite(h) else p.y) + ALT + 40.0, q.z)

func voit(p: Vector3) -> bool:
	return not depart and Vector2(p.x - global_position.x, p.z - global_position.z).length() < VUE

func _physics_process(dt: float) -> void:
	var c = main.gendarmes.cible() if main and main.get("gendarmes") else null
	if c == null:
		return
	age += dt
	var p: Vector3 = c.global_position
	var but: Vector3
	if depart:
		but = global_position + (global_position - p).normalized() * 500.0 + Vector3.UP * 200.0
	else:
		_ang += dt * 0.45
		var jv: Vector3 = (c as RigidBody3D).linear_velocity if c is RigidBody3D else Vector3.ZERO
		but = p + jv * 2.0 + Vector3(cos(_ang), 0.0, sin(_ang)) * RAYON
		var h := Relief.hauteur(but)
		but.y = (h if is_finite(h) else p.y) + ALT
	var e := but - global_position
	var vv := e.normalized() * minf(VMAX, e.length() * 0.6)
	_v = _v.lerp(vv, clampf(dt * 1.2, 0.0, 1.0))
	global_position += _v * dt
	# nez dans le sens de la marche, penché en avant selon la vitesse
	var hz := Vector3(_v.x, 0.0, _v.z)
	if hz.length() > 1.0:
		var b := Basis.looking_at(-hz.normalized(), Vector3.UP)
		_modele.global_transform = Transform3D(b * Basis(Vector3.RIGHT, deg_to_rad(clampf(hz.length() * 0.4, 0.0, 14.0))), global_position)
	for r in _tournants:
		(r[0] as Node3D).rotate_object_local(r[1], r[2] * dt)
	# projecteur la nuit, braqué sur le joueur
	var nuit: bool = main.get("car") != null and main.car.lights_on
	_phare.light_energy = 6.0 if nuit and not depart else 0.0
	if nuit and not depart and p.distance_to(global_position) > 1.0:
		_phare.global_transform = Transform3D(Basis.looking_at(p - global_position, Vector3.UP), global_position - Vector3.UP * 1.5)
