## Mémoire vidéo d'une texture ou d'une scène (.glb : ses textures) (v6.70, #122) : écart du compteur de Godot avant/après chargement.
## xvfb-run godot --path . --script res://tools/mesure_texture.gd -- res://chemin1 res://chemin2 …
extends SceneTree

func _initialize() -> void:
	var garde := []
	for p in OS.get_cmdline_user_args():
		await process_frame
		var avant := Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)
		var r: Resource = load(p)
		garde.append(r)
		await process_frame
		await process_frame
		var apres := Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)
		var dim := "%4d × %-4d" % [r.get_width(), r.get_height()] if r is Texture2D else "(scène)    "
		print("[texture] %-60s %s %6.1f Mo" % [p.trim_prefix("res://"), dim, (apres - avant) / 1e6])
	quit()
