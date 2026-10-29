## Ligne de bus (#148, initiative de Claude, Activités > Taxi > « Prendre une ligne de bus », mode « bus ») : le joueur
## laisse sa voiture et prend le volant du bus B1 (voitures.gd « bus », véhicule de service) ; une ligne de NB_ARRETS
## vrais arrêts (pietons.arrets_bus, nœuds bus_stop d'OSM) enchaînés de proche en proche, itinéraire au GPS
## (activities._itineraire). À chaque arrêt : porte avant (PORTE) à moins de R_ARRET m du poteau, bus arrêté ->
## portes ouvertes, les passants qui attendent montent (posés à l'approche : pietons.peupler_arret), d'autres
## descendent (pietons.bus_a_l_arret) ; bus tenu immobile portes ouvertes (frein de porte), on repart quand tout le
## monde est monté. Recette : TARIF par voyageur, prime
## PRIME_HEURE à l'heure (horaire de chaque arrêt, ± ECART s), MALUS_CHOC par choc avec des voyageurs à bord et par
## arrêt brûlé. v7.03 : arrêt demandé (sonnette) par un voyageur à bord ; sans demande ni personne qui attend, on passe. Au
## terminus (ou ■ Arrêter) : la voiture du joueur revient (garage.vue_changee : caisse et pièces du garage).
extends Node

const NB_ARRETS := 6
const PORTE := Vector3(-1.35, 0.0, 3.9)         # porte avant droite (repère du véhicule : avant +Z, droite -X)
const R_ARRET := 7.0                            # porte à moins de ça du poteau (quais d'OSM un peu en retrait)
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
var ligne := ""                                 # « LIGNE 4 · Gare > Hôtel de Ville » (réseau Ruban), sinon ""
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
var oublis := 0                                # arrêts demandés brûlés
var _attendent := 0                             # passants qui attendent à l'arrêt visé
var _demande := false                           # un voyageur a demandé l'arrêt (sonnette)
var _sonne := false
var _plus_pres := INF                           # distance la plus courte du bus à l'arrêt visé
var _ding: AudioStreamPlayer
var _porte_t := 0.0
var _peuple := -1
var _stop_t := 0.0
var _conseil := false
var _prev_v := Vector3.ZERO
var _choc_cd := 0.0

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
	noms.clear()
	ligne = ""
	if not _ligne_ruban(tous, p) and not _ligne_proche(tous, p):
		return false
	var names = main.get_node("HUD").names
	horaires.clear()
	var h := 0.0
	var prec := p
	for q: Vector3 in arrets:
		if noms.size() < horaires.size() + 1:
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
	oublis = 0
	_peuple = -1
	_viser()
	return true

