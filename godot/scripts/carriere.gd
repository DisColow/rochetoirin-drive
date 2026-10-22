## Mode carrière « De Rochetoirin à la Nationale » (#120, #131) : 4 chapitres (scénario validé par l'utilisateur le
## 21/10 ; chapitre 1 en v6.74, rival réel en v6.83 (#128), chapitres 2 à 4 en v6.84 (#131)), carte jamais verrouillée
## hors mission, rivaux qui roulent vraiment (concurrent.gd).
## - Onglet « Carrière » du menu Activités (menu_activites.gd) : chapitres (un chapitre s'ouvre quand le précédent est à
##   100), jauge de réputation, missions, rivaux, classement du championnat ; chaque mission se lance de là
##   (itinéraire GPS jusqu'à son départ, ou « Y aller » : la voiture y est posée).
## - Genres de missions (CHAPITRES[].missions[].genre) :
##   livraison (chargement fragile pris au départ, arrêts, temps limité, 3 gros chocs = raté) ;
##   taxi (course de taxi imposée d'activities.gd, `impose` : client nommé, temps limité, chocs comptés) ;
##   chrono (médaille sur une épreuve, gagnée à tout moment) ; chasse (lieu à trouver sans GPS avant que la zone se
##   referme : chasse d'activities.gd) ; course (épreuve contre 3 voitures, place à tenir) ; nuit (courses de taxi de
##   nuit d'affilée, moyenne d'étoiles) ; duel (épreuve contre un rival) ; manche (championnat du chapitre 4 : 5 manches
##   contre les 3 rivaux, points POINTS, champion = fin de la carrière).
## - Réputation (0 à 100 par chapitre) : missions ; bonus du jeu libre (médailles d'épreuves, clients contents) et pertes
##   (décor cassé pendant une mission, client mécontent, KA-BOOM), comptés au chapitre en cours. À 100 : message d'un
##   personnage, voiture offerte (`cadeau` ; sa demi-valeur en prime si on l'a déjà), chapitre suivant ouvert.
## - Progression dans user://carriere.cfg (l'ancienne sauvegarde du chapitre 1 est relue) ; le jeu libre ne change pas.
## Essais : --drive-test --carriere-test (chapitre 1), --drive-test --carriere2-test (chapitres 2 à 4).
extends Node

const UI := preload("res://scripts/ui.gd")
const VT := preload("res://scripts/voix_tel.gd")
const Chargement := preload("res://scripts/chargement.gd")
const Voitures := preload("res://scripts/voitures.gd")
const FICHIER := "user://carriere.cfg"
const STOP_R := 14.0
const MEDAILLES := ["or", "argent", "bronze"]
const POINTS := [10, 6, 4, 3]                        # championnat : points de la 1re à la 4e place
const ORDRE_RIVAUX := ["kevin", "sandrine", "didier"]

const RIVAUX := {
	"kevin": {"nom": "Kévin Turbot", "court": "Kévin", "voiture": "p106", "voix": "m", "graine": 4242,
		"titre": "le roi du village", "couleur": Color(-1, 0, 0), "allure": 1.02,
		"avant": [["Alors, c'est toi le nouveau ? Ma 106 va te mettre une raclée.", "On en reparle à l'arrivée.", "Tu parles beaucoup pour un pot de yaourt."],
			["Encore toi ? Tu n'as pas eu ta dose la dernière fois ?", "Cette fois, c'est la bonne.", "Je m'échauffais."]],
		"ripostes": ["Ha ! On verra bien.", "Cause toujours…", "Accroche-toi à ton volant !"],
		"victoire": "Pff… coup de chance. Profite, ça ne durera pas.",
		"defaite": "Retourne à ton tracteur, gamin ! Reviens quand tu sauras conduire.",
		"manche": "Le championnat ? Je l'ai gagné cent fois… dans ma tête. Cette fois, c'est pour de vrai !"},
	"sandrine": {"nom": "Sandrine Dérapage", "court": "Sandrine", "voiture": "p206", "voix": "f", "graine": 5151,
		"titre": "la reine de la vallée", "couleur": Color(0.85, 0.25, 0.55), "allure": 0.96,
		"avant": [["C'est toi, le petit prodige du village ? Dans la vallée, les virages, c'est moi qui les dessine.", "Montre-moi ça.", "Kévin m'a dit la même chose."],
			["Tu reviens te faire peigner ? Ma 206 t'a gardé une place… derrière elle.", "Pas cette fois.", "J'ai changé de pneus."]],
		"ripostes": ["Ceinture bouclée ? Tu vas en avoir besoin.", "Regarde bien mes feux arrière, c'est tout ce que tu verras.", "On se retrouve à l'arrivée !"],
		"victoire": "Bon… tu as de la conduite, je l'admets. Mais la vallée, ça se mérite tous les jours.",
		"defaite": "Trop sage dans les virages, mon chou. Reviens quand tu oseras freiner tard.",
		"manche": "Kévin, Didier et toi sur la même grille ? Je vais adorer vous voir dans mon rétroviseur."},
	"didier": {"nom": "Didier Klaxon", "court": "Didier", "voiture": "p306", "voix": "m", "graine": 6262,
		"titre": "patron des Taxis Klaxon, le roi de la ville", "couleur": Color(0.95, 0.75, 0.1), "allure": 0.92,
		"avant": [["Taxis Klaxon, trente ans de métier. Un amateur qui vient voler mes clients ? On règle ça sur la route.", "Tes clients me préfèrent.", "Le compteur tourne, Didier."],
			["Encore toi ? J'ai réglé la 306 aux petits oignons depuis la dernière fois.", "Moi aussi, j'ai bossé.", "On va voir ça."]],
		"ripostes": ["À la gare, le dernier paie le café !", "Attache ta ceinture, c'est moi qui conduis la ville.", "Klaxon un jour, Klaxon toujours !"],
		"victoire": "Chapeau… Tu peux garder les clients de la gare. Pour cette fois.",
		"defaite": "En ville, c'est l'expérience qui compte. Reviens dans trente ans !",
		"manche": "Le titre du Nord-Isère a toujours été jaune Klaxon. Ça ne va pas changer aujourd'hui."},
}

