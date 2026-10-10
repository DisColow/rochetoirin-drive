## Conversations du taxi (data/taxi.json, généré par pipeline/taxi_dialogues.py), dans l'esprit de Neo Cab ou Night
## Call, sans gêner la conduite : une bulle en bas de l'écran, entre les commandes.
## - Chaque client a un caractère (jovial, timide, grincheux…) aux goûts cachés : chaque ton de réponse (chaleureux,
##   drôle, curieux, sobre, ou le silence quand on ne répond pas à temps) lui plaît plus ou moins.
## - Une intervention du client est un fil de trois échanges : il parle, on répond, il réagit, et ça continue.
## - Indicateurs : après chaque réponse, ♥ (apprécié), • (bof) ou ✗ (agacé), et la jauge d'humeur du client.
## - Indices : son allure (sous son nom), ses réactions, et ses réponses quand on lui pose des questions (bouton
##   « bulle » ou touche P) ; ce qu'on apprend de ses goûts reste affiché.
## - Voix : chaque réplique (client et chauffeur) est dite par une voix de synthèse intelligible enregistrée par
##   pipeline/build_voix.py (morceaux enchaînés pour les noms de lieux, métiers…), passée par le bus « Voix » :
##   talkie-walkie (bande étroite, saturation légère, grésillement), hauteur propre à chaque client.
extends CanvasLayer

var main: Node
var hud: CanvasLayer
var data := {}
var client := {}                  # client en cours : prénom, caractère, goûts, voix, satisfaction…
var riding := false

const ANSWER_T := 10.0
const VAR := "\\{(prenom|age|metier|metier_detail|loisir|animal|famille|commune|dest|dest_commune)\\}"
const TON_NOM := {"chaleureux": "la gentillesse", "drole": "l'humour", "curieux": "qu'on s'intéresse à lui",
	"sobre": "les réponses courtes", "silence": "le calme"}

var _box: PanelContainer
var _name: Label
var _hint: Label
var _mood: ProgressBar
var _verdict: Label
var _text: Label
var _choices: HBoxContainer
var _timer_bar: ProgressBar
var _talk_btn: TouchScreenButton
var _rng := RandomNumberGenerator.new()
var _re_var := RegEx.new()
var _re_acc := RegEx.new()

# déroulé : file d'étapes (parole du client / du joueur, choix, pause) jouées l'une après l'autre
var _queue: Array = []
var _step := {}
var _full := ""
var _shown := 0.0
var _speed := 30.0
var _hold := 0.0
var _wait := 0.0
var _wait_max := 1.0
var _fil: Array = []              # fil de conversation en cours
var _node := 0
var _next := 0.0                  # le client reprend la parole dans…
var _since := 99.0
var _used := {}
var _asked := {}

# voix
var _player: AudioStreamPlayer
var _noise_player: AudioStreamPlayer
var _noise: AudioStreamWAV
var _say_end := 0                  # fin prévue de la réplique (ms) : ne dépend pas du seul signal du lecteur

func _ready() -> void:
	layer = 3
	process_mode = Node.PROCESS_MODE_ALWAYS
	if FileAccess.file_exists("res://data/taxi.json"):
		data = JSON.parse_string(FileAccess.get_file_as_string("res://data/taxi.json"))
	_re_var.compile(VAR)
	_re_acc.compile("\\{([^{}|]*)\\|([^{}]*)\\}")
	_rng.randomize()
	_build_ui()
	for a in [["parler", KEY_P], ["reponse1", KEY_1], ["reponse2", KEY_2], ["reponse3", KEY_3], ["reponse4", KEY_4]]:
		if not InputMap.has_action(a[0]):
			InputMap.add_action(a[0])
			var k := InputEventKey.new(); k.physical_keycode = a[1]
			InputMap.action_add_event(a[0], k)
	_make_voice()

