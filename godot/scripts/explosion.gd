## Explosion de la voiture (#129, à la place du champignon façon dessin animé de #121) : boules de feu, fumée et
## poussière tirées de vraies simulations (planches d'images CC0 de Unity Labs, explosion.gdshader), éclair, lueur sur
## le décor, débris, étincelles et secousse de la caméra. Trois styles :
##   « film »     explosion de cinéma (boule de feu qui s'éteint en fumée noire, poussière au sol), 1,8 s ;
##   « mini »     petit champignon (boule de feu qui monte en chapeau sur un pied de fumée, onde de poussière), 2,2 s ;
##   « atomique » grand champignon, anneau de condensation et souffle au ras du sol, 2,8 s.
## Une bouffée = une recette (départ, durée, trajet, taille, images de l'animation, opacité, teinte) évaluée à chaque
## image ; tout est dessiné en trois MultiMesh (un par planche), sans rien créer pendant l'effet. Temps réglable à la
## main (`auto = false` + `regler(t)`) pour les captures de l'essai --explosion-test.
extends Node3D

const Relief := preload("res://scripts/relief.gd")
const PLANCHES := {   # nom -> [texture, images par côté, images de l'animation, densité]
	"a": ["res://assets/fx/explosion_a.png", 5, 25, 0.85],   # boule de feu ronde -> fumée noire
	"b": ["res://assets/fx/explosion_b.png", 5, 25, 0.85],   # boule de feu déchiquetée
	"p": ["res://assets/fx/fumee_boule.png", 8, 64, 0.6],    # bouffée grise qui tourne sur elle-même
}
const DUREES := {"film": 1.8, "mini": 2.2, "atomique": 2.8}
const BLANC := Color(1, 1, 1, 1)                       # teinte neutre, feu gardé
const GRIS_CHAUD := Color(0.72, 0.69, 0.66, 1)
const CHAPEAU := Color(2.4, 2.05, 1.75, 1)             # fumée du champignon éclaircie : gris brun au lieu de noir
const POUSSIERE := Color(1.2, 1.06, 0.88, 0)           # sur la bouffée grise (~0,52) : terre beige
const POUSSIERE_FIN := Color(1.05, 1.0, 0.94, 0)
const FUMEE_NOIRE := Color(0.42, 0.4, 0.38, 0)
const PIED_CHAUD := Color(1.6, 1.0, 0.6, 0)            # pied du champignon éclairé par la boule de feu
const PIED_FROID := Color(1.05, 0.98, 0.9, 0)

var style := "film"
var temps := 0.0
var auto := true                  # faux : le temps n'avance que par regler() (essais)
var graine := -1                  # >= 0 : tirage fixe (captures comparables)
var duree := 1.8

