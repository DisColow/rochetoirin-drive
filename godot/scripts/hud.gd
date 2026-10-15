## Interface (disposition de la première version) : mini-GPS en haut à droite avec le panneau de vitesse (limitation
## et compteur) dessous, nom de la rue dans une pastille en haut au centre (commune et coordonnées en petit),
## boutons carte / caméra / remise sur la route en haut à gauche ; commandes tactiles multipoint (◀ ▶ à gauche, frein
## et accélérateur à droite). La manette et le clavier passent par les mêmes actions.
extends CanvasLayer
const PerfMon := preload("res://scripts/perf_monitor.gd")

const UI := preload("res://scripts/ui.gd")

var car: VehicleBody3D
var speed: Label
var buttons := []
var map: Control
var road: Label
var where: Label
var names = preload("res://scripts/road_name.gd").new()
var _name_t := 0.0
signal teleport(pos: Vector3, heading: float)

var gps: Control
var pill: Control
var speed_panel: Control
var _road_text := ""
var _where_text := ""
var _limit := 0

func _ready() -> void:
	gps = preload("res://scripts/gps.gd").new()
	gps.car = car
	gps.open_map.connect(_open_map)
	add_child(gps)
	pill = Control.new()
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.draw.connect(_draw_pill)
	add_child(pill)
	speed_panel = Control.new()
	speed_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	speed_panel.draw.connect(_draw_speed)
	add_child(speed_panel)
	argent_panel = Control.new()                       # argent du garage, toujours visible (#59)
	argent_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	argent_panel.draw.connect(_draw_argent)
	add_child(argent_panel)
	get_viewport().size_changed.connect(_layout)
	_add_button("gauche", "◀", 0)
	_add_button("droite", "▶", 1)
	_add_button("freiner", "FREIN", 2)
	_add_button("accelerer", "GAZ", 3)
	_add_button("camera", "CAM", 4)
	_add_button("replacer", "↺", 5)
	# plus de bouton « carte » (#58) : toucher la mini-carte l'ouvre (touche M au clavier)
	_add_button("reglages", "⚙", 6)
	_add_button("activites", "★", 7)
	_add_button("radio", "♪", 8)
	_faire_pli()
	_freins_tactiles()
	map = preload("res://scripts/map.gd").new()
	map.car = car
	map.visible = false
	map.teleport.connect(func(p, h): teleport.emit(p, h))
	map.closed.connect(func(): _show_drive(true))
	add_child(map)
	_layout()

var settings: Control

## Guide des touches (#63) : commande, clavier, manette (boutons à la Xbox ; A = croix, B = rond… sur PlayStation).
const GUIDE := [
	["Commande", "Clavier", "Manette"],
	["Accélérer", "↑", "Gâchette droite"],
	["Freiner, marche arrière", "↓", "Gâchette gauche"],
	["Tourner", "← →", "Stick gauche"],
	["Frein à main", "Espace", "A"],
	["Frein de parking", "P", "Croix ↓"],
	["Caméra", "C", "Clic du stick droit"],
	["Descendre / monter (à l'arrêt)", "E", "Y"],
	["Remettre sur la route", "R", "X"],
	["Carte", "M", "Select / View"],
	["Activités et garage", "T", "RB"],
	["Radio", "N", "LB"],
	["Réglages", "Échap", "Start / Menu"],
	["Menus : choisir", "↑ ↓ ← →, 1 à 9", "Croix directionnelle"],
	["Menus : valider", "Entrée", "A"],
	["Menus : fermer", "Échap", "B"],
]

## Rangée de boutons du haut repliable (#52) : bouton ‹ / › à gauche ; repliée, il ne reste que lui.
var replie := false
var _pli: Button
var _conduite := true
var _en_activite := false
func _faire_pli() -> void:
	_pli = Button.new()
	_pli.add_to_group("ui_zone")
	_pli.custom_minimum_size = Vector2(64, 92)
	_pli.add_theme_font_size_override("font_size", 40)
	_pli.focus_mode = Control.FOCUS_NONE
	_pli.pressed.connect(func(): replier(not replie))
	add_child(_pli)
	replier(false)

func replier(oui: bool) -> void:
	replie = oui
	_pli.text = "›" if oui else "‹"
	for i in range(4, buttons.size()):
		buttons[i].visible = _conduite and not oui

