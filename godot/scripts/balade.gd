## Balade (v6.98, initiative de Claude) : la voiture roule toute seule d'un lieu à l'autre et la caméra filme comme au
## cinéma, pour regarder le pays, la météo et le cycle jour et nuit. Pilote : celui des concurrents (concurrent.gd, sur
## la voiture du joueur) à allure de promenade : virages doux (A_LAT) et limitation de vitesse de chaque route
## (road_name.gd, relevée tous les 20 m du trajet). Lieux de places.json à 1,2-3,5 km, l'un après l'autre. Plans de 7 à
## 12 s, coupés net : poursuite, bord de route (la voiture passe devant un téléobjectif), drone, au ras de la roue, de
## face, survol en cercle. Commandes de conduite cachées ; un toucher, une touche ou un bouton de manette rend la main
## (activities._stop). Essai : -- --drive-test --balade-test.
extends Node3D
const Relief := preload("res://scripts/relief.gd")
const PerfMon := preload("res://scripts/perf_monitor.gd")

const A_LAT := 2.2                  # accélération latérale admise en virage (m/s² ; les concurrents : 5)
const LIMITE_INCONNUE := 70.0       # km/h quand la route n'a pas de limitation connue
const PLANS := ["poursuite", "bord", "drone", "roue", "face", "survol"]
const POIDS := [3.0, 3.0, 2.0, 1.5, 1.5, 1.5]
const DUREE := Vector2(7.0, 12.0)

var main: Node
var actif := false
var lieu := ""                      # nom du lieu visé
var lieux := 0                      # lieux atteints (essais)
var plans_vus := {}                 # plans montrés (essais)
var _pilote: Node
var _pilote_parti := false
var _cam: Camera3D
var _plan := 0
var _plan_t := 0.0
var _fixe := Vector3.ZERO           # position de la caméra au bord de la route
var _angle := 0.0
var _lisse := Vector3.INF
var _aide_voie := true
var _rng := RandomNumberGenerator.new()
var _feux := []                     # feux tricolores du trajet : [indice du point d'arrêt, code du feu (trafic.bin)]
var _v0 := PackedFloat32Array()     # profil du pilote sans les feux
var arrets_feu := 0                 # arrêts à un feu rouge (essais)
var destination := Vector2.INF      # essais : lieu imposé (premier trajet)
var _arrete_feu := false

func demarrer() -> void:
	if actif:
		return
	actif = true
	lieux = 0
	_rng.randomize()
	var car: VehicleBody3D = main.car
	_aide_voie = car.aide_voie
	car.aide_voie = false                 # l'aide au maintien dans la voie contrarierait le pilote
	car.reversing = false
	_cam = Camera3D.new()
	_cam.far = 20000.0
	add_child(_cam)
	_plan = 0
	_plan_t = _rng.randf_range(DUREE.x, DUREE.y)
	plans_vus = {"poursuite": true}
	var hud = main.get_node_or_null("HUD")
	if hud and hud.has_method("commandes_visibles"):
		hud.commandes_visibles(false)
	_trajet()

func arreter() -> void:
	if not actif:
		return
	actif = false
	if is_instance_valid(_pilote):
		_pilote.queue_free()
	_pilote = null
	var car: VehicleBody3D = main.car
	car.aide_voie = _aide_voie
	car.touch_throttle = 0.0
	car.touch_brake = 0.0
	car.touch_steer = 0.0
	if _cam:
		_cam.queue_free()
		_cam = null
	main.cam_rig.cam.current = true
	var hud = main.get_node_or_null("HUD")
	if hud and hud.has_method("commandes_visibles"):
		hud.commandes_visibles(true)

## Prochain lieu (places.json) à 1,2-3,5 km à vol d'oiseau, sinon le plus proche au-delà de 800 m ; trajet du pilote.
func _trajet() -> void:
	var act = main.activities
	var car: VehicleBody3D = main.car
	var p0 := Vector2(car.global_position.x, car.global_position.z)
	var choix := []
	var repli := -1
	var repli_d := INF
	for k in act.places.size():
		var pl: Dictionary = act.places[k]
		var q := Vector2(float(pl.x), float(pl.z))
		var d := p0.distance_to(q)
		if d > 1200.0 and d < 3500.0:
			choix.append(k)
		elif d > 800.0 and d < repli_d:
			repli = k
			repli_d = d
	var k: int = choix[_rng.randi() % choix.size()] if not choix.is_empty() else repli
	var dest := p0 + Vector2(1500.0, 0.0).rotated(_rng.randf() * TAU)
	lieu = "la campagne"
	if destination != Vector2.INF:
		dest = destination
		k = -1
		lieu = "la destination de l'essai"
		destination = Vector2.INF
	if k >= 0:
		dest = Vector2(float(act.places[k].x), float(act.places[k].z))
		lieu = str(act.places[k].n)
		var commune := str(act.places[k].get("c", ""))
		if commune != "" and not lieu.contains(commune):
			lieu += " (%s)" % commune
	if is_instance_valid(_pilote):
		_pilote.queue_free()
	_pilote = preload("res://scripts/concurrent.gd").new()
	_pilote.main = main
	_pilote.voiture = car
	_pilote.nom = "balade"
	_pilote.a_lat = A_LAT
	_pilote.temps_cible = 1.0                     # pas de mise à l'échelle : le profil est celui de la route
	_pilote.doubler = false
	_pilote.points = [p0, dest]
	_pilote_parti = false
	add_child(_pilote)
	act._set_status("Balade vers %s…" % lieu)

