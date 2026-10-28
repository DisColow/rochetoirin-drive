## Ligne de bus (#148, initiative de Claude, Activités > Taxi > « Prendre une ligne de bus », mode « bus ») : le joueur
## laisse sa voiture et prend le volant du bus B1 (voitures.gd « bus », véhicule de service) ; une ligne de NB_ARRETS
## vrais arrêts (pietons.arrets_bus, nœuds bus_stop d'OSM) enchaînés de proche en proche, itinéraire au GPS
## (activities._itineraire). À chaque arrêt : porte avant (PORTE) à moins de R_ARRET m du poteau, bus arrêté ->
## portes ouvertes, les passants qui attendent montent (posés à l'approche : pietons.peupler_arret), d'autres
## descendent (pietons.bus_a_l_arret) ; on repart quand tout le monde est monté. Recette : TARIF par voyageur, prime
## PRIME_HEURE à l'heure (horaire de chaque arrêt, ± ECART s), MALUS_CHOC par choc avec des voyageurs à bord. Au
## terminus (ou ■ Arrêter) : la voiture du joueur revient (garage.vue_changee : caisse et pièces du garage).
extends Node

const NB_ARRETS := 6
const PORTE := Vector3(-1.35, 0.0, 3.9)         # porte avant droite (repère du véhicule : avant +Z, droite -X)
const R_ARRET := 6.0                            # porte à moins de ça du poteau
const D_MIN := 220.0                            # arrêt suivant : de D_MIN à D_MAX m à vol d'oiseau
const D_MAX := 1000.0
const R_DEPART := 1500.0                        # premier arrêt à moins de ça du joueur
const TARIF := 1.70
const PRIME_HEURE := 5.0
const ECART := 60.0                             # à l'heure : moins d'une minute d'avance ou de retard
const MALUS_CHOC := 2.0
const V_HORAIRE := 7.0                          # m/s sur le trajet (×1,4 pour les détours) : horaire de chaque arrêt
const ATTENTE := 20.0                           # s comptées à chaque arrêt dans l'horaire
const PEUPLER := 120.0                          # passants posés à l'arrêt visé quand le bus en est à moins de ça

var main: Node
var actif := false
var arrets: Array = []                          # Vector3 des arrêts de la ligne
var noms: Array = []
var horaires: Array = []                        # s depuis le départ
var i := 0                                      # arrêt visé
var t := 0.0
var phase := ""                                 # "route", "portes"
var voyageurs := 0                              # à bord
var transportes := 0
var recette := 0.0
var primes := 0.0
var chocs := 0
var a_l_heure := 0
var _porte_t := 0.0
var _peuple := -1
var _stop_t := 0.0
var _conseil := false
var _prev_v := Vector3.ZERO
var _choc_cd := 0.0
var _parti_tot := false

func _act():
	return main.activities