const CREDITS := """Enseigne de la boulangerie : polices Kaushan Script et Caveat (Pablo Impallari, SIL Open Font License).
Voix du taxi : synthèse vocale de l'appareil ; à défaut, synthèse Piper (rhasspy) ; voix « Siwis » (Université d'Édimbourg, CC BY 4.0) et « Gilles » (CC0), effet talkie-walkie ffmpeg.
Voiture : « Ford Ranger Raptor 2019 » par David_Holiday (Sketchfab, licence CC BY 4.0), repeint en noir.
Lampadaires : « Street Lantern » par Samuel Francis Johnson (Oneironauticus) (Sketchfab, licence CC BY 4.0).
Aéronefs (Sketchfab, licence CC BY 4.0) : « Free Cessna 172 Replica » par quadzii, « Low Poly Airliner » par maurogsw, « Low Poly Helicopter » par antonmoek, « UNDERPOLY: Free Sailplane Glider » par underpolyproject.
Animations des clients : « Universal Animation Library » 1 et 2 de Quaternius (CC0).
Clients du taxi : MakeHuman (MPFB 2 et « makehuman system assets », communauté MakeHuman, licence CC0) ; son de téléportation : Joseph SARDIN - BigSoundBank.com (CC0).
Rochetoirin Info (radio) : « Flash info » de 20 Minutes et journal de RTL (podcasts publics, écoutés en direct, non enregistrés dans le jeu), titres de franceinfo et du Dauphiné Libéré (flux RSS).
Pièces du garage (Sketchfab, licence CC BY 4.0) : « Universal Spoiler 1 » et « 2 » par the_86_guy, « Ultimate Car Spoiler Pack » par DevPoly3D, « Universal Custom Car Spoiler » par JollyFox, « Car agressive Wing modification » par knitro_vedant, « Dual Exhaust Tip » par wojteX, « Exhaust Tips » par wiktors360, « Basic Low-Poly Exhaust Tip » 1 et 2 par NANOxDucko, « BBS RS16 Tuner Car Wheel », « Mugen M7 Tuner Car Wheel » et « Tuner Car Wheel » par TinoD2, « Volkswagen Rim » par PolyTigr, « Concept car Rim » par LagzDesign.
Soucoupe du gardien : « UFO » par sebslom (sketchfab.com/3d-models), licence CC BY 4.0.
Pluie et orage : Sound Effect by Premankur Adhikary from Pixabay.
Sons (moteur, roulement, ambiances, oiseaux, animaux, cloches, essuie-glaces, soucoupe…) : enregistrements de Joseph SARDIN - BigSoundBank.com (licence CC0) ; chocs : « Impact Sounds » de Kenney (CC0) et effets sonores de Mixkit.co (licence Mixkit, gratuite).
Arbres : modèles Sketchfab (licences CC BY / CC0, auteurs listés dans le dépôt).
Cultures (Sketchfab) : « Maize Corn Plant » par gilles.schaeck, « Wheat — FREE » par Yaroslav Karas, « Realistic Wheat » par Graphetta, « Sunflower » par zvanstone (licences CC BY 4.0), « Rapeseed, Brassica napus » par ffish.asia / floraZia (CC0).
Animaux (Sketchfab, licence CC BY 4.0) : « Cow » par JosueBoisvert, « Sheep » par kenchoo, « Horse Rigged (Game Ready) » par abhayexe.
Voitures garées (Sketchfab, licence CC BY 4.0) : « Generic 80s european car » par henryviii, « Low Poly Small car » et « Low-Poly Sedan car » par scailman, « Blue Sedan | Stylized Low Poly » par R3indeer.
Clients du taxi : « Low Poly Characters (PACK) » par micaelsampaio (Sketchfab, licence CC BY 4.0).
Musiques de la radio : Kevin MacLeod (incompetech.com), licence Creative Commons Attribution 4.0 — voir assets/radio/radio.json pour les titres.
Polices de l'interface : « Pixelify Sans » (Stefie Justprince) et « DSEG » (Keshikan), licence SIL Open Font License 1.1.
Textures : Poly Haven et ambientCG (CC0).
Données : © les contributeurs d'OpenStreetMap (ODbL) ; IGN (BD TOPO, RGE ALTI, LiDAR HD, BD ORTHO, Licence Ouverte Etalab).
Modèles des commerces, équipements, haies, maisons, clôtures et sprite de la voiture : faits avec Blender pour le jeu ; boutons de la planche de bord dessinés pixel par pixel pour le jeu."""

## Message bref au centre de l'écran (péage…), qui s'efface tout seul.
var _toast: PanelContainer
var _toast_t := 0.0
func toast(text: String, secs := 3.5) -> void:
	if _toast == null:
		_toast = PanelContainer.new()
		_toast.add_theme_stylebox_override("panel", UI.panel(40, 18))
		_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var l := Label.new(); l.add_theme_font_size_override("font_size", 34)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_toast.add_child(l)
		add_child(_toast)
	(_toast.get_child(0) as Label).text = text
	_toast.reset_size()
	var vs := get_viewport().get_visible_rect().size
	_toast.position = Vector2((vs.x - _toast.get_combined_minimum_size().x) / 2, maxf(vs.y * 0.3, 230.0))
	_toast.modulate.a = 1.0
	_toast.visible = true
	_toast_t = secs

