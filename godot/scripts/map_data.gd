## Données et dessin de la carte façon GPS (style de la première version) : fond sombre d'occupation du sol avec relief
## ombré, routes en vecteurs (couleur et largeur par classe, liseré sombre), emprises des bâtiments quand on zoome.
## Partagé par le mini-GPS et la grande carte (chargé une seule fois).
## Rendu économe : routes et bâtiments précalculés en maillages par carrés de 1 km (quelques appels de dessin) ; la
## largeur des routes à l'écran (en pixels, constante quel que soit le zoom) est appliquée par un shader.
extends RefCounted

static var _inst = null

const COL := [Color8(230, 140, 60), Color8(235, 200, 90), Color8(225, 215, 150), Color8(210, 210, 210),
	Color8(180, 185, 190), Color8(140, 145, 150), Color8(120, 105, 85)]
const WID := [11.0, 9.0, 8.0, 7.0, 6.0, 4.5, 3.5]
const BLD := Color8(92, 96, 108)
const CHUNK := 1024.0

const ROAD_SHADER := """
shader_type canvas_item;
uniform float ppm = 1.0;          // pixels par mètre
uniform float px_scale = 1.0;
uniform bool outline = false;
const float WIDTHS[7] = float[](11.0, 9.0, 8.0, 7.0, 6.0, 4.5, 3.5);
void vertex() {
	// UV = direction de décalage × (classe + 1) : la longueur code la classe de la route
	float c = floor(length(UV) + 0.5) - 1.0;
	vec2 dir = normalize(UV);
	float w = WIDTHS[int(clamp(c, 0.0, 6.0))] * px_scale * clamp(sqrt(ppm / 0.5), 0.3, 1.0);
	bool hide = (c >= 5.0 && ppm < 0.12) || (c > 3.5 && c < 4.5 && ppm < 0.05) || (c > 5.5 && ppm < 0.25);
	w = outline ? max(w * 1.45, 2.4) : max(w, 1.3);
	VERTEX += dir * (hide ? 0.0 : w * 0.5 / ppm);
	if (outline) { COLOR = vec4(0.03, 0.04, 0.055, 0.8); }
	if (hide) { COLOR.a = 0.0; }
}
"""

var bg: Texture2D
var meta: Dictionary
var bg_rect: Rect2
var road_chunks := {}        # Vector2i -> ArrayMesh
var bld_chunks := {}         # Vector2i -> ArrayMesh
var road_mat: ShaderMaterial
var outline_mat: ShaderMaterial

static func get_inst():
	if _inst == null:
		_inst = load("res://scripts/map_data.gd").new()
	return _inst

func _init() -> void:
	meta = JSON.parse_string(FileAccess.get_file_as_string("res://world/map.json"))
	bg = load("res://assets/tex/gps_bg.png")
	bg_rect = Rect2(float(meta.x0), float(meta.z0), float(meta.w) * float(meta.res), float(meta.h) * float(meta.res))
	var sh := Shader.new(); sh.code = ROAD_SHADER
	road_mat = ShaderMaterial.new(); road_mat.shader = sh
	outline_mat = ShaderMaterial.new(); outline_mat.shader = sh; outline_mat.set_shader_parameter("outline", true)
	_load_roads()
	_load_buildings()

func _chunk(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CHUNK), floori(p.y / CHUNK))

func _load_roads() -> void:
	var sp := StreamPeerBuffer.new()
	sp.data_array = FileAccess.get_file_as_bytes("res://world/gps_roads.bin")
	var n := sp.get_32()
	var acc := {}                # chunk -> [verts, uvs, uv2, cols, idx]
	for i in n:
		var c := sp.get_32(); var k := sp.get_32()
		for j in 4:
			sp.get_float()
		var pts := PackedVector2Array(); pts.resize(k)
		for j in k:
			pts[j] = Vector2(sp.get_float(), sp.get_float())
		for j in k - 1:
			var a := pts[j]; var b := pts[j + 1]
			var d := b - a
			if d.length() < 0.01:
				continue
			var nrm := Vector2(-d.y, d.x).normalized()
			var key := _chunk((a + b) * 0.5)
			if not acc.has(key):
				acc[key] = [PackedVector2Array(), PackedVector2Array(), PackedVector2Array(), PackedColorArray(), PackedInt32Array()]
			var A: Array = acc[key]
			var base: int = A[0].size()
			# quadrilatère du tronçon (décalé par le shader) + petits « joints » aux extrémités (carrés tournés)
			for q in [[a, nrm], [a, -nrm], [b, nrm], [b, -nrm]]:
				A[0].append(q[0]); A[1].append(q[1] * (c + 1)); A[3].append(COL[c])
			A[4].append_array([base, base + 1, base + 2, base + 1, base + 3, base + 2])
			var dn := d.normalized()
			var jb: int = A[0].size()
			for q in [nrm, dn, -nrm, -dn]:
				A[0].append(b); A[1].append(q * (c + 1)); A[3].append(COL[c])
			A[4].append_array([jb, jb + 1, jb + 2, jb, jb + 2, jb + 3])
	for key in acc:
		var A: Array = acc[key]
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = A[0]; arr[Mesh.ARRAY_TEX_UV] = A[1]
		arr[Mesh.ARRAY_COLOR] = A[3]; arr[Mesh.ARRAY_INDEX] = A[4]
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		road_chunks[key] = m

