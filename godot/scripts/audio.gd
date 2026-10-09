## Moteur sonore (sons : pipeline/build_sons.py, enregistrements de Joseph Sardin - BigSoundBank et Kenney, CC0).
## Voiture : moteur à boucles par régime (paliers d'un vrai 4 cylindres essence, boîte 5 vitesses simulée, version
## « en charge » ou « frein moteur » selon l'accélérateur), démarreur, roulement selon ce qu'il y a sous chaque roue
## (asphalte, gravier, herbe), vent de la vitesse, crissement des pneus, chocs selon l'objet heurté, retombées.
## Monde : fonds sonores dosés d'après la carte des ambiances (world/ambiance.bin : bâti, bois, eau, autoroute) et
## l'heure ; ruisseaux là où l'eau coule ; merles, rouge-gorge, corneilles le jour, rossignol et chouette la nuit ;
## meuglements près des troupeaux ; chiens dans les villages ; cloches des églises qui sonnent l'heure réelle.
## Mixage, comme dans les grands jeux de conduite : la vitesse couvre peu à peu l'ambiance ; vue extérieure = fenêtre
## ouverte (voiture et monde à plein) ; vue conducteur = dehors étouffé (passe-bas), moteur assourdi.
## Les sources trop faibles sont mises en pause (décodage économisé sur le téléphone).
extends Node

var car: VehicleBody3D
var cam_rig: Node
var main: Node

const GEARS := [3.42, 1.95, 1.3, 0.97, 0.78]     # boîte 5 vitesses (Espace I 2,0 l)
const FINAL := 3.89
const WHEEL_R := 0.31
const IDLE := 850.0
const REDLINE := 5800.0
const SFX := "res://assets/sfx/%s.ogg"

var rpm := IDLE
var gear := 0
var surface := ""                # surface dominante sous les roues (pour les essais)
var _shift_t := 0.0
var _load := 0.0
var _start_t := 0.0
var _loops := []                 # [{f0, on, off}] triées par fréquence
var _roll := {}                  # surface -> AudioStreamPlayer
var _wind: AudioStreamPlayer
var _squeal: AudioStreamPlayer
var _beds := {}                  # nom -> [AudioStreamPlayer, volume courant]
var _streams := []               # 2 sources 3D de ruisseau
var _pool := []                  # sources 3D pour les sons ponctuels
var _pool_i := 0
var _bus_car := -1
var _bus_world := -1
var _lp_world: AudioEffectLowPassFilter
var _lp_car: AudioEffectLowPassFilter
var _amb: PackedByteArray
var _meta := {}
var _eau_cells := {}             # Vector2i (cases de 64 m) -> [indices de points de ruisseau]
var _prev_v := Vector3.ZERO
var _air_t := 0.0
var _hit_cd := 0.0
var _t := 0.0
var _amb_t := 0.0
var _bird_t := 3.0
var _cow_t := 6.0
var _dog_t := 20.0
var _bell_last := ""
var _bell_left := 0
var _bell_t := 0.0
var _bell_pos := Vector3.ZERO
var _cockpit := 0.0              # 0 vue extérieure, 1 vue conducteur (fondu)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_bus_car = _bus("Voiture")
	_bus_world = _bus("Monde")
	_lp_car = AudioServer.get_bus_effect(_bus_car, 0)
	_lp_world = AudioServer.get_bus_effect(_bus_world, 0)
	if not ResourceLoader.exists(SFX % "moteur_ralenti_charge"):
		set_process(false); set_physics_process(false)
		return
	# moteur
	var man = JSON.parse_string(FileAccess.get_file_as_string("res://assets/sfx/moteur.json"))
	for m in man:
		_loops.append({f0 = float(m.f0), on = _player("moteur_%s_charge" % m.nom, _bus_car), off = _player("moteur_%s_lache" % m.nom, _bus_car)})
	_loops.sort_custom(func(a, b): return a.f0 < b.f0)
	for s in ["asphalte", "gravier", "herbe"]:
		_roll[s] = _player("roule_" + s, _bus_car)
	_wind = _player("vent", _bus_car)
	_squeal = _player("crissement", _bus_car)
	# monde
	for b in ["amb_jour", "amb_jour2", "amb_soir", "amb_nuit", "amb_village", "amb_ville", "amb_bois", "amb_autoroute"]:
		_beds[b] = [_player(b, _bus_world), 0.0]
	for n in ["ruisseau", "ruisseau2"]:
		var p := _player3d(n, true)
		p.unit_size = 9.0; p.max_distance = 160.0
		_streams.append(p)
	for i in 8:
		_pool.append(_player3d("", false))
	_load_ambiance()
	if car:
		car.contact_monitor = true
		car.max_contacts_reported = 6
	var st := _player("demarreur", _bus_car, false)
	st.volume_db = -2.0
	st.play()
	st.finished.connect(st.queue_free)
	_start_t = 1.1