## Réglages : densité de la végétation (mémorisée dans user://reglages.cfg).
func _open_settings() -> void:
	if settings and is_instance_valid(settings):
		return
	var veg = get_parent().vegetation
	_show_drive(false)
	settings = PanelContainer.new()
	# bande du haut réservée à la croix de fermeture (#69) : elle ne cache rien du contenu, qui défile dessous
	var sbs := UI.panel(44, 26)
	sbs.content_margin_top = 92
	settings.add_theme_stylebox_override("panel", sbs)
	_croix = Button.new()
	_croix.text = "✕"
	_croix.custom_minimum_size = Vector2(72, 72)
	_croix.add_theme_font_size_override("font_size", 38)
	_croix.focus_mode = Control.FOCUS_NONE
	_croix.pressed.connect(_fermer_reglages)
	# contenu défilant (glisser au doigt, molette) : le menu tient sur les petits écrans
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.get_v_scroll_bar().custom_minimum_size.x = 34          # barre facile à attraper au doigt (issue #38)
	settings.add_child(sc)
	var dfl := preload("res://scripts/defilement.gd").new()   # défilement au doigt depuis un bouton (issue #38)
	dfl.sc = sc
	settings.add_child(dfl)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 12)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	var t := Label.new(); t.text = "Réglages"; t.add_theme_font_size_override("font_size", 44); v.add_child(t)
	var l := Label.new(); l.text = "Performances"; l.add_theme_font_size_override("font_size", 30); v.add_child(l)
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 12); v.add_child(h)
	var main_n = get_parent()
	var boutons := []
	var maj := func():
		for j in boutons.size():
			boutons[j].button_pressed = (j == 4 and main_n.perf_auto) or (j < 4 and not main_n.perf_auto and j == veg.level)
	for i in 5:
		var b := Button.new()
		b.text = ["Économie", "Équilibré", "Élevée", "Maximale", "Auto"][i]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(170, 70)
		b.add_theme_font_size_override("font_size", 28)
		b.pressed.connect(func():
			main_n.perf_auto = i == 4
			if i < 4:
				appliquer_niveau(i)
			var cfg := ConfigFile.new(); cfg.load("user://reglages.cfg")
			cfg.set_value("affichage", "perf_auto", main_n.perf_auto); cfg.save("user://reglages.cfg")
			maj.call())
		h.add_child(b)
		boutons.append(b)
	maj.call()
	# heure de la journée (lumière, ciel, phares et fenêtres éclairées le soir)
	var lt := Label.new(); lt.text = "Heure de la journée"; lt.add_theme_font_size_override("font_size", 30); v.add_child(lt)
	var ht := HBoxContainer.new(); ht.add_theme_constant_override("separation", 16); v.add_child(ht)
	var main_node = get_parent()
	for i in main_node.TIMES.size():
		var b := Button.new()
		b.text = main_node.TIMES[i]
		b.toggle_mode = true
		b.button_pressed = i == main_node.time_of_day
		b.custom_minimum_size = Vector2(220, 70)
		b.add_theme_font_size_override("font_size", 30)
		b.pressed.connect(func():
			main_node.set_time(i)
			var cfg := ConfigFile.new(); cfg.load("user://reglages.cfg")
			cfg.set_value("affichage", "heure", i); cfg.save("user://reglages.cfg")
			for c in ht.get_children():
				c.button_pressed = c == b)
		ht.add_child(b)
	# météo (ciel, lumière, brume, pluie et route mouillée)
	var lw := Label.new(); lw.text = "Météo"; lw.add_theme_font_size_override("font_size", 30); v.add_child(lw)
	var hw := HBoxContainer.new(); hw.add_theme_constant_override("separation", 16); v.add_child(hw)
	for i in main_node.WEATHERS.size():
		var b := Button.new()
		b.text = main_node.WEATHERS[i]
		b.toggle_mode = true
		b.button_pressed = i == main_node.weather
		b.custom_minimum_size = Vector2(220, 70)
		b.add_theme_font_size_override("font_size", 30)
		b.pressed.connect(func():
			main_node.set_weather(i)
			var cfg := ConfigFile.new(); cfg.load("user://reglages.cfg")
			cfg.set_value("affichage", "meteo", i); cfg.save("user://reglages.cfg")
			for c in hw.get_children():
				c.button_pressed = c == b)
		hw.add_child(b)
	# conduite (v6.25) : aide au maintien dans la voie
	var lc := Label.new(); lc.text = "Conduite"; lc.add_theme_font_size_override("font_size", 30); v.add_child(lc)
	# interrupteur lisible (issue #37) : pastille verte / grise à gauche et état écrit en toutes lettres
	var b_voie := Button.new()
	b_voie.toggle_mode = true
	b_voie.button_pressed = car != null and car.aide_voie
	b_voie.custom_minimum_size = Vector2(560, 70)
	b_voie.add_theme_font_size_override("font_size", 28)
	b_voie.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var etat_voie := func(on: bool):
		b_voie.icon = _pastille(Color(0.25, 0.9, 0.35) if on else Color(0.45, 0.45, 0.48))
		b_voie.text = "  Aide au maintien dans la voie : " + ("ACTIVÉE" if on else "désactivée")
	etat_voie.call(b_voie.button_pressed)
	b_voie.toggled.connect(func(on: bool):
		etat_voie.call(on)
		if car:
			car.aide_voie = on
		var cfg := ConfigFile.new(); cfg.load("user://reglages.cfg")
		cfg.set_value("conduite", "aide_voie", on); cfg.save("user://reglages.cfg"))
	v.add_child(b_voie)
	# son : volumes de l'ambiance, des effets (voiture, voix) et de la musique (radio), de 0 à 150 %
	var ls := Label.new(); ls.text = "Son"; ls.add_theme_font_size_override("font_size", 30); v.add_child(ls)
	var hs := HBoxContainer.new(); hs.add_theme_constant_override("separation", 24); v.add_child(hs)
	var AU := preload("res://scripts/audio.gd")
	AU.volume_db("ambiance")
	for cat in [["ambiance", "Ambiance"], ["effets", "Effets"], ["musique", "Musique"], ["voix", "Voix"]]:
		var col := VBoxContainer.new(); col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cl := Label.new(); cl.add_theme_font_size_override("font_size", 24)
		col.add_child(cl)
		var sl := HSlider.new()
		sl.min_value = 0.0; sl.max_value = 1.5; sl.step = 0.05
		sl.value = float(AU.volumes[cat[0]])
		sl.custom_minimum_size = Vector2(220, 48)
		var upd := func(x: float):
			cl.text = "%s  %d %%" % [cat[1], int(round(x * 100.0))]
		upd.call(sl.value)
		sl.value_changed.connect(func(x: float):
			upd.call(x)
			AU.set_volume(cat[0], x))
		col.add_child(sl)
		hs.add_child(col)
	# voix du taxi (v6.8) : synthèse vocale du téléphone ; voix choisie pour les femmes et pour les hommes
	var VT := preload("res://scripts/voix_tel.gd")
	var hv := HBoxContainer.new(); hv.add_theme_constant_override("separation", 16); v.add_child(hv)
	if not VT.dispo():
		var nv := Label.new(); nv.add_theme_font_size_override("font_size", 22); nv.modulate = Color(1, 1, 1, 0.7)
		nv.text = "Voix du taxi : aucune voix française sur cet appareil (voix enregistrées utilisées).\nPour l'ajouter : Paramètres Android > Synthèse vocale > voix française."
		hv.add_child(nv)
	else:
		for sx in [["f", "Voix des femmes"], ["m", "Voix des hommes"]]:
			var bv := Button.new(); bv.custom_minimum_size = Vector2(0, 64); bv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			bv.add_theme_font_size_override("font_size", 22); bv.clip_text = true
			var nom_v := func() -> String:
				var cur := VT.reglage(sx[0])
				for x in VT.voix():
					if x.id == cur:
						return "%s : %s" % [sx[1], x.nom]
				return "%s : auto" % sx[1]
			bv.text = nom_v.call()
			bv.pressed.connect(func():
				# voix suivante de la liste (auto, puis chaque voix française), et on l'écoute aussitôt
				var ids: Array = [""] + VT.voix().map(func(x): return x.id)
				var i := ids.find(VT.reglage(sx[0]))
				VT.regler(sx[0], ids[(i + 1) % ids.size()])
				bv.text = nom_v.call()
				var AU2 := preload("res://scripts/audio.gd")
				VT.dire("Bonjour ! Vous m'emmenez à Rochetoirin ?", VT.choisir(sx[0], 1), float(AU2.volumes["voix"]), true))
			hv.add_child(bv)
	var note := Label.new()
	note.text = "Auto : le jeu choisit le niveau selon sa fluidité. Économie = le plus fluide.\nVersion %s (mises à jour automatiques au lancement)" % str(Engine.get_meta("version_jeu", ProjectSettings.get_setting("application/config/version", "")))
	note.add_theme_font_size_override("font_size", 22); note.modulate = Color(1, 1, 1, 0.7); v.add_child(note)
	# éditeur de monde : champ de la formule magique (dictée au micro du clavier, ou saisie)
	var fm := Button.new(); fm.text = "Formule magique…"; fm.custom_minimum_size = Vector2(0, 64)
	fm.add_theme_font_size_override("font_size", 28)
	fm.pressed.connect(func():
		_fermer_reglages()
		if main_node.get("editeur"):
			main_node.editeur.open_formula())
	v.add_child(fm)
	# crédits (licences des modèles, sons et données)
	var cb := Button.new(); cb.text = "Crédits"; cb.custom_minimum_size = Vector2(0, 64)
	cb.add_theme_font_size_override("font_size", 28)
	var cr := Label.new()
	cr.text = CREDITS
	cr.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cr.custom_minimum_size = Vector2(900, 0)
	cr.add_theme_font_size_override("font_size", 20)
	cr.visible = false
	cb.pressed.connect(func():
		cr.visible = not cr.visible
		_fit_settings.call_deferred())
	v.add_child(cb)
	v.add_child(cr)
	# mesure des performances : relevé de 3 minutes en conduisant, puis envoi en un toucher
	var mp := Button.new(); mp.custom_minimum_size = Vector2(0, 64)
	mp.add_theme_font_size_override("font_size", 28)
	var pm = main_node.get("perf")
	mp.text = ("Mesure en cours… (encore %d s)" % int(pm.reste())) if pm and pm.en_releve() else "Mesurer les performances (3 min de conduite)"
	mp.pressed.connect(func():
		if pm and not pm.en_releve():
			pm.demarrer_releve()
			_fermer_reglages()
			toast("Mesure lancée : roule normalement pendant 3 minutes.", 4.0))
	v.add_child(mp)
	# signaler un bug : ticket GitHub pré-rempli (version, appareil, position, journal) ouvert dans le navigateur
	var bb := Button.new(); bb.text = "Signaler un bug…"; bb.custom_minimum_size = Vector2(0, 64)
	bb.add_theme_font_size_override("font_size", 28)
	var bug_box := VBoxContainer.new(); bug_box.visible = false
	bug_box.add_theme_constant_override("separation", 8)
	var bug_txt := TextEdit.new()
	bug_txt.placeholder_text = "Que s'est-il passé ? (ce que vous faisiez, ce que vous avez vu)"
	bug_txt.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	bug_txt.custom_minimum_size = Vector2(900, 180)
	bug_txt.add_theme_font_size_override("font_size", 26)
	bug_box.add_child(bug_txt)
	UI.saisie_tactile(bug_txt, "Signaler un bug")
	var bug_send := Button.new(); bug_send.text = "Envoyer le signalement"; bug_send.custom_minimum_size = Vector2(0, 64)
	bug_send.add_theme_font_size_override("font_size", 28)
	bug_send.pressed.connect(func():
		send_bug_report(bug_txt.text)
		bug_txt.text = ""
		bug_box.visible = false
		_fit_settings.call_deferred())
	bug_box.add_child(bug_send)
	bb.pressed.connect(func():
		bug_box.visible = not bug_box.visible
		if bug_box.visible:
			UI.focus_saisie(bug_txt, "Signaler un bug")
		_fit_settings.call_deferred())
	v.add_child(bb)
	v.add_child(bug_box)
	# guide des touches (#63) : clavier et manette, déplié à la demande
	var gk := Button.new(); gk.text = "Guide des touches (clavier et manette)"
	gk.custom_minimum_size = Vector2(0, 70); gk.add_theme_font_size_override("font_size", 28)
	var guide := GridContainer.new(); guide.columns = 3; guide.visible = false
	guide.add_theme_constant_override("h_separation", 28); guide.add_theme_constant_override("v_separation", 6)
	for ligne in GUIDE:
		for j in 3:
			var c := Label.new(); c.text = ligne[j]
			c.add_theme_font_size_override("font_size", 24 if ligne[0] != "Commande" else 26)
			if ligne[0] == "Commande":
				c.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
			guide.add_child(c)
	gk.pressed.connect(func():
		guide.visible = not guide.visible
		_fit_settings.call_deferred())
	v.add_child(gk)
	v.add_child(guide)
	var close := Button.new(); close.text = "Fermer"; close.custom_minimum_size = Vector2(0, 76)
	close.add_theme_font_size_override("font_size", 32)
	close.pressed.connect(_fermer_reglages)
	v.add_child(close)
	add_child(settings)
	_fit_settings()

