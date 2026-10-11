"""Commerces : devantures, enseignes parodiques, stores, croix de pharmacie, carottes de tabac, terrasses, supermarchés
(enseigne géante, auvent d'entrée, totem, abri à chariots) et stations-service (auvent, pompes, totem).
 - points OSM (data/osm_shops.json, fetch_shops.py) dans la zone de jeu ;
 - jamais de vraie marque : chaque marque connue a sa parodie (PARODIES), les commerces indépendants reçoivent un nom
   inventé selon leur métier (on ne reprend pas le nom des vrais commerçants) ;
 - la devanture se pose sur la façade réelle du bâtiment en jeu (même découpe au bord des routes et même
   simplification que build_buildings.py), sur le mur le plus proche de la rue, sans chevauchement entre commerces ;
 - rien ne déborde sur la chaussée : store et potences seulement si leur emprise reste hors de la chaussée, terrasse
   seulement s'il y a la place devant (hors trottoir), totems et stations hors de l'emprise des routes ;
Modèles : blender_commerces.py (../godot/assets/shops/*.glb).
Sorties : ../godot/assets/shops/enseignes.png (atlas 4096², cases 640 × 128 pour les bandeaux, 256 × 256 pour les
totems), ../godot/world/shops/s_tx_tz.bin : int32 n puis n × 17 float32 (modèle, base 3 × 3 colonnes, origine,
données d'instance r, g, b, a)."""
import hashlib, json, math, os, pickle, shutil
from collections import defaultdict
import numpy as np
import shapely
from shapely.geometry import LineString, Point, Polygon
from shapely.ops import unary_union
from shapely.strtree import STRtree
from PIL import Image, ImageDraw, ImageFont
import geo
from build_vegetation import Carved
from build_fences import Local
from build_buildings import load as load_buildings

OUT_A = "../godot/assets/shops"
OUT_W = "../godot/world/shops"
TILE = 256.0
MODELS = ["vitrine", "porte", "enseigne", "lampes", "banne", "croix", "carotte", "totem", "ombriere", "pompe",
          "abri_caddies", "terrasse", "auvent", "bandeau", "pilastre", "coffre_rideau", "porte_sectionnelle", "bardage",
          "boutique_station", "gonfleur", "lavage", "panneau_prix", "affiche", "marquise"]
MID = {n: i for i, n in enumerate(MODELS)}

F_SANS = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
F_SERIF = "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf"
F_COND = "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf"
F_ITAL = "/usr/share/fonts/truetype/liberation/LiberationSerif-BoldItalic.ttf"

# marque réelle -> (parodie, fond, texte, police, style)
PARODIES = {
    "Crédit Agricole": ("Crédit Agricolo", (0, 122, 110), (255, 255, 255), F_SANS, "banque"),
    "Vival": ("Vivol", (230, 30, 40), (255, 255, 255), F_SANS, None),
    "La Poste": ("La Pausse", (255, 205, 0), (20, 40, 110), F_SANS, None),
    "Renault": ("Renaud", (255, 205, 0), (0, 0, 0), F_SANS, "losange"),
    "Carrefour": ("Carrefou", (255, 255, 255), (0, 75, 160), F_SANS, "carrefou"),
    "Carrefour Market": ("Carrefou Marquette", (255, 255, 255), (0, 75, 160), F_SANS, "carrefou"),
    "Carrefour Contact": ("Carrefou Contacte", (255, 255, 255), (0, 75, 160), F_SANS, "carrefou"),
    "Carrefour City": ("Carrefou Citi", (255, 255, 255), (0, 75, 160), F_SANS, "carrefou"),
    "Carrefour Express": ("Carrefou Exprès", (255, 255, 255), (0, 75, 160), F_SANS, "carrefou"),
    "Lidl": ("Lidol", (0, 80, 170), (255, 225, 0), F_SANS, "rond"),
    "Marie Blachère": ("Marie Blachoir", (120, 30, 40), (255, 240, 220), F_ITAL, None),
    "Intermarché": ("Entremarché", (226, 0, 26), (255, 255, 255), F_SANS, None),
    "McDonald's": ("McDonuts", (200, 16, 46), (255, 199, 44), F_SANS, "m"),
    "Caisse d'Épargne": ("Caisse d'Éparpille", (220, 0, 40), (255, 255, 255), F_SANS, "banque"),
    "Total": ("Totale", (240, 70, 30), (255, 255, 255), F_SANS, "soleil"),
    "TotalEnergies": ("Totale Énergies", (240, 70, 30), (255, 255, 255), F_SANS, "soleil"),
    "Peugeot": ("Pijo", (20, 30, 60), (255, 255, 255), F_SANS, None),
    "LCL": ("LOL", (0, 45, 110), (255, 220, 0), F_SANS, "banque"),
    "Crédit Mutuel": ("Crédit Mutant", (0, 60, 130), (255, 255, 255), F_SANS, "banque"),
    "Gamm Vert": ("Gang Vert", (90, 170, 50), (255, 255, 255), F_SANS, None),
    "E.Leclerc": ("E.Leplerc", (0, 90, 170), (255, 255, 255), F_SANS, "orange"),
    "Grand Frais": ("Grand Froid", (40, 120, 60), (255, 255, 255), F_SERIF, None),
    "Proxi": ("Proxo", (230, 30, 40), (255, 255, 255), F_SANS, None),
    "Eni": ("Énu", (255, 210, 0), (0, 0, 0), F_SANS, None),
    "Aldi": ("Aldo", (0, 40, 120), (255, 255, 255), F_SANS, "rond"),
    "Action": ("Faction", (0, 80, 160), (255, 255, 255), F_SANS, None),
    "GiFi": ("GiFou", (230, 0, 125), (255, 255, 255), F_SANS, None),
    "Speedy": ("Speedo", (255, 210, 0), (0, 0, 0), F_SANS, None),
    "Point S": ("Point Z", (230, 0, 30), (255, 255, 255), F_SANS, None),
    "Castorama": ("Castorami", (0, 90, 170), (255, 255, 255), F_SANS, None),
    "Intersport": ("Intersporc", (0, 60, 140), (255, 255, 255), F_SANS, None),
    "Boulanger": ("Boulangé", (255, 255, 255), (230, 40, 30), F_SANS, None),
    "Super U": ("Super Ü", (230, 0, 30), (255, 255, 255), F_SANS, None),
    "U Express": ("Ü Exprès", (230, 0, 30), (255, 255, 255), F_SANS, None),
    "Hyper U": ("Hyper Ü", (230, 0, 30), (255, 255, 255), F_SANS, None),
    "Netto": ("Nettoie", (255, 220, 0), (200, 0, 30), F_SANS, None),
    "Auchan": ("Oh Chan", (230, 30, 40), (255, 255, 255), F_SANS, None),
    "Casino": ("Casinon", (0, 120, 70), (255, 255, 255), F_SANS, None),
    "Spar": ("Sparre", (0, 130, 70), (255, 255, 255), F_SANS, None),
    "Dacia": ("Dacio", (100, 110, 40), (255, 255, 255), F_SANS, None),
    "Citroën": ("Citronne", (180, 0, 30), (255, 255, 255), F_SANS, None),
    "BNP Paribas": ("BNP Paripas", (0, 140, 90), (255, 255, 255), F_SANS, "banque"),
    "Société Générale": ("Société Généreuse", (230, 0, 30), (255, 255, 255), F_SANS, "banque"),
    "Banque Populaire": ("Banque Pas Populaire", (0, 50, 120), (255, 255, 255), F_SANS, "banque"),
    "CIC": ("CIQ", (0, 80, 140), (255, 255, 255), F_SANS, "banque"),
    "Krys": ("Kriss", (0, 0, 0), (255, 255, 255), F_SANS, None),
    "Atol": ("Atoll", (0, 60, 130), (255, 255, 255), F_SANS, None),
    "Paul": ("Paulo", (40, 30, 30), (220, 200, 150), F_SERIF, None),
    "Franck Provost": ("Franck Provot", (0, 0, 0), (255, 255, 255), F_SERIF, None),
    "Yves Rocher": ("Yves Rochet", (0, 100, 50), (255, 255, 255), F_SERIF, None),
    "Biocoop": ("Bioquoi", (120, 170, 40), (255, 255, 255), F_SANS, None),
    "SFR": ("SFRR", (230, 0, 30), (255, 255, 255), F_SANS, None),
    "Thiriet": ("Thirié", (0, 80, 160), (255, 255, 255), F_SANS, None),
    "Point P": ("Point Q", (230, 0, 30), (255, 255, 255), F_SANS, None),
    "Maison de la Presse": ("Maison de la Presse-Purée", (0, 60, 130), (255, 255, 255), F_SANS, None),
    "Columbus Café & Co": ("Colombo Café & Co", (90, 50, 30), (255, 255, 255), F_SERIF, None),
    "Burger King": ("Burger Kong", (240, 130, 0), (120, 40, 20), F_SANS, None),
    "KFC": ("KFQ", (200, 16, 46), (255, 255, 255), F_SANS, None),
    "Esso": ("Asso", (255, 255, 255), (0, 60, 150), F_SANS, None),
    "Avia": ("Avion", (230, 0, 30), (255, 255, 255), F_SANS, None),
}
GENERIC = {   # métier -> (étiquette, noms inventés, fond, texte, police, accessoires)
    "bakery": ("BOULANGERIE · PÂTISSERIE", ["Au Pain Doré", "La Mie Câline d'Isère", "Le Fournil du Balcon", "Aux Délices de Rochetoirin", "La Baguette Magique"],
               (110, 70, 40), (250, 235, 200), F_SERIF, ("banne", (0.55, 0.32, 0.18))),
    "butcher": ("BOUCHERIE · CHARCUTERIE", ["Chez Bébert", "La Côte de Bœuf", "Boucherie du Dauphin"], (150, 20, 25), (255, 255, 255), F_SERIF, ("banne", (0.65, 0.08, 0.08))),
    "pharmacy": ("PHARMACIE", ["Pharmacie du Centre", "Pharmacie des Collines", "Pharmacie de la Bourbre"], (255, 255, 255), (0, 140, 70), F_SANS, ("croix", None)),
    "tobacco": ("TABAC · PRESSE", ["Le Balto", "Le Narval", "Tabac du Commerce"], (40, 40, 45), (255, 255, 255), F_SANS, ("carotte", None)),
    "newsagent": ("TABAC · PRESSE", ["Le Balto", "Le Narval", "Tabac du Commerce"], (40, 40, 45), (255, 255, 255), F_SANS, ("carotte", None)),
    "hairdresser": ("COIFFURE", ["Tif'Isère", "Hair de Rien", "Coup d'Ciseaux", "Diminu'Tif", "L'Hair du Temps"], (20, 20, 25), (230, 190, 120), F_ITAL, None),
    "beauty": ("INSTITUT DE BEAUTÉ", ["Belle de Jour", "Zen Attitude", "L'Instant Pour Soi"], (230, 200, 210), (90, 40, 60), F_ITAL, None),
    "bar": ("CAFÉ · BAR", ["Café des Sports", "Le Bar du Commerce", "Le Penalty", "Chez Dédé"], (25, 60, 40), (240, 220, 160), F_SERIF, ("terrasse", (0.12, 0.35, 0.2))),
    "pub": ("PUB", ["Le Trèfle", "The Dauphin"], (20, 50, 30), (240, 220, 160), F_SERIF, ("terrasse", (0.12, 0.35, 0.2))),
    "cafe": ("CAFÉ", ["Le Petit Noir", "Café de la Place"], (60, 35, 25), (240, 220, 180), F_SERIF, ("terrasse", (0.6, 0.12, 0.1))),
    "restaurant": ("RESTAURANT", ["Le Relais du Coin", "La Bonne Fourchette", "L'Auberge du Mont", "Chez Mémé", "Le Gratin Dauphinois"],
                   (90, 20, 25), (245, 230, 200), F_SERIF, ("terrasse", (0.55, 0.1, 0.1))),
    "fast_food": ("SNACK", ["Kebab du Coin", "Tacos Tacos", "Pizza Bella", "Le Petit Creux"], (230, 120, 0), (255, 255, 255), F_SANS, None),
    "bank": ("BANQUE", ["Banque de l'Isère"], (0, 60, 120), (255, 255, 255), F_SANS, None),
    "post_office": ("LA PAUSSE", ["La Pausse"], (255, 205, 0), (20, 40, 110), F_SANS, None),
    "florist": ("FLEURS", ["L'Atelier Fleuri", "Au Jardin d'Émilie", "Pétales & Cie"], (240, 235, 225), (120, 40, 90), F_ITAL, ("banne", (0.2, 0.42, 0.25))),
    "optician": ("OPTIQUE", ["Vue sur la Bourbre", "Optique Lunettes & Cie"], (255, 255, 255), (20, 60, 120), F_SANS, None),
    "clothes": ("PRÊT-À-PORTER", ["Mademoiselle Isère", "Le Dressing", "Fil d'Ariane"], (30, 30, 35), (255, 255, 255), F_ITAL, None),
    "shoes": ("CHAUSSURES", ["Pied à Terre", "La Godasse"], (50, 40, 35), (255, 255, 255), F_SANS, None),
    "car": ("AUTOMOBILES", ["Garage du Rond-Point", "Auto Dauphiné"], (20, 60, 130), (255, 255, 255), F_SANS, None),
    "car_repair": ("GARAGE · RÉPARATIONS", ["Garage du Rond-Point", "Garage Moderne", "Auto Service des Vallons"], (20, 60, 130), (255, 255, 255), F_SANS, None),
    "convenience": ("ÉPICERIE", ["L'Épicerie du Village", "Panier Malin"], (200, 30, 40), (255, 255, 255), F_SANS, ("banne", (0.65, 0.1, 0.1))),
    "supermarket": ("SUPERMARCHÉ", ["Marché Plus", "Super Panier"], (200, 30, 40), (255, 255, 255), F_SANS, None),
    "laundry": ("LAVERIE", ["Lav'Express"], (0, 140, 200), (255, 255, 255), F_SANS, None),
    "jewelry": ("BIJOUTERIE", ["Or & Merveilles"], (20, 20, 25), (220, 190, 110), F_SERIF, None),
    "doityourself": ("BRICOLAGE", ["Brico Bob"], (240, 130, 0), (255, 255, 255), F_SANS, None),
    "garden_centre": ("JARDINERIE", ["Les Serres du Coteau"], (60, 130, 50), (255, 255, 255), F_SANS, None),
    "pet": ("ANIMALERIE", ["Croquettes & Cie"], (0, 120, 160), (255, 255, 255), F_SANS, None),
    "fuel": ("STATION", ["Station du Rond-Point"], (230, 30, 40), (255, 255, 255), F_SANS, None),
}
OTHER = ("COMMERCE", ["Le Comptoir", "Au Bon Coin", "Chez Nous", "La Boutique", "L'Échoppe", "Le Magasin du Coin"],
         (60, 60, 70), (255, 255, 255), F_SANS, None)

