"""Import du modèle 3D de l'Espace IV (Sketchfab « 2008 Renault Espace » par tonielpro520, CC-BY-4.0) -> assets/car.bin.

Téléchargement : jeton personnel dans SKETCHFAB_TOKEN (jamais écrit dans le dépôt) :
    SKETCHFAB_TOKEN=... python3 import_car.py --download
puis conversion : python3 import_car.py  (lit data/car/scene.gltf)

Repère du jeu : x à droite, y en haut, avant vers -z, origine au sol au milieu de l'empattement.
Le modèle (avant vers -X, droite vers -Z une fois l'axe Y relevé) est mis à l'échelle sur l'empattement réel (2,80 m).
Matériaux -> matériaux du shader voiture (CAR_FS) : carrosserie argent repeinte en rouge, vitres, phares, feux,
intérieur, pneus, jantes. Une roue (avant droite) est extraite et recentrée : le jeu la duplique et la fait tourner.
Format : 'CAR1', puis 3 blocs (caisse, vitres, roue) : nv, ni, nv × 12 float32, ni × uint32.
"""
import json, os, struct, sys, urllib.request, zipfile, io
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "data", "car")
OUT = os.path.join(HERE, "..", "app", "src", "main", "assets", "car.bin")
UID = "b8e7c65711134fca865f635ccddafcf5"
WHEELBASE, TRACK, WHEEL_R = 2.80, 1.56, 0.33

M_PAINT, M_GLASS, M_PLASTIC, M_CHROME, M_RUBBER, M_LAMP, M_TAIL, M_PLATE_FRONT, M_PLATE_REAR, M_INTERIOR = range(10)
RED = (0.60, 0.035, 0.045)
GLASS = (0.05, 0.07, 0.085)
BLACK = (0.045, 0.045, 0.05)
TYRE = (0.04, 0.04, 0.045)
RIM = (0.70, 0.72, 0.75)
CHROME = (0.78, 0.78, 0.80)
LAMP = (0.60, 0.64, 0.70)
TAIL = (0.75, 0.04, 0.04)
ORANGE = (0.95, 0.45, 0.05)


def download():
    tok = os.environ.get("SKETCHFAB_TOKEN")
    if not tok:
        sys.exit("SKETCHFAB_TOKEN absent")
    req = urllib.request.Request("https://api.sketchfab.com/v3/models/%s/download" % UID, headers={"Authorization": "Token " + tok})
    url = json.load(urllib.request.urlopen(req))["gltf"]["url"]
    z = zipfile.ZipFile(io.BytesIO(urllib.request.urlopen(url).read()))
    os.makedirs(SRC, exist_ok=True)
    z.extractall(SRC)
    print("modèle téléchargé dans", SRC)


def load():
    import trimesh
    sc = trimesh.load(os.path.join(SRC, "scene.gltf"), force="scene")
    parts = []
    for name in sc.graph.nodes_geometry:
        T, g = sc.graph[name]
        m = sc.geometry[g].copy()
        m.apply_transform(T)
        m.merge_vertices(merge_tex=True, merge_norm=True)
        parts.append((name, m.visual.material.name, m))
    return parts


def decimate(m, ratio, min_faces=200):
    """Simplification quadrique (fast-simplification) en gardant au moins min_faces triangles."""
    import fast_simplification, trimesh
    n = len(m.faces)
    target = max(min_faces, int(n * ratio))
    if target >= n:
        return m
    v, f = fast_simplification.simplify(np.asarray(m.vertices, np.float32), np.asarray(m.faces, np.int32), 1 - target / n)
    out = trimesh.Trimesh(v, f, process=False)
    out.visual = m.visual.__class__(material=m.visual.material) if hasattr(m.visual, "material") else m.visual
    return out


BODY_RATIO, WHEEL_RATIO = 0.25, 0.06


def crease(m, angle=35.0):
    """Normales lissées sauf sur les arêtes vives (sommets dédoublés au-delà de [angle] degrés)."""
    import trimesh
    try:
        return trimesh.graph.smooth_shade(m, angle=np.radians(angle))
    except Exception:
        return m


