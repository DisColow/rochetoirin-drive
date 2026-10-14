## Cultures fauchées au passage de la voiture (tous les champs ; les tiges explosent en éclats, #131) : carte des passages de 96 m de côté qui suit la
## voiture (256 × 256 px, 0,375 m par pixel). L'empreinte de la caisse y est peinte en roulant ; le shader des cultures
## (crops.gdshader, trample_tex) y lit, pour chaque tige, si elle est couchée et dans quel sens, et la couche au sol.
## Canaux : R, V = sens de la marche (×0,5 + 0,5), B = écrasement (0 … 1), A = (ligne de l'atlas des cultures + 1) / 8
## (texture des tiges couchées dessinée au sol par terrain.gdshader). La trace n'est peinte que dans les champs
## (crops.field_at) et reste tant qu'on est dans le coin (la carte glisse avec la voiture en gardant ce qui est peint).
extends Node

const N := 256
const TAILLE := 96.0
var car: VehicleBody3D
var mats: Array = []              # matériaux qui lisent la carte (cultures)
var crops: Node                    # champs (field_at) ; null : on peint partout
var terrain_mat: Object            # matériau du relief (Terrain3DMaterial : set_shader_param)
var dust: Node                     # effets (dust.gd) : plants fauchés projetés en morceaux de sprite
var audio: Node                    # sons (audio.gd) : froissement du feuillage (issue #8)
# couleur des éclats par type de culture (moyennes de l'atlas des cultures) : principale, seconde (épis, fleurs)
const ECLATS := [[Color(0.56, 0.67, 0.34), Color(0.85, 0.78, 0.45)],     # maïs
	[Color(0.68, 0.58, 0.36), Color(0.86, 0.76, 0.42)],                    # céréales (blé cuit d'après modèle, v6.37)
	[Color(0.45, 0.52, 0.20), Color(0.92, 0.82, 0.22)],                    # colza : tiges vertes, fleurs jaunes
	[Color(0.40, 0.50, 0.14), Color(0.92, 0.76, 0.14)]]                    # tournesol
const ROW := [0, 4, 5, 3]          # type de culture -> ligne de l'atlas des tiges couchées (dessus des céréales, du feuillage)
const VIDE := Color(0.5, 0.5, 0.0, 0.0)
const TOUT := Color(1.0, 0.5, 1.0, 5.0 / 8.0)
var _img: Image
var _tex: ImageTexture
var _orig := Vector2.ZERO          # coin de la carte (monde x, z)
var _sale := false
var _t := 0.0
var _debug := OS.get_cmdline_user_args().has("--trample-debug")
var _tout := OS.get_cmdline_user_args().has("--trample-all")

func _ready() -> void:
	_img = Image.create(N, N, false, Image.FORMAT_RGBA8)
	_img.fill(TOUT if _tout else VIDE)
	_tex = ImageTexture.create_from_image(_img)

func attacher(m: ShaderMaterial) -> void:
	mats.append(m)
	m.set_shader_parameter("trample_tex", _tex)
	_zone()

## Relief : tiges couchées dessinées au sol dans la trace (texture des cultures).
func attacher_relief(m: Object, atlas: Texture2D) -> void:
	terrain_mat = m
	m.set_shader_param("trample_tex", _tex)
	m.set_shader_param("crops_albedo", atlas)
	_zone()

func _zone() -> void:
	for m in mats:
		m.set_shader_parameter("trample_zone", Vector4(_orig.x, _orig.y, TAILLE, 1.0))
	if terrain_mat:
		terrain_mat.set_shader_param("trample_zone", Vector4(_orig.x, _orig.y, TAILLE, 1.0))

