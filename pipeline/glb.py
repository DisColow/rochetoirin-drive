"""Écriture minimale de fichiers glTF binaires (.glb) : une primitive par matériau (nom = nom du matériau,
remplacé dans Godot par le matériau PBR du même nom)."""
import json, struct
import numpy as np


def write_glb(path, prims, node_name="tile"):
    """prims : [(nom_matériau, positions N×3, normales N×3, uv N×2, indices[, couleurs[, uv2 N×2]])] ou
    {nom_de_nœud: [prims]} (un nœud / maillage par entrée)."""
    groups = prims if isinstance(prims, dict) else {node_name: prims}
    blob = bytearray(); views, accs, mats = [], [], []
    meshes, nodes = [], []

    def add(arr, target, comp, typ, minmax=False):
        a = np.ascontiguousarray(arr)
        while len(blob) % 4:
            blob.append(0)
        off = len(blob); blob.extend(a.tobytes())
        views.append(dict(buffer=0, byteOffset=off, byteLength=a.nbytes, **({"target": target} if target else {})))
        acc = dict(bufferView=len(views) - 1, componentType=comp, count=int(a.shape[0]), type=typ)
        if minmax:
            acc["min"] = a.min(0).tolist(); acc["max"] = a.max(0).tolist()
        accs.append(acc)
        return len(accs) - 1

    for gname, gprims in groups.items():
      meshes_prims = []
      for pr in gprims:
        name, P, Nn, UV, I = pr[:5]
        COL = pr[5] if len(pr) > 5 else None
        P = np.asarray(P, np.float32); Nn = np.asarray(Nn, np.float32); UV = np.asarray(UV, np.float32)
        I = np.asarray(I, np.uint32)
        ip = add(P, 34962, 5126, "VEC3", True)
        inn = add(Nn, 34962, 5126, "VEC3")
        iu = add(UV, 34962, 5126, "VEC2")
        ii = add(I, 34963, 5125, "SCALAR")
        at = dict(POSITION=ip, NORMAL=inn, TEXCOORD_0=iu)
        if len(pr) > 6 and pr[6] is not None:
            at["TEXCOORD_1"] = add(np.asarray(pr[6], np.float32), 34962, 5126, "VEC2")
        if COL is not None:
            at["COLOR_0"] = add(np.c_[np.asarray(COL, np.float32), np.ones(len(COL), np.float32)], 34962, 5126, "VEC4")
        mats.append(dict(name=name))
        meshes_prims.append(dict(attributes=at, indices=ii, material=len(mats) - 1))
      meshes.append(dict(name=gname, primitives=meshes_prims)); nodes.append(dict(name=gname, mesh=len(meshes) - 1))
    gl = dict(asset=dict(version="2.0", generator="rochetoirin"), scene=0, scenes=[dict(nodes=list(range(len(nodes))))],
              nodes=nodes, meshes=meshes,
              materials=mats, accessors=accs, bufferViews=views, buffers=[dict(byteLength=len(blob))])
    js = json.dumps(gl, separators=(",", ":")).encode()
    while len(js) % 4:
        js += b" "
    while len(blob) % 4:
        blob.append(0)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(blob)))
        f.write(struct.pack("<II", len(js), 0x4E4F534A)); f.write(js)
        f.write(struct.pack("<II", len(blob), 0x004E4942)); f.write(blob)