## Bus « Voiture » et « Monde » (avec leur filtre passe-bas), créés une seule fois ; appelable avant le moteur sonore.
static func ensure_buses() -> void:
	_bus("Voiture")
	_bus("Monde")

static func _bus(name: String) -> int:
	var i := AudioServer.get_bus_index(name)
	if i < 0:
		AudioServer.add_bus()
		i = AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, name)
		AudioServer.set_bus_send(i, "Master")
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 20000.0
		AudioServer.add_bus_effect(i, lp)
	return i

func _stream(name: String, loop: bool) -> AudioStream:
	if not ResourceLoader.exists(SFX % name):
		return null
	var st: AudioStreamOggVorbis = (load(SFX % name) as AudioStreamOggVorbis).duplicate()
	st.loop = loop
	return st

func _player(name: String, bus: int, loop := true) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = _stream(name, loop)
	p.bus = AudioServer.get_bus_name(bus)
	p.volume_db = -80.0
	add_child(p)
	if loop and p.stream:
		p.play(randf() * 0.5)
		p.stream_paused = true
	return p

func _player3d(name: String, loop: bool) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	if name != "":
		p.stream = _stream(name, loop)
	p.bus = "Monde"
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.unit_size = 14.0
	p.max_distance = 400.0
	p.panning_strength = 0.8
	add_child(p)
	if loop and p.stream:
		p.play(randf() * 5.0)
		p.stream_paused = true
	return p

## Volume linéaire ; en dessous du seuil la source est mise en pause (plus de décodage).
func _vol(p, lin: float) -> void:
	if p == null or p.stream == null:
		return
	if lin < 0.0015:
		if not p.stream_paused:
			p.stream_paused = true
		p.volume_db = -80.0
		return
	if p.stream_paused:
		p.stream_paused = false
	if not p.playing:
		p.play()
	p.volume_db = linear_to_db(lin)

