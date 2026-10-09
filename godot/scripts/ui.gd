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
