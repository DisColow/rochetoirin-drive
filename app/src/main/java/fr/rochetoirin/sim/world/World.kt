package fr.rochetoirin.sim.world

import org.json.JSONObject
import java.io.InputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/**
 * Grille d'altitude. Repère : x = Est, y = altitude, z = Sud.
 * La triangulation (diagonale v00-v11) est la même que celle du rendu et de l'outil de préparation.
 */
class HeightGrid(val nx: Int, val nz: Int, val x0: Float, val z0: Float, val step: Float, val h: FloatArray) {
    val x1 get() = x0 + (nx - 1) * step
    val z1 get() = z0 + (nz - 1) * step

    fun at(i: Int, j: Int) = h[j * nx + i]

    fun height(x: Float, z: Float): Float {
        val gx = ((x - x0) / step).coerceIn(0f, nx - 1.0001f)
        val gz = ((z - z0) / step).coerceIn(0f, nz - 1.0001f)
        val i = gx.toInt(); val j = gz.toInt()
        val fx = gx - i; val fz = gz - j
        val h00 = h[j * nx + i]; val h10 = h[j * nx + i + 1]
        val h01 = h[(j + 1) * nx + i]; val h11 = h[(j + 1) * nx + i + 1]
        return if (fz >= fx) h00 + (h11 - h01) * fx + (h01 - h00) * fz
        else h00 + (h10 - h00) * fx + (h11 - h10) * fz
    }

    companion object {
        fun load(open: (String) -> InputStream, name: String): HeightGrid {
            val bytes = open(name).use { it.readBytes() }
            val bb = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
            bb.position(4)
            val nx = bb.int; val nz = bb.int
            val x0 = bb.float; val z0 = bb.float; val step = bb.float
            val h = FloatArray(nx * nz)
            bb.asFloatBuffer().get(h)
            return HeightGrid(nx, nz, x0, z0, step, h)
        }
    }
}

/** Tuile de routes pré-calculée (sommets : pos3, normale3, lat, abscisse, demi-largeur, style). */
class RoadChunk(val cx: Int, val cz: Int, val vertices: FloatArray, val indices: IntArray)

class Way(
    val style: Int, val kind: String, val oneway: Boolean, val name: String,
    val speed: Int, val width: Float, val bridge: Boolean, val nodes: IntArray,
) {
    val drivable get() = true
}

class Poi(val name: String, val kind: String, val node: Int, val x: Float, val z: Float)

class Bridge(val hw: Float, val pts: FloatArray) // x,y,z répétés

/** Résultat d'une recherche de la route la plus proche. */
class RoadHit {
    var way: Way? = null
    var wayIndex = -1
    var seg = 0
    var dist = Float.MAX_VALUE
    var dirX = 0f
    var dirZ = 0f
}

/** [open] ouvre un fichier de données (assets Android, ou fichiers locaux pour les tests). */
internal fun readRoadChunks(open: (String) -> InputStream, name: String): List<RoadChunk> {
    val bytes = open(name).use { it.readBytes() }
    val bb = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
    bb.position(4)
    bb.float; bb.float; bb.float; bb.int; bb.int
    val n = bb.int
    val list = ArrayList<RoadChunk>(n)
    repeat(n) {
        val cx = bb.int; val cz = bb.int; val nv = bb.int; val ni = bb.int
        val v = FloatArray(nv * 10)
        bb.asFloatBuffer().get(v); bb.position(bb.position() + nv * 40)
        val idx = IntArray(ni)
        bb.asIntBuffer().get(idx); bb.position(bb.position() + ni * 4)
        list.add(RoadChunk(cx, cz, v, idx))
    }
    return list
}

