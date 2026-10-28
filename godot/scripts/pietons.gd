## Passants (v6.88, initiative de Claude) : piétons qui marchent sur les trottoirs, les rues piétonnes et, en ville, le
## long des rues (world/pietons.bin de pipeline/build_pietons.py). Modèles des clients du taxi (assets/clients/mh_*.glb,
## MakeHuman ; marche et attente jouées par pieton.gd d'après `vitesse`), chargés en arrière-plan.
## - Autour du joueur : NOMBRE selon le niveau de performances × réglage ⚙ > Conduite > Circulation (densité commune
##   avec la circulation), moins la nuit ; apparition hors de vue (ou au-delà de R_VU), disparition au-delà de R_LOIN ;
##   lignes tirées selon leur poids (bâti, lieux publics proches). Réserve de passants cachés (pas de new/free en jeu).
## - Chemin : la ligne jusqu'au bout, puis une autre ligne du même nœud, sinon demi-tour ; pauses de temps en temps.
##   Passages piétons (genre 3) : il attend au bord qu'aucune voiture n'arrive (_libre), puis traverse ; les voitures de
##   la circulation s'arrêtent devant lui (sur_passage(), obstacles de circulation.gd). Arrêts de bus (genre 4) : il
##   attend sur place, face à la route.
## - Voiture pilotée (joueur, concurrent) qui fonce sur lui : il s'écarte d'un bond, perpendiculairement à sa route, puis
##   revient sur son chemin ; touché quand même : « pouf » (éclair de téléportation du taxi), il disparaît. Personne
##   n'est jamais blessé.
## Klaxon du joueur (klaxon.gd) : klaxon() ; ils se tournent vers la voiture, s'écartent s'ils sont devant elle.
## Essai : -- --drive-test --pietons-test.
extends Node3D

const PerfMon := preload("res://scripts/perf_monitor.gd")
const Relief := preload("res://scripts/relief.gd")
const PIETON := preload("res://scripts/pieton.gd")
const NOMBRE := [3, 8, 12, 16]                 # par niveau de performances (Économie, Équilibré, Élevée, Maximale)
const DENSITES := [0.0, 0.5, 1.0, 1.6]         # comme circulation.gd (⚙ > Conduite > Circulation)
const NUIT := 0.35                             # part des passants la nuit
const PLUIE := 0.4                             # part des passants sous la pluie (main.pluie, v6.91), qui pressent le pas
const R_MIN := 25.0                            # apparition au moins à cette distance
const R_MAX := 110.0
const R_VU := 75.0                             # apparition dans le champ seulement au-delà
const R_LOIN := 140.0
const CASE := 64.0
const BOND := 4.5                              # vitesse de l'écart (m/s)
const T_BOND := 0.65

var target: Node3D
var main: Node
var ok := false
var niveau := 1
var densite := 2
var passants: Array = []                       # en scène : {n, k, l, s, sens, v, lat, pause, off, bond, bond_t, m}
var bonds := 0                                 # écarts devant une voiture (essais)
var poufs := 0                                 # passants touchés (essais)
var traversees := 0                            # passages piétons empruntés (essais)
var sursauts := 0                              # passants qui ont entendu le klaxon du joueur (essais)
var adoptes := 0                               # clients du taxi devenus passants (essais)
var fuites := 0                                # passants qui ont fui une explosion (essais)
var montes := 0                                # passants montés dans un bus (essais)
var descendus := 0                             # passants descendus d'un bus (essais)

var _p0 := PackedInt32Array()
var _np := PackedInt32Array()
var _na := PackedInt32Array()
var _nb := PackedInt32Array()
var _genre := PackedInt32Array()
var _poids := PackedFloat32Array()
var _pas := PackedFloat32Array()               # écart entre deux points de chaque ligne (m)
var _pts := PackedVector3Array()
var _adj := {}                                 # nœud -> PackedInt32Array de (ligne << 1 | bout)
var _grille := {}                              # case -> PackedInt32Array de lignes
var _modeles: Array = []                       # [chemin, scène ou null, sexe, âge]
var _reserve: Array = []                       # passants cachés, prêts à resservir : [nœud, modèle]
var _remplir := true
var _presse := 1.0                             # pas pressé sous la pluie

