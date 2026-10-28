## Pluie : traits de pluie autour de la caméra (inclinés par le vent et par la vitesse de la voiture) et bruit de
## pluie en boucle ; s'arrête et repart en fondu.
extends Node3D
const PerfMon := preload("res://scripts/perf_monitor.gd")

var cam_rig: Node3D
var car: VehicleBody3D
var on := false
var amount := 0.0
var main: Node
var drops: CPUParticles3D
var mat: StandardMaterial3D
var sound: AudioStreamPlayer

func _ready() -> void:
	mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR   # v6.19 : sans mélange (gouttes pleines, plus claires)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.albedo_color = Color(0.72, 0.76, 0.82, 1.0)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var q := QuadMesh.new()
	q.size = Vector2(0.012, 0.55)
	q.material = mat
	drops = CPUParticles3D.new()
	drops.mesh = q
	drops.amount = 1400
	drops.lifetime = 1.1
	drops.preprocess = 1.1
	drops.local_coords = false
	drops.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	drops.emission_box_extents = Vector3(16, 1, 16)
	drops.direction = Vector3(0, -1, 0)
	drops.spread = 3.0
	drops.initial_velocity_min = 9.0
	drops.initial_velocity_max = 11.0
	drops.gravity = Vector3(0, -6, 0)
	drops.emitting = false
	drops.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	drops.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))
	add_child(drops)
	if ResourceLoader.exists("res://assets/sfx/pluie.ogg"):
		# pluie et orage enregistrés (« Rain and thunder », Premankur Adhikary, Pixabay), 90 s bouclables
		sound = AudioStreamPlayer.new()
		var og: AudioStreamOggVorbis = load("res://assets/sfx/pluie.ogg")
		og.loop = true
		sound.stream = og
		sound.volume_db = -60.0
		sound.bus = "Monde"
		add_child(sound)
	elif ResourceLoader.exists("res://assets/sfx/pluie.wav"):
		sound = AudioStreamPlayer.new()
		var st: AudioStreamWAV = load("res://assets/sfx/pluie.wav")
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		st.loop_end = st.data.size() / 2
		sound.stream = st
		sound.volume_db = -60.0
		add_child(sound)

## Éclairs (v6.94) : la boucle de pluie contient des coups de tonnerre (début du grondement relevé par analyse de
## pluie.ogg : énergie sous 200 Hz, et sa force de 0 à 1) ; un éclair part un peu avant chacun, d'autant plus tôt que le
## tonnerre est faible (lointain : le son voyage moins vite que la lumière).
const TONNERRES := [[15.3, 0.25], [19.8, 1.0], [22.35, 0.45], [26.1, 0.8], [30.85, 0.65], [68.45, 0.5]]
var _pos_prec := -1.0

func _eclairs() -> void:
	if sound == null or not sound.playing or main == null or amount < 0.5:
		_pos_prec = -1.0
		return
	var pos := sound.get_playback_position()
	if _pos_prec >= 0.0:
		for f in eclairs_entre(_pos_prec, pos):
			main.eclair(float(f) * amount)
	_pos_prec = pos

## Éclairs à lancer quand le son passe de la position p0 à p1 (s ; la boucle peut être repartie au début) : leur force.
func eclairs_entre(p0: float, p1: float) -> Array:
	var l := []
	for t in TONNERRES:
		var at: float = float(t[0]) - lerpf(2.6, 1.0, float(t[1]))
		if ((p0 < at and p1 >= at) if p1 >= p0 else (at > p0 or at <= p1)):
			l.append(float(t[1]))
	return l

## Gouttes moins visibles la nuit (seulement dans la lumière des phares et des lampadaires).
func set_night(n: float) -> void:
	mat.albedo_color = Color(0.72, 0.76, 0.82, 1.0).lerp(Color(0.5, 0.55, 0.62, 0.16), n)

func _process(dt: float) -> void:
	var t0_perf := Time.get_ticks_usec()
	_process_corps(dt)
	PerfMon.note("rain", Time.get_ticks_usec() - t0_perf)

func _process_corps(dt: float) -> void:
	amount = move_toward(amount, 1.0 if on else 0.0, dt * 0.25)      # premières gouttes en 4 s
	drops.emitting = amount > 0.05
	if sound:
		if amount > 0.01 and not sound.playing:
			sound.play()
		elif amount <= 0.01 and sound.playing:
			sound.stop()
		sound.volume_db = linear_to_db(maxf(amount, 0.001)) - 9.0
		_eclairs()
	if not drops.emitting or cam_rig == null:
		return
	var cam: Camera3D = cam_rig.cam
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	# la pluie tombe autour et devant la caméra ; la voiture « avance dans les gouttes »
	var v := car.linear_velocity if car else Vector3.ZERO
	drops.global_position = cam.global_position + fwd.normalized() * 9.0 + Vector3(0, 7.0, 0) + v * 0.5
	var w := Vector3(0.8, 0, 0.6) * 2.5 - v * 0.35
	drops.direction = (Vector3(0, -10, 0) + w).normalized()
