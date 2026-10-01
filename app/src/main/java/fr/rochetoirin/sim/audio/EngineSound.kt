package fr.rochetoirin.sim.audio

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.min
import kotlin.math.sin
import kotlin.random.Random

/**
 * Synthèse temps réel du son : moteur 4 cylindres (fréquence d'allumage = 2 × régime),
 * admission, bruit de roulement / vent, et klaxon double ton.
 */
class EngineSound {
    @Volatile var rpm = 800f
    @Volatile var load = 0f        // 0..1 (accélérateur)
    @Volatile var speed = 0f       // m/s
    @Volatile var horn = false
    @Volatile var offRoad = false
    @Volatile var enabled = true
    /** Déclenche un bruit de choc d'intensité donnée (m/s). */
    @Volatile var bump = 0f

    private val rate = 22050
    @Volatile private var running = false
    private var thread: Thread? = null

    fun start() {
        if (running) return
        running = true
        thread = Thread({ loop() }, "engine-sound").apply { priority = Thread.MAX_PRIORITY; start() }
    }

    fun stop() {
        running = false
        thread?.join(500)
        thread = null
    }

    private fun loop() {
        val minBuf = AudioTrack.getMinBufferSize(rate, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT)
        val track = AudioTrack.Builder()
            .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_GAME).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
            .setAudioFormat(AudioFormat.Builder().setSampleRate(rate).setEncoding(AudioFormat.ENCODING_PCM_16BIT).setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build())
            .setBufferSizeInBytes(maxOf(minBuf, 2048 * 2))
            .setTransferMode(AudioTrack.MODE_STREAM)
            .build()
        track.play()
        val n = 512
        val buf = ShortArray(n)
        val rnd = Random(1)
        var phase = 0.0
        var hornPhase1 = 0.0; var hornPhase2 = 0.0
        var curRpm = rpm; var curLoad = 0f; var curSpeed = 0f; var hornEnv = 0f; var master = 0f
        var bumpEnv = 0f; var lpBump = 0f
        var lp1 = 0f; var lp2 = 0f; var lpWind = 0f; var lpRoad = 0f; var lpOut = 0f
        val twoPi = 2 * PI
        while (running) {
            val tRpm = rpm; val tLoad = load; val tSpeed = speed; val tHorn = horn; val on = enabled
            val tRough = offRoad
            if (bump > 0f) { bumpEnv = min(1.5f, bump / 6f); bump = 0f }
            for (i in 0 until n) {
                curRpm += (tRpm - curRpm) * 0.002f
                curLoad += (tLoad - curLoad) * 0.001f
                curSpeed += (tSpeed - curSpeed) * 0.001f
                master += ((if (on) 1f else 0f) - master) * 0.0005f
                hornEnv += ((if (tHorn) 1f else 0f) - hornEnv) * 0.01f

                // moteur
                val f = curRpm / 60.0 * 2.0
                phase += f / rate
                if (phase > 1000.0) phase -= 1000.0
                val p = phase * twoPi
                val fire = sin(p) * 0.55 + sin(2 * p + 0.6) * 0.28 + sin(3 * p + 1.1) * 0.12 + sin(0.5 * p) * 0.30
                // impulsions d'allumage (forme asymétrique)
                val frac = phase - Math.floor(phase)
                val pulse = if (frac < 0.25) sin(frac / 0.25 * PI) else 0.0
                val noise = rnd.nextFloat() * 2f - 1f
                lp1 += (noise - lp1) * 0.08f
                lp2 += (lp1 - lp2) * 0.08f
                val intake = lp2 * (0.25f + curLoad * 1.1f) * (curRpm / 4000f)
                var engine = (fire * 0.5 + pulse * 0.45).toFloat() * (0.30f + curLoad * 0.55f) + intake * 1.6f
                engine *= 0.55f + min(1f, curRpm / 5000f) * 0.45f

                // vent et roulement
                val n2 = rnd.nextFloat() * 2f - 1f
                lpWind += (n2 - lpWind) * 0.03f
                lpRoad += (n2 - lpRoad) * (if (tRough) 0.25f else 0.12f)
                val wind = lpWind * min(1f, curSpeed / 35f) * 0.9f
                val road = lpRoad * min(1f, curSpeed / 25f) * (if (tRough) 0.45f else 0.18f)

                // klaxon (deux tons ~ 410 / 510 Hz, saturés)
                hornPhase1 += 410.0 / rate; hornPhase2 += 512.0 / rate
                if (hornPhase1 > 1) hornPhase1 -= 1; if (hornPhase2 > 1) hornPhase2 -= 1
                val h = (sq(hornPhase1) + sq(hornPhase2)) * 0.22f * hornEnv

                // choc : bruit grave et bref
                lpBump += (n2 - lpBump) * 0.04f
                val thump = lpBump * bumpEnv * 3f
                bumpEnv *= 0.9996f
                var s = (engine * 0.55f + wind + road + thump) * master + h * (if (on) 1f else 0.6f)
                lpOut += (s - lpOut) * 0.5f
                s = lpOut
                s = s / (1f + abs(s))   // saturation douce
                buf[i] = (s * 26000f).toInt().coerceIn(-32767, 32767).toShort()
            }
            track.write(buf, 0, n)
        }
        track.stop()
        track.release()
    }

    private fun sq(ph: Double): Float = if (ph < 0.5) 1f else -1f
}
