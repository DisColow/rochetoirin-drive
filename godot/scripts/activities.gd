## Activités (bouton ★, touche T) :
##  - Course : on pose sur la carte le départ A, des points de passage et l'arrivée B, puis on court contre la montre
##    (portes lumineuses, 3-2-1-partez, temps intermédiaires) ; le tracé n'est pas enregistré (« Recommencer » rejoue
##    le dernier).
##  - Chasse au lieu : le joueur 1 choisit un lieu (sur la carte, dans la liste des lieux nommés, ou au hasard pour
##    jouer seul), passe l'appareil au joueur 2 qui doit le trouver au plus vite ; la carte et le GPS montrent une zone
##    qui contient le lieu et rétrécit avec le temps.
##  - Taxi : un client attend au bord d'une route ; on s'arrête à côté, il annonce sa destination (lieu réel nommé) ;
##    compteur, pourboire selon le temps et la conduite (chocs), courses enchaînées et gains cumulés.
## Les repères (marks) et le cercle (circle) sont dessinés par la carte (map.gd) et le GPS (gps.gd).
extends CanvasLayer
const UI := preload("res://scripts/ui.gd")
const Relief := preload("res://scripts/relief.gd")
const PerfMon := preload("res://scripts/perf_monitor.gd")

const FONT_BIG := 34
const CHECK_R := 16.0            # rayon des portes de la course (m)
const TAXI_STOP_R := 14.0        # rayon de prise en charge / de dépôt (m)

var main: Node
var car: VehicleBody3D
var hud: CanvasLayer
var map: Control
var pts := PackedFloat32Array()   # points de route : x, z, y, cap
var places: Array = []

var mode := ""                    # "", "course", "chasse", "taxi"
var marks: Array = []             # [{p: Vector2, col: Color, txt: String, gps: bool}]
var circle := {}                  # {c: Vector2, r: float}
var join_marks := false           # relier les repères (tracé de la course)
var epreuves: Array = []          # épreuves chronométrées (#59, world/epreuves.json de build_epreuves.py)
var _epreuve := -1                # épreuve en cours (-1 : course libre)
var _offre: Control               # proposition de départ quand on s'arrête sur un départ d'épreuve
var _offre_vue := -1              # épreuve déjà proposée (pas de nouvelle proposition avant de s'éloigner)
const MEDAILLES := ["or", "argent", "bronze"]
const PRIMES := {"or": 150.0, "argent": 90.0, "bronze": 50.0}
const COUL_MEDAILLE := {"or": Color(1.0, 0.8, 0.15), "argent": Color(0.8, 0.82, 0.86), "bronze": Color(0.8, 0.5, 0.25)}

var _menu: Control
var _status: PanelContainer
var _status_l: Label
var _stop_btn: Button
var _bar: HBoxContainer
var _beacons: Array = []
var _bip: AudioStreamPlayer
var _t := 0.0

# course
var _route: Array = []            # indices de points de route (A, étapes…, B)
var _last_route: Array = []
var _best := INF
var _next := 0
var _count := 0.0
var _splits: Array = []

# chasse
var _target := Vector2.ZERO
var _target_name := ""
var _found_r := 40.0
var _c0 := Vector2.ZERO
var _r0 := 1000.0
var _dur := 300.0

# taxi
var _client: Node3D
var _cl_pos := Vector2.ZERO
var _dest := -1
var _dest_name := ""
var _cl_nom := ""                  # lieu de prise en charge annoncé (v6.25)
# courses variées (#53, sans pression de temps) : « arret » = petite course en chemin, on attend le client (le
# compteur tourne) ; « retour » = on le dépose, puis on revient le chercher plus tard et il raconte
var _sorte := "normale"
var _arret := -1                   # point de l'arrêt en chemin (-1 : aucun ou déjà fait)
var _arret_nom := ""
var _arret_t := 0.0                # temps d'attente restant à l'arrêt
var _arret_recit := ""
var _arret_annonce := ""
var _embarque_t := 0.0
var _rappel := {}                  # client à reprendre : {idx, nom, retour, retour_nom, recit, courses, client}
var _en_rappel := false
var _profil := {}                  # client MakeHuman : {fichier, sexe, age, modele}
const ARRETS := [
	["Vous pouvez vous arrêter à {lieu} ? J'ai un colis à récupérer, j'en ai pour deux minutes.", "Voilà, c'est fait ! Le colis était plus gros que prévu, mais il rentre."],
	["Arrêtez-moi deux minutes à {lieu}, je dépose un papier et je reviens.", "C'est bon, ils avaient même le tampon. On peut repartir."],
	["On fait un petit arrêt à {lieu} ? Je dois dire bonjour à quelqu'un, ce ne sera pas long.", "Il m'a gardé plus longtemps que prévu, désolé ! Prenez votre temps pour repartir."],
	["Vous m'attendez à {lieu} ? Je prends un truc et je reviens tout de suite.", "Me revoilà ! Merci d'avoir attendu."],
	["Petit détour par {lieu}, ça ne vous embête pas ? J'ai oublié mes clés chez une amie.", "Les clés étaient dans la poche de son manteau à elle. Ne me demandez pas comment."],
]
const RETOURS := [
	["J'ai rendez-vous chez le coiffeur. Vous pourrez revenir me chercher tout à l'heure ?", "Alors, la coupe ? Le coiffeur m'a parlé de pêche pendant une heure, je sais tout sur le brochet maintenant."],
	["Je vais voir ma sœur, ça fait des mois. Vous repassez me prendre plus tard ?", "Ma sœur m'a fait goûter son nouveau gratin. Une catastrophe, mais je l'adore."],
	["J'ai un entretien d'embauche. Vous revenez me chercher après ? Je vous ferai le récit !", "L'entretien s'est bien passé, je crois ! Ils m'ont demandé ma plus grande qualité, j'ai dit : la ponctualité. J'étais en avance."],
	["Je vais au marché. Vous me reprenez tout à l'heure ? J'aurai des sacs.", "Le marché était plein à craquer. J'ai trouvé des champignons magnifiques, et un melon qui sent jusqu'ici."],
	["Rendez-vous à la banque. Vous repassez me chercher ? Je vous dirai si je suis riche.", "La banque a dit oui ! Enfin, peut-être. Enfin, ils réfléchissent."],
	["Réunion de l'association. Vous pourrez revenir me prendre ? Ça ne devrait pas durer.", "Trois heures de réunion pour choisir la couleur des nappes. On a pris blanc, comme l'an dernier."],
	["Je vais chez le médecin, rien de grave. Vous me reprenez après ?", "Le médecin dit que tout va bien, il faut juste que je marche plus. Alors je prends le taxi, logique."],
]
var route_gps := PackedVector2Array()   # itinéraire affiché sur la carte et le GPS (v6.30, taxi)
var _itin = null
var _itin_t := 0.0
var _itin_cible := Vector2.INF
var _fare_d := 0.0
var _expected := 60.0
var _shocks := 0
var _rides := 0
var _total := 0.0
var _compteur: Control = null      # taximètre (taximetre.gd, issue #44)
var _stop_t := 0.0
var _prev_v := Vector3.ZERO
var _shock_cd := 0.0
var _phase := ""
var _talk: CanvasLayer             # conversations des clients (taxi_talk.gd)
var _status_t := 0.0            # > 0 : le message de fin s'efface au bout de ce temps


