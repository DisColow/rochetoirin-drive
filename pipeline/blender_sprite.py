"""Voiture en sprite : rendus de l'Espace (body.glb + wheel.glb, build_espace.py) sous tous les angles, avec Blender
(Cycles, caméra orthographique, fond transparent), pour build_car_sprite.py qui en fait du pixel art.

Vues : 32 directions autour de la voiture × 4 hauteurs de caméra × 3 braquages (gauche, droit, droite).
Deux passes par vue : couleur (éclairage de studio qui suit la caméra, comme les sprites précalculés des jeux
des années 90) et masque des feux (phares en vert, feux arrière en rouge) pour les allumer en jeu.
Repère du jeu : az = 0 caméra derrière la voiture, az = 90° caméra sur son flanc gauche ; el = hauteur (°).
Lancer avec le Python où bpy est installé :  <venv>/bin/python blender_sprite.py [--test]
Sortie : data/sprite_raw/{c,m}_<el>_<az>_<braquage>.png"""
import math, os, sys
import bpy
import mathutils

HERE = os.path.dirname(os.path.abspath(__file__))
CAR = os.path.join(HERE, "..", "godot", "assets", "car")
OUT = os.path.join(HERE, "data", "sprite_raw")
N_AZ = 32
ELS = [6, 20, 38, 60]
STEERS = [-0.38, 0.0, 0.38]          # rad, + = vers la gauche
W, H = 768, 654                      # 3 × le sprite final (256 × 218)
ORTHO = 6.6                          # largeur couverte (m) : Ranger de 5,4 m
CENTER = mathutils.Vector((0.0, 0.0, 0.9))

COLORS = {  # nom de matériau : (couleur, métal, rugosité, vernis) — teintes de la planche de référence de l'utilisateur
    # (bordeaux, bas de caisse et boucliers gris anthracite, vitres ardoise, enjoliveurs gris clair, phares jaune pâle)
    "paint": ((0.012, 0.012, 0.014), 0.0, 0.3, 0.6), "cover": ((0.62, 0.63, 0.63), 0.0, 0.4, 0.1), "beige": ((0.048, 0.051, 0.058), 0.0, 0.62, 0.0),
    "glass": ((0.085, 0.10, 0.12), 0.0, 0.22, 0.0), "chrome": ((0.7, 0.7, 0.72), 1.0, 0.2, 0.0),
    "rubber": ((0.022, 0.022, 0.026), 0.0, 0.9, 0.0), "plastic": ((0.03, 0.03, 0.034), 0.0, 0.6, 0.0),
    "lamp": ((0.95, 0.86, 0.55), 0.0, 0.15, 0.0), "tail": ((0.6, 0.03, 0.03), 0.0, 0.2, 0.0),
    "orange": ((0.95, 0.42, 0.04), 0.0, 0.2, 0.0), "fog": ((0.95, 0.86, 0.55), 0.0, 0.15, 0.0),
    "hubcap": ((0.55, 0.57, 0.6), 0.3, 0.4, 0.0), "interior": ((0.05, 0.05, 0.055), 0.0, 0.85, 0.0),
    "plate_front": ((0.12, 0.12, 0.13), 0.0, 0.5, 0.0), "plate_rear": ((0.12, 0.12, 0.13), 0.0, 0.5, 0.0),
}
MASK = {"lamp": (0.0, 1.0, 0.0), "tail": (1.0, 0.0, 0.0), "glass": (0.0, 0.0, 1.0)}


def material(name, col, metal, rough, coat):
    m = bpy.data.materials.new(name + "_s")
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*col, 1.0)
    b.inputs["Metallic"].default_value = metal
    b.inputs["Roughness"].default_value = rough
    if coat and "Coat Weight" in b.inputs:
        b.inputs["Coat Weight"].default_value = coat
        b.inputs["Coat Roughness"].default_value = 0.08
    return m


def emission(name, col):
    m = bpy.data.materials.new(name + "_m")
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    e = nt.nodes.new("ShaderNodeEmission"); e.inputs["Color"].default_value = (*col, 1.0); e.inputs["Strength"].default_value = 1.0
    o = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(e.outputs[0], o.inputs[0])
    return m


