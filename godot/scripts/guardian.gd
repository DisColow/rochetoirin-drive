## Gardien des limites : une soucoupe volante (« UFO » de sebslom, Sketchfab, CC BY 4.0), invisible et silencieuse tant
## qu'on ne tombe pas : on peut rouler au-delà de la limite tant qu'il y a du relief. Dès que la voiture commence à
## tomber hors de la carte (plus de relief dessous), elle surgit du ciel, la saisit dans son rayon tracteur, la soulève, l'emporte au-dessus du pays et la repose doucement sur la route la plus
## proche, dans le sens qui ramène vers l'intérieur de la carte, puis repart vers le ciel et disparaît.
## Pas de cinématique : la caméra suit la voiture, le joueur reprend la main dès qu'elle touche la route.
extends Node3D

const RESPAWN_MARGIN := 40.0    # dépôt à au moins 40 m de la limite
const BEAM_H := 10.0            # hauteur de la soucoupe au-dessus de la voiture portée (m)
const CRUISE := 28.0            # marge de vol au-dessus du relief pendant le transport (m)

var car: VehicleBody3D
var terrain: Node
var zone := PackedVector2Array()
var body: Node3D                # soucoupe (tourne sur elle-même)
var beam: MeshInstance3D
var beam_mat: ShaderMaterial
var beam_light: SpotLight3D
var under_light: OmniLight3D
var sparks: CPUParticles3D
var snd_hum: AudioStreamPlayer3D
var snd_beam: AudioStreamPlayer3D
var snd_in: AudioStreamPlayer3D     # passage en piqué à l'arrivée
var snd_out: AudioStreamPlayer3D    # départ en flèche
var state := "veille"           # veille (cachée), saisie, levage, transport, depose, depart
var _t := 0.0
var _st := 0.0                  # temps passé dans l'état courant
var _charge := 0.0              # éveil de la soucoupe (0 à 1)
var _beam := 0.0                # intensité du rayon (0 à 1)
var _out_dir := Vector2(1, 0)
var _tilt := Vector3.ZERO
# trajet de la voiture portée
var _p0 := Vector3.ZERO         # où elle a été saisie
var _b0 := Basis()
var _lift := Vector3.ZERO       # fin du levage
var _dest := Vector3.ZERO       # point de route d'arrivée
var _dest_h := 0.0              # cap d'arrivée (degrés, 0 = Nord, sens horaire)
var _cruise_y := 0.0
var _dur := 1.0

func _ready() -> void:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://world/zone.json"))
	for p in d.pts:
		zone.append(Vector2(float(p[0]), float(p[1])))
	_build_saucer()
	_build_beam()
	snd_hum = _sound("soucoupe", 60.0)
	snd_beam = _sound("rayon", 40.0)
	snd_in = _sound("soucoupe_arrivee", 90.0, false)
	snd_out = _sound("soucoupe_depart", 90.0, false)

# ---------------------------------------------------------------- soucoupe et rayon
func _build_saucer() -> void:
	body = Node3D.new()
	add_child(body)
	var model: Node3D = load("res://assets/ufo/ufo.glb").instantiate()
	body.add_child(model)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# lueur sous la coque (s'allume quand la soucoupe se réveille)
	under_light = OmniLight3D.new()
	under_light.light_color = Color(0.55, 1.0, 0.75)
	under_light.omni_range = 18.0
	under_light.light_energy = 0.0
	under_light.position = Vector3(0, -1.0, 0)
	body.add_child(under_light)
	var halo := MeshInstance3D.new()
	var q := QuadMesh.new(); q.size = Vector2(9, 9); q.orientation = PlaneMesh.FACE_Y
	halo.mesh = q
	halo.position = Vector3(0, -0.15, 0)
	halo.material_override = _additive("""
uniform float strength = 0.0;
void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float lamps = smoothstep(0.75, 1.0, sin(a * 8.0 + TIME * 2.5)) * smoothstep(0.12, 0.0, abs(r - 0.72));
	float core = smoothstep(0.55, 0.0, r);
	ALBEDO = (vec3(0.45, 1.0, 0.7) * core * 0.9 + vec3(1.0, 0.95, 0.6) * lamps * 2.5) * strength;
}
""")
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(halo)
	body.set_meta("halo", halo)

