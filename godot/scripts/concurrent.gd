## Concurrent piloté par le jeu (#128) : une vraie voiture du garage (car.gd : mêmes physique et collisions que celle du
## joueur) qui fait la course sur le tracé d'une épreuve ; on peut la pousser, la sortir de la route ou la détruire.
## - Tracé et profil de vitesse comme l'ancien fantôme du rival (itineraire.gd jambe par jambe ; virages,
##   accélération, freinage) ; allure réglée pour finir vers le temps visé (niveau de l'épreuve, #127), corrigée en
##   route d'après l'avance ou le retard sur l'horaire, sans dépasser ce que la voiture peut faire.
## - Volant : poursuite d'un point du tracé devant la voiture (plus loin avec la vitesse), décalé sur le côté pour
##   doubler une voiture plus lente ; pédales : vitesse du profil un peu plus loin, freinage avant les virages.
## - KA-BOOM au-delà de 60 km/h perdus d'un coup contre un obstacle ou une voiture (comme le joueur, #121) : explosion,
##   retour sur le tracé RETOUR s après, RECUL m derrière (choix de l'utilisateur) ; retournée, bloquée ou perdue loin
##   du tracé : remise sur le tracé.
## - Loin du joueur (plus de LOIN m : le relief n'a de collisions qu'à 96 m de la caméra), la voiture est figée et
##   avance sur le tracé à l'allure du profil (comme le fantôme) ; elle redevient physique en approchant (PRES m).
## Essai : --drive-test --course-ia-test (essais.gd).
extends Node

const Relief := preload("res://scripts/relief.gd")
const Car := preload("res://scripts/car.gd")
const PerfMon := preload("res://scripts/perf_monitor.gd")
const PAS := 2.0                    # rééchantillonnage du tracé (m)
const A_ACC := 3.0
const A_FREIN := 6.0
const LOIN := 85.0
const PRES := 70.0
const RETOUR := 4.0
const RECUL := 30.0
const VOIE := 2.2                   # décalage latéral maximal pour doubler (m)

var points: Array = []              # étapes (Vector2) : départ, points de passage, arrivée
var temps_cible := 300.0            # temps visé (s)
var a_lat := 5.0                    # accélération latérale admise en virage (m/s²)
var modele := "p106"
var nom := "Concurrent"
var couleur := Color(-1, 0, 0)      # peinture (r < 0 : celle du modèle)
var depart := Transform3D()         # place sur la grille de départ
var main: Node
var autres: Array = []              # voitures de la course (joueur compris) : dépassements
var voiture: Car                    # donnée d'avance (essai : voiture du joueur pilotée), sinon créée
var doubler := true                 # balade (v6.98) : non, on suit la voiture de devant à bonne distance
var suivie := ""                    # balade : voiture suivie (essais : raison d'un arrêt)

var pret := false                   # tracé et profil prêts
var parti := false                  # « Partez ! »
var fini := false
var t := 0.0                        # temps de course
var t_arrivee := -1.0
var s := 0.0                        # progression sur le tracé (m)
var longueur := 0.0
var detruit := 0                    # explosions
var fige := false                   # loin du joueur : sans physique
var evites := {}                    # voitures de la circulation contournées (essais : id -> vrai)

var _propre := false                # voiture créée ici (rendue à la fin)
var _itin
var _etape := 0
var _chemin := PackedVector2Array()
var _s := PackedFloat32Array()
var _v := PackedFloat32Array()      # vitesse du profil (m/s)
var _tps := PackedFloat32Array()    # horaire : heure de passage prévue à chaque point
var _i := 0                         # point du tracé le plus proche
var _allure := 1.0                  # correction de l'allure d'après l'horaire
var _off := 0.0                     # décalage latéral (m, + à gauche)
var _off_but := 0.0
var _boum_t := -1.0
var _bloque_t := 0.0
var _recul_t := 0.0
var _perdu_t := 0.0
var _v_prec := Vector3.ZERO
var _sens_t := 0.0                  # temps passé à contresens du tracé
var _ij := 0                        # point du tracé le plus proche du joueur (classement)

