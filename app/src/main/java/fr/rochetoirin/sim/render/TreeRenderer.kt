package fr.rochetoirin.sim.render

import android.opengl.GLES30.*
import fr.rochetoirin.sim.gl.Bounds
import fr.rochetoirin.sim.gl.Gl
import fr.rochetoirin.sim.world.TreeChunk
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Arbres instanciés, trois niveaux de détail par tuile :
 * maillage fin (< 130 m), maillage simplifié (< 380 m), panneaux face caméra (< 3,2 km).
 */
class TreeRenderer(chunks: List<TreeChunk>) {
    private class Geo(val vbo: Int, val ibo: Int, val count: Int)

    private class TChunk(val bounds: Bounds, val count: Int, val vaoHi: Int, val vaoLo: Int, val vaoBb: Int)

    init { glBindVertexArray(0) }   // ne pas modifier un VAO resté lié

    private val hi = mesh(1)
    private val lo = mesh(0)
    private val quad: Geo
    private val list = ArrayList<TChunk>()

    init {
        // panneau : deux triangles, coins (-1..1, 0..1)
        val qv = floatArrayOf(-1f, 0f, 1f, 0f, 1f, 1f, -1f, 1f)
        val qb = Gl.genBuffer(); glBindBuffer(GL_ARRAY_BUFFER, qb)
        glBufferData(GL_ARRAY_BUFFER, qv.size * 4, Gl.floats(qv), GL_STATIC_DRAW)
        val qi = Gl.genBuffer(); glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, qi)
        val qidx = intArrayOf(0, 1, 2, 0, 2, 3)
        glBufferData(GL_ELEMENT_ARRAY_BUFFER, 24, Gl.ints(qidx), GL_STATIC_DRAW)
        quad = Geo(qb, qi, 6)

