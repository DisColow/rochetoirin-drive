## Radars (#182, hypothèses validées par l'utilisateur le 07/11) :
## - radars fixes sur les routes limitées à 70 km/h et plus, un tous les ESPACE m en moyenne (circulation.points_radar),
##   panneau « Contrôles radar fréquents » ANNONCE m avant dans chaque sens ; au-delà de la limite + TOLERANCE : flash,
##   bip et amende (AMENDES) ; ⚙ > Conduite > Radars (`conduite/radars`) ;
## - contrôles des gendarmes au radar mobile : de temps en temps (MOBILE_T), une Gendarmerette garée au bord d'une route
##   rapide MOBILE_D m devant, radar sur trépied derrière elle ; au-delà de + WANTED km/h, recherche (1 étoile, 2 au-delà
##   de + WANTED2) ; en dessous, flash et amende comme un radar fixe. Avec les gendarmes (⚙ > Conduite > Gendarmes).
## Seulement au volant, en balade libre, en taxi ou en livraison (pas en course, ni en service de gendarme ou de bus).
## Modèles : assets/props/radar_fixe.glb et radar_mobile.glb s'ils existent, sinon modèles simples faits ici.
extends Node3D
const PerfMon := preload("res://scripts/perf_monitor.gd")
const Zone := preload("res://scripts/zone.gd")
const Relief := preload("res://scripts/relief.gd")
const Gendarme := preload("res://scripts/gendarme.gd")

const ESPACE := 3000.0
const V_MIN := 69.0                 # km/h : routes limitées à 70 et plus
const ANNONCE := 200.0
const TOLERANCE := 5.0
const AMENDES := [[20.0, 45.0], [50.0, 90.0], [INF, 135.0]]      # [excès jusqu'à (km/h), amende (€)]
const CASE := 256.0
const VUE := 650.0                  # modèles posés à cette distance
const R_DETECTE := 40.0
const MOBILE_T := Vector2(150.0, 300.0)
const MOBILE_D := Vector2(330.0, 420.0)
const WANTED := 30.0
const WANTED2 := 50.0
const MODES := ["", "taxi", "livreur"]

var main: Node
var actif := true
var radars: Array = []              # {axe, t (Vector2), bord, lim, double, poste (Vector3), noeuds: Array}
var _grille := {}
var _s := {}                        # radar -> abscisse le long de la route au pas d'avant
var _vu := {}                       # radar -> heure du dernier flash
var _pose := {}                     # radar -> true (modèles posés)
var _t_pose := 0.0
var _flash: ColorRect
var _flash_t := 0.0
var _lampe: OmniLight3D
var _lampe_t := 0.0
var _mobile_t := 0.0
var mobile := {}                    # contrôle mobile en cours : {g, r (radar), noeuds}
var flashs := 0                     # essais
var _prete := false

func _ready() -> void:
	var cfg := ConfigFile.new()
	cfg.load("user://reglages.cfg")
	actif = bool(cfg.get_value("conduite", "radars", true))
	_mobile_t = randf_range(MOBILE_T.x, MOBILE_T.y)
	var couche := CanvasLayer.new()
	couche.layer = 105
	add_child(couche)
	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(1, 1, 1, 0)
	_flash.visible = false
	couche.add_child(_flash)
	_lampe = OmniLight3D.new()
	_lampe.light_color = Color(0.92, 0.95, 1.0)
	_lampe.omni_range = 30.0
	_lampe.light_energy = 0.0
	_lampe.visible = false
	add_child(_lampe)

func _preparer() -> void:
	var circ = main.get("circulation")
	if circ == null or not circ.ok:
		return
	_prete = true
	for r in circ.points_radar(ESPACE, V_MIN):
		var axe: Vector3 = r[0]
		var t: Vector2 = r[1]
		var droite := Vector3(-t.y, 0.0, t.x)
		var poste := axe + droite * (float(r[2]) + 2.2)
		if not Zone.dedans(Vector2(poste.x, poste.z), 80.0):
			continue
		# poteau trop près d'une autre route (carrefour, bretelle) : pas de radar ici
		var vp: Array = circ.voie_proche(poste, 6.0)
		if (vp[1] as Vector3) != Vector3.ZERO and Vector2(vp[0].x - poste.x, vp[0].z - poste.z).length() < float(r[2]) - 0.5:
			continue
		var d := {"axe": axe, "t": t, "bord": float(r[2]), "lim": float(r[3]), "double": bool(r[4]), "poste": poste, "noeuds": []}
		var i := radars.size()
		radars.append(d)
		var c := Vector2i(floori(axe.x / CASE), floori(axe.z / CASE))
		if not _grille.has(c):
			_grille[c] = []
		_grille[c].append(i)
	print("[radars] %d radars fixes" % radars.size())

