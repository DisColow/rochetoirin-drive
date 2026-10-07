## Gardien des limites : un combattant volant (inspiré des héros de mangas de combat : cheveux en pics, kimono orange
## et bleu, aura dorée) plane toujours au-delà de la limite de la carte la plus proche de la voiture. Quand la voiture
## s'approche de la limite, il charge son attaque (on l'entend, la boule d'énergie grossit) ; si elle sort, il tire une
## vague d'énergie : la voiture explose puis réapparaît sur la route la plus proche, dans le sens inverse.
## Il dit « Ka… mé… ha… mé… » en chargeant (mains ramenées à la hanche, boule bleue qui grossit) mais ne tire
## (« HAAA ! », bras tendus) que si la voiture tombe vraiment dans le vide hors de la carte.
## Pas de cinématique : le jeu continue, la caméra ne bouge pas.
extends Node3D

const SCALE := 5.0              # personnage agrandi : visible de loin
const OUT_DIST := 65.0          # distance au-delà de la limite (m)
const ALT := 24.0               # altitude au-dessus du sol (m)
const CHARGE_DIST := 220.0      # début de la charge (distance de la voiture à la limite, m)
const RESPAWN_MARGIN := 40.0    # réapparition à au moins 40 m de la limite

var car: VehicleBody3D
var terrain: Node
var zone := PackedVector2Array()
var body: Node3D
var model: Node3D
var skel: Skeleton3D
var hand_l := -1
var hand_r := -1
var aura: MeshInstance3D
var ball: MeshInstance3D
var beam: MeshInstance3D
var flash: OmniLight3D
var fire: CPUParticles3D
var smoke: CPUParticles3D
var debris: CPUParticles3D
var snd_charge: AudioStreamPlayer3D
var snd_wave: AudioStreamPlayer3D
var snd_boom: AudioStreamPlayer3D
var snd_kame: AudioStreamPlayer3D
var snd_ha: AudioStreamPlayer3D
var _said := false
var iks := []
var anim: AnimationPlayer
var glow: MeshInstance3D
var ball_light: OmniLight3D
var head: MeshInstance3D
var state := "veille"
var _t := 0.0
var _out_t := 0.0
var _charge := 0.0
var _hit_pos := Vector3.ZERO
var _out_dir := Vector2(1, 0)

func _ready() -> void:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://world/zone.json"))
	for p in d.pts:
		zone.append(Vector2(float(p[0]), float(p[1])))
	_build_character()
	_build_effects()
	snd_charge = _sound("charge", true, 70.0)
	snd_wave = _sound("vague", false, 120.0)
	snd_boom = _sound("boum", false, 150.0)
	snd_kame = _sound("kame", false, 260.0)
	snd_ha = _sound("ha", false, 320.0)
	snd_kame.volume_db = 4.0
	snd_ha.volume_db = 6.0

