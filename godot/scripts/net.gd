## Multijoueur sur le réseau local, jusqu'à 4 joueurs (v6.44, #139, issue #20 : « multijoueur ad hoc ») : un joueur
## héberge, les autres trouvent la partie toute seule (annonce UDP sur le Wi-Fi ou le point d'accès d'un téléphone)
## ou tapent son adresse. ENet (port 47601) ; annonces UDP (port 47602).
## - chaque joueur envoie l'état de sa voiture 20 fois par seconde ; les voitures des autres sont de vrais Raptor
##   (couleur par joueur, nom au-dessus), interpolées avec 120 ms de retard, et on peut les percuter ;
## - course : l'hôte lance le tracé pour tout le monde (départs décalés), classement à l'arrivée ;
## - taxi : chacun ses clients, classement commun des gains.
extends Node

const PORT := 47601
const ANNONCE := 47602
const MAXI := 4
const COULEURS := [Color(0.015, 0.015, 0.018), Color(0.75, 0.12, 0.08), Color(0.08, 0.28, 0.7), Color(0.85, 0.62, 0.08)]
const RETARD := 0.12

var main: Node
var car: VehicleBody3D
var act: Node                         # activités (course, taxi)
var nom := "Joueur"
var joueurs := {}                     # id -> {nom, idx, taxi, courses}
var autos := {}                       # id -> Node3D (voiture d'un autre joueur)
var parties := {}                     # adresse -> {nom, n, vu}
var _udp: PacketPeerUDP
var _ecoute: PacketPeerUDP
var _t := 0.0
var _ta := 0.0
var _course_res := []                 # [nom, temps]

func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://reglages.cfg") == OK:
		nom = str(cfg.get_value("reseau", "nom", nom))
	multiplayer.peer_connected.connect(_arrivee)
	multiplayer.peer_disconnected.connect(_depart)
	multiplayer.connected_to_server.connect(func(): _toast("Connecté à la partie."); _presenter.rpc(nom))
	multiplayer.connection_failed.connect(func(): _toast("Impossible de rejoindre la partie."); quitter())
	multiplayer.server_disconnected.connect(func(): _toast("L'hôte a quitté la partie."); quitter())
	# essais : -- --net-host (héberge) / --net-join=IP (rejoint) ; état imprimé toutes les 2 s
	for a in OS.get_cmdline_user_args():
		if a == "--net-host":
			get_tree().create_timer(3.0).timeout.connect(func(): heberger())
		elif a.begins_with("--net-join="):
			var ip := a.trim_prefix("--net-join=")
			get_tree().create_timer(6.0).timeout.connect(func(): nom = "Invité"; rejoindre(ip))
	var essai := false
	for a in OS.get_cmdline_user_args():
		essai = essai or a == "--net-host" or a.begins_with("--net-join=")
	if essai:
		var tm := Timer.new(); tm.wait_time = 2.0; tm.autostart = true; add_child(tm)
		tm.timeout.connect(func():
			var l := []
			for id in autos:
				l.append("%s@%s" % [joueurs[id].nom if joueurs.has(id) else str(id), (autos[id] as Node3D).global_position.snapped(Vector3(0.1, 0.1, 0.1))])
			print("  [net] en ligne=%s hôte=%s joueurs=%d autres voitures=%s moi=%s" % [en_ligne(), hote(), joueurs.size(), l, car.global_position.snapped(Vector3(0.1, 0.1, 0.1)) if car else "-"]))

func en_ligne() -> bool:
	return multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer) \
		and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

func hote() -> bool:
	return en_ligne() and multiplayer.is_server()

func _toast(t: String) -> void:
	if main and main.has_node("HUD"):
		main.get_node("HUD").toast(t, 4.0)

func sauver_nom(n: String) -> void:
	nom = n.strip_edges().substr(0, 16) if n.strip_edges() != "" else "Joueur"
	var cfg := ConfigFile.new(); cfg.load("user://reglages.cfg")
	cfg.set_value("reseau", "nom", nom); cfg.save("user://reglages.cfg")

# ================================================================ connexion
func heberger() -> bool:
	quitter()
	var p := ENetMultiplayerPeer.new()
	if p.create_server(PORT, MAXI - 1) != OK:
		_toast("Impossible d'héberger (port %d occupé ?)" % PORT)
		return false
	multiplayer.multiplayer_peer = p
	joueurs = {1: {"nom": nom, "idx": 0, "taxi": 0.0, "courses": 0}}
	_udp = PacketPeerUDP.new()
	_udp.set_broadcast_enabled(true)
	_udp.set_dest_address("255.255.255.255", ANNONCE)
	_toast("Partie créée : les autres joueurs la verront dans « Rejoindre ». Adresse : " + adresse())
	return true

