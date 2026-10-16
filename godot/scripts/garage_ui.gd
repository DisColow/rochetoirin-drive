## Écran du garage (issue #43), ouvert depuis le menu Activités (★) quand la voiture est arrêtée : la caméra tourne
## autour de la voiture (camera_rig.vitrine), le menu est à gauche. Familles Technique / Peinture / Carrosserie ; chaque
## rubrique propose ses choix. Toucher un choix l'essaie aussitôt sur la voiture (aperçu) ; « Acheter et monter » le
## paie avec l'argent du jeu, un choix déjà acheté se monte gratuitement. En quittant, l'aperçu non acheté est retiré.
extends PanelContainer
const UI := preload("res://scripts/ui.gd")
const Garage := preload("res://scripts/garage.gd")
const Voitures := preload("res://scripts/voitures.gd")

signal ferme

var garage: Node
var tuning: Node
var cam_rig: Node
var famille := "Technique"
var _sel := {}                      # rubrique -> choix essayé (aperçu)
var _argent: Label
var _liste: VBoxContainer
var _sc: ScrollContainer
var _action: Button
var _info: Label
var _r_sel := ""                    # rubrique du dernier choix touché

func _ready() -> void:
	add_to_group("ui_zone")
	add_theme_stylebox_override("panel", UI.panel(28, 22))
	var vs := get_viewport().get_visible_rect().size
	position = Vector2(16, 16)
	custom_minimum_size = Vector2(minf(760.0, vs.x * 0.5), vs.y - 32)
	size = custom_minimum_size
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 12)
	add_child(v)
	var h := HBoxContainer.new(); v.add_child(h)
	var t := Label.new(); t.text = "Garage"; t.add_theme_font_size_override("font_size", 44)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL; h.add_child(t)
	_argent = Label.new(); _argent.add_theme_font_size_override("font_size", 38)
	_argent.add_theme_color_override("font_color", Color(0.55, 1.0, 0.45)); h.add_child(_argent)
	var onglets := HBoxContainer.new(); onglets.add_theme_constant_override("separation", 8); v.add_child(onglets)
	for f in ["Voitures", "Technique", "Peinture", "Carrosserie"]:
		var b := Button.new(); b.text = f; b.toggle_mode = true; b.button_pressed = f == famille
		b.custom_minimum_size = Vector2(0, 66); b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 28)
		b.pressed.connect(func():
			famille = f
			for o in onglets.get_children():
				o.button_pressed = o.text == f
			_remplir())
		onglets.add_child(b)
	_sc = ScrollContainer.new(); _sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_sc.get_v_scroll_bar().custom_minimum_size.x = 34
	v.add_child(_sc)
	var d := preload("res://scripts/defilement.gd").new(); d.sc = _sc; add_child(d)
	_liste = VBoxContainer.new(); _liste.add_theme_constant_override("separation", 10)
	_liste.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sc.add_child(_liste)
	_info = Label.new(); _info.add_theme_font_size_override("font_size", 24)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; v.add_child(_info)
	var bas := HBoxContainer.new(); bas.add_theme_constant_override("separation", 10); v.add_child(bas)
	_action = Button.new(); _action.custom_minimum_size = Vector2(0, 76); _action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_action.add_theme_font_size_override("font_size", 28); _action.pressed.connect(_acheter); bas.add_child(_action)
	var q := Button.new(); q.text = "Quitter"; q.custom_minimum_size = Vector2(170, 76)
	q.add_theme_font_size_override("font_size", 28); q.pressed.connect(fermer); bas.add_child(q)
	garage.change.connect(_maj)
	if cam_rig:
		cam_rig.vitrine = true
	_remplir()

func fermer() -> void:
	garage.apercu.clear()
	garage.fin_essai()                  # voiture essayée et pas achetée : on retrouve la sienne
	tuning.appliquer()
	if cam_rig:
		cam_rig.vitrine = false
		cam_rig.snap()
	ferme.emit()
	queue_free()

func _remplir() -> void:
	for c in _liste.get_children():
		c.queue_free()
	if famille == "Voitures":
		_remplir_voitures()
		return
	for r in Garage.CATALOGUE:
		var e: Array = Garage.CATALOGUE[r]
		if e[1] != famille:
			continue
		var l := Label.new(); l.text = e[0]; l.add_theme_font_size_override("font_size", 30)
		l.add_theme_color_override("font_color", Color(1.0, 0.82, 0.45))
		_liste.add_child(l)
		var g := GridContainer.new(); g.columns = 2
		g.add_theme_constant_override("h_separation", 8); g.add_theme_constant_override("v_separation", 8)
		_liste.add_child(g)
		for i in (e[2] as Array).size():
			var b := Button.new()
			b.set_meta("r", r); b.set_meta("i", i)
			b.custom_minimum_size = Vector2(0, 74); b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.add_theme_font_size_override("font_size", 23)
			b.clip_text = true
			b.pressed.connect(_essayer.bind(r, i))
			g.add_child(b)
	_maj()