# ---------------------------------------------------------------- voiture
func _physics_process(dt: float) -> void:
	if car == null or not is_instance_valid(car):
		return
	_t += dt
	var v: float = absf(car.forward_speed())
	var kmh := v * 3.6
	var thr: float = car.thr_in
	var brk: float = car.brk_in
	var on: bool = not car.blown and not car.carried
	# boîte automatique simulée : régime d'après la vitesse des roues et le rapport engagé
	var wrpm := v / (TAU * WHEEL_R) * 60.0 * FINAL
	var target := IDLE
	if car.reversing:
		gear = 0
		target = maxf(IDLE, wrpm * 3.6)
	else:
		var r: float = wrpm * GEARS[gear]
		var up := lerpf(2600.0, 5400.0, thr)
		var down := lerpf(1250.0, 2300.0, thr)
		if _shift_t <= 0.0 and gear < GEARS.size() - 1 and r > up:
			gear += 1; _shift_t = 0.28
		elif _shift_t <= 0.0 and gear > 0 and r < down:
			gear -= 1; _shift_t = 0.18
		r = wrpm * GEARS[gear]
		target = maxf(IDLE, r)
		if v < 5.0:
			target = maxf(target, IDLE + 1900.0 * thr)       # embrayage qui patine au démarrage
	target = minf(target, REDLINE)
	_shift_t -= dt
	var shifting := _shift_t > 0.0
	rpm = move_toward(rpm, target, (9000.0 if target > rpm else 5000.0) * dt)
	var pedal := brk if car.reversing else thr            # en marche arrière, c'est FREIN qui fait reculer
	_load = move_toward(_load, 0.0 if shifting else pedal, dt * (6.0 if pedal > _load else 3.0))
	# boucles : les deux qui encadrent la fréquence d'allumage voulue, fondu à puissance constante (en log)
	var f := rpm / 30.0
	var n := _loops.size()
	var gains := []
	gains.resize(n)
	gains.fill(0.0)
	if n > 0:
		if f <= _loops[0].f0:
			gains[0] = 1.0
		elif f >= _loops[n - 1].f0:
			gains[n - 1] = 1.0
		else:
			for i in n - 1:
				if f >= _loops[i].f0 and f < _loops[i + 1].f0:
					var w := log(f / _loops[i].f0) / log(_loops[i + 1].f0 / _loops[i].f0)
					gains[i] = cos(w * PI / 2); gains[i + 1] = sin(w * PI / 2)
	var start := clampf(1.0 - _start_t / 1.1, 0.0, 1.0)
	_start_t -= dt
	var master := (0.55 + 0.45 * clampf((rpm - IDLE) / (REDLINE - IDLE), 0.0, 1.0)) * start * (1.0 if on else 0.0)
	for i in n:
		var L = _loops[i]
		var ps := clampf(f / L.f0, 0.35, 2.6)
		L.on.pitch_scale = ps; L.off.pitch_scale = ps
		_vol(L.on, gains[i] * master * (0.3 + 0.7 * _load))
		_vol(L.off, gains[i] * master * (1.0 - _load) * 0.9)
	# roulement : part des roues sur chaque surface
	var cnt := {"asphalte": 0.0, "gravier": 0.0, "herbe": 0.0}
	var in_air := true
	for w in car.wheels:
		if not w.is_in_contact():
			continue
		in_air = false
		var b = w.get_contact_body()
		var s := "herbe"
		if b and b.has_meta("surface"):
			s = "gravier" if String(b.get_meta("surface")) == "dirt" else "asphalte"
		cnt[s] += 1.0
	var tot: float = maxf(1.0, cnt.asphalte + cnt.gravier + cnt.herbe)
	surface = "" if in_air else ("asphalte" if cnt.asphalte >= maxf(cnt.gravier, cnt.herbe) else ("gravier" if cnt.gravier >= cnt.herbe else "herbe"))
	var rl := pow(clampf(v / 28.0, 0.0, 1.0), 0.8) * (1.0 if on else 0.0)
	for s in _roll:
		var k: float = cnt[s] / tot
		_vol(_roll[s], rl * k * (1.25 if s == "gravier" else 1.0))
		_roll[s].pitch_scale = 0.75 + v / 45.0
	# vent
	_vol(_wind, pow(clampf((v - 4.0) / 40.0, 0.0, 1.0), 1.6) * 0.9 * (1.0 if on else 0.0))
	_wind.pitch_scale = 0.8 + v / 90.0
	# crissement : glissement des roues (skidinfo) ou dérive latérale, freinage appuyé à vitesse sur asphalte
	var skid := 0.0
	for w in car.wheels:
		if w.is_in_contact():
			skid = maxf(skid, 1.0 - w.get_skidinfo())
	var lat: float = absf(car.linear_velocity.dot(car.global_transform.basis.x))
	var sq := maxf(skid * 1.2, (lat - 2.5) / 6.0)
	if brk > 0.8 and not car.reversing and kmh > 35.0:
		sq = maxf(sq, 0.35)
	sq = clampf(sq, 0.0, 1.0) * clampf(v / 8.0, 0.0, 1.0) * (cnt.asphalte / tot)
	_vol(_squeal, sq * 0.8 * (1.0 if on else 0.0))
	_squeal.pitch_scale = 0.92 + 0.16 * sq
	# chocs : brusque variation de vitesse (hors gravité), objet heurté d'après sa famille de nœuds
	_hit_cd -= dt
	var dv: Vector3 = car.linear_velocity - _prev_v
	dv.y += 9.8 * dt
	_prev_v = car.linear_velocity
	if in_air:
		_air_t += dt
	else:
		if _air_t > 0.35 and on:
			_one_shot("choc_sol_%d" % (randi() % 5), car.global_position, clampf(_air_t * 0.8, 0.3, 1.0), 0.9)
		_air_t = 0.0
	if on and _hit_cd <= 0.0 and dv.length() > 2.2 and not car.carried:
		var kind := "sol"
		for b in car.get_colliding_bodies():
			var c := _family(b)
			if c != "":
				kind = c
				break
		if kind != "sol" or dv.length() > 5.0:
			var hard := dv.length()
			var name := ""
			match kind:
				"dur":
					name = ("choc_dur_%d" if hard > 7.0 else ("choc_moyen_%d" if hard > 4.0 else "choc_leger_%d")) % (randi() % 5)
				"bois":
					name = "choc_bois_%d" % (randi() % 5)
				"plastique":
					name = "choc_plastique_%d" % (randi() % 5)
				_:
					name = "choc_sol_%d" % (randi() % 5)
			_one_shot(name, car.global_position, clampf(hard / 9.0, 0.25, 1.0), randf_range(0.9, 1.08))
			_hit_cd = 0.18

