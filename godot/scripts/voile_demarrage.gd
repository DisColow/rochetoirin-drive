## Voile de démarrage : fond, titre, spinner et « Démarrage… » au-dessus de tout pendant que la scène du jeu se
## construit (posé par boot.gd juste avant de changer de scène) ; s'efface en fondu quand le jeu tourne avec fluidité
## (ou au bout de 8 s sur un téléphone lent). Script à part : boot.gd est libéré au changement de scène.
extends CanvasLayer

var _a := 0.0
var _fluide := 0.0
var _present := 0.0
var _boite: Control
var _roue: Control

func _ready() -> void:
	layer = 120
	name = "VoileDemarrage"
	process_mode = Node.PROCESS_MODE_ALWAYS          # le jeu peut être en pause (menu) : le voile s'efface quand même
	_boite = Control.new()
	_boite.set_anchors_preset(Control.PRESET_FULL_RECT)
	_boite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_boite)
	var fond := ColorRect.new()
	fond.color = Color(0.06, 0.07, 0.09)
	fond.set_anchors_preset(Control.PRESET_FULL_RECT)
	fond.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boite.add_child(fond)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boite.add_child(centre)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 22)
	centre.add_child(v)
	var t := Label.new()
	t.text = "Rochetoirin Simulator"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 56)
	v.add_child(t)
	_roue = Control.new()
	_roue.custom_minimum_size = Vector2(0, 84)
	_roue.draw.connect(_dessine)
	v.add_child(_roue)
	var i := Label.new()
	i.text = "Démarrage…"
	i.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	i.add_theme_font_size_override("font_size", 28)
	i.modulate = Color(1, 1, 1, 0.8)
	v.add_child(i)

func _process(dt: float) -> void:
	_a = fmod(_a + minf(dt, 0.1) * TAU * 0.9, TAU)
	_roue.queue_redraw()
	var sc := get_tree().current_scene
	var la := sc != null and sc.name == "Main"
	_present = _present + minf(dt, 0.5) if la else 0.0
	if la and (dt < 0.1 or _present > 8.0):
		_fluide += minf(dt, 0.1)
	else:
		_fluide = 0.0
	if _fluide > 0.6:
		_boite.modulate.a = clampf(1.0 - (_fluide - 0.6) / 0.4, 0.0, 1.0)
		if _fluide > 1.0:
			queue_free()

func _dessine() -> void:
	var c := _roue.size / 2.0
	var r := minf(_roue.size.y / 2.0, 36.0) - 4.0
	_roue.draw_arc(c, r, 0.0, TAU, 48, Color(1, 1, 1, 0.12), 7.0, true)
	for k in 12:
		var a0 := _a - k * 0.16
		_roue.draw_arc(c, r, a0 - 0.17, a0, 6, Color(1.0, 0.72, 0.28, 1.0 - k / 12.0), 7.0, true)

## Appelé par main.gd quand le jeu est prêt (après ses premières images).
func fermer() -> void:
	if not is_inside_tree():
		return
	queue_free()
