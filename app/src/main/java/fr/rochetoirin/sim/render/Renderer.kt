package fr.rochetoirin.sim.render

import android.opengl.GLES30.*
import android.opengl.GLSurfaceView
import android.opengl.Matrix
import android.os.SystemClock
import fr.rochetoirin.sim.car.CarModel
import fr.rochetoirin.sim.game.Game
import fr.rochetoirin.sim.gl.Bounds
import fr.rochetoirin.sim.gl.Frustum
import fr.rochetoirin.sim.gl.Gl
import fr.rochetoirin.sim.gl.Mesh
import fr.rochetoirin.sim.gl.Textures
import fr.rochetoirin.sim.world.HeightGrid
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

class Renderer(
    private val game: Game,
    private val open: (String) -> java.io.InputStream,
    private val onReady: () -> Unit,
) : GLSurfaceView.Renderer {
    /** [kind] : 0 zone jouable, 1 anneau lointain, 2 panorama ; [big] = nombre d'indices des gros objets. */
    private class Chunk(val mesh: Mesh, val bounds: Bounds, val kind: Int = 0, val big: Int = 0)

    private val world = game.world
    private var terrainChunks = ArrayList<Chunk>()
    private var roadChunks = ArrayList<Chunk>()

    private var pTerrain = 0; private var pRoad = 0; private var pSky = 0; private var pCar = 0
    private var pShadow = 0; private var pMarker = 0
    private var pProps = 0; private var pTree = 0; private var pBillboard = 0
    private var pPropsDepth = 0; private var pTreeDepth = 0; private var pCarDepth = 0
    private var shadows: ShadowMaps? = null
    private var shadowsOn = true
    private var texGrass = 0; private var texNoise = 0; private var texPlates = 0
    private var texLand = 0; private var texLandFar = 0
    private var propChunks = ArrayList<Chunk>()
    private var streetChunks = ArrayList<Chunk>()
    private var decalChunks = ArrayList<Chunk>()
    private var texSigns = 0
    private var texLeaf = 0
    private var pImp = 0; private var pImpDepth = 0
    private var texImpCol = 0; private var texImpNrm = 0; private var texHedge = 0
    private val impParams = FloatArray(32)
    private var texMask = 0
    private var texAO = 0
    private var pGrass = 0
    private var grass: GrassRenderer? = null
    private var trees: TreeRenderer? = null
    private lateinit var body: Mesh
    private lateinit var glass: Mesh
    private lateinit var wheel: Mesh
    private lateinit var steer: Mesh
    private lateinit var cylinder: Mesh
    private var emptyVao = 0

    private var width = 1; private var height = 1
    private val view = FloatArray(16)
    private val proj = FloatArray(16)
    private val vp = FloatArray(16)
    private val inv = FloatArray(16)
    private val model = FloatArray(16)
    private val tmp = FloatArray(16)
    private val tmp2 = FloatArray(16)
    private val frustum = Frustum()
    private val sun = floatArrayOf(-0.45f, 0.72f, 0.53f).also {
        val l = sqrt(it[0] * it[0] + it[1] * it[1] + it[2] * it[2]); for (i in 0..2) it[i] /= l
    }
    private val eye = FloatArray(3)
    private var lastTime = 0L
    private var time = 0f

    // caméra
    private var camYaw = 0f
    private var orbitYaw = 0f
    private var orbitPitch = 0f
    private var smoothEye: FloatArray? = null
    private var camInit = false
    @Volatile var fps = 0f
    /** Ombres portées et herbe 3D (option « Graphismes : élevés »). */
    @Volatile var highQuality = true

    override fun onSurfaceCreated(unused: GL10?, config: EGLConfig?) {
        pTerrain = Gl.program(Shaders.TERRAIN_VS, Shaders.TERRAIN_FS)
        pRoad = Gl.program(Shaders.ROAD_VS, Shaders.ROAD_FS)
        pSky = Gl.program(Shaders.SKY_VS, Shaders.SKY_FS)
        pCar = Gl.program(Shaders.CAR_VS, Shaders.CAR_FS)
        pShadow = Gl.program(Shaders.SHADOW_VS, Shaders.SHADOW_FS)
        pMarker = Gl.program(Shaders.MARKER_VS, Shaders.MARKER_FS)
        texGrass = Textures.upload(Textures.grass())
        texNoise = Textures.upload(Textures.noise())
        texPlates = Textures.upload(Textures.plates(), repeat = false)
        pProps = Gl.program(Shaders.PROPS_VS, Shaders.PROPS_FS)
        pTree = Gl.program(Shaders.TREE_VS, Shaders.TREE_FS)
        pBillboard = Gl.program(Shaders.BILLBOARD_VS, Shaders.BILLBOARD_FS)
        pPropsDepth = Gl.program(Shaders.PROPS_VS, Shaders.PROPS_DEPTH_FS)
        pTreeDepth = Gl.program(Shaders.TREE_VS, Shaders.TREE_DEPTH_FS)
        texLeaf = Textures.upload(Textures.leaves(), repeat = false)
        pImp = Gl.program(Shaders.IMP_VS, Shaders.IMP_FS)
        pImpDepth = Gl.program(Shaders.IMP_VS, Shaders.IMP_DEPTH_FS)
        texImpCol = loadRgba("trees_imp_col.webp")
        texImpNrm = loadRgba("trees_imp_nrm.webp")
        texHedge = loadRgba("hedge_leaves.png", repeat = true)
        try {
            val ja = org.json.JSONArray(open("trees_imp.json").bufferedReader().readText())
            for (k in 0 until minOf(8, ja.length())) {
                val o = ja.getJSONObject(k); val h = o.getDouble("H").toFloat()
                impParams[k * 4] = o.getDouble("S").toFloat() / h; impParams[k * 4 + 1] = o.getDouble("R").toFloat() / h
            }
        } catch (e: Exception) { }
        pGrass = Gl.program(Shaders.GRASS_VS, Shaders.GRASS_FS)
        pCarDepth = Gl.program(Shaders.CAR_VS, Shaders.DEPTH_FS)
        shadows = ShadowMaps(2048)
        texLand = loadNearest("landcover.png")
        texLandFar = loadNearest("landfar.png")

        terrainChunks = ArrayList()
        buildTerrain(world.terrain, 32, null, 0)
        buildTerrain(world.far, 12, floatArrayOf(world.terrain.x0, world.terrain.z0, world.terrain.x1, world.terrain.z1), 1)
        world.decor.pano?.let { buildTerrain(it, 24, floatArrayOf(world.far.x0, world.far.z0, world.far.x1, world.far.z1), 2) }
        texSigns = Textures.upload(Textures.signs(world.decor.signNames), repeat = false)
        decalChunks = ArrayList()
        for (rc in world.decalChunks) decalChunks.add(Chunk(Mesh(Gl.floats(rc.vertices), Gl.ints(rc.indices), intArrayOf(3, 3, 4)), boundsOf(rc.vertices, 10)))
        streetChunks = ArrayList()
        for (pc in world.decor.street) {
            streetChunks.add(Chunk(Mesh(Gl.floats(pc.vertices), Gl.ints(pc.indices), intArrayOf(3, 3, 3, 2, 2)), boundsOf(pc.vertices, 13), 0, pc.bigIndices))
        }
        propChunks = ArrayList()
        for (pc in world.decor.props) {
            val b = Bounds(Float.MAX_VALUE, Float.MAX_VALUE, Float.MAX_VALUE, -Float.MAX_VALUE, -Float.MAX_VALUE, -Float.MAX_VALUE)
            val v = pc.vertices
            var k = 0
            while (k < v.size) {
                b.minX = min(b.minX, v[k]); b.maxX = max(b.maxX, v[k])
                b.minY = min(b.minY, v[k + 1]); b.maxY = max(b.maxY, v[k + 1])
                b.minZ = min(b.minZ, v[k + 2]); b.maxZ = max(b.maxZ, v[k + 2])
                k += 13
            }
            propChunks.add(Chunk(Mesh(Gl.floats(v), Gl.ints(pc.indices), intArrayOf(3, 3, 3, 2, 2)), b, 0, pc.bigIndices))
        }
        trees = TreeRenderer(world.decor.trees)
        texMask = loadNearest("grassmask.png")
        texAO = loadNearest("groundao.png", linear = true)
        grass = GrassRenderer(world.terrain)
        roadChunks = ArrayList()
        for (rc in world.roadChunks) {
            val b = Bounds(Float.MAX_VALUE, Float.MAX_VALUE, Float.MAX_VALUE, -Float.MAX_VALUE, -Float.MAX_VALUE, -Float.MAX_VALUE)
            val v = rc.vertices
            var k = 0
            while (k < v.size) {
                b.minX = min(b.minX, v[k]); b.maxX = max(b.maxX, v[k])
                b.minY = min(b.minY, v[k + 1]); b.maxY = max(b.maxY, v[k + 1])
                b.minZ = min(b.minZ, v[k + 2]); b.maxZ = max(b.maxZ, v[k + 2])
                k += 10
            }
            roadChunks.add(Chunk(Mesh(Gl.floats(v), Gl.ints(rc.indices), intArrayOf(3, 3, 4)), b))
        }

        val car = CarModel.load(try { open("car.bin").use { it.readBytes() } } catch (e: Exception) { null }) ?: CarModel.build()
        val layout = intArrayOf(3, 3, 4, 2)
        body = Mesh(Gl.floats(car.bodyV), Gl.ints(car.bodyI), layout)
        glass = Mesh(Gl.floats(car.glassV), Gl.ints(car.glassI), layout)
        wheel = Mesh(Gl.floats(car.wheelV), Gl.ints(car.wheelI), layout)
        steer = Mesh(Gl.floats(car.steerV), Gl.ints(car.steerI), layout)
        cylinder = buildCylinder()
        emptyVao = Gl.genVao()

        glClearColor(0.7f, 0.8f, 0.9f, 1f)
        lastTime = SystemClock.elapsedRealtimeNanos()
        onReady()
    }

    override fun onSurfaceChanged(unused: GL10?, w: Int, h: Int) {
        width = w; height = h
        glViewport(0, 0, w, h)
    }

    // ------------------------------------------------------------------------------ construction
    private fun boundsOf(v: FloatArray, stride: Int): Bounds {
        val b = Bounds(Float.MAX_VALUE, Float.MAX_VALUE, Float.MAX_VALUE, -Float.MAX_VALUE, -Float.MAX_VALUE, -Float.MAX_VALUE)
        var k = 0
        while (k < v.size) {
            b.minX = min(b.minX, v[k]); b.maxX = max(b.maxX, v[k])
            b.minY = min(b.minY, v[k + 1]); b.maxY = max(b.maxY, v[k + 1])
            b.minZ = min(b.minZ, v[k + 2]); b.maxZ = max(b.maxZ, v[k + 2])
            k += stride
        }
        return b
    }

    /** RVBA non prémultiplié (l'alpha porte la couverture ou la profondeur), avec mipmaps. */
    private fun loadRgba(name: String, repeat: Boolean = false): Int {
        val opts = android.graphics.BitmapFactory.Options().apply { inScaled = false; inPremultiplied = false; inPreferredConfig = android.graphics.Bitmap.Config.ARGB_8888 }
        val bmp = try { open(name).use { android.graphics.BitmapFactory.decodeStream(it, null, opts) } } catch (e: Exception) { null } ?: return 0
        val w = bmp.width; val h = bmp.height
        val px = IntArray(w * h)
        bmp.getPixels(px, 0, w, 0, 0, w, h)
        bmp.recycle()
        val buf = java.nio.ByteBuffer.allocateDirect(w * h * 4)
        for (c in px) { buf.put((c shr 16).toByte()); buf.put((c shr 8).toByte()); buf.put(c.toByte()); buf.put((c ushr 24).toByte()) }
        buf.position(0)
        val t = IntArray(1)
        glGenTextures(1, t, 0)
        glBindTexture(GL_TEXTURE_2D, t[0])
        glPixelStorei(GL_UNPACK_ALIGNMENT, 1)
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, buf)
        glGenerateMipmap(GL_TEXTURE_2D)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
        val wrap = if (repeat) GL_REPEAT else GL_CLAMP_TO_EDGE
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, wrap)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, wrap)
        return t[0]
    }

    private fun impUniforms(p: Int, dirMode: Boolean) {
        glUniform4fv(glGetUniformLocation(p, "uImp"), 8, impParams, 0)
        glUniform1f(glGetUniformLocation(p, "uDirMode"), if (dirMode) 1f else 0f)
        glUniform3f(glGetUniformLocation(p, "uFaceDir"), sun[0], 0f, sun[2])
        bindTex(p, "uImpCol", texImpCol, 9)
        bindTex(p, "uImpNrm", texImpNrm, 10)
    }

    private fun loadNearest(name: String, linear: Boolean = false): Int {
        // ARGB forcé : un PNG en niveaux de gris serait sinon décodé en ALPHA_8 (canal rouge vide)
        val opts = android.graphics.BitmapFactory.Options().apply { inScaled = false; inPremultiplied = false; inPreferredConfig = android.graphics.Bitmap.Config.ARGB_8888 }
        val bmp = open(name).use { android.graphics.BitmapFactory.decodeStream(it, null, opts) } ?: return 0
        val t = IntArray(1)
        glGenTextures(1, t, 0)
        glBindTexture(GL_TEXTURE_2D, t[0])
        glPixelStorei(GL_UNPACK_ALIGNMENT, 1)
        android.opengl.GLUtils.texImage2D(GL_TEXTURE_2D, 0, bmp, 0)
        val f = if (linear) GL_LINEAR else GL_NEAREST
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, f)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, f)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)
        bmp.recycle()
        return t[0]
    }

    private fun buildTerrain(g: HeightGrid, cells: Int, hole: FloatArray?, kind: Int) {
        val ncx = (g.nx - 1 + cells - 1) / cells
        val ncz = (g.nz - 1 + cells - 1) / cells
        for (cz in 0 until ncz) for (cx in 0 until ncx) {
            val i0 = cx * cells; val i1 = min(g.nx - 1, i0 + cells)
            val j0 = cz * cells; val j1 = min(g.nz - 1, j0 + cells)
            val w = i1 - i0 + 1; val h = j1 - j0 + 1
            val v = FloatArray(w * h * 6)
            val b = Bounds(g.x0 + i0 * g.step, Float.MAX_VALUE, g.z0 + j0 * g.step, g.x0 + i1 * g.step, -Float.MAX_VALUE, g.z0 + j1 * g.step)
            for (j in 0 until h) for (i in 0 until w) {
                val gi = i0 + i; val gj = j0 + j
                val y = g.at(gi, gj)
                val o = (j * w + i) * 6
                v[o] = g.x0 + gi * g.step; v[o + 1] = y; v[o + 2] = g.z0 + gj * g.step
                val hx = g.at(min(g.nx - 1, gi + 1), gj) - g.at(max(0, gi - 1), gj)
                val hz = g.at(gi, min(g.nz - 1, gj + 1)) - g.at(gi, max(0, gj - 1))
                val nx = -hx; val ny = 2 * g.step; val nz = -hz
                val l = sqrt(nx * nx + ny * ny + nz * nz)
                v[o + 3] = nx / l; v[o + 4] = ny / l; v[o + 5] = nz / l
                b.minY = min(b.minY, y); b.maxY = max(b.maxY, y)
            }
            val idx = ArrayList<Int>()
            for (j in 0 until h - 1) for (i in 0 until w - 1) {
                if (hole != null) {
                    val xa = g.x0 + (i0 + i) * g.step; val xb = xa + g.step
                    val za = g.z0 + (j0 + j) * g.step; val zb = za + g.step
                    if (xa >= hole[0] - 0.01f && xb <= hole[2] + 0.01f && za >= hole[1] - 0.01f && zb <= hole[3] + 0.01f) continue
                }
                val a = j * w + i; val bb = a + 1; val c = a + w; val d = c + 1
                // diagonale v00-v11 (identique à HeightGrid.height)
                idx.add(a); idx.add(c); idx.add(d)
                idx.add(a); idx.add(d); idx.add(bb)
            }
            if (idx.isEmpty()) continue
            terrainChunks.add(Chunk(Mesh(Gl.floats(v), Gl.ints(idx.toIntArray()), intArrayOf(3, 3)), b, kind))
        }
    }

    private fun buildCylinder(): Mesh {
        val seg = 24
        val v = FloatArray((seg + 1) * 2 * 3)
        for (k in 0..seg) {
            val a = 2 * PI * k / seg
            val x = cos(a).toFloat(); val z = sin(a).toFloat()
            v[k * 6] = x; v[k * 6 + 1] = 0f; v[k * 6 + 2] = z
            v[k * 6 + 3] = x; v[k * 6 + 4] = 1f; v[k * 6 + 5] = z
        }
        val idx = IntArray(seg * 6)
        for (k in 0 until seg) {
            val a = k * 2; val b = a + 1; val c = a + 2; val d = a + 3
            idx[k * 6] = a; idx[k * 6 + 1] = c; idx[k * 6 + 2] = b
            idx[k * 6 + 3] = b; idx[k * 6 + 4] = c; idx[k * 6 + 5] = d
        }
        return Mesh(Gl.floats(v), Gl.ints(idx), intArrayOf(3))
    }

    // ------------------------------------------------------------------------------ image
    override fun onDrawFrame(unused: GL10?) {
        val now = SystemClock.elapsedRealtimeNanos()
        val dt = ((now - lastTime) / 1e9f).coerceIn(0.001f, 0.05f)
        lastTime = now
        fps = fps * 0.95f + (1f / dt) * 0.05f
        time += dt
        // physique en sous-pas pour la stabilité
        val steps = max(1, (dt / 0.0084f).toInt() + 1)
        repeat(steps) { game.update(dt / steps) }

        updateCamera(dt)
        val hq = highQuality
        if (hq) renderShadows()
        shadowsOn = hq

        glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)
        val aspect = width.toFloat() / height
        val fovy = if (game.camMode == 1) 62f else 52f

        // ciel
        Matrix.perspectiveM(proj, 0, fovy, aspect, 1f, 100f)
        Matrix.multiplyMM(vp, 0, proj, 0, view, 0)
        Matrix.invertM(inv, 0, vp, 0)
        glDisable(GL_DEPTH_TEST)
        glUseProgram(pSky)
        common(pSky)
        glUniformMatrix4fv(glGetUniformLocation(pSky, "uInvVP"), 1, false, inv, 0)
        glUniform1f(glGetUniformLocation(pSky, "uTime"), time)
        bindTex(pSky, "uNoise", texNoise, 1)
        glBindVertexArray(emptyVao)
        glDrawArrays(GL_TRIANGLES, 0, 3)

        // tranches de profondeur : du plus loin au plus proche
        glEnable(GL_DEPTH_TEST)
        glDepthFunc(GL_LEQUAL)
        val slices = arrayOf(floatArrayOf(5000f, 260000f), floatArrayOf(500f, 6000f), floatArrayOf(36f, 600f), floatArrayOf(0.1f, 40f))
        for (s in slices) {
            glClear(GL_DEPTH_BUFFER_BIT)
            Matrix.perspectiveM(proj, 0, fovy, aspect, s[0], s[1])
            Matrix.multiplyMM(vp, 0, proj, 0, view, 0)
            frustum.set(vp)
            drawSlice(s[0], s[1])
        }
    }

    private fun common(p: Int) {
        glUniform3f(glGetUniformLocation(p, "uCamPos"), eye[0], eye[1], eye[2])
        glUniform3f(glGetUniformLocation(p, "uSunDir"), sun[0], sun[1], sun[2])
        // ombres : unités 6 et 7 (toujours affectées, deux types d'échantillonneurs ne peuvent partager une unité)
        glUniform1i(glGetUniformLocation(p, "uShadow0"), 6)
        glUniform1i(glGetUniformLocation(p, "uShadow1"), 7)
        val sm = shadows
        if (sm != null && shadowsOn) {
            glUniformMatrix4fv(glGetUniformLocation(p, "uShadowM0"), 1, false, sm.texM[0], 0)
            glUniformMatrix4fv(glGetUniformLocation(p, "uShadowM1"), 1, false, sm.texM[1], 0)
            glUniform3f(glGetUniformLocation(p, "uShadowP"), sm.texel(0), sm.texel(1), 1f)
        } else glUniform3f(glGetUniformLocation(p, "uShadowP"), 0f, 0f, 0f)
    }

    /** Cartes d'ombre du soleil : décor, équipements, arbres et véhicule vus depuis le soleil. */
    private fun renderShadows() {
        val sm = shadows ?: return
        // direction horizontale du regard (3e ligne de la matrice de vue)
        var fx = -view[2]; var fz = -view[10]
        val l = sqrt(fx * fx + fz * fz)
        if (l < 1e-3f) { fx = 0f; fz = -1f } else { fx /= l; fz /= l }
        sm.update(eye, fx, fz, sun)
        for (k in 0..1) {
            sm.begin(k)
            val lvp = sm.lightVP[k]
            glUseProgram(pPropsDepth)
            glUniformMatrix4fv(glGetUniformLocation(pPropsDepth, "uVP"), 1, false, lvp, 0)
            for (c in propChunks) {
                val b = c.bounds
                if (!sm.touches(k, b.minX, b.minZ, b.maxX, b.maxZ, b.maxY - b.minY)) continue
                if (k == 0 || minDist(b) < 600f) c.mesh.draw() else if (c.big > 0) c.mesh.draw(0, c.big)
            }
            for (c in streetChunks) {
                val b = c.bounds
                if (!sm.touches(k, b.minX, b.minZ, b.maxX, b.maxZ, 12f)) continue
                if (k == 0) c.mesh.draw() else if (c.big > 0) c.mesh.draw(0, c.big)
            }
            glUseProgram(pTreeDepth)
            glUniformMatrix4fv(glGetUniformLocation(pTreeDepth, "uVP"), 1, false, lvp, 0)
            bindTex(pTreeDepth, "uLeaf", texLeaf, 3)
            trees?.drawDepth(k == 0) { b -> sm.touches(k, b.minX, b.minZ, b.maxX, b.maxZ, 25f) }
            glUseProgram(pImpDepth)
            glUniformMatrix4fv(glGetUniformLocation(pImpDepth, "uVP"), 1, false, lvp, 0)
            glUniform3f(glGetUniformLocation(pImpDepth, "uCamPos"), eye[0], eye[1], eye[2])
            impUniforms(pImpDepth, true)
            trees?.drawImpostorDepth { b -> sm.touches(k, b.minX, b.minZ, b.maxX, b.maxZ, 25f) }
            glUseProgram(pCarDepth)
            glUniformMatrix4fv(glGetUniformLocation(pCarDepth, "uVP"), 1, false, lvp, 0)
            drawCarParts(pCarDepth, withSteer = false)
            sm.end(width, height)
        }
        glActiveTexture(GL_TEXTURE6); glBindTexture(GL_TEXTURE_2D, sm.tex[0])
        glActiveTexture(GL_TEXTURE7); glBindTexture(GL_TEXTURE_2D, sm.tex[1])
        glActiveTexture(GL_TEXTURE0)
    }

    private fun inRange(b: Bounds, near: Float, far: Float): Boolean {
        // distance mini/maxi de l'œil à la boîte
        val dx = max(max(b.minX - eye[0], 0f), eye[0] - b.maxX)
        val dy = max(max(b.minY - eye[1], 0f), eye[1] - b.maxY)
        val dz = max(max(b.minZ - eye[2], 0f), eye[2] - b.maxZ)
        val dmin = sqrt(dx * dx + dy * dy + dz * dz)
        val fx = max(abs(b.minX - eye[0]), abs(b.maxX - eye[0]))
        val fy = max(abs(b.minY - eye[1]), abs(b.maxY - eye[1]))
        val fz = max(abs(b.minZ - eye[2]), abs(b.maxZ - eye[2]))
        val dmax = sqrt(fx * fx + fy * fy + fz * fz)
        return dmin <= far && dmax >= near
    }

    private val carBounds = Bounds(0f, 0f, 0f, 0f, 0f, 0f)

    private fun minDist(b: Bounds): Float {
        val dx = max(max(b.minX - eye[0], 0f), eye[0] - b.maxX)
        val dy = max(max(b.minY - eye[1], 0f), eye[1] - b.maxY)
        val dz = max(max(b.minZ - eye[2], 0f), eye[2] - b.maxZ)
        return sqrt(dx * dx + dy * dy + dz * dz)
    }

    private fun drawSlice(near: Float, far: Float) {
        // terrain (zone jouable, anneau lointain, panorama alpin)
        glUseProgram(pTerrain)
        common(pTerrain)
        glUniformMatrix4fv(glGetUniformLocation(pTerrain, "uVP"), 1, false, vp, 0)
        bindTex(pTerrain, "uGrass", texGrass, 0)
        bindTex(pTerrain, "uNoise", texNoise, 1)
        bindTex(pTerrain, "uLand", texLand, 2)
        bindTex(pTerrain, "uLandFar", texLandFar, 3)
        bindTex(pTerrain, "uAO", texAO, 8)
        val t = world.terrain
        glUniform4f(glGetUniformLocation(pTerrain, "uLandRect"), t.x0, t.z0, t.x1 - t.x0, t.z1 - t.z0)
        glUniform4f(glGetUniformLocation(pTerrain, "uFarRect"), world.far.x0, world.far.z0, 16600f, 18200f)
        val uMode = glGetUniformLocation(pTerrain, "uMode")
        var mode = -1
        glEnable(GL_CULL_FACE)
        glCullFace(GL_BACK)
        glFrontFace(GL_CCW)
        for (c in terrainChunks) {
            if (!inRange(c.bounds, near, far) || !frustum.visible(c.bounds)) continue
            if (c.kind != mode) { mode = c.kind; glUniform1i(uMode, mode) }
            c.mesh.draw()
        }
        glDisable(GL_CULL_FACE)
        if (near > 4000f) return   // la tranche lointaine ne contient que le relief

        // routes : pas d'écriture de profondeur, l'ordre du tampon gère les recouvrements
        glUseProgram(pRoad)
        common(pRoad)
        glUniformMatrix4fv(glGetUniformLocation(pRoad, "uVP"), 1, false, vp, 0)
        bindTex(pRoad, "uGrass", texGrass, 0)
        bindTex(pRoad, "uNoise", texNoise, 1)
        bindTex(pRoad, "uAO", texAO, 8)
        glUniform4f(glGetUniformLocation(pRoad, "uAORect"), world.terrain.x0, world.terrain.z0, world.terrain.x1 - world.terrain.x0, world.terrain.z1 - world.terrain.z0)
        glDepthMask(false)
        glEnable(GL_POLYGON_OFFSET_FILL)
        glPolygonOffset(-1f, -2f)
        for (c in roadChunks) if (inRange(c.bounds, near, far) && frustum.visible(c.bounds)) c.mesh.draw()
        // marquages ponctuels et plateaux, par-dessus la chaussée
        glPolygonOffset(-2f, -4f)
        for (c in decalChunks) if (minDist(c.bounds) < 900f && inRange(c.bounds, near, far) && frustum.visible(c.bounds)) c.mesh.draw()
        glDisable(GL_POLYGON_OFFSET_FILL)

        val v = game.vehicle
        carBounds.minX = v.x - 3f; carBounds.maxX = v.x + 3f
        carBounds.minY = v.y - 1f; carBounds.maxY = v.y + 2.5f
        carBounds.minZ = v.z - 3f; carBounds.maxZ = v.z + 3f
        val carVisible = inRange(carBounds, near, far) && frustum.visible(carBounds)

        // ombre douce sous le véhicule
        if (carVisible) drawShadow()
        glDepthMask(true)

        // herbe 3D (30 m autour de la caméra)
        val gr = grass
        if (gr != null && shadowsOn && near < gr.radius) {
            glUseProgram(pGrass)
            common(pGrass)
            glUniformMatrix4fv(glGetUniformLocation(pGrass, "uVP"), 1, false, vp, 0)
            bindTex(pGrass, "uGrass", texGrass, 0)
            bindTex(pGrass, "uNoise", texNoise, 1)
            bindTex(pGrass, "uLand", texLand, 2)
            bindTex(pGrass, "uMask", texMask, 3)
            bindTex(pGrass, "uAO", texAO, 8)
            glUniform4f(glGetUniformLocation(pGrass, "uLandRect"), t.x0, t.z0, t.x1 - t.x0, t.z1 - t.z0)
            gr.draw(pGrass, eye, time) { p, name, tex, unit -> bindTex(p, name, tex, unit) }
        }

        // bâtiments, eau, pylônes
        glUseProgram(pProps)
        common(pProps)
        glUniformMatrix4fv(glGetUniformLocation(pProps, "uVP"), 1, false, vp, 0)
        glUniform1f(glGetUniformLocation(pProps, "uTime"), time)
        bindTex(pProps, "uNoise", texNoise, 1)
        bindTex(pProps, "uSigns", texSigns, 2)
        bindTex(pProps, "uHedge", texHedge, 11)
        for (c in propChunks) {
            if (!inRange(c.bounds, near, far) || !frustum.visible(c.bounds)) continue
            val d = minDist(c.bounds)
            if (d < 1400f) c.mesh.draw() else if (d < 5500f && c.big > 0) c.mesh.draw(0, c.big)
        }
        // équipements de la route : mobilier proche, trottoirs et terre-pleins plus loin
        for (c in streetChunks) {
            if (!inRange(c.bounds, near, far) || !frustum.visible(c.bounds)) continue
            val d = minDist(c.bounds)
            if (d < 650f) c.mesh.draw() else if (d < 1600f && c.big > 0) c.mesh.draw(0, c.big)
        }

        // arbres et haies
        trees?.draw(pTree, pBillboard, { b -> inRange(b, near, far) && frustum.visible(b) }, { b -> minDist(b) }) { p ->
            common(p)
            glUniformMatrix4fv(glGetUniformLocation(p, "uVP"), 1, false, vp, 0)
            bindTex(p, "uNoise", texNoise, 1)
            bindTex(p, "uLeaf", texLeaf, 3)
        }
        trees?.drawImpostors(pImp, { b -> inRange(b, near, far) && frustum.visible(b) }, { b -> minDist(b) }) { p ->
            common(p)
            glUniformMatrix4fv(glGetUniformLocation(p, "uVP"), 1, false, vp, 0)
            impUniforms(p, false)
        }

        if (carVisible) drawCar(opaque = true)
        drawMarker(near, far)
        if (carVisible) drawCar(opaque = false)
    }

    private fun bindTex(p: Int, name: String, tex: Int, unit: Int) {
        glActiveTexture(GL_TEXTURE0 + unit)
        glBindTexture(GL_TEXTURE_2D, tex)
        glUniform1i(glGetUniformLocation(p, name), unit)
    }

    private val corners = FloatArray(12)

    private fun drawShadow() {
        val v = game.vehicle
        val fx = sin(v.yaw); val fz = -cos(v.yaw); val rx = cos(v.yaw); val rz = sin(v.yaw)
        val hl = 2.55f; val hw = 1.08f
        val sx = floatArrayOf(-1f, 1f, 1f, -1f); val sz = floatArrayOf(-1f, -1f, 1f, 1f)
        val lift = max(0f, v.y - world.groundHeight(v.x, v.z, v.y + 1f))
        for (k in 0 until 4) {
            val x = v.x + rx * hw * sx[k] - fx * hl * sz[k]
            val z = v.z + rz * hw * sx[k] - fz * hl * sz[k]
            corners[k * 3] = x; corners[k * 3 + 1] = world.groundHeight(x, z, v.y + 1f) + 0.05f; corners[k * 3 + 2] = z
        }
        glUseProgram(pShadow)
        glUniformMatrix4fv(glGetUniformLocation(pShadow, "uVP"), 1, false, vp, 0)
        glUniform3fv(glGetUniformLocation(pShadow, "uCorners"), 4, corners, 0)
        // les vraies ombres portées existent : ne reste qu'un assombrissement de contact sous la caisse
        glUniform1f(glGetUniformLocation(pShadow, "uAlpha"), 0.38f * max(0f, 1f - lift / 3f))
        glEnable(GL_BLEND)
        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
        glEnable(GL_POLYGON_OFFSET_FILL)
        glPolygonOffset(-2f, -4f)
        glBindVertexArray(emptyVao)
        glDrawArrays(GL_TRIANGLE_FAN, 0, 4)
        glDisable(GL_POLYGON_OFFSET_FILL)
        glDisable(GL_BLEND)
    }

    private fun drawCar(opaque: Boolean) {
        val v = game.vehicle
        glUseProgram(pCar)
        common(pCar)
        glUniformMatrix4fv(glGetUniformLocation(pCar, "uVP"), 1, false, vp, 0)
        bindTex(pCar, "uPlates", texPlates, 0)
        glUniform1f(glGetUniformLocation(pCar, "uBrake"), if (game.input.brake > 0.05f) 1f else 0f)
        val uModel = glGetUniformLocation(pCar, "uModel")
        v.modelMatrix(model)
        if (!opaque) {
            glEnable(GL_BLEND)
            glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
            glDepthMask(false)
            glUniformMatrix4fv(uModel, 1, false, model, 0)
            glass.draw()
            glDepthMask(true)
            glDisable(GL_BLEND)
            return
        }
        drawCarParts(pCar, withSteer = true)
    }

    /** Caisse, volant et roues (avec le programme [p] : rendu normal ou carte d'ombre). */
    private fun drawCarParts(p: Int, withSteer: Boolean) {
        val v = game.vehicle
        val uModel = glGetUniformLocation(p, "uModel")
        v.modelMatrix(model)
        glUniformMatrix4fv(uModel, 1, false, model, 0)
        body.draw()
        if (!withSteer) { drawWheels(uModel); return }

        // volant
        Matrix.translateM(tmp, 0, model, 0, CarModel.STEERING_POS[0], CarModel.STEERING_POS[1], CarModel.STEERING_POS[2])
        Matrix.rotateM(tmp, 0, -(90f - CarModel.STEERING_TILT), 1f, 0f, 0f)
        Matrix.rotateM(tmp, 0, -game.input.steer * 220f, 0f, 0f, 1f)
        glUniformMatrix4fv(uModel, 1, false, tmp, 0)
        steer.draw()
        drawWheels(uModel)
    }

    private fun drawWheels(uModel: Int) {
        val v = game.vehicle
        // roues (sans le pompage de caisse)
        v.modelMatrix(tmp2, withHeave = false)
        val spinDeg = Math.toDegrees(v.wheelSpin.toDouble()).toFloat()
        for (k in 0 until 4) {
            val right = k % 2 == 1
            val front = k < 2
            val wx = (if (right) 1f else -1f) * (CarModel.TRACK / 2)
            val wz = if (front) CarModel.FRONT_AXLE_Z else CarModel.REAR_AXLE_Z
            Matrix.translateM(tmp, 0, tmp2, 0, wx, CarModel.WHEEL_R, wz)
            if (front) Matrix.rotateM(tmp, 0, Math.toDegrees(-v.steerAngle.toDouble()).toFloat(), 0f, 1f, 0f)
            if (!right) Matrix.rotateM(tmp, 0, 180f, 0f, 1f, 0f)
            Matrix.rotateM(tmp, 0, if (right) -spinDeg else spinDeg, 1f, 0f, 0f)
            glUniformMatrix4fv(uModel, 1, false, tmp, 0)
            wheel.draw()
        }
    }

    private fun drawMarker(near: Float, far: Float) {
        val j = game.job ?: return
        val t = j.target
        val gy = world.terrain.height(t.x, t.z)
        val b = Bounds(t.x - 6, gy, t.z - 6, t.x + 6, gy + 60, t.z + 6)
        if (!inRange(b, near, far) || !frustum.visible(b)) return
        glUseProgram(pMarker)
        glUniformMatrix4fv(glGetUniformLocation(pMarker, "uVP"), 1, false, vp, 0)
        glUniform4f(glGetUniformLocation(pMarker, "uCenter"), t.x, gy - 1f, t.z, 5.5f)
        glUniform1f(glGetUniformLocation(pMarker, "uHeight"), 60f)
        glUniform1f(glGetUniformLocation(pMarker, "uTime"), time)
        val pickup = j.target === j.offer.from
        if (pickup) glUniform4f(glGetUniformLocation(pMarker, "uColor"), 0.2f, 0.75f, 1.0f, 0.55f)
        else glUniform4f(glGetUniformLocation(pMarker, "uColor"), 1.0f, 0.65f, 0.1f, 0.55f)
        glEnable(GL_BLEND)
        glBlendFunc(GL_SRC_ALPHA, GL_ONE)
        glDepthMask(false)
        cylinder.draw()
        glDepthMask(true)
        glDisable(GL_BLEND)
    }

    // ------------------------------------------------------------------------------ caméra
    private fun updateCamera(dt: Float) {
        val v = game.vehicle
        orbitYaw += game.input.orbitDX * 0.006f
        orbitPitch = (orbitPitch + game.input.orbitDY * 0.004f).coerceIn(-0.6f, 1.1f)
        game.input.orbitDX = 0f; game.input.orbitDY = 0f

        // la caméra rattrape le cap du véhicule
        if (!camInit) { camYaw = v.yaw; camInit = true }
        var d = v.yaw - camYaw
        while (d > PI) d -= (2 * PI).toFloat()
        while (d < -PI) d += (2 * PI).toFloat()
        camYaw += d * min(1f, dt * 3.2f)
        // l'orbite revient doucement derrière le véhicule quand on roule
        if (v.speedKmh > 10f && abs(game.input.orbitDX) < 0.01f) {
            orbitYaw *= (1f - min(1f, dt * 0.6f))
            orbitPitch *= (1f - min(1f, dt * 0.6f))
        }

        val up = floatArrayOf(0f, 1f, 0f)
        when (game.camMode) {
            1 -> {
                // cabine : œil du conducteur
                v.modelMatrix(model)
                val e = CarModel.DRIVER_EYE
                val p = FloatArray(4)
                Matrix.multiplyMV(p, 0, model, 0, floatArrayOf(e[0], e[1], e[2], 1f), 0)
                val lookYaw = orbitYaw.coerceIn(-2.4f, 2.4f)
                val lookPitch = (-orbitPitch * 0.6f).coerceIn(-0.6f, 0.5f)
                val dir = floatArrayOf(sin(lookYaw) * cos(lookPitch), sin(lookPitch) - 0.06f, -cos(lookYaw) * cos(lookPitch), 0f)
                val wd = FloatArray(4)
                Matrix.multiplyMV(wd, 0, model, 0, dir, 0)
                val wu = FloatArray(4)
                Matrix.multiplyMV(wu, 0, model, 0, floatArrayOf(0f, 1f, 0f, 0f), 0)
                eye[0] = p[0]; eye[1] = p[1]; eye[2] = p[2]
                Matrix.setLookAtM(view, 0, eye[0], eye[1], eye[2], eye[0] + wd[0], eye[1] + wd[1], eye[2] + wd[2], wu[0], wu[1], wu[2])
                smoothEye = null
                return
            }
            else -> {
                val far = game.camMode == 2
                val dist = if (far) 14f else 7.6f
                val h = if (far) 4.2f else 2.0f
                val yaw = camYaw + orbitYaw
                val pitch = 0.12f + orbitPitch * 0.5f
                val tx = v.x; val ty = v.y + 1.35f; val tz = v.z
                var ex = tx - sin(yaw) * dist * cos(pitch)
                var ez = tz + cos(yaw) * dist * cos(pitch)
                var ey = ty + h - 1.35f + sin(pitch) * dist
                val ground = world.groundHeight(ex, ez, ey) + 0.6f
                if (ey < ground) ey = ground
                val s = smoothEye
                if (s == null) smoothEye = floatArrayOf(ex, ey, ez)
                else {
                    val f = min(1f, dt * 12f)
                    s[0] += (ex - s[0]) * f; s[1] += (ey - s[1]) * f; s[2] += (ez - s[2]) * f
                    ex = s[0]; ey = s[1]; ez = s[2]
                }
                eye[0] = ex; eye[1] = ey; eye[2] = ez
                Matrix.setLookAtM(view, 0, ex, ey, ez, tx, ty, tz, up[0], up[1], up[2])
            }
        }
    }
}
