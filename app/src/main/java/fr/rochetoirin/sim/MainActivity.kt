package fr.rochetoirin.sim

import android.app.Activity
import android.content.Context
import android.graphics.Color
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.opengl.GLSurfaceView
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.Surface
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.TextView
import fr.rochetoirin.sim.audio.EngineSound
import fr.rochetoirin.sim.game.Game
import fr.rochetoirin.sim.game.Persistence
import fr.rochetoirin.sim.render.Renderer
import fr.rochetoirin.sim.ui.HudView
import fr.rochetoirin.sim.world.World
import javax.microedition.khronos.egl.EGL10
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.egl.EGLDisplay
import kotlin.concurrent.thread
import kotlin.math.atan2

class MainActivity : Activity(), SensorEventListener, HudView.Settings {
    private lateinit var root: FrameLayout
    private lateinit var loading: TextView
    private var glView: GLSurfaceView? = null
    private var game: Game? = null
    private val engine = EngineSound()
    private val handler = Handler(Looper.getMainLooper())
    private var sensors: SensorManager? = null
    @Volatile private var tilt = 0f

    private val prefs by lazy { getSharedPreferences("rochetoirin", Context.MODE_PRIVATE) }

    override var tiltSteering: Boolean
        get() = prefs.getBoolean("tilt", false)
        set(v) { prefs.edit().putBoolean("tilt", v).apply(); updateSensors() }
    override var sound: Boolean
        get() = prefs.getBoolean("sound", true)
        set(v) { prefs.edit().putBoolean("sound", v).apply(); engine.enabled = v }

    override var highGraphics: Boolean
        get() = prefs.getBoolean("hiGfx", true)
        set(v) { prefs.edit().putBoolean("hiGfx", v).apply(); renderer?.highQuality = v }
    private var renderer: Renderer? = null

    override fun tiltValue() = tilt

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        root = FrameLayout(this)
        root.setBackgroundColor(Color.rgb(20, 24, 30))
        loading = TextView(this).apply {
            text = "Rochetoirin Simulator\n\nChargement du relief et des routes…"
            setTextColor(Color.WHITE)
            textSize = 20f
            gravity = Gravity.CENTER
        }
        root.addView(loading, FrameLayout.LayoutParams(-1, -1))
        setContentView(root)
        hideSystemUi()
        sensors = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        engine.enabled = sound

