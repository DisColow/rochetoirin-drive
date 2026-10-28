## Circulation (#132) : voitures qui roulent toutes seules sur le réseau de world/trafic.bin (pipeline/build_trafic.py :
## voies carrossables d'OSM d'un carrefour à l'autre, altitude de la chaussée, vitesse autorisée, sens uniques, voies).
## - Modèles des voitures garées (assets/props/car1, car3) sans habitacle, une couleur par voiture ; roues à part, qui
##   tournent ; feux stop au freinage, phares et veilleuses le soir et la nuit (circulation.gdshader). Une MultiMesh d'un
##   exemplaire par voiture (niveau de détail propre à chacune) et une MultiMesh pour toutes les roues d'un modèle.
## - Conduite (modèle IDM, « Intelligent Driver Model ») : voie de droite (la plus à droite des grands axes, parfois
##   une autre), vitesse autorisée × `perso` (0,85 à 1,02), ralentit avant les virages (A_LAT) ; garde ses distances
##   avec ce qui la précède dans sa voie : autres voitures, joueur (en voiture ou à pied), concurrents, épaves ; klaxonne
##   quand le joueur la bloque ; un seul véhicule à la fois dans un carrefour (réservation du nœud) ; raccord lissé d'une
##   voie à l'autre (décalage qui s'estompe sur RACCORD m). v6.87 (#134) : feux tricolores respectés (phase de chaque
##   arrivée dans trafic.bin, même calcul que signal_light.gdshader, horloge Env.temps_feux()) ; obstacle immobile
##   (épave, joueur arrêté) dépassé après ATTENTE s : autre file d'un sens unique, ou voie d'en face si elle est libre
##   (écart `dep` progressif le long de la voie, donc la voiture braque), clignotant à gauche puis à droite. v6.89 : véhicule
##   lent (joueur, autre voiture) doublé sur route rapide (_doubler) ; chaque voiture tient sa voie à sa façon (derive).
##   Course contre des concurrents : leur tracé est dégagé et barré (_route_course, _sur_trace).
## - Autour du joueur : NOMBRE voitures selon le niveau de performances × réglage ⚙ > Conduite > Circulation ;
##   apparition hors de vue (ou au loin, dans le fondu), disparition au-delà de R_LOIN ; tout est replacé après une
##   téléportation (vider()).
## - Choc : un corps cinématique (AnimatableBody3D) suit chaque voiture ; juste avant qu'une voiture pilotée (joueur,
##   concurrent) la percute, elle devient un corps rigide (comme les voitures garées : meta « matiere » = metal, donc
##   KA-BOOM possible) qu'on pousse ou retourne : une épave, rendue au bout de EPAVE s loin ou hors de vue.
## v6.88 (#135) : s'arrêtent devant les passants qui traversent aux passages piétons (pietons.gd).
## Essai : -- --drive-test --circulation-test [--circulation-debug].
extends Node3D

const PerfMon := preload("res://scripts/perf_monitor.gd")
const Env := preload("res://scripts/env.gd")
const MODELES := ["car1", "car3"]
const BOITES := [Vector3(1.66, 1.48, 3.75), Vector3(1.76, 1.45, 4.45)]     # comme props.gd (largeur, hauteur, longueur)
const MASSES := [1100.0, 1400.0]
const SANS := ["InteriorPanel", "InteriorPanel_0"]                         # habitacle, invisible derrière les vitres
const ROUES := ["rubber", "material"]
const COULEURS := [Color(0.92, 0.92, 0.9), Color(0.92, 0.92, 0.9), Color(0.62, 0.64, 0.66), Color(0.62, 0.64, 0.66),
	Color(0.05, 0.05, 0.06), Color(0.05, 0.05, 0.06), Color(0.3, 0.32, 0.34), Color(0.08, 0.14, 0.32), Color(0.55, 0.05, 0.05),
	Color(0.12, 0.25, 0.16), Color(0.66, 0.6, 0.48), Color(0.75, 0.42, 0.08), Color(0.2, 0.42, 0.7)]
const NOMBRE := [4, 8, 14, 20]                 # par niveau de performances (Économie, Équilibré, Élevée, Maximale)
const DENSITES := [0.0, 0.5, 1.0, 1.6]         # ⚙ > Conduite > Circulation : aucune, peu, normale, dense
const NOMS_DENSITES := ["Aucune", "Peu", "Normale", "Dense"]
const R_LOIN := 380.0
const R_MAX := 320.0                           # apparition au plus à cette distance
const R_CACHE := 50.0                          # apparition hors de vue au moins à cette distance
const R_VU := 270.0                            # apparition dans le champ seulement au-delà (fondu de FONDU)
const FONDU := 300.0
const CASE := 128.0
const RACCORD := 9.0
const A_LAT := 2.4                             # accélération latérale en virage (m/s²)
const IDM_A := 1.6                             # accélération (m/s²)
const IDM_B := 2.6                             # freinage confortable
const IDM_S0 := 2.6                            # écart à l'arrêt (m, pare-chocs à pare-chocs)
const IDM_T := 1.2                             # temps de suivi (s)
const LARGEUR_VOIE := 3.5
const EPAVE := 40.0
const RAYON_ROUE := 0.3
const CLASSE_POIDS := [1.0, 0.6, 1.0, 0.7, 0.9, 0.6, 0.75, 0.6, 0.45, 0.35, 0.15]   # chance d'apparaître (CLASSES)
const ARRET_FEU := 5.0                         # arrêt à cette distance du nœud d'un feu (m)
const ATTENTE := 3.0                           # s derrière un obstacle immobile avant de le dépasser
const DEGAGE := 85.0                           # voie d'en face libre sur cette longueur pour dépasser (m)
const COURSE_MARGE := 30.0                     # course contre des concurrents : tracé dégagé sur cette largeur (m)
const COURSE_CASE := 16.0
const BARRAGE := 12.0                          # course : arrêt à cette distance du carrefour d'une rue du tracé (m)
const LENT := 4.0                              # s derrière un véhicule lent (route rapide) avant de le doubler
const V_RAPIDE := 19.0                         # doubler un véhicule lent : routes limitées à ~70 km/h et plus (m/s)
const PLUIE_V := 0.85                          # sous la pluie (main.pluie, v6.91) : vitesse visée ×, temps de suivi ×
const PLUIE_T := 1.5

var target: Node3D
var main: Node
var ok := false
var niveau := 1
var densite := 2
var voitures: Array = []
var epaves: Array = []
var accidents := 0                             # voitures devenues épaves (essais)
var _pluie := 0.0

# réseau
var _nx := PackedFloat32Array()
var _nz := PackedFloat32Array()
var _deg := PackedInt32Array()                 # arcs touchant chaque nœud
var _a := PackedInt32Array()
var _b := PackedInt32Array()
var _p0 := PackedInt32Array()
var _np := PackedInt32Array()
var _fl := PackedInt32Array()
var _v := PackedFloat32Array()
var _dl := PackedFloat32Array()
var _feu_b := PackedInt32Array()               # feu à l'arrivée en b dans le sens de l'arc (phase × 2 + axe, -1 : aucun)
var _feu_a := PackedInt32Array()               # feu à l'arrivée en a à contresens
var _P := PackedFloat32Array()                 # x, y, z
var _sort_debut := PackedInt32Array()          # voies sortant de chaque nœud (CSR) : (arc << 1) | sens
var _sort := PackedInt32Array()
var _grille := {}                              # case -> PackedInt32Array d'arcs
var _cums := {}                                # arc -> longueurs cumulées le long de l'axe
var _resa := {}                                # nœud -> [voiture, heure de la réservation]