def main():
    parts = load()
    allv = np.vstack([m.vertices for _, _, m in parts])
    lo, hi = allv.min(0), allv.max(0)
    ext = hi - lo
    rel = lambda v: (v - lo) / ext
    # roues : pièces compactes en bas, près des quatre coins (pneus, jantes, disques)
    wheel_parts = {}
    for name, mat, m in parts:
        a, b = rel(m.bounds[0]), rel(m.bounds[1])
        if b[1] < 0.42 and (b[0] - a[0]) < 0.17 and (b[2] - a[2]) < 0.13:
            key = (a[0] > 0.5, a[2] > 0.5)                 # (arrière ?, côté +Z ?)
            wheel_parts.setdefault(key, []).append((name, mat, m))
    centers = {}
    for key, lst in wheel_parts.items():
        tyre = max(lst, key=lambda t: len(t[2].faces))[2]
        centers[key] = tyre.bounds.mean(axis=0)
    print("roues :", {k: len(v) for k, v in wheel_parts.items()})
    front = [c for (rear, _), c in centers.items() if not rear]
    rearc = [c for (rear, _), c in centers.items() if rear]
    s = WHEELBASE / abs(np.mean([c[0] for c in rearc]) - np.mean([c[0] for c in front]))
    mid = (np.mean([c[0] for c in rearc]) + np.mean([c[0] for c in front])) / 2
    zmid = np.mean([c[2] for c in centers.values()])
    ground = lo[1]

    def to_game(v):
        v = np.asarray(v, float)
        return np.c_[-(v[:, 2] - zmid) * s, (v[:, 1] - ground) * s, (v[:, 0] - mid) * s]

    def nrm_game(n):
        n = np.asarray(n, float)
        return np.c_[-n[:, 2], n[:, 1], n[:, 0]]

    print("échelle %.3g m/unité, longueur %.2f m, largeur %.2f m, hauteur %.2f m" % (s, ext[0] * s, ext[2] * s, ext[1] * s))
    in_wheel = {name for lst in wheel_parts.values() for name, _, _ in lst}
    parts = [(n, mt, decimate(m, WHEEL_RATIO if n in in_wheel else BODY_RATIO)) for n, mt, m in parts]
    wheel_parts = {k: [(n, mt, decimate(m, WHEEL_RATIO)) for n, mt, m in lst] for k, lst in wheel_parts.items()}
    body, glass, wheel = [], [], []          # listes de (V (n,12), I)

    def emit(dst, P, N, col, mat, faces, uv=None):
        V = np.zeros((len(P), 12), np.float32)
        V[:, 0:3] = P; V[:, 3:6] = N; V[:, 6:9] = col; V[:, 9] = mat
        if uv is not None:
            V[:, 10:12] = uv
        dst.append((V, faces.astype(np.uint32)))

    wc = [to_game([c])[0] for c in centers.values()]
    INTERIOR = {"auto_14": (0.11, 0.11, 0.12), "auto_13": (0.19, 0.19, 0.21), "auto_19": (0.08, 0.08, 0.09)}
    steer_c = None
    for name, mat, m in parts:
        if name in in_wheel:
            continue
        base = tuple(float(x) for x in np.array(m.visual.material.main_color[:3]) / 255.0) if hasattr(m.visual, "material") else (0.3, 0.3, 0.3)
        base = INTERIOR.get(mat, base)
        if mat == "auto_16":                               # volant du modèle : remplacé par le volant animé du jeu
            steer_c = to_game([m.bounds.mean(axis=0)])[0]
            continue
        m = crease(m)
        P = to_game(m.vertices); N = nrm_game(m.vertex_normals)
        F = np.asarray(m.faces)
        if mat == "silver1":
            # pièces argent dans les passages de roue (moyeux, disques) : jantes, pas carrosserie
            tc = P[F].mean(axis=1)
            near = np.zeros(len(F), bool)
            for c in wc:
                near |= (np.hypot(tc[:, 1] - c[1], tc[:, 2] - c[2]) < 0.36) & (np.abs(np.abs(tc[:, 0]) - abs(c[0])) < 0.32)
            if near.any():
                emit(body, P, N, RIM, M_CHROME, F[near])
            F = F[~near]
            if not len(F):
                continue
        r = rel(m.triangles_center)
        if mat == "silver1":
            emit(body, P, N, RED, M_PAINT, F)
        elif mat == "auto_11":
            emit(glass, P, N, GLASS, M_GLASS, F)
        elif mat == "chrome2":
            # lentilles des phares à l'avant, enjoliveurs chromés ailleurs
            lamp = r[:, 0] < 0.08
            for sel, col, mm in ((lamp, LAMP, M_LAMP), (~lamp, CHROME, M_CHROME)):
                if sel.any():
                    emit(body, P, N, col, mm, F[sel])
        elif mat in ("r_glass", "auto_9"):
            emit(body, P, N, TAIL, M_TAIL, F)
        elif mat == "auto_10":
            emit(body, P, N, ORANGE, M_LAMP, F)
        elif mat in ("auto_6", "Material__130"):
            # habitacle (au-dessus du plancher, à l'intérieur) en mat, extérieur en plastique noir
            emit(body, P, N, BLACK, M_PLASTIC, F)
        else:
            emit(body, P, N, base, M_INTERIOR, F)
    # roue avant droite (jeu : x > 0 = droite) recentrée sur son moyeu, face extérieure vers +x
    key = min(centers, key=lambda k: (k[0], -to_game([centers[k]])[0, 0]))
    cg = to_game([centers[key]])[0]
    side = 1.0 if cg[0] > 0 else -1.0
    for name, mat, m in wheel_parts[key]:
        P = to_game(m.vertices) - cg
        N = nrm_game(m.vertex_normals)
        P[:, 0] *= side; N[:, 0] *= side
        F = np.asarray(m.faces)
        if side < 0:
            F = F[:, ::-1]
        big = len(m.faces) > 15000
        emit(wheel, P, N, TYRE if mat == "auto_6" else RIM, M_RUBBER if mat == "auto_6" else M_CHROME, F)
    print("roue : centre %s, rayon mesuré %.3f m" % (np.round(cg, 2), cg[1]))
    # plaques d'immatriculation (texture du jeu « 4127 XR 38 ») sur les pare-chocs
    bodyP = np.vstack([v[:, :3] for v, _ in body])
    def plate(zsign, y0, y1, mat, v0):
        sel = (np.abs(bodyP[:, 0]) < 0.25) & (bodyP[:, 1] > y0) & (bodyP[:, 1] < y1)
        z = (bodyP[sel, 2].min() - 0.012) if zsign < 0 else (bodyP[sel, 2].max() + 0.012)
        yc = (y0 + y1) / 2
        w, h = 0.52, 0.11
        P = np.array([[-w / 2, yc - h / 2, z], [w / 2, yc - h / 2, z], [w / 2, yc + h / 2, z], [-w / 2, yc + h / 2, z]])
        # vue de face (avant) : la droite du lecteur est -x ; vue de l'arrière : +x
        tu = (P[:, 0] + w / 2) / w if zsign > 0 else 1 - (P[:, 0] + w / 2) / w
        tv = 1 - (P[:, 1] - (yc - h / 2)) / h
        uv = np.c_[tu, v0 + tv * 0.5]
        N = np.tile([0, 0, zsign], (4, 1))
        F = np.array([[0, 1, 2], [0, 2, 3]]) if zsign > 0 else np.array([[0, 2, 1], [0, 3, 2]])
        emit(body, P, N, (1, 1, 1), mat, F, uv)
    plate(-1, 0.38, 0.55, M_PLATE_FRONT, 0.0)
    plate(1, 0.56, 0.70, M_PLATE_REAR, 0.5)

    def pack(lst):
        V, I, off = [], [], 0
        for v, f in lst:
            V.append(v); I.append(f.ravel() + off); off += len(v)
        V = np.vstack(V) if V else np.zeros((0, 12), np.float32)
        I = np.concatenate(I) if I else np.zeros(0, np.uint32)
        return struct.pack("<ii", len(V), len(I)) + V.astype("<f4").tobytes() + I.astype("<u4").tobytes()

    # volant animé et œil du conducteur : position du volant du modèle, œil 55 cm en arrière et 30 cm plus haut
    if steer_c is None:
        steer_c = np.array([-0.40, 1.02, -0.52])
    eye = steer_c + np.array([0.0, 0.30, 0.55])
    meta = np.concatenate([steer_c, eye]).astype("<f4")
    print("volant", np.round(steer_c, 2), "œil", np.round(eye, 2))
    out = b"CAR1" + pack(body) + pack(glass) + pack(wheel) + struct.pack("<i", len(meta)) + meta.tobytes()
    open(OUT, "wb").write(out)
    nb = sum(len(v) for v, _ in body)
    print("car.bin : caisse %d sommets, vitres %d, roue %d — %.1f Mo" % (nb, sum(len(v) for v, _ in glass), sum(len(v) for v, _ in wheel), len(out) / 1e6))


if __name__ == "__main__":
    if "--download" in sys.argv:
        download()
    else:
        main()
