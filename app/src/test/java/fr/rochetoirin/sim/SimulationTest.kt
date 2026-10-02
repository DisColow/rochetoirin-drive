package fr.rochetoirin.sim

import fr.rochetoirin.sim.car.CarModel
import fr.rochetoirin.sim.game.ActiveJob
import fr.rochetoirin.sim.game.Game
import fr.rochetoirin.sim.game.Persistence
import fr.rochetoirin.sim.world.World
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.hypot

/** Tests « sans écran » : vrai monde, vraie physique, vrai GPS, vraies livraisons. */
class SimulationTest {
    private val world by lazy { World { File("src/main/assets", it).inputStream() } }

    private fun newGame() = Game(world, 0, 0, object : Persistence {
        override fun save(money: Int, deliveries: Int) {}
    })

    @Test
    fun worldLoads() {
        assertTrue(world.terrain.nx > 400)
        assertTrue(world.roadChunks.isNotEmpty())
        assertEquals("Mairie de Rochetoirin", world.start.name)
        val h = world.terrain.height(world.start.x, world.start.z)
        println("Altitude devant la mairie : %.1f m".format(h))
        assertTrue("altitude plausible", h in 380f..520f)
    }

    @Test
    fun accelerationAndBraking() {
        val g = newGame()
        val v = g.vehicle
        world.decor.collisionsEnabled = false   // on mesure le moteur et les freins, pas les obstacles
        g.input.throttle = 1f
        var t = 0f
        var t100: Float? = null
        val dt = 1f / 120f
        while (t < 20f) {
            g.update(dt); t += dt
            if (t100 == null && v.speedKmh >= 50f) t100 = t
            val ground = world.groundHeight(v.x, v.z, v.y + 1f)
            assertTrue("le véhicule ne passe pas sous le sol", v.y > ground - 0.2f)   // tolérance : bordures de trottoir sous le centre
        }
        println("0-50 km/h : %.1f s, vitesse après 20 s : %.0f km/h, rapport %d, %s".format(t100 ?: -1f, v.speedKmh, v.gear, g.streetName))
        assertNotNull(t100)
        g.input.throttle = 0f; g.input.brake = 1f
        var stop = 0f
        while (v.speedKmh > 0.1f && stop < 15f) { g.update(dt); stop += dt }
        println("Freinage jusqu'à l'arrêt : %.1f s".format(stop))
        world.decor.collisionsEnabled = true
        assertTrue(stop < 8f)
    }

