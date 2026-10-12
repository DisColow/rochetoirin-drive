## Relief chargé autour de la voiture (v6.16, issue #11, demande de l'utilisateur) : au lieu des 173 régions Terrain3D
## d'un bloc (765 Mo de mémoire vive, autant de textures, 8 s de chargement figé), seules les régions à moins de
## R_CHARGE de la caméra sont dans Terrain3D, et celles restées au-delà de R_GARDE sont libérées. Les régions sont lues
## d'avance sur un fil (dès R_LIRE) ; ajouts et retraits sont groupés en une seule mise à jour, car Terrain3D refait
## alors toutes ses textures (≈ 3 ms par région chargée sur le PC de test : moins de régions = mise à jour plus brève).
## Ailleurs, un relief de remplacement prend leur place : maillage léger (hauteurs tous les 32 m) habillé de l'aspect
## exact du vrai relief vu de loin (albédo, normales, rugosité cuits à partir de lui par tools/bake_relief.gd), si
## bien qu'une région qui se charge au loin ne se voit pas (pas de « popping »). Le remplaçant s'efface (shader
## relief.gdshader, masque des régions chargées) là où le vrai relief est chargé, en gardant une bordure de 32 m
## sous lui pour qu'aucun interstice ne laisse voir le ciel au raccord.
extends Node3D

const DOSSIER := "res://terrain"
const REG := 1024.0
const R_CHARGE := 1800.0     # région mise dans Terrain3D dès que la caméra est à moins de R_CHARGE de son bord
const R_LIRE := 2600.0       # lue d'avance (sur un fil) dès R_LIRE
const R_GARDE := 2600.0      # libérée au-delà (marge de 800 m : pas de va-et-vient)
const MAXI := 30             # au-delà, les régions lointaines sont libérées sans attendre un ajout
const R_IMMEDIAT := 1200.0   # au démarrage et à la téléportation : chargée tout de suite (le reste en arrière-plan)
const BLOC := 4              # régions par côté d'un morceau du maillage de remplacement

static var actif: Node3D = null

var terrain: Terrain3D
var cible: Node3D                  # caméra (ou voiture)
var dispo := {}                    # Vector2i -> chemin du fichier de la région
var charge := {}                   # Vector2i -> true (régions actives dans Terrain3D)
var _attente := {}                 # Vector2i -> chemin (lecture en cours sur un fil)
var _pretes := {}                  # Vector2i -> Terrain3DRegion lue, pas encore dans Terrain3D
var _masque: Image
var _masque_tex: ImageTexture
var _mat: ShaderMaterial
var _h := PackedFloat32Array()     # hauteurs de secours (grille)
var _hx0 := 0.0
var _hz0 := 0.0
var _hpas := 32.0
var _hw := 0
var _hh := 0
var _t := 0.0
var _morceaux := []
var r_charge := R_CHARGE       # (captures de contrôle : modifiables)
var r_garde := R_GARDE
var r_lire := R_LIRE

func _init(t: Terrain3D) -> void:
	terrain = t
	name = "Relief"
	actif = self
	for f in DirAccess.get_files_at(DOSSIER):
		f = f.trim_suffix(".remap")
		if f.begins_with("terrain3d") and f.ends_with(".res"):
			var loc := Vector2i(f.substr(9, 3).replace("_", "").to_int(), f.substr(12, 3).replace("_", "").to_int())
			dispo[loc] = DOSSIER + "/" + f
	_masque = Image.create(32, 32, false, Image.FORMAT_R8)
	_masque_tex = ImageTexture.create_from_image(_masque)
	_lire_hauteurs()

func _ready() -> void:
	_remplacant()

## Hauteur du sol : vrai relief s'il est chargé là, sinon relief de remplacement (grille de 32 m) ; NaN hors carte.
static func hauteur(p: Vector3) -> float:
	if actif == null:
		return NAN
	var h: float = actif.terrain.data.get_height(p)
	if is_nan(h):
		h = actif._hauteur_grille(p.x, p.z)
	return h

func _hauteur_grille(x: float, z: float) -> float:
	if _hw == 0:
		return NAN
	var u := (x - _hx0) / _hpas
	var v := (z - _hz0) / _hpas
	var a := int(floor(u))
	var b := int(floor(v))
	if a < 0 or b < 0 or a >= _hw - 1 or b >= _hh - 1:
		return NAN
	var fu := u - a
	var fv := v - b
	var i := b * _hw + a
	return lerpf(lerpf(_h[i], _h[i + 1], fu), lerpf(_h[i + _hw], _h[i + _hw + 1], fu), fv)

