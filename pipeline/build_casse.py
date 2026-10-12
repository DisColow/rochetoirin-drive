"""Décor destructible (v6.9) : positions des panneaux de signalisation, relevées dans les tuiles de routes
(../godot/world/roads/t_*.glb, matériau « metal » des mâts : cylindres de 8 faces = 18 sommets, posés par
furniture._pole) -> ../godot/world/panneaux.bin : nombre (u32), puis x, y du pied, z, hauteur (float32) par mât.
Lu par casse.gd (panneaux renversés au choc, effacés de la tuile par le shader : simple.gdshader, uniform casse)."""
import glob, json, os, struct

HERE = os.path.dirname(os.path.abspath(__file__))
ROADS = os.path.join(HERE, "..", "godot", "world", "roads")
OUT = os.path.join(HERE, "..", "godot", "world", "panneaux.bin")


def positions(path):
    b = open(path, "rb").read()
    n = struct.unpack_from("<I", b, 12)[0]
    g = json.loads(b[20:20 + n])
    bin0 = 20 + n + 8
    mats = [m.get("name") for m in g.get("materials", [])]
    out = []
    for m in g["meshes"]:
        if m.get("name") != "detail":
            continue
        for p in m["primitives"]:
            if mats[p["material"]] != "metal":
                continue
            a = g["accessors"][p["attributes"]["POSITION"]]
            v = g["bufferViews"][a["bufferView"]]
            off = bin0 + v.get("byteOffset", 0) + a.get("byteOffset", 0)
            st = v.get("byteStride", 12)
            pts = [struct.unpack_from("<3f", b, off + i * st) for i in range(a["count"])]
            for i in range(0, len(pts) - 17, 18):
                grp = pts[i:i + 18]
                xs = [q[0] for q in grp]; zs = [q[2] for q in grp]; ys = [q[1] for q in grp]
                r = (max(xs) - min(xs)) / 2
                if r > 0.1 or max(zs) - min(zs) > 0.25:      # pas un mât (ou groupes décalés)
                    continue
                out.append((sum(xs) / 18, min(ys), sum(zs) / 18, max(ys) - min(ys)))
    return out


def main():
    allp = []
    for f in sorted(glob.glob(os.path.join(ROADS, "t_*.glb"))):
        allp += positions(f)
    with open(OUT, "wb") as fo:
        fo.write(struct.pack("<I", len(allp)))
        for p in allp:
            fo.write(struct.pack("<4f", *p))
    print("panneaux :", len(allp), "mâts ->", OUT)


if __name__ == "__main__":
    main()