func _ready() -> void:
	ok = _charger()
	if not ok:
		return
	var f := "res://assets/clients/mh.json"
	var mh = JSON.parse_string(FileAccess.get_file_as_string(f)) if FileAccess.file_exists(f) else []
	for e in mh:
		var ch := "res://assets/clients/" + str(e.fichier)
		if ResourceLoader.exists(ch):
			ResourceLoader.load_threaded_request(ch)
			_modeles.append([ch, null, str(e.get("sexe", "m")), int(e.get("age", 30))])
	ok = not _modeles.is_empty()

func _charger() -> bool:
	var f := "res://world/pietons.bin"
	if not FileAccess.file_exists(f):
		return false
	var b := FileAccess.get_file_as_bytes(f)
	var o := 0
	var nl := b.decode_s32(o); o += 4
	var t := b.slice(o, o + nl * 24); o += nl * 24
	var ti := t.to_int32_array()
	var tf := t.to_float32_array()
	for v in [_p0, _np, _na, _nb, _genre]:
		v.resize(nl)
	_poids.resize(nl); _pas.resize(nl)
	for k in nl:
		_p0[k] = ti[k * 6]; _np[k] = ti[k * 6 + 1]; _na[k] = ti[k * 6 + 2]; _nb[k] = ti[k * 6 + 3]
		_genre[k] = ti[k * 6 + 4]; _poids[k] = tf[k * 6 + 5]
	var np := b.decode_s32(o); o += 4
	var xyz := b.slice(o, o + np * 12).to_float32_array()
	_pts.resize(np)
	for i in np:
		_pts[i] = Vector3(xyz[i * 3], xyz[i * 3 + 1], xyz[i * 3 + 2])
	for k in nl:
		var p0 := _p0[k]
		var n := _np[k]
		var L := 0.0
		for i in range(1, n):
			L += Vector2(_pts[p0 + i].x - _pts[p0 + i - 1].x, _pts[p0 + i].z - _pts[p0 + i - 1].z).length()
		_pas[k] = L / float(maxi(n - 1, 1))
		for bout in 2:
			var nd := _na[k] if bout == 0 else _nb[k]
			var a: PackedInt32Array = _adj.get(nd, PackedInt32Array())
			a.append((k << 1) | bout)
			_adj[nd] = a
		var vu := {}
		for i in range(0, n, 4):
			var c := Vector2i(floori(_pts[p0 + i].x / CASE), floori(_pts[p0 + i].z / CASE))
			if not vu.has(c):
				vu[c] = true
				var g: PackedInt32Array = _grille.get(c, PackedInt32Array())
				g.append(k)
				_grille[c] = g
	return nl > 0

# ================================================================ réglages
func voulu() -> int:
	var n := float(NOMBRE[clampi(niveau, 0, NOMBRE.size() - 1)]) * float(DENSITES[clampi(densite, 0, DENSITES.size() - 1)])
	if main and int(main.get("time_of_day")) == 3:
		n *= NUIT
	if main:
		n *= lerpf(1.0, PLUIE, float(main.get("pluie")))
	return int(round(n))

func set_niveau(n: int) -> void:
	niveau = n

func set_densite(d: int) -> void:
	densite = clampi(d, 0, DENSITES.size() - 1)

## Téléportation : tout est replacé autour de la nouvelle position.
func vider() -> void:
	for i in range(passants.size() - 1, -1, -1):
		_retirer(i)
	_remplir = true

# ================================================================ chemins
func longueur(k: int) -> float:
	return _pas[k] * float(_np[k] - 1)

