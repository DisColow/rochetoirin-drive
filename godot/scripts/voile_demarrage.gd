## Voile de démarrage : fond, titre, barre de progression et étape en cours au-dessus de tout pendant que la scène du jeu se
## construit (posé par boot.gd juste avant de changer de scène) ; s'efface en fondu quand le jeu tourne avec fluidité
## (ou au bout de 8 s sur un téléphone lent). Script à part : boot.gd est libéré au changement de scène.
extends CanvasLayer

var _fluide := 0.0
var _present := 0.0
var _boite: Control
var _info: Label
var _barre: ProgressBar
const Chargement := preload("res://scripts/chargement.gd")

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
	# étape en cours et barre de progression réelle (v6.14, chargement.gd)
	_barre = ProgressBar.new()
	_barre.custom_minimum_size = Vector2(760, 30)
	_barre.max_value = 1.0
	_barre.show_percentage = false
	_barre.value = Chargement.DEPART
	v.add_child(_barre)
	_info = Label.new()
	_info.text = "Démarrage…"
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.add_theme_font_size_override("font_size", 28)
	_info.modulate = Color(1, 1, 1, 0.8)
	v.add_child(_info)

func _process(dt: float) -> void:
	if OS.get_cmdline_user_args().has("--capture-chargement"):
		_capture()
	# la barre suit la progression (sans jamais reculer) ; texte : étape en cours et pourcentage
	var p := Chargement.progres()
	_barre.value = maxf(_barre.value, p)
	if Chargement.fini:
		_info.text = "C'est parti !"
	elif Chargement.etape != "":
		_info.text = "%s… %d %%" % [Chargement.etape, mini(int(_barre.value * 100.0), 99)]
	var sc := get_tree().current_scene
	var la := sc != null and sc.name == "Main"
	_present = _present + minf(dt, 0.5) if la else 0.0
	if la and Chargement.fini and (dt < 0.1 or _present > 8.0):
		_fluide += minf(dt, 0.1)
	else:
		_fluide = 0.0
	if _fluide > 0.6:
		_boite.modulate.a = clampf(1.0 - (_fluide - 0.6) / 0.4, 0.0, 1.0)
		if _fluide > 1.0:
			queue_free()

## Appelé par main.gd quand le jeu est prêt (après ses premières images).
func fermer() -> void:
	if not is_inside_tree():
		return
	queue_free()

## Essai : -- --capture-chargement enregistre l'écran toutes les 2 s (user://shots/chargement_N.png).
var _cap_t := 0
var _cap_n := 0
func _capture() -> void:
	if Time.get_ticks_msec() < _cap_t:
		return
	_cap_t = Time.get_ticks_msec() + 2000
	DirAccess.make_dir_recursive_absolute("user://shots")
	get_viewport().get_texture().get_image().save_png("user://shots/chargement_%02d.png" % _cap_n)
	print("[chargement] capture %d : %s" % [_cap_n, _info.text])
	_cap_n += 1