## Taille du menu des réglages : tout le contenu s'il tient, sinon 90 % de la hauteur de l'écran (le reste défile).
var _croix: Button
func _fermer_reglages() -> void:
	if settings and is_instance_valid(settings):
		settings.queue_free()
	settings = null
	if _croix and is_instance_valid(_croix):
		_croix.queue_free()
	_croix = null
	_show_drive(true)

func _fit_settings() -> void:
	if not (settings and is_instance_valid(settings)):
		return
	var sc: ScrollContainer = settings.get_child(0)
	var v: Control = sc.get_child(0)
	var vs := get_viewport().get_visible_rect().size
	var need := v.get_combined_minimum_size()
	var pad := settings.get_combined_minimum_size() - sc.get_combined_minimum_size()
	sc.custom_minimum_size = Vector2(need.x + 24.0, minf(need.y, vs.y * 0.9 - pad.y))
	settings.reset_size()
	settings.position = (vs - settings.size) / 2
	if _croix and is_instance_valid(_croix):
		if _croix.get_parent() == null:
			add_child(_croix)
		_croix.position = settings.position + Vector2(settings.size.x - 72 - 14, 12)

## Signalement de bug : ouvre un ticket GitHub pré-rempli dans le navigateur (il n'y a plus qu'à appuyer sur
## « Create »). Pas de jeton dans le jeu : un jeton d'écriture embarqué dans l'APK serait public.
func send_bug_report(text: String) -> void:
	var main_node = get_parent()
	var p: Vector3 = main_node.car.global_position
	var ver := str(Engine.get_meta("version_jeu", ProjectSettings.get_setting("application/config/version", "?")))
	var first := text.strip_edges().split("\n")[0]
	var title := "Bug : %s" % (first.left(70) if first != "" else "(sans description)")
	var body := "**Description** :\n%s\n\n| | |\n|---|---|\n" % (text.strip_edges() if text.strip_edges() != "" else "_(vide)_")
	body += "| Version | %s |\n" % ver
	body += "| Appareil | %s (%s %s) |\n" % [OS.get_model_name(), OS.get_name(), OS.get_version()]
	body += "| Rendu | %s, %s |\n" % [RenderingServer.get_video_adapter_name(), str(get_viewport().get_visible_rect().size)]
	body += "| Voiture | x %.1f, y %.1f, z %.1f |\n" % [p.x, p.y, p.z]
	body += "| Images/s | %d |\n" % Engine.get_frames_per_second()
	var st := "user://etat.txt"
	if FileAccess.file_exists(st):
		body += "\nÉtat :\n```\n%s\n```\n" % FileAccess.get_file_as_string(st).strip_edges().right(800)
	var lg := "user://logs/godot.log"
	if FileAccess.file_exists(lg):
		var lines := FileAccess.get_file_as_string(lg).split("\n")
		var tail := "\n".join(lines.slice(maxi(0, lines.size() - 40)))
		body += "\nJournal (fin) :\n```\n%s\n```\n" % tail.right(2500)
	body += "\n_Signalement envoyé depuis le jeu (⚙ > Signaler un bug)._"
	var url := "https://github.com/DisColow/rochetoirin-drive/issues/new?title=%s&labels=bug&body=%s" % [title.uri_encode(), body.uri_encode()]
	OS.shell_open(url)
	toast("Signalement prêt dans le navigateur :\nappuyez sur « Create » pour l'envoyer.", 4.0)

