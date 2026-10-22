## Décor destructible (v6.9, issue #7) : panneaux de signalisation, lampadaires, clôtures (grillages, panneaux,
## poteaux), haies et murets (v6.24 : au-delà d'une vitesse minimale, sinon obstacles) et petits arbres (moins de 9 m : les gros restent des obstacles) sont
## renversés quand la voiture les touche.
## - Détection avant le contact : boîte de la voiture (meta.json) élargie du rayon de l'objet ; candidats proches
##   relevés toutes les 0,2 s (panneaux : world/panneaux.bin de build_casse.py ; lampadaires : poles.pieds ;
##   arbres : vegetation.data ; clôtures : fences.lignes), testés à chaque pas de physique.
## - L'objet disparaît de son lot (exemplaire caché, ou sommets effacés par le shader : env_casse, uniform casse_pts).
##   #123 (v6.81) : clôtures, grillages, haies, murets et piliers éclatent en plusieurs morceaux ; petits arbres,
##   lampadaires et poteaux électriques ou téléphoniques (fils coupés) basculent et se couchent. Les débris restent
##   au sol (figés une fois immobiles) tant que la voiture ne s'éloigne pas à plus de LOIN m.
## - La voiture perd un peu de vitesse selon l'objet ; son du choc selon la matière ; poussière et éclats (dust.gd).
## Tout réapparaît quand la tuile est rechargée (on revient plus tard).
extends Node3D

const Env := preload("res://scripts/env.gd")
const PerfMon := preload("res://scripts/perf_monitor.gd")
const LOIN := 220.0               # #123 : débris rendus à la réserve quand la voiture s'en éloigne à plus de LOIN m
const POSE := 1.5                 # immobile depuis POSE s : figé sur place (plus de calcul physique)
const MAX_DEBRIS := 32
const ARBRE_MAX := 9.0            # hauteur maximale d'un arbre cassable (m)
const GRILLE := 16.0
# perte de vitesse (part, inutilisée depuis #105), son, rayon de l'objet (m), vitesse minimale pour casser (m/s)
const KINDS := {
	"panneau": [0.06, "choc_leger_%d", 0.12, 0.0],
	"lampadaire": [0.22, "choc_dur_%d", 0.18, 0.0],
	"arbre": [0.14, "choc_bois_%d", 0.2, 0.0],
	"cloture": [0.1, "choc_bois_%d", 0.1, 0.0],
	"haie": [0.2, "choc_bois_%d", 0.45, 3.0],
	"muret": [0.38, "choc_dur_%d", 0.22, 2.5],          # v6.55 (#85) : 7 m/s avant, on ne les cassait presque jamais
	"pilier": [0.3, "choc_dur_%d", 0.25, 2.5],          # piliers de portail (#85)
	"grillage": [0.08, "choc_leger_%d", 0.1, 0.0],       # clôture d'emprise de l'autoroute (#76), grillages des terrains de sport (#85)
	"barriere": [0.05, "choc_leger_%d", 0.12, 0.0],      # bras des barrières de passage à niveau (#125, rails.gd)
	"poteau": [0.2, "choc_bois_%d", 0.18, 2.0],          # poteaux électriques et téléphoniques (#123, poles.gd)
}
const LIGNES := ["cloture", "haie", "muret", "pilier"]      # fences.genres
# matière de chaque genre pour les sons de choc (audio.impact, issue #28)
const MATIERE := {"panneau": "metal", "lampadaire": "metal", "arbre": "bois", "cloture": "bois", "haie": "haie", "muret": "dur", "pilier": "dur", "grillage": "metal", "barriere": "metal", "poteau": "bois"}
# genres qui basculent et se couchent au sol (#123) ; les autres éclatent
const COUCHES := ["arbre", "lampadaire", "poteau"]
# #123 (v6.82) : objets des terrains de sport (sport.gd) et de l'autoroute (autoroute.gd) : comportement (« repousse »,
# « couche », « segment » = travée de glissière ou de séparateur, défoncée seulement par un choc de face), rayon de
# détection (m), masse (kg), matière (son), vitesse minimale (m/s ; segments : vitesse perpendiculaire à la travée)
const OBJETS := {
	"but_foot": ["repousse", 0.2, 110.0, "metal", 0.0],
	"poteaux_rugby": ["repousse", 0.25, 160.0, "metal", 0.0],
	"filet_tennis": ["repousse", 0.15, 25.0, "metal", 0.0],
	"panier_basket": ["couche", 0.3, 180.0, "metal", 0.0],
	"mat_eclairage": ["couche", 0.35, 700.0, "metal", 3.0],
	"banc_touche": ["repousse", 0.4, 90.0, "metal", 0.0],
	"borne_sos": ["repousse", 0.3, 60.0, "metal", 0.0],
	"panneau_bleu": ["repousse", 0.3, 45.0, "metal", 0.0],
	"chevron": ["repousse", 0.12, 8.0, "metal", 0.0],
	"rond": ["repousse", 0.1, 8.0, "metal", 0.0],
	"glissiere": ["segment", 0.2, 70.0, "metal", 5.0],
	"gba": ["segment", 0.3, 900.0, "dur", 8.0],
}

var main: Node
var car: VehicleBody3D
var poles: Node
var vegetation: Node
var fences: Node
var _hw := 0.95                   # demi-largeur, demi-longueur de la voiture
var _hl := 2.6
var _panneaux := {}               # case de 16 m -> Array de Vector4 (x, y du pied, z, hauteur)
var _arbres := {}                 # tuile -> [arbres affichés, {case de 16 m -> PackedInt32Array (indices cassables)}]
var _proches: Array = []          # [genre, données…] relevés toutes les 0,2 s
var _t := 0.0
var _casses: Array = []           # points déjà cassés (Vector3) : pas deux fois
var _pts: Array = []              # points effacés par le shader (Vector4), 16 au plus
var _debris: Array = []           # [RigidBody3D, âge, temps immobile]
var _pas := 0