        thread(name = "load") {
            val world = World { assets.open(it) }
            val g = Game(world, prefs.getInt("money", 0), prefs.getInt("deliveries", 0), object : Persistence {
                override fun save(money: Int, deliveries: Int) {
                    prefs.edit().putInt("money", money).putInt("deliveries", deliveries).apply()
                }
            })
            handler.post { start(g) }
        }
    }

    private fun start(g: Game) {
        game = g
        val gl = GLSurfaceView(this)
        gl.setEGLContextClientVersion(3)
        gl.setEGLConfigChooser(MsaaChooser())
        gl.preserveEGLContextOnPause = true
        val r = Renderer(g, { assets.open(it) }) { handler.post { loading.visibility = View.GONE } }
        r.highQuality = highGraphics
        renderer = r
        gl.setRenderer(r)
        glView = gl
        root.addView(gl, 0, FrameLayout.LayoutParams(-1, -1))
        root.addView(HudView(this, g, this), 1, FrameLayout.LayoutParams(-1, -1))
        engine.start()
        handler.post(soundTick)
        updateSensors()
    }

    private val soundTick = object : Runnable {
        override fun run() {
            game?.let { g ->
                val v = g.vehicle
                engine.rpm = v.rpm
                engine.load = v.throttleOut
                engine.speed = kotlin.math.abs(v.speed)
                engine.horn = g.input.horn
                engine.offRoad = !v.onRoad
                if (g.impact > 0f) { engine.bump = g.impact; g.impact = 0f }
            }
            handler.postDelayed(this, 30)
        }
    }

    override fun onResume() {
        super.onResume()
        glView?.onResume()
        hideSystemUi()
        if (game != null) engine.start()
        updateSensors()
    }

    override fun onPause() {
        super.onPause()
        glView?.onPause()
        engine.stop()
        sensors?.unregisterListener(this)
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) hideSystemUi()
    }

    @Suppress("DEPRECATION")
    private fun hideSystemUi() {
        if (Build.VERSION.SDK_INT >= 30) {
            window.setDecorFitsSystemWindows(false)
            window.insetsController?.let {
                it.hide(WindowInsets.Type.statusBars() or WindowInsets.Type.navigationBars())
                it.systemBarsBehavior = WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            }
        } else {
            window.decorView.systemUiVisibility = (View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or View.SYSTEM_UI_FLAG_FULLSCREEN
                or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or View.SYSTEM_UI_FLAG_LAYOUT_STABLE)
        }
    }

    // --- direction par inclinaison ---
    private fun updateSensors() {
        val sm = sensors ?: return
        sm.unregisterListener(this)
        if (tiltSteering) {
            sm.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)?.let { sm.registerListener(this, it, SensorManager.SENSOR_DELAY_GAME) }
        }
    }

    @Suppress("DEPRECATION")
    override fun onSensorChanged(e: SensorEvent) {
        val rot = windowManager.defaultDisplay.rotation
        val gx = e.values[0]; val gy = e.values[1]
        // angle de « volant » du téléphone tenu à l'horizontale
        var a = Math.toDegrees(atan2(gy.toDouble(), gx.toDouble())).toFloat()
        if (rot == Surface.ROTATION_270) a = -Math.toDegrees(atan2(-gy.toDouble(), -gx.toDouble())).toFloat()
        val s = (a / 28f).coerceIn(-1f, 1f)
        tilt += (s - tilt) * 0.35f
    }

    override fun onAccuracyChanged(s: Sensor?, a: Int) {}

    /** Choisit une configuration EGL avec anticrénelage 4x si possible. */
    private class MsaaChooser : GLSurfaceView.EGLConfigChooser {
        override fun chooseConfig(egl: EGL10, display: EGLDisplay): EGLConfig {
            val es3 = 0x40 // EGL_OPENGL_ES3_BIT_KHR
            val attempts = listOf(
                intArrayOf(EGL10.EGL_RED_SIZE, 8, EGL10.EGL_GREEN_SIZE, 8, EGL10.EGL_BLUE_SIZE, 8, EGL10.EGL_DEPTH_SIZE, 24,
                    EGL10.EGL_RENDERABLE_TYPE, es3, EGL10.EGL_SAMPLE_BUFFERS, 1, EGL10.EGL_SAMPLES, 4, EGL10.EGL_NONE),
                intArrayOf(EGL10.EGL_RED_SIZE, 8, EGL10.EGL_GREEN_SIZE, 8, EGL10.EGL_BLUE_SIZE, 8, EGL10.EGL_DEPTH_SIZE, 24,
                    EGL10.EGL_RENDERABLE_TYPE, es3, EGL10.EGL_NONE),
                intArrayOf(EGL10.EGL_RED_SIZE, 8, EGL10.EGL_GREEN_SIZE, 8, EGL10.EGL_BLUE_SIZE, 8, EGL10.EGL_DEPTH_SIZE, 16,
                    EGL10.EGL_RENDERABLE_TYPE, es3, EGL10.EGL_NONE),
            )
            for (a in attempts) {
                val n = IntArray(1)
                val cfg = arrayOfNulls<EGLConfig>(1)
                if (egl.eglChooseConfig(display, a, cfg, 1, n) && n[0] > 0 && cfg[0] != null) return cfg[0]!!
            }
            throw IllegalStateException("Aucune configuration OpenGL ES 3 disponible")
        }
    }
}
