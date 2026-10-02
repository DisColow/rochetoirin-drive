package fr.rochetoirin.sim.game

import android.view.KeyEvent
import kotlin.math.abs
import kotlin.math.max

/**
 * Manette (Bluetooth / USB) : stick gauche ou croix = direction, gâchette droite = gaz, gâchette gauche = frein
 * (boutons A / B pour les manettes sans gâchettes analogiques), Y = marche avant / arrière, LB = klaxon,
 * RB ou Select = caméra, stick droit = orbite de la caméra.
 */
class Gamepad(private val game: Game) {
    @Volatile var stickX = 0f; private set
    @Volatile var dpadLeft = false; private set
    @Volatile var dpadRight = false; private set
    @Volatile var throttle = 0f; private set
    @Volatile var brake = 0f; private set
    @Volatile var orbitX = 0f; private set
    @Volatile var orbitY = 0f; private set
    @Volatile private var lastUse = 0L
    private var rtAxis = 0f; private var ltAxis = 0f
    private var aBtn = false; private var bBtn = false

    /** Manette utilisée récemment (l'interface affiche alors son aide). */
    fun active(now: Long) = now - lastUse < 10_000L

    /** Direction analogique avec zone morte et courbe progressive (0 si le stick est au repos). */
    val analogSteer: Float
        get() {
            val s = stickX
            if (abs(s) < DEAD) return 0f
            val t = (abs(s) - DEAD) / (1f - DEAD) * Math.signum(s)
            return t * (0.45f + 0.55f * abs(t))
        }

    fun onAxes(x: Float, hatX: Float, rTrigger: Float, lTrigger: Float, rx: Float, ry: Float, now: Long) {
        stickX = x.coerceIn(-1f, 1f)
        dpadLeft = hatX < -0.5f; dpadRight = hatX > 0.5f
        rtAxis = rTrigger.coerceIn(0f, 1f); ltAxis = lTrigger.coerceIn(0f, 1f)
        orbitX = if (abs(rx) > DEAD) rx else 0f
        orbitY = if (abs(ry) > DEAD) ry else 0f
        refresh()
        if (abs(x) > DEAD || abs(hatX) > 0.5f || rTrigger > 0.05f || lTrigger > 0.05f || orbitX != 0f || orbitY != 0f) lastUse = now
    }

    /** Renvoie true si la touche est une commande de conduite. */
    fun onKey(code: Int, down: Boolean, repeat: Int, now: Long): Boolean {
        val first = down && repeat == 0
        when (code) {
            KeyEvent.KEYCODE_DPAD_LEFT -> dpadLeft = down
            KeyEvent.KEYCODE_DPAD_RIGHT -> dpadRight = down
            KeyEvent.KEYCODE_BUTTON_A, KeyEvent.KEYCODE_DPAD_UP -> aBtn = down
            KeyEvent.KEYCODE_BUTTON_B, KeyEvent.KEYCODE_BUTTON_X, KeyEvent.KEYCODE_DPAD_DOWN -> bBtn = down
            KeyEvent.KEYCODE_BUTTON_R2 -> rtAxis = if (down) 1f else 0f
            KeyEvent.KEYCODE_BUTTON_L2 -> ltAxis = if (down) 1f else 0f
            KeyEvent.KEYCODE_BUTTON_L1 -> game.input.horn = down
            KeyEvent.KEYCODE_BUTTON_Y -> if (first) game.reverseSelected = !game.reverseSelected
            KeyEvent.KEYCODE_BUTTON_R1, KeyEvent.KEYCODE_BUTTON_SELECT -> if (first) game.camMode = (game.camMode + 1) % 3
            else -> return false
        }
        refresh()
        lastUse = now
        return true
    }

    private fun refresh() {
        throttle = max(rtAxis, if (aBtn) 1f else 0f)
        brake = max(ltAxis, if (bBtn) 1f else 0f)
    }

    companion object {
        const val DEAD = 0.12f
    }
}