func _additive(code: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = Shader.new()
	m.shader.code = "shader_type spatial;\nrender_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;\n" + code
	return m

func _build_beam() -> void:
	# cône de lumière : anneaux qui montent, bords plus vifs, fondu en haut et au pied
	beam = MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 1.6; c.bottom_radius = 4.5; c.height = 1.0
	c.radial_segments = 32; c.rings = 1; c.cap_top = false; c.cap_bottom = false
	beam.mesh = c
	beam_mat = _additive("""
uniform float strength = 0.0;
void fragment() {
	float f = abs(dot(NORMAL, VIEW));
	float edge = 0.35 + pow(1.0 - f, 2.0) * 1.6;
	float rings = 0.55 + 0.45 * smoothstep(0.3, 1.0, sin(UV.y * 40.0 + TIME * 9.0));
	float swirl = 0.8 + 0.2 * sin(UV.x * 6.2832 * 6.0 + UV.y * 12.0 - TIME * 3.0);
	float ends = smoothstep(0.0, 0.12, UV.y) * smoothstep(1.0, 0.8, UV.y);
	ALBEDO = vec3(0.45, 1.0, 0.72) * edge * rings * swirl * ends * strength * 0.32;
}
""")
	beam.material_override = beam_mat
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.visible = false
	add_child(beam)
	beam_light = SpotLight3D.new()
	beam_light.light_color = Color(0.55, 1.0, 0.75)
	beam_light.spot_range = 40.0
	beam_light.spot_angle = 16.0
	beam_light.light_energy = 0.0
	beam_light.shadow_enabled = false
	beam_light.rotation = Vector3(-PI / 2, 0, 0)        # vers le bas
	body.add_child(beam_light)
	# étincelles qui montent dans le rayon
	sparks = CPUParticles3D.new()
	sparks.emitting = false
	sparks.amount = 40
	sparks.lifetime = 1.4
	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	sparks.emission_sphere_radius = 2.5
	sparks.direction = Vector3.UP
	sparks.spread = 8.0
	sparks.gravity = Vector3.ZERO
	sparks.initial_velocity_min = 5.0; sparks.initial_velocity_max = 9.0
	sparks.scale_amount_min = 0.05; sparks.scale_amount_max = 0.13
	var q := QuadMesh.new(); q.size = Vector2(1, 1)
	sparks.mesh = q
	var tex := GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5); tex.fill_to = Vector2(0.5, 0.0)
	var tg := Gradient.new(); tg.set_color(0, Color(1, 1, 1, 1)); tg.set_color(1, Color(1, 1, 1, 0))
	tex.gradient = tg
	var g := Gradient.new()
	g.set_color(0, Color(0.8, 1.0, 0.85, 0.0)); g.add_point(0.2, Color(0.7, 1.0, 0.8, 1.0)); g.set_color(1, Color(0.4, 1.0, 0.7, 0.0))
	sparks.color_ramp = g
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sparks.material_override = mat
	add_child(sparks)

## Sons de la soucoupe : enregistrements BigSoundBank (CC0, build_sons.py) ; `loop` : boucle sans couture.
func _sound(name: String, unit: float, loop := true) -> AudioStreamPlayer3D:
	var s := AudioStreamPlayer3D.new()
	var st: AudioStreamOggVorbis = (load("res://assets/sfx/%s.ogg" % name) as AudioStreamOggVorbis).duplicate()
	st.loop = loop
	s.stream = st
	s.unit_size = unit
	s.max_distance = 1200.0
	s.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	add_child(s)
	return s