## Vraie ligne du réseau Ruban (#149, world/lignes_bus.json de pipeline/fetch_lignes_bus.py) : ses arrêts ramenés aux
## arrêts de la carte (à RACCORD m au plus, longés par une voie), puis, de l'arrêt le plus proche du joueur (R_DEPART)
## dans le sens de la ligne, NB_ARRETS arrêts consécutifs (ceux hors de la carte sont sautés) ; vrais noms d'arrêts.
const RACCORD := 35.0
const Relief := preload("res://scripts/relief.gd")
var _lignes = null
var _pos_ruban: Array = []
func _ligne_ruban(tous: PackedVector3Array, p: Vector3) -> bool:
	if _lignes == null:
		_lignes = []
		if FileAccess.file_exists("res://world/lignes_bus.json"):
			var l = JSON.parse_string(FileAccess.get_file_as_string("res://world/lignes_bus.json"))
			if l is Array:
				_lignes = l
	var departs := []                                   # [distance au joueur, ligne, rang du premier arrêt]
	var cartes := []                                    # par ligne : indice de l'arrêt de la carte de chaque arrêt (-1)
	# chaque arrêt d'OSM : celui de la carte s'il y en a un à RACCORD m (panneau, passants qui attendent), sinon le quai
	# d'OSM lui-même ; positions communes dans _pos_ruban (indice : clé de _desservis, au-delà des arrêts de la carte)
	_pos_ruban = Array(tous)
	var index := {}
	for li in _lignes.size():
		var c := PackedInt32Array()
		for a in _lignes[li].arrets:
			var q := Vector3(float(a[0]), 0.0, float(a[1]))
			if absf(q.x - p.x) > 6000.0 or absf(q.z - p.z) > 6000.0:
				c.append(-1)
				continue
			var best := -1
			var bd := RACCORD
			for k in tous.size():
				var d := Vector2(tous[k].x - q.x, tous[k].z - q.z).length()
				if d < bd:
					bd = d
					best = k
			if best < 0:
				var cle := "%d,%d" % [roundi(q.x), roundi(q.z)]
				if not index.has(cle):
					index[cle] = _pos_ruban.size()
					_pos_ruban.append(Vector3(q.x, Relief.hauteur(q), q.z))
				best = index[cle]
			c.append(best)
			if (_pos_ruban[best] as Vector3).distance_to(Vector3(p.x, (_pos_ruban[best] as Vector3).y, p.z)) < R_DEPART:
				departs.append([Vector2(_pos_ruban[best].x - p.x, _pos_ruban[best].z - p.z).length(), li, c.size() - 1])
		cartes.append(c)
	departs.sort_custom(func(a, b): return a[0] < b[0])
	var meilleur := []
	var m_li := -1
	for dep in departs.slice(0, 60):
		var li: int = dep[1]
		var suite := []
		var vus := {}
		var long := 0.0
		for j in range(int(dep[2]), cartes[li].size()):
			var k: int = cartes[li][j]
			if k < 0 or vus.has(k):
				continue
			if suite.size() > 0:                          # ligne de ville : ni grand trou, ni trop longue
				var ecart := (_pos_ruban[k] as Vector3).distance_to(_pos_ruban[int(suite[-1][0])])
				if ecart > 1200.0 or long + ecart > 4000.0:
					break
				long += ecart
			var cle_d: Variant = ("r%d" % k) if k >= tous.size() else k
			if not _desservis.has(cle_d):
				var ci = main.get("circulation")
				_desservis[cle_d] = ci == null or not ci.ok or not ci.voie_arret(_pos_ruban[k], 0.0).is_empty()
			if not _desservis[cle_d]:
				continue
			vus[k] = true
			suite.append([k, String(_lignes[li].arrets[j][2])])
			if suite.size() >= NB_ARRETS:
				break
		if suite.size() > meilleur.size():
			meilleur = suite
			m_li = li
		if meilleur.size() >= NB_ARRETS - 1:            # la plus proche qui en a au moins 5
			break
	if OS.get_cmdline_user_args().has("--ligne-bus-test"):
		var raccordes := 0
		for c in cartes:
			for k in c:
				raccordes += 1 if k >= 0 else 0
		print("  [ligne] réseau Ruban : %d variantes, %d arrêts raccordés à la carte, %d départs à moins de %d m, meilleure suite %d arrêts" % [
			_lignes.size(), raccordes, departs.size(), int(R_DEPART), meilleur.size()])
	if meilleur.size() < 4:
		return false
	arrets.clear()
	var ci2 = main.get("circulation")
	for e in meilleur:
		var q: Vector3 = _pos_ruban[int(e[0])]
		if int(e[0]) >= tous.size() and ci2 and ci2.ok:   # quai d'OSM : poteau ramené au bord de la voie
			q = ci2.bord_arret(q)
		arrets.append(q)
		noms.append(String(e[1]) if String(e[1]) != "" else "Arrêt %d" % (noms.size() + 1))
	ligne = "LIGNE %s · %s" % [_lignes[m_li].ref, _lignes[m_li].nom]
	return true

