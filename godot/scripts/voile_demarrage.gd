## Voile de démarrage : fond, titre, barre de progression et étape en cours au-dessus de tout pendant que la scène du jeu se
## construit (posé par boot.gd juste avant de changer de scène) ; s'efface en fondu quand le jeu tourne avec fluidité
## (ou au bout de 8 s sur un téléphone lent). Script à part : boot.gd est libéré au changement de scène.
extends CanvasLayer

var _fluide := 0.0
var _present := 0.0
var _boite: Control
var _info: Label
var _barre: ProgressBar
# astuces et anecdotes (#96, façon Fallout 4) : une toutes les 7 s, en fondu, sous la barre
const ASTUCES := "res://data/astuces.json"
const DUREE_ASTUCE := 7.0
var _astuce_titre: Label
var _astuce: Label
var _liste: Array = []
var _t_astuce := 0.0
var _i_astuce := -1
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
	var sep := Control.new(); sep.custom_minimum_size = Vector2(0, 40)
	v.add_child(sep)
	_astuce_titre = Label.new()
	_astuce_titre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_astuce_titre.add_theme_font_size_override("font_size", 26)
	_astuce_titre.add_theme_color_override("font_color", Color(1.0, 0.78, 0.3))
	v.add_child(_astuce_titre)
	_astuce = Label.new()
	_astuce.custom_minimum_size = Vector2(900, 120)
	_astuce.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_astuce.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_astuce.add_theme_font_size_override("font_size", 30)
	v.add_child(_astuce)
	var d = JSON.parse_string(FileAccess.get_file_as_string(ASTUCES)) if FileAccess.file_exists(ASTUCES) else null
	if d is Dictionary:
		for tx in d.get("astuces", []):
			_liste.append(["ASTUCE", tx])
		for tx in d.get("anecdotes", []):
			_liste.append(["LE SAVIEZ-VOUS ?", tx])
	_liste.shuffle()
	_suivante()

func _suivante() -> void:
	if _liste.is_empty():
		return
	_i_astuce = (_i_astuce + 1) % _liste.size()
	_astuce_titre.text = _liste[_i_astuce][0]
	_astuce.text = _liste[_i_astuce][1]
	_t_astuce = 0.0

func _process(dt: float) -> void:
	if OS.get_cmdline_user_args().has("--capture-chargement"):
		_capture()
	# la barre suit la progression (sans jamais reculer) ; texte : étape en cours et pourcentage
	_t_astuce += minf(dt, 0.5)
	if _t_astuce > DUREE_ASTUCE:
		_suivante()
	var fa := clampf(minf(_t_astuce / 0.4, (DUREE_ASTUCE - _t_astuce) / 0.4), 0.0, 1.0)
	_astuce.modulate.a = fa; _astuce_titre.modulate.a = fa
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