## Point de l'écran occupé par l'interface (boutons, GPS, compteur, carte, réglages) : pas de rotation de caméra.
func is_ui_point(p: Vector2) -> bool:
	if map.visible or (settings and is_instance_valid(settings)) or get_tree().paused:
		return true
	for b in buttons:
		if not b.visible:
			continue
		if b.shape is CircleShape2D:
			var r: float = b.shape.radius
			if p.distance_to(b.position + Vector2(r, r)) < r + 28.0:
				return true
		elif Rect2(b.position, b.shape.size).grow(20.0).has_point(p):
			return true
	# autres zones d'interface (bulle de conversation du taxi…)
	for n in get_tree().get_nodes_in_group("ui_zone"):
		if n is Control and n.is_visible_in_tree() and n.get_global_rect().grow(16.0).has_point(p):
			return true
		if n is TouchScreenButton and n.visible and Rect2(n.position, n.shape.size).grow(20.0).has_point(p):
			return true
	return Rect2(gps.position, gps.size).has_point(p) or Rect2(speed_panel.position, speed_panel.size).has_point(p)

func _open_map() -> void:
	if not map.visible:
		_show_drive(false)
		map.open()

var _panel_sb: StyleBox
func _panel(ci: CanvasItem, r: Rect2) -> void:
	if _panel_sb == null:
		_panel_sb = UI.panel()
	ci.draw_style_box(_panel_sb, r)