class World(open: (String) -> InputStream) {
    val terrain = HeightGrid.load(open, "terrain.bin")
    val far = HeightGrid.load(open, "far.bin")
    val roadChunks: List<RoadChunk>
    /** Passages piétons, lignes de stop, plateaux ralentisseurs (même format que les routes). */
    val decalChunks: List<RoadChunk>
    val chunkSize: Float
    val nodeX: FloatArray
    val nodeZ: FloatArray
    val ways: List<Way>
    val bridges: List<Bridge>
    val pois: List<Poi>
    val start: Poi
    val minX: Float; val minZ: Float; val maxX: Float; val maxZ: Float

    // index spatial des segments de route : cellules de 40 m
    private val cell = 40f
    private val gridW: Int
    private val gridH: Int
    private val segIndex: Array<IntArray>

    init {
        // --- routes et marquages ponctuels ---
        roadChunks = readRoadChunks(open, "roads.bin")
        decalChunks = try { readRoadChunks(open, "decals.bin") } catch (e: Exception) { emptyList() }
        chunkSize = 320f

        // --- graphe, ponts, lieux ---
        val json = JSONObject(open("map.json").use { String(it.readBytes(), Charsets.UTF_8) })
        val jn = json.getJSONArray("nodes")
        nodeX = FloatArray(jn.length()); nodeZ = FloatArray(jn.length())
        for (i in 0 until jn.length()) {
            val p = jn.getJSONArray(i)
            nodeX[i] = p.getDouble(0).toFloat(); nodeZ[i] = p.getDouble(1).toFloat()
        }
        val jw = json.getJSONArray("ways")
        ways = List(jw.length()) { i ->
            val o = jw.getJSONObject(i)
            val nd = o.getJSONArray("nd")
            Way(
                o.getInt("c"), o.getString("k"), o.getInt("o") == 1, o.getString("n"), o.getInt("s"),
                o.getDouble("w").toFloat(), o.getInt("b") == 1, IntArray(nd.length()) { nd.getInt(it) },
            )
        }
        val jb = json.getJSONArray("bridges")
        bridges = List(jb.length()) { i ->
            val o = jb.getJSONObject(i)
            val p = o.getJSONArray("p")
            val pts = FloatArray(p.length() * 3)
            for (k in 0 until p.length()) {
                val q = p.getJSONArray(k)
                pts[k * 3] = q.getDouble(0).toFloat(); pts[k * 3 + 1] = q.getDouble(1).toFloat(); pts[k * 3 + 2] = q.getDouble(2).toFloat()
            }
            Bridge(o.getDouble("hw").toFloat(), pts)
        }
        fun poi(o: JSONObject) = Poi(o.getString("name"), o.getString("kind"), o.getInt("node"),
            o.getDouble("x").toFloat(), o.getDouble("z").toFloat())
        val jp = json.getJSONArray("pois")
        pois = List(jp.length()) { poi(jp.getJSONObject(it)) }
        start = poi(json.getJSONObject("start"))
        val b = json.getJSONArray("bounds")
        minX = b.getDouble(0).toFloat(); minZ = b.getDouble(1).toFloat()
        maxX = b.getDouble(2).toFloat(); maxZ = b.getDouble(3).toFloat()

        // --- index spatial ---
        gridW = ((maxX - minX) / cell).toInt() + 1
        gridH = ((maxZ - minZ) / cell).toInt() + 1
        val tmp = Array(gridW * gridH) { ArrayList<Int>() }
        for ((wi, w) in ways.withIndex()) {
            for (s in 0 until w.nodes.size - 1) {
                val a = w.nodes[s]; val c = w.nodes[s + 1]
                val ax = nodeX[a]; val az = nodeZ[a]; val bx = nodeX[c]; val bz = nodeZ[c]
                val len = hypot(bx - ax, bz - az)
                val steps = max(1, (len / (cell * 0.5f)).toInt())
                var last = -1
                for (k in 0..steps) {
                    val t = k.toFloat() / steps
                    val id = cellId(ax + (bx - ax) * t, az + (bz - az) * t)
                    if (id >= 0 && id != last) {
                        val key = (wi shl 12) or s
                        // ajouté aussi dans les cellules voisines pour couvrir la largeur
                        for (dj in -1..1) for (di in -1..1) {
                            val cx = id % gridW + di; val cz = id / gridW + dj
                            if (cx in 0 until gridW && cz in 0 until gridH) {
                                val l = tmp[cz * gridW + cx]
                                if (l.isEmpty() || l[l.size - 1] != key) l.add(key)
                            }
                        }
                        last = id
                    }
                }
            }
        }
        segIndex = Array(tmp.size) { tmp[it].distinct().toIntArray() }
    }

