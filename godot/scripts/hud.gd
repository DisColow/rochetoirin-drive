## Interface (disposition de la première version) : mini-GPS en haut à droite avec le panneau de vitesse (limitation
## et compteur) dessous, nom de la rue dans une pastille en haut au centre (commune et coordonnées en petit),
## boutons carte / caméra / remise sur la route en haut à gauche ; commandes tactiles multipoint (◀ ▶ à gauche, frein
## et accélérateur à droite). La manette et le clavier passent par les mêmes actions.
extends CanvasLayer

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
	map = preload("res://scripts/map.gd").new()
	map.car = car
	map.visible = false
	map.teleport.connect(func(p, h): teleport.emit(p, h))
	map.closed.connect(func(): _show_drive(true))
	add_child(map)
	_layout()

var settings: Control

const CREDITS := """Gardien : « Goku (Rigged & Animated) » par Kari (sketchfab.com/3d-models), licence CC BY 4.0.
Pluie et orage : Sound Effect by Premankur Adhikary from Pixabay.
Arbres : modèles Sketchfab (licences CC BY / CC0, auteurs listés dans le dépôt).
Textures : Poly Haven et ambientCG (CC0).
Données : © les contributeurs d'OpenStreetMap (ODbL) ; IGN (BD TOPO, RGE ALTI, LiDAR HD, BD ORTHO, Licence Ouverte Etalab).
Voix du gardien : Piper, voix française « tom ».
Modèles des commerces, équipements, haies, maisons et sprite de la voiture : faits avec Blender pour le jeu."""

## Message bref au centre de l'écran (péage…), qui s'efface tout seul.
var _toast: PanelContainer
var _toast_t := 0.0
func toast(text: String, secs := 3.5) -> void:
	if _toast == null:
		_toast = PanelContainer.new()
		var sb := StyleBoxFlat.new(); sb.bg_color = Color(0.06, 0.12, 0.3, 0.88); sb.set_corner_radius_all(18)
		sb.content_margin_left = 34; sb.content_margin_right = 34; sb.content_margin_top = 14; sb.content_margin_bottom = 14
		sb.border_color = Color(1, 1, 1, 0.8); sb.set_border_width_all(3)
		_toast.add_theme_stylebox_override("panel", sb)
		_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var l := Label.new(); l.add_theme_font_size_override("font_size", 34)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_toast.add_child(l)
		add_child(_toast)
	(_toast.get_child(0) as Label).text = text
	_toast.reset_size()
	var vs := get_viewport().get_visible_rect().size
	_toast.position = Vector2((vs.x - _toast.get_combined_minimum_size().x) / 2, vs.y * 0.22)
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
	var sb := StyleBoxFlat.new(); sb.bg_color = Color(0.08, 0.09, 0.11, 0.94); sb.set_corner_radius_all(22)
	sb.content_margin_left = 40; sb.content_margin_right = 40; sb.content_margin_top = 22; sb.content_margin_bottom = 22
	settings.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 12)
	settings.add_child(v)
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
			cfg.set_value("affichage", "voiture", opt[0]); cfg.save("user://reglages.cfg")
			for c in hc.get_children():
				c.button_pressed = c == b)
		hc.add_child(b)
	var note := Label.new(); note.text = "Moins de végétation = jeu plus fluide sur les téléphones modestes."
	note.add_theme_font_size_override("font_size", 22); note.modulate = Color(1, 1, 1, 0.7); v.add_child(note)
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
		settings.reset_size()
		settings.position = (get_viewport().get_visible_rect().size - settings.get_combined_minimum_size()) / 2)
	v.add_child(cb)
	v.add_child(cr)
	var close := Button.new(); close.text = "Fermer"; close.custom_minimum_size = Vector2(0, 76)
	close.add_theme_font_size_override("font_size", 32)
	close.pressed.connect(func():
		settings.queue_free(); settings = null
		_show_drive(true))
	v.add_child(close)
	add_child(settings)
	settings.position = (get_viewport().get_visible_rect().size - settings.get_combined_minimum_size()) / 2

## Point de l'écran occupé par l'interface (boutons, GPS, compteur, carte, réglages) : pas de rotation de caméra.
func is_ui_point(p: Vector2) -> bool:
	if map.visible or (settings and is_instance_valid(settings)):
		return true
	for b in buttons:
		if not b.visible:
			continue
		var r: float = b.shape.radius
		if p.distance_to(b.position + Vector2(r, r)) < r + 28.0:
			return true
	return Rect2(gps.position, gps.size).has_point(p) or Rect2(speed_panel.position, speed_panel.size).has_point(p)