func _draw_pill() -> void:
	if _road_text == "":
		return
	var f := pill.get_theme_default_font()
	var w := maxf(f.get_string_size(_road_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x, f.get_string_size(_where_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x) + 56
	var r := Rect2(pill.size.x / 2 - w / 2, 0, w, 84)
	_panel(pill, r)
	pill.draw_string(f, Vector2(r.position.x, 38), _road_text, HORIZONTAL_ALIGNMENT_CENTER, w, 32, Color.WHITE)
	pill.draw_string(f, Vector2(r.position.x, 70), _where_text, HORIZONTAL_ALIGNMENT_CENTER, w, 19, Color(0.75, 0.77, 0.8))

## Compteur : panneau de limitation, puis afficheur à cristaux liquides (vitesse en 7 segments, segments éteints en
## filigrane comme sur les tableaux de bord numériques des années 80).
var _lcd: Font
var argent_panel: Control
var _argent := -1.0
## Argent du garage (#59) : sous le compteur de vitesse, chiffres verts.
func _draw_argent() -> void:
	var r := Rect2(Vector2.ZERO, argent_panel.size)
	_panel(argent_panel, r)
	var f := argent_panel.get_theme_default_font()
	var t := preload("res://scripts/garage.gd").euros(maxf(_argent, 0.0))
	argent_panel.draw_string(f, Vector2(18, r.size.y / 2 + 11), "Argent", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(0.8, 0.8, 0.82))
	argent_panel.draw_string(f, Vector2(0, r.size.y / 2 + 13), t, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 20, 34, Color8(120, 255, 150))

func _draw_speed() -> void:
	var r := Rect2(Vector2.ZERO, speed_panel.size)
	_panel(speed_panel, r)
	var f := speed_panel.get_theme_default_font()
	var cy := r.size.y / 2
	if _limit > 0:
		var c := Vector2(62, cy)
		speed_panel.draw_circle(c, 36, Color.WHITE)
		speed_panel.draw_arc(c, 31, 0, TAU, 48, Color8(205, 30, 30), 9.0, true)
		var fs := 26 if _limit >= 100 else 30
		speed_panel.draw_string(f, c + Vector2(-40, fs * 0.36), str(_limit), HORIZONTAL_ALIGNMENT_CENTER, 80, fs, Color.BLACK)
	if _lcd == null:
		_lcd = UI.lcd_font()
	var kmh := int(round(car.kmh())) if car else 0
	var over := _limit > 0 and kmh > _limit + 5
	var win := Rect2(120, 14, r.size.x - 134, r.size.y - 28)
	speed_panel.draw_rect(win, Color8(14, 26, 20))
	speed_panel.draw_rect(Rect2(win.position, Vector2(win.size.x, 3)), Color8(4, 8, 6))
	var lit := Color8(255, 96, 70) if over else Color8(120, 255, 190)
	var fs2 := 50
	var x := win.position.x + 14
	var w := win.size.x - 116
	speed_panel.draw_string(_lcd, Vector2(x, cy + fs2 * 0.5), "888", HORIZONTAL_ALIGNMENT_RIGHT, w, fs2, Color(lit, 0.08))
	speed_panel.draw_string(_lcd, Vector2(x, cy + fs2 * 0.5), str(kmh), HORIZONTAL_ALIGNMENT_RIGHT, w, fs2, lit)
	speed_panel.draw_string(f, Vector2(win.end.x - 92, cy + 12), "km/h", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(lit, 0.75))
	# témoin de l'aide au maintien dans la voie (v6.25) : deux lignes de voie, vertes quand elle corrige
	if car and car.aide_voie:
		var on: bool = car.voie.actif
		var tc := Color8(120, 255, 190) if on else Color(lit, 0.18)
		var bx := win.end.x - 60
		var by := win.position.y + 6
		speed_panel.draw_line(Vector2(bx - 10, by + 22), Vector2(bx - 4, by), tc, 4.0)
		speed_panel.draw_line(Vector2(bx + 10, by + 22), Vector2(bx + 4, by), tc, 4.0)

func _disc(r: int, col: Color, text_col: Color) -> ImageTexture:
	var img := Image.create(r * 2, r * 2, false, Image.FORMAT_RGBA8)
	for y in r * 2:
		for x in r * 2:
			var d := Vector2(x - r + 0.5, y - r + 0.5).length()
			var a := clampf(r - d, 0.0, 1.0)
			var edge := 1.0 if d > r - 4 else 0.0
			img.set_pixel(x, y, Color(col.r, col.g, col.b, col.a * a).lerp(Color(1, 1, 1, 0.55 * a), edge * 0.6))
	return ImageTexture.create_from_image(img)

## Boutons : les commandes de conduite restent de grands disques translucides ; les autres sont des boutons poussoirs
## de planche de bord en pixel art (build_ui.py), avec témoin orange pour la radio et les activités.
const DASH := {"camera": "camera", "replacer": "replacer", "carte": "carte", "reglages": "reglages",
	"activites": "activites", "radio": "radio"}
var _leds := {}                       # action -> [bouton, état du témoin]

func _add_button(action: String, label: String, idx: int) -> void:
	var big := idx < 4
	var b := TouchScreenButton.new()
	b.action = action
	b.passby_press = true
	var icon: String = DASH.get(action, "")
	if not big and icon != "" and ResourceLoader.exists("res://assets/ui/btn_%s.png" % icon):
		b.texture_normal = load("res://assets/ui/btn_%s.png" % icon)
		b.texture_pressed = load("res://assets/ui/btn_%s_p.png" % icon)
		var rs := RectangleShape2D.new(); rs.size = b.texture_normal.get_size()
		b.shape = rs; b.shape_centered = true
		if ResourceLoader.exists("res://assets/ui/btn_%s_on.png" % icon):
			_leds[action] = [b, false, icon]
		add_child(b)
		buttons.append(b)
		return
	var r := 92 if big else 46
	b.texture_normal = _disc(r, Color(0.08, 0.09, 0.1, 0.38), Color.WHITE)
	b.texture_pressed = _disc(r, Color(0.9, 0.9, 0.9, 0.45), Color.WHITE)
	var sh := CircleShape2D.new(); sh.radius = r
	b.shape = sh; b.shape_centered = true
	var l := Label.new()
	l.text = label
	l.add_theme_font_size_override("font_size", 40 if big else (30 if label.length() <= 3 else 22))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size = Vector2(r * 2, r * 2)
	l.modulate = Color(1, 1, 1, 0.85)
	b.add_child(l)
	add_child(b)
	buttons.append(b)

## Témoins des boutons : radio allumée, activité en cours.
func _update_leds() -> void:
	var m = get_parent()
	for action in _leds:
		var e: Array = _leds[action]
		var on := false
		if action == "radio":
			on = m.get("radio") != null and m.radio.station >= 0
		elif action == "activites":
			var acts := get_tree().get_nodes_in_group("activites")
			on = not acts.is_empty() and str(acts[0].mode) != ""
		if on != e[1]:
			e[1] = on
			var b: TouchScreenButton = e[0]
			b.texture_normal = load("res://assets/ui/btn_%s%s.png" % [e[2], "_on" if on else ""])
			b.texture_pressed = load("res://assets/ui/btn_%s_p%s.png" % [e[2], "_on" if on else ""])

## Frein à main (#64) : disque translucide au-dessus de FREIN (on le tient) ; frein de parking : petit bouton « P »
## sous l'argent, témoin rouge quand il est serré.
var b_frein_main: TouchScreenButton
var b_parking: Button
var b_pied: Button
func _freins_tactiles() -> void:
	b_frein_main = TouchScreenButton.new()
	b_frein_main.action = "frein_main"
	b_frein_main.passby_press = true
	b_frein_main.texture_normal = _disc(40, Color(0.08, 0.09, 0.1, 0.38), Color.WHITE)
	b_frein_main.texture_pressed = _disc(40, Color(0.9, 0.9, 0.9, 0.45), Color.WHITE)
	var sh := CircleShape2D.new(); sh.radius = 40
	b_frein_main.shape = sh; b_frein_main.shape_centered = true
	var l := Label.new(); l.text = "F. À\nMAIN"; l.add_theme_font_size_override("font_size", 17)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size = Vector2(80, 80); l.modulate = Color(1, 1, 1, 0.85)
	b_frein_main.add_child(l)
	add_child(b_frein_main)
	b_parking = Button.new()
	b_parking.text = "P"
	b_parking.custom_minimum_size = Vector2(46, 46)
	b_parking.add_theme_font_size_override("font_size", 22)
	b_parking.focus_mode = Control.FOCUS_NONE
	b_parking.add_to_group("ui_zone")
	b_parking.pressed.connect(func():
		var c = get_parent().get("car")
		if c:
			c.frein_parking = not c.frein_parking)
	add_child(b_parking)
	# descendre / monter (#66) : petit bouton à côté du « P », seulement quand c'est possible
	b_pied = Button.new()
	b_pied.text = "À PIED"
	b_pied.custom_minimum_size = Vector2(110, 46)
	b_pied.add_theme_font_size_override("font_size", 20)
	b_pied.focus_mode = Control.FOCUS_NONE
	b_pied.add_to_group("ui_zone")
	b_pied.visible = false
	b_pied.pressed.connect(func():
		var pd = get_parent().get("pied")
		if pd:
			pd.basculer())
	add_child(b_pied)

func _layout() -> void:
	var s := get_viewport().get_visible_rect().size
	var gw := minf(s.x * 0.28, 540.0); var gh := minf(s.y * 0.36, 310.0)
	gps.position = Vector2(s.x - gw - 24, 24); gps.size = Vector2(gw, gh)
	speed_panel.position = Vector2(s.x - gw - 24, 24 + gh + 14); speed_panel.size = Vector2(gw, 96)
	argent_panel.position = Vector2(s.x - gw - 24, 24 + gh + 14 + 96 + 10); argent_panel.size = Vector2(gw, 58)
	if b_parking:
		b_parking.position = Vector2(s.x - 24 - 46, 24 + gh + 14 + 96 + 10 + 58 + 10)
		b_pied.position = b_parking.position - Vector2(110 + 10, 0)
		b_frein_main.position = Vector2(s.x - 470 + 12, s.y - 230 - 100)
	pill.position = Vector2(0, 20); pill.size = Vector2(s.x, 90)
	var pos := [Vector2(60, s.y - 230), Vector2(290, s.y - 230), Vector2(s.x - 470, s.y - 230), Vector2(s.x - 240, s.y - 260),
		Vector2(214, 22), Vector2(90, 22), Vector2(338, 22), Vector2(462, 22), Vector2(586, 22)]
	for i in buttons.size():
		buttons[i].position = pos[i]
	if _pli:
		_pli.position = Vector2(14, 30)

## Niveau de performances (0 Économie … 3 Maximale) : végétation, herbe, cultures, puis ombres, anticrénelage,
## distances, résolution (main.gd, set_post) ; mémorisé dans user://reglages.cfg.
func appliquer_niveau(i: int) -> void:
	var m = get_parent()
	m.vegetation.set_level(i)
	m.vegetation.update_now()
	m.crops.set_level(i)
	m.grass.set_level(i)
	m.set_post(i)
	var cfg := ConfigFile.new(); cfg.load("user://reglages.cfg")
	cfg.set_value("affichage", "vegetation", i); cfg.save("user://reglages.cfg")

## Fin d'un relevé de performances : bandeau « Envoyer » (ticket GitHub pré-rempli) / « Copier ».
func releve_perf_fini(texte: String) -> void:
	var box := HBoxContainer.new()
	box.position = Vector2(470, 128)
	box.add_theme_constant_override("separation", 12)
	var lab := Label.new()
	lab.text = "Mesure des performances terminée."
	lab.add_theme_font_size_override("font_size", 24)
	lab.add_theme_color_override("font_outline_color", Color.BLACK)
	lab.add_theme_constant_override("outline_size", 8)
	box.add_child(lab)
	var send := Button.new(); send.text = "Envoyer le relevé"
	send.add_theme_font_size_override("font_size", 24); send.custom_minimum_size = Vector2(0, 64)
	send.pressed.connect(func():
		var body := texte if texte.length() < 6000 else texte.substr(0, 6000)
		OS.shell_open("https://github.com/DisColow/rochetoirin-drive/issues/new?title=%s&body=%s" % [
			("Performances v%s" % ProjectSettings.get_setting("application/config/version", "?")).uri_encode(),
			("```\n%s\n```" % body).uri_encode()])
		send.text = "Merci !")
	box.add_child(send)
	var copy := Button.new(); copy.text = "Copier"
	copy.add_theme_font_size_override("font_size", 24); copy.custom_minimum_size = Vector2(0, 64)
	copy.pressed.connect(func():
		DisplayServer.clipboard_set(texte)
		copy.text = "Copié")
	box.add_child(copy)
	add_child(box)
	get_tree().create_timer(60.0).timeout.connect(func(): if is_instance_valid(box): box.queue_free())

func _show_drive(on: bool) -> void:
	_conduite = on
	for i in buttons.size():
		buttons[i].visible = on and (i < 4 or not replie)
	if _pli:
		_pli.visible = on
	gps.visible = on
	pill.visible = on
	speed_panel.visible = on
	argent_panel.visible = on
	if b_parking:
		b_parking.visible = on
		b_frein_main.visible = on
	get_tree().paused = not on

func _process(_dt: float) -> void:
	var t0_perf := Time.get_ticks_usec()
	_process_corps(_dt)
	PerfMon.note("hud", Time.get_ticks_usec() - t0_perf)

func _process_corps(_dt: float) -> void:
	_update_leds()
	# vue cockpit : la mini-carte disparaît, le GPS de la planche de bord la remplace (#60)
	var ck = get_parent().get("cockpit")
	var gps_vu: bool = _conduite and not (ck != null and ck.active)
	if gps.visible != gps_vu:
		gps.visible = gps_vu
	if b_parking and car:
		b_parking.modulate = Color(1.0, 0.35, 0.3) if car.frein_parking else Color(1, 1, 1, 0.75)
		var pd = get_parent().get("pied")
		if pd:
			var a_pied: bool = pd.actif
			b_pied.visible = _conduite and (a_pied or pd.peut_sortir())
			b_pied.text = ("MONTER" if pd.pres_de_la_voiture() else "VOITURE") if a_pied else "À PIED"
			# à pied : plus de compteur ni de freins à l'écran
			speed_panel.visible = _conduite and not a_pied
			b_parking.visible = _conduite and not a_pied
			b_frein_main.visible = _conduite and not a_pied
	var g = get_parent().get("garage")
	if g and float(g.argent) != _argent:
		_argent = float(g.argent)
		argent_panel.queue_redraw()
	# rangée du haut repliée d'elle-même au début d'une activité, dépliée à la fin (#52)
	var acts := get_tree().get_nodes_in_group("activites")
	var en_act := not acts.is_empty() and str(acts[0].mode) != ""
	if en_act != _en_activite:
		_en_activite = en_act
		replier(en_act)
	if _toast and _toast.visible:
		_toast_t -= _dt
		_toast.modulate.a = clampf(_toast_t / 0.6, 0.0, 1.0)
		if _toast_t <= 0.0:
			_toast.visible = false
	if Input.is_action_just_pressed("carte") and not map.visible and not UI.saisie_active():
		_open_map()
	var nav = get_parent().get("nav")
	if Input.is_action_just_pressed("reglages") and not map.visible and not UI.saisie_active() and not (nav and (nav.vient_de_fermer() or nav.menu_ouvert() != null)):
		_open_settings()
	if car:
		speed_panel.queue_redraw()
		_name_t -= _dt
		if _name_t <= 0.0:
			_name_t = 0.3
			var p := car.global_position
			_road_text = names.road_at(p)
			_limit = names.speed_limit
			_where_text = "%s  ·  x %d  z %d" % [names.commune_at(p), int(round(p.x)), int(round(p.z))]
			pill.queue_redraw()

## Pastille ronde de 28 px (témoin d'un interrupteur) : disque coloré cerné de sombre, reflet en haut.
func _pastille(c: Color) -> ImageTexture:
	var n := 28
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var ctr := Vector2(n, n) * 0.5 - Vector2(0.5, 0.5)
	for y in n:
		for x in n:
			var d := Vector2(x, y).distance_to(ctr)
			if d <= n * 0.5 - 0.5:
				var col := c if d < n * 0.5 - 3.0 else Color(0.08, 0.08, 0.09)
				if d < n * 0.5 - 3.0 and Vector2(x, y).distance_to(ctr - Vector2(4, 5)) < 4.0:
					col = col.lightened(0.45)
				img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)