def setup():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 24
    sc.cycles.use_denoising = True
    sc.render.film_transparent = True
    sc.render.resolution_x, sc.render.resolution_y = W, H
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "Medium High Contrast"
    # carrosserie
    bpy.ops.import_scene.gltf(filepath=os.path.join(CAR, "body.glb"))
    body = [o for o in bpy.context.selected_objects if o.type == "MESH"]
    wheels = []
    import json
    meta = json.load(open(os.path.join(CAR, "meta.json")))
    meta_wb, meta_tr, r = meta["wheelbase"], meta["track"], meta["radius"]
    for front in (True, False):
        for right in (True, False):
            bpy.ops.import_scene.gltf(filepath=os.path.join(CAR, "wheel.glb"))
            root = bpy.context.selected_objects[0]
            while root.parent:
                root = root.parent
            piv = bpy.data.objects.new("pivot", None)
            sc.collection.objects.link(piv)
            # repère glTF du modèle : avant -Z, droite +X  ->  Blender : avant +Y, droite +X
            piv.location = ((1 if right else -1) * meta_tr / 2, (1 if front else -1) * meta_wb / 2, r)
            for o in bpy.context.selected_objects:
                if o.parent is None:
                    o.parent = piv
                    o.location = (0, 0, 0)
                    o.rotation_euler = (0, 0, math.pi if right else 0.0)
            wheels.append((piv, front))
    meshes = [o for o in sc.objects if o.type == "MESH"]
    mats_c, mats_m = {}, {}
    for o in meshes:
        for slot in o.material_slots:
            nm = slot.material.name.split(".")[0] if slot.material else ""
            if nm not in mats_c:
                c = COLORS.get(nm, ((0.1, 0.1, 0.1), 0.0, 0.6, 0.0))
                mats_c[nm] = material(nm, *c)
                mats_m[nm] = emission(nm, MASK.get(nm, (0.0, 0.0, 0.0)))
    # éclairage : soleil principal (au-dessus, à gauche de la caméra), contre-jour, ciel bleuté
    w = bpy.data.worlds.new("ciel"); sc.world = w; w.use_nodes = True
    nt = w.node_tree
    bg = nt.nodes["Background"]; bg.inputs["Strength"].default_value = 0.6
    # dégradé de studio : ciel clair en haut, sol sombre en bas (reflets francs dans les vitres, comme en pixel art)
    tc = nt.nodes.new("ShaderNodeTexCoord"); sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.45; ramp.color_ramp.elements[0].color = (0.06, 0.06, 0.07, 1)
    ramp.color_ramp.elements[1].position = 0.62; ramp.color_ramp.elements[1].color = (0.5, 0.54, 0.62, 1)
    mr = nt.nodes.new("ShaderNodeMapRange"); mr.inputs["From Min"].default_value = -1.0; mr.inputs["From Max"].default_value = 1.0
    nt.links.new(tc.outputs["Generated"], sep.inputs[0])
    nt.links.new(sep.outputs["Z"], mr.inputs["Value"]); nt.links.new(mr.outputs["Result"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bg.inputs["Color"])
    key = bpy.data.objects.new("key", bpy.data.lights.new("key", "SUN")); sc.collection.objects.link(key)
    key.data.energy = 2.7; key.data.angle = math.radians(6)
    rim = bpy.data.objects.new("rim", bpy.data.lights.new("rim", "SUN")); sc.collection.objects.link(rim)
    rim.data.energy = 1.1; rim.data.angle = math.radians(15)
    fill = bpy.data.objects.new("fill", bpy.data.lights.new("fill", "SUN")); sc.collection.objects.link(fill)
    fill.data.energy = 0.9; fill.data.angle = math.radians(30)
    camd = bpy.data.cameras.new("cam"); camd.type = "ORTHO"; camd.ortho_scale = ORTHO
    cam = bpy.data.objects.new("cam", camd); sc.collection.objects.link(cam); sc.camera = cam
    return sc, meshes, mats_c, mats_m, wheels, cam, key, rim, fill


def assign(meshes, mats):
    for o in meshes:
        for slot in o.material_slots:
            if slot.material is not None:
                nm = slot.material.name.split(".")[0].replace("_s", "").replace("_m", "")
                slot.material = mats.get(nm, slot.material)


def look(obj, target):
    d = target - obj.location
    obj.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()


def main():
    test = "--test" in sys.argv
    os.makedirs(OUT, exist_ok=True)
    sc, meshes, mats_c, mats_m, wheels, cam, key, rim, fill = setup()
    # noms d'origine des matériaux pour pouvoir permuter
    for o in meshes:
        for slot in o.material_slots:
            if slot.material is not None:
                slot.material = mats_c[slot.material.name.split(".")[0]]
    jobs = []
    for ei, el in enumerate(ELS):
        for a in range(N_AZ):
            for si, st in enumerate(STEERS):
                jobs.append((ei, el, a, si, st))
    if test:
        jobs = [(1, 20, 0, 1, 0.0), (1, 20, 4, 1, 0.0), (1, 20, 8, 0, -0.38), (1, 20, 16, 2, 0.38), (3, 60, 12, 1, 0.0)]
    for ei, el, a, si, st in jobs:
        f = "%s/c_%d_%02d_%d.png" % (OUT, ei, a, si)
        if os.path.exists(f) and os.path.exists(f.replace("/c_", "/m_")) and not test:
            continue
        az = 2 * math.pi * a / N_AZ
        e = math.radians(el)
        d = mathutils.Vector((-math.sin(az) * math.cos(e), -math.cos(az) * math.cos(e), math.sin(e)))
        cam.location = CENTER + d * 30.0
        look(cam, CENTER)
        # lumière principale : au-dessus, à gauche et un peu derrière la caméra ; contre-jour opposé
        right = d.cross(mathutils.Vector((0, 0, 1))).normalized()
        kd = (d * 0.6 - right * 0.7 + mathutils.Vector((0, 0, 1.1))).normalized()
        key.location = CENTER + kd * 10; look(key, CENTER)
        rd = (-d * 0.8 + right * 0.5 + mathutils.Vector((0, 0, 0.6))).normalized()
        rim.location = CENTER + rd * 10; look(rim, CENTER)
        fd = (d * 0.9 + right * 0.6 + mathutils.Vector((0, 0, 0.3))).normalized()   # appoint côté ombre
        fill.location = CENTER + fd * 10; look(fill, CENTER)
        for piv, front in wheels:
            piv.rotation_euler = (0, 0, st if front else 0.0)
        sc.cycles.samples = 24
        assign(meshes, mats_c)
        sc.render.filepath = f
        bpy.ops.render.render(write_still=True)
        sc.cycles.samples = 2
        sc.cycles.use_denoising = False
        assign(meshes, mats_m)
        sc.render.filepath = f.replace("/c_", "/m_")
        bpy.ops.render.render(write_still=True)
        sc.cycles.use_denoising = True
        print("vue", ei, a, si, flush=True)


if __name__ == "__main__":
    main()