# rendu
var _corps: Array = []                         # par modèle : Mesh de la caisse
var _roue: Array = []                          # par modèle : Mesh d'une roue (centrée sur son axe)
var _pos_roues: Array = []                     # par modèle : 4 centres de roue (avant gauche, avant droite, arrière gauche, arrière droite)
var _mm_roues: Array = []                      # par modèle : MultiMeshInstance3D de toutes les roues
var _mat: ShaderMaterial
var _id := 0
var _remplir := true
var _course_cases := {}                        # cases de COURSE_CASE m le long du tracé de la course en cours
var _course_id := 0                            # concurrent dont le tracé a servi
var _trace := {}                               # cases de 8 m -> [point, direction] du tracé (voies qui le suivent)
var _t := 0.0
var _son_klaxon: AudioStream
var _moteurs: Array = []                       # AudioStreamPlayer3D des voitures les plus proches
var _debug := false

func _ready() -> void:
	_debug = OS.get_cmdline_user_args().has("--circulation-debug")
	ok = _charger()
	if not ok:
		return
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://scripts/circulation.gdshader")
	Env.add(_mat)
	Env.phares_sur(_mat)
	Env.fade(_mat, FONDU)
	for k in MODELES.size():
		_preparer_modele(k)
	if ResourceLoader.exists("res://assets/sfx/klaxon.ogg"):
		_son_klaxon = load("res://assets/sfx/klaxon.ogg")
	for k in 2:
		var ap := AudioStreamPlayer3D.new()
		ap.stream = load("res://assets/sfx/moteur_moyen_charge.ogg")
		ap.bus = "Monde" if AudioServer.get_bus_index("Monde") >= 0 else "Master"
		ap.unit_size = 6.0
		ap.max_distance = 90.0
		ap.volume_db = -8.0
		add_child(ap)
		_moteurs.append(ap)

# ================================================================ réseau
func _charger() -> bool:
	var f := "res://world/trafic.bin"
	if not FileAccess.file_exists(f):
		return false
	var b := FileAccess.get_file_as_bytes(f)
	var o := 0
	var nn := b.decode_s32(o); o += 4
	var xz := b.slice(o, o + nn * 8).to_float32_array(); o += nn * 8
	_nx.resize(nn); _nz.resize(nn); _deg.resize(nn)
	for i in nn:
		_nx[i] = xz[i * 2]; _nz[i] = xz[i * 2 + 1]
	var na := b.decode_s32(o); o += 4
	# 9 champs par arc depuis la v6.87 (feux), 7 avant : reconnu à la taille du fichier
	var champs := 9 if o + na * 36 + 4 <= b.size() and b.size() == o + na * 36 + 4 + b.decode_s32(o + na * 36) * 12 else 7
	var raw := b.slice(o, o + na * champs * 4); o += na * champs * 4
	var ints := raw.to_int32_array()
	var flts := raw.to_float32_array()
	for t in [_a, _b, _p0, _np, _fl, _v, _dl, _feu_b, _feu_a]:
		t.resize(na)
	var nsort := PackedInt32Array(); nsort.resize(nn + 1)
	for k in na:
		var j := k * champs
		_a[k] = ints[j]; _b[k] = ints[j + 1]; _p0[k] = ints[j + 2]; _np[k] = ints[j + 3]
		_fl[k] = ints[j + 4]; _v[k] = flts[j + 5]; _dl[k] = flts[j + 6]
		_feu_b[k] = ints[j + 7] if champs == 9 else -1
		_feu_a[k] = ints[j + 8] if champs == 9 else -1
		if not (_fl[k] & 1):
			_dl[k] = maxf(_dl[k], 1.25)          # double sens étroit : les voitures se croisent sans se toucher
		_deg[_a[k]] += 1; _deg[_b[k]] += 1
		nsort[_a[k] + 1] += 1
		if not (_fl[k] & 1):
			nsort[_b[k] + 1] += 1
	for i in nn:
		nsort[i + 1] += nsort[i]
	_sort_debut = nsort.duplicate()
	_sort.resize(nsort[nn])
	var rempli := nsort.duplicate()
	for k in na:
		_sort[rempli[_a[k]]] = k << 1; rempli[_a[k]] += 1
		if not (_fl[k] & 1):
			_sort[rempli[_b[k]]] = (k << 1) | 1; rempli[_b[k]] += 1
	var npt := b.decode_s32(o); o += 4
	_P = b.slice(o, o + npt * 12).to_float32_array()
	for k in na:
		var vu := {}
		var i := _p0[k]
		while true:
			var c := Vector2i(floori(_P[i * 3] / CASE), floori(_P[i * 3 + 2] / CASE))
			if not vu.has(c):
				vu[c] = true
				if not _grille.has(c):
					_grille[c] = PackedInt32Array()
				var l: PackedInt32Array = _grille[c]
				l.append(k)
				_grille[c] = l
			if i == _p0[k] + _np[k] - 1:
				break
			i = mini(i + 4, _p0[k] + _np[k] - 1)
	return true

func _cum(k: int) -> PackedFloat32Array:
	if _cums.has(k):
		return _cums[k]
	var c := PackedFloat32Array(); c.resize(_np[k])
	var p0 := _p0[k]
	for i in range(1, _np[k]):
		var j := (p0 + i) * 3
		c[i] = c[i - 1] + Vector2(_P[j] - _P[j - 3], _P[j + 2] - _P[j - 1]).length()
	_cums[k] = c
	return c

func _longueur(voie: int) -> float:
	var c := _cum(voie >> 1)
	return c[c.size() - 1]

func _voies(k: int) -> int:
	return maxi(1, (_fl[k] >> 4) & 15)

## Point de la voie à s m de son début (dans le sens de marche), rang = voie comptée depuis la droite :
## [position, direction de marche (Vector2)].
func _geo(voie: int, s: float, rang: int) -> Array:
	var k := voie >> 1
	var c := _cum(k)
	var L := c[c.size() - 1]
	var d := clampf(s if voie & 1 == 0 else L - s, 0.0, L)
	var i := clampi(c.bsearch(d) - 1, 0, c.size() - 2)
	var seg := maxf(c[i + 1] - c[i], 0.001)
	var f := clampf((d - c[i]) / seg, 0.0, 1.0)
	var j := (_p0[k] + i) * 3
	var a := Vector3(_P[j], _P[j + 1], _P[j + 2])
	var b := Vector3(_P[j + 3], _P[j + 4], _P[j + 5])
	var t := Vector2(b.x - a.x, b.z - a.z).normalized()
	if voie & 1:
		t = -t
	var off := _dl[k]
	if _fl[k] & 1 and _voies(k) > 1:
		off -= float(rang) * minf(2.0 * _dl[k] / float(_voies(k) - 1), LARGEUR_VOIE)
	var p := a.lerp(b, f)
	return [p + Vector3(-t.y, 0.0, t.x) * off, t]

