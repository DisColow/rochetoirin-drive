## Vue cockpit en pixel art (à la manière des vieux jeux de voitures) : l'habitacle de l'Espace I est dessiné dans une
## petite image de 480 pixels de large (build_cockpit.py) affichée en gros pixels par-dessus la route en 3D.
## Animé : aiguilles des compteurs, volant tourné avec la direction et mains dessus, heure sur l'autoradio, voyant des
## phares, lettre de la boîte, rétroviseur (vraie vue arrière en basse résolution), sapin désodorisant qui se balance,
## habitacle qui suit les secousses ; éclairé selon l'heure de la journée (compteurs rétroéclairés la nuit).
extends CanvasLayer

const VW := 480
const DIR := "res://assets/cockpit/"

var car: VehicleBody3D
var main: Node
var eye := Vector3.ZERO
var active := false

var vp: SubViewport
var view: TextureRect
var back: Node2D
var lit: Node2D
var glow: Node2D
var front: Node2D
var mirror_vp: SubViewport
var mirror_cam: Camera3D
var meta: Dictionary
var tex := {}
var vh := 216
var _speed := 0.0
var _rpm := 800.0
var _pine_a := 0.0
var _pine_v := 0.0
var _prev_v := Vector3.ZERO
var _bob := 0.0
var _bob_v := 0.0
var _frame := 0
var _clock := 0.0
# pluie : gouttes sur le pare-brise (x, y, taille, âge) et essuie-glaces
var rain := 0.0
var drops := []
var _wipe := 0.0
var _wipe_prev := 0.0
var _rng := RandomNumberGenerator.new()

const FONT := {
	"0": "111101101101111", "1": "010110010010111", "2": "111001111100111", "3": "111001111001111",
	"4": "101101111001001", "5": "111100111001111", "6": "111100111101111", "7": "111001010010010",
	"8": "111101111101111", "9": "111101111001111", ":": "000010000010000", "P": "111101111100100",
	"R": "110101110101101", "N": "101111111111101", "D": "110101101101110", " ": "000000000000000",
}

func _ready() -> void:
	layer = 0
	meta = JSON.parse_string(FileAccess.get_file_as_string(DIR + "meta.json"))
	for n in ["dash", "glow", "top", "wheel", "hand_l", "hand_r", "pillar", "sleeve", "pine"]:
		tex[n] = load(DIR + n + ".png")
	vp = SubViewport.new()
	vp.disable_3d = true
	vp.transparent_bg = true
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(vp)
	for k in ["back", "lit", "glow", "front"]:
		var n := Node2D.new()
		n.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		vp.add_child(n)
		set(k, n)
	back.draw.connect(_draw_back)
	lit.draw.connect(_draw_lit)
	glow.draw.connect(_draw_glow)
	front.draw.connect(_draw_front)
	view = TextureRect.new()
	view.texture = vp.get_texture()
	view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_SCALE
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(view)
	# rétroviseur : deuxième caméra, minuscule (60 × 15 pixels), vers l'arrière
	mirror_vp = SubViewport.new()
	var m: Array = meta.mirror
	mirror_vp.size = Vector2i(int(m[2]), int(m[3]))
	mirror_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	mirror_vp.msaa_3d = Viewport.MSAA_DISABLED
	add_child(mirror_vp)
	mirror_cam = Camera3D.new()
	mirror_cam.keep_aspect = Camera3D.KEEP_WIDTH
	mirror_cam.fov = 48.0
	mirror_cam.near = 0.3
	mirror_cam.far = 600.0
	mirror_vp.add_child(mirror_cam)
	mirror_cam.current = true
	get_viewport().size_changed.connect(_resize)
	_resize()
	set_active(false)

func _resize() -> void:
	var s := get_viewport().get_visible_rect().size
	vh = clampi(int(round(VW * s.y / maxf(s.x, 1.0))), 160, 400)
	vp.size = Vector2i(VW, vh)

