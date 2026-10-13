## Itinéraire du GPS (v6.30, demande de l'utilisateur : taxi guidé sur la carte et la mini-carte). Graphe routier
## world/graphe.bin (pipeline/build_itineraire.py) ; plus court chemin A* (sens uniques respectés, chemins de terre
## pénalisés), calculé sur un fil de travail : calculer(depuis, vers) puis lire `route` quand `pret` passe à vrai.
extends RefCounted

var ok := false
var nx := PackedFloat32Array()          # x, z des nœuds
var nz := PackedFloat32Array()
var adj_debut := PackedInt32Array()     # liste d'adjacence (CSR) : arcs sortants de chaque nœud
var adj := PackedInt32Array()           # (arc << 1) | sens (0 : a -> b, 1 : b -> a)
var arc_a := PackedInt32Array()
var arc_b := PackedInt32Array()
var arc_l := PackedFloat32Array()
var arc_p0 := PackedInt32Array()
var arc_np := PackedInt32Array()
var px := PackedFloat32Array()
var pz := PackedFloat32Array()
var grille := {}                        # case de 100 m -> PackedInt32Array de nœuds
const CASE := 100.0

var route := PackedVector2Array()       # dernier itinéraire calculé (points de l'axe)
var longueur := 0.0
var pret := false
var _tache := -1
var _res := PackedVector2Array()
var _res_l := 0.0

func _init() -> void:
	var f := "res://world/graphe.bin"
	if not FileAccess.file_exists(f):
		return
	var b := FileAccess.get_file_as_bytes(f)
	var o := 0
	var nn := b.decode_s32(o); o += 4
	var xz := b.slice(o, o + nn * 8).to_float32_array(); o += nn * 8
	nx.resize(nn); nz.resize(nn)
	for i in nn:
		nx[i] = xz[i * 2]; nz[i] = xz[i * 2 + 1]
		var k := Vector2i(floori(nx[i] / CASE), floori(nz[i] / CASE))
		if not grille.has(k):
			grille[k] = PackedInt32Array()
		var l: PackedInt32Array = grille[k]
		l.append(i)
		grille[k] = l
	var na := b.decode_s32(o); o += 4
	var raw := b.slice(o, o + na * 24); o += na * 24
	var ints := raw.to_int32_array()
	var flts := raw.to_float32_array()
	arc_a.resize(na); arc_b.resize(na); arc_l.resize(na); arc_p0.resize(na); arc_np.resize(na)
	var deg := PackedInt32Array(); deg.resize(nn + 1)
	var sens_unique := PackedByteArray(); sens_unique.resize(na)
	for k in na:
		arc_a[k] = ints[k * 6]; arc_b[k] = ints[k * 6 + 1]
		var fl := ints[k * 6 + 3]
		arc_l[k] = flts[k * 6 + 2] * (2.5 if fl & 2 else 1.0)       # chemins de terre : à éviter
		arc_p0[k] = ints[k * 6 + 4]; arc_np[k] = ints[k * 6 + 5]
		sens_unique[k] = fl & 1
		deg[arc_a[k] + 1] += 1
		if not (fl & 1):
			deg[arc_b[k] + 1] += 1
	for i in nn:
		deg[i + 1] += deg[i]
	adj_debut = deg.duplicate()
	adj.resize(deg[nn])
	var rempli := deg.duplicate()
	for k in na:
		adj[rempli[arc_a[k]]] = k << 1; rempli[arc_a[k]] += 1
		if not sens_unique[k]:
			adj[rempli[arc_b[k]]] = (k << 1) | 1; rempli[arc_b[k]] += 1
	var np_ := b.decode_s32(o); o += 4
	var pp := b.slice(o, o + np_ * 8).to_float32_array()
	px.resize(np_); pz.resize(np_)
	for i in np_:
		px[i] = pp[i * 2]; pz[i] = pp[i * 2 + 1]
	ok = true

func plus_proche(p: Vector2) -> int:
	var c := Vector2i(floori(p.x / CASE), floori(p.y / CASE))
	var best := -1
	var bd := INF
	for r in 4:
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				for i: int in grille.get(c + Vector2i(dx, dz), PackedInt32Array()):
					var d := Vector2(nx[i] - p.x, nz[i] - p.y).length_squared()
					if d < bd:
						bd = d; best = i
		if best >= 0 and r >= 1:
			break
	return best