## Famille de l'objet heurté : bâtiments, poteaux, voitures garées -> dur ; arbres, clôtures, haies -> bois ;
## poubelles, mobilier -> plastique ; routes et relief -> "".
func _family(b: Object) -> String:
	if b == null or not (b is Node):
		return ""
	if (b as Node).has_meta("surface"):
		return ""
	var path := String((b as Node).get_path()).to_lower()
	for k in ["vegetation", "fences", "haie", "tree", "arbre", "animaux"]:
		if path.contains(k):
			return "bois"
	for k in ["props", "poubelle", "bin"]:
		if path.contains(k):
			return "plastique"
	if path.contains("terrain"):
		return ""
	return "dur"

func _one_shot(name: String, pos: Vector3, gain: float, pitch := 1.0, unit := 14.0, maxd := 400.0) -> void:
	var st := _stream(name, false)
	if st == null:
		return
	var p: AudioStreamPlayer3D = _pool[_pool_i % _pool.size()]
	_pool_i += 1
	p.stream = st
	p.global_position = pos
	p.unit_size = unit
	p.max_distance = maxd
	p.pitch_scale = pitch
	p.volume_db = linear_to_db(maxf(gain, 0.001))
	p.stream_paused = false
	p.play()

# ---------------------------------------------------------------- monde
func _load_ambiance() -> void:
	if not FileAccess.file_exists("res://world/ambiance.json"):
		return
	_meta = JSON.parse_string(FileAccess.get_file_as_string("res://world/ambiance.json"))
	_amb = FileAccess.get_file_as_bytes("res://world/ambiance.bin")
	for i in _meta.eaux.size():
		var e = _meta.eaux[i]
		var c := Vector2i(floori(float(e[0]) / 64.0), floori(float(e[2]) / 64.0))
		if not _eau_cells.has(c):
			_eau_cells[c] = []
		_eau_cells[c].append(i)

## Valeurs de la carte des ambiances (0 à 1) au point (interpolation bilinéaire) : [bâti, bois, eau, autoroute].
func amb_at(x: float, z: float) -> Array:
	if _amb.is_empty():
		return [0.0, 0.3, 0.0, 0.0]
	var cell := float(_meta.cell)
	var fx := (x - float(_meta.x0)) / cell - 0.5
	var fz := (z - float(_meta.z0)) / cell - 0.5
	var nx := int(_meta.nx); var nz := int(_meta.nz)
	var ix := clampi(floori(fx), 0, nx - 2); var iz := clampi(floori(fz), 0, nz - 2)
	var tx := clampf(fx - ix, 0.0, 1.0); var tz := clampf(fz - iz, 0.0, 1.0)
	var out := []
	for ch in 4:
		var a := _amb[(iz * nx + ix) * 4 + ch]; var b := _amb[(iz * nx + ix + 1) * 4 + ch]
		var c := _amb[((iz + 1) * nx + ix) * 4 + ch]; var d := _amb[((iz + 1) * nx + ix + 1) * 4 + ch]
		out.append(lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz) / 255.0)
	return out

func _process(dt: float) -> void:
	if car == null or not is_instance_valid(car):
		return
	var cam := get_viewport().get_camera_3d()
	var cp: Vector3 = cam.global_position if cam else car.global_position
	# vue conducteur : dehors étouffé, moteur assourdi ; vue extérieure : fenêtre ouverte
	var inside := 1.0 if (cam_rig and cam_rig.mode == 1) else 0.0
	_cockpit = move_toward(_cockpit, inside, dt * 3.0)
	if _lp_world:
		_lp_world.cutoff_hz = lerpf(20000.0, 650.0, pow(_cockpit, 0.5))
	if _lp_car:
		_lp_car.cutoff_hz = lerpf(20000.0, 3200.0, _cockpit)
	AudioServer.set_bus_volume_db(_bus_world, lerpf(0.0, -9.0, _cockpit))
	AudioServer.set_bus_volume_db(_bus_car, lerpf(0.0, -2.0, _cockpit))
	_rain_inside(dt)
	_amb_t -= dt
	if _amb_t <= 0.0:
		_amb_t = 0.25
		_update_beds(cp, 0.25)
		_update_streams(cp)
	_spot_sounds(cp, dt)

