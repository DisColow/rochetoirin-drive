## Conversations du taxi (data/taxi.json), dans l'esprit de Neo Cab ou Night Call, sans gêner la conduite : une bulle
## discrète en bas de l'écran, entre les commandes. Chaque client a un caractère (jovial, timide, grincheux…) dont les
## goûts restent cachés : chaque ton de réponse (chaleureux, drôle, curieux, sobre, ou le silence quand on ne répond
## pas à temps) lui plaît plus ou moins, ce qui change le pourboire. Le client parle de lui (métier, famille,
## maison), des nouvelles du coin, de la météo ou de sa destination ; le joueur peut aussi lancer la conversation
## (bouton « bulle » ou touche P), au risque d'agacer les taiseux. Réponses au doigt ou touches 1, 2, 3.
## Voix : babillage caricatural façon talkie-walkie (syllabes synthétisées, hauteur propre à chaque client, filtre
## bande étroite et grésillement), comme les voix sans paroles des jeux de Nintendo ; la radio baisse quand il parle.
extends CanvasLayer

var main: Node
var hud: CanvasLayer
var data := {}
var client := {}                  # client en cours : prénom, caractère, goûts, voix, satisfaction…
var riding := false

var _box: PanelContainer
var _name: Label
var _text: Label
var _choices: HBoxContainer
var _talk_btn: TouchScreenButton
var _full := ""                   # texte en train de s'afficher
var _shown := 0.0
var _hold := 0.0                  # temps d'affichage restant une fois le texte complet
var _wait := 0.0                  # temps restant pour répondre (0 : pas de question)
var _line := {}                   # réplique en cours (avec ses réponses)
var _next := 0.0                  # le client reprend la parole dans…
var _since := 99.0                # temps depuis le dernier échange
var _used := {}
var _rng := RandomNumberGenerator.new()
var _voice: Array = []            # syllabes (AudioStreamWAV) : a, e, i, o, u, ou
var _noise: AudioStreamWAV
var _players: Array = []
var _pi := 0
var _blip_acc := 0.0

const ANSWER_T := 9.0

func _ready() -> void:
	layer = 3
	process_mode = Node.PROCESS_MODE_ALWAYS
	if FileAccess.file_exists("res://data/taxi.json"):
		data = JSON.parse_string(FileAccess.get_file_as_string("res://data/taxi.json"))
	_rng.randomize()
	_box = PanelContainer.new()
	_box.add_theme_stylebox_override("panel", preload("res://scripts/ui.gd").panel(30, 16))
	_box.add_to_group("ui_zone")
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 8)
	_box.add_child(v)
	_name = Label.new(); _name.add_theme_font_size_override("font_size", 21)
	_name.add_theme_color_override("font_color", Color(1.0, 0.72, 0.28))
	v.add_child(_name)
	_text = Label.new(); _text.add_theme_font_size_override("font_size", 27)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(800, 0)
	v.add_child(_text)
	_choices = HBoxContainer.new(); _choices.add_theme_constant_override("separation", 10)
	v.add_child(_choices)
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
	for a in [["parler", KEY_P], ["reponse1", KEY_1], ["reponse2", KEY_2], ["reponse3", KEY_3]]:
		if not InputMap.has_action(a[0]):
			InputMap.add_action(a[0])
			var k := InputEventKey.new(); k.physical_keycode = a[1]
			InputMap.action_add_event(a[0], k)
	_make_voice()

# ---------------------------------------------------------------- client et course
## Nouveau client : caractère tiré au sort (goûts un peu variés d'un client à l'autre), identité, voix.
func start_ride(home: String, dest: String, dest_commune: String, dest_kind: String) -> String:
	if data.is_empty():
		return "« Bonjour ! %s, %s, s'il vous plaît. »" % [dest, dest_commune]
	var car_: Dictionary = data.caracteres[_rng.randi() % data.caracteres.size()]
	var g := {}
	for k in car_.gouts:
		g[k] = float(car_.gouts[k]) + _rng.randf_range(-0.6, 0.6)
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
		"pitch": _rng.randf_range(1.25, 1.65) if fem else _rng.randf_range(0.78, 1.08),
		"sat": 0.0,
	}
	_used = {}
	riding = true
	_since = 0.0
	_next = lerpf(42.0, 9.0, client.bavard) * _rng.randf_range(0.8, 1.25)
	var hello := _fill(_pick(data.bonjour))
	_say(hello, 4.5)
	return ""

## Fin de course : satisfaction de la conversation (-3 … 4) et mot de la fin (selon les étoiles de conduite aussi).
func end_ride(stars: int) -> Dictionary:
	riding = false
	_wait = 0.0
	_clear_choices()
	if client.is_empty():
		return {"sat": 0.0, "line": ""}
	var sat := clampf(float(client.sat), -3.0, 4.0)
	var score := sat + (stars - 3) * 0.8
	var cat := "bien" if score >= 1.5 else ("mal" if score <= -1.5 else "moyen")
	var line := _fill(_pick(data.fin[cat]))
	_say(line, 4.0)
	return {"sat": sat, "line": line}

