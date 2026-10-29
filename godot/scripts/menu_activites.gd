## Menu des activités en plein écran (#119) : un onglet par activité (Carrière, Épreuves, Course libre, Taxi, Chasse
## au lieu, Garage, Multijoueur, Succès). Onglet Carrière (#120) : chapitre, jauge de réputation, missions, rival (carriere.gd). Onglet Épreuves (#112) : liste avec l'icône de la médaille gagnée, et pour l'épreuve
## touchée, la carte du tracé (carte_trace.gd), le meilleur temps, les temps des médailles, Lancer et Retour.
## Les actions appellent celles d'activities.gd (act).
extends Control

const UI := preload("res://scripts/ui.gd")
const Voitures := preload("res://scripts/voitures.gd")
const ONGLETS := ["Épreuves", "Course libre", "Métiers", "Chasse au lieu", "Garage", "Multijoueur", "Carrière", "Succès"]
const ORDRE := [6, 0, 1, 2, 3, 4, 5, 7]       # ordre d'affichage des onglets (indices de ONGLETS : la carrière en tête)

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
	_tabs.resize(ONGLETS.size())
	for i in ORDRE:
		var b := _bouton(barre, ONGLETS[i], _aller.bind(i), 0.0, 27)
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_tabs[i] = b
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
		6: _carriere()
		7: _succes()

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
	var niv: int = act.niveau_menu
	var faites := 0
	for e in tri:
		if act._medaille(int(e.id), niv) != "":
			faites += 1
	# #127 : niveau de difficulté (temps des médailles resserrés, primes multipliées)
	var hn := HBoxContainer.new()
	hn.add_theme_constant_override("separation", 8)
	l.add_child(hn)
	for k in act.NIVEAUX_EP.size():
		var bn := _bouton(hn, "%s  ×%s" % [act.NIVEAUX_EP[k][0], str(act.NIVEAUX_EP[k][2]).replace(".", ",")],
			func(): act.niveau_menu = k; _aller(0), 0.0, 24)
		bn.toggle_mode = true
		bn.button_pressed = k == niv
		bn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_texte(l, "%d / %d épreuves réussies en %s" % [faites, tri.size(), act.NIVEAUX_EP[niv][0]], 24, Color(1.0, 0.85, 0.45))
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
		var md := Medaille.new(act._medaille(id, niv), 60.0)
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
	var niv: int = act.niveau_menu
	var rec = act.main.garage.records.get(act.cle_ep(id, niv)) if act.main.garage else null
	var med: String = act._medaille(id, niv)
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
		var tc := VBoxContainer.new()
		tc.add_theme_constant_override("separation", 0)
		cell.add_child(tc)
		_texte(tc, act._fmt(act.temps_medaille(e, m, niv)), 23).autowrap_mode = TextServer.AUTOWRAP_OFF
		_texte(tc, act._euros(act.prime_medaille(e, m, niv)), 19, Color(0.6, 1.0, 0.6)).autowrap_mode = TextServer.AUTOWRAP_OFF
	_texte(v, "%.1f km · %d point(s) de passage" % [float(e.km), e.etapes.size()], 21, Color(1, 1, 1, 0.65))
	# #128 : seul contre le chrono, ou course contre 3 concurrents (vraies voitures pilotées par le jeu)
	var hm := HBoxContainer.new()
	hm.add_theme_constant_override("separation", 8)
	v.add_child(hm)
	for k in 2:
		var bm := _bouton(hm, ["Contre-la-montre", "Course contre 3 voitures"][k], func(): act.avec_concurrents = k == 1; _aller(0), 0.0, 22)
		bm.toggle_mode = true
		bm.button_pressed = act.avec_concurrents == (k == 1)
		bm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	v.add_child(hb)
	var go := _bouton(hb, "▶ Lancer (%s)" % act.NIVEAUX_EP[niv][0], func(): act._close_menu(true); act._epreuve_depart(id, niv))
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
	# v6.98 : balade (balade.gd)
	_texte(v, "Balade : la voiture roule toute seule d'un lieu à l'autre, en respectant les limitations, et la caméra "
		+ "filme comme au cinéma. Touchez l'écran pour reprendre le volant.")
	_bouton(v, "Partir en balade", act._balade_start)

