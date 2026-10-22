## #124 étape 2 : contrôle de la fusion des modèles des voitures garées (props.gd _fusionner) : surfaces, sommets,
## triangles et niveaux de détail avant / après. godot --headless --script res://tools/essai_fusion_props.gd
extends SceneTree

func _init() -> void:
	var props = load("res://scripts/props.gd").new()
	props._ready()
	for t in props.MODELS:
		var sc: PackedScene = load("res://assets/props/%s.glb" % props.MODELS[t])
		var m0: Mesh = (sc.instantiate().find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh
		var m1: Mesh = props.meshes[t]
		var info := func(m: Mesh) -> String:
			var tri := 0
			for s in m.get_surface_count():
				tri += (m.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			return "%d surfaces, %d triangles" % [m.get_surface_count(), tri]
		print("[fusion] %s : avant %s" % [props.MODELS[t], info.call(m0)])
		print("[fusion] %s : après %s" % [props.MODELS[t], info.call(m1)])
	# niveaux de détail : refaits sur la voiture 1 fusionnée, comme dans props.gd
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, (props.meshes[1] as Mesh).surface_get_arrays(0), [], {}, null)
	im.generate_lods(25.0, 60.0, [])
	var tl := []
	for l in im.get_surface_lod_count(0):
		tl.append("%.3f:%d" % [im.get_surface_lod_size(0, l), im.get_surface_lod_indices(0, l).size() / 3])
	print("[fusion] car1 : niveaux de détail ", ", ".join(tl))
	props.free()
	quit()