func set_active(on: bool) -> void:
	active = on
	view.visible = on
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	mirror_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if car and car.has_method("set_cockpit"):
		car.set_cockpit(on)
	_prev_v = car.linear_velocity if car else Vector3.ZERO

# ---------------------------------------------------------------- animation
func _process(dt: float) -> void:
	if not active or car == null:
		return
	view.visible = not car.blown
	_frame += 1
	_clock += dt
	var t := car.global_transform
	# rétroviseur : vue arrière rafraîchie un affichage sur deux
	mirror_cam.global_transform = Transform3D(Basis.looking_at(-t.basis.z, t.basis.y), t * Vector3(0.0, eye.y + 0.02, eye.z + 0.55))
	mirror_vp.render_target_update_mode = SubViewport.UPDATE_ONCE if _frame % 2 == 0 else SubViewport.UPDATE_DISABLED
	var kmh: float = car.kmh()
	_speed = lerpf(_speed, kmh, 1.0 - exp(-dt * 8.0))
	# régime d'une boîte automatique à 4 rapports
	var tops := [38.0, 70.0, 110.0, 190.0]
	var g := 0
	while g < 3 and kmh > tops[g] * 0.86:
		g += 1
	var thr: float = maxf(Input.get_action_strength("accelerer"), car.touch_throttle)
	var want := 850.0 + clampf(kmh / tops[g], 0.0, 1.0) * 5000.0 + thr * 700.0
	if kmh < 3.0:
		want = 850.0 + thr * 1800.0
	_rpm = lerpf(_rpm, want, 1.0 - exp(-dt * 5.0))
	# accélérations ressenties (repère de la voiture) : sapin et secousses
	var v := car.linear_velocity
	var acc := (v - _prev_v) / maxf(dt, 0.001)
	_prev_v = v
	var lat := acc.dot(t.basis.x)
	var lon := acc.dot(t.basis.z)
	_pine_v += (-_pine_a * 30.0 - _pine_v * 2.2 - lat * 0.09) * dt
	_pine_a = clampf(_pine_a + _pine_v * dt, -1.1, 1.1)
	var vert := acc.dot(t.basis.y) + lon * 0.15
	_bob_v += (-_bob * 180.0 - _bob_v * 18.0 - clampf(vert, -40.0, 40.0) * 0.12) * dt
	_bob = clampf(_bob + _bob_v * dt, -3.0, 3.0)
	_rain_update(dt, kmh)
	var off := Vector2(0, round(_bob))
	for n in [lit, glow, front, back]:
		n.position = off
	# éclairage de l'habitacle selon l'heure
	var amb: Color = [Color(0.96, 0.96, 0.96), Color(0.95, 0.86, 0.74), Color(0.78, 0.56, 0.46), Color(0.17, 0.19, 0.28)][_tod()]
	lit.modulate = amb
	front.modulate = amb
	for n in [back, lit, glow, front]:
		n.queue_redraw()

const WIPERS := [[Vector2(62, 0), 96.0], [Vector2(252, 0), 92.0]]     # pivot (y : pied du pare-brise), longueur

func _wiper_angle(ph: float) -> float:
	# 0 : à plat vers la droite ; monte jusqu'à 100° (aller-retour avec un temps d'arrêt en bas)
	var t := fposmod(ph, 1.0)
	var u := clampf(t / 0.8, 0.0, 1.0)
	return deg_to_rad(100.0) * sin(u * PI)

