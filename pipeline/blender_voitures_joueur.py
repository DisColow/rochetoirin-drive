"""Voitures du joueur à acheter au garage (#95) : conversion des modèles de fetch_voitures_joueur.py au format de la
voiture du jeu (comme blender_ranger.py) :
  - avant vers +Y Blender (-Z glTF), échelle réelle (longueur), origine au sol au milieu de l'empattement ;
  - roues repérées par motifs (noms d'objets ou de matériaux), séparées en morceaux, rangées par coin ; la roue avant
    droite devient wheel.glb (centrée), les autres sont retirées (car.gd pose quatre exemplaires) ;
  - matériaux renommés d'après car.gd quand ils sont unis (paint = teinte du garage, glass, rubber, chrome, lamp,
    tail, plastic) ; les matériaux texturés gardent leur texture (ramenée à 1024 px) ;
  - objets retirés (coques noires de contour, intérieurs trop lourds…), maillage allégé pour le téléphone.
Sorties : ../godot/assets/voitures/<id>/{body,wheel}.glb + meta.json.
<venv>/bin/python blender_voitures_joueur.py [id…]"""
import json, math, os, re, sys
import bpy, bmesh
import mathutils

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "godot", "import", "voitures")
OUT = os.path.join(HERE, "..", "godot", "assets", "voitures")
FACES = 26000                     # caisse (toujours à l'écran et dans les ombres)

