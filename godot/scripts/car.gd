## Renault Espace I (1984-1988, rouge foncé et bas beige doré, la voiture du père de l'utilisateur) : physique de véhicule à roues sur rayons, boîte automatique, direction adaptée à la vitesse.
## Sans friction : marche arrière comme dans les jeux (FREIN freine puis recule, GAZ en reculant freine puis avance), remise sur la route automatique (sortie de zone,
## chute, retournement, blocage), aides à la stabilité.
extends VehicleBody3D

const MAX_KMH := 185.0
const POWER := 72000.0         # puissance aux roues (W) : 130 km/h atteints franchement, pointe vers 185
const ENGINE := 4800.0          # force max (N) au démarrage (limitée par l'adhérence)
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
var road_pts := PackedFloat32Array()
var _hold_t := 0.0
var _hold_xf := Transform3D()   # points de route (x, z, y, cap) pour la remise sur la route

func _ready() -> void:
	mass = 1650.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.22, 0)        # bas (moteur, plancher) : pas de basculement en virage
	# pas d'amortissement générique (0,1 par défaut dans le projet = 7 kN à 130 km/h) : traînée aérodynamique réelle
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp = 0.6
	continuous_cd = true
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/car/meta.json"))
	var body: Node3D = load("res://assets/car/body.glb").instantiate()
	_body = body
	body.rotation.y = PI          # modèle : avant vers -Z ; véhicule Godot : avant vers +Z
	add_child(body)
	_materials(body)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.76, 1.15, 4.24)
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
		w.wheel_roll_influence = 0.03
		w.use_as_steering = front
		w.use_as_traction = front
		var v: Node3D = wheel_scene.instantiate()
		_materials(v)
		v.rotation.y = 0.0 if right else PI
		w.add_child(v)
		add_child(w)
		wheels.append(w)
	for n in body.find_children("*", "MeshInstance3D", true, false):
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_steering_wheel(meta)
	# ombre douce de contact sous la caisse (le soleil seul laisse la voiture « flotter » quand il est haut)
	var gr := Gradient.new()
	gr.set_color(0, Color(0, 0, 0, 0.62)); gr.set_color(1, Color(0, 0, 0, 0.0))
	gr.add_point(0.55, Color(0, 0, 0, 0.45))
	var gt := GradientTexture2D.new()
	gt.gradient = gr; gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5); gt.fill_to = Vector2(0.5, 0.0); gt.width = 64; gt.height = 128
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.albedo_texture = gt
	sm.render_priority = -1
	var pm := PlaneMesh.new(); pm.size = Vector2(2.3, 4.9)
	var blob := MeshInstance3D.new()
	blob.mesh = pm; blob.material_override = sm
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	blob.position = Vector3(0, 0.05, 0)
	add_child(blob)
	_blob = blob

var _wheel_node: Node3D
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
	paint.albedo_color = Color(0.40, 0.025, 0.03)            # rouge foncé, peinture opaque des années 80
	paint.metallic = 0.0; paint.roughness = 0.32
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
	var hub := StandardMaterial3D.new()                      # enjoliveurs argentés
	hub.albedo_color = Color(0.72, 0.73, 0.75); hub.metallic = 0.45; hub.roughness = 0.35
	if _lamp_mat == null:
		_lamp_mat = lamp; _tail_mat = tail
	var by_name := {"hubcap": hub, "paint": paint, "beige": beige, "orange": orange, "fog": fog, "glass": glass, "chrome": chrome, "rubber": rubber, "plastic": plastic,
		"lamp": lamp, "tail": tail, "interior": vcol, "plate_front": vcol, "plate_rear": vcol}
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var m: Material = mi.mesh.surface_get_material(s)
			var nm := m.resource_name if m else ""
			if by_name.has(nm):
				mi.set_surface_override_material(s, by_name[nm])

var _body: Node3D
var blown := false

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
	_blob.transparency = clampf(gap / 1.2, 0.0, 1.0)

## Vue cockpit (habitacle en pixel art) : la caisse 3D ne fait plus que porter son ombre, le volant 3D disparaît.
func set_cockpit(on: bool) -> void:
	for n in _body.find_children("*", "MeshInstance3D", true, false):
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if on else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if _wheel_node:
		_wheel_node.visible = not on

## Explosion (gardien des limites) : la voiture disparaît et s'immobilise jusqu'à sa réapparition.
func blow_up() -> void:
	blown = true
	_body.visible = false
	_blob.visible = false
	for w in wheels:
		w.visible = false
	freeze = true

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
	blown = false

var _lamp_mat: StandardMaterial3D
var _tail_mat: StandardMaterial3D
var _beams := []