# ---------------------------------------------------------------- géométrie de la limite
## [point de la limite le plus proche, distance] (2D)
func _nearest(p: Vector2) -> Array:
	var best := Vector2.ZERO; var bd := INF
	var n := zone.size()
	for i in n:
		var q := Geometry2D.get_closest_point_to_segment(p, zone[i], zone[(i + 1) % n])
		var d := p.distance_squared_to(q)
		if d < bd:
			bd = d; best = q
	return [best, sqrt(bd)]

func _ground(x: float, z: float, fallback: float) -> float:
	if terrain and terrain.data:
		var h: float = terrain.data.get_height(Vector3(x, 0, z))
		if not is_nan(h) and absf(h) < 5000.0:
			return h
	return fallback

# ---------------------------------------------------------------- boucle
func _process(dt: float) -> void:
	if car == null or zone.is_empty():
		return
	_t += dt
	_st += dt
	var cp := car.global_position
	var p := Vector2(cp.x, cp.z)
	var inside := Geometry2D.is_point_in_polygon(p, zone)
	var nr := _nearest(p)
	var q: Vector2 = nr[0]; var d: float = nr[1]
	var prev := global_position
	match state:
		"veille":
			# cachée : aucun aperçu de l'engin avant qu'on en ait besoin
			if d > 0.5:
				_out_dir = ((q - p) if inside else (p - q)).normalized()
			visible = false
			_charge = 0.0
			_beam = 0.0
			if not inside and not car.blown and _in_void(cp):
				_seize()
				return
		"depart":
			# repart en flèche vers le ciel, au-delà de la limite, puis disparaît
			_beam = move_toward(_beam, 0.0, dt * 2.0)
			_charge = move_toward(_charge, 0.0, dt * 0.35)
			_fly_to(_dest + Vector3(-_out_dir.x * 260.0, 160.0, -_out_dir.y * 260.0) * _ease(minf(_st / 3.0, 1.0)), dt, 160.0)
			if _st > 3.2:
				_go("veille")
		"saisie":
			# la voiture est figée dans le rayon ; la soucoupe vient se placer au-dessus
			_charge = 1.0
			var above := car.global_position + Vector3(0, BEAM_H, 0)
			_fly_to(above, dt, 90.0)
			_beam = move_toward(_beam, 1.0, dt * 2.0)
			_hold_car(_p0, _b0, dt)
			if global_position.distance_to(above) < 1.5 or _st > 4.0:
				_go("levage")
				_dur = clampf((_cruise_y - _p0.y) / 9.0, 1.8, 4.0)
				_lift = Vector3(_p0.x, _cruise_y, _p0.z)
		"levage":
			var k := _ease(_st / _dur)
			var pos := _p0.lerp(_lift, k)
			pos += Vector3(sin(_t * 2.3), 0, cos(_t * 1.9)) * 0.25 * sin(PI * k)
			var b := _b0.slerp(_level(_b0), k)
			_hold_car(pos, b.rotated(Vector3.UP, sin(_t * 1.4) * 0.15 * k), dt)
			_fly_to(pos + Vector3(0, BEAM_H, 0), dt, 200.0)
			if _st >= _dur:
				_go("transport")
				_dur = clampf(Vector2(_lift.x, _lift.z).distance_to(Vector2(_dest.x, _dest.z)) / 55.0, 2.0, 12.0)
		"transport":
			var k := _ease(_st / _dur)
			var a := Vector3(_lift.x, _cruise_y, _lift.z)
			var e := Vector3(_dest.x, _cruise_y, _dest.z)
			var pos := a.lerp(e, k) + Vector3(0, sin(_t * 1.7) * 0.4, 0)
			var b0 := _level(_b0)
			var b := b0.slerp(_heading_basis(_dest_h), k)
			_hold_car(pos, b.rotated(Vector3.UP, sin(_t * 1.4) * 0.15 * (1.0 - k)), dt)
			_fly_to(pos + Vector3(0, BEAM_H, 0), dt, 400.0)
			if _st >= _dur:
				_go("depose")
				_dur = clampf((_cruise_y - _dest.y) / 10.0, 1.5, 4.0)
		"depose":
			var k := _ease(_st / _dur)
			var pos := Vector3(_dest.x, lerpf(_cruise_y, _dest.y, k), _dest.z)
			_hold_car(pos, _heading_basis(_dest_h), dt)
			_fly_to(Vector3(_dest.x, _cruise_y + BEAM_H * 0.7 + (_dest.y - _cruise_y) * k * 0.5, _dest.z), dt, 200.0)
			if _st >= _dur:
				_release()
	# saucer : rotation lente, inclinaison dans le sens du vol
	var v := (global_position - prev) / maxf(dt, 1e-4)
	var tilt := Vector3(clampf(v.z * 0.004, -0.2, 0.2), 0, clampf(-v.x * 0.004, -0.2, 0.2))
	_tilt = _tilt.lerp(tilt, clampf(dt * 3.0, 0.0, 1.0))
	body.transform.basis = Basis.from_euler(_tilt) * Basis(Vector3.UP, _t * (0.6 + 1.4 * _beam))
	_effects(dt)