# métiers moins fréquents : (étiquette, noms inventés, fond, texte, police) ; noms jamais repris des vrais commerces
for _k, _v in {
    "car_wash": ("LAVAGE AUTO", ["Lav'Auto Express", "Station Bulle", "Brillance Auto"], (0, 120, 200), (255, 255, 255), F_SANS),
    "furniture": ("MEUBLES", ["L'Atelier du Meuble", "Maison & Salon", "Le Grenier Moderne", "Confort Dauphiné"], (60, 50, 45), (255, 255, 255), F_SANS),
    "variety_store": ("BAZAR · DISCOUNT", ["Tout à Petits Prix", "Le Grand Bazar", "Bric & Broc"], (230, 0, 60), (255, 255, 255), F_SANS),
    "mobile_phone": ("TÉLÉPHONIE", ["Allô Mobile", "Phone Service", "Répar'Phone"], (230, 30, 40), (255, 255, 255), F_SANS),
    "electronics": ("ÉLECTROMÉNAGER · TV", ["Électro Dauphiné", "Le Grand Écran", "Électro Service"], (240, 120, 0), (255, 255, 255), F_SANS),
    "interior_decoration": ("DÉCORATION", ["Déco & Vous", "L'Instant Déco", "Maison Bohème"], (240, 235, 225), (60, 50, 45), F_ITAL),
    "travel_agency": ("VOYAGES", ["Évasion Voyages", "Horizons Lointains", "Bon Voyage"], (0, 120, 190), (255, 255, 255), F_SANS),
    "sports": ("SPORTS", ["Sport Passion", "Le Vestiaire", "Top Sport"], (0, 70, 150), (255, 255, 255), F_SANS),
    "kitchen": ("CUISINES · BAINS", ["Cuisines Création", "L'Art de la Cuisine", "Cuisine & Bain"], (40, 40, 45), (255, 255, 255), F_SANS),
    "greengrocer": ("PRIMEUR", ["Le Panier Frais", "Fruits & Légumes du Coin", "Au Jardin Gourmand"], (60, 140, 50), (255, 255, 255), F_SERIF),
    "fireplace": ("POÊLES · CHEMINÉES", ["Au Coin du Feu", "Flamme Dauphinoise", "Chaleur Bois"], (40, 40, 45), (240, 130, 30), F_SANS),
    "tattoo": ("TATOUAGE", ["Encre Noire", "L'Aiguille d'Or", "Ink Isère"], (20, 20, 22), (255, 255, 255), F_ITAL),
    "paint": ("PEINTURES", ["Couleurs & Murs", "La Palette", "Peintures du Nord-Isère"], (230, 230, 230), (30, 90, 170), F_SANS),
    "books": ("LIBRAIRIE", ["La Page Tournée", "Au Fil des Mots", "Le Marque-Page"], (110, 30, 35), (255, 240, 220), F_SERIF),
    "cosmetics": ("PARFUMERIE · BEAUTÉ", ["Belle & Rebelle", "L'Essentiel Beauté", "Fleur de Peau"], (20, 20, 25), (255, 255, 255), F_ITAL),
    "perfumery": ("PARFUMERIE", ["Sillage", "L'Heure Bleue", "Essence"], (20, 20, 25), (220, 190, 110), F_ITAL),
    "confectionery": ("CONFISERIE", ["Les Bonbons de Mamie", "Douceurs Sucrées", "Le Petit Gourmand"], (230, 110, 160), (255, 255, 255), F_ITAL),
    "chocolate": ("CHOCOLATIER", ["Cacao & Cie", "Le Chocolat d'Antan", "Ganache"], (80, 45, 30), (230, 200, 150), F_SERIF),
    "cheese": ("FROMAGERIE", ["La Cloche à Fromage", "Le Saint-Marcellin", "Crème & Croûte"], (240, 225, 180), (90, 60, 30), F_SERIF),
    "alcohol": ("CAVE · VINS", ["La Cave du Coin", "Tire-Bouchon", "Vins & Terroirs"], (90, 20, 35), (240, 220, 180), F_SERIF),
    "wine": ("CAVE · VINS", ["La Cave du Coin", "Tire-Bouchon", "Vins & Terroirs"], (90, 20, 35), (240, 220, 180), F_SERIF),
    "deli": ("ÉPICERIE FINE", ["Le Garde-Manger", "Saveurs d'Ici", "Gourmandises"], (40, 60, 45), (230, 200, 140), F_SERIF),
    "dry_cleaning": ("PRESSING", ["Pressing Net", "Blanc d'Isère", "Pressing du Centre"], (0, 130, 190), (255, 255, 255), F_SANS),
    "computer": ("INFORMATIQUE", ["Clic & Répare", "Informatique Services", "Octet"], (30, 40, 60), (120, 200, 255), F_SANS),
    "toys": ("JOUETS", ["Le Coffre à Jouets", "Pirouette", "Jeux & Merveilles"], (230, 50, 40), (255, 220, 0), F_SANS),
    "frozen_food": ("SURGELÉS", ["Le Grand Froid", "Banquise", "Surgelés Gourmands"], (0, 90, 170), (255, 255, 255), F_SANS),
    "funeral_directors": ("POMPES FUNÈBRES", ["Pompes Funèbres du Dauphiné", "Pompes Funèbres de la Bourbre"], (40, 40, 50), (220, 220, 220), F_SERIF),
    "motorcycle": ("MOTOS", ["Moto Passion", "Deux Roues 38", "Bécane Service"], (20, 20, 22), (240, 130, 0), F_SANS),
    "tyres": ("PNEUS", ["Pneu Service", "Gomme & Jante", "Roule Malin"], (20, 20, 22), (255, 210, 0), F_SANS),
    "hardware": ("QUINCAILLERIE", ["La Quincaillerie", "Clou & Vis", "Outils Pro"], (200, 30, 30), (255, 255, 255), F_SANS),
    "bicycle": ("CYCLES", ["Cycles Dauphiné", "Le Grand Braquet", "Roue Libre"], (30, 120, 60), (255, 255, 255), F_SANS),
    "massage": ("MASSAGES", ["Bien-Être & Sérénité", "Zen Attitude", "Les Mains d'Or"], (230, 220, 200), (90, 60, 40), F_ITAL),
    "e-cigarette": ("CIGARETTE ÉLECTRONIQUE", ["Le Nuage", "Vapo Store", "Fumée Douce"], (20, 20, 22), (120, 220, 200), F_SANS),
    "second_hand": ("DÉPÔT-VENTE", ["Seconde Main", "Le Grenier", "Troc & Puces"], (90, 60, 120), (255, 255, 255), F_SANS),
    "hearing_aids": ("AUDITION", ["Audition Conseil", "À l'Écoute", "Bien Entendre"], (255, 255, 255), (0, 90, 160), F_SANS),
    "medical_supply": ("MATÉRIEL MÉDICAL", ["Médical Services", "Santé Confort"], (255, 255, 255), (0, 130, 90), F_SANS),
    "fabric": ("TISSUS · MERCERIE", ["Fil & Aiguille", "Le Comptoir des Tissus"], (150, 40, 90), (255, 255, 255), F_ITAL),
    "photo": ("PHOTO", ["Photo Flash", "Déclic", "L'Objectif"], (20, 20, 22), (230, 30, 40), F_SANS),
    "pastry": ("PÂTISSERIE", ["Le Chou Gourmand", "Mille Douceurs", "L'Éclair d'Or"], (250, 235, 240), (150, 50, 90), F_ITAL),
    "ice_cream": ("GLACIER", ["Givre & Sorbet", "La Boule Glacée"], (180, 220, 240), (40, 80, 150), F_ITAL),
    "pet_grooming": ("TOILETTAGE", ["Poils & Moustaches", "Toutou Beau"], (240, 160, 190), (255, 255, 255), F_ITAL),
    "nutrition_supplements": ("NUTRITION", ["Forme & Vitalité", "Nutri Sport"], (40, 120, 60), (255, 255, 255), F_SANS),
    "gold_buyer": ("ACHAT OR", ["Or & Argent", "Le Comptoir de l'Or"], (20, 20, 22), (220, 180, 80), F_SERIF),
    "watches": ("HORLOGERIE", ["Le Temps Passe", "L'Heure Juste"], (20, 20, 22), (220, 180, 80), F_SERIF),
    "bag": ("MAROQUINERIE", ["Sacs & Valises", "Cuir d'Isère"], (80, 50, 30), (240, 220, 180), F_SERIF),
    "leather": ("MAROQUINERIE", ["Sacs & Valises", "Cuir d'Isère"], (80, 50, 30), (240, 220, 180), F_SERIF),
    "fashion_accessories": ("ACCESSOIRES", ["Bijoux & Babioles", "Les Petits Riens"], (240, 220, 230), (120, 40, 80), F_ITAL),
    "baby_goods": ("PUÉRICULTURE", ["Bébé Câlin", "Petits Petons"], (255, 255, 255), (230, 80, 140), F_SANS),
    "bed": ("LITERIE", ["Le Roi du Sommeil", "Doux Rêves"], (20, 40, 90), (255, 255, 255), F_SANS),
    "bathroom_furnishing": ("SALLES DE BAINS", ["Bain & Bien-Être", "L'Eau Vive"], (0, 90, 170), (255, 255, 255), F_SANS),
    "tiles": ("CARRELAGE", ["Carrelages du Rhône", "Le Monde du Carreau"], (220, 220, 220), (180, 40, 40), F_SANS),
    "trade": ("NÉGOCE · MATÉRIAUX", ["Matériaux Dauphiné", "Négoce du Bâtiment"], (230, 230, 230), (200, 30, 30), F_SANS),
    "wholesale": ("GROSSISTE", ["Le Grossiste", "Cash Pro"], (0, 70, 140), (255, 255, 255), F_SANS),
    "car_parts": ("PIÈCES AUTO", ["Pièces Auto Service", "Auto Pièces 38"], (220, 30, 30), (255, 255, 255), F_SANS),
    "art": ("GALERIE D'ART", ["Galerie des Arts", "L'Atelier"], (240, 240, 240), (30, 30, 30), F_SERIF),
    "copyshop": ("REPROGRAPHIE", ["Copie Express", "Imprim'Services"], (0, 110, 180), (255, 255, 255), F_SANS),
    "stationery": ("PAPETERIE", ["Papier Crayon", "La Plume"], (40, 90, 160), (255, 255, 255), F_SANS),
    "gas": ("GAZ · STATION", ["Station du Carrefour"], (230, 30, 40), (255, 255, 255), F_SANS),
    "beverages": ("BOISSONS", ["Le Comptoir des Boissons"], (0, 90, 60), (255, 255, 255), F_SANS),
    "seafood": ("POISSONNERIE", ["La Marée", "Au Bon Poisson"], (0, 90, 150), (255, 255, 255), F_SERIF),
    "ticket": ("BILLETTERIE", ["Point Billets"], (230, 30, 40), (255, 255, 255), F_SANS),
}.items():
    GENERIC.setdefault(_k, _v + (None,))
