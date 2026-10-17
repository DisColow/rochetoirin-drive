## Menu des activités en plein écran (#119) : un onglet par activité (Épreuves, Course libre, Taxi, Chasse au lieu,
## Garage, Multijoueur). Onglet Épreuves (#112) : liste avec l'icône de la médaille gagnée, et pour l'épreuve
## touchée, la carte du tracé (carte_trace.gd), le meilleur temps, les temps des médailles, Lancer et Retour.
## Les actions appellent celles d'activities.gd (act).
extends Control

const UI := preload("res://scripts/ui.gd")
const ONGLETS := ["Épreuves", "Course libre", "Taxi", "Chasse au lieu", "Garage", "Multijoueur"]

var act: Node
var onglet := 0
var choix := -1                      # épreuve affichée dans la fiche (-1 : aucune)
var _tabs: Array = []
var _corps: Control

class Medaille extends Control:
	## Pastille de médaille dessinée (or, argent, bronze ; vide : cercle gris pointillé) avec son ruban.
	var med := ""
	func _init(m: String, s := 44.0) -> void:
		med = m
		custom_minimum_size = Vector2(s, s)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var s := size.y
		var c := Vector2(s * 0.5, s * 0.6)
		var r := s * 0.34
		if med == "":
			draw_arc(c, r, 0, TAU, 32, Color(1, 1, 1, 0.25), 3.0, true)
			return
		var col: Color = {"or": Color(1.0, 0.8, 0.15), "argent": Color(0.82, 0.84, 0.88), "bronze": Color(0.8, 0.5, 0.25)}[med]
		draw_colored_polygon(PackedVector2Array([Vector2(c.x - r * 0.9, 0), Vector2(c.x - r * 0.1, 0), Vector2(c.x, c.y - r * 0.5), Vector2(c.x - r * 0.4, c.y - r * 0.6)]), Color(0.2, 0.35, 0.85))
		draw_colored_polygon(PackedVector2Array([Vector2(c.x + r * 0.9, 0), Vector2(c.x + r * 0.1, 0), Vector2(c.x, c.y - r * 0.5), Vector2(c.x + r * 0.4, c.y - r * 0.6)]), Color(0.85, 0.2, 0.25))
		draw_circle(c, r + 2.0, Color.BLACK)
		draw_circle(c, r, col)
		draw_circle(c, r * 0.68, col.darkened(0.18))
		draw_circle(c + Vector2(-r * 0.3, -r * 0.3), r * 0.18, Color(1, 1, 1, 0.55))

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group("ui_zone")
	# plein écran : la taille suit la fenêtre (les ancres seules ne suffisent pas, le parent n'est pas un Control)
	size = get_viewport_rect().size
	get_viewport().size_changed.connect(func(): size = get_viewport_rect().size)
	var fond := ColorRect.new()
	fond.color = Color(0.06, 0.07, 0.09, 0.97)
	fond.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(fond)
	var cadre := Panel.new()
	cadre.set_anchors_preset(Control.PRESET_FULL_RECT)
	cadre.add_theme_stylebox_override("panel", UI.panel(0, 0))
	cadre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cadre)
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	for k in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + k, 28)
	add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	m.add_child(v)
	var haut := HBoxContainer.new()
	haut.add_theme_constant_override("separation", 10)
	v.add_child(haut)
	var titre := Label.new()
	titre.text = "Activités"
	titre.add_theme_font_size_override("font_size", 46)
	haut.add_child(titre)
	var esp := Control.new()
	esp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	haut.add_child(esp)
	if act.mode != "":
		_bouton(haut, "■ Arrêter l'activité", act._stop_and_close, 0.0, 28)
	_bouton(haut, "✕ Fermer", act._resume, 0.0, 28)
	var barre := HBoxContainer.new()
	barre.add_theme_constant_override("separation", 6)
	v.add_child(barre)
	for i in ONGLETS.size():
		var b := _bouton(barre, ONGLETS[i], _aller.bind(i), 0.0, 27)
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_tabs.append(b)
	_corps = MarginContainer.new()
	_corps.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_corps)
	_aller(onglet)

func _bouton(p: Control, t: String, f: Callable, w := 0.0, fs := 30) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(w, 72)
	b.add_theme_font_size_override("font_size", fs)
	b.pressed.connect(f)
	p.add_child(b)
	return b

func _texte(p: Control, t: String, fs := 26, col := Color(1, 1, 1)) -> Label:
	var l := Label.new()
	l.text = t
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	p.add_child(l)
	return l

func _aller(i: int) -> void:
	onglet = i
	for k in _tabs.size():
		_tabs[k].set_pressed_no_signal(k == i)
	for c in _corps.get_children():
		c.queue_free()
	match i:
		0: _epreuves()
		1: _course()
		2: _taxi()
		3: _chasse()
		4: _garage()
		5: _multi()

func _colonne() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	_corps.add_child(v)
	return v

