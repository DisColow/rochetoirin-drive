## Chargement des tuiles en arrière-plan (ResourceLoader.load_threaded_request) : le fil principal ne lit plus les
## fichiers lui-même (c'était la principale source d'à-coups en roulant) ; il demande une tuile, puis la pose quand
## elle est prête. Une tuile qui n'est plus voulue avant la fin de sa lecture est récupérée puis jetée (pas de fuite).
extends RefCounted

var _req := {}            # chemin -> vrai : lectures demandées, pas encore récupérées

## La ressource si elle est prête, sinon null (et la lecture est lancée au premier appel).
func pret(path: String) -> Resource:
	if not _req.has(path):
		if ResourceLoader.has_cached(path):
			return load(path)
		if ResourceLoader.load_threaded_request(path, "", true) != OK:
			return load(path)
		_req[path] = true
		return null
	match ResourceLoader.load_threaded_get_status(path):
		ResourceLoader.THREAD_LOAD_LOADED:
			_req.erase(path)
			return ResourceLoader.load_threaded_get(path)
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return null
		_:
			_req.erase(path)
			return load(path)        # échec de la lecture en arrière-plan : lecture directe

## Lectures demandées qui ne sont plus voulues : récupérées dès qu'elles sont finies, puis oubliées.
func menage(voulus: Dictionary) -> void:
	for path in _req.keys():
		if voulus.has(path):
			continue
		var st := ResourceLoader.load_threaded_get_status(path)
		if st != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			if st == ResourceLoader.THREAD_LOAD_LOADED:
				ResourceLoader.load_threaded_get(path)
			_req.erase(path)
