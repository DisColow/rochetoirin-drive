## Interface : compteur de vitesse ; commandes tactiles multipoint (◀ ▶ à gauche, frein et accélérateur à droite),
## boutons caméra et « remettre sur la route ». La manette et le clavier passent par les mêmes actions.
extends CanvasLayer

var car: VehicleBody3D
var speed: Label
var buttons := []
var map: Control
signal teleport(pos: Vector3, heading: float)

func _ready() -> void:
	speed = Label.new()
	speed.add_theme_font_size_override("font_size", 46)
	speed.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	speed.add_theme_constant_override("outline_size", 8)
	speed.position = Vector2(40, 24)
	add_child(speed)
	get_viewport().size_changed.connect(_layout)
	_add_button("gauche", "◀", 0)
	_add_button("droite", "▶", 1)
	_add_button("freiner", "FREIN", 2)
	_add_button("accelerer", "GAZ", 3)
	_add_button("camera", "CAM", 4)
	_add_button("replacer", "↺", 5)
	_add_button("carte", "CARTE", 6)
	map = preload("res://scripts/map.gd").new()
	map.car = car
	map.visible = false
	map.teleport.connect(func(p, h): teleport.emit(p, h))
	map.closed.connect(func(): _show_drive(true))
	add_child(map)
	_layout()

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
	var pos := [Vector2(60, s.y - 230), Vector2(290, s.y - 230), Vector2(s.x - 470, s.y - 230), Vector2(s.x - 240, s.y - 260),
		Vector2(s.x - 140, 30), Vector2(s.x - 260, 30), Vector2(s.x - 380, 30)]
	for i in buttons.size():
		buttons[i].position = pos[i]

func _show_drive(on: bool) -> void:
	for b in buttons:
		b.visible = on
	speed.visible = on
	get_tree().paused = not on

func _process(_dt: float) -> void:
	if Input.is_action_just_pressed("carte") and not map.visible:
		_show_drive(false)
		map.open()
	if car:
		speed.text = "%d km/h" % int(round(car.kmh()))