func _build_ui() -> void:
	_box = PanelContainer.new()
	_box.add_theme_stylebox_override("panel", preload("res://scripts/ui.gd").panel(30, 16))
	_box.add_to_group("ui_zone")
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 6)
	_box.add_child(v)
	var top := HBoxContainer.new(); top.add_theme_constant_override("separation", 14)
	v.add_child(top)
	_name = Label.new(); _name.add_theme_font_size_override("font_size", 21)
	_name.add_theme_color_override("font_color", Color(1.0, 0.72, 0.28))
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_name)
	_verdict = Label.new(); _verdict.add_theme_font_size_override("font_size", 22)
	top.add_child(_verdict)
	var ml := Label.new(); ml.text = "Humeur"; ml.add_theme_font_size_override("font_size", 18)
	ml.modulate = Color(1, 1, 1, 0.7)
	top.add_child(ml)
	_mood = ProgressBar.new(); _mood.min_value = -3.0; _mood.max_value = 4.0; _mood.show_percentage = false
	_mood.custom_minimum_size = Vector2(150, 18); _mood.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := StyleBoxFlat.new(); fill.bg_color = Color.WHITE; fill.set_corner_radius_all(3)
	var bg := StyleBoxFlat.new(); bg.bg_color = Color(0, 0, 0, 0.45); bg.set_corner_radius_all(3)
	_mood.add_theme_stylebox_override("fill", fill)
	_mood.add_theme_stylebox_override("background", bg)
	top.add_child(_mood)
	_hint = Label.new(); _hint.add_theme_font_size_override("font_size", 18)
	_hint.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_hint)
	_text = Label.new(); _text.add_theme_font_size_override("font_size", 27)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(800, 0)
	v.add_child(_text)
	_choices = HBoxContainer.new(); _choices.add_theme_constant_override("separation", 10)
	v.add_child(_choices)
	_timer_bar = ProgressBar.new(); _timer_bar.show_percentage = false; _timer_bar.custom_minimum_size = Vector2(0, 6)
	_timer_bar.max_value = 1.0
	v.add_child(_timer_bar)
	_box.visible = false
	add_child(_box)
	if ResourceLoader.exists("res://assets/ui/btn_parler.png"):
		_talk_btn = TouchScreenButton.new()
		_talk_btn.texture_normal = load("res://assets/ui/btn_parler.png")
		_talk_btn.texture_pressed = load("res://assets/ui/btn_parler_p.png")
		var rs := RectangleShape2D.new(); rs.size = _talk_btn.texture_normal.get_size()
		_talk_btn.shape = rs; _talk_btn.shape_centered = true
		_talk_btn.action = "parler"
		_talk_btn.visible = false
		_talk_btn.add_to_group("ui_zone")
		add_child(_talk_btn)

# ---------------------------------------------------------------- client et course
## Nouveau client : caractère tiré au sort (goûts un peu variés d'un client à l'autre), identité, voix.
func start_ride(home: String, dest: String, dest_commune: String, dest_kind: String) -> String:
	if data.is_empty():
		return "« Bonjour ! %s, %s, s'il vous plaît. »" % [dest, dest_commune]
	var car_: Dictionary = data.caracteres[_rng.randi() % data.caracteres.size()]
	var g := {}
	for k in car_.gouts:
		g[k] = float(car_.gouts[k]) + _rng.randf_range(-0.4, 0.4)
	var fem := _rng.randf() < 0.5
	var met: Dictionary = data.metiers[_rng.randi() % data.metiers.size()]
	var age := _rng.randi_range(19, 84)
	if met.m == "retraité":
		age = _rng.randi_range(63, 88)
	elif met.m == "étudiant":
		age = _rng.randi_range(18, 25)
	client = {
		"car": car_, "gouts": g, "bavard": clampf(float(car_.bavard) + _rng.randf_range(-0.15, 0.15), 0.05, 1.0),
		"prenom": _pick(data.prenoms.f if fem else data.prenoms.m), "fem": fem, "age": age,
		"metier": met.f if fem else met.m, "metier_detail": met.detail,
		"loisir": _pick(data.loisirs), "animal": _pick(data.animaux), "famille": _pick(data.familles),
		"commune": home, "dest": dest, "dest_commune": dest_commune, "kind": dest_kind,
		"tts": _rng.randi_range(0, 7),
		"pitch": _rng.randf_range(1.15, 1.35) if fem else _rng.randf_range(0.78, 0.95),
		"allure": "", "connu": {},
		"sat": 0.0,
	}
	client.allure = _fill(_pick(car_.allure))         # après « client » : accord au féminin
	_used = {}
	_asked = {}
	_queue.clear()
	_fil = []
	riding = true
	_since = 0.0
	_next = lerpf(30.0, 8.0, client.bavard) * _rng.randf_range(0.8, 1.2)
	_verdict.text = ""
	_client_says(_pick(data.bonjour), 2.5)
	return ""