func _ready() -> void:
	_itin = preload("res://scripts/itineraire.gd").new()
	if voiture == null:
		_propre = true
		voiture = Car.new()
		voiture.ia = true
		voiture.voiture = modele
		voiture.name = "Concurrent_" + nom
		main.add_child(voiture)
		if couleur.r >= 0.0 and voiture._paint_mat:
			voiture._paint_mat.albedo_color = couleur
		voiture.contact_monitor = true
		voiture.max_contacts_reported = 4
		voiture.global_transform = depart
		voiture.hold(1.0)
		if main.get("car"):
			voiture.set_lights(main.car.lights_on)
		# nom au-dessus de la voiture, même taille à l'écran de près comme de loin
		var l := Label3D.new()
		l.text = nom
		l.font_size = 48
		l.pixel_size = 0.0011
		l.fixed_size = true
		l.outline_size = 10
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.modulate = Color(1, 1, 1) if couleur.r < 0.0 else couleur.lightened(0.45)
		l.position = Vector3(0, voiture.gabarit.y + 0.9, 0)
		l.visibility_range_end = 160.0
		voiture.add_child(l)
	if points.size() >= 2:
		_itin.calculer(points[0], points[1])

func _exit_tree() -> void:
	if _propre and is_instance_valid(voiture):
		voiture.queue_free()

func _process(_dt: float) -> void:
	if pret:
		return
	_itin.suivre()
	if _itin.pret and _etape < points.size() - 1:
		var r: PackedVector2Array = _itin.route
		if r.size() < 2:
			r = PackedVector2Array([points[_etape], points[_etape + 1]])     # pas d'itinéraire : ligne droite
		if not _chemin.is_empty():
			r = r.slice(1)
		_chemin.append_array(r)
		_etape += 1
		if _etape < points.size() - 1:
			_itin.pret = false
			_itin.calculer(points[_etape], points[_etape + 1])
		else:
			_profil()
			pret = true

## Rééchantillonnage, vitesses limites (virages, vitesse maximale de la voiture, accélération, freinage), mises à
## l'échelle du temps visé quand la voiture irait plus vite ; horaire.
func _profil() -> void:
	var p := PackedVector2Array([_chemin[0]])
	var reste := 0.0
	for i in range(1, _chemin.size()):
		var a := _chemin[i - 1]; var b := _chemin[i]
		var l := a.distance_to(b)
		var u := PAS - reste
		while u <= l:
			p.append(a.lerp(b, u / l))
			u += PAS
		reste = l - (u - PAS)
	if p[p.size() - 1].distance_to(_chemin[_chemin.size() - 1]) > 0.2:
		p.append(_chemin[_chemin.size() - 1])
	_chemin = p
	var n := p.size()
	_s.resize(n); _v.resize(n); _tps.resize(n)
	_s[0] = 0.0
	for i in range(1, n):
		_s[i] = _s[i - 1] + p[i - 1].distance_to(p[i])
	longueur = _s[n - 1]
	var vmax := float(voiture.vmax) / 3.6 * 0.92
	for i in n:
		# courbure sur ±3 points (6 m de part et d'autre) : angle entre les deux directions / distance
		var i0 := maxi(i - 3, 0); var i1 := mini(i + 3, n - 1)
		var k := 0.0
		if i1 - i0 >= 2:
			var d0 := (p[i] - p[i0]).normalized(); var d1 := (p[i1] - p[i]).normalized()
			k = absf(d0.angle_to(d1)) / maxf(_s[i1] - _s[i0], 0.1)
		_v[i] = minf(vmax, sqrt(a_lat / maxf(k, 1e-4)))
	var T := _horaire()
	if T < temps_cible:                       # plus rapide que visé : même allure partout, arrivée au temps visé
		for i in n:
			_v[i] *= T / temps_cible
		_horaire()

func _horaire() -> float:
	var n := _v.size()
	_v[0] = 0.0
	for i in range(1, n):                     # accélération
		_v[i] = minf(_v[i], sqrt(_v[i - 1] * _v[i - 1] + 2.0 * A_ACC * (_s[i] - _s[i - 1])))
	for i in range(n - 2, -1, -1):            # freinage
		_v[i] = minf(_v[i], sqrt(_v[i + 1] * _v[i + 1] + 2.0 * A_FREIN * (_s[i + 1] - _s[i])))
	_tps[0] = 0.0
	for i in range(1, n):
		_tps[i] = _tps[i - 1] + (_s[i] - _s[i - 1]) / maxf((_v[i - 1] + _v[i]) * 0.5, 0.5)
	return _tps[n - 1]

