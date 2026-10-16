## Fond de l'écran de démarrage et de chargement (#102) : illustration « Rochetoirin Drive » (le titre est dans l'image)
## couvrant tout l'écran, assombrie en bas pour que la barre, l'étape et les astuces restent lisibles.
## Partagé par boot.gd et voile_demarrage.gd ; renvoie le conteneur du bas où poser la barre et les textes.

static func poser(parent: Control) -> VBoxContainer:
	var fond := ColorRect.new()
	fond.color = Color(0.06, 0.07, 0.09)
	fond.set_anchors_preset(Control.PRESET_FULL_RECT)
	fond.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(fond)
	# image qui couvre l'écran, calée en haut : sur un écran allongé (20:9) on rogne la route en bas, pas le titre
	var img := TextureRect.new()
	img.texture = load("res://assets/logo/splash.jpg")
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_SCALE
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(img)
	var caler := func() -> void:
		var ecran: Vector2 = parent.size if parent.size.x > 0 else parent.get_viewport_rect().size
		var t: Vector2 = img.texture.get_size()
		var k: float = maxf(ecran.x / t.x, ecran.y / t.y)
		img.size = t * k
		img.position = Vector2((ecran.x - t.x * k) / 2.0, 0.0)
	parent.resized.connect(caler)
	parent.get_viewport().size_changed.connect(caler)
	caler.call_deferred()
	# dégradé noir sur le bas de l'écran (45 %)
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.0))
	g.set_color(1, Color(0, 0, 0, 0.82))
	g.add_point(0.35, Color(0, 0, 0, 0.45))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0); gt.fill_to = Vector2(0, 1)
	gt.width = 4; gt.height = 128
	var ombre := TextureRect.new()
	ombre.texture = gt
	ombre.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ombre.stretch_mode = TextureRect.STRETCH_SCALE
	ombre.anchor_left = 0; ombre.anchor_right = 1; ombre.anchor_top = 0.55; ombre.anchor_bottom = 1
	ombre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(ombre)
	var bas := VBoxContainer.new()
	bas.anchor_left = 0.5; bas.anchor_right = 0.5; bas.anchor_top = 1.0; bas.anchor_bottom = 1.0
	bas.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bas.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bas.offset_bottom = -36
	bas.alignment = BoxContainer.ALIGNMENT_END
	bas.add_theme_constant_override("separation", 12)
	bas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bas)
	return bas

## Texte lisible sur l'illustration : contour sombre.
static func lisible(l: Label) -> void:
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 8)
