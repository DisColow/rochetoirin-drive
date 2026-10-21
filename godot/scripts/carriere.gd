## Mode carrière (#120, chapitre 1 « Le village », validé par l'utilisateur le 21/10 : chapitre 1 seul, carte libre,
## rival en fantôme qui roule en même temps).
## - Onglet « Carrière » du menu Activités (menu_activites.gd) : jauge de réputation, missions, rival ; chaque mission
##   se lance de là (itinéraire GPS jusqu'à son départ, ou « Y aller » : la voiture y est posée).
## - Missions : livraison (boulangerie, chargement fragile, temps limité, ici), taxi imposé (le maire : la course de
##   taxi d'activities.gd avec `impose`), premier chrono (médaille sur une épreuve), duel (épreuve contre le fantôme du
##   rival, fantome.gd).
## - Réputation (0 à 100) : 25 par mission ; bonus du jeu libre (médailles d'épreuves, clients contents) ; pertes
##   (décor cassé pendant une mission, client mécontent, KA-BOOM). À 100 : message d'un personnage (suite à venir).
## - Progression gardée dans user://carriere.cfg ; le jeu libre ne change pas.
extends Node

const UI := preload("res://scripts/ui.gd")
const VT := preload("res://scripts/voix_tel.gd")
const FICHIER := "user://carriere.cfg"
const BOULANGERIE := Vector2(49.0, 410.0)        # Chez Flonflon, boulangerie de Rochetoirin (sur mesure)
const STOP_R := 14.0
const MEDAILLES := ["or", "argent", "bronze"]
const RIVAL := {"nom": "Kévin Turbot", "court": "Kévin", "voiture": "p106"}
const MISSIONS := [
	{"id": "pain", "titre": "Le pain du matin", "genre": "livraison", "rep": 25, "prime": 150.0,
	 "texte": "Flonflon, le boulanger, a trois commandes à livrer : l'école de Rochetoirin, la mairie de Saint-Jean-de-Soudain et Montbertaud. Chargement fragile : au troisième gros choc, la tarte est fichue.",
	 "arrets": ["École primaire publique Rochetoirin", "Mairie de Saint-Jean-de-Soudain", "Montbertaud"]},
	{"id": "maire", "titre": "Monsieur le maire", "genre": "taxi", "rep": 25, "prime": 120.0,
	 "texte": "Le maire est coincé à la mairie de Saint-Chef. Ramène-le à la mairie de Rochetoirin avant l'ouverture du conseil municipal.",
	 "depart": "Mairie de Saint-Chef", "arrivee": "Mairie de Rochetoirin"},
	{"id": "chrono", "titre": "Premier chrono", "genre": "chrono", "rep": 25, "prime": 0.0, "epreuve": 14, "medaille": "bronze",
	 "texte": "Montre au village que tu sais conduire : au moins le bronze au sprint de la place des Anciens Combattants."},
	{"id": "duel", "titre": "Le duel", "genre": "duel", "rep": 25, "prime": 200.0, "epreuve": 0, "allure": 0.88,
	 "texte": "Kévin Turbot et sa Pijo 106 font la loi au village. Il te défie jusqu'à la chapelle Saint-Joseph : il roule en même temps que toi, en fantôme."},
]
const REPLIQUES_AVANT := [
	["Alors, c'est toi le nouveau ? Ma 106 va te mettre une raclée.", "On en reparle à l'arrivée.", "Tu parles beaucoup pour un pot de yaourt."],
	["Encore toi ? Tu n'as pas eu ta dose la dernière fois ?", "Cette fois, c'est la bonne.", "Je m'échauffais."],
]
const RIPOSTES := ["Ha ! On verra bien.", "Cause toujours…", "Accroche-toi à ton volant !"]
const APRES_VICTOIRE := "Pff… coup de chance. Profite, ça ne durera pas."
const APRES_DEFAITE := "Retourne à ton tracteur, gamin ! Reviens quand tu sauras conduire."
const MESSAGE_FIN := {"de": "Flonflon (le boulanger)",
	"texte": "Tout le village parle de toi ! Même Kévin a arrêté de crâner. Il paraît qu'on te réclame dans la vallée… La suite arrive bientôt : chapitre 2, « La vallée »."}

var main: Node
var act: Node                      # activities.gd
var hud: CanvasLayer
var car: VehicleBody3D
var rep := 0.0
var faites := {}                   # mission -> true
var message_vu := false
var commencee := false             # une mission a été lancée : les bonus et pertes du jeu libre comptent
var victoires := 0
var defaites := 0
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
var _fantome: Node3D
var _bulle: Control
var _voix := {}