## Point de la ligne k à s m de son début.
func point(k: int, s: float) -> Vector3:
	var u := clampf(s / maxf(_pas[k], 0.01), 0.0, float(_np[k] - 1))
	var i := mini(int(u), _np[k] - 2)
	return _pts[_p0[k] + i].lerp(_pts[_p0[k] + i + 1], u - float(i))

## Sens de la ligne k à s m (vers la fin de la ligne).
func tangente(k: int, s: float) -> Vector3:
	var i := clampi(int(s / maxf(_pas[k], 0.01)), 0, _np[k] - 2)
	var d := _pts[_p0[k] + i + 1] - _pts[_p0[k] + i]
	d.y = 0.0
	return d.normalized() if d.length_squared() > 1e-6 else Vector3.FORWARD

func _visible(p: Vector3) -> bool:
	var cam := get_viewport().get_camera_3d()
	return cam != null and cam.is_position_in_frustum(p + Vector3(0, 1.0, 0))

# ================================================================ apparition, disparition
## Un modèle chargé, le moins porté par les passants en scène (pas de jumeaux côte à côte) ; -1 : aucun encore.
func _modele_pret() -> int:
	var nb := {}
	for c in passants:
		nb[int(c.m)] = int(nb.get(int(c.m), 0)) + 1
	var meilleur := -1
	var n_min := 1 << 30
	for i in _modeles.size():
		var m: Array = _modeles[i]
		if m[1] == null and ResourceLoader.load_threaded_get_status(m[0]) == ResourceLoader.THREAD_LOAD_LOADED:
			m[1] = ResourceLoader.load_threaded_get(m[0])
		if m[1] != null:
			var k := int(nb.get(i, 0)) * 8 + randi() % 8
			if k < n_min:
				n_min = k
				meilleur = i
	return meilleur

func _apparaitre(p: Vector3, partout: bool) -> void:
	var q := Vector2(p.x, p.z) + Vector2.from_angle(randf() * TAU) * randf_range(R_MIN, R_MAX)
	var lignes: PackedInt32Array = _grille.get(Vector2i(floori(q.x / CASE), floori(q.y / CASE)), PackedInt32Array())
	if lignes.is_empty():
		return
	var k := lignes[randi() % lignes.size()]
	if _genre[k] == 3 or randf() * 3.0 > _poids[k] + 0.25:
		return
	var s := randf_range(0.0, longueur(k))
	var pos := point(k, s)
	var d := pos.distance_to(p)
	if d < R_MIN * (0.5 if partout else 1.0) or d > R_MAX + 10.0:
		return
	if not partout and d < R_VU and _visible(pos):
		return
	for o in passants:
		if (o.n as Node3D).global_position.distance_squared_to(pos) < 9.0:
			return
	var m := _modele_pret()
	if m < 0:
		return
	var n: Node3D = null
	for i in _reserve.size():
		if int(_reserve[i][1]) == m:
			n = _reserve[i][0]
			_reserve.remove_at(i)
			break
	if n == null:
		n = (_modeles[m][1] as PackedScene).instantiate()
		n.set_script(PIETON)
		add_child(n)
	n.visible = true
	n.process_mode = Node.PROCESS_MODE_INHERIT
	var age := int(_modeles[m][3])
	var v := randf_range(1.15, 1.5) * (0.75 if age >= 60 else 1.0)
	var c := {"n": n, "m": m, "l": k, "s": s, "sens": 1 if randf() < 0.5 else -1, "v": v, "lat": randf_range(-0.3, 0.3),
		"pause": randf_range(0.0, 6.0) if randf() < 0.3 else 0.0, "off": Vector3.ZERO, "bond": Vector3.ZERO, "bond_t": 0.0,
		"traverse": -1, "attente": 0.0, "regard": Vector3.ZERO, "regard_t": 0.0}
	if _genre[k] == 4:                           # arrêt de bus : attend sur place, tourné vers la route
		c.pause = 1e9
		c.lat = 0.0
		c.sens = 1
	passants.append(c)
	_placer(c, 1.0)

