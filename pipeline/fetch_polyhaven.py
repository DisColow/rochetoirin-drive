"""Textures PBR et ciel HDRI Poly Haven (CC0) -> data/ph/<id>/{diff,nor_gl,rough,disp}.jpg ; ciel .hdr"""
import json, os, urllib.request
H = {"User-Agent": "rochetoirin-drive/1.0"}
TEX = ["asphalt_02", "gravel_road", "concrete_pavement", "concrete", "leafy_grass", "grass_ground", "forest_ground_04",
       "aerial_rocks_02", "brown_mud_02", "dry_ground_rocks"]
HDRI = "kloofendal_48d_partly_cloudy_puresky"
def get(u, p):
    if not os.path.exists(p):
        open(p, "wb").write(urllib.request.urlopen(urllib.request.Request(u, headers=H), timeout=300).read())
for t in TEX:
    f = json.loads(urllib.request.urlopen(urllib.request.Request("https://api.polyhaven.com/files/" + t, headers=H)).read())
    os.makedirs("data/ph/" + t, exist_ok=True)
    for key, name in (("Diffuse", "diff"), ("nor_gl", "nor_gl"), ("Rough", "rough"), ("Displacement", "disp"), ("AO", "ao")):
        if key in f and "2k" in f[key]:
            d = f[key]["2k"]
            fmt = "jpg" if "jpg" in d else "png"
            get(d[fmt]["url"], "data/ph/%s/%s.%s" % (t, name, fmt))
    print(t, os.listdir("data/ph/" + t))
f = json.loads(urllib.request.urlopen(urllib.request.Request("https://api.polyhaven.com/files/" + HDRI, headers=H)).read())
get(f["hdri"]["4k"]["hdr"]["url"], "data/ph/sky.hdr")
print("ciel", os.path.getsize("data/ph/sky.hdr"))
