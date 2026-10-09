## Autoradio de l'Espace : six stations à thème (musiques de Kevin MacLeod, incompetech.com, CC BY 4.0 ;
## assets/radio/radio.json, pipeline/fetch_radio.py). Comme dans les grands jeux en monde ouvert, chaque station
## « émet » en continu, même quand on ne l'écoute pas : on tombe en cours de morceau, et l'ordre des morceaux change à
## chaque tour du programme. Grésillement en changeant de station. Son d'autoradio (haut-parleurs de portière : bande
## étroite) dans l'habitacle ; en vue extérieure (fenêtre ouverte), plus lointain et plus sourd.
## Commandes : bouton ♪ (ou touche N) : station suivante, puis arrêt ; l'écran de l'autoradio du cockpit affiche la
## fréquence.
extends Node

var main: Node
var hud: CanvasLayer
var cam_rig: Node
var stations := []
var station := -1                 # -1 : radio éteinte
var title := ""
var _player: AudioStreamPlayer
var _noise: AudioStreamPlayer
var _bus := -1
var _lp: AudioEffectLowPassFilter
var _hp: AudioEffectHighPassFilter
var _cockpit := 0.0
var _cur := -1                     # indice du morceau en cours dans le programme de la station
var _lap := -1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not FileAccess.file_exists("res://assets/radio/radio.json"):
		set_process(false)
		return
	stations = JSON.parse_string(FileAccess.get_file_as_string("res://assets/radio/radio.json")).stations
	_bus = AudioServer.get_bus_index("Radio")
	if _bus < 0:
		AudioServer.add_bus()
		_bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(_bus, "Radio")
		AudioServer.set_bus_send(_bus, "Master")
		_hp = AudioEffectHighPassFilter.new(); _hp.cutoff_hz = 170.0
		_lp = AudioEffectLowPassFilter.new(); _lp.cutoff_hz = 7000.0
		AudioServer.add_bus_effect(_bus, _hp)
		AudioServer.add_bus_effect(_bus, _lp)
	else:
		_hp = AudioServer.get_bus_effect(_bus, 0)
		_lp = AudioServer.get_bus_effect(_bus, 1)
	_player = AudioStreamPlayer.new()
	_player.bus = "Radio"
	_player.finished.connect(_tune)
	add_child(_player)
	_noise = AudioStreamPlayer.new()
	_noise.bus = "Radio"
	if ResourceLoader.exists("res://assets/sfx/radio_gresil.ogg"):
		_noise.stream = load("res://assets/sfx/radio_gresil.ogg")
	add_child(_noise)
	if not InputMap.has_action("radio"):
		InputMap.add_action("radio")
		var k := InputEventKey.new(); k.physical_keycode = KEY_N
		InputMap.action_add_event("radio", k)
	var cfg := ConfigFile.new()
	if cfg.load("user://reglages.cfg") == OK:
		station = int(cfg.get_value("audio", "radio", -1))
	if station >= stations.size():
		station = -1
	if OS.get_cmdline_user_args().has("--radio"):
		station = 1                                         # essais
	if station >= 0:
		_tune()

func _process(dt: float) -> void:
	if Input.is_action_just_pressed("radio"):
		next()
	var inside := 1.0 if (cam_rig and cam_rig.mode == 1) else 0.0
	_cockpit = move_toward(_cockpit, inside, dt * 3.0)
	if _lp:
		_lp.cutoff_hz = lerpf(2600.0, 7000.0, _cockpit)
	AudioServer.set_bus_volume_db(_bus, lerpf(-9.0, -1.0, _cockpit))
	# en pause (carte, menus) la radio continue, un peu plus bas
	_player.volume_db = -6.0 if get_tree().paused else 0.0

## Station suivante ; après la dernière, arrêt.
func next() -> void:
	station += 1
	if station >= stations.size():
		station = -1
	if _noise.stream:
		_noise.play()
	_cur = -1; _lap = -1
	if station < 0:
		_player.stop()
		title = ""
		if hud:
			hud.toast("♪ Radio éteinte", 1.6)
	else:
		_tune()
		if hud:
			var s = stations[station]
			hud.toast("♪ %s  %s FM\n%s" % [s.nom, s.freq, title], 3.0)
	var cfg := ConfigFile.new()
	cfg.load("user://reglages.cfg")
	cfg.set_value("audio", "radio", station)
	cfg.save("user://reglages.cfg")

## Programme de la station : ordre des morceaux tiré au sort pour chaque tour (graine : station, tour).
func _order(s: int, lap: int) -> Array:
	var n: int = stations[s].morceaux.size()
	var idx := range(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(s, lap))
	for i in range(n - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = idx[i]; idx[i] = idx[j]; idx[j] = t
	return idx

## Cale le lecteur sur ce que la station émet en ce moment (horloge réelle).
func _tune() -> void:
	if station < 0 or station >= stations.size():
		return
	var st = stations[station]
	var total := 0.0
	for m in st.morceaux:
		total += float(m.duree)
	var t := fmod(Time.get_unix_time_from_system() + station * 977.0, total * 1000.0)
	var lap := int(t / total)
	var pos := t - lap * total
	var order := _order(station, lap)
	for k in order.size():
		var m = st.morceaux[order[k]]
		var d := float(m.duree)
		if pos < d or k == order.size() - 1:
			var path := "res://assets/radio/%s.ogg" % m.fichier
			if not ResourceLoader.exists(path):
				return
			_player.stream = load(path)
			title = m.titre
			_player.play(clampf(pos, 0.0, d - 0.5))
			return
		pos -= d

## Texte de l'écran de l'autoradio (cockpit) : fréquence de la station, vide si éteinte.
func lcd_text() -> String:
	return "" if station < 0 else String(stations[station].freq)