func _retirer(i: int) -> void:
	var c: Dictionary = passants[i]
	var n: Node3D = c.n
	n.visible = false
	n.process_mode = Node.PROCESS_MODE_DISABLED
	_reserve.append([n, int(c.m)])
	passants.remove_at(i)

# ================================================================ marche
func _physics_process(dt: float) -> void:
	if not ok or target == null or get_tree().paused:
		return
	var t0 := Time.get_ticks_usec()
	_presse = 1.0 + 0.3 * (float(main.get("pluie")) if main else 0.0)
	var p := target.global_position
	for i in range(passants.size() - 1, -1, -1):
		if (passants[i].n as Node3D).global_position.distance_to(p) > R_LOIN:
			_retirer(i)
	var n := voulu()
	while passants.size() > n:                   # en trop (réglage baissé, client du taxi adopté) : hors de vue d'abord
		var j := -1
		for i in passants.size():
			var q: Vector3 = (passants[i].n as Node3D).global_position
			if not _visible(q) and (j < 0 or q.distance_squared_to(p) > (passants[j].n as Node3D).global_position.distance_squared_to(p)):
				j = i
		if j < 0:
			break
		_retirer(j)
	var essais := 60 if _remplir else 2
	while passants.size() < n and essais > 0:
		essais -= 1
		_apparaitre(p, _remplir)
	if _remplir and passants.size() >= n:
		_remplir = false
	var autos := _autos()
	for i in range(passants.size() - 1, -1, -1):
		var c: Dictionary = passants[i]
		if bool(c.get("a_bord", false)):         # monté dans le bus (v7.01)
			montes += 1
			_retirer(i)
			continue
		if _eviter(c, autos):
			_retirer(i)
			continue
		_marcher(c, dt)
		_placer(c, dt)
	PerfMon.note("pietons", Time.get_ticks_usec() - t0)

## Arrêts de bus (genre 4) : position de chaque ligne (circulation.gd : les bus s'y arrêtent, v7.01).
func arrets_bus() -> PackedVector3Array:
	var l := PackedVector3Array()
	for k in _genre.size():
		if _genre[k] == 4:
			l.append(point(k, longueur(k) * 0.5))
	return l

## Bus arrêté à l'arrêt p, porte avant à `porte` (v7.01) : les passants qui attendent à moins de 15 m montent (ils
## marchent jusqu'à la porte puis disparaissent) ; un ou deux autres descendent et partent à pied. [montés, descendus]
func bus_a_l_arret(p: Vector3, porte: Vector3) -> Array:
	if not ok:
		return [0, 0]
	var m0 := 0
	for c in passants:
		if _genre[int(c.l)] == 4 and (c.n as Node3D).global_position.distance_to(p) < 15.0 and not c.has("monte"):
			c.monte = porte
			c.pause = 0.0
			m0 += 1
	var d0 := 0
	for i in randi_range(1, 2):
		var m := _modele_pret()
		if m < 0:
			break
		var n: Node3D = null
		for j in _reserve.size():
			if int(_reserve[j][1]) == m:
				n = _reserve[j][0]
				_reserve.remove_at(j)
				break
		if n == null:
			n = (_modeles[m][1] as PackedScene).instantiate()
			n.set_script(PIETON)
			add_child(n)
		n.visible = true
		n.process_mode = Node.PROCESS_MODE_INHERIT
		n.global_position = porte + Vector3(randf_range(-0.4, 0.4), 0.0, randf_range(-0.4, 0.4))
		if adopter(n, m):
			adoptes -= 1                            # compté comme descendu, pas comme client du taxi
			d0 += 1
		else:
			n.visible = false
			n.process_mode = Node.PROCESS_MODE_DISABLED
			_reserve.append([n, m])
	descendus += d0
	return [m0, d0]