func rejoindre(ip: String) -> void:
	quitter()
	var p := ENetMultiplayerPeer.new()
	if p.create_client(ip.strip_edges(), PORT) != OK:
		_toast("Adresse invalide.")
		return
	multiplayer.multiplayer_peer = p
	_toast("Connexion à %s…" % ip)

func quitter() -> void:
	if multiplayer.multiplayer_peer and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	for id in autos.keys():
		autos[id].queue_free()
	autos.clear()
	joueurs.clear()
	_udp = null

## Adresses IPv4 locales (affichées pour rejoindre à la main).
func adresse() -> String:
	var l := []
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254"):
			l.append(a)
	return ", ".join(l) if not l.is_empty() else "inconnue"

func chercher(actif: bool) -> void:
	if actif and _ecoute == null:
		_ecoute = PacketPeerUDP.new()
		if _ecoute.bind(ANNONCE) != OK:
			_ecoute = null
	elif not actif and _ecoute:
		_ecoute.close(); _ecoute = null
		parties.clear()

func _arrivee(id: int) -> void:
	if multiplayer.is_server():
		var idx := 1
		var pris := []
		for j in joueurs.values():
			pris.append(j.idx)
		while idx in pris:
			idx += 1
		joueurs[id] = {"nom": "…", "idx": idx, "taxi": 0.0, "courses": 0}
		_liste.rpc(joueurs)

func _depart(id: int) -> void:
	if joueurs.has(id):
		_toast("%s a quitté la partie." % joueurs[id].nom)
		joueurs.erase(id)
	if autos.has(id):
		autos[id].queue_free(); autos.erase(id)
	if multiplayer.is_server():
		_liste.rpc(joueurs)

