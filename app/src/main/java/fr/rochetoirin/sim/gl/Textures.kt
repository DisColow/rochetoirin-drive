package fr.rochetoirin.sim.gl

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.opengl.GLES30.*
import android.opengl.GLUtils
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.random.Random

/** Textures générées procéduralement (aucune image externe). */
object Textures {

    /** Bruit de valeur périodique (tuilable) sur [0,1]². */
    private class TileNoise(val period: Int, seed: Int) {
        private val v = Random(seed).let { r -> FloatArray(period * period) { r.nextFloat() } }
        fun at(x: Float, y: Float): Float {
            val xi = floor(x).toInt(); val yi = floor(y).toInt()
            val fx = x - xi; val fy = y - yi
            val sx = fx * fx * (3 - 2 * fx); val sy = fy * fy * (3 - 2 * fy)
            fun g(i: Int, j: Int) = v[Math.floorMod(j, period) * period + Math.floorMod(i, period)]
            val a = g(xi, yi) + (g(xi + 1, yi) - g(xi, yi)) * sx
            val b = g(xi, yi + 1) + (g(xi + 1, yi + 1) - g(xi, yi + 1)) * sx
            return a + (b - a) * sy
        }
    }

    private fun fbm(u: Float, v: Float, base: Int, octaves: Int, seed: Int): Float {
        var sum = 0f; var amp = 0.5f; var p = base; var norm = 0f
        for (o in 0 until octaves) {
            val n = TileNoiseCache.get(p, seed + o)
            sum += n.at(u * p, v * p) * amp
            norm += amp; amp *= 0.5f; p *= 2
        }
        return sum / norm
    }

    private object TileNoiseCache {
        private val map = HashMap<Long, TileNoise>()
        fun get(p: Int, s: Int): TileNoise = map.getOrPut((p.toLong() shl 32) or s.toLong()) { TileNoise(p, s) }
    }

