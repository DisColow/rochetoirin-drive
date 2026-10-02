package fr.rochetoirin.sim.ui

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.os.SystemClock
import android.view.MotionEvent
import android.view.View
import fr.rochetoirin.sim.game.ActiveJob
import fr.rochetoirin.sim.game.Game
import fr.rochetoirin.sim.game.JobOffer
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin

/** Interface de conduite dessinée au-dessus de la vue 3D. */
@SuppressLint("ViewConstructor")
class HudView(context: Context, private val game: Game, private val settings: Settings) : View(context) {

    interface Settings {
        var tiltSteering: Boolean
        var sound: Boolean
        /** Graphismes élevés : ombres portées du soleil et herbe 3D (standard : désactivées). */
        var highGraphics: Boolean
        fun tiltValue(): Float
    }

    private val dp = resources.displayMetrics.density
    private val map = MapPainter(game.world) { context.assets.open(it) }

    // --- pinceaux ---
    private val fill = Paint(Paint.ANTI_ALIAS_FLAG)
    private val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }
    private val text = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE; typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD) }
    private val panelBg = Color.argb(185, 18, 22, 30)
    private val accent = Color.rgb(255, 176, 32)   // jaune-orangé façon ETS

    // --- zones ---
    private var W = 1f; private var H = 1f
    private val wheelC = FloatArray(2); private var wheelR = 1f
    private val throttleR = RectF(); private val brakeR = RectF(); private val gearR = RectF()
    private val gpsR = RectF()
    private val btnJobs = RectF(); private val btnCam = RectF(); private val btnMap = RectF(); private val btnOpt = RectF()
    private val panelR = RectF()

    // --- état des commandes ---
    private enum class Role { NONE, STEER, HORN, THROTTLE, BRAKE, ORBIT, BUTTON, PANEL }
    private val roles = HashMap<Int, Role>()
    private val lastX = HashMap<Int, Float>(); private val lastY = HashMap<Int, Float>()
    private var steerAngleDeg = 0f        // rotation du volant affiché (tactile)
    private var steerTouchAngle = 0f
    private var steering = false
    private var throttleTarget = 0f; private var brakeTarget = 0f
    private var throttle = 0f; private var brake = 0f
    private var lastFrame = SystemClock.uptimeMillis()

    private enum class Overlay { NONE, JOBS, MAP, OPTIONS }
    private var overlay = Overlay.NONE
    private val panelButtons = ArrayList<Pair<RectF, () -> Unit>>()
    private var pressedButton: RectF? = null

    private val maxWheelDeg = 200f
    private val pedalShaders = java.util.IdentityHashMap<RectF, Shader>()
    private val gpsClip = Path()

    override fun onSizeChanged(w: Int, h: Int, ow: Int, oh: Int) {
        W = w.toFloat(); H = h.toFloat()
        wheelR = min(H * 0.21f, W * 0.12f)
        wheelC[0] = wheelR * 1.35f + 12 * dp; wheelC[1] = H - wheelR * 1.25f - 8 * dp
        val pw = min(W * 0.075f, 78 * dp)
        throttleR.set(W - pw - 18 * dp, H - H * 0.34f, W - 18 * dp, H - 16 * dp)
        brakeR.set(throttleR.left - pw * 1.55f - 14 * dp, H - H * 0.25f, throttleR.left - 14 * dp, H - 16 * dp)
        gearR.set(brakeR.left - 72 * dp, brakeR.bottom - 56 * dp, brakeR.left - 14 * dp, brakeR.bottom)
        val gw = min(W * 0.28f, 330 * dp); val gh = min(H * 0.36f, 220 * dp)
        gpsR.set(W - gw - 12 * dp, 12 * dp, W - 12 * dp, 12 * dp + gh)
        val b = 48 * dp; var x = 12 * dp
        for (r in listOf(btnJobs, btnCam, btnMap, btnOpt)) { r.set(x, 12 * dp, x + b, 12 * dp + b); x += b + 8 * dp }
        panelR.set(W * 0.18f, H * 0.10f, W * 0.82f, H * 0.90f)
        pedalShaders.clear()
        gpsClip.reset(); gpsClip.addRoundRect(gpsR, 14 * dp, 14 * dp, Path.Direction.CW)
    }

    // ============================================================================ dessin
    override fun onDraw(c: Canvas) {
        val now = SystemClock.uptimeMillis()
        val dt = ((now - lastFrame) / 1000f).coerceIn(0f, 0.1f)
        lastFrame = now
        updateControls(dt)

        drawTopLeft(c)
        drawGps(c)
        drawSpeed(c)
        drawStreet(c)
        drawMessage(c)
        if (settings.tiltSteering) drawTilt(c) else drawWheel(c)
        drawPedals(c)

        when (overlay) {
            Overlay.JOBS -> drawJobs(c)
            Overlay.MAP -> drawBigMap(c)
            Overlay.OPTIONS -> drawOptions(c)
            Overlay.NONE -> {}
        }
        postInvalidateOnAnimation()
    }

    private fun updateControls(dt: Float) {
        // volant : retour au centre quand on lâche
        if (settings.tiltSteering) {
            game.input.steer = settings.tiltValue()
        } else {
            if (!steering) {
                val back = 520f * dt
                steerAngleDeg = if (abs(steerAngleDeg) < back) 0f else steerAngleDeg - back * Math.signum(steerAngleDeg)
            }
            val s = steerAngleDeg / maxWheelDeg
            game.input.steer = s * (0.55f + 0.45f * abs(s))   // courbe progressive
        }
        throttle += (throttleTarget - throttle) * min(1f, dt * 6f)
        brake += (brakeTarget - brake) * min(1f, dt * 10f)
        if (throttleTarget == 0f && throttle < 0.02f) throttle = 0f
        if (brakeTarget == 0f && brake < 0.02f) brake = 0f
        game.input.throttle = throttle
        game.input.brake = brake
    }

    private fun panel(c: Canvas, r: RectF, radius: Float = 12 * dp, color: Int = panelBg) {
        fill.color = color
        c.drawRoundRect(r, radius, radius, fill)
    }

    private fun drawTopLeft(c: Canvas) {
        iconButton(c, btnJobs, "jobs", overlay == Overlay.JOBS)
        iconButton(c, btnCam, "cam", false)
        iconButton(c, btnMap, "map", overlay == Overlay.MAP)
        iconButton(c, btnOpt, "opt", overlay == Overlay.OPTIONS)

        // argent + livraison en cours
        val top = btnJobs.bottom + 10 * dp
        val j = game.job
        val r = RectF(12 * dp, top, 12 * dp + min(W * 0.34f, 360 * dp), top + if (j != null) 92 * dp else 40 * dp)
        panel(c, r)
        text.textSize = 17 * dp; text.textAlign = Paint.Align.LEFT
        text.color = accent
        c.drawText("%,d €".format(game.money).replace(',', ' '), r.left + 12 * dp, r.top + 27 * dp, text)
        text.color = Color.LTGRAY; text.textSize = 13 * dp; text.textAlign = Paint.Align.RIGHT
        c.drawText("${game.deliveries} livraison${if (game.deliveries > 1) "s" else ""}", r.right - 12 * dp, r.top + 26 * dp, text)
        if (j != null) {
            text.textAlign = Paint.Align.LEFT
            text.color = Color.WHITE; text.textSize = 14 * dp
            c.drawText(ellipsize(j.offer.cargo, r.width() - 24 * dp), r.left + 12 * dp, r.top + 50 * dp, text)
            val phase = when (j.phase) {
                ActiveJob.Phase.TO_PICKUP -> "Chargement : "
                ActiveJob.Phase.LOADING -> "Chargement en cours…"
                ActiveJob.Phase.TO_DROP -> "Livraison : "
                ActiveJob.Phase.UNLOADING -> "Déchargement en cours…"
            }
            val dest = if (j.phase == ActiveJob.Phase.TO_PICKUP || j.phase == ActiveJob.Phase.TO_DROP) j.target.name else ""
            text.color = Color.LTGRAY; text.textSize = 13 * dp
            c.drawText(ellipsize(phase + dest, r.width() - 24 * dp), r.left + 12 * dp, r.top + 70 * dp, text)
            val left = j.offer.timeLimit - j.elapsed
            val started = j.phase == ActiveJob.Phase.TO_DROP || j.phase == ActiveJob.Phase.UNLOADING
            val t = if (!started) "délai %d:%02d après chargement".format((left / 60).toInt(), (left % 60).toInt())
                else if (left >= 0) "%d:%02d".format((left / 60).toInt(), (left % 60).toInt()) else "en retard"
            text.color = if (left >= 0) Color.WHITE else Color.rgb(255, 90, 80)
            c.drawText("⏱ $t", r.left + 12 * dp, r.top + 86 * dp, text)
            if (j.phase == ActiveJob.Phase.LOADING || j.phase == ActiveJob.Phase.UNLOADING) {
                val p = 1f - j.timer / 4f
                fill.color = accent
                c.drawRect(r.left + 100 * dp, r.top + 80 * dp, r.left + 100 * dp + (r.width() - 112 * dp) * p, r.top + 85 * dp, fill)
            }
        }
    }

    private fun iconButton(c: Canvas, r: RectF, icon: String, active: Boolean) {
        panel(c, r, 10 * dp, if (active) Color.argb(230, 200, 130, 20) else panelBg)
        stroke.color = Color.WHITE; stroke.strokeWidth = 2.2f * dp
        fill.color = Color.WHITE
        val cx = r.centerX(); val cy = r.centerY(); val s = r.width() * 0.22f
        when (icon) {
            "jobs" -> { // carton
                c.drawRect(cx - s, cy - s * 0.7f, cx + s, cy + s * 0.9f, stroke)
                c.drawLine(cx - s, cy - s * 0.1f, cx + s, cy - s * 0.1f, stroke)
                c.drawLine(cx, cy - s * 0.7f, cx, cy - s * 0.1f, stroke)
            }
            "cam" -> {
                c.drawRoundRect(cx - s, cy - s * 0.6f, cx + s * 0.5f, cy + s * 0.6f, 3 * dp, 3 * dp, stroke)
                val p = Path(); p.moveTo(cx + s * 0.5f, cy); p.lineTo(cx + s * 1.1f, cy - s * 0.5f); p.lineTo(cx + s * 1.1f, cy + s * 0.5f); p.close()
                c.drawPath(p, fill)
            }
            "map" -> {
                val p = Path()
                p.moveTo(cx - s, cy - s * 0.7f); p.lineTo(cx - s * 0.33f, cy - s); p.lineTo(cx + s * 0.33f, cy - s * 0.7f)
                p.lineTo(cx + s, cy - s); p.lineTo(cx + s, cy + s * 0.7f); p.lineTo(cx + s * 0.33f, cy + s)
                p.lineTo(cx - s * 0.33f, cy + s * 0.7f); p.lineTo(cx - s, cy + s); p.close()
                c.drawPath(p, stroke)
            }
            "opt" -> {
                c.drawCircle(cx, cy, s * 0.45f, stroke)
                for (k in 0 until 8) {
                    val a = k * PI.toFloat() / 4
                    c.drawLine(cx + cos(a) * s * 0.7f, cy + sin(a) * s * 0.7f, cx + cos(a) * s, cy + sin(a) * s, stroke)
                }
            }
        }
    }

    private fun drawGps(c: Canvas) {
        val r = gpsR
        val v = game.vehicle
        c.save()
        c.clipPath(gpsClip)
        fill.color = Color.rgb(20, 26, 34)
        c.drawRect(r, fill)
        // zoom selon la vitesse (comme dans ETS)
        val ppm = (r.height() / (260f + v.speedKmh * 5f)).coerceAtLeast(0.25f)
        val ax = r.centerX(); val ay = r.top + r.height() * 0.66f
        c.translate(ax, ay)
        c.rotate(-Math.toDegrees(v.yaw.toDouble()).toFloat())
        c.scale(ppm, ppm)
        c.translate(-v.x, -v.z)
        val radius = hypot(r.width(), r.height()) / ppm
        map.draw(c, ppm, v.x, v.z, radius, game.route)
        game.job?.let { j -> map.marker(c, j.target.x, j.target.z, 9f / ppm, if (j.target === j.offer.from) Color.rgb(60, 180, 255) else accent) }
        c.restore()
        // flèche du joueur
        val p = Path()
        val s = 11 * dp
        p.moveTo(ax, ay - s); p.lineTo(ax + s * 0.75f, ay + s * 0.8f); p.lineTo(ax, ay + s * 0.35f); p.lineTo(ax - s * 0.75f, ay + s * 0.8f); p.close()
        fill.color = Color.BLACK; stroke.color = Color.BLACK; stroke.strokeWidth = 3 * dp
        c.drawPath(p, stroke)
        fill.color = accent
        c.drawPath(p, fill)
        stroke.color = Color.argb(160, 255, 255, 255); stroke.strokeWidth = 1.5f * dp
        c.drawRoundRect(r, 14 * dp, 14 * dp, stroke)
        // distance restante
        if (game.route != null) {
            val d = game.routeRemaining
            val t = if (d >= 1000) "%.1f km".format(d / 1000f) else "${(d / 10).roundToInt() * 10} m"
            val tr = RectF(r.left + 8 * dp, r.bottom - 30 * dp, r.left + 92 * dp, r.bottom - 8 * dp)
            panel(c, tr, 8 * dp, Color.argb(200, 0, 0, 0))
            text.textSize = 13 * dp; text.color = Color.WHITE; text.textAlign = Paint.Align.CENTER
            c.drawText(t, tr.centerX(), tr.bottom - 6 * dp, text)
        }
        // boussole
        c.save()
        c.translate(r.right - 20 * dp, r.top + 20 * dp)
        c.rotate(-Math.toDegrees(v.yaw.toDouble()).toFloat())
        text.textSize = 12 * dp; text.color = Color.rgb(255, 90, 80); text.textAlign = Paint.Align.CENTER
        c.drawText("N", 0f, 4 * dp, text)
        c.restore()
    }

    private fun drawSpeed(c: Canvas) {
        val v = game.vehicle
        val x = gpsR.left; val y = gpsR.bottom + 10 * dp
        val r = RectF(x, y, gpsR.right, y + 64 * dp)
        panel(c, r)
        // panneau de limitation
        val cx = r.left + 34 * dp; val cy = r.centerY(); val rad = 24 * dp
        fill.color = Color.WHITE; c.drawCircle(cx, cy, rad, fill)
        stroke.color = Color.rgb(205, 30, 30); stroke.strokeWidth = 5 * dp
        c.drawCircle(cx, cy, rad - 3 * dp, stroke)
        text.color = Color.BLACK; text.textSize = (if (game.speedLimit >= 100) 15 else 18) * dp; text.textAlign = Paint.Align.CENTER
        c.drawText("${game.speedLimit}", cx, cy + 6 * dp, text)
        // vitesse
        val kmh = v.speedKmh.roundToInt()
        val over = game.overSpeedTime > 1f
        text.color = if (over) Color.rgb(255, 80, 70) else Color.WHITE
        text.textSize = 34 * dp; text.textAlign = Paint.Align.RIGHT
        c.drawText("$kmh", r.left + 140 * dp, cy + 12 * dp, text)
        text.textSize = 13 * dp; text.textAlign = Paint.Align.LEFT; text.color = Color.LTGRAY
        c.drawText("km/h", r.left + 144 * dp, cy + 12 * dp, text)
        // rapport et compte-tours
        val gear = if (v.reverse) "R" else "D${v.gear}"
        text.textSize = 18 * dp; text.color = accent; text.textAlign = Paint.Align.RIGHT
        c.drawText(gear, r.right - 12 * dp, cy - 2 * dp, text)
        val rpmW = r.right - 12 * dp - (r.left + 190 * dp)
        if (rpmW > 20 * dp) {
            val f = ((v.rpm - 800f) / 5300f).coerceIn(0f, 1f)
            fill.color = Color.argb(90, 255, 255, 255)
            c.drawRect(r.left + 190 * dp, cy + 8 * dp, r.right - 12 * dp, cy + 13 * dp, fill)
            fill.color = if (v.rpm > 5500) Color.rgb(255, 80, 60) else accent
            c.drawRect(r.left + 190 * dp, cy + 8 * dp, r.left + 190 * dp + rpmW * f, cy + 13 * dp, fill)
        }
    }

    private fun drawStreet(c: Canvas) {
        val name = game.streetName
        if (name.isEmpty()) return
        text.textSize = 15 * dp; text.textAlign = Paint.Align.CENTER
        val w = text.measureText(name) + 28 * dp
        val r = RectF(W / 2 - w / 2, 12 * dp, W / 2 + w / 2, 44 * dp)
        panel(c, r, 16 * dp)
        text.color = Color.WHITE
        c.drawText(name, W / 2, r.bottom - 10 * dp, text)
    }

    private fun drawMessage(c: Canvas) {
        if (game.messageTime <= 0f || game.message.isEmpty()) return
        val a = (min(1f, game.messageTime) * 255).toInt()
        text.textSize = 18 * dp; text.textAlign = Paint.Align.CENTER
        val w = min(W * 0.55f, text.measureText(game.message) + 40 * dp)
        val r = RectF(W / 2 - w / 2, H * 0.28f, W / 2 + w / 2, H * 0.28f + 42 * dp)
        panel(c, r, 12 * dp, Color.argb((a * 0.8f).toInt(), 30, 30, 30))
        fill.color = Color.argb(a, 255, 176, 32)
        c.drawRect(r.left, r.top + 8 * dp, r.left + 4 * dp, r.bottom - 8 * dp, fill)
        text.color = Color.argb(a, 255, 255, 255)
        c.drawText(ellipsize(game.message, w - 30 * dp), W / 2, r.bottom - 14 * dp, text)
    }

    private fun drawWheel(c: Canvas) {
        val cx = wheelC[0]; val cy = wheelC[1]; val r = wheelR
        c.save()
        c.rotate(steerAngleDeg, cx, cy)
        stroke.color = Color.argb(150, 10, 10, 12); stroke.strokeWidth = r * 0.22f
        c.drawCircle(cx, cy, r * 0.86f, stroke)
        stroke.color = Color.argb(200, 235, 235, 235); stroke.strokeWidth = r * 0.04f
        c.drawCircle(cx, cy, r * 0.97f, stroke)
        c.drawCircle(cx, cy, r * 0.75f, stroke)
        stroke.color = Color.argb(160, 10, 10, 12); stroke.strokeWidth = r * 0.16f
        c.drawLine(cx - r * 0.75f, cy, cx - r * 0.25f, cy, stroke)
        c.drawLine(cx + r * 0.25f, cy, cx + r * 0.75f, cy, stroke)
        c.drawLine(cx, cy + r * 0.25f, cx, cy + r * 0.75f, stroke)
        fill.color = accent
        c.drawRect(cx - r * 0.05f, cy - r * 0.97f, cx + r * 0.05f, cy - r * 0.75f, fill)
        c.restore()
        // moyeu = klaxon (losange Renault)
        fill.color = if (game.input.horn) Color.argb(220, 200, 130, 20) else Color.argb(170, 15, 15, 18)
        c.drawCircle(cx, cy, r * 0.26f, fill)
        val p = Path()
        val s = r * 0.13f
        p.moveTo(cx, cy - s * 1.3f); p.lineTo(cx + s * 0.8f, cy); p.lineTo(cx, cy + s * 1.3f); p.lineTo(cx - s * 0.8f, cy); p.close()
        stroke.color = Color.rgb(220, 220, 225); stroke.strokeWidth = r * 0.05f
        c.drawPath(p, stroke)
    }

    private fun drawTilt(c: Canvas) {
        val cx = wheelC[0]; val cy = wheelC[1] + wheelR * 0.5f
        val w = wheelR * 1.6f
        fill.color = panelBg
        c.drawRoundRect(cx - w / 2, cy - 14 * dp, cx + w / 2, cy + 14 * dp, 14 * dp, 14 * dp, fill)
        fill.color = accent
        val x = cx + game.input.steer * (w / 2 - 12 * dp)
        c.drawCircle(x, cy, 10 * dp, fill)
        // klaxon
        fill.color = if (game.input.horn) Color.argb(220, 200, 130, 20) else panelBg
        c.drawCircle(wheelC[0], wheelC[1] - wheelR * 0.2f, wheelR * 0.3f, fill)
        text.textSize = 12 * dp; text.color = Color.WHITE; text.textAlign = Paint.Align.CENTER
        c.drawText("KLAXON", wheelC[0], wheelC[1] - wheelR * 0.2f + 4 * dp, text)
    }

    private fun drawPedals(c: Canvas) {
        pedal(c, throttleR, throttle, "")
        pedal(c, brakeR, brake, "")
        // sélecteur D / R
        panel(c, gearR, 10 * dp, if (game.reverseSelected) Color.argb(220, 190, 40, 40) else panelBg)
        text.textSize = 20 * dp; text.textAlign = Paint.Align.CENTER; text.color = Color.WHITE
        c.drawText(if (game.reverseSelected) "R" else "D", gearR.centerX(), gearR.centerY() + 7 * dp, text)
    }

    private fun pedal(c: Canvas, r: RectF, value: Float, label: String) {
        val inset = value * 4 * dp
        val rr = RectF(r.left + inset, r.top + inset, r.right - inset, r.bottom - inset)
        fill.shader = pedalShaders.getOrPut(r) {
            LinearGradient(0f, r.top, 0f, r.bottom, Color.argb(200, 70, 72, 78), Color.argb(200, 30, 31, 35), Shader.TileMode.CLAMP)
        }
        c.drawRoundRect(rr, 10 * dp, 10 * dp, fill)
        fill.shader = null
        stroke.color = Color.argb(140, 0, 0, 0); stroke.strokeWidth = 3 * dp
        val n = ((rr.height() / (14 * dp)).toInt()).coerceAtLeast(2)
        for (k in 1 until n) {
            val y = rr.top + rr.height() * k / n
            c.drawLine(rr.left + 10 * dp, y, rr.right - 10 * dp, y, stroke)
        }
        stroke.color = if (value > 0.01f) accent else Color.argb(120, 255, 255, 255); stroke.strokeWidth = 2 * dp
        c.drawRoundRect(rr, 10 * dp, 10 * dp, stroke)
    }

    // ------------------------------------------------------------------------ panneaux
    private fun overlayFrame(c: Canvas, title: String) {
        fill.color = Color.argb(120, 0, 0, 0)
        c.drawRect(0f, 0f, W, H, fill)
        panel(c, panelR, 16 * dp, Color.argb(240, 24, 28, 36))
        fill.color = accent
        c.drawRect(panelR.left, panelR.top + 16 * dp, panelR.left + 5 * dp, panelR.top + 44 * dp, fill)
        text.textSize = 21 * dp; text.color = Color.WHITE; text.textAlign = Paint.Align.LEFT
        c.drawText(title, panelR.left + 20 * dp, panelR.top + 38 * dp, text)
        panelButtons.clear()
        val close = RectF(panelR.right - 50 * dp, panelR.top + 12 * dp, panelR.right - 14 * dp, panelR.top + 48 * dp)
        button(c, close, "✕", false) { overlay = Overlay.NONE }
    }

    private fun button(c: Canvas, r: RectF, label: String, primary: Boolean, action: () -> Unit) {
        val pressed = pressedButton === r || (pressedButton != null && pressedButton == r)
        panel(c, r, 8 * dp, when {
            pressed -> Color.rgb(255, 210, 120)
            primary -> accent
            else -> Color.argb(255, 60, 66, 78)
        })
        text.textSize = 15 * dp; text.textAlign = Paint.Align.CENTER
        text.color = if (primary) Color.BLACK else Color.WHITE
        c.drawText(label, r.centerX(), r.centerY() + 5 * dp, text)
        panelButtons.add(r to action)
    }

    private fun drawJobs(c: Canvas) {
        overlayFrame(c, "Carnet de livraisons")
        val j = game.job
        var y = panelR.top + 64 * dp
        val x0 = panelR.left + 20 * dp; val x1 = panelR.right - 20 * dp
        if (j != null) {
            text.textSize = 16 * dp; text.color = Color.WHITE; text.textAlign = Paint.Align.LEFT
            c.drawText("Livraison en cours : ${j.offer.cargo}", x0, y + 20 * dp, text)
            text.color = Color.LTGRAY; text.textSize = 14 * dp
            c.drawText("De : ${j.offer.from.name}", x0, y + 46 * dp, text)
            c.drawText("À : ${j.offer.to.name}", x0, y + 68 * dp, text)
            c.drawText("Rémunération : ${j.offer.pay} € (+15 % si à l'heure)", x0, y + 90 * dp, text)
            button(c, RectF(x0, y + 110 * dp, x0 + 200 * dp, y + 150 * dp), "Annuler la livraison", false) {
                game.post { game.cancelJob() }
                overlay = Overlay.NONE
            }
            return
        }
        val offers = game.offers
        if (offers.isEmpty()) {
            text.textSize = 15 * dp; text.color = Color.LTGRAY; text.textAlign = Paint.Align.LEFT
            c.drawText("Aucune offre pour le moment.", x0, y + 20 * dp, text)
            return
        }
        val rowH = min(62 * dp, (panelR.bottom - y - 16 * dp) / offers.size)
        for (o in offers) {
            drawOffer(c, o, x0, y, x1, rowH)
            y += rowH
        }
    }

    private fun drawOffer(c: Canvas, o: JobOffer, x0: Float, y: Float, x1: Float, h: Float) {
        stroke.color = Color.argb(60, 255, 255, 255); stroke.strokeWidth = 1 * dp
        c.drawLine(x0, y + h, x1, y + h, stroke)
        val bw = 110 * dp
        text.textAlign = Paint.Align.LEFT
        text.textSize = 15 * dp; text.color = Color.WHITE
        c.drawText(ellipsize(o.cargo, x1 - x0 - bw - 120 * dp), x0, y + h * 0.40f, text)
        text.textSize = 13 * dp; text.color = Color.LTGRAY
        c.drawText(ellipsize("${o.from.name}  →  ${o.to.name}", x1 - x0 - bw - 20 * dp), x0, y + h * 0.78f, text)
        text.textAlign = Paint.Align.RIGHT; text.textSize = 15 * dp; text.color = accent
        c.drawText("${o.pay} €", x1 - bw - 14 * dp, y + h * 0.40f, text)
        text.textSize = 12 * dp; text.color = Color.LTGRAY
        c.drawText("%.1f km".format(o.distance / 1000f), x1 - bw - 14 * dp, y + h * 0.78f, text)
        button(c, RectF(x1 - bw, y + h * 0.18f, x1, y + h * 0.82f), "Accepter", true) {
            game.post { game.accept(o) }
            overlay = Overlay.NONE
        }
    }

    private fun drawBigMap(c: Canvas) {
        overlayFrame(c, "Carte de Rochetoirin")
        val r = RectF(panelR.left + 14 * dp, panelR.top + 58 * dp, panelR.right - 14 * dp, panelR.bottom - 14 * dp)
        val w = game.world
        val ppm = min(r.width() / (w.maxX - w.minX), r.height() / (w.maxZ - w.minZ))
        c.save()
        c.clipRect(r)
        fill.color = Color.rgb(20, 26, 34); c.drawRect(r, fill)
        c.translate(r.centerX(), r.centerY())
        c.scale(ppm, ppm)
        c.translate(-(w.minX + w.maxX) / 2, -(w.minZ + w.maxZ) / 2)
        map.draw(c, ppm, 0f, 0f, 1e6f, game.route)
        game.job?.let { j ->
            map.marker(c, j.offer.from.x, j.offer.from.z, 7f / ppm, Color.rgb(60, 180, 255))
            map.marker(c, j.offer.to.x, j.offer.to.z, 7f / ppm, accent)
        }
        val v = game.vehicle
        c.save()
        c.translate(v.x, v.z); c.rotate(Math.toDegrees(v.yaw.toDouble()).toFloat()); c.scale(1 / ppm, 1 / ppm)
        val p = Path(); val s = 10 * dp
        p.moveTo(0f, -s); p.lineTo(s * 0.75f, s * 0.8f); p.lineTo(0f, s * 0.35f); p.lineTo(-s * 0.75f, s * 0.8f); p.close()
        fill.color = accent; c.drawPath(p, fill)
        c.restore()
        c.restore()
        text.textSize = 12 * dp; text.color = Color.LTGRAY; text.textAlign = Paint.Align.RIGHT
        c.drawText("Données : © OpenStreetMap, IGN (RGE ALTI, BD TOPO, RPG)", r.right - 6 * dp, r.bottom - 6 * dp, text)
    }

    private fun drawOptions(c: Canvas) {
        overlayFrame(c, "Options")
        val x0 = panelR.left + 20 * dp
        var y = panelR.top + 70 * dp
        val bw = min(panelR.width() - 40 * dp, 420 * dp)
        button(c, RectF(x0, y, x0 + bw, y + 46 * dp), "Direction : " + if (settings.tiltSteering) "inclinaison du téléphone" else "volant tactile", false) {
            settings.tiltSteering = !settings.tiltSteering
        }
        y += 58 * dp
        button(c, RectF(x0, y, x0 + bw, y + 46 * dp), "Son moteur : " + if (settings.sound) "activé" else "coupé", false) {
            settings.sound = !settings.sound
        }
        y += 58 * dp
        button(c, RectF(x0, y, x0 + bw, y + 46 * dp), "Graphismes : " + if (settings.highGraphics) "élevés (ombres, herbe 3D)" else "standard", false) {
            settings.highGraphics = !settings.highGraphics
        }
        y += 58 * dp
        button(c, RectF(x0, y, x0 + bw, y + 46 * dp), "Replacer le véhicule sur la route", false) {
            game.post { respawn() }
            overlay = Overlay.NONE
        }
        y += 58 * dp
        button(c, RectF(x0, y, x0 + bw, y + 46 * dp), "Retour à la mairie de Rochetoirin", false) {
            game.post { val s = game.world.start; game.vehicle.place(s.x, s.z, game.vehicle.yaw) }
            overlay = Overlay.NONE
        }
        text.textSize = 12 * dp; text.color = Color.GRAY; text.textAlign = Paint.Align.LEFT
        c.drawText("Glissez au centre de l'écran pour tourner la caméra.", x0, panelR.bottom - 36 * dp, text)
        c.drawText("IGN : RGE ALTI, BD TOPO, RPG 2025 — Routes : © contributeurs OpenStreetMap", x0, panelR.bottom - 16 * dp, text)
    }

    /** Replace le véhicule sur le nœud routier le plus proche, dans l'axe de la route. */
    private fun respawn() {
        val w = game.world
        val v = game.vehicle
        val hit = fr.rochetoirin.sim.world.RoadHit()
        var r = 40f
        while (r < 2000f) {
            for (k in 0 until 16) {
                val a = k * PI.toFloat() / 8
                w.nearestRoad(v.x + cos(a) * r * 0.5f, v.z + sin(a) * r * 0.5f, hit)
                if (hit.way != null) {
                    val n = hit.way!!.nodes[hit.seg]
                    v.place(w.nodeX[n], w.nodeZ[n], atan2(hit.dirX, -hit.dirZ))
                    return
                }
            }
            r *= 1.6f
        }
    }

    private fun ellipsize(s: String, maxW: Float): String {
        if (text.measureText(s) <= maxW) return s
        var e = s
        while (e.length > 1 && text.measureText("$e…") > maxW) e = e.dropLast(1)
        return "$e…"
    }

    // ============================================================================ tactile
    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(e: MotionEvent): Boolean {
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> {
                val i = e.actionIndex
                down(e.getPointerId(i), e.getX(i), e.getY(i))
            }
            MotionEvent.ACTION_MOVE -> for (i in 0 until e.pointerCount) move(e.getPointerId(i), e.getX(i), e.getY(i))
            MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP -> {
                val i = e.actionIndex
                up(e.getPointerId(i), e.getX(i), e.getY(i))
            }
            MotionEvent.ACTION_CANCEL -> for (i in 0 until e.pointerCount) up(e.getPointerId(i), -1f, -1f)
        }
        return true
    }

    private fun down(id: Int, x: Float, y: Float) {
        lastX[id] = x; lastY[id] = y
        if (overlay != Overlay.NONE) {
            pressedButton = panelButtons.firstOrNull { it.first.contains(x, y) }?.first
            roles[id] = Role.PANEL
            return
        }
        val dw = hypot(x - wheelC[0], y - wheelC[1])
        val role = when {
            btnJobs.contains(x, y) || btnCam.contains(x, y) || btnMap.contains(x, y) || btnOpt.contains(x, y) || gearR.contains(x, y) -> Role.BUTTON
            gpsR.contains(x, y) -> Role.BUTTON
            expanded(throttleR, 10 * dp).contains(x, y) -> Role.THROTTLE
            expanded(brakeR, 10 * dp).contains(x, y) -> Role.BRAKE
            !settings.tiltSteering && dw < wheelR * 0.27f -> Role.HORN
            settings.tiltSteering && hypot(x - wheelC[0], y - (wheelC[1] - wheelR * 0.2f)) < wheelR * 0.35f -> Role.HORN
            !settings.tiltSteering && dw < wheelR * 1.45f -> Role.STEER
            else -> Role.ORBIT
        }
        roles[id] = role
        when (role) {
            Role.STEER -> { steering = true; steerTouchAngle = angle(x, y) }
            Role.HORN -> game.input.horn = true
            Role.THROTTLE -> throttleTarget = pedalValue(throttleR, y)
            Role.BRAKE -> brakeTarget = pedalValue(brakeR, y)
            else -> {}
        }
    }

    private fun move(id: Int, x: Float, y: Float) {
        val px = lastX[id] ?: x; val py = lastY[id] ?: y
        lastX[id] = x; lastY[id] = y
        when (roles[id]) {
            Role.STEER -> {
                val a = angle(x, y)
                var d = a - steerTouchAngle
                while (d > 180f) d -= 360f
                while (d < -180f) d += 360f
                steerTouchAngle = a
                // près du centre, l'angle est instable : on l'atténue
                val dist = hypot(x - wheelC[0], y - wheelC[1])
                if (dist > wheelR * 0.3f) steerAngleDeg = (steerAngleDeg + d).coerceIn(-maxWheelDeg, maxWheelDeg)
            }
            Role.THROTTLE -> throttleTarget = pedalValue(throttleR, y)
            Role.BRAKE -> brakeTarget = pedalValue(brakeR, y)
            Role.ORBIT -> { game.input.orbitDX += x - px; game.input.orbitDY += y - py }
            else -> {}
        }
    }

    private fun up(id: Int, x: Float, y: Float) {
        val role = roles.remove(id) ?: return
        when (role) {
            Role.STEER -> steering = roles.containsValue(Role.STEER)
            Role.HORN -> game.input.horn = false
            Role.THROTTLE -> throttleTarget = 0f
            Role.BRAKE -> brakeTarget = 0f
            Role.BUTTON -> when {
                btnJobs.contains(x, y) -> overlay = Overlay.JOBS
                btnCam.contains(x, y) -> game.camMode = (game.camMode + 1) % 3
                btnMap.contains(x, y) || gpsR.contains(x, y) -> overlay = Overlay.MAP
                btnOpt.contains(x, y) -> overlay = Overlay.OPTIONS
                gearR.contains(x, y) -> game.reverseSelected = !game.reverseSelected
            }
            Role.PANEL -> {
                val b = panelButtons.firstOrNull { it.first.contains(x, y) }
                if (b != null && b.first == pressedButton) b.second()
                else if (!panelR.contains(x, y) && x >= 0) overlay = Overlay.NONE
                pressedButton = null
            }
            else -> {}
        }
    }

    private fun expanded(r: RectF, m: Float) = RectF(r.left - m, r.top - m, r.right + m, r.bottom + m)

    private fun pedalValue(r: RectF, y: Float): Float = (0.35f + 0.65f * (r.bottom - y) / (r.height() * 0.75f)).coerceIn(0.35f, 1f)

    private fun angle(x: Float, y: Float) = Math.toDegrees(atan2((y - wheelC[1]).toDouble(), (x - wheelC[0]).toDouble())).toFloat()
}