## Client du taxi déposé (activities.gd) : il devient un passant, rejoint la ligne la plus proche (25 m) et poursuit
## son chemin ; il ne disparaît que loin ou hors de vue. Modèle m de mh.json (-1 : inconnu). Faux si aucune ligne.
func adopter(n: Node3D, m: int) -> bool:
	if not ok or m < 0 or m >= _modeles.size():
		return false
	var p := n.global_position
	var best := -1
	var bs := 0.0
	var bd := 25.0 * 25.0
	var c0 := Vector2i(floori(p.x / CASE), floori(p.z / CASE))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for k: int in _grille.get(c0 + Vector2i(dx, dz), PackedInt32Array()):
				if _genre[k] == 3 or _genre[k] == 4:
					continue
				for i in _np[k]:
					var q := _pts[_p0[k] + i]
					var d := Vector2(q.x - p.x, q.z - p.z).length_squared()
					if d < bd:
						bd = d; best = k; bs = float(i) * _pas[k]
	if best < 0:
		return false
	if n.get_parent() != self:
		n.reparent(self)
	n.set("cible", Vector3.INF)
	var off := p - point(best, bs)                # rejoint la ligne en marchant (off s'estompe)
	off.y = 0.0
	var c := {"n": n, "m": m, "l": best, "s": bs, "sens": 1 if randf() < 0.5 else -1, "v": randf_range(1.2, 1.45),
		"lat": randf_range(-0.2, 0.2), "pause": 0.0, "off": off, "bond": Vector3.ZERO, "bond_t": 0.0,
		"traverse": -1, "attente": 0.0, "regard": Vector3.ZERO, "regard_t": 0.0}
	passants.append(c)
	adoptes += 1
	return true

## Voitures pilotées : [position, vitesse, transformation].
func _autos() -> Array:
	var l := []
	var circ = main.get("circulation") if main else null
	var pil: Array = circ._pilotes() if circ and circ.has_method("_pilotes") else ([main.car] if main and main.get("car") else [])
	for o in pil:
		var b: RigidBody3D = o
		if b.visible:
			var v := b.linear_velocity
			v.y = 0.0
			l.append([b.global_position, v, b.global_transform])
	return l

func _marcher(c: Dictionary, dt: float) -> void:
	if float(c.bond_t) > 0.0:                    # écart d'un bond
		c.bond_t = float(c.bond_t) - dt
		c.off = (c.off as Vector3) + (c.bond as Vector3) * dt
		return
	if c.has("monte"):                           # vers la porte du bus (v7.01), puis à bord
		var vers: Vector3 = (c.monte as Vector3) - (c.n as Node3D).global_position
		vers.y = 0.0
		if vers.length() < 0.8:
			c.a_bord = true
		else:
			c.off = (c.off as Vector3) + vers.normalized() * 1.5 * dt
			c.regard = c.monte
			c.regard_t = 1.0
		return
	if float(c.pause) > 0.0:
		c.pause = float(c.pause) - dt
		return
	c.off = (c.off as Vector3).move_toward(Vector3.ZERO, dt * 0.8)      # retour sur son chemin après un bond
	if int(c.traverse) >= 0:                     # au bord du passage piéton : attend que la voie soit libre
		c.attente = float(c.attente) + dt
		if _libre(int(c.traverse) >> 1):
			_prendre(c, int(c.traverse))
		elif float(c.attente) > 25.0:
			c.traverse = -1
			c.sens = -int(c.sens)
		return
	var k := int(c.l)
	var L := longueur(k)
	var s := float(c.s) + float(c.sens) * float(c.v) * _presse * (1.2 if _genre[k] == 3 else 1.0) * dt
	if s >= 0.0 and s <= L:
		c.s = s
		if _genre[k] != 3 and randf() < dt / 40.0:          # s'arrête de temps en temps (vitrine, téléphone…)
			c.pause = randf_range(2.0, 7.0)
		return
	# bout de la ligne : une autre ligne du même nœud (passage piéton une fois sur deux), sinon demi-tour
	c.s = clampf(s, 0.0, L)
	var nd := _nb[k] if int(c.sens) > 0 else _na[k]
	var a: PackedInt32Array = _adj.get(nd, PackedInt32Array())
	var autres := []
	var passages := []
	for e in a:
		if e >> 1 != k:
			if _genre[e >> 1] == 3:
				if _genre[k] != 3:
					passages.append(e)
			else:
				autres.append(e)
	if not passages.is_empty() and (autres.is_empty() or randf() < 0.5):
		c.traverse = passages[randi() % passages.size()]
		c.attente = 0.0
		return
	if autres.is_empty() or (_genre[k] != 3 and randf() < 0.15):
		c.sens = -int(c.sens)
		if randf() < 0.5:
			c.pause = randf_range(1.0, 4.0)
		return
	_prendre(c, autres[randi() % autres.size()])

