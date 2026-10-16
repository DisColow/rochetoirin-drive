## Grande carte (style GPS de la première version : occupation du sol, relief, routes en vecteurs, bâtiments au zoom) ;
## glisser pour déplacer, pincer (ou molette, boutons + −) pour zoomer, toucher un endroit pour s'y téléporter (point de
## route le plus proche, dans le sens de la voie).
extends Control
const PerfMon := preload("res://scripts/perf_monitor.gd")

signal teleport(pos: Vector3, heading: float)
signal closed
signal picked(w: Vector2)          # mode choix (activités) : endroit touché, en mètres (x, z)

const HINT := "Touchez un endroit pour vous y rendre"
var pick_mode := false             # activités : un toucher choisit un point au lieu de téléporter
var locked := false                # activité en cours : pas de téléportation
var hint: Label

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
	hint = Label.new()
	hint.text = HINT
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

func set_hint(t: String) -> void:
	hint.text = t

func open() -> void:
	if not pick_mode:
		hint.text = "Téléportation désactivée pendant l'activité (★ pour l'arrêter)" if locked else HINT
	position = Vector2.ZERO
	size = get_viewport_rect().size
	# (#93) doigts oubliés d'une ouverture précédente (zoom à deux doigts interrompu, carte fermée doigt posé) :
	# sans ce ménage, le doigt qui se lève après avoir touché la mini-carte téléportait tout de suite
	touches.clear()
	moved = 99.0
	visible = true
	_layout()
	_recenter()

func _recenter() -> void:
	center = Vector2(car.global_position.x, car.global_position.z)
	zoom = maxf(0.6, _zoom_min())
	_borner()
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
	zoom = clampf(zoom * f, _zoom_min(), 8.0)
	center = w - (at - size / 2) * _mpp()
	_borner()
	queue_redraw()

## Zoom le plus large : la carte remplit encore tout l'écran (#58 : pas de fond noir autour).
func _zoom_min() -> float:
	return maxf(size.x / float(meta.w), size.y / float(meta.h))

## Vue gardée dans l'emprise de la carte (#58 : on ne regarde pas en dehors).
func _borner() -> void:
	var demi := size / 2 * _mpp()
	var x0 := float(meta.x0); var z0 := float(meta.z0)
	var x1 := x0 + float(meta.w) * float(meta.res); var z1 := z0 + float(meta.h) * float(meta.res)
	center.x = clampf(center.x, x0 + demi.x, maxf(x0 + demi.x, x1 - demi.x))
	center.y = clampf(center.y, z0 + demi.y, maxf(z0 + demi.y, z1 - demi.y))

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
		# nom entier, centré sur la commune (issue #36 : largeur fixe de 160 px, les noms longs étaient tronqués)
		var w: float = f.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x
		overlay.draw_string_outline(f, p + Vector2(-w * 0.5, 0), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, 8, Color.BLACK)
		overlay.draw_string(f, p + Vector2(-w * 0.5, 0), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color.WHITE)
	var c := world_to_screen(Vector2(car.global_position.x, car.global_position.z))
	var fwd: Vector3 = car.global_transform.basis.z
	_draw_activity(f)
	data.arrow(overlay, c, Vector2(fwd.x, fwd.z), 22.0)          # par-dessus l'itinéraire (#49)
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
			# seulement un doigt posé DANS la carte ouverte (#93 : jamais le doigt qui a touché la mini-carte)
			if touches.has(e.index) and touches.size() == 1 and moved < 18.0:
				_pick(e.position)
			touches.erase(e.index)
			moved = 99.0 if touches.size() > 0 else moved
	elif e is InputEventScreenDrag:
		touches[e.index] = e.position
		if touches.size() == 1:
			center -= e.relative * _mpp()
			_borner()
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

## Repères des activités (points du tracé, client, destination) et cercle de la chasse au lieu.
func _draw_activity(f: Font) -> void:
	var act = get_tree().get_first_node_in_group("activites")
	if act == null:
		return
	if not act.circle.is_empty():
		var cc := world_to_screen(act.circle.c)
		var rr: float = act.circle.r / _mpp()
		overlay.draw_circle(cc, rr, Color(1.0, 0.35, 0.2, 0.12))
		overlay.draw_arc(cc, rr, 0, TAU, 96, Color(1.0, 0.45, 0.25, 0.95), 4.0, true)
	var rt: PackedVector2Array = act.get("route_gps") if act.get("route_gps") != null else PackedVector2Array()
	if rt.size() > 1:                       # itinéraire du taxi (v6.30)
		var sc := PackedVector2Array()
		for q in rt:
			sc.append(world_to_screen(q))
		overlay.draw_polyline(sc, Color(0, 0, 0, 0.8), 10.0, true)
		overlay.draw_polyline(sc, Color(0.25, 0.65, 1.0), 6.0, true)
	var prev := Vector2.INF
	for m in act.marks:
		var sp := world_to_screen(m.p)
		if act.join_marks and prev != Vector2.INF:
			overlay.draw_line(prev, sp, Color(1, 0.85, 0.2, 0.8), 4.0, true)
		prev = sp
	# départs des épreuves (#59) : drapeau à damier, cerclé de la couleur de la médaille gagnée
	for e in act.reperes_epreuves():
		var sp := world_to_screen(e.p)
		if not Rect2(Vector2.ZERO, size).grow(40).has_point(sp):
			continue
		var anneau: Color = act.COUL_MEDAILLE.get(e.med, Color(0.15, 0.15, 0.17))
		overlay.draw_circle(sp, 19, anneau)
		overlay.draw_circle(sp, 15, Color.WHITE)
		for i in 3:
			for j in 3:
				if (i + j) % 2 == 0:
					overlay.draw_rect(Rect2(sp + Vector2(-9 + i * 6, -9 + j * 6), Vector2(6, 6)), Color.BLACK)
		if zoom > 1.2:
			var we: float = f.get_string_size(e.nom, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
			overlay.draw_string_outline(f, sp + Vector2(-we * 0.5, 38), e.nom, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, 6, Color.BLACK)
			overlay.draw_string(f, sp + Vector2(-we * 0.5, 38), e.nom, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1.0, 0.9, 0.6))
	for m in act.marks:
		var sp := world_to_screen(m.p)
		overlay.draw_circle(sp, 17, Color.BLACK)
		overlay.draw_circle(sp, 14, m.col)
		var wm: float = f.get_string_size(m.txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
		overlay.draw_string_outline(f, sp + Vector2(-wm * 0.5, -24), m.txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, 7, Color.BLACK)
		overlay.draw_string(f, sp + Vector2(-wm * 0.5, -24), m.txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color.WHITE)

func _pick(s: Vector2) -> void:
	var w := screen_to_world(s)
	if pick_mode:
		picked.emit(w)
		queue_redraw()
		return
	if locked:
		hint.text = "Téléportation désactivée pendant l'activité (★ pour l'arrêter)"
		return
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
	var t0_perf := Time.get_ticks_usec()
	_process_corps(_dt)
	PerfMon.note("map", Time.get_ticks_usec() - t0_perf)

func _process_corps(_dt: float) -> void:
	pass