func _ready() -> void:
	add_to_group("activites")
	layer = 2
	pts = FileAccess.get_file_as_bytes("res://world/teleport.bin").to_float32_array()
	if FileAccess.file_exists("res://world/places.json"):
		places = JSON.parse_string(FileAccess.get_file_as_string("res://world/places.json"))
	if FileAccess.file_exists("res://world/epreuves.json"):
		epreuves = JSON.parse_string(FileAccess.get_file_as_string("res://world/epreuves.json"))
	_status = PanelContainer.new()
	_status.add_theme_stylebox_override("panel", preload("res://scripts/ui.gd").panel(30, 14))
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status.mouse_filter = Control.MOUSE_FILTER_PASS
	var sh := HBoxContainer.new(); sh.add_theme_constant_override("separation", 18)
	_status.add_child(sh)
	_status_l = Label.new(); _status_l.add_theme_font_size_override("font_size", 30)
	_status_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sh.add_child(_status_l)
	# arrêter l'activité en cours (taxi, course, chasse) d'un seul toucher
	_stop_btn = Button.new(); _stop_btn.text = "■ Arrêter"
	_stop_btn.add_theme_font_size_override("font_size", 26)
	_stop_btn.custom_minimum_size = Vector2(0, 64)
	_stop_btn.focus_mode = Control.FOCUS_NONE
	_stop_btn.add_to_group("ui_zone")
	_stop_btn.pressed.connect(func():
		_stop()
		hud.toast("Activité arrêtée.", 2.5))
	sh.add_child(_stop_btn)
	_status.visible = false
	add_child(_status)
	_bip = AudioStreamPlayer.new()
	if ResourceLoader.exists("res://assets/sfx/bip.wav"):
		_bip.stream = load("res://assets/sfx/bip.wav")
	add_child(_bip)
	if not InputMap.has_action("activites"):
		InputMap.add_action("activites")
		var k := InputEventKey.new(); k.physical_keycode = KEY_T
		InputMap.action_add_event("activites", k)
	map.picked.connect(_on_pick)
	_talk = preload("res://scripts/taxi_talk.gd").new()
	_talk.main = main
	_talk.hud = hud
	add_child(_talk)


# ================================================================ outils
func _vs() -> Vector2:
	return get_viewport().get_visible_rect().size

func _set_status(t: String) -> void:
	_status_l.text = t
	_stop_btn.visible = mode != ""
	_status.visible = t != ""
	_status.reset_size()
	_status.position = Vector2((_vs().x - _status.get_combined_minimum_size().x) / 2, 122)

func _fmt(t: float) -> String:
	var m := int(t / 60.0)
	var s := t - m * 60.0
	return ("%d min %04.1f s" % [m, s]).replace(".", ",") if m > 0 else ("%.1f s" % s).replace(".", ",")

func _euros(v: float) -> String:
	return ("%.2f €" % v).replace(".", ",")

func _nearest(w: Vector2) -> int:
	var best := -1; var bd := INF
	for i in range(0, pts.size(), 4):
		var dx := pts[i] - w.x; var dz := pts[i + 1] - w.y
		var d := dx * dx + dz * dz
		if d < bd:
			bd = d; best = i
	return best

func _rp(i: int) -> Vector2:
	return Vector2(pts[i], pts[i + 1])

func _r3(i: int) -> Vector3:
	return Vector3(pts[i], pts[i + 2], pts[i + 1])

func _car2() -> Vector2:
	return Vector2(car.global_position.x, car.global_position.z)

## Point de route proche de w dont le sens de marche va vers `toward` (départ d'une course, d'un dépôt…).
func _start_at(i: int, toward: Vector2) -> Array:
	var p := _rp(i)
	var best := i; var bs := -2.0
	for j in range(0, pts.size(), 4):
		if absf(pts[j] - p.x) > 12.0 or absf(pts[j + 1] - p.y) > 12.0:
			continue
		var h := deg_to_rad(pts[j + 3])
		var s := Vector2(sin(h), -cos(h)).dot((toward - _rp(j)).normalized())
		if s > bs:
			bs = s; best = j
	return [_r3(best), pts[best + 3]]

func _ground(x: float, z: float, fallback: float) -> float:
	var t = main.get("terrain")
	if t and t.data:
		var h: float = Relief.hauteur(Vector3(x, 0, z))
		if not is_nan(h):
			return h
	return fallback

## Colonne de lumière (porte de course, client, destination) : cylindre additif qui s'efface vers le haut + anneau au sol.
func _beacon(p: Vector3, col: Color, r: float, h := 70.0) -> Node3D:
	# colonne de lumière qui traverse le sol (10 m dessous) : aucun écart visible entre le sol et la lumière,
	# même en pente ; sa base, la plus vive, forme le cercle lumineux au ras du sol
	const DEPTH := 10.0
	var root := Node3D.new()
	var sm := ShaderMaterial.new()
	sm.shader = Shader.new()
	sm.shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