# plus de noms pour les métiers fréquents (moins de doublons d'une enseigne à l'autre)
for _k, _more in {
    "clothes": ["Le Fil Rouge", "Tendance", "Ma Garde-Robe", "L'Étiquette", "Coton & Lin", "Maille à Part", "Jean'Isère",
                "Les Petites Robes", "Chic & Choc", "Mode d'Ici"],
    "restaurant": ["Le Bistrot du Marché", "La Table d'Hôtes", "Le Petit Zinc", "L'Assiette Dauphinoise", "Le Tilleul",
                   "La Marmite", "Le Coin Gourmand", "Chez Lulu", "La Pergola", "Le Comptoir des Saveurs"],
    "hairdresser": ["Coupe Tifs", "Ciseaux d'Or", "Mèche Rebelle", "Le Salon", "Barbe & Brushing", "Studio Coiffure",
                    "Boucles & Brillance"],
    "fast_food": ["Burger du Coin", "Snack Express", "Kebab Royal", "Pizza Express", "Le Croc'", "Tacos Plus"],
    "bakery": ["Le Pain d'Antan", "La Mie Dorée", "Aux Pains d'Isère", "Le Fournil de la Bourbre", "La Croûte Dorée"],
    "beauty": ["Bulle de Beauté", "Ongles & Cie", "L'Écrin", "Soin Divin"],
    "bank": ["Banque de la Bourbre", "Crédit du Dauphiné", "Caisse Régionale"],
    "car_repair": ["Garage de la Gare", "Garage des Collines", "Auto Réparation 38", "Mécanique Service"],
    "car": ["Auto Bourbre", "Dauphiné Automobiles", "Les Autos du Rond-Point", "Garage Central"],
    "bar": ["Le Balto", "Le Rallye", "Le Bar des Amis", "Café de la Gare"],
    "optician": ["Les Lunettes d'Isère", "Vue d'Ici", "Optique du Centre"],
    "convenience": ["L'Épicerie Fine du Coin", "Proxi Panier", "Le Petit Marché"],
    "butcher": ["Boucherie du Marché", "La Bonne Viande", "Boucherie Traditionnelle"],
}.items():
    if _k in GENERIC:
        _g = GENERIC[_k]
        GENERIC[_k] = (_g[0], _g[1] + [n for n in _more if n not in _g[1]]) + _g[2:]

