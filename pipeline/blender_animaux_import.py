"""Animaux des prés d'après les modèles Sketchfab (fetch_animaux.py) : import glTF, squelette retiré (pose de repos),
maillages fusionnés, mis à la taille réelle (longueur du corps), tête vers +z glTF (-y Blender), sabots à y = 0,
textures de couleur ramenées à 1024 px. Sortie : ../godot/assets/animaux/<nom>.glb (remplace les modèles de
blender_animaux.py ; clôture et piquet restent faits là).
  <venv>/bin/python blender_animaux_import.py [--preview]   (--preview : vues de profil pour vérifier l'orientation)"""
import math, os, sys
import bpy
import mathutils

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "godot", "import", "animaux")
OUT = os.path.join(HERE, "..", "godot", "assets", "animaux")
# nom : (longueur du corps en m, rotation autour de la verticale en degrés pour mettre la tête vers -y Blender)
SPEC = {"vache": (2.4, 0.0), "mouton": (1.3, 0.0), "cheval": (2.4, 0.0)}


def load(name):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, name, "scene.gltf"))
    # formes d'affichage des os (icosphère créée par l'importeur) : hors du modèle, supprimées
    def in_model(o):
        while o.parent:
            o = o.parent
        return o.name.startswith("Sketchfab_model")
    for o in list(bpy.data.objects):
        if o.type == "MESH" and not in_model(o):
            bpy.data.objects.remove(o, do_unlink=True)
    # squelettes retirés : le maillage garde sa pose de repos
    for o in list(bpy.data.objects):
        for m in list(getattr(o, "modifiers", [])):
            if m.type == "ARMATURE":
                o.modifiers.remove(m)
    for o in list(bpy.data.objects):
        if o.type != "MESH":
            # garder la transformation monde des enfants
            for c in o.children:
                mw = c.matrix_world.copy(); c.parent = None; c.matrix_world = mw
    for o in list(bpy.data.objects):
        if o.type != "MESH":
            bpy.data.objects.remove(o, do_unlink=True)
    meshes = sorted([o for o in bpy.data.objects if o.type == "MESH"], key=lambda o: -len(o.data.polygons))
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    if len(meshes) > 1:
        bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    for vg in list(o.vertex_groups):
        o.vertex_groups.remove(vg)
    return o


def bbox(o):
    V = [o.matrix_world @ v.co for v in o.data.vertices]
    mn = mathutils.Vector((min(v.x for v in V), min(v.y for v in V), min(v.z for v in V)))
    mx = mathutils.Vector((max(v.x for v in V), max(v.y for v in V), max(v.z for v in V)))
    return mn, mx


def normalize(o, length, rot):
    mn, mx = bbox(o)
    # corps le long de y (Blender) : si le plus long côté horizontal est x, quart de tour
    if (mx.x - mn.x) > (mx.y - mn.y):
        o.rotation_euler = (0, 0, math.radians(90))
        bpy.ops.object.transform_apply(rotation=True)
    o.rotation_euler = (0, 0, math.radians(rot))
    bpy.ops.object.transform_apply(rotation=True)
    mn, mx = bbox(o)
    s = length / (mx.y - mn.y)
    o.scale = (s, s, s)
    bpy.ops.object.transform_apply(scale=True)
    mn, mx = bbox(o)
    o.location = (-(mn.x + mx.x) / 2, -(mn.y + mx.y) / 2, -mn.z)
    bpy.ops.object.transform_apply(location=True)
    return bbox(o)


def preview(name, o):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"; sc.cycles.device = "CPU"; sc.cycles.samples = 8
    w = bpy.data.worlds.new("w"); sc.world = w; w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.2
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN")); sc.collection.objects.link(sun)
    sun.rotation_euler = (math.radians(40), 0, math.radians(60)); sun.data.energy = 3.0
    sc.render.resolution_x, sc.render.resolution_y = 640, 360
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam); sc.camera = cam
    cam.data.type = "ORTHO"; cam.data.ortho_scale = 3.2
    cam.location = (8, 0, 0.8); cam.rotation_euler = (math.radians(90), 0, math.radians(90))   # regarde vers -x : -y à gauche
    sc.render.filepath = os.path.join(HERE, "data", "animaux_%s.png" % name)
    bpy.ops.render.render(write_still=True)


def main():
    pv = "--preview" in sys.argv
    os.makedirs(OUT, exist_ok=True)
    for name, (length, rot) in SPEC.items():
        o = load(name)
        mn, mx = normalize(o, length, rot)
        print(name, "taille", [round(v, 2) for v in (mx - mn)], "faces", len(o.data.polygons), flush=True)
        for m in o.data.materials:
            if m and m.use_nodes:
                # couleur seulement (le jeu n'utilise pas les cartes de normales / rugosité de ces modèles)
                for n in list(m.node_tree.nodes):
                    if n.type == "TEX_IMAGE" and n.image:
                        im = n.image
                        if max(im.size) > 1024:
                            im.scale(1024, 1024 * im.size[1] // max(im.size[0], 1)) if im.size[0] >= im.size[1] else im.scale(1024 * im.size[0] // im.size[1], 1024)
                bsdf = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
                if bsdf:
                    for inp in ("Normal", "Metallic", "Roughness"):
                        for l in list(bsdf.inputs[inp].links):
                            m.node_tree.links.remove(l)
        if pv:
            preview(name, o)
            continue
        bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, name + ".glb"), export_format="GLB", use_selection=False,
                                  export_image_format="JPEG", export_apply=True, export_skins=False, export_animations=False)


if __name__ == "__main__":
    main()