func _load_buildings() -> void:
	var sp := StreamPeerBuffer.new()
	sp.data_array = FileAccess.get_file_as_bytes("res://world/gps_bld.bin")
	var n := sp.get_32()
	var acc := {}
	for i in n:
		var k := sp.get_32()
		for j in 4:
			sp.get_float()
		var pts := PackedVector2Array(); pts.resize(k)
		for j in k:
			pts[j] = Vector2(sp.get_float(), sp.get_float())
		var tri := Geometry2D.triangulate_polygon(pts)
		if tri.is_empty():
			continue
		var key := _chunk(pts[0])
		if not acc.has(key):
			acc[key] = [PackedVector2Array(), PackedInt32Array()]
		var A: Array = acc[key]
		var base: int = A[0].size()
		A[0].append_array(pts)
		for t in tri:
			A[1].append(base + t)
	for key in acc:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = acc[key][0]; arr[Mesh.ARRAY_INDEX] = acc[key][1]
		var cols := PackedColorArray(); cols.resize(acc[key][0].size()); cols.fill(BLD)
		arr[Mesh.ARRAY_COLOR] = cols
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		bld_chunks[key] = m

## Couches de dessin (enfants du contrôle, chacune avec son matériau) : à créer une fois par vue.
func make_layers(parent: Control) -> Array:
	var out := []
	for m in [null, outline_mat, road_mat]:
		var l := Control.new()
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.set_anchors_preset(Control.PRESET_FULL_RECT)
		if m:
			l.material = m.duplicate()
		parent.add_child(l)
		out.append(l)
	return out

## Dessine sur les couches (fond + bâtiments, liseré, routes) ; xf : monde -> écran ; view : partie visible (monde).
func draw_layers(layers: Array, xf: Transform2D, ppm: float, view: Rect2, px_scale := 1.0) -> void:
	for l in layers:
		if not l.has_meta("relie"):
			l.draw.connect(_draw_layer.bind(l))
			l.set_meta("relie", true)
		l.set_meta("xf", xf); l.set_meta("ppm", ppm); l.set_meta("view", view)
		if l.material:
			l.material.set_shader_parameter("ppm", ppm)
			l.material.set_shader_parameter("px_scale", px_scale)
		l.queue_redraw()

func _draw_layer(l: Control) -> void:
	var xf: Transform2D = l.get_meta("xf"); var ppm: float = l.get_meta("ppm"); var view: Rect2 = l.get_meta("view")
	var c0 := _chunk(view.position); var c1 := _chunk(view.end)
	l.draw_set_transform_matrix(xf)
	if l.material == null:
		l.draw_rect(view.grow(view.size.length()), Color8(20, 26, 34))
		l.draw_texture_rect(bg, bg_rect, false)
		if ppm > 0.45:
			for cx in range(c0.x, c1.x + 1):
				for cz in range(c0.y, c1.y + 1):
					var m: ArrayMesh = bld_chunks.get(Vector2i(cx, cz))
					if m:
						l.draw_mesh(m, null)
	else:
		for cx in range(c0.x, c1.x + 1):
			for cz in range(c0.y, c1.y + 1):
				var m: ArrayMesh = road_chunks.get(Vector2i(cx, cz))
				if m:
					l.draw_mesh(m, null)
	l.draw_set_transform_matrix(Transform2D.IDENTITY)

## Flèche du joueur (écran), pointe vers dir.
static func arrow(ci: CanvasItem, c: Vector2, dir: Vector2, s: float, col := Color8(255, 176, 32)) -> void:
	var d := dir.normalized(); var n := Vector2(-d.y, d.x)
	var pts := PackedVector2Array([c + d * s, c - d * s * 0.8 + n * s * 0.75, c - d * s * 0.35, c - d * s * 0.8 - n * s * 0.75])
	ci.draw_colored_polygon(pts, col)
	pts.append(pts[0])
	ci.draw_polyline(pts, Color.BLACK, 3.0, true)