func _go(s: String) -> void:
	state = s
	_st = 0.0

func _ease(k: float) -> float:
	k = clampf(k, 0.0, 1.0)
	return k * k * (3.0 - 2.0 * k)

func _fly_to(target: Vector3, dt: float, speed: float) -> void:
	var gp := global_position
	if gp.distance_to(target) > 2500.0 or gp == Vector3.ZERO:
		global_position = target
	else:
		global_position = gp.move_toward(target, (speed + 2.5 * gp.distance_to(target)) * dt)

func _hold_car(pos: Vector3, b: Basis, _dt: float) -> void:
	car.global_transform = Transform3D(b.orthonormalized(), pos)
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO

## Base de la voiture remise à plat (même cap).
func _level(b: Basis) -> Basis:
	var f := b.z
	f.y = 0.0
	if f.length() < 0.1:
		f = Vector3(0, 0, 1)
	return Basis.looking_at(-f.normalized(), Vector3.UP)

## Base d'un cap (0 = Nord = -Z, sens horaire ; l'avant de la voiture est +Z), comme car.place().
func _heading_basis(h: float) -> Basis:
	return Basis(Vector3.UP, PI - deg_to_rad(h))

func _effects(dt: float) -> void:
	var halo: MeshInstance3D = body.get_meta("halo")
	(halo.material_override as ShaderMaterial).set_shader_parameter("strength", 0.25 + 0.75 * maxf(_charge, _beam))
	under_light.light_energy = 0.4 + 2.0 * maxf(_charge, _beam)
	beam_light.light_energy = 6.0 * _beam
	beam_mat.set_shader_parameter("strength", _beam)
	# rayon : du ventre de la soucoupe jusqu'au sol sous la voiture
	var a := global_position + Vector3(0, -0.5, 0)
	var cp := car.global_position
	var foot := Vector3(cp.x, cp.y - 1.5, cp.z)
	if state in ["veille", "depart"]:
		foot = a + (foot - a).normalized() * a.distance_to(foot) * _beam
	var L := a.distance_to(foot)
	beam.visible = _beam > 0.01 and L > 0.5
	if beam.visible:
		var y := (a - foot) / L
		var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.95 else Vector3.RIGHT).normalized()
		var z := x.cross(y)
		beam.global_transform = Transform3D(Basis(x, y * L, z), (a + foot) * 0.5)
	sparks.emitting = _beam > 0.5 and state != "depart"
	sparks.global_position = cp
	# sons : vrombissement selon l'éveil, rayon pendant le portage
	var hum := maxf(_charge, _beam) if visible else 0.0
	if hum > 0.02:
		if not snd_hum.playing:
			snd_hum.play()
		snd_hum.volume_db = linear_to_db(0.2 + 0.8 * hum)
		snd_hum.pitch_scale = 0.85 + 0.3 * hum + 0.03 * sin(_t * 0.7)
	elif snd_hum.playing:
		snd_hum.stop()
	if _beam > 0.05:
		if not snd_beam.playing:
			snd_beam.play()
		snd_beam.volume_db = linear_to_db(maxf(_beam, 0.01))
		snd_beam.global_position = cp
	elif snd_beam.playing:
		snd_beam.stop()
	snd_hum.global_position = global_position
	snd_in.global_position = global_position
	snd_out.global_position = global_position

