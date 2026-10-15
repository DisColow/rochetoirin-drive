## Menus au clavier et à la manette (issue #62) : dès qu'on touche une touche ou un bouton de manette, le menu ouvert
## (activités, garage, réglages, carte, éditeur) devient navigable : flèches / croix directionnelle pour passer d'un
## bouton à l'autre, Entrée / A pour valider, Échap / B pour fermer, et les chiffres 1 à 9 pour toucher directement le
## n-ième bouton (pastille numérotée affichée à côté de chacun). Au doigt, rien ne change (pas de focus, pas de
## pastilles). Ajoute aussi les boutons de manette des commandes de jeu qui n'en avaient pas (TOUCHES).
extends Node

var main: Node
var physique := false                  # dernière saisie au clavier ou à la manette
var _menu: Control                     # menu préparé (pastilles posées)
var _pastilles: Array[Label] = []
var _ferme_image := -10

## Vrai pendant l'image où Échap / B / Start vient de fermer un menu (la même touche ne doit pas rouvrir les réglages).
func vient_de_fermer() -> bool:
	return Engine.get_process_frames() - _ferme_image <= 1

## Commandes de jeu : action -> [touche, bouton de manette (-1 : aucun)] ; lu aussi par le guide des touches (#63).
const TOUCHES := {
	"reglages": [KEY_ESCAPE, JOY_BUTTON_START],
	"activites": [KEY_T, JOY_BUTTON_RIGHT_SHOULDER],
	"radio": [KEY_N, JOY_BUTTON_LEFT_SHOULDER],
	"frein_main": [KEY_SPACE, JOY_BUTTON_A],
	"frein_parking": [KEY_P, JOY_BUTTON_DPAD_DOWN],
}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in TOUCHES:
		if not InputMap.has_action(a):
			InputMap.add_action(a, 0.5)
		var t: Array = TOUCHES[a]
		var deja_t := false
		var deja_j := false
		for e in InputMap.action_get_events(a):
			deja_t = deja_t or e is InputEventKey
			deja_j = deja_j or e is InputEventJoypadButton
		if not deja_t:
			var k := InputEventKey.new(); k.physical_keycode = t[0]
			InputMap.action_add_event(a, k)
		if not deja_j and int(t[1]) >= 0:
			var j := InputEventJoypadButton.new(); j.button_index = t[1]
			InputMap.action_add_event(a, j)

## Menu ouvert en ce moment (le plus au-dessus), ou null.
func menu_ouvert() -> Control:
	if main == null:
		return null
	var hud = main.get_node_or_null("HUD")
	var act = main.get("activities")
	for c in [hud.get("settings") if hud else null, act.get("_menu") if act else null]:
		if c is Control and is_instance_valid(c) and c.is_visible_in_tree():
			return c
	if hud and hud.get("map") and hud.map.visible:
		return hud.map
	return null

func _input(e: InputEvent) -> void:
	if e is InputEventScreenTouch or e is InputEventScreenDrag or e is InputEventMouse:
		if physique and not (e is InputEventMouseMotion):
			physique = false
			_effacer()
		return
	if not (e is InputEventKey or e is InputEventJoypadButton or e is InputEventJoypadMotion):
		return
	if e is InputEventJoypadMotion and absf(e.axis_value) < 0.5:
		return
	# #79 : on écrit dans un champ (clavier du téléphone ou clavier physique) : les touches sont pour lui, rien ne
	# doit lui reprendre le focus (le clavier du téléphone disparaissait à la première touche)
	var f0 := get_viewport().gui_get_focus_owner()
	if f0 is LineEdit or f0 is TextEdit:
		return
	physique = true
	var m := menu_ouvert()
	if m == null:
		_effacer()
		return
	if m != _menu:
		_preparer(m)
	if not e.is_pressed() or e.is_echo():
		return
	# Échap / B : fermer (le bouton « Fermer », « Retour » ou « ✕ » du menu)
	if e.is_action("ui_cancel") or e.is_action("reglages"):
		var b := _bouton_fermer(m)
		if b:
			_ferme_image = Engine.get_process_frames()
			b.pressed.emit()
			get_viewport().set_input_as_handled()
			return
	# chiffres : n-ième bouton
	if e is InputEventKey:
		var n := -1
		if e.physical_keycode >= KEY_1 and e.physical_keycode <= KEY_9:
			n = e.physical_keycode - KEY_1
		elif e.keycode >= KEY_KP_1 and e.keycode <= KEY_KP_9:
			n = e.keycode - KEY_KP_1
		var l := _boutons(m)
		if n >= 0 and n < l.size():
			l[n].grab_focus()
			_appuyer(l[n])
			get_viewport().set_input_as_handled()
			return
	# premier déplacement : le focus va au premier bouton
	var f := get_viewport().gui_get_focus_owner()
	if f == null or not m.is_ancestor_of(f):
		var l := _boutons(m)
		if not l.is_empty():
			l[0].grab_focus()
			get_viewport().set_input_as_handled()

func _process(_dt: float) -> void:
	if _menu and (not is_instance_valid(_menu) or not _menu.is_visible_in_tree()):
		_menu = null
		_pastilles.clear()
	elif physique and _menu:
		# le menu peut changer de contenu (sous-menus) : pastilles remises à jour
		var l := _boutons(_menu)
		if l.size() != _pastilles.size():
			_preparer(_menu)

## Boutons visibles du menu, dans l'ordre de lecture.
func _boutons(m: Control) -> Array[BaseButton]:
	var out: Array[BaseButton] = []
	for c in m.find_children("*", "BaseButton", true, false):
		var b := c as BaseButton
		if b.is_visible_in_tree() and not b.disabled:
			out.append(b)
	return out

func _bouton_fermer(m: Control) -> BaseButton:
	for b in _boutons(m):
		var t := (b as Button).text if b is Button else ""
		if t in ["Fermer", "Retour", "✕", "Annuler", "Quitter"] or t.begins_with("Fermer") or t.begins_with("← "):
			return b
	return null

func _appuyer(b: BaseButton) -> void:
	if b.toggle_mode:
		b.button_pressed = not b.button_pressed
	b.pressed.emit()

## Focus possible sur chaque bouton, défilement qui suit le focus, pastilles 1 à 9.
func _preparer(m: Control) -> void:
	_effacer()
	_menu = m
	for sc in m.find_children("*", "ScrollContainer", true, false):
		(sc as ScrollContainer).follow_focus = true
	var l := _boutons(m)
	for i in l.size():
		var b := l[i]
		b.focus_mode = Control.FOCUS_ALL
		if i < 9:
			var p := Label.new()
			p.text = str(i + 1)
			p.add_theme_font_size_override("font_size", 20)
			p.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
			p.add_theme_color_override("font_outline_color", Color.BLACK)
			p.add_theme_constant_override("outline_size", 6)
			p.mouse_filter = Control.MOUSE_FILTER_IGNORE
			p.position = Vector2(4, 0)
			b.add_child(p)
			_pastilles.append(p)

func _effacer() -> void:
	for p in _pastilles:
		if is_instance_valid(p):
			p.queue_free()
	_pastilles.clear()
	_menu = null