func set_actif(on: bool) -> void:
	actif = on
	for i in _pose.keys():
		for n in radars[i].noeuds:
			if is_instance_valid(n):
				n.visible = on

func _physics_process(dt: float) -> void:
	var t0 := Time.get_ticks_usec()
	_pas(dt)
	PerfMon.note("radars", Time.get_ticks_usec() - t0)

func _process(dt: float) -> void:
	if _flash_t > 0.0:
		_flash_t -= dt
		_flash.color.a = clampf(_flash_t / 0.35, 0.0, 1.0) * 0.85
		_flash.visible = _flash_t > 0.0
	if _lampe_t > 0.0:
		_lampe_t -= dt
		_lampe.light_energy = 9.0 if _lampe_t > 0.0 else 0.0
		_lampe.visible = _lampe_t > 0.0

func _au_volant() -> bool:
	var car = main.get("car")
	if car == null or car.blown or car.carried or not car.controle or car.get("ia"):
		return false
	var pd = main.get("pied")
	if pd and pd.get("actif"):
		return false
	var act = main.get("activities")
	return act == null or str(act.mode) in MODES

func _pas(dt: float) -> void:
	if not _prete:
		_preparer()
		if not _prete:
			return
	var car = main.get("car")
	if car == null:
		return
	var p: Vector3 = car.global_position
	_t_pose -= dt
	if _t_pose <= 0.0:
		_t_pose = 0.5
		_poser_autour(p)
		_mobile_menage(p)
	if not actif:
		return
	var ok := _au_volant()
	var kmh: float = car.kmh()
	var c := Vector2i(floori(p.x / CASE), floori(p.z / CASE))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for i: int in _grille.get(c + Vector2i(dx, dz), []):
				_passage(i, radars[i], p, kmh, ok, false)
	if not mobile.is_empty():
		_passage(-1, mobile.r, p, kmh, ok, true)
	_mobile_lancer(dt, car, p, ok)

## Passage devant un radar : la voiture franchit la ligne du radar (abscisse le long de la route qui change de signe)
## près de la chaussée.
func _passage(i: int, r: Dictionary, p: Vector3, kmh: float, ok: bool, est_mobile: bool) -> void:
	var axe: Vector3 = r.axe
	var q := Vector2(p.x - axe.x, p.z - axe.z)
	if q.length() > R_DETECTE:
		_s.erase(i)
		return
	var t: Vector2 = r.t
	var s := q.dot(t)
	var lat := absf(q.dot(Vector2(-t.y, t.x)))
	var avant = _s.get(i)
	_s[i] = s
	if avant == null or signf(float(avant)) == signf(s) or lat > float(r.bord) + 6.0 or not ok:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_vu.get(i, -100.0)) < 5.0:
		return
	_vu[i] = now
	var exces := kmh - float(r.lim)
	if OS.get_cmdline_user_args().has("--radars-debug"):
		print("[radars] passage %s à %.0f km/h (limite %.0f)" % ["mobile" if est_mobile else "fixe n° %d" % i, kmh, r.lim])
	if exces <= TOLERANCE:
		return
	_flasher(r.poste)
	var gd = main.get("gendarmes")
	if est_mobile and exces > WANTED and gd and gd.actif:
		gd.infraction("radar", p, 2 if exces > WANTED2 else 1)
		main.get_node("HUD").toast("Flashé à %d km/h (limite %d) : les gendarmes vous prennent en chasse !" % [int(kmh), int(r.lim)], 4.0)
		return
	var montant := 0.0
	for a in AMENDES:
		if exces <= float(a[0]):
			montant = float(a[1])
			break
	var g = main.get("garage")
	var paye: float = g.payer(montant) if g else 0.0
	main.get_node("HUD").toast("Flashé à %d km/h (limite %d) : −%d €" % [int(kmh), int(r.lim), int(paye)], 4.0)
	print("[radars] flash à %.0f km/h (limite %.0f) : amende %.0f €" % [kmh, r.lim, paye])

func _flasher(poste: Vector3) -> void:
	flashs += 1
	_flash_t = 0.35
	_flash.color.a = 0.85
	_flash.visible = true
	_lampe.global_position = poste + Vector3(0.0, 2.6, 0.0)
	_lampe_t = 0.12
	var s = main.get("sound")
	if s and s.has_method("_one_shot"):
		s._one_shot("bip", poste, 1.4, 1.5, 20.0, 300.0)

