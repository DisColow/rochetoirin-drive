## Petit champignon atomique façon dessin animé (#121) : la voiture lancée contre un obstacle indestructible explose.
## Éclair, pied qui monte, chapeau qui gonfle et passe du jaune au gris, anneau autour du pied, jupe de poussière au sol,
## « KA-BOOM ! » ; couleurs pleines sans éclairage et contour noir (coque inversée) comme un cartoon. ~7 m de haut, 3,4 s.
extends Node3D

const DUREE := 3.4
var _t := 0.0
var _parts := {}                     # nom -> [MeshInstance3D, StandardMaterial3D, contour MeshInstance3D]
var _texte: Label3D

func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	return m

func _piece(nom: String, mesh: Mesh, c: Color) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := _mat(c)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var o := MeshInstance3D.new()             # contour : même maillage un peu plus gros, faces arrière en noir
	o.mesh = mesh
	var om := _mat(Color.BLACK)
	om.cull_mode = BaseMaterial3D.CULL_FRONT
	o.material_override = om
	o.scale = Vector3.ONE * 1.08
	o.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.add_child(o)
	_parts[nom] = [mi, m]

func _ready() -> void:
	var sp := SphereMesh.new(); sp.radius = 1.0; sp.height = 2.0; sp.radial_segments = 20; sp.rings = 10
	var cy := CylinderMesh.new(); cy.top_radius = 0.7; cy.bottom_radius = 1.0; cy.height = 1.0; cy.radial_segments = 16
	var to := TorusMesh.new(); to.inner_radius = 0.9; to.outer_radius = 1.5; to.rings = 20; to.ring_segments = 10
	_piece("jupe", sp, Color(0.85, 0.6, 0.3))
	_piece("pied", cy, Color(1.0, 0.75, 0.2))
	_piece("anneau", to, Color(1.0, 0.6, 0.15))
	_piece("chapeau", sp, Color(1.0, 0.95, 0.4))
	_piece("eclair", sp, Color(1.0, 1.0, 0.85))
	_texte = Label3D.new()
	_texte.text = "KA-BOOM !"
	_texte.font_size = 180
	_texte.pixel_size = 0.012
	_texte.outline_size = 40
	_texte.modulate = Color(1.0, 0.9, 0.15)
	_texte.outline_modulate = Color(0.75, 0.05, 0.05)
	_texte.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_texte.no_depth_test = true
	add_child(_texte)
	_maj()

static func _cloche(x: float, a: float, b: float) -> float:
	return clampf(x / a, 0.0, 1.0) * (1.0 - clampf((x - b) / (1.0 - b), 0.0, 1.0))

func _process(dt: float) -> void:
	_t += dt
	if _t >= DUREE:
		queue_free()
		return
	_maj()

func _maj() -> void:
	var x := _t / DUREE
	var monte := 1.0 - pow(1.0 - clampf(x / 0.45, 0.0, 1.0), 3.0)          # pied qui jaillit puis ralentit
	var vie := 1.0 - clampf((x - 0.8) / 0.2, 0.0, 1.0)                     # tout se résorbe à la fin
	var h := 5.2 * monte
	var gris := clampf((x - 0.25) / 0.5, 0.0, 1.0)
	var e: MeshInstance3D = _parts.eclair[0]
	var fe := _cloche(x, 0.03, 0.12) * 3.2
	e.scale = Vector3.ONE * maxf(fe, 0.001)
	e.position = Vector3(0, 1.0, 0)
	e.visible = fe > 0.01
	var j: MeshInstance3D = _parts.jupe[0]
	var rj := 3.4 * clampf(x / 0.2, 0.0, 1.0) * vie
	j.scale = Vector3(rj, rj * 0.22, rj) + Vector3.ONE * 0.001
	(_parts.jupe[1] as StandardMaterial3D).albedo_color = Color(0.85, 0.6, 0.3).lerp(Color(0.55, 0.5, 0.45), gris)
	var p: MeshInstance3D = _parts.pied[0]
	p.scale = Vector3(0.75 * vie, maxf(h, 0.01), 0.75 * vie) + Vector3.ONE * 0.001
	p.position = Vector3(0, h * 0.5, 0)
	(_parts.pied[1] as StandardMaterial3D).albedo_color = Color(1.0, 0.75, 0.2).lerp(Color(0.6, 0.52, 0.45), gris)
	var a: MeshInstance3D = _parts.anneau[0]
	var ra := (0.6 + 0.9 * clampf((x - 0.15) / 0.4, 0.0, 1.0)) * vie * monte
	a.scale = Vector3(ra, ra * 0.8, ra) + Vector3.ONE * 0.001
	a.position = Vector3(0, h * 0.55, 0)
	(_parts.anneau[1] as StandardMaterial3D).albedo_color = Color(1.0, 0.6, 0.15).lerp(Color(0.5, 0.45, 0.42), gris)
	var c: MeshInstance3D = _parts.chapeau[0]
	var rc := (0.6 + 1.9 * monte) * vie * (1.0 + 0.06 * sin(_t * 18.0) * (1.0 - gris))
	c.scale = Vector3(rc, rc * 0.68, rc) + Vector3.ONE * 0.001
	c.position = Vector3(0, h + rc * 0.35, 0)
	(_parts.chapeau[1] as StandardMaterial3D).albedo_color = Color(1.0, 0.95, 0.4).lerp(Color(1.0, 0.45, 0.1), clampf(x / 0.25, 0.0, 1.0)).lerp(Color(0.62, 0.58, 0.55), gris)
	var tp := _cloche(x, 0.08, 0.7)
	_texte.scale = Vector3.ONE * maxf(tp * (1.0 + 0.15 * sin(_t * 14.0)), 0.001)
	_texte.position = Vector3(0, h + rc + 1.6, 0)
	_texte.visible = tp > 0.01