## Vitesses du profil du pilote plafonnées à la limitation de chaque route (relevée tous les 20 m), puis horaire.
func _limiter() -> void:
	var names = main.get_node("HUD").names
	var cur: int = names.current
	var lim0: int = names.speed_limit
	var ch: PackedVector2Array = _pilote._chemin
	var v: PackedFloat32Array = _pilote._v
	var lim := LIMITE_INCONNUE
	for i in ch.size():
		if i % 10 == 0:
			names.current = -1
			names.road_at(Vector3(ch[i].x, 0.0, ch[i].y))
			lim = float(names.speed_limit) if names.speed_limit > 0 else LIMITE_INCONNUE
		v[i] = minf(v[i], lim / 3.6 * 0.95)
	_pilote._v = v
	names.current = cur
	names.speed_limit = lim0
	_pilote._horaire()

## Feux tricolores du trajet : arrivées d'arcs de la circulation qui portent un feu (trafic.bin) dont le nœud est à
## moins de 7 m du trajet, dans le même sens ; point d'arrêt ARRET_FEU m avant le nœud.
func _relever_feux() -> void:
	_feux = []
	_v0 = _pilote._v.duplicate()
	var circ = main.get("circulation")
	if circ == null or not circ.ok:
		return
	var ch: PackedVector2Array = _pilote._chemin
	var grille := {}
	for i in ch.size():
		var c := Vector2i(floori(ch[i].x / 10.0), floori(ch[i].y / 10.0))
		if not grille.has(c):
			grille[c] = []
		grille[c].append(i)
	for k in circ._a.size():
		for bout in 2:
			var feu: int = circ._feu_b[k] if bout == 0 else circ._feu_a[k]
			if feu < 0:
				continue
			var n: int = circ._b[k] if bout == 0 else circ._a[k]
			var q := Vector2(circ._nx[n], circ._nz[n])
			var cle := Vector2i(floori(q.x / 10.0), floori(q.y / 10.0))
			var best := -1
			var bd := 49.0
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					for i in grille.get(cle + Vector2i(dx, dz), []):
						var d := ch[i].distance_squared_to(q)
						if d < bd:
							bd = d
							best = i
			if best < 3:
				continue
			var p0: int = circ._p0[k]
			var np: int = circ._np[k]
			var i1 := p0 + np - 1 if bout == 0 else p0
			var i0 := p0 + np - 2 if bout == 0 else p0 + 1
			var arrivee := Vector2(circ._P[i1 * 3] - circ._P[i0 * 3], circ._P[i1 * 3 + 2] - circ._P[i0 * 3 + 2]).normalized()
			var sens := (ch[mini(best + 2, ch.size() - 1)] - ch[maxi(best - 2, 0)]).normalized()
			if sens.dot(arrivee) < 0.7:
				continue
			var arret := best
			while arret > 0 and _pilote._s[best] - _pilote._s[arret] < circ.ARRET_FEU:
				arret -= 1
			_feux.append([arret, feu])

## Au rouge (et à l'orange si l'arrêt est confortable), vitesse du profil nulle au point d'arrêt ; au vert, rendue.
func _feux_appliquer() -> void:
	if _feux.is_empty():
		return
	var circ = main.circulation
	var s: float = _pilote.s
	var v: PackedFloat32Array = _pilote._v
	var change := false
	var arrete := false
	for f in _feux:
		var i: int = f[0]
		var d: float = _pilote._s[i] - s
		var rouge := false
		if d > -1.0 and d < 120.0:
			var etat: int = circ._etat_feu(int(f[1]))
			var vit := absf(main.car.forward_speed())
			rouge = etat == 2 or (etat == 1 and vit * vit / (2.0 * maxf(d, 0.01)) < 3.5)
			if rouge and d < 6.0 and vit < 0.5:
				arrete = true
		for j in range(maxi(i - 1, 0), mini(i + 2, v.size())):
			var bj := 0.0 if rouge else _v0[j]
			if v[j] != bj:
				v[j] = bj
				change = true
	if change:
		_pilote._v = v
	if arrete and not _arrete_feu:
		arrets_feu += 1
	_arrete_feu = arrete

func _unhandled_input(e: InputEvent) -> void:
	if not actif:
		return
	# toucher hors de la rangée de boutons du haut (radio, carte, réglages… : ils ne rendent pas la main)
	var haut := get_viewport().get_visible_rect().size.y * 0.2
	var main_reprise: bool = (e is InputEventScreenTouch and e.pressed and e.position.y > haut) \
		or (e is InputEventMouseButton and e.pressed and e.position.y > haut) \
		or (e is InputEventKey and e.pressed and not e.echo) or (e is InputEventJoypadButton and e.pressed)
	if main_reprise:
		get_viewport().set_input_as_handled()
		main.activities._stop()