const CHAPITRES := [
	{"titre": "Le village", "lieux": "Rochetoirin, Saint-Chef", "rivaux": ["kevin"], "cadeau": "deuche",
	 "intro": "De Rochetoirin à la Nationale : fais-toi un nom au village. Chaque mission rapporte 25 points de réputation ; les médailles et les clients contents en rapportent aussi, le décor cassé en mission et le KA-BOOM en coûtent.",
	 "fin": {"de": "Flonflon (le boulanger)",
		"texte": "Tout le village parle de toi ! Même Kévin a arrêté de crâner. Prends ma vieille Citrouille Deuche de livraison, elle t'attend au garage. Et file dans la vallée : à Saint-Didier, on cherche un chauffeur… Méfie-toi de Sandrine Dérapage, la reine de la vallée. Chapitre 2 « La vallée » : ouvert !"},
	 "missions": [
		{"id": "pain", "titre": "Le pain du matin", "genre": "livraison", "rep": 25, "prime": 450.0,
		 "texte": "Flonflon, le boulanger, a trois commandes à livrer : l'école de Rochetoirin, la mairie de Saint-Jean-de-Soudain et Montbertaud. Chargement fragile : au troisième gros choc, la tarte est fichue.",
		 "depart_xz": [49.0, 410.0], "depart_nom": "Boulangerie Chez Flonflon", "vitesse": 12.0,
		 "arrets": ["École primaire publique Rochetoirin", "Mairie de Saint-Jean-de-Soudain", "Montbertaud"],
		 "charge": "Commandes chargées : pain, croissants… et la tarte du maire.\nAttention aux chocs !",
		 "aie": "Aïe, la tarte ! (%d / 3)", "casse": "Troisième choc : la tarte du maire est en miettes.",
		 "retard": "Trop tard : les clients ont déjà déjeuné."},
		{"id": "maire", "titre": "Monsieur le maire", "genre": "taxi", "rep": 25, "prime": 360.0,
		 "texte": "Le maire est coincé à la mairie de Saint-Chef. Ramène-le à la mairie de Rochetoirin avant l'ouverture du conseil municipal.",
		 "depart": "Mairie de Saint-Chef", "arrivee": "Mairie de Rochetoirin", "vitesse": 15.0, "marge": 40.0,
		 "client": {"prenom": "Bernard", "metier": "maire de Rochetoirin", "sexe": "m", "age": [50, 120], "dit": "Merci ! Le conseil commence bientôt : on ne traîne pas."},
		 "ok": "Arrivé en %s : le conseil peut commencer.", "rate": "Le conseil municipal a commencé sans le maire…"},
		{"id": "chrono", "titre": "Premier chrono", "genre": "chrono", "rep": 25, "prime": 0.0, "epreuve": 14, "medaille": "bronze",
		 "texte": "Montre au village que tu sais conduire : au moins le bronze au sprint de la place des Anciens Combattants."},
		{"id": "duel", "titre": "Le duel", "genre": "duel", "rep": 25, "prime": 600.0, "epreuve": 0, "allure": 0.88, "rival": "kevin",
		 "texte": "Kévin Turbot et sa Pijo 106 font la loi au village. Il te défie jusqu'à la chapelle Saint-Joseph : il roule en même temps que toi, pare-chocs contre pare-chocs."},
	 ]},
	{"titre": "La vallée", "lieux": "Saint-Didier, Saint-Clair, La Chapelle, Montcarra", "rivaux": ["sandrine"], "cadeau": "r5",
	 "intro": "Saint-Didier, Saint-Clair et La Chapelle-de-la-Tour : la vallée t'attend. Cinq missions de 20 points, et Sandrine Dérapage qui ne laisse passer personne.",
	 "fin": {"de": "Josette (la fermière de la Cassole)",
		"texte": "Toute la vallée ne parle que de toi ! Sandrine te salue (elle est vexée). Mon neveu te laisse sa Renaud Cinq : elle est au garage. En ville, les Taxis Klaxon cherchent du monde… et leur patron, Didier, n'aime pas la concurrence. Chapitre 3 « La ville » : ouvert !"},
	 "missions": [
		{"id": "oeufs", "titre": "Les œufs de la Cassole", "genre": "livraison", "rep": 20, "prime": 700.0,
		 "texte": "Josette, à la ferme de la Cassole, livre les cantines de la vallée : Saint-Didier, Saint-Clair et La Chapelle-de-la-Tour. Six douzaines d'œufs extra-frais : au troisième gros choc, c'est l'omelette.",
		 "depart_xz": [5972.0, 3441.0], "depart_nom": "Ferme de la Cassole", "vitesse": 12.0,
		 "arrets": ["École primaire \"Les Ptits Cassolards\" (Élémentaire)", "École primaire le Village", "École primaire|La Chapelle-de-la-Tour"],
		 "charge": "Six douzaines d'œufs chargées.\nRoule comme sur des œufs !",
		 "aie": "Crac ! Des œufs cassés (%d / 3)", "casse": "Troisième choc : une omelette géante dans le coffre.",
		 "retard": "Trop tard : les cantines ont servi des pâtes."},
		{"id": "colis", "titre": "Le colis perdu", "genre": "chasse", "rep": 20, "prime": 500.0,
		 "texte": "Au relais poste de Saint-Clair, un colis attend depuis un mois : il est pour la Maison forte de la Maison Blanche. Trouve-la sans GPS, avant que la zone de recherche se referme.",
		 "depart": "Relais Poste|Saint-Clair-de-la-Tour", "lieu": "Maison forte de la Maison Blanche",
		 "ok": "Colis livré en %s : le châtelain t'offre un verre de jus de pomme.",
		 "rate": "La zone s'est refermée : le colis retourne à l'expéditeur."},
		{"id": "chrono2", "titre": "Chrono de la Cassole", "genre": "chrono", "rep": 20, "prime": 0.0, "epreuve": 17, "medaille": "argent",
		 "texte": "Le sprint de la ferme de la Cassole à l'église Saint-Didier est la fierté du coin : décroche au moins l'argent."},
		{"id": "mariee", "titre": "La mariée est en retard", "genre": "taxi", "rep": 20, "prime": 650.0,
		 "texte": "Mélanie se prépare au château de Pin ; la cérémonie commence à l'église de La Chapelle-de-la-Tour. Conduis-la à l'heure… et sans froisser la robe : au troisième choc, c'est raté.",
		 "depart": "Château de Pin", "arrivee": "Église de l'Assomption|La Chapelle-de-la-Tour", "vitesse": 15.0, "marge": 40.0, "chocs_max": 3,
		 "client": {"prenom": "Mélanie", "metier": "la mariée", "sexe": "f", "age": [18, 40], "dit": "Je suis en retard ! Et attention à ma robe, s'il vous plaît !"},
		 "aie": "La robe ! (%d / 3)", "ok": "Arrivée en %s : « Oui ! »", "rate": "La cérémonie a commencé sans la mariée…",
		 "chocs": "Troisième choc : la robe est froissée, Mélanie descend furieuse."},
		{"id": "duel2", "titre": "Le duel de la vallée", "genre": "duel", "rep": 20, "prime": 900.0, "epreuve": 10, "allure": 0.86, "rival": "sandrine",
		 "texte": "Sandrine Dérapage et sa Pijo 206 t'attendent devant l'église de La Chapelle-de-la-Tour : course jusqu'à la mairie de Saint-Jean-de-Soudain."},
	 ]},
	{"titre": "La ville", "lieux": "La Tour-du-Pin, Bourgoin-Jallieu", "rivaux": ["didier"], "cadeau": "laguna",
	 "intro": "La Tour-du-Pin et Bourgoin-Jallieu : clients pressés, service de nuit et courses en ville. Les Taxis Klaxon de Didier tiennent le pavé.",
	 "fin": {"de": "La centrale des taxis du Nord-Isère",
		"texte": "Même Didier Klaxon te tire son chapeau ! La centrale te confie une Renaud Lagune Break, la voiture des taxis : elle est au garage. Le grand championnat du Nord-Isère commence à L'Isle-d'Abeau : 5 manches contre Kévin, Sandrine et Didier. Chapitre 4 « La finale » : ouvert !"},
	 "missions": [
		{"id": "bebe", "titre": "Le bébé arrive !", "genre": "taxi", "rep": 20, "prime": 800.0,
		 "texte": "À Bellefontaine, Jessica perd les eaux : direction le centre hospitalier de La Tour-du-Pin, vite… mais en douceur (au troisième choc, c'est raté).",
		 "depart": "Bellefontaine", "arrivee": "Centre hospitalier de La Tour-du-Pin", "vitesse": 16.0, "marge": 30.0, "chocs_max": 3,
		 "client": {"prenom": "Jessica", "metier": "future maman", "sexe": "f", "age": [18, 38], "dit": "Vite, le bébé arrive ! Mais doucement dans les bosses !"},
		 "aie": "Doucement, les contractions ! (%d / 3)", "ok": "Arrivée en %s : c'est une fille, elle s'appellera… comme toi !",
		 "rate": "Trop tard : le bébé est né sur la banquette arrière.", "chocs": "Troisième choc : Jessica appelle une ambulance."},
		{"id": "train", "titre": "Le train de 18 h 12", "genre": "taxi", "rep": 20, "prime": 800.0,
		 "texte": "Jean-Charles a oublié l'heure au golf des 3 vallons, à L'Isle-d'Abeau : son train part de la gare de Bourgoin-Jallieu dans quelques minutes.",
		 "depart": "Golf des 3 vallons", "arrivee": "Gare de Bourgoin-Jallieu", "vitesse": 16.0, "marge": 30.0,
		 "client": {"prenom": "Jean-Charles", "metier": "banquier lyonnais", "sexe": "m", "age": [30, 60], "dit": "Gare de Bourgoin, et vite : mon train part dans quelques minutes !"},
		 "ok": "Arrivé en %s : Jean-Charles saute dans le train.", "rate": "Le train est parti sous les yeux de Jean-Charles…"},
		{"id": "nuit", "titre": "Service de nuit", "genre": "nuit", "rep": 20, "prime": 900.0, "courses": 3, "etoiles": 4.0,
		 "texte": "La nuit tombe sur Bourgoin : la centrale te confie le service de nuit. Trois courses d'affilée, au moins 4 étoiles de moyenne ; un client à 2 étoiles ou moins, et tu es renvoyé.",
		 "depart": "Hôtel de Ville|Bourgoin-Jallieu"},
		{"id": "ville", "titre": "La course de la ville", "genre": "course", "rep": 20, "prime": 700.0, "epreuve": 24, "niveau": 1, "place": 2,
		 "texte": "Le sprint de la chapelle Saint-Barthélémy, en plein Bourgoin, contre trois voitures (niveau Difficile) : finis dans les deux premiers."},
		{"id": "duel3", "titre": "Taxi contre taxi", "genre": "duel", "rep": 20, "prime": 1200.0, "epreuve": 3, "allure": 0.84, "rival": "didier",
		 "texte": "Didier Klaxon n'aime pas qu'on prenne ses clients : course de la chapelle Saint-François à la gare de Bourgoin-Jallieu contre sa Pijo 306 Maxi."},
	 ]},
	{"titre": "La finale", "lieux": "L'Isle-d'Abeau, Bourgoin-Jallieu", "rivaux": ["kevin", "sandrine", "didier"], "cadeau": "gt3",
	 "intro": "Le grand championnat du Nord-Isère : 5 manches contre Kévin, Sandrine et Didier (niveau Difficile). Points à chaque manche : 10, 6, 4 et 3. Le premier au classement après la 5e manche est champion.",
	 "fin": {"de": "Bernard (le maire de Rochetoirin)",
		"texte": "Champion du Nord-Isère ! De Rochetoirin à la Nationale, tout le monde connaît ton nom. Le village t'offre une Porc'Che 119 GT3 RS : elle t'attend au garage. Fête ce soir sur la place des Anciens Combattants ! (Fin de la carrière : merci d'avoir joué.)"},
	 "missions": [
		{"id": "manche1", "titre": "Manche 1 : les chapelles", "genre": "manche", "n": 1, "epreuve": 25, "niveau": 1, "rep": 0, "prime": 0.0,
		 "texte": "Sprint de la chapelle Sainte-Anne à la mosquée, au cœur de L'Isle-d'Abeau."},
		{"id": "manche2", "titre": "Manche 2 : la gare", "genre": "manche", "n": 2, "epreuve": 15, "niveau": 1, "rep": 0, "prime": 0.0,
		 "texte": "Sprint de la chapelle Saint-Germain à la gare de L'Isle-d'Abeau."},
		{"id": "manche3", "titre": "Manche 3 : les collines", "genre": "manche", "n": 3, "epreuve": 1, "niveau": 1, "rep": 0, "prime": 0.0,
		 "texte": "De la chapelle Saint-Germain à la chapelle Sainte-Anne, par les collines de L'Isle-d'Abeau."},
		{"id": "manche4", "titre": "Manche 4 : Bourgoin – L'Isle-d'Abeau", "genre": "manche", "n": 4, "epreuve": 6, "niveau": 1, "rep": 0, "prime": 0.0,
		 "texte": "Du Champions Five de Bourgoin à la mosquée de L'Isle-d'Abeau."},
		{"id": "manche5", "titre": "Manche 5 : la grande finale", "genre": "manche", "n": 5, "epreuve": 27, "niveau": 1, "rep": 0, "prime": 0.0,
		 "texte": "La longue : de la chapelle Saint-Germain à la gare de Bourgoin-Jallieu, 9 km. Tout se joue ici."},
	 ]},
]

