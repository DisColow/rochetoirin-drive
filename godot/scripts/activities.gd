## Activités (bouton ★, touche T) :
##  - Course : on pose sur la carte le départ A, des points de passage et l'arrivée B, puis on court contre la montre
##    (portes lumineuses, 3-2-1-partez, temps intermédiaires) ; le tracé n'est pas enregistré (« Recommencer » rejoue
##    le dernier).
##  - Chasse au lieu : le joueur 1 choisit un lieu (sur la carte, dans la liste des lieux nommés, ou au hasard pour
##    jouer seul), passe l'appareil au joueur 2 qui doit le trouver au plus vite ; la carte et le GPS montrent une zone
##    qui contient le lieu et rétrécit avec le temps.
##  - Taxi : un client attend au bord d'une route ; on s'arrête à côté, il annonce sa destination (lieu réel nommé) ;
##    compteur, pourboire selon le temps et la conduite (chocs), courses enchaînées et gains cumulés.
## Les repères (marks) et le cercle (circle) sont dessinés par la carte (map.gd) et le GPS (gps.gd).
extends CanvasLayer

const FONT_BIG := 34
const CHECK_R := 16.0            # rayon des portes de la course (m)
const TAXI_STOP_R := 14.0        # rayon de prise en charge / de dépôt (m)

var main: Node
var car: VehicleBody3D
var hud: CanvasLayer
var map: Control
var pts := PackedFloat32Array()   # points de route : x, z, y, cap
var places: Array = []

var mode := ""                    # "", "course", "chasse", "taxi"
var marks: Array = []             # [{p: Vector2, col: Color, txt: String, gps: bool}]
var circle := {}                  # {c: Vector2, r: float}
var join_marks := false           # relier les repères (tracé de la course)

var _menu: Control
var _status: PanelContainer
var _status_l: Label
var _stop_btn: Button
var _bar: HBoxContainer
var _beacons: Array = []
var _bip: AudioStreamPlayer
var _t := 0.0

# course
var _route: Array = []            # indices de points de route (A, étapes…, B)
var _last_route: Array = []
var _best := INF
var _next := 0
var _count := 0.0
var _splits: Array = []

# chasse
var _target := Vector2.ZERO
var _target_name := ""
var _found_r := 40.0
var _c0 := Vector2.ZERO
var _r0 := 1000.0
var _dur := 300.0

# taxi
var _client: Node3D
var _cl_pos := Vector2.ZERO
var _dest := -1
var _dest_name := ""
var _fare_d := 0.0
var _expected := 60.0
var _shocks := 0
var _rides := 0
var _total := 0.0
var _stop_t := 0.0
var _prev_v := Vector3.ZERO
var _shock_cd := 0.0
var _phase := ""
var _talk: CanvasLayer             # conversations des clients (taxi_talk.gd)
var _status_t := 0.0            # > 0 : le message de fin s'efface au bout de ce temps


func _ready() -> void:
	add_to_group("activites")
	layer = 2
	pts = FileAccess.get_file_as_bytes("res://world/teleport.bin").to_float32_array()
	if FileAccess.file_exists("res://world/places.json"):
		places = JSON.parse_string(FileAccess.get_file_as_string("res://world/places.json"))
	_status = PanelContainer.new()
	_status.add_theme_stylebox_override("panel", preload("res://scripts/ui.gd").panel(30, 14))
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status.mouse_filter = Control.MOUSE_FILTER_PASS
	var sh := HBoxContainer.new(); sh.add_theme_constant_override("separation", 18)
	_status.add_child(sh)
	_status_l = Label.new(); _status_l.add_theme_font_size_override("font_size", 30)
	_status_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sh.add_child(_status_l)
	# arrêter l'activité en cours (taxi, course, chasse) d'un seul toucher
	_stop_btn = Button.new(); _stop_btn.text = "■ Arrêter"
	_stop_btn.add_theme_font_size_override("font_size", 26)
	_stop_btn.custom_minimum_size = Vector2(0, 64)
	_stop_btn.focus_mode = Control.FOCUS_NONE
	_stop_btn.add_to_group("ui_zone")
	_stop_btn.pressed.connect(func():
		_stop()
		hud.toast("Activité arrêtée.", 2.5))
	sh.add_child(_stop_btn)
	_status.visible = false
	add_child(_status)
	_bip = AudioStreamPlayer.new()
	if ResourceLoader.exists("res://assets/sfx/bip.wav"):
		_bip.stream = load("res://assets/sfx/bip.wav")
	add_child(_bip)
	if not InputMap.has_action("activites"):
		InputMap.add_action("activites")
		var k := InputEventKey.new(); k.physical_keycode = KEY_T
		InputMap.action_add_event("activites", k)
	map.picked.connect(_on_pick)
	_talk = preload("res://scripts/taxi_talk.gd").new()
	_talk.main = main
	_talk.hud = hud
	add_child(_talk)


