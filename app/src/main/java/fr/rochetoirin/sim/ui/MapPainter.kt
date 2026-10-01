package fr.rochetoirin.sim.ui

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import fr.rochetoirin.sim.game.Gps
import fr.rochetoirin.sim.world.World
import kotlin.math.max
import kotlin.math.min

/** Dessin vectoriel de la carte (GPS et carte plein écran). */
class MapPainter(private val world: World, open: ((String) -> java.io.InputStream)? = null) {
    private class WayLines(val cls: Int, val pts: FloatArray, val minX: Float, val minZ: Float, val maxX: Float, val maxZ: Float)

    private val lines: List<WayLines>
    private val relief: Bitmap

    private val roadPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; strokeCap = Paint.Cap.ROUND }
    private val routePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE; strokeCap = Paint.Cap.ROUND; strokeJoin = Paint.Join.ROUND
        color = Color.rgb(240, 70, 50)
    }
    private val reliefPaint = Paint(Paint.FILTER_BITMAP_FLAG)
    private val fill = Paint(Paint.ANTI_ALIAS_FLAG)
    private val path = Path()
    private val buildingPath = Path()

    init {
        val l = ArrayList<WayLines>()
        for (w in world.ways) {
            val n = w.nodes.size
            val pts = FloatArray((n - 1) * 4)
            var mnx = Float.MAX_VALUE; var mnz = Float.MAX_VALUE; var mxx = -Float.MAX_VALUE; var mxz = -Float.MAX_VALUE
            for (k in 0 until n - 1) {
                val a = w.nodes[k]; val b = w.nodes[k + 1]
                pts[k * 4] = world.nodeX[a]; pts[k * 4 + 1] = world.nodeZ[a]
                pts[k * 4 + 2] = world.nodeX[b]; pts[k * 4 + 3] = world.nodeZ[b]
            }
            for (i in w.nodes) {
                mnx = min(mnx, world.nodeX[i]); mxx = max(mxx, world.nodeX[i])
                mnz = min(mnz, world.nodeZ[i]); mxz = max(mxz, world.nodeZ[i])
            }
            l.add(WayLines(w.style, pts, mnx, mnz, mxx, mxz))
        }
        // ordre de dessin : chemins d'abord, grands axes en dernier
        lines = l.sortedByDescending { it.cls }

        // relief ombré (1 pixel = 1 maille de 10 m)
        val g = world.terrain
        val px = IntArray(g.nx * g.nz)
        var hmin = Float.MAX_VALUE; var hmax = -Float.MAX_VALUE
        for (h in g.h) { hmin = min(hmin, h); hmax = max(hmax, h) }
        for (j in 0 until g.nz) for (i in 0 until g.nx) {
            val hx = g.at(min(g.nx - 1, i + 1), j) - g.at(max(0, i - 1), j)
            val hz = g.at(i, min(g.nz - 1, j + 1)) - g.at(i, max(0, j - 1))
            val shade = (0.5f + (-hx * 0.6f + -hz * 0.8f) * 0.06f).coerceIn(0f, 1f)
            val e = (g.at(i, j) - hmin) / (hmax - hmin)
            val r = 22 + (shade * 26).toInt() + (e * 10).toInt()
            val gg = 32 + (shade * 30).toInt() + (e * 12).toInt()
            val b = 40 + (shade * 26).toInt()
            px[j * g.nx + i] = Color.rgb(r, gg, b)
        }
        relief = landcoverRelief(open) ?: Bitmap.createBitmap(px, g.nx, g.nz, Bitmap.Config.ARGB_8888)
        // emprises des bâtiments (affichées quand on zoome)
        for (r in world.decor.buildingRings()) {
            val p = Path()
            p.moveTo(r[0], r[1])
            var k = 2
            while (k < r.size) { p.lineTo(r[k], r[k + 1]); k += 2 }
            p.close()
            buildingPath.addPath(p)
        }
    }

    private val buildingPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.rgb(92, 96, 108) }

    /** Fond de carte : occupation du sol réelle (couleurs sombres façon GPS d'ETS) + ombrage du relief. */
    private fun landcoverRelief(open: ((String) -> java.io.InputStream)?): Bitmap? {
        if (open == null) return null
        val opts = android.graphics.BitmapFactory.Options().apply { inScaled = false; inPremultiplied = false }
        val lc = try { open("landcover.png").use { android.graphics.BitmapFactory.decodeStream(it, null, opts) } } catch (e: Exception) { null } ?: return null
        val w = lc.width; val h = lc.height
        val src = IntArray(w * h); lc.getPixels(src, 0, w, 0, 0, w, h); lc.recycle()
        val pal = intArrayOf(
            Color.rgb(34, 48, 36), Color.rgb(34, 50, 36), Color.rgb(40, 54, 38), Color.rgb(66, 60, 38), Color.rgb(70, 64, 44),
            Color.rgb(32, 52, 30), Color.rgb(36, 52, 32), Color.rgb(54, 58, 34), Color.rgb(46, 50, 36), Color.rgb(56, 46, 36),
            Color.rgb(20, 38, 24), Color.rgb(40, 52, 40), Color.rgb(50, 52, 56), Color.rgb(60, 60, 58), Color.rgb(36, 62, 36),
            Color.rgb(30, 54, 82), Color.rgb(26, 42, 28), Color.rgb(38, 54, 36),
        )
        val g = world.terrain
        val out = IntArray(w * h)
        for (j in 0 until h) for (i in 0 until w) {
            val c = pal[(Color.red(src[j * w + i])).coerceIn(0, pal.size - 1)]
            val x = g.x0 + (i + 0.5f) * (g.x1 - g.x0) / w; val z = g.z0 + (j + 0.5f) * (g.z1 - g.z0) / h
            val hx = g.height(x + 10f, z) - g.height(x - 10f, z); val hz = g.height(x, z + 10f) - g.height(x, z - 10f)
            val s = (1f + (-hx * 0.6f - hz * 0.8f) * 0.03f).coerceIn(0.6f, 1.4f)
            out[j * w + i] = Color.rgb((Color.red(c) * s).toInt().coerceIn(0, 255), (Color.green(c) * s).toInt().coerceIn(0, 255), (Color.blue(c) * s).toInt().coerceIn(0, 255))
        }
        return Bitmap.createBitmap(out, w, h, Bitmap.Config.ARGB_8888)
    }

    private val reliefDst = RectF(world.terrain.x0, world.terrain.z0, world.terrain.x1, world.terrain.z1)

    /**
     * Dessine la carte dans le repère courant du canvas (déjà transformé en coordonnées monde).
     * [ppm] = pixels par mètre (pour garder des épaisseurs lisibles), [cx],[cz],[radius] = zone utile.
     */
    fun draw(c: Canvas, ppm: Float, cx: Float, cz: Float, radius: Float, route: Gps.Route?) {
        c.drawBitmap(relief, null, reliefDst, reliefPaint)
        if (ppm > 0.3f) c.drawPath(buildingPath, buildingPaint)
        val minW = 1.6f / ppm
        for (pass in 0..1) {
            for (w in lines) {
                if (w.maxX < cx - radius || w.minX > cx + radius || w.maxZ < cz - radius || w.minZ > cz + radius) continue
                val (col, width) = when (w.cls) {
                    0 -> Color.rgb(230, 140, 60) to 11f
                    1 -> Color.rgb(235, 200, 90) to 9f
                    2 -> Color.rgb(225, 215, 150) to 8f
                    3 -> Color.rgb(210, 210, 210) to 7f
                    4 -> Color.rgb(180, 185, 190) to 6f
                    5 -> Color.rgb(140, 145, 150) to 4.5f
                    else -> Color.rgb(120, 105, 85) to 3.5f
                }
                if (pass == 0) {
                    roadPaint.color = Color.argb(200, 8, 10, 14)
                    roadPaint.strokeWidth = max(width + 3f, minW * 1.6f)
                } else {
                    roadPaint.color = col
                    roadPaint.strokeWidth = max(width, minW)
                }
                c.drawLines(w.pts, roadPaint)
            }
        }
        if (route != null && route.size >= 2) {
            path.reset()
            path.moveTo(route.xs[0], route.zs[0])
            for (k in 1 until route.size) path.lineTo(route.xs[k], route.zs[k])
            routePaint.strokeWidth = max(6f, 4f / ppm)
            routePaint.alpha = 235
            c.drawPath(path, routePaint)
        }
    }

    fun marker(c: Canvas, x: Float, z: Float, size: Float, color: Int) {
        fill.color = Color.BLACK
        c.drawCircle(x, z, size * 1.25f, fill)
        fill.color = color
        c.drawCircle(x, z, size, fill)
        fill.color = Color.WHITE
        c.drawCircle(x, z, size * 0.4f, fill)
    }
}
