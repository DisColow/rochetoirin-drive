## Fantôme d'un rival (mode carrière, #120 : « les fantômes qui roulent en même temps ») : voiture translucide qui roule
## en même temps que le joueur sur le tracé d'une épreuve et arrive au temps voulu ; aucune collision (on la traverse).
## - Tracé par les routes : itineraire.gd, étape par étape (comme carte_trace.gd), calculé en arrière-plan.
## - Profil de vitesse : virages (accélération latérale), accélération et freinage, puis mis à l'échelle pour finir
##   exactement au temps cible.
## - Horloge : celle de la course du joueur (activities._t), donc départ au « Partez ! » et aucun décalage.
extends Node3D

const Relief := preload("res://scripts/relief.gd")
const Voitures := preload("res://scripts/voitures.gd")
const PAS := 2.0                    # rééchantillonnage du tracé (m)
const A_LAT := 6.5                  # accélération latérale admise (m/s²)
const A_ACC := 3.0
const A_FREIN := 6.0
const V_MAX := 42.0                 # ~150 km/h
const DECALE := 2.4                 # départ à côté du joueur (m, à gauche), rejoint l'axe en 60 m

var points: Array = []             # étapes (Vector2) : départ, points de passage, arrivée
var temps_cible := 300.0
var voiture := "p106"
var nom := "Rival"
var pret := false                  # tracé et profil prêts
var t := -1.0                      # temps de course (< 0 : pas encore parti)
var longueur := 0.0

var _itin
var _etape := 0
var _chemin := PackedVector2Array()
var _s := PackedFloat32Array()     # abscisse curviligne de chaque point
var _tps := PackedFloat32Array()   # heure de passage à chaque point
var _modele: Node3D
var _roues: Array = []
var _r_roue := 0.3
var _y_roue := 0.3

func _ready() -> void:
	_itin = preload("res://scripts/itineraire.gd").new()
	_construire()
	visible = false
	if points.size() >= 2:
		_itin.calculer(points[0], points[1])

## Calcul du tracé jambe par jambe, puis du profil ; ensuite, position à l'heure t.
func _process(_dt: float) -> void:
	if not pret:
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
				_poser(0.0)
				visible = true
		return
	if t >= 0.0:
		_poser(t)

## Abscisses curvilignes, vitesses limites (virages, accélération, freinage), puis temps de passage à l'échelle.
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
	_s.resize(n); _tps.resize(n)
	var v := PackedFloat32Array(); v.resize(n)
	_s[0] = 0.0
	for i in range(1, n):
		_s[i] = _s[i - 1] + p[i - 1].distance_to(p[i])
	longueur = _s[n - 1]
	for i in n:
		# courbure sur ±3 points (6 m de part et d'autre) : angle entre les deux directions / distance
		var i0 := maxi(i - 3, 0); var i1 := mini(i + 3, n - 1)
		var k := 0.0
		if i1 - i0 >= 2:
			var d0 := (p[i] - p[i0]).normalized(); var d1 := (p[i1] - p[i]).normalized()
			k = absf(d0.angle_to(d1)) / maxf(_s[i1] - _s[i0], 0.1)
		v[i] = minf(V_MAX, sqrt(A_LAT / maxf(k, 1e-4)))
	v[0] = 0.0
	for i in range(1, n):                     # accélération
		v[i] = minf(v[i], sqrt(v[i - 1] * v[i - 1] + 2.0 * A_ACC * (_s[i] - _s[i - 1])))
	for i in range(n - 2, -1, -1):            # freinage
		v[i] = minf(v[i], sqrt(v[i + 1] * v[i + 1] + 2.0 * A_FREIN * (_s[i + 1] - _s[i])))
	_tps[0] = 0.0
	for i in range(1, n):
		var vm := maxf((v[i - 1] + v[i]) * 0.5, 0.5)
		_tps[i] = _tps[i - 1] + (_s[i] - _s[i - 1]) / vm
	var k_t := temps_cible / maxf(_tps[n - 1], 0.1)        # même allure partout, arrivée au temps cible
	for i in n:
		_tps[i] *= k_t

