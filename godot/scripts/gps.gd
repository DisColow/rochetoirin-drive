## Mini-GPS (en haut à droite, comme dans la première version) : carte tournée dans le sens de marche, zoom selon la
## vitesse, flèche du joueur, boussole. Toucher le GPS ouvre la grande carte.
## mini = true : même GPS en tout petit, dans l'écran central du cockpit pixel art (cockpit.gd, issue #29).
extends Control
const PerfMon := preload("res://scripts/perf_monitor.gd")

signal open_map

var car: Node3D                    # la voiture, ou le piéton quand on marche (#66)
var data
var layers := []
var overlay: Control
var _ppm := 0.9
var _th := 0.0
var _xf := Transform2D.IDENTITY
var _vu := false          # déjà affiché depuis la dernière fois qu'il était caché
var mini := false         # écran du cockpit : tailles réduites, pas de boussole ni de cadre, pas de toucher
var k := 1.0              # échelle des repères (flèche, tracés)

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	data = load("res://scripts/map_data.gd").get_inst()
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE if mini else Control.MOUSE_FILTER_STOP
	k = 0.24 if mini else 1.0
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
	var t0_perf := Time.get_ticks_usec()
	_process_corps(_dt)
	PerfMon.note("gps", Time.get_ticks_usec() - t0_perf)

func _process_corps(_dt: float) -> void:
	if not visible or car == null:
		_vu = false
		return
	var p := Vector2(car.global_position.x, car.global_position.z)
	var f3 := car.global_transform.basis.z
	var f := Vector2(f3.x, f3.z)
	if f.length() < 0.01:
		f = Vector2(0, -1)
	# zoom selon la vitesse : 260 m de champ à l'arrêt, ~900 m à 130 km/h ; transition douce
	var kmh: float = car.kmh() if car.has_method("kmh") else 0.0          # piéton (#66) : pas de compteur
	var want: float = size.y / ((150.0 + kmh * 2.5) if mini else (260.0 + kmh * 5.0))
	# premier affichage (ouverture de la vue cockpit) : zoom juste d'emblée, sans glissement (issue #34)
	_ppm = lerpf(_ppm, want, 0.05) if _vu else want
	_vu = true
	var anchor := Vector2(size.x * 0.5, size.y * 0.66)
	_th = -PI / 2 - f.angle()
	var xf := Transform2D.IDENTITY.translated(-p).rotated(_th).scaled(Vector2(_ppm, _ppm)).translated(anchor)
	_xf = xf
	var r := size.length() / _ppm
	data.draw_layers(layers, xf, _ppm, Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), 0.6 if mini else 1.0)
	overlay.queue_redraw()

func _draw_overlay() -> void:
	var anchor := Vector2(size.x * 0.5, size.y * 0.66)
	if mini:
		_draw_activity(anchor)
		data.arrow(overlay, anchor, Vector2(0, -1), 17.0 * k, Color8(255, 176, 32), 3.0 * k)
		return
	var north := Vector2(0, -1).rotated(_th)
	var nc := Vector2(size.x - 34, 34)
	overlay.draw_circle(nc, 20, Color(0, 0, 0, 0.55))
	overlay.draw_string(get_theme_default_font(), nc + north * 11 - Vector2(8, -8), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color8(255, 90, 80))
	_draw_activity(anchor)
	data.arrow(overlay, anchor, Vector2(0, -1), 17.0 * k, Color8(255, 176, 32), 3.0 * k)   # par-dessus l'itinéraire (#49)
	overlay.draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.55), false, 3.0)

## Repères des activités : point visé (ou flèche au bord du GPS s'il est hors champ) et cercle de la chasse au lieu.
func _draw_activity(anchor: Vector2) -> void:
	var act = get_tree().get_first_node_in_group("activites")
	if act == null:
		return
	if not act.circle.is_empty():
		overlay.draw_arc(_xf * act.circle.c, act.circle.r * _ppm, 0, TAU, 96, Color(1.0, 0.45, 0.25, 0.95), maxf(3.0 * k, 1.0), not mini)
	# itinéraire (taxi, v6.30) : trait bleu vif cerné de noir, comme un GPS de voiture
	var rt: PackedVector2Array = act.get("route_gps") if act.get("route_gps") != null else PackedVector2Array()
	if rt.size() > 1:
		var sc := PackedVector2Array()
		for q in rt:
			sc.append(_xf * q)
		overlay.draw_polyline(sc, Color(0, 0, 0, 0.8), maxf(9.0 * k, 2.0), not mini)
		overlay.draw_polyline(sc, Color(0.25, 0.65, 1.0), maxf(6.0 * k, 1.0), not mini)
	var inner := Rect2(Vector2(16, 16) * k, size - Vector2(32, 32) * k)
	for e in act.reperes_epreuves():                    # départs des épreuves (#59), seulement dans le cadre
		var ep: Vector2 = _xf * e.p
		if inner.has_point(ep):
			overlay.draw_circle(ep, 10 * k + 0.5, act.COUL_MEDAILLE.get(e.med, Color(0.15, 0.15, 0.17)))
			overlay.draw_circle(ep, 7 * k + 0.5, Color.WHITE)
			overlay.draw_rect(Rect2(ep - Vector2(4, 4) * k, Vector2(4, 4) * k), Color.BLACK)
			overlay.draw_rect(Rect2(ep, Vector2(4, 4) * k), Color.BLACK)
	for m in act.marks:
		if not m.get("gps", true):
			continue
		var sp: Vector2 = _xf * m.p
		if inner.has_point(sp):
			overlay.draw_circle(sp, 12 * k + 0.5, Color.BLACK)
			overlay.draw_circle(sp, 9 * k + 0.5, m.col)
		else:
			var d := (sp - anchor).normalized()
			var t := INF
			for ax in 2:
				if absf(d[ax]) > 1e-4:
					var lim := (inner.position[ax] if d[ax] < 0 else inner.end[ax])
					t = minf(t, (lim - anchor[ax]) / d[ax])
			var e := anchor + d * t
			var n := Vector2(-d.y, d.x)
			var kk := maxf(k, 0.3)
			overlay.draw_colored_polygon(PackedVector2Array([e + d * 12 * kk, e - d * 10 * kk + n * 11 * kk, e - d * 10 * kk - n * 11 * kk]), Color.BLACK)
			overlay.draw_colored_polygon(PackedVector2Array([e + d * 9 * kk, e - d * 7 * kk + n * 8 * kk, e - d * 7 * kk - n * 8 * kk]), m.col)