# ---------------------------------------------------------------- personnage (formes simples, original)
func _mat(c: Color, emit := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.7
	if emit > 0.0:
		m.emission_enabled = true; m.emission = c; m.emission_energy_multiplier = emit
	return m

func _part(parent: Node3D, mesh: Mesh, m: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh; mi.material_override = m
	mi.position = pos; mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new(); c.radius = r; c.height = h; c.radial_segments = 12; c.rings = 4
	return c

func _build_character() -> void:
	# modèle « Goku (Rigged & Animated) » de Kari (Sketchfab, CC BY 4.0), animation de garde en boucle
	body = Node3D.new()
	body.scale = Vector3.ONE * SCALE
	add_child(body)
	model = load("res://models/goku.glb").instantiate()
	model.scale = Vector3.ONE * (1.8 / 2.85)          # hauteur d'origine 2,85 -> 1,8 (× SCALE)
	body.add_child(model)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var aps := model.find_children("*", "AnimationPlayer", true, false)
	if aps.size() > 0:
		var ap: AnimationPlayer = aps[0]
		var an := ap.get_animation_list()[0]
		ap.get_animation(an).loop_mode = Animation.LOOP_LINEAR
		ap.play(an)
	var sks := model.find_children("*", "Skeleton3D", true, false)
	if sks.size() > 0:
		skel = sks[0]
		hand_l = skel.find_bone("mixamorig_LeftHand_011")
		hand_r = skel.find_bone("mixamorig_RightHand_035")
		# bras guidés par cinématique inverse à deux os (calculée ici : épaule -> coude -> main)
		for side in [["mixamorig_LeftArm_09", "mixamorig_LeftForeArm_010", "mixamorig_LeftHand_011"],
				["mixamorig_RightArm_033", "mixamorig_RightForeArm_034", "mixamorig_RightHand_035"]]:
			var ids := [skel.find_bone(side[0]), skel.find_bone(side[1]), skel.find_bone(side[2])]
			if -1 in ids:
				continue
			iks.append(ids)
		var aps2 := model.find_children("*", "AnimationPlayer", true, false)
		if aps2.size() > 0:
			anim = aps2[0]
	# aura dorée (panneau lumineux additif) et boule d'énergie bleue
	aura = MeshInstance3D.new()
	var q := QuadMesh.new(); q.size = Vector2(2.6, 3.4)
	aura.mesh = q
	var sm := ShaderMaterial.new()
	sm.shader = Shader.new()
	sm.shader.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec3 col : source_color = vec3(1.0, 0.85, 0.35);
uniform float strength = 1.0;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0, 0, 0), vec4(0, length(MODEL_MATRIX[1].xyz), 0, 0), vec4(0, 0, length(MODEL_MATRIX[2].xyz), 0), vec4(0, 0, 0, 1));
}
void fragment() {
	vec2 p = (UV - 0.5) * vec2(2.0, 2.0);
	float flame = 0.75 + 0.25 * sin(TIME * 13.0 + UV.y * 20.0) * sin(TIME * 7.0 + UV.x * 9.0);
	float r = length(p * vec2(1.0, 0.8 + 0.2 * UV.y));
	float a = smoothstep(1.0, 0.25, r) * flame * strength;
	ALBEDO = col * a * 1.6;
}
"""
	aura.material_override = sm
	aura.position = Vector3(0, 1.1, 0)
	aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(aura)
	ball = MeshInstance3D.new()
	var s := SphereMesh.new(); s.radius = 0.2; s.height = 0.4
	ball.mesh = s
	var bm := _mat(Color(0.55, 0.8, 1.0), 6.0)
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ball.material_override = bm
	ball.position = Vector3(-0.42, 1.0, 0.12)
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(ball)
	# halo bleu autour de la boule (panneau additif face à la caméra) et lumière bleue sur le personnage
	glow = MeshInstance3D.new()
	var gq := QuadMesh.new(); gq.size = Vector2(1.0, 1.0)
	glow.mesh = gq
	var gm := ShaderMaterial.new()
	gm.shader = Shader.new()
	gm.shader.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform float strength = 1.0;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0, 0, 0), vec4(0, length(MODEL_MATRIX[1].xyz), 0, 0), vec4(0, 0, length(MODEL_MATRIX[2].xyz), 0), vec4(0, 0, 0, 1));
}
void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float a = atan(p.y, p.x);
	float rays = 0.6 + 0.4 * sin(a * 9.0 + TIME * 6.0) * sin(a * 5.0 - TIME * 9.0);
	float core = smoothstep(0.35, 0.0, r);
	float halo = smoothstep(1.0, 0.2, r) * rays;
	ALBEDO = (vec3(0.35, 0.65, 1.0) * halo * 1.4 + vec3(0.9, 0.97, 1.0) * core * 2.0) * strength;
}
"""
	glow.material_override = gm
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(glow)
	ball_light = OmniLight3D.new()
	ball_light.light_color = Color(0.45, 0.7, 1.0)
	ball_light.omni_range = 4.0
	ball_light.light_energy = 0.0
	body.add_child(ball_light)