func _ready() -> void:
	charger()

func charger() -> void:
	var c := ConfigFile.new()
	if c.load(FICHIER) != OK:
		return
	rep = float(c.get_value("carriere", "reputation", 0.0))
	faites = c.get_value("carriere", "faites", {})
	message_vu = bool(c.get_value("carriere", "message_vu", false))
	commencee = bool(c.get_value("carriere", "commencee", false))
	victoires = int(c.get_value("carriere", "victoires", 0))
	defaites = int(c.get_value("carriere", "defaites", 0))

func sauver() -> void:
	var c := ConfigFile.new()
	c.set_value("carriere", "reputation", rep)
	c.set_value("carriere", "faites", faites)
	c.set_value("carriere", "message_vu", message_vu)
	c.set_value("carriere", "commencee", commencee)
	c.set_value("carriere", "victoires", victoires)
	c.set_value("carriere", "defaites", defaites)
	c.save(FICHIER)

func mission(id: String) -> Dictionary:
	for m in MISSIONS:
		if m.id == id:
			return m
	return {}

func chapitre_fini() -> bool:
	return rep >= 100.0

## Réputation : gain ou perte (bandeau), sauvegarde ; à 100, message de fin de chapitre.
func gagner(n: float, raison: String) -> void:
	if chapitre_fini():
		return
	var avant := rep
	rep = clampf(rep + n, 0.0, 100.0)
	if is_equal_approx(avant, rep):
		return
	sauver()
	if hud:
		hud.toast("%+d réputation : %s  (%d / 100)" % [int(round(rep - avant)), raison, int(rep)], 4.0)
	if rep >= 100.0 and not message_vu:
		get_tree().create_timer(4.5).timeout.connect(_message_fin)

# ================================================================ lancement des missions
## Lance une mission depuis l'onglet Carrière : y_aller = la voiture est posée au départ ; sinon itinéraire GPS.
func lancer(id: String, y_aller: bool) -> void:
	var m := mission(id)
	if m.is_empty():
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
			_maire(m, y_aller)
		"chrono":
			var e: Dictionary = act.epreuves[int(m.epreuve)]
			if y_aller:
				act._epreuve_depart(int(m.epreuve))
			else:
				_vers(Vector2(e.a[0], e.a[1]), "Départ de l'épreuve : " + str(e.nom))
		"duel":
			en_cours = id
			act.mode = "mission"
			act.map.locked = true
			var e: Dictionary = act.epreuves[int(m.epreuve)]
			var a := Vector2(e.a[0], e.a[1])
			_depart = act._nearest(a)
			if y_aller:
				var s: Array = act._start_at(_depart, Vector2(e.etapes[0][0], e.etapes[0][1]))
				hud.teleport.emit(s[0], s[1])
				_phase = "defi"
				get_tree().create_timer(1.2).timeout.connect(_defi)
			else:
				_phase = "aller"
				_balise(_depart, Color(0.95, 0.35, 0.3), "Kévin")

## Itinéraire GPS seul vers un point (mission sans état : premier chrono).
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

## Fin de mission (réussie, ratée, ou arrêtée par le bouton ■ d'activities.gd).
func arreter(annonce := true) -> void:
	if _fantome and is_instance_valid(_fantome):
		_fantome.queue_free()
	_fantome = null
	_fermer_bulle()
	if en_cours != "" and annonce and hud:
		hud.toast("Mission arrêtée.", 2.5)
	en_cours = ""
	_phase = ""
	_depart = -1

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
	if neuf:
		get_tree().create_timer(2.0).timeout.connect(func(): gagner(float(m.rep), String(m.titre)))
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
		for p in act.places:
			if str(p.n) == str(n):
				_arrets.append({i = act._nearest(Vector2(p.x, p.z)), nom = str(n)})
				break
	_depart = act._nearest(BOULANGERIE)
	_k = 0
	_chocs = 0
	_casses = 0
	_stop_t = 0.0
	_phase = "aller"
	if y_aller:
		var s: Array = act._start_at(_depart, act._rp(_arrets[0].i) if not _arrets.is_empty() else BOULANGERIE)
		hud.teleport.emit(s[0], s[1])
	_balise(_depart, Color(1.0, 0.75, 0.3), "Boulangerie")
	hud.toast("%s\nPassez prendre les commandes à la boulangerie Chez Flonflon." % m.titre, 5.0)

