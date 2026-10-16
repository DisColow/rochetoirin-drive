## Caméra : poursuite souple derrière la voiture, ou vue conducteur (bouton caméra).
extends Node3D
const PerfMon := preload("res://scripts/perf_monitor.gd")

var target: VehicleBody3D
var cam: Camera3D
var mode := 0                      # 0 poursuite, 1 conducteur, 2 capot
# crans de la vue poursuite (#103) : [distance derrière, hauteur, regard devant] ; le bouton caméra passe de l'un à
# l'autre (proche, moyen, loin), puis vue conducteur, vue capot, et revient au plus proche
const CRANS := [[5.3, 2.6, 4.5], [7.6, 3.2, 6.0], [10.5, 4.0, 8.0]]
var cran := 0
var _pos := Vector3.ZERO
var _look := Vector3.ZERO
var _org := Vector3.INF            # position de la voiture à l'image précédente (lissage relatif, #92)
var _org_l := Vector3.ZERO
var eye := Vector3(-0.39, 1.33, 0.10)
var cockpit: CanvasLayer          # habitacle en pixel art (vue conducteur)
var hud: CanvasLayer
var shake := 0.0                  # secousse (explosion), décroît toute seule
# regard au doigt : glisser sur l'écran (hors boutons) tourne la caméra ; elle revient en place quand on lâche
var yaw_off := 0.0
var pitch_off := 0.0
var _drag := {}
var _idle := 0.0
var _carry := 0.0                 # 0 à 1 : plan large quand la soucoupe porte la voiture
var vitrine := false              # garage (#43) : la caméra tourne lentement autour de la voiture arrêtée
var _vitrine_a := 0.0

func _input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed and not (hud and hud.is_ui_point(e.position)):
			_drag[e.index] = true
		elif not e.pressed:
			_drag.erase(e.index)
	elif e is InputEventScreenDrag and _drag.has(e.index):
		if mode == 1:
			return                       # vue conducteur : regard fixe (le cockpit pixel art est une image plate)
		var lim := 0.55 if mode != 0 and not vitrine else PI
		yaw_off = clampf(yaw_off - e.relative.x * 0.006, -lim, lim)
		pitch_off = clampf(pitch_off - e.relative.y * 0.004, -0.35 if mode != 0 else -0.25, 0.6 if mode == 0 else 0.35)
		_idle = 0.0

func _ready() -> void:
	cam = Camera3D.new()
	cam.near = 0.08
	cam.far = 160000.0
	cam.fov = 62.0
	add_child(cam)
	cam.make_current()
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/car/meta.json"))
	eye = Vector3(-meta.eye[0], meta.eye[1], -meta.eye[2])      # modèle tourné de 180°
	_pos = target.global_position + Vector3(0, 3, -7)

func snap() -> void:
	var t := target.global_transform
	var flat := Vector3(t.basis.z.x, 0, t.basis.z.z).normalized()
	_pos = t.origin - flat * 5.3 + Vector3(0, 2.6, 0)
	_look = t.origin + Vector3(0, 1.3, 0)
	_org = t.origin; _org_l = t.origin

func cycle() -> void:
	if mode == 0 and cran < CRANS.size() - 1:
		cran += 1
		return
	cran = 0
	set_mode((mode + 1) % 3)

func set_mode(m: int) -> void:
	mode = m
	if mode == 1:
		yaw_off = 0.0
		pitch_off = 0.0
	if target and target.has_method("set_view_mode"):
		target.set_view_mode(m)
	if cockpit:
		cockpit.eye = eye
		cockpit.set_active(mode == 1)

func _process(dt: float) -> void:
	var t0_perf := Time.get_ticks_usec()
	_process_corps(dt)
	PerfMon.note("camera_rig", Time.get_ticks_usec() - t0_perf)

