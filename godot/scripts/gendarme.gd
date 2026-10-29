## Gendarme (#150) : voiture de gendarmerie pilotée par le jeu (car.gd : mêmes physique et chocs que le joueur et les
## concurrents de course), rampe de gyrophares et sirène deux-tons.
## - « patrouille » : roule à l'allure de la route sur un itinéraire (itineraire.gd) vers un point proche du joueur ;
##   repart vers un autre point au bout du trajet ; gyrophares éteints.
## - « poursuite » : itinéraire recalculé toutes les REPLAN s vers la position du joueur (anticipée) ; à moins de DIRECT
##   m et en vue, fonce droit sur un point devant lui pour le percuter ou le coincer ; gyrophares et sirène.
## - « barrage » (3 étoiles) : arrêtée en travers de la route devant le joueur, gyrophares allumés, frein serré ;
##   repart en poursuite quand il est passé (gendarmes.gd).
## - « fuite » (activité « Gendarme », livree = false) : voiture ordinaire qui file à l'opposé du joueur ; « arret » :
##   immobilisée (gendarme_joueur.gd).
## - « repli » : la poursuite est finie : roule au pas puis disparaît hors de vue (gendarmes.gd).
## - Volant et pédales comme concurrent.gd (poursuite d'un point devant, vitesse visée d'après les virages à venir,
##   écart pour contourner la circulation, marche arrière quand la voiture est bloquée, remise sur la route).
## - Loin du joueur (plus de LOIN m : le relief n'a de collisions qu'à 96 m de la caméra) : figée, glisse sur
##   l'itinéraire (posée sur le relief) ; redevient physique en approchant (PRES m).
extends Node

const PerfMon := preload("res://scripts/perf_monitor.gd")

const Relief := preload("res://scripts/relief.gd")
const Car := preload("res://scripts/car.gd")
const PAS := 2.0                    # rééchantillonnage de l'itinéraire (m)
const LOIN := 85.0
const PRES := 70.0
const DIRECT := 45.0                # poursuite : droit sur le joueur en deçà (m), s'il est en vue
const ARRET := 6.0                  # joueur arrêté : le gendarme s'arrête à cette distance (interpellation)
const REPLAN := 2.0                 # poursuite : nouvel itinéraire toutes les REPLAN s
const A_LAT := 6.0                  # accélération latérale admise en virage (m/s²)
const VOIE := 2.2
const GYRO := 0.12                  # demi-période des éclats des gyrophares (s)
const FUITE_V := 0.85               # fuyard : part de sa vitesse maximale

var main: Node
const MODELE := "p306"              # voiture provisoire (#150 : choix A ou B en attente)
var modele := MODELE
var couleur := Color(0.1, 0.17, 0.42)
var mode := "patrouille"
var livree := true                  # false : voiture ordinaire (fuyard de l'activité « Gendarme »)
var voiture: Car
var fige := false
var cible := Vector2.ZERO           # bout de l'itinéraire en cours
var direct := false                 # poursuite : droit sur le joueur (essais)
var blown := false
var boum_t := 0.0                   # temps depuis l'explosion
var obstacle := ""                  # essais : ce qui cache le joueur (en_vue)
var age := 0.0                      # temps depuis l'arrivée (barrage)

var _itin
var _chemin := PackedVector2Array()
var _s := PackedFloat32Array()
var _v := PackedFloat32Array()
var _i := 0
var _off := 0.0
var _off_but := 0.0
var _replan_t := 0.0
var _bloque_t := 0.0
var _recul_t := 0.0
var _gyro: Array = []               # [MeshInstance3D, matériau] des feux de la rampe
var _gyro_t := 0.0
var _lueur: OmniLight3D
var _sirene: AudioStreamPlayer3D
var _vmax := 40.0
var _v_prec := Vector3.ZERO

func _ready() -> void:
	_itin = preload("res://scripts/itineraire.gd").new()
	voiture = Car.new()
	voiture.ia = true
	voiture.voiture = modele
	voiture.name = "Gendarme"
	main.add_child(voiture)
	voiture.contact_monitor = true
	voiture.max_contacts_reported = 4
	_vmax = float(voiture.vmax) / 3.6 * 0.95
	if livree:
		voiture.set_meta("gendarme", true)
		var h := habiller(voiture, couleur)
		_gyro = h.gyro; _lueur = h.lueur; _sirene = h.sirene
	if main.get("car"):
		voiture.set_lights(main.car.lights_on)

