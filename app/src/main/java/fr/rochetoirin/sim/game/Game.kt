package fr.rochetoirin.sim.game

import fr.rochetoirin.sim.car.Vehicle
import fr.rochetoirin.sim.world.Poi
import fr.rochetoirin.sim.world.World
import java.util.concurrent.ConcurrentLinkedQueue
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.hypot
import kotlin.math.roundToInt
import kotlin.random.Random

/** Commandes du joueur (écrites par l'interface, lues par la boucle de jeu). */
class Input {
    @Volatile var steer = 0f        // -1 (gauche) .. 1 (droite)
    @Volatile var throttle = 0f     // 0..1
    @Volatile var brake = 0f        // 0..1
    @Volatile var horn = false
    @Volatile var orbitDX = 0f      // glissement caméra accumulé (px)
    @Volatile var orbitDY = 0f
}

class JobOffer(val cargo: String, val from: Poi, val to: Poi, val distance: Float, val pay: Int, val timeLimit: Float)

class ActiveJob(val offer: JobOffer) {
    enum class Phase { TO_PICKUP, LOADING, TO_DROP, UNLOADING }
    var phase = Phase.TO_PICKUP
    var timer = 0f
    var elapsed = 0f
    val target get() = if (phase == Phase.TO_PICKUP || phase == Phase.LOADING) offer.from else offer.to
}

interface Persistence {
    fun save(money: Int, deliveries: Int)
}

class Game(val world: World, startMoney: Int, startDeliveries: Int, private val persistence: Persistence) {
    val vehicle = Vehicle(world)
    val gps = Gps(world)
    val input = Input()
    private val commands = ConcurrentLinkedQueue<() -> Unit>()
    private val rnd = Random(System.currentTimeMillis())

    // --- état lisible par l'interface ---
    @Volatile var money = startMoney
    @Volatile var deliveries = startDeliveries
    @Volatile var offers: List<JobOffer> = emptyList()
    @Volatile var job: ActiveJob? = null
    @Volatile var route: Gps.Route? = null
    @Volatile var routeRemaining = 0f
    @Volatile var message = ""
    @Volatile var messageTime = 0f
    @Volatile var streetName = ""
    @Volatile var speedLimit = 50
    @Volatile var camMode = 0
    @Volatile var reverseSelected = false
    @Volatile var overSpeedTime = 0f
    /** Dernier choc (m/s), lu puis remis à zéro par le son. */
    @Volatile var impact = 0f

    private var routeTimer = 0f

    /** Lieux de livraison accessibles en voiture (aller et retour) depuis la mairie. */
    val jobPois = gps.stronglyConnected(world.start.node).let { ok -> world.pois.filter { ok[it.node] } }

    init {
        val s = world.start
        // orienté le long de la route devant la mairie
        val w = world.ways.firstOrNull { it.nodes.contains(s.node) }
        var heading = 0f
        if (w != null) {
            val k = w.nodes.indexOf(s.node)
            val o = if (k + 1 < w.nodes.size) w.nodes[k + 1] else w.nodes[k - 1]
            heading = atan2(world.nodeX[o] - s.x, -(world.nodeZ[o] - s.z))
        }
        // sur la voie de droite
        vehicle.place(s.x + kotlin.math.cos(heading) * 1.4f, s.z + kotlin.math.sin(heading) * 1.4f, heading)
        generateOffers()
        say("Bienvenue à Rochetoirin ! Ouvrez le carnet de livraisons 📦")
    }

    fun post(cmd: () -> Unit) { commands.add(cmd) }

    fun say(text: String, seconds: Float = 4f) { message = text; messageTime = seconds }

    // ------------------------------------------------------------------------------

    fun generateOffers() {
        val pois = jobPois
        val list = ArrayList<JobOffer>()
        var tries = 0
        while (list.size < 5 && tries < 200) {
            tries++
            val a = pois[rnd.nextInt(pois.size)]
            val b = pois[rnd.nextInt(pois.size)]
            if (a === b || a.node == b.node) continue
            val d = hypot(a.x - b.x, a.z - b.z)
            if (d < 500f || d > 5000f) continue
            if (list.any { it.from === a || it.to === b }) continue
            val r = gps.route(a.x, a.z, 0f, b.node) ?: continue
            val km = r.length / 1000f
            val pay = ((45 + km * 90 + rnd.nextInt(0, 30)) / 5f).roundToInt() * 5
            val limit = r.time * 1.7f + 150f
            list.add(JobOffer(cargos[rnd.nextInt(cargos.size)], a, b, r.length, pay, limit))
        }
        offers = list
    }

    fun accept(o: JobOffer) {
        job = ActiveJob(o)
        route = null; routeTimer = 0f
        say("Direction : ${o.from.name}")
    }

    fun cancelJob() {
        job = null; route = null
        say("Livraison annulée")
        generateOffers()
    }

