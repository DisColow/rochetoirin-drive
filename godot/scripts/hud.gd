## Interface (disposition de la première version) : mini-GPS en haut à droite avec le panneau de vitesse (limitation
## et compteur) dessous, nom de la rue dans une pastille en haut au centre (commune et coordonnées en petit),
## boutons carte / caméra / remise sur la route en haut à gauche ; commandes tactiles multipoint (◀ ▶ à gauche, frein
## et accélérateur à droite). La manette et le clavier passent par les mêmes actions.
extends CanvasLayer

const UI := preload("res://scripts/ui.gd")

var car: VehicleBody3D
var speed: Label
var buttons := []
var map: Control
var road: Label
var where: Label
var names = preload("res://scripts/road_name.gd").new()
var _name_t := 0.0
signal teleport(pos: Vector3, heading: float)

var gps: Control
var pill: Control
var speed_panel: Control
var _road_text := ""
var _where_text := ""
var _limit := 0

func _ready() -> void:
	gps = preload("res://scripts/gps.gd").new()
	gps.car = car
	gps.open_map.connect(_open_map)
	add_child(gps)
	pill = Control.new()
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.draw.connect(_draw_pill)
	add_child(pill)
	speed_panel = Control.new()
	speed_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	speed_panel.draw.connect(_draw_speed)
	add_child(speed_panel)
	get_viewport().size_changed.connect(_layout)
	_add_button("gauche", "◀", 0)
	_add_button("droite", "▶", 1)
	_add_button("freiner", "FREIN", 2)
	_add_button("accelerer", "GAZ", 3)
	_add_button("camera", "CAM", 4)
	_add_button("replacer", "↺", 5)
	_add_button("carte", "CARTE", 6)
	_add_button("reglages", "⚙", 7)
	_add_button("activites", "★", 8)
	_add_button("radio", "♪", 9)
	map = preload("res://scripts/map.gd").new()
	map.car = car
	map.visible = false
	map.teleport.connect(func(p, h): teleport.emit(p, h))
	map.closed.connect(func(): _show_drive(true))
	add_child(map)
	_layout()

var settings: Control

const CREDITS := """Voiture : « Ford Ranger Raptor 2019 » par David_Holiday (Sketchfab, licence CC BY 4.0), repeint en noir avec couvercle de benne blanc.
Soucoupe du gardien : « UFO » par sebslom (sketchfab.com/3d-models), licence CC BY 4.0.
Pluie et orage : Sound Effect by Premankur Adhikary from Pixabay.
Sons (moteur, roulement, ambiances, oiseaux, animaux, cloches, essuie-glaces, soucoupe…) : enregistrements de Joseph SARDIN - BigSoundBank.com (licence CC0) ; chocs : « Impact Sounds » de Kenney (CC0).
Arbres : modèles Sketchfab (licences CC BY / CC0, auteurs listés dans le dépôt).
Animaux (Sketchfab, licence CC BY 4.0) : « Cow » par JosueBoisvert, « Sheep » par kenchoo, « Horse Rigged (Game Ready) » par abhayexe.
Voitures garées (Sketchfab, licence CC BY 4.0) : « Generic 80s european car » par henryviii, « Low Poly Small car » et « Low-Poly Sedan car » par scailman, « Blue Sedan | Stylized Low Poly » par R3indeer.
Clients du taxi : « Low Poly Characters (PACK) » par micaelsampaio (Sketchfab, licence CC BY 4.0).
Musiques de la radio : Kevin MacLeod (incompetech.com), licence Creative Commons Attribution 4.0 — voir assets/radio/radio.json pour les titres.
Polices de l'interface : « Pixelify Sans » (Stefie Justprince) et « DSEG » (Keshikan), licence SIL Open Font License 1.1.
Textures : Poly Haven et ambientCG (CC0).
Données : © les contributeurs d'OpenStreetMap (ODbL) ; IGN (BD TOPO, RGE ALTI, LiDAR HD, BD ORTHO, Licence Ouverte Etalab).
Modèles des commerces, équipements, haies, maisons, clôtures et sprite de la voiture : faits avec Blender pour le jeu ; boutons de la planche de bord dessinés pixel par pixel pour le jeu."""

