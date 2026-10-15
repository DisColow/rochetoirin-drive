## Station d'information de l'autoradio (issue #56), sans API payante :
##   - journal : le dernier « Flash info » de 20 Minutes (2 min, podcast public en MP3, plusieurs par jour), sinon le
##     journal de RTL (3 min) ; téléchargé dans user://journal.mp3 quand un nouvel épisode paraît (Godot ne lit pas
##     l'AAC des podcasts de Radio France) ;
##   - flash : les derniers titres de France Info et du Dauphiné (Nord-Isère, via Google Actualités), lus par la voix
##     du téléphone (voix_tel.gd), sans le sport.
## radio.gd enchaîne : journal ou flash, deux chansons, flash, deux chansons…
extends Node
const VoixTel := preload("res://scripts/voix_tel.gd")

const JOURNAL_RSS := ["https://feeds.acast.com/public/shows/69e234ef289eeb2c7b2b4918",
	"https://feeds.audiomeans.fr/feed/81fdd41c-51e9-4839-b867-7ad5bfe61dea.xml"]
const TITRES_RSS := ["https://www.franceinfo.fr/titres.rss",
	"https://news.google.com/rss/search?q=site:ledauphine.com+Nord-Is%C3%A8re&hl=fr&gl=FR&ceid=FR:fr"]
const JOURNAL := "user://journal.mp3"
const JOURNAL_INFO := "user://journal.cfg"
const SPORT := "(?i)\\b(foot|football|rugby|basket|handball|tennis|cyclis|vélo|tour de france|ligue 1|ligue 2|top 14|match|championnat|coupe du monde|jeux olympiques|olympique|athlét|biathlon|formule 1|PSG|OL\\b|OM\\b|FCG|CSBJ|buteur|entraîneur|sélectionneur)"

var titres: Array[String] = []
var journal: AudioStream            # null tant que le journal du jour n'est pas là
var journal_titre := ""
var _flux := 0                      # flux du journal essayé (20 Minutes, puis RTL)
var _lus := 0                        # titres déjà lus (on avance dans la liste à chaque flash)
var _sport := RegEx.new()

func _ready() -> void:
	_sport.compile(SPORT)
	_charger_journal()
	_rafraichir()
	var t := Timer.new(); t.wait_time = 1800.0; t.autostart = true
	t.timeout.connect(_rafraichir)
	add_child(t)

func _rafraichir() -> void:
	titres.clear()
	for u in TITRES_RSS:
		_telecharger(u, _lire_titres)
	_flux = 0
	_telecharger(JOURNAL_RSS[0], _lire_flux_journal)

## Téléchargement (HTTPRequest jetable) ; rappel(corps) si la réponse est bonne.
func _telecharger(url: String, rappel: Callable, fichier := "") -> void:
	var h := HTTPRequest.new()
	h.timeout = 120.0
	if fichier != "":
		h.download_file = fichier
	var px := OS.get_environment("HTTPS_PROXY").trim_prefix("http://").trim_suffix("/").split(":")
	if px.size() == 2:                   # PC derrière un proxy (variable d'environnement)
		h.set_https_proxy(px[0], int(px[1])); h.set_http_proxy(px[0], int(px[1]))
	add_child(h)
	h.request_completed.connect(func(res: int, code: int, _hd: PackedStringArray, corps: PackedByteArray):
		h.queue_free()
		if res == HTTPRequest.RESULT_SUCCESS and code == 200:
			rappel.call(corps))
	if h.request(url) != OK:
		h.queue_free()

## Les <item><title> d'un flux RSS.
static func items(corps: PackedByteArray, champ := "title") -> Array[String]:
	var out: Array[String] = []
	var p := XMLParser.new()
	if p.open_buffer(corps) != OK:
		return out
	var dans_item := false
	var lire := false
	while p.read() == OK:
		match p.get_node_type():
			XMLParser.NODE_ELEMENT:
				if p.get_node_name() == "item":
					dans_item = true
				lire = dans_item and p.get_node_name() == champ
			XMLParser.NODE_ELEMENT_END:
				if p.get_node_name() == "item":
					dans_item = false
				lire = false
			XMLParser.NODE_TEXT, XMLParser.NODE_CDATA:
				# le contenu d'un bloc CDATA se lit par get_node_name()
				var txt := (p.get_node_name() if p.get_node_type() == XMLParser.NODE_CDATA else p.get_node_data()).strip_edges()
				if lire and txt != "":
					out.append(txt)
					lire = false
	return out

func _lire_titres(corps: PackedByteArray) -> void:
	for t in items(corps).slice(0, 8):
		t = t.replace(" - Le Dauphiné Libéré", "").replace(" - ledauphine.com", "")
		if _sport.search(t) == null and not titres.has(t):
			titres.append(t)

## Premier épisode du flux : téléchargé s'il est plus récent que celui qu'on a (MP3 seulement, sinon flux suivant).
func _lire_flux_journal(corps: PackedByteArray) -> void:
	var s := corps.get_string_from_utf8()
	var i := s.find("<item>")
	var re := RegEx.new()
	re.compile("<enclosure[^>]*url=\"([^\"]+)\"[^>]*>")
	var m := re.search(s.substr(i, s.find("</item>", i) - i)) if i >= 0 else null
	if m == null or not ("audio/mpeg" in m.get_string(0) or ".mp3" in m.get_string(1)):
		_flux += 1
		if _flux < JOURNAL_RSS.size():
			_telecharger(JOURNAL_RSS[_flux], _lire_flux_journal)
		return
	var url := m.get_string(1)
	var titre: String = items(corps)[0] if not items(corps).is_empty() else "Journal"
	var c := ConfigFile.new()
	c.load(JOURNAL_INFO)
	if c.get_value("journal", "url", "") == url and FileAccess.file_exists(JOURNAL):
		return
	_telecharger(url, func(_b):
		var c2 := ConfigFile.new()
		c2.set_value("journal", "url", url)
		c2.set_value("journal", "titre", titre)
		c2.save(JOURNAL_INFO)
		_charger_journal(), JOURNAL)

func _charger_journal() -> void:
	if not FileAccess.file_exists(JOURNAL):
		return
	var c := ConfigFile.new()
	c.load(JOURNAL_INFO)
	var mp3 := AudioStreamMP3.new()
	mp3.data = FileAccess.get_file_as_bytes(JOURNAL)
	if mp3.get_length() > 30.0:
		journal = mp3
		journal_titre = str(c.get_value("journal", "titre", "Journal"))

## Texte du flash : trois titres pas encore lus, ou "" s'il n'y a rien.
func flash() -> String:
	if titres.is_empty():
		return ""
	var l: Array[String] = []
	for k in 3:
		l.append(titres[(_lus + k) % titres.size()])
	_lus += 3
	return "Flash info. " + ". ".join(l) + "."

## Lit le flash avec la voix du téléphone ; durée estimée (s), 0 si aucune voix.
func lire_flash(t: String, volume: float) -> float:
	if t == "" or not VoixTel.dispo():
		return 0.0
	var v := VoixTel.choisir("f", 105)
	if v.is_empty():
		return 0.0
	VoixTel.dire(t, v, volume, true)
	return VoixTel.duree(t, float(v.debit))