func _livraison_process(dt: float) -> void:
	var m := mission(en_cours)
	var c: Vector2 = act._car2()
	var lent: bool = car.kmh() < 10.0
	if _phase == "aller":
		act._itineraire(dt, act._rp(_depart))
		var d := c.distance_to(act._rp(_depart))
		act._set_status("Mission : %s\nBoulangerie Chez Flonflon : %d m" % [m.titre, int(d)])
		if _arrive(d, lent, dt):
			_phase = "livre"
			_t = 0.0
			# temps limite : trajet à ~43 km/h (lignes droites × 1,35) + 12 s par arrêt, arrondi aux 10 s
			var long := 0.0
			var q: Vector2 = act._rp(_depart)
			for a in _arrets:
				long += q.distance_to(act._rp(a.i)) * 1.35
				q = act._rp(a.i)
			_limite = ceilf((long / 12.0 + 12.0 * _arrets.size()) / 10.0) * 10.0
			_prev_v = car.linear_velocity
			act._bip.play()
			hud.toast("Commandes chargées : pain, croissants… et la tarte du maire.\nAttention aux chocs !", 5.0)
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
		_rater(m, "Trop tard : les clients ont déjà déjeuné.")
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

# ================================================================ taxi imposé : le maire
func _maire(m: Dictionary, y_aller: bool) -> void:
	var pick := -1
	var dest := -1
	for p in act.places:
		if str(p.n) == str(m.depart):
			pick = act._nearest(Vector2(p.x, p.z))
		if str(p.n) == str(m.arrivee):
			dest = act._nearest(Vector2(p.x, p.z))
	if pick < 0 or dest < 0:
		return
	# temps limite : ligne droite × 1,35 à ~54 km/h, + 40 s
	var limite := ceilf((act._rp(pick).distance_to(act._rp(dest)) * 1.35 / 15.0 + 40.0) / 10.0) * 10.0
	act.impose = {pick = pick, nom = "Monsieur le maire (%s)" % m.depart, dest = dest, dest_nom = str(m.arrivee), limite = limite}
	if y_aller:
		var s: Array = act._start_at(act._nearest(act._rp(pick) + Vector2(80, 0)), act._rp(pick))
		hud.teleport.emit(s[0], s[1])
	act._taxi_start()
	en_cours = String(m.id)
	_phase = "taxi"

## Fin de la course imposée (activities.gd) : à l'heure ou non.
func taxi_impose_fini(a_l_heure: bool, t: float) -> void:
	var m := mission("maire")
	en_cours = ""
	_phase = ""
	if a_l_heure:
		_reussir(m, "\nArrivé en %s : le conseil peut commencer." % act._fmt(t))
	else:
		_rater(m, "Le conseil municipal a commencé sans le maire…")

# ================================================================ duel contre le rival
func _defi() -> void:
	if en_cours != "duel":
		return
	_phase = "defi"
	car.hold(0.5)
	var r: Array = REPLIQUES_AVANT[mini(victoires + defaites, REPLIQUES_AVANT.size() - 1)]
	_dire(str(r[0]))
	_bulle_choix(str(RIVAL.nom), str(r[0]), [str(r[1]), str(r[2])], func(_r: int):
		_dire(RIPOSTES[randi() % RIPOSTES.size()])
		_lancer_duel())

func _lancer_duel() -> void:
	var m := mission("duel")
	var id := int(m.epreuve)
	var e: Dictionary = act.epreuves[id]
	act.mode = ""
	act._epreuve_depart(id)                       # pose la voiture, 3-2-1 ; le fantôme part au « Partez ! »
	_fantome = preload("res://scripts/fantome.gd").new()
	var pts := []
	for i in act._route:
		pts.append(act._rp(i))
	pts[0] = act._car2()                          # départ à côté de la voiture du joueur (déjà posée)
	_fantome.points = pts
	_fantome.temps_cible = float(e["or"]) * float(m.allure)
	_fantome.voiture = String(RIVAL.voiture)
	_fantome.nom = String(RIVAL.court)
	main.add_child(_fantome)
	en_cours = "duel"
	_phase = "course"

func _duel_process() -> void:
	if _fantome == null or not is_instance_valid(_fantome):
		return
	if act.mode == "course" and act._phase == "course":
		_fantome.t = act._t
		if act._t > _fantome.temps_cible and _phase == "course":
			_phase = "rival_arrive"
			hud.toast("%s a franchi la ligne en %s !" % [RIVAL.court, act._fmt(_fantome.temps_cible)], 4.0)
	elif act.mode == "" and _phase in ["course", "rival_arrive"]:
		arreter()                                   # course arrêtée (■)

