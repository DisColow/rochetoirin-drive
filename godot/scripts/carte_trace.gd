## Carte d'un tracé de course (#112, menu des épreuves) : fond, bâtiments et routes de la carte (map_data.gd), tracé
## par les routes (itineraire.gd, étape par étape, calculé en arrière-plan ; ligne droite en attendant) et points de
## passage numérotés (A vert, 1, 2…, arrivée rouge).
extends Control

var points: Array = []               # Vector2 (x, z) : départ, étapes, arrivée
var _data
var _layers := []
var _over: Control
var _itin
static var _graphe
var _leg := 0
var _trace := PackedVector2Array()  # chemin par les routes, étapes déjà calculées
var _fini := false

func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _ready() -> void:
	_data = load("res://scripts/map_data.gd").get_inst()
	_layers = _data.make_layers(self)
	_over = Control.new()
	_over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_over.set_anchors_preset(Control.PRESET_FULL_RECT)
	_over.draw.connect(_dessus)
	add_child(_over)
	resized.connect(queue_redraw)

func montrer(pts: Array) -> void:
	points = pts
	_trace = PackedVector2Array()
	_leg = 0
	_fini = false
	if _itin == null:
		if _graphe == null:                     # graphe routier lu une seule fois (long à décoder)
			_graphe = preload("res://scripts/itineraire.gd").new()
		_itin = _graphe
	if points.size() >= 2:
		_itin.calculer(points[0], points[1])
	queue_redraw()

func _process(_dt: float) -> void:
	if _itin == null or _fini or points.size() < 2:
		return
	_itin.suivre()
	if not _itin.pret:
		return
	var r: PackedVector2Array = _itin.route
	_trace.append_array(r if r.size() >= 2 else PackedVector2Array([points[_leg], points[_leg + 1]]))
	_leg += 1
	if _leg >= points.size() - 1:
		_fini = true
	else:
		_itin.calculer(points[_leg], points[_leg + 1])
	_over.queue_redraw()

func _xf() -> Array:
	var r := Rect2(points[0], Vector2.ZERO)
	for p in points:
		r = r.expand(p)
	for p in _trace:
		r = r.expand(p)
	r = r.grow(maxf(r.size.x, r.size.y) * 0.12 + 60.0)
	var ppm := minf(size.x / maxf(r.size.x, 1.0), size.y / maxf(r.size.y, 1.0))
	var xf := Transform2D.IDENTITY.translated(-r.get_center()).scaled(Vector2(ppm, ppm)).translated(size / 2)
	return [xf, ppm, Rect2(r.get_center() - size / 2 / ppm, size / ppm)]

func _draw() -> void:
	if points.size() < 2 or size.x < 10.0:
		return
	var x := _xf()
	_data.draw_layers(_layers, x[0], x[1], x[2], 1.0)
	_over.queue_redraw()

func _dessus() -> void:
	if points.size() < 2:
		return
	var xf: Transform2D = _xf()[0]
	var ligne := PackedVector2Array()
	if _fini:
		for p in _trace:
			ligne.append(xf * p)
	else:
		for p in _trace:
			ligne.append(xf * p)
		for i in range(_leg, points.size()):
			ligne.append(xf * points[i])
	if ligne.size() >= 2:
		_over.draw_polyline(ligne, Color(0, 0, 0, 0.85), 9.0, true)
		_over.draw_polyline(ligne, Color(1.0, 0.82, 0.2), 5.0, true)
	var f := get_theme_default_font()
	for i in points.size():
		var sp: Vector2 = xf * points[i]
		var fin := i == points.size() - 1
		var col := Color(0.2, 0.85, 0.3) if i == 0 else (Color(0.95, 0.25, 0.2) if fin else Color(1, 0.8, 0.15))
		var tx := "A" if i == 0 else ("B" if fin else str(i))
		_over.draw_circle(sp, 17, Color.BLACK)
		_over.draw_circle(sp, 14, col)
		var w: float = f.get_string_size(tx, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
		_over.draw_string(f, sp + Vector2(-w * 0.5, 8), tx, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.BLACK)