var _recettes := {}               # planche -> [recette…]
var _mm := {}                     # planche -> MultiMesh
var _mats := {}                   # planche -> ShaderMaterial
var _debris := []                 # [p0, v, t0, vie, taille, axe, vitesse de rotation]
var _etinc := []                  # [p0, v, t0, vie]
var _mm_debris: MultiMesh
var _mm_etinc: MultiMesh
var _lampe: OmniLight3D
var _lampe_max := 6.0
var _lampe_vie := 0.5
var _onde: MeshInstance3D         # anneau de condensation (atomique)
var _onde_mat: ShaderMaterial
var _sol := -0.2                  # hauteur du sol sous le centre (repère local)
var _secousse := 0.7
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	duree = DUREES.get(style, 1.8)
	if graine >= 0:
		_rng.seed = graine
	else:
		_rng.randomize()
	var g := global_position
	var h := Relief.hauteur(g)
	if is_finite(h) and absf(h - g.y) < 4.0:
		_sol = h - g.y
	var pie = get_parent().get("pietons")         # v6.90 : les passants proches s'enfuient
	if pie and pie.has_method("panique"):
		pie.panique(g)
	for nom in PLANCHES:
		_recettes[nom] = []
	match style:
		"mini": _champignon(1.0, false)
		"atomique": _champignon(2.0, true)
		_: _film()
	for nom in PLANCHES:
		var l: Array = _recettes[nom]
		if l.is_empty():
			continue
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://scripts/explosion.gdshader")
		mat.set_shader_parameter("planche", load(PLANCHES[nom][0]))
		mat.set_shader_parameter("grille", float(PLANCHES[nom][1]))
		mat.set_shader_parameter("nb", float(PLANCHES[nom][2]))
		mat.set_shader_parameter("densite", float(PLANCHES[nom][3]))
		var qm := QuadMesh.new()
		qm.material = mat
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = qm
		mm.instance_count = l.size()
		mm.visible_instance_count = 0
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.custom_aabb = AABB(Vector3(-40, -10, -40), Vector3(80, 70, 80))
		add_child(mi)
		_mm[nom] = mm
		_mats[nom] = mat
	_mm_debris = _lot(_debris.size(), _mat_debris())
	_mm_etinc = _lot(_etinc.size(), _mat_etinc())
	if int(Engine.get_meta("niveau_perf", 1)) == 0:
		_lampe_max = 0.0                 # Économie (#124) : pas de vraie lampe, le feu garde son propre éclat
	_lampe = OmniLight3D.new()
	_lampe.light_color = Color(1.0, 0.62, 0.3)
	_lampe.omni_range = 12.0 * sqrt(maxf(_lampe_max, 1.0))
	_lampe.shadow_enabled = false
	_lampe.position = Vector3(0, 2.0, 0)
	add_child(_lampe)
	var m := get_parent()
	if m and m.get("cam_rig") and auto:
		# #128 : explosion d'un concurrent au loin : secousse moindre (pleine jusqu'à 30 m, nulle à 230 m)
		var d: float = (m.cam_rig.cam as Camera3D).global_position.distance_to(global_position) if m.cam_rig.get("cam") else 0.0
		m.cam_rig.shake = maxf(float(m.cam_rig.shake), _secousse * clampf(1.0 - (d - 30.0) / 200.0, 0.0, 1.0))
	regler(0.0)

func _process(dt: float) -> void:
	if not auto:
		return
	temps += dt
	if temps >= duree:
		queue_free()
		return
	regler(temps)

# ---------------------------------------------------------------- recettes

## Une bouffée : planche, départ et durée (s), trajet p0 -> p1 (rapide puis ralenti, exposant k), taille s0 -> s1 (m),
## images de l'animation a0 -> a1 (0 … 1), opacité maximale, part de la vie en fondu d'entrée et de sortie, teinte
## c0 -> c1 (alpha = part de feu), rotation initiale et vitesse de rotation (rad, rad/s).
func _b(pl: String, t0: float, d: float, p0: Vector3, p1: Vector3, k: float, s0: float, s1: float, a0: float, a1: float,
		op: float, fin: float, fout: float, c0: Color, c1: Color, rv := 0.0) -> void:
	_recettes[pl].append({t0 = t0, d = d, p0 = p0, p1 = p1, k = k, s0 = s0, s1 = s1, a0 = a0, a1 = a1, op = op,
		fin = fin, fout = fout, c0 = c0, c1 = c1, r0 = _rng.randf() * TAU, rv = rv})

func _hasard_plat(r: float) -> Vector3:
	var a := _rng.randf() * TAU
	return Vector3(cos(a), 0.0, sin(a)) * r * sqrt(_rng.randf())

## Explosion de cinéma : éclair, trois boules de feu qui s'éteignent en fumée noire, anneau de poussière au sol.
func _film() -> void:
	_b("a", 0.0, 0.14, Vector3(0, 1.2, 0), Vector3(0, 1.6, 0), 2.0, 5.0, 9.0, 0.0, 0.04, 1.0, 0.05, 0.6, BLANC, BLANC)
	for i in 3:
		var d := _hasard_plat(1.1)
		_b("a", 0.03 * i, 1.7, d + Vector3(0, 1.3, 0), d * 1.4 + Vector3(0, 3.4 + i * 0.4, 0), 2.0, 7.5 - i, 11.0 - i,
			0.0, 1.0, 1.0, 0.02, 0.3, BLANC, GRIS_CHAUD, _rng.randf_range(-0.4, 0.4))
	for i in 2:
		var d := _hasard_plat(1.6)
		_b("b", 0.08 + 0.05 * i, 1.4, d + Vector3(0, 0.8, 0), d * 1.6 + Vector3(0, 2.2, 0), 2.0, 5.0, 8.0, 0.0, 1.0, 1.0,
			0.03, 0.35, BLANC, GRIS_CHAUD, _rng.randf_range(-0.5, 0.5))
	_jupe(12, 1.5, Vector2(8.0, 11.0), 0.03, 1.5, 2.5, Vector2(5.0, 6.5), 3.0, 1.0)
	for i in 3:
		var d := _hasard_plat(1.5)
		_b("p", 0.6 + 0.1 * i, 1.15, d + Vector3(0, 2.5, 0), d * 2.0 + Vector3(0, 6.5 + i, 0), 1.6, 4.0, 7.0,
			_rng.randf() * 0.5, _rng.randf() * 0.5 + 0.4, 0.85, 0.25, 0.5, FUMEE_NOIRE, FUMEE_NOIRE.lightened(0.1),
			_rng.randf_range(-0.3, 0.3))
	_projections(14, 1.0, 1.7)
	_lampe_max = 7.0
	_lampe_vie = 0.55
	_secousse = 0.7

