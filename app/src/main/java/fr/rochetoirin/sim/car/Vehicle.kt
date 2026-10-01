package fr.rochetoirin.sim.car

import fr.rochetoirin.sim.world.RoadHit
import fr.rochetoirin.sim.world.World
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sign
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.math.tan

/**
 * Physique « simulation légère » d'un Espace 2.0 16V boîte auto :
 * moteur + convertisseur, boîte 5 rapports, résistance de l'air et au roulement,
 * pente, adhérence latérale limitée (sous-virage), suspension (tangage/roulis), petits sauts.
 */
class Vehicle(private val world: World) {
    // --- état ---
    var x = 0f; var y = 0f; var z = 0f
    var yaw = 0f                 // cap : 0 = Nord, sens horaire
    var speed = 0f               // m/s, signée (négative en marche arrière)
    var pitch = 0f; var roll = 0f
    var steerAngle = 0f          // rad, roues avant
    var wheelSpin = 0f           // rad, rotation des roues
    var rpm = 800f
    var gear = 1                 // rapport engagé (1..5)
    var reverse = false
    var onRoad = true
    var surfaceRoad: RoadHit = RoadHit()
    var bodyHeave = 0f           // débattement de suspension (m)
    var longAccel = 0f
    var latAccel = 0f
    var throttleOut = 0f
    /** Vitesse (m/s) du dernier choc, remise à zéro par le jeu une fois traitée. */
    var lastImpact = 0f

    private var vy = 0f
    private var pitchVel = 0f; private var rollVel = 0f; private var heaveVel = 0f
    private var yawRate = 0f
    private var shiftTimer = 0f
    private var airborne = false

    // --- caractéristiques ---
    private val mass = 1720f
    private val g = 9.81f
    private val ratios = floatArrayOf(0f, 3.75f, 2.10f, 1.42f, 1.05f, 0.82f)
    private val reverseRatio = 3.40f
    private val finalDrive = 4.05f
    private val idle = 800f
    private val redline = 6100f

    fun place(px: Float, pz: Float, heading: Float) {
        x = px; z = pz; yaw = heading; speed = 0f; vy = 0f
        y = world.groundHeight(x, z, 1e4f)
        pitch = 0f; roll = 0f
    }

    /** Couple moteur (N·m) d'un 2.0 16V de 140 ch environ. */
    private fun torque(r: Float): Float {
        val t = when {
            r < 1000f -> 120f
            r < 3750f -> 120f + (191f - 120f) * (r - 1000f) / 2750f
            r < 5500f -> 191f - (191f - 165f) * (r - 3750f) / 1750f
            else -> 165f - (r - 5500f) * 0.12f
        }
        return max(0f, t)
    }