## Fin de course : satisfaction de la conversation (-3 … 4) et mot de la fin (selon les étoiles de conduite aussi).
func end_ride(stars: int) -> Dictionary:
	riding = false
	_wait = 0.0
	_queue.clear()
	_fil = []
	_clear_choices()
	if client.is_empty():
		return {"sat": 0.0, "line": ""}
	var sat := clampf(float(client.sat), -3.0, 4.0)
	var score := sat + (stars - 3) * 0.8
	var cat := "bien" if score >= 1.5 else ("mal" if score <= -1.5 else "moyen")
	var line: String = _pick(data.fin[cat])
	_step = {}
	_client_says(line, 4.0)
	return {"sat": sat, "line": _fill(line)}

func stop() -> void:
	riding = false
	_wait = 0.0
	_hold = 0.0
	_full = ""
	_queue.clear()
	_step = {}
	_fil = []
	_box.visible = false
	if not _voices.is_empty():
		DisplayServer.tts_stop()
	_hiss_player.stop()
	_clear_choices()

# ---------------------------------------------------------------- déroulé
func _client_says(t: String, hold := 1.2) -> void:
	_queue.append({"kind": "dit", "who": "client", "t": t, "hold": hold})
	if _step.is_empty():
		_advance()

func _player_says(t: String) -> void:
	_queue.append({"kind": "dit", "who": "joueur", "t": t, "hold": 0.5})
	if _step.is_empty():
		_advance()

func _advance() -> void:
	_step = {}
	if _queue.is_empty():
		return
	_step = _queue.pop_front()
	match _step.kind:
		"dit":
			_say(_step.t, _step.who)
			_hold = float(_step.hold)
		"choix":
			_show_choices(_step.options)
		"appel":
			(_step.f as Callable).call()
			_advance()

func _process(dt: float) -> void:
	var paused := get_tree().paused
	visible = not paused
	if _talk_btn:
		_talk_btn.visible = riding and not paused and _step.is_empty() and _queue.is_empty()
		var vs := get_viewport().get_visible_rect().size
		var bh := _box.size.y + 30.0 if _box.visible else 22.0
		_talk_btn.position = Vector2((vs.x - _talk_btn.shape.size.x) / 2.0, vs.y - _talk_btn.shape.size.y - bh)
	var speaking := _full != "" and (_shown < _full.length() or Time.get_ticks_msec() < _say_end)
	if main and main.get("radio") != null and main.radio.has_method("set_duck"):
		main.radio.set_duck(1.0 if speaking else 0.0)
	var AU := preload("res://scripts/audio.gd")
	AU.talk_duck = move_toward(AU.talk_duck, 1.0 if speaking else 0.0, dt * (5.0 if speaking else 1.2))
	if paused:
		return
	_layout()
	if client.size() > 0:
		_mood.value = clampf(float(client.sat), -3.0, 4.0)
		_mood.modulate = Color(1.0, 0.45, 0.4).lerp(Color(0.5, 1.0, 0.5), clampf((float(client.sat) + 3.0) / 7.0, 0.0, 1.0))
	# texte qui s'écrit au rythme de la voix
	if _full != "" and _shown < _full.length():
		_shown = minf(_shown + dt * _speed, _full.length())
		_text.text = _full.substr(0, int(_shown))
	elif _step.get("kind", "") == "dit" and Time.get_ticks_msec() > _say_end:
		_hold -= dt
		if _hold <= 0.0:
			_squelch()
			_hiss_player.stop()
			_advance()
	elif _step.is_empty() and _box.visible and _full != "":
		_hold -= dt
		if _hold <= -3.0:
			_box.visible = false
			_full = ""
	if not riding:
		return
	_since += dt
	if _step.get("kind", "") == "choix":
		_wait -= dt
		_timer_bar.value = clampf(_wait / _wait_max, 0.0, 1.0)
		for i in 4:
			if Input.is_action_just_pressed("reponse%d" % (i + 1)) and i < _choices.get_child_count():
				_choices.get_child(i).emit_signal("pressed")
				return
		if _wait <= 0.0:
			(_step.timeout as Callable).call()
		return
	if not _step.is_empty() or not _queue.is_empty():
		return
	if Input.is_action_just_pressed("parler"):
		_ask_menu()
		return
	_next -= dt
	if _next <= 0.0:
		_start_fil(_topic())

