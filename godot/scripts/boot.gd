## Démarrage : charge la dernière mise à jour téléchargée (user://maj/, paquet .pck de Godot qui ne contient que les
## fichiers modifiés depuis l'APK installé), puis lance le jeu. Ce script ne fait jamais partie d'une mise à jour : il
## doit rester simple et sûr. Sécurité : si le jeu s'est arrêté deux fois de suite sans tenir 40 s après une mise à
## jour, elle est mise de côté et on repart de l'APK installé.
extends Node

const DIR := "user://maj/"

func _ready() -> void:
	var base := ""
	if FileAccess.file_exists("res://data/base.json"):
		var j = JSON.parse_string(FileAccess.get_file_as_string("res://data/base.json"))
		if typeof(j) == TYPE_DICTIONARY:
			base = str(j.get("code", ""))
	var etat := ConfigFile.new()
	etat.load(DIR + "etat.cfg")
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
	DirAccess.make_dir_recursive_absolute(DIR)
	etat.save(DIR + "etat.cfg")
	# anciennes mises à jour
	for f in DirAccess.get_files_at(DIR):
		if f.ends_with(".pck") and f != str(etat.get_value("maj", "fichier", "")):
			DirAccess.remove_absolute(DIR + f)
	var m = load("res://scripts/maj.gd").new()
	m.name = "Maj"
	get_tree().root.add_child.call_deferred(m)
	get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
