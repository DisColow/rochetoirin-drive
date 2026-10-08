"""Modèles 3D des commerces, faits avec Blender (module Python bpy 4.2, sans interface) : arêtes biseautées, volumes
propres, matériaux nommés (remplacés en jeu par les shaders du jeu).
Lancer avec le Python où bpy est installé :  <venv>/bin/python blender_commerces.py
Repère des modèles (après export glTF) : x le long de la façade, y en haut, +z vers la rue ; origine au pied du mur.
Sorties : ../godot/assets/shops/<nom>.glb
 - vitrine (module de 1 m), porte (1 m), enseigne (bandeau 1 × 1, face avant UV 0..1 -> case de l'atlas),
   banne (store de 1 m), croix (pharmacie), carotte (tabac), totem, ombriere (station-service), pompe,
   abri_caddies, terrasse (table, chaises, parasol), auvent (entrée de supermarché) ;
 - habillage des devantures d'après les photos Street View (couleur d'instance, matériau « bande ») : bandeau (planche
   de 1 × 0,8 m au-dessus des vitrines), pilastre (montant de 3,8 m), coffre_rideau (coffre de rideau métallique de
   1 m), porte_sectionnelle (porte d'atelier à lames, module de 1 × 3 m), bardage (panneau nervuré de 1 × 1 m des
   grandes surfaces, mis à l'échelle de la façade)."""
import math, os
import bpy
import bmesh

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "godot", "assets", "shops")
MATS = {}


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    MATS.clear()


def mat(name, col=(0.8, 0.8, 0.8), metal=0.0, rough=0.5):
    if name not in MATS:
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        b = m.node_tree.nodes["Principled BSDF"]
        b.inputs["Base Color"].default_value = (*col, 1.0)
        b.inputs["Metallic"].default_value = metal
        b.inputs["Roughness"].default_value = rough
        MATS[name] = m
    return MATS[name]


def obj_from_bm(bm, name, m):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(o)
    o.data.materials.append(m)
    return o