func _noeud_fin(voie: int) -> int:
	return _b[voie >> 1] if voie & 1 == 0 else _a[voie >> 1]

## Voie suivante au bout de `voie` : plutôt tout droit et vers les grands axes, pas de demi-tour ni d'impasse s'il y a
## mieux ; -1 si rien (impasse d'un sens unique) ; -2 si la seule suite est le tracé d'une course (route barrée).
func _suite(voie: int) -> int:
	var n := _noeud_fin(voie)
	var t_fin: Vector2 = _geo(voie, _longueur(voie), 0)[1]
	var retour := voie ^ 1
	var cands := []
	var poids := []
	var total := 0.0
	var barre := false
	var ferme := not _trace.is_empty() and not _sur_trace(voie)        # course : on ne s'engage pas sur le tracé
	for i in range(_sort_debut[n], _sort_debut[n + 1]):
		var w := _sort[i]
		if w == retour:
			continue
		if ferme and _sur_trace(w):
			barre = true
			continue
		var t0: Vector2 = _geo(w, 0.0, 0)[1]
		var p := (1.6 + t_fin.dot(t0)) * float(CLASSE_POIDS[clampi((_fl[w >> 1] >> 8) & 15, 0, 10)])
		if _deg[_noeud_fin(w)] <= 1:
			p *= 0.05
		cands.append(w); poids.append(p); total += p
	if cands.is_empty():
		if barre:
			return -2
		return retour if not (_fl[voie >> 1] & 1) else -1
	var r := randf() * total
	for i in cands.size():
		r -= float(poids[i])
		if r <= 0.0:
			return cands[i]
	return cands[cands.size() - 1]

# ================================================================ modèles
func _preparer_modele(m: int) -> void:
	var sc: PackedScene = load("res://assets/props/%s.glb" % MODELES[m])
	var mesh: Mesh = (sc.instantiate().find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh
	var corps := []
	var roues := []
	for s in mesh.get_surface_count():
		var mt := mesh.surface_get_material(s)
		var nm := mt.resource_name if mt else ""
		if nm in SANS:
			continue
		var col := Color(0.5, 0.5, 0.5); var rm := 0.6
		if mt is StandardMaterial3D:
			var sm := mt as StandardMaterial3D
			col = sm.albedo_color
			rm = roundf(sm.metallic * 10.0) + clampf(sm.roughness, 0.0, 0.99)
		match nm:
			"paint": rm = -1.0
			"Front_lights": rm = -2.0; col = Color(0.85, 0.88, 0.9)
			"Brake_lights": rm = -3.0; col = Color(0.55, 0.04, 0.04)
			"Turn_lights": rm = -4.0; col = Color(0.75, 0.42, 0.08)
			"glass": col = Color(0.05, 0.06, 0.07); rm = 3.05
			"rubber": col = Color(0.03, 0.03, 0.035); rm = 0.9
		(roues if nm in ROUES else corps).append([mesh.surface_get_arrays(s), Color(col.r, col.g, col.b, rm)])
	_corps.append(_fusion(corps, true))
	# roues : les 4 groupes de triangles (avant/arrière × gauche/droite) ; la roue avant gauche sert pour les quatre
	var groupes := [[], [], [], []]
	var centres := [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	for r in roues:
		var a: Array = r[0]
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		for t in range(0, idx.size(), 3):
			var c := (v[idx[t]] + v[idx[t + 1]] + v[idx[t + 2]]) / 3.0
			groupes[(0 if c.z < 0.0 else 2) + (0 if c.x < 0.0 else 1)].append([r, t])
	var boites := []
	for g in 4:
		var bb := AABB()
		var premier := true
		for e in groupes[g]:
			var a: Array = e[0][0]
			var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
			for q in 3:
				var p := v[idx[e[1] + q]]
				if premier:
					bb = AABB(p, Vector3.ZERO); premier = false
				else:
					bb = bb.expand(p)
		boites.append(bb)
		centres[g] = bb.get_center()
	_pos_roues.append(centres)
	var P := PackedVector3Array(); var N := PackedVector3Array(); var U := PackedVector2Array(); var U2 := PackedVector2Array()
	var I := PackedInt32Array()
	for e in groupes[0]:
		var a: Array = e[0][0]
		var col: Color = e[0][1]
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var nr: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		for q in 3:
			P.append(v[idx[e[1] + q]] - centres[0]); N.append(nr[idx[e[1] + q]])
			U.append(Vector2(col.r, col.g)); U2.append(Vector2(col.b, col.a))
			I.append(I.size())
	var arr := []; arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = P; arr[Mesh.ARRAY_NORMAL] = N; arr[Mesh.ARRAY_TEX_UV] = U; arr[Mesh.ARRAY_TEX_UV2] = U2
	arr[Mesh.ARRAY_INDEX] = I
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	am.surface_set_material(0, _mat)
	_roue.append(am)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = am
	mm.instance_count = NOMBRE[NOMBRE.size() - 1] * 2 * 4
	mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-1e5, -2e3, -1e5), Vector3(2e5, 4e3, 2e5))
	add_child(mi)
	_mm_roues.append(mi)

## Surfaces [arrays, Color(r, v, b, rm)] en une seule (couleur et aspect de chaque matériau dans UV, UV2 ; voir
## circulation.gdshader), niveaux de détail comme à l'import.
func _fusion(parts: Array, lods: bool) -> Mesh:
	var P := PackedVector3Array(); var N := PackedVector3Array(); var U := PackedVector2Array(); var U2 := PackedVector2Array()
	var I := PackedInt32Array()
	for pa in parts:
		var a: Array = pa[0]
		var col: Color = pa[1]
		var base := P.size()
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		P.append_array(v)
		N.append_array(a[Mesh.ARRAY_NORMAL])
		for i in v.size():
			U.append(Vector2(col.r, col.g)); U2.append(Vector2(col.b, col.a))
		for i: int in a[Mesh.ARRAY_INDEX]:
			I.append(i + base)
	var arr := []; arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = P; arr[Mesh.ARRAY_NORMAL] = N; arr[Mesh.ARRAY_TEX_UV] = U; arr[Mesh.ARRAY_TEX_UV2] = U2
	arr[Mesh.ARRAY_INDEX] = I
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, _mat)
	if lods:
		im.generate_lods(25.0, 60.0, [])
	return im.get_mesh()

# ================================================================ réglages
func voulu() -> int:
	return int(round(float(NOMBRE[clampi(niveau, 0, NOMBRE.size() - 1)]) * float(DENSITES[clampi(densite, 0, DENSITES.size() - 1)])))

func set_niveau(n: int) -> void:
	niveau = n

func set_densite(d: int) -> void:
	densite = clampi(d, 0, DENSITES.size() - 1)

## Téléportation : tout est replacé autour de la nouvelle position.
func vider() -> void:
	for i in range(voitures.size() - 1, -1, -1):
		_retirer(i)
	for e in epaves:
		if is_instance_valid(e.rb):
			e.rb.queue_free()
	epaves.clear()
	_resa.clear()
	_remplir = true

# ================================================================ apparition, disparition
func _visible(p: Vector3) -> bool:
	var cam := get_viewport().get_camera_3d()
	return cam != null and cam.is_position_in_frustum(p + Vector3(0, 0.8, 0))