## Message bref au centre de l'écran (péage…), qui s'efface tout seul.
var _toast: PanelContainer
var _toast_t := 0.0
func toast(text: String, secs := 3.5) -> void:
	if _toast == null:
		_toast = PanelContainer.new()
		_toast.add_theme_stylebox_override("panel", UI.panel(40, 18))
		_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var l := Label.new(); l.add_theme_font_size_override("font_size", 34)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_toast.add_child(l)
		add_child(_toast)
	(_toast.get_child(0) as Label).text = text
	_toast.reset_size()
	var vs := get_viewport().get_visible_rect().size
	_toast.position = Vector2((vs.x - _toast.get_combined_minimum_size().x) / 2, maxf(vs.y * 0.3, 230.0))
	_toast.modulate.a = 1.0
	_toast.visible = true
	_toast_t = secs

## Réglages : densité de la végétation (mémorisée dans user://reglages.cfg).
func _open_settings() -> void:
	if settings and is_instance_valid(settings):
		return
	var veg = get_parent().vegetation
	_show_drive(false)
	settings = PanelContainer.new()
	settings.add_theme_stylebox_override("panel", UI.panel(44, 26))
	# contenu défilant (glisser au doigt, molette) : le menu tient sur les petits écrans
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	settings.add_child(sc)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 12)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	var t := Label.new(); t.text = "Réglages"; t.add_theme_font_size_override("font_size", 44); v.add_child(t)
	var l := Label.new(); l.text = "Densité de la végétation"; l.add_theme_font_size_override("font_size", 30); v.add_child(l)
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 16); v.add_child(h)
	for i in veg.LEVELS.size():
		var b := Button.new()
		b.text = veg.LEVELS[i].name
		b.toggle_mode = true
		b.button_pressed = i == veg.level
		b.custom_minimum_size = Vector2(220, 70)
		b.add_theme_font_size_override("font_size", 30)
		b.pressed.connect(func():
			veg.set_level(i)
			veg.update_now()
			get_parent().crops.set_level(i)
			get_parent().grass.set_level(i)
			get_parent().set_post(i)
			var cfg := ConfigFile.new(); cfg.load("user://reglages.cfg")
			cfg.set_value("affichage", "vegetation", i); cfg.save("user://reglages.cfg")
			for c in h.get_children():
				c.button_pressed = c == b)
		h.add_child(b)
	# heure de la journée (lumière, ciel, phares et fenêtres éclairées le soir)
	var lt := Label.new(); lt.text = "Heure de la journée"; lt.add_theme_font_size_override("font_size", 30); v.add_child(lt)
	var ht := HBoxContainer.new(); ht.add_theme_constant_override("separation", 16); v.add_child(ht)
	var main_node = get_parent()
	for i in main_node.TIMES.size():
		var b := Button.new()
		b.text = main_node.TIMES[i]
		b.toggle_mode = true
		b.button_pressed = i == main_node.time_of_day
		b.custom_minimum_size = Vector2(220, 70)
		b.add_theme_font_size_override("font_size", 30)
		b.pressed.connect(func():
			main_node.set_time(i)
			var cfg := ConfigFile.new(); cfg.load("user://reglages.cfg")
			cfg.set_value("affichage", "heure", i); cfg.save("user://reglages.cfg")
			for c in ht.get_children():
				c.button_pressed = c == b)
		ht.add_child(b)
	# météo (ciel, lumière, brume, pluie et route mouillée)
	var lw := Label.new(); lw.text = "Météo"; lw.add_theme_font_size_override("font_size", 30); v.add_child(lw)
	var hw := HBoxContainer.new(); hw.add_theme_constant_override("separation", 16); v.add_child(hw)
	for i in main_node.WEATHERS.size():
		var b := Button.new()
		b.text = main_node.WEATHERS[i]
		b.toggle_mode = true
		b.button_pressed = i == main_node.weather
		b.custom_minimum_size = Vector2(220, 70)
		b.add_theme_font_size_override("font_size", 30)
		b.pressed.connect(func():
			main_node.set_weather(i)
			var cfg := ConfigFile.new(); cfg.load("user://reglages.cfg")
			cfg.set_value("affichage", "meteo", i); cfg.save("user://reglages.cfg")
			for c in hw.get_children():
				c.button_pressed = c == b)
		hw.add_child(b)
	# son : volumes de l'ambiance, des effets (voiture, voix) et de la musique (radio), de 0 à 150 %
	var ls := Label.new(); ls.text = "Son"; ls.add_theme_font_size_override("font_size", 30); v.add_child(ls)
	var hs := HBoxContainer.new(); hs.add_theme_constant_override("separation", 24); v.add_child(hs)
	var AU := preload("res://scripts/audio.gd")
	AU.volume_db("ambiance")
	for cat in [["ambiance", "Ambiance"], ["effets", "Effets"], ["musique", "Musique"]]:
		var col := VBoxContainer.new(); col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cl := Label.new(); cl.add_theme_font_size_override("font_size", 24)
		col.add_child(cl)
		var sl := HSlider.new()
		sl.min_value = 0.0; sl.max_value = 1.5; sl.step = 0.05
		sl.value = float(AU.volumes[cat[0]])
		sl.custom_minimum_size = Vector2(220, 48)
		var upd := func(x: float):
			cl.text = "%s  %d %%" % [cat[1], int(round(x * 100.0))]
		upd.call(sl.value)
		sl.value_changed.connect(func(x: float):
			upd.call(x)
			AU.set_volume(cat[0], x))
		col.add_child(sl)
		hs.add_child(col)
	# voiture : sprite pixel art ou modèle 3D
	var lc := Label.new(); lc.text = "Voiture"; lc.add_theme_font_size_override("font_size", 30); v.add_child(lc)
	var hc := HBoxContainer.new(); hc.add_theme_constant_override("separation", 16); v.add_child(hc)
	var car_node = main_node.car
	for opt in [["sprite", "Sprite pixel art"], ["3d", "Modèle 3D"]]:
		var b := Button.new()
		b.text = opt[1]
		b.toggle_mode = true
		b.button_pressed = (opt[0] == "sprite") == car_node.sprite_mode
		b.custom_minimum_size = Vector2(340, 70)
		b.add_theme_font_size_override("font_size", 30)
		b.pressed.connect(func():
			car_node.set_sprite_mode(opt[0] == "sprite")
			var cfg := ConfigFile.new(); cfg.load("user://reglages.cfg")
			cfg.set_value("affichage", "voiture_v53", opt[0]); cfg.save("user://reglages.cfg")
			for c in hc.get_children():
				c.button_pressed = c == b)
		hc.add_child(b)
	var note := Label.new()
	note.text = "Moins de végétation = jeu plus fluide sur les téléphones modestes.\nVersion %s (mises à jour automatiques au lancement)" % str(Engine.get_meta("version_jeu", ProjectSettings.get_setting("application/config/version", "")))
	note.add_theme_font_size_override("font_size", 22); note.modulate = Color(1, 1, 1, 0.7); v.add_child(note)
	# éditeur de monde : champ de la formule magique (dictée au micro du clavier, ou saisie)
	var fm := Button.new(); fm.text = "Formule magique…"; fm.custom_minimum_size = Vector2(0, 64)
	fm.add_theme_font_size_override("font_size", 28)
	fm.pressed.connect(func():
		settings.queue_free(); settings = null
		_show_drive(true)
		if main_node.get("editeur"):
			main_node.editeur.open_formula())
	v.add_child(fm)
	# crédits (licences des modèles, sons et données)
	var cb := Button.new(); cb.text = "Crédits"; cb.custom_minimum_size = Vector2(0, 64)
	cb.add_theme_font_size_override("font_size", 28)
	var cr := Label.new()
	cr.text = CREDITS
	cr.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cr.custom_minimum_size = Vector2(900, 0)
	cr.add_theme_font_size_override("font_size", 20)
	cr.visible = false
	cb.pressed.connect(func():
		cr.visible = not cr.visible
		_fit_settings.call_deferred())
	v.add_child(cb)
	v.add_child(cr)
	# signaler un bug : ticket GitHub pré-rempli (version, appareil, position, journal) ouvert dans le navigateur
	var bb := Button.new(); bb.text = "Signaler un bug…"; bb.custom_minimum_size = Vector2(0, 64)
	bb.add_theme_font_size_override("font_size", 28)
	var bug_box := VBoxContainer.new(); bug_box.visible = false
	bug_box.add_theme_constant_override("separation", 8)
	var bug_txt := TextEdit.new()
	bug_txt.placeholder_text = "Que s'est-il passé ? (ce que vous faisiez, ce que vous avez vu)"
	bug_txt.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	bug_txt.custom_minimum_size = Vector2(900, 180)
	bug_txt.add_theme_font_size_override("font_size", 26)
	bug_box.add_child(bug_txt)
	var bug_send := Button.new(); bug_send.text = "Envoyer le signalement"; bug_send.custom_minimum_size = Vector2(0, 64)
	bug_send.add_theme_font_size_override("font_size", 28)
	bug_send.pressed.connect(func():
		send_bug_report(bug_txt.text)
		bug_txt.text = ""
		bug_box.visible = false
		_fit_settings.call_deferred())
	bug_box.add_child(bug_send)
	bb.pressed.connect(func():
		bug_box.visible = not bug_box.visible
		if bug_box.visible:
			bug_txt.grab_focus()
		_fit_settings.call_deferred())
	v.add_child(bb)
	v.add_child(bug_box)
	var close := Button.new(); close.text = "Fermer"; close.custom_minimum_size = Vector2(0, 76)
	close.add_theme_font_size_override("font_size", 32)
	close.pressed.connect(func():
		settings.queue_free(); settings = null
		_show_drive(true))
	v.add_child(close)
	add_child(settings)
	_fit_settings()

