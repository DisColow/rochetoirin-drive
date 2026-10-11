## Éditeur de monde : en roulant, on touche un objet du décor qui ne plaît pas (bâtiment, clôture, arbre, commerce…),
## puis on demande de le refaire d'après Street View ou on écrit (ou dicte) ce qui ne va pas. Chaque demande ouvre une
## issue GitHub pré-remplie dans le navigateur (position, coordonnées GPS, commune et rue, objet touché, caméra, lien
## Street View, ligne de capture --shots, version du jeu) : il ne reste qu'à appuyer sur « Create ».
## Ouverture : formule magique « Sésame, ouvre-toi » ; fermeture : « Hasta la vista, baby ». La formule se dit dans le
## champ « Formule magique » (micro du clavier du téléphone : dictée vocale) ou s'y tape ; ce champ s'ouvre par un
## appui long sur le nom de la rue en haut de l'écran, la touche F2, ou ⚙ > Formule magique.
extends CanvasLayer

const UI := preload("res://scripts/ui.gd")
const REPO := "https://github.com/DisColow/rochetoirin-drive/issues/new"
const LAT0 := 45.5855
const LON0 := 5.4160
const M_LAT := 111132.0

var main: Node
var hud: CanvasLayer
var active := false

var _formula: PanelContainer
var _formula_edit: LineEdit
var _banner: PanelContainer
var _panel: PanelContainer
var _title: Label
var _info: Label
var _main_row: HBoxContainer
var _remark_box: VBoxContainer
var _remark: TextEdit
var _pin: Sprite3D
var _sel := {}                    # objet sélectionné : catégorie, point, nœud…
var _press := {}                  # index -> [position, temps]
var _pill_hold := -1.0

func _ready() -> void:
	layer = 4
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not InputMap.has_action("formule"):
		InputMap.add_action("formule")
		var k := InputEventKey.new(); k.physical_keycode = KEY_F2
		InputMap.action_add_event("formule", k)
	# champ de la formule magique
	_formula = PanelContainer.new()
	_formula.add_theme_stylebox_override("panel", UI.panel(28, 16))
	_formula.add_to_group("ui_zone")
	var fv := VBoxContainer.new(); fv.add_theme_constant_override("separation", 8)
	_formula.add_child(fv)
	var fl := Label.new(); fl.text = "Formule magique (dites-la avec le micro du clavier, ou tapez-la)"
	fl.add_theme_font_size_override("font_size", 22); fl.add_theme_color_override("font_color", Color(1.0, 0.72, 0.28))
	fv.add_child(fl)
	_formula_edit = LineEdit.new()
	_formula_edit.placeholder_text = "…"
	_formula_edit.custom_minimum_size = Vector2(760, 64)
	_formula_edit.add_theme_font_size_override("font_size", 30)
	_formula_edit.text_changed.connect(_on_formula.bind(false))
	_formula_edit.text_submitted.connect(_on_formula.bind(true))
	fv.add_child(_formula_edit)
	var fb := Button.new(); fb.text = "Fermer"; fb.add_theme_font_size_override("font_size", 24)
	fb.custom_minimum_size = Vector2(0, 56); fb.pressed.connect(_close_formula)
	fv.add_child(fb)
	_formula.visible = false
	add_child(_formula)
	# bandeau du mode éditeur
	_banner = PanelContainer.new()
	_banner.add_theme_stylebox_override("panel", UI.panel(24, 10))
	_banner.add_to_group("ui_zone")
	var bh := HBoxContainer.new(); bh.add_theme_constant_override("separation", 16)
	_banner.add_child(bh)
	var bl := Label.new()
	bl.text = "ÉDITEUR DE MONDE · touchez un objet du décor"
	bl.add_theme_font_size_override("font_size", 24); bl.add_theme_color_override("font_color", Color(1.0, 0.72, 0.28))
	bh.add_child(bl)
	var bq := Button.new(); bq.text = "Quitter"; bq.add_theme_font_size_override("font_size", 22)
	bq.focus_mode = Control.FOCUS_NONE
	bq.pressed.connect(func(): set_active(false))
	bh.add_child(bq)
	_banner.visible = false
	add_child(_banner)
	# panneau de l'objet sélectionné
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UI.panel(30, 18))
	_panel.add_to_group("ui_zone")
	var pv := VBoxContainer.new(); pv.add_theme_constant_override("separation", 10)
	_panel.add_child(pv)
	_title = Label.new(); _title.add_theme_font_size_override("font_size", 28)
	pv.add_child(_title)
	_info = Label.new(); _info.add_theme_font_size_override("font_size", 19)
	_info.add_theme_color_override("font_color", Color(0.75, 0.73, 0.68))
	pv.add_child(_info)
	_main_row = HBoxContainer.new(); _main_row.add_theme_constant_override("separation", 10)
	pv.add_child(_main_row)
	_button(_main_row, "Générer depuis Street View", func(): _send("streetview", ""))
	_button(_main_row, "Écrire une remarque…", _open_remark)
	_button(_main_row, "Annuler", _deselect)
	_remark_box = VBoxContainer.new(); _remark_box.add_theme_constant_override("separation", 8)
	pv.add_child(_remark_box)
	_remark = TextEdit.new()
	_remark.placeholder_text = "Ce qui ne va pas, ce qu'il faudrait changer…"
	_remark.custom_minimum_size = Vector2(820, 130)
	_remark.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_remark.add_theme_font_size_override("font_size", 24)
	_remark_box.add_child(_remark)
	var rr := HBoxContainer.new(); rr.add_theme_constant_override("separation", 10)
	_remark_box.add_child(rr)
	_button(rr, "Envoyer", func(): _send("remarque", _remark.text.strip_edges()))
	_button(rr, "Street View + remarque", func(): _send("streetview", _remark.text.strip_edges()))
	_button(rr, "Retour", func(): _remark_box.visible = false; _main_row.visible = true)
	_panel.visible = false
	add_child(_panel)
	# repère de la sélection dans le monde
	_pin = Sprite3D.new()
	if ResourceLoader.exists("res://assets/ui/repere.png"):
		_pin.texture = load("res://assets/ui/repere.png")
	_pin.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_pin.no_depth_test = true
	_pin.shaded = false
	_pin.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_pin.pixel_size = 0.03
	_pin.offset = Vector2(0, 32)
	_pin.render_priority = 10
	_pin.visible = false

