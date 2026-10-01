package fr.rochetoirin.sim.gl

import android.opengl.GLES30.*
import android.util.Log
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.nio.IntBuffer
import java.nio.ShortBuffer

object Gl {
    fun program(vs: String, fs: String): Int {
        val v = shader(GL_VERTEX_SHADER, vs)
        val f = shader(GL_FRAGMENT_SHADER, fs)
        val p = glCreateProgram()
        glAttachShader(p, v)
        glAttachShader(p, f)
        glLinkProgram(p)
        val ok = IntArray(1)
        glGetProgramiv(p, GL_LINK_STATUS, ok, 0)
        if (ok[0] == 0) {
            val log = glGetProgramInfoLog(p)
            Log.e("Gl", "link: $log")
            throw RuntimeException("Program link failed: $log")
        }
        glDeleteShader(v)
        glDeleteShader(f)
        return p
    }

    private fun shader(type: Int, src: String): Int {
        val s = glCreateShader(type)
        glShaderSource(s, src)
        glCompileShader(s)
        val ok = IntArray(1)
        glGetShaderiv(s, GL_COMPILE_STATUS, ok, 0)
        if (ok[0] == 0) {
            val log = glGetShaderInfoLog(s)
            Log.e("Gl", "compile: $log\n$src")
            throw RuntimeException("Shader compile failed: $log")
        }
        return s
    }

    fun floats(n: Int): FloatBuffer =
        ByteBuffer.allocateDirect(n * 4).order(ByteOrder.nativeOrder()).asFloatBuffer()

    fun floats(a: FloatArray): FloatBuffer = floats(a.size).apply { put(a); position(0) }

    fun ints(a: IntArray): IntBuffer =
        ByteBuffer.allocateDirect(a.size * 4).order(ByteOrder.nativeOrder()).asIntBuffer().apply { put(a); position(0) }

    fun shorts(a: ShortArray): ShortBuffer =
        ByteBuffer.allocateDirect(a.size * 2).order(ByteOrder.nativeOrder()).asShortBuffer().apply { put(a); position(0) }

    fun genBuffer(): Int {
        val b = IntArray(1)
        glGenBuffers(1, b, 0)
        return b[0]
    }

    fun genVao(): Int {
        val b = IntArray(1)
        glGenVertexArrays(1, b, 0)
        return b[0]
    }

    fun uniforms(program: Int, vararg names: String): IntArray =
        IntArray(names.size) { glGetUniformLocation(program, names[it]) }
}

/** Maillage indexé stocké sur le GPU. [layout] = nombre de flottants par attribut (location 0, 1, 2…). */
class Mesh(vertices: FloatBuffer, indices: IntBuffer, layout: IntArray) {
    val vao = Gl.genVao()
    private val vbo = Gl.genBuffer()
    private val ibo = Gl.genBuffer()
    val count = indices.limit()

    init {
        glBindVertexArray(vao)
        glBindBuffer(GL_ARRAY_BUFFER, vbo)
        glBufferData(GL_ARRAY_BUFFER, vertices.limit() * 4, vertices, GL_STATIC_DRAW)
        val stride = layout.sum() * 4
        var off = 0
        for ((i, n) in layout.withIndex()) {
            glEnableVertexAttribArray(i)
            glVertexAttribPointer(i, n, GL_FLOAT, false, stride, off)
            off += n * 4
        }
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ibo)
        glBufferData(GL_ELEMENT_ARRAY_BUFFER, count * 4, indices, GL_STATIC_DRAW)
        glBindVertexArray(0)
    }

    fun draw(first: Int = 0, n: Int = count) {
        glBindVertexArray(vao)
        glDrawElements(GL_TRIANGLES, n, GL_UNSIGNED_INT, first * 4)
    }
}

/** Boîte englobante pour le découpage (frustum + tranches de profondeur). */
class Bounds(var minX: Float, var minY: Float, var minZ: Float, var maxX: Float, var maxY: Float, var maxZ: Float) {
    val cx get() = (minX + maxX) / 2
    val cy get() = (minY + maxY) / 2
    val cz get() = (minZ + maxZ) / 2
    val radius: Float
        get() {
            val dx = maxX - minX; val dy = maxY - minY; val dz = maxZ - minZ
            return 0.5f * kotlin.math.sqrt(dx * dx + dy * dy + dz * dz)
        }
}

/** Plans du frustum extraits d'une matrice vue-projection (colonne-major). */
class Frustum {
    private val p = FloatArray(24)

    fun set(m: FloatArray) {
        // lignes de la matrice
        fun row(r: Int, c: Int) = m[c * 4 + r]
        for (i in 0 until 6) {
            val sign = if (i % 2 == 0) 1f else -1f
            val r = i / 2
            for (c in 0 until 4) p[i * 4 + c] = row(3, c) + sign * row(r, c)
            val len = kotlin.math.sqrt(p[i * 4] * p[i * 4] + p[i * 4 + 1] * p[i * 4 + 1] + p[i * 4 + 2] * p[i * 4 + 2])
            for (c in 0 until 4) p[i * 4 + c] /= len
        }
    }

    fun visible(b: Bounds): Boolean {
        for (i in 0 until 6) {
            val a = p[i * 4]; val bb = p[i * 4 + 1]; val c = p[i * 4 + 2]; val d = p[i * 4 + 3]
            val x = if (a > 0) b.maxX else b.minX
            val y = if (bb > 0) b.maxY else b.minY
            val z = if (c > 0) b.maxZ else b.minZ
            if (a * x + bb * y + c * z + d < 0) return false
        }
        return true
    }
}