func _rain_update(dt: float, kmh: float) -> void:
	if rain <= 0.01 and drops.is_empty():
		return
	var base := float(vh - 100) + 13.0
	# nouvelles gouttes
	var n := int(rain * dt * 60.0 + _rng.randf())
	for i in n:
		drops.append([_rng.randf_range(24, 456), _rng.randf_range(16, base - 4), _rng.randi_range(1, 3), 0.0])
	# les gouttes glissent vers le bas, ou vers le haut et les côtés quand on roule vite
	var up := clampf((kmh - 50.0) / 60.0, 0.0, 1.0)
	for d in drops:
		d[3] += dt
		d[1] += (6.0 * (1.0 - up) - 30.0 * up) * dt * (0.3 + 0.2 * d[2])
		d[0] += (float(d[0]) - 240.0) * 0.6 * up * dt
	# essuie-glaces : balayage qui efface les gouttes
	if rain > 0.01:
		_wipe += dt / 1.3
	elif fposmod(_wipe, 1.0) > 0.01:
		_wipe = minf(_wipe + dt / 1.3, ceil(_wipe))
	var a0 := _wiper_angle(_wipe_prev); var a1 := _wiper_angle(_wipe)
	_wipe_prev = _wipe
	var lo := minf(a0, a1) - 0.03; var hi := maxf(a0, a1) + 0.03
	var keep := []
	for d in drops:
		var gone: bool = d[1] < 10.0 or d[1] > base or d[0] < 10.0 or d[0] > 470.0 or d[3] > 25.0
		if not gone:
			for w in WIPERS:
				var piv: Vector2 = Vector2(w[0].x, base)
				var v := Vector2(d[0], d[1]) - piv
				var ang := atan2(-v.y, v.x)
				if v.length() < float(w[1]) and ang >= lo and ang <= hi:
					gone = true
		if not gone:
			keep.append(d)
	drops = keep
	if drops.size() > 260:
		drops = drops.slice(drops.size() - 260)

func _draw_rain() -> void:
	if drops.is_empty() and rain <= 0.01:
		return
	var amb: Color = lit.modulate
	var hi := Color(0.85, 0.9, 0.95) * amb; hi.a = 0.85
	var lo := Color(0.25, 0.28, 0.32) * amb; lo.a = 0.7
	for d in drops:
		var p := Vector2(round(d[0]), round(d[1]))
		var sz: int = d[2]
		if sz >= 2:
			back.draw_rect(Rect2(p, Vector2(sz, sz)), Color(0.55, 0.6, 0.66, 0.45) * amb)
		back.draw_rect(Rect2(p, Vector2(1, 1)), hi)
		back.draw_rect(Rect2(p + Vector2(0, sz), Vector2(maxf(sz - 1, 1), 1)), lo)
	# essuie-glaces (bras et balais noirs), pieds cachés par la planche de bord
	var base := float(vh - 100) + 13.0
	var a := _wiper_angle(_wipe)
	for w in WIPERS:
		var piv := Vector2(w[0].x, base + 4.0)
		var dirv := Vector2(cos(a), -sin(a))
		var tip: Vector2 = piv + dirv * float(w[1])
		var col := Color(0.04, 0.04, 0.045)
		back.draw_line(piv, piv + dirv * float(w[1]) * 0.55, col, 2.0)
		back.draw_line(piv + dirv * float(w[1]) * 0.25, tip, col, 1.0)
		var n := Vector2(-dirv.y, dirv.x)
		back.draw_line(piv + dirv * float(w[1]) * 0.3 + n, tip + n, Color(0.12, 0.12, 0.13), 1.0)

func _tod() -> int:
	return int(main.time_of_day) if main and "time_of_day" in main else 0

func _night() -> float:
	return [0.0, 0.0, 0.45, 1.0][_tod()]

# ---------------------------------------------------------------- dessin
func _draw_back() -> void:
	var m: Array = meta.mirror
	back.draw_set_transform(Vector2(float(m[0]) + float(m[2]), float(m[1])), 0.0, Vector2(-1, 1))
	back.draw_texture_rect(mirror_vp.get_texture(), Rect2(0, 0, float(m[2]), float(m[3])), false, Color(0.82, 0.84, 0.88))
	back.draw_set_transform(Vector2.ZERO)
	_draw_rain()

