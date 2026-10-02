package fr.rochetoirin.sim.render

import android.opengl.GLES30.*
import fr.rochetoirin.sim.gl.Gl
import fr.rochetoirin.sim.gl.Textures
import fr.rochetoirin.sim.world.HeightGrid
import kotlin.math.floor

/**
 * Herbe 3D autour de la caméra : une grille de touffes (deux cartes croisées) régénérée
 * dans le shader à chaque image. Les positions dépendent de la cellule du monde, donc restent
 * fixes quand la caméra bouge ; hauteur lue dans une texture du relief.
 */
class GrassRenderer(terrain: HeightGrid) {
    val radius = 30f
    private val spacing = 0.42f
    private val n = (2 * radius / spacing).toInt()
    private val vao: Int
    private val count: Int
    private val texHeight: Int
    private val texTuft: Int
    private val hx0 = terrain.x0
    private val hz0 = terrain.z0
    private val hstep = terrain.step

    init {
        glBindVertexArray(0)
        // deux cartes croisées : (x, y, n° de carte)
        val v = floatArrayOf(-0.5f, 0f, 0f, 0.5f, 0f, 0f, 0.5f, 1f, 0f, -0.5f, 1f, 0f,
                             -0.5f, 0f, 1f, 0.5f, 0f, 1f, 0.5f, 1f, 1f, -0.5f, 1f, 1f)
        val idx = intArrayOf(0, 1, 2, 0, 2, 3, 4, 5, 6, 4, 6, 7)
        count = idx.size
        vao = Gl.genVao()
        glBindVertexArray(vao)
        val vb = Gl.genBuffer(); glBindBuffer(GL_ARRAY_BUFFER, vb)
        glBufferData(GL_ARRAY_BUFFER, v.size * 4, Gl.floats(v), GL_STATIC_DRAW)
        glEnableVertexAttribArray(0); glVertexAttribPointer(0, 3, GL_FLOAT, false, 12, 0)
        val ib = Gl.genBuffer(); glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ib)
        glBufferData(GL_ELEMENT_ARRAY_BUFFER, idx.size * 4, Gl.ints(idx), GL_STATIC_DRAW)
        glBindVertexArray(0)
        // relief en texture flottante (lue par texelFetch dans le shader de sommets)
        val h = FloatArray(terrain.nx * terrain.nz)
        for (j in 0 until terrain.nz) for (i in 0 until terrain.nx) h[j * terrain.nx + i] = terrain.at(i, j)
        val t = IntArray(1)
        glGenTextures(1, t, 0)
        texHeight = t[0]
        glBindTexture(GL_TEXTURE_2D, texHeight)
        glPixelStorei(GL_UNPACK_ALIGNMENT, 4)
        glTexImage2D(GL_TEXTURE_2D, 0, GL_R32F, terrain.nx, terrain.nz, 0, GL_RED, GL_FLOAT, Gl.floats(h))
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST)
        texTuft = Textures.upload(Textures.tufts(), repeat = false)
    }

    fun draw(p: Int, eye: FloatArray, time: Float, bind: (Int, String, Int, Int) -> Unit) {
        val ox = floor((eye[0] - radius) / spacing) * spacing
        val oz = floor((eye[2] - radius) / spacing) * spacing
        glUniform4f(glGetUniformLocation(p, "uGrid"), ox, oz, spacing, n.toFloat())
        glUniform3f(glGetUniformLocation(p, "uHRect"), hx0, hz0, hstep)
        glUniform1f(glGetUniformLocation(p, "uRadius"), radius)
        glUniform1f(glGetUniformLocation(p, "uTime"), time)
        bind(p, "uHeight", texHeight, 4)
        bind(p, "uTuft", texTuft, 5)
        glBindVertexArray(vao)
        glDrawElementsInstanced(GL_TRIANGLES, count, GL_UNSIGNED_INT, 0, n * n)
        glBindVertexArray(0)
    }
}
