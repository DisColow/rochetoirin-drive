## Rapport de plantage : le jeu note toutes les 10 s où il en est (position, route, images/s, mémoire) dans son
## journal. S'il s'est arrêté brutalement (drapeau « en cours » resté présent), un bandeau propose au démarrage suivant
## de copier le journal de la partie précédente, à coller dans un message.
extends Node

const FLAG := "user://en_cours.flag"
var car: Node3D
var hud: CanvasLayer
var names
var _t := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if FileAccess.file_exists(FLAG):
		var prev := _previous_log()
		if prev != "":
			_banner(prev)
	_set_flag(true)

func _set_flag(on: bool) -> void:
	if on:
		var f := FileAccess.open(FLAG, FileAccess.WRITE)
		if f:
			f.store_string(Time.get_datetime_string_from_system())
	elif FileAccess.file_exists(FLAG):
		DirAccess.remove_absolute(FLAG)

func _notification(what: int) -> void:
	# mise en arrière-plan ou fermeture normale : pas un plantage
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		_set_flag(false)
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		_set_flag(true)

func _previous_log() -> String:
	var dir := "user://logs"
	if not DirAccess.dir_exists_absolute(dir):
		return ""
	var files := Array(DirAccess.get_files_at(dir)).filter(func(f): return f.begins_with("godot") and f != "godot.log")
	if files.is_empty():
		return ""
	files.sort()
	var txt := FileAccess.get_file_as_string(dir + "/" + files[-1])
	var lines := txt.split("\n")
	return "\n".join(lines.slice(max(0, lines.size() - 150)))

func _banner(text: String) -> void:
	var b := Button.new()
	b.text = "La partie précédente s'est arrêtée brutalement. Toucher ici pour copier le rapport."
	b.add_theme_font_size_override("font_size", 24)
	b.position = Vector2(400, 24)
	b.size = Vector2(860, 64)
	b.pressed.connect(func():
		DisplayServer.clipboard_set("Rapport Rochetoirin Simulator v%s\n%s" % [ProjectSettings.get_setting("application/config/version", "?"), text])
		b.text = "Rapport copié : collez-le dans votre message."
		get_tree().create_timer(4.0).timeout.connect(b.queue_free))
	hud.add_child(b)
	get_tree().create_timer(25.0).timeout.connect(func(): if is_instance_valid(b): b.queue_free())

func _process(dt: float) -> void:
	_t -= dt
	if _t > 0 or car == null:
		return
	_t = 10.0
	var p := car.global_position
	print("[état] %s pos=(%d, %d, %d) %s · %d km/h · %d img/s · mémoire %d Mo · vidéo %d Mo · objets %d" % [
		Time.get_time_string_from_system(), p.x, p.y, p.z, names.road_at(p) if names else "", int(car.kmh()),
		Engine.get_frames_per_second(), Performance.get_monitor(Performance.MEMORY_STATIC) / 1e6,
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1e6, Performance.get_monitor(Performance.OBJECT_COUNT)])