func _button(parent: Control, t: String, f: Callable) -> void:
	var b := Button.new(); b.text = t
	b.add_theme_font_size_override("font_size", 23)
	b.custom_minimum_size = Vector2(0, 62)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(f)
	parent.add_child(b)

# ---------------------------------------------------------------- formule magique
func open_formula() -> void:
	_formula.visible = true
	_formula_edit.text = ""
	_formula_edit.grab_focus()            # clavier virtuel (son micro permet de dicter)

func _close_formula() -> void:
	_formula.visible = false
	_formula_edit.release_focus()

static func _norm(t: String) -> String:
	var s := t.to_lower()
	for a in [["é", "e"], ["è", "e"], ["ê", "e"], ["à", "a"], ["â", "a"], ["î", "i"], ["ô", "o"], ["û", "u"], ["ç", "c"],
			["z", "s"], ["-", " "], [",", " "], [".", " "], ["!", " "], ["'", " "], ["’", " "]]:
		s = s.replace(a[0], a[1])
	while s.contains("  "):
		s = s.replace("  ", " ")
	return s.strip_edges()

## Reconnaissance tolérante (dictée approximative) : mots-clés, ou ressemblance avec la formule entière.
static func match_formula(t: String) -> String:
	var s := _norm(t)
	var nospace := s.replace(" ", "")
	if (s.contains("sesam") or s.contains("sesame")) and (s.contains("ouvre") or s.contains("ouvert")):
		return "ouvrir"
	if nospace.similarity("sesameouvretoi") > 0.72:
		return "ouvrir"
	if (s.contains("hasta") or s.contains("asta")) and s.contains("vista"):
		return "fermer"
	if nospace.similarity("hastalavistababy") > 0.7:
		return "fermer"
	return ""

