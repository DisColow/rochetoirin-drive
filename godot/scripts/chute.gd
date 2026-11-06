## Chute du bout du monde (#180, bord « cascade ») : la voiture qui passe la lèvre tombe dans la mer de nuages en
## tournoyant ; la caméra reste au bord et s'éloigne, puis un cercle noir se referme sur la voiture (fermeture façon
## Star Wars) ; elle réapparaît sur la route la plus proche, tournée vers l'intérieur, le cercle se rouvre et une
## fenêtre explique ce qui s'est passé. Pendant la chute, la voiture est « portée » (car.carried : ni physique, ni
## remise automatique) et suit une trajectoire calculée (le relief a encore ses collisions sous la lèvre).
extends Node

const DUREE := 3.4                   # s de chute avant la fin de la fermeture
const FERME := 1.3                   # s de fermeture du cercle (à la fin de la chute)
const NOIR := 0.35                   # s d'écran noir (remise sur la route)
const OUVRE := 0.6                   # s de réouverture
const G := 14.0                      # m/s² (un peu plus que la vraie : la chute se voit mieux)
const TITRE := "Chute du bout du monde"
const MESSAGE := "Petit oiseau, si tu n'as pas d'ailes, tu ne peux pas voler."

const IRIS := """shader_type canvas_item;
uniform vec2 centre;
uniform float rayon;
uniform vec2 taille;
void fragment() {
	float d = distance(UV * taille, centre);
	COLOR = vec4(0.0, 0.0, 0.0, smoothstep(rayon - 2.0, rayon + 2.0, d));
}
"""

var main: Node
var car: VehicleBody3D
var actif := false
var chutes := 0                      # essais
var _t := 0.0
var _p0 := Vector3.ZERO
var _v0 := Vector3.ZERO
var _b0 := Basis()
var _axe := Vector3.RIGHT
var _dehors := Vector2.ZERO
var _levre := Vector3.ZERO
var _cam0 := Vector3.ZERO
var _couche: CanvasLayer
var _iris: ColorRect
var _mat: ShaderMaterial
var _rayon0 := 1.0
var _phase := ""

func _ready() -> void:
	_couche = CanvasLayer.new()
	_couche.layer = 110
	_couche.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_couche)
	_iris = ColorRect.new()
	_iris.set_anchors_preset(Control.PRESET_FULL_RECT)
	_iris.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = IRIS
	_mat.shader = sh
	_iris.material = _mat
	_iris.visible = false
	_couche.add_child(_iris)

## Début de la chute : la voiture vient de passer la lèvre (dehors : direction vers le vide, unitaire).
func tomber(dehors: Vector2, levre: Vector3) -> void:
	if actif or car == null:
		return
	actif = true
	chutes += 1
	_t = 0.0
	_phase = "chute"
	_dehors = dehors
	_levre = levre
	_p0 = car.global_position
	var v: Vector3 = car.linear_velocity
	var vh := Vector3(v.x, 0.0, v.z)
	var sortie := maxf(vh.dot(Vector3(dehors.x, 0.0, dehors.y)), 4.0)       # au moins 4 m/s vers le vide
	_v0 = vh + Vector3(dehors.x, 0.0, dehors.y) * maxf(0.0, sortie - vh.length()) + Vector3(0.0, maxf(v.y, 0.0), 0.0)
	_b0 = car.global_basis
	_axe = Vector3(-dehors.y, 0.0, dehors.x).normalized()                     # bascule vers l'avant, dans le vide
	car.carried = true
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	car.freeze = true
	var rig = main.get("cam_rig")
	if rig:
		rig.set_process(false)
		_cam0 = rig.cam.global_position
	var vs := get_viewport().get_visible_rect().size
	_rayon0 = vs.length() * 0.6
	_mat.set_shader_parameter("taille", vs)
	_mat.set_shader_parameter("rayon", _rayon0)
	_mat.set_shader_parameter("centre", vs * 0.5)
	_iris.visible = true
	var s = main.get("sound")
	if s and s.has_method("_one_shot"):
		s._one_shot("ressort", _p0, 0.6, 0.55, 40.0, 800.0)              # sifflement grave de la chute
	print("[chute] la voiture tombe du bout du monde en %s à %.0f km/h" % [_p0.snapped(Vector3(0.1, 0.1, 0.1)), v.length() * 3.6])

func _process(dt: float) -> void:
	if not actif:
		return
	_t += dt
	var vs := get_viewport().get_visible_rect().size
	var rig = main.get("cam_rig")
	var cam: Camera3D = rig.cam if rig else get_viewport().get_camera_3d()
	if _phase == "chute":
		var tc := minf(_t, DUREE)
		var p := _p0 + _v0 * tc + Vector3(0.0, -0.5 * G * tc * tc, 0.0)
		var b := Basis(_axe, 1.6 * tc + 0.35 * tc * tc) * _b0                  # tournoie de plus en plus vite
		car.global_transform = Transform3D(b.orthonormalized(), p)
		if cam:
			# caméra : passe en 0,8 s au-dessus du vide, au-delà du rideau de la cascade (sinon l'eau qui tombe ou la lèvre
			# cache la voiture), puis monte : la voiture s'enfonce et rapetisse vers la mer de nuages
			var dehors := Vector3(_dehors.x, 0.0, _dehors.y)
			var haut := _levre + dehors * 12.0 + Vector3(0.0, 6.0, 0.0)
			var a := smoothstep(0.0, 0.8, tc)
			var k := smoothstep(0.6, DUREE, tc)
			cam.global_position = _cam0.lerp(haut, a) + Vector3(0.0, 16.0 * k, 0.0) - dehors * (4.0 * k)
			cam.look_at(p, (Vector3.UP + dehors).normalized())      # (pas d'UP seul : visée presque verticale)
			var c := cam.unproject_position(p) if not cam.is_position_behind(p) else vs * 0.5
			_mat.set_shader_parameter("centre", c)
		var f := clampf((_t - (DUREE - FERME)) / FERME, 0.0, 1.0)
		_mat.set_shader_parameter("rayon", _rayon0 * (1.0 - f * f * (3.0 - 2.0 * f)))
		if _t >= DUREE:
			_phase = "noir"
			_t = 0.0
			_mat.set_shader_parameter("rayon", -4.0)
			_remettre()
	elif _phase == "noir":
		if _t >= NOIR:
			_phase = "ouvre"
			_t = 0.0
	elif _phase == "ouvre":
		var f := clampf(_t / OUVRE, 0.0, 1.0)
		_mat.set_shader_parameter("centre", vs * 0.5)
		_mat.set_shader_parameter("rayon", _rayon0 * f * f)
		if f >= 1.0:
			_iris.visible = false
			actif = false
			_phase = ""
			var hud = main.get_node_or_null("HUD")
			if hud and hud.has_method("consigne"):
				hud.consigne(TITRE, MESSAGE, PackedStringArray(), Callable(), "Compris")

## Voiture reposée debout au bord, tournée vers l'intérieur, puis remise sur la route la plus proche dans ce sens.
func _remettre() -> void:
	var dedans := Vector3(-_dehors.x, 0.0, -_dehors.y)
	car.freeze = false
	car.carried = false
	car.global_transform = Transform3D(Basis.looking_at(-dedans, Vector3.UP), _levre + dedans * 30.0 + Vector3(0, 2.0, 0))
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	car.reset_to_road()
	car.hold(0.4)
	var rig = main.get("cam_rig")
	if rig:
		rig.set_process(true)
		rig.snap()
	print("[chute] reposée sur la route en %s" % car.global_position.snapped(Vector3(0.1, 0.1, 0.1)))
