## Rétroviseur (#163, demande de l'utilisateur) : en vue extérieure, en haut au centre comme dans les jeux de course,
## l'arrière de la voiture vu par une petite caméra posée sur le toit (image retournée comme un miroir). Économie :
## image de TAILLE pixels, refaite une image sur PAS (≈ 15 fois par seconde), vue jusqu'à LOIN m. Masqué au poste de
## conduite, dans les menus et quand la vue extérieure n'est pas affichée. ⚙ > Conduite > Rétroviseur.
extends Control
const TAILLE := Vector2i(320, 88)
const PAS := 4
const LOIN := 220.0
const ECRAN := Vector2(500, 138)          # taille à l'écran (repère 1920 × 1080 : entre les icônes et la mini-carte)

var main: Node
var actif := true
var _vp: SubViewport
var _cam: Camera3D
var _n := 0

func _ready() -> void:
	name = "Retro"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cfg := ConfigFile.new()
	if cfg.load("user://reglages.cfg") == OK:
		actif = bool(cfg.get_value("conduite", "retroviseur", true))
	_vp = SubViewport.new()
	_vp.size = TAILLE
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	_vp.positional_shadow_atlas_size = 0
	_vp.audio_listener_enable_3d = false
	_vp.handle_input_locally = false
	_cam = Camera3D.new()
	_cam.fov = 38.0
	_cam.near = 0.3
	_cam.far = LOIN
	_vp.add_child(_cam)
	add_child(_vp)
	var cadre := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.06, 0.07)
	sb.set_corner_radius_all(22)
	sb.border_color = Color(0.25, 0.25, 0.28)
	sb.set_border_width_all(5)
	cadre.add_theme_stylebox_override("panel", sb)
	cadre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cadre.size = ECRAN + Vector2(16, 16)
	add_child(cadre)
	var img := TextureRect.new()
	img.texture = _vp.get_texture()
	img.flip_h = true                         # miroir
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_SCALE
	img.position = Vector2(8, 8)
	img.size = ECRAN
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(img)
	size = ECRAN + Vector2(16, 16)

func _process(_dt: float) -> void:
	var car = main.get("car") if main else null
	var rig = main.get("cam_rig") if main else null
	var voir: bool = actif and car != null and not car.blown and is_visible_in_tree() \
		and (rig == null or rig.mode != 1) and not get_tree().paused
	var vs := get_viewport().get_visible_rect().size
	position = Vector2((vs.x - size.x) * 0.5, 14)
	(get_child(1) as Control).visible = voir          # cadre
	(get_child(2) as Control).visible = voir          # image
	if not voir:
		_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	var xf: Transform3D = car.global_transform
	var g: Vector3 = car.gabarit
	var o := xf.origin + xf.basis.y * (g.y + 0.25) - xf.basis.z * (g.z * 0.35)
	_cam.global_transform = Transform3D(Basis.IDENTITY, o)
	_cam.look_at(o - xf.basis.z * 30.0 + xf.basis.y * 0.5, xf.basis.y)
	_n += 1
	if _n % PAS == 0:
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
