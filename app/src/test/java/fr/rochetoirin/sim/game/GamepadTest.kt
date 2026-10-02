package fr.rochetoirin.sim.game

import android.view.KeyEvent
import fr.rochetoirin.sim.world.World
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class GamepadTest {
    private val game by lazy {
        Game(World { File("src/main/assets", it).inputStream() }, 0, 0, object : Persistence {
            override fun save(money: Int, deliveries: Int) {}
        })
    }

    @Test
    fun mapping() {
        val p = Gamepad(game)
        p.onAxes(0.05f, 0f, 0f, 0f, 0f, 0f, 1000L)
        assertEquals("zone morte", 0f, p.analogSteer, 1e-6f)
        p.onAxes(1f, 0f, 0.8f, 0f, 0f, 0f, 1000L)
        assertEquals(1f, p.analogSteer, 1e-4f)
        assertEquals(0.8f, p.throttle, 1e-6f)
        p.onAxes(-0.5f, 0f, 0f, 1f, 0f, 0f, 1000L)
        assertTrue(p.analogSteer < -0.1f && p.analogSteer > -0.5f)
        assertEquals(1f, p.brake, 1e-6f)
        assertTrue(p.active(5000L)); assertFalse(p.active(20_000L))
        // boutons : A = gaz, Y = marche arrière, croix = direction
        assertTrue(p.onKey(KeyEvent.KEYCODE_BUTTON_A, true, 0, 2000L))
        assertEquals(1f, p.throttle, 1e-6f)
        p.onKey(KeyEvent.KEYCODE_BUTTON_A, false, 0, 2000L)
        p.onAxes(0f, 0f, 0f, 0f, 0f, 0f, 2000L)
        assertEquals(0f, p.throttle, 1e-6f)
        assertFalse(game.reverseSelected)
        p.onKey(KeyEvent.KEYCODE_BUTTON_Y, true, 0, 2000L)
        p.onKey(KeyEvent.KEYCODE_BUTTON_Y, true, 1, 2000L)   // répétition : ignorée
        assertTrue(game.reverseSelected)
        p.onKey(KeyEvent.KEYCODE_DPAD_LEFT, true, 0, 2000L)
        assertTrue(p.dpadLeft)
        assertFalse(p.onKey(KeyEvent.KEYCODE_VOLUME_UP, true, 0, 2000L))
    }
}