    fun update(dt: Float, steerIn: Float, throttleIn: Float, brakeIn: Float) {
        val fx = sin(yaw); val fz = -cos(yaw)          // avant
        val rx = cos(yaw); val rz = sin(yaw)           // droite

        // --- nature du sol ---
        world.nearestRoad(x, z, surfaceRoad)
        val w = surfaceRoad.way
        onRoad = w != null && surfaceRoad.dist < w.width * 0.5f + 0.6f
        val track = onRoad && w!!.kind == "track"
        val grip = if (!onRoad) 0.62f else if (track) 0.75f else 0.98f
        val crr = if (!onRoad) 0.055f else if (track) 0.03f else 0.013f

        // --- direction : angle max réduit avec la vitesse (direction assistée « à la ETS ») ---
        val v = abs(speed)
        val maxSteer = (0.62f / (1f + v / 9f)).coerceAtLeast(0.045f)
        val target = steerIn * maxSteer
        steerAngle += (target - steerAngle) * min(1f, dt * 10f)

        // --- moteur / boîte ---
        val wheelRpm = v / CarModel.WHEEL_R * 60f / (2 * PI.toFloat())
        val ratio = if (reverse) reverseRatio else ratios[gear]
        val shaftRpm = wheelRpm * ratio * finalDrive
        // convertisseur de couple : le moteur peut monter au-dessus de l'arbre à basse vitesse
        val stall = idle + throttleIn * 1700f
        val targetRpm = max(shaftRpm, stall * (1f - min(1f, shaftRpm / 2200f)) + shaftRpm * min(1f, shaftRpm / 2200f))
        rpm += (targetRpm.coerceIn(idle, redline) - rpm) * min(1f, dt * 8f)
        if (shiftTimer > 0f) shiftTimer -= dt
        if (!reverse && shiftTimer <= 0f) {
            val up = 2300f + throttleIn * 2900f
            val down = 1150f + throttleIn * 1500f
            if (shaftRpm > up && gear < 5) { gear++; shiftTimer = 0.6f }
            else if (gear > 1 && shaftRpm * ratios[gear - 1] / ratios[gear] < up * 0.85f && shaftRpm < down) { gear--; shiftTimer = 0.6f }
        }
        val converterMult = 1f + 1.1f * (1f - min(1f, shaftRpm / 1800f))
        val shifting = shiftTimer > 0.4f
        var drive = if (rpm < redline - 50f && !shifting) torque(rpm) * throttleIn * ratio * finalDrive * 0.88f * converterMult / CarModel.WHEEL_R else 0f
        drive = min(drive, grip * mass * g * 0.55f)  // traction avant : motricité limitée
        throttleOut = throttleIn

        // --- forces longitudinales ---
        val dir = if (reverse) -1f else 1f
        var fLong = drive * dir
        fLong -= 0.53f * speed * abs(speed)                          // aéro (SCx ≈ 0.88)
        fLong -= sign(speed) * crr * mass * g                         // roulement
        fLong -= mass * g * sin(pitch)                                // pente
        if (throttleIn < 0.05f && v > 0.5f) fLong -= sign(speed) * 260f * (ratio / 2f) // frein moteur
        val brakeF = brakeIn * grip * mass * g * 0.95f
        var newSpeed = speed + fLong / mass * dt
        // freinage : ne fait pas repartir en arrière
        if (brakeF > 0f) {
            val dv = brakeF / mass * dt
            newSpeed = if (abs(newSpeed) <= dv) 0f else newSpeed - sign(newSpeed) * dv
        }
        // à l'arrêt sans gaz : le véhicule ne dérive pas sur faible pente
        if (abs(newSpeed) < 0.08f && throttleIn < 0.05f && abs(sin(pitch)) < 0.12f) newSpeed = 0f
        if (airborne) newSpeed = speed - 0.53f * speed * abs(speed) / mass * dt
        longAccel = (newSpeed - speed) / max(dt, 1e-4f)
        speed = newSpeed

        // --- lacet : modèle bicyclette avec limite d'adhérence ---
        var wantYawRate = speed * tan(steerAngle) / CarModel.WHEELBASE
        val maxLat = grip * g
        if (abs(speed) > 1f && abs(wantYawRate * speed) > maxLat) {
            wantYawRate = sign(wantYawRate) * maxLat / abs(speed)
            speed -= sign(speed) * min(abs(speed), 1.5f * dt)          // ripage des pneus
        }
        if (airborne) wantYawRate = yawRate
        val oldYaw = yaw
        yawRate += (wantYawRate - yawRate) * min(1f, dt * 9f)
        latAccel = yawRate * speed
        yaw += yawRate * dt
        if (yaw > PI) yaw -= (2 * PI).toFloat()
        if (yaw < -PI) yaw += (2 * PI).toFloat()

        // --- déplacement (avec collisions contre bâtiments, arbres et haies) ---
        val ox = x; val oz = z
        x += fx * speed * dt
        z += fz * speed * dt
        if (world.decor.collides(x, z, yaw, 2.30f, 0.92f) && !world.decor.collides(ox, oz, oldYaw, 2.30f, 0.92f)) {
            x = ox; z = oz; yaw = oldYaw; yawRate = 0f
            if (abs(speed) > 1.5f) lastImpact = abs(speed)
            speed = -speed * 0.2f
        }
        val cx = world.clampX(x); val cz = world.clampZ(z)
        if (cx != x || cz != z) { x = cx; z = cz; speed *= 0.3f }
        wheelSpin += speed / CarModel.WHEEL_R * dt

        // --- contact avec le sol aux quatre roues ---
        val hf = CarModel.WHEELBASE / 2; val ht = CarModel.TRACK / 2
        val ref = y + 1.0f
        val hFL = world.groundHeight(x + fx * hf - rx * ht, z + fz * hf - rz * ht, ref)
        val hFR = world.groundHeight(x + fx * hf + rx * ht, z + fz * hf + rz * ht, ref)
        val hRL = world.groundHeight(x - fx * hf - rx * ht, z - fz * hf - rz * ht, ref)
        val hRR = world.groundHeight(x - fx * hf + rx * ht, z - fz * hf + rz * ht, ref)
        val ground = (hFL + hFR + hRL + hRR) / 4f
        val gPitch = atan2((hFL + hFR) / 2 - (hRL + hRR) / 2, CarModel.WHEELBASE)
        val gRoll = atan2((hFR + hRR) / 2 - (hFL + hRL) / 2, CarModel.TRACK)

        // vertical : gravité + contact
        vy -= g * dt
        y += vy * dt
        if (y <= ground) {
            val impact = -vy
            y = ground
            vy = 0f
            if (airborne && impact > 2f) heaveVel -= impact * 0.25f
            airborne = false
        } else if (y > ground + 0.12f) {
            airborne = true
        } else {
            // collé au sol (suivi des bosses) sauf si on décolle franchement
            val follow = min(1f, dt * 30f)
            y += (ground - y) * follow
            vy = max(vy, 0f) * 0.5f
            airborne = false
        }

        // suspension : ressorts amortis sur tangage, roulis, pompage + transferts de charge
        val pitchTarget = gPitch + (longAccel * 0.0055f).coerceIn(-0.06f, 0.06f)
        val rollTarget = gRoll + (latAccel * 0.009f).coerceIn(-0.07f, 0.07f)
        val k = 90f; val c = 13f
        if (!airborne) {
            pitchVel += ((pitchTarget - pitch) * k - pitchVel * c) * dt
            rollVel += ((rollTarget - roll) * k - rollVel * c) * dt
        } else {
            pitchVel *= exp(-dt)
            rollVel *= exp(-dt)
        }
        pitch += pitchVel * dt
        roll += rollVel * dt
        heaveVel += (-bodyHeave * 120f - heaveVel * 14f) * dt
        bodyHeave += heaveVel * dt
        bodyHeave = bodyHeave.coerceIn(-0.12f, 0.12f)
    }

    val speedKmh get() = abs(speed) * 3.6f

    /** Matrice modèle (colonne-major) de la caisse. */
    fun modelMatrix(out: FloatArray, withHeave: Boolean = true) {
        android.opengl.Matrix.setIdentityM(out, 0)
        android.opengl.Matrix.translateM(out, 0, x, y + if (withHeave) bodyHeave else 0f, z)
        android.opengl.Matrix.rotateM(out, 0, Math.toDegrees(-yaw.toDouble()).toFloat(), 0f, 1f, 0f)
        android.opengl.Matrix.rotateM(out, 0, Math.toDegrees(pitch.toDouble()).toFloat(), 1f, 0f, 0f)
        android.opengl.Matrix.rotateM(out, 0, Math.toDegrees(roll.toDouble()).toFloat(), 0f, 0f, 1f)
    }

    companion object {
        fun lenOf(a: Float, b: Float) = sqrt(a * a + b * b)
    }
}
