package fr.rochetoirin.sim.game

import fr.rochetoirin.sim.world.RoadHit
import fr.rochetoirin.sim.world.World
import java.util.PriorityQueue
import kotlin.math.hypot

/** Calcul d'itinéraire (A*) sur le graphe routier OSM, en temps de parcours. */
class Gps(private val world: World) {
    private val n = world.nodeX.size
    private val adjStart = IntArray(n + 1)
    private val adjTo: IntArray
    private val adjCost: FloatArray
    private val adjLen: FloatArray

    init {
        val edges = ArrayList<FloatArray>() // from, to, cost, len
        for (w in world.ways) {
            val mps = (w.speed / 3.6f) * when (w.kind) {
                "track" -> 0.35f
                "service" -> 0.6f
                else -> 1f
            }
            for (k in 0 until w.nodes.size - 1) {
                val a = w.nodes[k]; val b = w.nodes[k + 1]
                val len = hypot(world.nodeX[b] - world.nodeX[a], world.nodeZ[b] - world.nodeZ[a])
                val cost = len / mps
                edges.add(floatArrayOf(a.toFloat(), b.toFloat(), cost, len))
                if (!w.oneway) edges.add(floatArrayOf(b.toFloat(), a.toFloat(), cost, len))
            }
        }
        val counts = IntArray(n)
        for (e in edges) counts[e[0].toInt()]++
        for (i in 0 until n) adjStart[i + 1] = adjStart[i] + counts[i]
        adjTo = IntArray(edges.size); adjCost = FloatArray(edges.size); adjLen = FloatArray(edges.size)
        val fill = adjStart.copyOf()
        for (e in edges) {
            val a = e[0].toInt(); val p = fill[a]++
            adjTo[p] = e[1].toInt(); adjCost[p] = e[2]; adjLen[p] = e[3]
        }
    }

    /** Nœuds atteignables depuis [from] ET qui permettent d'y revenir (même composante fortement connexe). */
    fun stronglyConnected(from: Int): BooleanArray {
        val fwd = BooleanArray(n); val bwd = BooleanArray(n)
        // arcs inverses
        val rev = Array(n) { ArrayList<Int>(2) }
        for (i in 0 until n) for (p in adjStart[i] until adjStart[i + 1]) rev[adjTo[p]].add(i)
        val stack = ArrayDeque<Int>()
        stack.add(from); fwd[from] = true
        while (stack.isNotEmpty()) {
            val i = stack.removeLast()
            for (p in adjStart[i] until adjStart[i + 1]) { val j = adjTo[p]; if (!fwd[j]) { fwd[j] = true; stack.add(j) } }
        }
        stack.add(from); bwd[from] = true
        while (stack.isNotEmpty()) {
            val i = stack.removeLast()
            for (j in rev[i]) if (!bwd[j]) { bwd[j] = true; stack.add(j) }
        }
        return BooleanArray(n) { fwd[it] && bwd[it] }
    }

    class Route(val xs: FloatArray, val zs: FloatArray, val length: Float, val time: Float) {
        val size get() = xs.size
    }

    private val hit = RoadHit()

    /** Itinéraire depuis une position quelconque jusqu'au nœud [target]. */
    fun route(x: Float, z: Float, yaw: Float, target: Int): Route? {
        world.nearestRoad(x, z, hit)
        val w = hit.way ?: return null
        val a = w.nodes[hit.seg]; val b = w.nodes[hit.seg + 1]
        val g = FloatArray(n) { Float.MAX_VALUE }
        val prev = IntArray(n) { -1 }
        val pq = PriorityQueue<Long>(256)
        val maxSpeed = 130f / 3.6f
        fun h(i: Int) = hypot(world.nodeX[i] - world.nodeX[target], world.nodeZ[i] - world.nodeZ[target]) / maxSpeed
        fun push(i: Int, cost: Float) {
            val f = cost + h(i)
            pq.add((java.lang.Float.floatToIntBits(f).toLong() shl 32) or i.toLong())
        }
        // on peut rejoindre les deux extrémités du segment courant (léger malus pour faire demi-tour)
        val fx = kotlin.math.sin(yaw); val fz = -kotlin.math.cos(yaw)
        for (s in intArrayOf(a, b)) {
            if (w.oneway && s == a) continue
            val dx = world.nodeX[s] - x; val dz = world.nodeZ[s] - z
            val d = hypot(dx, dz)
            val behind = (dx * fx + dz * fz) < 0
            val c = d / 8f + if (behind && d > 5f) 12f else 0f
            if (c < g[s]) { g[s] = c; push(s, c) }
        }
        val closed = BooleanArray(n)
        while (pq.isNotEmpty()) {
            val top = pq.poll()!!
            val i = (top and 0xFFFFFFFFL).toInt()
            if (closed[i]) continue
            closed[i] = true
            if (i == target) break
            for (p in adjStart[i] until adjStart[i + 1]) {
                val j = adjTo[p]
                val c = g[i] + adjCost[p]
                if (c < g[j]) { g[j] = c; prev[j] = i; push(j, c) }
            }
        }
        if (g[target] == Float.MAX_VALUE) return null
        val path = ArrayList<Int>()
        var cur = target
        while (cur != -1) { path.add(cur); cur = prev[cur] }
        path.reverse()
        val xs = FloatArray(path.size + 1); val zs = FloatArray(path.size + 1)
        xs[0] = x; zs[0] = z
        var len = 0f
        for ((k, i) in path.withIndex()) {
            xs[k + 1] = world.nodeX[i]; zs[k + 1] = world.nodeZ[i]
            len += hypot(xs[k + 1] - xs[k], zs[k + 1] - zs[k])
        }
        return Route(xs, zs, len, g[target])
    }

    /** Distance d'un point à la polyligne de l'itinéraire, et distance restante depuis ce point. */
    fun progress(r: Route, x: Float, z: Float): Pair<Float, Float> {
        var best = Float.MAX_VALUE; var bestK = 0; var bestT = 0f
        for (k in 0 until r.size - 1) {
            val ax = r.xs[k]; val az = r.zs[k]
            val dx = r.xs[k + 1] - ax; val dz = r.zs[k + 1] - az
            val l2 = dx * dx + dz * dz
            val t = if (l2 < 1e-6f) 0f else (((x - ax) * dx + (z - az) * dz) / l2).coerceIn(0f, 1f)
            val d = hypot(x - (ax + dx * t), z - (az + dz * t))
            if (d < best) { best = d; bestK = k; bestT = t }
        }
        var rem = 0f
        for (k in bestK until r.size - 1) {
            val l = hypot(r.xs[k + 1] - r.xs[k], r.zs[k + 1] - r.zs[k])
            rem += if (k == bestK) l * (1 - bestT) else l
        }
        return best to rem
    }
}
