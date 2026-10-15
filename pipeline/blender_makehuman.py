"""Clients du taxi faits avec MakeHuman (issue #55) : MPFB 2 (extension Blender de la communauté MakeHuman) et le pack
« makehuman_system_assets » (CC0) : corps, peaux, vêtements, coiffures. Maillage allégé « proxy741 », squelette
« game_engine » (os : pelvis, thigh_l, calf_l, upperarm_l…), matériaux simples ; textures ramenées à 512 px.
Sortie : ../godot/assets/clients/mh_<n>.glb et mh.json (sexe et âge de chaque personnage, pour le taxi).
Prérequis : venv avec bpy ; MPFB installé comme extension (lien user_default/mpfb) et les ressources liées dans son
dossier data (voir docs/REPRISE.md).   <venv>/bin/python blender_makehuman.py"""
import json, os, sys
import bpy
import addon_utils            # après bpy (qui installe les chemins de Blender)

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "godot", "assets", "clients")
addon_utils.enable("bl_ext.user_default.mpfb", default_set=True)
M = "bl_ext.user_default.mpfb.services."
HS = sys.modules[M + "humanservice"].HumanService
AS = sys.modules[M + "assetservice"].AssetService
ES = sys.modules[M + "exportservice"].ExportService
OS_ = sys.modules[M + "objectservice"].ObjectService
TS = sys.modules[M + "targetservice"].TargetService


def age(ans):
    """Âge en années -> macro MakeHuman (0,5 = 25 ans, 1 = 90 ans)."""
    return 0.5 + (ans - 25) / 65 * 0.5 if ans >= 25 else 0.1875 + (ans - 11) / 14 * 0.3125


# sexe, âge, origine, peau, tenue, coiffure, chapeau, chaussures, carrure (poids, muscle)
# + teinte des vêtements (multipliée sur leur texture : chaque client a ses couleurs, #55 « stylés »)
PERSOS = [
    ("m", 30, "caucasian", "young_caucasian_male", "male_casualsuit03", "short02", None, "shoes01", 0.5, 0.55, (0.55, 0.15, 0.12)),
    ("f", 28, "caucasian", "young_caucasian_female", "female_casualsuit02", "long01", None, "shoes03", 0.45, 0.5, (1.0, 0.95, 0.9)),
    ("m", 70, "caucasian", "old_caucasian_male", "male_elegantsuit01", "short01", "fedora01", "shoes02", 0.6, 0.4, (0.75, 0.7, 0.6)),
    ("f", 66, "caucasian", "old_caucasian_female", "female_elegantsuit01", "bob01", None, "shoes03", 0.6, 0.4, (0.5, 0.6, 0.9)),
    ("m", 45, "african", "middleage_african_male", "male_worksuit01", "short03", None, "shoes05", 0.6, 0.65, (1.0, 0.75, 0.4)),
    ("f", 22, "african", "young_african_female", "female_sportsuit01", "afro01", None, "shoes04", 0.4, 0.55, (0.9, 0.35, 0.6)),
    ("m", 20, "asian", "young_asian_male", "male_casualsuit06", "short04", None, "shoes06", 0.4, 0.5, (0.35, 0.8, 0.45)),
    ("f", 41, "asian", "middleage_asian_female", "female_casualsuit01", "ponytail01", None, "shoes03", 0.5, 0.5, (0.95, 0.6, 0.25)),
    ("m", 55, "caucasian", "middleage_caucasian_male", "male_casualsuit05", "short01", "fedora_cocked", "shoes02", 0.7, 0.5, (0.6, 0.55, 0.45)),
    ("f", 35, "caucasian", "young_caucasian_female2", "female_casualsuit01", "braid01", None, "shoes01", 0.5, 0.5, (0.45, 0.25, 0.55)),
]