func stop() -> void:
	riding = false
	_wait = 0.0
	_hold = 0.0
	_full = ""
	_box.visible = false
	_clear_choices()

# ---------------------------------------------------------------- dialogue
func _process(dt: float) -> void:
	var paused := get_tree().paused
	visible = not paused
	if _talk_btn:
		# en bas au milieu, entre les commandes, là où s'affiche la bulle (caché pendant qu'on se parle)
		_talk_btn.visible = riding and not paused and not _box.visible
		var vs := get_viewport().get_visible_rect().size
		_talk_btn.position = Vector2((vs.x - _talk_btn.shape.size.x) / 2.0, vs.y - _talk_btn.shape.size.y - 22.0)
	if main and main.get("radio") != null and main.radio.has_method("set_duck"):
		main.radio.set_duck(1.0 if (_box.visible and _shown < _full.length()) else 0.0)
	if paused:
		return
	_layout()
	# texte qui s'écrit, avec la voix
	if _full != "" and _shown < _full.length():
		var before := int(_shown)
		_shown = minf(_shown + dt * 30.0, _full.length())
		for i in range(before, int(_shown)):
			_blip(_full[i], i == _full.length() - 1 and _full.ends_with("?"))
		_text.text = _full.substr(0, int(_shown))
		if int(_shown) >= _full.length():
			_squelch()
	elif _hold > 0.0 and _wait <= 0.0:
		_hold -= dt
		if _hold <= 0.0:
			_box.visible = false
			_full = ""
	if not riding:
		return
	_since += dt
	if _wait > 0.0:
		_wait -= dt
		for i in 3:
			if Input.is_action_just_pressed("reponse%d" % (i + 1)) and i < _choices.get_child_count():
				_answer(_choices.get_child(i).get_meta("ton"))
				return
		if _wait <= 0.0:
			_answer("silence")
		return
	if Input.is_action_just_pressed("parler") and _full == "":
		_player_starts()
		return
	if _full == "" and not _box.visible:
		_next -= dt
		if _next <= 0.0:
			_client_starts(_topic())

func _topic() -> String:
	var subjects := ["vie", "maison", "nouvelles", "meteo", "destination"]
	subjects.shuffle()
	for s in subjects:
		if not _used.has(s):
			return s
	return subjects[0]

func _client_starts(subject: String) -> void:
	var pool: Array
	if subject == "destination":
		var d: Dictionary = data.sujets.destination
		pool = d.get(client.kind, d.autre)
	elif subject == "meteo" and main and int(main.get("weather")) == 2:
		pool = data.sujets.meteo_pluie
	else:
		pool = data.sujets[subject]
	_used[subject] = true
	_line = pool[_rng.randi() % pool.size()]
	_say(_fill(_line.dit), 0.0)
	# trois réponses sur quatre, dans le désordre
	var reps: Array = (_line.rep as Array).duplicate()
	reps.shuffle()
	_clear_choices()
	for k in mini(3, reps.size()):
		var r: Dictionary = reps[k]
		var b := Button.new()
		b.text = "%d. %s" % [k + 1, _fill(r.t)]
		b.set_meta("ton", r.ton)
		b.add_theme_font_size_override("font_size", 21)
		b.custom_minimum_size = Vector2(0, 62)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.size_flags_stretch_ratio = 1.0
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func(): _answer(r.ton))
		_choices.add_child(b)
	_wait = ANSWER_T + _full.length() / 30.0
	_since = 0.0

## Le joueur lance la conversation : les taiseux n'aiment pas qu'on les dérange, personne n'aime le harcèlement.
func _player_starts() -> void:
	var g: Dictionary = client.gouts
	if _since < 18.0:
		client.sat -= 0.8
		_say(_fill(_pick(data.trop)), 3.0)
		_since = 0.0
		return
	if client.bavard < 0.3 and g.curieux < 0.5:
		client.sat -= 0.6
		_say(_fill(_pick(data.derange)), 3.0)
		_since = 0.0
		_next = 999.0
		return
	client.sat += 0.25 * clampf(g.curieux, -1.0, 2.0)
	var free := []
	for q in data.questions:
		if not _used.has(q.sujet):
			free.append(q)
	if free.is_empty():
		free = data.questions
	var q: Dictionary = free[_rng.randi() % free.size()]
	_client_starts(q.sujet)

func _answer(ton: String) -> void:
	_wait = 0.0
	_clear_choices()
	var d: float = client.gouts.get(ton, 0.0)
	client.sat += d * 0.5
	_since = 0.0
	_next = lerpf(60.0, 16.0, client.bavard) * _rng.randf_range(0.8, 1.3)
	if ton == "silence" and absf(d) < 0.9:
		_hold = 0.0
		_box.visible = false
		_full = ""
		return
	var cat := "bien" if d >= 0.9 else ("mal" if d <= -0.9 else "moyen")
	_say(_pick(client.car[cat]), 3.2)

func _say(t: String, hold: float) -> void:
	_full = t
	_shown = 0.0
	_hold = hold
	_text.text = ""
	_name.text = "%s · %d ans" % [client.get("prenom", "Client"), int(client.get("age", 40))] if not client.is_empty() else "Client"
	_box.visible = true
	_squelch()

