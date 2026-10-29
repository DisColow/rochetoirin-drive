## Gendarmes (#150, initiative de Claude, hypothèses à valider dans l'issue) : patrouilles et courses-poursuites en
## balade libre (pas pendant les activités : taxi, bus, courses, chasse, balade automatique).
## - Une patrouille (gendarme.gd) passe de temps en temps près du joueur (toutes les PATROUILLE s).
## - Infraction commise sous les yeux d'un gendarme (à moins de VU m, en vue) : excès de vitesse (EXCES km/h au-dessus
##   de la vitesse autorisée de la route, circulation.limite), feu rouge grillé (circulation.feu_franchi), voiture de
##   la circulation percutée (circulation._accident), gendarme embouti ; gendarme détruit : 3 étoiles d'office.
##   Niveau de recherche 1 à 3 étoiles ; autant de voitures à la poursuite que d'étoiles (renforts hors de vue).
## - Les gendarmes foncent sur le joueur quand ils le voient, sinon vers l'endroit où il a été vu pour la dernière fois
##   (piste) ; les renforts ne sont appelés que s'il est en vue (ou s'il n'y a plus personne : une voiture fouille).
## - Semés : aucun gendarme à moins de SEMER_D m en vue pendant SEMER_T s -> prime, succès.
## - Arrestation : moins de ARRET_V km/h à moins de ARRET_D m d'un gendarme pendant ARRET_T s -> amende.
## - Bandeau en haut de l'écran : étoiles, distance du plus proche, compte à rebours pour semer ou de l'arrestation.
## Essai : --drive-test --gendarmes-test (essais.gd).
extends Node

const Gendarme := preload("res://scripts/gendarme.gd")
const VU := 120.0
const SEMER_D := 250.0
const SEMER_T := 20.0
const ARRET_D := 9.0
const ARRET_V := 5.0
const ARRET_T := 3.0
const AMENDE := 50.0                # par étoile
const PRIME := 30.0                 # par étoile
const EXCES := 30.0
const PATROUILLE := Vector2(70.0, 160.0)
const R_APPARITION := Vector2(150.0, 260.0)
const R_DISPARITION := 450.0
const RENFORT := 6.0                # s entre deux renforts
const NIVEAUX := {"vitesse": 1, "feu": 1, "accrochage": 1, "gendarme": 2, "explosion": 3}
const MOTIFS := {"vitesse": "excès de vitesse", "feu": "feu rouge grillé", "accrochage": "accident",
	"gendarme": "voiture de gendarmerie emboutie", "explosion": "voiture de gendarmerie détruite"}

var main: Node
var actif := true                   # ⚙ > Conduite > Gendarmes
var etoiles := 0
var liste: Array = []               # gendarme.gd
var semes := 0                      # essais
var arrestations := 0
var dernier := ""                   # dernière infraction relevée (essais)

var _vu_t := 0.0                    # temps sans être vu (poursuite)
var _vu_pos := Vector3.INF          # où le joueur a été vu pour la dernière fois
var _arret_t := 0.0
var _patrouille_t := 45.0
var _renfort_t := 0.0
var _prec := Vector3.INF
var _vit_t := 0.0
var _infr_t := 0.0                  # délai entre deux infractions comptées
var _choc_t := 0.0
var _itin                           # graphe routier (points d'apparition)
var _bandeau: Label

func _ready() -> void:
	_itin = preload("res://scripts/itineraire.gd").new()
	var cl := CanvasLayer.new()
	cl.layer = 5
	add_child(cl)
	_bandeau = Label.new()
	_bandeau.add_theme_font_size_override("font_size", 30)
	_bandeau.add_theme_color_override("font_color", Color(1.0, 0.92, 0.55))
	_bandeau.add_theme_color_override("font_outline_color", Color(0.02, 0.05, 0.2))
	_bandeau.add_theme_constant_override("outline_size", 10)
	_bandeau.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bandeau.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)          # en bas, entre les commandes tactiles
	_bandeau.offset_left = -400.0; _bandeau.offset_right = 400.0
	_bandeau.offset_top = -190.0; _bandeau.offset_bottom = -110.0
	_bandeau.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_bandeau.visible = false
	cl.add_child(_bandeau)

func set_actif(on: bool) -> void:
	actif = on
	if not on:
		_fin("")

## Voitures des gendarmes (corps physiques : la circulation les évite et s'écarte, #132).
func voitures() -> Array:
	var l := []
	for g in liste:
		if is_instance_valid(g) and not g.blown and is_instance_valid(g.voiture) and not g.fige:
			l.append(g.voiture)
	return l

## Gendarmes en balade libre seulement : ni activité en cours, ni à pied.
func _permis() -> bool:
	if not actif or not main.get("car") or not main.car.controle:
		return false
	var act = main.get("activities")
	return act == null or str(act.get("mode")) == ""

