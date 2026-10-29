## Livreur de repas (#151, initiative de Claude) : Activités > Taxi > « Livrer des repas » (activities._livreur_start,
## mode « livreur »). Tournée de NB livraisons avec sa propre voiture :
## - commande à prendre dans un des restaurants proches (world/restos.json de pipeline/build_restos.py : points OSM et
##   nom de l'enseigne en jeu), balise et GPS ; arrêt à moins de R_PRISE m (moins de V_ARRET km/h pendant 1 s) ;
## - livraison à une adresse tirée au hasard (nœud du graphe routier à D_MIN-D_MAX m, rue nommée, numéro au hasard),
##   délai d'après la distance (V_DELAI de moyenne + MARGE s) ; arrêt à moins de R_LIVRE m ;
## - état du repas : −CHOC à chaque choc ; en dessous de REFUS, le client refuse la commande ;
## - paiement : BASE + PAR_KM par km + pourboire (POURBOIRE au plus, selon l'avance) ; en retard : moitié, sans pourboire.
## Essai : --drive-test --livreur-test (essais.gd).
extends Node

const NB := 3
const R_PRISE := 25.0
const R_LIVRE := 18.0
const V_ARRET := 5.0
const D_MIN := 800.0
const D_MAX := 2500.0
const R_RESTO := 3000.0
const V_DELAI := 9.7                # m/s (35 km/h de moyenne)
const MARGE := 60.0
const DETOUR := 1.35                # longueur de la route / distance à vol d'oiseau
const CHOC := 15.0
const REFUS := 40.0
const BASE := 6.0
const PAR_KM := 0.8
const POURBOIRE := 4.0
const COULEUR_RESTO := Color(1.0, 0.55, 0.15)
const COULEUR_CLIENT := Color(0.35, 0.95, 0.45)

var main: Node
var actif := false
var restos: Array = []              # [{x, z, nom, metier, cuisine}]
var n := 0                          # livraison en cours (0..NB-1)
var phase := ""                     # « resto » : aller chercher la commande ; « client » : la livrer
var resto: Dictionary = {}
var resto_rue := ""
var dest := Vector3.ZERO
var adresse := ""
var delai := 0.0                    # temps accordé (s)
var t := 0.0                        # temps écoulé depuis la prise de la commande
var etat := 100.0                   # état du repas (%)
var gain := 0.0
var livrees := 0
var refusees := 0
var en_retard := 0
var _arret_t := 0.0
var _prev_v := Vector3.ZERO
var _prev_p := Vector3.ZERO
var _choc_cd := 0.0
var _itin                           # graphe routier (adresses)
var _deja := {}                     # restaurants déjà servis pendant la tournée

func _ready() -> void:
	var f := "res://world/restos.json"
	if FileAccess.file_exists(f):
		var d = JSON.parse_string(FileAccess.get_file_as_string(f))
		if d is Array:
			restos = d
	_itin = preload("res://scripts/itineraire.gd").new()

func _act():
	return main.activities

func demarrer() -> bool:
	if restos.is_empty() or not _itin.ok:
		return false
	n = 0
	gain = 0.0
	livrees = 0; refusees = 0; en_retard = 0
	_deja.clear()
	if not _prochain_resto():
		return false
	actif = true
	return true

func arreter() -> void:
	actif = false
	phase = ""

## Restaurant de la prochaine commande : au hasard parmi les 4 plus proches du joueur (à moins de R_RESTO m), pas deux
## fois le même pendant la tournée.
func _prochain_resto() -> bool:
	var p: Vector3 = main.car.global_position
	var cand: Array = []
	for i in restos.size():
		if _deja.has(i):
			continue
		var r: Dictionary = restos[i]
		var d := Vector2(float(r.x) - p.x, float(r.z) - p.z).length()
		if d < R_RESTO:
			cand.append([d, i])
	if cand.is_empty():
		return false
	cand.sort_custom(func(a, b): return a[0] < b[0])
	var k: int = cand[randi() % mini(4, cand.size())][1]
	_deja[k] = true
	resto = restos[k]
	var q := _sol(Vector3(float(resto.x), 0.0, float(resto.z)))
	resto_rue = _rue(q)
	phase = "resto"
	_arret_t = 0.0
	_viser(q, COULEUR_RESTO)
	return true