func _pillar(ci: CanvasItem, pts: PackedVector2Array) -> void:
	var uv := PackedVector2Array()
	var w := maxf(pts[1].x - pts[0].x, 1.0)
	for p in pts:
		uv.append(Vector2((p.x - lerpf(pts[0].x, pts[3].x, p.y / maxf(pts[3].y, 1.0))) / w, p.y / 8.0))
	ci.draw_polygon(pts, PackedColorArray(), uv, tex.pillar)

func _draw_lit() -> void:
	var dy := float(vh - 100)
	# montants de pare-brise (le gauche, tout près du conducteur, est plus large)
	_pillar(lit, PackedVector2Array([Vector2(0, 0), Vector2(46, 0), Vector2(20, dy + 12), Vector2(0, dy + 12)]))
	lit.draw_line(Vector2(46, 0), Vector2(20, dy + 12), Color(0.05, 0.05, 0.055), 1.0)
	_pillar(lit, PackedVector2Array([Vector2(446, 0), Vector2(480, 0), Vector2(480, dy + 12), Vector2(464, dy + 12)]))
	lit.draw_line(Vector2(446, 0), Vector2(464, dy + 12), Color(0.05, 0.05, 0.055), 1.0)
	lit.draw_texture(tex.top, Vector2.ZERO)
	lit.draw_texture(tex.dash, Vector2(0, dy))

func _px_text(ci: CanvasItem, p: Vector2, s: String, col: Color) -> void:
	for ch in s:
		var gl: String = FONT.get(ch, FONT[" "])
		for k in 15:
			if gl[k] == "1":
				ci.draw_rect(Rect2(p.x + k % 3, p.y + k / 3, 1, 1), col)
		p.x += 4

func _needle(c: Vector2, r: float, a_deg: float, col: Color) -> void:
	var a := deg_to_rad(a_deg)
	var d := Vector2(sin(a), -cos(a))
	glow.draw_line(c - d * 3.0, c + d * r, col, -1.0)
	glow.draw_line(c - d * 2.0 + Vector2(d.y, -d.x) * 0.6, c + d * (r - 3.0) + Vector2(d.y, -d.x) * 0.6, col.darkened(0.25), -1.0)
	glow.draw_rect(Rect2(c - Vector2(1.5, 1.5), Vector2(3, 3)), Color(0.08, 0.08, 0.09))

func _draw_glow() -> void:
	var dy := float(vh - 100)
	var night := _night()
	var amb: Color = lit.modulate
	if night > 0.0:
		glow.draw_texture(tex.glow, Vector2(0, dy), Color(1, 1, 1, night))
	var G: Dictionary = meta.gauges
	var nd := (Color(1.0, 0.42, 0.08) * amb).lerp(Color(1.0, 0.5, 0.15), night)
	nd.a = 1.0
	var s: Array = G.speed; var r: Array = G.rpm; var f: Array = G.fuel; var tp: Array = G.temp
	_needle(Vector2(s[0], float(s[1]) + dy) + Vector2(0.5, 0.5), float(s[2]) - 2.5, -125.0 + 250.0 * clampf(_speed / 200.0, 0.0, 1.0), nd)
	_needle(Vector2(r[0], float(r[1]) + dy) + Vector2(0.5, 0.5), float(r[2]) - 2.5, -125.0 + 250.0 * clampf(_rpm / 7000.0, 0.0, 1.0), nd)
	_needle(Vector2(f[0], float(f[1]) + dy) + Vector2(0.5, 0.5), float(f[2]) - 2.0, 32.0, nd)
	_needle(Vector2(tp[0], float(tp[1]) + dy) + Vector2(0.5, 0.5), float(tp[2]) - 2.0, -6.0 + sin(_clock * 0.05) * 3.0, nd)
	# voyant vert des feux
	var L: Array = meta.lamps
	if car.get("_beams") and not car._beams.is_empty() and car._beams[0].visible:
		var p: Array = L[0]
		glow.draw_rect(Rect2(float(p[0]) - 2, float(p[1]) - 2 + dy, 5, 4), Color(0.2, 0.95, 0.3))
	# heure sur l'autoradio
	var lcd: Array = meta.lcd
	var hm: Array = [[12, 0], [17, 30], [20, 45], [23, 10]][_tod()]
	var mins := int(hm[0]) * 60 + int(hm[1]) + int(_clock / 60.0)
	var txt := "%2d:%02d" % [(mins / 60) % 24, mins % 60]
	var lc := Color(0.3, 0.85, 0.45).lerp(Color(0.45, 1.0, 0.6), night)
	if night == 0.0:
		lc = lc * amb * 0.8
	lc.a = 1.0
	_px_text(glow, Vector2(float(lcd[0]) + 6, float(lcd[1]) + 1 + dy), txt, lc)
	# lettre de la boîte automatique
	var gpos: Array = meta.gear
	var gi := 1 if car.reversing else (0 if absf(car.kmh()) < 0.5 and car.touch_throttle == 0.0 and Input.get_action_strength("accelerer") == 0.0 else 3)
	var gc := Color(1.0, 0.75, 0.3) * (amb if night == 0.0 else Color.WHITE)
	gc.a = 1.0
	_px_text(glow, Vector2(float(gpos[0]) + gi * 8, float(gpos[1]) + dy), "PRND"[gi], gc)

