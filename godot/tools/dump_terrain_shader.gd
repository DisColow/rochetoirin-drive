## Outil : écrit le code du shader généré par Terrain3D (mêmes réglages que main.gd) dans
## user://terrain_genere.gdshader, base du shader remplaçant (scripts/terrain.gdshader).
extends SceneTree

func _init() -> void:
	var terrain := Terrain3D.new()
	terrain.change_region_size(512)
	terrain.vertex_spacing = 2.0
	terrain.data_directory = "res://terrain"
	terrain.assets = load("res://assets/terrain_assets.tres")
	var m := terrain.material
	m.world_background = Terrain3DMaterial.NONE
	m.show_checkered = false
	root.add_child.call_deferred(terrain)
	await process_frame
	await process_frame
	var rid: RID = m.get_shader_rid()
	var code := RenderingServer.shader_get_code(rid)
	var f := FileAccess.open("user://terrain_genere.gdshader", FileAccess.WRITE)
	f.store_string(code)
	f.close()
	print("shader terrain : ", code.length(), " caractères")
	quit()