func _exit_tree() -> void:
	if is_instance_valid(voiture):
		voiture.queue_free()

## Livrée bleue : peinture « paint » de la carrosserie, ou carrosserie texturée (306 du garage) passée en niveaux de gris
## et teintée de `couleur` (détails, vitres et feux gardent leurs nuances).
const TEINTE := """shader_type spatial;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform vec3 teinte : source_color;
void fragment() {
	vec3 c = texture(tex, UV).rgb;
	float l = dot(c, vec3(0.3, 0.59, 0.11));
	ALBEDO = teinte * clamp(l * 2.4, 0.0, 1.6);
	ROUGHNESS = 0.35;
	METALLIC = 0.25;
}
"""

## Habille une voiture en gendarmerie (gendarmes de la poursuite, voiture du joueur dans l'activité « Gendarme ») :
## livrée bleue, rampe de gyrophares, lueur et sirène ; rend {gyro: [[MeshInstance3D, matériau]], lueur, sirene}.
static func habiller(v: Car, col: Color) -> Dictionary:
	_repeindre(v, col)
	return _rampe(v)

static func _repeindre(v: Car, col: Color) -> void:
	if v._paint_mat:
		v._paint_mat.albedo_color = col          # carrosserie « paint » (sans effet sinon)
	var corps: Node3D = v.get("_body")
	if corps == null:
		return
	var sh := Shader.new()
	sh.code = TEINTE
	var repeint := 0
	for mi in corps.find_children("*", "MeshInstance3D", true, false):
		var m3 := mi as MeshInstance3D
		for k in m3.mesh.get_surface_count():
			var m := m3.get_active_material(k) as BaseMaterial3D          # glTF : ORMMaterial3D
			if m and m.albedo_texture:
				var t := ShaderMaterial.new()
				t.shader = sh
				t.set_shader_parameter("tex", m.albedo_texture)
				t.set_shader_parameter("teinte", col)
				m3.set_surface_override_material(k, t)
				repeint += 1
	print("[gendarmes] livrée : %d surface(s) teintée(s)" % repeint)

## Haut de la carrosserie (repère de la voiture), d'après les boîtes des maillages ; gabarit à défaut.
static func _toit(v: Car) -> float:
	var corps: Node3D = v.get("_body")
	var h := -INF
	if corps:
		var inv := v.global_transform.affine_inverse()
		for mi in corps.find_children("*", "MeshInstance3D", true, false):
			var b: AABB = (inv * (mi as MeshInstance3D).global_transform) * (mi as MeshInstance3D).get_aabb()
			h = maxf(h, b.end.y)
	return h if is_finite(h) else v.gabarit.y

## Rampe de gyrophares sur le toit : deux feux bleus et un témoin blanc, matériaux sans ombrage (éclats visibles de
## loin, la nuit comme le jour), lueur bleue la nuit.
static func _rampe(v: Car) -> Dictionary:
	var gyro := []
	var g := v.gabarit
	var socle := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(minf(g.x * 0.62, 1.2), 0.1, 0.24)
	socle.mesh = bm
	var ms := StandardMaterial3D.new()
	ms.albedo_color = Color(0.85, 0.86, 0.9)
	socle.material_override = ms
	socle.position = Vector3(0, _toit(v) + 0.04, -g.z * 0.05)
	v.add_child(socle)
	for dx in [-1.0, 1.0]:
		var f := MeshInstance3D.new()
		var fm := BoxMesh.new()
		fm.size = Vector3(bm.size.x * 0.36, 0.12, 0.22)
		f.mesh = fm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.08, 0.15, 0.45)
		f.material_override = m
		f.position = socle.position + Vector3(dx * bm.size.x * 0.3, 0.05, 0)
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		v.add_child(f)
		gyro.append([f, m])
	var lueur := OmniLight3D.new()
	lueur.light_color = Color(0.25, 0.4, 1.0)
	lueur.omni_range = 14.0
	lueur.light_energy = 0.0
	lueur.shadow_enabled = false
	lueur.position = socle.position + Vector3(0, 0.4, 0)
	v.add_child(lueur)
	var sirene := AudioStreamPlayer3D.new()
	if ResourceLoader.exists("res://assets/sfx/sirene.ogg"):
		var st: AudioStream = (load("res://assets/sfx/sirene.ogg") as AudioStream).duplicate()
		if st is AudioStreamOggVorbis:
			(st as AudioStreamOggVorbis).loop = true
		sirene.stream = st
	sirene.unit_size = 18.0
	sirene.max_distance = 600.0
	sirene.volume_db = -2.0
	sirene.bus = "Monde"
	v.add_child(sirene)
	return {"gyro": gyro, "lueur": lueur, "sirene": sirene}

