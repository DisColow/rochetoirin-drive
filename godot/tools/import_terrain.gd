## Import headless des régions préparées par pipeline/prepare_terrain.py dans Terrain3D (res://terrain/*.res)
## et création de la liste de textures (res://assets/terrain_assets.tres).
## godot --headless --path godot --script res://tools/import_terrain.gd
extends SceneTree

const TEX := ["gazon", "prairie", "sous_bois", "roche", "chaume", "accotement"]
# échelle des textures : nombre de répétitions par mètre (env. 3 m par motif, roche plus grande)
const UV := [0.30, 0.25, 0.22, 0.10, 0.18, 0.35]

func _initialize() -> void:
	var t := Terrain3D.new()
	root.add_child(t)
	await process_frame
	t.change_region_size(512)
	t.vertex_spacing = 2.0
	var idx: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://import/terrain/index.json"))
	var n := 0
	for r in idx["regions"]:
		var i := int(r[0]); var j := int(r[1])
		var base := "res://import/terrain/r_%d_%d" % [i, j]
		var h := Image.create_from_data(512, 512, false, Image.FORMAT_RF, FileAccess.get_file_as_bytes(base + ".h.raw"))
		var c := Image.create_from_data(512, 512, false, Image.FORMAT_RF, FileAccess.get_file_as_bytes(base + ".c.raw"))
		var col := Image.load_from_file(ProjectSettings.globalize_path(base + ".color.png"))
		col.convert(Image.FORMAT_RGBA8)
		t.data.import_images([h, c, col], Vector3(i * 1024.0, 0.0, j * 1024.0), 0.0, 1.0)
		n += 1
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://terrain"))
	t.data.save_directory("res://terrain")
	print("régions importées : ", n, " ; hauteurs ", t.data.get_height_range())
	# textures
	var assets := Terrain3DAssets.new()
	for k in TEX.size():
		var ta := Terrain3DTextureAsset.new()
		ta.name = TEX[k]
		ta.albedo_texture = load("res://assets/terrain_tex/%d_albedo_height.png" % k)
		ta.normal_texture = load("res://assets/terrain_tex/%d_normal_rough.png" % k)
		ta.uv_scale = UV[k]
		ta.detiling_rotation = 0.25
		assets.set_texture(k, ta)
	ResourceSaver.save(assets, "res://assets/terrain_assets.tres")
	print("textures : ", TEX.size())
	quit()