var main: Node
var act: Node                      # activities.gd
var hud: CanvasLayer
var car: VehicleBody3D
var reps := [0.0, 0.0, 0.0, 0.0]   # réputation de chaque chapitre (0 à 100)
var faites := {}                   # mission -> true
var fins_vues: Array = []          # chapitres dont le message de fin a été lu (voiture offerte)
var commencee := false             # une mission a été lancée : les bonus et pertes du jeu libre comptent
var duels := {}                    # rival -> [victoires, défaites]
var champ := {}                    # championnat : {manche: dernière manche courue, points: {joueur, kevin…}, resultats: [[ids…]…]}
var en_cours := ""                 # mission en cours ("" : aucune)

var _phase := ""
var _arrets: Array = []            # livraison : [{i: point de route, nom}]
var _k := 0
var _t := 0.0
var _limite := 0.0
var _chocs := 0
var _casses := 0
var _prev_v := Vector3.ZERO
var _choc_cd := 0.0
var _stop_t := 0.0
var _depart := -1                  # point de route du départ de la mission (GPS)
var _rival: Node                   # concurrent.gd du duel (#128)
var _concs := {}                   # manche du championnat : rival -> concurrent.gd
var _taxi_m := ""                  # mission de la course de taxi imposée en cours
var _courses := 0                  # service de nuit : courses faites, étoiles cumulées
var _etoiles := 0
var _heure_avant := -1             # heure de la journée à rendre après le service de nuit
var _bulle: Control
var _voix := {}                    # graine -> voix du téléphone

