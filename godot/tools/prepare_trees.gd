## Prépare les modèles de végétation (import/trees/<nom>/scene.gltf, Sketchfab CC-BY) pour le jeu :
## un seul maillage par modèle (une surface par matériau), base du tronc à l'origine, hauteur 1 m (mis à l'échelle de
## l'arbre réel à l'affichage), textures réduites à 1024 px, feuillage en transparence découpée.
## Sortie : res://assets/veg/<nom>.glb (+ meta.json : rayon relatif de la couronne, part du tronc).
## godot --headless --path . --script res://tools/prepare_trees.gd
extends SceneTree

const NAMES := ["chene", "feuillu", "chene2", "bouleau", "peuplier", "epicea", "sapin", "pin", "mais"]

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute("res://assets/veg")
	var meta := {}
	for n in NAMES:
		meta[n] = _prepare(n)
	var f := FileAccess.open("res://assets/veg/meta.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, " "))
	f.close()
	quit()

func _xf(node: Node, root: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n := node
	while n != null and n != root:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t

func _small(tex: Texture2D, size: int) -> Texture2D:
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null:
		return null
	if img.is_compressed():
		img.decompress()
	var s := float(size) / maxf(img.get_width(), img.get_height())
	if s < 1.0:
		img.resize(int(img.get_width() * s), int(img.get_height() * s), Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)

func _material(src: Material, leaves: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var s := src as BaseMaterial3D
	if s:
		m.albedo_color = s.albedo_color
		m.albedo_texture = _small(s.albedo_texture, 1024)
		if s.normal_enabled and s.normal_texture:
			m.normal_enabled = true
			m.normal_texture = _small(s.normal_texture, 512)
	m.roughness = 0.85
	m.metallic = 0.0
	if leaves:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.45
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

func _is_leaves(src: Material) -> bool:
	var s := src as BaseMaterial3D
	if s == null:
		return false
	if s.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		return true
	var tex := s.albedo_texture
	if tex and tex.get_image():
		var img := tex.get_image()
		if img.is_compressed():
			img.decompress()
		return img.detect_alpha() != Image.ALPHA_NONE
	return false

func _prepare(n: String) -> Dictionary:
	var sc: Node = load("res://import/trees/%s/scene.gltf" % n).instantiate()
	# 1) fusion de tous les maillages (transformations des nœuds appliquées), par matériau ; seuls positions,
	#    normales, UV et indices sont gardés (formats de sommets hétérogènes selon les modèles)
	var arrs := {}
	var mats := {}
	for mi in sc.find_children("*", "MeshInstance3D", true, false):
		var xf := _xf(mi, sc)
		var mesh: Mesh = mi.mesh
		for s in mesh.get_surface_count():
			var mat: Material = mi.get_surface_override_material(s)
			if mat == null:
				mat = mesh.surface_get_material(s)
			var key := str(mat.get_instance_id()) if mat else "none"
			var src: Array = mesh.surface_get_arrays(s)
			var vs: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
			if vs.is_empty():
				continue
			var ns = src[Mesh.ARRAY_NORMAL]
			var uv = src[Mesh.ARRAY_TEX_UV]
			var ix = src[Mesh.ARRAY_INDEX]
			if not arrs.has(key):
				arrs[key] = [PackedVector3Array(), PackedVector3Array(), PackedVector2Array(), PackedInt32Array()]
				mats[key] = mat
			var d: Array = arrs[key]
			var off: int = d[0].size()
			var basis := xf.basis.inverse().transposed()
			for i in vs.size():
				d[0].append(xf * vs[i])
				d[1].append((basis * ns[i]).normalized() if ns != null and ns.size() == vs.size() else Vector3.UP)
				d[2].append(uv[i] if uv != null and uv.size() == vs.size() else Vector2.ZERO)
			if ix != null and ix.size() > 0:
				for k in ix:
					d[3].append(k + off)
			else:
				for k in vs.size():
					d[3].append(k + off)
	for key in arrs:
		var d: Array = arrs[key]
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = d[0]; a[Mesh.ARRAY_NORMAL] = d[1]; a[Mesh.ARRAY_TEX_UV] = d[2]; a[Mesh.ARRAY_INDEX] = d[3]
		arrs[key] = a
	# 2) emprise : hauteur totale, centre du tronc (sommets des 4 % inférieurs)
	var all := PackedVector3Array()
	for key in arrs:
		all.append_array(arrs[key][Mesh.ARRAY_VERTEX])
	var ymin := INF
	var ymax := -INF
	for v in all:
		ymin = minf(ymin, v.y); ymax = maxf(ymax, v.y)
	var h := ymax - ymin
	var base := Vector3.ZERO
	var nb := 0
	for v in all:
		if v.y < ymin + h * 0.04:
			base += v; nb += 1
	base = base / maxf(nb, 1)
	base.y = ymin
	var rmax := 0.0
	var trunk_top := 0.0
	for v in all:
		rmax = maxf(rmax, Vector2(v.x - base.x, v.z - base.z).length())
	# 3) maillage normalisé (hauteur 1)
	var am := ArrayMesh.new()
	var leaves_part := 0
	for key in arrs:
		var a: Array = arrs[key]
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		for i in vs.size():
			vs[i] = (vs[i] - base) / h
		a[Mesh.ARRAY_VERTEX] = vs
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		var leaves := _is_leaves(mats[key])
		if leaves:
			leaves_part += 1
		am.surface_set_material(am.get_surface_count() - 1, _material(mats[key], leaves))
	var mi := MeshInstance3D.new()
	mi.name = "tree"
	mi.mesh = am
	var root := Node3D.new()
	root.name = n
	root.add_child(mi)
	mi.owner = root
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	doc.append_from_scene(root, state)
	doc.write_to_filesystem(state, "res://assets/veg/%s.glb" % n)
	var tris := 0
	for s in am.get_surface_count():
		tris += am.surface_get_array_index_len(s) / 3
	print(n, " : ", tris, " triangles, hauteur d'origine ", snappedf(h, 0.01), ", couronne ", snappedf(rmax / h, 0.01), " h, ",
		am.get_surface_count(), " surfaces (", leaves_part, " feuillage)")
	return {"crown": rmax / h, "tris": tris}
