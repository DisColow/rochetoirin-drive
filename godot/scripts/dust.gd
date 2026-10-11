## Effets des roues selon ce qu'il y a dessous (comme dans les grands jeux de rallye) : dans l'herbe, brins et mottes
## arrachés qui volent et retombent ; sur les chemins de terre, nuage de poussière et mottes ; sur le gravier,
## cailloux projetés et poussière claire ; sur route mouillée, gerbes d'eau ; sur l'asphalte, fumée de pneus quand
## ça glisse (dérapage, patinage, freinage bloqué). Débris en petits carrés unis, façon pixel art ; d'autant plus
## qu'on roule vite ou que les roues avant (motrices) patinent. Surface : meta « surface » des routes (roads.gd),
## sinon terrain = herbe.
extends Node3D

var car: VehicleBody3D
var roads: Node
var wet := 0.0
var _fx := []                     # par roue : {type: CPUParticles3D}

func _ready() -> void:
	var soft := _soft_mesh()
	var bit := _bit_mesh()
	for i in 4:
		var d := {}
		# brins d'herbe (et quelques mottes de terre)
		d.herbe = _emitter(bit, 28, 0.75, Vector3(0, -9.0, 0), Vector2(0.05, 0.10), _ramp([
			Color(0.24, 0.42, 0.11), Color(0.34, 0.52, 0.14), Color(0.46, 0.6, 0.2), Color(0.3, 0.48, 0.12),
			Color(0.36, 0.27, 0.16)]))
		# mottes et cailloux de terre
		d.mottes = _emitter(bit, 14, 0.7, Vector3(0, -9.0, 0), Vector2(0.06, 0.12), _ramp([
			Color(0.42, 0.32, 0.2), Color(0.5, 0.4, 0.26), Color(0.33, 0.25, 0.16)]))
		# cailloux du gravier
		d.cailloux = _emitter(bit, 16, 0.55, Vector3(0, -9.0, 0), Vector2(0.04, 0.07), _ramp([
			Color(0.62, 0.6, 0.56), Color(0.48, 0.47, 0.45), Color(0.72, 0.7, 0.66)]))
		# nuage de poussière (terre, gravier)
		d.poussiere = _emitter(soft, 32, 2.2, Vector3(0, 0.25, 0), Vector2(0.8, 1.6), null)
		d.poussiere.color = Color(0.72, 0.64, 0.52, 0.45)
		# gerbes d'eau (route mouillée)
		d.eau = _emitter(soft, 30, 0.9, Vector3(0, -3.0, 0), Vector2(0.4, 0.9), null)
		d.eau.color = Color(0.82, 0.86, 0.9, 0.4)
		# fumée de pneus (dérapage sur l'asphalte)
		d.fumee = _emitter(soft, 36, 2.6, Vector3(0, 0.4, 0), Vector2(1.0, 2.0), null)
		d.fumee.color = Color(0.86, 0.86, 0.86, 0.45)
		_fx.append(d)

## Nuages (poussière, eau, fumée) : boules à facettes translucides, sans panneau face à la caméra (les modes
## « billboard » ignorent la position et la taille de chaque particule en Compatibility).
func _soft_mesh() -> SphereMesh:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH       # tramé : chemin opaque, rendu pixel art
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	var q := SphereMesh.new(); q.radius = 0.5; q.height = 1.0; q.radial_segments = 8; q.rings = 4
	q.material = mat
	return q

## Débris : petit cube uni qui tournoie (des carrés à l'écran, façon pixel art), éclairé comme le décor.
func _bit_mesh() -> BoxMesh:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	mat.vertex_color_use_as_albedo = true
	var q := BoxMesh.new(); q.size = Vector3(1, 1, 1); q.material = mat
	return q

func _ramp(cols: Array) -> Gradient:
	var g := Gradient.new()
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	g.offsets = PackedFloat32Array(range(cols.size()).map(func(k): return float(k) / cols.size()))
	g.colors = PackedColorArray(cols)
	return g

func _emitter(mesh: Mesh, amount: int, life: float, grav: Vector3, size: Vector2, ramp: Gradient) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.mesh = mesh
	p.amount = amount
	p.lifetime = life
	p.local_coords = false
	p.emitting = false
	p.spread = 28.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 4.0
	p.gravity = grav
	p.scale_amount_min = size.x
	p.scale_amount_max = size.y
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.12
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if ramp:
		p.color_initial_ramp = ramp
		p.angle_min = 0.0; p.angle_max = 90.0
		p.angular_velocity_min = -360.0; p.angular_velocity_max = 360.0
	else:
		p.damping_min = 0.6; p.damping_max = 1.4
		p.angle_min = 0.0; p.angle_max = 360.0
		# pas de dégradé de couleur (il écrase la teinte en Compatibility) : la bouffée gonfle puis se résorbe
		var sc := Curve.new()
		sc.add_point(Vector2(0, 0.3)); sc.add_point(Vector2(0.6, 2.2)); sc.add_point(Vector2(1, 0.0))
		p.scale_amount_curve = sc
	add_child(p)
	return p

## Surface sous la roue : "asphalte", "terre" (chemins), "herbe" (terrain hors route).
func _surface(w: VehicleWheel3D) -> String:
	var b := w.get_contact_body()
	if b == null:
		return "herbe"
	if b.has_meta("surface"):
		return "terre" if String(b.get_meta("surface")) == "dirt" else "asphalte"
	var n := b as Node
	while n:
		if n == roads:
			return "asphalte"
		n = n.get_parent()
	return "herbe"

func _process(_dt: float) -> void:
	if car == null or car.wheels.size() < 4:
		return
	var kmh: float = car.kmh()
	var back := -car.global_basis.z * (1.0 if car.forward_speed() >= 0.0 else -1.0)
	var lat: float = absf(car.linear_velocity.dot(car.global_basis.x))
	for i in 4:
		var w: VehicleWheel3D = car.wheels[i]
		var d: Dictionary = _fx[i]
		var on := {}
		var amount := 0.0
		if not car.blown and w.is_in_contact():
			var s := _surface(w)
			var slip := 1.0 - w.get_skidinfo()             # 0 adhérence … 1 glisse
			var spin: float = slip if w.use_as_traction else 0.0
			amount = clampf(kmh / 50.0 + spin * 1.2 + lat / 8.0, 0.0, 1.0)
			if kmh > 4.0 or spin > 0.3:
				match s:
					"herbe":
						on.herbe = true
						if amount > 0.5:
							on.mottes = true
					"terre":
						on.mottes = true
						if wet <= 0.3:
							on.poussiere = true
					"asphalte":
						if wet > 0.3 and kmh > 15.0:
							on.eau = true
						if slip > 0.35 or lat > 4.0:
							on.fumee = true
				if s == "terre" and slip > 0.2:
					on.cailloux = true
		var pos := w.global_position - car.global_basis.y * (w.wheel_radius * 0.85) + back * 0.25
		for k in d:
			var p: CPUParticles3D = d[k]
			var go: bool = on.has(k)
			p.emitting = go
			if go:
				p.global_position = pos
				p.direction = (back + Vector3(0, 0.9 if k in ["herbe", "mottes", "cailloux"] else 0.5, 0)).normalized()
				p.initial_velocity_max = 1.5 + kmh / 18.0 * (0.5 + amount)