func _open_map() -> void:
	if not map.visible:
		_show_drive(false)
		map.open()

func _panel(ci: CanvasItem, r: Rect2, radius: float, col := Color(0.08, 0.09, 0.11, 0.78)) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(radius))
	sb.anti_aliasing = true
	ci.draw_style_box(sb, r)

func _draw_pill() -> void:
	if _road_text == "":
		return
	var f := pill.get_theme_default_font()
	var w := maxf(f.get_string_size(_road_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x, f.get_string_size(_where_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x) + 56
	var r := Rect2(pill.size.x / 2 - w / 2, 0, w, 84)
	_panel(pill, r, 30)
	pill.draw_string(f, Vector2(r.position.x, 38), _road_text, HORIZONTAL_ALIGNMENT_CENTER, w, 32, Color.WHITE)
	pill.draw_string(f, Vector2(r.position.x, 70), _where_text, HORIZONTAL_ALIGNMENT_CENTER, w, 19, Color(0.75, 0.77, 0.8))

func _draw_speed() -> void:
	var r := Rect2(Vector2.ZERO, speed_panel.size)
	_panel(speed_panel, r, 18)
	var f := speed_panel.get_theme_default_font()
	var cy := r.size.y / 2
	if _limit > 0:
		var c := Vector2(58, cy)
		speed_panel.draw_circle(c, 38, Color.WHITE)
		speed_panel.draw_arc(c, 33, 0, TAU, 48, Color8(205, 30, 30), 9.0, true)
		var fs := 28 if _limit >= 100 else 32
		speed_panel.draw_string(f, c + Vector2(-40, fs * 0.36), str(_limit), HORIZONTAL_ALIGNMENT_CENTER, 80, fs, Color.BLACK)
	var kmh := int(round(car.kmh())) if car else 0
	var over := _limit > 0 and kmh > _limit + 5
	speed_panel.draw_string(f, Vector2(120, cy + 22), str(kmh), HORIZONTAL_ALIGNMENT_RIGHT, 200, 62,
		Color8(255, 90, 80) if over else Color.WHITE)
	speed_panel.draw_string(f, Vector2(330, cy + 20), "km/h", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.75, 0.77, 0.8))

func _disc(r: int, col: Color, text_col: Color) -> ImageTexture:
	var img := Image.create(r * 2, r * 2, false, Image.FORMAT_RGBA8)
	for y in r * 2:
		for x in r * 2:
			var d := Vector2(x - r + 0.5, y - r + 0.5).length()
			var a := clampf(r - d, 0.0, 1.0)
			var edge := 1.0 if d > r - 4 else 0.0
			img.set_pixel(x, y, Color(col.r, col.g, col.b, col.a * a).lerp(Color(1, 1, 1, 0.55 * a), edge * 0.6))
	return ImageTexture.create_from_image(img)

func _add_button(action: String, label: String, idx: int) -> void:
	var big := idx < 4
	var r := 92 if big else 46
	var b := TouchScreenButton.new()
	b.texture_normal = _disc(r, Color(0.08, 0.09, 0.1, 0.38), Color.WHITE)
	b.texture_pressed = _disc(r, Color(0.9, 0.9, 0.9, 0.45), Color.WHITE)
	b.action = action
	b.passby_press = true
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

func _layout() -> void:
	var s := get_viewport().get_visible_rect().size
	var gw := minf(s.x * 0.28, 540.0); var gh := minf(s.y * 0.36, 310.0)
	gps.position = Vector2(s.x - gw - 24, 24); gps.size = Vector2(gw, gh)
	speed_panel.position = Vector2(s.x - gw - 24, 24 + gh + 14); speed_panel.size = Vector2(gw, 96)
	pill.position = Vector2(0, 20); pill.size = Vector2(s.x, 90)
	var pos := [Vector2(60, s.y - 230), Vector2(290, s.y - 230), Vector2(s.x - 470, s.y - 230), Vector2(s.x - 240, s.y - 260),
		Vector2(150, 24), Vector2(270, 24), Vector2(30, 24), Vector2(390, 24)]
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
