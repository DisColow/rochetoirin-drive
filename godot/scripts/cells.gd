## Objets posés par lots (MultiMesh) découpés en cases de 64 m : la portée d'affichage s'applique case par case, au
## lieu de faire apparaître ou disparaître d'un bloc toute une tuile de 256 m ; et les matériaux effacent l'objet par
## tramage avant la portée (fade_far, env.gdshaderinc), si bien que la case est retirée une fois invisible : plus rien
## ne surgit ni ne s'éteint d'un coup.
extends RefCounted

const CELL := 64.0
const Env := preload("res://scripts/env.gd")
static var _meshes := {}      # "modèle_portée" -> copie du modèle aux matériaux fondus
static var _mats := {}        # "matériau_portée" -> matériau fondu

## Copie du modèle dont les matériaux s'effacent progressivement jusqu'à `far` (m).
static func faded(mesh: Mesh, far: float) -> Mesh:
	var key := "%d_%d" % [mesh.get_instance_id(), int(far)]
	if _meshes.has(key):
		return _meshes[key]
	var m := mesh.duplicate() as Mesh
	for s in m.get_surface_count():
		var mt := mesh.surface_get_material(s)
		if mt:
			m.surface_set_material(s, material(mt, far))
	_meshes[key] = m
	return m

## Variante d'un matériau qui s'efface jusqu'à `far` : copie d'un ShaderMaterial (shader à env_fade_keep), matériau simple
## pour un StandardMaterial3D opaque ou découpé ; sinon le matériau tel quel.
static func material(mt: Material, far: float) -> Material:
	var key := "%d_%d" % [mt.get_instance_id(), int(far)]
	if _mats.has(key):
		return _mats[key]
	var out: ShaderMaterial = null
	if mt is ShaderMaterial and (mt as ShaderMaterial).shader.code.contains("env_fade_keep"):
		out = mt.duplicate()
		Env.add(out)
	elif mt is StandardMaterial3D:
		var sm := mt as StandardMaterial3D
		var scissor := sm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		if (sm.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED or scissor) and not sm.emission_enabled:
			out = ShaderMaterial.new()
			out.shader = preload("res://scripts/simple_2f.gdshader") if sm.cull_mode == BaseMaterial3D.CULL_DISABLED else preload("res://scripts/simple.gdshader")
			out.set_shader_parameter("albedo", Color(sm.albedo_color.r, sm.albedo_color.g, sm.albedo_color.b))
			out.set_shader_parameter("rough", sm.roughness)
			out.set_shader_parameter("metal", sm.metallic)
			if sm.albedo_texture:
				out.set_shader_parameter("textured", true)
				out.set_shader_parameter("tex", sm.albedo_texture)
			if scissor:
				out.set_shader_parameter("scissor", sm.alpha_scissor_threshold)
			Env.add(out)
	if out == null:
		_mats[key] = mt
		return mt
	Env.fade(out, far)
	_mats[key] = out
	return out

## Pose les objets `items` ([Transform3D, Color de données d'instance ou rien]) sous `parent`, une MultiMesh par case,
## effacés jusqu'à `far` (m). Renvoie les MultiMeshInstance3D créées.
static func add(parent: Node, mesh: Mesh, items: Array, far: float, shadow: bool, fade := true) -> Array:
	var fm := faded(mesh, far) if fade else mesh
	var custom := false
	var by := {}
	var sc := 1.0
	for it in items:
		var xf: Transform3D = it[0]
		var k := Vector2i(floori(xf.origin.x / CELL), floori(xf.origin.z / CELL))
		if not by.has(k):
			by[k] = []
		by[k].append(it)
		custom = custom or it.size() > 1
		sc = maxf(sc, maxf(xf.basis.x.length(), maxf(xf.basis.y.length(), xf.basis.z.length())))
	# la case n'est retirée qu'au-delà de la distance où tout ce qu'elle contient s'est effacé
	var reach := far + CELL * 0.75 + mesh.get_aabb().size.length() * 0.5 * sc + (5.0 if fade else 0.0)
	var out := []
	for k in by:
		var l: Array = by[k]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = custom
		mm.mesh = fm
		mm.instance_count = l.size()
		for i in l.size():
			mm.set_instance_transform(i, l[i][0])
			if custom:
				mm.set_instance_custom_data(i, l[i][1] if l[i].size() > 1 else Color(0, 0, 0, 0))
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = reach if fade else far
		mi.visibility_range_end_margin = 10.0
		parent.add_child(mi)
		out.append(mi)
	return out