func _process_corps(dt: float) -> void:
	if Input.is_action_just_pressed("camera") and not preload("res://scripts/ui.gd").saisie_active():
		cycle()
	shake = move_toward(shake, 0.0, dt * 1.2)
	if _drag.is_empty():
		_idle += dt
		if _idle > 1.2:
			var k0 := 1.0 - exp(-dt * 2.5)
			yaw_off = lerpf(yaw_off, 0.0, k0)
			pitch_off = lerpf(pitch_off, 0.0, k0)
	if cockpit:
		cockpit.look_offset(yaw_off, pitch_off)
	var t := target.global_transform
	var fwd := t.basis.z
	if vitrine:
		# vue du garage : tour lent (et au doigt), voiture décalée à droite de l'écran (menu à gauche)
		_vitrine_a += dt * 0.22
		var dir := Vector3(fwd.x, 0, fwd.z).normalized().rotated(Vector3.UP, _vitrine_a + yaw_off + 2.4)
		var p := t.origin + dir * 6.4 + Vector3(0, 1.9 + 3.0 * maxf(pitch_off, 0.0), 0)
		var gauche := dir.cross(Vector3.UP).normalized()          # à gauche vu de la caméra
		cam.global_position = p
		cam.look_at(t.origin + Vector3(0, 0.8, 0) + gauche * 1.6, Vector3.UP)
		cam.fov = 55.0
		_pos = p
		_org = t.origin; _org_l = t.origin
		return
	if mode == 0:
		var flat := Vector3(fwd.x, 0, fwd.z).normalized().rotated(Vector3.UP, yaw_off)
		# caméra proche de la voiture (souhait du joueur), à toutes les vitesses
		# (v6.57, #92 : un peu plus haute, 2,05 m avant, pour mieux voir devant la voiture)
		var cd: float = CRANS[cran][0]; var ch: float = CRANS[cran][1]; var cv: float = CRANS[cran][2]
		var want := t.origin - flat * cd * cos(pitch_off) + Vector3(0, ch + cd * sin(pitch_off), 0)
		# voiture portée par la soucoupe : plan large, un peu en contrebas, voiture et soucoupe dans le cadre
		_carry = move_toward(_carry, 1.0 if target.carried else 0.0, dt * 0.8)
		var c := _carry * _carry * (3.0 - 2.0 * _carry)
		if c > 0.0:
			want = want.lerp(t.origin - flat * 19.0 + Vector3(0, 1.0, 0), c)
		var k := 1.0 - exp(-dt * lerpf(5.0, 14.0, c))
		# lissage dans le repère de la voiture (#92) : lissée en position absolue, la caméra traînait d'autant plus
		# que la voiture allait vite (5,7 m derrière à l'arrêt, 11,6 m à 100 km/h : la voiture rapetissait)
		var rel := (_pos - _org) if _org != Vector3.INF else (want - t.origin)
		rel = rel.lerp(want - t.origin, k)
		_org = t.origin
		_pos = t.origin + rel
		# bras à ressort : la caméra ne traverse ni murs, ni haies, ni relief (rayon depuis le toit de la voiture)
		var head := t.origin + Vector3(0, 1.5, 0)
		var q := PhysicsRayQueryParameters3D.create(head, _pos + (_pos - head).normalized() * 0.4)
		q.exclude = [target.get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			var hp: Vector3 = hit.position
			_pos = head + (hp - head) * maxf(0.0, 1.0 - 0.45 / maxf((hp - head).length(), 0.01))
		var look_at := (t.origin + Vector3(0, 1.3, 0) + flat * cv).lerp(t.origin + Vector3(0, 5.0, 0), c)
		_look = t.origin + ((_look - _org_l) if _look != Vector3.ZERO else (look_at - t.origin)).lerp(look_at - t.origin, 1.0 - exp(-dt * 10.0))
		_org_l = t.origin
		cam.global_position = _pos
		cam.look_at(_look, Vector3.UP)
		var boost := 9.0 if target.get("nitro_actif") else 0.0      # nitro (#98) : le champ s'ouvre
		cam.fov = lerpf(cam.fov, 62.0 + clampf(target.kmh() / 30.0, 0.0, 4.0) + boost, 1.0 - exp(-dt * (4.0 if boost > 0.0 else 2.0)))
	else:
		var p := t * (eye if mode == 1 else Vector3(0, 1.45, 1.2))
		cam.global_position = p
		# vue conducteur : regard un peu plongeant (la route apparaît au-dessus de la planche de bord en pixel art)
		var b := Basis.looking_at(fwd.rotated(t.basis.y, yaw_off), t.basis.y)
		b = b * Basis(Vector3.RIGHT, pitch_off)
		if mode == 1:
			b = b * Basis(Vector3.RIGHT, deg_to_rad(-7.0))
		cam.global_basis = b
		cam.fov = 68.0 if mode == 1 else 66.0
	if shake > 0.0:
		cam.global_position += Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * shake * 0.6
