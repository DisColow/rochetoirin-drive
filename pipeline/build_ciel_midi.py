"""Ciel de midi (v6.70, #122) : le panorama HDR de Poly Haven (4096 × 2048, ~45 Mo de mémoire vidéo avec ses
mipmaps) découpé en deux images, sans mipmaps (le ciel est toujours agrandi à l'écran) :
  - midi_haut.hdr : la moitié haute à pleine définition (4096 × 1024), la seule qu'on voit ;
  - midi_bas.hdr : la moitié basse (cachée par le relief et l'horizon, utile seulement à la lumière ambiante),
    réduite à 1024 × 256.
Environ 18 Mo au lieu de 45. Lus par scripts/ciel_midi.gdshader (même projection que PanoramaSkyMaterial).
midi.json : azimut du soleil (point le plus lumineux de la moitié haute, comme main.gd le cherchait au démarrage).
Appelé par build_assets.py ; seul :  python3 build_ciel_midi.py"""
import json, os
import numpy as np
import rgbe

SRC = "data/ph/sky.hdr"
OUT = "../godot/assets/ciel"
STUB = """[remap]

importer="texture"
type="CompressedTexture2D"

[params]

compress/mode=0
mipmaps/generate=false
process/size_limit=0
"""


def main():
    os.makedirs(OUT, exist_ok=True)
    a = rgbe.lire(SRC)
    H, W, _ = a.shape
    haut = a[:H // 2]
    f = rgbe.vers_float(a[H // 2:])
    bas = f.reshape(H // 2 // 4, 4, W // 4, 4, 3).mean(axis=(1, 3))
    fh = rgbe.vers_float(haut[::4, ::4]).sum(axis=-1)
    y, x = np.unravel_index(int(np.argmax(fh)), fh.shape)
    json.dump({"soleil_az": round(float(x * 4) / W, 5)}, open(os.path.join(OUT, "midi.json"), "w"))
    print("soleil : u =", round(float(x * 4) / W, 4), "hauteur", round(90 - (y * 4 + 0.5) / H * 180, 1), "°")
    for nom, img in (("midi_haut.hdr", haut), ("midi_bas.hdr", rgbe.depuis_float(bas))):
        rgbe.ecrire(os.path.join(OUT, nom), img)
        imp = os.path.join(OUT, nom + ".import")
        if not os.path.exists(imp):
            open(imp, "w").write(STUB)
        print(nom, img.shape[1], "×", img.shape[0])


if __name__ == "__main__":
    main()
