## Rapport de plantage : le jeu note toutes les 5 s où il en est (position, route, images/s, mémoire) dans
## user://etat.txt (fichier refermé à chaque écriture : rien ne se perd) et dans son journal. Le drapeau vaut « jeu »
## pendant la partie, « pause » en arrière-plan : s'il vaut encore « jeu » au démarrage suivant, la partie s'est
## arrêtée brutalement (plantage, ou blocage fermé par Android) et un bandeau propose de copier le rapport.
extends Node

const FLAG := "user://en_cours.flag"
const STATE := "user://etat.txt"
var _lines := PackedStringArray()
var car: Node3D
var hud: CanvasLayer
var names
var _t := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if FileAccess.file_exists(FLAG) and FileAccess.get_file_as_string(FLAG).begins_with("jeu"):
		var st := FileAccess.get_file_as_string(STATE) if FileAccess.file_exists(STATE) else "(pas d'état enregistré)"
		_banner("--- dernier état ---\n%s\n--- journal ---\n%s" % [st, _previous_log()])
	_set_flag("jeu")

func _set_flag(v: String) -> void:
	var f := FileAccess.open(FLAG, FileAccess.WRITE)
	if f:
		f.store_string(v + " " + Time.get_datetime_string_from_system())
		f.close()

func _notification(what: int) -> void:
	# arrière-plan ou fermeture normale : pas un plantage (un jeu bloqué ne reçoit plus ces notifications)
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_PREDELETE, NOTIFICATION_EXIT_TREE,
			NOTIFICATION_WM_GO_BACK_REQUEST]:
		_set_flag("pause")
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		_set_flag("jeu")

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

var _air := false
var _air_t := 0.0

func _process(dt: float) -> void:
	if car == null:
		return
	# sauts : l'état est écrit au décollage (si le jeu plante à l'atterrissage, on le saura)
	var air: bool = car.wheels.all(func(w): return not w.is_in_contact())
	_air_t = _air_t + dt if air else 0.0
	if _air_t > 0.25 and not _air:
		_air = true
		_t = 0.0
	elif not air and _air:
		_air = false
		_t = 0.0
	_t -= dt
	if _t > 0:
		return
	_t = 5.0
	var p := car.global_position
	var line := ("[saut] " if _air else "[état] ") + "%s pos=(%d, %d, %d) %s · %d km/h · %d img/s · mémoire %d Mo · vidéo %d Mo · objets %d" % [
		Time.get_time_string_from_system(), p.x, p.y, p.z, names.road_at(p) if names else "", int(car.kmh()),
		Engine.get_frames_per_second(), Performance.get_monitor(Performance.MEMORY_STATIC) / 1e6,
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1e6, Performance.get_monitor(Performance.OBJECT_COUNT)]
	print(line)
	_lines.append(line)
	if _lines.size() > 40:
		_lines = _lines.slice(_lines.size() - 40)
	var f := FileAccess.open(STATE, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_lines))
		f.close()
