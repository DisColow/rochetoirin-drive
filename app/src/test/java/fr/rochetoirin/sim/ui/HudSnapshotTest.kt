package fr.rochetoirin.sim.ui

import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.View
import androidx.test.core.app.ApplicationProvider
import fr.rochetoirin.sim.game.Game
import fr.rochetoirin.sim.game.Persistence
import fr.rochetoirin.sim.world.World
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File
import java.io.FileOutputStream

/** Rend l'interface (HUD) dans une image, pour vérifier la mise en page sans appareil. */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [33], qualifiers = "w872dp-h392dp-land-xxhdpi")
class HudSnapshotTest {
    private fun snapshot(name: String, prep: (Game, HudView) -> Unit) {
        val world = World { File("src/main/assets", it).inputStream() }
        val game = Game(world, 1240, 7, object : Persistence { override fun save(money: Int, deliveries: Int) {} })
        val settings = object : HudView.Settings {
            override var tiltSteering = false
            override var sound = true
            override fun tiltValue() = 0f
        }
        val hud = HudView(ApplicationProvider.getApplicationContext(), game, settings)
        val w = 2400; val h = 1080
        hud.measure(View.MeasureSpec.makeMeasureSpec(w, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(h, View.MeasureSpec.EXACTLY))
        hud.layout(0, 0, w, h)
        prep(game, hud)
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        hud.draw(Canvas(bmp))
        File("build/hud").mkdirs()
        FileOutputStream("build/hud/$name.png").use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }

    @Test
    fun driving() = snapshot("driving") { g, _ ->
        g.accept(g.offers.first())
        g.input.throttle = 0.6f
        repeat(60 * 4) { g.update(1f / 60f) }
        println("CAR %.2f %.2f %.2f %.4f".format(java.util.Locale.ROOT, g.vehicle.x, g.vehicle.y, g.vehicle.z, g.vehicle.yaw))
    }

    @Test
    fun jobsMenu() = snapshot("jobs") { _, hud ->
        val f = HudView::class.java.getDeclaredField("overlay"); f.isAccessible = true
        val e = f.type.enumConstants.first { it.toString() == "JOBS" }
        f.set(hud, e)
    }

    @Test
    fun bigMap() = snapshot("map") { g, hud ->
        g.accept(g.offers.first())
        g.update(0.016f)
        val f = HudView::class.java.getDeclaredField("overlay"); f.isAccessible = true
        f.set(hud, f.type.enumConstants.first { it.toString() == "MAP" })
    }
}