## Point du tracé, direction et vitesse du profil à la distance d du départ.
func _au(d: float) -> Array:
	var n := _s.size()
	var i := clampi(_s.bsearch(d), 1, n - 1)
	var f := clampf((d - _s[i - 1]) / maxf(_s[i] - _s[i - 1], 1e-4), 0.0, 1.0)
	var dir := (_chemin[mini(i + 1, n - 1)] - _chemin[maxi(i - 2, 0)]).normalized()
	return [_chemin[i - 1].lerp(_chemin[i], f), dir, lerpf(_v[i - 1], _v[i], f)]

## Progression du joueur sur ce tracé (classement), cherchée autour de la précédente.
func progression(p: Vector3) -> float:
	if not pret:
		return 0.0
	var q := Vector2(p.x, p.z)
	var bd := INF
	for i in range(maxi(_ij - 10, 0), mini(_ij + 60, _chemin.size())):
		var d := q.distance_squared_to(_chemin[i])
		if d < bd:
			bd = d; _ij = i
	return _s[_ij]

func _physics_process(dt: float) -> void:
	var t0 := Time.get_ticks_usec()
	_pas(dt)
	PerfMon.note("concurrents", Time.get_ticks_usec() - t0)

func _pas(dt: float) -> void:
	if not pret or not is_instance_valid(voiture):
		return
	if not parti:
		_tenir()
		return
	t += dt
	if _boum_t >= 0.0:
		_boum_t -= dt
		if _boum_t < 0.0:
			_reposer(maxf(s - RECUL, 0.0))
		return
	if not fige:
		_suivre()
	if not fini and s >= longueur - 8.0:
		fini = true
		t_arrivee = t
	var j = main.get("car")
	var dj: float = voiture.global_position.distance_to(j.global_position) if j and j != voiture else 0.0
	if fige:
		if dj < PRES:
			_degeler()
		else:
			_glisser(dt)
			return
	elif dj > LOIN and _propre:
		_figer()
		return
	_piloter(dt)
	_surveiller(dt)

## Avant le départ : tenue sur la grille, posée sur le sol (le relief se charge pendant le compte à rebours).
func _tenir() -> void:
	if not _propre:
		return
	var xf := depart
	var h := Relief.hauteur(xf.origin)
	if is_finite(h):
		xf.origin.y = h + 0.1
	voiture.global_transform = xf
	voiture.hold(0.1)

## Avance de la progression : point du tracé le plus proche, cherché autour du précédent.
func _suivre() -> void:
	var p := Vector2(voiture.global_position.x, voiture.global_position.z)
	var bd := INF
	var bi := _i
	for i in range(maxi(_i - 5, 0), mini(_i + 40, _chemin.size())):
		var d := p.distance_squared_to(_chemin[i])
		if d < bd:
			bd = d; bi = i
	_i = bi
	s = _s[_i]
	_perdu_t = _perdu_t + get_physics_process_delta_time() if bd > 400.0 else 0.0

