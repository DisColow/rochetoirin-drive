"""Véhicules lourds de la circulation (#136, choix de l'utilisateur : T5 et B1 de la planche) : tracteur avec remorque
et bus de ville, modèles Sketchfab CC BY de fetch_lourds.py (../godot/import/lourds/<nom>/model.glb) -> modèles au format
des voitures de la circulation (circulation.gd _preparer_modele : un maillage, des matériaux unis nommés ; roues
« rubber » tournantes, feux « Front_lights » / « Brake_lights », vitres « glass »).
  - orientation (avant vers +Y de Blender, soit -Z dans Godot), longueur réelle, centré, posé sur z = 0 ;
  - couleurs des textures relevées au centre de chaque face puis regroupées (k-moyennes) en quelques matériaux unis :
    le shader de la circulation n'a pas de textures (une couleur et un aspect par matériau) ;
  - roues (v7.00) : faces des pièces de roue (objets ou matériaux d'origine, `roues`) regroupées par essieu (k-moyennes
    sur la position en long) et par côté, matériaux « roue_<n>_c<couleur> » (n = essieu × 2 + côté) : circulation.gd
    en fait une roue par groupe, qui tourne sur son axe à la vitesse de son rayon ;
  - allégé (Decimate) au-delà de MAX_TRIS.
Usage : <python avec bpy> blender_lourds.py [dossier de sortie] (défaut : ../godot/assets/props)."""
import bpy, bmesh, math, os, sys, random
from mathutils import Vector

ICI = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(ICI, "..", "godot", "import", "lourds")
OUT = sys.argv[-1] if len(sys.argv) > 1 and os.path.isdir(sys.argv[-1]) else os.path.join(ICI, "..", "godot", "assets", "props")
# nom -> source, longueur (m), rotation autour de Z (°) pour mettre l'avant vers +Y, roues tournantes : objets ou
# matériaux d'origine des roues, matériau des feux, triangles au plus, couleurs
LOURDS = {
    "lourd_tracteur": dict(src="tracteur", long=7.4, rot=180.0, roues=dict(objets=("Jante", "Pneu"), essieux=3), feux=None,
                           max_tris=14000, couleurs=10),
    "lourd_bus": dict(src="bus", long=11.5, rot=90.0, roues=dict(materiaux=("material", "material_4"), essieux=2),
                      feux="light", max_tris=26000, couleurs=12),
}


def lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def texture_de(mat):
    if not mat or not mat.use_nodes:
        return None
    for n in mat.node_tree.nodes:
        if n.type == "TEX_IMAGE" and n.image:
            return n.image
    return None


def base_de(mat):
    if not mat or not mat.use_nodes:
        return (0.6, 0.6, 0.6)
    b = mat.node_tree.nodes.get("Principled BSDF")
    return tuple(b.inputs[0].default_value[:3]) if b else (0.6, 0.6, 0.6)


def kmoyennes(pts, k, n_iter=12):
    random.seed(1)
    centres = random.sample(pts, min(k, len(pts)))
    for _ in range(n_iter):
        groupes = [[] for _ in centres]
        for p in pts:
            i = min(range(len(centres)), key=lambda j: sum((p[t] - centres[j][t]) ** 2 for t in range(3)))
            groupes[i].append(p)
        centres = [tuple(sum(q[t] for q in g) / len(g) for t in range(3)) if g else centres[i]
                   for i, g in enumerate(groupes)]
    return centres