func _lire_hauteurs() -> void:
	var f := FileAccess.open("res://world/relief/hauteurs.bin", FileAccess.READ)
	if f == null:
		push_warning("relief : hauteurs.bin absent")
		return
	_hx0 = f.get_float(); _hz0 = f.get_float(); _hpas = f.get_float()
	_hw = f.get_32(); _hh = f.get_32()
	_h = f.get_buffer(_hw * _hh * 4).to_float32_array()

## Distance (plan) de p au carré de la région.
static func _dist(loc: Vector2i, p: Vector3) -> float:
	var dx := maxf(maxf(loc.x * REG - p.x, p.x - (loc.x + 1) * REG), 0.0)
	var dz := maxf(maxf(loc.y * REG - p.z, p.z - (loc.y + 1) * REG), 0.0)
	return sqrt(dx * dx + dz * dz)

## Charge tout de suite les régions à moins de `r` de p (démarrage, téléportation) ; les autres suivent en arrière-plan.
func charger_autour(p: Vector3, r := R_IMMEDIAT) -> void:
	var n := 0
	for loc in dispo:
		if not charge.has(loc) and _dist(loc, p) < r:
			if _pretes.has(loc):
				_ajouter(loc, _pretes[loc])
				_pretes.erase(loc)
			elif _attente.has(loc):
				_ajouter(loc, ResourceLoader.load_threaded_get(_attente[loc]))
				_attente.erase(loc)
			else:
				terrain.data.load_region(loc, DOSSIER, false)
				charge[loc] = true
			n += 1
	if n > 0:
		_appliquer()
	_suivre(p)

func _process(dt: float) -> void:
	_t += dt
	if _t < 0.25:
		return
	_t = 0.0
	var p := cible.global_position if cible and is_instance_valid(cible) else Vector3.ZERO
	var t0 := Time.get_ticks_usec()
	_suivre(p)
	# lectures finies : gardées prêtes
	for loc in _attente.keys():
		var st := ResourceLoader.load_threaded_get_status(_attente[loc])
		if st != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			var res = ResourceLoader.load_threaded_get(_attente[loc]) if st == ResourceLoader.THREAD_LOAD_LOADED else null
			_attente.erase(loc)
			if res:
				_pretes[loc] = res
	for loc in _pretes.keys():
		if _dist(loc, p) > r_lire + 400.0:
			_pretes.erase(loc)              # on s'en est éloigné avant d'en avoir besoin
	# régions devenues proches : ajoutées, avec le retrait des lointaines, en une seule mise à jour
	# (dès qu'il en faut une, celles qui seront bientôt nécessaires suivent dans la même mise à jour : moins de mises à jour)
	var ajouts := []
	for loc in _pretes:
		if _dist(loc, p) < r_charge:
			ajouts.append(loc)
	if not ajouts.is_empty():
		for loc in _pretes:
			if not ajouts.has(loc) and _dist(loc, p) < r_charge + 500.0:
				ajouts.append(loc)
	var loin := []
	for loc in charge:
		if _dist(loc, p) > r_garde:
			loin.append(loc)
	if ajouts.is_empty() and (loin.is_empty() or charge.size() <= MAXI):
		return
	for loc in loin:
		terrain.data.remove_regionl(loc, false)
		# Terrain3D garde une région retirée jusqu'à l'enregistrement : « l'enregistrer » dans un dossier vide la retire
		# de sa liste (sans rien écrire) et libère sa mémoire
		terrain.data.save_region(loc, "res://__relief_libre", false)
		charge.erase(loc)
	for loc in ajouts:
		_ajouter(loc, _pretes[loc])
		_pretes.erase(loc)
	_appliquer()
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	PerfMon.note("relief", Time.get_ticks_usec() - t0)
	if OS.is_debug_build() or OS.get_cmdline_user_args().has("--relief-debug"):
		print("[relief] +%d -%d -> %d régions, %.1f ms" % [ajouts.size(), loin.size(), charge.size(), ms])

