"""Touffes de haie faites avec Blender : grappes de cartes de feuillage (texture build_haie_tex.py) disposées en dôme,
une par essence (thuya, laurier-palme, photinia, champêtre). fences.gd en couvre le volume des haies (dessus et
flancs) pour une silhouette feuillue, irrégulière, au lieu d'un bloc lisse.
Repère (après export glTF) : +z = vers l'extérieur de la haie, la touffe tient dans ±0,45 m.
Lancer avec le Python où bpy est installé :  <venv>/bin/python blender_haies.py
Sorties : ../godot/assets/fence/touffe_<essence>.glb"""
import math, os, random, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
import bmesh
import mathutils
import blender_commerces
from blender_commerces import reset, mat, export

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "godot", "assets", "fence")
blender_commerces.OUT = OUT
# essence : case de l'atlas (colonne, ligne), nombre de cartes, taille, aplatissement du dôme
ESS = {"thuya": ((0, 0), 11, 0.55, 0.55), "laurier": ((1, 0), 9, 0.62, 0.7),
       "photinia": ((0, 1), 10, 0.58, 0.65), "champetre": ((1, 1), 12, 0.6, 0.85)}


def touffe(name, cell, n, size, flat):
    reset()
    rng = random.Random(hash(name) & 0xffff)
    m = mat("feuilles", (0.3, 0.5, 0.25), rough=0.7)
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    u0, v0 = cell[0] * 0.5, cell[1] * 0.5
    for k in range(n):
        # centre sur un dôme (vers +Y Blender = -Z glTF ? non : on vise -Y Blender = +Z glTF, l'extérieur)
        th = math.acos(1 - rng.random() * 0.9)          # 0 = sommet du dôme
        ph = rng.random() * 2 * math.pi
        nrm = mathutils.Vector((math.sin(th) * math.cos(ph), math.sin(th) * math.sin(ph) * flat, math.cos(th)))
        nrm = mathutils.Vector((nrm.x, -nrm.z, nrm.y)).normalized()      # axe du dôme : -Y Blender (= +z glTF)
        c = nrm * 0.18 * (0.6 + 0.4 * rng.random())
        s = size * (0.75 + 0.5 * rng.random())
        # repère de la carte : normale ~ nrm, inclinée au hasard, tournée sur elle-même
        nn = (nrm + mathutils.Vector((rng.uniform(-.5, .5), rng.uniform(-.5, .5), rng.uniform(-.5, .5)))).normalized()
        t = nn.cross(mathutils.Vector((0, 0, 1)))
        if t.length < 1e-3:
            t = mathutils.Vector((1, 0, 0))
        t.normalize()
        b = nn.cross(t).normalized()
        a = rng.random() * 2 * math.pi
        t, b = t * math.cos(a) + b * math.sin(a), b * math.cos(a) - t * math.sin(a)
        vs = [bm.verts.new(c + (t * x + b * y) * s / 2) for x, y in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
        f = bm.faces.new(vs)
        for lp, (x, y) in zip(f.loops, ((0, 0), (1, 0), (1, 1), (0, 1))):
            # v Blender en bas -> v glTF = 1 - v : on vise la case (colonne, ligne) depuis le haut de l'image
            lp[uvl].uv = (u0 + x * 0.5, 1 - (v0 + (1 - y) * 0.5))
    bm.normal_update()
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    o = bpy.data.objects.new(name, me); bpy.context.collection.objects.link(o); o.data.materials.append(m)
    # normales orientées vers l'extérieur du dôme (éclairage doux de feuillage)
    me.shade_smooth()
    export("touffe_" + name)


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, (cell, n, size, flat) in ESS.items():
        touffe(name, cell, n, size, flat)


if __name__ == "__main__":
    main()