func voir_gyros(on: bool) -> void:
	if _sirene == null:
		return
	if on and _sirene.stream and not _sirene.playing:
		_sirene.play(randf() * 4.0)
	elif not on and _sirene.playing:
		_sirene.stop()
	if not on:
		for e in _gyro:
			(e[1] as StandardMaterial3D).albedo_color = Color(0.08, 0.15, 0.45)
		_lueur.light_energy = 0.0

func _gyros(dt: float) -> void:
	if mode != "poursuite" and mode != "barrage":
		return
	_gyro_t += dt
	clignoter(_gyro, _lueur, _gyro_t, main.get("car") != null and main.car.lights_on)

## Double éclat alterné gauche / droite des gyrophares à l'instant t ; lueur bleue la nuit.
static func clignoter(gyro: Array, lueur: OmniLight3D, t: float, nuit: bool) -> void:
	var ph := int(t / GYRO) % 8
	for j in mini(2, gyro.size()):
		var on := ph in ([0, 2] if j == 0 else [4, 6])
		(gyro[j][1] as StandardMaterial3D).albedo_color = Color(0.35, 0.55, 1.0) * 2.2 if on else Color(0.05, 0.08, 0.25)
	if lueur:
		lueur.light_energy = (2.5 if ph in [0, 2, 4, 6] else 0.0) if nuit else 0.0

## Place la voiture (figée) au point p, cap vers `vers`.
func poser(p: Vector2, vers: Vector2) -> void:
	var y := Relief.hauteur(Vector3(p.x, 0, p.y))
	if is_nan(y):
		y = main.car.global_position.y if main.get("car") else 0.0
	var d := (vers - p).normalized()
	voiture.place(Vector3(p.x, y + 0.3, p.y), rad_to_deg(atan2(d.x, -d.y)))
	_chemin = PackedVector2Array()
	_figer()

func aller(vers: Vector2) -> void:
	var p := voiture.global_position
	cible = vers
	_itin.calculer(Vector2(p.x, p.z), vers)

func _joueur() -> Node3D:
	if not main.get("car"):
		return null
	return main.gendarmes.cible() if main.get("gendarmes") else main.car

func _physics_process(dt: float) -> void:
	var t0 := Time.get_ticks_usec()
	_pas(dt)
	PerfMon.note("gendarmes", Time.get_ticks_usec() - t0)

