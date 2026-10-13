## Bâtiments refaits sur mesure d'après Street View (world/sur_mesure.json) : la boulangerie et le restaurant
## (pipeline/boulangerie/), puis tous les bâtiments non résidentiels (pipeline/sur_mesure/batiment.py, directive du
## 13/10). Un modèle et un atlas par bâtiment, façades peintes (sur_mesure.gdshader) ; le bâtiment BD TOPO et la
## devanture générique qu'il remplace ne sont plus générés. Collisions : boîtes (BoxShape3D, « boites »).
## v6.21 : chargés autour de la caméra seulement (lecture en arrière-plan, scripts/chargeur.gd), libérés au-delà de
## R_LIBERE ; ceux à moins de R_IMMEDIAT sont posés tout de suite (démarrage, téléportation : pas d'apparition tardive).
extends Node3D

const Env := preload("res://scripts/env.gd")
const PerfMon := preload("res://scripts/perf_monitor.gd")
const R_CHARGE := 1100.0
const R_LIBERE := 1400.0
const R_IMMEDIAT := 350.0
const VUE := 1300.0                    # comme les bâtiments génériques (buildings.gd, VIEW)

var _defs := {}                        # id -> entrée de sur_mesure.json
var _poses := {}                       # id -> [modèle, corps, matériau]
var _chargeur = preload("res://scripts/chargeur.gd").new()
var _t := 0.0
var _dernier := Vector3(1e9, 0, 1e9)

func _ready() -> void:
	name = "SurMesure"
	if not FileAccess.file_exists("res://world/sur_mesure.json"):
		return
	_defs = JSON.parse_string(FileAccess.get_file_as_string("res://world/sur_mesure.json"))

func _camera() -> Vector3:
	var c := get_viewport().get_camera_3d()
	return c.global_position if c else Vector3(1e9, 0, 1e9)

func _process(dt: float) -> void:
	var t0 := Time.get_ticks_usec()
	_suivre(dt)
	PerfMon.note("sur_mesure", Time.get_ticks_usec() - t0)

func _suivre(dt: float) -> void:
	var p := _camera()
	if p.x > 1e8:
		return
	var saut := p.distance_to(_dernier) > 300.0       # démarrage ou téléportation : on pose tout de suite le proche
	_t -= dt
	if _t > 0.0 and not saut:
		_poser_prets(p)
		return
	_t = 0.5
	_dernier = p
	var voulus := {}
	for k in _defs:
		var e: Dictionary = _defs[k]
		var d := Vector2(e.pos[0] - p.x, e.pos[2] - p.z).length()
		if _poses.has(k):
			if d > R_LIBERE:
				Env.remove(_poses[k][2])
				_poses[k][0].queue_free(); _poses[k][1].queue_free()
				_poses.erase(k)
			continue
		if d < R_CHARGE:
			voulus[e.glb] = true; voulus[e.atlas] = true
			if d < R_IMMEDIAT and saut:
				_poser(k, load(e.glb), load(e.atlas))
	_chargeur.menage(voulus)
	_poser_prets(p)

## Pose au plus un bâtiment par image, dès que son modèle et son atlas sont lus.
func _poser_prets(p: Vector3) -> void:
	for k in _defs:
		if _poses.has(k):
			continue
		var e: Dictionary = _defs[k]
		if Vector2(e.pos[0] - p.x, e.pos[2] - p.z).length() >= R_CHARGE:
			continue
		var sc := _chargeur.pret(e.glb) as PackedScene
		var tx := _chargeur.pret(e.atlas) as Texture2D
		if sc != null and tx != null:
			_poser(k, sc, tx)
			return

func _poser(k: String, sc: PackedScene, atlas: Texture2D) -> void:
	if sc == null or _poses.has(k):
		return
	var e: Dictionary = _defs[k]
	var n := sc.instantiate()
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://scripts/sur_mesure.gdshader")
	mat.set_shader_parameter("atlas", atlas)
	Env.add(mat)
	var corps := StaticBody3D.new()
	corps.name = k + "_col"
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if String(m.name).begins_with("col"):
			m.queue_free()                 # (ancien maillage de collision : remplacé par les boîtes)
		else:
			m.material_override = mat
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			m.visibility_range_end = VUE
			m.visibility_range_end_margin = 100.0
	# collisions : boîtes seulement (v6.18, BoxShape3D), [cx, cy, cz, demi-tailles, lacet] relatifs à la pose
	for b in e.get("boites", []):
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(b[3], b[4], b[5]) * 2.0
		cs.shape = sh
		cs.transform = Transform3D(Basis(Vector3.UP, b[6]), Vector3(b[0], b[1], b[2]))
		corps.add_child(cs)
	n.name = k
	var p: Array = e.pos
	n.position = Vector3(p[0], p[1], p[2])
	corps.position = n.position
	add_child(n)
	add_child(corps)
	_poses[k] = [n, corps, mat]
