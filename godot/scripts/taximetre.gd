## Compteur de taxi (issue #44) façon taximètre américain : boîtier noir, gros chiffres rouges à sept segments (police
## LCD du compteur de vitesse), voyant « LIBRE » entre deux courses, distance et attente comptées. Tarif (#127 : trois
## fois le tarif réel, sinon il fallait des heures de taxi pour une voiture) : prise en charge 10,50 €, 4,80 € par km
## parcouru, 1,80 € par minute d'attente (sous 10 km/h). activities.gd le fait tourner pendant la course et encaisse
## son montant à l'arrivée. v6.93 : tarif de nuit (« TARIF 2 », main.tarif_nuit) : le kilomètre à 7,20 € ; le
## compteur ajoute chaque mètre au tarif du moment (la nuit peut tomber pendant la course).
extends Control
const UI := preload("res://scripts/ui.gd")

const PRISE := 10.5
const PAR_KM := 4.8
const PAR_MIN := 1.8
const PAR_KM_NUIT := 7.2

var montant := 0.0
var distance := 0.0          # m
var attente := 0.0           # s
var en_course := false
var nuit := false            # tarif de nuit (activities.gd, d'après main.tarif_nuit)
var _lcd: Font
var _clign := 0.0
var _l_chiffres := 240.0

func _ready() -> void:
	_lcd = UI.lcd_font()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# largeur mesurée sur les chiffres (#52 : le « € » chevauchait le montant)
	_l_chiffres = _lcd.get_string_size("888.88", HORIZONTAL_ALIGNMENT_LEFT, -1, 58).x
	custom_minimum_size = Vector2(maxf(330.0, 22.0 + _l_chiffres + 56.0), 150)
	size = custom_minimum_size

func demarrer() -> void:
	montant = PRISE; distance = 0.0; attente = 0.0; en_course = true
	queue_redraw()

func arreter() -> void:
	en_course = false
	queue_redraw()

## À chaque image de la course : distance parcourue (m) et vitesse (km/h).
func compter(dt: float, metres: float, kmh: float) -> void:
	if not en_course:
		return
	distance += metres
	montant += (PAR_KM_NUIT if nuit else PAR_KM) * metres / 1000.0
	if kmh < 10.0:
		attente += dt
		montant += PAR_MIN * dt / 60.0
	queue_redraw()

func _process(dt: float) -> void:
	_clign += dt
	if not en_course and visible:
		queue_redraw()

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(0.05, 0.05, 0.06))
	draw_rect(r, Color(0.32, 0.32, 0.35), false, 4.0)
	draw_rect(r.grow(-6), Color(0.12, 0.12, 0.13), false, 2.0)
	var f := get_theme_default_font()
	var rouge := Color(1.0, 0.16, 0.1)
	var eteint := Color(0.25, 0.04, 0.03)
	# afficheur principal : fond des segments éteints puis montant
	var txt := ("%6.2f" % minf(montant, 999.99)) if en_course else "  0.00"
	draw_string(_lcd, Vector2(22, 96), "888.88", HORIZONTAL_ALIGNMENT_LEFT, -1, 58, eteint)
	draw_string(_lcd, Vector2(22, 96), txt.replace(" ", "!"), HORIZONTAL_ALIGNMENT_LEFT, -1, 58, rouge)
	draw_string(f, Vector2(22.0 + _l_chiffres + 10.0, 94), "€", HORIZONTAL_ALIGNMENT_LEFT, -1, 40, rouge)
	draw_string(f, Vector2(14, 22), "TAXI  ·  TARIF 2  ·  NUIT" if nuit else "TAXI  ·  TARIF 1", HORIZONTAL_ALIGNMENT_LEFT, -1, 18,
		Color(0.55, 0.7, 1.0) if nuit else Color(0.75, 0.75, 0.78))
	if en_course:
		var att := int(attente)
		draw_string(f, Vector2(14, 136), "%.1f km   attente %d:%02d" % [distance / 1000.0, att / 60, att % 60], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1.0, 0.55, 0.2))
	elif fmod(_clign, 1.2) < 0.8:
		draw_string(f, Vector2(14, 136), "LIBRE", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(0.25, 0.95, 0.35))