func _ready() -> void:
	charger()
	get_tree().create_timer(6.0).timeout.connect(_verifier_fins)

func _champ_vide() -> Dictionary:
	return {"manche": 0, "points": {"joueur": 0, "kevin": 0, "sandrine": 0, "didier": 0}, "resultats": []}

func charger() -> void:
	champ = _champ_vide()
	var c := ConfigFile.new()
	if c.load(FICHIER) != OK:
		return
	var r = c.get_value("carriere", "reps", null)
	if r is Array and r.size() == reps.size():
		reps = r.duplicate()
	else:
		reps[0] = float(c.get_value("carriere", "reputation", 0.0))      # sauvegarde du chapitre 1 seul (v6.74)
	faites = c.get_value("carriere", "faites", {})
	fins_vues = c.get_value("carriere", "fins_vues", [])
	commencee = bool(c.get_value("carriere", "commencee", false))
	duels = c.get_value("carriere", "duels", {})
	if duels.is_empty() and (c.has_section_key("carriere", "victoires") or c.has_section_key("carriere", "defaites")):
		duels["kevin"] = [int(c.get_value("carriere", "victoires", 0)), int(c.get_value("carriere", "defaites", 0))]
	var ch = c.get_value("carriere", "championnat", {})
	if ch is Dictionary and ch.has("points"):
		champ = ch

func sauver() -> void:
	var c := ConfigFile.new()
	c.set_value("carriere", "reps", reps)
	c.set_value("carriere", "faites", faites)
	c.set_value("carriere", "fins_vues", fins_vues)
	c.set_value("carriere", "commencee", commencee)
	c.set_value("carriere", "duels", duels)
	c.set_value("carriere", "championnat", champ)
	c.save(FICHIER)

## Remet la carrière à zéro (essais).
func effacer() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FICHIER))
	reps = [0.0, 0.0, 0.0, 0.0]
	faites = {}; fins_vues = []; commencee = false; duels = {}; champ = _champ_vide()

# ================================================================ chapitres
func mission(id: String) -> Dictionary:
	for ch in CHAPITRES:
		for m in ch.missions:
			if m.id == id:
				return m
	return {}

func chapitre_de(id: String) -> int:
	for k in CHAPITRES.size():
		for m in CHAPITRES[k].missions:
			if m.id == id:
				return k
	return -1

func fini(ch: int) -> bool:
	return float(reps[ch]) >= 100.0

func ouvert(ch: int) -> bool:
	return ch == 0 or fini(ch - 1)

## Chapitre en cours : le premier qui n'est pas fini (le dernier quand tout est fini).
func courant() -> int:
	for k in CHAPITRES.size():
		if not fini(k):
			return k
	return CHAPITRES.size() - 1

func carriere_finie() -> bool:
	return fini(CHAPITRES.size() - 1)

func duel_bilan(rival: String) -> Array:
	return duels.get(rival, [0, 0])

## Réputation du chapitre ch (chapitre en cours par défaut) : gain ou perte (bandeau), sauvegarde ; à 100, message de
## fin du chapitre. Le chapitre 4 se joue aux points du championnat, pas à la réputation.
func gagner(n: float, raison: String, ch := -1) -> void:
	if ch < 0:
		ch = courant()
	if fini(ch) or not ouvert(ch) or String(CHAPITRES[ch].missions[0].genre) == "manche":
		return
	var avant := float(reps[ch])
	reps[ch] = clampf(avant + n, 0.0, 100.0)
	if is_equal_approx(avant, float(reps[ch])):
		return
	sauver()
	if hud:
		hud.toast("%+d réputation : %s  (%d / 100)" % [int(round(float(reps[ch]) - avant)), raison, int(reps[ch])], 4.0)
	if fini(ch) and not fins_vues.has(ch):
		get_tree().create_timer(4.5).timeout.connect(_message_fin.bind(ch))

## Messages de fin restés en attente (chapitre 1 fini avant la v6.84 : ouverture du chapitre 2 et voiture offerte),
## montrés hors activité, une fois le monde chargé.
func _verifier_fins() -> void:
	for k in CHAPITRES.size():
		if fini(k) and not fins_vues.has(k):
			if not Chargement.fini or get_tree().paused or (act and act.mode != "") or _bulle != null:
				get_tree().create_timer(8.0).timeout.connect(_verifier_fins)
			else:
				_message_fin(k)
			return

# ================================================================ lancement des missions
## Lance une mission depuis l'onglet Carrière : y_aller = la voiture est posée au départ ; sinon itinéraire GPS.
func lancer(id: String, y_aller: bool) -> void:
	var m := mission(id)
	if m.is_empty() or not ouvert(chapitre_de(id)):
		return
	if String(m.genre) == "manche":
		if int(champ.manche) >= 5 and not carriere_finie():
			recommencer_championnat()
		if int(m.n) != int(champ.manche) + 1 and not carriere_finie():
			hud.toast("Championnat : cours d'abord la manche %d." % (int(champ.manche) + 1), 3.0)
			return
	act._stop()
	arreter(false)
	act._close_menu(true)
	if not commencee:
		commencee = true
		sauver()
	match String(m.genre):
		"livraison":
			_livraison(m, y_aller)
		"taxi":
			_taxi(m, y_aller)
		"chrono":
			var e: Dictionary = act.epreuves[int(m.epreuve)]
			if y_aller:
				act._epreuve_depart(int(m.epreuve))
			else:
				_vers(Vector2(e.a[0], e.a[1]), "Départ de l'épreuve : " + str(e.nom))
		_:
			# chasse, nuit, course, duel, manche : on va au départ, la suite se joue sur place (_au_depart)
			en_cours = id
			act.mode = "mission"
			act.map.locked = true
			var p := _point_depart(m)
			_depart = act._nearest(p)
			if y_aller:
				var vers: Vector2 = p + Vector2(0.0, -60.0)
				if m.has("epreuve"):
					var e: Dictionary = act.epreuves[int(m.epreuve)]
					vers = Vector2(e.etapes[0][0], e.etapes[0][1]) if not e.etapes.is_empty() else Vector2(e.b[0], e.b[1])
				var s: Array = act._start_at(_depart, vers)
				hud.teleport.emit(s[0], s[1])
				_phase = "pret"
				get_tree().create_timer(1.2).timeout.connect(_au_depart)
			else:
				_phase = "aller"
				_balise(_depart, Color(0.95, 0.35, 0.3), _nom_depart(m))

