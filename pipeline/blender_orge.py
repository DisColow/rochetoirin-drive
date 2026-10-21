"""Épis des champs de céréales (v6.72, #117, choix « C » : épis d'orge scannée devant le feuillage du blé actuel).
Orge « Barley, Hordeum vulgare » (ffish.asia / floraZia, CC0, Sketchfab 5dbaa85638694660ac2f74df49aeb795 ; jeton dans
SKETCHFAB_TOKEN, jamais écrit) : trois tiges scannées, posées en rang dense devant la caméra, en albédo (sans
éclairage, fond transparent) comme tools/bake_cultures.gd, au format d'une touffe de crops.gd : 2,4 m de large sur
1,2 m de haut (HCASE des céréales), 4 variantes. Tiges gardées à 15 cm des bords (touffes voisines sans tige coupée),
de plus en plus rares vers les bords et de hauteurs variées : la touffe n'a pas une silhouette de rectangle.
Sorties : data/orge/touffe_ble_<v>.png (1024 × 512), reprises par build_touffes.py (céréales).
<venv bpy>/bin/python blender_orge.py"""
import io, json, math, os, random, urllib.request, zipfile
import bpy
import mathutils

HERE = os.path.dirname(os.path.abspath(__file__))
D = os.path.join(HERE, "data", "orge")
UID = "5dbaa85638694660ac2f74df49aeb795"
LARGEUR, HAUT = 2.4, 1.2          # crops.gd LARGEUR, HCASE[1]
DENSITE = 70                      # tiges par mètre de rang (160 dans le candidat C de la planche : rangées trop opaques en jeu)


def telecharger():
    if os.path.exists(os.path.join(D, "scene.gltf")):
        return
    tok = os.environ.get("SKETCHFAB_TOKEN", "")
    if not tok:
        raise SystemExit("SKETCHFAB_TOKEN absent")
    h = {"Authorization": "Token " + tok}
    dl = json.loads(urllib.request.urlopen(urllib.request.Request(
        "https://api.sketchfab.com/v3/models/%s/download" % UID, headers=h)).read())
    os.makedirs(D, exist_ok=True)
    zipfile.ZipFile(io.BytesIO(urllib.request.urlopen(dl["gltf"]["url"]).read())).extractall(D)


def scene_vide():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 16
    sc.cycles.max_bounces = 0
    sc.cycles.use_denoising = False
    sc.render.film_transparent = True
    sc.render.resolution_x, sc.render.resolution_y = 1024, 512
    sc.view_settings.view_transform = "Standard"
    w = bpy.data.worlds.new("w")
    w.color = (0, 0, 0)
    sc.world = w
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = LARGEUR                      # largeur (côté le plus long de l'image)
    cam.location = (0, -10, HAUT / 2)
    cam.rotation_euler = (math.radians(90), 0, 0)
    sc.collection.objects.link(cam)
    sc.camera = cam
    return sc


def tiges():
    """Les trois tiges du scan (une par matériau), pied au centre, 1 m de haut, en émission (albédo)."""
    avant = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(D, "scene.gltf"))
    neufs = [o for o in bpy.data.objects if o not in avant]
    mesh = [o for o in neufs if o.type == "MESH"]
    for o in mesh:
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mw
    for o in [o for o in neufs if o.type != "MESH"]:
        bpy.data.objects.remove(o)
    par_mat = {}
    for o in mesh:
        noms = [m.name for m in o.data.materials if m]
        if not noms or noms[0] == "Material.001":       # socle du scan
            bpy.data.objects.remove(o)
            continue
        par_mat.setdefault(noms[0], []).append(o)
    out = []
    for k, lst in sorted(par_mat.items()):
        bpy.ops.object.select_all(action="DESELECT")
        for o in lst:
            o.select_set(True)
        bpy.context.view_layer.objects.active = lst[0]
        if len(lst) > 1:
            bpy.ops.object.join()
        o = bpy.context.view_layer.objects.active
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        bb = [mathutils.Vector(v) for v in o.bound_box]
        mn = mathutils.Vector([min(v[i] for v in bb) for i in range(3)])
        mx = mathutils.Vector([max(v[i] for v in bb) for i in range(3)])
        s = 1.0 / (mx.z - mn.z)
        for v in o.data.vertices:
            v.co = (v.co - mathutils.Vector(((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, mn.z))) * s
        for m in o.data.materials:
            emission(m)
        out.append(o)
    return out


def emission(m):
    if not m or not m.use_nodes:
        return
    nt = m.node_tree
    bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is None:
        return
    sortie = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
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
    nt.links.new(mix.outputs[0], sortie.inputs["Surface"])


def main():
    telecharger()
    for v in range(4):
        sc = scene_vide()
        modeles = tiges()
        rng = random.Random(117 * 10 + v)
        for i in range(round(LARGEUR * DENSITE)):
            x = rng.uniform(-LARGEUR / 2 + 0.15, LARGEUR / 2 - 0.15)
            if rng.random() > max(0.12, min(1.0, (LARGEUR / 2 - 0.15 - abs(x)) / 0.45)):
                continue                                # moins de tiges vers les bords de la touffe
            o = rng.choice(modeles).copy()
            sc.collection.objects.link(o)
            o.location = (x, rng.uniform(-0.3, 0.3), 0)
            o.rotation_euler = (rng.uniform(-0.1, 0.1), rng.uniform(-0.12, 0.12), rng.uniform(0, 2 * math.pi))
            h = rng.uniform(0.72, 1.08)
            o.scale = (h, h, h)
        for m in modeles:
            m.hide_render = True
        sc.render.filepath = os.path.join(D, "touffe_ble_%d.png" % v)
        bpy.ops.render.render(write_still=True)
        print("OK", sc.render.filepath)


main()
