"""Textures des voitures du garage importées compressées (v6.70, #122) : Godot extrait les images des glb sans
compression (« sans perte ») quand l'import se fait sans éditeur, et une seule voiture pesait jusqu'à 123 Mo de
mémoire vidéo (R5). Met « compress/mode=2 » (compression vidéo) dans le .import de chaque image, et
« compress/normal_map=1 » pour les cartes de normales ; crée un .import minimal si l'image n'en a pas encore.
À lancer après blender_voitures_joueur.py, avant l'import Godot.   python3 compresser_textures.py [dossier…]"""
import glob, os, re, sys

DOSSIERS = sys.argv[1:] or ["../godot/assets/voitures"]
STUB = """[remap]

importer="texture"
type="CompressedTexture2D"

[params]

compress/mode=2
compress/normal_map=%d
mipmaps/generate=true
"""


def main():
    n = 0
    for d in DOSSIERS:
        for f in sorted(glob.glob(os.path.join(d, "**", "*.*"), recursive=True)):
            if not f.lower().endswith((".png", ".jpg", ".jpeg", ".webp")):
                continue
            normale = "normal" in os.path.basename(f).lower()
            imp = f + ".import"
            if not os.path.exists(imp):
                open(imp, "w").write(STUB % (1 if normale else 0))
                n += 1
                continue
            t = open(imp).read()
            t2 = re.sub(r"^compress/mode=\d$", "compress/mode=2", t, flags=re.M)
            if normale:
                t2 = re.sub(r"^compress/normal_map=\d$", "compress/normal_map=1", t2, flags=re.M)
            if t2 != t:
                open(imp, "w").write(t2)
                n += 1
    print(n, "fichiers .import modifiés")


if __name__ == "__main__":
    main()
