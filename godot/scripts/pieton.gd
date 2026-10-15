## Piéton (clients du taxi faits avec MakeHuman, issue #55) : marche calculée sur le squelette « game_engine » de MPFB
## (cuisses, genoux, bras, balancement du bassin), sans fichier d'animation ; au repos, bras le long du corps (les
## modèles sont en pose A). Le modèle regarde vers +Z.
## Rotations données dans le repère du personnage (x : côté, y : haut, z : avant) puis ramenées au repère de chaque os.
extends Node3D
const Relief := preload("res://scripts/relief.gd")

var vitesse := 0.0                 # m/s (0 : immobile)
var cible := Vector3.INF           # marche vers ce point (repère monde), puis s'arrête ; signal arrive
signal arrive
var _sk: Skeleton3D
var _os := {}                      # nom -> indice
var _phase := 0.0

func _ready() -> void:
	# cheveux, cils, sourcils : transparence coupée au seuil, deux faces (pas de transparence mélangée, et les mèches
	# vues de l'intérieur ne disparaissent pas)
	for mi in find_children("*", "MeshInstance3D", true, false):
		var m3 := mi as MeshInstance3D
		for k in m3.mesh.get_surface_count():
			var m := m3.mesh.surface_get_material(k) as BaseMaterial3D
			if m and m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				var c := m.duplicate() as BaseMaterial3D
				c.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				c.alpha_scissor_threshold = 0.35
				c.cull_mode = BaseMaterial3D.CULL_DISABLED
				m3.set_surface_override_material(k, c)
	var l := find_children("*", "Skeleton3D", true, false)
	if l.is_empty():
		return
	_sk = l[0]
	for n in ["pelvis", "spine_01", "thigh_l", "thigh_r", "calf_l", "calf_r", "foot_l", "foot_r", "upperarm_l",
			"upperarm_r", "lowerarm_l", "lowerarm_r"]:
		var i := _sk.find_bone(n)
		if i >= 0:
			_os[n] = i
	_poser(0.0)

func _process(dt: float) -> void:
	if cible.is_finite():
		var d := cible - global_position
		d.y = 0.0
		if d.length() < 0.5:
			cible = Vector3.INF
			vitesse = 0.0
			arrive.emit()
		else:
			vitesse = 1.4
			var dir := d.normalized()
			global_position += dir * vitesse * dt
			global_position.y = Relief.hauteur(global_position)
			rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), 1.0 - exp(-dt * 8.0))
	if _sk == null:
		return
	if vitesse > 0.05:
		_phase += dt * vitesse * 3.2            # ~1,1 pas par seconde à 1,4 m/s
	_poser(clampf(vitesse / 1.4, 0.0, 1.0))

## Rotation d'un os : angle (rad) autour d'un axe du repère du personnage, appliquée à sa pose de repos.
func _tourner(nom: String, axe: Vector3, angle: float) -> void:
	if not _os.has(nom):
		return
	var b: int = _os[nom]
	var g := _sk.get_bone_global_rest(b).basis.orthonormalized()
	var delta := Quaternion(g.inverse() * Basis(axe, angle) * g)
	_sk.set_bone_pose_rotation(b, Quaternion(_sk.get_bone_rest(b).basis.orthonormalized()) * delta)

func _poser(k: float) -> void:
	var s := sin(_phase) * k
	var c := cos(_phase) * k
	# jambes : la cuisse avance, le genou plie surtout au passage de la jambe
	_tourner("thigh_l", Vector3.RIGHT, -0.45 * s)
	_tourner("thigh_r", Vector3.RIGHT, 0.45 * s)
	_tourner("calf_l", Vector3.RIGHT, 0.7 * maxf(0.0, -c) * k)
	_tourner("calf_r", Vector3.RIGHT, 0.7 * maxf(0.0, c) * k)
	# bras le long du corps (pose A -> pose de marche), balancés à l'opposé des jambes, coudes un peu pliés
	_tourner("upperarm_l", Vector3.BACK, -1.05)
	_tourner("upperarm_r", Vector3.BACK, 1.05)
	if _os.has("upperarm_l"):
		_tourner_plus("upperarm_l", Vector3.RIGHT, 0.35 * s)
		_tourner_plus("upperarm_r", Vector3.RIGHT, -0.35 * s)
	_tourner("lowerarm_l", Vector3.RIGHT, -0.25 - 0.15 * k)
	_tourner("lowerarm_r", Vector3.RIGHT, -0.25 - 0.15 * k)
	_tourner("pelvis", Vector3.UP, 0.08 * s)
	_tourner("spine_01", Vector3.UP, -0.1 * s)

## Ajoute une rotation (repère du personnage) à la pose déjà posée de l'os.
func _tourner_plus(nom: String, axe: Vector3, angle: float) -> void:
	var b: int = _os[nom]
	var g := _sk.get_bone_global_rest(b).basis.orthonormalized()
	var delta := Quaternion(g.inverse() * Basis(axe, angle) * g)
	_sk.set_bone_pose_rotation(b, _sk.get_bone_pose_rotation(b) * delta)