## Texte et état de chaque bouton : choix monté (✓), acheté, ou son prix ; le choix essayé est enfoncé.
func _maj() -> void:
	_argent.text = Garage.euros(garage.argent)
	if famille == "Voitures":
		_maj_voitures()
		return
	for g in _liste.get_children():
		if not g is GridContainer:
			continue
		for b in g.get_children():
			var r: String = b.get_meta("r"); var i: int = b.get_meta("i")
			var nom: String = Garage.CATALOGUE[r][2][i][0]
			var etat := "✓ monté" if int(garage.monte.get(r, 0)) == i else ("acheté" if garage.a(r, i) else Garage.euros(garage.prix(r, i)))
			b.text = "%s\n%s" % [nom, etat]
			b.toggle_mode = true
			b.button_pressed = garage.choix(r) == i
	_maj_action()

func _essayer(r: String, i: int) -> void:
	_r_sel = r
	garage.apercu[r] = i
	tuning.appliquer()
	_maj()

func _maj_action() -> void:
	if not garage.a_voiture(garage.vue):
		_action.text = "Achetez d'abord cette voiture (onglet Voitures)"
		_action.disabled = true
		_info.text = "Vous essayez la %s." % Voitures.CATALOGUE[garage.vue].nom
		return
	if _r_sel == "":
		_action.text = "Touchez une pièce pour l'essayer"
		_action.disabled = true
		_info.text = "Gagnez de l'argent au taxi, aux courses et à la chasse au lieu."
		return
	var i: int = garage.choix(_r_sel)
	var nom: String = Garage.CATALOGUE[_r_sel][2][i][0]
	_info.text = "%s : %s" % [Garage.CATALOGUE[_r_sel][0], nom]
	if int(garage.monte.get(_r_sel, 0)) == i:
		_action.text = "Déjà monté"
		_action.disabled = true
	elif garage.a(_r_sel, i):
		_action.text = "Monter (déjà acheté)"
		_action.disabled = false
	elif garage.argent >= garage.prix(_r_sel, i):
		_action.text = "Acheter et monter : " + Garage.euros(garage.prix(_r_sel, i))
		_action.disabled = false
	else:
		_action.text = "Il manque " + Garage.euros(garage.prix(_r_sel, i) - garage.argent)
		_action.disabled = true

func _acheter() -> void:
	if famille == "Voitures":
		if garage.acheter_voiture(garage.vue):
			garage.conduire(garage.vue)
		_maj()
		return
	if _r_sel == "":
		return
	var i: int = garage.choix(_r_sel)
	if garage.prendre(_r_sel, i):
		garage.apercu.erase(_r_sel)
		tuning.appliquer()
		_maj()

# ---------------------------------------------------------------- voitures (#95)
## Une ligne par voiture : nom, année, puissance, vitesse, transmission ; toucher l'essaie aussitôt (elle remplace la
## voiture dans le garage) ; « Acheter » puis « Prendre le volant ».
func _remplir_voitures() -> void:
	for id in Voitures.ordre():
		if not ResourceLoader.exists(String(Voitures.CATALOGUE[id].dossier) + "/body.glb"):
			continue
		var b := Button.new()
		b.set_meta("v", id)
		b.custom_minimum_size = Vector2(0, 92); b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 24)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.toggle_mode = true
		b.pressed.connect(func():
			garage.voir(id)
			_maj())
		_liste.add_child(b)
	_maj()

func _maj_voitures() -> void:
	for b in _liste.get_children():
		if not b is Button:
			continue
		var id: String = b.get_meta("v")
		var f: Dictionary = Voitures.CATALOGUE[id]
		var etat: String = "✓ au volant" if id == garage.voiture else ("achetée" if garage.a_voiture(id) else Garage.euros(float(f.prix)))
		var tr: String = {"4x4": "4 roues motrices", "avant": "traction", "arriere": "propulsion"}[f.traction]
		b.text = "%s (%d) — %s\n%d ch · %d km/h · %s%s" % [f.nom, int(f.annee), etat, roundi(float(f.kw) * 1.36),
			int(f.vmax), tr, " · GPS" if f.gps else ""]
		b.button_pressed = id == garage.vue
	var v: Dictionary = Voitures.CATALOGUE[garage.vue]
	_info.text = String(v.texte)
	if garage.vue == garage.voiture:
		_action.text = "Vous conduisez cette voiture"
		_action.disabled = true
	elif garage.a_voiture(garage.vue):
		_action.text = "Prendre le volant"
		_action.disabled = false
	elif garage.argent >= float(v.prix):
		_action.text = "Acheter et prendre le volant : " + Garage.euros(float(v.prix))
		_action.disabled = false
	else:
		_action.text = "Il manque " + Garage.euros(float(v.prix) - garage.argent)
		_action.disabled = true