def teinter(o, col):
    """Multiplie la couleur de base des matériaux de l'objet (texture -> BSDF) par col."""
    for sl in o.material_slots:
        m = sl.material
        if m is None or not m.use_nodes:
            continue
        nt = m.node_tree
        bsdf = next((nd for nd in nt.nodes if nd.type == "BSDF_PRINCIPLED"), None)
        if bsdf is None or not bsdf.inputs["Base Color"].links:
            continue
        lien = bsdf.inputs["Base Color"].links[0]
        mix = nt.nodes.new("ShaderNodeMix"); mix.data_type = "RGBA"; mix.blend_type = "MULTIPLY"
        mix.inputs["Factor"].default_value = 1.0
        mix.inputs[7].default_value = (*col, 1.0)
        nt.links.new(lien.from_socket, mix.inputs[6])
        nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])


def trouver(nom, sous):
    p = AS.find_asset_absolute_path(nom, asset_subdir=sous)
    if p is None:
        raise SystemExit("ressource introuvable : %s/%s" % (sous, nom))
    return p


os.makedirs(OUT, exist_ok=True)
infos = []
for n, (sexe, ans, origine, peau, tenue, coiffure, chapeau, chaussures, poids, muscle, teinte) in enumerate(PERSOS):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    addon_utils.enable("bl_ext.user_default.mpfb", default_set=True)
    macro = TS.get_default_macro_info_dict()
    macro["gender"] = 1.0 if sexe == "m" else 0.0
    macro["age"] = age(ans)
    macro["weight"] = poids
    macro["muscle"] = muscle
    macro["race"] = {"african": 0.0, "asian": 0.0, "caucasian": 0.0}
    macro["race"][origine] = 1.0
    base = HS.create_human(macro_detail_dict=macro)
    HS.add_builtin_rig(base, "game_engine")
    HS.add_mhclo_asset(trouver("proxy741.proxy", "proxymeshes"), base, asset_type="Proxymeshes", subdiv_levels=0,
                       material_type="GAMEENGINE")
    proxy = OS_.find_object_of_type_amongst_nearest_relatives(base, "Proxymeshes")
    HS.set_character_skin(trouver(peau + ".mhmat", "skins"), base, bodyproxy=proxy, skin_type="GAMEENGINE")
    for nom, sous, typ in [("low-poly.mhclo", "eyes", "Eyes"), ("eyebrow001.mhclo", "eyebrows", "Eyebrows"),
                           (tenue + ".mhclo", "clothes", "Clothes"), (chaussures + ".mhclo", "clothes", "Clothes"),
                           (coiffure + ".mhclo", "hair", "Hair")] + ([(chapeau + ".mhclo", "clothes", "Clothes")] if chapeau else []):
        o = HS.add_mhclo_asset(trouver(nom, sous), base, asset_type=typ, subdiv_levels=0, material_type="GAMEENGINE")
        if nom == tenue + ".mhclo":
            teinter(o, teinte)
    racine = ES.create_character_copy(base, name_suffix="_export")
    eb = OS_.find_object_of_type_amongst_nearest_relatives(racine, "Basemesh")
    ES.bake_modifiers_remove_helpers(eb, bake_masks=True, bake_subdiv=True, remove_helpers=True, also_proxy=True)
    garder = {racine} | set(OS_.get_list_of_children(racine))
    garder.discard(eb)                                     # le maillage allégé remplace le corps complet
    for o in list(bpy.data.objects):
        if o not in garder:
            bpy.data.objects.remove(o, do_unlink=True)
    for im in bpy.data.images:
        if im.size[0] > 512:
            im.scale(512, max(1, 512 * im.size[1] // im.size[0]))
    faces = sum(len(o.data.polygons) for o in bpy.data.objects if o.type == "MESH")
    f = os.path.join(OUT, "mh_%d.glb" % n)
    bpy.ops.export_scene.gltf(filepath=f, export_format="GLB", export_image_format="JPEG", export_apply=True,
                              export_animations=False)
    infos.append({"fichier": "mh_%d.glb" % n, "sexe": sexe, "age": ans})
    print("perso", n, sexe, ans, tenue, "faces", faces, "Mo %.1f" % (os.path.getsize(f) / 1e6))
json.dump(infos, open(os.path.join(OUT, "mh.json"), "w"), indent=1)