## Demande la lecture en arrière-plan des régions proches qui manquent.
func _suivre(p: Vector3) -> void:
	for loc in dispo:
		if not charge.has(loc) and not _attente.has(loc) and not _pretes.has(loc) and _dist(loc, p) < r_lire:
			if ResourceLoader.load_threaded_request(dispo[loc], "Terrain3DRegion", false, ResourceLoader.CACHE_MODE_IGNORE) == OK:
				_attente[loc] = dispo[loc]

func _ajouter(loc: Vector2i, res) -> void:
	var r := res as Terrain3DRegion
	if r == null:
		push_warning("relief : région %s illisible" % loc)
		return
	r.location = loc
	terrain.data.add_region(r, false)
	charge[loc] = true

## Textures de Terrain3D refaites, masque du remplaçant mis à jour (même image).
func _appliquer() -> void:
	terrain.data.update_maps()
	_masque.fill(Color.BLACK)
	for loc in charge:
		var c: Vector2i = loc + Vector2i(16, 16)
		if c.x >= 0 and c.y >= 0 and c.x < 32 and c.y < 32:
			_masque.set_pixel(c.x, c.y, Color.WHITE)
	_masque_tex.update(_masque)

func _exit_tree() -> void:
	# lectures en cours terminées avant de quitter (une lecture abandonnée faisait planter la sortie, essai v6.14)
	for loc in _attente:
		ResourceLoader.load_threaded_get(_attente[loc])
	_attente.clear()
	_pretes.clear()
	if actif == self:
		actif = null

## Maillage de remplacement : un morceau par bloc de BLOC × BLOC régions, sommets tous les 32 m, en coordonnées du monde.
func _remplacant() -> void:
	if _hw == 0:
		return
	var alb: Texture2D = load("res://world/relief/albedo.png")
	var nor: Texture2D = load("res://world/relief/normale.png")
	var mat: Texture2D = load("res://world/relief/matiere.png")
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://scripts/relief.gdshader")
	_mat.set_shader_parameter("albedo_tex", alb)
	_mat.set_shader_parameter("normale_tex", nor)
	_mat.set_shader_parameter("matiere_tex", mat)
	_mat.set_shader_parameter("masque", _masque_tex)
	_mat.set_shader_parameter("zone", Vector4(_hx0, _hz0, (_hw - 1) * _hpas, (_hh - 1) * _hpas))
	Env.add(_mat)
	var q := int(REG / _hpas)                      # quads par région
	var i0 := int(floor(_hx0 / REG))
	var j0 := int(floor(_hz0 / REG))
	var nx := (_hw - 1) / q
	var nz := (_hh - 1) / q
	for bj in range(0, nz, BLOC):
		for bi in range(0, nx, BLOC):
			var a0 := bi * q
			var b0 := bj * q
			var a1 := mini(bi + BLOC, nx) * q
			var b1 := mini(bj + BLOC, nz) * q
			var w := a1 - a0 + 1
			var pts := PackedVector3Array()
			pts.resize(w * (b1 - b0 + 1))
			for b in range(b0, b1 + 1):
				for a in range(a0, a1 + 1):
					var h := _h[b * _hw + a]
					pts[(b - b0) * w + (a - a0)] = Vector3(_hx0 + a * _hpas, 0.0 if is_nan(h) else h, _hz0 + b * _hpas)
			var idx := PackedInt32Array()
			for b in range(b0, b1):
				for a in range(a0, a1):
					var loc := Vector2i(i0 + a / q, j0 + b / q)
					if not dispo.has(loc):
						continue
					var k := b * _hw + a
					if is_nan(_h[k]) or is_nan(_h[k + 1]) or is_nan(_h[k + _hw]) or is_nan(_h[k + _hw + 1]):
						continue
					var v := (b - b0) * w + (a - a0)
					idx.append_array([v, v + 1, v + w, v + 1, v + w + 1, v + w])
			if idx.is_empty():
				continue
			var arr := []
			arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = pts
			arr[Mesh.ARRAY_INDEX] = idx
			var m := ArrayMesh.new()
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			var mi := MeshInstance3D.new()
			mi.mesh = m
			mi.material_override = _mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.name = "Remplacant_%d_%d" % [bi, bj]
			add_child(mi)
			_morceaux.append(mi)

const Env := preload("res://scripts/env.gd")
const PerfMon := preload("res://scripts/perf_monitor.gd")
