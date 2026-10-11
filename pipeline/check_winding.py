"""Contrôle des tuiles glb générées (routes, autoroutes) : pour chaque matériau, part des triangles dont l'ordre des
sommets donne une face tournée à l'opposé de leur normale (vus de dos : sombres, ou invisibles). Godot : face avant =
sommets dans le sens horaire vus de face ; glTF (sens trigonométrique) est retourné à l'import.
Usage : python3 check_winding.py ../godot/world/roads [...]"""
import json, os, struct, sys
from collections import defaultdict
import numpy as np

CT = {5126: np.float32, 5125: np.uint32, 5123: np.uint16}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3}


def read(path):
    b = open(path, "rb").read()
    jl = struct.unpack("<I", b[12:16])[0]
    J = json.loads(b[20:20 + jl])
    off = 20 + jl
    bl = struct.unpack("<I", b[off:off + 4])[0]
    B = b[off + 8:off + 8 + bl]

    def acc(i):
        a = J["accessors"][i]; v = J["bufferViews"][a["bufferView"]]
        o = v.get("byteOffset", 0) + a.get("byteOffset", 0)
        n = a["count"] * NC[a["type"]]
        return np.frombuffer(B, CT[a["componentType"]], n, o).reshape(a["count"], NC[a["type"]])
    for m in J["meshes"]:
        for p in m["primitives"]:
            name = J["materials"][p["material"]]["name"] if "material" in p else "?"
            P = acc(p["attributes"]["POSITION"]); N = acc(p["attributes"]["NORMAL"])
            I = acc(p["indices"]).ravel().reshape(-1, 3)
            yield name, P, N, I


def main():
    bad = defaultdict(lambda: [0, 0])
    for d in sys.argv[1:]:
        for f in sorted(os.listdir(d)):
            if not f.endswith(".glb"):
                continue
            for name, P, N, I in read(os.path.join(d, f)):
                g = np.cross(P[I[:, 1]] - P[I[:, 0]], P[I[:, 2]] - P[I[:, 0]])
                n = N[I[:, 0]] + N[I[:, 1]] + N[I[:, 2]]
                ok = np.linalg.norm(g, axis=1) > 1e-9
                s = np.einsum("ij,ij->i", g[ok], n[ok])
                bad[name][0] += int((s < 0).sum()); bad[name][1] += int(ok.sum())
    for k, (b, t) in sorted(bad.items(), key=lambda kv: -kv[1][0]):
        print("%-22s %7d / %7d triangles à l'envers (%.0f %%)" % (k, b, t, 100.0 * b / max(t, 1)))


if __name__ == "__main__":
    main()