## Lieu de places.json par son nom (« nom|commune » quand le nom ne suffit pas).
func _lieu(n: String) -> Dictionary:
	var nom := n.get_slice("|", 0)
	var com := n.get_slice("|", 1) if n.contains("|") else ""
	for p in act.places:
		if str(p.n) == nom and (com == "" or str(p.get("c", "")) == com):
			return p
	push_warning("carrière : lieu introuvable « %s »" % n)
	return {}

## Lieux nommés de toutes les missions (essai : chacun doit désigner un seul lieu de places.json).
func lieux_des_missions() -> Array:
	var l := []
	for ch in CHAPITRES:
		for m in ch.missions:
			for k in ["depart", "arrivee", "lieu"]:
				if m.has(k):
					l.append(str(m[k]))
			for n in m.get("arrets", []):
				l.append(str(n))
	return l

func _point_depart(m: Dictionary) -> Vector2:
	if m.has("epreuve"):
		var e: Dictionary = act.epreuves[int(m.epreuve)]
		return Vector2(e.a[0], e.a[1])
	if m.has("depart_xz"):
		return Vector2(m.depart_xz[0], m.depart_xz[1])
	var l := _lieu(str(m.get("depart", "")))
	return Vector2(l.x, l.z) if not l.is_empty() else act._car2()

func _nom_depart(m: Dictionary) -> String:
	match String(m.genre):
		"duel":
			return str(RIVAUX[m.rival].court)
		"manche":
			return "Manche %d" % int(m.n)
		"chasse":
			return "Relais poste"
		"nuit":
			return "Centrale"
	return "Départ"

## Itinéraire GPS seul vers un point (mission sans état : chrono).
func _vers(p: Vector2, txt: String) -> void:
	var i: int = act._nearest(p)
	act.marks = [{p = act._rp(i), col = Color(1.0, 0.8, 0.2), txt = "Départ", gps = true}]
	act._beacon(act._r3(i), Color(1.0, 0.8, 0.2), 8.0, 60.0)
	hud.toast(txt + "\nSuivez le GPS ; l'épreuve vous sera proposée sur place.", 5.0)
	act._itin_cible = Vector2.INF
	act.route_gps = PackedVector2Array()
	en_cours = ""
	_depart = i
	_phase = "guide"

func _balise(i: int, col: Color, txt: String) -> void:
	for b in act._beacons:
		if is_instance_valid(b):
			b.queue_free()
	act._beacons.clear()
	act._beacon(act._r3(i), col, 8.0, 60.0)
	act.marks = [{p = act._rp(i), col = col, txt = txt, gps = true}]

## Arrivé au départ d'une mission qui se joue sur place.
func _au_depart() -> void:
	var m := mission(en_cours)
	if m.is_empty() or _phase not in ["pret", "aller"]:
		return
	act._clear_world()
	match String(m.genre):
		"duel":
			_defi()
		"manche":
			_defi_manche(m)
		"course":
			_phase = "course"
			act.mode = ""
			act._epreuve_depart(int(m.epreuve), int(m.niveau), true)
		"chasse":
			_chasse_debut(m)
		"nuit":
			_nuit_debut(m)

## Fin de mission (réussie, ratée, ou arrêtée par le bouton ■ d'activities.gd).
func arreter(annonce := true) -> void:
	_rival = null                      # retiré par activities.gd (_fin_concurrents)
	_concs = {}
	_fermer_bulle()
	_rendre_heure()
	if en_cours != "" and annonce and hud:
		hud.toast("Mission arrêtée.", 2.5)
	en_cours = ""
	_phase = ""
	_depart = -1
	_taxi_m = ""

## Appelé par activities._stop() (bouton ■, nouvelle activité).
func activite_arretee() -> void:
	if _phase == "guide":
		_phase = ""
	if en_cours != "" and _phase != "course":
		arreter(false)

func _reussir(m: Dictionary, detail := "") -> void:
	var neuf := not faites.has(m.id)
	faites[m.id] = true
	sauver()
	if main.garage and float(m.prime) > 0.0:
		main.garage.gagner(float(m.prime))
	hud.toast("Mission réussie : %s%s%s" % [m.titre, detail, ("\nPrime : %d €" % int(m.prime)) if float(m.prime) > 0.0 else ""], 6.0)
	if neuf and int(m.rep) > 0:
		get_tree().create_timer(2.0).timeout.connect(gagner.bind(float(m.rep), String(m.titre), chapitre_de(String(m.id))))
	act._bip.play()

func _rater(m: Dictionary, pourquoi: String) -> void:
	hud.toast("Mission ratée : %s\n%s\nOn peut la retenter depuis le menu (★ > Carrière)." % [m.titre, pourquoi], 7.0)

# ================================================================ livraison
func _livraison(m: Dictionary, y_aller: bool) -> void:
	en_cours = String(m.id)
	act.mode = "mission"
	act.map.locked = true
	_arrets = []
	for n in m.arrets:
		var l := _lieu(str(n))
		if not l.is_empty():
			_arrets.append({i = act._nearest(Vector2(l.x, l.z)), nom = str(l.n)})
	var p := _point_depart(m)
	_depart = act._nearest(p)
	_k = 0
	_chocs = 0
	_casses = 0
	_stop_t = 0.0
	_phase = "aller"
	if y_aller:
		var s: Array = act._start_at(_depart, act._rp(_arrets[0].i) if not _arrets.is_empty() else p)
		hud.teleport.emit(s[0], s[1])
	_balise(_depart, Color(1.0, 0.75, 0.3), "Chargement")
	hud.toast("%s\nPassez prendre le chargement : %s." % [m.titre, m.depart_nom], 5.0)

func _livraison_process(dt: float) -> void:
	var m := mission(en_cours)
	var c: Vector2 = act._car2()
	var lent: bool = car.kmh() < 10.0
	if _phase == "aller":
		act._itineraire(dt, act._rp(_depart))
		var d := c.distance_to(act._rp(_depart))
		act._set_status("Mission : %s\n%s : %d m" % [m.titre, m.depart_nom, int(d)])
		if _arrive(d, lent, dt):
			_phase = "livre"
			_t = 0.0
			# temps limite : trajet à `vitesse` m/s (lignes droites × 1,35) + 12 s par arrêt, arrondi aux 10 s
			var long := 0.0
			var q: Vector2 = act._rp(_depart)
			for a in _arrets:
				long += q.distance_to(act._rp(a.i)) * 1.35
				q = act._rp(a.i)
			_limite = ceilf((long / float(m.get("vitesse", 12.0)) + 12.0 * _arrets.size()) / 10.0) * 10.0
			_prev_v = car.linear_velocity
			act._bip.play()
			hud.toast(str(m.charge), 5.0)
			_balise(_arrets[0].i, Color(0.3, 0.95, 0.4), "Livraison")
		return
	_t += dt
	var a: Dictionary = _arrets[_k]
	act._itineraire(dt, act._rp(a.i))
	var d2 := c.distance_to(act._rp(a.i))
	var reste := maxf(_limite - _t, 0.0)
	act._set_status("Mission : %s  ·  %s\nLivraison %d / %d : %s, %d m\nChargement %s" % [m.titre, act._fmt(reste), _k + 1,
		_arrets.size(), a.nom, int(d2), "♥".repeat(3 - _chocs) + "♡".repeat(_chocs)])
	if _t > _limite:
		_fin_mission()
		_rater(m, str(m.retard))
		return
	if _arrive(d2, lent, dt):
		act._bip.play()
		_k += 1
		if _k >= _arrets.size():
			_fin_mission()
			_reussir(m, "\n%s, %d choc(s)" % [act._fmt(_t), _chocs])
			return
		hud.toast("Livré : %s" % a.nom, 2.5)
		_balise(_arrets[_k].i, Color(0.3, 0.95, 0.4), "Livraison")

