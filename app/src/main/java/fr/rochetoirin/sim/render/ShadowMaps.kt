package fr.rochetoirin.sim.render

import android.opengl.GLES30.*
import android.opengl.Matrix
import kotlin.math.floor

/**
 * Ombres portées du soleil : deux cartes de profondeur orthographiques (cascades) centrées
 * devant la caméra. Cascade 0 : ~45 m de rayon (ombres nettes de la voiture, des haies, des
 * poteaux) ; cascade 1 : ~300 m (bâtiments, arbres au loin). Filtrage PCF matériel.
 */
class ShadowMaps(val size: Int = 2048) {
    val radius = floatArrayOf(45f, 300f)
    val tex = IntArray(2)
    private val fbo = IntArray(2)
    /** Matrice monde -> espace lumière (clip) pour le rendu des occulteurs. */
    val lightVP = Array(2) { FloatArray(16) }
    /** Matrice monde -> coordonnées de texture [0,1]³ pour l'échantillonnage. */
    val texM = Array(2) { FloatArray(16) }
    val center = Array(2) { FloatArray(3) }
    private val view = FloatArray(16)
    private val proj = FloatArray(16)
    private val bias = floatArrayOf(0.5f, 0f, 0f, 0f, 0f, 0.5f, 0f, 0f, 0f, 0f, 0.5f, 0f, 0.5f, 0.5f, 0.5f, 1f)

    init {
        glGenTextures(2, tex, 0)
        glGenFramebuffers(2, fbo, 0)
        for (k in 0..1) {
            glBindTexture(GL_TEXTURE_2D, tex[k])
            glTexStorage2D(GL_TEXTURE_2D, 1, GL_DEPTH_COMPONENT24, size, size)
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_COMPARE_MODE, GL_COMPARE_REF_TO_TEXTURE)
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_COMPARE_FUNC, GL_LEQUAL)
            glBindFramebuffer(GL_FRAMEBUFFER, fbo[k])
            glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_TEXTURE_2D, tex[k], 0)
            glDrawBuffers(1, intArrayOf(GL_NONE), 0)
            glReadBuffer(GL_NONE)
        }
        glBindFramebuffer(GL_FRAMEBUFFER, 0)
        glBindTexture(GL_TEXTURE_2D, 0)
    }

    /** Place les cascades : [eye] position de l'œil, [fx],[fz] direction horizontale du regard. */
    fun update(eye: FloatArray, fx: Float, fz: Float, sun: FloatArray) {
        val ahead = floatArrayOf(radius[0] * 0.55f, radius[1] * 0.75f)
        for (k in 0..1) {
            val r = radius[k]
            val c = center[k]
            c[0] = eye[0] + fx * ahead[k]; c[1] = eye[1] - 2f; c[2] = eye[2] + fz * ahead[k]
            val d = 600f
            Matrix.setLookAtM(view, 0, c[0] + sun[0] * d, c[1] + sun[1] * d, c[2] + sun[2] * d, c[0], c[1], c[2], 0f, 1f, 0f)
            Matrix.orthoM(proj, 0, -r, r, -r, r, 1f, d + 400f)
            Matrix.multiplyMM(lightVP[k], 0, proj, 0, view, 0)
            // alignement sur les texels : supprime le scintillement quand la caméra bouge
            val o = FloatArray(4)
            Matrix.multiplyMV(o, 0, lightVP[k], 0, floatArrayOf(0f, 0f, 0f, 1f), 0)
            val half = size / 2f
            val ox = o[0] * half; val oy = o[1] * half
            proj[12] += (floor(ox + 0.5f) - ox) / half
            proj[13] += (floor(oy + 0.5f) - oy) / half
            Matrix.multiplyMM(lightVP[k], 0, proj, 0, view, 0)
            Matrix.multiplyMM(texM[k], 0, bias, 0, lightVP[k], 0)
        }
    }

    /** Taille d'un texel (m) de chaque cascade, pour le décalage selon la normale. */
    fun texel(k: Int) = 2f * radius[k] / size

    fun begin(k: Int) {
        glBindFramebuffer(GL_FRAMEBUFFER, fbo[k])
        glViewport(0, 0, size, size)
        glClear(GL_DEPTH_BUFFER_BIT)
        glEnable(GL_DEPTH_TEST)
        glDepthFunc(GL_LEQUAL)
        glDepthMask(true)
        glEnable(GL_POLYGON_OFFSET_FILL)
        glPolygonOffset(1.6f, 3f)
    }

    fun end(width: Int, height: Int) {
        glDisable(GL_POLYGON_OFFSET_FILL)
        glBindFramebuffer(GL_FRAMEBUFFER, 0)
        glViewport(0, 0, width, height)
    }

    /** Une boîte touche-t-elle la cascade k (test horizontal grossier, généreux) ? */
    fun touches(k: Int, minX: Float, minZ: Float, maxX: Float, maxZ: Float, height: Float = 60f): Boolean {
        val c = center[k]
        val r = radius[k] + height        // l'ombre d'un objet haut porte loin
        return maxX >= c[0] - r && minX <= c[0] + r && maxZ >= c[2] - r && minZ <= c[2] + r
    }
}
