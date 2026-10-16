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
    "espace": dict(lh=(1.86, 1.73), L=4.66, rot=-90, roues=[r"^Object_(17|18|28|29|33|34|60|61)$"], suppr=[],
                   mats={"r_glass": "glass"}, couleur=None),
    "deuche": dict(lh=(1.48, 1.6), L=3.86, rot=0, roues=["Wheels"], suppr=[], mats={"Windshield": "glass", "glass": "glass"},
                   couleur=None),
    "clio": dict(lh=(1.64, 1.42), L=3.77, rot=180, roues=["Cylinder"], suppr=[], mats={"Glass": "glass"}, couleur=None),
    "laguna": dict(lh=(1.75, 1.47), L=4.70, rot=180, roues=["pneu512", "silv"], suppr=[],
                   mats={"RT_Carpaint": "paint", "matte": "plastic", "vitres": "glass", "vitres_int": "glass",
                         "vitres_2": "lamp", "exterieur": "plastic", "exterieur22": "chrome", "Material_4": "tail",
                         "pneu512": "rubber", "silv": "hubcap"},
                   couleur=(0.10, 0.20, 0.26)),
    "p206": dict(lh=(1.67, 1.43), L=3.83, rot=180, roues=["Carro_Pneu", "Carro_Roda"], suppr=["Carro_Freio", "Carro_Disco_Freio"],
                 mats={"Carro_Pintura": "paint", "Carro_Vidros": "glass", "Carro_Pneu": "rubber"},
                 couleur=(0.82, 0.83, 0.84)),
    "p106": dict(lh=(1.59, 1.37), L=3.68, rot=180, roues=[r"^unnamed\.0(09|14|15|16)_"], suppr=[],
                 mats={}, couleur=None),
    "p306": dict(lh=(1.69, 1.38), L=4.03, rot=180, roues=["Cylinder"], suppr=["_Material_0"], mats={}, couleur=None),
    "r5": dict(lh=(1.52, 1.39), L=3.52, rot=90, roues=["FrontLeft", "FrontRight", "RearLeft", "RearRight"], suppr=["SUSPENSION"],
               mats={"Pintura": "paint", "VIDRIO": "glass"}, couleur=(0.86, 0.72, 0.30)),
    "gt3": dict(lh=(1.88, 1.3), L=4.55, rot=180, roues=["Rim1Mtl", "Tyre1Mtl", "Rotor1Mtl", "Caliper1Mtl"], suppr=[],
                mats={"Paint1Mtl": "paint", "Glass1Mtl": "glass", "Glass2Mtl": "glass", "Windows1Mtl": "glass",
                      "Tyre1Mtl": "rubber"}, couleur=(0.95, 0.38, 0.05)),
    "twingo": dict(lh=(1.63, 1.42), L=3.43, rot=0, roues=["^object_0$", "^object_1$"], suppr=[], mats={}, couleur=None),
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


def convertir(cid, c):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, cid, "scene.gltf"))
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
    # roues : morceaux séparés, rangés par coin
    roues = [o for o in ms if c["roues"] and correspond(o, c["roues"])]
    corps = [o for o in ms if o not in roues]
    if roues:
        r = joindre(roues, "roues")
        bpy.ops.object.select_all(action="DESELECT"); r.select_set(True)
        bpy.context.view_layer.objects.active = r
        bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.mesh.separate(type="LOOSE"); bpy.ops.object.mode_set(mode="OBJECT")
        morceaux = [o for o in objets_maillage() if o not in corps]
    else:
        morceaux = []
    mn, mx = bornes(corps + morceaux)
    cx = (mn.x + mx.x) / 2; cy = (mn.y + mx.y) / 2
    coins = {}
    for o in morceaux:
        a, b = bornes([o])
        ctr = (a + b) / 2
        coins.setdefault((ctr.x > cx, ctr.y > cy), []).append(o)
    if len(coins) != 4:
        sys.exit("%s : %d coins de roues trouvés" % (cid, len(coins)))
    centres = {}
    for k, l in coins.items():
        a, b = bornes(l)
        centres[k] = ((a + b) / 2, (b.z - a.z) / 2)
    av_d = coins[(True, True)]
    wc, rayon = centres[(True, True)]
    sol = min(centres[k][0].z - centres[k][1] for k in centres)
    ar = (centres[(True, False)][0].y + centres[(False, False)][0].y) / 2
    av = (centres[(True, True)][0].y + centres[(False, True)][0].y) / 2
    voie = centres[(True, True)][0].x - centres[(False, True)][0].x
    mid = (av + ar) / 2
    for k, l in coins.items():
        if k != (True, True):
            for o in l:
                bpy.data.objects.remove(o, do_unlink=True)
    # caisse : origine au sol au milieu de l'empattement
    b = joindre(corps, "caisse")
    b.data.transform(mathutils.Matrix.Translation((-(mn.x + mx.x) / 2, -mid, -sol)))
    alleger(b, FACES)
    w = joindre(av_d, "roue")
    w.data.transform(mathutils.Matrix.Translation(-wc))
    alleger(w, 2500)
    # matériaux
    for o in (b, w):
        for sl in o.material_slots:
            m = sl.material
            if not m:
                continue
            for p, cible in c["mats"].items():
                if m.name.split(".")[0] == p:
                    if cible == "paint" and c["couleur"]:
                        materiau(m.name, c["couleur"], 0.0, 0.3)
                    m.name = cible
                    break
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
    json.dump(meta, open(os.path.join(d, "meta.json"), "w"))
    print("OK", cid, "caisse", len(b.data.polygons), "faces, roue", len(w.data.polygons), meta)


def main():
    seuls = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for cid, c in CARS.items():
        if seuls and cid not in seuls:
            continue
        convertir(cid, c)


main()