## Pluie sur le toit (vue conducteur) et essuie-glaces : un cycle enregistré joué à chaque balayage du cockpit.
var _wipe_n := -1
var _rain_roof: AudioStreamPlayer
func _rain_inside(dt: float) -> void:
	var raining: bool = main != null and main.weather == 2
	if _rain_roof == null:
		_rain_roof = _player("pluie_toit", _bus_car)
	_vol(_rain_roof, (0.8 if raining else 0.0) * _cockpit)
	var ck = main.cockpit if main else null
	if ck == null or not ("_wipe" in ck):
		return
	var n := int(floor(ck._wipe))
	if n != _wipe_n:
		if _wipe_n >= 0 and (raining or fposmod(ck._wipe, 1.0) > 0.0):
			var p := _player("essuie_glace", _bus_car, false)
			p.volume_db = linear_to_db(lerpf(0.25, 0.9, _cockpit))
			p.play()
			p.finished.connect(p.queue_free)
		_wipe_n = n


func _update_beds(cp: Vector3, dt: float) -> void:
	var a := amb_at(cp.x, cp.z)
	var bati: float = a[0]; var bois: float = a[1]; var auto: float = a[3]
	var tod: int = main.time_of_day if main else 0
	var wx: int = main.weather if main else 0
	var rain := 1.0 if wx == 2 else 0.0
	var wind: float = main.wind_strength if main else 0.55
	var day := 1.0 if tod <= 1 else 0.0
	var soir := 1.0 if tod == 2 else 0.0
	var nuit := 1.0 if tod == 3 else 0.0
	var camp := clampf(1.0 - bati * 1.8, 0.0, 1.0)
	var village := smoothstep(0.06, 0.3, bati) * (1.0 - smoothstep(0.5, 0.75, bati))
	var ville := smoothstep(0.5, 0.75, bati)
	var birds := 1.0 - 0.75 * rain
	var kmh: float = absf(car.forward_speed()) * 3.6
	var mask := 1.0 - 0.8 * smoothstep(10.0, 110.0, kmh)          # la vitesse couvre l'ambiance
	var want := {
		"amb_jour": day * camp * birds * (1.0 if bois > 0.35 else 0.0),
		"amb_jour2": day * camp * birds * (0.0 if bois > 0.35 else 1.0),
		"amb_soir": soir * camp * birds,
		"amb_nuit": nuit * (1.0 - 0.6 * bati) * (1.0 - 0.6 * rain),
		"amb_village": village * (1.0 if nuit == 0.0 else 0.45),
		"amb_ville": ville * (1.0 if nuit == 0.0 else 0.55),
		"amb_bois": bois * clampf(0.3 + wind, 0.0, 1.2) * 0.8,
		"amb_autoroute": auto,
	}
	for k in _beds:
		var cur: float = move_toward(_beds[k][1], want[k], dt * 0.35)
		_beds[k][1] = cur
		_vol(_beds[k][0], cur * mask)

func _update_streams(cp: Vector3) -> void:
	if _meta.is_empty():
		return
	var c := Vector2i(floori(cp.x / 64.0), floori(cp.z / 64.0))
	var cand := []
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			var k := Vector2i(c.x + dx, c.y + dz)
			if _eau_cells.has(k):
				for i in _eau_cells[k]:
					var e = _meta.eaux[i]
					cand.append([Vector2(float(e[0]) - cp.x, float(e[2]) - cp.z).length(), i])
	cand.sort_custom(func(a, b): return a[0] < b[0])
	var used := []
	for s in _streams.size():
		var p: AudioStreamPlayer3D = _streams[s]
		var pick := -1
		for q in cand:
			var far := true
			for u in used:
				var e1 = _meta.eaux[u]; var e2 = _meta.eaux[q[1]]
				if Vector2(float(e1[0]) - float(e2[0]), float(e1[2]) - float(e2[2])).length() < 60.0:
					far = false
			if far:
				pick = q[1]
				break
		if pick < 0:
			_vol(p, 0.0)
			continue
		used.append(pick)
		var e = _meta.eaux[pick]
		p.global_position = Vector3(float(e[0]), float(e[1]) + 0.5, float(e[2]))
		_vol(p, [0.6, 1.0, 1.4][int(e[3])])