func _draw_front() -> void:
	var dy := float(vh - 100)
	var c := Vector2(240, dy + 80)
	var rot := -clampf(car.steer_value / 0.55, -1.0, 1.0) * deg_to_rad(125.0)
	var rr := float(meta.wheel_r) - float(meta.wheel_t) / 2.0
	var hands := []
	# les mains suivent la jante sur ±35°, puis la jante glisse dedans (pas de bras croisés devant les compteurs)
	var hr := clampf(rot, -deg_to_rad(35.0), deg_to_rad(35.0))
	for k in [[-58.0, Vector2(40, vh + 60), "hand_l"], [58.0, Vector2(440, vh + 60), "hand_r"]]:
		var a := deg_to_rad(float(k[0])) + hr
		hands.append([c + Vector2(sin(a), -cos(a)) * rr, k[1], k[2]])
	# avant-bras (manches du pull) : du bas de l'écran jusqu'aux mains
	for h in hands:
		var hp: Vector2 = h[0]; var sh: Vector2 = h[1]
		var d := (hp - sh).normalized()
		var n := Vector2(-d.y, d.x)
		var pts := PackedVector2Array([sh - n * 26.0, sh + n * 26.0, hp + d * 2.0 + n * 7.0, hp + d * 2.0 - n * 7.0])
		var uv := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 6), Vector2(0, 6)])
		front.draw_polygon(pts, PackedColorArray(), uv, tex.sleeve)
	front.draw_set_transform(c, rot, Vector2.ONE)
	front.draw_texture(tex.wheel, Vector2(-80, -80))
	front.draw_set_transform(Vector2.ZERO)
	for h in hands:
		var hp: Vector2 = h[0]
		front.draw_texture(tex[h[2]], (hp - Vector2(11, 10)).round())
	# sapin désodorisant pendu au rétroviseur
	var m: Array = meta.mirror
	var piv := Vector2(float(m[0]) + float(m[2]) * 0.5 + 8.0, float(m[1]) + float(m[3]) + 3.0)
	var dirv := Vector2(sin(_pine_a), cos(_pine_a))
	front.draw_line(piv, piv + dirv * 7.0, Color(0.85, 0.85, 0.8), -1.0)
	front.draw_set_transform(piv + dirv * 7.0, -_pine_a, Vector2.ONE)
	front.draw_texture(tex.pine, Vector2(-5, 0))
	front.draw_set_transform(Vector2.ZERO)