## Phares (soir, nuit) : deux faisceaux, optiques et feux arrière lumineux.
func set_lights(on: bool) -> void:
	if _beams.is_empty() and on:
		for sx in [-0.585, 0.585]:
			var s := SpotLight3D.new()
			s.position = Vector3(sx, 0.69, 2.2)
			s.rotation = Vector3(deg_to_rad(-4.0), PI, 0)        # vers l'avant (+Z) et un peu vers le bas
			s.spot_range = 45.0
			s.spot_angle = 28.0
			s.spot_attenuation = 0.8
			s.light_energy = 6.0
			s.light_color = Color(1.0, 0.93, 0.78)
			s.shadow_enabled = false
			add_child(s)
			_beams.append(s)
	for s in _beams:
		s.visible = on
	if _lamp_mat:
		_lamp_mat.emission_enabled = on
		_lamp_mat.emission = Color(1.0, 0.95, 0.85)
		_lamp_mat.emission_energy_multiplier = 3.0
	if _tail_mat:
		_tail_mat.emission_enabled = on
		_tail_mat.emission = Color(0.9, 0.05, 0.03)
		_tail_mat.emission_energy_multiplier = 2.0

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
	_place_blob()
	if _hold_t > 0.0:
		_hold_t -= dt
		global_transform = _hold_xf
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		return
	var thr := clampf(Input.get_action_strength("accelerer") + touch_throttle, 0.0, 1.0)
	var brk := clampf(Input.get_action_strength("freiner") + touch_brake, 0.0, 1.0)
	var st := clampf(Input.get_action_strength("gauche") - Input.get_action_strength("droite") + touch_steer, -1.0, 1.0)
	var v := forward_speed()
	# sens de marche « jeu » : la pédale opposée au mouvement freine, puis la voiture repart dans l'autre sens dès
	# qu'elle est presque arrêtée (pas besoin d'attendre l'arrêt complet)
	if brk > 0.1 and thr < 0.1 and v < 0.6:
		reversing = true
	elif thr > 0.1 and brk < 0.1 and v > -0.6:
		reversing = false
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
		if thr > 0.1:
			# en reculant, GAZ freine (puis repart en avant, voir plus haut)
			engine_force = 0.0
			brake = BRAKE * thr
		else:
			engine_force = -ENGINE * 0.5 * brk if spd < 25.0 else 0.0
			brake = 0.0
	else:
		# boîte auto : force limitée par la puissance (F = P / v), coupée à la vitesse max
		var f := thr * minf(ENGINE, POWER / maxf(absf(v), 1.0))
		if spd > MAX_KMH:
			f = 0.0
		engine_force = f if brk < 0.1 or thr > brk else 0.0
		brake = BRAKE * brk + (2.0 if thr < 0.05 and spd < 3.0 and brk < 0.1 else 0.0)
	# frein moteur léger et aide à la stabilité en virage (anti-dérive latérale)
	if thr < 0.05 and not reversing:
		apply_central_force(-linear_velocity * 25.0)
	# traînée aérodynamique (SCx Espace IV ≈ 0,9 m²)
	apply_central_force(-linear_velocity * linear_velocity.length() * 0.55)
	var side := global_transform.basis.x
	var lat := linear_velocity.dot(side)
	apply_central_force(-side * lat * mass * 0.6 * dt * 60.0 * 0.05)
	_anti_roll()
	_recovery(dt)

## Aide à la stabilité : ramène doucement la caisse à plat autour de son axe longitudinal (roulis), sans toucher au
## tangage (montées, descentes) ; plus ferme en l'air pour retomber sur les roues après un saut.
func _anti_roll() -> void:
	var fwd := global_transform.basis.z
	var up := global_transform.basis.y
	var on_ground := wheels.any(func(w): return w.is_in_contact())
	# angle de roulis : inclinaison de l'axe vertical de la caisse dans le plan perpendiculaire à l'avant
	var ref := (Vector3.UP - fwd * Vector3.UP.dot(fwd)).normalized()
	var roll := up.signed_angle_to(ref, fwd)
	var k := 9000.0 if on_ground else 14000.0
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
	# bloqué (accélère sans avancer) plus de 4 s
	var thr := Input.get_action_strength("accelerer") + touch_throttle
	_stuck_t = _stuck_t + dt if (thr > 0.3 and kmh() < 1.5) else 0.0
	if p.y < -50.0 or _flip_t > 1.2 or _stuck_t > 4.0 or Input.is_action_just_pressed("replacer"):
		reset_to_road()

## Remise sur la route la plus proche, dans le sens de la voie le plus proche de celui de la voiture.
func reset_to_road() -> void:
	var p := global_position
	if not p.is_finite():
		p = safe[-1].origin if safe.size() > 0 else Vector3.ZERO
	var fwd := global_transform.basis.z
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
			# cap du point (0 = Nord = -Z, sens horaire) -> direction ; sens opposé pénalisé de 15 m
			var h := deg_to_rad(road_pts[i + 3])
			if Vector2(sin(h), -cos(h)).dot(Vector2(fwd.x, fwd.z).normalized()) < 0.0:
				d += 225.0
		if d < bd:
			bd = d; best = i
	if best >= 0:
		place(Vector3(road_pts[best], road_pts[best + 2] + 0.3, road_pts[best + 1]), road_pts[best + 3])
	else:
		var t: Transform3D = safe[max(0, safe.size() - 3)] if safe.size() > 0 else global_transform
		global_transform = Transform3D(Basis(Vector3.UP, t.basis.get_euler().y), t.origin + Vector3(0, 0.8, 0))
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
	_flip_t = 0.0; _stuck_t = 0.0