func _arrive(d: float, lent: bool, dt: float) -> bool:
	if d < STOP_R and lent:
		_stop_t += dt
		if _stop_t > 0.6:
			_stop_t = 0.0
			return true
	else:
		_stop_t = 0.0
	return false

func _fin_mission() -> void:
	en_cours = ""
	_phase = ""
	act._clear_world()
	act.mode = ""
	act.map.locked = false
	act._set_status("")

# ================================================================ taxi imposé (le maire, la mariée, le bébé, le train)
func _taxi(m: Dictionary, y_aller: bool) -> void:
	var a := _lieu(str(m.depart))
	var b := _lieu(str(m.arrivee))
	if a.is_empty() or b.is_empty():
		return
	var pick: int = act._nearest(Vector2(a.x, a.z))
	var dest: int = act._nearest(Vector2(b.x, b.z))
	# temps limite : ligne droite × 1,35 à `vitesse` m/s, + `marge` s, arrondi aux 10 s
	var limite := ceilf((act._rp(pick).distance_to(act._rp(dest)) * 1.35 / float(m.vitesse) + float(m.marge)) / 10.0) * 10.0
	var cl: Dictionary = m.client
	act.impose = {pick = pick, nom = "%s (%s)" % [cl.prenom, str(m.depart).get_slice("|", 0)], dest = dest,
		dest_nom = str(b.n), dest_k = str(b.get("k", "autre")), limite = limite, client = cl, chocs_max = int(m.get("chocs_max", 0)), aie = str(m.get("aie", ""))}
	if y_aller:
		var s: Array = act._start_at(act._nearest(act._rp(pick) + Vector2(80, 0)), act._rp(pick))
		hud.teleport.emit(s[0], s[1])
	act._taxi_start()
	en_cours = String(m.id)
	_taxi_m = en_cours
	_phase = "taxi"

## Fin de la course imposée (activities.gd) : à l'heure ou non ; raison « chocs » : trop de chocs.
func taxi_impose_fini(a_l_heure: bool, t: float, raison := "") -> void:
	var m := mission(_taxi_m if _taxi_m != "" else "maire")
	en_cours = ""
	_phase = ""
	_taxi_m = ""
	if raison == "chocs":
		_rater(m, str(m.get("chocs", "Le client est descendu.")))
	elif a_l_heure:
		_reussir(m, "\n" + (str(m.ok) % act._fmt(t)))
	else:
		_rater(m, str(m.rate))

# ================================================================ chasse au lieu sans GPS (le colis perdu)
func _chasse_debut(m: Dictionary) -> void:
	var l := _lieu(str(m.lieu))
	if l.is_empty():
		arreter(false)
		return
	act._target = Vector2(l.x, l.z)
	act._target_name = "%s (%s)" % [l.n, l.c]
	act._found_r = 45.0
	act._hunt_begin()
	act.mode = "chasse"
	_limite = act._dur + 30.0
	act.chasse_limite = _limite
	_phase = "chasse"
	hud.toast("%s\nTrouve « %s » avant %s : pas de GPS, seulement la zone sur la carte." % [m.titre, l.n, act._fmt(_limite)], 6.0)

## Lieu trouvé (activities.gd).
func chasse_finie(t: float) -> void:
	var m := mission(en_cours)
	if m.is_empty() or String(m.genre) != "chasse":
		return
	en_cours = ""
	_phase = ""
	_reussir(m, "\n" + (str(m.ok) % act._fmt(t)))

# ================================================================ service de nuit (taxi)
func _nuit_debut(m: Dictionary) -> void:
	_heure_avant = int(main.time_of_day)
	main.set_time(3)
	_courses = 0
	_etoiles = 0
	act._taxi_start()
	_phase = "nuit"
	hud.toast("%s\nLa nuit tombe sur Bourgoin… %d courses, au moins %d étoiles de moyenne." % [m.titre, int(m.courses), int(m.etoiles)], 6.0)

func _rendre_heure() -> void:
	if _heure_avant >= 0 and main:
		main.set_time(_heure_avant)
	_heure_avant = -1

func _nuit_course(m: Dictionary, etoiles: int) -> void:
	_courses += 1
	_etoiles += etoiles
	var moy := float(_etoiles) / float(_courses)
	var fin := etoiles <= 2 or _courses >= int(m.courses)
	if not fin:
		get_tree().create_timer(2.0).timeout.connect(func():
			hud.toast("Service de nuit : course %d / %d, moyenne %s ★" % [_courses, int(m.courses), ("%.1f" % moy).replace(".", ",")], 3.5))
		return
	en_cours = ""
	_phase = ""
	act.call_deferred("_stop")
	get_tree().create_timer(2.0).timeout.connect(_rendre_heure)
	if etoiles <= 2:
		_rater(m, "Client mécontent (%d ★) : la centrale te retire du service." % etoiles)
	elif moy < float(m.etoiles):
		_rater(m, "Moyenne de %s ★ : la centrale attendait mieux." % ("%.1f" % moy).replace(".", ","))
	else:
		_reussir(m, "\n%d courses, moyenne %s ★" % [_courses, ("%.1f" % moy).replace(".", ",")])

# ================================================================ duel contre un rival
func _defi() -> void:
	var m := mission(en_cours)
	if m.is_empty() or String(m.genre) != "duel":
		return
	_phase = "defi"
	car.hold(0.5)
	var rv: Dictionary = RIVAUX[m.rival]
	var bilan := duel_bilan(String(m.rival))
	var r: Array = rv.avant[mini(int(bilan[0]) + int(bilan[1]), rv.avant.size() - 1)]
	_dire(str(r[0]), rv)
	_bulle_choix(str(rv.nom), str(r[0]), [str(r[1]), str(r[2])], func(_r: int):
		_dire(str(rv.ripostes[randi() % rv.ripostes.size()]), rv)
		_lancer_duel())

func _lancer_duel() -> void:
	var m := mission(en_cours)
	var rv: Dictionary = RIVAUX[m.rival]
	var id := int(m.epreuve)
	var e: Dictionary = act.epreuves[id]
	act.mode = ""
	act._epreuve_depart(id, 0, false)             # pose la voiture, 3-2-1 ; le rival part au « Partez ! »
	_rival = act.ajouter_concurrent(String(rv.voiture), String(rv.court), float(e["or"]) * float(m.allure), 1, rv.couleur)
	_phase = "course"