        for (c in chunks) {
            if (c.count == 0) continue
            val d = c.data
            val b = Bounds(Float.MAX_VALUE, Float.MAX_VALUE, Float.MAX_VALUE, -Float.MAX_VALUE, -Float.MAX_VALUE, -Float.MAX_VALUE)
            for (k in 0 until c.count) {
                val x = d[k * 6]; val y = d[k * 6 + 1]; val z = d[k * 6 + 2]; val h = d[k * 6 + 3]
                b.minX = min(b.minX, x - 6); b.maxX = max(b.maxX, x + 6)
                b.minZ = min(b.minZ, z - 6); b.maxZ = max(b.maxZ, z + 6)
                b.minY = min(b.minY, y - 1); b.maxY = max(b.maxY, y + h * 1.1f)
            }
            val inst = Gl.genBuffer()
            glBindBuffer(GL_ARRAY_BUFFER, inst)
            glBufferData(GL_ARRAY_BUFFER, d.size * 4, Gl.floats(d), GL_STATIC_DRAW)
            list.add(TChunk(b, c.count, vao(hi, inst, false), vao(lo, inst, false), vao(quad, inst, true)))
        }
        glBindVertexArray(0)
    }

    private fun vao(g: Geo, inst: Int, billboard: Boolean): Int {
        val v = Gl.genVao()
        glBindVertexArray(v)
        glBindBuffer(GL_ARRAY_BUFFER, g.vbo)
        if (billboard) {
            glEnableVertexAttribArray(0); glVertexAttribPointer(0, 2, GL_FLOAT, false, 8, 0)
        } else {
            glEnableVertexAttribArray(0); glVertexAttribPointer(0, 3, GL_FLOAT, false, 28, 0)
            glEnableVertexAttribArray(1); glVertexAttribPointer(1, 3, GL_FLOAT, false, 28, 12)
            glEnableVertexAttribArray(2); glVertexAttribPointer(2, 1, GL_FLOAT, false, 28, 24)
        }
        glBindBuffer(GL_ARRAY_BUFFER, inst)
        glEnableVertexAttribArray(3); glVertexAttribPointer(3, 4, GL_FLOAT, false, 24, 0); glVertexAttribDivisor(3, 1)
        glEnableVertexAttribArray(4); glVertexAttribPointer(4, 2, GL_FLOAT, false, 24, 16); glVertexAttribDivisor(4, 1)
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, g.ibo)
        glBindVertexArray(0)
        return v
    }

    /**
     * Dessine les tuiles visibles dans la tranche [near, far].
     * [visible] teste frustum + tranche, [distance] donne la distance mini œil-tuile.
     */
    fun draw(pMesh: Int, pBillboard: Int, visible: (Bounds) -> Boolean, distance: (Bounds) -> Float, setup: (Int) -> Unit) {
        var used = -1
        for (c in list) {
            if (!visible(c.bounds)) continue
            val d = distance(c.bounds)
            if (d > 3200f) continue
            if (d < 380f) {
                if (used != pMesh) { glUseProgram(pMesh); setup(pMesh); used = pMesh }
                if (d < 130f) { glBindVertexArray(c.vaoHi); glDrawElementsInstanced(GL_TRIANGLES, hi.count, GL_UNSIGNED_INT, 0, c.count) }
                else { glBindVertexArray(c.vaoLo); glDrawElementsInstanced(GL_TRIANGLES, lo.count, GL_UNSIGNED_INT, 0, c.count) }
            } else {
                if (used != pBillboard) { glUseProgram(pBillboard); setup(pBillboard); used = pBillboard }
                glBindVertexArray(c.vaoBb)
                glDrawElementsInstanced(GL_TRIANGLES, 6, GL_UNSIGNED_INT, 0, c.count)
            }
        }
    }

    /** Sphère géodésique (houppier) + tronc hexagonal. Sommets : pos3, normale3, partie. */
    private fun mesh(subdiv: Int): Geo {
        val t = ((1 + sqrt(5.0)) / 2).toFloat()
        val pts = arrayListOf(
            floatArrayOf(-1f, t, 0f), floatArrayOf(1f, t, 0f), floatArrayOf(-1f, -t, 0f), floatArrayOf(1f, -t, 0f),
            floatArrayOf(0f, -1f, t), floatArrayOf(0f, 1f, t), floatArrayOf(0f, -1f, -t), floatArrayOf(0f, 1f, -t),
            floatArrayOf(t, 0f, -1f), floatArrayOf(t, 0f, 1f), floatArrayOf(-t, 0f, -1f), floatArrayOf(-t, 0f, 1f),
        ).map { val l = sqrt(it[0] * it[0] + it[1] * it[1] + it[2] * it[2]); floatArrayOf(it[0] / l, it[1] / l, it[2] / l) }.toMutableList()
        var faces = mutableListOf(
            intArrayOf(0, 11, 5), intArrayOf(0, 5, 1), intArrayOf(0, 1, 7), intArrayOf(0, 7, 10), intArrayOf(0, 10, 11),
            intArrayOf(1, 5, 9), intArrayOf(5, 11, 4), intArrayOf(11, 10, 2), intArrayOf(10, 7, 6), intArrayOf(7, 1, 8),
            intArrayOf(3, 9, 4), intArrayOf(3, 4, 2), intArrayOf(3, 2, 6), intArrayOf(3, 6, 8), intArrayOf(3, 8, 9),
            intArrayOf(4, 9, 5), intArrayOf(2, 4, 11), intArrayOf(6, 2, 10), intArrayOf(8, 6, 7), intArrayOf(9, 8, 1),
        )
        repeat(subdiv) {
            val cache = HashMap<Long, Int>()
            fun mid(a: Int, b: Int): Int {
                val key = (min(a, b).toLong() shl 32) or max(a, b).toLong()
                return cache.getOrPut(key) {
                    val p = pts[a]; val q = pts[b]
                    val m = floatArrayOf((p[0] + q[0]) / 2, (p[1] + q[1]) / 2, (p[2] + q[2]) / 2)
                    val l = sqrt(m[0] * m[0] + m[1] * m[1] + m[2] * m[2])
                    pts.add(floatArrayOf(m[0] / l, m[1] / l, m[2] / l)); pts.size - 1
                }
            }
            val nf = ArrayList<IntArray>()
            for (f in faces) {
                val a = mid(f[0], f[1]); val b = mid(f[1], f[2]); val c = mid(f[2], f[0])
                nf.add(intArrayOf(f[0], a, c)); nf.add(intArrayOf(f[1], b, a)); nf.add(intArrayOf(f[2], c, b)); nf.add(intArrayOf(a, b, c))
            }
            faces = nf
        }
        val v = ArrayList<Float>()
        val idx = ArrayList<Int>()
        for (p in pts) { v.add(p[0]); v.add(p[1]); v.add(p[2]); v.add(p[0]); v.add(p[1]); v.add(p[2]); v.add(0f) }
        for (f in faces) { idx.add(f[0]); idx.add(f[1]); idx.add(f[2]) }
        // tronc
        val sides = if (subdiv > 0) 6 else 3
        val base = pts.size
        for (k in 0 until sides) {
            val a = (2 * PI * k / sides).toFloat()
            val cx = cos(a); val cz = sin(a)
            v.addAll(listOf(cx, 0f, cz, cx, 0f, cz, 1f)); v.addAll(listOf(cx, 1f, cz, cx, 0f, cz, 1f))
        }
        for (k in 0 until sides) {
            val a = base + k * 2; val b = base + ((k + 1) % sides) * 2
            idx.addAll(listOf(a, b, b + 1, a, b + 1, a + 1))
        }
        val vb = Gl.genBuffer(); glBindBuffer(GL_ARRAY_BUFFER, vb)
        glBufferData(GL_ARRAY_BUFFER, v.size * 4, Gl.floats(v.toFloatArray()), GL_STATIC_DRAW)
        val ib = Gl.genBuffer(); glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ib)
        glBufferData(GL_ELEMENT_ARRAY_BUFFER, idx.size * 4, Gl.ints(idx.toIntArray()), GL_STATIC_DRAW)
        return Geo(vb, ib, idx.size)
    }
}