func _process(dt: float) -> void:
	var t0 := Time.get_ticks_usec()
	_process_corps(dt)
	PerfMon.note("balade", Time.get_ticks_usec() - t0)

func _process_corps(dt: float) -> void:
	if not actif or get_tree().paused:
		return
	if is_instance_valid(_pilote):
		if _pilote.pret and not _pilote_parti:
			_limiter()
			_relever_feux()
			_pilote.parti = true
			_pilote_parti = true
			main.activities._set_status("Balade vers %s\nToucher l'écran pour reprendre le volant" % lieu)
		elif _pilote.fini:
			lieux += 1
			_trajet()
		elif _pilote_parti:
			_feux_appliquer()
	_filmer(dt)

## Caméra : un plan tiré au sort toutes les 7 à 12 s (jamais deux fois le même de suite).
func _filmer(dt: float) -> void:
	var car: VehicleBody3D = main.car
	var xf := car.global_transform
	var p := xf.origin
	var avant := xf.basis.z
	avant.y = 0.0
	avant = avant.normalized() if avant.length_squared() > 1e-4 else Vector3.FORWARD
	var cote := avant.cross(Vector3.UP).normalized()
	_plan_t -= dt
	if _plan == 1 and _fixe.distance_to(p) > 75.0 and (p - _fixe).dot(avant) > 0.0:
		_plan_t = 0.0                                     # la voiture est passée et s'éloigne
	if _plan_t <= 0.0:
		_nouveau_plan(p, avant, cote)
	if _plan == 0:
		main.cam_rig.cam.current = true
		return
	_cam.current = true
	var vise := p + Vector3.UP * 0.8
	var pos := _cam.global_position
	match _plan:
		1:
			pos = _fixe
			_cam.fov = 32.0
		2:
			pos = _suivre(p - avant * 24.0 + Vector3.UP * 13.0, dt, 2.0)
			vise = p + avant * 12.0
			_cam.fov = 60.0
		3:
			# au ras de la roue arrière, un peu à l'écart de la carrosserie, vers l'avant le long du flanc
			var g: Vector3 = car.gabarit
			pos = xf * Vector3((g.x * 0.5 + 0.5) * signf(_angle), 0.5, -g.z * 0.3)
			vise = pos + avant * 25.0 - cote * signf(_angle) * 0.8
			_cam.fov = 72.0
		4:
			pos = _suivre(p + avant * 9.0 + Vector3.UP * 1.4, dt, 4.0)
			_cam.fov = 50.0
		5:
			_angle += dt * 0.12
			pos = _suivre(p + Vector3(cos(_angle), 0.0, sin(_angle)) * 32.0 + Vector3.UP * 18.0, dt, 3.0)
			_cam.fov = 55.0
	_cam.global_position = pos
	if pos.distance_squared_to(vise) > 0.01:
		_cam.look_at(vise)

func _suivre(but: Vector3, dt: float, k: float) -> Vector3:
	_lisse = but if _lisse == Vector3.INF else _lisse.lerp(but, 1.0 - exp(-dt * k))
	return _lisse

func _nouveau_plan(p: Vector3, avant: Vector3, cote: Vector3) -> void:
	var total := 0.0
	for w in POIDS:
		total += w
	var n := _plan
	while n == _plan:
		var r := _rng.randf() * total
		n = 0
		while n < POIDS.size() - 1 and r > POIDS[n]:
			r -= POIDS[n]
			n += 1
		if n == 1 and not _place_bord(p, avant, cote):
			n = _plan                                       # pas de bord de route dégagé : on retire
	_plan = n
	_plan_t = _rng.randf_range(DUREE.x, DUREE.y)
	_lisse = Vector3.INF
	_angle = _rng.randf_range(-PI, PI) if n == 5 else (1.0 if _rng.randf() < 0.5 else -1.0)
	plans_vus[PLANS[n]] = true

## Bord de route : 50 à 70 m devant sur le trajet, 5 à 7 m sur le côté, à 3 m (au-dessus des haies) ; vue dégagée vers
## la route (rayon contre les collisions : bâtiments, clôtures chargées).
func _place_bord(p: Vector3, avant: Vector3, cote: Vector3) -> bool:
	var devant := p + avant * _rng.randf_range(50.0, 70.0)
	if is_instance_valid(_pilote) and _pilote.pret:
		var a: Array = _pilote._au(_pilote.s + _rng.randf_range(50.0, 70.0))
		devant = Vector3(a[0].x, p.y, a[0].y)
	var espace := get_world_3d().direct_space_state
	for sens in ([1.0, -1.0] if _rng.randf() < 0.5 else [-1.0, 1.0]):
		var c: Vector3 = devant + cote * sens * _rng.randf_range(5.0, 7.0)
		var h := Relief.hauteur(c)
		if not is_finite(h):
			continue
		c.y = h + 3.0
		var q := PhysicsRayQueryParameters3D.create(c, Vector3(devant.x, h + 0.8, devant.z))
		q.exclude = [main.car.get_rid()]
		if espace.intersect_ray(q).is_empty():
			_fixe = c
			return true
	return false