    fun upload(bmp: Bitmap, repeat: Boolean = true, mipmap: Boolean = true): Int {
        val t = IntArray(1)
        glGenTextures(1, t, 0)
        glBindTexture(GL_TEXTURE_2D, t[0])
        GLUtils.texImage2D(GL_TEXTURE_2D, 0, bmp, 0)
        val wrap = if (repeat) GL_REPEAT else GL_CLAMP_TO_EDGE
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, wrap)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, wrap)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
        if (mipmap) {
            glGenerateMipmap(GL_TEXTURE_2D)
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR)
            val ext = glGetString(GL_EXTENSIONS) ?: ""
            if (ext.contains("GL_EXT_texture_filter_anisotropic")) {
                glTexParameterf(GL_TEXTURE_2D, 0x84FE /* MAX_ANISOTROPY */, 8f)
            }
        } else {
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
        }
        bmp.recycle()
        return t[0]
    }

    /** Herbe : variations de vert + brins clairs/sombres. Tuilable. */
    fun grass(size: Int = 256): Bitmap {
        val px = IntArray(size * size)
        val r = Random(7)
        val lum = FloatArray(size * size)
        for (y in 0 until size) for (x in 0 until size) {
            val u = x.toFloat() / size; val v = y.toFloat() / size
            lum[y * size + x] = fbm(u, v, 4, 5, 11) * 0.75f + fbm(u, v, 32, 2, 50) * 0.25f
        }
        // brins : petits traits verticaux plus clairs ou plus sombres
        val blades = FloatArray(size * size)
        repeat(size * size / 6) {
            val x = r.nextInt(size); val y = r.nextInt(size)
            val len = 2 + r.nextInt(4)
            val s = if (r.nextFloat() < 0.6f) 0.22f else -0.25f
            val lean = r.nextInt(3) - 1
            for (k in 0 until len) {
                val xx = Math.floorMod(x + (k * lean) / 2, size); val yy = Math.floorMod(y - k, size)
                blades[yy * size + xx] += s * (1f - k.toFloat() / len)
            }
        }
        for (i in px.indices) {
            val l = lum[i]
            val b = blades[i]
            val dry = fbm((i % size).toFloat() / size, (i / size).toFloat() / size, 2, 3, 90)
            var cr = 0.22f + 0.09f * l + 0.12f * max(0f, dry - 0.55f)
            var cg = 0.34f + 0.13f * l + 0.04f * max(0f, dry - 0.55f)
            var cb = 0.12f + 0.04f * l
            cr += b * 0.35f; cg += b * 0.55f; cb += b * 0.15f
            px[i] = Color.rgb(c(cr), c(cg), c(cb))
        }
        return Bitmap.createBitmap(px, size, size, Bitmap.Config.ARGB_8888)
    }

    /** Bruit multi-canal (R,G,B,A = échelles différentes), pour les variations macro. */
    fun noise(size: Int = 256): Bitmap {
        val px = IntArray(size * size)
        for (y in 0 until size) for (x in 0 until size) {
            val u = x.toFloat() / size; val v = y.toFloat() / size
            val a = fbm(u, v, 4, 4, 100)
            val b = fbm(u, v, 8, 4, 200)
            val c = fbm(u, v, 32, 3, 300)
            val d = fbm(u, v, 64, 2, 400)
            px[y * size + x] = Color.argb(c(d), c(a), c(b), c(c))
        }
        return Bitmap.createBitmap(px, size, size, Bitmap.Config.ARGB_8888)
    }

    /**
     * Atlas des plaques d'immatriculation (ancien format FNI, Isère = 38) :
     * moitié haute = plaque avant blanche, moitié basse = plaque arrière jaune.
     */
    fun plates(): Bitmap {
        val w = 512; val h = 256
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val cv = Canvas(bmp)
        val p = Paint(Paint.ANTI_ALIAS_FLAG)
        fun plate(top: Float, bg: Int) {
            p.color = bg
            cv.drawRect(0f, top, w.toFloat(), top + 128f, p)
            p.color = Color.BLACK
            p.style = Paint.Style.STROKE; p.strokeWidth = 6f
            cv.drawRoundRect(RectF(5f, top + 5f, w - 5f, top + 123f), 10f, 10f, p)
            p.style = Paint.Style.FILL
            p.typeface = Typeface.create(Typeface.MONOSPACE, Typeface.BOLD)
            p.textSize = 92f
            p.textAlign = Paint.Align.CENTER
            p.textScaleX = 0.82f
            cv.drawText("4127 XR 38", w / 2f, top + 98f, p)
        }
        plate(0f, Color.rgb(245, 245, 240))
        plate(128f, Color.rgb(250, 205, 30))
        return bmp
    }

    private fun c(f: Float) = (min(1f, max(0f, f)) * 255).toInt()

    /**
     * Atlas des panneaux (1024 × 512, cases de 128 px, 8 colonnes × 4 lignes) :
     * ligne 0 : STOP, cédez le passage, passage piéton, dos d'âne, passage à niveau, croix de Saint-André, dos gris, barrière
     * ligne 1 : limitations 30, 50, 70, 80, 90, 110, 130, feu tricolore
     * lignes 2-3 : entrées / sorties d'agglomération (256 × 128) pour 4 communes.
     */
    fun signs(names: List<String>): Bitmap {
        val bmp = Bitmap.createBitmap(1024, 512, Bitmap.Config.ARGB_8888)
        val cv = Canvas(bmp)
        val p = Paint(Paint.ANTI_ALIAS_FLAG)
        val red = Color.rgb(200, 20, 30); val white = Color.rgb(245, 245, 240); val black = Color.rgb(20, 20, 20)
        val blue = Color.rgb(20, 70, 160)
        fun cell(c: Int, r: Int, f: (Float, Float) -> Unit) { cv.save(); cv.translate(c * 128f, r * 128f); f(64f, 64f); cv.restore() }
        fun poly(pts: FloatArray, color: Int) {
            val path = android.graphics.Path()
            path.moveTo(pts[0], pts[1])
            var k = 2
            while (k < pts.size) { path.lineTo(pts[k], pts[k + 1]); k += 2 }
            path.close()
            p.style = Paint.Style.FILL; p.color = color
            cv.drawPath(path, p)
        }
        fun text(t: String, x: Float, y: Float, size: Float, color: Int, scaleX: Float = 1f) {
            p.style = Paint.Style.FILL; p.color = color; p.textSize = size; p.textAlign = Paint.Align.CENTER
            p.typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD); p.textScaleX = scaleX
            cv.drawText(t, x, y, p)
            p.textScaleX = 1f
        }
        fun octagon(cx: Float, cy: Float, r: Float): FloatArray {
            val a = FloatArray(16)
            for (k in 0 until 8) {
                val ang = Math.PI / 8 + k * Math.PI / 4
                a[k * 2] = cx + (r * Math.cos(ang)).toFloat(); a[k * 2 + 1] = cy + (r * Math.sin(ang)).toFloat()
            }
            return a
        }
        // STOP
        cell(0, 0) { cx, cy ->
            poly(octagon(cx, cy, 62f), white); poly(octagon(cx, cy, 56f), red)
            text("STOP", cx, cy + 13f, 38f, white, 0.9f)
        }
        // cédez le passage (triangle pointe en bas)
        cell(1, 0) { cx, cy ->
            poly(floatArrayOf(4f, 10f, 124f, 10f, 64f, 120f), red)
            poly(floatArrayOf(24f, 22f, 104f, 22f, 64f, 94f), white)
        }
        fun warning(c: Int, icon: () -> Unit) = cell(c, 0) { _, _ ->
            poly(floatArrayOf(64f, 6f, 124f, 116f, 4f, 116f), red)
            poly(floatArrayOf(64f, 28f, 104f, 102f, 24f, 102f), white)
            icon()
        }
        // passage piéton (C20a)
        cell(2, 0) { cx, cy ->
            p.style = Paint.Style.FILL; p.color = white; cv.drawRoundRect(RectF(4f, 4f, 124f, 124f), 10f, 10f, p)
            p.color = blue; cv.drawRoundRect(RectF(10f, 10f, 118f, 118f), 8f, 8f, p)
            poly(floatArrayOf(64f, 18f, 112f, 108f, 16f, 108f), white)
            p.color = black
            for (k in 0 until 4) cv.drawRect(34f + k * 16f, 96f, 42f + k * 16f, 104f, p)
            cv.drawCircle(64f, 50f, 6f, p)
            p.strokeWidth = 6f; p.style = Paint.Style.STROKE
            cv.drawLine(64f, 56f, 62f, 76f, p); cv.drawLine(62f, 76f, 52f, 92f, p); cv.drawLine(62f, 76f, 72f, 92f, p)
            cv.drawLine(64f, 62f, 52f, 72f, p); cv.drawLine(64f, 62f, 76f, 70f, p)
        }
        // dos d'âne (A2b)
        warning(3) {
            p.style = Paint.Style.FILL; p.color = black
            val path = android.graphics.Path(); path.moveTo(34f, 92f); path.cubicTo(50f, 92f, 52f, 62f, 64f, 62f); path.cubicTo(76f, 62f, 78f, 92f, 94f, 92f); path.close()
            cv.drawPath(path, p)
        }
        // passage à niveau avec barrières (A7)
        warning(4) {
            p.style = Paint.Style.FILL; p.color = black
            cv.drawRect(40f, 62f, 46f, 94f, p)
            for (k in 0 until 4) { p.color = if (k % 2 == 0) black else white; cv.drawRect(46f + k * 11f, 70f, 57f + k * 11f, 78f, p) }
            p.style = Paint.Style.STROKE; p.color = black; p.strokeWidth = 2f; cv.drawRect(46f, 70f, 90f, 78f, p)
        }
        // croix de Saint-André
        cell(5, 0) { cx, cy ->
            for (ang in floatArrayOf(45f, -45f)) {
                cv.save(); cv.rotate(ang, cx, cy)
                p.style = Paint.Style.FILL; p.color = red; cv.drawRect(4f, cy - 13f, 124f, cy + 13f, p)
                p.color = white; cv.drawRect(10f, cy - 8f, 118f, cy + 8f, p)
                cv.restore()
            }
        }
        // dos gris de panneau
        cell(6, 0) { _, _ -> p.style = Paint.Style.FILL; p.color = Color.rgb(150, 152, 155); cv.drawRect(0f, 0f, 128f, 128f, p) }
        // bandes rouges et blanches (barrière)
        cell(7, 0) { _, _ ->
            p.style = Paint.Style.FILL
            for (k in 0 until 8) { p.color = if (k % 2 == 0) red else white; cv.drawRect(k * 16f, 0f, k * 16f + 16f, 128f, p) }
        }
        // limitations de vitesse
        for ((k, v) in listOf(30, 50, 70, 80, 90, 110, 130).withIndex()) cell(k, 1) { cx, cy ->
            p.style = Paint.Style.FILL; p.color = red; cv.drawCircle(cx, cy, 60f, p)
            p.color = white; cv.drawCircle(cx, cy, 47f, p)
            text("$v", cx, cy + 17f, if (v >= 100) 40f else 50f, black, if (v >= 100) 0.8f else 1f)
        }
        // feu tricolore (vert allumé)
        cell(7, 1) { cx, _ ->
            p.style = Paint.Style.FILL; p.color = Color.rgb(25, 25, 28); cv.drawRoundRect(RectF(34f, 2f, 94f, 126f), 10f, 10f, p)
            p.color = Color.rgb(70, 15, 15); cv.drawCircle(cx, 24f, 16f, p)
            p.color = Color.rgb(80, 60, 10); cv.drawCircle(cx, 64f, 16f, p)
            p.color = Color.rgb(60, 255, 120); cv.drawCircle(cx, 104f, 16f, p)
        }
        // entrées / sorties d'agglomération (EB10 / EB20)
        for ((i, name) in names.take(4).withIndex()) for (exit in 0..1) {
            val slot = i * 2 + exit
            val x0 = (slot % 4) * 256f; val y0 = (2 + slot / 4) * 128f
            p.style = Paint.Style.FILL; p.color = red; cv.drawRect(x0 + 2f, y0 + 14f, x0 + 254f, y0 + 114f, p)
            p.color = white; cv.drawRect(x0 + 10f, y0 + 22f, x0 + 246f, y0 + 106f, p)
            val t = name.uppercase()
            val size = if (t.length > 14) 26f else if (t.length > 10) 32f else 38f
            text(t, x0 + 128f, y0 + 64f + size * 0.36f, size, black, if (t.length > 18) 0.75f else 0.9f)
            if (exit == 1) {
                p.style = Paint.Style.STROKE; p.color = red; p.strokeWidth = 12f
                cv.drawLine(x0 + 18f, y0 + 100f, x0 + 238f, y0 + 28f, p)
            }
        }
        return bmp
    }
}