# id : L = longueur réelle (m), rot = rotation (degrés, autour de Z) qui met l'avant vers +Y, roues = motifs des
# objets/matériaux des roues, suppr = motifs à retirer, mats = motif -> nom du jeu (ou couleur RVB pour les modèles
# sans texture), lh = largeur et hauteur réelles (m), couleur = teinte d'origine de la peinture (garage : « d'origine »)
CARS = {
    # Espace IV : 348 000 faces sans texture ; allégé matériau par matériau (caisse peu, intérieur beaucoup : sinon
    # l'intérieur sombre perce la carrosserie), repeint en rouge comme l'Espace du début du jeu
    "espace": dict(effacer_mats=["chrome2", "chrome"], effacer=[("ar", 0.75, 1.2)], marque="renaud", logos=[("av", 0.66, 0.16), ("ar", 1.0, 0.14)], lh=(1.86, 1.73), L=4.66, rot=-90,
                   roues=[r"^Object_(17|18|28|29|33|34|60|61)$"], suppr=[],
                   mats={"r_glass": "glass", "auto_11": "glass", "Material__130": "glass", "silver1": "paint", "auto_9": "tail", "auto_10": "orange",
                         "chrome2": "chrome"},
                   par_materiau={"silver1": 1.0, "chrome2": 0.5, "auto_6": 1.0, "r_glass": 1.0, "auto_11": 1.0, "Material__130": 1.0}, cylindres=True, vider=True, faces=90000,
                   couleur=(0.42, 0.03, 0.04)),
    "deuche": dict(effacer=[("ar", 0.64, 0.80)], effacer_mats=["material"], effacer_x=0.55, marque="citrouille", logos=[("av", 0.58, 0.2), ("ar", 0.72, 0.1)], lh=(1.48, 1.6), L=3.86, rot=0, roues=["Wheels"], suppr=[], mats={"Windshield": "glass", "glass": "glass"},
                   couleur=None),
    "clio": dict(marque="renaud", lh=(1.64, 1.42), L=3.77, rot=180, roues=["Cylinder"], suppr=[], mats={"Glass": "glass"}, couleur=None),
    # Laguna : modèle sans aucune texture (tout blanc), peint pour le jeu pièce par pièce ; badge de la marque retiré
    "laguna": dict(effacer=[("ar", 0.4, 1.0)], marque="renaud", logos=[("av", 0.70, 0.12), ("ar", 0.95, 0.11)], lh=(1.75, 1.47), L=4.70, rot=180, roues=["pneu512", "silv"], suppr=["Material_23"],
                   mats={"RT_Carpaint": "paint", "matte": "plastic", "vitres": "glass", "vitres_int": "glass",
                         "vitres_2": "lamp", "exterieur": "tail", "exterieur22": "plastic", "pneu512": "rubber",
                         "silv": "hubcap", "Material_16": "hubcap", "Material_4": "plastic", "Default": "orange",
                         "Material_8": "orange", "Material_15": "plastic", "Material_24": "plastic",
                         "EXT_PLATE_plastic": (0.86, 0.86, 0.82), "cuir": (0.10, 0.10, 0.11), "cuirbv": (0.10, 0.10, 0.11),
                         "interieur": (0.16, 0.16, 0.17), "plastique": (0.07, 0.07, 0.075),
                         "plastique3": (0.07, 0.07, 0.075), "beige-haut": (0.55, 0.51, 0.44),
                         "compteurs": (0.04, 0.04, 0.045), "moquette": (0.05, 0.05, 0.05), "moteur": (0.2, 0.2, 0.2),
                         "CAR_Sottoscocca": (0.05, 0.05, 0.05), "CAR_PinzaFreni": (0.3, 0.3, 0.3)},
                   defaut=(0.07, 0.07, 0.075), couleur=(0.10, 0.20, 0.26)),
    "p206": dict(effacer_mats=["Carro_Cromado"], effacer=[("av", 0.35, 0.85), ("ar", 0.5, 1.2)], marque="pijo", logos=[("av", 0.64, 0.11), ("ar", 0.92, 0.12)], lh=(1.67, 1.43), L=3.83, rot=180, roues=["Carro_Pneu", "Carro_Roda"], suppr=["Carro_Freio", "Carro_Disco_Freio"],
                 mats={"Carro_Pintura": "paint", "Carro_Vidros": "glass", "Carro_Pneu": "rubber"},
                 couleur=(0.82, 0.83, 0.84)),
    "p106": dict(marque="pijo", lh=(1.59, 1.37), L=3.68, rot=180, roues=[r"^unnamed\.0(09|14|15|16)_"], suppr=[],
                 mats={}, couleur=None),
    "p306": dict(roue_de="p206", marque="pijo", lh=(1.69, 1.38), L=4.03, rot=180, roues=["Cylinder"], suppr=["_Material_0"], mats={}, couleur=None),
    "r5": dict(marque="renaud", logos=[("av", 0.62, 0.10)], lh=(1.52, 1.39), L=3.52, rot=90, roues=["FrontLeft", "FrontRight", "RearLeft", "RearRight"], suppr=["SUSPENSION"],
               mats={"Pintura": "paint", "VIDRIO": "glass"}, couleur=(0.86, 0.72, 0.30)),
    "gt3": dict(marque="porcche", logos=[("capot", 0.28, 0.10)], lh=(1.88, 1.3), L=4.55, rot=180, roues=["Rim1Mtl", "Tyre1Mtl", "Rotor1Mtl", "Caliper1Mtl"], suppr=[],
                mats={"Paint1Mtl": "paint", "Glass1Mtl": "glass", "Glass2Mtl": "glass", "Windows1Mtl": "glass",
                      "Tyre1Mtl": "rubber"}, couleur=(0.95, 0.38, 0.05)),
    # bus B1 de la circulation (#136), conduit par le joueur dans l'activité « Ligne de bus » (#148) : pas au garage
    "bus": dict(src="../lourds/bus/model.glb", L=11.5, rot=90, roues=[r"^material(_4)?$"], suppr=[r"^seat$", r"^wood$"],
                mats={"glass": "glass", "light": "lamp"}, faces=40000, couleur=None, roue_unie=(0.62, 0.63, 0.66),
                eye=[-0.75, 2.05, -3.7], steer=[-0.75, 1.6, -4.1]),     # poste de conduite tout à l'avant
    "twingo": dict(marque="renaud", logos=[("av", 0.55, 0.13)], lh=(1.63, 1.42), L=3.43, rot=0, roues=["^object_0$", "^object_1$"], suppr=[], mats={}, couleur=None),
}


def objets_maillage():
    return [o for o in bpy.data.objects if o.type == "MESH"]


def correspond(o, motifs):
    noms = [o.name] + [m.name for m in o.data.materials if m]
    return any(re.search(p, n) for p in motifs for n in noms)          # motifs : expressions régulières


def bornes(objs):
    V = [o.matrix_world @ v.co for o in objs for v in o.data.vertices]
    mn = mathutils.Vector([min(v[i] for v in V) for i in range(3)])
    mx = mathutils.Vector([max(v[i] for v in V) for i in range(3)])
    return mn, mx


def joindre(objs, nom):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    o = bpy.context.view_layer.objects.active
    o.name = nom
    return o


