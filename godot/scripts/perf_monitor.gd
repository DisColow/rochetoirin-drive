## Mesure des performances : chaque image est chronométrée ; par tranche de 5 s, on note les images/s moyennes, le
## 1 % des images les plus lentes, la pire image, les à-coups (images de plus de 50 ms), le temps passé par
## chaque système du jeu, la charge de dessin (appels, primitives, objets) et la zone traversée. Toujours actif à faible coût
## (résumé dans le journal toutes les 30 s) ; un relevé de 3 minutes se lance depuis ⚙ et s'envoie en un toucher
## (ticket GitHub pré-rempli ou copie) : il dit où et pourquoi le téléphone rame.
## Le niveau de performances automatique (Réglages) s'appuie aussi sur ces mesures : get_fps_moyen().
extends Node

signal releve_fini(texte: String)

## Temps passé par chaque système du jeu dans son traitement par image (µs), cumulé sur la tranche en cours.
static var _sys := {}

static func note(nom: String, us: int) -> void:
	var e = _sys.get(nom)
	if e == null:
		_sys[nom] = [us, us, 1]
	else:
		e[0] += us
		e[1] = maxi(e[1], us)
		e[2] += 1

var car: Node3D
var names
var _dts := PackedFloat32Array()       # durées des images de la tranche en cours (s)
var _t := 0.0
var _tranches: Array = []              # tranches du relevé en cours
var _releve := false
var _releve_t := 0.0
var _journal_t := 0.0
var _hist := PackedFloat32Array()      # images/s des dernières tranches (niveau automatique)
const TRANCHE := 5.0
const DUREE_RELEVE := 180.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func demarrer_releve() -> void:
	_tranches.clear()
	_releve = true
	_releve_t = 0.0

func en_releve() -> bool:
	return _releve

func reste() -> float:
	return maxf(0.0, DUREE_RELEVE - _releve_t)

## Images/s moyennes des dernières tranches (0 tant qu'on n'a pas mesuré).
func get_fps_moyen(n := 3) -> float:
	if _hist.is_empty():
		return 0.0
	var s := 0.0
	var k := mini(n, _hist.size())
	for i in k:
		s += _hist[_hist.size() - 1 - i]
	return s / k

var _dernier := 0

func _process(delta: float) -> void:
	# durée réelle de l'image (le delta de Godot est plafonné quand le jeu rame : il ne dit pas la vérité)
	var now := Time.get_ticks_usec()
	var dt := (now - _dernier) / 1e6 if _dernier > 0 else delta
	_dernier = now
	if get_tree().paused:
		return
	_dts.append(dt)
	_t += dt
	if _releve:
		_releve_t += dt
	if _t < TRANCHE:
		return
	var tr := _tranche()
	tr["sys"] = _systemes()
	_sys.clear()
	_t = 0.0
	_dts.clear()
	_hist.append(tr.fps)
	if _hist.size() > 24:
		_hist = _hist.slice(_hist.size() - 24)
	_journal_t += TRANCHE
	if _journal_t >= 30.0 or tr.acoups > 0:
		_journal_t = 0.0
		print("[perf] ", _ligne(tr))
	if _releve:
		_tranches.append(tr)
		if _releve_t >= DUREE_RELEVE:
			_releve = false
			releve_fini.emit(rapport())

func _tranche() -> Dictionary:
	var s := _dts.duplicate()
	s.sort()
	var n := s.size()
	var tot := 0.0
	var acoups := 0
	for d in s:
		tot += d
		if d > 0.05:
			acoups += 1
	var p99: float = s[clampi(int(n * 0.99), 0, n - 1)] if n > 0 else 0.0
	var p := car.global_position if car else Vector3.ZERO
	var zone := ""
	if names:
		zone = str(names.road_at(p))
	return {
		"fps": n / maxf(tot, 0.001),
		"bas": 1.0 / maxf(p99, 0.001),                 # images/s du 1 % le plus lent
		"pire": (s[n - 1] if n > 0 else 0.0) * 1000.0,
		"acoups": acoups,
		"appels": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"prims": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0,
		"objets": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"kmh": car.kmh() if car and car.has_method("kmh") else 0.0,
		"pos": "%d,%d" % [p.x, p.z],
		"zone": zone,
	}

## Les 5 systèmes les plus coûteux de la tranche : « nom moy/pire ms ».
func _systemes() -> String:
	var l := []
	for k in _sys:
		var e = _sys[k]
		l.append([k, float(e[0]) / maxi(e[2], 1) / 1000.0, e[1] / 1000.0])
	l.sort_custom(func(a, b): return a[1] + a[2] * 0.2 > b[1] + b[2] * 0.2)
	var out := PackedStringArray()
	for i in mini(5, l.size()):
		out.append("%s %.1f/%.0f" % l[i])
	return ", ".join(out)

func _ligne(t: Dictionary) -> String:
	return "%.0f img/s (1 %% bas %.0f, pire %.0f ms, %d à-coups) · %d appels, %.0fk prim., %d objets · %d km/h · %s (%s)" % [
		t.fps, t.bas, t.pire, t.acoups, t.appels, t.prims, t.objets, t.kmh, t.zone, t.pos] + \
		("\n    systèmes (moy/pire ms) : " + str(t.get("sys", "")) if t.get("sys", "") != "" else "")

## Relevé lisible : synthèse, puis tranche par tranche.
func rapport() -> String:
	var lines := PackedStringArray()
	var fps := 0.0; var bas := 1e9; var ac := 0
	for t in _tranches:
		fps += t.fps; bas = minf(bas, t.bas); ac += t.acoups
	var n := maxi(_tranches.size(), 1)
	lines.append("Relevé de performances v%s · %s · %s · écran %s · rendu %s" % [
		ProjectSettings.get_setting("application/config/version", "?"), OS.get_model_name(),
		RenderingServer.get_video_adapter_name(), str(get_viewport().get_visible_rect().size),
		str(Engine.get_meta("niveau_perf", "?"))])
	lines.append("Moyenne %.0f img/s · pire tranche (1 %% bas) %.0f img/s · %d à-coups en %d s" % [fps / n, bas if bas < 1e8 else 0.0, ac, int(n * TRANCHE)])
	for t in _tranches:
		lines.append(_ligne(t))
	return "\n".join(lines)