## Ligne tracée depuis la position du joueur, puis prise du bus ; faux (message) s'il n'y a pas d'arrêt assez près.
func demarrer() -> bool:
	var pie = main.get("pietons")
	var car: VehicleBody3D = main.car
	if pie == null or not pie.ok:
		return false
	var tous: PackedVector3Array = pie.arrets_bus()
	var p := car.global_position
	var cand := []
	for k in tous.size():
		if tous[k].distance_to(p) < R_DEPART:
			cand.append([tous[k].distance_to(p), k])
	var cur := _premier_desservi(tous, cand)
	if cur < 0:
		return false
	arrets = [tous[cur]]
	var pris := {cur: true}
	var dir := Vector3.ZERO
	while arrets.size() < NB_ARRETS:
		var q0: Vector3 = arrets[-1]
		cand.clear()
		for k in tous.size():
			if pris.has(k):
				continue
			var d := tous[k].distance_to(q0)
			if d < D_MIN or d > D_MAX:
				continue
			var sc := d
			if dir != Vector3.ZERO and (tous[k] - q0).normalized().dot(dir) < -0.2:
				sc += 1500.0                            # pas de demi-tour : la ligne avance
			cand.append([sc, k])
		var best := _premier_desservi(tous, cand)
		if best < 0:
			break
		dir = (tous[best] - q0).normalized()
		pris[best] = true
		arrets.append(tous[best])
	if arrets.size() < 3:
		return false
	var names = main.get_node("HUD").names
	noms.clear()
	horaires.clear()
	var h := 0.0
	var prec := p
	for q: Vector3 in arrets:
		var n: String = names.road_at_fixe(q) if names else ""
		noms.append(n if n != "" and n != "Hors route" else "Arrêt %d" % (noms.size() + 1))
		h += prec.distance_to(q) * 1.4 / V_HORAIRE + (ATTENTE if horaires.size() > 0 else 15.0)
		horaires.append(roundf(h / 10.0) * 10.0)
		prec = q
	# prise du bus à la place de la voiture
	car.construire("bus")
	car.set("nitro_niveau", 0)
	car.global_position += Vector3.UP * 0.4
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	actif = true
	i = 0
	t = 0.0
	voyageurs = 0
	transportes = 0
	recette = 0.0
	primes = 0.0
	chocs = 0
	a_l_heure = 0
	_peuple = -1
	_viser()
	return true

## Meilleur candidat ([score, indice], le plus petit score d'abord) longé par une voie de la circulation où le bus peut
## s'arrêter (sinon arrêt sur une voie de service, un parking de gare… : inaccessible) ; -1 si aucun.
var _desservis := {}
func _premier_desservi(tous: PackedVector3Array, cand: Array) -> int:
	cand.sort_custom(func(a, b): return a[0] < b[0])
	var ci = main.get("circulation")
	for c in cand:
		var k: int = c[1]
		if not _desservis.has(k):
			_desservis[k] = ci == null or not ci.ok or not ci.voie_arret(tous[k], 0.0).is_empty()
		if _desservis[k]:
			return k
	return -1

## Fin de service : la voiture du joueur revient (avec ses pièces du garage).
func arreter() -> void:
	if not actif:
		return
	actif = false
	phase = ""
	var g = main.get("garage")
	if g:
		g.vue_changee.emit(g.vue)
	else:
		main.car.construire(preload("res://scripts/voitures.gd").actuelle())
	main.car.global_position += Vector3.UP * 0.4

func _viser() -> void:
	var act = _act()
	for b in act._beacons:
		if is_instance_valid(b):
			b.queue_free()
	act._beacons.clear()
	phase = "route"
	_stop_t = 0.0
	_conseil = false
	_parti_tot = false
	var q: Vector3 = arrets[i]
	act._beacon(q, Color(0.25, 0.75, 1.0), 3.0, 40.0)
	act.marks = []
	for k in range(i, arrets.size()):
		act.marks.append({p = Vector2(arrets[k].x, arrets[k].z), col = Color(0.25, 0.75, 1.0) if k == i else Color(0.25, 0.5, 0.8),
			txt = str(k + 1), gps = k == i})
	act.join_marks = true

static func _mmss(s: float) -> String:
	var a := absf(s)
	return "%d:%02d" % [int(a) / 60, int(a) % 60]