def alleger(o, faces):
    n = len(o.data.polygons)
    if n > faces:
        md = o.modifiers.new("dec", "DECIMATE")
        md.ratio = faces / n
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.modifier_apply(modifier="dec")


def materiau(nom, col, metal=0.0, rough=0.5):
    m = bpy.data.materials.get(nom) or bpy.data.materials.new(nom)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*col, 1.0)
    b.inputs["Metallic"].default_value = metal
    b.inputs["Roughness"].default_value = rough
    return m


LOGOS = os.path.join(SRC, "_logos")         # faux_logos.py


def poser_logos(b, c):
    """Faux logos (#95) : décalcomanie un peu plus grande que le vrai badge, posée dessus (lancer de rayon sur la
    caisse) : ("av" | "ar", hauteur depuis le sol en m, taille en m) ou ("capot", distance depuis l'avant, taille)."""
    from mathutils.bvhtree import BVHTree
    arbre = BVHTree.FromObject(b, bpy.context.evaluated_depsgraph_get())
    a, z = bornes([b])
    mat = None
    for cote, h, t in c.get("logos", []):
        if cote == "capot":
            o = mathutils.Vector((0, z.y - h, z.z + 1)); d = mathutils.Vector((0, 0, -1))
        else:
            o = mathutils.Vector((0, (z.y + 1) if cote == "av" else (a.y - 1), h))
            d = mathutils.Vector((0, -1 if cote == "av" else 1, 0))
        hit, n, _, _ = arbre.ray_cast(o, d)
        if hit is None:
            print("  logo non posé", cote, h)
            continue
        if n.dot(d) > 0:
            n = -n
        if mat is None:
            im = bpy.data.images.load(os.path.join(LOGOS, c["marque"] + ".png"))
            mat = bpy.data.materials.new("logo_" + c["marque"]); mat.use_nodes = True
            nt = mat.node_tree; bs = nt.nodes["Principled BSDF"]
            tx = nt.nodes.new("ShaderNodeTexImage"); tx.image = im
            seuil = nt.nodes.new("ShaderNodeMath"); seuil.operation = "GREATER_THAN"; seuil.inputs[1].default_value = 0.5
            nt.links.new(tx.outputs["Color"], bs.inputs["Base Color"])
            nt.links.new(tx.outputs["Alpha"], seuil.inputs[0])
            nt.links.new(seuil.outputs[0], bs.inputs["Alpha"])
            bs.inputs["Metallic"].default_value = 0.6; bs.inputs["Roughness"].default_value = 0.25
        # plan face à la normale, haut = +Z (ou vers l'avant sur le capot)
        haut = mathutils.Vector((0, 1, 0)) if cote == "capot" else mathutils.Vector((0, 0, 1))
        dx = haut.cross(n).normalized(); dy = n.cross(dx).normalized()
        ctr = hit + n * 0.006
        me = bpy.data.meshes.new("logo")
        pts = [ctr + (dx * sx + dy * sy) * t / 2 for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
        me.from_pydata(pts, [], [(0, 1, 2, 3)])
        uv = me.uv_layers.new()
        for i, (u, v) in enumerate(((0, 0), (1, 0), (1, 1), (0, 1))):
            uv.data[i].uv = (u, v)
        me.materials.append(mat)
        ob = bpy.data.objects.new("logo", me); bpy.context.scene.collection.objects.link(ob)
        bpy.ops.object.select_all(action="DESELECT"); ob.select_set(True); b.select_set(True)
        bpy.context.view_layer.objects.active = b
        bpy.ops.object.join()


def effacer_badges(b, c):
    """Vrais badges et lettrages en volume (#95) : petits îlots minces (moins de 5 cm d'épaisseur) sur la face avant ou
    arrière, dans une bande de hauteur : ("av" | "ar", hauteur basse, hauteur haute en m depuis le sol), retirés ;
    effacer_mats : seulement ces matériaux (chromes des badges), noms d'origine ou du jeu."""
    if not c.get("effacer"):
        return
    a, z = bornes([b])
    bm = bmesh.new(); bm.from_mesh(b.data); bm.verts.ensure_lookup_table()
    vus = set(); retire = []
    for v0 in bm.verts:
        if v0.index in vus:
            continue
        pile = [v0]; ilot = []; vus.add(v0.index)
        while pile:
            v = pile.pop(); ilot.append(v)
            for e in v.link_edges:
                u = e.other_vert(v)
                if u.index not in vus:
                    vus.add(u.index); pile.append(u)
        if len(ilot) > 3000:
            continue
        P = [v.co for v in ilot]
        lo = [min(p[i] for p in P) for i in range(3)]; hi = [max(p[i] for p in P) for i in range(3)]
        if max(hi[0] - lo[0], hi[2] - lo[2]) > 0.3 or hi[1] - lo[1] > 0.05:
            continue
        fs = {f for v in ilot for f in v.link_faces}
        mats = {b.data.materials[f.material_index].name.split(".")[0] for f in fs} if b.data.materials else set()
        if c.get("effacer_mats") and not mats & set(c["effacer_mats"]):
            continue
        for cote, z0, z1 in c["effacer"]:
            bout = (hi[1] > z.y - 0.45) if cote == "av" else (lo[1] < a.y + 0.45)
            if bout and z0 <= lo[2] and hi[2] <= z1 and abs((lo[0] + hi[0]) / 2) < c.get("effacer_x", 0.65) * (z.x - a.x) / 2:
                retire += [f for v in ilot for f in v.link_faces]
                break
    if retire:
        bmesh.ops.delete(bm, geom=list(set(retire)), context="FACES")
        bm.to_mesh(b.data)
    bm.free()
    print("  badges et lettrages retirés :", len(set(retire)), "faces")


def convertir(cid, c):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, c["src"]) if c.get("src") else os.path.join(SRC, cid, "scene.gltf"))
    for o in list(bpy.data.objects):
        if o.type == "MESH":
            mw = o.matrix_world.copy(); o.parent = None; o.matrix_world = mw
    for o in list(bpy.data.objects):
        if o.type != "MESH" or (c["suppr"] and correspond(o, c["suppr"])):
            bpy.data.objects.remove(o, do_unlink=True)
    ms = objets_maillage()
    bpy.ops.object.select_all(action="DESELECT")
    for o in ms:
        o.select_set(True)
    bpy.context.view_layer.objects.active = ms[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    # allègement par matériau (objet entier, d'après son matériau principal), avant de tout joindre
    if c.get("par_materiau"):
        for o in ms:
            if c["roues"] and correspond(o, c["roues"]):
                continue
            cpt = {}
            for p in o.data.polygons:
                cpt[p.material_index] = cpt.get(p.material_index, 0) + 1
            mi = max(cpt, key=cpt.get) if cpt else 0
            nom = o.data.materials[mi].name.split(".")[0] if o.data.materials else ""
            alleger(o, max(40, int(len(o.data.polygons) * c["par_materiau"].get(nom, 0.25))))
    # orientation et échelle (sur les données : objets à l'identité)
    R = mathutils.Matrix.Rotation(math.radians(c["rot"]), 4, "Z")
    for o in ms:
        o.data.transform(R)
    mn, mx = bornes(ms)
    s = c["L"] / (mx.y - mn.y)
    for o in ms:
        o.data.transform(mathutils.Matrix.Scale(s, 4))
    if c.get("lh"):
        V = [v.co for o in ms for v in o.data.vertices]
        a, z = bornes(ms)
        cx0 = (a.x + z.x) / 2
        bande = [v for v in V if abs(v.y - (a.y + 0.2 * (z.y - a.y))) < 0.08 * (z.y - a.y)
                 or abs(v.y - (a.y + 0.8 * (z.y - a.y))) < 0.08 * (z.y - a.y)]
        lar = 2 * max(abs(v.x - cx0) for v in bande)
        hs = sorted(v.z for v in V)
        hau = hs[int(len(hs) * 0.995)] - a.z
        M = mathutils.Matrix.Diagonal((c["lh"][0] / lar, 1.0, c["lh"][1] / hau, 1.0))
        for o in ms:
            o.data.transform(M)
    # roues : sommets rangés par coin (sans séparer les morceaux : les pneus à crampons en comptent des milliers)
    roues = [o for o in ms if c["roues"] and correspond(o, c["roues"])]
    corps = [o for o in ms if o not in roues]
    if not roues:
        sys.exit("%s : aucune roue trouvée" % cid)
    r = joindre(roues, "roues")
    roues_extra = []
    mn, mx = bornes(corps + [r])
    cx = (mn.x + mx.x) / 2; cy = (mn.y + mx.y) / 2
    coin = lambda v: (v.x > cx, v.y > cy)
    pts = {}
    for v in r.data.vertices:
        pts.setdefault(coin(v.co), []).append(v.co)
    if len(pts) != 4:
        sys.exit("%s : %d coins de roues trouvés" % (cid, len(pts)))
    centres = {}
    for k, l in pts.items():
        a = mathutils.Vector([min(p[i] for p in l) for i in range(3)])
        b = mathutils.Vector([max(p[i] for p in l) for i in range(3)])
        centres[k] = ((a + b) / 2, (b.z - a.z) / 2)
    wc, rayon = centres[(True, True)]
    sol = min(centres[k][0].z - centres[k][1] for k in centres)
    ar = (centres[(True, False)][0].y + centres[(False, False)][0].y) / 2
    av = (centres[(True, True)][0].y + centres[(False, True)][0].y) / 2
    voie = centres[(True, True)][0].x - centres[(False, True)][0].x
    mid = (av + ar) / 2
    # pièces des roues rangées dans d'autres objets (jantes, enjoliveurs) : faces de la caisse dans le cylindre d'une
    # roue -> retirées de la caisse ; celles de la roue avant droite rejoignent la roue
    if c.get("cylindres"):
        for o in list(corps):
            bm = bmesh.new(); bm.from_mesh(o.data)
            dedans = {}
            for f in bm.faces:
                q = f.calc_center_median()
                for k, (ctr, rr) in centres.items():
                    if (q.y - ctr.y) ** 2 + (q.z - ctr.z) ** 2 < (rr * 1.02) ** 2 and abs(q.x - ctr.x) < 0.2:
                        dedans.setdefault(k, []).append(f)
                        break
            if dedans.get((True, True)):
                bmw = bm.copy()
                garde = {f.index for f in dedans[(True, True)]}
                bmesh.ops.delete(bmw, geom=[f for f in bmw.faces if f.index not in garde], context="FACES")
                me = bpy.data.meshes.new("jante"); bmw.to_mesh(me); bmw.free()
                for m in o.data.materials:
                    me.materials.append(m)
                oj = bpy.data.objects.new("jante", me); bpy.context.scene.collection.objects.link(oj)
                roues_extra.append(oj)
            tout = [f for l in dedans.values() for f in l]
            if tout:
                bmesh.ops.delete(bm, geom=tout, context="FACES")
                bm.to_mesh(o.data)
            bm.free()
    # on ne garde que la roue avant droite
    bm = bmesh.new(); bm.from_mesh(r.data)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if coin(f.calc_center_median()) != (True, True)], context="FACES")
    bm.to_mesh(r.data); bm.free()
    av_d = [r] + roues_extra
    # habitacle vidé (les vitres du jeu sont opaques : on ne le voit jamais) : faces au milieu de la cabine dont le
    # matériau n'est ni carrosserie, ni vitre, ni feu
    if c.get("vider"):
        a, z = bornes(corps)
        W, H = z.x - a.x, z.z - a.z
        gardes = {p for p, cible in c["mats"].items() if cible in ("paint", "glass", "lamp", "tail", "orange", "chrome")}
        for o in corps:
            bm = bmesh.new(); bm.from_mesh(o.data)
            hors = []
            for f in bm.faces:
                q = f.calc_center_median()
                nom = o.data.materials[f.material_index].name.split(".")[0] if o.data.materials else ""
                if nom not in gardes and abs(q.x - (a.x + z.x) / 2) < 0.36 * W and a.z + 0.28 * H < q.z < a.z + 0.88 * H \
                        and ar - 0.3 < q.y < av + 0.1:
                    hors.append(f)
            if hors:
                bmesh.ops.delete(bm, geom=hors, context="FACES")
                bm.to_mesh(o.data)
            bm.free()
    # caisse : origine au sol au milieu de l'empattement
    b = joindre(corps, "caisse")
    b.data.transform(mathutils.Matrix.Translation((-(mn.x + mx.x) / 2, -mid, -sol)))
    alleger(b, c.get("faces", FACES))
    effacer_badges(b, c)
    poser_logos(b, c)
    w = joindre(av_d, "roue")
    w.data.transform(mathutils.Matrix.Translation(-wc))
    if c.get("roue_unie"):                  # bus : texture de roue déformée par l'allègement -> pneu et jante unis,
        w.data.materials.clear()            # d'après la distance de chaque face à l'axe (x), avant l'allègement
        w.data.materials.append(materiau("rubber", (0.035, 0.035, 0.04), 0.0, 0.85))
        w.data.materials.append(materiau("hubcap", c["roue_unie"], 0.6, 0.35))
        for f in w.data.polygons:
            q = f.center
            f.material_index = 0 if (q.y ** 2 + q.z ** 2) ** 0.5 > 0.58 * rayon else 1
    alleger(w, 2500)
    # matériaux (ceux de la roue copiés : une jante peut partager le matériau de la caisse)
    for sl in w.material_slots:
        if sl.material and not c.get("roue_unie"):
            sl.material = sl.material.copy()
    for o in (b, w):
        for sl in o.material_slots:
            m = sl.material
            if not m:
                continue
            for p, cible in c["mats"].items():
                if m.name.split(".")[0] == p:
                    if isinstance(cible, tuple):          # couleur posée sur un matériau sans texture
                        materiau(m.name, cible, 0.0, 0.55)
                        break
                    if o is w and cible not in ("rubber",):
                        cible = "hubcap"                  # roue : tout ce qui n'est pas le pneu est la jante
                    elif cible == "paint" and c["couleur"]:
                        materiau(m.name, c["couleur"], 0.0, 0.3)
                    deja = bpy.data.materials.get(cible)
                    if deja and deja != m:
                        sl.material = deja                # même nom du jeu : un seul matériau (sinon « glass.001 »)
                    else:
                        m.name = cible
                    break
            else:
                # matériau blanc sans texture, non repéré : plastique sombre (modèle livré sans couleurs)
                b0 = m.node_tree.nodes.get("Principled BSDF") if m.use_nodes else None
                if c.get("defaut") and b0 and not b0.inputs["Base Color"].links \
                        and min(b0.inputs["Base Color"].default_value[:3]) > 0.95:
                    materiau(m.name, c["defaut"], 0.0, 0.6)
    for im in bpy.data.images:
        if im.size[0] > 1024:
            im.scale(1024, max(1, 1024 * im.size[1] // im.size[0]))
    d = os.path.join(OUT, cid)
    os.makedirs(d, exist_ok=True)
    for o, f in ((w, "wheel.glb"), (b, "body.glb")):
        bpy.ops.object.select_all(action="DESELECT"); o.select_set(True)
        bpy.ops.export_scene.gltf(filepath=os.path.join(d, f), export_format="GLB", use_selection=True,
                                  export_yup=True, export_apply=True, export_image_format="JPEG")
    a, z = bornes([b])
    L, W, H = z.y - a.y, z.x - a.x, z.z - a.z
    meta = {"wheelbase": round(av - ar, 3), "track": round(voie, 3), "radius": round(rayon, 3),
            "wheel_center": [0.0, 0.0, 0.0], "box": [round(W * 0.95, 2), round(H * 0.62, 2), round(L * 0.96, 2)],
            "box_y": round(H * 0.45, 2), "dims": [round(L, 2), round(W, 2), round(H, 2)],
            # repère du jeu (comme assets/car/meta.json) : x conducteur à gauche, avant vers -Z
            "eye": [-round(W * 0.2, 2), round(H * 0.78, 2), round(L * 0.02, 2)],
            "steer": [-round(W * 0.2, 2), round(H * 0.62, 2), -round(L * 0.1, 2)],
            "beams": [round(W * 0.36, 2), round(H * 0.5, 2), round(z.y - mid - 0.1, 2)],
            "couleur": list(c["couleur"]) if c["couleur"] else None}
    for k in ("eye", "steer"):              # poste de conduite placé à la main (bus : tout à l'avant)
        if c.get(k):
            meta[k] = c[k]
    if c.get("roue_de"):                    # #109 : roue du modèle ratée, celle d'une autre voiture (car.gd)
        meta["roue_de"] = c["roue_de"]
    json.dump(meta, open(os.path.join(d, "meta.json"), "w"))
    print("OK", cid, "caisse", len(b.data.polygons), "faces, roue", len(w.data.polygons), meta)


def main():
    seuls = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for cid, c in CARS.items():
        if seuls and cid not in seuls:
            continue
        convertir(cid, c)


main()
