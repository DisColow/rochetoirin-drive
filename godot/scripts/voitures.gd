## Voitures du joueur (#95) : catalogue du garage. On les achète au garage puis on passe de l'une à l'autre ;
## chacune garde ses propres améliorations (garage.gd). Noms et logos parodiés (pas de vraie marque).
## Modèles : pipeline/fetch_voitures_joueur.py + blender_voitures_joueur.py -> assets/voitures/<id>/ ; le pick-up
## de départ reste dans assets/car (blender_ranger.py).
##   masse (kg), kw = puissance aux roues, vmax (km/h), traction : "4x4" | "avant" | "arriere", cx = ½ ρ SCx,
##   gps : écran GPS dans le tableau de bord (sinon la mini-carte reste affichée en vue conducteur),
##   moteur : hauteur du son du moteur (1 = V6 du pick-up), credit : modèle 3D d'origine (⚙ > Crédits).

const DEPART := "ranger"

const CATALOGUE := {
	"ranger": {"nom": "Fjord Rangeur Rapace", "marque": "Fjord", "prix": 0, "dossier": "res://assets/car",
		"masse": 2400.0, "kw": 300.0, "vmax": 230.0, "traction": "4x4", "cx": 0.98, "gps": true, "moteur": 1.0,
		"annee": 2019, "texte": "Le pick-up préparé du début : 4 roues motrices, 0 à 100 en 5 s.",
		"credit": "« Ford Ranger Raptor 2019 » de David_Holiday (CC BY 4.0)"},
	"deuche": {"nom": "Citrouille Deuche", "marque": "Citrouille", "prix": 1500, "dossier": "res://assets/voitures/deuche",
		"masse": 600.0, "kw": 22.0, "vmax": 115.0, "traction": "avant", "cx": 0.55, "gps": false, "moteur": 1.55,
		"annee": 1986, "texte": "Capote roulée, suspensions de chamallow. Elle penche dans les virages, mais elle passe partout.",
		"credit": "« [FREE] 2CV Charleston 1986 » de pagesm (CC BY 4.0)"},
	"r5": {"nom": "Renaud Cinq", "marque": "Renaud", "prix": 2000, "dossier": "res://assets/voitures/r5",
		"masse": 800.0, "kw": 33.0, "vmax": 140.0, "traction": "avant", "cx": 0.48, "gps": false, "moteur": 1.35,
		"annee": 1978, "texte": "La petite citadine des années 70, jaune moutarde d'origine.",
		"credit": "« Renault 5 V2 » de 41iveR (CC BY 4.0)"},
	"twingo": {"nom": "Renaud Tango", "marque": "Renaud", "prix": 2500, "dossier": "res://assets/voitures/twingo",
		"masse": 800.0, "kw": 43.0, "vmax": 155.0, "traction": "avant", "cx": 0.45, "gps": false, "moteur": 1.3,
		"annee": 1996, "texte": "Le sourire sur roues. Toute petite, très maniable.",
		"credit": "« Renault Twingo » de brentonmckey (CC BY 4.0)"},
	"p106": {"nom": "Pijo 106", "marque": "Pijo", "prix": 3000, "dossier": "res://assets/voitures/p106",
		"masse": 880.0, "kw": 55.0, "vmax": 170.0, "traction": "avant", "cx": 0.44, "gps": false, "moteur": 1.25,
		"annee": 1996, "texte": "Légère et vive : la reine des départementales.",
		"credit": "« 1996 Peugeot 106 » de zairiqzairiqpixarcarsbfdi (CC BY 4.0)"},
	"clio": {"nom": "Renaud Clia", "marque": "Renaud", "prix": 3500, "dossier": "res://assets/voitures/clio",
		"masse": 1000.0, "kw": 72.0, "vmax": 185.0, "traction": "avant", "cx": 0.46, "gps": false, "moteur": 1.2,
		"annee": 1998, "texte": "La citadine de tout le monde, version 16 soupapes.",
		"credit": "« 1997 Renault Clio Mk.2 » de ImperialBlue3D (CC BY 4.0)"},
	"espace": {"nom": "Renaud Espèce", "marque": "Renaud", "prix": 4000, "dossier": "res://assets/voitures/espace",
		"masse": 1700.0, "kw": 110.0, "vmax": 195.0, "traction": "avant", "cx": 0.72, "gps": true, "moteur": 1.05,
		"annee": 2008, "texte": "Le monospace familial des débuts du jeu : de la place pour toute la famille.",
		"credit": "« 2008 Renault Espace » de tonielpro520 (CC BY 4.0)"},
	"p206": {"nom": "Pijo 206", "marque": "Pijo", "prix": 4500, "dossier": "res://assets/voitures/p206",
		"masse": 1050.0, "kw": 80.0, "vmax": 192.0, "traction": "avant", "cx": 0.46, "gps": false, "moteur": 1.2,
		"annee": 2000, "texte": "La compacte des années 2000, phares en amande.",
		"credit": "« 2000 Peugeot 206 » de tonielpro520 (CC BY 4.0)"},
	"laguna": {"nom": "Renaud Lagune Break", "marque": "Renaud", "prix": 5000, "dossier": "res://assets/voitures/laguna",
		"masse": 1400.0, "kw": 103.0, "vmax": 205.0, "traction": "avant", "cx": 0.62, "gps": true, "moteur": 1.1,
		"annee": 2001, "texte": "Le grand break du début des années 2000, carte-clé et GPS de série.",
		"credit": "« Renault Laguna Estate 2001 » de szymonpasterczyk (CC BY 4.0), peinte pour le jeu"},
	"p306": {"nom": "Pijo 306 Maxi", "marque": "Pijo", "prix": 9000, "dossier": "res://assets/voitures/p306",
		"masse": 1100.0, "kw": 200.0, "vmax": 220.0, "traction": "avant", "cx": 0.5, "gps": false, "moteur": 1.4,
		"annee": 1996, "texte": "Kit-car de rallye : élargie, rageuse, faite pour les chemins.",
		"credit": "« Lowpoly Peugeot 306 Maxi » de anxietybot (CC BY 4.0)"},
	"gt3": {"nom": "Porc'Che 119 GT3 RS", "marque": "Porc'Che", "prix": 20000, "dossier": "res://assets/voitures/gt3",
		"masse": 1420.0, "kw": 368.0, "vmax": 310.0, "traction": "arriere", "cx": 0.45, "gps": true, "moteur": 1.5,
		"annee": 2016, "texte": "La sportive ultime : moteur à plat à l'arrière, aileron géant, 310 km/h.",
		"credit": "« Porsche 911 GT3 RS (991.1) '16 » de Car2022 (CC BY 4.0)"},
	# bus de l'activité « Ligne de bus » (#148) : pas au garage (service), conduit le temps d'une ligne
	"bus": {"nom": "Autobus B1", "marque": "", "prix": 0, "dossier": "res://assets/voitures/bus", "service": true,
		"masse": 11000.0, "kw": 190.0, "vmax": 90.0, "traction": "arriere", "cx": 3.2, "gps": false, "moteur": 0.7,
		"annee": 1995, "texte": "L'autobus de ville : 11,5 m, 11 tonnes, porte avant à droite.",
		"credit": "modèle B1 de la circulation (voir Tracteurs et bus)"},
}

## Ordre d'affichage dans le garage : du moins cher au plus cher (sans les véhicules de service).
static func ordre() -> Array:
	var l := CATALOGUE.keys().filter(func(id): return not CATALOGUE[id].get("service", false))
	l.sort_custom(func(a, b): return int(CATALOGUE[a].prix) < int(CATALOGUE[b].prix))
	return l

## Voiture choisie à la dernière partie (lue tôt, avant le garage : car.gd la charge dans son _ready).
static func actuelle() -> String:
	var c := ConfigFile.new()
	if c.load("user://garage.cfg") == OK:
		var v := String(c.get_value("garage", "voiture", DEPART))
		if CATALOGUE.has(v) and not CATALOGUE[v].get("service", false) and ResourceLoader.exists(String(CATALOGUE[v].dossier) + "/body.glb"):
			return v
	return DEPART