# ---------------------------------------------------------------- fils de conversation (le client parle)
func _topic() -> String:
	var subjects: Array = data.fils.keys()
	subjects.erase("meteo_pluie")
	if main and int(main.get("weather")) == 2:
		subjects.erase("meteo"); subjects.append("meteo_pluie")
	subjects.shuffle()
	for s in subjects:
		if not _used.has(s):
			return s
	return subjects[0]

func _start_fil(subject: String) -> void:
	_used[subject] = true
	var pool: Array = data.fils[subject]
	_fil = pool[_rng.randi() % pool.size()]
	_node = 0
	_since = 0.0
	_exchange()

func _exchange() -> void:
	if _node >= _fil.size():
		_fil = []
		_next = lerpf(55.0, 14.0, client.bavard) * _rng.randf_range(0.8, 1.3)
		return
	var n: Dictionary = _fil[_node]
	_client_says(n.dit, 0.3)
	# trois réponses sur quatre (toujours au moins une qui plaît), dans le désordre
	var tons: Array = (n.rep as Dictionary).keys()
	tons.sort_custom(func(a, b): return float(client.gouts.get(a, 0.0)) > float(client.gouts.get(b, 0.0)))
	var pick: Array = [tons[0]]
	var rest := tons.slice(1)
	rest.shuffle()
	pick.append_array(rest.slice(0, 2))
	pick.shuffle()
	var opts := []
	for t in pick:
		opts.append({"t": n.rep[t], "ton": t})
	_queue.append({"kind": "choix", "options": opts, "timeout": func(): _answer("", "silence")})

func _answer(text: String, ton: String) -> void:
	_clear_choices()
	_step = {}
	var d: float = float(client.gouts.get(ton, 0.0))
	client.sat = float(client.sat) + d * 0.45
	_since = 0.0
	var cat := "bien" if d >= 0.9 else ("mal" if d <= -0.9 else "moyen")
	_verdict.text = {"bien": "♥ Apprécié", "moyen": "• Bof", "mal": "✗ Agacé"}[cat]
	_verdict.add_theme_color_override("font_color", {"bien": Color(0.45, 1.0, 0.5), "moyen": Color(0.8, 0.8, 0.8),
		"mal": Color(1.0, 0.4, 0.35)}[cat])
	if text != "":
		_player_says(text)
	var reaction: String = _pick(client.car[cat]) if text != "" else _pick(data.silence if cat != "mal" else client.car.mal)
	# un client agacé deux fois de suite écourte le fil
	if cat == "mal" and _node > 0 and _rng.randf() < 0.5:
		_node = 99
	_node += 1
	_client_says(reaction, 0.6)
	_queue.append({"kind": "appel", "f": _exchange})
	if _step.is_empty():
		_advance()

# ---------------------------------------------------------------- questions au client
func _ask_menu() -> void:
	if _since < 6.0:
		client.sat -= 0.5
		_client_says(_pick(data.trop))
		_since = 0.0
		return
	var free := []
	for q in data.questions:
		if not _asked.has(q.id):
			free.append(q)
	if free.is_empty():
		_client_says(_pick(data.trop))
		return
	free.shuffle()
	var opts := []
	for q in free.slice(0, 3):
		opts.append({"t": _pick(q.t), "ton": "question", "q": q})
	opts.append({"t": "Rien, laissez.", "ton": "annule"})
	_queue.append({"kind": "choix", "options": opts, "timeout": _cancel_choice})
	_advance()

