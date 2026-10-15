## Défilement d'une liste au doigt même en partant d'un bouton (même règle que les réglages, issue #38) : au-delà de
## 14 px de glissé, la liste suit le doigt et le bouton de départ n'est pas déclenché au lâcher.
## Usage : Defilement.new() ajouté comme enfant, `sc` = le ScrollContainer à faire défiler.
extends Node

var sc: ScrollContainer
var _glisse := 0.0
var _defile := false
var _appui := false
var _fin_defile := 0

func _input(e: InputEvent) -> void:
	if sc == null or not sc.is_visible_in_tree():
		_appui = false; _defile = false
		return
	var clic: bool = (e is InputEventScreenTouch) or (e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT)
	if clic and not e.pressed:
		if _defile:
			_fin_defile = Time.get_ticks_msec()
			_defile = false
		_appui = false
		if Time.get_ticks_msec() - _fin_defile < 150:
			sc.get_viewport().set_input_as_handled()          # le bouton de départ n'est pas déclenché
		return
	if clic:
		if e.pressed and sc.get_global_rect().has_point(e.position):
			_appui = true; _glisse = 0.0; _defile = false
		return
	if _appui and ((e is InputEventScreenDrag) or (e is InputEventMouseMotion)):
		# le doigt produit un glissé tactile ET une souris émulée : un seul des deux fait défiler
		var pilote: bool = e is InputEventScreenDrag or not Input.is_emulating_mouse_from_touch() or DisplayServer.get_name() != "android"
		if not _defile:
			if pilote:
				_glisse += e.relative.y
			if absf(_glisse) > 14.0:
				_defile = true
				sc.scroll_vertical -= int(_glisse)
		elif pilote:
			sc.scroll_vertical -= int(e.relative.y)
		if _defile:
			sc.get_viewport().set_input_as_handled()