## Taille du menu des réglages : tout le contenu s'il tient, sinon 90 % de la hauteur de l'écran (le reste défile).
func _fit_settings() -> void:
	if not (settings and is_instance_valid(settings)):
		return
	var sc: ScrollContainer = settings.get_child(0)
	var v: Control = sc.get_child(0)
	var vs := get_viewport().get_visible_rect().size
	var need := v.get_combined_minimum_size()
	var pad := settings.get_combined_minimum_size() - sc.get_combined_minimum_size()
	sc.custom_minimum_size = Vector2(need.x + 24.0, minf(need.y, vs.y * 0.9 - pad.y))
	settings.reset_size()
	settings.position = (vs - settings.size) / 2

## Signalement de bug : ouvre un ticket GitHub pré-rempli dans le navigateur (il n'y a plus qu'à appuyer sur
## « Create »). Pas de jeton dans le jeu : un jeton d'écriture embarqué dans l'APK serait public.
func send_bug_report(text: String) -> void:
	var main_node = get_parent()
	var p: Vector3 = main_node.car.global_position
	var ver := str(Engine.get_meta("version_jeu", ProjectSettings.get_setting("application/config/version", "?")))
	var first := text.strip_edges().split("\n")[0]
	var title := "Bug : %s" % (first.left(70) if first != "" else "(sans description)")
	var body := "**Description** :\n%s\n\n| | |\n|---|---|\n" % (text.strip_edges() if text.strip_edges() != "" else "_(vide)_")
	body += "| Version | %s |\n" % ver
	body += "| Appareil | %s (%s %s) |\n" % [OS.get_model_name(), OS.get_name(), OS.get_version()]
	body += "| Rendu | %s, %s |\n" % [RenderingServer.get_video_adapter_name(), str(get_viewport().get_visible_rect().size)]
	body += "| Voiture | x %.1f, y %.1f, z %.1f |\n" % [p.x, p.y, p.z]
	body += "| Images/s | %d |\n" % Engine.get_frames_per_second()
	var st := "user://etat.txt"
	if FileAccess.file_exists(st):
		body += "\nÉtat :\n```\n%s\n```\n" % FileAccess.get_file_as_string(st).strip_edges().right(800)
	var lg := "user://logs/godot.log"
	if FileAccess.file_exists(lg):
		var lines := FileAccess.get_file_as_string(lg).split("\n")
		var tail := "\n".join(lines.slice(maxi(0, lines.size() - 40)))
		body += "\nJournal (fin) :\n```\n%s\n```\n" % tail.right(2500)
	body += "\n_Signalement envoyé depuis le jeu (⚙ > Signaler un bug)._"
	var url := "https://github.com/DisColow/rochetoirin-drive/issues/new?title=%s&labels=bug&body=%s" % [title.uri_encode(), body.uri_encode()]
	OS.shell_open(url)
	toast("Signalement prêt dans le navigateur :\nappuyez sur « Create » pour l'envoyer.", 4.0)