func _temoin(p: Vector3) -> bool:
	for g in liste:
		if is_instance_valid(g) and not g.blown and g.mode != "repli":
			var q: Vector3 = g.voiture.global_position
			if q.distance_to(p) < VU and g.en_vue(q, p):
				return true
	return false

## Infraction du joueur en p (motif : clé de NIVEAUX) : comptée si un gendarme la voit (une voiture de gendarmerie
## emboutie ou détruite l'est toujours).
func infraction(motif: String, p: Vector3) -> void:
	if not _permis() or _infr_t > 0.0:
		return
	if motif not in ["gendarme", "explosion"] and not _temoin(p):
		return
	_infr_t = 4.0
	dernier = motif
	_vu_pos = p
	var avant := etoiles
	etoiles = clampi(maxi(etoiles + (1 if etoiles > 0 else 0), int(NIVEAUX[motif])), 1, 3)
	_vu_t = 0.0
	for g in liste:
		if is_instance_valid(g) and not g.blown:
			g.mode = "poursuite"
			g.voir_gyros(true)
	main.get_node("HUD").toast("Gendarmerette : %s ! %s" % [MOTIFS[motif], _etoiles_txt()], 3.0)
	if avant == 0:
		_renfort_t = 1.5
	print("[gendarmes] infraction : %s, %d étoile(s)" % [motif, etoiles])

func _etoiles_txt() -> String:
	return "★".repeat(etoiles) + "☆".repeat(3 - etoiles)

## Où les gendarmes vont chercher le joueur : sa position s'ils le voient (ou l'ont vu il y a moins de 2 s), sinon
## l'endroit où il a été vu pour la dernière fois : [position, vitesse].
func piste() -> Array:
	var car = main.get("car")
	if car and (_vu_t < 2.0 or not _vu_pos.is_finite()):
		return [car.global_position, car.linear_velocity]
	return [_vu_pos, Vector3.ZERO]

## Point d'apparition : nœud du graphe routier entre R_APPARITION.x et .y m du joueur, de préférence derrière la
## caméra et hors de vue ; Vector2.INF sinon.
func _point_apparition() -> Vector2:
	if not _itin.ok:
		return Vector2.INF
	var j: Vector3 = main.car.global_position
	var cam := get_viewport().get_camera_3d()
	var av: Vector3 = -cam.global_transform.basis.z if cam else main.car.global_transform.basis.z
	var best := Vector2.INF
	var bs := -INF
	var c := Vector2i(floori(j.x / _itin.CASE), floori(j.z / _itin.CASE))
	for dx in range(-3, 4):
		for dz in range(-3, 4):
			for i: int in _itin.grille.get(c + Vector2i(dx, dz), PackedInt32Array()):
				var q := Vector2(_itin.nx[i], _itin.nz[i])
				var d := q.distance_to(Vector2(j.x, j.z))
				if d < R_APPARITION.x or d > R_APPARITION.y:
					continue
				var dir := (q - Vector2(j.x, j.z)) / d
				var sc := -dir.dot(Vector2(av.x, av.z)) + randf() * 0.6
				if sc > bs:
					bs = sc; best = q
	return best

func _apparaitre(mode: String) -> void:
	var p := _point_apparition()
	if p == Vector2.INF:
		return
	var g := Gendarme.new()
	g.main = self.main
	g.mode = mode
	add_child(g)
	var j: Vector3 = main.car.global_position
	g.poser(p, Vector2(j.x, j.z))
	if mode == "poursuite":
		g.voir_gyros(true)
		var q: Vector3 = piste()[0]
		g.aller(Vector2(q.x, q.z))
	liste.append(g)
	print("[gendarmes] %s à %.0f m" % [mode, p.distance_to(Vector2(j.x, j.z))])

func _physics_process(dt: float) -> void:
	_infr_t = maxf(_infr_t - dt, 0.0)
	_choc_t = maxf(_choc_t - dt, 0.0)
	var car = main.get("car")
	if car == null:
		return
	var p: Vector3 = car.global_position
	_menage(p)
	if not _permis():
		if etoiles > 0 or not liste.is_empty():
			_fin("")
		_prec = Vector3.INF
		return
	# infractions : vitesse (toutes les 0,5 s), feu rouge, gendarme embouti
	_vit_t -= dt
	var circ = main.get("circulation")
	if circ and _vit_t <= 0.0:
		_vit_t = 0.5
		var lim: float = circ.limite(p)
		if lim > 0.0 and car.kmh() > lim + EXCES:
			infraction("vitesse", p)
	if circ and _prec.is_finite() and car.kmh() > 10.0 and circ.feu_franchi(_prec, p):
		infraction("feu", p)
	_prec = p
	for g in liste:
		if not is_instance_valid(g) or g.blown or g.fige:
			continue
		if g.voiture in car.get_colliding_bodies() and _choc_t <= 0.0:
			_choc_t = 2.0
			var rel: Vector3 = car.linear_velocity - g.voiture.linear_velocity
			if rel.dot((g.voiture.global_position - p).normalized()) > 4.0:
				infraction("gendarme", p)
	# patrouilles et renforts
	if etoiles == 0:
		_patrouille_t -= dt
		if _patrouille_t <= 0.0 and liste.is_empty():
			_patrouille_t = randf_range(PATROUILLE.x, PATROUILLE.y)
			_apparaitre("patrouille")
		_bandeau.visible = false
		return
	var actifs := 0
	for g in liste:
		if is_instance_valid(g) and not g.blown and g.mode == "poursuite":
			actifs += 1
	_renfort_t -= dt
	# renforts appelés par ceux qui vous voient ; plus personne à vos trousses : une voiture vient fouiller le secteur
	var fouille := actifs == 0 and _vu_pos.is_finite() and _vu_pos.distance_to(p) < R_DISPARITION - 150.0
	if _renfort_t <= 0.0 and ((actifs < etoiles and _vu_t < 3.0) or fouille):
		_renfort_t = RENFORT
		_apparaitre("poursuite")
	_poursuite(dt, car, p)