func _build_effects() -> void:
	beam = MeshInstance3D.new()
	var c := CylinderMesh.new(); c.top_radius = 1.0; c.bottom_radius = 1.0; c.height = 1.0; c.radial_segments = 16
	beam.mesh = c
	var bm := _mat(Color(0.75, 0.92, 1.0), 12.0)
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam.material_override = bm
	var shell := MeshInstance3D.new()
	shell.mesh = c
	shell.scale = Vector3(2.2, 1.0, 2.2)
	var sm2 := ShaderMaterial.new()
	sm2.shader = Shader.new()
	sm2.shader.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
void fragment() {
	float f = abs(dot(NORMAL, VIEW));
	float edge = pow(1.0 - f, 1.3);
	float flow = 0.55 + 0.45 * sin(UV.y * 70.0 - TIME * 55.0 + UV.x * 18.0) * sin(UV.y * 23.0 - TIME * 31.0);
	ALBEDO = vec3(0.3, 0.62, 1.0) * (0.35 + edge * 1.8) * flow;
}
"""
	shell.material_override = sm2
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.add_child(shell)
	beam.visible = false
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)
	head = MeshInstance3D.new()
	var hs := SphereMesh.new(); hs.radius = 1.0; hs.height = 2.0
	head.mesh = hs
	head.material_override = bm
	head.visible = false
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(head)
	flash = OmniLight3D.new()
	flash.light_color = Color(1.0, 0.7, 0.35)
	flash.omni_range = 60.0
	flash.light_energy = 0.0
	add_child(flash)
	fire = _particles(Color(1.0, 0.55, 0.15), 70, 1.0, 11.0, 3.0)
	smoke = _particles(Color(0.25, 0.24, 0.23), 50, 3.0, 5.0, 5.0)
	debris = _debris()

func _particles(col: Color, n: int, life: float, speed: float, size: float) -> CPUParticles3D:
	var hot := col.r > 0.5
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = n
	p.lifetime = life
	p.explosiveness = 0.92
	p.direction = Vector3.UP
	p.spread = 75.0
	p.initial_velocity_min = speed * 0.4; p.initial_velocity_max = speed
	p.gravity = Vector3(0, -2.0 if hot else 2.0, 0)
	p.damping_min = 3.0; p.damping_max = 6.0
	p.scale_amount_min = size * 0.7; p.scale_amount_max = size * 1.5
	# grossit en vieillissant ; couleur : jaune -> orange -> rouge sombre (feu), gris -> transparent (fumée)
	var sc := Curve.new(); sc.add_point(Vector2(0, 0.5)); sc.add_point(Vector2(1, 1.6))
	p.scale_amount_curve = sc
	var g := Gradient.new()
	if hot:
		g.set_color(0, Color(1.0, 0.95, 0.6, 1.0)); g.set_color(1, Color(0.35, 0.05, 0.0, 0.0))
		g.add_point(0.35, Color(1.0, 0.5, 0.1, 0.9))
	else:
		g.set_color(0, Color(0.3, 0.29, 0.28, 0.0)); g.set_color(1, Color(0.2, 0.2, 0.2, 0.0))
		g.add_point(0.15, Color(0.28, 0.27, 0.26, 0.75))
	p.color_ramp = g
	var q := QuadMesh.new(); q.size = Vector2(1, 1)
	p.mesh = q
	var tex := GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5); tex.fill_to = Vector2(0.5, 0.0)
	var tg := Gradient.new(); tg.set_color(0, Color(1, 1, 1, 1)); tg.set_color(1, Color(1, 1, 1, 0))
	tex.gradient = tg
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if hot else BaseMaterial3D.BLEND_MODE_MIX
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if hot else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	p.material_override = mat
	add_child(p)
	return p

func _debris() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false; p.one_shot = true
	p.amount = 24; p.lifetime = 2.2; p.explosiveness = 1.0
	p.direction = Vector3.UP; p.spread = 70.0
	p.initial_velocity_min = 8.0; p.initial_velocity_max = 18.0
	p.gravity = Vector3(0, -9.8, 0)
	p.angular_velocity_min = -400.0; p.angular_velocity_max = 400.0
	p.scale_amount_min = 0.15; p.scale_amount_max = 0.6
	var b := BoxMesh.new(); b.size = Vector3(1, 0.15, 0.7)
	p.mesh = b
	p.material_override = _mat(Color(0.4, 0.03, 0.03))
	add_child(p)
	return p

func _sound(name: String, loop: bool, unit: float) -> AudioStreamPlayer3D:
	var s := AudioStreamPlayer3D.new()
	var st: AudioStreamWAV = load("res://assets/sfx/%s.wav" % name)
	if loop:
		st = st.duplicate()
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		st.loop_begin = 0
		st.loop_end = st.data.size() / 2
	s.stream = st
	s.unit_size = unit
	s.max_distance = 1500.0
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
	var cp := car.global_position
	var p := Vector2(cp.x, cp.z)
	var inside := Geometry2D.is_point_in_polygon(p, zone)
	var nr := _nearest(p)
	var q: Vector2 = nr[0]; var d: float = nr[1]
	if d > 0.5:
		_out_dir = ((q - p) if inside else (p - q)).normalized()
	# position : au-delà de la limite, face à la voiture, il plane (léger balancement)
	var target2 := q + _out_dir * OUT_DIST
	var gy := _ground(target2.x, target2.y, cp.y)
	var target := Vector3(target2.x, gy + ALT + sin(_t * 1.3) * 1.5, target2.y)
	var gp := global_position
	if gp.distance_to(target) > 2500.0 or gp == Vector3.ZERO:
		global_position = target
	else:
		global_position = gp.move_toward(target, (60.0 + gp.distance_to(target)) * dt)
	var look := Vector3(cp.x, global_position.y, cp.z)
	if look.distance_to(global_position) > 1.0:
		body.look_at(look, Vector3.UP, true)
	match state:
		"veille", "charge":
			_out_t = _out_t + dt if not inside else 0.0
			var want := clampf(1.0 - (d - 20.0) / (CHARGE_DIST - 20.0), 0.0, 1.0) if inside else 1.0
			_charge = move_toward(_charge, want, dt * 0.8)
			state = "charge" if _charge > 0.02 else "veille"
			_pose(_charge, 0.0)
			if _charge > 0.12 and not _said:
				_said = true
				snd_kame.global_position = global_position
				snd_kame.play()
			elif _charge < 0.03:
				_said = false
			if state == "charge":
				if not snd_charge.playing:
					snd_charge.play()
				snd_charge.volume_db = linear_to_db(0.25 + 0.75 * _charge)
				snd_charge.pitch_scale = 0.8 + 0.6 * _charge
			elif snd_charge.playing:
				snd_charge.stop()
			if not inside and not car.blown and _in_void(cp, d):
				_fire()
		"tir":
			var k := clampf((_t - _fire_t) / 0.35, 0.0, 1.0)
			var a: Vector3 = ball.global_position
			var b := a.lerp(_hit_pos, k)
			_place_beam(a, b, 2.2 + 0.5 * sin(_t * 40.0))
			head.visible = beam.visible
			head.global_position = b
			head.scale = Vector3.ONE * (3.0 + 0.6 * sin(_t * 30.0))
			_pose(1.0, 1.0)
			if k >= 1.0 and not _exploded:
				_explode()
			if _t - _fire_t > 1.4:
				beam.visible = false
				head.visible = false
			if _t - _fire_t > 2.2:
				_respawn()
				state = "repos"
		"repos":
			_charge = move_toward(_charge, 0.0, dt)
			_pose(_charge, 0.0)
			if _t - _fire_t > 5.0:
				state = "veille"
	flash.light_energy = move_toward(flash.light_energy, 0.0, dt * 12.0)
	(aura.material_override as ShaderMaterial).set_shader_parameter("strength", 0.6 + 0.6 * _charge)

var _fire_t := 0.0
var _exploded := false

## La voiture tombe dans le vide hors de la carte : plus de relief dessous, ou nettement sous le sol, ou en chute
## libre. (Rouler hors de la zone sur du relief ne déclenche pas le tir ; très loin, si.)
func _in_void(cp: Vector3, d: float) -> bool:
	if d > 350.0:
		return true
	var h := NAN
	if terrain and terrain.data:
		h = terrain.data.get_height(cp)
	if is_nan(h) or absf(h) > 5000.0:
		return true
	if cp.y < h - 2.5:
		return true
	var touching := false
	for w in car.wheels:
		if w.is_in_contact():
			touching = true
	return not touching and car.linear_velocity.y < -9.0

func _pose(charge: float, fire_k: float) -> void:
	# boule d'énergie entre les poings (garde du modèle), qui grossit avec la charge ; projetée vers l'avant au tir
	var at := Vector3(0, 1.3, 0.35)
	if skel and hand_l >= 0 and hand_r >= 0:
		var pl := skel.global_transform * skel.get_bone_global_pose(hand_l).origin
		var pr := skel.global_transform * skel.get_bone_global_pose(hand_r).origin
		at = body.to_local((pl + pr) * 0.5)
	ball.position = at.lerp(at + Vector3(0, 0, 0.5), fire_k)
	ball.scale = Vector3.ONE * (0.2 + charge * 1.6 + fire_k * 0.8)
	ball.visible = charge > 0.03
	glow.position = ball.position
	glow.scale = Vector3.ONE * (0.25 + charge * 0.9 + fire_k * 0.8)
	glow.visible = ball.visible
	(glow.material_override as ShaderMaterial).set_shader_parameter("strength", 0.4 + 0.8 * charge + fire_k)
	ball_light.position = ball.position
	ball_light.light_energy = charge * 3.0 + fire_k * 6.0
	# bras : mains jointes ramenées à la hanche droite pendant la charge, projetées vers l'avant au tir
	var k := clampf(charge * 1.6, 0.0, 1.0)
	var w := maxf(k, fire_k)
	if anim:
		if w > 0.01 and anim.is_playing():
			anim.pause()
		elif w <= 0.01 and not anim.is_playing():
			anim.play()
	if w > 0.01 and skel:
		var hip := Vector3(-0.30, 0.95, -0.05)
		var front := Vector3(0.0, 1.30, 0.75)
		for i in iks.size():
			var sgn := 1.0 if i == 0 else -1.0
			var tp := hip.lerp(front, fire_k) + Vector3(0.07 * sgn, 0.0, 0.0)
			var tw := body.to_global(tp)
			_arm_ik(iks[i], skel.global_transform.affine_inverse() * tw, w, sgn)

## Cinématique inverse à deux os : oriente bras et avant-bras pour amener la main vers la cible (repère du squelette),
## coude vers l'extérieur et vers le bas ; w : part de la correction (fondu depuis la pose de garde).
func _arm_ik(ids: Array, target: Vector3, w: float, sgn: float) -> void:
	var gA := skel.get_bone_global_pose(ids[0])
	var gB := skel.get_bone_global_pose(ids[1])
	var gC := skel.get_bone_global_pose(ids[2])
	var S := gA.origin; var E := gB.origin; var H := gC.origin
	var a := S.distance_to(E); var b := E.distance_to(H)
	var to := target - S
	var d := clampf(to.length(), absf(a - b) + 0.001, a + b - 0.001)
	var dir := to.normalized()
	var pole := (Vector3(sgn * 1.0, -0.6, -0.4)).normalized()
	pole = (pole - dir * pole.dot(dir)).normalized()
	var x := (a * a - b * b + d * d) / (2.0 * d)
	var h := sqrt(maxf(a * a - x * x, 0.0))
	var E2 := S + dir * x + pole * h
	var T2 := S + dir * d
	# bras
	var q1 := Quaternion((E - S).normalized(), (E2 - S).normalized())
	q1 = Quaternion.IDENTITY.slerp(q1, w)
	var nA := Transform3D(Basis(q1) * gA.basis, S)
	_set_global(ids[0], nA)
	gB = skel.get_bone_global_pose(ids[1])
	gC = skel.get_bone_global_pose(ids[2])
	var q2 := Quaternion((gC.origin - gB.origin).normalized(), (T2 - gB.origin).normalized())
	q2 = Quaternion.IDENTITY.slerp(q2, w)
	_set_global(ids[1], Transform3D(Basis(q2) * gB.basis, gB.origin))

func _set_global(i: int, g: Transform3D) -> void:
	var par := skel.get_bone_parent(i)
	var pg := skel.get_bone_global_pose(par) if par >= 0 else Transform3D.IDENTITY
	var loc := pg.affine_inverse() * g
	skel.set_bone_pose_rotation(i, loc.basis.get_rotation_quaternion())

func _place_beam(a: Vector3, b: Vector3, r: float) -> void:
	var L := a.distance_to(b)
	if L < 0.1:
		beam.visible = false
		return
	beam.visible = true
	var y := (b - a) / L
	var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	beam.global_transform = Transform3D(Basis(x * r, y * L, z * r), (a + b) * 0.5)

func _fire() -> void:
	state = "tir"
	_fire_t = _t
	_exploded = false
	_hit_pos = car.global_position + Vector3(0, 0.8, 0)
	snd_charge.stop()
	snd_wave.global_position = global_position
	snd_wave.play()
	snd_ha.global_position = global_position
	snd_ha.play()

func _explode() -> void:
	_exploded = true
	var p := car.global_position + Vector3(0, 0.7, 0)
	for e in [fire, smoke, debris]:
		e.global_position = p
		e.restart()
		e.emitting = true
	flash.global_position = p + Vector3(0, 2, 0)
	flash.light_energy = 16.0
	snd_boom.global_position = p
	snd_boom.play()
	if car.has_method("blow_up"):
		car.blow_up()
	var rig = get_parent().get("cam_rig")
	if rig and "shake" in rig:
		rig.shake = 1.0

## Réapparition sur la route la plus proche, dans le sens inverse de la marche, à bonne distance de la limite.
func _respawn() -> void:
	var cp := car.global_position
	var fwd := car.global_transform.basis.z
	var pts: PackedFloat32Array = car.road_pts
	var cands := []
	for i in range(0, pts.size(), 4):
		var dx := pts[i] - cp.x; var dz := pts[i + 1] - cp.z
		var dd := dx * dx + dz * dz
		if dd > 900.0 * 900.0:
			continue
		var h := deg_to_rad(pts[i + 3])
		# sens inverse de la voiture privilégié
		if Vector2(sin(h), -cos(h)).dot(Vector2(fwd.x, fwd.z).normalized()) > 0.0:
			dd += 400.0
		cands.append([dd, i])
	cands.sort_custom(func(a, b): return a[0] < b[0])
	for c in cands.slice(0, 400):
		var i: int = c[1]
		var p2 := Vector2(pts[i], pts[i + 1])
		if Geometry2D.is_point_in_polygon(p2, zone) and float(_nearest(p2)[1]) >= RESPAWN_MARGIN:
			car.respawn_at(Vector3(pts[i], pts[i + 2] + 0.3, pts[i + 1]), pts[i + 3])
			_snap_camera()
			return
	car.respawn_at(Vector3.INF, 0.0)
	_snap_camera()

func _snap_camera() -> void:
	var rig = get_parent().get("cam_rig")
	if rig and rig.has_method("snap"):
		rig.snap()