func _ask(q: Dictionary, text: String) -> void:
	_clear_choices()
	_step = {}
	_asked[q.id] = true
	_since = 0.0
	var g: Dictionary = client.gouts
	_player_says(text)
	if client.bavard < 0.3 and float(g.curieux) < 0.0 and _rng.randf() < 0.6:
		client.sat = float(client.sat) - 0.4
		_verdict.text = "✗ Dérangé" if not client.fem else "✗ Dérangée"
		_verdict.add_theme_color_override("font_color", Color(1.0, 0.4, 0.35))
		_client_says(_pick(data.esquive))
		_next = maxf(_next, 25.0)
		return
	client.sat = float(client.sat) + 0.25 * clampf(float(g.curieux), -1.0, 2.0)
	var ans: String
	if q.has("fait"):
		ans = _pick(q.fait)
	else:
		ans = _pick(client.car.reponses[q.id])
		if q.id == "aime":
			# ce qu'on apprend de ses goûts reste affiché (indice pour les réponses suivantes)
			var best := ""
			var worst := ""
			for t in ["chaleureux", "drole", "curieux", "sobre", "silence"]:
				if best == "" or float(g[t]) > float(g[best]):
					best = t
				if worst == "" or float(g[t]) < float(g[worst]):
					worst = t
			client.connu = {"aime": TON_NOM[best], "deteste": TON_NOM[worst]}
	_client_says(ans, 1.0)
	_next = maxf(_next, 12.0)

# ---------------------------------------------------------------- bulle et choix
func _show_choices(opts: Array) -> void:
	_clear_choices()
	var k := 0
	for o in opts:
		var b := Button.new()
		b.text = "%d. %s" % [k + 1, o.t]
		b.add_theme_font_size_override("font_size", 21)
		b.custom_minimum_size = Vector2(0, 62)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.focus_mode = Control.FOCUS_NONE
		var oo: Dictionary = o
		b.pressed.connect(func():
			if oo.ton == "question":
				_ask(oo.q, oo.t)
			elif oo.ton == "annule":
				_cancel_choice()
				_box.visible = false
				_full = ""
			else:
				_answer(oo.t, oo.ton))
		_choices.add_child(b)
		k += 1
	_wait_max = ANSWER_T + 2.0
	_wait = _wait_max
	_timer_bar.visible = true
	_box.visible = true

func _cancel_choice() -> void:
	_clear_choices()
	_step = {}

func _clear_choices() -> void:
	for c in _choices.get_children():
		c.queue_free()
	_timer_bar.visible = false

func _say(t: String, who: String) -> void:
	var filled := _fill(t)
	_full = filled
	_shown = 0.0
	_text.text = ""
	_box.visible = true
	if who == "joueur":
		_name.text = "Vous"
		_name.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
	else:
		_name.text = "%s · %d ans · %s" % [client.get("prenom", "Client"), int(client.get("age", 40)), client.get("metier", "")] \
			if not client.is_empty() else "Client"
		_name.add_theme_color_override("font_color", Color(1.0, 0.72, 0.28))
	var h := str(client.get("allure", ""))
	if client.get("connu", {}).size() > 0:
		h += "   Aime : %s. N'aime pas : %s." % [client.connu.aime, client.connu.deteste]
	_hint.text = h
	_hint.visible = h != ""
	var dur := _speak(t, who)
	_say_end = Time.get_ticks_msec() + int(dur * 1000.0) + 400
	_speed = clampf(filled.length() / maxf(dur, 0.3), 10.0, 40.0) if dur > 0.0 else 30.0

func _layout() -> void:
	var vs := get_viewport().get_visible_rect().size
	var w := minf(900.0, vs.x - 980.0) if vs.x > 1700 else minf(900.0, vs.x - 40.0)
	_text.custom_minimum_size.x = w - 60.0
	_box.reset_size()
	var h := _box.get_combined_minimum_size().y
	_box.size = Vector2(w, h)
	_box.position = Vector2((vs.x - w) / 2.0, vs.y - h - 18.0)

func _pick(a: Array) -> String:
	return str(a[_rng.randi() % a.size()])

func _accord(t: String) -> String:
	var fem: bool = client.get("fem", false)
	t = _re_acc.sub(t, "$2" if fem else "$1", true)
	return t.replace("{e}", "e" if fem else "")

func _fill(t: String) -> String:
	t = _accord(t)
	for k in ["prenom", "age", "metier", "metier_detail", "loisir", "animal", "famille", "commune", "dest", "dest_commune"]:
		t = t.replace("{%s}" % k, str(client.get(k, "")))
	return t

