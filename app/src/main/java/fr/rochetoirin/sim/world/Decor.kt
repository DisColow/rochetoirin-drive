package fr.rochetoirin.sim.world

import java.io.InputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/** Tuile de décor (bâtiments, eau, pylônes) : 13 flottants par sommet. [bigIndices] = premiers indices (gros objets). */
class PropChunk(val cx: Int, val cz: Int, val vertices: FloatArray, val indices: IntArray, val bigIndices: Int)

/** Tuile d'arbres : instances (x, y, z, hauteur, type, aléa). */
class TreeChunk(val cx: Int, val cz: Int, val data: FloatArray) {
    val count get() = data.size / 6
}

object TreeType {
    const val OAK = 0; const val BUSH = 1; const val POPLAR = 2; const val CONIFER = 3; const val FRUIT = 4; const val SHRUB = 5
    /** Rayon de collision du tronc / de l'arbuste (m). */
    val TRUNK = floatArrayOf(0.45f, 0.9f, 0.4f, 0.4f, 0.25f, 0.7f)
}

/** Décor 3D et obstacles. Les images (occupation du sol) sont chargées par le moteur de rendu. */
class Decor(open: (String) -> InputStream, private val world: World) {
    val props: List<PropChunk>
    /** Trottoirs, panneaux, lampadaires, feux, barrières, îlots, glissières, caténaires. */
    val street: List<PropChunk>
    val surf: Surf
    /** Communes des panneaux d'entrée d'agglomération (ordre de l'atlas). */
    val signNames: List<String>
    val trees: List<TreeChunk>
    val pano: HeightGrid?
    val chunkSize: Float
    private val buildings: List<FloatArray>     // anneaux x,z
    private val bMinX: FloatArray; private val bMinZ: FloatArray; private val bMaxX: FloatArray; private val bMaxZ: FloatArray

    // index spatial des obstacles (cellules de 24 m)
    private val cell = 24f
    private val gw: Int
    private val gh: Int
    private val bIndex: Array<IntArray>
    private val tIndex: Array<FloatArray>   // x, z, rayon répétés

    init {
        fun bytes(name: String): ByteBuffer? = try {
            ByteBuffer.wrap(open(name).use { it.readBytes() }).order(ByteOrder.LITTLE_ENDIAN)
        } catch (e: Exception) { null }

        // --- props (bâtiments…) et équipements de la route
        fun propChunks(name: String): List<PropChunk> {
            val pl = ArrayList<PropChunk>()
            bytes(name)?.let { bb ->
                bb.position(4); bb.float; bb.float; bb.float; bb.int; bb.int
                val n = bb.int
                repeat(n) {
                    val cx = bb.int; val cz = bb.int; val nv = bb.int; val ni = bb.int; val nb = bb.int
                    val v = FloatArray(nv * 13); bb.asFloatBuffer().get(v); bb.position(bb.position() + nv * 52)
                    val idx = IntArray(ni); bb.asIntBuffer().get(idx); bb.position(bb.position() + ni * 4)
                    pl.add(PropChunk(cx, cz, v, idx, nb))
                }
            }
            return pl
        }
        props = propChunks("props.bin")
        street = propChunks("street.bin")
        chunkSize = 320f
        surf = Surf(bytes("surf.bin"))
        signNames = try {
            val js = org.json.JSONObject(open("street.json").use { String(it.readBytes(), Charsets.UTF_8) }).getJSONArray("signs")
            List(js.length()) { js.getString(it) }
        } catch (e: Exception) { emptyList() }

        // --- arbres
        val tl = ArrayList<TreeChunk>()
        bytes("trees.bin")?.let { bb ->
            bb.position(4); bb.float; bb.float; bb.float; bb.int; bb.int
            val n = bb.int
            repeat(n) {
                val cx = bb.int; val cz = bb.int; val c = bb.int
                val d = FloatArray(c * 6); bb.asFloatBuffer().get(d); bb.position(bb.position() + c * 24)
                tl.add(TreeChunk(cx, cz, d))
            }
        }
        trees = tl

        pano = try { HeightGrid.load(open, "pano.bin") } catch (e: Exception) { null }

        // --- emprises des bâtiments
        val bl = ArrayList<FloatArray>()
        bytes("collide.bin")?.let { bb ->
            bb.position(4)
            val n = bb.int
            repeat(n) {
                val k = bb.int
                val r = FloatArray(k * 2); bb.asFloatBuffer().get(r); bb.position(bb.position() + k * 8)
                bl.add(r)
            }
        }
        buildings = bl
        bMinX = FloatArray(bl.size); bMinZ = FloatArray(bl.size); bMaxX = FloatArray(bl.size); bMaxZ = FloatArray(bl.size)
        gw = ((world.maxX - world.minX) / cell).toInt() + 1
        gh = ((world.maxZ - world.minZ) / cell).toInt() + 1
        val bt = Array(gw * gh) { ArrayList<Int>(0) }
        for ((i, r) in bl.withIndex()) {
            var a = Float.MAX_VALUE; var b = Float.MAX_VALUE; var c = -Float.MAX_VALUE; var d = -Float.MAX_VALUE
            var k = 0
            while (k < r.size) { a = min(a, r[k]); c = max(c, r[k]); b = min(b, r[k + 1]); d = max(d, r[k + 1]); k += 2 }
            bMinX[i] = a; bMinZ[i] = b; bMaxX[i] = c; bMaxZ[i] = d
            for (j in cellOf(b)..cellOf(d, false)) for (ii in cellOfX(a)..cellOfX(c, false)) bt[j * gw + ii].add(i)
        }
        bIndex = Array(bt.size) { bt[it].toIntArray() }
        val tt = Array(gw * gh) { ArrayList<Float>(0) }
        for (ch in trees) {
            val d = ch.data
            for (k in 0 until ch.count) {
                val x = d[k * 6]; val z = d[k * 6 + 2]; val type = d[k * 6 + 4].toInt()
                val ci = cellOfX(x); val cj = cellOf(z)
                val l = tt[cj * gw + ci]
                l.add(x); l.add(z); l.add(TreeType.TRUNK[type.coerceIn(0, 5)])
            }
        }
        tIndex = Array(tt.size) { tt[it].toFloatArray() }
    }

