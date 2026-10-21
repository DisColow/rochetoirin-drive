"""Candidats pour le blé (#117, 21/10) : bandes vues de côté (albédo, sans éclairage, fond transparent) comme
tools/bake_cultures.gd, 3 m de large. Modèles téléchargés à part (Sketchfab, jeton) : orge scannée ffish.asia /
floraZia (CC0, 5dbaa85638694660ac2f74df49aeb795) et épi DigitalFlow (CC BY, 22fc307dabed485e8a53b6a3543842f8).
Planche : docs/apercus/ble_candidats.jpg (A actuel, B orge dense : N_ORGE=480, C = B devant le feuillage de A).
<venv bpy>/bin/python candidats_ble.py -- <sortie> <orge/scene.gltf> <ble3/scene.gltf>"""
import bpy, sys, math, random, mathutils

args = sys.argv[sys.argv.index("--") + 1:]
OUT, ORGE, BLE3 = args
TAILLE = 3.0


def importer(chemin):
    avant = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=chemin)
    neufs = [o for o in bpy.data.objects if o not in avant]
    for o in neufs:
        if o.type == "MESH":
            o.select_set(True)
    for o in neufs:
        if o.type == "MESH":
            bpy.context.view_layer.objects.active = o
            mw = o.matrix_world.copy()
            o.parent = None
            o.matrix_world = mw
    mesh = [o for o in neufs if o.type == "MESH"]
    for o in [o for o in neufs if o.type != "MESH"]:
        bpy.data.objects.remove(o)
    return mesh


def joindre(objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return o


def normaliser(o, hauteur):
    """Pied au centre (x, y), base à z = 0, hauteur donnée."""
    bb = [o.matrix_world @ mathutils.Vector(v) for v in o.bound_box]
    mn = mathutils.Vector([min(v[i] for v in bb) for i in range(3)])
    mx = mathutils.Vector([max(v[i] for v in bb) for i in range(3)])
    k = hauteur / (mx.z - mn.z)
    for v in o.data.vertices:
        v.co = (v.co - mathutils.Vector(((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, mn.z))) * k
    o.location = (0, 0, 0)
    return o


def emission(o):
    for m in o.data.materials:
        if not m or not m.use_nodes:
            continue
        nt = m.node_tree
        bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
        out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
        if bsdf is None:
            continue
        em = nt.nodes.new("ShaderNodeEmission")
        tr = nt.nodes.new("ShaderNodeBsdfTransparent")
        mix = nt.nodes.new("ShaderNodeMixShader")
        c = bsdf.inputs["Base Color"]
        if c.is_linked:
            nt.links.new(c.links[0].from_socket, em.inputs["Color"])
        else:
            em.inputs["Color"].default_value = c.default_value
        a = bsdf.inputs["Alpha"]
        if a.is_linked:
            nt.links.new(a.links[0].from_socket, mix.inputs["Fac"])
        else:
            mix.inputs["Fac"].default_value = 1.0
        nt.links.new(tr.outputs[0], mix.inputs[1])
        nt.links.new(em.outputs[0], mix.inputs[2])
        nt.links.new(mix.outputs[0], out.inputs["Surface"])


def mat_tige(col):
    m = bpy.data.materials.new("tige")
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        if n.type != "OUTPUT_MATERIAL":
            nt.nodes.remove(n)
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = col
    nt.links.new(em.outputs[0], nt.nodes["Material Output"].inputs["Surface"])
    return m


def scene_vide():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 16
    sc.cycles.max_bounces = 0
    sc.cycles.use_denoising = False
    sc.render.film_transparent = True
    sc.render.resolution_x = sc.render.resolution_y = 1024
    sc.view_settings.view_transform = "Standard"
    w = bpy.data.worlds.new("w"); w.color = (0, 0, 0); sc.world = w
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.type = "ORTHO"; cam.data.ortho_scale = TAILLE
    cam.location = (0, -10, TAILLE / 2); cam.rotation_euler = (math.radians(90), 0, 0)
    sc.collection.objects.link(cam); sc.camera = cam
    return sc


def bande(modeles, n, hmin, hmax, prof, nom, graine=7):
    rng = random.Random(graine)
    sc = bpy.context.scene
    for i in range(n):
        src = rng.choice(modeles)
        o = src.copy()                      # même maillage (instance liée)
        sc.collection.objects.link(o)
        x = rng.uniform(-TAILLE / 2 - 0.2, TAILLE / 2 + 0.2)
        y = rng.uniform(-prof / 2, prof / 2)
        h = rng.uniform(hmin, hmax)
        o.location = (x, y, 0)
        o.rotation_euler = (rng.uniform(-0.08, 0.08), rng.uniform(-0.1, 0.1), rng.uniform(0, 2 * math.pi))
        o.scale = (h, h, h)
    for m in modeles:
        m.hide_render = True
    sc.render.filepath = OUT + "/bande_%s.png" % nom
    bpy.ops.render.render(write_still=True)
    print("OK", nom)


# orge (ffish.asia / floraZia, CC0) : trois tiges scannées, une par matériau
scene_vide()
objs = importer(ORGE)
par_mat = {}
for o in objs:
    mats = [m.name for m in o.data.materials if m]
    if not mats or mats[0] == "Material.001":         # socle / étiquette du scan
        bpy.data.objects.remove(o)
        continue
    par_mat.setdefault(mats[0], []).append(o)
tiges = []
for k, lst in sorted(par_mat.items()):
    t = normaliser(joindre(lst), 1.0)
    emission(t)
    tiges.append(t)
print("orge : tiges", len(tiges))
bande(tiges, int(__import__("os").environ.get("N_ORGE", "230")), 0.85, 1.05, 0.6, "orge" + __import__("os").environ.get("SUFFIXE", ""))
if __import__("os").environ.get("SEULEMENT_ORGE"):
    raise SystemExit

# blé (DigitalFlow, CC BY) : un épi détaillé, posé sur une tige fine
scene_vide()
epi = normaliser(joindre(importer(BLE3)), 0.17)
emission(epi)
bpy.ops.mesh.primitive_cylinder_add(vertices=6, radius=0.003, depth=0.85, location=(0, 0, 0.425))
tige = bpy.context.view_layer.objects.active
tige.data.materials.append(mat_tige((0.72, 0.62, 0.36, 1.0)))
epi.location = (0, 0, 0.83)
bpy.ops.object.select_all(action="DESELECT")
epi.select_set(True); tige.select_set(True)
bpy.context.view_layer.objects.active = tige
bpy.ops.object.join()
plant = bpy.context.view_layer.objects.active
print("blé : faces", len(plant.data.polygons))
bande([plant], 230, 0.85, 1.05, 0.6, "ble3")