# Fiches des devantures d'après les photos Street View (fetch_sv_shops.py, cache privé), relevées à la main dans
# sources/shops_sv.txt : « id type cadre bandeau enseigne_fond/enseigne_texte store rideau terrasse »
#   type : V vitrine en rez-de-chaussée, G grande surface (bardage, grandes lettres), A atelier (portes sectionnelles),
#          S station-service, X photo inexploitable (le métier décide) ; couleurs nommées (PALETTE), « - » = aucun ;
#   store : couleur (ou couleur+couleur, toile rayée) ; rideau : r = rideau métallique ; terrasse : t.
PALETTE = {
    "blanc": (240, 240, 236), "creme": (232, 222, 196), "beige": (205, 185, 150), "gris_clair": (190, 192, 192),
    "gris": (135, 138, 140), "anthracite": (60, 63, 66), "noir": (25, 25, 27), "bois": (125, 85, 50),
    "marron": (90, 60, 40), "bordeaux": (110, 25, 35), "rouge": (200, 30, 35), "orange": (235, 120, 25),
    "jaune": (245, 200, 30), "vert_clair": (140, 190, 70), "vert": (40, 130, 60), "vert_fonce": (25, 75, 45),
    "turquoise": (30, 160, 170), "bleu_clair": (110, 170, 220), "bleu": (30, 90, 180), "bleu_marine": (25, 40, 85),
    "violet": (110, 50, 130), "rose": (225, 110, 160), "or": (200, 160, 70), "alu": (175, 178, 180),
    "terracotta": (185, 85, 45),
}
ATELIERS = ("car_repair", "car", "tyres", "car_wash", "motorcycle", "car_parts", "trade", "agrarian", "craft")
GRANDES = ("supermarket", "doityourself", "garden_centre", "furniture", "electronics", "sports", "car", "hardware",
           "department_store", "wholesale", "pet", "toys", "kitchen", "bed", "interior_decoration", "variety_store",
           "clothes", "shoes", "appliance", "paint", "farm")
CADRES = ["anthracite", "noir", "alu", "blanc", "anthracite", "bois", "alu"]
BARDAGES = ["gris_clair", "blanc", "anthracite", "gris_clair", "beige", "gris"]


def load_fiches(path="sources/shops_sv.txt"):
    out = {}
    if not os.path.exists(path):
        return out
    for ln in open(path, encoding="utf-8"):
        ln = ln.split("#")[0].split()
        if len(ln) < 2:
            continue
        f = dict(type=ln[1])
        c = lambda v: PALETTE.get(v) if v and v != "-" else None
        if len(ln) >= 8:
            f["cadre"] = c(ln[2]); f["bandeau"] = c(ln[3])
            e = ln[4].split("/")
            if len(e) == 2 and c(e[0]) and c(e[1]):
                f["ens"] = (c(e[0]), c(e[1]))
            f["store"] = c(ln[5].split("+")[0]) if ln[5] != "-" else None
            f["rideau"] = ln[6] == "r"
            f["terrasse"] = ln[7] == "t"
        out[ln[0]] = f
    return out


def c01(c):
    return (c[0] / 255.0, c[1] / 255.0, c[2] / 255.0, 1.0)


def pick_w(key, salt, items):
    r = rnd(key, salt) * sum(w for _, w in items)
    for v, w in items:
        r -= w
        if r <= 0:
            return v
    return items[-1][0]


def rnd(key, salt=""):
    return int(hashlib.md5((str(key) + salt).encode()).hexdigest()[:8], 16) / 2 ** 32