## Adresse de livraison : nœud du graphe routier à D_MIN-D_MAX m du restaurant, sur une rue qui a un nom.
func _adresse(depuis: Vector3) -> bool:
	var best := Vector3.INF
	var c := Vector2i(floori(depuis.x / _itin.CASE), floori(depuis.z / _itin.CASE))
	var R := int(ceilf(D_MAX / _itin.CASE))
	for essai in 60:
		var k := c + Vector2i(randi_range(-R, R), randi_range(-R, R))
		var l: PackedInt32Array = _itin.grille.get(k, PackedInt32Array())
		if l.is_empty():
			continue
		var i: int = l[randi() % l.size()]
		var q := Vector3(_itin.nx[i], 0.0, _itin.nz[i])
		var d := Vector2(q.x - depuis.x, q.z - depuis.z).length()
		if d < D_MIN or d > D_MAX:
			continue
		q = _sol(q)
		var rue := _rue(q)
		var circ = main.get("circulation")
		if rue == "" or (circ and circ.limite(q, 15.0) > 72.0):      # une rue, pas une route rapide
			continue
		best = q
		adresse = "%d %s" % [randi_range(1, 60), _minuscule(rue)]
		var com := _commune(q)
		if com != "":
			adresse += ", " + com
		break
	if best == Vector3.INF:
		return false
	dest = best
	return true

static func _minuscule(rue: String) -> String:
	# « Rue des Pivollets » -> « rue des Pivollets » après un numéro
	for m in ["Rue", "Route", "Chemin", "Avenue", "Allée", "Impasse", "Place", "Boulevard", "Montée", "Lotissement", "Quai"]:
		if rue.begins_with(m + " "):
			return m.to_lower() + rue.substr(m.length())
	return rue

## Nom de la rue en q, sans le numéro de route (« D 522 · Rue de la Libération » -> « Rue de la Libération ») ; vide
## pour une route sans nom de rue (« A 43 », « Voie de service »).
func _rue(q: Vector3) -> String:
	var nm = main.get_node("HUD").get("names")
	if nm == null:
		return ""
	var r := String(nm.road_at(q))
	if " · " in r:
		r = r.get_slice(" · ", r.get_slice_count(" · ") - 1)
	var re := RegEx.new()
	re.compile("^(A|N|D|M|E|RN|RD|C|VC|CD) ?\\d")
	if r == "" or re.search(r) != null or r.begins_with("Voie de service") or r.begins_with("Chemin de terre") or r.begins_with("Sentier") or r.begins_with("Bretelle") \
			or r.begins_with("Échangeur") or r.begins_with("Autoroute"):
		return ""
	return r

func _commune(q: Vector3) -> String:
	var nm = main.get_node("HUD").get("names")
	return String(nm.commune_at(q)) if nm else ""

func _sol(q: Vector3) -> Vector3:
	var h := preload("res://scripts/relief.gd").hauteur(q)
	q.y = h if is_finite(h) else main.car.global_position.y
	return q

func _viser(q: Vector3, col: Color) -> void:
	var act = _act()
	for b in act._beacons:
		if is_instance_valid(b):
			b.queue_free()
	act._beacons.clear()
	act._beacon(q, col, 3.0, 40.0)
	act.marks = [{p = Vector2(q.x, q.z), col = col, txt = str(n + 1), gps = true}]
	act.join_marks = false

func cible() -> Vector3:
	return _sol(Vector3(float(resto.x), 0.0, float(resto.z))) if phase == "resto" else dest

static func _mmss(s: float) -> String:
	var a := absf(s)
	return "%s%d:%02d" % ["-" if s < 0.0 else "", int(a) / 60, int(a) % 60]

func process(dt: float) -> void:
	if not actif:
		return
	var act = _act()
	var car: VehicleBody3D = main.car
	var q := cible()
	act._itineraire(dt, Vector2(q.x, q.z))
	var d := Vector2(car.global_position.x - q.x, car.global_position.z - q.z).length()
	var head := "LIVREUR · commande %d/%d" % [n + 1, NB]
	if phase == "resto":
		act._set_status("%s\n→ %s%s : %d m" % [head, resto.nom, (", " + _minuscule(resto_rue)) if resto_rue != "" else "", int(d)])
		if d < R_PRISE and car.kmh() < V_ARRET:
			_arret_t += dt
			if _arret_t > 1.0:
				_prendre()
		else:
			_arret_t = 0.0
	elif phase == "client":
		t += dt
		var reste := delai - t
		act._set_status("%s\n→ %s : %d m  ·  %s  ·  repas %d %%" % [head, adresse, int(d),
			("reste " + _mmss(reste)) if reste >= 0.0 else ("en retard de " + _mmss(-reste)), int(etat)])
		if d < R_LIVRE and car.kmh() < V_ARRET:
			_arret_t += dt
			if _arret_t > 1.0:
				_livrer()
		else:
			_arret_t = 0.0