## Secours (v7.02) : arrêts de la carte enchaînés de proche en proche à partir du plus proche du joueur.
func _ligne_proche(tous: PackedVector3Array, p: Vector3) -> bool:
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
	return arrets.size() >= 3

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
	# arrêt demandé (sonnette) par un voyageur à bord ; quelqu'un attend ou non : sans l'un ni l'autre, on peut passer
	var dern := i == arrets.size() - 1
	_attendent = 0 if dern or randf() < 0.25 else randi_range(1, 4)
	_demande = dern or (voyageurs > 0 and randf() < 0.55)
	_sonne = false
	_plus_pres = INF
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
		if _attendent > 0:                               # au terminus, personne ne monte
			_attendent = main.pietons.peupler_arret(q, _attendent)    # ceux qui ont pu être posés
	if _demande and not _sonne and d < 250.0 and phase == "route" and i < arrets.size() - 1:
		_sonne = true
		_sonnette()
		main.get_node("HUD").toast("Arrêt demandé : %s" % noms[i], 2.5)
	var head := "%s  ·  arrêt %d/%d  ·  %d à bord  ·  %s" % [ligne if ligne != "" else "BUS", i + 1, arrets.size(), voyageurs,
		act._euros(recette + primes)]
	var reste := float(horaires[i]) - t
	var heure := ("dans " + _mmss(reste)) if reste >= 0.0 else ("retard " + _mmss(reste))
	if phase == "route":
		var porte := car.global_transform * PORTE
		var dp := Vector2(porte.x - q.x, porte.z - q.z).length()
		var libre := not _demande and _attendent == 0
		act._set_status("%s\n→ %s%s : %d m  ·  passage %s%s" % [head, noms[i], " (terminus)" if i == arrets.size() - 1 else "", int(d), heure,
			"  ·  ARRÊT DEMANDÉ" if _sonne else ("  ·  personne : vous pouvez passer" if libre and d < PEUPLER else "")])
		# arrêt dépassé : sans demande ni personne qui attend, desservi en passant ; sinon brûlé
		var rel := q - car.global_position
		_plus_pres = minf(_plus_pres, d)
		if _plus_pres < 15.0 and d > _plus_pres + 10.0 and rel.dot(car.global_transform.basis.z) < 0.0:
			if libre:
				var ecart := t - float(horaires[i])
				if absf(ecart) <= ECART:
					primes += PRIME_HEURE
					a_l_heure += 1
				main.get_node("HUD").toast("%s : personne à prendre ni à déposer, vous passez%s." % [noms[i],
					(" à l'heure (+%s)" % act._euros(PRIME_HEURE)) if absf(ecart) <= ECART else ""], 3.0)
			else:
				oublis += 1
				main.get_node("HUD").toast("Arrêt %s brûlé ! Les voyageurs râlent (−%s)." % [noms[i], act._euros(MALUS_CHOC)], 3.0)
			act._bip.play()
			i += 1
			if i >= arrets.size():
				_fin()
			else:
				_viser()
			return
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
		car.hold(0.2)                                   # frein de porte (comme un vrai bus) : immobile portes ouvertes
		act._set_status("%s\n%s : portes ouvertes, montée des voyageurs…" % [head, noms[i]])
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
	var desc := voyageurs if dern else (randi_range(1, mini(2, voyageurs)) if _demande and voyageurs > 0 else 0)
	var r: Array = main.pietons.bus_a_l_arret(arrets[i], porte, mini(desc, 4))
	var monte := 0 if dern else int(r[0])
	voyageurs = maxi(voyageurs - desc, 0) + monte
	transportes += monte
	recette += monte * TARIF
	var ecart := t - float(horaires[i])
	var msg := "%s : %s, %s." % [noms[i], _accord(monte, "voyageur monte", "voyageurs montent", "personne ne monte"),
		_accord(desc, "descend", "descendent", "personne ne descend")]
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
	for b in act._beacons:                              # la colonne lumineuse s'efface : on y est
		if is_instance_valid(b):
			b.queue_free()
	act._beacons.clear()
	_porte_t = maxf(4.0, float(r[2]) + 1.5)
	phase = "portes"

## « 1 voyageur monte », « 3 voyageurs montent », « personne ne monte ».
static func _accord(n: int, un: String, plusieurs: String, aucun: String) -> String:
	if n == 0:
		return aucun
	return "1 " + un if n == 1 else "%d %s" % [n, plusieurs]

## Sonnette « arrêt demandé » : ding-dong (le bip des activités, plus aigu puis plus grave).
func _sonnette() -> void:
	if _ding == null:
		_ding = AudioStreamPlayer.new()
		_ding.stream = load("res://assets/sfx/bip.wav")
		_ding.volume_db = -4.0
		add_child(_ding)
	_ding.pitch_scale = 1.6
	_ding.play()
	await get_tree().create_timer(0.32).timeout
	if _ding:
		_ding.pitch_scale = 1.25
		_ding.play()

func _fin() -> void:
	var act = _act()
	var total := maxf(recette + primes - (chocs + oublis) * MALUS_CHOC, 0.0)
	var g = main.get("garage")
	if g:
		g.gagner(total)
	if main.get("succes"):
		main.succes.noter("lignes_bus")
		main.succes.noter("voyageurs", transportes)
	var bilan := "Terminus ! %s, %d arrêt%s sur %d à l'heure, %s : %s gagnés." % [
		_accord(transportes, "voyageur", "voyageurs", "aucun voyageur"), a_l_heure, "s" if a_l_heure > 1 else "", arrets.size(),
		_accord(chocs, "choc", "chocs", "aucun choc") + (", " + _accord(oublis, "arrêt brûlé", "arrêts brûlés", "") if oublis > 0 else ""),
		act._euros(total)]
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
