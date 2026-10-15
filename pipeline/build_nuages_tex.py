"""Texture des nuages du ciel peint (issue #57) -> ../godot/assets/fx/nuages.png : 512 × 512, raccord sans couture
(bruit filtré en 1/f dans le domaine de Fourier, donc périodique), R = masses (grandes échelles), G = détail.
Lue par scripts/ciel.gdshader (projection sur un plafond de nuages)."""
import numpy as np
from PIL import Image

N = 512
rng = np.random.default_rng(57)


def bruit(beta, fmin):
    f = np.fft.fftfreq(N)[:, None] ** 2 + np.fft.fftfreq(N)[None, :] ** 2
    f = np.sqrt(f); f[0, 0] = 1.0
    amp = np.where(f * N >= fmin, f ** (-beta / 2), 0.0)
    x = np.real(np.fft.ifft2(np.fft.fft2(rng.standard_normal((N, N))) * amp))
    x = (x - x.min()) / (x.max() - x.min())
    return x


r = bruit(3.2, 2)                    # masses de cumulus
g = bruit(2.2, 8)                    # bord effiloché
img = np.dstack([r, g, np.zeros_like(r)]) * 255
Image.fromarray(img.astype(np.uint8), "RGB").save("../godot/assets/fx/nuages.png")
print("nuages.png", r.mean(), g.mean())
