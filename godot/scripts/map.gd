## Carte : photo aérienne + routes ; glisser pour déplacer, pincer (ou molette, boutons + −) pour zoomer,
## toucher un endroit pour s'y téléporter (point de route le plus proche, dans le sens de la voie).
extends Control

signal teleport(pos: Vector3, heading: float)
signal closed

var tex: Texture2D
var meta: Dictionary
var pts: PackedFloat32Array
var car: Node3D
var zoom := 1.0
var center := Vector2.ZERO          # en mètres (x, z)
var touches := {}
var moved := 0.0
var pinch_d := 0.0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	tex = load("res://assets/tex/map.jpg")
	meta = JSON.parse_string(FileAccess.get_file_as_string("res://world/map.json"))
	var b := FileAccess.get_file_as_bytes("res://world/teleport.bin")
	pts = b.to_float32_array()
	for spec in [["✕", Vector2(-110, 24), _close], ["+", Vector2(-110, 140), func(): _zoom_at(1.5, size / 2)],
			["−", Vector2(-110, 250), func(): _zoom_at(1 / 1.5, size / 2)], ["◎", Vector2(-110, 360), _recenter]]:
		var bt := Button.new()
		bt.text = spec[0]
		bt.add_theme_font_size_override("font_size", 46)
		bt.custom_minimum_size = Vector2(90, 90)
		bt.position = Vector2(size.x + spec[1].x, spec[1].y) if size.x > 0 else Vector2(0, spec[1].y)
		bt.pressed.connect(spec[2])
		bt.set_meta("dx", spec[1].x)
		add_child(bt)
	var hint := Label.new()
	hint.text = "Touchez un endroit pour vous y rendre"
	hint.add_theme_font_size_override("font_size", 30)
	hint.add_theme_color_override("font_outline_color", Color.BLACK)
	hint.add_theme_constant_override("outline_size", 8)
	hint.position = Vector2(30, 24)
	add_child(hint)
	resized.connect(_layout)

func _layout() -> void:
	for c in get_children():
		if c is Button:
			c.position.x = size.x + float(c.get_meta("dx"))

func open() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size
	visible = true
	_layout()
	_recenter()

func _recenter() -> void:
	center = Vector2(car.global_position.x, car.global_position.z)
	zoom = 0.6
	queue_redraw()

func _close() -> void:
	visible = false
	closed.emit()

# mètres par pixel écran
func _mpp() -> float:
	return float(meta.res) / zoom

func world_to_screen(p: Vector2) -> Vector2:
	return size / 2 + (p - center) / _mpp()

func screen_to_world(s: Vector2) -> Vector2:
	return center + (s - size / 2) * _mpp()

func _zoom_at(f: float, at: Vector2) -> void:
	var w := screen_to_world(at)
	var zmin := size.x * 0.9 / float(meta.w)            # toute la carte tient à l'écran
	zoom = clampf(zoom * f, zmin, 8.0)
	center = w - (at - size / 2) * _mpp()
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.06, 0.07))
	var tl := world_to_screen(Vector2(meta.x0, meta.z0))
	var sz := Vector2(meta.w, meta.h) * float(meta.res) / _mpp()
	draw_texture_rect(tex, Rect2(tl, sz), false)
	var f := get_theme_default_font()
	for name in meta.towns:
		var p := world_to_screen(Vector2(meta.towns[name][0], meta.towns[name][1]))
		draw_string_outline(f, p + Vector2(-60, 0), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, 8, Color.BLACK)
		draw_string(f, p + Vector2(-60, 0), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color.WHITE)
	# voiture : flèche rouge dans le sens de marche
	var c := world_to_screen(Vector2(car.global_position.x, car.global_position.z))
	var fwd: Vector3 = car.global_transform.basis.z
	var d := Vector2(fwd.x, fwd.z).normalized()
	var n := Vector2(-d.y, d.x)
	draw_colored_polygon(PackedVector2Array([c + d * 26, c - d * 16 + n * 15, c - d * 8, c - d * 16 - n * 15]), Color(0.9, 0.1, 0.1))
	draw_polyline(PackedVector2Array([c + d * 26, c - d * 16 + n * 15, c - d * 8, c - d * 16 - n * 15, c + d * 26]), Color.WHITE, 3)

func _gui_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed:
			touches[e.index] = e.position
			if touches.size() == 1:
				moved = 0.0
			elif touches.size() == 2:
				var v := touches.values()
				pinch_d = (v[0] - v[1]).length()
		else:
			if touches.size() == 1 and moved < 18.0:
				_pick(e.position)
			touches.erase(e.index)
			moved = 99.0 if touches.size() > 0 else moved
	elif e is InputEventScreenDrag:
		touches[e.index] = e.position
		if touches.size() == 1:
			center -= e.relative * _mpp()
			moved += e.relative.length()
		elif touches.size() == 2:
			var v := touches.values()
			var dd: float = (v[0] - v[1]).length()
			if pinch_d > 0:
				_zoom_at(dd / pinch_d, (v[0] + v[1]) / 2)
			pinch_d = dd
			moved = 99.0
		queue_redraw()
	elif e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(1.2, e.position)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(1 / 1.2, e.position)
	elif e is InputEventMagnifyGesture:
		_zoom_at(e.factor, e.position)

func _pick(s: Vector2) -> void:
	var w := screen_to_world(s)
	var best := -1
	var bd := 1e18
	for i in range(0, pts.size(), 4):
		var dx := pts[i] - w.x
		var dz := pts[i + 1] - w.y
		var d := dx * dx + dz * dz
		if d < bd:
			bd = d; best = i
	# pas de téléportation à plus de 60 pixels d'une route
	if best < 0 or sqrt(bd) / _mpp() > 60.0:
		return
	visible = false
	teleport.emit(Vector3(pts[best], pts[best + 2], pts[best + 1]), pts[best + 3])
	closed.emit()

func _process(_dt: float) -> void:
	if visible:
		queue_redraw()