# ================================================================ outils
func _vs() -> Vector2:
	return get_viewport().get_visible_rect().size

func _set_status(t: String) -> void:
	_status_l.text = t
	_stop_btn.visible = mode != ""
	_status.visible = t != ""
	_status.reset_size()
	_status.position = Vector2((_vs().x - _status.get_combined_minimum_size().x) / 2, 122)

func _fmt(t: float) -> String:
	var m := int(t / 60.0)
	var s := t - m * 60.0
	return ("%d min %04.1f s" % [m, s]).replace(".", ",") if m > 0 else ("%.1f s" % s).replace(".", ",")

func _euros(v: float) -> String:
	return ("%.2f €" % v).replace(".", ",")

func _nearest(w: Vector2) -> int:
	var best := -1; var bd := INF
	for i in range(0, pts.size(), 4):
		var dx := pts[i] - w.x; var dz := pts[i + 1] - w.y
		var d := dx * dx + dz * dz
		if d < bd:
			bd = d; best = i
	return best

func _rp(i: int) -> Vector2:
	return Vector2(pts[i], pts[i + 1])

func _r3(i: int) -> Vector3:
	return Vector3(pts[i], pts[i + 2], pts[i + 1])

func _car2() -> Vector2:
	return Vector2(car.global_position.x, car.global_position.z)

## Point de route proche de w dont le sens de marche va vers `toward` (départ d'une course, d'un dépôt…).
func _start_at(i: int, toward: Vector2) -> Array:
	var p := _rp(i)
	var best := i; var bs := -2.0
	for j in range(0, pts.size(), 4):
		if absf(pts[j] - p.x) > 12.0 or absf(pts[j + 1] - p.y) > 12.0:
			continue
		var h := deg_to_rad(pts[j + 3])
		var s := Vector2(sin(h), -cos(h)).dot((toward - _rp(j)).normalized())
		if s > bs:
			bs = s; best = j
	return [_r3(best), pts[best + 3]]

func _ground(x: float, z: float, fallback: float) -> float:
	var t = main.get("terrain")
	if t and t.data:
		var h: float = t.data.get_height(Vector3(x, 0, z))
		if not is_nan(h):
			return h
	return fallback

## Colonne de lumière (porte de course, client, destination) : cylindre additif qui s'efface vers le haut + anneau au sol.
func _beacon(p: Vector3, col: Color, r: float, h := 70.0) -> Node3D:
	# colonne de lumière qui traverse le sol (10 m dessous) : aucun écart visible entre le sol et la lumière,
	# même en pente ; sa base, la plus vive, forme le cercle lumineux au ras du sol
	const DEPTH := 10.0
	var root := Node3D.new()
	var sm := ShaderMaterial.new()
	sm.shader = Shader.new()
	sm.shader.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec3 col : source_color;
