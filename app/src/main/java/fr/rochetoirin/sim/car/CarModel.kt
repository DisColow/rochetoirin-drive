package fr.rochetoirin.sim.car

import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Modèle 3D procédural d'un Renault Espace IV (2002-2006), rouge.
 *
 * Repère du véhicule : x = droite, y = haut, z = arrière (l'avant regarde vers -z).
 * Origine au sol, au milieu de l'empattement.
 * Format des sommets : position(3), normale(3), couleur(3) + matériau(1), uv(2) = 12 flottants.
 */
object CarModel {
    // --- dimensions (m) ---
    const val LENGTH = 4.66f
    const val WHEELBASE = 2.80f
    const val TRACK = 1.56f
    const val WHEEL_R = 0.33f
    const val WHEEL_W = 0.21f
    private const val FRONT = -2.35f            // z du pare-chocs avant
    val FRONT_AXLE_Z = -WHEELBASE / 2
    val REAR_AXLE_Z = WHEELBASE / 2

    // Position de l'œil du conducteur (conduite à gauche) et du volant
    val DRIVER_EYE = floatArrayOf(-0.40f, 1.33f, 0.12f)
    val STEERING_POS = floatArrayOf(-0.40f, 1.02f, -0.52f)
    const val STEERING_TILT = 62f   // degrés depuis l'horizontale

    // --- matériaux (lus par le shader) ---
    const val M_PAINT = 0f
    const val M_GLASS = 1f
    const val M_PLASTIC = 2f
    const val M_CHROME = 3f
    const val M_RUBBER = 4f
    const val M_LAMP = 5f
    const val M_TAIL = 6f
    const val M_PLATE_FRONT = 7f
    const val M_PLATE_REAR = 8f
    const val M_INTERIOR = 9f
    const val M_SCREEN = 10f

    private val RED = floatArrayOf(0.60f, 0.035f, 0.045f)
    private val BLACK = floatArrayOf(0.045f, 0.045f, 0.05f)
    private val GLASS = floatArrayOf(0.05f, 0.07f, 0.085f)
    private val CHROME = floatArrayOf(0.78f, 0.78f, 0.80f)
    private val LAMP = floatArrayOf(0.60f, 0.64f, 0.70f)
    private val TAIL = floatArrayOf(0.75f, 0.04f, 0.04f)
    private val ORANGE = floatArrayOf(0.95f, 0.45f, 0.05f)
    private val TYRE = floatArrayOf(0.04f, 0.04f, 0.045f)
    private val RIM = floatArrayOf(0.70f, 0.72f, 0.75f)
    private val INTERIOR = floatArrayOf(0.14f, 0.14f, 0.15f)
    private val SEAT = floatArrayOf(0.20f, 0.20f, 0.22f)
    private val WHITE = floatArrayOf(1f, 1f, 1f)

    class Builder {
        val v = ArrayList<Float>()
        val i = ArrayList<Int>()
        val count get() = v.size / 12

        fun vert(x: Float, y: Float, z: Float, nx: Float, ny: Float, nz: Float, c: FloatArray, m: Float, u: Float = 0f, w: Float = 0f): Int {
            val l = sqrt(nx * nx + ny * ny + nz * nz).let { if (it < 1e-6f) 1f else it }
            v.add(x); v.add(y); v.add(z); v.add(nx / l); v.add(ny / l); v.add(nz / l)
            v.add(c[0]); v.add(c[1]); v.add(c[2]); v.add(m); v.add(u); v.add(w)
            return count - 1
        }

        private fun px(k: Int) = v[k * 12]
        private fun py(k: Int) = v[k * 12 + 1]
        private fun pz(k: Int) = v[k * 12 + 2]

        /** Triangle orienté pour que sa face avant (CCW) suive la normale du sommet a. */
        fun tri(a: Int, b: Int, c: Int) {
            val ux = px(b) - px(a); val uy = py(b) - py(a); val uz = pz(b) - pz(a)
            val wx = px(c) - px(a); val wy = py(c) - py(a); val wz = pz(c) - pz(a)
            val cx = uy * wz - uz * wy; val cy = uz * wx - ux * wz; val cz = ux * wy - uy * wx
            val nx = v[a * 12 + 3] + v[b * 12 + 3] + v[c * 12 + 3]
            val ny = v[a * 12 + 4] + v[b * 12 + 4] + v[c * 12 + 4]
            val nz = v[a * 12 + 5] + v[b * 12 + 5] + v[c * 12 + 5]
            if (cx * nx + cy * ny + cz * nz >= 0) { i.add(a); i.add(b); i.add(c) } else { i.add(a); i.add(c); i.add(b) }
        }

        fun quad(a: Int, b: Int, c: Int, d: Int) { tri(a, b, c); tri(a, c, d) }

        /** Boîte alignée sur les axes. */
        fun box(cx: Float, cy: Float, cz: Float, sx: Float, sy: Float, sz: Float, c: FloatArray, m: Float) {
            val hx = sx / 2; val hy = sy / 2; val hz = sz / 2
            val faces = arrayOf(
                floatArrayOf(1f, 0f, 0f), floatArrayOf(-1f, 0f, 0f), floatArrayOf(0f, 1f, 0f),
                floatArrayOf(0f, -1f, 0f), floatArrayOf(0f, 0f, 1f), floatArrayOf(0f, 0f, -1f),
            )
            for (n in faces) {
                // deux axes tangents
                val t1 = if (n[0] != 0f) floatArrayOf(0f, 1f, 0f) else floatArrayOf(1f, 0f, 0f)
                val t2 = floatArrayOf(n[1] * t1[2] - n[2] * t1[1], n[2] * t1[0] - n[0] * t1[2], n[0] * t1[1] - n[1] * t1[0])
                val ids = IntArray(4)
                val sg = arrayOf(floatArrayOf(-1f, -1f), floatArrayOf(1f, -1f), floatArrayOf(1f, 1f), floatArrayOf(-1f, 1f))
                for (k in 0 until 4) {
                    val x = cx + (n[0] + t1[0] * sg[k][0] + t2[0] * sg[k][1]) * hx
                    val y = cy + (n[1] + t1[1] * sg[k][0] + t2[1] * sg[k][1]) * hy
                    val z = cz + (n[2] + t1[2] * sg[k][0] + t2[2] * sg[k][1]) * hz
                    ids[k] = vert(x, y, z, n[0], n[1], n[2], c, m)
                }
                quad(ids[0], ids[1], ids[2], ids[3])
            }
        }

        fun vertices() = v.toFloatArray()
        fun indices() = i.toIntArray()
    }

    class Meshes(
        val bodyV: FloatArray, val bodyI: IntArray,
        val glassV: FloatArray, val glassI: IntArray,
        val wheelV: FloatArray, val wheelI: IntArray,
        val steerV: FloatArray, val steerI: IntArray,
    )

    // ------------------------------------------------------------------------------
    // Profils de la carrosserie (s = distance depuis l'avant)
    // ------------------------------------------------------------------------------
    private fun lerpTable(t: FloatArray, s: Float): Float {
        if (s <= t[0]) return t[1]
        var k = 0
        while (k + 3 < t.size) {
            val s0 = t[k]; val s1 = t[k + 2]
            if (s <= s1) {
                val f = (s - s0) / (s1 - s0)
                return t[k + 1] + (t[k + 3] - t[k + 1]) * f
            }
            k += 2
        }
        return t[t.size - 1]
    }

    private val TOP = floatArrayOf(
        0.00f, 0.58f, 0.05f, 0.72f, 0.15f, 0.82f, 0.35f, 0.90f, 0.62f, 0.965f, 0.86f, 1.01f,
        1.20f, 1.24f, 1.55f, 1.47f, 1.80f, 1.61f, 1.98f, 1.675f, 2.25f, 1.71f, 3.20f, 1.73f,
        4.20f, 1.72f, 4.48f, 1.69f, 4.60f, 1.645f, 4.66f, 1.60f,
    )
    private val BOTTOM = floatArrayOf(0f, 0.34f, 0.18f, 0.25f, 4.45f, 0.27f, 4.66f, 0.36f)
    private val HALFW = floatArrayOf(0f, 0.78f, 0.08f, 0.86f, 0.30f, 0.905f, 0.8f, 0.925f, 4.30f, 0.93f, 4.60f, 0.905f, 4.66f, 0.87f)
    private val BELT = floatArrayOf(0f, 0.80f, 0.86f, 0.975f, 4.66f, 1.05f)

    private const val WS0 = 0.86f   // base du pare-brise
    private const val WS1 = 1.95f   // haut du pare-brise
    private const val ARCH_R = 0.40f

    private fun archBottom(s: Float, base: Float): Float {
        var b = base
        for (axle in floatArrayOf(-FRONT + FRONT_AXLE_Z, -FRONT + REAR_AXLE_Z)) {
            val d = s - axle
            if (kotlin.math.abs(d) < ARCH_R) b = max(b, WHEEL_R + sqrt(ARCH_R * ARCH_R - d * d))
        }
        return b
    }

    private const val RING = 9

    /** Demi-section (côté droit) à la station s : RING points (x,y), du bas-centre au toit-centre. */
    private fun ring(s: Float): FloatArray {
        val t = lerpTable(TOP, s)
        val b = archBottom(s, lerpTable(BOTTOM, s))
        val hw = lerpTable(HALFW, s)
        val bl = min(lerpTable(BELT, s), t - 0.06f)
        val wt = max(bl + 0.004f, t - 0.10f)
        val re = t - 0.028f
        val ws = ((s - WS0) / (WS1 - WS0)).coerceIn(0f, 1f)
        val k1 = 0.96f + (0.89f - 0.96f) * ws
        val k2 = 0.93f + (0.83f - 0.93f) * ws
        val mid = min(bl - 0.03f, max(b + 0.14f, 0.56f))
        return floatArrayOf(
            0f, b,
            hw - 0.14f, b,
            hw - 0.025f, min(b + 0.10f, mid - 0.02f),
            hw, mid,
            hw - 0.015f, bl,
            hw * k1, wt,
            hw * k2, re,
            hw * 0.45f, t - 0.006f,
            0f, t,
        )
    }

    private fun bandColor(band: Int, s: Float): Pair<FloatArray, Float> {
        val glassSide = s in 0.93f..4.42f && s !in 2.20f..2.28f && s !in 3.30f..3.37f
        val pillar = s in 2.20f..2.28f || s in 3.30f..3.37f
        val windshield = s in WS0..WS1 - 0.02f
        val headlight = s in 0.04f..0.30f
        return when (band) {
            0 -> BLACK to M_PLASTIC
            1 -> if (s < 0.20f || s > 4.36f) BLACK to M_PLASTIC else RED to M_PAINT
            2 -> RED to M_PAINT
            3 -> RED to M_PAINT
            4 -> if (glassSide) GLASS to M_GLASS else if (pillar) BLACK to M_PLASTIC else RED to M_PAINT
            5 -> if (headlight) LAMP to M_LAMP else RED to M_PAINT
            6 -> if (windshield) GLASS to M_GLASS else if (headlight) LAMP to M_LAMP else RED to M_PAINT
            else -> if (windshield) GLASS to M_GLASS else if (s in 0.05f..0.11f) BLACK to M_PLASTIC else RED to M_PAINT
        }
    }

    fun build(): Meshes {
        val body = Builder()
        val glass = Builder()

        // stations
        val st = ArrayList<Float>()
        var s = 0f
        while (s < LENGTH - 1e-4f) { st.add(s); s += if (s < 0.4f) 0.025f else 0.05f }
        st.add(LENGTH)
        // points et normales lissées
        val pts = st.map { ring(it) }
        val n = st.size
        fun P(k: Int, j: Int) = floatArrayOf(pts[k][j * 2], pts[k][j * 2 + 1], FRONT + st[k])
        fun normal(k: Int, j: Int): FloatArray {
            val a = P(k, max(0, j - 1)); val b = P(k, min(RING - 1, j + 1))
            val c = P(max(0, k - 1), j); val d = P(min(n - 1, k + 1), j)
            val tx = b[0] - a[0]; val ty = b[1] - a[1]; val tz = b[2] - a[2]   // le long de l'anneau
            val lx = d[0] - c[0]; val ly = d[1] - c[1]; val lz = d[2] - c[2]   // le long du véhicule
            var nx = ty * lz - tz * ly; var ny = tz * lx - tx * lz; var nz = tx * ly - ty * lx
            // vers l'extérieur
            val p = P(k, j)
            if (nx * p[0] + ny * (p[1] - 0.9f) + nz * (p[2] - (FRONT + LENGTH / 2)) * 0.35f < 0) { nx = -nx; ny = -ny; nz = -nz }
            return floatArrayOf(nx, ny, nz)
        }

        for (side in intArrayOf(1, -1)) {
            val sx = side.toFloat()
            for (k in 0 until n - 1) {
                val sm = (st[k] + st[k + 1]) / 2
                for (j in 0 until RING - 1) {
                    val (col, mat) = bandColor(j, sm)
                    val bld = if (mat == M_GLASS) glass else body
                    val ids = IntArray(4)
                    val corners = arrayOf(intArrayOf(k, j), intArrayOf(k + 1, j), intArrayOf(k + 1, j + 1), intArrayOf(k, j + 1))
                    for ((q, cr) in corners.withIndex()) {
                        val p = P(cr[0], cr[1]); val nn = normal(cr[0], cr[1])
                        ids[q] = bld.vert(p[0] * sx, p[1], p[2], nn[0] * sx, nn[1], nn[2], col, mat)
                    }
                    bld.quad(ids[0], ids[1], ids[2], ids[3])
                }
            }
        }

        rearFace(body, glass, pts.last())
        frontFace(body, pts.first())
        details(body)
        interior(body)

        val wheel = wheel()
        val steer = steeringWheel()
        return Meshes(body.vertices(), body.indices(), glass.vertices(), glass.indices(),
            wheel.vertices(), wheel.indices(), steer.vertices(), steer.indices())
    }

    /** Face arrière verticale : lunette, feux verticaux, plaque jaune, pare-chocs. */
    private fun rearFace(body: Builder, glass: Builder, r: FloatArray) {
        val z = FRONT + LENGTH
        val ys = ArrayList<Float>()
        for (j in 0 until RING) ys.add(r[j * 2 + 1])
        val bl = r[4 * 2 + 1]
        ys.addAll(listOf(0.45f, 0.62f, 0.75f, 0.86f, bl + 0.03f, 1.45f, r[RING * 2 - 1] - 0.12f))
        val yl = ys.filter { it >= r[1] && it <= r[RING * 2 - 1] }.distinct().sorted()
        fun halfW(y: Float): Float {
            // largeur du contour à la hauteur y (on suit l'anneau)
            var best = 0f
            for (j in 0 until RING - 1) {
                val y0 = r[j * 2 + 1]; val y1 = r[j * 2 + 3]
                if (y in min(y0, y1)..max(y0, y1) && y1 != y0) {
                    val f = (y - y0) / (y1 - y0)
                    best = max(best, r[j * 2] + (r[j * 2 + 2] - r[j * 2]) * f)
                }
            }
            return best
        }
        val us = floatArrayOf(-1f, -0.80f, -0.30f, 0f, 0.30f, 0.80f, 1f)
        for (a in 0 until yl.size - 1) {
            val y0 = yl[a]; val y1 = yl[a + 1]; val ym = (y0 + y1) / 2
            val w0 = halfW(y0); val w1 = halfW(y1)
            for (b in 0 until us.size - 1) {
                val u0 = us[b]; val u1 = us[b + 1]; val um = kotlin.math.abs((u0 + u1) / 2)
                var col = RED; var mat = M_PAINT; var plate = false
                when {
                    ym < 0.45f -> { col = BLACK; mat = M_PLASTIC }
                    ym in 0.62f..0.75f && um < 0.30f -> { plate = true }
                    ym in 0.86f..1.45f && um > 0.80f -> { col = TAIL; mat = M_TAIL }
                    ym > bl + 0.03f && ym < yl.last() - 0.12f + 0.001f && um < 0.80f -> { col = GLASS; mat = M_GLASS }
                }
                val bld = if (mat == M_GLASS) glass else body
                if (plate) { col = WHITE; mat = M_PLATE_REAR }
                fun vv(u: Float, y: Float, w: Float): Int {
                    val tu = (u + 0.30f) / 0.60f; val tv = 1f - (y - 0.62f) / 0.13f
                    return bld.vert(u * w, y, z, 0f, 0f, 1f, col, mat, tu, 0.5f + tv * 0.5f)
                }
                bld.quad(vv(u0, y0, w0), vv(u1, y0, w0), vv(u1, y1, w1), vv(u0, y1, w1))
            }
        }
        // feu de brouillard / recul dans le bouclier et becquet
        body.box(0f, yl.last() + 0.012f, z - 0.10f, 1.40f, 0.03f, 0.22f, BLACK, M_PLASTIC)
    }

    /** Nez du véhicule : bouclier, grille, plaque blanche, losange Renault, antibrouillards. */
    private fun frontFace(body: Builder, r: FloatArray) {
        val z = FRONT
        val top = r[RING * 2 - 1]; val bot = r[1]
        val w = r[3 * 2]
        // remplissage de la face avant (éventail)
        val c = body.vert(0f, (top + bot) / 2, z, 0f, 0f, -1f, RED, M_PAINT)
        val ring = ArrayList<Int>()
        for (j in 0 until RING) ring.add(body.vert(r[j * 2], r[j * 2 + 1], z, 0f, 0f, -1f, RED, M_PAINT))
        for (j in RING - 1 downTo 0) ring.add(body.vert(-r[j * 2], r[j * 2 + 1], z, 0f, 0f, -1f, RED, M_PAINT))
        for (k in 0 until ring.size - 1) body.tri(c, ring[k], ring[k + 1])
        // prise d'air inférieure
        fun panel(x0: Float, x1: Float, y0: Float, y1: Float, col: FloatArray, m: Float, dz: Float, u0: Float = 0f, v0: Float = 0f, u1: Float = 0f, v1: Float = 0f) {
            val a = body.vert(x0, y0, z - dz, 0f, 0f, -1f, col, m, u0, v1)
            val b = body.vert(x1, y0, z - dz, 0f, 0f, -1f, col, m, u1, v1)
            val cc = body.vert(x1, y1, z - dz, 0f, 0f, -1f, col, m, u1, v0)
            val d = body.vert(x0, y1, z - dz, 0f, 0f, -1f, col, m, u0, v0)
            body.quad(a, b, cc, d)
        }
        panel(-w * 0.85f, w * 0.85f, bot + 0.02f, bot + 0.13f, BLACK, M_PLASTIC, 0.004f)
        panel(-0.27f, 0.27f, bot + 0.05f, bot + 0.16f, WHITE, M_PLATE_FRONT, 0.012f, 1f, 0f, 0f, 0.5f)
        // antibrouillards
        panel(-w * 0.80f, -w * 0.62f, bot + 0.05f, bot + 0.11f, LAMP, M_LAMP, 0.008f)
        panel(w * 0.62f, w * 0.80f, bot + 0.05f, bot + 0.11f, LAMP, M_LAMP, 0.008f)
        // losange Renault sur la calandre (incliné comme le capot)
        val ly = 0.745f; val lz = FRONT + 0.07f
        val nY = 0.55f; val nZ = -0.83f
        val hs = 0.085f
        val dirs = arrayOf(floatArrayOf(0f, hs * 1.25f), floatArrayOf(hs * 0.8f, 0f), floatArrayOf(0f, -hs * 1.25f), floatArrayOf(-hs * 0.8f, 0f))
        val ctr = body.vert(0f, ly, lz - 0.012f, 0f, nY, nZ, CHROME, M_CHROME)
        val ids = dirs.map { d -> body.vert(d[0], ly + d[1] * 0.83f, lz - 0.012f + d[1] * 0.55f, 0f, nY, nZ, CHROME, M_CHROME) }
        for (k in 0 until 4) body.tri(ctr, ids[k], ids[(k + 1) % 4])
        // clignotants latéraux
        body.box(0.93f, 0.72f, FRONT + 0.75f, 0.01f, 0.03f, 0.07f, ORANGE, M_LAMP)
        body.box(-0.93f, 0.72f, FRONT + 0.75f, 0.01f, 0.03f, 0.07f, ORANGE, M_LAMP)
    }

    private fun details(b: Builder) {
        // rétroviseurs
        for (sd in intArrayOf(-1, 1)) {
            b.box(sd * 0.955f, 1.06f, FRONT + 1.30f, 0.10f, 0.04f, 0.07f, BLACK, M_PLASTIC)
            b.box(sd * 1.04f, 1.10f, FRONT + 1.31f, 0.17f, 0.12f, 0.08f, RED, M_PAINT)
            b.box(sd * 1.04f, 1.10f, FRONT + 1.352f, 0.15f, 0.10f, 0.004f, CHROME, M_CHROME)
            // barres de toit
            b.box(sd * 0.70f, 1.755f, FRONT + 3.2f, 0.04f, 0.035f, 2.2f, CHROME, M_CHROME)
            b.box(sd * 0.70f, 1.74f, FRONT + 2.15f, 0.05f, 0.04f, 0.08f, BLACK, M_PLASTIC)
            b.box(sd * 0.70f, 1.735f, FRONT + 4.28f, 0.05f, 0.04f, 0.08f, BLACK, M_PLASTIC)
            // baguettes de protection latérales
            b.box(sd * 0.932f, 0.62f, FRONT + 2.35f, 0.012f, 0.06f, 2.0f, BLACK, M_PLASTIC)
            // poignées
            b.box(sd * 0.935f, 0.93f, FRONT + 1.95f, 0.012f, 0.03f, 0.14f, BLACK, M_PLASTIC)
            b.box(sd * 0.937f, 0.94f, FRONT + 3.05f, 0.012f, 0.03f, 0.14f, BLACK, M_PLASTIC)
        }
        // essuie-glaces
        b.box(-0.35f, 1.025f, FRONT + 0.92f, 0.60f, 0.015f, 0.025f, BLACK, M_PLASTIC)
        b.box(0.30f, 1.025f, FRONT + 0.92f, 0.55f, 0.015f, 0.025f, BLACK, M_PLASTIC)
        // échappement
        b.box(-0.55f, 0.27f, FRONT + LENGTH - 0.05f, 0.07f, 0.07f, 0.18f, CHROME, M_CHROME)
    }

    private fun interior(b: Builder) {
        // planche de bord profonde typique de l'Espace
        b.box(0f, 0.93f, FRONT + 1.22f, 1.70f, 0.14f, 0.60f, INTERIOR, M_INTERIOR)
        b.box(0f, 0.80f, FRONT + 1.50f, 1.70f, 0.30f, 0.12f, INTERIOR, M_INTERIOR)
        // écran central de l'instrumentation (compteur au centre)
        b.box(0f, 1.015f, FRONT + 1.30f, 0.34f, 0.03f, 0.14f, floatArrayOf(0.02f, 0.03f, 0.03f), M_SCREEN)
        // console centrale
        b.box(0f, 0.62f, FRONT + 1.85f, 0.26f, 0.35f, 0.60f, INTERIOR, M_INTERIOR)
        // sièges (5 places, 3 rangées)
        for (x in floatArrayOf(-0.42f, 0.42f)) {
            b.box(x, 0.62f, FRONT + 2.45f, 0.50f, 0.14f, 0.50f, SEAT, M_INTERIOR)
            b.box(x, 1.02f, FRONT + 2.72f, 0.48f, 0.70f, 0.12f, SEAT, M_INTERIOR)
            b.box(x, 1.44f, FRONT + 2.74f, 0.26f, 0.16f, 0.10f, SEAT, M_INTERIOR)
        }
        for (x in floatArrayOf(-0.55f, 0f, 0.55f)) {
            b.box(x, 0.64f, FRONT + 3.45f, 0.46f, 0.14f, 0.48f, SEAT, M_INTERIOR)
            b.box(x, 1.02f, FRONT + 3.72f, 0.44f, 0.66f, 0.12f, SEAT, M_INTERIOR)
        }
        // plancher et habillages
        b.box(0f, 0.36f, FRONT + 2.9f, 1.72f, 0.04f, 3.5f, INTERIOR, M_INTERIOR)
        // rétroviseur intérieur
        b.box(0f, 1.50f, FRONT + 1.92f, 0.22f, 0.06f, 0.02f, BLACK, M_PLASTIC)
    }

    /** Roue centrée à l'origine, axe = x, face extérieure vers +x. */
    private fun wheel(): Builder {
        val b = Builder()
        val seg = 30
        val r = WHEEL_R; val hw = WHEEL_W / 2
        val rimR = 0.215f
        for (k in 0 until seg) {
            val a0 = (2 * PI * k / seg).toFloat(); val a1 = (2 * PI * (k + 1) / seg).toFloat()
            val c0 = cos(a0); val s0 = sin(a0); val c1 = cos(a1); val s1 = sin(a1)
            // bande de roulement
            b.quad(
                b.vert(-hw, c0 * r, s0 * r, 0f, c0, s0, TYRE, M_RUBBER), b.vert(hw, c0 * r, s0 * r, 0f, c0, s0, TYRE, M_RUBBER),
                b.vert(hw, c1 * r, s1 * r, 0f, c1, s1, TYRE, M_RUBBER), b.vert(-hw, c1 * r, s1 * r, 0f, c1, s1, TYRE, M_RUBBER),
            )
            // flancs (bombés)
            for (sd in intArrayOf(-1, 1)) {
                val x = sd * hw
                val ri = rimR
                b.quad(
                    b.vert(x, c0 * r, s0 * r, sd.toFloat(), c0 * 0.4f, s0 * 0.4f, TYRE, M_RUBBER),
                    b.vert(x, c1 * r, s1 * r, sd.toFloat(), c1 * 0.4f, s1 * 0.4f, TYRE, M_RUBBER),
                    b.vert(x * 0.9f, c1 * ri, s1 * ri, sd.toFloat(), 0f, 0f, TYRE, M_RUBBER),
                    b.vert(x * 0.9f, c0 * ri, s0 * ri, sd.toFloat(), 0f, 0f, TYRE, M_RUBBER),
                )
            }
            // jante : 5 branches sur la face extérieure, fond sombre
            val spoke = k % 6 < 2
            val xr = hw * 0.75f
            val col = if (spoke) RIM else floatArrayOf(0.08f, 0.08f, 0.09f)
            val xin = if (spoke) xr else xr - 0.06f
            b.quad(
                b.vert(xin, c0 * rimR, s0 * rimR, 1f, 0f, 0f, col, M_CHROME), b.vert(xin, c1 * rimR, s1 * rimR, 1f, 0f, 0f, col, M_CHROME),
                b.vert(xin, c1 * 0.06f, s1 * 0.06f, 1f, 0f, 0f, col, M_CHROME), b.vert(xin, c0 * 0.06f, s0 * 0.06f, 1f, 0f, 0f, col, M_CHROME),
            )
            // bord de jante
            b.quad(
                b.vert(xr, c0 * rimR, s0 * rimR, 0.3f, -c0, -s0, RIM, M_CHROME), b.vert(xr, c1 * rimR, s1 * rimR, 0.3f, -c1, -s1, RIM, M_CHROME),
                b.vert(xr - 0.07f, c1 * (rimR - 0.01f), s1 * (rimR - 0.01f), 0.3f, -c1, -s1, RIM, M_CHROME),
                b.vert(xr - 0.07f, c0 * (rimR - 0.01f), s0 * (rimR - 0.01f), 0.3f, -c0, -s0, RIM, M_CHROME),
            )
            // moyeu
            val hub = b.vert(xr + 0.01f, 0f, 0f, 1f, 0f, 0f, RIM, M_CHROME)
            b.tri(hub, b.vert(xr, c0 * 0.06f, s0 * 0.06f, 1f, 0f, 0f, RIM, M_CHROME), b.vert(xr, c1 * 0.06f, s1 * 0.06f, 1f, 0f, 0f, RIM, M_CHROME))
        }
        return b
    }

    /** Volant, centré à l'origine, dans le plan xy (axe de rotation = z). */
    private fun steeringWheel(): Builder {
        val b = Builder()
        val seg = 28
        val R = 0.19f; val t = 0.018f
        val col = floatArrayOf(0.08f, 0.08f, 0.085f)
        for (k in 0 until seg) {
            val a0 = (2 * PI * k / seg).toFloat(); val a1 = (2 * PI * (k + 1) / seg).toFloat()
            for (q in 0 until 4) {
                val p0 = (PI / 2 * q).toFloat(); val p1 = (PI / 2 * (q + 1)).toFloat()
                fun pt(a: Float, p: Float): Int {
                    val rr = R + cos(p) * t
                    return b.vert(cos(a) * rr, sin(a) * rr, sin(p) * t, cos(a) * cos(p), sin(a) * cos(p), sin(p), col, M_PLASTIC)
                }
                b.quad(pt(a0, p0), pt(a1, p0), pt(a1, p1), pt(a0, p1))
            }
        }
        // branches et moyeu (avec logo)
        b.box(0f, -0.09f, 0.01f, 0.05f, 0.18f, 0.02f, col, M_PLASTIC)
        b.box(-0.10f, -0.01f, 0.01f, 0.20f, 0.045f, 0.02f, col, M_PLASTIC)
        b.box(0.10f, -0.01f, 0.01f, 0.20f, 0.045f, 0.02f, col, M_PLASTIC)
        b.box(0f, 0f, 0.0f, 0.11f, 0.09f, 0.05f, col, M_PLASTIC)
        b.box(0f, 0f, -0.027f, 0.03f, 0.04f, 0.005f, CHROME, M_CHROME)
        return b
    }
}