# ---------------------------------------------------------------- modèles
func _poser_autour(p: Vector3) -> void:
	var c := Vector2i(floori(p.x / CASE), floori(p.z / CASE))
	var r := int(ceil(VUE / CASE))
	var voulus := {}
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			for i: int in _grille.get(c + Vector2i(dx, dz), []):
				if Vector2(radars[i].axe.x - p.x, radars[i].axe.z - p.z).length() < VUE:
					voulus[i] = true
	for i in _pose.keys():
		if not voulus.has(i):
			for n in radars[i].noeuds:
				if is_instance_valid(n):
					n.queue_free()
			radars[i].noeuds = []
			_pose.erase(i)
	for i in voulus:
		if not _pose.has(i):
			_pose[i] = true
			_poser(radars[i])

func _poser(r: Dictionary) -> void:
	var t: Vector2 = r.t
	var droite := Vector3(-t.y, 0.0, t.x)
	var dir3 := Vector3(t.x, 0.0, t.y)
	var n := _cabine()
	add_child(n)
	var poste: Vector3 = r.poste
	poste.y = _sol(poste)
	n.global_position = poste
	n.look_at(poste + dir3, Vector3.UP)       # -Z vers l'aval : la face (+Z) regarde les voitures qui arrivent
	n.visible = actif
	r.noeuds.append(n)
	# panneaux ANNONCE m avant, dans chaque sens de circulation
	for sens in ([1.0, -1.0] if r.double else [1.0]):
		var pp: Vector3 = (r.axe as Vector3) - dir3 * (ANNONCE * sens) + droite * ((float(r.bord) + 1.6) * sens)
		pp.y = _sol(pp)
		var pn := _panneau()
		add_child(pn)
		pn.global_position = pp
		pn.look_at(pp + dir3 * sens, Vector3.UP)
		pn.visible = actif
		r.noeuds.append(pn)

func _sol(p: Vector3) -> float:
	var h := Relief.hauteur(p)
	return h if not is_nan(h) else p.y

static var _mats := {}
static func _mat(nom: String, c: Color, emi := false) -> StandardMaterial3D:
	if not _mats.has(nom):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.55
		if emi:
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mats[nom] = m
	return _mats[nom]

