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
    companion object {
        /** Touffes du houppier (centre x, y, z et rayon, dans la sphère unité du houppier). */
        val LUMPS_HI = arrayOf(
            floatArrayOf(0f, 0.05f, 0f, 0.62f), floatArrayOf(0.45f, 0.25f, 0.15f, 0.48f), floatArrayOf(-0.42f, 0.22f, -0.2f, 0.5f),
            floatArrayOf(0.1f, 0.32f, -0.48f, 0.46f), floatArrayOf(-0.15f, 0.35f, 0.46f, 0.47f), floatArrayOf(0.38f, -0.25f, -0.3f, 0.45f),
            floatArrayOf(-0.4f, -0.22f, 0.28f, 0.44f), floatArrayOf(0.05f, 0.55f, 0f, 0.42f), floatArrayOf(0f, -0.4f, 0.05f, 0.45f))
        val LUMPS_LO = arrayOf(
            floatArrayOf(0f, 0.05f, 0f, 0.7f), floatArrayOf(0.42f, 0.1f, 0.2f, 0.5f), floatArrayOf(-0.42f, 0.12f, -0.15f, 0.5f),
            floatArrayOf(0.05f, 0.15f, -0.45f, 0.5f), floatArrayOf(-0.05f, 0.2f, 0.45f, 0.5f))
    }

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

    /** Carte d'ombre : maillage fin pour la cascade proche, simplifié pour la lointaine. */
    fun drawDepth(fine: Boolean, touches: (Bounds) -> Boolean) {
        for (c in list) {
            if (!touches(c.bounds)) continue
            if (fine) { glBindVertexArray(c.vaoHi); glDrawElementsInstanced(GL_TRIANGLES, hi.count, GL_UNSIGNED_INT, 0, c.count) }
            else { glBindVertexArray(c.vaoLo); glDrawElementsInstanced(GL_TRIANGLES, lo.count, GL_UNSIGNED_INT, 0, c.count) }
        }
        glBindVertexArray(0)
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
        // houppier en grappe de touffes (au lieu d'une boule unique) : silhouette irrégulière,
        // normales mêlant celle de la touffe et celle du houppier (éclairage doux)
        val lumps = if (subdiv > 0) LUMPS_HI else LUMPS_LO
        for ((li, l) in lumps.withIndex()) {
            val base0 = v.size / 7
            for (p in pts) {
                val x = l[0] + p[0] * l[3]; val y = l[1] + p[1] * l[3]; val z = l[2] + p[2] * l[3]
                val lc = sqrt(x * x + y * y + z * z).coerceAtLeast(1e-3f)
                var nx = p[0] * 0.6f + x / lc * 0.4f; var ny = p[1] * 0.6f + y / lc * 0.4f; var nz = p[2] * 0.6f + z / lc * 0.4f
                val ln = sqrt(nx * nx + ny * ny + nz * nz); nx /= ln; ny /= ln; nz /= ln
                v.add(x); v.add(y); v.add(z); v.add(nx); v.add(ny); v.add(nz); v.add(li * 0.05f)
            }
            for (f in faces) { idx.add(base0 + f[0]); idx.add(base0 + f[1]); idx.add(base0 + f[2]) }
        }
        // plaques de feuillage : cartes détourées posées sur les touffes (4 sommets alignés -> gl_VertexID & 3)
        while ((v.size / 7) % 4 != 0) repeat(7) { v.add(0f) }
        val ico = pts.take(12)
        for ((li, l) in lumps.withIndex()) {
            val cl = sqrt(l[0] * l[0] + l[1] * l[1] + l[2] * l[2])
            var made = 0
            for ((k, d) in ico.withIndex()) {
                if (made >= (if (subdiv > 0) 10 else 4)) break
                val out = if (cl < 0.1f) d[1] else (d[0] * l[0] + d[1] * l[1] + d[2] * l[2]) / cl
                if (out < -0.25f) continue
                // repère de la carte : inclinée vers l'extérieur pour rester visible sous plusieurs angles
                val ref = if (kotlin.math.abs(d[1]) < 0.9f) floatArrayOf(0f, 1f, 0f) else floatArrayOf(1f, 0f, 0f)
                var t1 = floatArrayOf(d[1] * ref[2] - d[2] * ref[1], d[2] * ref[0] - d[0] * ref[2], d[0] * ref[1] - d[1] * ref[0])
                var lt = sqrt(t1[0] * t1[0] + t1[1] * t1[1] + t1[2] * t1[2]); t1 = floatArrayOf(t1[0] / lt, t1[1] / lt, t1[2] / lt)
                val t2 = floatArrayOf(d[1] * t1[2] - d[2] * t1[1], d[2] * t1[0] - d[0] * t1[2], d[0] * t1[1] - d[1] * t1[0])
                val tilt = 0.55f + 0.1f * (k % 3)
                val u = floatArrayOf(t2[0] * (1 - tilt) + d[0] * tilt, t2[1] * (1 - tilt) + d[1] * tilt, t2[2] * (1 - tilt) + d[2] * tilt)
                lt = sqrt(u[0] * u[0] + u[1] * u[1] + u[2] * u[2]); for (q in 0..2) u[q] /= lt
                val s = l[3] * 0.5f
                val cx = l[0] + d[0] * l[3] * 0.9f; val cy = l[1] + d[1] * l[3] * 0.9f; val cz = l[2] + d[2] * l[3] * 0.9f
                val b0 = v.size / 7
                for ((sa, sb) in arrayOf(-1f to -1f, 1f to -1f, 1f to 1f, -1f to 1f)) {
                    v.add(cx + t1[0] * s * sa + u[0] * s * sb); v.add(cy + t1[1] * s * sa + u[1] * s * sb); v.add(cz + t1[2] * s * sa + u[2] * s * sb)
                    v.add(d[0]); v.add(d[1]); v.add(d[2]); v.add(0.5f + li * 0.02f)
                }
                idx.addAll(listOf(b0, b0 + 1, b0 + 2, b0, b0 + 2, b0 + 3))
                made++
            }
        }
        // tronc
        val sides = if (subdiv > 0) 6 else 3
        val base = v.size / 7
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