@rpc("any_peer", "reliable")
func _presenter(n: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	if multiplayer.is_server() and joueurs.has(id):
		joueurs[id].nom = n.substr(0, 16)
		_liste.rpc(joueurs)
		_toast("%s a rejoint la partie." % joueurs[id].nom)

@rpc("authority", "call_local", "reliable")
func _liste(l: Dictionary) -> void:
	joueurs = l
	for id in autos.keys():
		if autos[id].has_meta("lbl") and joueurs.has(id):
			autos[id].get_meta("lbl").text = joueurs[id].nom

# ================================================================ état des voitures
@rpc("any_peer", "unreliable_ordered")
func _etat(t: float, p: Vector3, q: Quaternion, v: float, st: float) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not autos.has(id):
		autos[id] = _auto(id)
	var a: Node3D = autos[id]
	var buf: Array = a.get_meta("buf")
	buf.append([t, p, q, v, st])
	if buf.size() > 12:
		buf.pop_front()
	a.set_meta("t_loc", Time.get_ticks_msec() / 1000.0 - t)

func _auto(id: int) -> Node3D:
	var root := Node3D.new()
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/car/meta.json"))
	var body: Node3D = load("res://assets/car/body.glb").instantiate()
	body.rotation.y = PI
	root.add_child(body)
	car._materials(body)
	var idx: int = joueurs[id].idx if joueurs.has(id) else 1
	var col: Color = COULEURS[idx % COULEURS.size()]
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var m = mi.get_surface_override_material(s)
			if m is StandardMaterial3D and m.albedo_color.v < 0.03 and m.clearcoat_enabled:
				var m2: StandardMaterial3D = m.duplicate()
				m2.albedo_color = col
				mi.set_surface_override_material(s, m2)
	# roues (tournent avec la vitesse, braquent à l'avant)
	var roues := []
	var wscene: PackedScene = load("res://assets/car/wheel.glb")
	var wb: float = meta.wheelbase; var tr: float = meta.track; var rm: float = meta.radius
	for i in 4:
		var front := i < 2; var right := i % 2 == 0
		var piv := Node3D.new()
		piv.position = Vector3((-1.0 if right else 1.0) * tr / 2, rm + 0.12 - (0.40 - rm), (1.0 if front else -1.0) * wb / 2)
		var w: Node3D = wscene.instantiate()
		car._materials(w)
		w.rotation.y = 0.0 if right else PI
		w.scale = Vector3(1.1, (0.40 - 0.045) / rm, (0.40 - 0.045) / rm)
		piv.add_child(w)
		root.add_child(piv)
		roues.append([piv, w, front])
	# caisse qu'on peut percuter (déplacée par le réseau)
	var corps := AnimatableBody3D.new()
	corps.sync_to_physics = false
	var cs := CollisionShape3D.new()
	var bx: Array = meta.get("box", [1.76, 1.15, 4.24])
	var box := BoxShape3D.new(); box.size = Vector3(bx[0], bx[1], bx[2])
	cs.shape = box; cs.position = Vector3(0, float(meta.get("box_y", 0.95)), 0)
	corps.add_child(cs)
	root.add_child(corps)
	root.set_meta("corps", corps)
	var lbl := Label3D.new()
	lbl.text = joueurs[id].nom if joueurs.has(id) else "…"
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.fixed_size = true
	lbl.pixel_size = 0.0022
	lbl.font_size = 40; lbl.outline_size = 12
	lbl.modulate = col.lightened(0.45)
	lbl.position = Vector3(0, 2.9, 0)
	root.add_child(lbl)
	root.set_meta("buf", [])
	root.set_meta("roues", roues)
	root.set_meta("lbl", lbl)
	main.add_child(root)
	return root

func _process(dt: float) -> void:
	# annonces de la partie (hôte) et écoute des parties (menu « Rejoindre »)
	_ta -= dt
	if _ta <= 0.0:
		_ta = 1.0
		if _udp and hote():
			_udp.put_packet(("ROCHETOIRIN|%s|%d" % [nom, joueurs.size()]).to_utf8_buffer())
		for k in parties.keys():
			if Time.get_ticks_msec() / 1000.0 - parties[k].vu > 4.0:
				parties.erase(k)
	if _ecoute:
		while _ecoute.get_available_packet_count() > 0:
			var s := _ecoute.get_packet().get_string_from_utf8()
			var ip := _ecoute.get_packet_ip()
			var f := s.split("|")
			if f.size() == 3 and f[0] == "ROCHETOIRIN":
				parties[ip] = {"nom": f[1], "n": int(f[2]), "vu": Time.get_ticks_msec() / 1000.0}
	if not en_ligne():
		return
	# envoi de l'état de ma voiture (20 fois par seconde)
	_t -= dt
	if _t <= 0.0 and car:
		_t = 0.05
		_etat.rpc(Time.get_ticks_msec() / 1000.0, car.global_position, car.global_basis.get_rotation_quaternion(),
			car.linear_velocity.length() * signf(car.forward_speed() + 0.001), car.steer_value)
	# voitures des autres : interpolation entre deux états reçus, RETARD derrière le dernier
	var now := Time.get_ticks_msec() / 1000.0
	for id in autos:
		var a: Node3D = autos[id]
		var buf: Array = a.get_meta("buf")
		if buf.is_empty():
			continue
		var tv: float = now - float(a.get_meta("t_loc", 0.0)) - RETARD
		var e0: Array = buf[0]; var e1: Array = buf[buf.size() - 1]
		for k in range(buf.size() - 1):
			if float(buf[k][0]) <= tv and float(buf[k + 1][0]) >= tv:
				e0 = buf[k]; e1 = buf[k + 1]
				break
		var span := maxf(float(e1[0]) - float(e0[0]), 0.001)
		var u := clampf((tv - float(e0[0])) / span, 0.0, 1.0)
		var p: Vector3 = (e0[1] as Vector3).lerp(e1[1], u)
		var q: Quaternion = (e0[2] as Quaternion).slerp(e1[2], u)
		a.global_transform = Transform3D(Basis(q), p)
		var v: float = lerpf(e0[3], e1[3], u)
		var st: float = lerpf(e0[4], e1[4], u)
		for r in a.get_meta("roues"):
			if r[2]:
				r[0].rotation.y = st
			r[1].rotation.x += v * dt / 0.40
		(a.get_meta("corps") as Node3D).global_transform = a.global_transform           # caisse de collision

# ================================================================ course ensemble
## L'hôte lance son tracé pour tout le monde : chacun part décalé derrière les autres (selon son rang de joueur).
func lancer_course(route: Array) -> void:
	if hote():
		_course_res = []
		_course.rpc(route)

@rpc("authority", "reliable")
func _course(route: Array) -> void:
	if act:
		act.course_reseau(route, rang())

func rang() -> int:
	var id := multiplayer.get_unique_id()
	return int(joueurs[id].idx) if joueurs.has(id) else 0

func arrivee_course(t: float) -> void:
	if en_ligne():
		_arrive.rpc(nom, t)

@rpc("any_peer", "call_local", "reliable")
func _arrive(n: String, t: float) -> void:
	_course_res.append([n, t])
	_course_res.sort_custom(func(a, b): return a[1] < b[1])
	var l := []
	for k in _course_res.size():
		l.append("%d. %s %s" % [k + 1, _course_res[k][0], act._fmt(_course_res[k][1]) if act else str(t)])
	_toast("Classement : " + "   ".join(l))

# ================================================================ taxi ensemble : classement des gains
func gains_taxi(total: float, courses: int) -> void:
	if en_ligne():
		_gains.rpc(total, courses)

@rpc("any_peer", "call_local", "reliable")
func _gains(total: float, courses: int) -> void:
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = multiplayer.get_unique_id()
	if joueurs.has(id):
		joueurs[id].taxi = total; joueurs[id].courses = courses
	var l := joueurs.values().duplicate()
	l.sort_custom(func(a, b): return float(a.taxi) > float(b.taxi))
	var s := []
	for j in l:
		s.append("%s %d €" % [j.nom, int(j.taxi)])
	_toast("Taxi : " + "   ".join(s))