static func _boite(parent: Node3D, taille: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = taille
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	mi.visibility_range_end = VUE
	parent.add_child(mi)
	return mi

## Cabine de radar fixe à la française : caisson gris sur un poteau, deux vitres sombres côté circulation (+Z).
func _cabine() -> Node3D:
	if ResourceLoader.exists("res://assets/props/radar_fixe.glb"):
		return (load("res://assets/props/radar_fixe.glb") as PackedScene).instantiate()
	var n := Node3D.new()
	var gris := _mat("gris", Color(0.50, 0.52, 0.54))
	var fonce := _mat("fonce", Color(0.06, 0.07, 0.08))
	var blanc := _mat("blanc", Color(0.92, 0.92, 0.9))
	_boite(n, Vector3(0.16, 2.1, 0.16), Vector3(0, 1.05, 0), gris)
	_boite(n, Vector3(0.62, 0.95, 0.85), Vector3(0, 2.55, 0), gris)
	_boite(n, Vector3(0.70, 0.06, 0.95), Vector3(0, 3.05, 0), gris)              # toit débordant
	_boite(n, Vector3(0.44, 0.26, 0.02), Vector3(0, 2.75, 0.43), fonce)           # vitre de l'appareil photo
	_boite(n, Vector3(0.24, 0.18, 0.02), Vector3(-0.08, 2.38, 0.43), fonce)       # vitre du flash
	_boite(n, Vector3(0.56, 0.05, 0.02), Vector3(0, 2.12, 0.43), blanc)           # bande réfléchissante
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(0.62, 3.1, 0.85)
	cs.shape = bx
	cs.position = Vector3(0, 1.55, 0)
	sb.add_child(cs)
	n.add_child(sb)
	return n

## Panneau d'annonce (blanc, texte noir) sur deux pieds, lisible côté +Z.
func _panneau() -> Node3D:
	var n := Node3D.new()
	var gris := _mat("gris", Color(0.50, 0.52, 0.54))
	var blanc := _mat("panneau", Color(0.95, 0.95, 0.93))
	_boite(n, Vector3(0.07, 2.2, 0.07), Vector3(-0.45, 1.1, 0), gris)
	_boite(n, Vector3(0.07, 2.2, 0.07), Vector3(0.45, 1.1, 0), gris)
	_boite(n, Vector3(1.3, 0.9, 0.04), Vector3(0, 1.95, 0.05), blanc)
	var l := Label3D.new()
	l.text = "CONTRÔLES\nRADAR\nFRÉQUENTS"
	l.font_size = 72
	l.pixel_size = 0.0035
	l.modulate = Color(0.05, 0.05, 0.05)
	l.outline_size = 0
	l.position = Vector3(0, 1.95, 0.08)
	l.visibility_range_end = 250.0
	n.add_child(l)
	return n

## Radar mobile sur trépied (côté +Z = vers la circulation).
func _trepied() -> Node3D:
	if ResourceLoader.exists("res://assets/props/radar_mobile.glb"):
		return (load("res://assets/props/radar_mobile.glb") as PackedScene).instantiate()
	var n := Node3D.new()
	var noir := _mat("noir", Color(0.08, 0.08, 0.09))
	var blanc := _mat("blanc", Color(0.92, 0.92, 0.9))
	var fonce := _mat("fonce", Color(0.06, 0.07, 0.08))
	for k in 3:
		var a := TAU * float(k) / 3.0
		var pied := _boite(n, Vector3(0.035, 1.3, 0.035), Vector3(cos(a) * 0.22, 0.62, sin(a) * 0.22), noir)
		pied.rotation = Vector3(sin(a) * 0.32, 0.0, -cos(a) * 0.32)
	_boite(n, Vector3(0.36, 0.30, 0.30), Vector3(0, 1.42, 0), blanc)
	_boite(n, Vector3(0.36, 0.30, 0.30), Vector3(0, 1.74, 0), blanc)
	_boite(n, Vector3(0.26, 0.20, 0.02), Vector3(0, 1.74, 0.16), fonce)
	_boite(n, Vector3(0.16, 0.16, 0.02), Vector3(0, 1.42, 0.16), fonce)
	return n

# ---------------------------------------------------------------- contrôles mobiles des gendarmes
func _mobile_lancer(dt: float, car: Node, p: Vector3, ok: bool) -> void:
	var gd = main.get("gendarmes")
	var act = main.get("activities")
	if not mobile.is_empty() or gd == null or not gd.actif or gd.etoiles > 0 or not ok or (act and str(act.mode) != ""):
		return
	_mobile_t -= dt
	if _mobile_t > 0.0 or car.kmh() < 40.0:
		return
	_mobile_t = 10.0                      # nouvel essai bientôt si la route devant ne s'y prête pas
	lancer_mobile(randf_range(MOBILE_D.x, MOBILE_D.y))

## Pose un contrôle radar des gendarmes `d` m devant la voiture, sur une route limitée à V_MIN au moins.
func lancer_mobile(d: float) -> bool:
	var car = main.car
	var circ = main.get("circulation")
	var gd = main.get("gendarmes")
	if circ == null or gd == null:
		return false
	var v: Vector3 = car.linear_velocity if car.linear_velocity.length() > 2.0 else car.global_transform.basis.z
	var r: Array = circ.devant(car.global_position, v, d, 0.6)
	if r.is_empty():
		return false
	var q: Vector3 = r[0]
	var t: Vector2 = r[1]
	var lim: float = circ.limite(q)
	if lim < V_MIN:
		return false
	var droite := Vector3(-t.y, 0.0, t.x)
	var dir3 := Vector3(t.x, 0.0, t.y)
	var pv := q + droite * 3.3                             # voie de droite -> bas-côté
	if not Zone.dedans(Vector2(pv.x, pv.z), 60.0):
		return false
	var g := Gendarme.new()
	g.main = main
	g.mode = "arret"
	gd.add_child(g)
	g.poser(Vector2(pv.x, pv.z), Vector2(pv.x + t.x, pv.z + t.y))
	gd.liste.append(g)
	var tp := _trepied()
	add_child(tp)
	var pt := pv - dir3 * 5.0 + droite * 0.6
	pt.y = _sol(pt)
	tp.global_position = pt
	tp.look_at(pt + dir3, Vector3.UP)
	tp.visible = actif
	_mobile_t = randf_range(MOBILE_T.x, MOBILE_T.y)
	mobile = {"g": g, "noeuds": [tp], "r": {"axe": q - droite * 1.75, "t": t, "bord": 4.0, "lim": lim, "double": true, "poste": pt}}
	print("[radars] contrôle mobile des gendarmes à %.0f m devant (limite %.0f)" % [d, lim])
	return true

func _mobile_menage(p: Vector3) -> void:
	if mobile.is_empty():
		return
	var g = mobile.g
	var loin: bool = Vector2(mobile.r.poste.x - p.x, mobile.r.poste.z - p.z).length() > 480.0
	if not is_instance_valid(g) or g.mode != "arret" or loin:
		if is_instance_valid(g) and g.mode == "arret" and loin:
			var gd = main.get("gendarmes")
			if gd:
				gd.liste.erase(g)
			g.queue_free()
		for n in mobile.noeuds:
			if is_instance_valid(n):
				n.queue_free()
		mobile = {}
		_s.erase(-1)