## Lance le calcul en arrière-plan ; `pret` passe à vrai quand `route` est à jour.
func calculer(depuis: Vector2, vers: Vector2) -> void:
	if not ok or _tache >= 0:
		return
	pret = false
	_tache = WorkerThreadPool.add_task(_calcul.bind(depuis, vers))

## À appeler régulièrement (fil principal) : récupère le résultat du fil de travail.
func suivre() -> void:
	if _tache >= 0 and WorkerThreadPool.is_task_completed(_tache):
		WorkerThreadPool.wait_for_task_completion(_tache)
		_tache = -1
		route = _res
		longueur = _res_l
		pret = true

func _calcul(depuis: Vector2, vers: Vector2) -> void:
	var s := plus_proche(depuis)
	var t := plus_proche(vers)
	_res = PackedVector2Array()
	_res_l = 0.0
	if s < 0 or t < 0:
		return
	var nn := nx.size()
	var g := PackedFloat32Array(); g.resize(nn); g.fill(INF)
	var par := PackedInt32Array(); par.resize(nn); par.fill(-1)      # (arc << 1) | sens par lequel on arrive
	var ferme := PackedByteArray(); ferme.resize(nn)
	var tas_f := PackedFloat32Array()
	var tas_n := PackedInt32Array()
	var cible := Vector2(nx[t], nz[t])
	g[s] = 0.0
	_pousser(tas_f, tas_n, Vector2(nx[s], nz[s]).distance_to(cible), s)
	var n_vus := 0
	while tas_n.size() > 0:
		var u := _extraire(tas_f, tas_n)
		if ferme[u]:
			continue
		ferme[u] = 1
		n_vus += 1
		if u == t or n_vus > 200000:
			break
		for j in range(adj_debut[u], adj_debut[u + 1]):
			var e := adj[j]
			var k := e >> 1
			var v := arc_b[k] if (e & 1) == 0 else arc_a[k]
			if ferme[v]:
				continue
			var ng := g[u] + arc_l[k]
			if ng < g[v]:
				g[v] = ng
				par[v] = e
				_pousser(tas_f, tas_n, ng + Vector2(nx[v], nz[v]).distance_to(cible), v)
	if par[t] < 0 and s != t:
		return
	# remontée : points de chaque arc dans le sens du trajet
	var morceaux := []
	var u := t
	while u != s:
		var e := par[u]
		var k := e >> 1
		var seg := PackedVector2Array()
		for i in arc_np[k]:
			seg.append(Vector2(px[arc_p0[k] + i], pz[arc_p0[k] + i]))
		if (e & 1) == 1:
			seg.reverse()
		morceaux.append(seg)
		u = arc_a[k] if (e & 1) == 0 else arc_b[k]
	morceaux.reverse()
	var out := PackedVector2Array([depuis])
	for seg: PackedVector2Array in morceaux:
		out.append_array(seg)
	out.append(vers)
	_res = out
	_res_l = g[t]

static func _pousser(f: PackedFloat32Array, n: PackedInt32Array, cle: float, v: int) -> void:
	f.append(cle); n.append(v)
	var i := f.size() - 1
	while i > 0:
		var p := (i - 1) >> 1
		if f[p] <= f[i]:
			break
		var tf := f[p]; f[p] = f[i]; f[i] = tf
		var tn := n[p]; n[p] = n[i]; n[i] = tn
		i = p

static func _extraire(f: PackedFloat32Array, n: PackedInt32Array) -> int:
	var v := n[0]
	var last := f.size() - 1
	f[0] = f[last]; n[0] = n[last]
	f.resize(last); n.resize(last)
	var i := 0
	while true:
		var l := i * 2 + 1
		if l >= last:
			break
		var r := l + 1
		var m := l if r >= last or f[l] <= f[r] else r
		if f[i] <= f[m]:
			break
		var tf := f[m]; f[m] = f[i]; f[i] = tf
		var tn := n[m]; n[m] = n[i]; n[i] = tn
		i = m
	return v

## Distance du point à l'itinéraire (m) : sortie de route -> nouveau calcul.
func ecart(p: Vector2) -> float:
	var bd := INF
	for i in range(0, route.size() - 1):
		var a := route[i]; var b := route[i + 1]
		var ab := b - a
		var tt := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
		bd = minf(bd, p.distance_to(a + ab * tt))
	return bd