func _physics_process(dt: float) -> void:
	if car == null or mats.is_empty():
		return
	var p := car.global_position
	var c := Vector2(p.x, p.z)
	if _orig == Vector2.ZERO:
		_orig = c - Vector2(TAILLE, TAILLE) * 0.5
		_zone()
	# la carte glisse avec la voiture (par pas entiers de pixels, en gardant la trace déjà peinte)
	var centre := _orig + Vector2(TAILLE, TAILLE) * 0.5
	if c.distance_to(centre) > TAILLE * 0.25:
		var px := TAILLE / N
		var d := Vector2i(roundi((c.x - centre.x) / px), roundi((c.y - centre.y) / px))
		var neuf := Image.create(N, N, false, Image.FORMAT_RGBA8)
		neuf.fill(TOUT if _tout else VIDE)
		neuf.blit_rect(_img, Rect2i(d.x, d.y, N, N), Vector2i.ZERO)
		_img = neuf
		_orig += Vector2(d) * px
		_zone()
		_sale = true
	# empreinte de la caisse (un peu plus large que la voiture : les tiges tombent de part et d'autre)
	var kmh: float = car.kmh()
	if kmh > 2.0 and car.wheels.any(func(w): return w.is_in_contact()):
		var fwd := Vector2(car.global_basis.z.x, car.global_basis.z.z).normalized()
		if car.forward_speed() < 0.0:
			fwd = -fwd
		var cote := Vector2(-fwd.y, fwd.x)
		var px := TAILLE / N
		# seulement dans un champ (rien sur la route ni dans l'herbe) : testé en 5 points le long du pinceau, chaque
		# ligne prend le point le plus proche
		var tp := [1, 1, 1, 1, 1]
		if crops:
			for j in 5:
				tp[j] = crops.field_at(c + fwd * ((j - 2) * 7.5 * px))
		var neufs := [0, 0, 0, 0]                    # pixels fauchés à l'instant, par type de culture
		for u in range(-15, 16):                    # ~ 5,6 m de long
			var t: int = tp[clampi(roundi((u + 15) / 7.5), 0, 4)]
			if t < 0:
				continue
			var dir_c := Color(fwd.x * 0.5 + 0.5, fwd.y * 0.5 + 0.5, 1.0, (ROW[clampi(t, 0, 3)] + 1.0) / 8.0)
			for v in range(-3, 4):                  # ~ 2,6 m de large : les plants touchés par la caisse éclatent (v6.39)
				var w := c + fwd * (u * px) + cote * (v * px * 1.0)
				var ix := int((w.x - _orig.x) / px)
				var iz := int((w.y - _orig.y) / px)
				if ix < 0 or iz < 0 or ix >= N or iz >= N:
					continue
				if _img.get_pixel(ix, iz).b < 0.5:
					neufs[clampi(t, 0, 3)] += 1
				_img.set_pixel(ix, iz, dir_c)
		_sale = true
		# plants fauchés : ils éclatent en morceaux de sprite qui volent, avec un bruit de feuillage (issues #8, #131)
		if dust:
			var sol := p.y - 0.5
			for w in car.wheels:
				if w.is_in_contact():
					sol = w.get_contact_point().y
					break
			var v3 := car.linear_velocity
			var avant := Vector3(fwd.x, 0.0, fwd.y)
			for t in 4:
				if neufs[t] > 0:
					var n := clampi(int(neufs[t] / 4.0 * clampf(kmh / 40.0, 0.5, 1.8)), 2, 14)
					dust.eclats_plants(Vector3(p.x, sol, p.z) + avant * 2.8, v3, sol, t, n, ECLATS[t][0])
		if audio:
			var tot: int = neufs[0] + neufs[1] + neufs[2] + neufs[3]
			if tot > 0:
				audio.feuillage(tot, kmh, neufs[0] + neufs[3] > 0)
	if _debug and Engine.get_physics_frames() % 120 == 0:
		var n := 0
		for y in range(0, N, 2):
			for x in range(0, N, 2):
				if _img.get_pixel(x, y).b > 0.5:
					n += 1
		print("[écrasement] texture liée : ", mats[0].get_shader_parameter("trample_tex") == _tex, " zone param ", mats[0].get_shader_parameter("trample_zone"), " zone ", _orig, " pixels écrasés ~", n * 4, " voiture ", c, " ", int(kmh), " km/h")
	_t -= dt
	if _sale and _t <= 0.0:
		_t = 0.08
		_sale = false
		_tex.update(_img)
