"""Étend la couleur des imposteurs sous les pixels transparents (pas de liseré sombre au filtrage / mipmaps)."""
import numpy as np
from PIL import Image
from scipy import ndimage as ndi
for f in ("albedo", "normal"):
    p = "../godot/assets/veg/impostors_%s.png" % f
    a = np.asarray(Image.open(p).convert("RGBA")).astype(np.float32)
    m = a[..., 3] > 8
    _, (iy, ix) = ndi.distance_transform_edt(~m, return_indices=True)
    rgb = a[..., :3][iy, ix]
    out = np.dstack([rgb, a[..., 3]]).astype(np.uint8)
    Image.fromarray(out, "RGBA").save(p)
    print(f, "couverture %.0f %%" % (100 * m.mean()))