## Point de l'écran occupé par l'interface (boutons, GPS, compteur, carte, réglages) : pas de rotation de caméra.
func is_ui_point(p: Vector2) -> bool:
	if map.visible or (settings and is_instance_valid(settings)) or get_tree().paused:
		return true
	for b in buttons:
		if not b.visible:
			continue
		if b.shape is CircleShape2D:
			var r: float = b.shape.radius
			if p.distance_to(b.position + Vector2(r, r)) < r + 28.0:
				return true
		elif Rect2(b.position, b.shape.size).grow(20.0).has_point(p):
			return true
	# autres zones d'interface (bulle de conversation du taxi…)
	for n in get_tree().get_nodes_in_group("ui_zone"):
		if n is Control and n.is_visible_in_tree() and n.get_global_rect().grow(16.0).has_point(p):
			return true
		if n is TouchScreenButton and n.visible and Rect2(n.position, n.shape.size).grow(20.0).has_point(p):
			return true
	return Rect2(gps.position, gps.size).has_point(p) or Rect2(speed_panel.position, speed_panel.size).has_point(p)

func _open_map() -> void:
	if not map.visible:
		_show_drive(false)
		map.open()

var _panel_sb: StyleBox
func _panel(ci: CanvasItem, r: Rect2) -> void:
	if _panel_sb == null:
		_panel_sb = UI.panel()
	ci.draw_style_box(_panel_sb, r)