## La voiture tombe hors de la carte : plus de relief dessous (au-delà des régions du relief), ou passée sous le sol.
func _in_void(cp: Vector3) -> bool:
	var h := NAN
	if terrain and terrain.data:
		h = terrain.data.get_height(cp)
	if is_nan(h) or absf(h) > 5000.0:
		return car.linear_velocity.y < -2.0           # plus de sol dessous et la voiture descend : elle tombe
	return cp.y < h - 2.5

# ---------------------------------------------------------------- saisie et dépôt
func _seize() -> void:
	_go("saisie")
	# surgit du ciel, au-delà de la limite, et fond sur la voiture
	var cp := car.global_position
	global_position = cp + Vector3(_out_dir.x * 90.0, 70.0, _out_dir.y * 90.0)
	visible = true
	_charge = 1.0
	snd_in.global_position = global_position
	snd_in.play()
	car.carried = true
	car.freeze = true
	_p0 = car.global_position
	_b0 = car.global_transform.basis.orthonormalized()
	_pick_dest()
	# altitude de croisière : au-dessus du relief tout le long du trajet
	var top := maxf(_p0.y, _dest.y)
	for i in 21:
		var k := i / 20.0
		var x := lerpf(_p0.x, _dest.x, k); var z := lerpf(_p0.z, _dest.z, k)
		top = maxf(top, _ground(x, z, top))
	_cruise_y = top + CRUISE

## Route d'arrivée : la plus proche dans la carte, à bonne distance de la limite, de préférence orientée vers
## l'intérieur (on repart dans le droit chemin).
func _pick_dest() -> void:
	var cp := car.global_position
	var pts: PackedFloat32Array = car.road_pts
	var inward := -_out_dir
	var cands := []
	for i in range(0, pts.size(), 4):
		var dx := pts[i] - cp.x; var dz := pts[i + 1] - cp.z
		var dd := dx * dx + dz * dz
		if dd > 1200.0 * 1200.0:
			continue
		var h := deg_to_rad(pts[i + 3])
		if Vector2(sin(h), -cos(h)).dot(inward) < 0.0:
			dd += 900.0
		cands.append([dd, i])
	cands.sort_custom(func(a, b): return a[0] < b[0])
	for c in cands.slice(0, 600):
		var i: int = c[1]
		var p2 := Vector2(pts[i], pts[i + 1])
		if Geometry2D.is_point_in_polygon(p2, zone) and float(_nearest(p2)[1]) >= RESPAWN_MARGIN:
			_dest = Vector3(pts[i], pts[i + 2] + 0.3, pts[i + 1])
			_dest_h = pts[i + 3]
			return
	# rien à proximité : route la plus proche du point de la limite
	var q: Vector2 = _nearest(Vector2(cp.x, cp.z))[0]
	var best := -1; var bd := INF
	for i in range(0, pts.size(), 4):
		var dd := Vector2(pts[i], pts[i + 1]).distance_squared_to(q)
		if dd < bd and Geometry2D.is_point_in_polygon(Vector2(pts[i], pts[i + 1]), zone):
			bd = dd; best = i
	if best >= 0:
		_dest = Vector3(pts[best], pts[best + 2] + 0.3, pts[best + 1])
		_dest_h = pts[best + 3]
	else:
		_dest = cp; _dest_h = 0.0

func _release() -> void:
	car.carried = false
	car.respawn_at(_dest, _dest_h)
	_go("depart")
	snd_out.play()
