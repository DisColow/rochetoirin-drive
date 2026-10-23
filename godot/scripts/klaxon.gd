## Klaxon du joueur (v6.88, initiative de Claude) : bouton KLAXON au-dessus des flèches, touche H, clic du stick gauche
## (nav_physique.gd TOUCHES). « Tut-tuuut » de assets/sfx/klaxon.ogg (celui de la circulation), plus grave pour une
## voiture lourde, répété tant qu'on appuie ; les passants proches sursautent (pietons.gd klaxon()).
extends Node3D

var main: Node
var coups := 0                        # coups de klaxon (essais)
var _son: AudioStreamPlayer3D

func _ready() -> void:
	_son = AudioStreamPlayer3D.new()
	if ResourceLoader.exists("res://assets/sfx/klaxon.ogg"):
		_son.stream = load("res://assets/sfx/klaxon.ogg")
	_son.bus = "Voiture" if AudioServer.get_bus_index("Voiture") >= 0 else "Master"
	_son.unit_size = 12.0
	_son.max_distance = 250.0
	add_child(_son)

func _process(_dt: float) -> void:
	var car: VehicleBody3D = main.get("car") if main else null
	if car == null or get_tree().paused:
		return
	global_position = car.global_position
	var pied = main.get("pied")
	if pied and bool(pied.get("actif")):
		return
	if Input.is_action_pressed("klaxon") and not _son.playing:
		klaxonner()

## Un coup de klaxon (aussi pour les essais).
func klaxonner() -> void:
	var car: VehicleBody3D = main.car
	_son.pitch_scale = clampf(1.12 - (car.mass - 1200.0) / 8000.0, 0.82, 1.15)
	_son.play()
	coups += 1
	var pie = main.get("pietons")
	if pie and pie.ok:
		pie.klaxon(car.global_position, car.global_transform.basis.z)
