## Sauvegarde de la partie (issue #51) : position et cap de la voiture, gardés dans user://partie.cfg toutes les 30 s
## et quand on quitte ou met le jeu en arrière-plan ; au lancement suivant, main.gd repart de là (sauf essais).
## L'heure, la météo et les réglages sont dans user://reglages.cfg (hud.gd), l'argent et les pièces du garage dans
## user://garage.cfg (garage.gd).
extends Node

const FICHIER := "user://partie.cfg"

var car: VehicleBody3D
var _t := 30.0

## Position et cap sauvegardés : [Vector3, cap en degrés], ou [] s'il n'y a pas de sauvegarde.
static func lire() -> Array:
	var c := ConfigFile.new()
	if c.load(FICHIER) != OK or not c.has_section_key("voiture", "position"):
		return []
	return [c.get_value("voiture", "position"), float(c.get_value("voiture", "cap", 0.0))]

func _process(dt: float) -> void:
	_t -= dt
	if _t <= 0.0:
		_t = 30.0
		sauver()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT]:
		sauver()

func sauver() -> void:
	if car == null or car.get("blown") or car.get("carried"):
		return
	# dernière position sûre (sur une route, roues au sol) plutôt que la position du moment (en l'air, dans un fossé…)
	var sur: Array = car.get("safe")
	var xf: Transform3D = sur[-1] if not sur.is_empty() else car.global_transform
	var z := xf.basis.z
	var c := ConfigFile.new()
	c.set_value("voiture", "position", xf.origin + Vector3(0, 0.3, 0))
	c.set_value("voiture", "cap", rad_to_deg(PI - atan2(z.x, z.z)))     # inverse de car.place()
	c.save(FICHIER)