## Volant (poursuite d'un point devant), pédales (vitesse du profil, horaire), dépassements.
func _piloter(dt: float) -> void:
	var v := voiture.forward_speed()
	var xf := voiture.global_transform
	# allure : en retard sur l'horaire, un peu plus vite (jusqu'à +8 %), en avance, un peu moins
	_allure = clampf(1.0 + (t - _tps[_i]) * 0.01, 0.9, 1.08)
	# vitesse visée : celle qui permet d'atteindre chaque vitesse du profil à venir en freinant à 4 m/s² (le profil
	# compte 6 m/s² ; marge pour le temps de réaction, les descentes et les virages pris en freinant)
	var v_cible := INF
	var d := 0.0
	while d <= maxf(v, 0.0) * 2.0 + 10.0:
		var va := float(_au(s + d)[2]) * _allure
		v_cible = minf(v_cible, sqrt(va * va + 2.0 * 4.0 * maxf(d - maxf(v, 0.0) * 0.3, 0.0)))
		d += 2.0
	if fini:
		v_cible = 0.0
	elif s < 15.0:
		v_cible = maxf(v_cible, 5.0)
	# voiture à côté : on s'écarte (3 m entre les deux) ; voiture devant sur notre trajectoire et plus lente : on se
	# décale du côté libre pour la doubler
	var gene := false
	# voitures à éviter : celles de la course, et celles de la circulation proches (#134 : position, vitesse)
	var vus := []
	for o in autres:
		if o == voiture or not is_instance_valid(o) or o.blown:
			continue
		vus.append([(o as Node3D).global_position, (o as RigidBody3D).linear_velocity, -1])
	var circ = main.get("circulation") if main else null
	if circ:
		for tc in circ.voitures:
			if ((tc.pos as Vector3) - xf.origin).length_squared() < 45.0 * 45.0:
				vus.append([tc.pos, (tc.dir as Vector3) * float(tc.v), int(tc.id)])
	for e in vus:
		var l: Vector3 = xf.affine_inverse() * (e[0] as Vector3)
		if absf(l.x) < 3.0 and l.z > -5.0 and l.z < 4.5:
			gene = true
			_off_but = clampf(_off - signf(l.x) * (3.0 - absf(l.x)), -VOIE, VOIE)
		elif l.z >= 4.5 and l.z < 16.0 + v * 0.8 and absf(l.x) < 2.3:
			var vo: float = (e[1] as Vector3).dot(xf.basis.z)
			if vo < v - 0.5 or l.z < 7.0:
				if not doubler:
					# seulement une voiture qui va dans notre sens, sur notre voie (une voiture qui arrive en face dans
					# une rue étroite n'est pas à suivre : chacune attendrait l'autre)
					var vit_o: Vector3 = e[1]
					if absf(l.x) < 1.6 and (vit_o.length() < 0.5 or vit_o.normalized().dot(xf.basis.z) > 0.5):
						v_cible = minf(v_cible, maxf(maxf(vo, 0.0) + (l.z - 9.0) * 0.4, 0.0))
						suivie = "voiture %d à %.0f m" % [int(e[2]), l.z]
					continue
				gene = true
				if int(e[2]) >= 0:
					evites[int(e[2])] = true
				_off_but = clampf(_off + (-VOIE if l.x > 0.0 else VOIE), -VOIE, VOIE)
				if l.z < 6.0 + v * 0.3 and absf(l.x) < 1.6:
					v_cible = minf(v_cible, maxf(vo - 1.0, 3.0))   # arrêtée devant : on avance au pas et on la pousse
	if not gene:
		_off_but = move_toward(_off_but, 0.0, dt * 0.5)
	_off = move_toward(_off, _off_but, dt * 1.6)
	var vise := clampf(4.0 + maxf(v, 0.0) * 0.45, 4.0, 22.0)
	var c: Array = _au(s + vise)
	var q: Vector2 = c[0] + Vector2(c[1].y, -c[1].x) * _off
	var l := xf.affine_inverse() * Vector3(q.x, xf.origin.y, q.y)
	# poursuite : braquage qui mène sur un arc de cercle jusqu'au point visé (empattement ~2,5 m)
	var alpha := atan2(l.x, l.z)
	var delta := atan2(2.0 * 2.5 * sin(alpha), maxf(Vector2(l.x, l.z).length(), 1.0))
	if l.z < 0.5:                             # point visé derrière : demi-tour, braquage à fond du bon côté, au pas
		delta = signf(l.x) * PI
		v_cible = minf(v_cible, 4.0)
	var k := clampf(absf(v) * 3.6 / 130.0, 0.0, 1.0)
	var st := clampf(delta / lerpf(Car.STEER_LOW, Car.STEER_HIGH, sqrt(k)), -1.0, 1.0)
	var thr := 0.0
	var brk := 0.0
	var e := v_cible - v
	if _recul_t > 0.0:                        # bloquée contre un obstacle : marche arrière, roues braquées à l'opposé
		_recul_t -= dt
		brk = 0.8; st = -st
	elif e > 0.3:
		thr = clampf(e * 0.3 + 0.1, 0.0, 1.0)
	elif e < -0.4:
		brk = clampf(-e * 0.6, 0.2, 1.0)
	voiture.touch_throttle = thr
	voiture.touch_brake = brk
	voiture.touch_steer = st

