## Pluie : traits de pluie autour de la caméra (inclinés par le vent et par la vitesse de la voiture) et bruit de
## pluie en boucle ; s'arrête et repart en fondu.
extends Node3D

var cam_rig: Node3D
var car: VehicleBody3D
var on := false
var amount := 0.0
var drops: CPUParticles3D
var mat: StandardMaterial3D
var sound: AudioStreamPlayer

func _ready() -> void:
	mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.albedo_color = Color(0.78, 0.82, 0.88, 0.32)
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
	if ResourceLoader.exists("res://assets/sfx/pluie.wav"):
		sound = AudioStreamPlayer.new()
		var st: AudioStreamWAV = load("res://assets/sfx/pluie.wav")
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		st.loop_end = st.data.size() / 2
		sound.stream = st
		sound.volume_db = -60.0
		add_child(sound)

## Gouttes moins visibles la nuit (seulement dans la lumière des phares et des lampadaires).
func set_night(n: float) -> void:
	mat.albedo_color = Color(0.78, 0.82, 0.88, 0.32).lerp(Color(0.5, 0.55, 0.62, 0.16), n)

func _process(dt: float) -> void:
	amount = move_toward(amount, 1.0 if on else 0.0, dt * 0.5)
	drops.emitting = amount > 0.05
	if sound:
		if amount > 0.01 and not sound.playing:
			sound.play()
		elif amount <= 0.01 and sound.playing:
			sound.stop()
		sound.volume_db = linear_to_db(maxf(amount, 0.001)) - 9.0
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