func _on_formula(t: String, submitted: bool) -> void:
	var m := match_formula(t)
	if m == "ouvrir":
		_close_formula()
		set_active(true)
	elif m == "fermer":
		_close_formula()
		set_active(false)
	elif submitted:
		_close_formula()
		if hud:
			hud.toast("… rien ne se passe.", 1.8)

func set_active(on: bool) -> void:
	if on == active:
		return
	active = on
	_banner.visible = on
	if not on:
		_deselect()
	if hud:
		hud.toast("Éditeur de monde ouvert" if on else "Éditeur de monde fermé", 2.0)

# ---------------------------------------------------------------- sélection
func _input(e: InputEvent) -> void:
	if not (e is InputEventScreenTouch):
		return
	if e.pressed:
		_press[e.index] = [e.position, Time.get_ticks_msec()]
		if _pill_rect().has_point(e.position) and not _formula.visible:
			_pill_hold = 0.0
		return
	_pill_hold = -1.0
	if not _press.has(e.index):
		return
	var p0: Vector2 = _press[e.index][0]
	var dt := Time.get_ticks_msec() - int(_press[e.index][1])
	_press.erase(e.index)
	# toucher bref sans glisser, hors des boutons : sélection
	if active and not get_tree().paused and dt < 450 and p0.distance_to(e.position) < 24.0 \
			and not (hud and hud.is_ui_point(e.position)):
		_pick(e.position)

func _pill_rect() -> Rect2:
	var vs := get_viewport().get_visible_rect().size
	return Rect2(vs.x / 2 - 260, 10, 520, 96)

func _pick(sp: Vector2) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var o := cam.project_ray_origin(sp)
	var d := cam.project_ray_normal(sp)
	var q := PhysicsRayQueryParameters3D.create(o, o + d * 600.0)
	q.exclude = [main.car.get_rid()]
	var hit := cam.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	var col: Object = hit.collider
	var cat := _category(col)
	_sel = {"cat": cat[0], "src": cat[1], "p": hit.position, "node": str((col as Node).get_path()) if col is Node else "",
		"cam": cam.global_position, "dir": d}
	if _pin.get_parent() == null:
		main.add_child(_pin)
	_pin.global_position = hit.position
	_pin.visible = true
	var p: Vector3 = hit.position
	var names = hud.names
	var road: String = names.road_at(main.car.global_position)
	_sel["commune"] = names.commune_at(p)
	_sel["road"] = road
	_title.text = "%s · %s" % [cat[0], _sel.commune]
	_info.text = "%s  ·  x %d  z %d  ·  %s" % [road if road != "" else "hors route", int(round(p.x)), int(round(p.z)), _gps_text(p)]
	_remark_box.visible = false
	_main_row.visible = true
	_panel.visible = true

## Catégorie de l'objet touché, d'après le gestionnaire du décor qui le porte.
func _category(col: Object) -> Array:
	var managers := [["buildings", "Bâtiment"], ["shops", "Commerce"], ["fences", "Clôture, haie ou muret"],
		["props", "Objet (voiture garée, poubelle, tracteur…)"], ["sport", "Équipement sportif"],
		["animaux", "Pré et animaux"], ["pools", "Piscine"], ["autoroute", "Autoroute (glissière, panneau, péage…)"],
		["vegetation", "Arbre"], ["roads", "Route ou trottoir"], ["poles", "Poteau, pylône ou lampadaire"],
		["water", "Eau (rivière, étang)"]]
	if col is Node:
		var n: Node = col
		if n.has_meta("surface"):
			return ["Route ou trottoir (%s)" % n.get_meta("surface"), "roads"]
		while n != null and n != main:
			for m in managers:
				var mgr = main.get(m[0])
				if mgr != null and n == mgr:
					return [m[1], m[0]]
			n = n.get_parent()
	if main.terrain and col == main.terrain:
		return ["Relief ou sol", "terrain"]
	return ["Décor", "inconnu"]

func _deselect() -> void:
	_sel = {}
	_panel.visible = false
	_pin.visible = false

func _open_remark() -> void:
	_main_row.visible = false
	_remark_box.visible = true
	_remark.grab_focus()

# ---------------------------------------------------------------- issue GitHub
static func lonlat(p: Vector3) -> Vector2:
	var m_lon := 111320.0 * cos(deg_to_rad(LAT0))
	return Vector2(LON0 + p.x / m_lon, LAT0 - p.z / M_LAT)