    /** Pilote automatique simple qui suit l'itinéraire du GPS : vérifie toute la boucle de livraison. */
    @Test
    fun autopilotDelivery() {
        val g = newGame()
        val v = g.vehicle
        world.decor.collisionsEnabled = false   // le pilote coupe les virages ; les collisions ont leur propre test
        // offre la plus courte pour un test rapide
        val offer = g.offers.minByOrNull { it.distance }!!
        println("Offre : ${offer.cargo} — ${offer.from.name} → ${offer.to.name}, %.1f km, ${offer.pay} €".format(offer.distance / 1000))
        g.accept(offer)
        val dt = 1f / 60f
        var t = 0f
        var offRoadTime = 0f
        var maxSpeed = 0f
        var lastPhase: ActiveJob.Phase? = null
        var lastRoute: fr.rochetoirin.sim.game.Gps.Route? = null
        var prog = 1
        var manoeuvre = 0f
        var stuck = 0f
        while (t < 1800f && g.job != null) {
            val r = g.route
            val j = g.job!!
            if (j.phase != lastPhase) { println("t=%5.0f s  phase %s".format(t, j.phase)); lastPhase = j.phase }
            if (r != null && r.size >= 2) {
                if (r !== lastRoute) { lastRoute = r; prog = 1 }
                while (prog < r.size - 1 && hypot(r.xs[prog] - v.x, r.zs[prog] - v.z) < 6f) prog++
                val dx = r.xs[prog] - v.x; val dz = r.zs[prog] - v.z
                var a = atan2(dx, -dz) - v.yaw
                while (a > PI) a -= (2 * PI).toFloat(); while (a < -PI) a += (2 * PI).toFloat()
                val distEnd = hypot(j.target.x - v.x, j.target.z - v.z)
                if (distEnd < 18f) {
                    g.reverseSelected = false
                    g.input.throttle = 0f; g.input.brake = 1f
                } else if (manoeuvre > 0f) {
                    // marche arrière braquée à l'opposé pour faire demi-tour
                    manoeuvre -= dt
                    g.reverseSelected = true
                    g.input.steer = -Math.signum(a); g.input.throttle = 0.4f; g.input.brake = 0f
                    if (manoeuvre <= 0f) g.reverseSelected = false
                } else {
                    g.reverseSelected = false
                    g.input.steer = (a * 3.5f).coerceIn(-1f, 1f)
                    val target = minOf(g.speedLimit * 0.9f, if (abs(a) > 0.5f) 8f else if (abs(a) > 0.2f) 18f else 70f, if (distEnd < 60f) 15f else 999f)
                    g.input.throttle = if (v.speedKmh < target) 0.7f else 0f
                    g.input.brake = if (v.speedKmh > target + 4f) 0.7f else 0f
                    if (v.speedKmh < 2f) { stuck += dt; if (stuck > 2f) { manoeuvre = 2.5f; stuck = 0f } } else stuck = 0f
                }
            } else {
                g.input.throttle = 0f; g.input.brake = 1f; g.input.steer = 0f
            }
            g.update(dt)
            t += dt
            if ((t / dt).toInt() % (60 * 60) == 0) println("  t=%4.0f pos=(%.0f,%.0f) y=%.1f v=%.0f km/h cap=%.0f° steer=%.2f route=%s reste=%.0f m dist=%.0f m %s".format(
                t, v.x, v.z, v.y, v.speedKmh, Math.toDegrees(v.yaw.toDouble()), g.input.steer, g.route?.size, g.routeRemaining,
                hypot(j.target.x - v.x, j.target.z - v.z), g.streetName))
            if (!v.onRoad) offRoadTime += dt
            maxSpeed = maxOf(maxSpeed, v.speedKmh)
        }
        println("Fin : t=%.0f s, argent=${g.money} €, livraisons=${g.deliveries}, hors route=%.0f s, vmax=%.0f km/h".format(t, offRoadTime, maxSpeed))
        world.decor.collisionsEnabled = true
        assertEquals(1, g.deliveries)
        assertTrue(g.money > 0)
    }

    /** On fonce dans une maison du village : le véhicule s'arrête, le choc est facturé. */
    @Test
    fun collisionWithHouse() {
        val g = Game(world, 1000, 0, object : Persistence { override fun save(money: Int, deliveries: Int) {} })
        val v = g.vehicle
        // maison au sud-ouest du carrefour Rue de Ravette / Rue du Vieux Chêne (centre ≈ 74, 343)
        // x = 78 : un chêne relevé sur l'orthophoto se trouve en (73.8, 360.8), sur l'ancienne trajectoire
        v.place(78f, 380f, 0f)   // plein nord, la maison est 32 m devant
        g.input.throttle = 1f
        var t = 0f
        var maxKmh = 0f
        while (t < 15f) { g.update(1f / 60f); t += 1f / 60f; maxKmh = maxOf(maxKmh, v.speedKmh) }
        println("Choc : vitesse max %.0f km/h, position z=%.1f, argent %d €, message « %s »".format(maxKmh, v.z, g.money, g.message))
        assertTrue("arrêté devant la maison", v.z in 348.5f..357f)
        assertTrue("facture de carrosserie", g.money < 1000)
    }