func _taxi() -> void:
	var v := _colonne()
	# v7.10 : onglet « Métiers » (taxi, bus, livreur), un titre par métier
	_texte(v, "Taxi", 32, Color(1.0, 0.85, 0.4))
	_texte(v, "Prenez des clients et déposez-les à destination, guidé par le GPS. Pourboire selon la conduite, le temps "
		+ "et la conversation.")
	if act._rides > 0:
		_texte(v, "%d course(s), %s gagnés" % [act._rides, act._euros(act._total)], 26, Color(1.0, 0.9, 0.6))
	_bouton(v, "Commencer le service", act._taxi_start)
	# #148 : ligne de bus (ligne_bus.gd)
	_texte(v, "Chauffeur de bus", 32, Color(1.0, 0.85, 0.4))
	_texte(v, "Prenez le volant du bus sur une vraie ligne du réseau Ruban. Arrêtez la porte avant au niveau du "
		+ "poteau, laissez monter les voyageurs, soyez à l'heure.")
	_bouton(v, "Prendre une ligne de bus", act._bus_start)
	# #151 : livreur de repas (livreur.gd)
	_texte(v, "Livreur de repas", 32, Color(1.0, 0.85, 0.4))
	_texte(v, "Récupérez 3 commandes dans les restaurants du coin et livrez-les à l'heure, sans renverser "
		+ "le repas. Pourboire si vous êtes en avance.")
	_bouton(v, "Livrer des repas", act._livreur_start)

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

# ---------------------------------------------------------------- carrière (#120, #131)
class Jauge extends Control:
	## Jauge de réputation : barre dorée sur fond sombre, valeur (ou texte donné) au milieu.
	var valeur := 0.0
	var txt := ""
	func _init(v: float, t := "") -> void:
		valeur = v
		txt = t if t != "" else "Réputation %d / 100" % int(v)
		custom_minimum_size = Vector2(420, 46)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0, 0, 0, 0.55))
		var f := clampf(valeur / 100.0, 0.0, 1.0)
		draw_rect(Rect2(Vector2(3, 3), Vector2((size.x - 6) * f, size.y - 6)), Color(1.0, 0.72, 0.2).lerp(Color(0.35, 0.9, 0.4), f))
		draw_rect(r, Color(1, 1, 1, 0.6), false, 2.0)
		var fnt := get_theme_default_font()
		var w := fnt.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
		draw_string_outline(fnt, Vector2((size.x - w) / 2, size.y / 2 + 9), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, 6, Color.BLACK)
		draw_string(fnt, Vector2((size.x - w) / 2, size.y / 2 + 9), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.WHITE)

var chap_vu := -1                    # chapitre affiché dans l'onglet Carrière (-1 : le chapitre en cours)

