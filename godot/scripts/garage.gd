## Garage (issue #43) : catalogue des améliorations, porte-monnaie et pièces achetées, gardés d'une partie à l'autre
## (user://garage.cfg). L'argent vient des activités (taxi : prix de la course et pourboire ; course et chasse au lieu :
## primes, activities.gd). Chaque choix d'une rubrique s'achète une fois, puis se monte ou se démonte gratuitement.
## Les effets sur la voiture sont appliqués par tuning.gd.
extends Node

signal change                       # argent, achat ou pièce montée

const FICHIER := "user://garage.cfg"
const DEPART := 300.0               # argent de départ (de quoi s'offrir une première pièce)

# rubrique : [nom affiché, famille, [[choix, prix en €], …]] ; le choix 0 est celui d'origine (gratuit)
const CATALOGUE := {
	"moteur": ["Moteur", "Technique", [["D'origine (300 kW)", 0], ["Stage 1 : +15 %", 400], ["Stage 2 : +30 %", 900], ["Stage 3 : +50 %", 1800]]],
	"boite": ["Boîte de vitesses", "Technique", [["D'origine", 0], ["Rapports courts", 350], ["Boîte course", 800]]],
	"suspension": ["Suspension", "Technique", [["D'origine", 0], ["Rabaissée (-7 cm)", 450], ["Rehaussée (+10 cm)", 450]]],
	"freins": ["Freins", "Technique", [["D'origine", 0], ["Freins sport", 300], ["Freins course", 700]]],
	"pneus": ["Pneus", "Technique", [["D'origine (tout-terrain)", 0], ["Route sport", 350], ["Semi-slicks", 800]]],
	# nitro (#98) : jauge qui se vide en boostant, se recharge en roulant et en dérapant
	"nitro": ["Nitro", "Technique", [["Aucun", 0], ["Nitro 1 (4 s, +6 m/s²)", 900], ["Nitro 2 (5 s, +8,5 m/s²)", 1700], ["Nitro 3 (6 s, +11 m/s²)", 2800]]],
	"couleur": ["Couleur", "Peinture", [["Noir", 0], ["Blanc", 150], ["Gris acier", 150], ["Rouge", 150], ["Orange", 150], ["Jaune taxi", 150], ["Vert", 150], ["Bleu nuit", 150], ["Bleu électrique", 150], ["Violet", 150], ["Rose", 150], ["Kaki", 150]]],
	"finition": ["Finition", "Peinture", [["Vernie", 0], ["Nacrée", 250], ["Mate", 250], ["Chromée", 900]]],
	"vinyle": ["Vinyles", "Peinture", [["Aucun", 0], ["Bandes de course", 250], ["Bande latérale", 200], ["Flammes", 400], ["Éclairs", 350], ["Damier", 350], ["Camouflage", 300], ["Tribal", 350], ["Étoiles", 300], ["Éclaboussures", 350], ["Rayures obliques", 250], ["Dents de requin", 400], ["Filets rétro", 250], ["Chevrons", 300], ["Vagues", 350], ["Pois", 250], ["Tigre", 400], ["Nid d'abeille", 300], ["Pixels 8 bits", 350], ["Numéro de course", 300], ["Circuit imprimé", 350], ["Griffures", 300], ["Tricolore", 250], ["Coucher de soleil rétro", 450]]],
	"vitres": ["Vitres", "Carrosserie", [["D'origine", 0], ["Fumées", 120], ["Limousine (noires)", 200]]],
	"neons": ["Néons sous la caisse", "Carrosserie", [["Aucun", 0], ["Bleus", 300], ["Violets", 300], ["Verts", 300], ["Rouges", 300], ["Roses", 300], ["Blancs", 300]]],
	"jantes": ["Jantes", "Carrosserie", [["D'origine", 0], ["Tuner à rayons", 700], ["Sept branches", 650], ["Étoile", 600], ["Sport fines", 550], ["Concept", 750]]],
	"aileron": ["Aileron", "Carrosserie", [["Aucun", 0], ["Universel", 400], ["Universel haut", 450], ["Course", 600], ["Col-de-cygne", 500], ["Agressif", 700]]],
	"echappement": ["Échappement (son plus grave)", "Carrosserie", [["D'origine", 0], ["Double sortie coudée", 350], ["Sorties fines", 300], ["Gros canons", 400], ["Canons étagés", 400]]],
	"bas_caisse": ["Bas de caisse", "Carrosserie", [["D'origine", 0], ["Jupes latérales", 250]]],
	"prise_air": ["Prise d'air de capot", "Carrosserie", [["Aucune", 0], ["Prise d'air", 300]]],
	"barre_led": ["Barre de LED sur le toit", "Carrosserie", [["Aucune", 0], ["Barre de LED", 350]]],
	"taxi": ["Enseigne TAXI", "Carrosserie", [["Aucune", 0], ["Enseigne lumineuse", 150]]],
}
const COULEURS := [Color(0.015, 0.015, 0.018), Color(0.82, 0.83, 0.84), Color(0.32, 0.34, 0.36), Color(0.55, 0.03, 0.03),
	Color(0.85, 0.30, 0.02), Color(0.95, 0.70, 0.05), Color(0.06, 0.35, 0.10), Color(0.02, 0.05, 0.18), Color(0.03, 0.25, 0.80),
	Color(0.30, 0.06, 0.45), Color(0.85, 0.25, 0.55), Color(0.30, 0.32, 0.18)]