func _draw_pill() -> void:
	if _road_text == "":
		return
	var f := pill.get_theme_default_font()
	var w := maxf(f.get_string_size(_road_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x, f.get_string_size(_where_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x) + 56
	var r := Rect2(pill.size.x / 2 - w / 2, 0, w, 84)
	_panel(pill, r)
	pill.draw_string(f, Vector2(r.position.x, 38), _road_text, HORIZONTAL_ALIGNMENT_CENTER, w, 32, Color.WHITE)
	pill.draw_string(f, Vector2(r.position.x, 70), _where_text, HORIZONTAL_ALIGNMENT_CENTER, w, 19, Color(0.75, 0.77, 0.8))

## Compteur : panneau de limitation, puis afficheur à cristaux liquides (vitesse en 7 segments, segments éteints en
## filigrane comme sur les tableaux de bord numériques des années 80).
var _lcd: Font
func _draw_speed() -> void:
	var r := Rect2(Vector2.ZERO, speed_panel.size)
	_panel(speed_panel, r)
	var f := speed_panel.get_theme_default_font()
	var cy := r.size.y / 2
	if _limit > 0:
		var c := Vector2(62, cy)
		speed_panel.draw_circle(c, 36, Color.WHITE)
		speed_panel.draw_arc(c, 31, 0, TAU, 48, Color8(205, 30, 30), 9.0, true)
		var fs := 26 if _limit >= 100 else 30
		speed_panel.draw_string(f, c + Vector2(-40, fs * 0.36), str(_limit), HORIZONTAL_ALIGNMENT_CENTER, 80, fs, Color.BLACK)
	if _lcd == null:
		_lcd = UI.lcd_font()
	var kmh := int(round(car.kmh())) if car else 0
	var over := _limit > 0 and kmh > _limit + 5
	var win := Rect2(120, 14, r.size.x - 134, r.size.y - 28)
	speed_panel.draw_rect(win, Color8(14, 26, 20))
	speed_panel.draw_rect(Rect2(win.position, Vector2(win.size.x, 3)), Color8(4, 8, 6))
	var lit := Color8(255, 96, 70) if over else Color8(120, 255, 190)
	var fs2 := 50
	var x := win.position.x + 14
	var w := win.size.x - 116
	speed_panel.draw_string(_lcd, Vector2(x, cy + fs2 * 0.5), "888", HORIZONTAL_ALIGNMENT_RIGHT, w, fs2, Color(lit, 0.08))
	speed_panel.draw_string(_lcd, Vector2(x, cy + fs2 * 0.5), str(kmh), HORIZONTAL_ALIGNMENT_RIGHT, w, fs2, lit)
	speed_panel.draw_string(f, Vector2(win.end.x - 92, cy + 12), "km/h", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(lit, 0.75))

func _disc(r: int, col: Color, text_col: Color) -> ImageTexture:
	var img := Image.create(r * 2, r * 2, false, Image.FORMAT_RGBA8)
	for y in r * 2:
		for x in r * 2:
			var d := Vector2(x - r + 0.5, y - r + 0.5).length()
			var a := clampf(r - d, 0.0, 1.0)
			var edge := 1.0 if d > r - 4 else 0.0
			img.set_pixel(x, y, Color(col.r, col.g, col.b, col.a * a).lerp(Color(1, 1, 1, 0.55 * a), edge * 0.6))
	return ImageTexture.create_from_image(img)

## Boutons : les commandes de conduite restent de grands disques translucides ; les autres sont des boutons poussoirs
## de planche de bord en pixel art (build_ui.py), avec témoin orange pour la radio et les activités.
const DASH := {"camera": "camera", "replacer": "replacer", "carte": "carte", "reglages": "reglages",
	"activites": "activites", "radio": "radio"}
var _leds := {}                       # action -> [bouton, état du témoin]

func _add_button(action: String, label: String, idx: int) -> void:
	var big := idx < 4
	var b := TouchScreenButton.new()
	b.action = action
	b.passby_press = true
	var icon: String = DASH.get(action, "")
	if not big and icon != "" and ResourceLoader.exists("res://assets/ui/btn_%s.png" % icon):
		b.texture_normal = load("res://assets/ui/btn_%s.png" % icon)
		b.texture_pressed = load("res://assets/ui/btn_%s_p.png" % icon)
		var rs := RectangleShape2D.new(); rs.size = b.texture_normal.get_size()
		b.shape = rs; b.shape_centered = true
		if ResourceLoader.exists("res://assets/ui/btn_%s_on.png" % icon):
			_leds[action] = [b, false, icon]
		add_child(b)
		buttons.append(b)
		return
	var r := 92 if big else 46
	b.texture_normal = _disc(r, Color(0.08, 0.09, 0.1, 0.38), Color.WHITE)
	b.texture_pressed = _disc(r, Color(0.9, 0.9, 0.9, 0.45), Color.WHITE)
	var sh := CircleShape2D.new(); sh.radius = r
	b.shape = sh; b.shape_centered = true
	var l := Label.new()
	l.text = label
	l.add_theme_font_size_override("font_size", 40 if big else (30 if label.length() <= 3 else 22))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size = Vector2(r * 2, r * 2)
	l.modulate = Color(1, 1, 1, 0.85)
	b.add_child(l)
	add_child(b)
	buttons.append(b)

## Témoins des boutons : radio allumée, activité en cours.
func _update_leds() -> void:
	var m = get_parent()
	for action in _leds:
		var e: Array = _leds[action]
		var on := false
		if action == "radio":
			on = m.get("radio") != null and m.radio.station >= 0
		elif action == "activites":
			var acts := get_tree().get_nodes_in_group("activites")
			on = not acts.is_empty() and str(acts[0].mode) != ""
		if on != e[1]:
			e[1] = on
			var b: TouchScreenButton = e[0]
			b.texture_normal = load("res://assets/ui/btn_%s%s.png" % [e[2], "_on" if on else ""])
			b.texture_pressed = load("res://assets/ui/btn_%s_p%s.png" % [e[2], "_on" if on else ""])

func _layout() -> void:
	var s := get_viewport().get_visible_rect().size
	var gw := minf(s.x * 0.28, 540.0); var gh := minf(s.y * 0.36, 310.0)
	gps.position = Vector2(s.x - gw - 24, 24); gps.size = Vector2(gw, gh)
	speed_panel.position = Vector2(s.x - gw - 24, 24 + gh + 14); speed_panel.size = Vector2(gw, 96)
	pill.position = Vector2(0, 20); pill.size = Vector2(s.x, 90)
	var pos := [Vector2(60, s.y - 230), Vector2(290, s.y - 230), Vector2(s.x - 470, s.y - 230), Vector2(s.x - 240, s.y - 260),
		Vector2(146, 22), Vector2(270, 22), Vector2(22, 22), Vector2(394, 22), Vector2(518, 22), Vector2(642, 22)]
	for i in buttons.size():
		buttons[i].position = pos[i]

func _show_drive(on: bool) -> void:
	for b in buttons:
		b.visible = on
	gps.visible = on
	pill.visible = on
	speed_panel.visible = on
	get_tree().paused = not on

func _process(_dt: float) -> void:
	_update_leds()
	if _toast and _toast.visible:
		_toast_t -= _dt
		_toast.modulate.a = clampf(_toast_t / 0.6, 0.0, 1.0)
		if _toast_t <= 0.0:
			_toast.visible = false
	if Input.is_action_just_pressed("carte") and not map.visible:
		_open_map()
	if Input.is_action_just_pressed("reglages") and not map.visible:
		_open_settings()
	if car:
		speed_panel.queue_redraw()
		_name_t -= _dt
		if _name_t <= 0.0:
			_name_t = 0.3
			var p := car.global_position
			_road_text = names.road_at(p)
			_limit = names.speed_limit
			_where_text = "%s  ·  x %d  z %d" % [names.commune_at(p), int(round(p.x)), int(round(p.z))]
			pill.queue_redraw()