## Passe sur la ligne e >> 1 par son bout e & 1.
func _prendre(c: Dictionary, e: int) -> void:
	if _genre[e >> 1] == 3:
		traversees += 1
	c.traverse = -1
	c.l = e >> 1
	c.sens = 1 if e & 1 == 0 else -1
	c.s = 0.0 if e & 1 == 0 else longueur(e >> 1)

## Passage piéton k libre : aucune voiture dessus ni qui arrive (40 m).
func _libre(k: int) -> bool:
	var m := point(k, longueur(k) * 0.5)
	var circ = main.get("circulation") if main else null
	if circ:
		for v in circ.voitures:
			var d: Vector3 = m - (v.pos as Vector3)
			d.y = 0.0
			var dl := d.length()
			if dl < 7.0:
				return false
			var f: Vector3 = v.dir
			var av := d.dot(f)
			if dl < 40.0 and float(v.v) > 0.5 and av > 0.0 and (d - f * av).length() < 6.0:
				return false
	for a in _autos():
		var d: Vector3 = m - (a[0] as Vector3)
		d.y = 0.0
		var dl := d.length()
		if dl < 8.0 or (dl < 40.0 and (a[1] as Vector3).dot(d) > 1.5 * dl):
			return false
	return true

## Passants sur un passage piéton (circulation.gd : obstacles) : [position, vitesse].
func sur_passage() -> Array:
	var l := []
	for c in passants:
		var k := int(c.l)
		if _genre[k] == 3 and int(c.traverse) < 0:
			l.append([(c.n as Node3D).global_position, tangente(k, float(c.s)) * float(c.sens) * float(c.v)])
	return l

func _placer(c: Dictionary, dt: float) -> void:
	var k := int(c.l)
	var s := float(c.s)
	var t := tangente(k, s) * float(c.sens)
	var pos := point(k, s) + Vector3(-t.z, 0.0, t.x) * float(c.lat) + (c.off as Vector3)
	if _genre[k] == 2 or (c.off as Vector3).length_squared() > 0.04:
		var y0 := pos.y
		pos.y = clampf(Relief.hauteur(pos), y0 - 0.6, y0 + 0.6)
	var n: Node3D = c.n
	n.global_position = pos
	var dir := t
	if int(c.traverse) >= 0:                      # tourné vers le passage piéton
		var e := int(c.traverse)
		dir = tangente(e >> 1, 0.0 if e & 1 == 0 else longueur(e >> 1)) * (1.0 if e & 1 == 0 else -1.0)
	if float(c.regard_t) > 0.0:                   # se tourne vers la voiture qui klaxonne
		c.regard_t = float(c.regard_t) - dt
		var vers: Vector3 = (c.regard as Vector3) - pos
		vers.y = 0.0
		if vers.length_squared() > 0.01:
			dir = vers.normalized()
	var vit := 0.0 if float(c.pause) > 0.0 or int(c.traverse) >= 0 else float(c.v) * _presse
	if float(c.bond_t) > 0.0:
		dir = (c.bond as Vector3).normalized()
		vit = BOND
	elif (c.off as Vector3).length_squared() > 0.01 and float(c.pause) <= 0.0:
		vit = maxf(vit, 0.6)
	n.rotation.y = lerp_angle(n.rotation.y, atan2(dir.x, dir.z), 1.0 - exp(-dt * 7.0))
	n.set("vitesse", vit)