    @Test
    fun routesBetweenAllPoisExist() {
        val g = newGame()
        val s = world.start
        var fails = 0
        for (p in world.pois) {
            val r = g.gps.route(s.x, s.z, 0f, p.node)
            if (r == null) { fails++; println("Pas d'itinéraire vers ${p.name}") }
        }
        println("${world.pois.size - fails}/${world.pois.size} lieux accessibles depuis la mairie")
        assertTrue(fails <= 2)
    }

    @Test
    fun exportCarMesh() {
        val m = CarModel.build()
        fun arr(a: FloatArray) = a.joinToString(",", "[", "]") { "%.4f".format(java.util.Locale.ROOT, it) }
        fun arr(a: IntArray) = a.joinToString(",", "[", "]")
        val json = """{"bodyV":${arr(m.bodyV)},"bodyI":${arr(m.bodyI)},"glassV":${arr(m.glassV)},"glassI":${arr(m.glassI)},"wheelV":${arr(m.wheelV)},"wheelI":${arr(m.wheelI)},"steerV":${arr(m.steerV)},"steerI":${arr(m.steerI)}}"""
        File("build/carmesh.json").writeText(json)
        println("Espace : ${m.bodyV.size / 12 + m.glassV.size / 12} sommets, ${(m.bodyI.size + m.glassI.size) / 3} triangles")
    }

    /** Les trottoirs sont franchissables : bordure basse, la voiture monte dessus sans être arrêtée. */
    @Test
    fun climbsSidewalk() {
        // un bord de rue résidentielle du village avec trottoir et rien derrière sur 8 m
        var found: FloatArray? = null
        loop@ for (w in world.ways) {
            if (w.kind != "residential" && w.kind != "tertiary") continue
            for (s in 0 until w.nodes.size - 1) {
                val ax = world.nodeX[w.nodes[s]]; val az = world.nodeZ[w.nodes[s]]
                val bx = world.nodeX[w.nodes[s + 1]]; val bz = world.nodeZ[w.nodes[s + 1]]
                val l = hypot(bx - ax, bz - az)
                if (l < 12f) continue
                val mx = (ax + bx) / 2; val mz = (az + bz) / 2
                if (hypot(mx - world.start.x, mz - world.start.z) > 3000f) continue
                for (sg in intArrayOf(1, -1)) {
                    val nx = -(bz - az) / l * sg; val nz = (bx - ax) / l * sg
                    val d = w.width / 2 + 0.8f
                    if (world.decor.surf.offset(mx + nx * d, mz + nz * d) < 0.12f) continue
                    val yaw = atan2(nx, -nz)
                    var clear = true
                    for (k in 0..8) if (world.decor.collides(mx + nx * k, mz + nz * k, yaw, 2.3f, 0.92f)) clear = false
                    if (clear) { found = floatArrayOf(mx, mz, nx, nz, w.width); break@loop }
                }
            }
        }
        assertNotNull("un trottoir dégagé", found)
        val (mx, mz, nx, nz) = found!!
        val g = newGame()
        val v = g.vehicle
        v.place(mx - nx * 3f, mz - nz * 3f, atan2(nx, -nz))
        val y0 = v.y
        g.input.throttle = 0.45f
        val dt = 1f / 60f
        var t = 0f
        var maxRise = 0f
        while (t < 6f) {
            g.update(dt); t += dt
            val dist = (v.x - mx) * nx + (v.z - mz) * nz
            maxRise = maxOf(maxRise, world.decor.surf.offset(v.x, v.z))
            if (dist > found[4] / 2 + 1.6f) break
        }
        val dist = (v.x - mx) * nx + (v.z - mz) * nz
        println("Trottoir : montée de %.2f m, %.1f m parcourus, %.1f km/h".format(maxRise, dist + 3f, v.speedKmh))
        assertTrue("la voiture est montée sur le trottoir", maxRise > 0.1f && dist > found[4] / 2 + 0.5f)
        assertTrue("sans choc", v.speed > 0.5f && abs(v.y - y0) < 1.5f)
    }
}