def box(name, c, s, m, bevel=0.0, seg=2):
    """Pavé centré en c (x, y=profondeur Blender, z haut), tailles s ; arêtes biseautées."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co.x = c[0] + v.co.x * s[0]
        v.co.y = c[1] + v.co.y * s[1]
        v.co.z = c[2] + v.co.z * s[2]
    o = obj_from_bm(bm, name, m)
    if bevel > 0:
        md = o.modifiers.new("biseau", "BEVEL")
        md.width = bevel; md.segments = seg; md.limit_method = "ANGLE"
    return o


def cyl(name, c, r, h, m, n=12, axis="Z"):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=n, radius1=r, radius2=r, depth=h)
    rot = {"Z": None, "X": ("Y", math.pi / 2), "Y": ("X", math.pi / 2)}[axis]
    if rot:
        import mathutils
        bmesh.ops.rotate(bm, verts=bm.verts, matrix=mathutils.Matrix.Rotation(rot[1], 3, rot[0]))
    for v in bm.verts:
        v.co.x += c[0]; v.co.y += c[1]; v.co.z += c[2]
    return obj_from_bm(bm, name, m)


def plane(name, c, w, h, m, facing=-1):
    """Rectangle vertical w × h centré en c, face vers -y (la rue) ; UV 0..1."""
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    x0, x1 = c[0] - w / 2, c[0] + w / 2
    z0, z1 = c[2] - h / 2, c[2] + h / 2
    vs = [bm.verts.new((x0, c[1], z0)), bm.verts.new((x1, c[1], z0)), bm.verts.new((x1, c[1], z1)), bm.verts.new((x0, c[1], z1))]
    f = bm.faces.new(vs if facing < 0 else list(reversed(vs)))
    uvs = [(0, 1), (1, 1), (1, 0), (0, 0)] if facing < 0 else [(1, 1), (0, 1), (0, 0), (1, 0)]
    for lp, u in zip(f.loops, uvs):
        lp[uv].uv = u
    bm.normal_update()
    return obj_from_bm(bm, name, m)


def export(name):
    bpy.ops.object.select_all(action="SELECT")
    bpy.context.view_layer.objects.active = bpy.context.selected_objects[0]
    bpy.ops.object.convert(target="MESH")              # applique biseaux et épaisseurs avant la fusion
    bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    o.name = name
    bpy.ops.object.shade_smooth_by_angle(angle=math.radians(35))
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, name + ".glb"), export_format="GLB", use_selection=True,
                              export_apply=True, export_yup=True, export_materials="EXPORT")
    print("modèle", name, len(o.data.polygons), "faces")


# ================================================================================================ modèles
FRAME = dict(col=(0.16, 0.17, 0.18), metal=0.6, rough=0.4)


def vitrine():
    reset()
    fr = mat("cadre", **FRAME)
    box("socle", (0, -0.06, 0.2), (1.0, 0.16, 0.4), mat("socle", (0.55, 0.53, 0.5), rough=0.8), bevel=0.02)
    for x in (-0.47, 0.47):
        box("montant", (x, -0.08, 1.65), (0.06, 0.1, 2.5), fr, bevel=0.012)
    box("traverse_b", (0, -0.08, 0.43), (1.0, 0.1, 0.06), fr, bevel=0.012)
    box("traverse_h", (0, -0.08, 2.88), (1.0, 0.1, 0.07), fr, bevel=0.012)
    box("imposte", (0, -0.08, 2.4), (1.0, 0.08, 0.04), fr, bevel=0.01)
    plane("verre", (0, -0.07, 1.65), 0.9, 2.42, mat("verre", (0.05, 0.06, 0.07), 0.2, 0.05))
    plane("interieur", (0, 0.35, 1.5), 1.0, 2.4, mat("interieur", (0.75, 0.72, 0.65), rough=0.9))
    export("vitrine")


def porte():
    reset()
    fr = mat("cadre", **FRAME)
    for x in (-0.47, 0.47):
        box("montant", (x, -0.08, 1.45), (0.06, 0.1, 2.9), fr, bevel=0.012)
    box("traverse_h", (0, -0.08, 2.88), (1.0, 0.1, 0.07), fr, bevel=0.012)
    box("imposte", (0, -0.08, 2.32), (1.0, 0.08, 0.05), fr, bevel=0.01)
    box("seuil", (0, -0.1, 0.02), (1.0, 0.2, 0.04), mat("socle", (0.55, 0.53, 0.5), rough=0.8), bevel=0.01)
    # vantail vitré et barre de tirage chromée
    for x in (-0.41, 0.41):
        box("cadre_porte", (x, -0.06, 1.17), (0.04, 0.05, 2.28), fr, bevel=0.008)
    box("bas_porte", (0, -0.06, 0.12), (0.86, 0.05, 0.2), fr, bevel=0.008)
    plane("verre", (0, -0.05, 1.25), 0.78, 2.1, mat("verre", (0.05, 0.06, 0.07), 0.2, 0.05))
    plane("verre_h", (0, -0.07, 2.6), 0.9, 0.5, mat("verre", (0.05, 0.06, 0.07), 0.2, 0.05))
    cyl("poignee", (0.3, -0.13, 1.1), 0.015, 0.7, mat("chrome", (0.85, 0.86, 0.88), 1.0, 0.15))
    for z in (0.78, 1.42):
        box("patte", (0.3, -0.1, z), (0.02, 0.06, 0.02), mat("chrome", (0.85, 0.86, 0.88), 1.0, 0.15))
    plane("interieur", (0, 0.35, 1.3), 1.0, 2.6, mat("interieur", (0.75, 0.72, 0.65), rough=0.9))
    export("porte")


def enseigne():
    """Bandeau de 1 × 1 (mis à l'échelle en jeu) : caisson biseauté, face avant = case de l'atlas des enseignes,
    deux lampes col-de-cygne au-dessus."""
    reset()
    box("caisson", (0, -0.07, 0.5), (1.0, 0.12, 1.0), mat("caisson", (0.12, 0.12, 0.13), 0.3, 0.4), bevel=0.02)
    plane("face", (0, -0.132, 0.5), 0.96, 0.92, mat("enseigne", (1, 1, 1), rough=0.35))
    export("enseigne")


def lampes():
    reset()
    m = mat("metal", (0.1, 0.1, 0.11), 0.7, 0.35)
    for x in (-0.3, 0.3):
        cyl("tige", (x, -0.2, 0.08), 0.012, 0.16, m, n=8)
        cyl("bras", (x, -0.35, 0.16), 0.012, 0.3, m, n=8, axis="Y")
        cone = cyl("abat", (x, -0.52, 0.12), 0.06, 0.08, m, n=12)
        plane("ampoule", (x, -0.52, 0.075), 0.08, 0.001, mat("ampoule", (1, 0.9, 0.7)))
    export("lampes")


def banne():
    """Store banne de 1 m : toile inclinée sur 1,2 m, lambrequin, bras ; « toile » colorée et rayée en jeu."""
    reset()
    t = mat("toile", (0.8, 0.8, 0.8), rough=0.85)
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    a = [bm.verts.new((-0.5, 0.0, 0.0)), bm.verts.new((0.5, 0.0, 0.0)), bm.verts.new((0.5, -1.2, -0.55)), bm.verts.new((-0.5, -1.2, -0.55))]
    f = bm.faces.new([a[0], a[3], a[2], a[1]])
    for lp, u in zip(f.loops, [(0, 0), (0, 1), (1, 1), (1, 0)]):
        lp[uv].uv = u
    # lambrequin festonné
    n = 4
    for i in range(n):
        x0 = -0.5 + i / n; x1 = x0 + 1 / n
        vs = [bm.verts.new((x0, -1.2, -0.55)), bm.verts.new((x1, -1.2, -0.55)), bm.verts.new((x1, -1.2, -0.75)),
              bm.verts.new(((x0 + x1) / 2, -1.2, -0.82)), bm.verts.new((x0, -1.2, -0.75))]
        ff = bm.faces.new(vs)
        for lp, v in zip(ff.loops, vs):
            lp[uv].uv = ((v.co.x + 0.5), 1.0)
    bm.normal_update()
    o = obj_from_bm(bm, "toile", t)
    md = o.modifiers.new("epaisseur", "SOLIDIFY"); md.thickness = 0.01
    cyl("barre", (0, -1.2, -0.55), 0.025, 1.0, mat("metal", (0.85, 0.85, 0.85), 0.8, 0.3), n=10, axis="X")
    cyl("coffre", (0, -0.05, 0.03), 0.06, 1.0, mat("coffre", (0.9, 0.9, 0.88), 0.2, 0.4), n=12, axis="X")
    export("banne")


def croix():
    """Croix de pharmacie lumineuse (double face) sur potence."""
    reset()
    g = mat("croix", (0.1, 0.75, 0.25), rough=0.3)
    for (sx, sz) in ((0.22, 0.66), (0.66, 0.22)):
        box("bras", (0, -0.55, 0), (0.12, sx, sz), g, bevel=0.015)
    box("potence", (0, -0.12, 0.0), (0.06, 0.25, 0.06), mat("metal", (0.2, 0.2, 0.21), 0.6, 0.4), bevel=0.01)
    export("croix")


def carotte():
    """Carotte de tabac : losange rouge allongé, double face, sur potence."""
    reset()
    pts = [(0, 0.45), (0.17, 0), (0, -0.45), (-0.17, 0)]
    m = mat("carotte", (0.8, 0.08, 0.06), rough=0.35)
    bm = bmesh.new()
    vs0 = [bm.verts.new((-0.05, -0.55 + px, pz)) for (px, pz) in pts]
    vs1 = [bm.verts.new((0.05, -0.55 + px, pz)) for (px, pz) in pts]
    bm.faces.new(vs0); bm.faces.new(list(reversed(vs1)))
    for i in range(4):
        j = (i + 1) % 4
        bm.faces.new([vs0[i], vs1[i], vs1[j], vs0[j]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = obj_from_bm(bm, "carotte", m)
    md = o.modifiers.new("biseau", "BEVEL"); md.width = 0.012; md.segments = 2
    box("potence", (0, -0.2, 0.42), (0.04, 0.4, 0.04), mat("metal", (0.2, 0.2, 0.21), 0.6, 0.4), bevel=0.008)
    export("carotte")


def totem():
    """Totem de supermarché (2 × 6 m) : pied gris, caisson double face (atlas) en haut."""
    reset()
    g = mat("blanc", (0.85, 0.85, 0.84), 0.2, 0.4)
    box("pied", (0, 0, 2.0), (0.5, 0.35, 4.0), mat("metal", (0.35, 0.36, 0.38), 0.6, 0.4), bevel=0.03)
    box("caisson", (0, 0, 4.9), (2.0, 0.42, 1.9), g, bevel=0.05)
    plane("face", (0, -0.212, 4.9), 1.84, 1.74, mat("enseigne", (1, 1, 1), rough=0.35))
    plane("dos", (0, 0.212, 4.9), 1.84, 1.74, mat("enseigne", (1, 1, 1), rough=0.35), facing=1)
    box("socle", (0, 0, 0.15), (0.9, 0.7, 0.3), mat("socle", (0.55, 0.53, 0.5), rough=0.8), bevel=0.03)
    export("totem")


def ombriere():
    """Auvent de station-service (14 × 8 m, 5 m sous plafond) : 4 poteaux, plafond blanc, bandeau coloré (« bande »)
    et enseigne (atlas) sur les deux grands côtés."""
    reset()
    w = mat("blanc", (0.88, 0.88, 0.87), 0.2, 0.45)
    for x in (-5.0, 5.0):
        for y in (-2.0, 2.0):
            box("poteau", (x, y, 2.6), (0.4, 0.4, 5.2), w, bevel=0.04)
    box("toit", (0, 0, 5.55), (14.0, 8.0, 0.7), w, bevel=0.06)
    box("bande", (0, 0, 5.35), (14.06, 8.06, 0.25), mat("bande", (0.8, 0.1, 0.1), rough=0.4), bevel=0.02)
    plane("enseigne", (4.5, -4.035, 5.68), 4.0, 0.42, mat("enseigne", (1, 1, 1), rough=0.35), facing=-1)
    plane("enseigne_dos", (-4.5, 4.035, 5.68), 4.0, 0.42, mat("enseigne", (1, 1, 1), rough=0.35), facing=1)
    # îlots sous l'auvent
    for x in (-2.5, 2.5):
        box("ilot", (x, 0, 0.1), (1.2, 4.5, 0.2), mat("socle", (0.55, 0.53, 0.5), rough=0.8), bevel=0.04)
    export("ombriere")


def pompe():
    reset()
    w = mat("blanc", (0.88, 0.88, 0.87), 0.2, 0.45)
    box("corps", (0, 0, 0.95), (0.9, 0.45, 1.7), w, bevel=0.04)
    box("bande", (0, 0, 1.55), (0.92, 0.47, 0.18), mat("bande", (0.8, 0.1, 0.1), rough=0.4), bevel=0.01)
    plane("ecran", (0, -0.231, 1.2), 0.38, 0.22, mat("ecran", (0.1, 0.2, 0.15), rough=0.2))
    for x in (-0.3, 0.3):
        cyl("pistolet", (x, -0.25, 0.95), 0.03, 0.18, mat("metal", (0.1, 0.1, 0.11), 0.4, 0.4), n=8)
        box("tuyau", (x, -0.26, 0.6), (0.03, 0.03, 0.55), mat("caoutchouc", (0.03, 0.03, 0.03), rough=0.8))
    export("pompe")


def abri_caddies():
    reset()
    m = mat("metal", (0.6, 0.62, 0.64), 0.8, 0.35)
    for x in (-1.9, 1.9):
        for y in (-0.9, 0.9):
            cyl("poteau", (x, y, 1.1), 0.04, 2.2, m, n=10)
    box("toit", (0, 0, 2.25), (4.1, 2.1, 0.08), mat("bande", (0.8, 0.1, 0.1), rough=0.4), bevel=0.02)
    # chariots alignés : paniers grillagés (barres fines) sur roulettes
    for k in range(6):
        x = -1.5 + k * 0.6
        for z in (0.5, 1.0):
            box("panier", (x, 0, z), (0.5, 1.0, 0.02), m)
        for y in (-0.48, 0.48):
            box("cote", (x, y, 0.75), (0.5, 0.02, 0.5), m)
        box("poignee", (x, 0.55, 1.05), (0.5, 0.03, 0.03), mat("bande", (0.8, 0.1, 0.1), rough=0.4))
        for y in (-0.4, 0.4):
            cyl("roue", (x, y, 0.08), 0.06, 0.04, mat("caoutchouc", (0.03, 0.03, 0.03), rough=0.8), n=8, axis="X")
    export("abri_caddies")


def terrasse():
    """Table de bistrot, deux chaises, parasol (« toile »)."""
    reset()
    m = mat("metal", (0.15, 0.15, 0.16), 0.6, 0.4)
    cyl("plateau", (0, 0, 0.74), 0.32, 0.03, mat("blanc", (0.88, 0.88, 0.87), 0.2, 0.45), n=20)
    cyl("pied", (0, 0, 0.37), 0.025, 0.72, m, n=8)
    cyl("base", (0, 0, 0.02), 0.2, 0.04, m, n=16)
    for sx in (-1, 1):
        box("assise", (sx * 0.55, 0, 0.45), (0.42, 0.42, 0.04), mat("rotin", (0.55, 0.38, 0.2), rough=0.8), bevel=0.01)
        box("dossier", (sx * 0.75, 0, 0.7), (0.04, 0.42, 0.5), mat("rotin", (0.55, 0.38, 0.2), rough=0.8), bevel=0.01)
        for dx in (-0.18, 0.18):
            for dy in (-0.18, 0.18):
                cyl("pied_chaise", (sx * 0.55 + dx, dy, 0.22), 0.012, 0.44, m, n=6)
    cyl("mat", (0, 0, 1.3), 0.025, 2.6, m, n=8)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=False, segments=8, radius1=1.3, radius2=0.05, depth=0.45)
    for v in bm.verts:
        v.co.z += 2.45
    obj_from_bm(bm, "parasol", mat("toile", (0.8, 0.8, 0.8), rough=0.85))
    export("terrasse")


def auvent():
    """Auvent vitré d'entrée de supermarché (6 × 3 m) sur deux poteaux."""
    reset()
    m = mat("metal", (0.6, 0.62, 0.64), 0.8, 0.35)
    for x in (-2.8, 2.8):
        cyl("poteau", (x, -2.8, 1.6), 0.08, 3.2, m, n=12)
    box("toit", (0, -1.5, 3.25), (6.2, 3.1, 0.12), mat("bande", (0.8, 0.1, 0.1), rough=0.4), bevel=0.03)
    box("rive", (0, -3.05, 3.15), (6.2, 0.08, 0.3), m, bevel=0.02)
    export("auvent")


def bandeau():
    """Planche peinte au-dessus des vitrines (devanture en applique) : 1 m × 0,8 m, 8 cm d'épaisseur, corniche."""
    reset()
    b = mat("bande", (0.8, 0.1, 0.1), rough=0.5)
    box("planche", (0, -0.04, 0.4), (1.0, 0.08, 0.8), b)
    box("corniche", (0, -0.07, 0.83), (1.0, 0.14, 0.06), b)
    box("filet", (0, -0.085, 0.04), (1.0, 0.03, 0.04), b)
    export("bandeau")


def pilastre():
    """Montant de devanture en applique (30 cm × 3,8 m), base et chapiteau simples."""
    reset()
    b = mat("bande", (0.8, 0.1, 0.1), rough=0.5)
    box("fut", (0, -0.06, 1.9), (0.3, 0.12, 3.8), b, bevel=0.01)
    box("base", (0, -0.08, 0.15), (0.36, 0.16, 0.3), b, bevel=0.01)
    box("chapiteau", (0, -0.09, 3.72), (0.38, 0.18, 0.16), b, bevel=0.01)
    export("pilastre")


def coffre_rideau():
    """Coffre de rideau métallique (1 m), posé sous l'enseigne au-dessus d'une vitrine, glissières latérales."""
    reset()
    c = mat("coffre", (0.9, 0.9, 0.88), 0.2, 0.4)
    box("coffre", (0, -0.16, 2.78), (1.0, 0.26, 0.3), c, bevel=0.015)
    box("lame", (0, -0.03, 2.6), (1.0, 0.02, 0.06), mat("metal", (0.45, 0.46, 0.48), 0.6, 0.4))
    export("coffre_rideau")


def porte_sectionnelle():
    """Porte d'atelier à lames horizontales (module de 1 × 3 m), dormant gris."""
    reset()
    b = mat("bande", (0.8, 0.1, 0.1), rough=0.45)
    plane("tablier", (0, -0.04, 1.5), 1.0, 3.0, b)
    for k in range(6):
        box("lame", (0, -0.055, 0.25 + k * 0.5), (1.0, 0.03, 0.04), b)
    box("linteau", (0, -0.07, 3.08), (1.0, 0.14, 0.16), mat("metal", (0.35, 0.36, 0.38), 0.6, 0.4))
    box("seuil", (0, -0.08, 0.015), (1.0, 0.16, 0.03), mat("socle", (0.55, 0.53, 0.5), rough=0.8))
    export("porte_sectionnelle")


def bardage():
    """Bardage métallique nervuré des grandes surfaces : panneau de 1 × 1 m (mis à l'échelle de la façade), 4 nervures."""
    reset()
    b = mat("bande", (0.8, 0.1, 0.1), rough=0.45)
    plane("tole", (0, -0.03, 0.5), 1.0, 1.0, b)
    for x in (-0.375, -0.125, 0.125, 0.375):
        box("nervure", (x, -0.05, 0.5), (0.05, 0.04, 1.0), b)
    export("bardage")


def main():
    os.makedirs(OUT, exist_ok=True)
    for f in (vitrine, porte, enseigne, lampes, banne, croix, carotte, totem, ombriere, pompe, abri_caddies, terrasse, auvent,
              bandeau, pilastre, coffre_rideau, porte_sectionnelle, bardage):
        f()


if __name__ == "__main__":
    main()
