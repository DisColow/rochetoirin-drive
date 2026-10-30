## Bord « cascade » façon Golden Sun 2 (#157, ⚙ > Conduite > Bord de la carte ; bord.gd le crée et l'allume) : au
## lieu des collines, le monde s'arrête à la limite de la zone jouable. Une bande d'eau peu profonde (les 14 derniers
## mètres) coule vers le bord et tombe en un rideau continu dans une mer de nuages, sous le point le plus bas de la
## carte ; au-delà, rien (les matériaux du sol s'effacent hors de la zone : env.gdshaderinc, env_hors_monde).
## Données world/cascade.bin (pipeline/build_cascade.py) et world/zone_sdf.bin (build_zone_sdf.py). Morceaux de
## MORCEAU points (256 m de bord) faits à la demande près de la caméra. Le freinage dans l'eau et le renvoi vers
## l'intérieur sont dans bord.gd.
extends Node3D
const Env := preload("res://scripts/env.gd")
const PerfMon := preload("res://scripts/perf_monitor.gd")

const MORCEAU := 64
const VUE := 2600.0
const LEVRE := 0.3                   # m : l'eau au-dessus du relief
const DECAL := [14.0, 10.0, 6.0, 3.0, 0.0]          # rangées de la bande (m à l'intérieur), de l'amont à la lèvre
# rideau : [avancée vers l'extérieur, hauteur sous la lèvre] (la dernière rangée descend jusqu'aux nuages)
const PROFIL := [[0.0, 0.0], [1.2, -0.5], [2.4, -2.2], [3.4, -6.0], [4.4, -16.0], [5.5, -60.0], [6.5, -9999.0]]

var actif := false
var y_nuages := 0.0
var _n := 0
var _d := PackedFloat32Array()       # par point : x, z, nx, nz, h à 0, 3, 6, 10, 14 m à l'intérieur
var _morceaux := {}                  # indice -> MeshInstance3D
var _mat_eau: ShaderMaterial
var _mat_rideau: ShaderMaterial
var _nuages: MeshInstance3D
var _t := 0.0
var _son: AudioStreamPlayer
var sdf_tex: ImageTexture
var sdf_rect := Vector4.ZERO

func _ready() -> void:
	name = "Cascade"
	var f := "res://world/cascade.bin"
	if FileAccess.file_exists(f):
		var b := FileAccess.get_file_as_bytes(f)
		_n = b.decode_s32(0)
		y_nuages = b.decode_float(4)
		_d = b.slice(8).to_float32_array()
	_lire_sdf()
	_mat_eau = ShaderMaterial.new()
	_mat_eau.shader = preload("res://scripts/cascade_eau.gdshader")
	_mat_rideau = ShaderMaterial.new()
	_mat_rideau.shader = preload("res://scripts/cascade_rideau.gdshader")
	_nuages = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60000.0, 60000.0)
	_nuages.mesh = pm
	var mn := ShaderMaterial.new()
	mn.shader = preload("res://scripts/cascade_nuages.gdshader")
	_nuages.material_override = mn
	_nuages.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_nuages.extra_cull_margin = 2000.0
	add_child(_nuages)
	_son = AudioStreamPlayer.new()
	_son.stream = load("res://assets/sfx/ruisseau.ogg")
	_son.pitch_scale = 0.5                  # ruisseau ralenti : le grondement sourd de la chute
	_son.volume_db = -80.0
	_son.bus = "Master"
	add_child(_son)
	visible = false

## Distance signée à la limite (world/zone_sdf.bin) : texture lue par les shaders (env_hors_monde).
func _lire_sdf() -> void:
	var f := "res://world/zone_sdf.bin"
	if not FileAccess.file_exists(f):
		return
	var b := FileAccess.get_file_as_bytes(f)
	var l := b.decode_s32(0); var h := b.decode_s32(4)
	var x0 := b.decode_float(8); var z0 := b.decode_float(12); var pas := b.decode_float(16)
	var img := Image.create_from_data(l, h, false, Image.FORMAT_R8, b.slice(24, 24 + l * h))
	sdf_tex = ImageTexture.create_from_image(img)
	sdf_rect = Vector4(x0 - 0.5 * pas, z0 - 0.5 * pas, 1.0 / (l * pas), 1.0 / (h * pas))