func _ready() -> void:
	_preparer_reserve()
	var meta_p := "res://assets/car/meta.json"
	if FileAccess.file_exists(meta_p):
		var m = JSON.parse_string(FileAccess.get_file_as_string(meta_p))
		if m is Dictionary and m.has("box"):
			_hw = float(m.box[0]) * 0.5
			_hl = float(m.box[2]) * 0.5
	if FileAccess.file_exists("res://world/panneaux.bin"):
		var b := FileAccess.get_file_as_bytes("res://world/panneaux.bin")
		var n := b.decode_u32(0)
		for i in n:
			var o := 4 + i * 16
			var p := Vector4(b.decode_float(o), b.decode_float(o + 4), b.decode_float(o + 8), b.decode_float(o + 12))
			var k := Vector2i(floori(p.x / GRILLE), floori(p.z / GRILLE))
			if not _panneaux.has(k):
				_panneaux[k] = []
			_panneaux[k].append(p)
	if OS.get_cmdline_user_args().has("--casse-test"):
		essai.call_deferred()
	if OS.get_cmdline_user_args().has("--casse-debug"):
		print("[casse] panneaux : ", _panneaux.size(), " cases ; boîte voiture ", _hw, " × ", _hl)

func _physics_process(dt: float) -> void:
	var t0 := Time.get_ticks_usec()
	_pas_corps(dt)
	PerfMon.note("casse", Time.get_ticks_usec() - t0)