## Position et cap à l'heure tt (fin du tracé : arrêté sur l'arrivée).
func _poser(tt: float) -> void:
	var n := _tps.size()
	if n < 2:
		return
	var i := clampi(_tps.bsearch(tt), 1, n - 1)
	var f := clampf((tt - _tps[i - 1]) / maxf(_tps[i] - _tps[i - 1], 1e-4), 0.0, 1.0)
	var q := _chemin[i - 1].lerp(_chemin[i], f)
	var s := lerpf(_s[i - 1], _s[i], f)
	var j := mini(i + 2, n - 1)
	var dir := (_chemin[j] - _chemin[maxi(i - 2, 0)]).normalized()
	var gauche := Vector2(dir.y, -dir.x)
	q += gauche * DECALE * clampf(1.0 - (s - 20.0) / 40.0, 0.0, 1.0)
	var av := q + dir * 1.3; var ar := q - dir * 1.3
	var y_av := Relief.hauteur(Vector3(av.x, 0, av.y)); var y_ar := Relief.hauteur(Vector3(ar.x, 0, ar.y))
	if is_nan(y_av) or is_nan(y_ar):
		return
	global_position = Vector3(q.x, (y_av + y_ar) * 0.5 + _r_roue - _y_roue, q.y)
	rotation = Vector3(atan2(y_av - y_ar, 2.6) * -1.0, atan2(dir.x, dir.y), 0.0)
	# roues : rotation selon la distance parcourue
	for r: Node3D in _roues:
		r.rotation.x = s / maxf(_r_roue, 0.1)

## Caisse et roues de la voiture du rival, en translucide tramé (pas de transparence mélangée, v6.19).
func _construire() -> void:
	var fiche: Dictionary = Voitures.CATALOGUE.get(voiture, Voitures.CATALOGUE[Voitures.DEPART])
	var dossier := String(fiche.dossier)
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dossier + "/meta.json"))
	# translucide par tramage (Bayer 4 × 4 + discard, comme les colonnes de lumière) : éclairé, bords plus pleins
	var mat := ShaderMaterial.new()
	mat.shader = Shader.new()
	mat.shader.code = """
shader_type spatial;
render_mode shadows_disabled;
uniform vec3 teinte : source_color = vec3(0.42, 0.68, 1.0);
void fragment() {
	float bord = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.0);
	ALBEDO = teinte * 0.6;
	EMISSION = teinte * (0.06 + 0.45 * bord);
	ROUGHNESS = 0.35;
	float couvre = 0.42 + 0.45 * bord;
	const float BAYER[16] = { 0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0 };
	if (couvre <= (BAYER[int(mod(FRAGCOORD.x, 4.0)) + int(mod(FRAGCOORD.y, 4.0)) * 4] + 0.5) / 16.0) {
		discard;
	}
}
"""
	_modele = Node3D.new()
	add_child(_modele)
	var body: Node3D = load(dossier + "/body.glb").instantiate()
	body.rotation.y = PI                    # modèle : avant vers -Z ; voiture du jeu : avant vers +Z
	_modele.add_child(body)
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).lod_bias = 64.0   # #130 : niveaux de détail de l'import déchirés (voir car.gd)
	_r_roue = float(meta.radius)
	_y_roue = _r_roue + 0.035 - 0.1         # centre des roues de car.gd, suspension tassée
	var wb := float(meta.wheelbase); var tr := float(meta.track)
	var scene: PackedScene = load(dossier + "/wheel.glb")
	if meta.has("roue_de"):
		scene = load(dossier.get_base_dir() + "/" + String(meta.roue_de) + "/wheel.glb")
	for i in 4:
		var front := i < 2
		var right := i % 2 == 0
		var pivot := Node3D.new()
		pivot.position = Vector3((-1.0 if right else 1.0) * tr / 2, _y_roue, (1.0 if front else -1.0) * wb / 2)
		var w: Node3D = scene.instantiate()
		w.rotation.y = 0.0 if right else PI
		pivot.add_child(w)
		_modele.add_child(pivot)
		_roues.append(pivot)
	for m in _modele.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).material_override = mat
		(m as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var l := Label3D.new()
	l.text = nom
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = 0.0018
	l.font_size = 40
	l.outline_size = 10
	l.modulate = Color(0.75, 0.92, 1.0)
	l.position = Vector3(0, 2.2, 0)
	add_child(l)

## Temps de passage à la distance s du départ (m), pour les écarts affichés.
func temps_a(s_: float) -> float:
	if not pret:
		return 0.0
	var i := clampi(_s.bsearch(s_), 1, _s.size() - 1)
	var f := clampf((s_ - _s[i - 1]) / maxf(_s[i] - _s[i - 1], 1e-4), 0.0, 1.0)
	return lerpf(_tps[i - 1], _tps[i], f)