func _carriere() -> void:
	var ca = act.main.get("carriere")
	if ca == null:
		return
	if chap_vu < 0 or not ca.ouvert(chap_vu):
		chap_vu = ca.courant()
	var k: int = chap_vu
	var ch: Dictionary = ca.CHAPITRES[k]
	var championnat: bool = String(ch.missions[0].genre) == "manche"
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_corps.add_child(sc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	# chapitres : finis (✔), ouvert, fermés tant que le précédent n'est pas à 100
	var hc := HBoxContainer.new()
	hc.add_theme_constant_override("separation", 8)
	v.add_child(hc)
	for j in ca.CHAPITRES.size():
		var t := "%s%d. %s" % ["✔ " if ca.fini(j) else "", j + 1, ca.CHAPITRES[j].titre]
		var b := _bouton(hc, t, func(): chap_vu = j; _aller(6), 0.0, 24)
		b.toggle_mode = true
		b.set_pressed_no_signal(j == k)
		b.disabled = not ca.ouvert(j)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if not ca.ouvert(j):
			b.tooltip_text = "Termine le chapitre %d pour l'ouvrir" % j
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 24)
	v.add_child(h)
	var ti := _texte(h, "Chapitre %d : %s" % [k + 1, ch.titre], 34, Color(1.0, 0.85, 0.45))
	ti.autowrap_mode = TextServer.AUTOWRAP_OFF
	ti.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if championnat:
		var mc := int(ca.champ.manche)
		var etat := "Champion !" if ca.fini(k) else ("Championnat perdu" if mc >= 5 else "Manche %d / 5" % (mc + 1))
		h.add_child(Jauge.new(100.0 if ca.fini(k) else mc * 20.0, etat))
	else:
		h.add_child(Jauge.new(float(ca.reps[k])))
	_texte(v, "%s  (%s)" % [ch.intro, ch.lieux], 22, Color(1, 1, 1, 0.7))
	for m in ch.missions:
		var faite: bool = ca.faites.has(m.id)
		var pc := PanelContainer.new()
		pc.add_theme_stylebox_override("panel", UI.panel(18, 10))
		v.add_child(pc)
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 16)
		pc.add_child(r)
		var ic := _texte(r, "✔" if faite else "○", 44, Color(0.4, 0.95, 0.45) if faite else Color(1, 1, 1, 0.5))
		ic.autowrap_mode = TextServer.AUTOWRAP_OFF
		ic.custom_minimum_size = Vector2(52, 0)
		var t := VBoxContainer.new()
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.add_theme_constant_override("separation", 2)
		r.add_child(t)
		_texte(t, str(m.titre), 28)
		_texte(t, str(m.texte), 20, Color(1, 1, 1, 0.75))
		var id := String(m.id)
		var gain := ""
		if String(m.genre) == "manche":
			var n := int(m.n)
			if n <= ca.champ.resultats.size():
				var o: Array = ca.champ.resultats[n - 1]
				gain = "Arrivé %s" % act._rang(o.find("joueur") + 1)
			else:
				gain = "Points : 10 / 6 / 4 / 3"
		else:
			gain = "+%d réputation" % int(m.rep) + (" · %d €" % int(m.prime) if float(m.prime) > 0.0 else "")
			if String(m.genre) == "duel":
				var bi: Array = ca.duel_bilan(String(m.rival))
				gain += " · duels : %d gagné(s), %d perdu(s)" % [int(bi[0]), int(bi[1])]
			if faite:
				gain = "Réussie"
		_texte(t, gain, 20, Color(1.0, 0.9, 0.6))
		var bv := VBoxContainer.new()
		bv.add_theme_constant_override("separation", 8)
		r.add_child(bv)
		var jouable := true
		if String(m.genre) == "manche" and not ca.carriere_finie():
			jouable = int(m.n) == int(ca.champ.manche) + 1 or (int(ca.champ.manche) >= 5 and int(m.n) == 1)
		if jouable:
			_bouton(bv, "Itinéraire" if not faite else "Rejouer", func(): ca.lancer(id, false), 230.0, 24)
			_bouton(bv, "Y aller", func(): ca.lancer(id, true), 230.0, 24)
	if not championnat and not ca.fini(k) and ch.missions.all(func(m): return ca.faites.has(m.id)):
		_texte(v, "Toutes les missions sont réussies ! Il manque %d point(s) : gagne-les avec des médailles d'épreuves ou des clients de taxi contents." % int(ceil(100.0 - float(ca.reps[k]))),
			24, Color(1.0, 0.85, 0.45))
	for rid in ch.rivaux:
		var rv: Dictionary = ca.RIVAUX[rid]
		var riv := _texte(v, "Rival : %s, au volant de sa %s : « %s »." % [rv.nom, Voitures.CATALOGUE[rv.voiture].nom, rv.titre], 22, Color(1.0, 0.6, 0.5))
		riv.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if championnat:
		var cl: Array = ca.classement()
		var tab := PanelContainer.new()
		tab.add_theme_stylebox_override("panel", UI.panel(18, 10))
		v.add_child(tab)
		var tv := VBoxContainer.new()
		tab.add_child(tv)
		_texte(tv, "Classement du championnat (après %d manche(s))" % int(ca.champ.manche), 26, Color(1.0, 0.85, 0.45))
		for j in cl.size():
			_texte(tv, "%s   %s   %d pts" % [act._rang(j + 1), ca.nom_court(cl[j][0]), int(cl[j][1])], 24,
				Color(0.5, 1.0, 0.6) if cl[j][0] == "joueur" else Color(1, 1, 1, 0.85))
		if int(ca.champ.manche) > 0 and not ca.carriere_finie():
			_bouton(v, "Recommencer le championnat", func(): ca.recommencer_championnat(); _aller(6), 0.0, 24)
	if ca.fini(k):
		var cad := String(ch.cadeau)
		var nom: String = Voitures.CATALOGUE[cad].nom if cad != "" else ""
		var fin := "Carrière terminée : champion du Nord-Isère !" if ca.carriere_finie() and k == ca.CHAPITRES.size() - 1 \
			else "Chapitre %d terminé !" % (k + 1)
		_texte(v, fin + ("  Cadeau : %s." % nom if nom != "" else ""), 26, Color(0.5, 1.0, 0.6))