func _apparaitre(p: Vector3, partout: bool) -> void:
	var q := Vector2(p.x, p.z) + Vector2.from_angle(randf() * TAU) * randf_range(R_CACHE, R_MAX)
	var arcs: PackedInt32Array = _grille.get(Vector2i(floori(q.x / CASE), floori(q.y / CASE)), PackedInt32Array())
	if arcs.is_empty():
		return
	var k := arcs[randi() % arcs.size()]
	if randf() > float(CLASSE_POIDS[clampi((_fl[k] >> 8) & 15, 0, 10)]):
		return
	var voie := (k << 1) | (0 if (_fl[k] & 1) or randf() < 0.5 else 1)
	var L := _longueur(voie)
	if L < 8.0:
		return
	var s := randf_range(2.0, L - 2.0)
	var rang := randi() % _voies(k) if _fl[k] & 1 else 0
	var g := _geo(voie, s, rang)
	var pos: Vector3 = g[0]
	var d := pos.distance_to(p)
	if d < R_CACHE * (0.6 if partout else 1.0) or d > R_MAX + 20.0 or _sur_course(pos):
		return
	if not partout and d < R_VU and _visible(pos):
		return
	for o in voitures:
		if (o.pos as Vector3).distance_squared_to(pos) < 18.0 * 18.0:
			return
	for e in epaves:
		if is_instance_valid(e.rb) and (e.rb as Node3D).global_position.distance_squared_to(pos) < 25.0 * 25.0:
			return
	var m := randi() % MODELES.size()
	var c := {"id": _id, "m": m, "col": COULEURS[randi() % COULEURS.size()], "voie": voie, "s": s, "L": L, "rang": rang,
		"v": _v[k] * 0.7, "perso": randf_range(0.85, 1.02), "suite": -1, "dec": Vector3.ZERO, "dec_s": -100.0,
		"pos": pos, "dir": Vector3(g[1].x, 0.0, g[1].y), "frein": false, "roue": 0.0, "resa": -1, "bloque": 0.0,
		"klaxon": 0.0, "impasse": false, "leader": "", "clign": 0, "dep": [], "attente": 0.0, "engage": -1, "lent": 0.0,
		"derive": randf_range(-0.3, 0.3)}
	_id += 1
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _corps[m]
	mm.instance_count = 1
	mm.set_instance_transform(0, Transform3D.IDENTITY)
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	add_child(mi)
	c["mi"] = mi
	var corps := AnimatableBody3D.new()
	corps.sync_to_physics = true
	corps.set_meta("matiere", "metal")
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = BOITES[m]
	cs.shape = bs
	cs.position = Vector3(0, BOITES[m].y / 2.0, 0)
	corps.add_child(cs)
	add_child(corps)
	c["corps"] = corps
	_placer(c)
	corps.global_transform = Transform3D(c.basis, c.pos)
	voitures.append(c)

func _retirer(i: int) -> void:
	var c: Dictionary = voitures[i]
	_liberer(c)
	(c.mi as Node).queue_free()
	(c.corps as Node).queue_free()
	voitures.remove_at(i)

func _liberer(c: Dictionary) -> void:
	if int(c.resa) >= 0 and _resa.has(int(c.resa)) and int(_resa[int(c.resa)][0]) == int(c.id):
		_resa.erase(int(c.resa))
	c.resa = -1

# ================================================================ conduite
## Position affichée à s m sur la voie de la voiture (décalage du raccord et écart de dépassement compris).
func _pos(c: Dictionary, s: float) -> Vector3:
	var g := _geo(int(c.voie), s, int(c.rang))
	var k := 1.0 - smoothstep(float(c.dec_s), float(c.dec_s) + RACCORD, s)
	var p: Vector3 = (g[0] as Vector3) + (c.dec as Vector3) * k
	var e := _ecart(c, s) - float(c.derive)       # dérive : chaque conducteur tient sa voie un peu à sa façon
	if e != 0.0:
		var t: Vector2 = g[1]
		p += Vector3(t.y, 0.0, -t.x) * e            # vers la gauche du sens de marche
	return p

## Écart de dépassement à s (m, vers la gauche) : monte de dep[0] à dep[1], tenu jusqu'à dep[2], redescend à dep[3].
func _ecart(c: Dictionary, s: float) -> float:
	var d: Array = c.dep
	if d.is_empty():
		return 0.0
	return float(d[4]) * smoothstep(float(d[0]), float(d[1]), s) * (1.0 - smoothstep(float(d[2]), float(d[3]), s))

func _placer(c: Dictionary) -> void:
	var s: float = c.s
	var L: float = c.L
	var s1 := clampf(s - 1.6, 0.0, L)
	var s2 := clampf(s + 1.6, 0.0, L)
	if s2 - s1 < 0.5:
		s1 = maxf(s2 - 3.2, 0.0)
	var p1 := _pos(c, s1)
	var p2 := _pos(c, s2)
	var f := p2 - p1
	if f.length_squared() < 0.01:
		f = c.dir
	f = f.normalized()
	c.pos = _pos(c, s)
	c.dir = Vector3(f.x, 0.0, f.z).normalized()
	c.basis = Basis.looking_at(f, Vector3.UP)

## Vitesse permise par les virages devant (et le virage du carrefour, sur la voie suivante).
func _v_virage(c: Dictionary) -> float:
	var vmax := INF
	var t0: Vector2 = Vector2(c.dir.x, c.dir.z)
	for d in [10.0, 22.0, 36.0]:
		var s: float = float(c.s) + d
		var t: Vector2
		if s <= float(c.L):
			t = _geo(int(c.voie), s, 0)[1]
		elif int(c.suite) >= 0:
			t = _geo(int(c.suite), minf(s - float(c.L), _longueur(int(c.suite))), 0)[1]
		else:
			break
		var ang := absf(t0.angle_to(t))
		if ang > 0.05:
			vmax = minf(vmax, sqrt(A_LAT * d / ang))
	return vmax

func _reserver(n: int, c: Dictionary) -> bool:
	var r = _resa.get(n)
	if r == null or int(r[0]) == int(c.id) or _t - float(r[1]) > 15.0:
		_resa[n] = [int(c.id), _t]
		c.resa = n
		return true
	return false

const VUE := 54.0                              # portée du regard le long du chemin (m)
const PAS_VUE := 3.0

## Chemin de la voiture devant elle (voie en cours, décalage du raccord compris, puis voie suivante) : un point tous
## les PAS_VUE m, le premier à sa position.
func _chemin(c: Dictionary) -> PackedVector3Array:
	var l := PackedVector3Array()
	var s: float = c.s
	var L: float = c.L
	var suite := int(c.suite)
	var d := 0.0
	while d <= VUE:
		var q := s + d
		if q <= L:
			l.append(_pos(c, q))
		elif suite >= 0 and q - L <= _longueur(suite):
			var rang := mini(int(c.rang), _voies(suite >> 1) - 1) if _fl[suite >> 1] & 1 else 0
			l.append(_geo(suite, q - L, rang)[0])
		else:
			break
		d += PAS_VUE
	return l