    // ------------------------------------------------------------------------------
    fun update(dt: Float) {
        while (true) { val c = commands.poll() ?: break; c() }
        val v = vehicle
        // marche avant / arrière : le changement se fait à l'arrêt
        if (reverseSelected != v.reverse && abs(v.speed) < 0.6f) v.reverse = reverseSelected
        val throttle = if (reverseSelected != v.reverse) 0f else input.throttle
        val brake = if (reverseSelected != v.reverse) 1f else input.brake
        v.update(dt, input.steer, throttle, brake)

        // nom de rue et limitation
        val w = v.surfaceRoad.way
        if (w != null && v.surfaceRoad.dist < w.width / 2 + 8f) {
            streetName = w.name.ifEmpty {
                when (w.kind) {
                    "track" -> "Chemin agricole"
                    "service" -> "Voie de desserte"
                    else -> "Route communale"
                }
            }
            speedLimit = w.speed
        } else {
            streetName = "Hors piste"
        }
        if (v.speedKmh > speedLimit + 5 && v.onRoad) overSpeedTime += dt else overSpeedTime = 0f

        // chocs : petite facture de carrosserie, comme dans ETS
        if (v.lastImpact > 0f) {
            val kmh = v.lastImpact * 3.6f
            impact = v.lastImpact
            if (kmh > 12f) {
                val cost = (kmh * 2.5f).roundToInt()
                money = (money - cost).coerceAtLeast(0)
                persistence.save(money, deliveries)
                say("Choc à ${kmh.roundToInt()} km/h ! Carrosserie : -$cost €")
            }
            v.lastImpact = 0f
        }
        if (messageTime > 0f) messageTime -= dt
        updateJob(dt)
    }

    private fun updateJob(dt: Float) {
        val j = job ?: return
        val v = vehicle
        if (j.phase == ActiveJob.Phase.TO_DROP || j.phase == ActiveJob.Phase.UNLOADING) j.elapsed += dt
        val t = j.target
        val dist = hypot(v.x - t.x, v.z - t.z)
        when (j.phase) {
            ActiveJob.Phase.TO_PICKUP, ActiveJob.Phase.TO_DROP -> {
                routeTimer -= dt
                val r = route
                var need = r == null
                if (r != null && routeTimer <= 0f) {
                    val (off, rem) = gps.progress(r, v.x, v.z)
                    routeRemaining = rem
                    if (off > 35f) need = true
                    routeTimer = 0.5f
                }
                if (need) {
                    route = gps.route(v.x, v.z, v.yaw, t.node)
                    route?.let { routeRemaining = it.length }
                    routeTimer = 2f
                }
                if (dist < 25f && v.speedKmh < 6f) {
                    j.phase = if (j.phase == ActiveJob.Phase.TO_PICKUP) ActiveJob.Phase.LOADING else ActiveJob.Phase.UNLOADING
                    j.timer = 4f
                    route = null
                    say(if (j.phase == ActiveJob.Phase.LOADING) "Chargement : ${j.offer.cargo}…" else "Déchargement…", 4f)
                }
            }
            ActiveJob.Phase.LOADING, ActiveJob.Phase.UNLOADING -> {
                if (dist > 30f) {
                    j.phase = if (j.phase == ActiveJob.Phase.LOADING) ActiveJob.Phase.TO_PICKUP else ActiveJob.Phase.TO_DROP
                    say("Restez sur place pour la manutention !")
                    return
                }
                j.timer -= dt
                if (j.timer <= 0f) {
                    if (j.phase == ActiveJob.Phase.LOADING) {
                        j.phase = ActiveJob.Phase.TO_DROP
                        routeTimer = 0f
                        say("Chargé ! Livrez à : ${j.offer.to.name}")
                    } else {
                        val late = j.elapsed > j.offer.timeLimit
                        val pay = if (late) (j.offer.pay * 0.7f).roundToInt() else (j.offer.pay * 1.15f).roundToInt()
                        money += pay
                        deliveries += 1
                        persistence.save(money, deliveries)
                        say(if (late) "Livré en retard : +$pay €" else "Livraison réussie, prime de ponctualité : +$pay €", 6f)
                        job = null
                        generateOffers()
                    }
                }
            }
        }
    }

    companion object {
        private val cargos = listOf(
            "Pains et viennoiseries", "Colis de La Poste", "Fleurs pour l'église", "Ballons et maillots",
            "Plants de tomates", "Fromages de Savoie", "Bois de chauffage", "Chaises pour la salle des fêtes",
            "Cartons de livres", "Noix de l'Isère", "Bottes de foin", "Caisses de vin de Savoie",
            "Matériel de sono", "Pneus d'occasion", "Sacs de terreau", "Gâteaux d'anniversaire",
            "Courrier de la mairie", "Lait de la ferme", "Tables de camping", "Pièces détachées",
        )
    }
}