func _pas(dt: float) -> void:
	if not is_instance_valid(voiture):
		return
	if blown:
		boum_t += dt
		return
	age += dt
	_itin.suivre()
	if _itin.pret:
		_itin.pret = false
		if _itin.route.size() >= 2:
			_prendre(_itin.route)
	var j := _joueur()
	if j == null:
		return
	_gyros(dt)
	var dj := voiture.global_position.distance_to(j.global_position)
	if mode == "poursuite":
		_replan_t -= dt
		if _replan_t <= 0.0 and not direct:
			_replan_t = REPLAN
			var pis: Array = main.gendarmes.piste()
			var q: Vector3 = pis[0] + (pis[1] as Vector3) * clampf(dj / 40.0, 0.5, 3.0)
			aller(Vector2(q.x, q.z))
	elif mode == "fuite":
		# activité « Gendarme » : le fuyard file à l'opposé du joueur, nouvel itinéraire toutes les 4 s ou au bout du chemin
		_replan_t -= dt
		if _replan_t <= 0.0 or _chemin.is_empty() or _i >= _chemin.size() - 6:
			_replan_t = 4.0
			var loin := voiture.global_position - j.global_position
			loin.y = 0.0
			if loin.length() < 1.0:
				loin = voiture.global_transform.basis.z
			var a := atan2(loin.z, loin.x) + randf_range(-0.6, 0.6)
			var q := voiture.global_position + Vector3(cos(a), 0.0, sin(a)) * 450.0
			aller(Vector2(q.x, q.z))
	elif mode == "patrouille" and (_chemin.is_empty() or _i >= _chemin.size() - 3) and _replan_t <= 0.0:
		_replan_t = 3.0
		var a := randf() * TAU
		var q := j.global_position + Vector3(cos(a), 0, sin(a)) * randf_range(80.0, 220.0)
		aller(Vector2(q.x, q.z))
	_replan_t -= dt if mode != "poursuite" else 0.0
	if fige:
		if dj < PRES:
			_degeler()
		else:
			_glisser(dt)
			return
	elif dj > LOIN:
		_figer()
		return
	if mode == "barrage" or mode == "arret":   # en travers de la route (ou fuyard immobilisé), frein serré
		voiture.touch_throttle = 0.0; voiture.touch_brake = 0.0; voiture.touch_steer = 0.0
		voiture.frein_parking = true
		_surveiller(dt)
		return
	voiture.frein_parking = false
	_suivre()
	_piloter(dt, j, dj)
	_surveiller(dt)

## Nouvel itinéraire : rééchantillonné tous les PAS m, vitesses limites des virages (A_LAT) et de la voiture, freinage
## avant les virages ; la voiture reprend au point le plus proche.
func _prendre(r: PackedVector2Array) -> void:
	var p := PackedVector2Array([r[0]])
	var reste := 0.0
	for k in range(1, r.size()):
		var a := r[k - 1]; var b := r[k]
		var l := a.distance_to(b)
		var u := PAS - reste
		while u <= l:
			p.append(a.lerp(b, u / l))
			u += PAS
		reste = l - (u - PAS)
	p.append(r[r.size() - 1])
	var n := p.size()
	_s.resize(n); _v.resize(n)
	_s[0] = 0.0
	for i in range(1, n):
		_s[i] = _s[i - 1] + p[i - 1].distance_to(p[i])
	var vm := _vmax if mode == "poursuite" else (_vmax * FUITE_V if mode == "fuite" else 14.0)
	for i in n:
		var i0 := maxi(i - 3, 0); var i1 := mini(i + 3, n - 1)
		var k := 0.0
		if i1 - i0 >= 2:
			var d0 := (p[i] - p[i0]).normalized(); var d1 := (p[i1] - p[i]).normalized()
			k = absf(d0.angle_to(d1)) / maxf(_s[i1] - _s[i0], 0.1)
		_v[i] = minf(vm, sqrt(A_LAT / maxf(k, 1e-4)))
	for i in range(n - 2, -1, -1):
		_v[i] = minf(_v[i], sqrt(_v[i + 1] * _v[i + 1] + 2.0 * 6.0 * (_s[i + 1] - _s[i])))
	_chemin = p
	_i = 0
	_suivre()

func _au(d: float) -> Array:
	var n := _s.size()
	if n < 2:
		var q := Vector2(voiture.global_position.x, voiture.global_position.z)
		return [q, Vector2(voiture.global_transform.basis.z.x, voiture.global_transform.basis.z.z).normalized(), 0.0]
	var i := clampi(_s.bsearch(d), 1, n - 1)
	var f := clampf((d - _s[i - 1]) / maxf(_s[i] - _s[i - 1], 1e-4), 0.0, 1.0)
	var dir := (_chemin[mini(i + 1, n - 1)] - _chemin[maxi(i - 2, 0)]).normalized()
	return [_chemin[i - 1].lerp(_chemin[i], f), dir, lerpf(_v[i - 1], _v[i], f)]

func _suivre() -> void:
	if _chemin.is_empty():
		return
	var p := Vector2(voiture.global_position.x, voiture.global_position.z)
	var bd := INF
	var bi := _i
	for i in range(maxi(_i - 5, 0), mini(_i + 40, _chemin.size())):
		var d := p.distance_squared_to(_chemin[i])
		if d < bd:
			bd = d; bi = i
	_i = bi