## Ce qui gêne la voiture : [distance libre devant (m), vitesse de l'obstacle dans notre sens (m/s), nom].
## Voitures de la circulation : le long des voies (même voie devant, ou voie suivante). Autres obstacles (joueur,
## concurrents, piéton, épaves) : projetés sur le chemin de la voiture (une rue qui tourne : un obstacle à 30 m sur la
## voie peut être à plusieurs mètres de la ligne droite devant la voiture).
func _devant(c: Dictionary, obstacles: Array) -> Array:
	var gap := INF
	var vl := 0.0
	var qui := ""
	var demi: float = BOITES[int(c.m)].z / 2.0
	var voie := int(c.voie)
	var suite := int(c.suite)
	var reste: float = float(c.L) - float(c.s)
	var deboite := _ecart(c, float(c.s)) > 1.0          # sur la voie d'en face : les voitures de sa voie sont à côté
	for o in voitures:
		if int(o.id) == int(c.id):
			continue
		if deboite and _ecart(o, float(o.s)) < 0.5:
			continue
		var g := INF
		if int(o.voie) == voie and float(o.s) > float(c.s) and (int(o.rang) == int(c.rang) or not (_fl[voie >> 1] & 1)):
			g = float(o.s) - float(c.s)
		elif suite >= 0 and int(o.voie) == suite:
			g = reste + float(o.s)
		else:
			continue
		g -= demi + BOITES[int(o.m)].z / 2.0
		if g < gap:
			gap = g
			vl = float(o.v)
			qui = "circulation"
	var p: Vector3 = c.pos
	var f: Vector3 = c.dir
	var chemin := PackedVector3Array()
	for o in obstacles:
		var op: Vector3 = o[0]
		var d := op - p
		if d.length_squared() > (VUE + 8.0) * (VUE + 8.0) or d.dot(f) < -2.0:
			continue
		if chemin.is_empty():
			chemin = _chemin(c)
		var best := -1
		var bd := INF
		for k in chemin.size():
			var e := Vector2(chemin[k].x - op.x, chemin[k].z - op.z).length_squared()
			if e < bd:
				bd = e; best = k
		# à moins de 2 m du chemin (demi-largeur des deux voitures), au pas des points près
		if best < 0 or bd > 2.0 * 2.0 + (PAS_VUE * 0.5) * (PAS_VUE * 0.5) or (best == 0 and d.dot(f) <= 0.0):
			continue
		var g := float(best) * PAS_VUE - demi - float(o[2])
		if g < gap:
			gap = g
			vl = maxf(0.0, (o[1] as Vector3).dot(f))
			qui = String(o[3])
	return [gap, vl, qui]

func _conduire(c: Dictionary, dt: float, obstacles: Array) -> void:
	var k := int(c.voie) >> 1
	if int(c.suite) == -2 and _trace.is_empty():
		c.suite = -1                            # fin de la course : la route est rouverte
		c.impasse = false
	if int(c.suite) == -1 and float(c.L) - float(c.s) < 60.0:
		c.suite = _suite(int(c.voie))
		c.clign = _clignotant(int(c.voie), int(c.suite))
	var v0: float = _v[k] * float(c.perso) * lerpf(1.0, PLUIE_V, _pluie)
	v0 = minf(v0, _v_virage(c))
	var dv := _devant(c, obstacles)
	var gap: float = dv[0]
	var vl: float = dv[1]
	c.leader = dv[2]
	var reste: float = float(c.L) - float(c.s)
	var n := _noeud_fin(int(c.voie))
	var horizon := maxf(18.0, float(c.v) * float(c.v) / 6.0 + 8.0)
	# feu tricolore (#134) : arrêt au rouge, et à l'orange si l'arrêt est confortable ; pas de réservation du carrefour
	# pendant l'attente (les voitures qui ont le vert passent)
	var rouge := false
	var feu := _feu_b[k] if int(c.voie) & 1 == 0 else _feu_a[k]
	if feu >= 0 and reste < 90.0 and int(c.engage) != int(c.voie):
		var etat := _etat_feu(feu)
		if etat != 0:
			# orange ou rouge : arrêt si on peut encore freiner ; sinon on est engagé et on passe (même s'il passe au
			# rouge pendant qu'on franchit la ligne), comme un vrai conducteur
			var freinage := float(c.v) * float(c.v) / (2.0 * maxf(reste - ARRET_FEU, 0.01))
			if reste > ARRET_FEU - 0.5 and freinage < (3.5 if etat == 1 else 7.0):
				rouge = true
				if reste - ARRET_FEU < gap:
					gap = reste - ARRET_FEU; vl = 0.0; c.leader = "feu"
			else:
				c.engage = int(c.voie)
	# carrefour : un seul véhicule à la fois ; sinon arrêt avant le nœud
	if not rouge and _deg[n] >= 3 and reste < horizon and int(c.resa) != n:
		if not _reserver(n, c):
			var g2 := reste - 6.0
			if g2 < gap:
				gap = g2; vl = 0.0; c.leader = "carrefour"
	if int(c.suite) < 0 and _deg[n] <= 1 and reste < gap:
		gap = reste - 2.0; vl = 0.0; c.leader = "impasse"
	if int(c.suite) == -2 and reste - BARRAGE < gap:            # route barrée par une course : arrêt avant le carrefour
		gap = reste - BARRAGE; vl = 0.0; c.leader = "barrage"
		c.impasse = true
	# obstacle immobile devant (épave, joueur arrêté, concurrent) : on le dépasse après ATTENTE s
	if (c.dep as Array).is_empty() and String(c.leader) in ["joueur", "épave", "concurrent"] and float(c.v) < 0.5 \
			and vl < 0.3 and gap < 12.0:
		c.attente = float(c.attente) + dt
		if float(c.attente) > ATTENTE:
			c.attente = 0.0
			_depasser(c, gap)
	elif float(c.v) > 1.0:
		c.attente = 0.0
	# véhicule lent devant (joueur qui traîne, autre voiture) sur une route rapide à double sens : on le double quand la
	# voie d'en face est libre sur toute la longueur du dépassement (v6.89)
	if (c.dep as Array).is_empty() and String(c.leader) in ["joueur", "circulation"] and not (_fl[k] & 1) \
			and _v[k] >= V_RAPIDE and gap < 30.0 and vl > 1.5 and vl < 0.65 * _v[k]:
		c.lent = float(c.lent) + dt
		if float(c.lent) > LENT:
			c.lent = 0.0
			_doubler(c, gap, vl)
	else:
		c.lent = 0.0
	var dep: Array = c.dep
	if _ecart(c, float(c.s)) > 0.3:
		v0 = minf(v0, 8.0) if dep.size() < 6 else maxf(v0, float(dep[5]))   # au pas autour d'un obstacle immobile
	var v: float = c.v
	var s_et := IDM_S0 + maxf(0.0, v * IDM_T * lerpf(1.0, PLUIE_T, _pluie) + v * (v - vl) / (2.0 * sqrt(IDM_A * IDM_B)))
	var acc := IDM_A * (1.0 - pow(v / maxf(v0, 0.5), 4.0) - pow(s_et / maxf(gap, 0.2), 2.0))
	acc = clampf(acc, -9.0, IDM_A)
	v = maxf(0.0, v + acc * dt)
	c.v = v
	c.frein = acc < -0.6 or (v < 2.5 and acc < -0.05) or (v < 0.4 and gap < 12.0)
	# bloqué par le joueur : klaxon
	c.klaxon = maxf(float(c.klaxon) - dt, 0.0)
	if v < 0.5 and String(c.leader) == "joueur":
		c.bloque = float(c.bloque) + dt
		if float(c.bloque) > 2.5 and float(c.klaxon) <= 0.0:
			_klaxonner(c)
	else:
		c.bloque = 0.0
	# avance, passage d'une voie à l'autre
	c.s = float(c.s) + v * dt
	c.roue = fmod(float(c.roue) + v * dt / RAYON_ROUE, TAU)
	while float(c.s) >= float(c.L):
		if int(c.suite) == -1:
			c.suite = _suite(int(c.voie))
		if int(c.suite) < 0:
			c.s = c.L; c.v = 0.0; c.impasse = true
			break
		var avant := _pos(c, float(c.L))
		var s_neuf: float = float(c.s) - float(c.L)
		var ancienne := int(c.voie)
		if int(c.suite) >= 0 and int(c.clign) == 0:
			c.clign = _clignotant(ancienne, int(c.suite))
		c.voie = c.suite
		c.suite = -1
		c.L = _longueur(int(c.voie))
		c.s = minf(s_neuf, float(c.L))
		var kv := int(c.voie) >> 1
		c.rang = mini(int(c.rang), _voies(kv) - 1) if _fl[kv] & 1 else 0
		c.dep = []
		c.dec = Vector3.ZERO
		c.dec = avant - _pos(c, 0.0)
		c.dec_s = 0.0
		if ancienne == (int(c.voie) ^ 1):
			c.dec_s = -RACCORD * 0.5          # demi-tour (impasse) : raccord plus court
	if int(c.resa) >= 0 and int(c.resa) != _noeud_fin(int(c.voie)) and float(c.s) > 12.0:
		_liberer(c)
	if not (c.dep as Array).is_empty() and float(c.s) > float(c.dep[3]):
		c.dep = []
		c.clign = 0
	# clignotant : à moins de 45 m du carrefour où elle tourne, éteint 10 m après
	if int(c.clign) != 0 and int(c.suite) < 0 and float(c.s) > 10.0:
		c.clign = 0
	# dépassement : clignotant à gauche pour déboîter, à droite pour se rabattre
	var dp: Array = c.dep
	if not dp.is_empty():
		c.clign = 1 if float(c.s) < float(dp[1]) else (2 if float(c.s) > float(dp[2]) - 4.0 else 0)
	_placer(c)