    /** Décor (bâtiments, arbres, panorama) et obstacles. */
    val decor = Decor(open, this)

    private fun cellId(x: Float, z: Float): Int {
        val cx = floor((x - minX) / cell).toInt(); val cz = floor((z - minZ) / cell).toInt()
        if (cx < 0 || cz < 0 || cx >= gridW || cz >= gridH) return -1
        return cz * gridW + cx
    }

    /** Segment de route le plus proche (dans un rayon d'environ 40 m). */
    fun nearestRoad(x: Float, z: Float, out: RoadHit, filter: ((Way) -> Boolean)? = null): RoadHit {
        out.way = null; out.dist = Float.MAX_VALUE; out.wayIndex = -1
        val id = cellId(x, z)
        if (id < 0) return out
        for (key in segIndex[id]) {
            val wi = key ushr 12; val s = key and 0xFFF
            val w = ways[wi]
            if (filter != null && !filter(w)) continue
            val a = w.nodes[s]; val c = w.nodes[s + 1]
            val ax = nodeX[a]; val az = nodeZ[a]
            val dx = nodeX[c] - ax; val dz = nodeZ[c] - az
            val l2 = dx * dx + dz * dz
            if (l2 < 1e-6f) continue
            val t = (((x - ax) * dx + (z - az) * dz) / l2).coerceIn(0f, 1f)
            val d = hypot(x - (ax + dx * t), z - (az + dz * t))
            if (d < out.dist) {
                val l = sqrt(l2)
                out.dist = d; out.way = w; out.wayIndex = wi; out.seg = s
                out.dirX = dx / l; out.dirZ = dz / l
            }
        }
        return out
    }

    private val tmpHit = RoadHit()

    /** Altitude du sol (terrain, chaussée ou tablier de pont) sous un point, connaissant l'altitude approximative du véhicule. */
    fun groundHeight(x: Float, z: Float, refY: Float): Float {
        var g = terrain.height(x, z)
        nearestRoad(x, z, tmpHit)
        val w = tmpHit.way
        if (w != null && !w.bridge && tmpHit.dist < w.width * 0.5f + 0.3f) g += 0.07f
        g += decor.surf.offset(x, z)   // trottoirs, plateaux, dos d'âne, terre-pleins
        for (b in bridges) {
            val p = b.pts
            var k = 0
            while (k + 5 < p.size) {
                val ax = p[k]; val ay = p[k + 1]; val az = p[k + 2]
                val dx = p[k + 3] - ax; val dy = p[k + 4] - ay; val dz = p[k + 5] - az
                val l2 = dx * dx + dz * dz
                if (l2 > 1e-6f) {
                    val t = ((x - ax) * dx + (z - az) * dz) / l2
                    if (t in 0f..1f) {
                        val d = abs((x - ax) * dz - (z - az) * dx) / sqrt(l2)
                        if (d < b.hw + 0.3f) {
                            val deck = ay + dy * t + 0.1f
                            if (refY > deck - 2.5f && deck > g) g = deck
                        }
                    }
                }
                k += 3
            }
        }
        return g
    }

    fun clampX(x: Float) = min(maxX - 60f, max(minX + 60f, x))
    fun clampZ(z: Float) = min(maxZ - 60f, max(minZ + 60f, z))
}