func process(dt: float) -> void:
	if not actif:
		return
	var act = _act()
	var car: VehicleBody3D = main.car
	t += dt
	var q: Vector3 = arrets[i]
	act._itineraire(dt, Vector2(q.x, q.z))
	var d := Vector2(car.global_position.x - q.x, car.global_position.z - q.z).length()
	if d < PEUPLER and _peuple != i:
		_peuple = i
		if i < arrets.size() - 1:                       # au terminus, personne ne monte
			main.pietons.peupler_arret(q, randi_range(1, 4))
	var head := "BUS  ·  arrêt %d/%d  ·  %d à bord  ·  %s" % [i + 1, arrets.size(), voyageurs, act._euros(recette + primes)]
	var reste := float(horaires[i]) - t
	var heure := ("dans " + _mmss(reste)) if reste >= 0.0 else ("retard " + _mmss(reste))
	if phase == "route":
		var porte := car.global_transform * PORTE
		var dp := Vector2(porte.x - q.x, porte.z - q.z).length()
		act._set_status("%s\n→ %s%s : %d m  ·  passage %s" % [head, noms[i], " (terminus)" if i == arrets.size() - 1 else "", int(d), heure])
		if dp < R_ARRET and car.kmh() < 3.0:
			_stop_t += dt
			if _stop_t > 0.8:
				_ouvrir(porte)
		else:
			_stop_t = 0.0
			if d < 16.0 and dp >= R_ARRET and car.kmh() < 3.0 and not _conseil:
				_conseil = true
				main.get_node("HUD").toast("Arrêtez la porte avant (à droite) au niveau du poteau.", 3.0)
	elif phase == "portes":
		_porte_t -= dt
		act._set_status("%s\n%s : portes ouvertes, montée des voyageurs…" % [head, noms[i]])
		if car.kmh() > 4.0 and not _parti_tot:
			_parti_tot = true
			chocs += 1
			main.get_node("HUD").toast("Attendez que tout le monde soit monté ! (−%s)" % act._euros(MALUS_CHOC), 2.5)
		if _porte_t <= 0.0:
			act._bip.play()
			i += 1
			if i >= arrets.size():
				_fin()
			else:
				_viser()

func _ouvrir(porte: Vector3) -> void:
	var act = _act()
	var dern := i == arrets.size() - 1
	var desc := voyageurs if dern else randi_range(0, mini(2, voyageurs))
	var r: Array = main.pietons.bus_a_l_arret(arrets[i], porte, mini(desc, 4))
	var monte := 0 if dern else int(r[0])
	voyageurs = maxi(voyageurs - desc, 0) + monte
	transportes += monte
	recette += monte * TARIF
	var ecart := t - float(horaires[i])
	var msg := "%s : %d voyageur(s) monte(nt), %d descend(ent)." % [noms[i], monte, desc]
	if absf(ecart) <= ECART:
		primes += PRIME_HEURE
		a_l_heure += 1
		msg += "  À l'heure : +%s" % act._euros(PRIME_HEURE)
	elif ecart < 0.0:
		msg += "  En avance de %s : pas de prime." % _mmss(ecart)
	else:
		msg += "  En retard de %s : pas de prime." % _mmss(ecart)
	main.get_node("HUD").toast(msg, 4.0)
	act._bip.play()
	_porte_t = maxf(4.0, float(r[2]) + 1.5)
	phase = "portes"

func _fin() -> void:
	var act = _act()
	var total := maxf(recette + primes - chocs * MALUS_CHOC, 0.0)
	var g = main.get("garage")
	if g:
		g.gagner(total)
	if main.get("succes"):
		main.succes.noter("lignes_bus")
		main.succes.noter("voyageurs", transportes)
	var bilan := "Terminus ! %d voyageurs, %d arrêt(s) sur %d à l'heure, %d choc(s) : %s gagnés." % [
		transportes, a_l_heure, arrets.size(), chocs, act._euros(total)]
	act._stop()
	act._set_status(bilan)
	act._status_t = 8.0
	main.get_node("HUD").toast(bilan, 6.0)

func _physics_process(dt: float) -> void:
	if not actif or get_tree().paused:
		return
	var car: VehicleBody3D = main.car
	_choc_cd -= dt
	var v := car.linear_velocity
	if _choc_cd <= 0.0 and voyageurs > 0 and (v - _prev_v).length() > 5.5 and not car.carried:
		chocs += 1
		_choc_cd = 1.0
		main.get_node("HUD").toast("Les voyageurs sont secoués ! (−%s)" % _act()._euros(MALUS_CHOC), 1.5)
	_prev_v = v
