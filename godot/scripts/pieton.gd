## Piéton (clients du taxi faits avec MakeHuman, issue #55) : marche calculée sur le squelette « game_engine » de MPFB
## (cuisses, genoux, bras, balancement du bassin), sans fichier d'animation ; au repos, bras le long du corps (les
## modèles sont en pose A). Le modèle regarde vers +Z.
## Rotations données dans le repère du personnage (x : côté, y : haut, z : avant) puis ramenées au repère de chaque os.
extends Node3D

var vitesse := 0.0                 # m/s (0 : immobile)
var _sk: Skeleton3D
var _os := {}                      # nom -> indice
var _phase := 0.0

func _ready() -> void:
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