# ---------------------------------------------------------------- succès (#133)
## Nombre lisible : entier avec espaces des milliers, sinon une décimale (0,4 km).
static func _nombre(x: float) -> String:
	if absf(x - roundf(x)) > 0.05 and x < 100.0:
		return ("%.1f" % x).replace(".", ",")
	var t := str(int(roundf(x)))
	var o := ""
	while t.length() > 3:
		o = " " + t.right(3) + o
		t = t.left(t.length() - 3)
	return t + o

func _succes() -> void:
	var su = act.main.get("succes")
	if su == null:
		return
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 20)
	_corps.add_child(h)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.size_flags_stretch_ratio = 1.6
	h.add_child(sc)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	sc.add_child(v)
	var n := 0
	for s in su.SUCCES:
		if su.obtenu(String(s.id)):
			n += 1
	# v7.11 : défi du jour
	var dj: Dictionary = su.defi()
	var pd := PanelContainer.new()
	pd.add_theme_stylebox_override("panel", UI.panel(14, 8))
	v.add_child(pd)
	var vd := VBoxContainer.new()
	pd.add_child(vd)
	_texte(vd, "Défi du jour : %s" % str(dj.texte), 28, Color(0.55, 0.85, 1.0))
	if su.defi_fait and su.defi_jour == su.jour():
		_texte(vd, "Réussi ! +%d € · nouveau défi demain" % int(dj.prime), 22, Color(0.5, 1.0, 0.6))
	else:
		var pr: float = su.defi_progres()
		_texte(vd, "%s sur %s · prime %d €" % [_nombre(pr), _nombre(float(dj.but)), int(dj.prime)], 22, Color(1, 1, 1, 0.75))
	_texte(v, "%d succès sur %d" % [n, su.SUCCES.size()], 30, Color(1.0, 0.85, 0.45))
	for s in su.SUCCES:
		var ok: bool = su.obtenu(String(s.id))
		var pc := PanelContainer.new()
		pc.add_theme_stylebox_override("panel", UI.panel(14, 8))
		v.add_child(pc)
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 14)
		pc.add_child(r)
		var ic := _texte(r, "★" if ok else "☆", 40, Color(1.0, 0.8, 0.2) if ok else Color(1, 1, 1, 0.35))
		ic.autowrap_mode = TextServer.AUTOWRAP_OFF
		ic.custom_minimum_size = Vector2(48, 0)
		var t := VBoxContainer.new()
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.add_theme_constant_override("separation", 2)
		r.add_child(t)
		_texte(t, str(s.titre), 26, Color(1, 1, 1) if ok else Color(1, 1, 1, 0.8))
		_texte(t, str(s.texte), 20, Color(1, 1, 1, 0.6))
		if ok:
			_texte(t, "Obtenu le %s  ·  +%d €" % [str(su.obtenus[s.id]), int(s.prime)], 20, Color(0.5, 1.0, 0.6))
		else:
			var b: float = su.but(s)
			var val: float = minf(su.valeur(String(s.stat)), b)
			var j := Jauge.new(100.0 * val / b, "%s / %s" % [_nombre(val), _nombre(b)])
			j.custom_minimum_size = Vector2(380, 34)
			t.add_child(j)
			_texte(t, "Prime : %d €" % int(s.prime), 18, Color(1.0, 0.9, 0.6))
	var pc2 := PanelContainer.new()
	pc2.add_theme_stylebox_override("panel", UI.panel(18, 12))
	pc2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc2.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(pc2)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 6)
	pc2.add_child(sv)
	_texte(sv, "Statistiques", 30, Color(1.0, 0.85, 0.45))
	for st in su.STATS:
		var row := HBoxContainer.new()
		sv.add_child(row)
		var a := _texte(row, str(st[1]), 22, Color(1, 1, 1, 0.75))
		a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var b := _texte(row, su.texte_stat(String(st[0]), String(st[2])), 22)
		b.autowrap_mode = TextServer.AUTOWRAP_OFF