## Course d'une mission (duel, course, manche) arrêtée par ■ : fin de la mission.
func _course_process() -> void:
	if act.mode == "course" and act._phase == "course":
		if _rival and is_instance_valid(_rival) and _rival.fini and _phase == "course":
			_phase = "rival_arrive"
			hud.toast("%s a franchi la ligne en %s !" % [_rival.nom, act._fmt(_rival.t_arrivee)], 4.0)
	elif act.mode == "" and _phase in ["course", "rival_arrive"]:
		arreter()

# ================================================================ championnat (chapitre 4)
func recommencer_championnat() -> void:
	champ = _champ_vide()
	for k in 5:
		faites.erase("manche%d" % (k + 1))
	sauver()

## Classement du championnat : [[id, points]…], meilleur d'abord (à égalité, le joueur devant).
func classement() -> Array:
	var l := []
	for id in ["joueur"] + ORDRE_RIVAUX:
		l.append([id, int(champ.points.get(id, 0))])
	l.sort_custom(func(a, b): return a[1] > b[1] or (a[1] == b[1] and a[0] == "joueur"))
	return l

func nom_court(id: String) -> String:
	return "Vous" if id == "joueur" else str(RIVAUX[id].court)

func _texte_classement() -> String:
	var t := PackedStringArray()
	for x in classement():
		t.append("%s %d" % [nom_court(x[0]), x[1]])
	return "Classement : " + " · ".join(t)

func _defi_manche(m: Dictionary) -> void:
	_phase = "defi"
	car.hold(0.5)
	var n := int(m.n)
	var rv: Dictionary = RIVAUX[ORDRE_RIVAUX[(n - 1) % ORDRE_RIVAUX.size()]]
	var ligne := str(rv.manche) if n <= 3 else ("Dernière manche : tout se joue maintenant !" if n == 5 else str(rv.ripostes[0]))
	_dire(ligne, rv)
	var tete := "" if n == 1 or carriere_finie() else "\n" + _texte_classement()
	_bulle_choix("%s · manche %d / 5" % [rv.nom, n], "« %s »%s" % [ligne, tete], ["C'est parti !"], func(_r: int): _lancer_manche(), false)

func _lancer_manche() -> void:
	var m := mission(en_cours)
	var id := int(m.epreuve)
	var e: Dictionary = act.epreuves[id]
	act.mode = ""
	act._epreuve_depart(id, int(m.niveau), false)
	_concs = {}
	for k in ORDRE_RIVAUX.size():
		var rid: String = ORDRE_RIVAUX[k]
		var rv: Dictionary = RIVAUX[rid]
		_concs[rid] = act.ajouter_concurrent(String(rv.voiture), String(rv.court), float(e["or"]) * float(rv.allure), k + 1, rv.couleur)
	act._course_ia = true                          # place affichée, prime de la place, concurrents détruits
	_phase = "course"

## Arrivée du joueur à une manche : ordre d'arrivée (les rivaux pas encore arrivés derrière lui, selon le chemin qui leur
## reste), points, classement ; après la 5e manche, champion ou championnat perdu.
func _fin_manche(m: Dictionary, t: float) -> void:
	var expo := carriere_finie()                   # déjà champion : manche rejouée pour le plaisir, classement inchangé
	var l := [["joueur", t, 0.0]]
	for rid in ORDRE_RIVAUX:
		var c = _concs.get(rid)
		if c and is_instance_valid(c):
			l.append([rid, c.t_arrivee if c.fini else INF, 0.0 if c.fini else c.longueur - c.s])
		else:
			l.append([rid, INF, INF])
	l.sort_custom(func(a, b): return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2]))
	var ordre := []
	for k in l.size():
		ordre.append(l[k][0])
		if not expo:
			champ.points[l[k][0]] = int(champ.points.get(l[k][0], 0)) + POINTS[k]
	if not expo:
		champ.manche = int(m.n)
		champ.resultats.append(ordre)
		faites[m.id] = true
		sauver()
	_concs = {}
	en_cours = ""
	_phase = ""
	var place := ordre.find("joueur") + 1
	var txt := PackedStringArray()
	for k in ordre.size():
		txt.append("%s %s" % [act._rang(k + 1), nom_court(ordre[k])])
	var corps := "Arrivée : %s" % ", ".join(txt) + ("" if expo else "\n" + _texte_classement())
	var fin := int(m.n) >= 5 and not expo
	var champion: bool = fin and classement()[0][0] == "joueur"
	if fin:
		corps += "\n" + ("Tu es champion du Nord-Isère !" if champion else "Championnat perdu : %s est champion. Tu peux le recommencer (★ > Carrière)." % nom_court(classement()[0][0]))
	get_tree().create_timer(2.5).timeout.connect(func():
		_bulle_choix("Championnat · manche %d / 5 · %s" % [int(m.n), act._rang(place)], corps, ["OK"], func(_r: int): pass)
		act._bip.play()
		if champion:
			reps[CHAPITRES.size() - 1] = 100.0
			sauver()
			get_tree().create_timer(4.0).timeout.connect(_message_fin.bind(CHAPITRES.size() - 1)))

# ================================================================ fin d'épreuve (activities.gd)
## Missions « chrono », « course », « duel » et « manche », bonus de médaille du jeu libre.
func epreuve_finie(id: int, t: float, med: String, avant: String, place := 1) -> void:
	const BONUS := {"or": 5.0, "argent": 3.0, "bronze": 2.0}
	var chrono := false
	for k in CHAPITRES.size():
		if not ouvert(k):
			continue
		for m in CHAPITRES[k].missions:
			if String(m.genre) == "chrono" and int(m.epreuve) == id and med != "" and not faites.has(m.id) \
					and MEDAILLES.find(med) <= MEDAILLES.find(str(m.medaille)):
				_reussir(m, "\n%s : médaille de %s" % [act._fmt(t), med])
				chrono = true
	if not chrono and commencee and med != "" and (avant == "" or MEDAILLES.find(med) < MEDAILLES.find(avant)):
		var b := float(BONUS[med]) - (float(BONUS[avant]) if avant != "" else 0.0)
		if b > 0.0:
			gagner(b, "médaille de %s" % med)
	var m := mission(en_cours)
	if m.is_empty() or not m.has("epreuve") or int(m.epreuve) != id:
		return
	match String(m.genre):
		"course":
			en_cours = ""
			_phase = ""
			if place <= int(m.place):
				_reussir(m, "\n%s · %s" % [act._rang(place), act._fmt(t)])
			else:
				_rater(m, "Arrivé %s : il fallait finir dans les %d premiers." % [act._rang(place), int(m.place)])
		"manche":
			_fin_manche(m, t)
		"duel":
			if _rival == null or not is_instance_valid(_rival):
				return
			var rid := String(m.rival)
			var rv: Dictionary = RIVAUX[rid]
			var tr: float = _rival.t_arrivee if _rival.fini else INF
			var gagne := t < tr
			var bilan: Array = duel_bilan(rid).duplicate()
			bilan[0 if gagne else 1] = int(bilan[0 if gagne else 1]) + 1
			duels[rid] = bilan
			sauver()
			_rival = null
			en_cours = ""
			_phase = ""
			get_tree().create_timer(2.5).timeout.connect(func():
				var ligne := str(rv.victoire) if gagne else str(rv.defaite)
				_dire(ligne, rv)
				_bulle_choix(str(rv.nom), ligne, ["OK"], func(_r: int): pass)
				if gagne:
					_reussir(m, "\nVous : %s · %s : %s" % [act._fmt(t), rv.court, act._fmt(tr) if tr < INF else "pas encore arrivé"])
				else:
					_rater(m, "%s a gagné de %s." % [rv.court, act._fmt(t - tr)]))