func set_actif(on: bool) -> void:
	actif = on and _n > 0 and sdf_tex != null
	visible = actif
	if sdf_tex:
		Env.set_value("env_zone_sdf", sdf_tex)
		Env.set_value("env_zone_rect", sdf_rect)
	Env.set_value("env_bout_monde", 1.0 if actif else 0.0)
	if not actif:
		for k in _morceaux:
			_morceaux[k].queue_free()
		_morceaux.clear()
		_son.stop()
	_t = 0.0

func _process(dt: float) -> void:
	if not actif:
		return
	var t0 := Time.get_ticks_usec()
	var cam := get_viewport().get_camera_3d()
	if cam:
		var c := cam.global_position
		_nuages.global_position = Vector3(snappedf(c.x, 64.0), y_nuages, snappedf(c.z, 64.0))
		_t -= dt
		if _t <= 0.0:
			_t = 0.5
			_morceaux_autour(c)
	PerfMon.note("cascade", Time.get_ticks_usec() - t0)

## Grondement de la chute selon la distance d (m) de l'auditeur au bord (bord.gd).
func son(d: float) -> void:
	if not actif:
		return
	var v := clampf(1.0 - d / 350.0, 0.0, 1.0)
	if v <= 0.0:
		if _son.playing:
			_son.stop()
		return
	if not _son.playing:
		_son.play()
	_son.volume_db = linear_to_db(0.08 + 0.92 * v * v) + 2.0

func _morceaux_autour(c: Vector3) -> void:
	var voulus := {}
	for k in ceili(float(_n) / MORCEAU):
		var i := mini(k * MORCEAU + MORCEAU / 2, _n - 1)
		if Vector2(_d[i * 9] - c.x, _d[i * 9 + 1] - c.z).length() < VUE + MORCEAU * 4.0:
			voulus[k] = true
	for k in _morceaux.keys():
		if not voulus.has(k):
			_morceaux[k].queue_free()
			_morceaux.erase(k)
	var faits := 0
	for k in voulus:
		if not _morceaux.has(k) and faits < 6:
			_morceaux[k] = _morceau(k)
			add_child(_morceaux[k])
			faits += 1

## Morceau k : surface 0 = bande d'eau (u : abscisse le long du bord, v : distance à la lèvre), surface 1 = rideau
## (u, v : longueur parcourue depuis la lèvre ; uv2.x : chute sous la lèvre, uv2.y : hauteur totale de la chute).
func _morceau(k: int) -> MeshInstance3D:
	var i0 := k * MORCEAU
	var cols := mini(MORCEAU, _n - i0) + 1          # le morceau suivant repart du dernier point (pas de trou)
	var bande := SurfaceTool.new()
	bande.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rideau := SurfaceTool.new()
	rideau.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in cols:
		var i := (i0 + j) % _n
		var p := Vector2(_d[i * 9], _d[i * 9 + 1])
		var nr := Vector2(_d[i * 9 + 2], _d[i * 9 + 3])
		var u := float(i0 + j) * 4.0
		for r in DECAL.size():
			var dd: float = DECAL[r]
			var q := p - nr * dd
			bande.set_uv(Vector2(u, dd))
			bande.add_vertex(Vector3(q.x, _d[i * 9 + 8 - r] + LEVRE, q.y))
		var h0: float = _d[i * 9 + 4] + LEVRE
		var v := 0.0
		var prec := Vector3(p.x, h0, p.y)
		for r in PROFIL.size():
			var q := p + nr * float(PROFIL[r][0])
			var pt := Vector3(q.x, maxf(h0 + float(PROFIL[r][1]), y_nuages - 30.0), q.y)
			v += pt.distance_to(prec)
			prec = pt
			rideau.set_uv(Vector2(u, v))
			rideau.set_uv2(Vector2(h0 - pt.y, h0 - y_nuages))
			rideau.add_vertex(pt)
	_grille(bande, cols, DECAL.size())
	_grille(rideau, cols, PROFIL.size())
	var m := bande.commit()
	rideau.commit(m)
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.set_surface_override_material(0, _mat_eau)
	mi.set_surface_override_material(1, _mat_rideau)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

static func _grille(st: SurfaceTool, cols: int, rangs: int) -> void:
	for j in cols - 1:
		for r in rangs - 1:
			var a := j * rangs + r
			var b := a + rangs
			st.add_index(a); st.add_index(b); st.add_index(a + 1)
			st.add_index(a + 1); st.add_index(b); st.add_index(b + 1)
