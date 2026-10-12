"""Lampadaire (« Street Lantern », Oneironauticus, CC BY 4.0, fetch_lampadaire.py) au format du jeu :
  - échelle d'origine (4,05 m, lanterne entre 3,14 et 3,65 m), origine au pied, Y en haut ;
  - un seul jeu d'UV (le modèle en a six), sans les textures métal/rugosité et spéculaire (inutiles au loin) ;
  - couleur et émission (vitres de la lanterne, allumées la nuit par poles.gd) réduites à 512 px.
Lancer avec le Python où bpy est installé :  <venv>/bin/python blender_lampadaire.py
Sortie : ../godot/assets/props/lampadaire.glb"""
import os
import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "godot", "import", "lampadaire", "scene.gltf")
OUT = os.path.join(HERE, "..", "godot", "assets", "props", "lampadaire.glb")
TEX = 512


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=SRC)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    for o in meshes:
        while len(o.data.uv_layers) > 1:
            o.data.uv_layers.remove(o.data.uv_layers[-1])
        for s in o.material_slots:
            m = s.material
            nt = m.node_tree
            bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
            for name in ("Metallic", "Roughness", "Specular IOR Level", "Specular Tint"):
                inp = bsdf.inputs.get(name)
                if inp is not None:
                    for l in list(inp.links):
                        nt.links.remove(l)
            bsdf.inputs["Metallic"].default_value = 0.4
            bsdf.inputs["Roughness"].default_value = 0.55
            m.use_backface_culling = True
            for n in list(nt.nodes):
                if n.type == "TEX_IMAGE":
                    if not n.outputs["Color"].links or n.image.name.find("metallic") >= 0 or n.image.name.find("specular") >= 0:
                        nt.nodes.remove(n)
                        continue
                    n.image.scale(TEX, TEX)
                    n.image.file_format = "JPEG"
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_yup=True,
                              export_apply=True, export_image_format="JPEG", export_texcoords=True)
    print("lampadaire :", sum(len(o.data.polygons) for o in meshes), "faces ->", OUT)


if __name__ == "__main__":
    main()
