# Performances : les 5 directives de l'utilisateur (v6.19)

Directives données après la v6.18. Ce qui est fait, ce qui existait déjà, et ce qui est impossible ou exclu.
**À respecter pour tout nouveau système.**

## 1. Découpage et streaming du monde
- Tout ce qui est gros est en tuiles lues **en arrière-plan** avec `ResourceLoader.load_threaded_request`
  (`scripts/chargeur.gd` : `pret(chemin)` renvoie la ressource quand elle est prête, `menage(voulus)` récupère les
  lectures devenues inutiles). Utilisé par `buildings.gd`, `roads.gd` et, depuis la v6.19, `water.gd`.
  Une tuile au plus est posée par image.
- Relief : régions Terrain3D chargées autour de la voiture (`relief.gd`, v6.16).
- Petits fichiers `.bin` (clôtures, cultures, végétation…) : lecture directe. Ils font quelques Ko, donc pas
  d'à-coup mesuré.
- Pose immédiate seulement au démarrage et à la téléportation (`update_now`).

## 2. Culling et LOD
- **OccluderInstance3D est impossible** : le rendu Compatibility (obligatoire pour l'APK) ne fait pas d'occlusion
  culling. On garde `visibility_range_end` par système, et les tuiles hors de vue sont déchargées.
- LOD : `meshes/generate_lods=true` est déjà mis dans les `.import` des bâtiments, commerces et voiture.
  Godot crée lui-même les niveaux, et ce réglage se garde quand on régénère.

## 3. MultiMesh et réserve d'objets
- Décor répété :
  - en MultiMesh depuis longtemps : arbres, herbe, cultures, commerces, poteaux, mobilier, faîtières…
  - fumée, poussière et traces de roues en MultiMesh à anneau (`dust.gd`), donc rien n'est créé en roulant.
- **Objets cassables** (`casse.gd`) :
  - réserve de `MAX_DEBRIS` corps rigides préparés au démarrage (`_preparer_reserve`) ;
  - `_prendre(masse, boite)` en prend un, l'habille, et `_rendre(rb)` le remet dans la réserve (caché, figé, sans
    collision, à y = −1000) ;
  - plus aucun `new()`/`queue_free()` pendant la conduite ;
  - les maillages des mâts de panneaux sont mis en cache par hauteur.
- Restent créés à la demande (rares, pas par image) : les colonnes de lumière des activités et les menus.

## 4. Draw calls, matériaux, transparence
- **Atlas** (déjà en place, à garder) :
  - bâtiments : une seule texture-tableau (`build_bld_tex.py`, couches `LAYERS`/`IDX`) et un seul `building.gdshader`
    par tuile ;
  - commerces : un `shop.gdshader` paramétré par `kind` et trois pages d'atlas d'enseignes ;
  - bâtiments sur mesure : un atlas par bâtiment (`sur_mesure.gdshader`).
  - Pour un nouvel objet, on ajoute une couche ou une case à l'atlas existant, pas un nouveau matériau.
- **Aucune transparence mélangée (blend)**. Pour un effet translucide, deux solutions :
  - tramage ordonné dans le shader : matrice de Bayer 4 × 4 et `discard`, voir `env_dither_keep` dans
    `env.gdshaderinc` ;
  - `ALPHA_SCISSOR` (StandardMaterial3D).
  **`ALPHA_HASH` ne marche pas en Compatibility** : l'alpha est ignoré, et le quad sort plein (vérifié v6.19).
  Ne jamais utiliser `TRANSPARENCY_ALPHA`, `blend_mix`/`blend_add` avec `ALPHA`, ni `GeometryInstance3D.transparency`.
  Conversions faites :
  - vitres de la voiture : opaques, verre fumé sombre, reflets par `metallic` 0,6 / `roughness` 0,04 ;
  - eau des piscines : opaque, avec un reflet du ciel en vue rasante ;
  - fumée des roues (`fumee.gdshader`) : tramage Bayer ;
  - pluie : gouttes pleines en `ALPHA_SCISSOR` ;
  - ombres de la voiture : `ALPHA_SCISSOR` ;
  - colonnes de lumière (activités) et halo/rayon de la soucoupe (gardien) : plus de mélange additif. La
    luminosité devient la couverture tramée (Bayer + `discard`).
- **Vitrines des commerces** (`shop.gdshader`, `kind == 6`) : aplat opaque avec **Interior Mapping**.
  - Chaque case UV 0…1 cache une pièce d'une profondeur de 1.
  - Le rayon de vue, passé dans le repère de la vitre (TANGENT, BINORMAL, −NORMAL), touche le fond (rayons et
    produits), les côtés, le sol ou le plafond (lampe).
  - Le reflet du ciel est ajouté par Fresnel, et l'intérieur est éclairé la nuit.

## 5. Collisions : uniquement des BoxShape3D sur le décor
- **Bâtiments** :
  - `build_buildings.py` (`boites()`) convertit chaque emprise en boîtes orientées : on trame l'emprise dans le repère
    de son rectangle minimal, puis on fusionne les bandes (pas de 0,5 m) ;
  - le résultat est écrit dans `world/buildings/c_<x>_<z>.bin` (float32 × 7 par boîte :
    centre x y z, demi-tailles x y z, lacet) ;
  - `buildings.gd` crée une `BoxShape3D` par boîte, et le glb n'a plus de maillage de collision.
- **Bâtiments sur mesure** : `"boites"` dans `world/sur_mesure.json`, écrit par `build_boulangerie.py`.
- **Clôtures** : une boîte par segment (`fences.gd`, `_corps`), et une brèche retire des segments entiers.
- **Piscines et troncs** : boîtes au lieu de cylindres.
- **Exclus** :
  - routes et trottoirs gardent leur maillage, car c'est la surface de roulage (des boîtes feraient des marches) ;
  - le relief garde le `HeightMapShape3D` de Terrain3D ;
  - la carrosserie de la voiture est déjà une boîte.