## Champignon : boule de feu qui monte et devient le cœur du chapeau, couronne de boules qui roulent autour, pied de
## fumée éclairé par le feu, onde de poussière ; « atomique » : deux fois plus grand, anneau de condensation (nuage de
## Wilson) et souffle au ras du sol.
func _champignon(e: float, atome: bool) -> void:
	var dm := duree - 0.2
	var H := 10.0 * e
	_b("a", 0.0, 0.16, Vector3(0, 1.5 * e, 0), Vector3(0, 2.0 * e, 0), 2.0, 6.0 * e, 11.0 * e, 0.0, 0.04, 1.0, 0.05, 0.6, BLANC, BLANC)
	for i in 2:
		var d := _hasard_plat(0.5 * e)
		_b("a", 0.02 * i, dm, d + Vector3(0, 1.6 * e, 0), d + Vector3(0, H, 0), 1.7, 6.5 * e, 10.5 * e, 0.0, 1.0, 1.0,
			0.02, 0.3, BLANC, CHAPEAU, _rng.randf_range(-0.3, 0.3))
	var nc := 10 if atome else 7
	for i in nc:
		var ang := TAU * float(i) / nc + _rng.randf() * 0.3
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		_b("b", 0.06 + _rng.randf() * 0.08, dm - 0.1, dir * 1.2 * e + Vector3(0, 2.0 * e, 0),
			dir * _rng.randf_range(3.8, 4.6) * e + Vector3(0, H + _rng.randf_range(-1.2, 0.0) * e, 0), 1.7, 3.5 * e, 6.5 * e,
			0.0, 1.0, 1.0, 0.03, 0.3, BLANC, CHAPEAU, _rng.randf_range(-0.8, 0.8))
	_b("b", 0.1, dm - 0.1, Vector3(0, 2.4 * e, 0), Vector3(0, H + 1.8 * e, 0), 1.7, 4.0 * e, 7.5 * e, 0.0, 1.0, 1.0,
		0.03, 0.3, BLANC, CHAPEAU, _rng.randf_range(-0.4, 0.4))
	var np := 8 if atome else 5
	for i in np:
		var f := (i + 0.5) / np
		var d := _hasard_plat(0.4 * e)
		var a0 := _rng.randf() * 0.5
		_b("p", 0.1 + 0.04 * i, dm - 0.1, d + Vector3(0, 0.8 * e, 0), d * 0.5 + Vector3(0, H * f * 0.92, 0), 1.7,
			2.2 * e, (3.4 + 0.8 * (1.0 - f)) * e, a0, a0 + 0.4, 1.0, 0.08, 0.3, PIED_CHAUD, PIED_FROID,
			_rng.randf_range(-0.5, 0.5))
	_jupe(22 if atome else 14, 1.5 * e, Vector2(11.0, 14.0) * e, 0.05, dm, 3.0 * e, Vector2(6.0, 7.5) * e, 3.0, 1.0)
	if atome:
		# souffle au ras du sol, plus rapide et plus loin que la jupe
		_jupe(18, 2.0, Vector2(26.0, 32.0), 0.0, 1.1, 2.0, Vector2(4.5, 6.0), 4.0, 0.8)
		var sm := SphereMesh.new()
		sm.radius = 1.0; sm.height = 2.0; sm.radial_segments = 32; sm.rings = 16
		_onde_mat = ShaderMaterial.new()
		_onde_mat.shader = Shader.new()
		_onde_mat.shader.code = ONDE_SHADER
		sm.material = _onde_mat
		_onde = MeshInstance3D.new()
		_onde.mesh = sm
		_onde.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_onde)
	_projections(26 if atome else 16, sqrt(e), dm)
	_lampe_max = 14.0 if atome else 8.0
	_lampe_vie = 0.9 if atome else 0.6
	_secousse = 1.6 if atome else 1.0