# ---------------------------------------------------------------- voix
## Synthèse vocale du système (Android, Windows, Linux : DisplayServer.tts_*), voix française de base, nette.
## Effet talkie-walkie autour : grésillement à l'ouverture et à la fermeture du micro, léger souffle radio pendant
## qu'on parle (bus « Voix » : bande étroite). La synthèse elle-même ne passe pas par les effets du jeu (elle sort
## directement du système), ce qui la garde compréhensible.
var _voices: PackedStringArray = []
var _hiss_player: AudioStreamPlayer

func _make_voice() -> void:
	var bus := AudioServer.get_bus_index("Voix")
	if bus < 0:
		AudioServer.add_bus()
		bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus, "Voix")
		AudioServer.set_bus_send(bus, "Master")
		var hp := AudioEffectHighPassFilter.new(); hp.cutoff_hz = 500.0
		var lp := AudioEffectLowPassFilter.new(); lp.cutoff_hz = 3000.0
		AudioServer.add_bus_effect(bus, hp)
		AudioServer.add_bus_effect(bus, lp)
	_player = AudioStreamPlayer.new(); _player.bus = "Voix"
	add_child(_player)
	_noise_player = AudioStreamPlayer.new(); _noise_player.bus = "Voix"; _noise_player.volume_db = -8.0
	add_child(_noise_player)
	_hiss_player = AudioStreamPlayer.new(); _hiss_player.bus = "Voix"; _hiss_player.volume_db = -30.0
	add_child(_hiss_player)
	var sr := 22050
	# grésillement d'ouverture / fermeture (bruit coloré, attaque sèche)
	var n := int(sr * 0.12)
	var pcm := PackedByteArray(); pcm.resize(n * 2)
	var prev := 0.0
	for i in n:
		var w := _rng.randf_range(-1.0, 1.0)
		prev = prev * 0.35 + w * 0.65
		var env := minf(1.0, i / (sr * 0.004)) * (1.0 - float(i) / n)
		pcm.encode_s16(i * 2, int(clampf(prev * env * 0.5, -1.0, 1.0) * 32767.0))
	_noise = AudioStreamWAV.new(); _noise.format = AudioStreamWAV.FORMAT_16_BITS; _noise.mix_rate = sr; _noise.data = pcm
	# souffle radio en boucle (1 s)
	var hn := sr
	var hp_ := PackedByteArray(); hp_.resize(hn * 2)
	for i in hn:
		hp_.encode_s16(i * 2, int(_rng.randf_range(-0.3, 0.3) * 32767.0))
	var hiss := AudioStreamWAV.new(); hiss.format = AudioStreamWAV.FORMAT_16_BITS; hiss.mix_rate = sr; hiss.data = hp_
	hiss.loop_mode = AudioStreamWAV.LOOP_FORWARD; hiss.loop_end = hn
	_hiss_player.stream = hiss
	if DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		for v in DisplayServer.tts_get_voices():
			if str(v.get("language", "")).begins_with("fr"):
				_voices.append(str(v.id))
		DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_ENDED, _tts_fin)
		DisplayServer.tts_set_utterance_callback(DisplayServer.TTS_UTTERANCE_CANCELED, _tts_fin)

func _tts_fin(_id: int) -> void:
	_say_end = Time.get_ticks_msec()
	_hiss_player.stop()

## Dit une réplique (texte complet, variables remplies). Renvoie une durée estimée (0 sans synthèse vocale : le texte
## s'écrit alors seul).
func _speak(t: String, who: String) -> float:
	_squelch()
	if _voices.is_empty():
		return 0.0
	DisplayServer.tts_stop()
	var txt := _fill(t)
	var voice: String = _voices[0]
	var pitch := 1.0
	if who != "joueur":
		voice = _voices[int(client.get("tts", 0)) % _voices.size()]
		pitch = float(client.get("pitch", 1.0))
	DisplayServer.tts_speak(txt, voice, 100, pitch, 1.0, 0, true)
	_hiss_player.play()
	return txt.length() / 13.0 + 0.3

func _squelch() -> void:
	if _noise == null:
		return
	_noise_player.stream = _noise
	_noise_player.play()