## Ligne de vue entre deux points (bâtiments, relief), à hauteur de toit.
func en_vue(a: Vector3, b: Vector3) -> bool:
	var w := voiture.get_world_3d()
	if w == null:
		return false
	var q := PhysicsRayQueryParameters3D.create(a + Vector3(0, 1.4, 0), b + Vector3(0, 1.0, 0))
	q.exclude = [voiture.get_rid()]
	if main.get("car"):
		q.exclude.append(main.car.get_rid())
	q.collide_with_areas = false
	var r := w.direct_space_state.intersect_ray(q)
	# une voiture (le joueur lui-même, la circulation) ne cache pas : seuls le décor et le relief comptent
	if r.is_empty() or r.collider is VehicleBody3D or (r.position as Vector3).distance_to(b) < 4.0:
		obstacle = ""
		return true
	obstacle = "%s à %.1f m" % [(r.collider as Node).get_path() if r.collider is Node else str(r.collider), (r.position as Vector3).distance_to(a)]
	return false

func _piloter(dt: float, j: Node3D, dj: float) -> void:
	var v := voiture.forward_speed()
	var xf := voiture.global_transform
	var s: float = _s[_i] if _i < _s.size() else 0.0
	var v_cible := 0.0
	var q: Vector2
	direct = mode == "poursuite" and dj < DIRECT and en_vue(xf.origin, j.global_position)
	if direct:
		# droit sur le joueur, en visant où il sera (moins loin quand on est tout près : on le percute)
		var jv: Vector3 = (j as RigidBody3D).linear_velocity if j is RigidBody3D else Vector3.ZERO
		var p := j.global_position + jv * clampf(dj / maxf(absf(v), 6.0), 0.0, 1.2)
		q = Vector2(p.x, p.z)
		if jv.length() < 4.0:
			# joueur arrêté ou au pas : on s'arrête à ARRET m de lui (interpellation, gendarmes.gd), sans l'emboutir
			v_cible = clampf((dj - ARRET) * 0.7, 0.0, 12.0)
		else:
			v_cible = minf(_vmax, jv.length() + 6.0 + dj * 0.3)
	elif _chemin.size() >= 2:
		v_cible = INF
		var d := 0.0
		while d <= maxf(v, 0.0) * 2.0 + 10.0:
			var va := float(_au(s + d)[2])
			v_cible = minf(v_cible, sqrt(va * va + 2.0 * 4.0 * maxf(d - maxf(v, 0.0) * 0.3, 0.0)))
			d += 2.0
		if _i >= _chemin.size() - 2:
			v_cible = 0.0
		var vise := clampf(4.0 + maxf(v, 0.0) * 0.45, 4.0, 22.0)
		var c: Array = _au(s + vise)
		q = c[0] + Vector2(c[1].y, -c[1].x) * _off
	else:
		q = Vector2(xf.origin.x, xf.origin.z) + Vector2(xf.basis.z.x, xf.basis.z.z) * 10.0
	if mode == "repli":
		v_cible = minf(v_cible, 8.0)
	# circulation : écart pour contourner une voiture lente ou arrêtée devant (pas le joueur en poursuite)
	var gene := false
	var circ = main.get("circulation")
	if circ and not direct:
		for tc in circ.voitures:
			var tp: Vector3 = tc.pos
			if (tp - xf.origin).length_squared() > 40.0 * 40.0:
				continue
			var l: Vector3 = xf.affine_inverse() * tp
			if l.z >= 3.0 and l.z < 14.0 + v * 0.8 and absf(l.x) < 2.3:
				var vo: float = ((tc.dir as Vector3) * float(tc.v)).dot(xf.basis.z)
				if vo < v - 0.5:
					gene = true
					_off_but = clampf(_off + (-VOIE if l.x > 0.0 else VOIE), -VOIE, VOIE)
					if l.z < 6.0 + v * 0.3 and absf(l.x) < 1.6:
						v_cible = minf(v_cible, maxf(vo - 1.0, 3.0))
	if not gene:
		_off_but = move_toward(_off_but, 0.0, dt * 0.5)
	_off = move_toward(_off, _off_but, dt * 1.6)
	var l := xf.affine_inverse() * Vector3(q.x, xf.origin.y, q.y)
	var alpha := atan2(l.x, l.z)
	var delta := atan2(2.0 * 2.5 * sin(alpha), maxf(Vector2(l.x, l.z).length(), 1.0))
	var recule := false
	if l.z < 0.5 and direct and Vector2(l.x, l.z).length() < 15.0:
		recule = true                         # joueur juste derrière (dépassé) : marche arrière vers lui
	elif l.z < 0.5:                           # point visé derrière : demi-tour au pas
		delta = signf(l.x) * PI
		v_cible = minf(v_cible, 5.0)
	var k := clampf(absf(v) * 3.6 / 130.0, 0.0, 1.0)
	var st := clampf(delta / lerpf(Car.STEER_LOW, Car.STEER_HIGH, sqrt(k)), -1.0, 1.0)
	var thr := 0.0
	var brk := 0.0
	var e := v_cible - v
	if recule:
		brk = 0.7 if dj > ARRET else 0.0; st = 0.0
	elif _recul_t > 0.0:
		_recul_t -= dt
		brk = 0.8; st = -st
	elif e > 0.3:
		thr = clampf(e * 0.3 + 0.1, 0.0, 1.0)
	elif e < -0.4:
		brk = clampf(-e * 0.6, 0.2, 1.0)
	voiture.touch_throttle = thr
	voiture.touch_brake = brk
	voiture.touch_steer = st