## Anneau de poussière qui s'étale au sol : n bouffées, rayon r0 -> [r1 min, max], taille s0 -> [s1 min, max].
func _jupe(n: int, r0: float, r1: Vector2, t0: float, d: float, s0: float, s1: Vector2, k: float, op: float) -> void:
	for i in n:
		var ang := TAU * (i + _rng.randf() * 0.6) / n
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var a0 := _rng.randf() * 0.5
		_b("p", t0 + _rng.randf() * 0.04, d, dir * r0 + Vector3(0, _sol + s0 * 0.3, 0),
			dir * _rng.randf_range(r1.x, r1.y) + Vector3(0, _sol + s1.x * 0.32, 0), k, s0,
			_rng.randf_range(s1.x, s1.y), a0, a0 + 0.4, op, 0.04, 0.6, POUSSIERE, POUSSIERE_FIN, _rng.randf_range(-0.6, 0.6))

## Débris (morceaux sombres qui retombent) et étincelles (traits orange rapides).
func _projections(n: int, f: float, vie: float) -> void:
	for i in n:
		var v := _hasard_plat(1.0).normalized() * _rng.randf_range(5.0, 13.0) * f + Vector3(0, _rng.randf_range(5.0, 13.0) * f, 0)
		_debris.append([Vector3(0, 0.8, 0) + _hasard_plat(0.8), v, _rng.randf() * 0.05, vie * _rng.randf_range(0.8, 1.0),
			_rng.randf_range(0.08, 0.28) * sqrt(f), Vector3(_rng.randf() - 0.5, _rng.randf() - 0.5, _rng.randf() - 0.5).normalized(),
			_rng.randf_range(4.0, 12.0)])
	for i in n:
		var v := _hasard_plat(1.0).normalized() * _rng.randf_range(8.0, 20.0) * f + Vector3(0, _rng.randf_range(4.0, 16.0) * f, 0)
		_etinc.append([Vector3(0, 1.0, 0) + _hasard_plat(0.6), v, _rng.randf() * 0.1, _rng.randf_range(0.35, 0.9)])

