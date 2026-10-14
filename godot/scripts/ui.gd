## Habillage de l'interface façon tableau de bord des années 80 (pipeline/build_ui.py : thème du projet
## assets/ui/theme.tres, cadres et touches en pixel art, police Pixelify Sans, afficheur DSEG7 du compteur).
extends RefCounted

## Cadre des panneaux (celui du thème), marges intérieures au choix ; à défaut de thème, un cadre sombre simple.
static func panel(margin_x := -1.0, margin_y := -1.0) -> StyleBox:
	var th := ThemeDB.get_project_theme()
	var sb: StyleBox
	if th and th.has_stylebox("panel", "PanelContainer"):
		sb = th.get_stylebox("panel", "PanelContainer").duplicate()
	else:
		var f := StyleBoxFlat.new(); f.bg_color = Color(0.08, 0.09, 0.11, 0.92); f.set_corner_radius_all(14)
		f.content_margin_left = 34; f.content_margin_right = 34; f.content_margin_top = 18; f.content_margin_bottom = 18
		sb = f
	if margin_x >= 0.0:
		sb.content_margin_left = margin_x; sb.content_margin_right = margin_x
	if margin_y >= 0.0:
		sb.content_margin_top = margin_y; sb.content_margin_bottom = margin_y
	return sb

## Police de l'afficheur à cristaux liquides (chiffres en 7 segments), ou celle du thème à défaut.
static func lcd_font() -> Font:
	if ResourceLoader.exists("res://assets/ui/lcd.ttf"):
		return load("res://assets/ui/lcd.ttf")
	return ThemeDB.fallback_font

## Saisie au doigt (issue #39) : sur écran tactile, toucher le champ ouvre une fenêtre en haut de l'écran (au-dessus du
## clavier du téléphone) avec une grande zone de texte, « Valider » et une croix ✕ pour annuler. Le texte validé est
## recopié dans le champ d'origine (signal text_changed émis, et text_submitted pour un LineEdit).
static func saisie_tactile(champ: Control, titre: String) -> void:
	if not DisplayServer.is_touchscreen_available():
		return
	champ.focus_mode = Control.FOCUS_NONE                 # le champ d'origine n'ouvre plus le clavier lui-même
	champ.gui_input.connect(func(e: InputEvent):
		var tap: bool = (e is InputEventScreenTouch and not e.pressed) or (e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed)
		if tap:
			champ.accept_event()
			ouvrir_saisie(champ, titre))

static func ouvrir_saisie(champ: Control, titre: String) -> void:
	var tree := champ.get_tree()
	var cl := CanvasLayer.new()
	cl.layer = 120
	var fond := ColorRect.new()
	fond.color = Color(0, 0, 0, 0.55)
	fond.set_anchors_preset(Control.PRESET_FULL_RECT)
	cl.add_child(fond)
	var vs := tree.root.get_visible_rect().size
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", panel(28, 18))
	pc.position = Vector2(vs.x * 0.04, vs.y * 0.03)
	pc.custom_minimum_size = Vector2(vs.x * 0.92, 0)
	cl.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	pc.add_child(v)
	var h := HBoxContainer.new()
	v.add_child(h)
	var t := Label.new(); t.text = titre; t.add_theme_font_size_override("font_size", 32)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	var croix := Button.new(); croix.text = "✕"; croix.custom_minimum_size = Vector2(80, 70)
	croix.add_theme_font_size_override("font_size", 34)
	h.add_child(croix)
	var multi := champ is TextEdit
	var ed: Control
	if multi:
		var te := TextEdit.new()
		te.text = (champ as TextEdit).text
		te.placeholder_text = (champ as TextEdit).placeholder_text
		te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		te.custom_minimum_size = Vector2(0, vs.y * 0.24)
		ed = te
	else:
		var le := LineEdit.new()
		le.text = (champ as LineEdit).text
		le.placeholder_text = (champ as LineEdit).placeholder_text
		le.custom_minimum_size = Vector2(0, 76)
		ed = le
	ed.add_theme_font_size_override("font_size", 30)
	v.add_child(ed)
	var ok := Button.new(); ok.text = "Valider"; ok.custom_minimum_size = Vector2(260, 70)
	ok.add_theme_font_size_override("font_size", 30)
	ok.size_flags_horizontal = Control.SIZE_SHRINK_END
	v.add_child(ok)
	tree.root.add_child(cl)
	var fermer := func(garder: bool):
		if garder:
			if multi:
				(champ as TextEdit).text = (ed as TextEdit).text
				champ.emit_signal("text_changed")
			else:
				(champ as LineEdit).text = (ed as LineEdit).text
				champ.emit_signal("text_changed", (ed as LineEdit).text)
				champ.emit_signal("text_submitted", (ed as LineEdit).text)
		DisplayServer.virtual_keyboard_hide()
		cl.queue_free()
	croix.pressed.connect(fermer.bind(false))
	ok.pressed.connect(fermer.bind(true))
	if not multi:
		(ed as LineEdit).text_submitted.connect(func(_t): fermer.call(true))
	ed.grab_focus.call_deferred()
	if not multi:
		(ed as LineEdit).caret_column = (ed as LineEdit).text.length()

## Mise au point d'un champ : fenêtre de saisie sur écran tactile, sinon focus classique (clavier physique).
static func focus_saisie(champ: Control, titre: String) -> void:
	if DisplayServer.is_touchscreen_available():
		ouvrir_saisie(champ, titre)
	else:
		champ.grab_focus()
