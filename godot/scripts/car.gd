## Renault Espace IV : physique de véhicule à roues sur rayons, boîte automatique, direction adaptée à la vitesse.
## Sans friction : marche arrière en restant sur le frein à l'arrêt, remise sur la route automatique (sortie de zone,
## chute, retournement, blocage), aides à la stabilité.
extends VehicleBody3D

const MAX_KMH := 175.0
const ENGINE := 4200.0          # force max (N) à bas régime
const BRAKE := 60.0
const STEER_LOW := 0.55         # braquage max à l'arrêt (rad)
const STEER_HIGH := 0.08        # à 130 km/h

var touch_throttle := 0.0
var touch_brake := 0.0
var touch_steer := 0.0
var steer_value := 0.0
var reversing := false
var safe := []                  # positions sûres récentes : [Transform3D]
var _safe_t := 0.0
var _stuck_t := 0.0
var _flip_t := 0.0
var wheels := []

func _ready() -> void:
	mass = 1650.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.45, 0)
	linear_damp = 0.02
	angular_damp = 0.6
	continuous_cd = true
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/car/meta.json"))
	var body: Node3D = load("res://assets/car/body.glb").instantiate()
	body.rotation.y = PI          # modèle : avant vers -Z ; véhicule Godot : avant vers +Z
	add_child(body)
	_materials(body)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.84, 1.05, 4.62)
	cs.shape = box
	cs.position = Vector3(0, 0.95, 0)
	add_child(cs)
	var wb: float = meta.wheelbase; var tr: float = meta.track; var r: float = meta.radius
	var wheel_scene: PackedScene = load("res://assets/car/wheel.glb")
	for i in 4:
		var front := i < 2
		var right := i % 2 == 0
		var w := VehicleWheel3D.new()
		w.position = Vector3((-1.0 if right else 1.0) * tr / 2, r + 0.12, (1.0 if front else -1.0) * wb / 2)
		w.wheel_radius = r
		w.suspension_travel = 0.18
		w.suspension_stiffness = 42.0
		w.suspension_max_force = 12000.0
		w.damping_compression = 0.9
		w.damping_relaxation = 1.4
		w.wheel_friction_slip = 2.6
		w.wheel_roll_influence = 0.12
		w.use_as_steering = front
		w.use_as_traction = front
		var v: Node3D = wheel_scene.instantiate()
		v.rotation.y = 0.0 if right else PI
		w.add_child(v)
		add_child(w)
		wheels.append(w)
	for n in body.find_children("*", "MeshInstance3D", true, false):
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

func _materials(root: Node) -> void:
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.55, 0.03, 0.04)
	paint.metallic = 0.6; paint.roughness = 0.28
	paint.clearcoat_enabled = true; paint.clearcoat = 0.8; paint.clearcoat_roughness = 0.1
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.04, 0.05, 0.06, 0.55)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.metallic = 0.2; glass.roughness = 0.03
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
	var by_name := {"paint": paint, "glass": glass, "chrome": chrome, "rubber": rubber, "plastic": plastic,
		"lamp": lamp, "tail": tail, "interior": vcol, "plate_front": vcol, "plate_rear": vcol}
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var m: Material = mi.mesh.surface_get_material(s)
			var nm := m.resource_name if m else ""
			if by_name.has(nm):
				mi.set_surface_override_material(s, by_name[nm])

func place(p: Vector3, heading_deg: float) -> void:
	# cap : 0 = Nord (-Z), sens horaire ; l'avant du véhicule est +Z
	var b := Basis(Vector3.UP, PI - deg_to_rad(heading_deg))
	global_transform = Transform3D(b, p)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	safe = [global_transform]

func kmh() -> float:
	return linear_velocity.length() * 3.6

func forward_speed() -> float:
	return linear_velocity.dot(global_transform.basis.z)

func _physics_process(dt: float) -> void:
	var thr := clampf(Input.get_action_strength("accelerer") + touch_throttle, 0.0, 1.0)
	var brk := clampf(Input.get_action_strength("freiner") + touch_brake, 0.0, 1.0)
	var st := clampf(Input.get_action_strength("gauche") - Input.get_action_strength("droite") + touch_steer, -1.0, 1.0)
	var v := forward_speed()
	# marche arrière : frein maintenu à l'arrêt
	if brk > 0.2 and v < 0.6 and thr < 0.1:
		reversing = true
	elif thr > 0.1 and v > -0.6:
		reversing = false
	var k := clampf(absf(v) * 3.6 / 130.0, 0.0, 1.0)
	var max_steer := lerpf(STEER_LOW, STEER_HIGH, sqrt(k))
	# direction progressive, retour au centre plus rapide
	var target := st * max_steer
	var rate := 2.2 if absf(target) > absf(steer_value) else 3.5
	steer_value = move_toward(steer_value, target, rate * dt)
	steering = steer_value
	var spd := absf(v) * 3.6
	if reversing:
		engine_force = -ENGINE * 0.5 * brk if spd < 25.0 else 0.0
		brake = 0.0
	else:
		# boîte auto : force décroissante avec la vitesse, coupée à la vitesse max
		var f := ENGINE * thr * clampf(1.15 - spd / 210.0, 0.25, 1.0)
		if spd > MAX_KMH:
			f = 0.0
		engine_force = f
		brake = BRAKE * brk + (2.0 if thr < 0.05 and spd < 3.0 and brk < 0.1 else 0.0)
	# frein moteur léger et aide à la stabilité en virage (anti-dérive latérale)
	if thr < 0.05 and not reversing:
		apply_central_force(-linear_velocity * 25.0)
	# traînée aérodynamique (SCx Espace IV ≈ 0,9 m²)
	apply_central_force(-linear_velocity * linear_velocity.length() * 0.55)
	var side := global_transform.basis.x
	var lat := linear_velocity.dot(side)
	apply_central_force(-side * lat * mass * 0.6 * dt * 60.0 * 0.05)
	_recovery(dt)

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
	# retourné ou sur le flanc plus de 2 s
	_flip_t = _flip_t + dt if up < 0.4 else 0.0
	# bloqué (accélère sans avancer) plus de 4 s
	var thr := Input.get_action_strength("accelerer") + touch_throttle
	_stuck_t = _stuck_t + dt if (thr > 0.3 and kmh() < 1.5) else 0.0
	if p.y < -50.0 or _flip_t > 2.0 or _stuck_t > 4.0 or Input.is_action_just_pressed("replacer"):
		reset_to_road()

func reset_to_road() -> void:
	var t: Transform3D = safe[max(0, safe.size() - 3)] if safe.size() > 0 else global_transform
	global_transform = Transform3D(Basis(Vector3.UP, t.basis.get_euler().y), t.origin + Vector3(0, 0.8, 0))
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_flip_t = 0.0; _stuck_t = 0.0
