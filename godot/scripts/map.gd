## Grande carte (style GPS de la première version : occupation du sol, relief, routes en vecteurs, bâtiments au zoom) ;
## glisser pour déplacer, pincer (ou molette, boutons + −) pour zoomer, toucher un endroit pour s'y téléporter (point de
## route le plus proche, dans le sens de la voie).
extends Control

signal teleport(pos: Vector3, heading: float)
signal closed

var data
var layers := []
var overlay: Control
var meta: Dictionary
var pts: PackedFloat32Array
var car: Node3D
var zoom := 1.0
var center := Vector2.ZERO          # en mètres (x, z)
var touches := {}
var moved := 0.0
var pinch_d := 0.0

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	data = load("res://scripts/map_data.gd").get_inst()
	meta = data.meta
	layers = data.make_layers(self)
	overlay = Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.draw.connect(_draw_overlay)
	add_child(overlay)
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
	# fond, routes et bâtiments : calques (maillages) ; ici seulement la mise à jour de leur transformation
	var m := _mpp()
	var ppm := 1.0 / m
	var xf := Transform2D.IDENTITY.translated(-center).scaled(Vector2(ppm, ppm)).translated(size / 2)
	data.draw_layers(layers, xf, ppm, Rect2(center - size / 2 * m, size * m), 1.15)
	overlay.queue_redraw()

func _draw_overlay() -> void:
	var f := get_theme_default_font()
	for name in meta.towns:
		var p := world_to_screen(Vector2(meta.towns[name][0], meta.towns[name][1]))
		overlay.draw_string_outline(f, p + Vector2(-80, 0), name, HORIZONTAL_ALIGNMENT_CENTER, 160, 28, 8, Color.BLACK)
		overlay.draw_string(f, p + Vector2(-80, 0), name, HORIZONTAL_ALIGNMENT_CENTER, 160, 28, Color.WHITE)
	var c := world_to_screen(Vector2(car.global_position.x, car.global_position.z))
	var fwd: Vector3 = car.global_transform.basis.z
	data.arrow(overlay, c, Vector2(fwd.x, fwd.z), 22.0)
	overlay.draw_string(f, Vector2(size.x - 24, size.y - 18), "Données : © contributeurs OpenStreetMap, IGN (RGE ALTI, BD TOPO, RPG, LiDAR HD)",
		HORIZONTAL_ALIGNMENT_RIGHT, -1, 18, Color(0.7, 0.72, 0.75))

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
	pass