## Pendant la poursuite : vu ou non, arrestation, semés, bandeau.
func _poursuite(dt: float, car: Node, p: Vector3) -> void:
	var dmin := INF
	var vu := false
	for g in liste:
		if not is_instance_valid(g) or g.blown or g.mode != "poursuite":
			continue
		var q: Vector3 = g.voiture.global_position
		var d := q.distance_to(p)
		dmin = minf(dmin, d)
		if d < SEMER_D and (d < 40.0 or g.en_vue(q, p)):
			vu = true
	_vu_t = 0.0 if vu else _vu_t + dt
	if vu:
		_vu_pos = p
	if car.kmh() < ARRET_V and dmin < ARRET_D:
		_arret_t += dt
	else:
		_arret_t = maxf(_arret_t - dt * 2.0, 0.0)
	var t := "%s  GENDARMERETTE" % _etoiles_txt()
	if dmin < INF:
		t += "  ·  %d m" % int(dmin)
	if _arret_t > 0.0:
		t += "\nArrestation dans %.0f s : repartez !" % ceilf(ARRET_T - _arret_t)
	elif _vu_t > 0.0:
		t += "\nHors de vue : semés dans %.0f s" % ceilf(SEMER_T - _vu_t)
	_bandeau.text = t
	_bandeau.visible = true
	if _arret_t >= ARRET_T:
		var amende := AMENDE * etoiles
		arrestations += 1
		var g = main.get("garage")
		if g:
			amende = g.payer(amende)
		if main.get("succes"):
			main.succes.noter("arrestations")
		_fin("Arrêté par la Gendarmerette : %s d'amende." % _euros(amende))
	elif _vu_t >= SEMER_T:
		var prime := PRIME * etoiles
		semes += 1
		var g = main.get("garage")
		if g:
			g.gagner(prime)
		if main.get("succes"):
			main.succes.noter("semes")
		_fin("Vous avez semé la Gendarmerette ! +%s" % _euros(prime))

func _euros(v: float) -> String:
	return ("%.2f €" % v).replace(".", ",")

## Fin de la poursuite : les gendarmes se replient (puis disparaissent hors de vue).
func _fin(msg: String) -> void:
	if msg != "":
		main.get_node("HUD").toast(msg, 4.0)
		print("[gendarmes] fin : %s" % msg)
	etoiles = 0
	_vu_t = 0.0
	_arret_t = 0.0
	_bandeau.visible = false
	_patrouille_t = randf_range(PATROUILLE.x, PATROUILLE.y)
	for g in liste:
		if is_instance_valid(g) and not g.blown:
			g.mode = "repli"
			g.voir_gyros(false)

## Gendarmes détruits (explosion : rendus après 4 s), loin, ou repliés hors de vue : retirés.
func _menage(p: Vector3) -> void:
	var cam := get_viewport().get_camera_3d()
	for k in range(liste.size() - 1, -1, -1):
		var g = liste[k]
		if not is_instance_valid(g):
			liste.remove_at(k)
			continue
		var q: Vector3 = g.voiture.global_position
		var d := q.distance_to(p)
		var cache: bool = cam == null or cam.is_position_behind(q) or d > 150.0
		if d > R_DISPARITION or (g.mode == "repli" and cache and d > 60.0) or (g.blown and g.boum_t > 4.0) \
				or (g.mode == "patrouille" and d > 320.0 and cache):
			print("[gendarmes] retiré : %s à %.0f m%s" % [g.mode, d, " (détruit)" if g.blown else ""])
			g.queue_free()
			liste.remove_at(k)

## Gendarme détruit par un choc (gendarme.gd) : 3 étoiles.
func detruit(g: Node) -> void:
	infraction("explosion", g.voiture.global_position)
