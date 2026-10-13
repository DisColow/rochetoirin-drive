## Bâtiments refaits sur mesure d'après Street View (world/sur_mesure.json, v6.17 : la boulangerie de Rochetoirin,
## pipeline/boulangerie/) : un modèle par bâtiment, façades peintes dans un atlas (sur_mesure.gdshader), posé à sa
## place ; le bâtiment BD TOPO et la devanture générique qu'il remplace ne sont plus générés. Collisions : boîtes
## (BoxShape3D) décrites dans sur_mesure.json (« boites »).
extends Node3D

const Env := preload("res://scripts/env.gd")

func _ready() -> void:
	name = "SurMesure"
	if not FileAccess.file_exists("res://world/sur_mesure.json"):
		return
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://world/sur_mesure.json"))
	for k in d:
		var e: Dictionary = d[k]
		var sc := load(e.glb) as PackedScene
		if sc == null:
			continue
		var n := sc.instantiate()
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://scripts/sur_mesure.gdshader")
		mat.set_shader_parameter("atlas", load(e.atlas))
		Env.add(mat)
		var corps := StaticBody3D.new()
		corps.name = k + "_col"
		for mi in n.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if String(m.name).begins_with("col"):
				m.queue_free()                 # (ancien maillage de collision : remplacé par les boîtes)
			else:
				m.material_override = mat
				m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		# collisions : boîtes seulement (v6.18, BoxShape3D), [cx, cy, cz, demi-tailles, lacet] relatifs à la pose
		for b in e.get("boites", []):
			var cs := CollisionShape3D.new()
			var sh := BoxShape3D.new()
			sh.size = Vector3(b[3], b[4], b[5]) * 2.0
			cs.shape = sh
			cs.transform = Transform3D(Basis(Vector3.UP, b[6]), Vector3(b[0], b[1], b[2]))
			corps.add_child(cs)
		n.name = k
		var p: Array = e.pos
		n.position = Vector3(p[0], p[1], p[2])
		corps.position = n.position
		add_child(n)
		add_child(corps)
