## Autoradio de l'Espace : six stations à thème (musiques de Kevin MacLeod, incompetech.com, CC BY 4.0 ;
## assets/radio/radio.json, pipeline/fetch_radio.py). Comme dans les grands jeux en monde ouvert, chaque station
## « émet » en continu, même quand on ne l'écoute pas : on tombe en cours de morceau, et l'ordre des morceaux change à
## chaque tour du programme. Grésillement en changeant de station. Son d'autoradio (haut-parleurs de portière : bande
## étroite) dans l'habitacle ; en vue extérieure (fenêtre ouverte), plus lointain et plus sourd.
## Commandes : bouton ♪ (ou touche N) : station suivante, puis arrêt ; l'écran de l'autoradio du cockpit affiche la
## fréquence.
## Dernière station, « Rochetoirin Info » (#56, radio_infos.gd) : début du journal du jour (podcast) ou flash des
## derniers titres lu par la voix du téléphone, puis deux chansons prises dans toutes les stations, et ainsi de suite.
extends Node
const PerfMon := preload("res://scripts/perf_monitor.gd")

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
var _duck := 0.0                   # baisse du volume quand un client du taxi parle
var _fm: AudioStreamPlayer         # grésillement FM : souffle léger et petits crachotements de temps en temps
var _fm_t := 6.0
var _fm_len := 0.0
var _fade := 0.0                   # creux de réception (trajets multiples) : la musique baisse un instant
var _rng := RandomNumberGenerator.new()
var infos: Node                    # radio_infos.gd
const JOURNAL_MAX := 420.0         # coupe un journal trop long (7 min)
var _etape := 0                    # station d'info : 0 actualité, 1-2 chansons
var _en_journal := false
var _dernier_journal := -1e9       # heure (s) du dernier journal diffusé : un par quart d'heure au plus
var _flash_t := 0.0                # flash lu par la voix du téléphone : temps restant

## 1 : quelqu'un parle dans la voiture (la radio baisse), 0 : volume normal.
func set_duck(on: float) -> void:
	_duck = move_toward(_duck, on, get_process_delta_time() * (6.0 if on > _duck else 1.5))

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not FileAccess.file_exists("res://assets/radio/radio.json"):
		set_process(false)
		return
	stations = JSON.parse_string(FileAccess.get_file_as_string("res://assets/radio/radio.json")).stations
	# station d'info (#56) : toutes les chansons, entre les actualités
	var toutes := []
	for st in stations:
		toutes.append_array(st.morceaux)
	stations.append({"nom": "Rochetoirin Info", "freq": "105.5", "infos": true, "morceaux": toutes})
	infos = preload("res://scripts/radio_infos.gd").new()
	add_child(infos)
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
	_fm = AudioStreamPlayer.new()
	_fm.bus = "Radio"
	_fm.stream = _noise.stream
	_fm.volume_db = -80.0
	add_child(_fm)
	_rng.randomize()
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
	var t0_perf := Time.get_ticks_usec()
	_process_corps(dt)
	PerfMon.note("radio", Time.get_ticks_usec() - t0_perf)

func _process_corps(dt: float) -> void:
	if Input.is_action_just_pressed("radio"):
		next()
	var inside := 1.0 if (cam_rig and cam_rig.mode == 1) else 0.0
	_cockpit = move_toward(_cockpit, inside, dt * 3.0)
	if _lp:
		_lp.cutoff_hz = lerpf(2600.0, 7000.0, _cockpit)
	AudioServer.set_bus_volume_db(_bus, lerpf(-4.0, 2.0, _cockpit) - 9.0 * _duck
		+ preload("res://scripts/audio.gd").volume_db("musique"))
	_fm_crackle(dt)
	if station >= 0 and stations[station].get("infos", false):
		if _en_journal and _player.playing and _player.get_playback_position() > JOURNAL_MAX:
			_player.stop()
			_tune()
		if _flash_t > 0.0:
			_flash_t -= dt
			if _flash_t <= 0.0:
				_tune()

## Charme de la FM : de temps en temps un crachotement (grésillement bref, plus ou moins fort) et un petit creux de
## réception où la musique faiblit, comme sur un autoradio en roulant dans les collines.
func _fm_crackle(dt: float) -> void:
	if station < 0 or _fm.stream == null or not _player.playing:
		_fm.volume_db = -80.0
		return
	_fm_t -= dt
	if _fm_t <= 0.0:
		_fm_t = _rng.randf_range(7.0, 26.0)
		_fm_len = _rng.randf_range(0.15, 1.1)
		_fm.pitch_scale = _rng.randf_range(0.8, 1.3)
		_fm.play(_rng.randf_range(0.0, maxf(_fm.stream.get_length() - 1.5, 0.0)))
		if _rng.randf() < 0.5:
			_fade = 1.0
	if _fm_len > 0.0:
		_fm_len -= dt
		_fm.volume_db = -22.0 + _rng.randf_range(-6.0, 3.0)
	else:
		_fm.volume_db = move_toward(_fm.volume_db, -80.0, dt * 120.0)
		if _fm.volume_db <= -79.0 and _fm.playing:
			_fm.stop()
	_fade = move_toward(_fade, 0.0, dt * 1.6)
	_player.volume_db = (-6.0 if get_tree().paused else 0.0) - 7.0 * sin(_fade * PI)

## Station suivante ; après la dernière, arrêt.
func next() -> void:
	if station >= 0 and stations[station].get("infos", false):
		_flash_t = 0.0
		DisplayServer.tts_stop()                     # le flash s'arrête avec la station
		_etape = 0
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
	if stations[station].get("infos", false):
		_tune_infos()
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

## Station d'info : actualité (journal du jour au plus une fois par demi-heure, sinon flash), puis deux chansons.
func _tune_infos() -> void:
	_en_journal = false
	_flash_t = 0.0
	var st = stations[station]
	if _etape % 3 == 0:
		_etape += 1
		var now := Time.get_unix_time_from_system()
		if infos.journal and now - _dernier_journal > 900.0:
			_dernier_journal = now
			_en_journal = true
			_player.stream = infos.journal
			_player.play(0.0)
			title = infos.journal_titre
			if hud:
				hud.toast("♪ Rochetoirin Info\n%s" % title, 3.0)
			return
		var t: String = infos.flash()
		var d: float = infos.lire_flash(t, clampf(0.8 + preload("res://scripts/audio.gd").volume_db("musique") / 30.0, 0.2, 1.0))
		if d > 0.0:
			_player.stop()
			title = "Flash info"
			_flash_t = d + 1.0
			return
	_etape += 1
	var m = st.morceaux[_rng.randi_range(0, st.morceaux.size() - 1)]
	var path := "res://assets/radio/%s.ogg" % m.fichier
	if ResourceLoader.exists(path):
		_player.stream = load(path)
		title = m.titre
		_player.play(0.0)

## Texte de l'écran de l'autoradio (cockpit) : fréquence de la station, vide si éteinte.
func lcd_text() -> String:
	return "" if station < 0 else String(stations[station].freq)
