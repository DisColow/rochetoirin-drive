## Mises à jour sans réinstaller l'APK : quelques secondes après le lancement, lit le catalogue publié par GitHub
## Actions (branche « maj » du dépôt) ; s'il existe une mise à jour plus récente pour cet APK (même « base »), la
## télécharge en arrière-plan (paquet .pck des seuls fichiers modifiés), vérifie son empreinte SHA-256, et la prépare
## pour le prochain lancement (scripts/boot.gd). Hors ligne ou en cas d'erreur : rien ne change, on réessaie au
## lancement suivant. Après 40 s de jeu sans plantage, la mise à jour en cours est validée.
extends Node

const DIR := "user://maj/"
const CATALOGUE := "https://raw.githubusercontent.com/DisColow/rochetoirin-drive/maj/catalogue.json"

var _http: HTTPRequest
var _cible := {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.has_feature("editor") or OS.get_cmdline_user_args().size() > 0 or OS.get_name() != "Android":
		return                      # essais, éditeur, PC : pas de mise à jour incrémentale (paquets Android)
	get_tree().create_timer(40.0).timeout.connect(_valide)
	get_tree().create_timer(6.0).timeout.connect(_verifie)

func _valide() -> void:
	var etat := ConfigFile.new()
	etat.load(DIR + "etat.cfg")
	etat.set_value("maj", "essais", 0)
	etat.save(DIR + "etat.cfg")

func _verifie() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 20.0
	add_child(_http)
	_http.request_completed.connect(_catalogue)
	_http.request(CATALOGUE + "?t=%d" % Time.get_unix_time_from_system())

func _catalogue(res: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if res != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var cat = JSON.parse_string(body.get_string_from_utf8())
	if typeof(cat) != TYPE_DICTIONARY or not cat.has("bases"):
		return
	var base := str(Engine.get_meta("base_code", ""))
	var e = cat.bases.get(base)
	if typeof(e) != TYPE_DICTIONARY:
		return
	var etat := ConfigFile.new()
	etat.load(DIR + "etat.cfg")
	var actuelle := str(Engine.get_meta("version_jeu", ""))
	if str(e.version) == actuelle or str(e.version) == str(etat.get_value("maj", "rejete", "")):
		return
	if str(e.version) == str(etat.get_value("maj", "version", "")) and FileAccess.file_exists(DIR + str(etat.get_value("maj", "fichier", ""))):
		_annonce(str(e.version), true)
		return
	_cible = e
	_http.request_completed.disconnect(_catalogue)
	_http.request_completed.connect(_recu)
	_http.download_file = DIR + "telechargement.tmp"
	_http.timeout = 0.0
	_http.use_threads = true
	_http.request(str(e.url))

func _recu(res: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
	var tmp := DIR + "telechargement.tmp"
	if res != HTTPRequest.RESULT_SUCCESS or code != 200 or FileAccess.get_sha256(tmp) != str(_cible.sha256):
		DirAccess.remove_absolute(tmp)
		return
	var nom := "maj-%s.pck" % str(_cible.version)
	DirAccess.rename_absolute(tmp, DIR + nom)
	var etat := ConfigFile.new()
	etat.load(DIR + "etat.cfg")
	etat.set_value("maj", "fichier", nom)
	etat.set_value("maj", "version", str(_cible.version))
	etat.set_value("maj", "base", str(Engine.get_meta("base_code", "")))
	etat.set_value("maj", "essais", 0)
	etat.save(DIR + "etat.cfg")
	_annonce(str(_cible.version), false)

func _annonce(v: String, deja: bool) -> void:
	var hud = get_tree().root.get_node_or_null("Main/HUD")
	if hud and hud.has_method("toast"):
		hud.toast("Mise à jour %s %s :\nelle s'appliquera au prochain lancement du jeu." % [v, "prête" if deja else "téléchargée"], 5.0)