uniform vec3 col : source_color;
uniform float h = 70.0;
uniform float base = 0.0;
uniform float r = 10.0;
varying float y;
void vertex() { y = VERTEX.y + base; }
void fragment() {
	float edge = 0.06 + 0.94 * pow(1.0 - abs(dot(NORMAL, VIEW)), 2.2);   // bords lumineux, centre transparent
	float bands = 0.75 + 0.25 * sin(y * 0.86 - TIME * 4.0);
	float up = clamp(y / h, 0.0, 1.0);
	float foot = exp(-max(y, 0.0) * 3.5);          // anneau vif au ras du sol (et dessous), surtout vu de biais
	// caméra dans la colonne (on y entre en voiture) : elle s'efface, sinon sa paroi voile tout le paysage
	float d = length(CAMERA_POSITION_WORLD.xz - NODE_POSITION_WORLD.xz);
	float fade = smoothstep(r * 0.7, r * 1.6, d);
	ALBEDO = col * (edge * bands * (1.0 - up) * 0.9 + foot * (0.15 + 0.55 * edge)) * fade;
	// v6.19 : plus de mélange additif ; la luminosité devient une couverture tramée (Bayer), rendu opaque
	float a_ = clamp(max(ALBEDO.r, max(ALBEDO.g, ALBEDO.b)), 0.0, 1.0);
	ALBEDO = ALBEDO / max(a_, 0.001);
	// tramage ordonné (Bayer 4 × 4) : ALPHA_HASH n'existe pas en Compatibility, on jette les pixels nous-mêmes
	const float BAYER[16] = { 0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0 };
	if (a_ <= (BAYER[int(mod(FRAGCOORD.x, 4.0)) + int(mod(FRAGCOORD.y, 4.0)) * 4] + 0.5) / 16.0) {
		discard;
	}
}
"""
	sm.set_shader_parameter("col", col)
	sm.set_shader_parameter("h", h)
	sm.set_shader_parameter("base", (h - DEPTH) / 2.0)
	sm.set_shader_parameter("r", r)
	var mi := MeshInstance3D.new()
	var cy := CylinderMesh.new(); cy.top_radius = r; cy.bottom_radius = r; cy.height = h + DEPTH
	cy.cap_top = false; cy.cap_bottom = false; cy.radial_segments = 48; cy.rings = 1
	mi.mesh = cy
	mi.material_override = sm
	mi.position = Vector3(0, (h - DEPTH) / 2.0, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	root.position = p
	main.add_child(root)
	_beacons.append(root)
	return root

func _clear_world() -> void:
	_status_t = 0.0
	route_gps = PackedVector2Array()
	_itin_cible = Vector2.INF
	for b in _beacons:
		if is_instance_valid(b):
			b.queue_free()
	_beacons.clear()
	if _client and is_instance_valid(_client):
		_client.queue_free()
	_client = null
	marks = []
	circle = {}
	join_marks = false

func _stop() -> void:
	if main.net and main.net.armes:
		main.net.armes.arreter()
	_epreuve = -1
	_rappel = {}
	_arret = -1
	if _compteur:
		_compteur.visible = false
		_compteur.arreter()
	_clear_world()
	_talk.stop()
	mode = ""
	_phase = ""
	map.locked = false
	_set_status("")

# ================================================================ menus
func _panel(title: String) -> VBoxContainer:
	_close_menu()
	hud._show_drive(false)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", preload("res://scripts/ui.gd").panel(44, 28))
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 14)
	pc.add_child(v)
	var t := Label.new(); t.text = title; t.add_theme_font_size_override("font_size", 44); v.add_child(t)
	add_child(pc)
	_menu = pc
	pc.resized.connect(func(): pc.position = (_vs() - pc.size) / 2)
	return v

func _text(v: Control, s: String, size := 26, wrap := true) -> Label:
	var l := Label.new(); l.text = s; l.add_theme_font_size_override("font_size", size)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(820, 0)
	v.add_child(l)
	return l

func _btn(v: Control, s: String, f: Callable, w := 0.0) -> Button:
	var b := Button.new(); b.text = s
	b.custom_minimum_size = Vector2(w, 78)
	b.add_theme_font_size_override("font_size", 31)
	b.pressed.connect(f)
	v.add_child(b)
	return b

func _close_menu(resume := false) -> void:
	if _menu and is_instance_valid(_menu):
		_menu.queue_free()
	_menu = null
	if resume:
		hud._show_drive(true)

func open_menu() -> void:
	var v := _panel("Activités")
	_btn(v, "Course : créer un tracé (départ, étapes facultatives, arrivée)", _course_setup)
	if not _last_route.is_empty():
		_btn(v, "Recommencer le dernier tracé" + ("" if _best == INF else "  (record " + _fmt(_best) + ")"), _course_again)
	_btn(v, "Chasse au lieu (un joueur cache, l'autre cherche)", _hunt_menu)
	_btn(v, "Taxi" + ("" if _rides == 0 else "  (%d courses, %s)" % [_rides, _euros(_total)]), _taxi_start)
	if not epreuves.is_empty():
		_btn(v, "Épreuves chronométrées (%d) : partir d'ici" % epreuves.size(), _epreuves_menu)
	if main.garage:
		_btn(v, "Garage : améliorer la voiture  (%s)" % main.garage.euros(main.garage.argent), _garage)
	_btn(v, "Multijoueur (jusqu'à 4)" + ("  — %d joueur(s)" % main.net.joueurs.size() if main.net and main.net.en_ligne() else ""), _net_menu)
	if mode != "":
		_btn(v, "Arrêter l'activité en cours", _stop_and_close)
	_btn(v, "Fermer", _resume)

# ================================================================ garage (#43, garage_ui.gd)
func _garage() -> void:
	if mode != "":
		hud.toast("Arrêtez d'abord l'activité en cours.", 3.0)
		return
	if car.kmh() > 3.0:
		hud.toast("Arrêtez-vous pour entrer au garage.", 3.0)
		return
	_close_menu()
	hud._show_drive(false)
	get_tree().paused = false            # la caméra tourne autour de la voiture, qui reste freinée à l'arrêt
	var g = preload("res://scripts/garage_ui.gd").new()
	g.garage = main.garage; g.tuning = main.tuning; g.cam_rig = main.cam_rig
	g.ferme.connect(func(): _menu = null; hud._show_drive(true))
	add_child(g)
	_menu = g

# ================================================================ multijoueur (v6.44, net.gd)
func _net_menu() -> void:
	var net = main.net
	net.chercher(true)
	var v := _panel("Multijoueur")
	if net.en_ligne():
		var l := []
		for j in net.joueurs.values():
			l.append(j.nom)
		_text(v, ("Vous hébergez la partie" if net.hote() else "Vous êtes dans une partie") + " : " + ", ".join(l) + ".")
		if net.hote():
			_text(v, "Adresse pour rejoindre : " + net.adresse() + ". Lancez une course (Activités > Course) : elle démarre pour tout le monde.", 24)
			_btn(v, "Courses à armes : " + ("OUI (caisses « ? » sur le tracé)" if net.armes_actives else "non"), func(): net.armes_actives = not net.armes_actives; _net_menu())
		else:
			_text(v, "L'hôte lance les courses ; au taxi, chacun ses clients et un classement commun des gains.", 24)
		_btn(v, "Quitter la partie", func(): net.quitter(); _net_menu())
		_btn(v, "Fermer", _resume)
		return
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 12); v.add_child(h)
	var nl := Label.new(); nl.text = "Votre nom :"; nl.add_theme_font_size_override("font_size", 28); h.add_child(nl)
	var ne := LineEdit.new(); ne.text = net.nom; ne.custom_minimum_size = Vector2(380, 70)
	ne.add_theme_font_size_override("font_size", 30); h.add_child(ne)
	UI.saisie_tactile(ne, "Votre nom")
	ne.text_changed.connect(func(t): net.sauver_nom(t))
	_btn(v, "Héberger une partie (même Wi-Fi ou point d'accès du téléphone)", func(): net.sauver_nom(ne.text); if net.heberger(): _net_menu())
	if net.parties.is_empty():
		_text(v, "Aucune partie trouvée pour l'instant sur le réseau.", 24)
	for ip in net.parties:
		var p: Dictionary = net.parties[ip]
		_btn(v, "Rejoindre la partie de %s (%d/4)" % [p.nom, p.n], func(): net.sauver_nom(ne.text); net.rejoindre(ip); _resume())
	var h2 := HBoxContainer.new(); h2.add_theme_constant_override("separation", 12); v.add_child(h2)
	var ie := LineEdit.new(); ie.placeholder_text = "adresse de l'hôte (ex. 192.168.1.20)"
	ie.custom_minimum_size = Vector2(520, 70); ie.add_theme_font_size_override("font_size", 28); h2.add_child(ie)
	UI.saisie_tactile(ie, "Adresse de l'hôte")
	_btn(h2, "Rejoindre", func(): net.sauver_nom(ne.text); net.rejoindre(ie.text); _resume())
	_btn(v, "Actualiser", _net_menu)
	_btn(v, "Fermer", func(): net.chercher(false); _resume())

## Course lancée par l'hôte : même tracé, départ décalé derrière les autres selon le rang du joueur.
func course_reseau(route: Array, rang: int) -> void:
	_route = route.duplicate()
	_course_start(rang)

func _resume() -> void:
	_close_menu(true)

func _stop_and_close() -> void:
	_stop()
	_close_menu(true)

func _course_again() -> void:
	_route = _last_route.duplicate()
	_course_start()

# ================================================================ choix sur la carte
var _pick_cb: Callable

func _pick_on_map(hint: String, cb: Callable, buttons: Array) -> void:
	_close_menu()
	_pick_cb = cb
	map.pick_mode = true
	if not map.visible:
		hud._show_drive(false)
		map.open()
	map.set_hint(hint)
	if _bar and is_instance_valid(_bar):
		_bar.queue_free()
	_bar = HBoxContainer.new()
	_bar.add_theme_constant_override("separation", 18)
	for b in buttons:
		var bt := Button.new(); bt.text = b[0]
		bt.custom_minimum_size = Vector2(0, 84)
		bt.add_theme_font_size_override("font_size", 30)
		bt.pressed.connect(b[1])
		bt.set_meta("id", b[0])
		_bar.add_child(bt)
	map.add_child(_bar)
	_bar.reset_size()
	_bar.position = Vector2(30, map.size.y - 110)

func _end_pick() -> void:
	map.pick_mode = false
	map.set_hint("Touchez un endroit pour vous y rendre")
	if _bar and is_instance_valid(_bar):
		_bar.queue_free()
	_bar = null

func _on_pick(w: Vector2) -> void:
	if _pick_cb.is_valid():
		_pick_cb.call(w)

# ================================================================ course
func _course_setup() -> void:
	_stop()
	_route = []
	_pick_on_map("Course : touchez le départ A, puis les étapes éventuelles, puis l'arrivée B", _course_pick,
		[["Effacer le dernier point", _course_undo], ["Lancer la course", _course_start], ["Annuler", _course_cancel]])
	_course_marks()

func _course_pick(w: Vector2) -> void:
	var i := _nearest(w)
	if i < 0 or _rp(i).distance_to(w) > 120.0:
		hud.toast("Touchez plus près d'une route")
		return
	_route.append(i)
	_course_marks()

func _course_undo() -> void:
	if not _route.is_empty():
		_route.pop_back()
	_course_marks()

func _course_cancel() -> void:
	_end_pick()
	_route = []
	marks = []
	join_marks = false
	map.visible = false
	hud._show_drive(true)

func _course_marks() -> void:
	marks = []
	join_marks = true
	for k in _route.size():
		var txt := "A" if k == 0 else ("B" if k == _route.size() - 1 else str(k))
		var col := Color(0.2, 0.85, 0.3) if k == 0 else (Color(0.95, 0.25, 0.2) if txt == "B" else Color(1, 0.8, 0.15))
		marks.append({p = _rp(_route[k]), col = col, txt = txt, gps = true})
	var n := _route.size()
	if map.pick_mode:
			map.set_hint(["Course : touchez le départ A", "Touchez l'arrivée B, ou des étapes (le dernier point posé est l'arrivée)"][n]
			if n < 2 else ("A → B : lancez la course, ou ajoutez des étapes (le dernier point posé est l'arrivée)" if n == 2 else
			"%d points : A, %d étape(s), B. Ajoutez des points ou lancez la course" % [n, n - 2]))
	if _bar and is_instance_valid(_bar):
		for b in _bar.get_children():
			if b.get_meta("id") == "Lancer la course":
				b.disabled = n < 2
	map.queue_redraw()

func _course_start(rang := -1) -> void:
	if _route.size() < 2:
		hud.toast("Il faut un départ et une arrivée")
		return
	_end_pick()
	_close_menu()
	_clear_world()
	_last_route = _route.duplicate()
	mode = "course"
	map.locked = true
	map.visible = false
	hud._show_drive(true)
	var s = _start_at(_route[0], _rp(_route[1]))
	if rang > 0:
		# course en multijoueur : départ en file, 9 m derrière le joueur précédent
		var dir := (_rp(_route[1]) - _rp(_route[0])).normalized()
		var p: Vector3 = s[0] - Vector3(dir.x, 0.0, dir.y) * 9.0 * rang
		p.y = _ground(p.x, p.z, p.y) + (s[0].y - _ground(s[0].x, s[0].z, s[0].y))
		s[0] = p
	hud.teleport.emit(s[0], s[1])
	if rang < 0 and main.net and main.net.hote():
		main.net.lancer_course(_route)
	_next = 1
	_count = 3.99
	_t = 0.0
	_splits = []
	_phase = "depart"
	_course_marks()
	_course_beacons()
	if main.net and main.net.armes and main.net.en_ligne() and main.net.armes_actives:
		var pts3 := []
		for i in _route:
			pts3.append(_r3(i))
		main.net.armes.demarrer(pts3)

func _course_beacons() -> void:
	for b in _beacons:
		if is_instance_valid(b):
			b.queue_free()
	_beacons.clear()
	for k in range(_next, mini(_next + 2, _route.size())):
		var fin := k == _route.size() - 1
		var col := Color(0.95, 0.25, 0.2) if fin else Color(1.0, 0.8, 0.15)
		if k > _next:
			col = col * 0.45
		_beacon(_r3(_route[k]), col, CHECK_R)
	for m in marks.size():
		marks[m].gps = m >= _next

func _course_process(dt: float) -> void:
	if _phase == "depart":
		_count -= dt
		car.hold(0.15)
		var n := int(ceil(_count))
		_set_status("Course : %s\n%s" % ["A → B" if _route.size() == 2 else "%d étape(s)" % (_route.size() - 2), str(n) if n >= 1 else "Partez !"])
		if _count <= 0.0:
			_phase = "course"
			_bip.play()
		return
	if _phase != "course":
		return
	_t += dt
	var target := _rp(_route[_next])
	var d := _car2().distance_to(target)
	var lab := "arrivée" if _next == _route.size() - 1 else "étape %d / %d" % [_next, _route.size() - 2]
	_set_status("%s\nprochain point : %s, %d m" % [_fmt(_t), lab, int(d)])
	if d < CHECK_R:
		_bip.play()
		_splits.append(_t)
		if _next == _route.size() - 1:
			_phase = "fini"
			var rec := _t < _best
			_best = minf(_best, _t)
			# prime du garage (#43) : 2 € par 100 m de tracé (au moins 10 €), 15 € de plus pour un record
			var long := 0.0
			for i in range(1, _route.size()):
				long += _rp(_route[i - 1]).distance_to(_rp(_route[i]))
			var prime := maxf(10.0, roundf(long * 0.02)) + (15.0 if rec else 0.0)
			var med := ""
			if _epreuve >= 0:
				var r := _epreuve_fin(_t)
				med = r[0]; prime = r[1]
			if main.garage:
				main.garage.gagner(prime)
			if _epreuve >= 0:
				hud.toast("Arrivée ! %s — %s\nPrime : %s" % [_fmt(_t), {"or": "médaille d'or", "argent": "médaille d'argent", "bronze": "médaille de bronze"}.get(med, "pas de médaille"), _euros(prime)], 7.0)
			else:
				hud.toast("Arrivée ! %s%s\nPrime : %s" % [_fmt(_t), "  — record !" if rec else "  (record %s)" % _fmt(_best), _euros(prime)], 6.0)
			_epreuve = -1
			if main.net:
				main.net.arrivee_course(_t)
			_set_status("Arrivée en %s\n★ pour recommencer ou créer un autre tracé" % _fmt(_t))
			_status_t = 12.0
			_clear_world()
			mode = ""
			map.locked = false
			return
		hud.toast("Étape %d : %s" % [_next, _fmt(_t)], 2.0)
		_next += 1
		_course_beacons()

# ================================================================ épreuves (#59)
## Repères des départs d'épreuves pour la carte et le GPS (hors activité) : [{p, nom, med}].
func reperes_epreuves() -> Array:
	if mode != "" or map.pick_mode:
		return []
	var out := []
	for e in epreuves:
		out.append({p = Vector2(e.a[0], e.a[1]), nom = e.nom, med = _medaille(int(e.id))})
	return out

func _medaille(id: int) -> String:
	return str(main.garage.medailles.get(str(id), "")) if main.garage else ""

## Départs d'épreuves visibles dans le monde (#78 : seulement sur la carte, on les trouvait mal) : colonne de lumière
## dorée et grand drapeau à damier sur un mât, à moins de 700 m, hors activité.
var _balises := {}                # id d'épreuve -> Node3D
var _balises_t := 0.0
func _balises_epreuves() -> void:
	var c := _car2()
	var garder := {}
	if mode == "":
		for e in epreuves:
			var p := Vector2(e.a[0], e.a[1])
			if c.distance_to(p) < 700.0:
				garder[int(e.id)] = true
				if not _balises.has(int(e.id)):
					var y: float = Relief.hauteur(Vector3(p.x, 0.0, p.y))
					var b := _beacon(Vector3(p.x, y, p.y), Color(2.2, 1.6, 0.35), 7.0, 90.0)   # couleur > 1 : colonne plus dense
					_beacons.erase(b)                       # géré ici, pas effacé avec les repères d'activité
					b.add_child(_drapeau())
					_balises[int(e.id)] = b
	for k in _balises.keys():
		if not garder.has(k):
			if is_instance_valid(_balises[k]):
				_balises[k].queue_free()
			_balises.erase(k)

func _drapeau() -> Node3D:
	var n := Node3D.new()
	var mat := StandardMaterial3D.new(); mat.albedo_color = Color(0.85, 0.85, 0.88); mat.metallic = 0.6
	var mat_d := ShaderMaterial.new()
	mat_d.shader = Shader.new()
	mat_d.shader.code = """
