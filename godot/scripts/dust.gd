## Poussière soulevée par les roues arrière hors du bitume (chemins, champs, bas-côtés), d'autant plus qu'on roule
## vite ; sur route mouillée, gerbes d'eau à la place (météo).
extends Node3D

var car: VehicleBody3D
var roads: Node
var wet := 0.0
var emitters := []

func _ready() -> void:
	var gr := Gradient.new()
	gr.set_color(0, Color(1, 1, 1, 0.0))
	gr.add_point(0.12, Color(1, 1, 1, 0.55))
	gr.set_color(1, Color(1, 1, 1, 0.0))
	var tex := GradientTexture2D.new()
	var g2 := Gradient.new()
	g2.set_color(0, Color(1, 1, 1, 1)); g2.set_color(1, Color(1, 1, 1, 0))
	tex.gradient = g2; tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5); tex.fill_to = Vector2(0.5, 0.0); tex.width = 32; tex.height = 32
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = tex
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	q.material = mat
	for i in 2:
		var p := CPUParticles3D.new()
		p.mesh = q
		p.amount = 40
		p.lifetime = 2.2
		p.local_coords = false
		p.emitting = false
		p.direction = Vector3(0, 0.6, -1)
		p.spread = 35.0
		p.initial_velocity_min = 0.5
		p.initial_velocity_max = 2.0
		p.gravity = Vector3(0, 0.25, 0)
		p.damping_min = 0.6
		p.damping_max = 1.2
		p.scale_amount_min = 0.8
		p.scale_amount_max = 1.6
		var sc := Curve.new()
		sc.add_point(Vector2(0, 0.4)); sc.add_point(Vector2(1, 2.6))
		p.scale_amount_curve = sc
		p.color_ramp = gr
		p.color = Color(0.72, 0.64, 0.52)
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 0.25
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(p)
		emitters.append(p)

func _on_road(w: VehicleWheel3D) -> bool:
	var b := w.get_contact_body()
	if b == null:
		return true
	var n := b as Node
	while n:
		if n == roads:
			return true
		n = n.get_parent()
	return false

func _process(_dt: float) -> void:
	if car == null or car.wheels.size() < 4:
		return
	var kmh: float = car.kmh()
	for i in 2:
		var w: VehicleWheel3D = car.wheels[2 + i]
		var p: CPUParticles3D = emitters[i]
		var go: bool = not car.blown and w.is_in_contact() and kmh > 12.0 and (wet > 0.3 or not _on_road(w))
		if wet > 0.3 and go and not _on_road(w):
			go = false                                     # terre mouillée : pas de poussière
		p.emitting = go
		if go:
			p.global_position = w.global_position - Vector3(0, 0.25, 0) - car.global_basis.z * 0.3
			var back := -car.global_basis.z
			p.direction = (back + Vector3(0, 0.5, 0)).normalized()
			p.initial_velocity_max = 1.0 + kmh / 25.0
			p.color = Color(0.72, 0.64, 0.52, 1.0) if wet <= 0.3 else Color(0.8, 0.84, 0.88, 0.8)
			p.speed_scale = 1.0