func _gps_text(p: Vector3) -> String:
	var ll := lonlat(p)
	return "%.6f, %.6f" % [ll.y, ll.x]

func _send(kind: String, remark: String) -> void:
	if _sel.is_empty():
		return
	var p: Vector3 = _sel.p
	var c: Vector3 = _sel.cam
	var car_p: Vector3 = main.car.global_position
	var ll := lonlat(p)
	var cl := lonlat(car_p)
	var heading := fposmod(rad_to_deg(atan2(p.x - car_p.x, -(p.z - car_p.z))), 360.0)
	var sv := "https://www.google.com/maps/@?api=1&map_action=pano&viewpoint=%.6f,%.6f&heading=%d" % [cl.y, cl.x, int(heading)]
	var look := c + (p - c).normalized() * minf((p - c).length(), 60.0)
	var shot := '{"name": "editeur", "pos": [%.1f, %.1f, %.1f], "look": [%.1f, %.1f, %.1f], "fov": 62}' % [c.x, c.y, c.z, p.x, p.y, p.z]
	var what := "Refaire d'après Street View" if kind == "streetview" else "Remarque"
	var title := "Éditeur : %s — %s, %s" % [_sel.cat, _sel.commune, _sel.road if _sel.road != "" else "x %d z %d" % [int(p.x), int(p.z)]]
	var body := "**Demande** : %s\n" % what
	if remark != "":
		body += "**Remarque** : %s\n" % remark
	body += "\n| | |\n|---|---|\n"
	body += "| Objet | %s (`%s`) |\n" % [_sel.cat, _sel.src]
	body += "| Nœud touché | `%s` |\n" % _sel.node
	body += "| Point touché (jeu) | x %.1f, y %.1f, z %.1f |\n" % [p.x, p.y, p.z]
	body += "| GPS du point | %.6f, %.6f |\n" % [ll.y, ll.x]
	body += "| Commune, rue | %s, %s |\n" % [_sel.commune, _sel.road]
	body += "| Voiture | x %.1f, y %.1f, z %.1f |\n" % [car_p.x, car_p.y, car_p.z]
	body += "| Caméra | x %.1f, y %.1f, z %.1f (regard vers le point) |\n" % [c.x, c.y, c.z]
	body += "| Street View | %s |\n" % sv
	body += "| Version | %s |\n" % str(ProjectSettings.get_setting("application/config/version", "?"))
	body += "\nCapture de contrôle (`--shots`) :\n```json\n[%s]\n```\n" % shot
	body += "\n_Demande créée par l'éditeur de monde (« Sésame, ouvre-toi »)._"
	var url := "%s?title=%s&labels=%s&body=%s" % [REPO, title.uri_encode(), "editeur-monde".uri_encode(), body.uri_encode()]
	OS.shell_open(url)
	if hud:
		hud.toast("Demande prête dans le navigateur :\nappuyez sur « Create » pour l'envoyer.", 4.0)
	_remark.text = ""
	_deselect()

func _process(dt: float) -> void:
	var vs := get_viewport().get_visible_rect().size
	var paused := get_tree().paused
	_banner.visible = active and not paused
	_panel.visible = not _sel.is_empty() and not paused
	if Input.is_action_just_pressed("formule") and not _formula.visible:
		open_formula()
	if _pill_hold >= 0.0:
		_pill_hold += dt
		if _pill_hold > 0.7:
			_pill_hold = -1.0
			open_formula()
	if _formula.visible:
		_formula.reset_size()
		_formula.position = Vector2((vs.x - _formula.size.x) / 2.0, 120.0)
	if _banner.visible:
		_banner.reset_size()
		_banner.position = Vector2((vs.x - _banner.size.x) / 2.0, 116.0)
	if _panel.visible:
		_remark.custom_minimum_size.x = minf(820.0, vs.x - 120.0)
		_panel.reset_size()
		_panel.position = Vector2((vs.x - _panel.size.x) / 2.0, vs.y - _panel.size.y - 18.0)
	if _pin.visible:
		_pin.modulate.a = 0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.008)
