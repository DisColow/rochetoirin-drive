## Accueil du premier lancement (v6.86, initiative de Claude) : pour un nouveau joueur (aucune partie sauvegardée au
## lancement), une fenêtre dit où aller : la carrière, le jeu libre, les commandes. Montrée une seule fois
## (reglages.cfg : accueil/vu), jamais pendant les essais. main.gd : `nouveau_joueur` relevé au tout début de _ready,
## montrer() appelé quand le voile de chargement se ferme. Capture d'essai : `-- --accueil-test`.
extends RefCounted

const UI := preload("res://scripts/ui.gd")
const REGLAGES := "user://reglages.cfg"

static func deja_vu() -> bool:
	var c := ConfigFile.new()
	c.load(REGLAGES)
	return bool(c.get_value("accueil", "vu", false))

static func noter_vu() -> void:
	var c := ConfigFile.new()
	c.load(REGLAGES)
	c.set_value("accueil", "vu", true)
	c.save(REGLAGES)

static func montrer(main: Node) -> void:
	var hud: CanvasLayer = main.get_node_or_null("HUD")
	if hud == null:
		return
	noter_vu()
	var fond := ColorRect.new()
	fond.color = Color(0, 0, 0, 0.55)
	fond.set_anchors_preset(Control.PRESET_FULL_RECT)
	fond.mouse_filter = Control.MOUSE_FILTER_STOP
	fond.add_to_group("ui_zone")
	hud.add_child(fond)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UI.panel(40, 26))
	fond.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	pc.add_child(v)
	var t := Label.new()
	t.text = "Bienvenue dans le Nord-Isère !"
	t.add_theme_font_size_override("font_size", 40)
	t.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	v.add_child(t)
	var vs: Vector2 = main.get_viewport().get_visible_rect().size
	for ligne in [
		"Tu es au volant d'un pick-up, sur les vraies routes de Rochetoirin, La Tour-du-Pin, Bourgoin-Jallieu et des villages autour.",
		"Le bouton au drapeau et à la clé (en haut) ouvre les activités : la carrière en 4 chapitres, les épreuves chronométrées, le taxi, la chasse au lieu, le garage, les succès.",
		"Touche la mini-carte pour voir la carte et t'y téléporter. Le bouton rouge te remet sur la route.",
		"Tout se casse (ou presque) : clôtures, poteaux, petits arbres… et gare au KA-BOOM contre un mur !"]:
		var l := Label.new()
		l.text = ligne
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(minf(1100.0, vs.x - 160.0), 0)
		l.add_theme_font_size_override("font_size", 26)
		v.add_child(l)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(h)
	var fermer := func(): fond.queue_free()
	for b in [["Commencer la carrière", func():
				fermer.call()
				var act = main.get("activities")
				if act:
					act.open_menu(6)],
			["Rouler librement", fermer],
			["Les commandes", func():
				fermer.call()
				if hud.has_method("_open_settings"):
					hud._open_settings()]]:
		var bt := Button.new()
		bt.text = b[0]
		bt.custom_minimum_size = Vector2(300, 76)
		bt.add_theme_font_size_override("font_size", 28)
		bt.pressed.connect(b[1])
		h.add_child(bt)
	pc.reset_size()
	pc.position = (vs - pc.size) / 2.0
