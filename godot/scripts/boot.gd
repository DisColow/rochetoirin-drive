## Démarrage : écran d'accueil qui vérifie s'il existe une mise à jour (catalogue publié par GitHub Actions, branche
## « maj »), la télécharge en montrant sa progression (paquet .pck des seuls fichiers modifiés depuis l'APK installé,
## empreinte SHA-256 vérifiée), la charge puis lance le jeu : la mise à jour s'applique tout de suite. Hors ligne,
## catalogue lent ou erreur : on joue avec ce qu'on a. Un bouton permet de jouer sans attendre la fin du téléchargement.
## Ce script ne fait jamais partie d'une mise à jour : il doit rester simple et sûr. Sécurité : si le jeu s'est arrêté
## deux fois de suite sans tenir 40 s après une mise à jour (scripts/maj.gd), elle est mise de côté et on repart de
## l'APK installé.
extends Control

const DIR := "user://maj/"
const CATALOGUE := "https://raw.githubusercontent.com/DisColow/rochetoirin-drive/maj/catalogue.json"

var base := ""
var etat := ConfigFile.new()
var _http: HTTPRequest
var _cible := {}
var _parti := false
var _info: Label
var _barre: ProgressBar
var _passer: Button

func _ready() -> void:
	if FileAccess.file_exists("res://data/base.json"):
		var j = JSON.parse_string(FileAccess.get_file_as_string("res://data/base.json"))
		if typeof(j) == TYPE_DICTIONARY:
			base = str(j.get("code", ""))
	DirAccess.make_dir_recursive_absolute(DIR)
	etat.load(DIR + "etat.cfg")
	if OS.has_environment("MAJ_ESSAI_BASE"):   # essai sur PC : se faire passer pour un APK de cette base
		base = OS.get_environment("MAJ_ESSAI_BASE")
	elif OS.has_feature("editor") or OS.get_cmdline_user_args().size() > 0 or OS.get_name() != "Android":
		_lancer.call_deferred()     # essais, éditeur, PC : pas de mise à jour incrémentale (paquets Android)
		return
	_ecran()
	_http = HTTPRequest.new()
	_http.timeout = 6.0
	add_child(_http)
	_http.request_completed.connect(_catalogue)
	if _http.request(CATALOGUE + "?t=%d" % Time.get_unix_time_from_system()) != OK:
		_lancer()

func _ecran() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size
	get_viewport().size_changed.connect(func(): size = get_viewport_rect().size)
	var fond := ColorRect.new()
	fond.color = Color(0.06, 0.07, 0.09)
	fond.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(fond)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(760, 0)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 22)
	centre.add_child(v)
	var t := Label.new()
	t.text = "Rochetoirin Simulator"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 56)
	v.add_child(t)
	_info = Label.new()
	_info.text = "Recherche de mise à jour…"
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.add_theme_font_size_override("font_size", 28)
	_info.modulate = Color(1, 1, 1, 0.8)
	v.add_child(_info)
	_barre = ProgressBar.new()
	_barre.custom_minimum_size = Vector2(760, 30)
	_barre.max_value = 1.0
	_barre.show_percentage = false
	_barre.visible = false
	v.add_child(_barre)
	_passer = Button.new()
	_passer.text = "Jouer sans attendre"
	_passer.custom_minimum_size = Vector2(0, 70)
	_passer.add_theme_font_size_override("font_size", 28)
	_passer.visible = false
	_passer.pressed.connect(_lancer)
	v.add_child(_passer)

func _catalogue(res: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if _parti:
		return
	var cat = JSON.parse_string(body.get_string_from_utf8()) if res == HTTPRequest.RESULT_SUCCESS and code == 200 else null
	if typeof(cat) != TYPE_DICTIONARY or typeof(cat.get("bases")) != TYPE_DICTIONARY:
		_lancer()
		return
	var e = cat.bases.get(base)
	if typeof(e) != TYPE_DICTIONARY:
		_lancer()
		return
	var v := str(e.version)
	var a_jour := v == str(etat.get_value("maj", "version", "")) and str(etat.get_value("maj", "base", "")) == base \
			and FileAccess.file_exists(DIR + str(etat.get_value("maj", "fichier", "")))
	if a_jour or v == str(ProjectSettings.get_setting("application/config/version", "")) \
			or v == str(etat.get_value("maj", "rejete", "")):
		_lancer()
		return
	_cible = e
	_info.text = "Téléchargement de la version %s…" % v
	_barre.visible = true
	_passer.visible = true
	_http.request_completed.disconnect(_catalogue)
	_http.request_completed.connect(_recu)
	_http.download_file = DIR + "telechargement.tmp"
	_http.timeout = 0.0
	_http.use_threads = true
	if _http.request(str(e.url)) != OK:
		_lancer()

func _process(_dt: float) -> void:
	if _cible.is_empty() or _parti:
		return
	var total := maxi(int(_cible.get("taille", 0)), _http.get_body_size())
	if total > 0:
		var fait := _http.get_downloaded_bytes()
		_barre.value = float(fait) / float(total)
		_info.text = "Téléchargement de la version %s… %.1f / %.1f Mo" % [str(_cible.version), fait / 1048576.0, total / 1048576.0]

func _recu(res: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
	if _parti:
		return
	var tmp := DIR + "telechargement.tmp"
	if res != HTTPRequest.RESULT_SUCCESS or code != 200 or FileAccess.get_sha256(tmp) != str(_cible.sha256):
		DirAccess.remove_absolute(tmp)
		_lancer()
		return
	var nom := "maj-%s.pck" % str(_cible.version)
	DirAccess.rename_absolute(tmp, DIR + nom)
	etat.set_value("maj", "fichier", nom)
	etat.set_value("maj", "version", str(_cible.version))
	etat.set_value("maj", "base", base)
	etat.set_value("maj", "essais", 0)
	_info.text = "Version %s installée." % str(_cible.version)
	if OS.has_environment("MAJ_ESSAI_BASE"):
		print("maj essai : ", nom, " vérifié")
		get_viewport().get_texture().get_image().save_png("user://shots/boot.png")
		get_tree().quit()
		return
	_lancer()

func _lancer() -> void:
	if _parti:
		return
	_parti = true
	if _http:
		_http.cancel_request()
		DirAccess.remove_absolute(DIR + "telechargement.tmp")
	var pck: String = etat.get_value("maj", "fichier", "")
	var ok := pck != "" and str(etat.get_value("maj", "base", "")) == base and FileAccess.file_exists(DIR + pck)
	var essais := int(etat.get_value("maj", "essais", 0))
	if ok and essais >= 2:
		ok = false
		etat.set_value("maj", "fichier", "")
		etat.set_value("maj", "rejete", etat.get_value("maj", "version", ""))
		DirAccess.remove_absolute(DIR + pck)
	if ok and ProjectSettings.load_resource_pack(DIR + pck, true):
		etat.set_value("maj", "essais", essais + 1)
		Engine.set_meta("version_jeu", str(etat.get_value("maj", "version", "")))
	else:
		Engine.set_meta("version_jeu", str(ProjectSettings.get_setting("application/config/version", "")))
	Engine.set_meta("base_code", base)
	Engine.set_meta("maj_verifiee", true)
	etat.save(DIR + "etat.cfg")
	# anciennes mises à jour
	for f in DirAccess.get_files_at(DIR):
		if f.ends_with(".pck") and f != str(etat.get_value("maj", "fichier", "")):
			DirAccess.remove_absolute(DIR + f)
	var m = load("res://scripts/maj.gd").new()
	m.name = "Maj"
	get_tree().root.add_child.call_deferred(m)
	get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