    private fun cellOfX(x: Float, lo: Boolean = true) = floor((x - world.minX) / cell).toInt().coerceIn(0, gw - 1)
    private fun cellOf(z: Float, lo: Boolean = true) = floor((z - world.minZ) / cell).toInt().coerceIn(0, gh - 1)

    /** Désactivable pour les tests de pilotage automatique. */
    var collisionsEnabled = true

    /** Le rectangle (centre, cap, demi-longueur, demi-largeur) touche-t-il un obstacle ? */
    fun collides(x: Float, z: Float, yaw: Float, hl: Float, hw: Float): Boolean {
        if (!collisionsEnabled) return false
        val fx = sin(yaw); val fz = -cos(yaw); val rx = cos(yaw); val rz = sin(yaw)
        val r = hl + hw
        for (cj in cellOf(z - r)..cellOf(z + r)) for (ci in cellOfX(x - r)..cellOfX(x + r)) {
            val id = cj * gw + ci
            // arbres : cercle contre rectangle
            val t = tIndex[id]
            var k = 0
            while (k < t.size) {
                val dx = t[k] - x; val dz = t[k + 1] - z
                val lf = dx * fx + dz * fz; val lr = dx * rx + dz * rz
                val qx = (kotlin.math.abs(lf) - hl).coerceAtLeast(0f); val qz = (kotlin.math.abs(lr) - hw).coerceAtLeast(0f)
                if (qx * qx + qz * qz < t[k + 2] * t[k + 2]) return true
                k += 3
            }
            for (b in bIndex[id]) {
                if (bMaxX[b] < x - r || bMinX[b] > x + r || bMaxZ[b] < z - r || bMinZ[b] > z + r) continue
                if (rectHitsPolygon(buildings[b], x, z, fx, fz, rx, rz, hl, hw)) return true
            }
        }
        return false
    }

    private fun rectHitsPolygon(p: FloatArray, x: Float, z: Float, fx: Float, fz: Float, rx: Float, rz: Float, hl: Float, hw: Float): Boolean {
        // points du contour du véhicule dans le polygone ?
        for (a in -2..2) for (b in -1..1) {
            if (a != -2 && a != 2 && b == 0) continue
            val px = x + fx * hl * a / 2f + rx * hw * b
            val pz = z + fz * hl * a / 2f + rz * hw * b
            if (inside(p, px, pz)) return true
        }
        // sommets du polygone dans le rectangle ?
        var k = 0
        while (k < p.size) {
            val dx = p[k] - x; val dz = p[k + 1] - z
            if (kotlin.math.abs(dx * fx + dz * fz) < hl && kotlin.math.abs(dx * rx + dz * rz) < hw) return true
            k += 2
        }
        return false
    }

    private fun inside(p: FloatArray, x: Float, z: Float): Boolean {
        var c = false
        val n = p.size / 2
        var j = n - 1
        for (i in 0 until n) {
            val xi = p[i * 2]; val zi = p[i * 2 + 1]; val xj = p[j * 2]; val zj = p[j * 2 + 1]
            if ((zi > z) != (zj > z) && x < (xj - xi) * (z - zi) / (zj - zi) + xi) c = !c
            j = i
        }
        return c
    }

    /** Emprises des bâtiments (pour la carte). */
    fun buildingRings(): List<FloatArray> = buildings
}

/** Surélévations de la chaussée (trottoirs, plateaux, dos d'âne) : tuiles de 32 m, 33 × 33 points en cm. */
class Surf(bb: ByteBuffer?) {
    private val x0: Float
    private val z0: Float
    private val tile: Float
    private val tiles = HashMap<Long, ByteArray>()

    init {
        if (bb == null) { x0 = 0f; z0 = 0f; tile = 32f }
        else {
            bb.position(4)
            x0 = bb.float; z0 = bb.float; tile = bb.float
            val n = bb.int
            repeat(n) {
                val tx = bb.int; val tz = bb.int
                val a = ByteArray(33 * 33); bb.get(a)
                tiles[(tx.toLong() shl 32) or (tz.toLong() and 0xffffffffL)] = a
            }
        }
    }

    /** Surélévation (m) au point (x, z), interpolée. */
    fun offset(x: Float, z: Float): Float {
        if (tiles.isEmpty()) return 0f
        val fx = (x - x0) / tile; val fz = (z - z0) / tile
        val tx = floor(fx).toInt(); val tz = floor(fz).toInt()
        val a = tiles[(tx.toLong() shl 32) or (tz.toLong() and 0xffffffffL)] ?: return 0f
        val gx = (fx - tx) * 32f; val gz = (fz - tz) * 32f
        val i = gx.toInt().coerceIn(0, 31); val j = gz.toInt().coerceIn(0, 31)
        val u = gx - i; val v = gz - j
        fun at(ii: Int, jj: Int) = (a[jj * 33 + ii].toInt() and 0xff) / 100f
        val top = at(i, j) + (at(i + 1, j) - at(i, j)) * u
        val bot = at(i, j + 1) + (at(i + 1, j + 1) - at(i, j + 1)) * u
        return top + (bot - top) * v
    }
}