const NEONS := [Color(0, 0, 0), Color(0.1, 0.4, 1.0), Color(0.6, 0.15, 1.0), Color(0.1, 1.0, 0.3), Color(1.0, 0.08, 0.05),
	Color(1.0, 0.2, 0.7), Color(0.9, 0.95, 1.0)]

var argent := DEPART
var possede := {}                   # rubrique -> [indices achetés]
var monte := {}                     # rubrique -> indice monté
var medailles := {}                 # épreuves (#59) : identifiant -> "or" | "argent" | "bronze"
var apercu := {}                    # rubrique -> choix essayé dans l'écran du garage (non acheté, non gardé)

func _ready() -> void:
	charger()

func charger() -> void:
	var c := ConfigFile.new()
	if c.load(FICHIER) == OK:
		argent = float(c.get_value("garage", "argent", DEPART))
		possede = c.get_value("garage", "possede", {})
		monte = c.get_value("garage", "monte", {})
		medailles = c.get_value("garage", "medailles", {})

func sauver() -> void:
	var c := ConfigFile.new()
	c.set_value("garage", "argent", argent)
	c.set_value("garage", "possede", possede)
	c.set_value("garage", "monte", monte)
	c.set_value("garage", "medailles", medailles)
	c.save(FICHIER)

## Choix affiché sur la voiture dans une rubrique : l'aperçu du garage, sinon la pièce montée (0 : d'origine).
func choix(r: String) -> int:
	return int(apercu.get(r, monte.get(r, 0)))

func a(r: String, i: int) -> bool:
	return i == 0 or (possede.get(r, []) as Array).has(i)

func prix(r: String, i: int) -> int:
	return int(CATALOGUE[r][2][i][1])

## Achète (si besoin) et monte le choix i ; false si l'argent manque.
func prendre(r: String, i: int) -> bool:
	if not a(r, i):
		if argent < prix(r, i):
			return false
		argent -= prix(r, i)
		var l: Array = possede.get(r, [])
		l.append(i)
		possede[r] = l
	monte[r] = i
	sauver()
	change.emit()
	return true

## Gains des activités (taxi, primes de course).
func gagner(somme: float) -> void:
	if somme <= 0.0:
		return
	argent += somme
	sauver()
	change.emit()

static func euros(v: float) -> String:
	return ("%.0f €" % v) if absf(v - roundf(v)) < 0.005 else ("%.2f €" % v).replace(".", ",")