## Explosion (choc), voiture bloquée, retournée ou perdue loin du tracé.
func _surveiller(dt: float) -> void:
	var vel := voiture.linear_velocity
	var dv := (_v_prec - vel).length() * 3.6
	_v_prec = vel
	if _propre and dv > Car.VITESSE_BOUM and not voiture.get_colliding_bodies().is_empty():
		_exploser()
		return
	if not voiture.global_position.is_finite() or Relief.hauteur(voiture.global_position) - voiture.global_position.y > 4.0:
		_reposer(maxf(s - 10.0, 0.0))                 # passée sous le relief
		return
	if voiture.global_transform.basis.y.y < 0.5 and voiture.kmh() < 20.0:
		_bloque_t += dt * 3.0                         # sur le flanc ou sur le toit
	elif voiture.kmh() < 3.0 and not fini and voiture.touch_throttle > 0.3:
		_bloque_t += dt
		if _bloque_t > 1.5 and _bloque_t - dt <= 1.5:
			_recul_t = 1.4
	else:
		_bloque_t = 0.0
	# à contresens du tracé (après un tête-à-queue ou une marche arrière) : remise dans le bon sens
	var dir: Vector2 = _au(s)[1]
	var cap := voiture.global_transform.basis.z
	_sens_t = _sens_t + dt if Vector2(cap.x, cap.z).normalized().dot(dir) < -0.3 and _recul_t <= 0.0 else 0.0
	if _bloque_t > 4.5 or _perdu_t > 3.0 or _sens_t > 1.5:
		_reposer(maxf(s - 10.0, 0.0))

## KA-BOOM : champignon atomique (#129), la voiture disparaît puis revient sur le tracé RETOUR s plus tard.
func exploser() -> void:
	if _boum_t < 0.0 and not voiture.blown:
		_exploser()

func _exploser() -> void:
	detruit += 1
	var fx = preload("res://scripts/explosion.gd").new()
	fx.style = voiture.style_explosion
	fx.position = voiture.global_position - Vector3(0, 0.3, 0)
	main.add_child(fx)
	if main.get("sound") and main.sound.has_method("boum"):
		main.sound.boum(voiture.global_position)
	voiture.linear_velocity = Vector3.ZERO
	voiture.angular_velocity = Vector3.ZERO
	voiture.blow_up()
	_boum_t = RETOUR
	if main.get("activities") and main.activities.has_method("concurrent_detruit"):
		main.activities.concurrent_detruit(self)

## Remise sur le tracé à la distance d (après une explosion, ou bloquée), à l'arrêt, dans le sens de la course.
func _reposer(d: float) -> void:
	if fige:
		_degeler()
	var c: Array = _au(d)
	var q: Vector2 = c[0]
	var y := Relief.hauteur(Vector3(q.x, 0, q.y))
	if is_nan(y):
		y = voiture.global_position.y
	var cap := rad_to_deg(atan2(c[1].x, -c[1].y))     # 0 = Nord (-Z), sens horaire (car.place)
	if voiture.blown:
		voiture.respawn_at(Vector3(q.x, y + 0.3, q.y), cap)
	else:
		voiture.place(Vector3(q.x, y + 0.3, q.y), cap)
		voiture.hold(0.5)
	_i = clampi(_s.bsearch(d), 0, _s.size() - 1)
	s = d
	_off = 0.0; _off_but = 0.0
	_bloque_t = 0.0; _perdu_t = 0.0; _recul_t = 0.0; _sens_t = 0.0
	_v_prec = Vector3.ZERO

## Loin du joueur : plus de physique, la voiture glisse sur le tracé à l'allure du profil (posée sur le relief).
func _figer() -> void:
	fige = true
	voiture.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	voiture.freeze = true

func _glisser(dt: float) -> void:
	var v: float = maxf(float(_au(s)[2]) * _allure, 3.0) if not fini else 0.0
	s = minf(s + v * dt, longueur)
	_i = clampi(_s.bsearch(s), 0, _s.size() - 1)
	var c: Array = _au(s)
	var q: Vector2 = c[0]
	var dir: Vector2 = c[1]
	var av := q + dir * 1.3; var ar := q - dir * 1.3
	var y_av := Relief.hauteur(Vector3(av.x, 0, av.y)); var y_ar := Relief.hauteur(Vector3(ar.x, 0, ar.y))
	if is_nan(y_av) or is_nan(y_ar):
		return
	var b := Basis(Vector3.UP, atan2(dir.x, dir.y)) * Basis(Vector3.RIGHT, -atan2(y_av - y_ar, 2.6))
	voiture.global_transform = Transform3D(b, Vector3(q.x, (y_av + y_ar) * 0.5 + 0.05, q.y))

func _degeler() -> void:
	fige = false
	voiture.freeze = false
	var c: Array = _au(s)
	voiture.linear_velocity = Vector3(c[1].x, 0.0, c[1].y) * float(c[2]) * _allure
	_v_prec = voiture.linear_velocity