## Bloquée (marche arrière), retournée ou passée sous le relief : remise sur l'itinéraire.
func _surveiller(dt: float) -> void:
	var vel := voiture.linear_velocity
	var dv := (_v_prec - vel).length() * 3.6
	_v_prec = vel
	if dv > Car.VITESSE_BOUM and not voiture.get_colliding_bodies().is_empty():
		_exploser()
		return
	if not voiture.global_position.is_finite() or Relief.hauteur(voiture.global_position) - voiture.global_position.y > 4.0:
		_reposer()
		return
	if voiture.global_transform.basis.y.y < 0.5 and voiture.kmh() < 20.0:
		_bloque_t += dt * 3.0
	elif voiture.kmh() < 3.0 and voiture.touch_throttle > 0.3:
		_bloque_t += dt
		if _bloque_t > 1.5 and _bloque_t - dt <= 1.5:
			_recul_t = 1.4
	else:
		_bloque_t = 0.0
	if _bloque_t > 4.5:
		_reposer()

## KA-BOOM (#121, #129) comme les concurrents : champignon, la voiture disparaît ; gendarmes.gd la retire.
func _exploser() -> void:
	blown = true
	voir_gyros(false)
	var fx = preload("res://scripts/explosion.gd").new()
	fx.style = voiture.style_explosion
	fx.position = voiture.global_position - Vector3(0, 0.3, 0)
	main.add_child(fx)
	if main.get("sound") and main.sound.has_method("boum"):
		main.sound.boum(voiture.global_position)
	voiture.linear_velocity = Vector3.ZERO
	voiture.angular_velocity = Vector3.ZERO
	voiture.blow_up()
	if main.get("gendarmes"):
		main.gendarmes.detruit(self)

func _reposer() -> void:
	var c: Array = _au((_s[_i] if _i < _s.size() else 0.0) + 4.0)
	var q: Vector2 = c[0]
	var y := Relief.hauteur(Vector3(q.x, 0, q.y))
	if is_nan(y):
		y = voiture.global_position.y
	voiture.place(Vector3(q.x, y + 0.3, q.y), rad_to_deg(atan2(c[1].x, -c[1].y)))
	voiture.hold(0.4)
	_bloque_t = 0.0; _recul_t = 0.0; _off = 0.0; _off_but = 0.0
	_v_prec = Vector3.ZERO

func _figer() -> void:
	fige = true
	voiture.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	voiture.freeze = true

## Figée : avance sur l'itinéraire à l'allure du profil (posée sur le relief).
func _glisser(dt: float) -> void:
	if _chemin.size() < 2:
		return
	var s := _s[_i]
	var v: float = maxf(float(_au(s)[2]), 4.0) * (0.5 if mode == "repli" else 1.0)
	s = minf(s + v * dt, _s[_s.size() - 1])
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
	var c: Array = _au(_s[_i] if _i < _s.size() else 0.0)
	voiture.linear_velocity = Vector3(c[1].x, 0.0, c[1].y) * float(c[2])
	_v_prec = voiture.linear_velocity
