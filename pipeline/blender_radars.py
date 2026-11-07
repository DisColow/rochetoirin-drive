"""Radars (#182) : modèles Sketchfab de fetch_radars.py -> ../godot/assets/props/radar_fixe.glb, radar_mobile.glb.
Base au sol à l'origine, objectif tourné vers +Z du jeu (-Y de Blender : c'est déjà le cas des deux modèles).
Cabine fixe (Gatso anglais jaune) repeinte en gris comme les cabines françaises : texture de la caisse passée en gris
(luminance éclaircie), le reste gardé.
Lancer : <venv bpy>/python -I blender_radars.py"""
import os
import bpy
import numpy as np

ICI = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(ICI, "../godot/import/radars")
OUT = os.path.join(ICI, "../godot/assets/props")


def griser(img):
    px = np.array(img.pixels[:], dtype=np.float32).reshape(-1, 4)
    lum = px[:, 0] * 0.3 + px[:, 1] * 0.59 + px[:, 2] * 0.11
    g = np.clip(lum * 0.55 + 0.04, 0.0, 1.0)              # gris moyen des cabines françaises
    px[:, 0] = g * 0.96; px[:, 1] = g * 0.98; px[:, 2] = g
    img.pixels[:] = px.ravel()
    img.update()
    img.pack()


def convertir(nom):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, nom, "scene.gltf"))
    if nom == "radar_fixe":
        for m in bpy.data.materials:
            if m.name == "face1" and m.node_tree:
                for n in m.node_tree.nodes:
                    if n.type == "TEX_IMAGE" and n.image:
                        griser(n.image)
    os.makedirs(OUT, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, nom + ".glb"), export_format="GLB", export_yup=True,
                              export_apply=True, export_image_format="AUTO")
    print(nom, "->", os.path.join(OUT, nom + ".glb"))


for k in ("radar_fixe", "radar_mobile"):
    convertir(k)