# ---------------------------------------------------------------- épreuves
func _epreuves() -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 20)
	_corps.add_child(h)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.size_flags_stretch_ratio = 0.95
	h.add_child(sc)
	var l := VBoxContainer.new()
	l.add_theme_constant_override("separation", 8)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(l)
	var c: Vector2 = act._car2()
	var tri: Array = act.epreuves.duplicate()
	tri.sort_custom(func(a, b): return c.distance_to(Vector2(a.a[0], a.a[1])) < c.distance_to(Vector2(b.a[0], b.a[1])))
	var faites := 0
	for e in tri:
		if act._medaille(int(e.id)) != "":
			faites += 1
	_texte(l, "%d / %d épreuves réussies" % [faites, tri.size()], 24, Color(1.0, 0.85, 0.45))
	if choix < 0 and not tri.is_empty():
		choix = int(tri[0].id)
	for e in tri:
		var id := int(e.id)
		var b := Button.new()
		b.toggle_mode = true
		b.button_pressed = id == choix
		b.custom_minimum_size = Vector2(0, 84)
		b.pressed.connect(func(): choix = id; _aller(0))
		l.add_child(b)
		var r := HBoxContainer.new()
		r.set_anchors_preset(Control.PRESET_FULL_RECT)
		r.offset_left = 12; r.offset_right = -12
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.add_theme_constant_override("separation", 12)
		b.add_child(r)
		var md := Medaille.new(act._medaille(id), 60.0)
		md.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		r.add_child(md)
		var t := VBoxContainer.new()
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.alignment = BoxContainer.ALIGNMENT_CENTER
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		t.add_theme_constant_override("separation", 0)
		r.add_child(t)
		var n := _texte(t, str(e.nom), 25)
		n.autowrap_mode = TextServer.AUTOWRAP_OFF
		n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var s := _texte(t, "%.1f km  ·  à %.1f km" % [float(e.km), c.distance_to(Vector2(e.a[0], e.a[1])) / 1000.0], 20, Color(1, 1, 1, 0.65))
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		s.autowrap_mode = TextServer.AUTOWRAP_OFF
	if choix >= 0:
		_fiche(h, act.epreuves[choix])

func _fiche(h: Control, e: Dictionary) -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_stretch_ratio = 1.05
	h.add_child(v)
	_texte(v, str(e.nom), 30)
	var carte := preload("res://scripts/carte_trace.gd").new()
	carte.size_flags_vertical = Control.SIZE_EXPAND_FILL
	carte.custom_minimum_size = Vector2(0, 240)
	v.add_child(carte)
	var pts := [Vector2(e.a[0], e.a[1])]
	for q in e.etapes:
		pts.append(Vector2(q[0], q[1]))
	pts.append(Vector2(e.b[0], e.b[1]))
	carte.montrer(pts)
	var id := int(e.id)
	var rec = act.main.garage.records.get(str(id)) if act.main.garage else null
	var med: String = act._medaille(id)
	var lr := HBoxContainer.new()
	lr.add_theme_constant_override("separation", 10)
	v.add_child(lr)
	lr.add_child(Medaille.new(med, 48.0))
	var lt0 := _texte(lr, ("Votre temps : " + act._fmt(float(rec))) if rec != null else ("Médaille obtenue" if med != "" else "Pas encore courue"), 26,
		Color(1.0, 0.9, 0.6))
	lt0.autowrap_mode = TextServer.AUTOWRAP_OFF             # dans une rangée : pas de retour à la ligne (calcul sans fin)
	var lt := HBoxContainer.new()
	lt.add_theme_constant_override("separation", 18)
	v.add_child(lt)
	for m in act.MEDAILLES:
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 4)
		lt.add_child(cell)
		cell.add_child(Medaille.new(m, 40.0))
		_texte(cell, act._fmt(float(e[m])), 23).autowrap_mode = TextServer.AUTOWRAP_OFF
	_texte(v, "%.1f km · %d point(s) de passage" % [float(e.km), e.etapes.size()], 21, Color(1, 1, 1, 0.65))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	v.add_child(hb)
	var go := _bouton(hb, "▶ Lancer", func(): act._close_menu(true); act._epreuve_depart(id))
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	go.disabled = act.mode != ""
	var ret := _bouton(hb, "Retour", act._resume)
	ret.size_flags_horizontal = Control.SIZE_EXPAND_FILL

# ---------------------------------------------------------------- autres onglets
func _course() -> void:
	var v := _colonne()
	_texte(v, "Posez un départ, des étapes si vous voulez, et une arrivée sur la carte : portes lumineuses, compte à "
		+ "rebours et chrono.")
	_bouton(v, "Créer un tracé", act._course_setup)
	if not act._last_route.is_empty():
		_bouton(v, "Recommencer le dernier tracé" + ("" if act._best == INF else "  (record " + act._fmt(act._best) + ")"), act._course_again)

func _taxi() -> void:
	var v := _colonne()
	_texte(v, "Prenez des clients et déposez-les à destination, guidé par le GPS. Pourboire selon la conduite, le temps "
		+ "et la conversation.")
	if act._rides > 0:
		_texte(v, "%d course(s), %s gagnés" % [act._rides, act._euros(act._total)], 26, Color(1.0, 0.9, 0.6))
	_bouton(v, "Commencer le service", act._taxi_start)

func _chasse() -> void:
	var v := _colonne()
	_texte(v, "Un joueur choisit un lieu, l'autre le cherche : la carte montre une zone qui le contient et qui rétrécit.")
	_bouton(v, "Choisir un lieu nommé (gare, mairie, église…)", func(): act._stop(); act._hunt_list())
	_bouton(v, "Choisir un endroit sur la carte", func(): act._stop(); act._hunt_map())
	_bouton(v, "Lieu tiré au sort (jouer seul)", func(): act._stop(); act._hunt_random())

func _garage() -> void:
	var v := _colonne()
	if act.main.garage:
		_texte(v, "Argent : " + act.main.garage.euros(act.main.garage.argent), 30, Color(1.0, 0.9, 0.6))
	_texte(v, "Voitures, moteur, pneus, vinyles et peinture. Arrêtez-vous pour entrer.")
	_bouton(v, "Entrer au garage", act._garage)

func _multi() -> void:
	var v := _colonne()
	var net = act.main.net
	_texte(v, "Jusqu'à 4 joueurs sur le même réseau : courses et taxi ensemble."
		+ ("\n%d joueur(s) dans la partie." % net.joueurs.size() if net and net.en_ligne() else ""))
	_bouton(v, "Ouvrir le multijoueur", act._net_menu)