shader_type spatial;
render_mode cull_disabled;
void vertex() { VERTEX.z += sin(VERTEX.x * 1.6 - TIME * 4.0) * 0.2 * (VERTEX.x + 2.1) / 4.2; }
void fragment() {
	vec2 q = floor(UV * vec2(6.0, 4.0));
	float d = mod(q.x + q.y, 2.0);
	ALBEDO = vec3(d * 0.95 + 0.03);
	ROUGHNESS = 0.8;
}
"""
	var mat_ = MeshInstance3D.new()
	var cy := CylinderMesh.new(); cy.top_radius = 0.09; cy.bottom_radius = 0.12; cy.height = 9.0
	mat_.mesh = cy; mat_.material_override = mat; mat_.position = Vector3(3.5, 4.5, 0)
	n.add_child(mat_)
	var dr := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(4.2, 2.8); pm.orientation = PlaneMesh.FACE_Z; pm.subdivide_width = 8
	dr.mesh = pm; dr.material_override = mat_d; dr.position = Vector3(3.5 + 2.15, 7.5, 0)
	n.add_child(dr)
	return n

## Menu des épreuves (#101) : on choisit une épreuve et la voiture est posée sur sa ligne de départ, sans y rouler.
func _epreuves_menu() -> void:
	if mode != "":
		hud.toast("Arrêtez d'abord l'activité en cours.", 3.0)
		return
	var v := _panel("Épreuves chronométrées")
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(900, minf(_vs().y * 0.62, 640.0))
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var l := VBoxContainer.new(); l.add_theme_constant_override("separation", 10)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(l)
	var c := _car2()
	var tri := epreuves.duplicate()
	tri.sort_custom(func(a, b): return c.distance_to(Vector2(a.a[0], a.a[1])) < c.distance_to(Vector2(b.a[0], b.a[1])))
	for e in tri:
		var id := int(e.id)
		var med := _medaille(id)
		var b := _btn(l, "%s — %.1f km%s   (à %.1f km)" % [e.nom, float(e.km), ("  · " + med) if med != "" else "",
			c.distance_to(Vector2(e.a[0], e.a[1])) / 1000.0], func(): _close_menu(true); _epreuve_depart(id))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn(v, "Retour", open_menu)

func _epreuve_proche() -> void:
	var c := _car2()
	var ici := -1
	for e in epreuves:
		if c.distance_to(Vector2(e.a[0], e.a[1])) < 25.0:          # #78 : rayon élargi
			ici = int(e.id)
	if ici < 0:
		_offre_vue = -1
		if _offre and is_instance_valid(_offre):
			_offre.queue_free()
		return
	if ici == _offre_vue or car.kmh() > 25.0 or _menu != null:
		return
	_offre_vue = ici
	var e: Dictionary = epreuves[ici]
	_offre = PanelContainer.new()
	_offre.add_theme_stylebox_override("panel", preload("res://scripts/ui.gd").panel(28, 16))
	_offre.add_to_group("ui_zone")
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 8); _offre.add_child(v)
	var med := _medaille(ici)
	_text(v, "Épreuve : %s (%.1f km)" % [e.nom, float(e.km)], 26, true)
	_text(v, "Or %s · Argent %s · Bronze %s%s" % [_fmt(float(e["or"])), _fmt(float(e.argent)), _fmt(float(e.bronze)),
		("   ·   votre médaille : " + med) if med != "" else ""], 22, true)
	var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 12); v.add_child(h)
	_btn(h, "Départ !", func(): _offre.queue_free(); _epreuve_depart(ici), 260)
	_btn(h, "Plus tard", func(): _offre.queue_free(), 220)
	add_child(_offre)
	_offre.reset_size()
	_offre.position = Vector2((_vs().x - _offre.size.x) / 2, _vs().y - _offre.size.y - 260)

func _epreuve_depart(id: int) -> void:
	var e: Dictionary = epreuves[id]
	_route = [_nearest(Vector2(e.a[0], e.a[1]))]
	for q in e.etapes:
		_route.append(_nearest(Vector2(q[0], q[1])))
	_route.append(_nearest(Vector2(e.b[0], e.b[1])))
	_course_start()
	_epreuve = id
	hud.toast("%s\nOr %s · Argent %s · Bronze %s" % [e.nom, _fmt(float(e["or"])), _fmt(float(e.argent)), _fmt(float(e.bronze))], 6.0)

## Fin d'une épreuve : médaille d'après le temps ; la prime ne paie que le progrès (de bronze à or : la différence).
func _epreuve_fin(t: float) -> Array:
	var e: Dictionary = epreuves[_epreuve]
	var med := ""
	for m in MEDAILLES:
		if t <= float(e[m]):
			med = m
			break
	var avant := _medaille(_epreuve)
	var prime := 10.0
	if med != "" and (avant == "" or MEDAILLES.find(med) < MEDAILLES.find(avant)):
		prime = PRIMES[med] - (PRIMES[avant] if avant != "" else 0.0)
		if main.garage:
			main.garage.medailles[str(_epreuve)] = med
			main.garage.sauver()
	return [med, prime]

# ================================================================ chasse au lieu
func _hunt_menu() -> void:
	_stop()
	var v := _panel("Chasse au lieu")
	_text(v, "Joueur 1 : choisissez le lieu à faire trouver, sans que le joueur 2 regarde. Le joueur 2 le cherche ensuite, "
		+ "en partant d'ici ; la carte lui montre une zone qui contient le lieu et qui rétrécit avec le temps.")
	_btn(v, "Choisir un lieu nommé (gare, mairie, église…)", _hunt_list)
	_btn(v, "Choisir un endroit sur la carte", _hunt_map)
	_btn(v, "Lieu tiré au sort (jouer seul)", _hunt_random)
	_btn(v, "Retour", open_menu)

func _hunt_map() -> void:
	_pick_on_map("Joueur 1 : touchez l'endroit à faire trouver", _hunt_pick_map, [["Annuler", _course_cancel]])

func _hunt_pick_map(w: Vector2) -> void:
	var i := _nearest(w)
	if i < 0 or _rp(i).distance_to(w) > 120.0:
		hud.toast("Touchez plus près d'une route")
		return
	_end_pick()
	map.visible = false
	_hunt_confirm(_rp(i), "", 30.0)

func _hunt_list() -> void:
	var v := _panel("Lieu à faire trouver")
	var f := LineEdit.new(); f.placeholder_text = "Rechercher (gare, mairie, Saint-Chef…)"
	f.add_theme_font_size_override("font_size", 28); f.custom_minimum_size = Vector2(900, 70)
	v.add_child(f)
	UI.saisie_tactile(f, "Rechercher un lieu")
	var il := ItemList.new()
	il.custom_minimum_size = Vector2(900, minf(_vs().y * 0.5, 520))
	il.add_theme_font_size_override("font_size", 26)
	v.add_child(il)
	var fill := func(q: String):
		il.clear()
		q = q.to_lower()
		for k in places.size():
			var p = places[k]
			var s := "%s  —  %s" % [p.n, p.c]
			if q == "" or s.to_lower().contains(q):
				il.add_item(s)
				il.set_item_metadata(il.item_count - 1, k)
	fill.call("")
	f.text_changed.connect(fill)
	il.item_selected.connect(func(ix): _hunt_place(il.get_item_metadata(ix)))
	_btn(v, "Retour", _hunt_menu)

func _hunt_place(k: int) -> void:
	var p = places[k]
	_hunt_confirm(Vector2(p.x, p.z), "%s (%s)" % [p.n, p.c], 45.0)

func _hunt_random() -> void:
	var c := _car2()
	var pool := []
	for k in places.size():
		var d := c.distance_to(Vector2(places[k].x, places[k].z))
		if d > 700.0 and d < 6000.0:
			pool.append(k)
	if pool.is_empty():
		pool = range(places.size())
	var p = places[pool[randi() % pool.size()]]
	_target = Vector2(p.x, p.z); _target_name = "%s (%s)" % [p.n, p.c]; _found_r = 45.0
	_hunt_begin()

func _hunt_confirm(t: Vector2, name: String, r: float) -> void:
	_target = t; _target_name = name; _found_r = r
	var v := _panel("Lieu choisi")
	_text(v, ("À trouver : " + name) if name != "" else "Un endroit secret a été choisi (aucun indice que la zone sur la carte).")
	_text(v, "Passez l'appareil au joueur 2, puis appuyez sur « C'est parti ».")
	_btn(v, "C'est parti", _hunt_begin)
	_btn(v, "Annuler", _resume)

func _hunt_begin() -> void:
	_close_menu()
	_clear_world()
	mode = "chasse"
	map.locked = true
	var d := _car2().distance_to(_target)
	_r0 = clampf(d * 0.75, 450.0, 2600.0)
	_c0 = _target + Vector2.from_angle(randf() * TAU) * _r0 * randf_range(0.35, 0.75)
	_dur = clampf(d / 6.0, 150.0, 720.0)
	_t = 0.0
	_phase = "chasse"
	hud._show_drive(true)
	hud.toast("À toi de jouer ! La zone rétrécit avec le temps", 4.0)

func _hunt_process(dt: float) -> void:
	if _phase != "chasse":
		return
	_t += dt
	var k := clampf(_t / _dur, 0.0, 1.0)
	var r := lerpf(_r0, 60.0, k)
	circle = {c = _target + (_c0 - _target) * (r / _r0), r = r}
	var what := ("À trouver : " + _target_name) if _target_name != "" else "Endroit secret"
	_set_status("%s\n%s  ·  zone de %d m" % [what, _fmt(_t), int(r)])
	if _car2().distance_to(_target) < _found_r:
		_bip.play()
		_phase = "fini"
		circle = {}
		marks = [{p = _target, col = Color(0.2, 0.85, 0.3), txt = "Trouvé", gps = true}]
		_beacon(Vector3(_target.x, _ground(_target.x, _target.y, car.global_position.y), _target.y), Color(0.3, 1.0, 0.4), 10.0)
		if main.garage:
			main.garage.gagner(25.0)                       # prime du garage (#43)
		hud.toast("Trouvé en %s !\nPrime : 25 €" % _fmt(_t), 7.0)
		_set_status("Trouvé en %s\n★ pour rejouer" % _fmt(_t))
		_status_t = 12.0
		mode = ""
		map.locked = false

# ================================================================ taxi
func _taxi_start() -> void:
	_close_menu()
	_clear_world()
	mode = "taxi"
	map.locked = true             # pas de téléportation pendant le taxi (■ Arrêter pour reprendre la main)
	hud._show_drive(true)
	# compteur de taxi (issue #44), sous les boutons du haut à gauche
	if _compteur == null:
		_compteur = preload("res://scripts/taximetre.gd").new()
		hud.add_child(_compteur)
	_compteur.position = Vector2(24, 136)            # sous le bouton ‹ / › de la rangée du haut (#52)
	_compteur.visible = true
	_compteur.arreter()
	_taxi_new_client()

func _taxi_new_client() -> void:
	_phase = "attente"
	marks = []
	for b in _beacons:
		if is_instance_valid(b):
			b.queue_free()
	_beacons.clear()
	var c := _car2()
	var pick := -1
	# v6.25 : le client attend le plus souvent devant un lieu nommé (places.json), annoncé par son nom pour que les
	# connaisseurs prennent des raccourcis ; sinon au bord d'une route, annoncée par son nom et sa commune
	_cl_nom = ""
	_en_rappel = false
	if not _rappel.is_empty() and int(_rappel.courses) <= 0:
		# on revient chercher le client déposé plus tôt (#53)
		_en_rappel = true
		pick = int(_rappel.idx)
		_cl_nom = str(_rappel.nom)
	var lieux := []
	for k in places.size():
		var d := c.distance_to(Vector2(places[k].x, places[k].z))
		if d > 250.0 and d < 1500.0 and str(places[k].n) != str(places[k].get("c", "")):
			lieux.append(k)
	if pick < 0 and not lieux.is_empty() and randf() < 0.8:
		var pl = places[lieux[randi() % lieux.size()]]
		var i := _nearest(Vector2(pl.x, pl.z))
		if i >= 0 and _rp(i).distance_to(Vector2(pl.x, pl.z)) < 60.0:
			pick = i
			var com := str(pl.get("c", ""))
			_cl_nom = "%s (%s)" % [pl.n, com] if com != "" and not str(pl.n).contains(com) else str(pl.n)
	for k in 300:
		if pick >= 0:
			break
		var i := (randi() % (pts.size() / 4)) * 4
		var d := _rp(i).distance_to(c)
		if d > 220.0 and d < 900.0:
			pick = i
	if pick < 0:
		pick = _nearest(c + Vector2(300, 0))
	if _cl_nom == "" and hud and hud.get("names"):
		var q := Vector3(_rp(pick).x, 0, _rp(pick).y)
		var com: String = hud.names.commune_at(q)
		_cl_nom = hud.names.road_at_fixe(q) + (" (%s)" % com if com != "" else "")
	var h := deg_to_rad(pts[pick + 3])
	var fwd := Vector2(sin(h), -cos(h))
	var side := Vector2(-fwd.y, fwd.x)          # à droite de la voie
	var p := _rp(pick) + side * 5.0
	_cl_pos = _rp(pick)
	var y := _ground(p.x, p.y, pts[pick + 2])
	if _client and is_instance_valid(_client):
		_client.queue_free()
	# clients faits avec MakeHuman (#55) : assets/clients/mh_<n>.glb (blender_makehuman.py), sexe et âge dans mh.json ;
	# le même client quand on revient le chercher (#53)
	_profil = {}
	var mh: Array = JSON.parse_string(FileAccess.get_file_as_string("res://assets/clients/mh.json")) if FileAccess.file_exists("res://assets/clients/mh.json") else []
	if not mh.is_empty():
		var k := int(_rappel.get("modele", randi() % mh.size())) if _en_rappel else randi() % mh.size()
		_profil = mh[k].duplicate()
		_profil["modele"] = k
		_client = (load("res://assets/clients/" + str(mh[k].fichier)) as PackedScene).instantiate()
		_client.set_script(preload("res://scripts/pieton.gd"))
		if not _en_rappel and _talk.choisir_caractere() == "ivre":
			_client.ivre = true
	else:
		var path := "res://assets/clients/client%d.glb" % (randi() % 4)
		_client = (load(path) as PackedScene).instantiate() if ResourceLoader.exists(path) else Node3D.new()
	_client.position = Vector3(p.x, y, p.y)
	_client.rotation.y = atan2(-side.x, -side.y)          # face à la route (+Z du modèle vers la chaussée)
	main.add_child(_client)
	_beacon(Vector3(_cl_pos.x, pts[pick + 2], _cl_pos.y), Color(0.25, 0.75, 1.0), 6.0, 40.0)
	marks = [{p = _cl_pos, col = Color(0.25, 0.75, 1.0), txt = "Client", gps = true}]
	if _en_rappel:
		hud.toast("Retour : allez rechercher votre client à " + _cl_nom, 5.0)
	elif _cl_nom != "":
		hud.toast("Client à prendre : " + _cl_nom, 5.0)
	_shocks = 0
	_stop_t = 0.0

## Itinéraire GPS vers la cible (client puis destination) : recalculé si la cible change ou si l'on s'en écarte.
func _itineraire(dt: float, cible: Vector2) -> void:
	if _itin == null:
		_itin = preload("res://scripts/itineraire.gd").new()
	_itin.suivre()
	if _itin.pret:
		route_gps = _itin.restant(_car2())
	_itin_t -= dt
	if _itin_t > 0.0:
		return
	_itin_t = 1.0
	var c := _car2()
	if cible != _itin_cible or route_gps.size() < 2 or _itin.ecart(c) > 35.0:
		_itin_cible = cible
		_itin.calculer(c, cible)

func _taxi_process(dt: float) -> void:
	var vise := _dest if _arret < 0 else _arret
	_itineraire(dt, _cl_pos if _phase == "attente" else _rp(vise))
	var c := _car2()
	var slow: bool = car.kmh() < 10.0
	var head := "TAXI  ·  %d course(s)  ·  %s" % [_rides, _euros(_total)]
	if _phase == "attente":
		var d := c.distance_to(_cl_pos)
		if _cl_nom != "":
			_set_status("%s\nClient : %s\n%d m (repère bleu)" % [head, _cl_nom, int(d)])
		else:
			_set_status("%s\nUn client attend à %d m (repère bleu)" % [head, int(d)])
		if d < TAXI_STOP_R and slow:
			_stop_t += dt
			if _stop_t > 0.6:
				_embarquer()
		else:
			_stop_t = 0.0
	elif _phase == "embarque":
		# le client marche jusqu'à la portière arrière droite ; s'il traîne (voiture repartie, obstacle) : 8 s au plus
		_embarque_t += dt
		var porte := car.global_transform * Vector3(-1.4, 0.0, -0.4)
		if _client and is_instance_valid(_client) and "cible" in _client:
			_client.cible = porte
			if Vector2(_client.global_position.x, _client.global_position.z).distance_to(Vector2(porte.x, porte.z)) < 0.7 or _embarque_t > 8.0:
				_teleport_fx(_client.global_position)
				_taxi_pickup()
		else:
			_taxi_pickup()
	elif _phase == "arret":
		# le client fait sa course (#53) : le compteur tourne au tarif d'attente, rien ne presse
		if _compteur:
			_compteur.compter(dt, 0.0, 0.0)
		_arret_t -= dt
		_set_status("%s\nLe client est à %s… (le compteur tourne)" % [head, _arret_nom])
		if _arret_t <= 0.0:
			_arret = -1
			_phase = "course"
			for bc in _beacons:
				if is_instance_valid(bc):
					bc.queue_free()
			_beacons.clear()
			if _client and is_instance_valid(_client):
				_client.visible = false
			_beacon(_r3(_dest), Color(0.2, 0.95, 0.4), 8.0, 60.0)
			marks = [{p = _rp(_dest), col = Color(0.2, 0.95, 0.4), txt = "Dépôt", gps = true}]
			_talk.dire(_arret_recit)
			_bip.play()
	elif _phase == "course":
		_t += dt
		if _compteur:
			_compteur.compter(dt, Vector2(car.linear_velocity.x, car.linear_velocity.z).length() * dt, car.kmh())
		var dest := _rp(vise)
		var d := c.distance_to(dest)
		var stars := _stars()
		var nom := _arret_nom + " (arrêt)" if _arret >= 0 else _dest_name
		_set_status("%s\n→ %s : %d m  ·  %s" % [head, nom, int(d), "★".repeat(stars) + "☆".repeat(5 - stars)])
		if d < TAXI_STOP_R and slow:
			_stop_t += dt
			if _stop_t > 0.6:
				_stop_t = 0.0
				if _arret >= 0:
					_phase = "arret"
					_bip.play()
					hud.toast("Le client descend un moment : attendez-le ici, le compteur tourne.", 4.0)
				else:
					_taxi_drop()
		else:
			_stop_t = 0.0

## Note de conduite : les chocs seulement (#53 : pas de pression de temps, le retard ne compte plus).
func _stars() -> int:
	return clampi(5 - _shocks, 1, 5)

## Arrêt près du client : il vient à la voiture à pied (#55), puis monte façon téléportation de Dragon Ball Z.
func _embarquer() -> void:
	_phase = "embarque"
	_embarque_t = 0.0
	_set_status("Le client arrive…")

## Éclair de téléportation (#55) : colonne de lumière qui se resserre, flash, souffle bref.
func _teleport_fx(p: Vector3) -> void:
	var n := Node3D.new()
	main.add_child(n)
	n.global_position = p
	var col := MeshInstance3D.new()
	var cy := CylinderMesh.new(); cy.top_radius = 0.5; cy.bottom_radius = 0.5; cy.height = 2.6; cy.radial_segments = 12
	col.mesh = cy
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.98, 0.8)
	col.material_override = m
	col.position.y = 1.3
	col.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(col)
	var l := OmniLight3D.new(); l.light_color = Color(1.0, 0.95, 0.7); l.light_energy = 4.0; l.omni_range = 6.0
	l.position.y = 1.2
	n.add_child(l)
	var son := AudioStreamPlayer3D.new()
	son.stream = load("res://assets/sfx/teleport.ogg") if ResourceLoader.exists("res://assets/sfx/teleport.ogg") else null
	son.bus = "Voiture"
	n.add_child(son)
	if son.stream:
		son.play()
	var tw := n.create_tween()
	tw.tween_property(col, "scale", Vector3(0.05, 1.4, 0.05), 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(l, "light_energy", 0.0, 0.35)
	tw.tween_callback(n.queue_free).set_delay(0.5)

func _taxi_pickup() -> void:
	if _client and is_instance_valid(_client):
		_client.visible = false
	var c := _car2()
	var pool := []
	for k in places.size():
		var d := c.distance_to(Vector2(places[k].x, places[k].z))
		if d > 600.0 and d < 4500.0:
			pool.append(k)
	if pool.is_empty():
		pool = range(places.size())
	var p = places[pool[randi() % pool.size()]]
	_dest = _nearest(Vector2(p.x, p.z))
	_dest_name = p.n
	_arret = -1
	_sorte = "normale"
	if _en_rappel:
		_dest = int(_rappel.retour)
		_dest_name = str(_rappel.retour_nom)
		p = {"n": _dest_name, "c": "", "k": "autre"}
	else:
		var r := randf()
		_sorte = "arret" if r < 0.22 else ("retour" if r < 0.38 and _rappel.is_empty() else "normale")
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--taxi-sorte="):                 # essai : type de course imposé
				_sorte = arg.trim_prefix("--taxi-sorte=")
				if _sorte == "retour" and not _rappel.is_empty():
					_sorte = "normale"
		if _sorte == "arret":
			# arrêt en chemin : un lieu à 300-1500 m, plus proche de la destination que la voiture
			var cands := []
			for k in places.size():
				var q := Vector2(places[k].x, places[k].z)
				var dq := c.distance_to(q)
				if dq > 300.0 and dq < 1500.0 and q.distance_to(_rp(_dest)) < c.distance_to(_rp(_dest)):
					cands.append(k)
			if cands.is_empty():
				_sorte = "normale"
			else:
				var a2 = places[cands[randi() % cands.size()]]
				_arret = _nearest(Vector2(a2.x, a2.z))
				_arret_nom = str(a2.n)
				var paire: Array = ARRETS[randi() % ARRETS.size()]
				_arret_recit = paire[1]
				_arret_t = randf_range(35.0, 70.0)
				_arret_annonce = str(paire[0]).replace("{lieu}", _arret_nom)
	_fare_d = c.distance_to(_rp(_dest)) * 1.3
	if _arret >= 0:                  # détour par l'arrêt compté dans le temps prévu (#75)
		_fare_d = (c.distance_to(_rp(_arret)) + _rp(_arret).distance_to(_rp(_dest))) * 1.3
	_expected = _fare_d / 11.0 + 20.0
	_t = 0.0
	_shocks = 0
	_stop_t = 0.0
	_phase = "course"
	if _compteur:
		_compteur.demarrer()
	for b in _beacons:
		if is_instance_valid(b):
			b.queue_free()
	_beacons.clear()
	if _arret >= 0:
		_beacon(_r3(_arret), Color(1.0, 0.75, 0.2), 8.0, 60.0)
		marks = [{p = _rp(_arret), col = Color(1.0, 0.75, 0.2), txt = "Arrêt", gps = true}]
	else:
		_beacon(_r3(_dest), Color(0.2, 0.95, 0.4), 8.0, 60.0)
		marks = [{p = _rp(_dest), col = Color(0.2, 0.95, 0.4), txt = "Dépôt", gps = true}]
	_bip.play()
	if _en_rappel:
		_talk.start_ride(hud.names.commune_at(car.global_position), p.n, p.c, "autre", _rappel.client)
		_talk.dire("Ah, vous voilà ! " + str(_rappel.recit), 2.5)
		_rappel = {}
	else:
		_talk.start_ride(hud.names.commune_at(car.global_position), p.n, p.c, str(p.get("k", "autre")), {}, _profil)
	if _arret >= 0:
		_talk.dire(_arret_annonce)                     # juste après le bonjour (file des répliques)
	if _sorte == "retour":
		var mot: Array = RETOURS[randi() % RETOURS.size()]
		_rappel = {"idx": _dest, "nom": _dest_name, "retour": _nearest(c), "retour_nom": _cl_nom if _cl_nom != "" else "son point de départ",
			"recit": mot[1], "courses": 1, "client": {}, "modele": _profil.get("modele", 0)}
		_talk.dire(str(mot[0]))

func _taxi_drop() -> void:
	# prix au compteur (issue #44) ; à défaut, l'ancien forfait sur la distance
	var fare := (_compteur.montant if _compteur else 3.5 + 1.6 * _fare_d / 1000.0) as float
	if _compteur:
		_compteur.arreter()
	var stars := _stars()
	var talk: Dictionary = _talk.end_ride(stars)
	if not _rappel.is_empty():
		if (_rappel.client as Dictionary).is_empty():
			_rappel.client = _talk.client.duplicate()          # le même client, plus tard (#53)
			hud.toast("Pensez à revenir chercher votre client à %s après la prochaine course." % _rappel.nom, 5.0)
		else:
			_rappel.courses = int(_rappel.courses) - 1
	# conversation : jusqu'à +24 % de pourboire si le client a apprécié, jusqu'à -18 % s'il a été agacé
	# temps (#75) : une part du pourboire, sans chrono affiché (pas de pression, #53) : +12 % dans les temps, rien
	# à 1,8 fois le temps prévu, -5 % au-delà de 2,5 fois
	var lent := _t / maxf(_expected, 1.0)
	var part_temps := 0.12 if lent <= 1.0 else (lerpf(0.12, 0.0, (lent - 1.0) / 0.8) if lent <= 1.8 else lerpf(0.0, -0.05, clampf((lent - 1.8) / 0.7, 0.0, 1.0)))
	var tip: float = maxf(0.0, fare * ([0.0, 0.0, 0.05, 0.1, 0.15, 0.25][stars] + 0.06 * float(talk.sat) + part_temps))
	_rides += 1
	_total += fare + tip
	if main.garage:
		main.garage.gagner(fare + tip)
	if main.net:
		main.net.gains_taxi(_total, _rides)
	_bip.play()
	var conv := ""
	if float(talk.sat) >= 1.5:
		conv = "\nLe client a aimé discuter avec vous."
	elif float(talk.sat) <= -1.5:
		conv = "\nLa conversation n'a pas plu au client."
	if part_temps >= 0.1:
		conv += "\nTrajet rapide : le client est content."
	elif part_temps < 0.0:
		conv += "\nLe trajet a paru long au client."
	hud.toast("Course : %s + pourboire %s%s" % [_euros(fare), _euros(tip), conv], 5.0)
	if _client and is_instance_valid(_client):
		if "cible" in _client:
			# il réapparaît près de la portière et s'en va à pied vers sa destination (#55), puis disparaît
			var cl := _client
			var porte := car.global_transform * Vector3(-1.4, 0.0, -0.4)
			cl.global_position = Vector3(porte.x, Relief.hauteur(porte), porte.z)
			cl.visible = true
			_teleport_fx(cl.global_position)
			var loin := car.global_transform * Vector3(-12.0, 0.0, -4.0)
			cl.cible = loin
			get_tree().create_timer(9.0).timeout.connect(func():
				if is_instance_valid(cl):
					cl.queue_free())
		else:
			_client.queue_free()
	_client = null
	_phase = "pause"
	get_tree().create_timer(3.0).timeout.connect(func():
		if mode == "taxi":
			_taxi_new_client())

# ================================================================ boucle
func _process(dt: float) -> void:
	var t0_perf := Time.get_ticks_usec()
	_process_corps(dt)
	PerfMon.note("activities", Time.get_ticks_usec() - t0_perf)

func _process_corps(dt: float) -> void:
	if Input.is_action_just_pressed("activites") and not map.visible and _menu == null and not preload("res://scripts/ui.gd").saisie_active():
		open_menu()
	if get_tree().paused or car == null:
		return
	if _status_t > 0.0:
		_status_t -= dt
		if _status_t <= 0.0 and mode == "":
			_set_status("")
	if mode == "" and not map.pick_mode:
		_epreuve_proche()
	_balises_t -= dt
	if _balises_t <= 0.0:
		_balises_t = 1.0
		_balises_epreuves()
	match mode:
		"course":
			_course_process(dt)
		"chasse":
			_hunt_process(dt)
		"taxi":
			_taxi_process(dt)

func _physics_process(dt: float) -> void:
	if get_tree().paused or car == null or mode != "taxi" or _phase != "course":
		return
	# choc : variation brutale de vitesse (collision), une fois par seconde au plus
	_shock_cd -= dt
	var v := car.linear_velocity
	if _shock_cd <= 0.0 and (v - _prev_v).length() > 5.5 and not car.carried:
		_shocks += 1
		_shock_cd = 1.0
		hud.toast("Aïe ! Le client n'apprécie pas", 1.5)
	_prev_v = v
