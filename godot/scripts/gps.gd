## Mini-GPS (en haut à droite, comme dans la première version) : carte tournée dans le sens de marche, zoom selon la
## vitesse, flèche du joueur, boussole. Toucher le GPS ouvre la grande carte.
extends Control

signal open_map

var car: VehicleBody3D
var data
var layers := []
var overlay: Control
var _ppm := 0.9
var _th := 0.0
var _xf := Transform2D.IDENTITY

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	data = load("res://scripts/map_data.gd").get_inst()
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	layers = data.make_layers(self)
	overlay = Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.draw.connect(_draw_overlay)
	add_child(overlay)

func _gui_input(e: InputEvent) -> void:
	if (e is InputEventScreenTouch and e.pressed) or (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT):
		open_map.emit()
		accept_event()

func _process(_dt: float) -> void:
	if not visible or car == null:
		return
	var p := Vector2(car.global_position.x, car.global_position.z)
	var f3 := car.global_transform.basis.z
	var f := Vector2(f3.x, f3.z)
	if f.length() < 0.01:
		f = Vector2(0, -1)
	# zoom selon la vitesse : 260 m de champ à l'arrêt, ~900 m à 130 km/h ; transition douce
	var want: float = size.y / (260.0 + car.kmh() * 5.0)
	_ppm = lerpf(_ppm, want, 0.05)
	var anchor := Vector2(size.x * 0.5, size.y * 0.66)
	_th = -PI / 2 - f.angle()
	var xf := Transform2D.IDENTITY.translated(-p).rotated(_th).scaled(Vector2(_ppm, _ppm)).translated(anchor)
	_xf = xf
	var r := size.length() / _ppm
	data.draw_layers(layers, xf, _ppm, Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), 1.0)
	overlay.queue_redraw()

func _draw_overlay() -> void:
	var anchor := Vector2(size.x * 0.5, size.y * 0.66)
	data.arrow(overlay, anchor, Vector2(0, -1), 17.0)
	var north := Vector2(0, -1).rotated(_th)
	var nc := Vector2(size.x - 34, 34)
	overlay.draw_circle(nc, 20, Color(0, 0, 0, 0.55))
	overlay.draw_string(get_theme_default_font(), nc + north * 11 - Vector2(8, -8), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color8(255, 90, 80))
	_draw_activity(anchor)
	overlay.draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.55), false, 3.0)

## Repères des activités : point visé (ou flèche au bord du GPS s'il est hors champ) et cercle de la chasse au lieu.
func _draw_activity(anchor: Vector2) -> void:
	var act = get_tree().get_first_node_in_group("activites")
	if act == null:
		return
	if not act.circle.is_empty():
		overlay.draw_arc(_xf * act.circle.c, act.circle.r * _ppm, 0, TAU, 96, Color(1.0, 0.45, 0.25, 0.95), 3.0, true)
	var inner := Rect2(Vector2(16, 16), size - Vector2(32, 32))
	for m in act.marks:
		if not m.get("gps", true):
			continue
		var sp: Vector2 = _xf * m.p
		if inner.has_point(sp):
			overlay.draw_circle(sp, 12, Color.BLACK)
			overlay.draw_circle(sp, 9, m.col)
		else:
			var d := (sp - anchor).normalized()
			var t := INF
			for k in 2:
				if absf(d[k]) > 1e-4:
					var lim := (inner.position[k] if d[k] < 0 else inner.end[k])
					t = minf(t, (lim - anchor[k]) / d[k])
			var e := anchor + d * t
			var n := Vector2(-d.y, d.x)
			overlay.draw_colored_polygon(PackedVector2Array([e + d * 12, e - d * 10 + n * 11, e - d * 10 - n * 11]), Color.BLACK)
			overlay.draw_colored_polygon(PackedVector2Array([e + d * 9, e - d * 7 + n * 8, e - d * 7 - n * 8]), m.col)