# ================================================================ jeu libre : bonus et pertes
func taxi_course(etoiles: int) -> void:
	var m := mission(en_cours)
	if not m.is_empty() and String(m.genre) == "nuit" and _phase == "nuit":
		_nuit_course(m, etoiles)
		return
	if not commencee:
		return                                      # carrière pas commencée : rien
	if etoiles >= 4:
		gagner(1.0, "client content")
	elif etoiles <= 2:
		gagner(-1.0, "client mécontent")

func decor_casse() -> void:
	if en_cours == "" or _casses >= 5:
		return
	_casses += 1
	gagner(-1.0, "décor cassé pendant la mission")

func explosion() -> void:
	if not commencee:
		return
	gagner(-3.0, "KA-BOOM")

# ================================================================ boucle
func _process(dt: float) -> void:
	if get_tree().paused or car == null:
		return
	match _phase:
		"aller":
			var m := mission(en_cours)
			if String(m.get("genre", "")) == "livraison":
				_livraison_process(dt)
			elif not m.is_empty():
				act._itineraire(dt, act._rp(_depart))
				var d: float = act._car2().distance_to(act._rp(_depart))
				var qui := "%s vous attend" % RIVAUX[m.rival].court if String(m.genre) == "duel" else "départ"
				act._set_status("%s\n%s : %d m" % [m.titre, qui, int(d)])
				if _arrive(d, car.kmh() < 10.0, dt):
					_au_depart()
		"livre":
			_livraison_process(dt)
		"guide":
			act._itineraire(dt, act._rp(_depart))
			if act._car2().distance_to(act._rp(_depart)) < 25.0:
				_phase = ""
				act._clear_world()
		"chasse":
			if act.mode != "chasse":
				if en_cours != "":
					arreter()                       # chasse arrêtée (■)
			elif act._t > _limite:
				var m := mission(en_cours)
				en_cours = ""
				_phase = ""
				act._stop()
				_rater(m, str(m.rate))
		"nuit":
			if act.mode != "taxi":
				arreter()                           # service arrêté (■)
		"course", "rival_arrive":
			_course_process()

func _physics_process(dt: float) -> void:
	if _phase != "livre" or car == null or get_tree().paused:
		return
	_choc_cd -= dt
	var v := car.linear_velocity
	if _choc_cd <= 0.0 and (v - _prev_v).length() > 5.5 and not car.carried:
		_chocs += 1
		_choc_cd = 1.0
		var m := mission(en_cours)
		if _chocs >= 3:
			_fin_mission()
			_rater(m, str(m.casse))
		else:
			hud.toast(str(m.aie) % _chocs, 2.0)
	_prev_v = v

# ================================================================ bulles et messages
## Réplique lue par la voix du téléphone (voix du rival), si l'appareil en a une.
func _dire(t: String, rv: Dictionary) -> void:
	# essais sous Linux : speech-dispatcher fige parfois le jeu (connu, voir CLAUDE.md) : pas de voix
	if OS.get_cmdline_user_args().has("--drive-test") or not VT.dispo():
		return
	var g := int(rv.get("graine", 4242))
	if not _voix.has(g):
		_voix[g] = VT.choisir(str(rv.get("voix", "m")), g)
	if not (_voix[g] as Dictionary).is_empty():
		VT.dire(t, _voix[g], float(preload("res://scripts/audio.gd").volumes["voix"]))

## Bulle d'un personnage (nom, réplique) avec des réponses ; f(k) reçoit l'indice de la réponse touchée.
func _bulle_choix(qui: String, texte: String, reponses: Array, f: Callable, cite := true) -> void:
	_fermer_bulle()
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UI.panel(28, 16))
	pc.add_to_group("ui_zone")
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	pc.add_child(v)
	var n := Label.new()
	n.text = qui
	n.add_theme_font_size_override("font_size", 24)
	n.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45))
	v.add_child(n)
	var l := Label.new()
	l.text = "« %s »" % texte if cite and not qui.begins_with("✉") and not qui.begins_with("Championnat") else texte
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(minf(900.0, act._vs().x - 120.0), 0)
	l.add_theme_font_size_override("font_size", 28)
	v.add_child(l)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	v.add_child(h)
	for k in reponses.size():
		var b := Button.new()
		b.text = str(reponses[k])
		b.custom_minimum_size = Vector2(0, 70)
		b.add_theme_font_size_override("font_size", 26)
		b.pressed.connect(func():
			_fermer_bulle()
			f.call(k))
		h.add_child(b)
	act.add_child(pc)
	_bulle = pc
	pc.reset_size()
	var vs: Vector2 = act._vs()
	pc.position = Vector2((vs.x - pc.size.x) / 2.0, maxf(20.0, vs.y - pc.size.y - 250.0))

func _fermer_bulle() -> void:
	if _bulle and is_instance_valid(_bulle):
		_bulle.queue_free()
	_bulle = null

## Message de fin de chapitre (« sur le téléphone ») et voiture offerte.
func _message_fin(ch: int) -> void:
	if fins_vues.has(ch):
		return
	fins_vues.append(ch)
	var cadeau := _offrir(String(CHAPITRES[ch].cadeau))
	sauver()
	var fin: Dictionary = CHAPITRES[ch].fin
	_bulle_choix("✉ Message de " + str(fin.de), str(fin.texte) + cadeau, ["Super !"], func(_r: int): pass)
	act._bip.play()

## Voiture offerte en fin de chapitre (sa demi-valeur en prime si on l'a déjà) ; texte ajouté au message.
func _offrir(id: String) -> String:
	var g = main.get("garage") if main else null
	if g == null or id == "" or not Voitures.CATALOGUE.has(id):
		return ""
	var nom := str(Voitures.CATALOGUE[id].nom)
	if g.a_voiture(id):
		var p := roundf(float(Voitures.CATALOGUE[id].prix) / 2.0)
		g.gagner(p)
		return "\n\n(Tu as déjà la %s : %s en prime à la place.)" % [nom, g.euros(p)]
	g.voitures.append(id)
	g.sauver()
	g.change.emit()
	return "\n\nCadeau : %s, ajoutée au garage." % nom