func _clear_choices() -> void:
	for c in _choices.get_children():
		c.queue_free()

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

func _fill(t: String) -> String:
	for k in ["prenom", "age", "metier", "metier_detail", "loisir", "animal", "famille", "commune", "dest", "dest_commune"]:
		t = t.replace("{%s}" % k, str(client.get(k, "")))
	return t.replace("{e}", "e" if client.get("fem", false) else "")

# ---------------------------------------------------------------- voix
## Syllabes synthétisées (synthèse par formants : impulsions glottiques qui excitent deux résonances) : a, é, i, o,
## u, ou ; chaque client les joue à sa hauteur. Bus « Voix » : bande étroite et saturation, façon talkie-walkie.
func _make_voice() -> void:
	var bus := AudioServer.get_bus_index("Voix")
	if bus < 0:
		AudioServer.add_bus()
		bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus, "Voix")
		AudioServer.set_bus_send(bus, "Master")
		var hp := AudioEffectHighPassFilter.new(); hp.cutoff_hz = 480.0
		var lp := AudioEffectLowPassFilter.new(); lp.cutoff_hz = 2700.0
		var ds := AudioEffectDistortion.new(); ds.mode = AudioEffectDistortion.MODE_OVERDRIVE; ds.drive = 0.35
		ds.post_gain = -4.0
		AudioServer.add_bus_effect(bus, hp)
		AudioServer.add_bus_effect(bus, ds)
		AudioServer.add_bus_effect(bus, lp)
		AudioServer.set_bus_volume_db(bus, -3.0)
	var sr := 22050
	var formants := [[780, 1250], [480, 1850], [300, 2250], [500, 900], [300, 1750], [330, 800]]
	for f in formants:
		_voice.append(_syllable(sr, 150.0, f[0], f[1]))
	# grésillement d'ouverture / fermeture du talkie-walkie
	var n := int(sr * 0.11)
	var pcm := PackedByteArray(); pcm.resize(n * 2)
	var prev := 0.0
	for i in n:
		var w := _rng.randf_range(-1.0, 1.0)
		prev = prev * 0.35 + w * 0.65
		var env := minf(1.0, i / (sr * 0.006)) * (1.0 - float(i) / n)
		pcm.encode_s16(i * 2, int(clampf(prev * env * 0.45, -1.0, 1.0) * 32767.0))
	_noise = AudioStreamWAV.new(); _noise.format = AudioStreamWAV.FORMAT_16_BITS; _noise.mix_rate = sr; _noise.data = pcm
	for i in 4:
		var p := AudioStreamPlayer.new()
		p.bus = "Voix"
		add_child(p)
		_players.append(p)

func _syllable(sr: int, f0: float, f1: float, f2: float) -> AudioStreamWAV:
	var n := int(sr * 0.085)
	var buf := PackedFloat32Array(); buf.resize(n)
	var period := int(sr / f0)
	var bw1 := 90.0; var bw2 := 130.0
	var t0 := 0
	while t0 < n:
		for j in mini(period * 3, n - t0):
			var t := float(j) / sr
			buf[t0 + j] += exp(-PI * bw1 * t) * sin(TAU * f1 * t) + 0.6 * exp(-PI * bw2 * t) * sin(TAU * f2 * t)
		t0 += period
	var pcm := PackedByteArray(); pcm.resize(n * 2)
	var peak := 0.001
	for i in n:
		peak = maxf(peak, absf(buf[i]))
	for i in n:
		var env := minf(1.0, i / (sr * 0.008)) * minf(1.0, (n - i) / (sr * 0.03))
		pcm.encode_s16(i * 2, int(buf[i] / peak * env * 0.8 * 32767.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS; s.mix_rate = sr; s.data = pcm
	return s

func _blip(ch: String, rising: bool) -> void:
	_blip_acc += 1.0
	var c := ch.to_lower()
	var v := -1
	match c:
		"a", "à", "â": v = 0
		"e", "é", "è", "ê", "ë": v = 1
		"i", "î", "y": v = 2
		"o", "ô": v = 3
		"u", "û", "ù": v = 4
	if v < 0:
		if c == " " or c == "." or c == "," or c == "!" or c == "?" or c == "…":
			return
		if _blip_acc < 2.0:
			return
		v = 5                          # une consonne de temps en temps : « ou »
	_blip_acc = 0.0
	if _voice.is_empty():
		return
	var p: AudioStreamPlayer = _players[_pi % _players.size()]
	_pi += 1
	p.stream = _voice[v]
	var base: float = client.get("pitch", 1.0)
	p.pitch_scale = base * _rng.randf_range(0.93, 1.07) * (1.18 if rising else 1.0)
	p.volume_db = -6.0
	p.play()

func _squelch() -> void:
	if _noise == null or _players.is_empty():
		return
	var p: AudioStreamPlayer = _players[_pi % _players.size()]
	_pi += 1
	p.stream = _noise
	p.pitch_scale = 1.0
	p.volume_db = -14.0
	p.play()