def convertir(nom, c):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, c["src"], "model.glb"))
    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    # couleur de chaque face (linéaire) : texture au centre UV de la face × couleur de base, sinon couleur de base ;
    # rôle : roue, feu, vitre, chrome, ou caisse
    faces = []        # (objet, index de face, couleur, rôle)
    pix_cache = {}
    for o in objs:
        me = o.data
        uv = me.uv_layers.active.data if me.uv_layers.active else None
        r = c["roues"] or {}
        roue_nom = any(t.lower() in o.name.lower() for t in r.get("objets", ()))
        for p in me.polygons:
            mat = me.materials[p.material_index] if me.materials else None
            nm = mat.name if mat else ""
            base = base_de(mat)
            img = texture_de(mat)
            col = base
            if img is not None and uv is not None:
                if img.name not in pix_cache:
                    pix_cache[img.name] = (img.size[0], img.size[1], img.pixels[:])
                w, h, px = pix_cache[img.name]
                u = sum(uv[i].uv.x for i in p.loop_indices) / p.loop_total
                v = sum(uv[i].uv.y for i in p.loop_indices) / p.loop_total
                x = int((u % 1.0) * w) % w
                y = int((v % 1.0) * h) % h
                j = (y * w + x) * 4
                col = tuple(lin(px[j + t]) * base[t] for t in range(3))
            role = "caisse"
            if roue_nom or nm in r.get("materiaux", ()):
                role = "roue"
            elif c["feux"] and nm == c["feux"]:
                role = "feu"
            elif "glass" in nm.lower():
                role = "vitre"
            elif "chrome" in nm.lower():
                role = "chrome"
            faces.append((o, p.index, col, role))
    # regroupement des couleurs de la caisse (roues comprises : jantes et pneus gardent leurs couleurs)
    pts = [f[2] for f in faces if f[3] in ("caisse", "roue")]
    centres = kmoyennes(random.sample(pts, min(len(pts), 4000)), c["couleurs"])
    mats = []
    for i, cc in enumerate(centres):
        m = bpy.data.materials.new("caisse_%d" % i)
        m.use_nodes = True
        b = m.node_tree.nodes["Principled BSDF"]
        b.inputs[0].default_value = (cc[0], cc[1], cc[2], 1.0)
        b.inputs["Roughness"].default_value = 0.6
        b.inputs["Metallic"].default_value = 0.0
        mats.append(m)

    def mat_nomme(n, col, rough, metal):
        m = bpy.data.materials.new(n)
        m.use_nodes = True
        b = m.node_tree.nodes["Principled BSDF"]
        b.inputs[0].default_value = (col[0], col[1], col[2], 1.0)
        b.inputs["Roughness"].default_value = rough
        b.inputs["Metallic"].default_value = metal
        return m
    m_roue = mat_nomme("rubber", (0.02, 0.02, 0.022), 0.9, 0.0)
    m_vitre = mat_nomme("glass", (0.03, 0.04, 0.05), 0.05, 0.0)
    m_chrome = mat_nomme("chrome", (0.75, 0.75, 0.75), 0.3, 1.0)
    m_av = mat_nomme("Front_lights", (0.85, 0.88, 0.9), 0.3, 0.0)
    m_ar = mat_nomme("Brake_lights", (0.55, 0.04, 0.04), 0.3, 0.0)
    # matériaux de chaque objet remplacés par les nouveaux (même liste pour tous les objets)
    tous = mats + [m_roue, m_vitre, m_chrome, m_av, m_ar]
    par_obj = {}
    for f in faces:
        par_obj.setdefault(f[0].name, []).append(f)
    for o in objs:
        me = o.data
        me.materials.clear()
        for m in tous:
            me.materials.append(m)
        attr = me.attributes.new("roue", "INT", "FACE")
        for (_, pi, col, role) in par_obj.get(o.name, []):
            attr.data[pi].value = 1 if role == "roue" else 0
            if role in ("caisse", "roue"):
                i = min(range(len(centres)), key=lambda j: sum((col[t] - centres[j][t]) ** 2 for t in range(3)))
            elif role == "roue":
                i = len(mats)
            elif role == "vitre":
                i = len(mats) + 1
            elif role == "chrome":
                i = len(mats) + 2
            else:
                i = len(mats) + 3          # feu : avant ou arrière, décidé après l'orientation
            me.polygons[pi].material_index = i
    # un seul objet, transformations appliquées
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.context.view_layer.update()
    for o in objs:
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mw
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    bpy.context.view_layer.update()
    ob.data.transform(ob.matrix_world)
    ob.matrix_world.identity()
    ob.data.transform(__import__("mathutils").Matrix.Rotation(math.radians(c["rot"]), 4, "Z"))
    vs = [v.co for v in ob.data.vertices]
    lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    s = c["long"] / (hi.y - lo.y)
    off = Vector((-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, -lo.z))
    for v in ob.data.vertices:
        v.co = (v.co + off) * s
    vs = [v.co for v in ob.data.vertices]
    print("%s avant allègement : x %.2f..%.2f, y %.2f..%.2f, z %.2f..%.2f" % (nom, min(v.x for v in vs), max(v.x for v in vs),
          min(v.y for v in vs), max(v.y for v in vs), min(v.z for v in vs), max(v.z for v in vs)))
    # feux : à l'arrière (y < 0) -> feux stop
    me = ob.data
    # roues : essieux (k-moyennes sur y) et côté (x) ; matériau « roue_<n>_c<couleur> » de la couleur de la face
    attr = me.attributes.get("roue")
    if attr is not None and c["roues"]:
        rf = [p for p in me.polygons if attr.data[p.index].value == 1]
        ys = sorted(p.center.y for p in rf)
        k = c["roues"]["essieux"]
        cy = [ys[int((i + 0.5) * len(ys) / k)] for i in range(k)]
        for _ in range(20):
            gr = [[] for _ in cy]
            for y in ys:
                gr[min(range(k), key=lambda j: abs(y - cy[j]))].append(y)
            cy = [sum(g) / len(g) if g else cy[i] for i, g in enumerate(gr)]
        cy.sort(reverse=True)                       # essieu 0 à l'avant
        nouv = {}
        for p in rf:
            e = min(range(k), key=lambda j: abs(p.center.y - cy[j]))
            g = e * 2 + (0 if p.center.x < 0.0 else 1)
            cle = (g, p.material_index)
            if cle not in nouv:
                base = me.materials[p.material_index]
                m = base.copy()
                m.name = "roue_%d_c%d" % cle
                me.materials.append(m)
                nouv[cle] = len(me.materials) - 1
            p.material_index = nouv[cle]
        print("%s : %d faces de roue, essieux à y = %s, %d matériaux de roue" % (nom, len(rf),
              ", ".join("%.2f" % (y * 1.0) for y in cy), len(nouv)))
    for p in me.polygons:
        if p.material_index == len(mats) + 3 and p.center.y < 0.0:
            p.material_index = len(mats) + 4
    # allègement
    n = sum(len(p.vertices) - 2 for p in me.polygons)
    if n > c["max_tris"]:
        d = ob.modifiers.new("dec", "DECIMATE")
        d.ratio = c["max_tris"] / n
        bpy.ops.object.modifier_apply(modifier="dec")
        # l'effondrement des arêtes laisse parfois quelques sommets aberrants (géométrie non fermée) : supprimés
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        hors = [v for v in bm.verts if abs(v.co.x) > c["long"] or abs(v.co.y) > c["long"] * 0.55 or v.co.z < -0.1 or v.co.z > 5.0]
        bmesh.ops.delete(bm, geom=hors, context="VERTS")
        bm.to_mesh(ob.data)
        bm.free()
        print("%s : %d sommets aberrants supprimés" % (nom, len(hors)))
    n2 = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    vs = [v.co for v in ob.data.vertices]
    taille = (max(v.x for v in vs) - min(v.x for v in vs), max(v.y for v in vs) - min(v.y for v in vs), max(v.z for v in vs))
    ob.name = nom
    f = os.path.join(OUT, nom + ".glb")
    bpy.ops.export_scene.gltf(filepath=f, export_format="GLB", use_selection=False, export_materials="EXPORT",
                              export_texcoords=False, export_normals=True, export_apply=True)
    print("%s : %d -> %d triangles, largeur %.2f, longueur %.2f, hauteur %.2f m -> %s" % (nom, n, n2, taille[0], taille[1],
                                                                                        taille[2], f))


for nom, c in LOURDS.items():
    convertir(nom, c)