## État d'un feu (phase × 2 + axe de trafic.bin) : 0 vert, 1 orange, 2 rouge ; même calcul que signal_light.gdshader.
func _etat_feu(feu: int) -> int:
	var t := fposmod(Env.temps_feux() + float(feu >> 1) + (30.0 if feu & 1 else 0.0), 60.0)
	return 0 if t < 27.0 else (1 if t < 30.0 else 2)

## Dépassement d'un obstacle immobile à `gap` m : autre file d'un sens unique à plusieurs voies (raccord lissé), ou
## voie d'en face si elle est libre sur DEGAGE m et que la manœuvre finit avant le bout de la voie.
func _depasser(c: Dictionary, gap: float) -> void:
	var k := int(c.voie) >> 1
	var s: float = c.s
	if _fl[k] & 1:
		if _voies(k) < 2:
			return
		var r2 := int(c.rang) + 1 if int(c.rang) + 1 < _voies(k) else int(c.rang) - 1
		for o in voitures:
			if int(o.id) != int(c.id) and int(o.voie) == int(c.voie) and int(o.rang) == r2 and absf(float(o.s) - s) < 25.0:
				return
		var avant := _pos(c, s)
		c.rang = r2
		c.dec = Vector3.ZERO
		c.dec = avant - _pos(c, s)
		c.dec_s = s
		return
	var fin: float = s + gap + BOITES[int(c.m)].z + 7.0
	if fin + 12.0 > float(c.L):
		return
	var rev := int(c.voie) ^ 1
	for o in voitures:
		if int(o.voie) == rev:
			var d_o := (float(c.L) - float(o.s)) - s     # distance de la voiture d'en face devant nous
			if d_o > -10.0 and d_o < DEGAGE:
				return
	c.dep = [s + 0.5, s + 7.0, fin, fin + 10.0, 2.0 * _dl[k]]
	if _debug:
		print("[circulation] voiture %d dépasse un obstacle (%s) à %.1f m : écart %.1f m de %.0f à %.0f m" % [int(c.id),
			c.leader, gap, 2.0 * _dl[k], s, fin])

## Doubler un véhicule lent (vitesse vl, gap m devant) : à la vitesse autorisée (au plus vl + 9 m/s), si la voie
## reste presque droite et la voie d'en face libre sur toute la longueur du dépassement (voitures qui arrivent comprises).
## dep[5] : vitesse du dépassement (au lieu du pas des obstacles immobiles).
func _doubler(c: Dictionary, gap: float, vl: float) -> void:
	var k := int(c.voie) >> 1
	var s: float = c.s
	var vd := minf(_v[k] * float(c.perso), vl + 9.0)
	if vd < vl + 4.0:
		return
	var long_l: float = BOITES[1].z if String(c.leader) == "circulation" else 5.0
	var rel: float = gap + long_l + BOITES[int(c.m)].z + 14.0
	var t := rel / (vd - vl)
	var dist := vd * t + 8.0
	var fin := s + dist
	if fin + 15.0 > float(c.L):
		return
	var t0: Vector2 = _geo(int(c.voie), s, 0)[1]
	for f in [0.5, 1.0]:
		if absf(t0.angle_to(_geo(int(c.voie), s + dist * f, 0)[1])) > deg_to_rad(18.0):
			return                                          # virage : pas de visibilité
	var rev := int(c.voie) ^ 1
	for o in voitures:
		if int(o.voie) == rev:
			var d_o := (float(c.L) - float(o.s)) - s       # voiture d'en face : distance devant nous
			if d_o > -10.0 and d_o < dist + float(o.v) * (t + 2.0) + 40.0:
				return
	# joueur ou concurrent sur la voie d'en face, devant
	var p: Vector3 = c.pos
	var fwd: Vector3 = c.dir
	for o in _pilotes():
		var d: Vector3 = (o as Node3D).global_position - p
		var av := d.dot(fwd)
		var lat := d.dot(Vector3(-fwd.z, 0.0, fwd.x))
		if av > gap + 3.0 and av < dist + 60.0 and absf(lat + 2.0 * _dl[k]) < 2.5:
			return
	c.dep = [s + 1.0, s + 10.0, fin - 14.0, fin, 2.0 * _dl[k], vd]
	if _debug:
		print("[circulation] voiture %d double un véhicule lent (%s, %.0f km/h) : de %.0f à %.0f m, à %.0f km/h" % [
			int(c.id), c.leader, vl * 3.6, s, fin, vd * 3.6])