func _pas_corps(dt: float) -> void:
	if car == null:
		return
	_vieillir(dt)
	var v := car.linear_velocity
	_t -= dt
	if _t <= 0.0:
		_t = 0.2
		_relever()
	if v.length() < 1.2 or _proches.is_empty():
		return
	var inv := car.global_transform.affine_inverse()
	for it in _proches:
		match it[0]:
			"objet":
				var spec: Array = OBJETS.get(String(it[3].nm), ["repousse", 0.2, 50.0, "metal", 0.0])
				var p: Vector3 = it[1]
				var cs: Array = it[3].cs
				if int(it[4]) < cs.size():                      # grands objets (banc de touche : 4 m) : point de leur boîte le plus proche
					p = _pres(cs[int(it[4])], car.global_position, p.y)
				if v.length() >= float(spec[4]) and _touche(inv, p, float(spec[1])) and not _deja(it[1], 0.5):
					_casser("objet", p, it)
					return
			"objet_seg":
				var spec: Array = OBJETS.get(String(it[4].nm), ["segment", 0.2, 50.0, "metal", 5.0])
				var a: Vector3 = it[1]; var b: Vector3 = it[2]
				var ab := Vector2(b.x - a.x, b.z - a.z)
				var nrm := Vector2(-ab.y, ab.x).normalized()
				if absf(Vector2(v.x, v.z).dot(nrm)) < float(spec[4]):
					continue                                  # on longe la glissière : elle tient (choc de face seulement)
				var c := car.global_position
				var tt := clampf(Vector2(c.x - a.x, c.z - a.z).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
				var q := a.lerp(b, tt)
				if _touche(inv, q, float(spec[1])) and not _deja(q, 1.5):
					_casser("objet_seg", q, it)
					return
			"cloture", "haie", "muret", "pilier", "grillage", "barriere":
				if v.length() < float(KINDS[it[0]][3]):
					continue
				var a: Vector3 = it[1]; var b: Vector3 = it[2]
				var c := car.global_position
				var ab := Vector2(b.x - a.x, b.z - a.z)
				var tt := clampf(Vector2(c.x - a.x, c.z - a.z).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
				var q := a.lerp(b, tt)
				if _touche(inv, q, KINDS[it[0]][2]) and not _deja(q, 2.2):
					_casser(it[0], q, it)
					return
			_:
				var p: Vector3 = it[1]
				if _touche(inv, p, KINDS[it[0]][2]) and not _deja(p, 0.5):
					_casser(it[0], p, it)
					return

func _touche(inv: Transform3D, p: Vector3, r: float) -> bool:
	var l := inv * p
	return absf(l.x) < _hw + r and absf(l.z) < _hl + r and l.y > -2.0 and l.y < 2.5

## Point de l'empreinte au sol d'une boîte de collision (BoxShape3D) le plus proche de c, à la hauteur y.
func _pres(cs: CollisionShape3D, c: Vector3, y: float) -> Vector3:
	var h: Vector3 = (cs.shape as BoxShape3D).size * 0.5
	var l := cs.transform.affine_inverse() * c
	var q := cs.transform * Vector3(clampf(l.x, -h.x, h.x), 0.0, clampf(l.z, -h.z, h.z))
	return Vector3(q.x, y, q.z)

func _deja(p: Vector3, r: float) -> bool:
	for q in _casses:
		if Vector2(q.x - p.x, q.z - p.z).length() < r:
			return true
	return false

## Candidats à moins de 30 m de la voiture.
func _relever() -> void:
	_proches.clear()
	var c := car.global_position
	var R := 30.0
	var R2 := R * R
	var kc := Vector2i(floori(c.x / GRILLE), floori(c.z / GRILLE))
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			for p: Vector4 in _panneaux.get(kc + Vector2i(dx, dz), []):
				if Vector2(p.x - c.x, p.z - c.z).length_squared() < R2:
					_proches.append(["panneau", Vector3(p.x, p.y, p.z), p.w])
	var tiles := []
	for dx in [-R, R]:
		for dz in [-R, R]:
			var k := Vector2i(floori((c.x + dx) / 256.0), floori((c.z + dz) / 256.0))
			if not tiles.has(k):
				tiles.append(k)
	for k in tiles:
		if poles and poles.pieds.has(k):
			for p: Vector3 in poles.pieds[k]:
				if Vector2(p.x - c.x, p.z - c.z).length_squared() < R2:
					_proches.append(["lampadaire", p])
		if poles and poles.poteaux.has(k):
			var PT: PackedVector3Array = poles.poteaux[k]
			var TT: PackedByteArray = poles.poteaux_t[k]
			for i in PT.size():
				if Vector2(PT[i].x - c.x, PT[i].z - c.z).length_squared() < R2:
					_proches.append(["poteau", PT[i], TT[i]])
		if fences and fences.lignes.has(k):
			var L: PackedVector3Array = fences.lignes[k]
			var G: PackedByteArray = fences.genres.get(k, PackedByteArray())
			var g: Dictionary = _grille_lignes(k)
			var vus := {}
			for gx in range(-2, 3):
				for gz in range(-2, 3):
					for i: int in g.get(kc + Vector2i(gx, gz), PackedInt32Array()):
						if vus.has(i):
							continue
						vus[i] = true
						_proches.append([LIGNES[G[i / 2]] if i / 2 < G.size() else "cloture", L[i], L[i + 1]])
		# grillage d'emprise de l'autoroute (#76 : on passait au travers) : travées de 4 m, autoroute.gd
		var au = main.get("autoroute") if main else null
		if au and au.grillages.has(k):
			var GA: PackedVector3Array = au.grillages[k]
			for i in range(0, GA.size() - 1, 2):
				if Vector2(GA[i].x - c.x, GA[i].z - c.z).length_squared() < R2:
					_proches.append(["grillage", GA[i], GA[i + 1]])
		# grillages des terrains de sport (#85) : travées avec collision, ouvertes par sport.breche
		var sp = main.get("sport") if main else null
		if sp and sp.grillages.has(k):
			var GS: PackedVector3Array = sp.grillages[k]
			for i in range(0, GS.size() - 1, 2):
				if Vector2(GS[i].x - c.x, GS[i].z - c.z).length_squared() < R2:
					_proches.append(["grillage", GS[i], GS[i + 1]])
		# bras des barrières de passage à niveau (#125) : segments pied -> bout, rails.gd
		var rl = main.get("rails") if main else null
		if rl and rl.barrieres.has(k):
			var GB: PackedVector3Array = rl.barrieres[k]
			for i in range(0, GB.size() - 1, 2):
				if GB[i].y > -900.0 and Vector2(GB[i].x - c.x, GB[i].z - c.z).length_squared() < R2:
					_proches.append(["barriere", GB[i], GB[i + 1]])
		# #123 : équipements de sport, bornes, balises, glissières et séparateurs de l'autoroute
		for sys in [sp, au]:
			if sys == null or not sys.get("objets") or not sys.objets.has(k):
				continue
			for o: Dictionary in sys.objets[k]:
				if o.has("a"):
					var oa: Vector3 = o.a; var ob: Vector3 = o.b
					if Vector2((oa.x + ob.x) * 0.5 - c.x, (oa.z + ob.z) * 0.5 - c.z).length_squared() < R2:
						_proches.append(["objet_seg", oa, ob, sys, o])
				else:
					for i in (o.pts as PackedVector3Array).size():
						var q: Vector3 = o.pts[i]
						if Vector2(q.x - c.x, q.z - c.z).length_squared() < R2:
							_proches.append(["objet", q, sys, o, i])           # i : boîte de collision de ce pied
		if vegetation and vegetation.data.has(k):
			var g: Dictionary = _grille_arbres(k)
			var a: PackedFloat32Array = vegetation.data[k]
			for gx in range(-2, 3):
				for gz in range(-2, 3):
					for i: int in g.get(kc + Vector2i(gx, gz), PackedInt32Array()):
						var o: int = i * 8
						var h: float = a[o + 3]
						if h <= 0.0 or h >= ARBRE_MAX:
							continue
						if Vector2(a[o] - c.x, a[o + 2] - c.z).length_squared() < R2:
							_proches.append(["arbre", Vector3(a[o], a[o + 1], a[o + 2]), k, i])

## Segments de clôtures cassables d'une tuile rangés par cases de 16 m (chaque case traversée par le segment).
var _lignes := {}
func _grille_lignes(k: Vector2i) -> Dictionary:
	var L: PackedVector3Array = fences.lignes[k]
	if _lignes.has(k) and _lignes[k][0] == L.size():
		return _lignes[k][1]
	for kk in _lignes.keys():
		if not fences.lignes.has(kk):
			_lignes.erase(kk)
	var g := {}
	for i in range(0, L.size() - 1, 2):
		var a := L[i]; var b := L[i + 1]
		var n := int(ceil(a.distance_to(b) / 6.0)) + 1
		for j in n + 1:
			var p := a.lerp(b, float(j) / n)
			var kk := Vector2i(floori(p.x / GRILLE), floori(p.z / GRILLE))
			if not g.has(kk):
				g[kk] = PackedInt32Array()
			var l: PackedInt32Array = g[kk]
			if l.is_empty() or l[-1] != i:
				l.append(i)
			g[kk] = l
	_lignes[k] = [L.size(), g]
	return g

## Arbres cassables d'une tuile rangés par cases de 16 m (fait une fois par tuile chargée).
func _grille_arbres(k: Vector2i) -> Dictionary:
	# seulement les arbres affichés (vegetation.visibles : densité réglable) ; refaite si le niveau change
	var nv: int = vegetation.visibles(k)
	if _arbres.has(k) and _arbres[k][0] == nv:
		return _arbres[k][1]
	for kk in _arbres.keys():
		if not vegetation.data.has(kk):
			_arbres.erase(kk)
	var g := {}
	var a: PackedFloat32Array = vegetation.data[k]
	for i in nv:
		var o: int = i * 8
		if a[o + 3] <= 0.0 or a[o + 3] >= ARBRE_MAX:
			continue
		var kk := Vector2i(floori(a[o] / GRILLE), floori(a[o + 2] / GRILLE))
		if not g.has(kk):
			g[kk] = PackedInt32Array()
		var l: PackedInt32Array = g[kk]
		l.append(i)
		g[kk] = l
	_arbres[k] = [nv, g]
	return g

# ---------------------------------------------------------------- casse
func _casser(genre: String, p: Vector3, it: Array) -> void:
	if main and main.get("carriere"):
		main.carriere.decor_casse()                   # carrière (#120) : décor cassé pendant une mission
	_casses.append(p)
	if _casses.size() > 200:
		_casses.pop_front()
	var v := car.linear_velocity
	var spd := v.length()
	var dir := v / maxf(spd, 0.01)
	var corps: Array = []                # débris (RigidBody3D) : un seul, ou plusieurs morceaux quand l'objet éclate
	var couche_obj := false              # objet de sport ou d'autoroute qui se couche (mât, panier)
	var matiere_obj := ""
	var seg := Vector3.RIGHT              # clôtures : direction de la ligne (morceaux répartis le long)
	if it.size() > 2 and it[2] is Vector3:
		seg = ((it[2] as Vector3) - (it[1] as Vector3)).normalized()
	match genre:
		"panneau":
			var h: float = it[2]
			_effacer(Vector4(p.x, p.z, 0.75, p.y + 0.5))
			var c := _corps_panneau(h)
			c.global_position = p + Vector3(0, h * 0.5 + 0.35, 0)
			corps.append(c)
		"lampadaire":
			var m: Mesh = poles.casser(p)
			var c := _corps_modele(m, 4.05, 0.16, 140.0)
			c.global_position = p + Vector3(0, 2.0, 0)
			corps.append(c)
		"poteau":
			var t: int = it[2]
			var h := 9.0 if t == 2 else 10.0
			var m: Mesh = poles.casser(p, t)
			poles.couper_fils(p)
			var c := _corps_modele(m, h, 0.15, 180.0 if t == 2 else 420.0)
			c.global_position = p + Vector3(0, h * 0.5, 0)
			corps.append(c)
		"arbre":
			var r: Array = vegetation.casser(it[2], it[3])
			if r.is_empty():
				return
			var h: float = r[1]
			var c := _corps_modele(r[0], h, clampf(h * 0.018, 0.08, 0.16), 40.0 + h * 25.0, h)
			c.global_position = p + Vector3(0, h * 0.5, 0)
			c.rotation.y = r[2]
			corps.append(c)
		"cloture":
			_effacer(Vector4(p.x, p.z, 1.7, p.y - 0.3))
			fences.breche(p, 1.9)
			for i in 2:                                       # deux demi-panneaux arrachés
				var c := _corps_cloture(0.5)
				c.global_position = p + seg * (i - 0.5) * 0.95 + Vector3(0, 0.7, 0)
				c.rotation.y = atan2(seg.x, seg.z) - PI * 0.5
				corps.append(c)
		"grillage":
			_effacer(Vector4(p.x, p.z, 2.4, p.y - 0.3))
			var sp = main.get("sport") if main else null
			if sp:
				sp.breche(p, 2.2)
			for i in 2:
				var c := _corps_cloture(0.5)
				c.global_position = p + seg * (i - 0.5) * 1.0 + Vector3(0, 0.9, 0)
				c.rotation.y = atan2(seg.x, seg.z) - PI * 0.5
				corps.append(c)
		"barriere":
			var rl = main.get("rails") if main else null
			var r: Array = rl.casser(p) if rl else []
			if r.is_empty():
				return
			var c := _prendre(12.0, Vector3(float(r[1]), 0.1, 0.1))
			(c.get_child(0) as MeshInstance3D).mesh = r[0]
			c.global_transform = r[2]
			corps.append(c)
		"haie":
			_effacer(Vector4(p.x, p.z, 2.1, p.y - 0.3))
			fences.breche(p, 2.3)
			for i in 2:                                       # touffes arrachées
				var c := _corps_bloc("buisson", Vector3(1.0, 0.9, 0.8), 18.0)
				c.global_position = p + seg * (i - 0.5) * 1.1 + Vector3(0, 0.9, 0)
				corps.append(c)
		"pilier":
			_effacer(Vector4(p.x, p.z, 0.8, p.y - 0.5))
			fences.breche(p, 1.0)
			for i in 2:
				var c := _corps_bloc("bloc", Vector3(0.4, 0.45, 0.4), 80.0)
				c.global_position = p + Vector3(0, 0.5 + i * 0.5, 0)
				corps.append(c)
		"objet", "objet_seg":
			var sys = it[2] if genre == "objet" else it[3]
			var o: Dictionary = it[3] if genre == "objet" else it[4]
			var spec: Array = OBJETS.get(String(o.nm), ["repousse", 0.2, 50.0, "metal", 0.0])
			var m: Mesh = sys.casser_objet(o)
			for q: Vector3 in o.get("pts", PackedVector3Array()):
				_casses.append(q)                            # les autres pieds du même objet : pas deux fois
			if String(o.nm) == "gba":
				for i in 3:                                       # le séparateur en béton éclate en blocs
					var c := _corps_bloc("bloc", Vector3(0.9, 0.45, 0.35), 200.0)
					c.global_position = p + seg * (i - 1) * 1.2 + Vector3(0, 0.5 + (i % 2) * 0.3, 0)
					corps.append(c)
			elif m:
				corps.append(_corps_objet(m, o.xf, float(spec[2])))
			couche_obj = String(spec[0]) == "couche"
			matiere_obj = String(spec[3])
		"muret":
			_effacer(Vector4(p.x, p.z, 1.9, p.y - 0.3))
			fences.breche(p, 2.1)
			for i in 3:                                       # le muret éclate en blocs de pierre
				var c := _corps_bloc("bloc", Vector3(0.9, 0.45, 0.35), 90.0)
				c.global_position = p + seg * (i - 1) * 0.65 + Vector3(0, 0.4 + (i % 2) * 0.3, 0)
				c.rotation.y = atan2(seg.x, seg.z) + randf_range(-0.6, 0.6)
				corps.append(c)
	# #105 : la voiture ne bronche pas (plus aucune perte de vitesse, KINDS[…][0] n'est plus utilisé)
	for c: RigidBody3D in corps:
		car.add_collision_exception_with(c)
		if genre in COUCHES or couche_obj:
			# #123 : bascule autour du pied dans le sens du choc et se couche (centre de masse bas : le pied glisse peu)
			var h: float = ((c.get_child(3) as CollisionShape3D).shape as BoxShape3D).size.y
			c.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
			c.center_of_mass = Vector3(0, -h * 0.3, 0)
			c.linear_velocity = dir * minf(spd, 14.0) * randf_range(0.15, 0.3) + Vector3(0, 0.4, 0)
			c.angular_velocity = Vector3.UP.cross(dir).normalized() * randf_range(1.0, 1.8) * clampf(spd / 8.0, 0.6, 1.4)
		elif genre == "objet" or (genre == "objet_seg" and matiere_obj == "metal"):
			# #123 : repoussé (but, banc, borne, glissière…) : glisse et roule dans le sens du choc, sans s'envoler
			c.linear_velocity = dir * spd * randf_range(0.45, 0.65) + Vector3(0, randf_range(0.6, 1.4), 0)
			c.angular_velocity = Vector3(randf_range(-1.5, 1.5), randf_range(-1.0, 1.0), randf_range(-1.5, 1.5))
		else:
			# éclats : chaque morceau part dans le sens du choc, écarté des autres
			c.linear_velocity = dir * spd * randf_range(0.5, 1.0) + Vector3(randf_range(-2.0, 2.0), randf_range(1.5, 4.5), randf_range(-2.0, 2.0))
			c.angular_velocity = dir.cross(Vector3.UP) * -randf_range(2.0, 5.0) + Vector3(randf_range(-2, 2), randf_range(-2, 2), randf_range(-2, 2))
		_debris.append([c, 0.0, 0.0])
	while _debris.size() > MAX_DEBRIS:
		_rendre(_debris.pop_front()[0])
	if main and main.get("sound") and main.sound.has_method("impact"):
		main.sound.impact(matiere_obj if matiere_obj != "" else MATIERE.get(genre, "dur"), maxf(spd, 3.0), p + Vector3(0, 1, 0), true)
	if main and main.get("dust"):
		var D = main.dust
		var mat: Dictionary = D.MATIERES.get("poussiere", {})
		for i in (9 if not genre in COUCHES else 5):             # #123 : nuage plus gros quand l'objet éclate
			if not mat.is_empty():
				D._nuage(mat, p + Vector3(randf_range(-0.6, 0.6), randf_range(0.2, 1.0), randf_range(-0.6, 0.6)), dir * spd * 0.2 + Vector3(0, 0.5, 0), 0.8)
		var col := Color(0.35, 0.27, 0.18) if genre in ["arbre", "cloture", "poteau"] else Color(0.55, 0.56, 0.58)
		if genre == "haie":
			col = Color(0.2, 0.36, 0.14)
		elif genre == "barriere":
			col = Color(0.85, 0.1, 0.08)
		elif genre == "muret" or genre == "pilier":
			col = Color(0.62, 0.58, 0.5)
		for i in (24 if genre == "haie" or genre == "muret" or genre == "pilier" else (14 if genre in ["cloture", "grillage"] else 8)):
			D._debris(p + Vector3(randf_range(-0.4, 0.4), randf_range(0.3, 1.5), randf_range(-0.4, 0.4)),
				dir * spd * randf_range(0.3, 0.8) + Vector3(randf_range(-2, 2), randf_range(2, 5), randf_range(-2, 2)),
				p.y, Vector3(randf_range(0.04, 0.15), randf_range(0.02, 0.06), randf_range(0.04, 0.2)), col)
	if OS.get_cmdline_user_args().has("--casse-debug"):
		print("[casse] ", genre, " renversé en ", p, " à ", int(spd * 3.6), " km/h")

## Efface (shader) l'objet autour d'un point : x, z, rayon, hauteur au-dessus de laquelle tout disparaît.
func _effacer(c: Vector4) -> void:
	_pts.append(c)
	if _pts.size() > 16:
		# #123 : les débris restent ; on rend d'abord l'objet effacé le plus loin de la voiture (plus le plus ancien)
		var loin := 0
		var dl := -1.0
		for i in _pts.size() - 1:
			var d := Vector2(_pts[i].x - car.global_position.x, _pts[i].y - car.global_position.z).length() if car else 0.0
			if d > dl:
				dl = d; loin = i
		_pts.remove_at(loin)
	var arr := []
	for q in _pts:
		arr.append(q)
	while arr.size() < 16:
		arr.append(Vector4.ZERO)
	Env.set_value("casse_pts", arr)
	Env.set_value("casse_n", _pts.size())

# ---------------------------------------------------------------- réserve de débris (v6.19 : pas d'instanciation en jeu)
## Réserve préparée au démarrage : MAX_DEBRIS corps rigides, chacun avec 3 emplacements de maillage et une boîte de
## collision (BoxShape3D seulement) ; un débris est pris dans la réserve, habillé (maillages et boîte selon l'objet
## renversé), puis rendu (caché, figé, sans collision) à la fin de sa vie ou quand la réserve est pleine. Plus aucun
## new()/queue_free() pendant la conduite. Les maillages des panneaux et clôtures sont créés une seule fois.
var _reserve: Array = []           # RigidBody3D libres
var _mats := {}
var _mailles := {}

func _preparer_reserve() -> void:
	var m_metal := StandardMaterial3D.new(); m_metal.albedo_color = Color(0.62, 0.63, 0.65); m_metal.metallic = 0.8; m_metal.roughness = 0.35
	var m_rouge := StandardMaterial3D.new(); m_rouge.albedo_color = Color(0.85, 0.1, 0.1); m_rouge.roughness = 0.45
	var m_blanc := StandardMaterial3D.new(); m_blanc.albedo_color = Color(0.95, 0.95, 0.95); m_blanc.roughness = 0.45
	var m_grille := StandardMaterial3D.new(); m_grille.albedo_color = Color(0.22, 0.27, 0.22); m_grille.roughness = 0.6; m_grille.metallic = 0.4
	var face := CylinderMesh.new(); face.top_radius = 0.36; face.bottom_radius = 0.36; face.height = 0.03; face.radial_segments = 16; face.material = m_rouge
	var inner := CylinderMesh.new(); inner.top_radius = 0.27; inner.bottom_radius = 0.27; inner.height = 0.035; inner.radial_segments = 16; inner.material = m_blanc
	var poteau := BoxMesh.new(); poteau.size = Vector3(0.06, 1.4, 0.06); poteau.material = m_grille
	var grille := BoxMesh.new(); grille.size = Vector3(1.8, 1.1, 0.02); grille.material = m_grille
	var m_feuil := StandardMaterial3D.new(); m_feuil.albedo_color = Color(0.17, 0.32, 0.12); m_feuil.roughness = 0.9
	var m_pierre := StandardMaterial3D.new(); m_pierre.albedo_color = Color(0.6, 0.56, 0.48); m_pierre.roughness = 0.95
	var buisson := SphereMesh.new(); buisson.radius = 0.6; buisson.height = 1.0; buisson.radial_segments = 8; buisson.rings = 4; buisson.material = m_feuil
	var bloc := BoxMesh.new(); bloc.size = Vector3(0.9, 0.45, 0.35); bloc.material = m_pierre
	_mats["metal"] = m_metal
	_mailles = {"face": face, "inner": inner, "poteau": poteau, "grille": grille, "buisson": buisson, "bloc": bloc, "mats": {}}
	for i in MAX_DEBRIS:
		var rb := RigidBody3D.new()
		rb.collision_layer = 1
		rb.collision_mask = 1
		rb.continuous_cd = true
		for k in 3:
			rb.add_child(MeshInstance3D.new())
		var cs := CollisionShape3D.new()
		cs.shape = BoxShape3D.new()
		rb.add_child(cs)
		add_child(rb)
		_rendre(rb)

func _rendre(rb: RigidBody3D) -> void:
	rb.freeze = true
	rb.visible = false
	(rb.get_child(3) as CollisionShape3D).disabled = true
	rb.global_position = Vector3(0, -1000, 0)
	if car and is_instance_valid(car):
		car.remove_collision_exception_with(rb)
	if not _reserve.has(rb):
		_reserve.append(rb)

func _prendre(masse: float, boite: Vector3) -> RigidBody3D:
	if _reserve.is_empty():
		var d: Array = _debris.pop_front()            # réserve vide : on reprend le plus vieux débris
		_rendre(d[0])
	var rb: RigidBody3D = _reserve.pop_back()
	rb.mass = masse
	for k in 3:
		var mi: MeshInstance3D = rb.get_child(k)
		mi.mesh = null; mi.transform = Transform3D.IDENTITY; mi.set_meta("e", 1.0)
	var cs: CollisionShape3D = rb.get_child(3)
	(cs.shape as BoxShape3D).size = boite
	cs.disabled = false
	rb.rotation = Vector3.ZERO
	rb.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_AUTO
	rb.linear_velocity = Vector3.ZERO
	rb.angular_velocity = Vector3.ZERO
	rb.visible = true
	rb.freeze = false
	return rb

func _corps_modele(m: Mesh, h: float, r: float, masse: float, echelle := 1.0) -> RigidBody3D:
	var rb := _prendre(masse, Vector3(maxf(r, 0.1) * 2.0, h, maxf(r, 0.1) * 2.0))
	var mi: MeshInstance3D = rb.get_child(0)
	mi.mesh = m
	mi.scale = Vector3.ONE * echelle
	mi.set_meta("e", echelle)
	mi.position = Vector3(0, -h * 0.5, 0)
	return rb

func _corps_panneau(h: float) -> RigidBody3D:
	var rb := _prendre(25.0, Vector3(0.7, h, 0.12))
	var cle := "mat%d" % int(h * 10)
	if not _mailles.mats.has(cle):
		var cm := CylinderMesh.new(); cm.top_radius = 0.035; cm.bottom_radius = 0.035; cm.height = h; cm.radial_segments = 8
		cm.material = _mats.metal
		_mailles.mats[cle] = cm
	(rb.get_child(0) as MeshInstance3D).mesh = _mailles.mats[cle]
	var face: MeshInstance3D = rb.get_child(1)
	face.mesh = _mailles.face
	face.rotation = Vector3(PI * 0.5, 0, 0)
	face.position = Vector3(0, h * 0.5 - 0.35, 0.05)
	var inner: MeshInstance3D = rb.get_child(2)
	inner.mesh = _mailles.inner
	inner.rotation = face.rotation
	inner.position = face.position + Vector3(0, 0, 0.002)
	return rb

## #123 : débris au modèle d'un objet posé par lots (équipement de sport, borne, glissière…) : boîte de collision à sa
## taille (boîte englobante du modèle, à l'échelle de l'exemplaire), posé exactement à la place de l'exemplaire caché.
func _corps_objet(m: Mesh, xf: Transform3D, masse: float) -> RigidBody3D:
	var ab := m.get_aabb()
	var S := Vector3(xf.basis.x.length(), xf.basis.y.length(), xf.basis.z.length())
	var c := ab.get_center()
	var rb := _prendre(masse, (ab.size * S).max(Vector3(0.1, 0.1, 0.1)))
	var mi: MeshInstance3D = rb.get_child(0)
	mi.mesh = m
	mi.transform = Transform3D(Basis.from_scale(S), -c * S)
	mi.set_meta("e", 1.0)
	# posé un peu au-dessus de sa place : sur un talus, la boîte enfoncée dans le relief était éjectée vers l'aval
	var lev := maxf(0.12, 0.15 * maxf(ab.size.x * S.x, ab.size.z * S.z))
	rb.global_transform = Transform3D(xf.basis.orthonormalized(), xf * c + Vector3(0, lev, 0))
	return rb

## Panneau de clôture arraché ; part < 1 : morceau (#123 : la clôture éclate en deux).
func _corps_cloture(part := 1.0) -> RigidBody3D:
	var rb := _prendre(30.0 * part, Vector3(1.9 * part, 1.3, 0.1))
	for i in 3:
		var mi: MeshInstance3D = rb.get_child(i)
		mi.mesh = _mailles.poteau if i < 2 else _mailles.grille
		mi.position = Vector3((-0.9 + i * 1.8) * part, 0, 0) if i < 2 else Vector3.ZERO
		mi.scale = Vector3(part, 1, 1) if i == 2 else Vector3.ONE
		mi.set_meta("e", 1.0)
	return rb

## Haie (touffe arrachée, trois boules) ou muret (trois blocs de pierre).
func _corps_bloc(nom: String, boite: Vector3, masse: float) -> RigidBody3D:
	var rb := _prendre(masse, boite)
	for i in 3:
		var mi: MeshInstance3D = rb.get_child(i)
		mi.mesh = _mailles[nom]
		if nom == "bloc":
			mi.position = Vector3((i - 1) * 0.3, (i % 2) * 0.12 - 0.06, (i - 1) * 0.08)
			mi.rotation = Vector3(0, (i - 1) * 0.5, (i - 1) * 0.3)
			mi.scale = Vector3.ONE * (0.55 if i != 1 else 0.8)
		else:
			mi.position = Vector3((i - 1) * 0.35, (i % 2) * 0.15, 0)
			mi.scale = Vector3.ONE * (0.75 if i != 1 else 1.0)
		mi.set_meta("e", mi.scale.x)
	return rb

## Débris (#123) : restent au sol ; figés une fois immobiles depuis POSE s (plus de calcul physique, la voiture
## les traverse toujours) ; rendus à la réserve quand la voiture est à plus de LOIN m (la tuile remet l'objet en
## place quand on revient) ou quand la réserve est vide (le plus ancien).
func _vieillir(dt: float) -> void:
	for i in range(_debris.size() - 1, -1, -1):
		var d: Array = _debris[i]
		var rb: RigidBody3D = d[0]
		if not is_instance_valid(rb):
			_debris.remove_at(i)
			continue
		d[1] += dt
		if not rb.freeze:
			if d[1] > 1.0 and rb.linear_velocity.length() < 0.2 and rb.angular_velocity.length() < 0.3:
				d[2] += dt
				if d[2] > POSE:
					rb.freeze = true
			else:
				d[2] = 0.0
		if rb.global_position.y < -500.0 or (car and rb.global_position.distance_to(car.global_position) > LOIN):
			_rendre(rb)
			_debris.remove_at(i)

# ---------------------------------------------------------------- essai : -- --casse-test
## Lance la voiture (vitesse imposée, 45 km/h) sur l'objet le plus proche de chaque genre et enregistre des captures
## dans user://shots/casse_<genre>_<n>.png ; le journal dit ce qui a été renversé.
func essai() -> void:
	while not preload("res://scripts/chargement.gd").fini:
		await get_tree().process_frame
	for i in 120:
		await get_tree().physics_frame
	DirAccess.make_dir_recursive_absolute("user://shots")
	var genres := ["panneau", "lampadaire", "poteau", "arbre", "cloture", "haie", "muret"]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--casse-genres="):
			genres = Array(a.trim_prefix("--casse-genres=").split(","))
	for genre in genres:
		var perp := Vector3.ZERO                   # clôtures : arrivée perpendiculaire au segment (sinon on longe la ligne)
		var c := car.global_position
		var best := Vector3.INF
		var bd := INF
		var boite: CollisionShape3D = null
		match genre:
			"panneau":
				for k in _panneaux:
					for p: Vector4 in _panneaux[k]:
						var d := Vector2(p.x - c.x, p.z - c.z).length()
						if d < bd and d > 3.0:
							bd = d; best = Vector3(p.x, p.y + 0.35, p.z)
			"lampadaire":
				for k in poles.pieds:
					for p: Vector3 in poles.pieds[k]:
						var d := Vector2(p.x - c.x, p.z - c.z).length()
						if d < bd and d > 3.0:
							bd = d; best = p
			"poteau":
				for k in poles.poteaux:
					for p: Vector3 in poles.poteaux[k]:
						var d := Vector2(p.x - c.x, p.z - c.z).length()
						if d < bd and d > 3.0:
							bd = d; best = p
			"arbre":
				for k in vegetation.data:
					var a: PackedFloat32Array = vegetation.data[k]
					for i in vegetation.visibles(k):
						var o: int = i * 8
						if a[o + 3] > 3.0 and a[o + 3] < ARBRE_MAX:
							var d := Vector2(a[o] - c.x, a[o + 2] - c.z).length()
							if d < bd and d > 3.0:
								bd = d; best = Vector3(a[o], a[o + 1], a[o + 2])
			"grillage_sport":                       # #85 : grillages des terrains de sport
				var sp = main.get("sport")
				if sp:
					for k in sp.grillages:
						var GS: PackedVector3Array = sp.grillages[k]
						for i in range(0, GS.size() - 1, 2):
							var m := (GS[i] + GS[i + 1]) * 0.5
							var d := Vector2(m.x - c.x, m.z - c.z).length()
							if d < bd and d > 3.0:
								bd = d; best = m
			"cloture", "haie", "muret", "pilier":
				for k in fences.lignes:
					var L: PackedVector3Array = fences.lignes[k]
					var G: PackedByteArray = fences.genres.get(k, PackedByteArray())
					for i in range(0, L.size() - 1, 2):
						if i / 2 >= G.size() or LIGNES[G[i / 2]] != genre:
							continue
						var m := (L[i] + L[i + 1]) * 0.5
						var d := Vector2(m.x - c.x, m.z - c.z).length()
						if d < bd and d > 3.0 and L[i].distance_to(L[i + 1]) > (3.0 if genre == "cloture" else (0.3 if genre == "pilier" else 1.5)):
							bd = d; best = m; perp = (L[i + 1] - L[i]).cross(Vector3.UP).normalized()
		if genre.begins_with("objet:"):                 # #123 : objet de sport ou d'autoroute du modèle donné
			var nom: String = String(genre).trim_prefix("objet:")
			for sys in [main.get("sport"), main.get("autoroute")]:
				if sys == null:
					continue
				for k in sys.objets:
					for o: Dictionary in sys.objets[k]:
						if String(o.nm) != nom:
							continue
						var q: Vector3 = ((o.a as Vector3) + (o.b as Vector3)) * 0.5 if o.has("a") else (o.pts as PackedVector3Array)[0]
						var d := Vector2(q.x - c.x, q.z - c.z).length()
						if d < bd and d > 3.0:
							bd = d; best = q
							perp = ((o.b as Vector3) - (o.a as Vector3)).cross(Vector3.UP).normalized() if o.has("a") else Vector3.ZERO
							boite = o.cs[0] if not o.has("a") and not (o.cs as Array).is_empty() else null
		if best == Vector3.INF:
			print("[casse] essai ", genre, " : aucun objet chargé")
			continue
		# élan court (hors de la boîte des grands objets : banc de touche, 4 m) ; objets sans sens imposé : de celui des
		# quatre côtés où le sol est le plus à niveau (les terrains de sport sont bordés de talus)
		var R := preload("res://scripts/relief.gd")
		var f := perp
		var start := Vector3.INF
		var ecart := INF
		for g: Vector3 in ([perp] if perp != Vector3.ZERO else [Vector3.RIGHT, Vector3.LEFT, Vector3.BACK, Vector3.FORWARD]):
			var ext := 0.0
			if boite:
				var hb: Vector3 = (boite.shape as BoxShape3D).size * 0.5
				var bb := boite.global_basis.orthonormalized()
				ext = absf(g.dot(bb.x)) * hb.x + absf(g.dot(bb.z)) * hb.z
			var st := best - g * (_hl + 1.0 + ext)
			var hs: float = R.hauteur(st)
			var e := absf(hs - best.y) if is_finite(hs) else 0.0
			if e < ecart - 0.05:
				ecart = e; f = g; start = st
				start.y = (maxf(hs, best.y) if is_finite(hs) else best.y) + 0.8
		car.place(start, 180.0 - rad_to_deg(atan2(f.x, f.z)))
		car.hold(0.3)
		for i in 40:
			await get_tree().physics_frame
		var n0 := _casses.size()
		var vit := 12.5
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--casse-vitesse="):
				vit = float(a.trim_prefix("--casse-vitesse="))
		# #105 : élan imposé jusqu'à la casse, puis roue libre ; vitesse juste avant et 0,25 s après le choc
		var v_avant := -1.0
		for i in 90:
			if _casses.size() == n0:
				car.linear_velocity = f * vit + Vector3(0, car.linear_velocity.y, 0)
			elif v_avant < 0.0:
				v_avant = vit * 3.6
				for j in 30:
					if OS.get_cmdline_user_args().has("--casse-debug") and j % 5 == 0:
						print("[casse]    +%d : %.0f km/h, touche %s" % [j, car.kmh(), car._touching()])
					await get_tree().physics_frame
				print("[casse] %s : %.0f km/h au choc, %.0f km/h 0,25 s après" % [genre, v_avant, car.kmh()])
			await get_tree().physics_frame
		var img_ok := DisplayServer.get_name() != "headless"
		if img_ok:
			get_viewport().get_texture().get_image().save_png("user://shots/casse_%s_1.png" % genre)
		var deb := ""
		if not _debris.is_empty() and is_instance_valid(_debris[-1][0]):
			deb = " ; débris en %s, %.1f m/s" % [_debris[-1][0].global_position, _debris[-1][0].linear_velocity.length()]
		print("[casse] essai ", genre, " en ", best, " : ", "renversé" if _casses.size() > n0 else "PAS renversé", ", voiture à ", int(car.kmh()), " km/h", deb)
		for i in 120:
			await get_tree().physics_frame
		if img_ok:
			get_viewport().get_texture().get_image().save_png("user://shots/casse_%s_2.png" % genre)
		if not _debris.is_empty() and is_instance_valid(_debris[-1][0]):
			var rb: RigidBody3D = _debris[-1][0]
			var n_morceaux := 0
			for d in _debris:
				if d[1] < 3.0:
					n_morceaux += 1
			print("[casse]    2 s plus tard : %d morceau(x), dernier en %s, posé %s, incliné de %.0f° (couché si > 60°)" % [
				n_morceaux, rb.global_position.snapped(Vector3.ONE * 0.1), rb.freeze or rb.linear_velocity.length() < 0.5,
				rad_to_deg(acos(clampf(rb.global_basis.y.normalized().dot(Vector3.UP), -1.0, 1.0)))])
			if img_ok and main and main.get("cam_rig"):
				# vue sur les morceaux (preuve) : caméra posée de côté, au-dessus du point de casse
				var rig = main.cam_rig
				rig.set_process(false)
				var cm: Camera3D = rig.cam
				var cote := f.cross(Vector3.UP).normalized()
				cm.global_position = best + cote * 7.0 - f * 3.0 + Vector3(0, 4.5, 0)
				cm.look_at(best + f * 2.0 + Vector3(0, 0.5, 0), Vector3.UP)
				for i in 4:
					await get_tree().process_frame
				get_viewport().get_texture().get_image().save_png("user://shots/casse_%s_3.png" % genre)
				rig.set_process(true)
	# #123 : les débris restent (avant : effacés au bout de 15 s) ; 20 s de jeu plus tard, voiture arrêtée à côté
	car.linear_velocity = Vector3.ZERO
	car.hold(30.0)
	Engine.time_scale = 4.0
	var t0 := Time.get_ticks_msec()
	var tt := 0.0
	while tt < 20.0:
		await get_tree().physics_frame
		tt += 1.0 / Engine.physics_ticks_per_second * Engine.time_scale
	Engine.time_scale = 1.0
	var vis := 0
	var fig := 0
	for d in _debris:
		if is_instance_valid(d[0]) and (d[0] as RigidBody3D).visible:
			vis += 1
			fig += 1 if (d[0] as RigidBody3D).freeze else 0
	print("[casse] 20 s plus tard : %d débris toujours au sol, dont %d figés (%.0f s réelles)" % [vis, fig, (Time.get_ticks_msec() - t0) / 1000.0])
	get_tree().quit()
