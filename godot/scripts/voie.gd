## Aide au maintien dans la voie (v6.25, demande de l'utilisateur) : quand le joueur ne tourne pas, un léger coup de
## volant ramène la voiture au milieu de sa voie (à droite sur les routes à double sens), comme l'assistance des
## voitures récentes. Données : world/voies.bin (pipeline/build_voies.py, grille de world/roadnames.json).
## Rien aux carrefours (deux routes de sens différents à moins de 12 m), hors de la chaussée, à moins de 15 km/h,
## en marche arrière, ni pendant ~0,35 s après un coup de volant du joueur. Réglage ⚙ > Conduite.
extends RefCounted

# v6.40 (demande du 14/10 : « ultra puissante ») : la voiture vise le milieu de sa voie quelques mètres devant elle
# (poursuite d'un point, comme un pilote automatique) : elle suit les virages, braque fort, reprend vite la main.
const V_MIN := 15.0 / 3.6
const K_VISEE := 2.4               # braquage (part du maximum) par radian d'écart avec le point visé
const MAXI := 1.0
const LIBRE := 0.35                # s sans action du joueur avant de reprendre la main
const LISSE := 7.0                 # vitesse de variation de la correction (par s)

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
	_v = v
	var c := _calcul(p, fwd) if v > V_MIN and _libre <= 0.0 else 0.0
	_lisse = move_toward(_lisse, c, LISSE * dt)
	actif = absf(_lisse) > 0.01 or (c != 0.0)
	return _lisse

func _calcul(p: Vector3, f: Vector3) -> float:
	var f2 := Vector2(f.x, f.z).normalized()
	var v2 := Vector2(p.x, p.z)
	var ici := _voie(v2, f2)
	if ici.is_empty():
		return 0.0
	ecart = ici[2]
	# point visé : milieu de la voie, plus loin quand on roule vite (anticipe les virages)
	var visee := clampf(_v * 0.55, 6.0, 22.0)
	var loin := _voie(v2 + f2 * visee, f2)
	var cible: Vector2 = loin[0] if not loin.is_empty() else ici[0] + ici[1] * visee
	var vers := (cible - v2).normalized()
	return clampf(-K_VISEE * f2.angle_to(vers), -MAXI, MAXI)

var _v := 0.0

## Milieu de la voie près du point q : [point du milieu de la voie, sens de la voie, écart latéral (m), largeur]
## ou [] (pas de route, carrefour, contresens d'un sens unique, voiture en travers, hors de la chaussée).
func _voie(q: Vector2, f2: Vector2) -> Array:
	var cx := floori((q.x - float(meta.x0)) / float(meta.cell))
	var cz := floori((q.y - float(meta.z0)) / float(meta.cell))
	var best := -1
	var bd := INF
	var cand: Array = []                # points à moins de 12 m
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var x := cx + dx; var z := cz + dz
			if x < 0 or z < 0 or x >= int(meta.nx) or z >= int(meta.nz):
				continue
			var k := z * int(meta.nx) + x
			for i in range(starts[k], starts[k + 1]):
				var o := i * 6
				var d := Vector2(pts[o] - q.x, pts[o + 1] - q.y).length_squared()
				if d < 144.0:
					cand.append(i)
					if d < bd:
						bd = d; best = i
	if best < 0:
		return []
	var ob := best * 6
	var dir := Vector2(pts[ob + 2], pts[ob + 3])
	var al := dir.dot(f2)
	var n := int(pts[ob + 5])
	if n > 0 and al < 0.0:
		return []                       # sens unique pris à contresens : pas d'aide
	if absf(al) < 0.7:
		return []                       # voiture en travers de la route
	if al < 0.0:
		dir = -dir
	# carrefour : une autre route (direction différente) tout près
	for i in cand:
		var o: int = i * 6
		if absf(Vector2(pts[o + 2], pts[o + 3]).dot(dir)) < 0.85:
			return []
	var hw := pts[ob + 4]
	var droite := Vector2(-dir.y, dir.x)          # (x, z) : à droite du sens de marche
	var axe := Vector2(pts[ob], pts[ob + 1])
	var lat := (q - axe).dot(droite)               # > 0 : à droite de l'axe
	if absf(lat) > hw + 1.5:
		return []                       # hors de la chaussée
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
	# point du milieu de la voie au droit de q
	var along := (q - axe).dot(dir)
	return [axe + dir * along + droite * cible, dir, lat - cible, hw]
