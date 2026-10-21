"""Lecture / écriture Radiance HDR (RGBE, RLE « nouveau format »)."""
import numpy as np

def lire(chemin):
    d = open(chemin, "rb").read()
    i = 0
    while True:
        j = d.index(b"\n", i)
        ligne = d[i:j]; i = j + 1
        if ligne == b"":
            break
    j = d.index(b"\n", i)
    res = d[i:j].split(); i = j + 1
    H, W = int(res[1]), int(res[3])
    out = np.zeros((H, W, 4), np.uint8)
    for y in range(H):
        if d[i] == 2 and d[i + 1] == 2 and (d[i + 2] << 8 | d[i + 3]) == W:
            i += 4
            for c in range(4):
                x = 0
                ligne = out[y, :, c]
                while x < W:
                    n = d[i]; i += 1
                    if n > 128:
                        n -= 128
                        ligne[x:x + n] = d[i]; i += 1
                    else:
                        ligne[x:x + n] = np.frombuffer(d, np.uint8, n, i); i += n
                    x += n
        else:
            out[y] = np.frombuffer(d, np.uint8, W * 4, i).reshape(W, 4); i += W * 4
    return out

def vers_float(rgbe):
    e = rgbe[..., 3].astype(np.int32)
    f = np.where(e > 0, np.ldexp(1.0, e - 136), 0.0)
    return rgbe[..., :3].astype(np.float64) * f[..., None]

def depuis_float(rgb):
    m = rgb.max(axis=-1)
    out = np.zeros(rgb.shape[:-1] + (4,), np.uint8)
    ok = m > 1e-32
    mant, ex = np.frexp(np.where(ok, m, 1.0))
    k = np.where(ok, mant * 256.0 / m, 0.0)
    out[..., :3] = np.clip(rgb * k[..., None], 0, 255).astype(np.uint8)
    out[..., 3] = np.where(ok, ex + 128, 0).astype(np.uint8)
    return out

def ecrire(chemin, rgbe):
    H, W, _ = rgbe.shape
    parts = [b"#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n", ("-Y %d +X %d\n" % (H, W)).encode()]
    for y in range(H):
        parts.append(bytes([2, 2, W >> 8, W & 255]))
        for c in range(4):
            ligne = rgbe[y, :, c].tobytes()
            for x in range(0, W, 128):
                morceau = ligne[x:x + 128]
                parts.append(bytes([len(morceau)]) + morceau)
    open(chemin, "wb").write(b"".join(parts))