## Fin d'une épreuve (activities.gd) : missions « premier chrono » et « duel », bonus de médaille.
func epreuve_finie(id: int, t: float, med: String, avant: String) -> void:
	const BONUS := {"or": 5.0, "argent": 3.0, "bronze": 2.0}
	var m_ch := mission("chrono")
	if id == int(m_ch.epreuve) and med != "" and not faites.has("chrono") and MEDAILLES.find(med) <= MEDAILLES.find(str(m_ch.medaille)):
		_reussir(m_ch, "\n%s : médaille de %s" % [act._fmt(t), med])
	elif commencee and med != "" and (avant == "" or MEDAILLES.find(med) < MEDAILLES.find(avant)):
		var b := float(BONUS[med]) - (float(BONUS[avant]) if avant != "" else 0.0)
		if b > 0.0:
			gagner(b, "médaille de %s" % med)
	if en_cours == "duel" and _fantome and is_instance_valid(_fantome):
		var tr: float = _fantome.temps_cible
		var gagne := t < tr
		var m := mission("duel")
		if gagne:
			victoires += 1
		else:
			defaites += 1
		sauver()
		var f := _fantome
		_fantome = null
		get_tree().create_timer(6.0).timeout.connect(func():
			if is_instance_valid(f):
				f.queue_free())
		en_cours = ""
		_phase = ""
		get_tree().create_timer(2.5).timeout.connect(func():
			var ligne := APRES_VICTOIRE if gagne else APRES_DEFAITE
			_dire(ligne)
			_bulle_choix(str(RIVAL.nom), ligne, ["OK"], func(_r: int): pass)
			if gagne:
				_reussir(m, "\nVous : %s · %s : %s" % [act._fmt(t), RIVAL.court, act._fmt(tr)])
			else:
				_rater(m, "%s a gagné de %s." % [RIVAL.court, act._fmt(t - tr)]))

# ================================================================ jeu libre : bonus et pertes
func taxi_course(etoiles: int) -> void:
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
			if en_cours == "duel":
				act._itineraire(dt, act._rp(_depart))
				var d: float = act._car2().distance_to(act._rp(_depart))
				act._set_status("Duel : %s vous attend\nau départ, %d m" % [RIVAL.court, int(d)])
				if _arrive(d, car.kmh() < 10.0, dt):
					act._clear_world()
					_phase = "defi"
					_defi()
			elif en_cours == "pain":
				_livraison_process(dt)
		"livre":
			_livraison_process(dt)
		"guide":
			act._itineraire(dt, act._rp(_depart))
			if act._car2().distance_to(act._rp(_depart)) < 25.0:
				_phase = ""
				act._clear_world()
		"course", "rival_arrive":
			_duel_process()

func _physics_process(dt: float) -> void:
	if _phase != "livre" or car == null or get_tree().paused:
		return
	_choc_cd -= dt
	var v := car.linear_velocity
	if _choc_cd <= 0.0 and (v - _prev_v).length() > 5.5 and not car.carried:
		_chocs += 1
		_choc_cd = 1.0
		if _chocs >= 3:
			var m := mission(en_cours)
			_fin_mission()
			_rater(m, "Troisième choc : la tarte du maire est en miettes.")
		else:
			hud.toast("Aïe, la tarte ! (%d / 3)" % _chocs, 2.0)
	_prev_v = v

# ================================================================ bulles et messages
## Réplique lue par la voix du téléphone (voix d'homme du rival), si l'appareil en a une.
func _dire(t: String) -> void:
	# essais sous Linux : speech-dispatcher fige parfois le jeu (connu, voir CLAUDE.md) : pas de voix
	if OS.get_cmdline_user_args().has("--drive-test") or not VT.dispo():
		return
	if _voix.is_empty():
		_voix = VT.choisir("m", 4242)
	if not _voix.is_empty():
		VT.dire(t, _voix, float(preload("res://scripts/audio.gd").volumes["voix"]))

## Bulle d'un personnage (nom, réplique) avec des réponses ; f(k) reçoit l'indice de la réponse touchée.
func _bulle_choix(qui: String, texte: String, reponses: Array, f: Callable) -> void:
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
	l.text = "« %s »" % texte
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(760, 0)
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
	pc.position = Vector2((vs.x - pc.size.x) / 2.0, vs.y - pc.size.y - 250.0)

func _fermer_bulle() -> void:
	if _bulle and is_instance_valid(_bulle):
		_bulle.queue_free()
	_bulle = null

## Message de fin de chapitre (« sur le téléphone »).
func _message_fin() -> void:
	if message_vu:
		return
	message_vu = true
	sauver()
	_bulle_choix("✉ Message de " + str(MESSAGE_FIN.de), str(MESSAGE_FIN.texte), ["Super !"], func(_r: int): pass)
	act._bip.play()
