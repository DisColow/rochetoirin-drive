## Mémoire vidéo du ciel de midi (v6.70, #122) : ancien panorama contre ciel en deux images, radiance comprise.
## xvfb-run godot --path . --script res://tools/mesure_ciel.gd -- ancien|nouveau
extends SceneTree

func _initialize() -> void:
	var cam := Camera3D.new()
	root.add_child(cam)
	for i in 10:
		await process_frame
	var avant := Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)
	var sky := Sky.new()
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	if OS.get_cmdline_user_args().has("ancien"):
		var m := PanoramaSkyMaterial.new()
		m.panorama = load("res://.godot/imported/sky.hdr-58b613cd1aeba3f6b838d7e6edc4a86f.ctex")
		sky.sky_material = m
	else:
		var m := ShaderMaterial.new()
		m.shader = load("res://scripts/ciel_midi.gdshader")
		m.set_shader_parameter("haut", load("res://assets/ciel/midi_haut.hdr"))
		m.set_shader_parameter("bas", load("res://assets/ciel/midi_bas.hdr"))
		sky.sky_material = m
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	for i in 30:
		await process_frame
	print("[ciel] %s : %.1f Mo de textures" % [OS.get_cmdline_user_args()[0], (Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) - avant) / 1e6])
	quit()
