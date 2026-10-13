## Aide au maintien dans la voie (v6.25, demande de l'utilisateur) : quand le joueur ne tourne pas, un léger coup de
## volant ramène la voiture au milieu de sa voie (à droite sur les routes à double sens), comme l'assistance des
## voitures récentes. Données : world/voies.bin (pipeline/build_voies.py, grille de world/roadnames.json).
## Rien aux carrefours (deux routes de sens différents à moins de 12 m), hors de la chaussée, à moins de 30 km/h,
## en marche arrière, ni pendant ~0,8 s après un coup de volant du joueur. Réglage ⚙ > Conduite.
extends RefCounted

const V_MIN := 30.0 / 3.6
const K_ECART := 0.09              # braquage (part du maximum) par mètre d'écart au milieu de la voie
const K_CAP := 1.1                 # … par radian d'écart de cap
const MAXI := 0.32
const LIBRE := 0.8                 # s sans action du joueur avant de reprendre la main

var meta: Dictionary
var starts: PackedInt32Array
var pts: PackedFloat32Array
var ok := false
var actif := false                 # correction en cours (témoin du tableau de bord)
var _libre := 0.0
var _lisse := 0.0
var ecart := 0.0                   # dernier écart au milieu de la voie (m, > 0 : trop à droite ; essais)

func _init() -> void:
	if not FileAccess.file_exists("res://world/voies.bin") or not FileAccess.file_exists("res://world/roadnames.json"):
		return
	meta = JSON.parse_string(FileAccess.get_file_as_string("res://world/roadnames.json"))
	var b := FileAccess.get_file_as_bytes("res://world/voies.bin")
	var n := int(meta.nx) * int(meta.nz) + 1
	starts = b.slice(0, n * 4).to_int32_array()
	pts = b.slice(n * 4).to_float32_array()
	ok = true

## Braquage à ajouter (-1 … 1, positif = à gauche) ; st = braquage demandé par le joueur.
func correction(p: Vector3, fwd: Vector3, v: float, st: float, dt: float) -> float:
	actif = false
	if not ok:
		return 0.0
	if absf(st) > 0.05:
		_libre = LIBRE
	_libre -= dt
	var c := _calcul(p, fwd) if v > V_MIN and _libre <= 0.0 else 0.0
	_lisse = move_toward(_lisse, c, 1.5 * dt)
	actif = absf(_lisse) > 0.01 or (c != 0.0)
	return _lisse

func _calcul(p: Vector3, f: Vector3) -> float:
	var f2 := Vector2(f.x, f.z).normalized()
	var cx := floori((p.x - float(meta.x0)) / float(meta.cell))
	var cz := floori((p.z - float(meta.z0)) / float(meta.cell))
	var best := -1
	var bd := INF
	var cand: Array = []                # (indice, distance²) des points alignés à moins de 12 m
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var x := cx + dx; var z := cz + dz
			if x < 0 or z < 0 or x >= int(meta.nx) or z >= int(meta.nz):
				continue
			var k := z * int(meta.nx) + x
			for i in range(starts[k], starts[k + 1]):
				var o := i * 6
				var d := Vector2(pts[o] - p.x, pts[o + 1] - p.z).length_squared()
				if d < 144.0:
					cand.append(i)
					if d < bd:
						bd = d; best = i
	if best < 0:
		return 0.0
	var ob := best * 6
	var dir := Vector2(pts[ob + 2], pts[ob + 3])
	var al := dir.dot(f2)
	var n := int(pts[ob + 5])
	if n > 0 and al < 0.0:
		return 0.0                      # sens unique pris à contresens : pas d'aide
	if absf(al) < 0.9:
		return 0.0                      # voiture en travers de la route
	if al < 0.0:
		dir = -dir
	# carrefour : une autre route (direction différente) tout près
	for i in cand:
		var o: int = i * 6
		if absf(Vector2(pts[o + 2], pts[o + 3]).dot(dir)) < 0.9:
			return 0.0
	var hw := pts[ob + 4]
	var droite := Vector2(-dir.y, dir.x)          # (x, z) : à droite du sens de marche
	var axe := Vector2(pts[ob], pts[ob + 1])
	var lat := (Vector2(p.x, p.z) - axe).dot(droite)   # > 0 : à droite de l'axe
	if absf(lat) > hw + 0.6:
		return 0.0                      # hors de la chaussée
	var cible := 0.0
	var nv := absi(n)
	if n < 0 and nv >= 2:
		# double sens : milieu de la voie de droite (ou de la voie la plus proche s'il y en a plusieurs par sens)
		var par := maxi(1, nv / 2)
		var lv := hw / par
		cible = clampf(floorf(maxf(lat, 0.0) / lv) * lv + lv * 0.5, lv * 0.5, hw - lv * 0.5)
	elif n > 0 and nv >= 2:
		var lv := 2.0 * hw / nv
		cible = clampf(floorf((lat + hw) / lv) * lv + lv * 0.5 - hw, -hw + lv * 0.5, hw - lv * 0.5)
	ecart = lat - cible                            # > 0 : trop à droite -> braquer à gauche (positif)
	var cap := f2.angle_to(dir)                    # rotation (repère x, z) pour aligner la voiture sur la voie
	return clampf(K_ECART * ecart - K_CAP * cap, -MAXI, MAXI)