## Commande récupérée : adresse et délai.
func _prendre() -> void:
	var r := cible()
	if not _adresse(r):
		main.get_node("HUD").toast("Pas d'adresse de livraison autour : commande suivante.", 3.0)
		_suivante()
		return
	phase = "client"
	t = 0.0
	etat = 100.0
	_arret_t = 0.0
	delai = Vector2(dest.x - r.x, dest.z - r.z).length() * DETOUR / V_DELAI + MARGE
	_viser(dest, COULEUR_CLIENT)
	main.get_node("HUD").toast("Commande de %s récupérée ! Livrez au %s en %s." % [resto.nom, adresse, _mmss(delai)], 4.5)

## Client servi : paiement selon l'avance, l'état du repas, la distance.
func _livrer() -> void:
	var r := _sol(Vector3(float(resto.x), 0.0, float(resto.z)))
	var km := Vector2(dest.x - r.x, dest.z - r.z).length() * DETOUR / 1000.0
	var reste := delai - t
	var msg := ""
	if etat < REFUS:
		refusees += 1
		msg = "Le client refuse le repas, tout est renversé !"
	elif reste < 0.0:
		var p := (BASE + PAR_KM * km) * 0.5
		gain += p
		livrees += 1
		en_retard += 1
		msg = "Livré, mais froid… le client paie la moitié : +%s" % _act()._euros(p)
	else:
		var pb := POURBOIRE * clampf(reste / delai * 2.0, 0.0, 1.0) * etat / 100.0
		var p := BASE + PAR_KM * km + pb
		gain += p
		livrees += 1
		msg = "Livré à l'heure ! +%s (pourboire %s)" % [_act()._euros(p), _act()._euros(pb)]
	main.get_node("HUD").toast(msg, 3.5)
	print("[livreur] livraison %d : %s (%.1f km, reste %.0f s, repas %d %%)" % [n + 1, msg, km, reste, int(etat)])
	_suivante()

func _suivante() -> void:
	n += 1
	if n >= NB:
		_fin()
		return
	if not _prochain_resto():
		_fin()

func _fin() -> void:
	var act = _act()
	var g = main.get("garage")
	if g:
		g.gagner(gain)
	if main.get("succes"):
		main.succes.noter("tournees")
		if livrees > 0:
			main.succes.noter("livraisons", livrees)
	var bilan := "Tournée finie : %d livraison%s sur %d%s : %s gagnés." % [livrees, "s" if livrees > 1 else "", NB,
		(", %d en retard" % en_retard if en_retard > 0 else "") + (", %d refusée%s" % [refusees, "s" if refusees > 1 else ""] if refusees > 0 else ""),
		act._euros(gain)]
	print("[livreur] fin : " + bilan)
	act._stop()
	act._set_status(bilan)
	act._status_t = 8.0
	main.get_node("HUD").toast(bilan, 6.0)

## Chocs pendant la livraison : le repas en pâtit.
func _physics_process(dt: float) -> void:
	if not actif or phase != "client" or get_tree().paused:
		_prev_v = main.car.linear_velocity if main and main.get("car") else Vector3.ZERO
		return
	var car: VehicleBody3D = main.car
	_choc_cd -= dt
	var v := car.linear_velocity
	var saut := car.global_position.distance_to(_prev_p) > 10.0      # téléportation, remise sur la route : pas un choc
	_prev_p = car.global_position
	if saut:
		_choc_cd = 0.5
	if _choc_cd <= 0.0 and (v - _prev_v).length() > 5.5 and not car.carried and float(car.get("_hold_t")) <= 0.0:
		etat = maxf(etat - CHOC, 0.0)
		_choc_cd = 1.0
		main.get_node("HUD").toast("Attention au repas ! (%d %%)" % int(etat), 1.5)
	_prev_v = v
