"""Textures de bâtiments : Poly Haven (CC0) -> data/ph/<id>/ ; ambientCG (CC0) -> data/acg/<id>/ (1K)."""
import io, json, os, urllib.request, zipfile
H = {"User-Agent": "rochetoirin-drive/1.0"}
PH = ["white_rough_plaster", "yellow_plaster_02", "beige_wall_001", "plastered_stone_wall", "rustic_stone_wall",
      "old_stone_wall", "castle_wall_varriation", "clay_roof_tiles", "clay_roof_tiles_02", "clay_roof_tiles_03",
      "roof_tiles", "ceramic_roof_01", "grey_roof_tiles", "factory_wall", "wood_shutter", "worn_shutter",
      "painted_metal_shutter", "rusty_metal_shutter", "wooden_garage_door", "rough_pine_door", "wood_plank_wall",
      "concrete_wall_008", "red_slate_roof_tiles_01", "roof_slates_02", "stone_wall_04", "medieval_wall_01"]
ACG = ["Plaster003", "Bricks085", "WoodSiding008", "CorrugatedSteel005", "RoofingTiles014A", "RoofingTiles012A", "Door001",
       "Door002", "Bricks075A"]
def get(u, p):
    if not os.path.exists(p):
        open(p, "wb").write(urllib.request.urlopen(urllib.request.Request(u, headers=H), timeout=300).read())
for t in PH:
    f = json.loads(urllib.request.urlopen(urllib.request.Request("https://api.polyhaven.com/files/" + t, headers=H)).read())
    os.makedirs("data/ph/" + t, exist_ok=True)
    for key, name in (("Diffuse", "diff"), ("nor_gl", "nor_gl"), ("Rough", "rough")):
        if key in f and "1k" in f[key]:
            d = f[key]["1k"]
            fmt = "jpg" if "jpg" in d else "png"
            get(d[fmt]["url"], "data/ph/%s/%s.%s" % (t, name, fmt))
    print(t, sorted(os.listdir("data/ph/" + t)))
for a in ACG:
    d = "data/acg/" + a
    if os.path.isdir(d):
        continue
    z = zipfile.ZipFile(io.BytesIO(urllib.request.urlopen(urllib.request.Request(
        "https://ambientcg.com/get?file=%s_1K-JPG.zip" % a, headers=H), timeout=300).read()))
    os.makedirs(d); z.extractall(d)
    print(a, sorted(os.listdir(d)))