## Clignotant pour passer de la voie `de` à la voie `vers` : 0 tout droit, 1 à gauche, 2 à droite (plus de 30°).
func _clignotant(de: int, vers: int) -> int:
	if vers < 0:
		return 0
	var t1: Vector2 = _geo(de, _longueur(de), 0)[1]
	var t2: Vector2 = _geo(vers, minf(6.0, _longueur(vers)), 0)[1]
	var a := t1.angle_to(t2)                   # repère x est, z sud : positif = vers la droite
	if absf(a) < deg_to_rad(30.0):
		return 0
	return 2 if a > 0.0 else 1

func _klaxonner(c: Dictionary) -> void:
	c.klaxon = 7.0
	if _son_klaxon == null:
		return
	var ap := AudioStreamPlayer3D.new()
	ap.stream = _son_klaxon
	ap.bus = "Monde" if AudioServer.get_bus_index("Monde") >= 0 else "Master"
	ap.unit_size = 10.0
	ap.pitch_scale = randf_range(0.9, 1.1)
	add_child(ap)
	ap.global_position = c.pos
	ap.play()
	ap.finished.connect(ap.queue_free)

# ================================================================ boucle
func _physics_process(dt: float) -> void:
	if not ok or target == null or get_tree().paused:
		return
	var t0 := Time.get_ticks_usec()
	_t += dt
	_pluie = float(main.get("pluie")) if main else 0.0
	var p := target.global_position
	_route_course()
	for i in range(voitures.size() - 1, -1, -1):
		var c: Dictionary = voitures[i]
		var d := (c.pos as Vector3).distance_to(p)
		if d > R_LOIN or (bool(c.impasse) and d > 40.0 and not _visible(c.pos)):
			_retirer(i)
	var n := voulu()
	while voitures.size() > n:
		_retirer(voitures.size() - 1)
	var essais := 80 if _remplir else 4
	while voitures.size() < n and essais > 0:
		essais -= 1
		_apparaitre(p, _remplir)
	_remplir = false
	var obstacles := _obstacles()
	for c in voitures:
		_conduire(c, dt, obstacles)
	_chocs()
	_epaves(dt)
	_rendre()
	PerfMon.note("circulation", Time.get_ticks_usec() - t0)

## Obstacles qui ne sont pas des voitures de la circulation : [position, vitesse (Vector3), demi-longueur, nom].
func _obstacles() -> Array:
	var l := []
	for o in _pilotes():
		var b: RigidBody3D = o
		var vel := b.linear_velocity
		vel.y = 0.0
		l.append([b.global_position, vel, 2.4, "joueur" if b == _joueur() else "concurrent"])
	for c in voitures:                                  # voiture qui dépasse, sur la voie d'en face
		if not (c.dep as Array).is_empty():
			l.append([c.pos, (c.dir as Vector3) * float(c.v), BOITES[int(c.m)].z / 2.0, "circulation"])
	if target and target != _joueur():                 # à pied (#66) : le piéton
		l.append([target.global_position, Vector3.ZERO, 0.5, "joueur"])
	for e in epaves:
		if is_instance_valid(e.rb):
			l.append([(e.rb as Node3D).global_position, Vector3.ZERO, 2.2, "épave"])
	var pie = main.get("pietons") if main else null
	if pie and pie.ok:                                  # passants qui traversent (v6.88, #135)
		for q in pie.sur_passage():
			l.append([q[0], q[1], 0.5, "passant"])
	return l

func _joueur() -> Node3D:
	return main.car if main and main.get("car") else null

## Voitures pilotées qui peuvent percuter la circulation : le joueur et les concurrents d'une course.
func _pilotes() -> Array:
	var l := []
	var j := _joueur()
	if j:
		l.append(j)
	var act = main.get("activities") if main else null
	if act and act.get("concurrents"):
		for c in act.concurrents:
			if is_instance_valid(c) and c.voiture and is_instance_valid(c.voiture):
				l.append(c.voiture)
	return l

## Juste avant qu'une voiture pilotée la percute (boîtes qui se touchent à la marge près, vitesse de rapprochement
## > 1,5 m/s), la voiture de la circulation devient un corps rigide (épave) : le choc se joue entre deux masses.
func _chocs() -> void:
	var pilotes := _pilotes()
	for i in range(voitures.size() - 1, -1, -1):
		var c: Dictionary = voitures[i]
		var cv: Vector3 = (c.dir as Vector3) * float(c.v)
		for o in pilotes:
			var b: RigidBody3D = o
			var d: Vector3 = b.global_position - (c.pos as Vector3)
			if d.length_squared() > 15.0 * 15.0:
				continue
			var rel := b.linear_velocity - cv
			var proche := -rel.dot(d.normalized())
			if proche < 1.5:
				continue
			# marge propre à chaque axe, selon la vitesse de rapprochement sur cet axe (une voiture qui en croise une
			# autre à 2,5 m de côté ne se rapproche pas latéralement : pas de choc)
			var loc: Vector3 = (c.basis as Basis).inverse() * d
			var rl: Vector3 = (c.basis as Basis).inverse() * rel
			var mx := 0.3 + maxf(0.0, -signf(loc.x) * rl.x) * 0.12
			var mz := 0.3 + maxf(0.0, -signf(loc.z) * rl.z) * 0.12
			var bx: Vector3 = BOITES[int(c.m)]
			if absf(loc.x) - (bx.x / 2.0 + 1.0) < mx and absf(loc.z) - (bx.z / 2.0 + 2.3) < mz:
				if _debug:
					print("[circulation] choc prévu : voiture %d, rapprochement %.1f m/s, repère de la voiture %s, vitesse du pilote %s" % [
						int(c.id), proche, loc.snapped(Vector3.ONE * 0.1), b.linear_velocity.snapped(Vector3.ONE * 0.1)])
				_accident(i, b)
				break

func _accident(i: int, par: Node3D) -> void:
	var c: Dictionary = voitures[i]
	var m := int(c.m)
	var rb := RigidBody3D.new()
	rb.set_meta("matiere", "metal")
	rb.mass = MASSES[m]
	rb.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	rb.center_of_mass = Vector3(0, BOITES[m].y * 0.35, 0)
	rb.angular_damp = 1.2
	rb.linear_damp = 0.3
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = BOITES[m]
	cs.shape = bs
	cs.position = Vector3(0, BOITES[m].y / 2.0, 0)
	rb.add_child(cs)
	var mi: MultiMeshInstance3D = c.mi
	remove_child(mi)
	rb.add_child(mi)
	mi.transform = Transform3D.IDENTITY
	for g in 4:
		var w := MeshInstance3D.new()
		w.mesh = _roue[m]
		w.transform = _roue_xf(m, g, float(c.roue))
		w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rb.add_child(w)
	(c.corps as Node).queue_free()
	_liberer(c)
	add_child(rb)
	rb.global_transform = Transform3D(c.basis, c.pos)
	rb.linear_velocity = (c.dir as Vector3) * float(c.v)
	epaves.append({"rb": rb, "t": 0.0})
	voitures.remove_at(i)
	accidents += 1
	if par == _joueur() and main.get("succes"):
		main.succes.noter("circulation")              # succès (#133)
	if _debug:
		print("[circulation] choc : voiture %d devient une épave (%.0f km/h, percutée par %s) à (%.0f, %.0f), meneur %s, suite %d, sur le tracé %s" % [
			int(c.id), float(c.v) * 3.6, par.name, (c.pos as Vector3).x, (c.pos as Vector3).z, c.leader, int(c.suite),
			str(not _trace.is_empty() and _sur_trace(int(c.voie)))])