const ONDE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back;
uniform float opacite = 0.0;
void fragment() {
	// coque de vapeur : visible surtout sur les bords (vue rasante), tramée
	float bord = pow(1.0 - abs(dot(NORMAL, VIEW)), 4.0);
	ALBEDO = vec3(0.93, 0.95, 0.98);
	const float BAYER[16] = { 0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0 };
	if (bord * opacite <= (BAYER[int(mod(FRAGCOORD.x, 4.0)) + int(mod(FRAGCOORD.y, 4.0)) * 4] + 0.5) / 16.0) {
		discard;
	}
}
"""

func _mat_debris() -> Material:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.1, 0.09, 0.085)
	m.roughness = 0.8
	m.metallic = 0.3
	return m

func _mat_etinc() -> Material:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.78, 0.4)
	return m

func _lot(n: int, mat: Material) -> MultiMesh:
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	bm.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = bm
	mm.instance_count = n
	mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-40, -10, -40), Vector3(80, 70, 80))
	add_child(mi)
	return mm

# ---------------------------------------------------------------- évaluation à l'instant t

func regler(t: float) -> void:
	temps = t
	# lumière de la boule de feu : pic tout de suite, puis s'éteint
	var lu := clampf(t / 0.03, 0.0, 1.0) * pow(clampf(1.0 - t / _lampe_vie, 0.0, 1.0), 1.5)
	_lampe.light_energy = _lampe_max * lu
	_lampe.visible = lu > 0.01 and _lampe_max > 0.0
	# lumière du moment sur la fumée : soleil et ciel de main.gd, plus la lueur du feu
	var lum := Vector3(1.05, 1.08, 1.1)
	var m := get_parent()
	if m and m.get("_sun"):
		var sun: DirectionalLight3D = m._sun
		var e := clampf(sun.light_energy, 0.0, 1.6)
		lum = Vector3(0.45, 0.5, 0.58) * clampf(0.35 + e * 0.5, 0.25, 1.0) + Vector3(sun.light_color.r, sun.light_color.g, sun.light_color.b) * e * 0.45
	lum += Vector3(1.0, 0.55, 0.25) * lu * 0.6
	for nom in _mm:
		_mats[nom].set_shader_parameter("lumiere", lum)
		var l: Array = _recettes[nom]
		var mm: MultiMesh = _mm[nom]
		var buf := PackedFloat32Array()
		buf.resize(l.size() * 20)
		var k := 0
		for r in l:
			var u: float = (t - r.t0) / r.d
			if u < 0.0 or u >= 1.0:
				continue
			var p: Vector3 = (r.p0 as Vector3).lerp(r.p1, 1.0 - pow(1.0 - u, r.k))
			var s: float = lerpf(r.s0, r.s1, 1.0 - pow(1.0 - u, 2.0))
			var op: float = r.op * clampf(u / maxf(r.fin, 0.001), 0.0, 1.0) * clampf((1.0 - u) / maxf(r.fout, 0.001), 0.0, 1.0)
			var c: Color = (r.c0 as Color).lerp(r.c1, smoothstep(0.0, 1.0, u))
			var o := k * 20
			buf[o] = 1.0; buf[o + 3] = p.x
			buf[o + 5] = 1.0; buf[o + 7] = p.y
			buf[o + 10] = 1.0; buf[o + 11] = p.z
			buf[o + 12] = c.r; buf[o + 13] = c.g; buf[o + 14] = c.b; buf[o + 15] = c.a
			buf[o + 16] = s; buf[o + 17] = r.r0 + r.rv * (t - r.t0); buf[o + 18] = lerpf(r.a0, r.a1, u); buf[o + 19] = op
			k += 1
		mm.buffer = buf
		mm.visible_instance_count = k
	_maj_projections(t)
	if _onde:
		var u := clampf(t / 0.45, 0.0, 1.0)
		var r := lerpf(3.0, 26.0, 1.0 - pow(1.0 - u, 2.0))
		_onde.scale = Vector3(r, r * 0.8, r)
		_onde.position = Vector3(0, 6.0, 0)
		_onde.visible = t < 0.45
		_onde_mat.set_shader_parameter("opacite", 0.6 * (1.0 - u))

func _maj_projections(t: float) -> void:
	const G := Vector3(0, -9.8, 0)
	var buf := PackedFloat32Array()
	buf.resize(_debris.size() * 12)
	var k := 0
	for d in _debris:
		var a: float = t - d[2]
		if a < 0.0 or a >= d[3]:
			continue
		var p: Vector3 = d[0] + d[1] * a + G * (0.5 * a * a)
		p.y = maxf(p.y, _sol + d[4] * 0.5)
		var fin := clampf((d[3] - a) / (d[3] * 0.2), 0.0, 1.0)
		var b := Basis(d[5], d[6] * a).scaled(Vector3.ONE * d[4] * fin)
		_poser(buf, k * 12, b, p)
		k += 1
	_mm_debris.buffer = buf
	_mm_debris.visible_instance_count = k
	var be := PackedFloat32Array()
	be.resize(_etinc.size() * 12)
	k = 0
	for d in _etinc:
		var a: float = t - d[2]
		if a < 0.0 or a >= d[3]:
			continue
		var v: Vector3 = d[1] + G * a
		var p: Vector3 = d[0] + d[1] * a + G * (0.5 * a * a)
		if p.y < _sol:
			continue
		var z := v.normalized()
		var x := z.cross(Vector3.UP if absf(z.y) < 0.98 else Vector3.RIGHT).normalized()
		var y := z.cross(x)
		var long := clampf(v.length() * 0.025, 0.08, 0.5) * clampf((d[3] - a) / (d[3] * 0.3), 0.0, 1.0)
		_poser(be, k * 12, Basis(x * 0.035, y * 0.035, z * long), p)
		k += 1
	_mm_etinc.buffer = be
	_mm_etinc.visible_instance_count = k

static func _poser(buf: PackedFloat32Array, o: int, b: Basis, p: Vector3) -> void:
	buf[o] = b.x.x; buf[o + 1] = b.y.x; buf[o + 2] = b.z.x; buf[o + 3] = p.x
	buf[o + 4] = b.x.y; buf[o + 5] = b.y.y; buf[o + 6] = b.z.y; buf[o + 7] = p.y
	buf[o + 8] = b.x.z; buf[o + 9] = b.y.z; buf[o + 10] = b.z.z; buf[o + 11] = p.z