uniform float h = 70.0;
uniform float base = 0.0;
uniform float r = 10.0;
varying float y;
void vertex() { y = VERTEX.y + base; }
void fragment() {
	float edge = 0.06 + 0.94 * pow(1.0 - abs(dot(NORMAL, VIEW)), 2.2);   // bords lumineux, centre transparent
	float bands = 0.75 + 0.25 * sin(y * 0.86 - TIME * 4.0);
	float up = clamp(y / h, 0.0, 1.0);
	float foot = exp(-max(y, 0.0) * 3.5);          // anneau vif au ras du sol (et dessous), surtout vu de biais
	// caméra dans la colonne (on y entre en voiture) : elle s'efface, sinon sa paroi voile tout le paysage
	float d = length(CAMERA_POSITION_WORLD.xz - NODE_POSITION_WORLD.xz);
	float fade = smoothstep(r * 0.7, r * 1.6, d);
	ALBEDO = col * (edge * bands * (1.0 - up) * 0.9 + foot * (0.15 + 0.55 * edge)) * fade;
}
"""
	sm.set_shader_parameter("col", col)
	sm.set_shader_parameter("h", h)
	sm.set_shader_parameter("base", (h - DEPTH) / 2.0)
	sm.set_shader_parameter("r", r)
	var mi := MeshInstance3D.new()
	var cy := CylinderMesh.new(); cy.top_radius = r; cy.bottom_radius = r; cy.height = h + DEPTH
	cy.cap_top = false; cy.cap_bottom = false; cy.radial_segments = 48; cy.rings = 1
	mi.mesh = cy
	mi.material_override = sm
	mi.position = Vector3(0, (h - DEPTH) / 2.0, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	root.position = p
	main.add_child(root)
	_beacons.append(root)
	return root

func _clear_world() -> void:
	_status_t = 0.0
	for b in _beacons:
		if is_instance_valid(b):
			b.queue_free()
	_beacons.clear()
	if _client and is_instance_valid(_client):
		_client.queue_free()
	_client = null
	marks = []
	circle = {}
	join_marks = false

func _stop() -> void:
	_clear_world()
	_talk.stop()
	mode = ""
	_phase = ""
	map.locked = false
	_set_status("")

# ================================================================ menus
func _panel(title: String) -> VBoxContainer:
	_close_menu()
	hud._show_drive(false)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", preload("res://scripts/ui.gd").panel(44, 28))
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 14)
	pc.add_child(v)
	var t := Label.new(); t.text = title; t.add_theme_font_size_override("font_size", 44); v.add_child(t)
	add_child(pc)
	_menu = pc
	pc.resized.connect(func(): pc.position = (_vs() - pc.size) / 2)
	return v

func _text(v: Control, s: String, size := 26, wrap := true) -> Label:
	var l := Label.new(); l.text = s; l.add_theme_font_size_override("font_size", size)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(820, 0)
	v.add_child(l)
	return l

func _btn(v: Control, s: String, f: Callable, w := 0.0) -> Button:
	var b := Button.new(); b.text = s
	b.custom_minimum_size = Vector2(w, 78)
	b.add_theme_font_size_override("font_size", 31)
	b.pressed.connect(f)
	v.add_child(b)
	return b

func _close_menu(resume := false) -> void:
	if _menu and is_instance_valid(_menu):
		_menu.queue_free()
	_menu = null
	if resume:
		hud._show_drive(true)

func open_menu() -> void:
	var v := _panel("Activités")
	_btn(v, "Course : créer un tracé (départ, étapes facultatives, arrivée)", _course_setup)
	if not _last_route.is_empty():
		_btn(v, "Recommencer le dernier tracé" + ("" if _best == INF else "  (record " + _fmt(_best) + ")"), _course_again)
	_btn(v, "Chasse au lieu (un joueur cache, l'autre cherche)", _hunt_menu)
	_btn(v, "Taxi" + ("" if _rides == 0 else "  (%d courses, %s)" % [_rides, _euros(_total)]), _taxi_start)
	if mode != "":
		_btn(v, "Arrêter l'activité en cours", _stop_and_close)
	_btn(v, "Fermer", _resume)

func _resume() -> void:
	_close_menu(true)

func _stop_and_close() -> void:
	_stop()
	_close_menu(true)

func _course_again() -> void:
	_route = _last_route.duplicate()
	_course_start()

# ================================================================ choix sur la carte
var _pick_cb: Callable

func _pick_on_map(hint: String, cb: Callable, buttons: Array) -> void:
	_close_menu()
	_pick_cb = cb
	map.pick_mode = true
	if not map.visible:
		hud._show_drive(false)
		map.open()
	map.set_hint(hint)
	if _bar and is_instance_valid(_bar):
		_bar.queue_free()
	_bar = HBoxContainer.new()
	_bar.add_theme_constant_override("separation", 18)
	for b in buttons:
		var bt := Button.new(); bt.text = b[0]
		bt.custom_minimum_size = Vector2(0, 84)
		bt.add_theme_font_size_override("font_size", 30)
		bt.pressed.connect(b[1])
		bt.set_meta("id", b[0])
		_bar.add_child(bt)
	map.add_child(_bar)
	_bar.reset_size()
	_bar.position = Vector2(30, map.size.y - 110)

func _end_pick() -> void:
	map.pick_mode = false
	map.set_hint("Touchez un endroit pour vous y rendre")
	if _bar and is_instance_valid(_bar):
		_bar.queue_free()
	_bar = null

func _on_pick(w: Vector2) -> void:
	if _pick_cb.is_valid():
		_pick_cb.call(w)

# ================================================================ course
func _course_setup() -> void:
	_stop()
	_route = []
	_pick_on_map("Course : touchez le départ A, puis les étapes éventuelles, puis l'arrivée B", _course_pick,
		[["Effacer le dernier point", _course_undo], ["Lancer la course", _course_start], ["Annuler", _course_cancel]])
	_course_marks()

func _course_pick(w: Vector2) -> void:
	var i := _nearest(w)
	if i < 0 or _rp(i).distance_to(w) > 120.0:
		hud.toast("Touchez plus près d'une route")
		return
	_route.append(i)
	_course_marks()

func _course_undo() -> void:
	if not _route.is_empty():
		_route.pop_back()
	_course_marks()

func _course_cancel() -> void:
	_end_pick()
	_route = []
	marks = []
	join_marks = false
	map.visible = false
	hud._show_drive(true)

func _course_marks() -> void:
	marks = []
	join_marks = true
	for k in _route.size():
		var txt := "A" if k == 0 else ("B" if k == _route.size() - 1 else str(k))
		var col := Color(0.2, 0.85, 0.3) if k == 0 else (Color(0.95, 0.25, 0.2) if txt == "B" else Color(1, 0.8, 0.15))
		marks.append({p = _rp(_route[k]), col = col, txt = txt, gps = true})
	var n := _route.size()
	if map.pick_mode:
			map.set_hint(["Course : touchez le départ A", "Touchez l'arrivée B, ou des étapes (le dernier point posé est l'arrivée)"][n]
			if n < 2 else ("A → B : lancez la course, ou ajoutez des étapes (le dernier point posé est l'arrivée)" if n == 2 else
			"%d points : A, %d étape(s), B. Ajoutez des points ou lancez la course" % [n, n - 2]))
	if _bar and is_instance_valid(_bar):
		for b in _bar.get_children():
			if b.get_meta("id") == "Lancer la course":
				b.disabled = n < 2
	map.queue_redraw()

func _course_start() -> void:
	if _route.size() < 2:
		hud.toast("Il faut un départ et une arrivée")
		return
	_end_pick()
	_close_menu()
	_clear_world()
	_last_route = _route.duplicate()
	mode = "course"
	map.locked = true
	map.visible = false
	hud._show_drive(true)
	var s = _start_at(_route[0], _rp(_route[1]))
	hud.teleport.emit(s[0], s[1])
	_next = 1
	_count = 3.99
	_t = 0.0
	_splits = []
	_phase = "depart"
	_course_marks()
	_course_beacons()

func _course_beacons() -> void:
	for b in _beacons:
		if is_instance_valid(b):
			b.queue_free()
	_beacons.clear()
	for k in range(_next, mini(_next + 2, _route.size())):
		var fin := k == _route.size() - 1
		var col := Color(0.95, 0.25, 0.2) if fin else Color(1.0, 0.8, 0.15)
		if k > _next:
			col = col * 0.45
		_beacon(_r3(_route[k]), col, CHECK_R)
	for m in marks.size():
		marks[m].gps = m >= _next

func _course_process(dt: float) -> void:
	if _phase == "depart":
		_count -= dt
		car.hold(0.15)
		var n := int(ceil(_count))
		_set_status("Course : %s\n%s" % ["A → B" if _route.size() == 2 else "%d étape(s)" % (_route.size() - 2), str(n) if n >= 1 else "Partez !"])
		if _count <= 0.0:
			_phase = "course"
			_bip.play()
		return
	if _phase != "course":
		return
	_t += dt
	var target := _rp(_route[_next])
	var d := _car2().distance_to(target)
	var lab := "arrivée" if _next == _route.size() - 1 else "étape %d / %d" % [_next, _route.size() - 2]
	_set_status("%s\nprochain point : %s, %d m" % [_fmt(_t), lab, int(d)])
	if d < CHECK_R:
		_bip.play()
		_splits.append(_t)
		if _next == _route.size() - 1:
			_phase = "fini"
			var rec := _t < _best
			_best = minf(_best, _t)
			hud.toast("Arrivée ! %s%s" % [_fmt(_t), "  — record !" if rec else "  (record %s)" % _fmt(_best)], 6.0)
			_set_status("Arrivée en %s\n★ pour recommencer ou créer un autre tracé" % _fmt(_t))
			_status_t = 12.0
			_clear_world()
			mode = ""
			map.locked = false
			return
		hud.toast("Étape %d : %s" % [_next, _fmt(_t)], 2.0)
		_next += 1
		_course_beacons()

# ================================================================ chasse au lieu
func _hunt_menu() -> void:
	_stop()
	var v := _panel("Chasse au lieu")
	_text(v, "Joueur 1 : choisissez le lieu à faire trouver, sans que le joueur 2 regarde. Le joueur 2 le cherche ensuite, "
		+ "en partant d'ici ; la carte lui montre une zone qui contient le lieu et qui rétrécit avec le temps.")
	_btn(v, "Choisir un lieu nommé (gare, mairie, église…)", _hunt_list)
	_btn(v, "Choisir un endroit sur la carte", _hunt_map)
	_btn(v, "Lieu tiré au sort (jouer seul)", _hunt_random)
	_btn(v, "Retour", open_menu)

func _hunt_map() -> void:
	_pick_on_map("Joueur 1 : touchez l'endroit à faire trouver", _hunt_pick_map, [["Annuler", _course_cancel]])

func _hunt_pick_map(w: Vector2) -> void:
	var i := _nearest(w)
	if i < 0 or _rp(i).distance_to(w) > 120.0:
		hud.toast("Touchez plus près d'une route")
		return
	_end_pick()
	map.visible = false
	_hunt_confirm(_rp(i), "", 30.0)

func _hunt_list() -> void:
	var v := _panel("Lieu à faire trouver")
	var f := LineEdit.new(); f.placeholder_text = "Rechercher (gare, mairie, Saint-Chef…)"
	f.add_theme_font_size_override("font_size", 28); f.custom_minimum_size = Vector2(900, 70)
	v.add_child(f)
	var il := ItemList.new()
	il.custom_minimum_size = Vector2(900, minf(_vs().y * 0.5, 520))
	il.add_theme_font_size_override("font_size", 26)
	v.add_child(il)
	var fill := func(q: String):
		il.clear()
		q = q.to_lower()
		for k in places.size():
			var p = places[k]
			var s := "%s  —  %s" % [p.n, p.c]
			if q == "" or s.to_lower().contains(q):
				il.add_item(s)
				il.set_item_metadata(il.item_count - 1, k)
	fill.call("")
	f.text_changed.connect(fill)
	il.item_selected.connect(func(ix): _hunt_place(il.get_item_metadata(ix)))
	_btn(v, "Retour", _hunt_menu)

func _hunt_place(k: int) -> void:
	var p = places[k]
	_hunt_confirm(Vector2(p.x, p.z), "%s (%s)" % [p.n, p.c], 45.0)

func _hunt_random() -> void:
	var c := _car2()
	var pool := []
	for k in places.size():
		var d := c.distance_to(Vector2(places[k].x, places[k].z))
		if d > 700.0 and d < 6000.0:
			pool.append(k)
	if pool.is_empty():
		pool = range(places.size())
	var p = places[pool[randi() % pool.size()]]
	_target = Vector2(p.x, p.z); _target_name = "%s (%s)" % [p.n, p.c]; _found_r = 45.0
	_hunt_begin()

func _hunt_confirm(t: Vector2, name: String, r: float) -> void:
	_target = t; _target_name = name; _found_r = r
	var v := _panel("Lieu choisi")
	_text(v, ("À trouver : " + name) if name != "" else "Un endroit secret a été choisi (aucun indice que la zone sur la carte).")
	_text(v, "Passez l'appareil au joueur 2, puis appuyez sur « C'est parti ».")
	_btn(v, "C'est parti", _hunt_begin)
	_btn(v, "Annuler", _resume)

func _hunt_begin() -> void:
	_close_menu()
	_clear_world()
	mode = "chasse"
	map.locked = true
	var d := _car2().distance_to(_target)
	_r0 = clampf(d * 0.75, 450.0, 2600.0)
	_c0 = _target + Vector2.from_angle(randf() * TAU) * _r0 * randf_range(0.35, 0.75)
	_dur = clampf(d / 6.0, 150.0, 720.0)
	_t = 0.0
	_phase = "chasse"
	hud._show_drive(true)
	hud.toast("À toi de jouer ! La zone rétrécit avec le temps", 4.0)

func _hunt_process(dt: float) -> void:
	if _phase != "chasse":
		return
	_t += dt
	var k := clampf(_t / _dur, 0.0, 1.0)
	var r := lerpf(_r0, 60.0, k)
	circle = {c = _target + (_c0 - _target) * (r / _r0), r = r}
	var what := ("À trouver : " + _target_name) if _target_name != "" else "Endroit secret"
	_set_status("%s\n%s  ·  zone de %d m" % [what, _fmt(_t), int(r)])
	if _car2().distance_to(_target) < _found_r:
		_bip.play()
		_phase = "fini"
		circle = {}
		marks = [{p = _target, col = Color(0.2, 0.85, 0.3), txt = "Trouvé", gps = true}]
		_beacon(Vector3(_target.x, _ground(_target.x, _target.y, car.global_position.y), _target.y), Color(0.3, 1.0, 0.4), 10.0)
		hud.toast("Trouvé en %s !" % _fmt(_t), 7.0)
		_set_status("Trouvé en %s\n★ pour rejouer" % _fmt(_t))
		_status_t = 12.0
		mode = ""
		map.locked = false

# ================================================================ taxi
func _taxi_start() -> void:
	_close_menu()
	_clear_world()
	mode = "taxi"
	map.locked = true             # pas de téléportation pendant le taxi (■ Arrêter pour reprendre la main)
	hud._show_drive(true)
	_taxi_new_client()

func _taxi_new_client() -> void:
	_phase = "attente"
	marks = []
	for b in _beacons:
		if is_instance_valid(b):
			b.queue_free()
	_beacons.clear()
	var c := _car2()
	var pick := -1
	for k in 300:
		var i := (randi() % (pts.size() / 4)) * 4
		var d := _rp(i).distance_to(c)
		if d > 220.0 and d < 900.0:
			pick = i; break
	if pick < 0:
		pick = _nearest(c + Vector2(300, 0))
	var h := deg_to_rad(pts[pick + 3])
	var fwd := Vector2(sin(h), -cos(h))
	var side := Vector2(-fwd.y, fwd.x)          # à droite de la voie
	var p := _rp(pick) + side * 5.0
	_cl_pos = _rp(pick)
	var y := _ground(p.x, p.y, pts[pick + 2])
	if _client and is_instance_valid(_client):
		_client.queue_free()
	var path := "res://assets/clients/client%d.glb" % (randi() % 4)
	if ResourceLoader.exists(path):
		_client = (load(path) as PackedScene).instantiate()
	else:
		_client = Node3D.new()
	_client.position = Vector3(p.x, y, p.y)
	_client.rotation.y = atan2(-side.x, -side.y)          # face à la route (+Z du modèle vers la chaussée)
	main.add_child(_client)
	_beacon(Vector3(_cl_pos.x, pts[pick + 2], _cl_pos.y), Color(0.25, 0.75, 1.0), 6.0, 40.0)
	marks = [{p = _cl_pos, col = Color(0.25, 0.75, 1.0), txt = "Client", gps = true}]
	_shocks = 0
	_stop_t = 0.0

func _taxi_process(dt: float) -> void:
	var c := _car2()
	var slow: bool = car.kmh() < 10.0
	var head := "TAXI  ·  %d course(s)  ·  %s" % [_rides, _euros(_total)]
	if _phase == "attente":
		var d := c.distance_to(_cl_pos)
		_set_status("%s\nUn client attend à %d m (repère bleu)" % [head, int(d)])
		if d < TAXI_STOP_R and slow:
			_stop_t += dt
			if _stop_t > 0.6:
				_taxi_pickup()
		else:
			_stop_t = 0.0
	elif _phase == "course":
		_t += dt
		var dest := _rp(_dest)
		var d := c.distance_to(dest)
		var stars := _stars()
		_set_status("%s\n→ %s : %d m  ·  %s  ·  %s" % [head, _dest_name, int(d), _fmt(_t), "★".repeat(stars) + "☆".repeat(5 - stars)])
		if d < TAXI_STOP_R and slow:
			_stop_t += dt
			if _stop_t > 0.6:
				_taxi_drop()
		else:
			_stop_t = 0.0

func _stars() -> int:
	var late := maxf(0.0, _t / _expected - 1.0)
	return clampi(5 - _shocks - int(late * 4.0), 1, 5)

func _taxi_pickup() -> void:
	if _client and is_instance_valid(_client):
		_client.visible = false
	var c := _car2()
	var pool := []
	for k in places.size():
		var d := c.distance_to(Vector2(places[k].x, places[k].z))
		if d > 600.0 and d < 4500.0:
			pool.append(k)
	if pool.is_empty():
		pool = range(places.size())
	var p = places[pool[randi() % pool.size()]]
	_dest = _nearest(Vector2(p.x, p.z))
	_dest_name = p.n
	_fare_d = c.distance_to(_rp(_dest)) * 1.3
	_expected = _fare_d / 11.0 + 20.0
	_t = 0.0
	_shocks = 0
	_stop_t = 0.0
	_phase = "course"
	for b in _beacons:
		if is_instance_valid(b):
			b.queue_free()
	_beacons.clear()
	_beacon(_r3(_dest), Color(0.2, 0.95, 0.4), 8.0, 60.0)
	marks = [{p = _rp(_dest), col = Color(0.2, 0.95, 0.4), txt = "Dépôt", gps = true}]
	_bip.play()
	_talk.start_ride(hud.names.commune_at(car.global_position), p.n, p.c, str(p.get("k", "autre")))

func _taxi_drop() -> void:
	var fare := 3.5 + 1.6 * _fare_d / 1000.0
	var stars := _stars()
	var talk: Dictionary = _talk.end_ride(stars)
	# conversation : jusqu'à +24 % de pourboire si le client a apprécié, jusqu'à -18 % s'il a été agacé
	var tip: float = maxf(0.0, fare * ([0.0, 0.0, 0.05, 0.1, 0.15, 0.25][stars] + 0.06 * float(talk.sat)))
	_rides += 1
	_total += fare + tip
	_bip.play()
	var conv := ""
	if float(talk.sat) >= 1.5:
		conv = "\nLe client a aimé discuter avec vous."
	elif float(talk.sat) <= -1.5:
		conv = "\nLa conversation n'a pas plu au client."
	hud.toast("Course : %s + pourboire %s%s" % [_euros(fare), _euros(tip), conv], 5.0)
	if _client and is_instance_valid(_client):
		_client.queue_free()
	_client = null
	_phase = "pause"
	get_tree().create_timer(3.0).timeout.connect(func():
		if mode == "taxi":
			_taxi_new_client())

# ================================================================ boucle
func _process(dt: float) -> void:
	if Input.is_action_just_pressed("activites") and not map.visible and _menu == null:
		open_menu()
	if get_tree().paused or car == null:
		return
	if _status_t > 0.0:
		_status_t -= dt
		if _status_t <= 0.0 and mode == "":
			_set_status("")
	match mode:
		"course":
			_course_process(dt)
		"chasse":
			_hunt_process(dt)
		"taxi":
			_taxi_process(dt)

func _physics_process(dt: float) -> void:
	if get_tree().paused or car == null or mode != "taxi" or _phase != "course":
		return
	# choc : variation brutale de vitesse (collision), une fois par seconde au plus
	_shock_cd -= dt
	var v := car.linear_velocity
	if _shock_cd <= 0.0 and (v - _prev_v).length() > 5.5 and not car.carried:
		_shocks += 1
		_shock_cd = 1.0
		hud.toast("Aïe ! Le client n'apprécie pas", 1.5)
	_prev_v = v