# ================================================================================================ atlas
class Atlas:
    """Trois pages de 4096² (enseignes.png, enseignes2.png, enseignes3.png) : bandeaux de 512 × 96 (8 colonnes ; 32
    lignes en page 1, au-dessus des totems, 42 en pages 2 et 3), totems de 256² (16 × 4 en bas de la page 1). La page d'un bandeau est codée
    dans la partie entière de son décalage x (+ 10 par page), lue par shop.gdshader."""
    W = 4096
    CW, CH = 512, 96
    COLS = 8
    ROWS = (32, 42, 42)
    SQ = 256

    def __init__(self):
        self.imgs = [Image.new("RGB", (self.W, self.W), (40, 40, 45)) for _ in self.ROWS]
        self.img = self.imgs[0]
        self.wide = {}
        self.sq = {}

    def _font(self, path, text, box_w, box_h, start):
        s = start
        while s > 10:
            f = ImageFont.truetype(path, s)
            b = f.getbbox(text)
            if b[2] - b[0] <= box_w and b[3] - b[1] <= box_h:
                return f
            s -= 2
        return ImageFont.truetype(path, 10)

    def _deco(self, d, style, x, y, h, fg, bg):
        """Petit logo parodique à gauche (formes simples, pas de logo réel)."""
        if style == "losange":
            d.polygon([(x + h * 0.5, y), (x + h, y + h * 0.5), (x + h * 0.5, y + h), (x, y + h * 0.5)], outline=fg, width=8)
        elif style == "rond":
            d.ellipse([x, y, x + h, y + h], fill=fg)
        elif style == "carrefou":
            d.polygon([(x, y + h * 0.5), (x + h * 0.45, y), (x + h * 0.45, y + h)], fill=(220, 30, 40))
            d.polygon([(x + h, y + h * 0.5), (x + h * 0.55, y), (x + h * 0.55, y + h)], fill=fg)
        elif style == "orange":
            d.ellipse([x, y, x + h, y + h], fill=(240, 120, 0))
        elif style == "soleil":
            for k in range(8):
                a = k * math.pi / 4
                d.line([(x + h / 2, y + h / 2), (x + h / 2 + math.cos(a) * h / 2, y + h / 2 + math.sin(a) * h / 2)], fill=(255, 200, 0), width=6)
            d.ellipse([x + h * 0.25, y + h * 0.25, x + h * 0.75, y + h * 0.75], fill=(255, 210, 0))
        elif style == "m":
            d.text((x, y - h * 0.15), "M", font=ImageFont.truetype(F_SANS, int(h * 1.1)), fill=(255, 199, 44))
        elif style == "banque":
            d.rectangle([x, y + h * 0.2, x + h, y + h * 0.8], outline=fg, width=6)
            d.line([(x, y + h * 0.5), (x + h, y + h * 0.5)], fill=fg, width=4)
        else:
            return 0
        return h + 18

    def wide_cell(self, key, title, sub, bg, fg, font, style=None):
        if key in self.wide:
            return self.wide[key]
        i = len(self.wide)
        page, k = 0, i
        while page < len(self.ROWS) and k >= self.COLS * self.ROWS[page]:
            k -= self.COLS * self.ROWS[page]; page += 1
        if page >= len(self.ROWS):
            return self.wide[next(iter(self.wide))]
        cx, cy = (k % self.COLS) * self.CW, (k // self.COLS) * self.CH
        H = self.CH
        cell = Image.new("RGB", (self.CW, H), bg)
        d = ImageDraw.Draw(cell)
        d.rectangle([2, 2, self.CW - 3, H - 3], outline=tuple(int(c * 0.75) for c in fg), width=2)
        x0 = 18 + self._deco(d, style, 18, int(H * 0.2), int(H * 0.6), fg, bg) if style else 18
        f = self._font(font, title, self.CW - x0 - 18, int(H * 0.47) if sub else int(H * 0.72), int(H * 0.66))
        b = f.getbbox(title)
        tw = b[2] - b[0]
        ty = int(H * 0.09) - b[1] if sub else (H - (b[3] - b[1])) // 2 - b[1]
        d.text((x0 + (self.CW - x0 - 18 - tw) // 2 - b[0], ty), title, font=f, fill=fg)
        if sub:
            fs = self._font(F_COND, sub, self.CW - x0 - 30, int(H * 0.22), int(H * 0.22))
            bs = fs.getbbox(sub)
            d.text((x0 + (self.CW - x0 - 18 - (bs[2] - bs[0])) // 2, int(H * 0.7)), sub, font=fs, fill=fg)
        self.imgs[page].paste(cell, (cx, cy))
        r = (cx / self.W + 10.0 * page, cy / self.W, self.CW / self.W, self.CH / self.W)
        self.wide[key] = r
        return r

    def drawn_cell(self, key, draw):
        """Case carrée dessinée par draw(image 256 × 256) : panneau des prix, affiches de cinéma."""
        if key in self.sq:
            return self.sq[key]
        i = len(self.sq)
        if i >= 64:
            return self.sq[next(iter(self.sq))]
        cx, cy = (i % 16) * self.SQ, self.ROWS[0] * self.CH + (i // 16) * self.SQ
        cell = Image.new("RGB", (self.SQ, self.SQ), (0, 0, 0))
        draw(cell)
        self.img.paste(cell, (cx, cy))
        r = (cx / self.W, cy / self.W, self.SQ / self.W, self.SQ / self.W)
        self.sq[key] = r
        return r

    def square_cell(self, key, title, bg, fg, font, style=None):
        if key in self.sq:
            return self.sq[key]
        i = len(self.sq)
        if i >= 64:
            return self.sq[next(iter(self.sq))]
        cx, cy = (i % 16) * self.SQ, self.ROWS[0] * self.CH + (i // 16) * self.SQ
        cell = Image.new("RGB", (self.SQ, self.SQ), bg)
        d = ImageDraw.Draw(cell)
        d.rectangle([4, 4, self.SQ - 5, self.SQ - 5], outline=fg, width=4)
        if style and self._deco(d, style, 78, 24, 100, fg, bg):
            area = (24, 140, 208, 90)
        else:
            area = (24, 40, 208, 170)
        words = title.split(" ")
        lines = [title] if len(words) < 2 else [" ".join(words[:len(words) // 2]), " ".join(words[len(words) // 2:])]
        hh = area[3] // len(lines)
        for k, ln in enumerate(lines):
            f = self._font(font, ln, area[2], hh - 6, 72)
            b = f.getbbox(ln)
            d.text((area[0] + (area[2] - (b[2] - b[0])) // 2 - b[0], area[1] + k * hh + (hh - (b[3] - b[1])) // 2 - b[1]), ln, font=f, fill=fg)
        self.img.paste(cell, (cx, cy))
        r = (cx / self.W, cy / self.W, self.SQ / self.W, self.SQ / self.W)
        self.sq[key] = r
        return r


# ================================================================================================ placement
def xf(model, origin, right, scale=(1, 1, 1), custom=(0, 0, 0, 0)):
    """Instance le long d'une façade de direction right (sens direct du contour) : repère direct, le +z du modèle
    (côté rue) va vers l'extérieur du bâtiment, donc le +x du modèle va dans le sens opposé à right."""
    r = -np.array([right[0], 0.0, right[1]]); r /= np.linalg.norm(r)
    up = np.array([0.0, 1.0, 0.0])
    out = np.cross(r, up)           # (rz, 0, -rx)
    B = np.c_[r * scale[0], up * scale[1], out * scale[2]]
    return (MID[model],) + tuple(B.T.ravel()) + tuple(origin) + tuple(custom)


def main():
    os.makedirs(OUT_A, exist_ok=True)
    shutil.rmtree(OUT_W, ignore_errors=True); os.makedirs(OUT_W)
    plan = json.load(open("data/routes_plan.json"))
    zone = Polygon(plan["zone"])
    dem = Carved()
    ways = pickle.load(open("data/roads.pkl", "rb"))["ways"]
    ways = [w for w in ways if len(w["P"]) > 1]
    CARR = Local([LineString(w["P"]).buffer(w["w"] / 2 + 0.2) for w in ways])                       # chaussée
    WALK = Local([LineString(w["P"]).buffer(w["w"] / 2 + (1.6 if any(w["sidewalk"]) else 0.0) + 0.5) for w in ways])
    MAINL = Local([LineString(w["P"]) for w in ways if w["cls"] not in ("track", "path", "footway", "service")])
    # bâtiments tels qu'en jeu (découpés au bord des chaussées, simplifiés)
    rbuf = [LineString(w["P"]).buffer(w["w"] / 2 + 0.3, cap_style="flat") for w in ways if not w["bridge"]]
    rtr = STRtree(rbuf)
    blds = []
    for p, g in load_buildings():
        hits = [rbuf[k] for k in rtr.query(g) if rbuf[k].intersects(g)]
        if hits and g.intersection(unary_union(hits)).area > 0.3:
            g2 = g.difference(unary_union(hits))
            parts = [q for q in getattr(g2, "geoms", [g2]) if q.geom_type == "Polygon"]
            g2 = max(parts, key=lambda q: q.area) if parts else None
            if g2 is None or g2.area < 0.6 * g.area or g2.area < 12:
                continue
            g = g2
        g = shapely.simplify(g, 0.3)
        if g.area < 6 or not g.is_valid:
            continue
        blds.append((p, shapely.geometry.polygon.orient(g, 1.0)))
    BT = STRtree([g for _, g in blds])
    BLD = Local([g for _, g in blds])
    d = json.load(open("data/osm_shops.json"))
    FICHES = load_fiches()
    print(len(FICHES), "fiches d'après Street View")
    atlas = Atlas()
    inst = []
    used = defaultdict(list)          # bâtiment -> intervalles (arête, t0, t1) occupés
    stats = defaultdict(int)

    from build_buildings import bati_overrides
    BOV = bati_overrides(blds)

    def height_info(p, g):
        H = p.get("hauteur")
        ov = BOV.get(p.get("cleabs"))
        if ov:
            H = ov["H"]
        if not H or H <= 0:
            f = p.get("nombre_d_etages")
            H = f * 2.8 + 0.6 if f else 5.0
        ring = np.asarray(g.exterior.coords)
        gr = dem.h(ring[:, 0], ring[:, 1])
        e = max(float(gr.min()) + H, float(gr.max()) + 2.6)
        if ov:
            e = max(e, float(gr.max()) + 4.3)       # comme build_buildings.py
        return float(gr.min()), e

    def free_box(c, d_, L, W, margin=0.0):
        d_ = np.asarray(d_) / np.linalg.norm(d_); n = np.array([-d_[1], d_[0]])
        poly = Polygon([c + d_ * L / 2 + n * W / 2, c - d_ * L / 2 + n * W / 2, c - d_ * L / 2 - n * W / 2, c + d_ * L / 2 - n * W / 2])
        w_, b_ = WALK.near(poly, margin), BLD.near(poly, 0.3)
        free_box.why = "route" if w_ else ("bâtiment" if b_ else "")
        return not w_ and not b_, poly

    def sign_for(tags, kind, key):
        brand = tags.get("brand") or ""
        if brand in PARODIES:
            nm, bg, fg, font, style = PARODIES[brand]
            return nm, None, bg, fg, font, style, None
        if brand:                                            # marque inconnue de la table : nom générique du métier
            pass
        lab, names, bg, fg, font, acc = GENERIC.get(kind, OTHER)
        nm = names[int(rnd(key, "nom") * len(names))]
        return nm, lab if lab.upper() != nm.upper() else None, bg, fg, font, None, acc

    # bâtiments « commerce » de la BD TOPO sans commerce OSM à moins de 25 m : devanture et enseigne génériques
    # (métier tiré au sort, nom inventé), traitées après les commerces OSM (qui gardent la priorité sur les façades)
    from build_buildings import classify
    osm_pts = []
    for e in d["elements"]:
        if "lon" in e or "center" in e:
            lon, lat = (e["lon"], e["lat"]) if "lon" in e else (e["center"]["lon"], e["center"]["lat"])
            osm_pts.append(Point(*geo.to_local(lon, lat)))
    OSMP = Local([q.buffer(25) for q in osm_pts])
    SMALL = [("bakery", 3), ("hairdresser", 3), ("restaurant", 3), ("pharmacy", 2), ("tobacco", 2), ("clothes", 2),
             ("florist", 1), ("optician", 1), ("bank", 1), ("cafe", 2), ("beauty", 1), ("car_repair", 1), ("butcher", 1)]
    BIG = [("doityourself", 3), ("garden_centre", 2), ("clothes", 2), ("car", 2), ("shoes", 1), ("pet", 1)]
    synth = []
    for bi, (p, g) in enumerate(blds):
        if classify(p, g) != "commerce" or not zone.contains(g.centroid) or OSMP.near(g.centroid, 0.0):
            continue
        k_ = pick_w(p.get("cleabs", str(bi)), "metier", BIG if g.area > 400 else SMALL)
        synth.append({"id": "bd%d" % bi, "tags": {"shop": k_}, "xz": (g.centroid.x, g.centroid.y)})
    stats["commerces BD TOPO sans OSM"] = len(synth)
    for e in list(d["elements"]) + synth:
        t = e.get("tags", {})
        kind = "fuel" if t.get("amenity") == "fuel" else (t.get("shop") or t.get("amenity") or t.get("craft"))
        if kind in ("vacant", None):
            continue
        if "xz" in e:
            x, z = e["xz"]
        else:
            lon, lat = (e["lon"], e["lat"]) if "lon" in e else (e["center"]["lon"], e["center"]["lat"])
            x, z = geo.to_local(lon, lat)
        P = Point(float(x), float(z))
        if not zone.contains(P):
            continue
        key = e["id"]
        title, sub, bg, fg, font, style, acc = sign_for(t, kind, key)
        fi = FICHES.get(key if isinstance(key, str) else "%s%d" % (e["type"][0], key))
        typ = fi["type"] if fi and fi["type"] != "X" else None
        if fi and typ:
            stats["d'après photo"] += 1
            if fi.get("ens"):
                bg, fg = fi["ens"]
        else:
            stats["d'après le métier"] += 1
        if typ is None and kind in ATELIERS:
            typ = "A"
        if kind == "fuel":
            stats["station"] += station(P, t, title, bg, fg, font, style, atlas, inst, dem, MAINL, free_box)
            continue
        # bâtiment
        cand = [i for i in BT.query(P.buffer(25))]
        if not cand:
            stats["sans bâtiment"] += 1
            continue
        bi = min(cand, key=lambda i: blds[i][1].distance(P))
        if blds[bi][1].distance(P) > 25:
            stats["sans bâtiment"] += 1
            continue
        p, g = blds[bi]
        big = typ == "G" or (typ is None and ((kind == "supermarket" and g.area > 700) or (kind in GRANDES and g.area > 600)))
        ring = np.asarray(g.exterior.coords)
        # façade : arête vers la route la plus proche (normale extérieure tournée vers elle)
        best = None
        for k in range(len(ring) - 1):
            a, b = ring[k], ring[k + 1]
            L = float(np.linalg.norm(b - a))
            if L < (6.0 if big else 2.4):
                continue
            tdir = (b - a) / L
            nrm = np.array([tdir[1], -tdir[0]])              # extérieur (polygone orienté dans le sens direct)
            m = (a + b) / 2
            dr = MAINL.dist(Point(m + nrm * 1.0), 60.0)
            dr2 = MAINL.dist(Point(m - nrm * 1.0), 60.0)
            if dr > dr2 + 0.5:
                continue                                     # la rue est de l'autre côté
            sc = dr - 0.02 * L - 3.0 * (P.distance(LineString([a, b])) < 4.0)
            if best is None or sc < best[0]:
                best = (sc, k, a, b, L, tdir, nrm)
        if best is None:
            stats["sans façade"] += 1
            continue
        _, k, a, b, L, tdir, nrm = best
        gmin, eave = height_info(p, g)
        if big:
            bard = (fi or {}).get("bandeau") or PALETTE[BARDAGES[int(rnd(key, "bardage") * len(BARDAGES))]]
            cad = (fi or {}).get("cadre") or PALETTE["alu"]
            stats["grande surface"] += supermarket(k, a, b, L, tdir, nrm, gmin, eave, title, sub, bg, fg, font, style, atlas,
                                                   inst, dem, free_box, used[bi], bard, cad, kind == "supermarket")
            continue
        # devanture : largeur selon le métier, centrée sur le point OSM projeté, sans chevaucher les voisines
        w = float(np.clip(L - 0.6, 2.0, 4.0 + 3.0 * rnd(key, "w")))
        w = float(math.floor(w))
        if w < 2:
            continue
        tp = float(np.clip(np.dot(np.array([P.x, P.y]) - a, tdir), w / 2 + 0.3, L - w / 2 - 0.3))
        ok = False
        for shift in (0, 1, -1, 2, -2, 3, -3, 4, -4, 5, -5, 6, -6):
            t0 = tp + shift * 1.0 - w / 2
            if t0 < 0.3 or t0 + w > L - 0.3:
                continue
            if any(kk == k and not (t0 + w <= u0 - 0.4 or t0 >= u1 + 0.4) for kk, u0, u1 in used[bi]):
                continue
            ok = True
            break
        if not ok:
            stats["façade pleine"] += 1
            continue
        used[bi].append((k, t0, t0 + w))
        c0 = a + tdir * t0
        yb = float(dem.h(np.array([c0[0] + tdir[0] * w / 2]), np.array([c0[1] + tdir[1] * w / 2]))[0]) - 0.05
        if eave - yb < 4.1:
            stats["mur trop bas"] += 1
            if fi and typ:
                stats["mur trop bas (photo)"] += 1
            used[bi].pop()
            continue
        # menuiseries, bandeau peint, rideau, store, terrasse : d'après la photo, sinon selon le métier
        cad = (fi or {}).get("cadre") or PALETTE[CADRES[int(rnd(key, "cadre") * len(CADRES))]]
        if fi and typ:
            band = fi.get("bandeau")
            rideau = fi.get("rideau", False)
            if acc and acc[0] == "banne":
                acc = ("banne", c01(fi["store"])[:3]) if fi.get("store") else None
            elif acc and acc[0] == "terrasse" and not fi.get("terrasse"):
                acc = None
            if fi.get("store") and not acc:
                acc = ("banne", c01(fi["store"])[:3])
            elif fi.get("terrasse") and not acc:
                acc = ("terrasse", (0.55, 0.1, 0.1))
        else:
            band = bg if (kind in ("bakery", "butcher", "bar", "restaurant", "cafe", "pub", "florist", "jewelry")
                          and rnd(key, "bandeau") < 0.6) else None
            rideau = rnd(key, "rideau") < (0.15 if kind in ("bakery", "restaurant", "cafe", "bar") else 0.45)
        if typ == "A":
            # atelier : portes sectionnelles de 3 m (couleur du cadre), porte de service, enseigne au-dessus
            nd = max(1, int((w - 1) // 3.4))
            xx = t0 + 0.2
            for j in range(nd):
                m = a + tdir * (xx + 1.5) + nrm * 0.12
                inst.append(xf("porte_sectionnelle", (m[0], yb, m[1]), tdir, (3.0, 1, 1), c01(cad)))
                xx += 3.4
            if w - (xx - t0) >= 1.0:
                m = a + tdir * (xx + 0.5) + nrm * 0.16
                inst.append(xf("porte", (m[0], yb, m[1]), tdir, custom=c01(PALETTE["anthracite"])))
            cen = a + tdir * (t0 + w / 2) + nrm * 0.16
            rect = atlas.wide_cell((title, sub, bg, fg), title, sub, bg, fg, font, style)
            sw = min(w, 6.0)
            inst.append(xf("enseigne", (cen[0], yb + 3.35, cen[1]), tdir, (sw, 0.85, 1), rect))
            stats["atelier"] += 1
            continue
        door = int(w // 2)
        for i in range(int(w)):
            m = a + tdir * (t0 + i + 0.5) + nrm * 0.16
            inst.append(xf("porte" if i == door else "vitrine", (m[0], yb, m[1]), tdir, custom=c01(cad)))
            if rideau:
                inst.append(xf("coffre_rideau", (m[0], yb, m[1]), tdir))
        if band:
            mb = a + tdir * (t0 + w / 2) + nrm * 0.1
            inst.append(xf("bandeau", (mb[0], yb + 2.95, mb[1]), tdir, (w + 0.6, 1.2, 1), c01(band)))
            for tt in (t0 - 0.15, t0 + w + 0.15):
                mp = a + tdir * tt + nrm * 0.1
                inst.append(xf("pilastre", (mp[0], yb - 0.02, mp[1]), tdir, custom=c01(band)))
            stats["bandeau peint"] += 1
        cen = a + tdir * (t0 + w / 2) + nrm * 0.16
        rect = atlas.wide_cell((title, sub, bg, fg), title, sub, bg, fg, font, style)
        sw = min(w, 5.2)
        inst.append(xf("enseigne", (cen[0], yb + 3.05, cen[1]), tdir, (sw, 0.85, 1), rect))
        inst.append(xf("lampes", (cen[0], yb + 3.9, cen[1]), tdir, (sw / 1.6, 1, 1)))
        # accessoires selon le métier, sans empiéter sur la chaussée
        if acc:
            what, col = acc
            if what == "banne":
                ok_b = not CARR.near(Polygon([a + tdir * t0, a + tdir * (t0 + w), a + tdir * (t0 + w) + nrm * 1.25, a + tdir * t0 + nrm * 1.25]), 0.0)
                if ok_b:
                    for i in range(int(w)):
                        m = a + tdir * (t0 + i + 0.5) + nrm * 0.18
                        inst.append(xf("banne", (m[0], yb + 2.98, m[1]), tdir, custom=(col[0], col[1], col[2], 1.0)))
                    stats["store"] += 1
            elif what in ("croix", "carotte"):
                m = a + tdir * (t0 + w + 0.35)
                if not CARR.near(Point(m + nrm * 0.7), 0.3):
                    inst.append(xf(what, (m[0], yb + (3.4 if what == "croix" else 3.0), m[1]), tdir))
                    stats[what] += 1
            elif what == "terrasse":
                for j, off in enumerate((-1.6, 1.6) if w >= 4 else (0.0,)):
                    m = a + tdir * (t0 + w / 2 + off) + nrm * 2.2
                    okt, _ = free_box(m, tdir, 2.4, 2.4)
                    if okt:
                        ym = float(dem.h(np.array([m[0]]), np.array([m[1]]))[0])
                        inst.append(xf("terrasse", (m[0], ym, m[1]), tdir, custom=(col[0], col[1], col[2], 1.0)))
                        stats["terrasse"] += 1
        stats["devanture"] += 1
    # cinémas (fetch_cinemas.py)
    if os.path.exists("data/osm_cinemas.json"):
        for e in json.load(open("data/osm_cinemas.json"))["elements"]:
            stats["cinéma"] += cinema(e, blds, BT, MAINL, atlas, inst, dem, free_box, used, height_info)
    # écriture
    atlas.imgs[0].save(OUT_A + "/enseignes.png")
    atlas.imgs[1].save(OUT_A + "/enseignes2.png")
    atlas.imgs[2].save(OUT_A + "/enseignes3.png")
    T = defaultdict(list)
    for r in inst:
        T[(int(math.floor(r[10] / TILE)), int(math.floor(r[12] / TILE)))].append(r)
    for (tx, tz), S in T.items():
        open("%s/s_%d_%d.bin" % (OUT_W, tx, tz), "wb").write(np.int32(len(S)).tobytes() + np.array(S, "<f4").tobytes())
    print(dict(stats), len(inst), "instances,", len(T), "tuiles,", len(atlas.wide), "enseignes,", len(atlas.sq), "totems")


def supermarket(k, a, b, L, tdir, nrm, gmin, eave, title, sub, bg, fg, font, style, atlas, inst, dem, free_box, used,
                bard=(190, 192, 192), cad=(175, 178, 180), market=True):
    """Grande surface : façade en bardage nervuré (couleur relevée sur la photo, sinon neutre), grande enseigne en haut
    de façade, vitrage et portes d'entrée ; supermarché : auvent d'entrée, totem et abri à chariots."""
    w = min(L - 2.0, 24.0)
    t0 = (L - w) / 2
    used.append((k, t0, t0 + w))
    cen = a + tdir * (L / 2) + nrm * 0.04
    yb = float(dem.h(np.array([cen[0]]), np.array([cen[1]]))[0]) - 0.05
    for i in range(int(L)):
        m = a + tdir * (i + 0.5) + nrm * 0.03
        ym = float(dem.h(np.array([m[0]]), np.array([m[1]]))[0]) - 0.1
        inst.append(xf("bardage", (m[0], ym, m[1]), tdir, (1.0, eave - ym - 0.15, 1), c01(bard)))
    rect = atlas.wide_cell((title, None, bg, fg), title, None, bg, fg, font, style)
    sh = float(np.clip((eave - yb) * 0.32, 1.4, 2.6))
    sw = min(sh * 5.0, w)
    ys = max(yb + 3.6, eave - sh - 0.5)
    inst.append(xf("enseigne", (cen[0], ys, cen[1]), tdir, (sw, sh, 1.6), rect))
    nv = int(min(w, 12 if market else 8))
    for i in range(nv):
        m = a + tdir * (L / 2 - nv / 2 + i + 0.5) + nrm * 0.09
        inst.append(xf("porte" if nv // 2 - 1 <= i <= nv // 2 else "vitrine", (m[0], yb, m[1]), tdir, custom=c01(cad)))
    if not market:
        return 1
    inst.append(xf("auvent", (cen[0], yb, cen[1]), tdir, custom=(bg[0] / 255, bg[1] / 255, bg[2] / 255, 1.0)))
    # totem et chariots devant, hors de l'emprise des routes et des bâtiments
    sq = atlas.square_cell((title, bg, fg), title, bg, fg, font, style)
    for dd in (14.0, 18.0, 10.0, 22.0):
        c = a + tdir * (L * 0.15) + nrm * dd
        ok, _ = free_box(c, tdir, 2.4, 1.0, 1.0)
        if ok:
            y = float(dem.h(np.array([c[0]]), np.array([c[1]]))[0])
            inst.append(xf("totem", (c[0], y - 0.05, c[1]), tdir, custom=sq))
            break
    for dd in (7.0, 9.0, 11.0):
        c = a + tdir * (L * 0.8) + nrm * dd
        ok, _ = free_box(c, tdir, 4.4, 2.4)
        if ok:
            y = float(dem.h(np.array([c[0]]), np.array([c[1]]))[0])
            inst.append(xf("abri_caddies", (c[0], y, c[1]), tdir, custom=(bg[0] / 255, bg[1] / 255, bg[2] / 255, 1.0)))
            break
    return 1


def draw_prices(seed):
    """Panneau des prix d'une station : carburants en chiffres orange lumineux sur fond noir (prix vraisemblables)."""
    def f(cell):
        d = ImageDraw.Draw(cell)
        rng = np.random.default_rng(seed)
        d.rectangle([3, 3, 252, 252], outline=(90, 90, 95), width=4)
        base = 1.70 + rng.uniform(0.0, 0.12)
        rows = [("SP95-E10", base + 0.06), ("SP98", base + 0.13), ("GAZOLE", base - 0.04), ("E85", 0.82 + rng.uniform(0, 0.08))]
        fl = ImageFont.truetype(F_COND, 26)
        fd = ImageFont.truetype(F_SANS, 40)
        for k, (nm, pr) in enumerate(rows):
            y = 14 + k * 60
            d.rectangle([10, y, 245, y + 54], fill=(14, 14, 16))
            d.text((16, y + 14), nm, font=fl, fill=(235, 235, 235))
            d.text((132, y + 5), ("%.3f" % pr).replace(".", ","), font=fd, fill=(255, 150, 20))
    return f


STATIONS = []


def station(P, t, title, bg, fg, font, style, atlas, inst, dem, MAINL, free_box):
    """Station-service façon grandes enseignes : auvent parallèle à la route (bandeau à la couleur de la marque,
    plafond lumineux) sur deux îlots de deux distributeurs, boutique vitrée derrière, station de lavage et borne de
    gonflage à côté quand la place le permet, totem au bord de la route avec son panneau des prix ; rien sur la
    route ni sur les bâtiments, et les éléments ne se chevauchent pas."""
    if any(P.distance(o) < 70.0 for o in STATIONS):
        return 0                                         # même station saisie deux fois dans OSM
    q = MAINL.near(P, 60.0)
    if not q:
        return 0
    ln = min(q, key=lambda l: l.distance(P))
    s = ln.project(P)
    a = np.asarray(ln.interpolate(max(0, s - 2)).coords[0]); b = np.asarray(ln.interpolate(min(ln.length, s + 2)).coords[0])
    tdir = (b - a) / max(np.linalg.norm(b - a), 1e-6)
    foot = np.asarray(ln.interpolate(s).coords[0])
    away = np.array([P.x, P.y]) - foot
    nrm = np.array([-tdir[1], tdir[0]])
    if np.dot(away, nrm) < 0:
        nrm = -nrm
    col = (bg[0] / 255, bg[1] / 255, bg[2] / 255, 1.0)
    placed = []
    STATIONS.append(P)

    def put(c, d_, L, W, margin=0.3):
        ok, poly = free_box(c, d_, L, W, margin)
        if ok and not any(poly.intersects(o) for o in placed):
            placed.append(poly)
            return True
        return False

    def gy(c):
        return float(dem.h(np.array([c[0]]), np.array([c[1]]))[0])

    why = defaultdict(int)
    # grand auvent si la place le permet, sinon plus petit (petites stations de village, stations de supermarché)
    cands = [(sc, along, dd) for sc in (1.0, 0.8, 0.62) for dd in np.arange(8.0, 36.0, 2.0) for along in (0.0, 6.0, -6.0, 12.0, -12.0)]
    for sc, along, dd in cands:
        c = foot + nrm * dd + tdir * along
        if not put(c, tdir, 16.5 * sc, 9.5 * sc, 0.5):
            why[getattr(free_box, "why", "?")] += 1
            continue
        y = gy(c)
        rect = atlas.wide_cell((title, None, bg, fg), title, None, bg, fg, font, style)
        inst.append(xf("ombriere", (c[0], y, c[1]), tdir, (sc, 1.0, sc), rect + ()))
        # distributeurs : sur les îlots (perpendiculaires à la route), écrans tournés vers les voitures
        for dx in (-2.6, 2.6):
            for dz in ((-1.4, 1.4) if sc > 0.7 else (0.0,)):
                m = c + tdir * dx * sc + nrm * dz * sc
                inst.append(xf("pompe", (m[0], y + 0.24, m[1]), nrm, custom=col))
        # boutique derrière l'auvent, façade vers les pompes
        bc = c + nrm * (4.5 + 6.0)
        if put(bc + nrm * 3.5, tdir, 12.5, 7.5):
            rb = atlas.wide_cell((title, None, bg, fg), title, None, bg, fg, font, style)
            inst.append(xf("boutique_station", (bc[0], gy(bc), bc[1]), tdir, custom=rb + ()))
        # station de lavage d'un côté, borne de gonflage de l'autre
        for side in (1, -1):
            lc = c + tdir * side * 12.0 + nrm * 6.0
            if put(lc, tdir, 5.5, 9.5):
                rl = atlas.wide_cell(("LAVAGE", None, bg, fg), "LAVAGE", None, bg, fg, F_SANS, None)
                inst.append(xf("lavage", (lc[0], gy(lc), lc[1]), tdir, custom=rl + ()))
                break
        for side in (-1, 1):
            gc = c + tdir * side * 9.6
            if put(gc, tdir, 0.9, 0.9, 0.2):
                inst.append(xf("gonfleur", (gc[0], gy(gc), gc[1]), tdir))
                break
        # totem et panneau des prix au bord de la route
        for along in (9.0, -9.0, 12.0, -12.0):
            tc = foot + nrm * (dd - 6.0) + tdir * along
            if put(tc, tdir, 2.4, 1.0, 0.8):
                sq = atlas.square_cell((title, bg, fg), title, bg, fg, font, style)
                yt = gy(tc)
                inst.append(xf("totem", (tc[0], yt - 0.05, tc[1]), tdir, custom=sq))
                rp = atlas.drawn_cell(("prix", int(rnd(title, "prix") * 3)), draw_prices(int(rnd(title, "prix") * 3)))
                inst.append(xf("panneau_prix", (tc[0], yt + 2.15, tc[1]), tdir, custom=rp))
                break
        return 1
    print("station non posée :", title, int(P.x), int(P.y), dict(why))
    return 0


# ---------------------------------------------------------------- cinémas
FILMS = [  # affiches parodiques : titre, fond, motif
    ("LA SOUCOUPE DE ROCHETOIRIN", (20, 24, 60), "soucoupe"),
    ("ESPACE 85", (180, 40, 30), "voiture"),
    ("LES VACHES DE SAINT-CHEF", (60, 120, 50), "vache"),
    ("BOURGOIN EXPRESS", (30, 30, 34), "train"),
    ("LE RETOUR DU TAXI", (230, 180, 30), "taxi"),
    ("NUIT SUR L'A43", (10, 14, 30), "route"),
]


def draw_poster(title, bg, motif):
    """Affiche de film (dessinée en 186 × 256 puis étirée en carré : le caisson est en portrait) : ciel en dégradé,
    motif en aplats, titre en capitales, « AU CINÉMA » en bas."""
    def f(cell):
        W, H = 186, 256
        im = Image.new("RGB", (W, H), bg)
        d = ImageDraw.Draw(im)
        for y in range(H):
            k = y / H
            d.line([(0, y), (W, y)], fill=tuple(int(c * (0.55 + 0.6 * k)) if c * (0.55 + 0.6 * k) < 255 else 255 for c in bg))
        cx, cy = W // 2, 104
        if motif == "soucoupe":
            d.polygon([(cx - 26, cy + 10), (cx + 26, cy + 10), (cx + 60, cy + 120), (cx - 60, cy + 120)], fill=(150, 255, 160))
            d.ellipse([cx - 60, cy - 8, cx + 60, cy + 18], fill=(190, 195, 205))
            d.ellipse([cx - 24, cy - 30, cx + 24, cy + 4], fill=(120, 200, 255))
        elif motif == "voiture":
            d.polygon([(30, 150), (60, 110), (150, 108), (160, 150)], fill=(120, 20, 30))
            d.rectangle([24, 148, 166, 172], fill=(120, 20, 30))
            d.polygon([(66, 114), (100, 112), (100, 140), (52, 140)], fill=(60, 70, 90))
            for x in (52, 140):
                d.ellipse([x - 14, 160, x + 14, 188], fill=(20, 20, 20))
            d.ellipse([cx - 40, 30, cx + 40, 90], fill=(255, 200, 80))
        elif motif == "vache":
            d.ellipse([40, 110, 150, 170], fill=(240, 240, 235))
            d.ellipse([70, 120, 100, 145], fill=(30, 30, 30)); d.ellipse([115, 140, 140, 160], fill=(30, 30, 30))
            d.ellipse([130, 92, 172, 132], fill=(240, 240, 235))
            for x in (55, 80, 115, 135):
                d.rectangle([x, 160, x + 9, 195], fill=(240, 240, 235))
            d.rectangle([0, 192, W, H], fill=(70, 140, 60))
        elif motif == "train":
            d.rectangle([0, 170, W, 176], fill=(160, 160, 170))
            d.polygon([(20, 168), (20, 110), (140, 110), (170, 150), (170, 168)], fill=(200, 40, 40))
            for x in (35, 65, 95):
                d.rectangle([x, 120, x + 20, 140], fill=(255, 230, 150))
        elif motif == "taxi":
            d.rectangle([40, 120, 150, 170], fill=(30, 30, 30))
            d.rectangle([70, 96, 120, 120], fill=(255, 255, 255))
            d.text((74, 98), "TAXI", font=ImageFont.truetype(F_SANS, 18), fill=(0, 0, 0))
            for x in (60, 130):
                d.ellipse([x - 12, 160, x + 12, 184], fill=(15, 15, 15))
        elif motif == "route":
            d.polygon([(cx - 10, 100), (cx + 10, 100), (W, H - 40), (0, H - 40)], fill=(40, 40, 50))
            for k in range(5):
                y0 = 110 + k * 22
                d.rectangle([cx - 2 - k, y0, cx + 2 + k, y0 + 10], fill=(240, 240, 240))
            d.ellipse([cx - 40, 160, cx - 20, 176], fill=(255, 250, 200)); d.ellipse([cx + 20, 160, cx + 40, 176], fill=(255, 250, 200))
        words = title.split(" ")
        lines, cur = [], ""
        for w_ in words:
            if len(cur + " " + w_) > 13 and cur:
                lines.append(cur); cur = w_
            else:
                cur = (cur + " " + w_).strip()
        lines.append(cur)
        fnt = ImageFont.truetype(F_COND, 22)
        y = 8
        for ln_ in lines:
            bx = fnt.getbbox(ln_)
            d.text(((W - (bx[2] - bx[0])) // 2, y), ln_, font=fnt, fill=(255, 255, 255), stroke_width=2, stroke_fill=(0, 0, 0))
            y += 26
        fs = ImageFont.truetype(F_COND, 15)
        bx = fs.getbbox("AU CINÉMA")
        d.rectangle([0, H - 30, W, H], fill=(0, 0, 0))
        d.text(((W - (bx[2] - bx[0])) // 2, H - 25), "AU CINÉMA", font=fs, fill=(255, 210, 60))
        cell.paste(im.resize((256, 256), Image.LANCZOS))
    return f


CINEMAS = {  # nom OSM -> nom parodié, sous-titre
    "Kinepolis Bourgoin-Jallieu": ("KINOPOLIX", "12 SALLES"),
    "L'Équinoxe": ("LE SOLSTICE", "CINÉMA"),
}


def cinema(e, blds, BT, MAINL, atlas, inst, dem, free_box, used, height_info):
    """Cinéma sur son bâtiment : façade en bardage sombre, grande enseigne lumineuse, entrée vitrée sous une marquise à
    ampoules, caissons lumineux d'affiches de part et d'autre."""
    c = e.get("center") or e
    x, z = geo.to_local(c["lon"], c["lat"])
    P = Point(float(x), float(z))
    cand = list(BT.query(P.buffer(40)))
    if not cand:
        return 0
    bi = min(cand, key=lambda i: blds[i][1].distance(P))
    if blds[bi][1].distance(P) > 40:
        return 0
    p, g = blds[bi]
    ring = np.asarray(g.exterior.coords)
    best = None
    for k in range(len(ring) - 1):
        a, b = ring[k], ring[k + 1]
        L = float(np.linalg.norm(b - a))
        if L < 10.0:
            continue
        tdir = (b - a) / L
        nrm = np.array([tdir[1], -tdir[0]])
        m = (a + b) / 2
        dr = MAINL.dist(Point(m + nrm * 1.0), 120.0)
        if dr > MAINL.dist(Point(m - nrm * 1.0), 120.0) + 0.5:
            continue
        sc = dr - 0.05 * L
        if best is None or sc < best[0]:
            best = (sc, k, a, b, L, tdir, nrm)
    if best is None:
        return 0
    _, k, a, b, L, tdir, nrm = best
    gmin, eave = height_info(p, g)
    name, sub = CINEMAS.get(e["tags"].get("name"), ("CINÉMA", None))
    bg, fg = (20, 18, 30), (255, 200, 60)
    supermarket(k, a, b, L, tdir, nrm, gmin, eave, name, sub, bg, fg, F_SANS, None, atlas, inst, dem, free_box, used[bi],
                (52, 48, 64), (40, 40, 44), market=False)
    cen = a + tdir * (L / 2) + nrm * 0.05
    yb = float(dem.h(np.array([cen[0]]), np.array([cen[1]]))[0]) - 0.05
    inst.append(xf("marquise", (cen[0], yb, cen[1]), tdir, custom=(0.85, 0.12, 0.15, 1.0)))
    n = 0
    for i in range(6):
        off = (6.2 + 2.3 * (i // 2)) * (1 if i % 2 == 0 else -1)
        if abs(off) > L / 2 - 1.2:
            continue
        m = a + tdir * (L / 2 + off) + nrm * 0.1
        ym = float(dem.h(np.array([m[0]]), np.array([m[1]]))[0]) + 0.35
        title, fbg, motif = FILMS[(i + int(rnd(name, "films") * 6)) % len(FILMS)]
        r = atlas.drawn_cell(("film", title), draw_poster(title, fbg, motif))
        inst.append(xf("affiche", (m[0], ym, m[1]), tdir, custom=r))
        n += 1
    return 1


if __name__ == "__main__":
    main()
