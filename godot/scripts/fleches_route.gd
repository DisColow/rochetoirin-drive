## Flèches d'itinéraire sur la route (#154, demande de l'utilisateur, façon Forza Horizon) : chevrons semi-transparents
## posés au milieu de la chaussée le long de l'itinéraire GPS (`activities.route_gps`), tous les PAS m de PRES à LOIN m
## devant la voiture, un de plus entre deux avant un virage serré. Ils sont calés sur la distance qui reste jusqu'à
## l'arrivée : ils ne glissent pas quand la voiture avance, et la vague de lumière du shader (fleches_route.gdshader)
## les parcourt dans le sens de la marche. Un seul MultiMesh, sans ombre ni lumière ; fondus aux deux bouts dans le
## shader. Option ⚙ > Conduite (`affichage/fleches_route`, activée par défaut).
extends MultiMeshInstance3D
const Relief := preload("res://scripts/relief.gd")

const PAS := 7.0
const PRES := 6.0
const LOIN := 160.0
const MAXI := 48
const HAUT := 0.25                   # m au-dessus de la chaussée
const VIRAGE := 0.6                  # rad : changement de cap sur ±10 m au-delà duquel on double les chevrons

var actif := true
var _act: Node
var _t := 0.0

func _ready() -> void:
	name = "FlechesRoute"
	var cfg := ConfigFile.new()
	if cfg.load("user://reglages.cfg") == OK:
		actif = cfg.get_value("affichage", "fleches_route", true)
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	var q := QuadMesh.new()
	q.size = Vector2(3.0, 4.2)
	q.orientation = PlaneMesh.FACE_Y
	multimesh.mesh = q
	multimesh.instance_count = MAXI
	multimesh.visible_instance_count = 0
	var m := ShaderMaterial.new()
	m.shader = preload("res://scripts/fleches_route.gdshader")
	material_override = m
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	extra_cull_margin = 4000.0           # boîte englobante du MultiMesh : les instances bougent sans la recalculer

func _process(dt: float) -> void:
	_t -= dt
	if _t > 0.0:
		return
	_t = 0.1
	if _act == null or not is_instance_valid(_act):
		_act = get_tree().get_first_node_in_group("activites")
	var rt := PackedVector2Array()
	if actif and _act:
		rt = _act.get("route_gps") if _act.get("route_gps") != null else PackedVector2Array()
	multimesh.visible_instance_count = _placer(rt) if rt.size() > 1 else 0

## Pose les chevrons le long de rt (rt[0] : la voiture projetée sur le tracé) ; renvoie leur nombre.
func _placer(rt: PackedVector2Array) -> int:
	var cum := PackedFloat32Array([0.0])
	for i in range(1, rt.size()):
		cum.append(cum[i - 1] + rt[i].distance_to(rt[i - 1]))
	var total := cum[-1]
	# abscisses calées sur l'arrivée : total - s multiple de PAS / 2
	var demi := PAS * 0.5
	var r := floorf((total - PRES) / demi) * demi          # distance restante du premier chevron
	var n := 0
	var j := 0
	while r > 0.0 and n < MAXI:
		var s := total - r
		if s > LOIN:
			break
		var impair := int(roundf(r / demi)) % 2 == 1
		if not impair or _cap(rt, cum, s - 10.0, s + 10.0, j) > VIRAGE:
			while j < rt.size() - 2 and cum[j + 1] < s:
				j += 1
			var a := rt[j]; var b := rt[j + 1]
			var f := clampf((s - cum[j]) / maxf(cum[j + 1] - cum[j], 1e-3), 0.0, 1.0)
			var p := a.lerp(b, f)
			var d := _point(rt, cum, s + 2.0, j) - _point(rt, cum, s - 2.0, j)
			if d.length_squared() < 1e-4:
				d = b - a
			d = d.normalized()
			var y := _hauteur(p)
			var bas := Basis(Vector3(d.y, 0.0, -d.x), Vector3.UP, Vector3(d.x, 0.0, d.y))
			multimesh.set_instance_transform(n, Transform3D(bas, Vector3(p.x, y + HAUT, p.y)))
			multimesh.set_instance_custom_data(n, Color(r, s, 0.0, 0.0))
			n += 1
		r -= demi
	return n

## Point du tracé à l'abscisse s (recherche à partir du segment j).
static func _point(rt: PackedVector2Array, cum: PackedFloat32Array, s: float, j: int) -> Vector2:
	s = clampf(s, 0.0, cum[-1])
	while j > 0 and cum[j] > s:
		j -= 1
	while j < rt.size() - 2 and cum[j + 1] < s:
		j += 1
	var f := clampf((s - cum[j]) / maxf(cum[j + 1] - cum[j], 1e-3), 0.0, 1.0)
	return rt[j].lerp(rt[j + 1], f)

## Changement de cap (rad) entre s0 et s1.
static func _cap(rt: PackedVector2Array, cum: PackedFloat32Array, s0: float, s1: float, j: int) -> float:
	var m := (s0 + s1) * 0.5
	var a := _point(rt, cum, m, j) - _point(rt, cum, s0, j)
	var b := _point(rt, cum, s1, j) - _point(rt, cum, m, j)
	if a.length_squared() < 1e-4 or b.length_squared() < 1e-4:
		return 0.0
	return absf(a.angle_to(b))

## Hauteur de la chaussée en p : rayon vers le bas sur les surfaces fixes (routes, ponts, relief : les tuiles de
## routes sont au-dessus du relief) ; à défaut, le relief.
func _hauteur(p: Vector2) -> float:
	var h := Relief.hauteur(Vector3(p.x, 0.0, p.y))
	if not is_finite(h):
		var c := get_viewport().get_camera_3d()
		h = c.global_position.y - 1.5 if c else 0.0
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, h + 8.0, p.y), Vector3(p.x, h - 3.0, p.y))
	var espace := get_world_3d().direct_space_state
	for _essai in 3:                     # voitures (joueur, circulation, garées) : on passe au travers
		var hit := espace.intersect_ray(q)
		if hit.is_empty():
			break
		if hit.collider is PhysicsBody3D and not hit.collider is StaticBody3D:
			q.exclude = q.exclude + [hit.rid]
			continue
		if (hit.normal as Vector3).y > 0.7:
			return float(hit.position.y)
		break
	return h
