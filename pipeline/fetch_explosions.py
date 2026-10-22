"""Explosions (#129) : planches d'images (« flipbooks ») de Unity Labs, simulations de feu et de fumée rendues dans
Houdini, publiées sous licence CC0 (https://unity.com/blog/engine-platform/free-vfx-image-sequences-flipbooks).
-> ../godot/assets/fx/ :
  explosion_a.png  boule de feu qui s'éteint en fumée noire (Explosion02HD, 5 × 5 images, ramenée à 1280 px : 256 px
                   par image au lieu de 409,6) ;
  explosion_b.png  boule de feu plus déchiquetée (Explosion00, 5 × 5 images, 1024 px) ;
  fumee_boule.png  bouffée de fumée grise qui tourne sur elle-même (Cloud02, 8 × 8 images, 1024 px) : poussière au
                   sol, pied du champignon.
Alpha non prémultiplié (couleurs étendues sous les pixels transparents) : mélange ordinaire dans explosion.gdshader."""
import io, os, sys, urllib.request, zipfile

from PIL import Image

BASE = "https://unity3d.com/files/labs/downloads/vfx/assets01/%s/%s-flipbooks.zip"
OUT = "../godot/assets/fx"
PLANCHES = [  # (paquet, fichier tga dans le zip, sortie, côté en px)
    ("Explosion02HD", "Explosion02HD_5x5.tga", "explosion_a.png", 1280),
    ("Explosion00", "Explosion00_5x5.tga", "explosion_b.png", 1024),
    ("Cloud02", "Cloud02_8x8.tga", "fumee_boule.png", 1024),
]


def main():
    os.makedirs(OUT, exist_ok=True)
    for paquet, tga, sortie, cote in PLANCHES:
        dest = os.path.join(OUT, sortie)
        if os.path.isfile(dest) and "--force" not in sys.argv:
            continue
        z = zipfile.ZipFile(io.BytesIO(urllib.request.urlopen(BASE % (paquet, paquet)).read()))
        im = Image.open(io.BytesIO(z.read(tga))).convert("RGBA")
        if im.size != (cote, cote):
            im = im.resize((cote, cote), Image.LANCZOS)
        im.save(dest, optimize=True)
        print("%s -> %s (%d px)" % (paquet, dest, cote))


if __name__ == "__main__":
    main()