func _spot_sounds(cp: Vector3, dt: float) -> void:
	var a := amb_at(cp.x, cp.z)
	var bati: float = a[0]; var bois: float = a[1]
	var tod: int = main.time_of_day if main else 0
	var rain: bool = main and main.weather == 2
	var kmh: float = absf(car.forward_speed()) * 3.6
	var mask := 1.0 - 0.8 * smoothstep(10.0, 110.0, kmh)
	# oiseaux : merles, rouge-gorge, corneilles le jour ; rossignol et chouette la nuit
	_bird_t -= dt
	if _bird_t <= 0.0:
		var life := clampf(0.25 + bois * 0.8 + (1.0 - bati) * 0.4, 0.15, 1.4)
		_bird_t = randf_range(3.0, 10.0) / life
		if not rain:
			var name := ""
			if tod <= 2:
				var r := randf()
				name = ("merle_%d" % (randi() % 8)) if r < 0.65 else ("rougegorge" if r < 0.85 else "corneille")
			elif randf() < 0.6:
				name = ("rossignol_%d" % (randi() % 3)) if (bois > 0.15 and randf() < 0.7) else "chouette"
			if name != "":
				var ang := randf() * TAU
				var d := randf_range(14.0, 55.0)
				_one_shot(name, cp + Vector3(cos(ang) * d, randf_range(4.0, 11.0), sin(ang) * d), 0.9 * mask, randf_range(0.96, 1.04), 10.0, 220.0)
	# vaches près des troupeaux
	_cow_t -= dt
	if _cow_t <= 0.0:
		_cow_t = randf_range(9.0, 26.0)
		if _meta.has("vaches"):
			var best = null; var bd := 260.0
			for v in _meta.vaches:
				var d := Vector2(float(v[0]) - cp.x, float(v[2]) - cp.z).length()
				if d < bd:
					bd = d; best = v
			if best != null and tod <= 2:
				_one_shot("vache_%d" % (randi() % 5), Vector3(float(best[0]), float(best[1]), float(best[2])) + Vector3(randf_range(-15, 15), 0, randf_range(-15, 15)), 1.0 * mask, randf_range(0.92, 1.05), 18.0, 600.0)
	# chiens dans les villages
	_dog_t -= dt
	if _dog_t <= 0.0:
		_dog_t = randf_range(25.0, 80.0)
		if bati > 0.06 and bati < 0.6:
			var ang := randf() * TAU
			var d := randf_range(30.0, 90.0)
			_one_shot("chien_%d" % (randi() % 3), cp + Vector3(cos(ang) * d, 1.0, sin(ang) * d), 0.8 * mask, randf_range(0.95, 1.05), 14.0, 400.0)
	_bells(cp, dt)

## Cloches : à l'heure réelle, l'église la plus proche (à moins de 1,8 km) sonne le nombre de coups de l'heure ;
## un coup à la demie.
func _bells(cp: Vector3, dt: float) -> void:
	if _bell_left > 0:
		_bell_t -= dt
		if _bell_t <= 0.0:
			_one_shot("cloche", _bell_pos, 1.0, 1.0, 70.0, 2500.0)
			_bell_left -= 1
			_bell_t = 2.3
		return
	var tm := Time.get_time_dict_from_system()
	if tm.minute != 0 and tm.minute != 30:
		return
	var key := "%d:%d" % [tm.hour, tm.minute]
	if key == _bell_last or not _meta.has("eglises"):
		return
	_bell_last = key
	var best = null; var bd := 1800.0
	for e in _meta.eglises:
		var d := Vector2(float(e[0]) - cp.x, float(e[2]) - cp.z).length()
		if d < bd:
			bd = d; best = e
	if best == null:
		return
	_bell_pos = Vector3(float(best[0]), float(best[1]), float(best[2]))
	var h: int = tm.hour % 12
	_bell_left = (12 if h == 0 else h) if tm.minute == 0 else 1
	_bell_t = 0.0

## État pour les essais (journal).
func debug() -> String:
	var b := []
	for k in _beds:
		if _beds[k][1] > 0.02:
			b.append("%s %.2f" % [k.trim_prefix("amb_"), _beds[k][1]])
	return "régime %d tr/min, rapport %d, charge %.2f, surface %s, ambiances [%s]" % [rpm, gear + 1, _load, surface, ", ".join(b)]
