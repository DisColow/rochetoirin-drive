## Mémoire vidéo d'une texture (v6.70, #122) : écart du compteur de Godot avant/après chargement.
## xvfb-run godot --path . --script res://tools/mesure_texture.gd -- res://chemin1 res://chemin2 …
extends SceneTree

func _initialize() -> void:
	var garde := []
	for p in OS.get_cmdline_user_args():
		await process_frame
		var avant := Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)
		var t: Texture2D = load(p)
		garde.append(t)
		await process_frame
		await process_frame
		var apres := Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)
		print("[texture] %-60s %4d × %-4d %6.1f Mo" % [p.get_file(), t.get_width(), t.get_height(), (apres - avant) / 1e6])
	quit()