## Voiture qui fonce sur le passant : bond de côté ; touché quand même : « pouf ». Vrai si le passant disparaît.
func _eviter(c: Dictionary, autos: Array) -> bool:
	var pos: Vector3 = (c.n as Node3D).global_position
	for a in autos:
		var rel: Vector3 = pos - (a[0] as Vector3)
		rel.y = 0.0
		if rel.length_squared() > 35.0 * 35.0:
			continue
		var v: Vector3 = a[1]
		var v2 := v.length_squared()
		var l: Vector3 = (a[2] as Transform3D).affine_inverse() * pos
		if v2 > 1.5 * 1.5 and absf(l.x) < 1.25 and absf(l.z) < 2.8 and l.y > -1.5 and l.y < 2.5:
			poufs += 1
			var act = main.get("activities") if main else null
			if act and act.has_method("_teleport_fx"):
				act._teleport_fx(pos)
			return true
		if v2 < 2.5 * 2.5 or float(c.bond_t) > 0.0:
			continue
		var tc := rel.dot(v) / v2                     # instant du plus proche passage
		if tc < 0.0 or tc > 1.8:
			continue
		var ecart := rel - v * tc                     # où il sera par rapport à la trajectoire de la voiture
		if ecart.length() < 1.7:
			var cote := ecart.normalized() if ecart.length() > 0.2 else Vector3(-v.z, 0.0, v.x).normalized() * (1.0 if randf() < 0.5 else -1.0)
			c.bond = cote * BOND
			c.bond_t = T_BOND
			c.pause = randf_range(1.5, 2.5)               # puis reste planté là, le temps de se remettre
			bonds += 1
	return false

## Coup de klaxon du joueur en p (avant de la voiture : f) : les passants à moins de 30 m sursautent et se tournent vers
## la voiture ; devant elle (14 m), ils s'écartent d'un bond ; sur un passage piéton, ils pressent le pas.
func klaxon(p: Vector3, f: Vector3) -> void:
	for c in passants:
		var d: Vector3 = (c.n as Node3D).global_position - p
		d.y = 0.0
		var dl := d.length()
		if dl > 30.0:
			continue
		sursauts += 1
		if _genre[int(c.l)] == 3 and int(c.traverse) < 0:
			c.v = minf(float(c.v) * 1.7, 2.6)
			continue
		if dl < 14.0 and d.dot(f) > 0.6 * dl and float(c.bond_t) <= 0.0:
			var lat := d - f * d.dot(f)
			c.bond = (lat.normalized() if lat.length() > 0.2 else Vector3(-f.z, 0.0, f.x)) * BOND
			c.bond_t = T_BOND
			c.pause = maxf(float(c.pause), randf_range(1.0, 2.0))
			bonds += 1
		else:
			c.regard = p
			c.regard_t = 1.6
			c.pause = maxf(float(c.pause), 1.2)

## Explosion en p (explosion.gd) : les passants à moins de 60 m s'enfuient en courant, puis restent plantés là.
func panique(p: Vector3) -> void:
	for c in passants:
		var d: Vector3 = (c.n as Node3D).global_position - p
		d.y = 0.0
		if d.length() > 60.0:
			continue
		var fuite := d.normalized() if d.length() > 0.5 else Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
		c.bond = fuite * randf_range(4.0, 5.0)
		c.bond_t = randf_range(2.5, 3.5)
		c.pause = randf_range(2.0, 4.0)
		c.traverse = -1
		fuites += 1