func _epaves(dt: float) -> void:
	var p := target.global_position
	for i in range(epaves.size() - 1, -1, -1):
		var e: Dictionary = epaves[i]
		if not is_instance_valid(e.rb):
			epaves.remove_at(i)
			continue
		var rb: RigidBody3D = e.rb
		e.t = float(e.t) + dt
		var d := rb.global_position.distance_to(p)
		if d > R_LOIN or (float(e.t) > EPAVE and d > 60.0 and not _visible(rb.global_position)):
			rb.queue_free()
			epaves.remove_at(i)

## Course contre des concurrents (activities.mode « course ») : leur tracé est dégagé sur COURSE_MARGE m de part et
## d'autre (sinon, en circulation dense, le peloton percutait voiture sur voiture et s'empilait sur les épaves dans les
## rues étroites des villages) : au départ, voitures et épaves du tracé retirées ; ensuite, aucune n'y apparaît, et
## celles d'ailleurs ne s'engagent plus sur le tracé (_suite : -2, arrêt BARRAGE m avant le carrefour, comme devant une route barrée,
## puis retirées hors de vue) ; les concurrents évitent celles qui le traversent (concurrent.gd).
func _route_course() -> void:
	var act = main.get("activities") if main else null
	var cs = act.get("concurrents") if act else null
	if act == null or str(act.mode) != "course" or cs == null or (cs as Array).is_empty() or not is_instance_valid(cs[0]):
		if not _course_cases.is_empty():
			_course_cases = {}
			_trace = {}
			_course_id = 0
		return
	var c0 = cs[0]
	if not c0.pret or c0.get_instance_id() == _course_id:
		return
	_course_id = c0.get_instance_id()
	_course_cases = {}
	_trace = {}
	var r := ceili(COURSE_MARGE / COURSE_CASE)
	var vu := {}
	var ch: PackedVector2Array = c0._chemin
	for i in ch.size():
		var q := ch[i]
		var kt := Vector2i(floori(q.x / 8.0), floori(q.y / 8.0))
		if not _trace.has(kt):
			_trace[kt] = []
		(_trace[kt] as Array).append([q, (ch[mini(i + 1, ch.size() - 1)] - ch[maxi(i - 1, 0)]).normalized()])
		var k := Vector2i(floori(q.x / COURSE_CASE), floori(q.y / COURSE_CASE))
		if vu.has(k):
			continue
		vu[k] = true
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				_course_cases[k + Vector2i(dx, dz)] = true
	var n_v := voitures.size()
	for i in range(voitures.size() - 1, -1, -1):
		if _sur_course(voitures[i].pos):
			_retirer(i)
	for i in range(epaves.size() - 1, -1, -1):
		var rb = epaves[i].rb
		if is_instance_valid(rb) and _sur_course((rb as Node3D).global_position):
			rb.queue_free()
			epaves.remove_at(i)
	for c in voitures:                                  # suites choisies avant la course : à refaire
		if int(c.suite) >= 0 and _sur_trace(int(c.suite)) and not _sur_trace(int(c.voie)):
			c.suite = -1
	if _debug:
		print("[circulation] course : tracé de %d points, %d cases dégagées, %d voitures retirées" % [c0._chemin.size(),
			_course_cases.size(), n_v - voitures.size()])

## La voie suit-elle le tracé de la course ? Deux de ses points (au tiers et aux deux tiers, 20 m au plus) à moins de
## 4,5 m d'un point du tracé, dans la même direction (dans un sens ou dans l'autre) : une rue qui débouche sur le tracé
## n'en fait pas partie.
func _sur_trace(voie: int) -> bool:
	var L := _longueur(voie)
	for s in [minf(L / 3.0, 10.0), minf(L * 2.0 / 3.0, 20.0)]:
		var g := _geo(voie, s, 0)
		var p: Vector3 = g[0]
		var t: Vector2 = g[1]
		var k := Vector2i(floori(p.x / 8.0), floori(p.z / 8.0))
		var pres := false
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				for e in _trace.get(k + Vector2i(dx, dz), []):
					if (e[0] as Vector2).distance_squared_to(Vector2(p.x, p.z)) < 4.5 * 4.5 and absf((e[1] as Vector2).dot(t)) > 0.8:
						pres = true
						break
				if pres:
					break
			if pres:
				break
		if not pres:
			return false
	return true

func _sur_course(p: Vector3) -> bool:
	return not _course_cases.is_empty() and _course_cases.has(Vector2i(floori(p.x / COURSE_CASE), floori(p.z / COURSE_CASE)))

## Roue g (0 avant gauche, 1 avant droite, 2 arrière gauche, 3 arrière droite) d'un modèle, tournée de l'angle a.
func _roue_xf(m: int, g: int, a: float) -> Transform3D:
	var b := Basis(Vector3.RIGHT, -a)
	if g % 2 == 1:
		b = b * Basis(Vector3.UP, PI)
	return Transform3D(b, _pos_roues[m][g])

func _rendre() -> void:
	var phares: bool = main != null and (int(main.get("time_of_day")) >= 2 or bool(main.get("phares_meteo")))
	var nb := [0, 0]
	var plus_proches := []
	for c in voitures:
		var m := int(c.m)
		var xf := Transform3D(c.basis, c.pos)
		var mi: MultiMeshInstance3D = c.mi
		var col: Color = c.col
		var cl := int(c.clign) if float(c.L) - float(c.s) < 45.0 or float(c.s) < 10.0 else 0
		var bits := (1 if phares else 0) | (2 if bool(c.frein) else 0) | (4 if cl == 1 else 0) | (8 if cl == 2 else 0)
		col.a = (float(bits) + 0.5) / 16.0
		mi.multimesh.set_instance_custom_data(0, col)
		mi.global_transform = xf
		(c.corps as AnimatableBody3D).global_transform = xf
		var mm: MultiMesh = (_mm_roues[m] as MultiMeshInstance3D).multimesh
		for g in 4:
			if nb[m] >= mm.instance_count:
				break
			mm.set_instance_transform(nb[m], xf * _roue_xf(m, g, float(c.roue)))
			mm.set_instance_custom_data(nb[m], col)
			nb[m] += 1
		plus_proches.append([(c.pos as Vector3).distance_squared_to(target.global_position), c])
	for m in MODELES.size():
		(_mm_roues[m] as MultiMeshInstance3D).multimesh.visible_instance_count = nb[m]
	# bruit de moteur des deux voitures les plus proches
	plus_proches.sort_custom(func(x, y): return x[0] < y[0])
	for k in _moteurs.size():
		var ap: AudioStreamPlayer3D = _moteurs[k]
		if k < plus_proches.size() and float(plus_proches[k][0]) < 80.0 * 80.0:
			var c: Dictionary = plus_proches[k][1]
			ap.global_position = c.pos
			ap.pitch_scale = clampf(0.55 + float(c.v) / 20.0, 0.5, 1.6)
			ap.volume_db = -14.0 + clampf(float(c.v) / 3.0, 0.0, 6.0)
			if not ap.playing:
				ap.play(randf() * 2.0)
		elif ap.playing:
			ap.stop()
