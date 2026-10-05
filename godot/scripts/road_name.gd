## Nom de la route sous la voiture (OSM : numéro · nom), commune et coordonnées, pour situer précisément un défaut.
## Données : world/roadnames.json/.bin (points d'axe tous les 4 m rangés par cellule de 64 m) et world/communes.bin.
extends RefCounted

var meta: Dictionary
var starts: PackedInt32Array
var pts: PackedFloat32Array
var communes: PackedByteArray
var current := -1
var speed_limit := 0             # vitesse max OSM de la route actuelle (0 : inconnue)

func _init() -> void:
	meta = JSON.parse_string(FileAccess.get_file_as_string("res://world/roadnames.json"))
	var b := FileAccess.get_file_as_bytes("res://world/roadnames.bin")
	var n := int(meta.nx) * int(meta.nz) + 1
	starts = b.slice(0, n * 4).to_int32_array()
	pts = b.slice(n * 4).to_float32_array()
	communes = FileAccess.get_file_as_bytes("res://world/communes.bin")

func _cell(x: float, z: float) -> Vector2i:
	return Vector2i(floori((x - float(meta.x0)) / float(meta.cell)), floori((z - float(meta.z0)) / float(meta.cell)))

## Nom de la route la plus proche (à moins de 25 m), en gardant la route actuelle aux carrefours si elle est presque aussi proche.
func road_at(p: Vector3) -> String:
	var c := _cell(p.x, p.z)
	var best := -1
	var best_i := -1
	var cur_i := -1
	var bd := 25.0 * 25.0
	var cur_d := 1e18
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var cx := c.x + dx
			var cz := c.y + dz
			if cx < 0 or cz < 0 or cx >= int(meta.nx) or cz >= int(meta.nz):
				continue
			var k := cz * int(meta.nx) + cx
			for i in range(starts[k], starts[k + 1]):
				var ddx := pts[i * 4] - p.x
				var ddz := pts[i * 4 + 1] - p.z
				var d := ddx * ddx + ddz * ddz
				var id := int(pts[i * 4 + 2])
				if id == current and d < cur_d:
					cur_d = d; cur_i = i
				if d < bd:
					bd = d; best = id; best_i = i
	if current >= 0 and cur_d < 36.0 and cur_d <= bd + 30.0:
		best = current; best_i = cur_i
	current = best
	speed_limit = int(pts[best_i * 4 + 3]) if best_i >= 0 else 0
	return meta.names[best] if best >= 0 else "Hors route"

func commune_at(p: Vector3) -> String:
	var c := _cell(p.x, p.z)
	if c.x < 0 or c.y < 0 or c.x >= int(meta.nx) or c.y >= int(meta.nz):
		return ""
	var i := communes[c.y * int(meta.nx) + c.x]
	return meta.communes[i] if i < meta.communes.size() else ""
