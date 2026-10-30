## Zone jouable (#156) : polygone de world/zone.json (pipeline/build_zone.py) ; au-delà commencent les collines du bord
## (bord.gd), qu'aucune activité ne doit faire traverser ni viser. Partagée par tous, lue une fois (sur le fil principal :
## ensuite en lecture seule, donc utilisable par les fils de travail de l'itinéraire).
extends RefCounted

const BANDE := 32.0              # m : bandes horizontales (côtés coupant chaque bande, pour le test d'appartenance)
const CASE := 64.0               # m : cases des côtés proches (test de marge)

static var _pts := PackedVector2Array()
static var _bandes := {}         # int -> PackedInt32Array de côtés
static var _cases := {}          # Vector2i -> PackedInt32Array de côtés
static var _lu := false

static func _lire() -> void:
	if _lu:
		return
	_lu = true
	if not FileAccess.file_exists("res://world/zone.json"):
		return
	var z = JSON.parse_string(FileAccess.get_file_as_string("res://world/zone.json"))
	if not z is Dictionary:
		return
	for q in z.pts:
		_pts.append(Vector2(q[0], q[1]))
	var n := _pts.size()
	for i in n:
		var a := _pts[i]; var b := _pts[(i + 1) % n]
		for j in range(floori(minf(a.y, b.y) / BANDE), floori(maxf(a.y, b.y) / BANDE) + 1):
			_ajouter(_bandes, j, i)
		for cx in range(floori(minf(a.x, b.x) / CASE), floori(maxf(a.x, b.x) / CASE) + 1):
			for cz in range(floori(minf(a.y, b.y) / CASE), floori(maxf(a.y, b.y) / CASE) + 1):
				_ajouter(_cases, Vector2i(cx, cz), i)

static func _ajouter(d: Dictionary, k: Variant, i: int) -> void:
	var l: PackedInt32Array = d.get(k, PackedInt32Array())
	l.append(i)
	d[k] = l

static func connue() -> bool:
	_lire()
	return not _pts.is_empty()

## p (x, z) dans la zone jouable, à `marge` m au moins de sa limite ; vrai partout si la zone n'est pas connue.
static func dedans(p: Vector2, marge := 0.0) -> bool:
	_lire()
	if _pts.is_empty():
		return true
	var n := _pts.size()
	var impair := false
	for i: int in _bandes.get(floori(p.y / BANDE), PackedInt32Array()):
		var a := _pts[i]; var b := _pts[(i + 1) % n]
		if (a.y > p.y) != (b.y > p.y) and p.x < a.x + (p.y - a.y) * (b.x - a.x) / (b.y - a.y):
			impair = not impair
	if not impair:
		return false
	return marge <= 0.0 or distance_bord(p, marge) >= marge

## Distance de p à la limite de la zone, plafonnée à `jusqua` m (au-delà, renvoie `jusqua`).
static func distance_bord(p: Vector2, jusqua: float) -> float:
	_lire()
	var n := _pts.size()
	var d2 := jusqua * jusqua
	var r := ceili(jusqua / CASE)
	var c := Vector2i(floori(p.x / CASE), floori(p.y / CASE))
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			for i: int in _cases.get(c + Vector2i(dx, dz), PackedInt32Array()):
				d2 = minf(d2, Geometry2D.get_closest_point_to_segment(p, _pts[i], _pts[(i + 1) % n]).distance_squared_to(p))
	return sqrt(d2)
